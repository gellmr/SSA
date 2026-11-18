# ==============================================================================
# RAG Document Fetcher, Indexer & Uploader Script
# Usage:
#   Set-Location -Path C:\repos\SSA\gcp
#   .\rag-upload.ps1
# ==============================================================================

$ErrorActionPreference = "Stop"

if ((Split-Path -Leaf (Get-Location)) -ne "gcp") {
    Set-Location $PSScriptRoot
}

$ProjectId  = "ssa-gcp-515109"
$Region     = "australia-southeast2"
$BucketName = "ssa-safety-docs"

$MdFile     = Join-Path $PSScriptRoot "ragdocs.md"
$DocsDir    = Join-Path $PSScriptRoot "ragdocs"

if (!(Test-Path $DocsDir)) {
    New-Item -ItemType Directory -Force -Path $DocsDir | Out-Null
}

function Get-GcpToken {
    $t = & gcloud auth print-access-token 2>$null
    if ($t) { return $t.Trim() }
    return $null
}

# 1. Parse active (uncommented) documents from ragdocs.md
Write-Host "Reading active documents from $MdFile..." -ForegroundColor Cyan
if (!(Test-Path $MdFile)) {
    Write-Error "Data file not found at '$MdFile'."
    exit 1
}

$activeDocs = @()
Get-Content $MdFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not ($line.StartsWith("#") -or $line.StartsWith("//"))) {
        $parts = $line -split '\|'
        $url = $parts[0].Trim()
        $localName = if ($parts.Length -gt 1 -and $parts[1].Trim()) { $parts[1].Trim() } else { [System.IO.Path]::GetFileName($url) }
        $activeDocs += [PSCustomObject]@{
            Url       = $url
            LocalName = $localName
        }
    }
}

if ($activeDocs.Count -eq 0) {
    Write-Error "No active (uncommented) documents found in $MdFile."
    exit 1
}

Write-Host "Found $($activeDocs.Count) active document(s) in $MdFile." -ForegroundColor Green

# 2. Download missing local PDFs
foreach ($doc in $activeDocs) {
    $dest = Join-Path $DocsDir $doc.LocalName
    if (!(Test-Path $dest)) {
        Write-Host "Downloading $($doc.LocalName)..." -ForegroundColor Yellow
        try {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $doc.Url -OutFile $dest -ErrorAction Stop
            $fileHeader = Get-Content -Encoding Byte -TotalCount 4 -Path $dest -ErrorAction SilentlyContinue
            $headerString = -join ($fileHeader | ForEach-Object { $_.ToString("X2") })
            if ($headerString -match "^25504446") {
                Write-Host "  [OK] Downloaded $($doc.LocalName)" -ForegroundColor Green
            } else {
                Remove-Item $dest -ErrorAction SilentlyContinue
                Write-Error "Failed downloading $($doc.LocalName) (Invalid PDF response)"
            }
        } catch {
            Remove-Item $dest -ErrorAction SilentlyContinue
            Write-Error "Network error downloading $($doc.LocalName): $_"
        }
    } else {
        Write-Host "  [OK] Local copy present: $($doc.LocalName)" -ForegroundColor DarkGray
    }
}

# 3. Generate metadata.jsonl for active documents (UTF-8 without BOM)
Write-Host "`nGenerating metadata.jsonl for $($activeDocs.Count) document(s)..." -ForegroundColor Cyan
$jsonlLines = @()
foreach ($doc in $activeDocs) {
    $cleanName = [System.IO.Path]::GetFileNameWithoutExtension($doc.LocalName)
    $docId = "doc-" + ($cleanName -replace '[^a-zA-Z0-9_\-]', '_')
    $docTitle = $cleanName -replace '[\s\-_]+', ' '
    $item = [ordered]@{
        _id        = $docId
        structData = @{ title = $docTitle }
        content    = @{ mimeType = "application/pdf"; uri = "gs://$BucketName/$($doc.LocalName)" }
    }
    $jsonlLines += ($item | ConvertTo-Json -Compress)
}
$jsonlPath = Join-Path $DocsDir "metadata.jsonl"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllLines($jsonlPath, $jsonlLines, $utf8NoBom)

# 4. Upload active PDFs and metadata.jsonl to GCS
Write-Host "`nSyncing active PDFs to gs://$BucketName..." -ForegroundColor Green
& cmd /c "gcloud storage buckets describe gs://$BucketName 2>NUL" | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Creating GCS bucket '$BucketName'..."
    & cmd /c "gcloud storage buckets create gs://$BucketName --project=$ProjectId --location=$Region"
}

$projectNum = (& cmd /c "gcloud projects describe $ProjectId --format=value(projectNumber) 2>NUL").Trim()
if (![string]::IsNullOrWhiteSpace($projectNum)) {
    Write-Host "Granting Storage Object Viewer permission to Discovery Engine Service Agent..."
    & cmd /c "gcloud storage buckets add-iam-policy-binding gs://$BucketName --member=serviceAccount:service-$projectNum@gcp-sa-discoveryengine.iam.gserviceaccount.com --role=roles/storage.objectViewer 2>NUL" | Out-Null
}

