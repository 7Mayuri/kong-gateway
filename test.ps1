# Runs every scenario and edge case against the running stack.
# Start the stack first (docker-compose up), then run this in a second terminal.

param(
    [string]$KongUrl = "http://localhost:8000",
    [string]$AdminUrl = "http://localhost:8001",
    [string]$BackendUrl = "http://localhost:5000",
    [switch]$SkipResilience,
    [switch]$SkipRateLimit
)

$ErrorActionPreference = "Continue"
$script:Passed = 0
$script:Failed = 0
$script:FailedNames = @()

function Write-Section($Title) {
    Write-Host ""
    Write-Host "=== $Title ===" -ForegroundColor Cyan
}

# Returns the status code and body of a curl call as one object.
function Invoke-Req {
    param([string[]]$CurlArgs)

    $raw = & curl.exe -s -w "`n%{http_code}" @CurlArgs 2>$null
    $lines = @($raw -split "`n")
    $code = $lines[-1].Trim()
    $body = if ($lines.Count -gt 1) { ($lines[0..($lines.Count - 2)] -join "`n").Trim() } else { "" }

    return [pscustomobject]@{ Code = $code; Body = $body }
}

function Check {
    param(
        [string]$Name,
        [string]$Expected,
        $Result,
        [string]$Contains
    )

    $ok = $Result.Code -eq $Expected
    if ($ok -and $Contains) {
        $ok = $Result.Body -like "*$Contains*"
    }

    if ($ok) {
        Write-Host ("  PASS  {0,-52} [{1}]" -f $Name, $Result.Code) -ForegroundColor Green
        $script:Passed++
    }
    else {
        Write-Host ("  FAIL  {0,-52} [{1}, expected {2}]" -f $Name, $Result.Code, $Expected) -ForegroundColor Red
        if ($Contains) { Write-Host "        expected body to contain: $Contains" -ForegroundColor DarkRed }
        Write-Host "        got: $($Result.Body)" -ForegroundColor DarkRed
        $script:Failed++
        $script:FailedNames += $Name
    }
}

Write-Host "Kong POC - full scenario and edge case suite" -ForegroundColor White
Write-Host "Kong: $KongUrl   Admin: $AdminUrl   Backend: $BackendUrl"

# ---------------------------------------------------------------------------
Write-Section "1. Preflight"

$r = Invoke-Req @("$BackendUrl/health")
Check "backend is reachable" "200" $r
if ($r.Code -ne "200") {
    Write-Host "`nBackend is not up. Run 'docker-compose up -d' first." -ForegroundColor Red
    exit 1
}

