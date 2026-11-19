param (
    [switch]$Up,
    [switch]$Down,
    [switch]$Downx
)

# Use -Downx to skip teardown of SQL instance.

$ErrorActionPreference = "Stop"

# Ensure exactly one switch is active
$activeFlags = @($Up, $Down, $Downx) | Where-Object { $_ }
if ($activeFlags.Count -ne 1) {
    Write-Error "Please specify exactly one flag: -Up, -Down, or -Downx"
    exit 1
}

# Configuration Variables
$ProjectId = "ssa-gcp-515109"
$Region    = "australia-southeast2" # Melbourne, Australia

# Resource Names
$RepoName        = "ssa-gcp-docker-repo"
$ServiceName     = "ssa-app"
$SqlInstanceName = "ssa-sql-instance"
$DatabaseName    = "ssa_gcp_db"
$BucketName      = "ssa-safety-docs" # GCS bucket for RAG documents
$DataStoreId     = "ssa-safety-datastore"
$EngineId        = "ssa-safety-engine"

# Helper to get GCP access token
function Get-GcpToken {
    $t = & gcloud auth print-access-token 2>$null
    if ($t) { return $t.Trim() }
    return $null
}

# Helper to provision Vertex AI Search Data Store and Engine
function Provision-VertexRag {
    param ($ProjId, $BktName)
    Write-Host "`n[UP] Provisioning Vertex AI Search RAG Data Store & Engine..." -ForegroundColor Green
    
    $token = Get-GcpToken
    if ([string]::IsNullOrWhiteSpace($token)) {
        Write-Host "Warning: Could not obtain GCP access token for RAG setup." -ForegroundColor Yellow
        return
    }

    $headers = @{
        Authorization       = "Bearer $token"
        "X-Goog-User-Project" = $ProjId
    }

    # 1. Find active Data Store or create a new one if needed
    $dsListUrl = "https://discoveryengine.googleapis.com/v1/projects/$ProjId/locations/global/collections/default_collection/dataStores"
    $activeDsId = $null
    try {
        $dsList = Invoke-RestMethod -Uri $dsListUrl -Method Get -Headers $headers -ErrorAction Stop
        if ($dsList.dataStores) {
            foreach ($ds in $dsList.dataStores) {
                if ($ds.name -match "/dataStores/(ssa-[^/]+)$") {
                    $activeDsId = $Matches[1]
                    break
                }
            }
        }
    } catch {}

    if (-not $activeDsId) {
        $activeDsId = "ssa-ds-" + (Get-Date -Format "yyMMdd-HHmmss")
        Write-Host "Creating Data Store '$activeDsId'..."
        $createDsUrl = "https://discoveryengine.googleapis.com/v1/projects/$ProjId/locations/global/collections/default_collection/dataStores?dataStoreId=$activeDsId"
        $dsBody = @{
            displayName      = "SSA Safety DataStore"
            industryVertical = "GENERIC"
            solutionTypes    = @("SOLUTION_TYPE_SEARCH")
            contentConfig    = "NO_CONTENT"
        } | ConvertTo-Json

        $null = Invoke-RestMethod -Uri $createDsUrl -Method Post -Headers $headers -ContentType "application/json" -Body $dsBody
        Write-Host "Data Store '$activeDsId' created successfully."
    } else {
        Write-Host "Active Data Store '$activeDsId' found."
    }

    # 2. Generate and upload metadata.jsonl for clean Discovery Engine document ingestion
    $localDocs = Join-Path $PSScriptRoot "ragdocs"
    if (Test-Path $localDocs) {
        $lines = @()
        $i = 1
        Get-ChildItem -Path "$localDocs\*.pdf" | ForEach-Object {
            $fileName = $_.Name
            $docTitle = [System.IO.Path]::GetFileNameWithoutExtension($fileName) -replace '[\s\-_]+', ' '
            $item = [ordered]@{
                _id        = "doc-$i"
                structData = @{ title = $docTitle }
                content    = @{ mimeType = "application/pdf"; uri = "gs://$BktName/$fileName" }
            }
            $lines += ($item | ConvertTo-Json -Compress)
            $i++
        }
        $jsonlPath = Join-Path $localDocs "metadata.jsonl"
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllLines($jsonlPath, $lines, $utf8NoBom)
        & cmd /c "gcloud storage cp `"$jsonlPath`" `"gs://$BktName/metadata.jsonl`" 2>NUL" | Out-Null
    }

    # 3. Trigger Document Import from GCS bucket
    Write-Host "Importing documents from gs://$BktName/metadata.jsonl into Data Store '$activeDsId'..."
    $importUrl = "https://discoveryengine.googleapis.com/v1/projects/$ProjId/locations/global/collections/default_collection/dataStores/$activeDsId/branches/0/documents:import"
    $importBody = @{
        gcsSource          = @{
            inputUris  = @("gs://$BktName/metadata.jsonl")
            dataSchema = "custom"
        }
        reconciliationMode = "INCREMENTAL"
    } | ConvertTo-Json -Depth 5

    $opName = $null
    try {
        $importRes = Invoke-RestMethod -Uri $importUrl -Method Post -Headers $headers -ContentType "application/json" -Body $importBody
        if ($importRes -and $importRes.name) {
            $opName = $importRes.name
        }
        Write-Host "Document import initiated."
    } catch {
        Write-Host "Document import notice: $_" -ForegroundColor DarkGray
    }

    # 4. Find active Search Engine or create a new one if needed
    $engListUrl = "https://discoveryengine.googleapis.com/v1/projects/$ProjId/locations/global/collections/default_collection/engines"
    $activeEngId = $null
    try {
        $engList = Invoke-RestMethod -Uri $engListUrl -Method Get -Headers $headers -ErrorAction Stop
        if ($engList.engines) {
            foreach ($eng in $engList.engines) {
                if ($eng.name -match "/engines/(ssa-[^/]+)$") {
                    $activeEngId = $Matches[1]
                    break
                }
            }
        }
    } catch {}

    if (-not $activeEngId) {
        $activeEngId = "ssa-eng-" + (Get-Date -Format "yyMMdd-HHmmss")
        Write-Host "Creating Search Engine '$activeEngId'..."
        $createEngUrl = "https://discoveryengine.googleapis.com/v1/projects/$ProjId/locations/global/collections/default_collection/engines?engineId=$activeEngId"
        $engBody = @{
            displayName        = "SSA Safety Engine"
            solutionType       = "SOLUTION_TYPE_SEARCH"
            dataStoreIds       = @($activeDsId)
            searchEngineConfig = @{
                searchTier   = "SEARCH_TIER_ENTERPRISE"
                searchAddOns = @("SEARCH_ADD_ON_LLM")
            }
        } | ConvertTo-Json -Depth 5

        $null = Invoke-RestMethod -Uri $createEngUrl -Method Post -Headers $headers -ContentType "application/json" -Body $engBody
        Write-Host "Search Engine '$activeEngId' created successfully."
    } else {
        Write-Host "Active Search Engine '$activeEngId' found."
    }

    return @{ DataStoreId = $activeDsId; OpName = $opName }
}

