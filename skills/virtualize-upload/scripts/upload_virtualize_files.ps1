#Requires -Version 5.1

$ErrorActionPreference = "Stop"

function Show-Usage {
  @"
Usage:
  scripts/upload_virtualize_files.ps1 --host HOST --port PORT --source PATH [options]

Required:
  --host HOST                 Virtualize server host (e.g. localhost)
  --port PORT                 Virtualize server port (e.g. 9080)
  --source PATH               File path or directory path to upload

Optional:
  --protocol PROTOCOL         http or https (default: http)
  --id ID                     Required upload id when source is a single file.
                              If omitted for single file, basename(source) is used.
  --id-prefix PREFIX          Prefix used for directory uploads.
                              Final id for each file is PREFIX/relative/path.
  --deploy true|false         Query parameter deploy (default: true)
  --replace true|false        Query parameter replace (default: false)
  --username USER             Virtualize API username (or use VIRT_USERNAME env var)
  --password PASS             Virtualize API password (or use VIRT_PASSWORD env var)
  --bearer-token TOKEN        Virtualize API bearer token (or use VIRT_BEARER_TOKEN env var)
                              When set, bearer auth is used instead of basic auth.
  --quiet-success true|false  Suppress per-file success lines (default: false)
  --progress-every N          Emit PROGRESS every N files (default: 25, 0 disables)
  --log-format FORMAT         text or jsonl (default: text)
  --summary-file PATH         Write final JSON summary to file
  --failures-file PATH        Write failure records as JSONL to file
  --timeout-seconds N         Per-file HTTP timeout seconds (default: 120)
  --max-retries N             Retries per file after first attempt (default: 2)
  --retry-backoff-ms N        Delay between retries in ms (default: 500)
  --continue-on-error true|false
                              Continue processing after a failed file (default: true)
  --dry-run true|false        Resolve files and IDs without uploading (default: false)
  --help                      Show this help text

Examples:
  .\scripts\upload_virtualize_files.ps1 --host localhost --port 9080 --source .\asset.pva --id "VirtualAssets/asset.pva"
  .\scripts\upload_virtualize_files.ps1 --host localhost --port 9080 --source .\assets --id-prefix "VirtualAssets"
  .\scripts\upload_virtualize_files.ps1 --host localhost --port 9080 --source .\assets --id-prefix "VirtualAssets" --quiet-success true --progress-every 25 --summary-file $env:TEMP\upload-summary.json
"@
}

function Normalize-Bool([string]$Value, [string]$FlagName) {
  if ($null -eq $Value) { throw "Error: --$FlagName must be 'true' or 'false'." }
  $lower = $Value.ToLowerInvariant()
  if ($lower -eq "true" -or $lower -eq "false") {
    return $lower
  }
  throw "Error: --$FlagName must be 'true' or 'false'."
}

function Test-NonNegativeInt([string]$Value, [string]$FlagName) {
  if ($null -eq $Value -or $Value -notmatch '^\d+$') {
    throw "Error: --$FlagName must be a non-negative integer."
  }
  return [int]$Value
}

function Is-Blank([string]$Value) {
  return ($null -eq $Value -or $Value.Trim().Length -eq 0)
}

function Build-UploadId([string]$FilePath, [string]$RelPath, [string]$SingleId, [string]$IdPrefix) {
  if ($SingleId) {
    return $SingleId
  }
  if ($RelPath) {
    $prefixNoTrailing = if ($null -eq $IdPrefix) { "" } else { $IdPrefix.TrimEnd('/') }
    if ($prefixNoTrailing) {
      return "$prefixNoTrailing/$RelPath"
    }
    return $RelPath
  }
  if ($IdPrefix) {
    $prefixNoTrailing = $IdPrefix.TrimEnd('/')
    return "$prefixNoTrailing/$(Split-Path -Leaf $FilePath)"
  }
  return Split-Path -Leaf $FilePath
}

function Ensure-ParentDir([string]$Path) {
  $parent = Split-Path -Parent $Path
  if ($parent -and -not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
  }
}