foreach ($doc in $activeDocs) {
    $filePath = Join-Path $DocsDir $doc.LocalName
    & cmd /c "gcloud storage cp `"$filePath`" `"gs://$BucketName/$($doc.LocalName)`" 2>NUL"
}
& cmd /c "gcloud storage cp `"$jsonlPath`" `"gs://$BucketName/metadata.jsonl`" 2>NUL"

# 5. Provision / Verify DataStore and Engine
Write-Host "`nProvisioning Vertex AI Search RAG Data Store & Engine..." -ForegroundColor Green
$token = Get-GcpToken
if ([string]::IsNullOrWhiteSpace($token)) {
    Write-Error "Could not obtain GCP access token."
    exit 1
}

$headers = @{
    Authorization       = "Bearer $token"
    "X-Goog-User-Project" = $ProjectId
}

# Discover or create DataStore
$dsListUrl = "https://discoveryengine.googleapis.com/v1/projects/$ProjectId/locations/global/collections/default_collection/dataStores"
$activeDsId = $null
try {
    $dsList = Invoke-RestMethod -Uri $dsListUrl -Headers $headers -ErrorAction Stop
    if ($dsList.dataStores) {
        $matchingDs = @()
        foreach ($ds in $dsList.dataStores) {
            if ($ds.name -match "/dataStores/(ssa-[^/]+)$") { $matchingDs += $Matches[1] }
        }
        if ($matchingDs.Count -gt 0) { $activeDsId = $matchingDs[-1] }
    }
} catch {}

if (-not $activeDsId) {
    $activeDsId = "ssa-ds-" + (Get-Date -Format "yyMMdd-HHmmss")
    Write-Host "Creating Data Store '$activeDsId'..."
    $createDsUrl = "https://discoveryengine.googleapis.com/v1/projects/$ProjectId/locations/global/collections/default_collection/dataStores?dataStoreId=$activeDsId"
    $dsBody = @{
        displayName      = "SSA Safety DataStore"
        industryVertical = "GENERIC"
        solutionTypes    = @("SOLUTION_TYPE_SEARCH")
        contentConfig    = "NO_CONTENT"
    } | ConvertTo-Json
    $null = Invoke-RestMethod -Uri $createDsUrl -Method Post -Headers $headers -ContentType "application/json" -Body $dsBody
}

# Discover or create Search Engine
$engListUrl = "https://discoveryengine.googleapis.com/v1/projects/$ProjectId/locations/global/collections/default_collection/engines"
$activeEngId = $null
try {
    $engList = Invoke-RestMethod -Uri $engListUrl -Headers $headers -ErrorAction Stop
    if ($engList.engines) {
        $matchingEng = @()
        foreach ($e in $engList.engines) {
            if ($e.name -match "/engines/(ssa-[^/]+)$") { $matchingEng += $Matches[1] }
        }
        if ($matchingEng.Count -gt 0) { $activeEngId = $matchingEng[-1] }
    }
} catch {}

if (-not $activeEngId) {
    $activeEngId = "ssa-eng-" + (Get-Date -Format "yyMMdd-HHmmss")
    Write-Host "Creating Search Engine '$activeEngId'..."
    $createEngUrl = "https://discoveryengine.googleapis.com/v1/projects/$ProjectId/locations/global/collections/default_collection/engines?engineId=$activeEngId"
    $engBody = @{
        displayName        = "SSA Safety Engine"
        solutionType       = "SOLUTION_TYPE_SEARCH"
        dataStoreIds       = @($activeDsId)
        searchEngineConfig = @{
            searchTier   = "SEARCH_TIER_STANDARD"
            searchAddOns = @("SEARCH_ADD_ON_LLM")
        }
    } | ConvertTo-Json -Depth 5
    $null = Invoke-RestMethod -Uri $createEngUrl -Method Post -Headers $headers -ContentType "application/json" -Body $engBody
}

# Trigger document import
Write-Host "Importing active documents into Data Store '$activeDsId'..."
$importUrl = "https://discoveryengine.googleapis.com/v1/projects/$ProjectId/locations/global/collections/default_collection/dataStores/$activeDsId/branches/0/documents:import"
$importBody = @{
    gcsSource          = @{
        inputUris  = @("gs://$BucketName/metadata.jsonl")
        dataSchema = "custom"
    }
    reconciliationMode = "FULL"
} | ConvertTo-Json -Depth 5

$null = Invoke-RestMethod -Uri $importUrl -Method Post -Headers $headers -ContentType "application/json" -Body $importBody

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host " RAG document upload and ingestion initiated successfully!" -ForegroundColor Green
Write-Host " Active DataStore: $activeDsId | Active Engine: $activeEngId" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "A single 50 page pdf doc should take about 1 minute to process."
Write-Host "But after this, global index propagation will take 5-10 minutes to register as done."
Write-Host "To monitor document indexing & secondary grounding status, run: .\poll.ps1" -ForegroundColor Yellow
