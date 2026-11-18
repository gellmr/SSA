# ==============================================================================
# Vertex AI Search & RAG Grounding Status Poller
# Usage:
#   Set-Location -Path C:\repos\SSA\gcp
#   .\poll.ps1
# ==============================================================================

$ErrorActionPreference = "Continue"

if ((Split-Path -Leaf (Get-Location)) -ne "gcp") {
    Set-Location $PSScriptRoot
}

$ProjectId = "ssa-gcp-515109"
$Interval  = 90
$MdFile    = Join-Path $PSScriptRoot "ragdocs.md"

# Calculate active document count from ragdocs.md (single source of truth)
$totalActiveDocs = 12
if (Test-Path $MdFile) {
    $activeLines = Get-Content $MdFile | Where-Object {
        $line = $_.Trim()
        $line -and -not ($line.StartsWith("#") -or $line.StartsWith("//"))
    }
    if ($activeLines) {
        $totalActiveDocs = $activeLines.Count
    }
}

$script:cachedToken = $null
$script:tokenExpiry = Get-Date

function Get-GcpToken {
    if (-not $script:cachedToken -or (Get-Date) -gt $script:tokenExpiry) {
        $t = & gcloud auth print-access-token 2>$null
        if ($t) {
            $script:cachedToken = $t.Trim()
            $script:tokenExpiry = (Get-Date).AddMinutes(10)
        }
    }
    return $script:cachedToken
}

Write-Host ""
Write-Host "==============================================================================================================================" -ForegroundColor Cyan
Write-Host " Vertex AI Search RAG Stack Status Poller - Project: $ProjectId" -ForegroundColor Cyan
Write-Host " Polling every $Interval seconds. Press Ctrl+C to stop at any time." -ForegroundColor DarkGray
Write-Host "==============================================================================================================================" -ForegroundColor Cyan
Write-Host ""

$headerFormat = "{0,-8} | {1,-20} | {2,-20} | {3,-9} | {4,-14} | {5,-13} | {6,-26} | {7,-8}"
Write-Host ($headerFormat -f "Time", "DataStore ID", "Engine ID", "Reg/Idx", "Import LRO", "SemanticState", "Search / Grounding", "Elapsed") -ForegroundColor Green
Write-Host ("-" * 136) -ForegroundColor DarkGray

$startTime = Get-Date