$r = Invoke-Req @("$AdminUrl/status")
Check "kong admin api is reachable" "200" $r
if ($r.Code -ne "200") {
    Write-Host "`nKong is not up. Run 'docker-compose up -d' first." -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
Write-Section "2. Backend direct (bypassing Kong)"

Check "GET /health" "200" (Invoke-Req @("$BackendUrl/health")) "ok"
Check "GET /api/ping" "200" (Invoke-Req @("$BackendUrl/api/ping")) "hello from app"
Check "GET /api/hello defaults to World" "200" (Invoke-Req @("$BackendUrl/api/hello")) "Hello, World!"
Check "GET /api/hello?name=Kong" "200" (Invoke-Req @("$BackendUrl/api/hello?name=Kong")) "Hello, Kong!"
Check "GET /api/data" "200" (Invoke-Req @("$BackendUrl/api/data")) "Item A"
Check "unknown path returns JSON 404" "404" (Invoke-Req @("$BackendUrl/does-not-exist")) "Not Found"

# ---------------------------------------------------------------------------
Write-Section "3. Backend error handling (edge cases)"

$malformed = Invoke-Req @("-X", "POST", "-H", "Content-Type: application/json", "--data", '{"broken":', "$BackendUrl/api/ping")
Check "malformed JSON body returns JSON 400" "400" $malformed "Malformed JSON body"

$bigFile = Join-Path $env:TEMP "kong-poc-big.json"
('{"a":"' + ('x' * 20000) + '"}') | Set-Content -Path $bigFile -NoNewline -Encoding ascii
$tooLarge = Invoke-Req @("-X", "POST", "-H", "Content-Type: application/json", "--data", "@$bigFile", "$BackendUrl/api/ping")
Check "oversized body returns JSON 413" "413" $tooLarge "Payload too large"
Remove-Item $bigFile -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------
Write-Section "4. Kong routing"

Check "GET /health through Kong (no auth needed)" "200" (Invoke-Req @("$KongUrl/health")) "ok"
Check "GET /api/ping through Kong" "200" (Invoke-Req @("$KongUrl/api/ping")) "hello from app"
Check "unrouted path returns 404" "404" (Invoke-Req @("$KongUrl/nothing-here"))
Check "POST to a GET-only route returns 404" "404" (Invoke-Req @("-X", "POST", "$KongUrl/api/hello"))

# ---------------------------------------------------------------------------
Write-Section "5. x-environment validation (custom plugin)"

Check "DEV is accepted" "200" (Invoke-Req @("-H", "x-environment: DEV", "$KongUrl/api/hello")) "Hello"
Check "UAT is accepted" "200" (Invoke-Req @("-H", "x-environment: UAT", "$KongUrl/api/hello")) "Hello"
Check "PROD is accepted" "200" (Invoke-Req @("-H", "x-environment: PROD", "$KongUrl/api/hello")) "Hello"
Check "lowercase dev is accepted" "200" (Invoke-Req @("-H", "x-environment: dev", "$KongUrl/api/hello"))
Check "mixed case Uat is accepted" "200" (Invoke-Req @("-H", "x-environment: Uat", "$KongUrl/api/hello"))
Check "padded '  PROD  ' is accepted" "200" (Invoke-Req @("-H", "x-environment:   PROD  ", "$KongUrl/api/hello"))

Check "missing header returns 400" "400" (Invoke-Req @("$KongUrl/api/hello")) "Missing x-environment header"
Check "unknown value returns 403" "403" (Invoke-Req @("-H", "x-environment: STAGING", "$KongUrl/api/hello")) "Allowed values: DEV, UAT, PROD"
Check "empty header value returns 400" "400" (Invoke-Req @("-H", "x-environment;", "$KongUrl/api/hello")) "Missing x-environment header"
Check "duplicate headers return 400" "400" (Invoke-Req @("-H", "x-environment: DEV", "-H", "x-environment: PROD", "$KongUrl/api/hello")) "Duplicate x-environment header"
Check "numeric value returns 403" "403" (Invoke-Req @("-H", "x-environment: 12345", "$KongUrl/api/hello"))
Check "near miss 'DEVELOPMENT' returns 403" "403" (Invoke-Req @("-H", "x-environment: DEVELOPMENT", "$KongUrl/api/hello"))
Check "route without the plugin ignores a bad value" "200" (Invoke-Req @("-H", "x-environment: NONSENSE", "$KongUrl/api/ping"))

$r = Invoke-Req @("-H", "x-environment: STAGING", "$KongUrl/api/hello")
Check "plugin errors are JSON, not HTML" "403" $r '"error"'

# ---------------------------------------------------------------------------
Write-Section "6. Key authentication"

Check "valid demo key is accepted" "200" (Invoke-Req @("-H", "apikey: demo-api-key-12345", "$KongUrl/api/data")) "Item A"
Check "valid test key is accepted" "200" (Invoke-Req @("-H", "apikey: test-api-key-67890", "$KongUrl/api/data")) "Item A"
Check "key passed as query string is accepted" "200" (Invoke-Req @("$KongUrl/api/data?apikey=demo-api-key-12345"))
Check "missing key returns 401" "401" (Invoke-Req @("$KongUrl/api/data"))
Check "invalid key returns 401" "401" (Invoke-Req @("-H", "apikey: not-a-real-key", "$KongUrl/api/data"))
Check "empty key returns 401" "401" (Invoke-Req @("-H", "apikey;", "$KongUrl/api/data"))
Check "key auth route ignores x-environment" "200" (Invoke-Req @("-H", "apikey: demo-api-key-12345", "-H", "x-environment: NONSENSE", "$KongUrl/api/data"))

# ---------------------------------------------------------------------------
Write-Section "7. Upstream failure handling"

if ($SkipResilience) {
    Write-Host "  SKIP  (-SkipResilience)" -ForegroundColor Yellow
}
else {
    Write-Host "  stopping backend container..." -ForegroundColor DarkGray
    docker stop kong-backend *> $null

    $down = Invoke-Req @("$KongUrl/api/ping")
    $isGatewayError = $down.Code -in @("502", "503")
    if ($isGatewayError) {
        Write-Host ("  PASS  {0,-52} [{1}]" -f "Kong returns a gateway error when backend is down", $down.Code) -ForegroundColor Green
        $script:Passed++
    }
    else {
        Write-Host ("  FAIL  {0,-52} [{1}, expected 502 or 503]" -f "Kong returns a gateway error when backend is down", $down.Code) -ForegroundColor Red
        $script:Failed++
        $script:FailedNames += "backend down returns gateway error"
    }

    Check "Kong itself stays up while backend is down" "200" (Invoke-Req @("$AdminUrl/status"))

    Write-Host "  restarting backend container..." -ForegroundColor DarkGray
    docker start kong-backend *> $null

    $recovered = $false
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 1
        if ((Invoke-Req @("$KongUrl/api/ping")).Code -eq "200") { $recovered = $true; break }
    }
    if ($recovered) {
        Write-Host ("  PASS  {0,-52} [200]" -f "traffic recovers after backend restarts") -ForegroundColor Green
        $script:Passed++
    }
    else {
        Write-Host ("  FAIL  {0,-52}" -f "traffic recovers after backend restarts") -ForegroundColor Red
        $script:Failed++
        $script:FailedNames += "recovery after restart"
    }
}

