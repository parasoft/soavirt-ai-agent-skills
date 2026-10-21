# =============================================================================
# soatest-scenario-execution-runner.ps1
# Executes an existing SOAtest .tst file and retrieves the execution report.
# =============================================================================

function Show-Usage {
    @"
Usage:
  powershell.exe -ExecutionPolicy Bypass -File soatest-scenario-execution-runner.ps1 `
      --tst-file-id "/TestAssets/AI-Generated-Tests/MyApi-Tests.tst" `
      [--host "localhost"] [--port 9080] [--protocol "http"] `
      [--username "user"] [--password "pass"] [--bearer-token "token"] `
      [--poll-interval-seconds 2] [--max-wait-minutes 15] `
            [--execution-json '{"general":{"config":"soatest.builtin://Run Automated Server Tests"}}'] `
        [--config "soatest.builtin://Run Automated Server Tests"] `
      [--report-output-dir "C:\reports"] [--output-per-test-json]

Required:
  --tst-file-id ID

Optional:
  --host HOST                 SOAtest host (default: localhost)
  --port PORT                 SOAtest port (default: 9080)
  --protocol http|https      SOAtest protocol (default: http)
  --username USER            SOAtest username
  --password PASS            SOAtest password
  --bearer-token TOKEN       SOAtest bearer token
  --poll-interval-seconds N  Polling interval in seconds (default: 2)
  --max-wait-minutes N       Maximum wait time in minutes (default: 15)
    --execution-json JSON      Full execution request body; sent unchanged when provided
    --config CONFIG            SOAtest configuration ID (default: soatest.builtin://Run Automated Server Tests)
  --report-output-dir PATH   Directory to save reports
                             (default: %TEMP%\parasoft\soavirt\reports)
  --output-per-test-json     Also emit per-test JSON report
  --help                     Show this help text

Examples:
  powershell.exe -ExecutionPolicy Bypass -File .\soatest-scenario-execution-runner.ps1 --tst-file-id "/TestAssets/Calculator_Add_Test.tst" --host "localhost" --port 9080 --protocol "http"
  powershell.exe -ExecutionPolicy Bypass -File .\soatest-scenario-execution-runner.ps1 --tst-file-id "/TestAssets/Calculator_Add_Test.tst" --host localhost --port 9080 --protocol http --poll-interval-seconds 5 --max-wait-minutes 30
"@
}

function Get-DefaultReportOutputDir {
    $reportDir = Join-Path $env:TEMP "parasoft\soavirt\reports"
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    return $reportDir
}

$TstFileId = ""
$ServerHost = "localhost"
$Port = 9080
$Protocol = "http"
$Username = ""
$Password = ""
$BearerToken = ""
$PollIntervalSeconds = 2
$MaxWaitMinutes = 15
$ExecutionJson = ""
$Config = "soatest.builtin://Run Automated Server Tests"
$ReportOutputDir = ""
$ReportOutputDirSpecified = $false
$OutputPerTestJson = $false

for ($i = 0; $i -lt $args.Count; $i++) {
    $arg = $args[$i]
    switch ($arg) {
        '--help' { Show-Usage; exit 0 }
        '--tst-file-id' { if ($i + 1 -ge $args.Count) { throw "Missing value for --tst-file-id" }; $TstFileId = $args[$i + 1]; $i++; continue }
        '--host' { if ($i + 1 -ge $args.Count) { throw "Missing value for --host" }; $ServerHost = $args[$i + 1]; $i++; continue }
        '--port' { if ($i + 1 -ge $args.Count) { throw "Missing value for --port" }; $Port = [int]$args[$i + 1]; $i++; continue }
        '--protocol' { if ($i + 1 -ge $args.Count) { throw "Missing value for --protocol" }; $Protocol = $args[$i + 1]; $i++; continue }
        '--username' { if ($i + 1 -ge $args.Count) { throw "Missing value for --username" }; $Username = $args[$i + 1]; $i++; continue }
        '--password' { if ($i + 1 -ge $args.Count) { throw "Missing value for --password" }; $Password = $args[$i + 1]; $i++; continue }
        '--bearer-token' { if ($i + 1 -ge $args.Count) { throw "Missing value for --bearer-token" }; $BearerToken = $args[$i + 1]; $i++; continue }
        '--poll-interval-seconds' { if ($i + 1 -ge $args.Count) { throw "Missing value for --poll-interval-seconds" }; $PollIntervalSeconds = [int]$args[$i + 1]; $i++; continue }
        '--max-wait-minutes' { if ($i + 1 -ge $args.Count) { throw "Missing value for --max-wait-minutes" }; $MaxWaitMinutes = [int]$args[$i + 1]; $i++; continue }
        '--execution-json' { if ($i + 1 -ge $args.Count) { throw "Missing value for --execution-json" }; $ExecutionJson = $args[$i + 1]; $i++; continue }
        '--config' { if ($i + 1 -ge $args.Count) { throw "Missing value for --config" }; $Config = $args[$i + 1]; $i++; continue }
        '--report-output-dir' { if ($i + 1 -ge $args.Count) { throw "Missing value for --report-output-dir" }; $ReportOutputDir = $args[$i + 1]; $ReportOutputDirSpecified = $true; $i++; continue }
        '--output-per-test-json' { $OutputPerTestJson = $true; continue }
        default { throw "Unknown argument: $arg" }
    }
}

if ([string]::IsNullOrWhiteSpace($TstFileId)) {
    Show-Usage
    throw "Error: --tst-file-id is required."
}

if (-not $ReportOutputDirSpecified) {
    $ReportOutputDir = Get-DefaultReportOutputDir
}
New-Item -ItemType Directory -Path $ReportOutputDir -Force | Out-Null

. "$PSScriptRoot/soatest-scenario-execution-helpers.ps1"

Initialize-SoaConfig -ServerHost $ServerHost -Port $Port -Protocol $Protocol -Username $Username -Password $Password -BearerToken $BearerToken -DeadlineMinutes 20

# ---------------------------------------------------------------------------
# Execute tests
# ---------------------------------------------------------------------------
Write-Output ""
Write-Output "=== [1/2] Executing tests: $TstFileId ==="
$jobId = if ([string]::IsNullOrWhiteSpace($ExecutionJson)) {
    Invoke-SoaExecution -TstFileId $TstFileId -Config $Config
} else {
    Invoke-SoaExecutionWithJson -JsonBody $ExecutionJson
}
if ($jobId -and $jobId.PSObject.Properties['succeeded'] -and -not $jobId.succeeded) {
    Write-Error "[FATAL] Could not start test execution: $($jobId.errorMessage)"
    if ([string]::IsNullOrWhiteSpace($jobId.responsePayload)) {
        Write-Error "[FATAL] Start execution response payload: <empty>"
    } else {
        Write-Error "[FATAL] Start execution response payload: $($jobId.responsePayload)"
    }
    exit 1
}
if (-not $jobId) {
    Write-Error "[FATAL] Could not start test execution. Aborting."
    exit 1
}
Wait-SoaExecution -JobId $jobId -PollIntervalSeconds $PollIntervalSeconds -MaxWaitMinutes $MaxWaitMinutes

# ---------------------------------------------------------------------------
# Retrieve and save execution report archive
# ---------------------------------------------------------------------------
Write-Output ""
Write-Output "=== [2/2] Retrieving execution report ==="

# Derive a report directory name from the .tst file's base name
$tstBase        = [System.IO.Path]::GetFileNameWithoutExtension(($TstFileId -split '/')[-1])
$runTimestamp   = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$reportBaseName = "$tstBase-execution-report-$runTimestamp"
$archivePath    = Join-Path $ReportOutputDir "$reportBaseName.zip"
$execReportDir  = Join-Path $ReportOutputDir $reportBaseName
$reportHtmlPath = Join-Path $execReportDir "report.html"

$execResults = Get-SoaExecutionResults -JobId $jobId
$reportXmlPath = $null
if ($execResults -and $execResults.PSObject.Properties['reportArchive'] -and $execResults.reportArchive) {
    $archiveBytes = [System.Convert]::FromBase64String($execResults.reportArchive)
    [System.IO.File]::WriteAllBytes($archivePath, $archiveBytes)
    if (Test-Path $execReportDir) { Remove-Item $execReportDir -Recurse -Force }
    Expand-Archive -Path $archivePath -DestinationPath $execReportDir
    Remove-Item $archivePath -Force
    Write-Output "  Execution report: $execReportDir"
    $reportXmlPath = Join-Path $execReportDir "report.xml"
} else {
    # Fall back to separately requesting the xml/html reports when the archive isn't available
    $execResults = Get-SoaExecutionResults -JobId $jobId
    if ($execResults -and (($execResults.PSObject.Properties['xmlReport'] -and $execResults.xmlReport) -or ($execResults.PSObject.Properties['htmlReport'] -and $execResults.htmlReport))) {
        New-Item -ItemType Directory -Path $execReportDir -Force | Out-Null
        if ($execResults.PSObject.Properties['xmlReport'] -and $execResults.xmlReport) {
            $reportXmlPath = Join-Path $execReportDir "report.xml"
            [System.IO.File]::WriteAllBytes($reportXmlPath, [System.Convert]::FromBase64String($execResults.xmlReport))
        }
        if ($execResults.PSObject.Properties['htmlReport'] -and $execResults.htmlReport) {
            [System.IO.File]::WriteAllBytes($reportHtmlPath, [System.Convert]::FromBase64String($execResults.htmlReport))
        }
        Write-Output "  Execution report: $execReportDir"
    } else {
        Write-Warning "[WARN] Report archive not available in execution results."
    }
}

if ($reportXmlPath) {
    if (Test-Path $reportXmlPath) {
        [xml]$reportXml = Get-Content $reportXmlPath -Raw -Encoding UTF8
        $project = $reportXml.SelectSingleNode('/ResultsSession/Exec/Projects/Project')
        if ($project) {
            $total  = [int]$project.total
            $passed = [int]$project.pass
            $failed = if ($project.fail) { [int]$project.fail } else { 0 }
            $errors = if ($project.err)  { [int]$project.err  } else { 0 }
            Write-Output ""
            Write-Output "=== Test Execution Summary ==="
            Write-Output "  Total:   $total"
            Write-Output "  Passed:  $passed"
            $combinedFailed = $failed + $errors
            Write-Output "  Failed:  $combinedFailed"
        }
        if ($OutputPerTestJson) {
            $perTestResults  = Get-SoaPerTestResults -ReportXml $reportXml
            $perTestJsonPath = Join-Path $execReportDir "per-test-results.json"
            $perTestResults | ConvertTo-Json -Depth 3 | Set-Content $perTestJsonPath -Encoding UTF8
            Write-Output ""
            Write-Output "=== Per-Test Results ==="
            foreach ($r in $perTestResults) {
                $code = if ($null -ne $r.httpStatusCode) { $r.httpStatusCode } else { '-' }
                $viol = if ($r.violationMsg) { " | $($r.violationMsg)" } else { '' }
                Write-Output ("  [{0,-4}] HTTP {1} | {2}{3}" -f $r.status.ToUpper(), $code, $r.testName, $viol)
            }
            Write-Output ""
            Write-Output "[OK] Per-test results: $perTestJsonPath"
        }
    }
}

Write-Output ""
Write-Output "=== [3/3] Cleaning up execution history ==="
$cleanupSucceeded = Remove-SoaExecution -JobId $jobId
if ($cleanupSucceeded) {
    Write-Output "  [OK] Deleted execution history for job: $jobId"
} else {
    Write-Warning "  [WARN] Could not delete execution history for job: $jobId"
}

Write-Output ""
Write-Output "=== DONE ==="
Write-Output "  .tst file: $TstFileId"
if (Test-Path $execReportDir) {
    Write-Output "  Execution report: $execReportDir"
}
if (Test-Path $reportHtmlPath) {
    Write-Output "  HTML report: $reportHtmlPath"
} else {
    Write-Output "  HTML report: not generated"
}