function Emit-Event([string]$EventName, [hashtable]$Fields, [string]$Format) {
  if ($Format -eq "jsonl") {
    $payload = [ordered]@{ event = $EventName }
    foreach ($key in $Fields.Keys) {
      $payload[$key] = $Fields[$key]
    }
    Write-Output ($payload | ConvertTo-Json -Compress)
    return
  }

  $parts = @()
  foreach ($key in $Fields.Keys) {
    $value = [string]$Fields[$key]
    $value = $value.Replace("`r", " ").Replace("`n", " ")
    $value = $value.Replace("'", "''")
    $parts += "$key='$value'"
  }
  if ($parts.Count -gt 0) {
    Write-Output ("{0} {1}" -f $EventName, ($parts -join " "))
  } else {
    Write-Output $EventName
  }
}

function Append-FailureArtifact(
  [string]$FailuresFile,
  [string]$FilePath,
  [string]$UploadId,
  [string]$Status,
  [int]$Attempts,
  [string]$Error,
  [string]$Detail
) {
  if (Is-Blank $FailuresFile) {
    return
  }
  Ensure-ParentDir $FailuresFile
  $record = [ordered]@{
    file     = $FilePath
    id       = $UploadId
    status   = $Status
    attempts = $Attempts
    error    = $Error
    detail   = $Detail
  }
  Add-Content -LiteralPath $FailuresFile -Value (($record | ConvertTo-Json -Compress)) -Encoding UTF8
}

$hostName = ""
$port = ""
$protocol = "http"
$source = ""
$singleId = ""
$idPrefix = ""
$deploy = "true"
$replace = "false"
$username = if ($env:VIRT_USERNAME) { $env:VIRT_USERNAME } else { "" }
$password = if ($env:VIRT_PASSWORD) { $env:VIRT_PASSWORD } else { "" }
$bearerToken = if ($env:VIRT_BEARER_TOKEN) { $env:VIRT_BEARER_TOKEN } else { "" }
$quietSuccess = "false"
$progressEveryRaw = "25"
$logFormat = "text"
$summaryFile = ""
$failuresFile = ""
$timeoutSecondsRaw = "120"
$maxRetriesRaw = "2"
$retryBackoffMsRaw = "500"
$continueOnError = "true"
$dryRun = "false"

for ($i = 0; $i -lt $args.Count; $i++) {
  $arg = $args[$i]
  switch ($arg) {
    "--host" { if ($i + 1 -ge $args.Count) { throw "Missing value for --host" }; $hostName = $args[++$i]; continue }
    "--port" { if ($i + 1 -ge $args.Count) { throw "Missing value for --port" }; $port = $args[++$i]; continue }
    "--protocol" { if ($i + 1 -ge $args.Count) { throw "Missing value for --protocol" }; $protocol = $args[++$i]; continue }
    "--source" { if ($i + 1 -ge $args.Count) { throw "Missing value for --source" }; $source = $args[++$i]; continue }
    "--id" { if ($i + 1 -ge $args.Count) { throw "Missing value for --id" }; $singleId = $args[++$i]; continue }
    "--id-prefix" { if ($i + 1 -ge $args.Count) { throw "Missing value for --id-prefix" }; $idPrefix = $args[++$i]; continue }
    "--deploy" { if ($i + 1 -ge $args.Count) { throw "Missing value for --deploy" }; $deploy = $args[++$i]; continue }
    "--replace" { if ($i + 1 -ge $args.Count) { throw "Missing value for --replace" }; $replace = $args[++$i]; continue }
    "--username" { if ($i + 1 -ge $args.Count) { throw "Missing value for --username" }; $username = $args[++$i]; continue }
    "--password" { if ($i + 1 -ge $args.Count) { throw "Missing value for --password" }; $password = $args[++$i]; continue }
    "--bearer-token" { if ($i + 1 -ge $args.Count) { throw "Missing value for --bearer-token" }; $bearerToken = $args[++$i]; continue }
    "--quiet-success" { if ($i + 1 -ge $args.Count) { throw "Missing value for --quiet-success" }; $quietSuccess = $args[++$i]; continue }
    "--progress-every" { if ($i + 1 -ge $args.Count) { throw "Missing value for --progress-every" }; $progressEveryRaw = $args[++$i]; continue }
    "--log-format" { if ($i + 1 -ge $args.Count) { throw "Missing value for --log-format" }; $logFormat = $args[++$i]; continue }
    "--summary-file" { if ($i + 1 -ge $args.Count) { throw "Missing value for --summary-file" }; $summaryFile = $args[++$i]; continue }
    "--failures-file" { if ($i + 1 -ge $args.Count) { throw "Missing value for --failures-file" }; $failuresFile = $args[++$i]; continue }
    "--timeout-seconds" { if ($i + 1 -ge $args.Count) { throw "Missing value for --timeout-seconds" }; $timeoutSecondsRaw = $args[++$i]; continue }
    "--max-retries" { if ($i + 1 -ge $args.Count) { throw "Missing value for --max-retries" }; $maxRetriesRaw = $args[++$i]; continue }
    "--retry-backoff-ms" { if ($i + 1 -ge $args.Count) { throw "Missing value for --retry-backoff-ms" }; $retryBackoffMsRaw = $args[++$i]; continue }
    "--continue-on-error" { if ($i + 1 -ge $args.Count) { throw "Missing value for --continue-on-error" }; $continueOnError = $args[++$i]; continue }
    "--dry-run" { if ($i + 1 -ge $args.Count) { throw "Missing value for --dry-run" }; $dryRun = $args[++$i]; continue }
    "--help" { Show-Usage; exit 0 }
    "-h" { Show-Usage; exit 0 }
    default { throw "Unknown argument: $arg" }
  }
}

