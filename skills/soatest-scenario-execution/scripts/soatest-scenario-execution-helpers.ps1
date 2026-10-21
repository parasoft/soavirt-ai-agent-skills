# =============================================================================
# SOAtest REST API v6 - Test Execution Helper Functions
# =============================================================================
# Dot-source this script to use all SOAtest execution helper functions.
#
# Usage:
#   . "$PSScriptRoot/soatest-scenario-execution-helpers.ps1"
#   Initialize-SoaConfig -BaseUrl "http://myhost:9080/soavirt/api/v6"
# =============================================================================

$script:SoaBase     = "http://localhost:9080/soavirt/api/v6"
$script:SoaHeaders  = @{ "Content-Type" = "application/json"; "Accept" = "application/json" }
$script:SoaDeadline = $null

function Get-SoaAuthorizationHeader {
    param(
        [string]$Username = "",
        [string]$Password = "",
        [string]$BearerToken = ""
    )

    if (-not [string]::IsNullOrWhiteSpace($BearerToken)) {
        return @{ "Authorization" = "Bearer $BearerToken" }
    }

    if (-not [string]::IsNullOrWhiteSpace($Username)) {
        $credentialString = "{0}:{1}" -f $Username, $Password
        $credentials = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($credentialString))
        return @{ "Authorization" = "Basic $credentials" }
    }

    return @{}
}

# ---------------------------------------------------------------------------
# Initialize-SoaConfig
# Call once at the top of a script to set the SOAtest base URL and optional
# global deadline. Omit -DeadlineMinutes to run without a deadline.
# ---------------------------------------------------------------------------
function Initialize-SoaConfig {
    param(
        [Alias('Host')]
        [string]$ServerHost        = "localhost",
        [int]$Port                 = 9080,
        [ValidateSet('http', 'https')]
        [string]$Protocol          = "http",
        [string]$Username          = "",
        [string]$Password          = "",
        [string]$BearerToken       = "",
        [string]$BaseUrl           = "",
        [int]$DeadlineMinutes      = 0
    )

    if (-not [string]::IsNullOrWhiteSpace($BaseUrl)) {
        $script:SoaBase = $BaseUrl.TrimEnd('/')
    } else {
        $script:SoaBase = "{0}://{1}:{2}/soavirt/api/v6" -f $Protocol, $ServerHost, $Port
    }

    $authHeaders = Get-SoaAuthorizationHeader -Username $Username -Password $Password -BearerToken $BearerToken
    $script:SoaHeaders = @{ "Content-Type" = "application/json"; "Accept" = "application/json" }
    foreach ($headerName in $authHeaders.Keys) {
        $script:SoaHeaders[$headerName] = $authHeaders[$headerName]
    }

    if ($DeadlineMinutes -gt 0) {
        $script:SoaDeadline = (Get-Date).AddMinutes($DeadlineMinutes)
        Write-Output "[SOA] Configured: $($script:SoaBase), deadline in $DeadlineMinutes min"
    } else {
        $script:SoaDeadline = $null
        Write-Output "[SOA] Configured: $($script:SoaBase), no deadline"
    }
}

# ---------------------------------------------------------------------------
# Assert-SoaDeadline (internal)
# ---------------------------------------------------------------------------
function Assert-SoaDeadline {
    param([string]$Context = "")
    if ($script:SoaDeadline -and (Get-Date) -gt $script:SoaDeadline) {
        Write-Error "[DEADLINE] Script deadline exceeded at: $Context"
        exit 1
    }
}

# ---------------------------------------------------------------------------
# Invoke-SoaExecution
# Starts a test execution for the given .tst file ID.
# Returns the job ID string, or $null on failure.
# ---------------------------------------------------------------------------
function Invoke-SoaExecution {
    param(
        [string]$TstFileId,
        [string]$Config = "soatest.builtin://Run Automated Server Tests"
    )
    Assert-SoaDeadline "Invoke-SoaExecution $TstFileId"
    $configJson = ConvertTo-Json $Config
    $idJson     = ConvertTo-Json $TstFileId
    $body = @"
{"general":{"config":$configJson,"localSettings":[{"name":"report.archive","value":"true"}]},"scopeOptions":{"workspace":{"resources":[$idJson]}}}
"@
    try {
        $r = Invoke-WebRequest -Uri "$script:SoaBase/testExecutions" `
            -Method POST -Headers $script:SoaHeaders -Body $body -UseBasicParsing -EA Stop
        $jobId = ($r.Content | ConvertFrom-Json).id
        Write-Host "[OK] Execution started: $jobId"
        return $jobId
    } catch {
        $errMsg = $_.Exception.Message
        $respBody = $_.ErrorDetails.Message
        if ($_.Exception.Response) {
            try {
                $stream = $_.Exception.Response.GetResponseStream()
                $reader = [System.IO.StreamReader]::new($stream)
                $streamBody = $reader.ReadToEnd()
                if (-not [string]::IsNullOrWhiteSpace($streamBody)) { $respBody = $streamBody }
            } catch {}
        }
        Write-Warning "[ERR] Invoke-SoaExecution: $errMsg | Response: $respBody"
        return [PSCustomObject]@{ succeeded = $false; errorMessage = $errMsg; responsePayload = $respBody }
    }
}

# ---------------------------------------------------------------------------
# Invoke-SoaExecutionWithJson
# Starts a test execution using the supplied JSON string as the request body.
# ---------------------------------------------------------------------------
function Invoke-SoaExecutionWithJson {
    param(
        [string]$JsonBody
    )
    Assert-SoaDeadline "Invoke-SoaExecutionWithJson"
    try {
        $r = Invoke-WebRequest -Uri "$script:SoaBase/testExecutions" `
            -Method POST -Headers $script:SoaHeaders -Body $JsonBody -UseBasicParsing -EA Stop
        $jobId = ($r.Content | ConvertFrom-Json).id
        Write-Host "[OK] Execution started: $jobId"
        return $jobId
    } catch {
        $errMsg = $_.Exception.Message
        $respBody = $_.ErrorDetails.Message
        if ($_.Exception.Response) {
            try {
                $stream = $_.Exception.Response.GetResponseStream()
                $reader = [System.IO.StreamReader]::new($stream)
                $streamBody = $reader.ReadToEnd()
                if (-not [string]::IsNullOrWhiteSpace($streamBody)) { $respBody = $streamBody }
            } catch {}
        }
        Write-Warning "[ERR] Invoke-SoaExecutionWithJson: $errMsg | Response: $respBody"
        return [PSCustomObject]@{ succeeded = $false; errorMessage = $errMsg; responsePayload = $respBody }
    }
}

