param (
    [switch]$Up,
    [switch]$Down,
    [switch]$Info
)

$ErrorActionPreference = "Stop"

$ProjectId    = "ssa-gcp-515109"
$Region       = "australia-southeast2"
$BucketName   = "ssa-safety-docs"
$LocalDocsDir = Join-Path $PSScriptRoot "ragdocs"
$MdFile       = Join-Path $PSScriptRoot "ragdocs.md"

# This script fails unless you run it from gcp folder.
if ((Split-Path -Leaf (Get-Location)) -ne "gcp") {
    Set-Location $PSScriptRoot
}

# Ensure exactly one switch is active
$activeFlags = @($Up, $Down, $Info) | Where-Object { $_ }
if ($activeFlags.Count -ne 1) {
    Write-Error "Please specify exactly one flag: -Up, -Down, or -Info"
    exit 1
}

# Helper function to parse active documents from ragdocs.md
function Get-ActiveDocs {
    param ([string]$Path)
    if (!(Test-Path $Path)) {
        Write-Error "Data file not found at '$Path'."
        exit 1
    }
    $docs = @()
    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not ($line.StartsWith("#") -or $line.StartsWith("//"))) {
            $parts = $line -split '\|'
            $url = $parts[0].Trim()
            $localName = if ($parts.Length -gt 1 -and $parts[1].Trim()) { $parts[1].Trim() } else { [System.IO.Path]::GetFileName($url) }
            $docs += $localName
        }
    }
    return $docs
}

if ($Up) {
    Write-Host "`n[Bucket] Reading active documents from $MdFile..." -ForegroundColor Cyan
    $activeFiles = Get-ActiveDocs $MdFile

    if ($activeFiles.Count -eq 0) {
        Write-Error "No active (uncommented) documents found in $MdFile."
        exit 1
    }

    Write-Host "`n[Bucket] Syncing $($activeFiles.Count) active document(s) to gs://$BucketName..." -ForegroundColor Green
    
    # Ensure bucket exists
    & cmd /c "gcloud storage buckets describe gs://$BucketName 2>NUL" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Bucket does not exist. Creating..."
        & cmd /c "gcloud storage buckets create gs://$BucketName --project=$ProjectId --location=$Region"
    }

    # Upload active PDF files
    foreach ($fileName in $activeFiles) {
        $filePath = Join-Path $LocalDocsDir $fileName
        if (Test-Path $filePath) {
            Write-Host "  Copying $fileName..." -ForegroundColor DarkGray
            & cmd /c "gcloud storage cp `"$filePath`" `"gs://$BucketName/$fileName`""
        } else {
            Write-Host "  Warning: Local file not found: $fileName" -ForegroundColor Yellow
        }
    }

    # Also upload metadata.jsonl if present
    $metaPath = Join-Path $LocalDocsDir "metadata.jsonl"
    if (Test-Path $metaPath) {
        Write-Host "  Copying metadata.jsonl..." -ForegroundColor DarkGray
        & cmd /c "gcloud storage cp `"$metaPath`" `"gs://$BucketName/metadata.jsonl`""
    }

    Write-Host "Bucket sync completed successfully!" -ForegroundColor Cyan
}

if ($Down) {
    Write-Host "`n[Bucket] Clearing all documents from gs://$BucketName..." -ForegroundColor DarkGray
    & cmd /c "gcloud storage rm gs://$BucketName/** 2>NUL"
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "All documents removed from bucket." -ForegroundColor Cyan
    } else {
        Write-Host "Bucket is already empty or not found." -ForegroundColor Yellow
    }
}

if ($Info) {
    Write-Host "`n[Bucket] Inspecting gs://$BucketName..." -ForegroundColor Cyan

    # Check if bucket exists
    & cmd /c "gcloud storage buckets describe gs://$BucketName 2>NUL" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Bucket gs://$BucketName does not exist." -ForegroundColor Yellow
        exit 0
    }

    # Fetch file list with sizes and timestamps
    $files = & cmd /c "gcloud storage ls -l gs://$BucketName/ 2>NUL"
    
    if ($LASTEXITCODE -ne 0 -or -not $files) {
        Write-Host "Bucket gs://$BucketName exists, but is currently empty." -ForegroundColor Yellow
        exit 0
    }

    # Print formatted table of files and total summary
    foreach ($line in $files) {
        if ($line -match "^TOTAL:") {
            Write-Host "`n$line" -ForegroundColor Green
        } elseif ($line.Trim() -ne "") {
            Write-Host "  $line" -ForegroundColor DarkGray
        }
    }
}