if ((Is-Blank $hostName) -or (Is-Blank $port) -or (Is-Blank $source)) {
  throw "Error: --host, --port, and --source are required."
}

if ($protocol -ne "http" -and $protocol -ne "https") {
  throw "Error: --protocol must be 'http' or 'https'."
}

if ($deploy -ne "true" -and $deploy -ne "false") {
  throw "Error: --deploy must be 'true' or 'false'."
}

if ($replace -ne "true" -and $replace -ne "false") {
  throw "Error: --replace must be 'true' or 'false'."
}

$quietSuccess = Normalize-Bool $quietSuccess "quiet-success"
$continueOnError = Normalize-Bool $continueOnError "continue-on-error"
$dryRun = Normalize-Bool $dryRun "dry-run"

if ($logFormat -ne "text" -and $logFormat -ne "jsonl") {
  throw "Error: --log-format must be 'text' or 'jsonl'."
}

$progressEvery = Test-NonNegativeInt $progressEveryRaw "progress-every"
$timeoutSeconds = Test-NonNegativeInt $timeoutSecondsRaw "timeout-seconds"
$maxRetries = Test-NonNegativeInt $maxRetriesRaw "max-retries"
$retryBackoffMs = Test-NonNegativeInt $retryBackoffMsRaw "retry-backoff-ms"

if (-not (Test-Path -LiteralPath $source)) {
  throw "Error: source path not found: $source"
}

$resolvedSource = (Resolve-Path -LiteralPath $source).Path
$uploadUrl = "{0}://{1}:{2}/soavirt/api/v6/files/upload" -f $protocol, $hostName, $port
$curlExe = (Get-Command curl.exe -ErrorAction SilentlyContinue).Source
if (Is-Blank $curlExe) {
  throw "Error: curl.exe was not found on PATH. Install curl and try again."
}

$files = @()
$sourceItem = Get-Item -LiteralPath $resolvedSource
if (-not $sourceItem.PSIsContainer) {
  $files = @($resolvedSource)
} else {
  $files = Get-ChildItem -LiteralPath $resolvedSource -File -Recurse | Sort-Object FullName | ForEach-Object { $_.FullName }
}
$totalFiles = $files.Count

$mode = if ($dryRun -eq "true") { "dry-run" } else { "upload" }
$authMode = if (-not (Is-Blank $bearerToken)) { "bearer" } elseif (-not (Is-Blank $username)) { "basic" } else { "none" }

Emit-Event "START" ([ordered]@{
  mode = $mode
  source = $resolvedSource
  total = $totalFiles
}) $logFormat