while ($true) {
    $nowStr = Get-Date -Format "HH:mm:ss"
    $elapsed = (Get-Date) - $startTime
    $elapsedStr = "{0:D2}m {1:D2}s" -f $elapsed.Minutes, $elapsed.Seconds

    $token = Get-GcpToken
    if ([string]::IsNullOrWhiteSpace($token)) {
        Write-Host ($headerFormat -f $nowStr, "NO_TOKEN", "NO_TOKEN", "0/0/$totalActiveDocs", "AUTH_FAIL", "UNKNOWN", "Auth token error", $elapsedStr) -ForegroundColor Red
        Start-Sleep -Seconds $Interval
        continue
    }

    $headers = @{
        Authorization         = "Bearer $token"
        "X-Goog-User-Project" = $ProjectId
    }

    # 1. Discover Active DataStore (Select latest by createTime)
    $dsId = "NONE"
    try {
        $dsListUrl = "https://discoveryengine.googleapis.com/v1/projects/$ProjectId/locations/global/collections/default_collection/dataStores"
        $dsRes = Invoke-RestMethod -Uri $dsListUrl -Headers $headers -ErrorAction Stop
        if ($dsRes.dataStores) {
            $sortedDs = $dsRes.dataStores | Where-Object { $_.name -match "/dataStores/(ssa-[^/]+)$" } | Sort-Object { $_.createTime }
            if ($sortedDs) {
                $dsId = ($sortedDs[-1].name -replace '.*/', '')
            }
        }
    } catch { $dsId = "ERR_FETCH" }

    # 2. Discover Active Search Engine (Select latest by createTime)
    $engId = "NONE"
    try {
        $engListUrl = "https://discoveryengine.googleapis.com/v1/projects/$ProjectId/locations/global/collections/default_collection/engines"
        $engRes = Invoke-RestMethod -Uri $engListUrl -Headers $headers -ErrorAction Stop
        if ($engRes.engines) {
            $sortedEng = $engRes.engines | Where-Object { $_.name -match "/engines/(ssa-[^/]+)$" } | Sort-Object { $_.createTime }
            if ($sortedEng) {
                $engId = ($sortedEng[-1].name -replace '.*/', '')
            }
        }
    } catch { $engId = "ERR_FETCH" }

    # 3. Check Registered vs. Indexed Document Count in DataStore
    $regCount = 0
    $idxCount = 0
    if ($dsId -ne "NONE" -and $dsId -ne "ERR_FETCH") {
        try {
            $docsUrl = "https://discoveryengine.googleapis.com/v1/projects/$ProjectId/locations/global/collections/default_collection/dataStores/$dsId/branches/0/documents?pageSize=100"
            $docsRes = Invoke-RestMethod -Uri $docsUrl -Headers $headers -ErrorAction Stop
            if ($docsRes.documents) {
                $regCount = $docsRes.documents.Count
                $idxCount = ($docsRes.documents | Where-Object { $_.indexStatus -and $_.indexStatus.indexTime }).Count
            }
        } catch {}
    }
    $docCountStr = "$regCount/$idxCount/$totalActiveDocs"

    # 4. Check Import LRO Status + Granular Counters
    $lroStatus = "IDLE"
    $lroDone = $false
    if ($dsId -ne "NONE" -and $dsId -ne "ERR_FETCH") {
        try {
            $opListUrl = "https://discoveryengine.googleapis.com/v1/projects/$ProjectId/locations/global/collections/default_collection/dataStores/$dsId/branches/0/operations"
            $opsRes = Invoke-RestMethod -Uri $opListUrl -Headers $headers -ErrorAction Stop
            if ($opsRes.operations) {
                $lastOp = $opsRes.operations | Select-Object -First 1
                $ok = if ($lastOp.metadata.successCount) { $lastOp.metadata.successCount } else { 0 }
                $fail = if ($lastOp.metadata.failureCount) { $lastOp.metadata.failureCount } else { 0 }
                if ($lastOp.done -eq $true) {
                    $lroDone = $true
                    $lroStatus = if ($fail -gt 0) { "DONE (err:$fail)" } else { "DONE ($ok ok)" }
                } else {
                    $lroStatus = "RUN ($ok ok)"
                }
            }
        } catch { $lroStatus = "UNKNOWN" }
    }

    # 5. Lightweight Retrieval Probe first; only test LLM summary once chunks return
    $semanticState = "UNKNOWN"
    $summaryStatus = "WAITING_IMPORT"

    if ($engId -ne "NONE" -and $engId -ne "ERR_FETCH" -and $lroDone) {
        try {
            $searchUrl = "https://discoveryengine.googleapis.com/v1/projects/$ProjectId/locations/global/collections/default_collection/engines/$engId/servingConfigs/default_search:search"
            
            # Step 5a: Cheap retrieval check (no LLM summary quota hit)
            $probeBody = @{
                query    = "confined space"
                pageSize = 1
            } | ConvertTo-Json

            $probeRes = Invoke-RestMethod -Uri $searchUrl -Method Post -Headers $headers -ContentType "application/json" -Body $probeBody -ErrorAction Stop
            if ($probeRes.semanticState) {
                $semanticState = $probeRes.semanticState
            }

            if ($probeRes.results -and $probeRes.results.Count -gt 0) {
                # Brief pause before hitting the summary endpoint to ease quota pressure
                Start-Sleep -Seconds 3

                # Step 5b: Chunks are queryable; now verify generative summary
                $summaryBody = @{
                    query             = "confined space"
                    pageSize          = 3
                    contentSearchSpec = @{
                        summarySpec = @{ summaryResultCount = 3; includeCitations = $true }
                    }
                } | ConvertTo-Json -Depth 5

                $sumRes = Invoke-RestMethod -Uri $searchUrl -Method Post -Headers $headers -ContentType "application/json" -Body $summaryBody -ErrorAction Stop
                $hasRealSummary = ($sumRes.summary -and $sumRes.summary.summaryText -and -not $sumRes.summary.summaryText.StartsWith("A summary could not be generated"))

                if ($hasRealSummary) {
                    $summaryStatus = "READY (Grounded)"
                } else {
                    $summaryStatus = "INDEXED (Warming LLM)"
                }
            } else {
                $summaryStatus = "PROPAGATING (0 hits)"
            }
        } catch {
            $code = $null
            if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
            if ($code -eq 429) {
                $summaryStatus = "HTTP_429 (Rate limit)"
            } elseif ($code -eq 404) {
                $summaryStatus = "HTTP_404 (Attaching)"
            } elseif ($code) {
                $summaryStatus = "HTTP_$code"
            } else {
                $summaryStatus = "NET_ERR"
            }
        }
    }

    # Print Table Row
    $rowColor = "Yellow"
    if ($summaryStatus -eq "READY (Grounded)" -and $regCount -eq $totalActiveDocs) {
        $rowColor = "Green"
    }

    Write-Host ($headerFormat -f $nowStr, $dsId, $engId, $docCountStr, $lroStatus, $semanticState, $summaryStatus, $elapsedStr) -ForegroundColor $rowColor

    if ($summaryStatus -eq "READY (Grounded)" -and $regCount -eq $totalActiveDocs) {
        Write-Host ""
        Write-Host "==============================================================================================================================" -ForegroundColor Green
        Write-Host " SUCCESS: RAG Ingestion & Secondary Generative AI Grounding is 100% COMPLETE and READY!" -ForegroundColor Green
        Write-Host "==============================================================================================================================" -ForegroundColor Green
        break
    }

    Start-Sleep -Seconds $Interval
}