# Helper to teardown Vertex AI Search Data Store and Engine
function Teardown-VertexRag {
    param ($ProjId)
    $token = Get-GcpToken
    if ([string]::IsNullOrWhiteSpace($token)) { return }

    $headers = @{
        Authorization       = "Bearer $token"
        "X-Goog-User-Project" = $ProjId
    }

    # 1. Delete all active ssa- engines
    $engListUrl = "https://discoveryengine.googleapis.com/v1/projects/$ProjId/locations/global/collections/default_collection/engines"
    try {
        $engList = Invoke-RestMethod -Uri $engListUrl -Method Get -Headers $headers -ErrorAction Stop
        if ($engList.engines) {
            foreach ($eng in $engList.engines) {
                if ($eng.name -match "/engines/(ssa-[^/]+)$") {
                    $engId = $Matches[1]
                    Write-Host "`n[DOWN] Deleting Search Engine '$engId'..." -ForegroundColor DarkGray
                    $delEngUrl = "https://discoveryengine.googleapis.com/v1/projects/$ProjId/locations/global/collections/default_collection/engines/$engId"
                    try {
                        $null = Invoke-RestMethod -Uri $delEngUrl -Method Delete -Headers $headers -ErrorAction Stop
                        Write-Host "Search Engine '$engId' deleted."
                    } catch {}
                }
            }
        }
    } catch {}

    # Also attempt standard fallback names
    foreach ($fallbackEng in @("ssa-safety-engine")) {
        $delEngUrl = "https://discoveryengine.googleapis.com/v1/projects/$ProjId/locations/global/collections/default_collection/engines/$fallbackEng"
        try { $null = Invoke-RestMethod -Uri $delEngUrl -Method Delete -Headers $headers -ErrorAction Stop } catch {}
    }

    # 2. Delete all active ssa- dataStores
    $dsListUrl = "https://discoveryengine.googleapis.com/v1/projects/$ProjId/locations/global/collections/default_collection/dataStores"
    try {
        $dsList = Invoke-RestMethod -Uri $dsListUrl -Method Get -Headers $headers -ErrorAction Stop
        if ($dsList.dataStores) {
            foreach ($ds in $dsList.dataStores) {
                if ($ds.name -match "/dataStores/(ssa-[^/]+)$") {
                    $dsId = $Matches[1]
                    Write-Host "`n[DOWN] Deleting Data Store '$dsId'..." -ForegroundColor DarkGray
                    $delDsUrl = "https://discoveryengine.googleapis.com/v1/projects/$ProjId/locations/global/collections/default_collection/dataStores/$dsId"
                    try {
                        $null = Invoke-RestMethod -Uri $delDsUrl -Method Delete -Headers $headers -ErrorAction Stop
                        Write-Host "Data Store '$dsId' deleted."
                    } catch {}
                }
            }
        }
    } catch {}

    # Also attempt standard fallback names
    foreach ($fallbackDs in @("ssa-safety-datastore")) {
        $delDsUrl = "https://discoveryengine.googleapis.com/v1/projects/$ProjId/locations/global/collections/default_collection/dataStores/$fallbackDs"
        try { $null = Invoke-RestMethod -Uri $delDsUrl -Method Delete -Headers $headers -ErrorAction Stop } catch {}
    }
}