Emit-Event "PREFLIGHT" ([ordered]@{
  protocol = $protocol
  host = $hostName
  port = [int]$port
  source = $resolvedSource
  id_prefix = $idPrefix
  single_id = $singleId
  deploy = $deploy
  replace = $replace
  auth_mode = $authMode
  log_format = $logFormat
  quiet_success = ($quietSuccess -eq "true")
  progress_every = $progressEvery
  timeout_seconds = $timeoutSeconds
  max_retries = $maxRetries
  retry_backoff_ms = $retryBackoffMs
  continue_on_error = ($continueOnError -eq "true")
  dry_run = ($dryRun -eq "true")
}) $logFormat

if (-not (Is-Blank $failuresFile)) {
  Ensure-ParentDir $failuresFile
  Set-Content -LiteralPath $failuresFile -Value $null -Encoding UTF8
}
function Upload-One([string]$FilePath, [string]$UploadId) {
  $attempt = 0
  $lastStatus = "none"
  $lastError = ""
  $lastDetail = ""

  while ($attempt -le $maxRetries) {
    $attempt++
    $responseFile = New-TemporaryFile
    $errorFile = New-TemporaryFile

    try {
      $curlArgs = @(
        "-sS",
        "--max-time", [string]$timeoutSeconds,
        "-o", $responseFile.FullName,
        "-w", "%{http_code}",
        "-X", "POST",
        $uploadUrl,
        "--get",
        "--url-query", "id=$UploadId",
        "--url-query", "deploy=$deploy",
        "--url-query", "replace=$replace",
        "-F", "file=@$FilePath"
      )

      if (-not (Is-Blank $bearerToken)) {
        $curlArgs += @("-H", "Authorization: Bearer $bearerToken")
      } elseif (-not (Is-Blank $username)) {
        $curlArgs += @("-u", ("{0}:{1}" -f $username, $password))
      }

      $statusCode = & $curlExe @curlArgs 2> $errorFile.FullName
      $curlExitCode = $LASTEXITCODE
      $body = if (Test-Path -LiteralPath $responseFile.FullName) { Get-Content -LiteralPath $responseFile.FullName -Raw } else { "" }
      $errBody = if (Test-Path -LiteralPath $errorFile.FullName) { Get-Content -LiteralPath $errorFile.FullName -Raw } else { "" }

      if ($curlExitCode -eq 0 -and $statusCode -match "^2\d\d$") {
        return [pscustomobject]@{
          Success = $true
          Status = [string]$statusCode
          Error = ""
          Detail = ""
          Attempts = $attempt
        }
      }

      if ($curlExitCode -eq 0) {
        $lastStatus = [string]$statusCode
        $lastError = "http_status_$statusCode"
        $lastDetail = $body
      } else {
        $lastStatus = "none"
        $lastError = "curl_exit_$curlExitCode"
        $lastDetail = $errBody
      }
    } catch {
      $lastStatus = "none"
      $lastError = "exception"
      $lastDetail = $_.Exception.Message
    } finally {
      Remove-Item -LiteralPath $responseFile.FullName -Force -ErrorAction SilentlyContinue
      Remove-Item -LiteralPath $errorFile.FullName -Force -ErrorAction SilentlyContinue
    }

    if ($attempt -le $maxRetries -and $retryBackoffMs -gt 0) {
      Start-Sleep -Milliseconds $retryBackoffMs
    }
  }

  return [pscustomobject]@{
    Success = $false
    Status = $lastStatus
    Error = $lastError
    Detail = $lastDetail
    Attempts = $attempt
  }
}

function Emit-ProgressEvent([int]$Processed, [int]$Total, [int]$Failed, [datetime]$StartedAtUtc) {
  $elapsedSeconds = [int]((New-TimeSpan -Start $StartedAtUtc -End (Get-Date).ToUniversalTime()).TotalSeconds)
  $percent = if ($Total -gt 0) { [int](($Processed * 100) / $Total) } else { 100 }
  $rate = if ($elapsedSeconds -gt 0) { [int]($Processed / $elapsedSeconds) } else { 0 }
  $eta = if ($rate -gt 0) { [int](($Total - $Processed) / $rate) } else { -1 }
  Emit-Event "PROGRESS" ([ordered]@{
    uploaded = $Processed
    total = $Total
    failed = $Failed
    percent = $percent
    elapsed_seconds = $elapsedSeconds
    rate_files_per_second = $rate
    eta_seconds = $eta
  }) $logFormat
}