# ---------------------------------------------------------------------------
# Wait-SoaExecution
# Polls the execution status until it completes or the timeout is reached.
# Returns the final status object, or exits 1 on timeout.
# ---------------------------------------------------------------------------
function Wait-SoaExecution {
    param(
        [string]$JobId,
        [int]$PollIntervalSeconds = 2,
        [int]$MaxWaitMinutes      = 15
    )
    $deadline  = (Get-Date).AddMinutes($MaxWaitMinutes)
    $iteration = 0
    Write-Host "[INFO] Polling execution '$JobId' (max ${MaxWaitMinutes}m, interval ${PollIntervalSeconds}s)..."
    while ((Get-Date) -lt $deadline) {
        $iteration++
        try {
            $r = Invoke-WebRequest -Uri "$script:SoaBase/testExecutions/$JobId/status" `
                -Method GET -Headers $script:SoaHeaders -UseBasicParsing -EA Stop
            $status = $r.Content | ConvertFrom-Json
            Write-Host "  [Poll $iteration] isRunning=$($status.isRunning) percent=$($status.percent)"
            if (-not $status.isRunning) { return $status }
        } catch {
            Write-Warning "  [Poll $iteration] Status check failed: $($_.Exception.Message)"
        }
        Start-Sleep -Seconds $PollIntervalSeconds
    }
    Write-Error "[DEADLINE] Execution did not finish within $MaxWaitMinutes minutes"
    exit 1
}

# ---------------------------------------------------------------------------
# Get-SoaExecutionResults
# Retrieves the results of a completed execution.
# ---------------------------------------------------------------------------
function Get-SoaExecutionResults {
    param(
        [string]$JobId
    )
    $query = "?includeReportArchive=true"
    try {
        $r = Invoke-WebRequest -Uri "$script:SoaBase/testExecutions/$JobId/results$query" `
            -Method GET -Headers $script:SoaHeaders -UseBasicParsing -EA Stop
        return $r.Content | ConvertFrom-Json
    } catch {
        Write-Warning "[ERR] Get-SoaExecutionResults '$JobId': $($_.Exception.Message)"
        return $null
    }
}

# ---------------------------------------------------------------------------
# Remove-SoaExecution
# Deletes the execution resource from the server history after reporting.
# ---------------------------------------------------------------------------
function Remove-SoaExecution {
    param(
        [string]$JobId
    )
    try {
        $r = Invoke-WebRequest -Uri "$script:SoaBase/testExecutions/$JobId" `
            -Method DELETE -Headers $script:SoaHeaders -UseBasicParsing -EA Stop
        return $true
    } catch {
        Write-Warning "[WARN] Remove-SoaExecution '$JobId': $($_.Exception.Message)"
        return $false
    }
}

# ---------------------------------------------------------------------------
# Get-HttpStatusFromHeaders (internal)
# ---------------------------------------------------------------------------
function Get-HttpStatusFromHeaders {
    param([string]$Headers)
    if ($Headers -match 'HTTP/\d+\.\d+\s+(\d{3})') { return [int]$Matches[1] }
    return $null
}

# ---------------------------------------------------------------------------
# Get-SoaPerTestResults
# Parses a SOAtest report.xml document into a per-test result array.
# Requires soatest.builtin://Run Automated Server Tests to populate traffic for all tests.
# ---------------------------------------------------------------------------
function Get-SoaPerTestResults {
    param([xml]$ReportXml)

    $trafficMap = @{}
    foreach ($t in $ReportXml.SelectNodes('/ResultsSession/Exec/TrafficData/Traffic')) {
        $trafficMap[$t.tfcRef] = $t
    }

    $violMap = @{}
    foreach ($v in $ReportXml.SelectNodes('/ResultsSession/Exec/ExecViols/FuncViol')) {
        if (-not $violMap.ContainsKey($v.tfcRef)) { $violMap[$v.tfcRef] = $v.msg }
    }

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($test in $ReportXml.SelectNodes('/ResultsSession/Exec/ExecutedTestsDetails//Test[@status]')) {
        $httpCode = $null
        $resBody  = $null
        $violMsg  = $null
        
        if ($test.tfcRef) {
            $traffic = $trafficMap[$test.tfcRef]
            if ($traffic) {
                $httpCode = Get-HttpStatusFromHeaders $traffic.resHeaders
                $resBody  = $traffic.resBody `
                    -replace '&quot;', '"' `
                    -replace '&lt;',   '<' `
                    -replace '&gt;',   '>' `
                    -replace '&amp;',  '&'
            }
            if ($violMap.ContainsKey($test.tfcRef)) {
                $violMsg = $violMap[$test.tfcRef]
            }
        }
        
        $results.Add([PSCustomObject]@{
            testName       = $test.name
            status         = $test.status
            httpStatusCode = $httpCode
            responseBody   = $resBody
            violationMsg   = $violMsg
        })
    }
    return $results
}