# ---------------------------------------------------------------------------
Write-Section "8. Rate limiting"

if ($SkipRateLimit) {
    Write-Host "  SKIP  (-SkipRateLimit)" -ForegroundColor Yellow
}
else {
    $headers = & curl.exe -s -D - -o NUL -H "x-environment: DEV" "$KongUrl/api/hello" 2>$null
    if ($headers -match "RateLimit-Limit") {
        Write-Host ("  PASS  {0,-52}" -f "rate limit headers are returned") -ForegroundColor Green
        $script:Passed++
    }
    else {
        Write-Host ("  FAIL  {0,-52}" -f "rate limit headers are returned") -ForegroundColor Red
        $script:Failed++
        $script:FailedNames += "rate limit headers"
    }

    # /api/data allows 30/min, so a burst of 40 must trip the limiter.
    Write-Host "  sending 40 requests to /api/data (limit is 30/min)..." -ForegroundColor DarkGray
    $codes = @()
    for ($i = 1; $i -le 40; $i++) {
        $codes += (& curl.exe -s -o NUL -w "%{http_code}" -H "apikey: demo-api-key-12345" "$KongUrl/api/data" 2>$null)
    }
    $throttled = @($codes | Where-Object { $_ -eq "429" }).Count
    $served = @($codes | Where-Object { $_ -eq "200" }).Count

    if ($throttled -gt 0) {
        Write-Host ("  PASS  {0,-52} [{1} x 200, {2} x 429]" -f "burst is throttled with 429", $served, $throttled) -ForegroundColor Green
        $script:Passed++
    }
    else {
        Write-Host ("  FAIL  {0,-52} [no 429 seen in {1} requests]" -f "burst is throttled with 429", $codes.Count) -ForegroundColor Red
        $script:Failed++
        $script:FailedNames += "rate limit throttling"
    }

    $limited = Invoke-Req @("-H", "apikey: demo-api-key-12345", "$KongUrl/api/data")
    if ($limited.Code -eq "429") {
        Check "429 response body is JSON" "429" $limited '"message"'
    }
    else {
        Write-Host "  NOTE  limiter window already reset, skipping 429 body check" -ForegroundColor Yellow
    }

    Write-Host "  note: /api/data quota is now used up for this minute" -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==============================================" -ForegroundColor White
Write-Host ("Passed: {0}   Failed: {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) {
    Write-Host "Failed checks:" -ForegroundColor Red
    $script:FailedNames | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
Write-Host "All checks passed." -ForegroundColor Green
exit 0