$processed = 0
$okCount = 0
$failures = 0
$startedAtUtc = (Get-Date).ToUniversalTime()
$lastProgressUploaded = -1

foreach ($fullName in $files) {
  $relPath = ""
  if ($sourceItem.PSIsContainer) {
    $baseDir = $resolvedSource.TrimEnd('\', '/')
    $relPath = $fullName.Substring($baseDir.Length).TrimStart('\', '/')
    $relPath = $relPath -replace '\\', '/'
  }
  $uploadId = Build-UploadId -FilePath $fullName -RelPath $relPath -SingleId $singleId -IdPrefix $idPrefix

  if ($dryRun -eq "true") {
    $okCount++
    if ($quietSuccess -ne "true") {
      Emit-Event "DRYRUN" ([ordered]@{ file = $fullName; id = $uploadId }) $logFormat
    }
  } else {
    $result = Upload-One -FilePath $fullName -UploadId $uploadId
    if ($result.Success) {
      $okCount++
      if ($quietSuccess -ne "true") {
        Emit-Event "OK" ([ordered]@{
          file = $fullName
          id = $uploadId
          status = $result.Status
          attempts = $result.Attempts
        }) $logFormat
      }
    } else {
      $failures++
      Emit-Event "FAIL" ([ordered]@{
        file = $fullName
        id = $uploadId
        status = $result.Status
        attempts = $result.Attempts
        error = $result.Error
      }) $logFormat
      Append-FailureArtifact -FailuresFile $failuresFile -FilePath $fullName -UploadId $uploadId -Status $result.Status -Attempts $result.Attempts -Error $result.Error -Detail $result.Detail

      if ($continueOnError -ne "true") {
        $processed++
        Emit-ProgressEvent -Processed $processed -Total $totalFiles -Failed $failures -StartedAtUtc $startedAtUtc
        $lastProgressUploaded = $processed
        break
      }
    }
  }

  $processed++
  if ($progressEvery -gt 0) {
    if (($processed % $progressEvery -eq 0) -or ($processed -eq $totalFiles)) {
      Emit-ProgressEvent -Processed $processed -Total $totalFiles -Failed $failures -StartedAtUtc $startedAtUtc
      $lastProgressUploaded = $processed
    }
  }
}

if ($lastProgressUploaded -ne $processed) {
  Emit-ProgressEvent -Processed $processed -Total $totalFiles -Failed $failures -StartedAtUtc $startedAtUtc
}

$elapsedSecondsFinal = [int]((New-TimeSpan -Start $startedAtUtc -End (Get-Date).ToUniversalTime()).TotalSeconds)
Emit-Event "DONE" ([ordered]@{
  mode = $mode
  total = $totalFiles
  ok = $okCount
  failed = $failures
  elapsed_seconds = $elapsedSecondsFinal
}) $logFormat

if (-not (Is-Blank $summaryFile)) {
  Ensure-ParentDir $summaryFile
  $summary = [ordered]@{
    mode = $mode
    source = $resolvedSource
    host = $hostName
    port = [int]$port
    protocol = $protocol
    total_files = $totalFiles
    ok = $okCount
    failed = $failures
    elapsed_seconds = $elapsedSecondsFinal
    log_format = $logFormat
    quiet_success = ($quietSuccess -eq "true")
    progress_every = $progressEvery
    max_retries = $maxRetries
    timeout_seconds = $timeoutSeconds
    retry_backoff_ms = $retryBackoffMs
    continue_on_error = ($continueOnError -eq "true")
    failures_file = if (Is-Blank $failuresFile) { $null } else { $failuresFile }
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
  }
  Set-Content -LiteralPath $summaryFile -Value (($summary | ConvertTo-Json -Depth 5)) -Encoding UTF8
}

if ($failures -gt 0) {
  exit 1
}
exit 0