# Secrets File (outside version control)
$SecretsFile = "C:\sensitive\ssa-gcp\secrets.md"

# Helper to read DB Password from secrets.md
$DbPassword = $null
if (Test-Path $SecretsFile) {
    $secretsContent = Get-Content $SecretsFile
    $match = $secretsContent | Select-String -Pattern "^DB_PASSWORD=(.*)$"
    if ($match) {
        $DbPassword = $match.Matches.Groups[1].Value.Trim()
    }
}

# This script fails unless you run it from gcp folder.
if ((Split-Path -Leaf (Get-Location)) -ne "gcp") {
    Write-Error "This script must be invoked from inside the 'gcp' folder. Current directory: $(Get-Location)"
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
if ($Up) { Write-Host " GCP Provisioning Script (-Up)" -ForegroundColor Cyan }
if ($Down) { Write-Host " GCP Provisioning Script (-Down)" -ForegroundColor Cyan }
if ($Downx) { Write-Host " GCP Provisioning Script (-Downx - skip teardown of SQL instance )" -ForegroundColor Cyan }
Write-Host " Project ID: $ProjectId" -ForegroundColor Cyan
Write-Host " Secrets File: $SecretsFile" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Ensure gcloud is pointing to the right project
Write-Host "`nSetting active GCP project to $ProjectId..."
& cmd /c "gcloud config set project $ProjectId 2>NUL" | Out-Null

if ($Up) {
    Write-Host "`n[UP] Enabling required GCP APIs..." -ForegroundColor Green
    & cmd /c "gcloud services enable compute.googleapis.com run.googleapis.com sqladmin.googleapis.com artifactregistry.googleapis.com storage.googleapis.com cloudbuild.googleapis.com aiplatform.googleapis.com discoveryengine.googleapis.com firebase.googleapis.com firebasehosting.googleapis.com 2>NUL" | Out-Null

    Write-Host "`nGranting VPC Network permissions to Cloud Run Service Agent..." -ForegroundColor Green
    $projectNum = (& cmd /c "gcloud projects describe $ProjectId --format=value(projectNumber) 2>NUL").Trim()
    if (![string]::IsNullOrWhiteSpace($projectNum)) {
        & cmd /c "gcloud projects add-iam-policy-binding $ProjectId --member=serviceAccount:service-$projectNum@serverless-robot-prod.iam.gserviceaccount.com --role=roles/compute.networkUser --condition=None 2>NUL" | Out-Null
    }
    Write-Host "`n[UP] Checking Artifact Registry repository '$RepoName'..." -ForegroundColor Green
    
    # Run silently and check exit code
    & cmd /c "gcloud artifacts repositories describe $RepoName --location=$Region --format=value(name) 2>NUL" | Out-Null
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Creating Artifact Registry repository '$RepoName'..."
        gcloud artifacts repositories create $RepoName `
            --repository-format=docker `
            --location=$Region `
            --description="Docker repository for SSA"
    } else {
        Write-Host "Repository '$RepoName' already exists."
    }

    Write-Host "`n[UP] Checking Cloud SQL instance '$SqlInstanceName'..." -ForegroundColor Green
    
    & cmd /c "gcloud sql instances describe $SqlInstanceName --format=value(name) 2>NUL" | Out-Null

    if ($LASTEXITCODE -ne 0) {
        if ([string]::IsNullOrWhiteSpace($DbPassword)) {
            Write-Error "Cannot provision database: DB_PASSWORD not found in $SecretsFile. Please add a line like 'DB_PASSWORD=YourPassword' and run again."
            exit 1
        }
        Write-Host "Creating Cloud SQL instance '$SqlInstanceName' (this will take ~10-15 minutes)..."
        gcloud sql instances create $SqlInstanceName `
            --database-version=SQLSERVER_2019_EXPRESS `
            --tier=db-custom-2-7680 `
            --region=$Region `
            --root-password="$DbPassword" `
              --authorized-networks="0.0.0.0/0"

        # GCP Cloud Run dynamically allocates IPs from a massive, shared Google pool.
        # In an enterprise environment we would need Private Service Connect, or NAT Gateway.
        # For this non-commercial portfolio project, I will allow all IPs (0.0.0.0/0)
        # and rely on strict TLS, with very strong runtime password.

        Write-Host "Creating database '$DatabaseName' inside instance..."
        gcloud sql databases create $DatabaseName --instance=$SqlInstanceName
    } else {
        Write-Host "Cloud SQL instance '$SqlInstanceName' already exists."
    }

    Write-Host "`n[UP] Checking Google Cloud Storage bucket '$BucketName'..." -ForegroundColor Green
    & cmd /c "gcloud storage buckets describe gs://$BucketName 2>NUL" | Out-Null
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Creating GCS bucket '$BucketName' for RAG documents..."
        & cmd /c "gcloud storage buckets create gs://$BucketName --project=$ProjectId --location=$Region"
        Write-Host "Bucket created successfully."
    } else {
        Write-Host "GCS bucket '$BucketName' already exists."
    }

    if (![string]::IsNullOrWhiteSpace($projectNum)) {
        Write-Host "Granting Storage Object Viewer permission to allUsers & Discovery Engine Service Agent..."
        & cmd /c "gcloud storage buckets add-iam-policy-binding gs://$BucketName --member=allUsers --role=roles/storage.objectViewer 2>NUL" | Out-Null
        & cmd /c "gcloud storage buckets add-iam-policy-binding gs://$BucketName --member=serviceAccount:service-$projectNum@gcp-sa-discoveryengine.iam.gserviceaccount.com --role=roles/storage.objectViewer 2>NUL" | Out-Null
    }

    Write-Host "`nProvisioning UP complete!" -ForegroundColor Cyan
    Write-Host "Next step: run .\rag-upload.ps1 to obtain and upload pdf safety documents." -ForegroundColor Yellow
}

if ($Down -or $Downx) {
    # Teardown Vertex AI Search RAG Engine and Data Store first
    Teardown-VertexRag -ProjId $ProjectId

    Write-Host "`n[DOWN] Deleting Cloud Run service '$ServiceName'..." -ForegroundColor DarkGray
    & cmd /c "gcloud run services delete $ServiceName --region=$Region --quiet 2>NUL" | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Host "Service deleted." } else { Write-Host "Service not found or already deleted." }

    Write-Host "`n[DOWN] Deleting Artifact Registry repository '$RepoName'..." -ForegroundColor DarkGray
    & cmd /c "gcloud artifacts repositories delete $RepoName --location=$Region --quiet 2>NUL" | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Host "Repository deleted." } else { Write-Host "Repository not found or already deleted." }

    if ($Down) {
        Write-Host "`n[DOWN] Deleting Cloud SQL instance '$SqlInstanceName'..." -ForegroundColor DarkGray
        & cmd /c "gcloud sql instances delete $SqlInstanceName --quiet 2>NUL" | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Host "SQL instance deleted." } else { Write-Host "SQL instance not found or already deleted." }
    }

    Write-Host "`n[DOWN] Deleting GCS bucket '$BucketName' and stored PDFs..." -ForegroundColor DarkGray
    & cmd /c "gcloud storage rm --recursive gs://$BucketName 2>NUL" | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Host "GCS bucket and contents deleted." } else { Write-Host "Bucket not found or already deleted." }

    Write-Host "`nTeardown complete!" -ForegroundColor Cyan
}
