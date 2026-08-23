# Runs every assignment scenario and every extra edge case against the running stack,
# prints the exact command and response for each, and writes an HTML report.
#
#   docker-compose up -d      # terminal 1
#   .\test.ps1                # terminal 2

param(
    [string]$KongUrl = "http://localhost:8000",
    [string]$AdminUrl = "http://localhost:8001",
    [string]$BackendUrl = "http://localhost:5000",
    [string]$ReportPath = "test-report.html",
    [switch]$SkipResilience,
    [switch]$SkipRateLimit,
    [switch]$NoReport,
    [switch]$Open
)

$ErrorActionPreference = "Continue"
$script:Results = @()
$script:StartedAt = Get-Date

$GROUP_A = "Assignment Scenarios"
$GROUP_B = "Edge Cases (beyond the assignment)"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Format-CurlCommand([string[]]$CurlArgs) {
    $parts = $CurlArgs | ForEach-Object {
        if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
    }
    return "curl -i " + ($parts -join ' ')
}

function Invoke-Curl([string[]]$CurlArgs) {
    $raw = & curl.exe -s -w "`n%{http_code}" @CurlArgs 2>$null
    $lines = @($raw -split "`n")
    $code = $lines[-1].Trim()
    $body = if ($lines.Count -gt 1) { ($lines[0..($lines.Count - 2)] -join "`n").Trim() } else { "" }
    return [pscustomobject]@{ Code = $code; Body = $body }
}

function Add-Result($Group, $Id, $Name, $Command, $Expected, $Actual, $Body, $Status, $Note) {
    $script:Results += [pscustomobject]@{
        Group = $Group; Id = $Id; Name = $Name; Command = $Command
        Expected = $Expected; Actual = $Actual; Body = $Body; Status = $Status; Note = $Note
    }

    $color = switch ($Status) { "PASS" { "Green" } "FAIL" { "Red" } default { "Yellow" } }
    Write-Host ""
    Write-Host ("[{0}] {1}" -f $Id, $Name) -ForegroundColor White
    Write-Host ("      $ {0}" -f $Command) -ForegroundColor DarkGray
    if ($Actual) {
        Write-Host ("      -> HTTP {0}   (expected {1})" -f $Actual, $Expected) -ForegroundColor Gray
    }
    if ($Body) {
        foreach ($line in ($Body -split "`n" | Select-Object -First 4)) {
            Write-Host ("      {0}" -f $line.Trim()) -ForegroundColor DarkCyan
        }
    }
    if ($Note) { Write-Host ("      {0}" -f $Note) -ForegroundColor DarkGray }
    Write-Host ("      {0}" -f $Status) -ForegroundColor $color
}

# Runs a curl scenario and records it.
function Test-Scenario {
    param(
        [string]$Group,
        [string]$Id,
        [string]$Name,
        [string[]]$CurlArgs,
        [string]$Expected,
        [string]$Contains,
        [string]$Note
    )

    $cmd = Format-CurlCommand $CurlArgs
    $res = Invoke-Curl $CurlArgs

    $ok = $res.Code -eq $Expected
    if ($ok -and $Contains) { $ok = $res.Body -like "*$Contains*" }

    $status = if ($ok) { "PASS" } else { "FAIL" }
    $detail = $Note
    if (-not $ok -and $Contains -and $res.Code -eq $Expected) {
        $detail = "expected body to contain: $Contains"
    }

    Add-Result $Group $Id $Name $cmd $Expected $res.Code $res.Body $status $detail
}

function Write-GroupHeader($Title) {
    Write-Host ""
    Write-Host ("=" * 78) -ForegroundColor Cyan
    Write-Host ("  $Title") -ForegroundColor Cyan
    Write-Host ("=" * 78) -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "Kong API Gateway - verification run" -ForegroundColor White
Write-Host "Kong proxy : $KongUrl"
Write-Host "Kong admin : $AdminUrl"
Write-Host "Backend    : $BackendUrl"
Write-Host "Started    : $($script:StartedAt.ToString('yyyy-MM-dd HH:mm:ss'))"

# Preflight, not part of the scored scenarios.
$pre = Invoke-Curl @("$BackendUrl/health")
if ($pre.Code -ne "200") {
    Write-Host "`nBackend is not responding. Start the stack with 'docker-compose up -d' first." -ForegroundColor Red
    exit 1
}
$pre = Invoke-Curl @("$AdminUrl/status")
if ($pre.Code -ne "200") {
    Write-Host "`nKong is not responding. Start the stack with 'docker-compose up -d' first." -ForegroundColor Red
    exit 1
}

# ===========================================================================
Write-GroupHeader "PART A - $GROUP_A"
# ===========================================================================

Test-Scenario $GROUP_A "A1" "Sample app is deployed and reachable through Docker" `
    @("$BackendUrl/health") "200" "ok" `
    "Requirement 1: dockerized backend responds"

Test-Scenario $GROUP_A "A2" "Kong service and route proxy traffic to the backend" `
    @("$KongUrl/api/ping") "200" "hello from app" `
    "Requirement 2: service and route configured in kong.yml"

Test-Scenario $GROUP_A "A3" "Key authentication accepts a registered consumer key" `
    @("-H", "apikey: demo-api-key-12345", "$KongUrl/api/data") "200" "Item A" `
    "Requirement 3: key-auth plugin, consumer demo-user"

Test-Scenario $GROUP_A "A4" "Key authentication rejects a request with no key" `
    @("$KongUrl/api/data") "401" "No API key found" `
    "Requirement 3: key-auth plugin"

Test-Scenario $GROUP_A "A5" "Key authentication rejects an unknown key" `
    @("-H", "apikey: not-a-real-key", "$KongUrl/api/data") "401" "" `
    "Requirement 3: key-auth plugin"

Test-Scenario $GROUP_A "A6" "Custom plugin allows x-environment: DEV" `
    @("-H", "x-environment: DEV", "$KongUrl/api/hello") "200" "Hello" `
    "Requirement 4: valid value passes through"

Test-Scenario $GROUP_A "A7" "Custom plugin allows x-environment: UAT" `
    @("-H", "x-environment: UAT", "$KongUrl/api/hello") "200" "Hello" `
    "Requirement 4: valid value passes through"

Test-Scenario $GROUP_A "A8" "Custom plugin allows x-environment: PROD" `
    @("-H", "x-environment: PROD", "$KongUrl/api/hello") "200" "Hello" `
    "Requirement 4: valid value passes through"

Test-Scenario $GROUP_A "A9" "Missing x-environment returns HTTP 400 with a JSON error" `
    @("$KongUrl/api/hello") "400" "Missing x-environment header" `
    "Requirement 4: missing header gives 400"

Test-Scenario $GROUP_A "A10" "Invalid x-environment returns HTTP 403 with a JSON error" `
    @("-H", "x-environment: STAGING", "$KongUrl/api/hello") "403" "Allowed values: DEV, UAT, PROD" `
    "Requirement 4: invalid header gives 403"

Write-Host ""
Write-Host "  (A11, the rate limiting burst, runs at the end because it uses up the route quota)" -ForegroundColor DarkGray

# ===========================================================================
Write-GroupHeader "PART B - $GROUP_B"
# ===========================================================================

Test-Scenario $GROUP_B "B1" "Lowercase value is accepted (case-insensitive match)" `
    @("-H", "x-environment: dev", "$KongUrl/api/hello") "200" "Hello" `
    "Plugin uppercases before comparing"

Test-Scenario $GROUP_B "B2" "Mixed case value is accepted" `
    @("-H", "x-environment: Uat", "$KongUrl/api/hello") "200" "Hello" ""

Test-Scenario $GROUP_B "B3" "Value padded with spaces is accepted" `
    @("-H", "x-environment:   PROD  ", "$KongUrl/api/hello") "200" "Hello" `
    "Plugin trims the header value"

Test-Scenario $GROUP_B "B4" "Header present but empty is treated as missing (400)" `
    @("-H", "x-environment;", "$KongUrl/api/hello") "400" "Missing x-environment header" `
    "An empty value carries no more meaning than an absent one"

Test-Scenario $GROUP_B "B5" "Duplicate x-environment headers are rejected (400)" `
    @("-H", "x-environment: DEV", "-H", "x-environment: PROD", "$KongUrl/api/hello") "400" "Duplicate x-environment header" `
    "Ambiguous intent, so it is rejected rather than silently using the first value"

Test-Scenario $GROUP_B "B6" "Numeric value is rejected (403)" `
    @("-H", "x-environment: 12345", "$KongUrl/api/hello") "403" "" ""

Test-Scenario $GROUP_B "B7" "Near miss DEVELOPMENT is rejected (403)" `
    @("-H", "x-environment: DEVELOPMENT", "$KongUrl/api/hello") "403" "" `
    "Match is exact, not a prefix match"

Test-Scenario $GROUP_B "B8" "A route without the plugin ignores a bad x-environment value" `
    @("-H", "x-environment: NONSENSE", "$KongUrl/api/ping") "200" "hello from app" `
    "Confirms the plugin is scoped per route, not global"

Test-Scenario $GROUP_B "B9" "Plugin errors are JSON, never an HTML error page" `
    @("-H", "x-environment: STAGING", "$KongUrl/api/hello") "403" '"error"' `
    "Uses kong.response.exit() from the Kong PDK"

Test-Scenario $GROUP_B "B10" "API key supplied as a query string is accepted" `
    @("$KongUrl/api/data?apikey=demo-api-key-12345") "200" "Item A" `
    "key-auth accepts the key in the query string by default"

Test-Scenario $GROUP_B "B11" "Empty API key is rejected (401)" `
    @("-H", "apikey;", "$KongUrl/api/data") "401" "" ""

Test-Scenario $GROUP_B "B12" "Second registered consumer key also works" `
    @("-H", "apikey: test-api-key-67890", "$KongUrl/api/data") "200" "Item A" `
    "Consumer test-user"

Test-Scenario $GROUP_B "B13" "Key-auth route is unaffected by x-environment" `
    @("-H", "apikey: demo-api-key-12345", "-H", "x-environment: NONSENSE", "$KongUrl/api/data") "200" "Item A" `
    "Plugins are independent per route"

Test-Scenario $GROUP_B "B14" "Unrouted path returns 404 from Kong" `
    @("$KongUrl/nothing-here") "404" "" ""

Test-Scenario $GROUP_B "B15" "Wrong HTTP method on a GET-only route returns 404" `
    @("-X", "POST", "$KongUrl/api/hello") "404" "" `
    "Routes are constrained by method in kong.yml"

Test-Scenario $GROUP_B "B16" "Backend returns a JSON 404 for an unknown path" `
    @("$BackendUrl/does-not-exist") "404" "Not Found" ""

Test-Scenario $GROUP_B "B17" "Malformed JSON body returns a JSON 400" `
    @("-X", "POST", "-H", "Content-Type: application/json", "--data", '{"broken":', "$BackendUrl/api/ping") "400" "Malformed JSON body" `
    "Express default HTML error page is never exposed"

$bigFile = Join-Path $env:TEMP "kong-poc-big.json"
('{"a":"' + ('x' * 20000) + '"}') | Set-Content -Path $bigFile -NoNewline -Encoding ascii
Test-Scenario $GROUP_B "B18" "Oversized request body returns a JSON 413" `
    @("-X", "POST", "-H", "Content-Type: application/json", "--data", "@$bigFile", "$BackendUrl/api/ping") "413" "Payload too large" `
    "Body limit is 10 kB, which also bounds per-request memory"
Remove-Item $bigFile -Force -ErrorAction SilentlyContinue

if ($SkipRateLimit) {
    Add-Result $GROUP_B "B19" "Rate limit headers are returned to the client" "(skipped)" "RateLimit-* present" "" "" "SKIP" "-SkipRateLimit was passed"
}
else {
    $hdrCmd = "curl -i -H `"x-environment: DEV`" $KongUrl/api/hello    # inspect RateLimit-* headers"
    $hdrs = & curl.exe -s -D - -o NUL -H "x-environment: DEV" "$KongUrl/api/hello" 2>$null
    $matched = (($hdrs | Select-String -Pattern "RateLimit-Limit|RateLimit-Remaining") | ForEach-Object { $_.Line.Trim() }) -join "`n"
    $status = if ($matched) { "PASS" } else { "FAIL" }
    Add-Result $GROUP_B "B19" "Rate limit headers are returned to the client" $hdrCmd "RateLimit-* present" "200" $matched $status `
        "Lets clients back off before they are throttled"
}

# Resilience scenarios need the docker CLI.
if ($SkipResilience) {
    Add-Result $GROUP_B "B20" "Kong returns 502 when the backend is down" "(skipped)" "502 or 503" "" "" "SKIP" "-SkipResilience was passed"
    Add-Result $GROUP_B "B21" "Kong stays healthy while the backend is down" "(skipped)" "200" "" "" "SKIP" "-SkipResilience was passed"
    Add-Result $GROUP_B "B22" "Traffic recovers after the backend restarts" "(skipped)" "200" "" "" "SKIP" "-SkipResilience was passed"
}
else {
    docker stop kong-backend *> $null

    $down = Invoke-Curl @("$KongUrl/api/ping")
    $status = if ($down.Code -eq "502" -or $down.Code -eq "503") { "PASS" } else { "FAIL" }
    Add-Result $GROUP_B "B20" "Kong returns 502 when the backend is down" `
        "docker stop kong-backend; curl -i $KongUrl/api/ping" "502 or 503" $down.Code $down.Body $status `
        "Upstream failure is contained and no stack trace is leaked"

    $admin = Invoke-Curl @("$AdminUrl/status")
    $status = if ($admin.Code -eq "200") { "PASS" } else { "FAIL" }
    Add-Result $GROUP_B "B21" "Kong stays healthy while the backend is down" `
        "curl -i $AdminUrl/status" "200" $admin.Code "" $status `
        "The gateway does not fail together with its upstream"

    docker start kong-backend *> $null
    $recovered = $false
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 1
        if ((Invoke-Curl @("$KongUrl/api/ping")).Code -eq "200") { $recovered = $true; break }
    }
    $status = if ($recovered) { "PASS" } else { "FAIL" }
    $actual = if ($recovered) { "200" } else { "timeout" }
    Add-Result $GROUP_B "B22" "Traffic recovers after the backend restarts" `
        "docker start kong-backend; curl -i $KongUrl/api/ping" "200" $actual "" $status `
        "No manual gateway intervention is needed"
}

# ===========================================================================
# Deferred to the end: this exhausts the /api/data quota, so running it earlier
# would make the other /api/data scenarios fail with 429. It belongs to Part A.
# ===========================================================================
Write-GroupHeader "PART A (continued) - rate limiting"

if ($SkipRateLimit) {
    Add-Result $GROUP_A "A11" "Rate limiting throttles a burst with HTTP 429" `
        "(skipped)" "some 429" "" "" "SKIP" "-SkipRateLimit was passed"
}
else {
    $burstCmd = "1..40 | ForEach-Object { curl -H `"apikey: demo-api-key-12345`" $KongUrl/api/data }"
    $codes = @()
    for ($i = 1; $i -le 40; $i++) {
        $codes += (& curl.exe -s -o NUL -w "%{http_code}" -H "apikey: demo-api-key-12345" "$KongUrl/api/data" 2>$null)
    }
    $served = @($codes | Where-Object { $_ -eq "200" }).Count
    $throttled = @($codes | Where-Object { $_ -eq "429" }).Count
    $summary = "$served responses were 200, $throttled were 429 (route limit is 30 per minute)"
    $status = if ($throttled -gt 0) { "PASS" } else { "FAIL" }
    Add-Result $GROUP_A "A11" "Rate limiting throttles a burst with HTTP 429" `
        $burstCmd "some 429" "$throttled x 429" $summary $status `
        "Requirement 3: rate-limiting plugin on /api/data"
}

# ===========================================================================
# Summary
# ===========================================================================

$passed = @($script:Results | Where-Object { $_.Status -eq "PASS" }).Count
$failed = @($script:Results | Where-Object { $_.Status -eq "FAIL" }).Count
$skipped = @($script:Results | Where-Object { $_.Status -eq "SKIP" }).Count

$aRows = @($script:Results | Where-Object { $_.Group -eq $GROUP_A })
$bRows = @($script:Results | Where-Object { $_.Group -eq $GROUP_B })
$aPass = @($aRows | Where-Object { $_.Status -eq "PASS" }).Count
$bPass = @($bRows | Where-Object { $_.Status -eq "PASS" }).Count

Write-Host ""
Write-Host ("=" * 78) -ForegroundColor White
Write-Host "  SUMMARY" -ForegroundColor White
Write-Host ("=" * 78) -ForegroundColor White
Write-Host ("  Part A  {0,-38} {1}/{2} passed" -f $GROUP_A, $aPass, $aRows.Count)
Write-Host ("  Part B  {0,-38} {1}/{2} passed" -f $GROUP_B, $bPass, $bRows.Count)
Write-Host ""
Write-Host ("  Passed {0}   Failed {1}   Skipped {2}" -f $passed, $failed, $skipped)

if ($failed -gt 0) {
    Write-Host ""
    Write-Host "  Failed scenarios:" -ForegroundColor Red
    $script:Results | Where-Object { $_.Status -eq "FAIL" } | ForEach-Object {
        Write-Host ("    [{0}] {1}" -f $_.Id, $_.Name) -ForegroundColor Red
    }
}

# ---------------------------------------------------------------------------
# HTML report
# ---------------------------------------------------------------------------

function ConvertTo-HtmlText($s) {
    if ($null -eq $s) { return "" }
    return ([string]$s -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;')
}

function New-ScenarioHtml($rows) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($r in $rows) {
        $cls = $r.Status.ToLower()
        [void]$sb.Append("<article class='card $cls'>")
        [void]$sb.Append("<header><span class='id'>$(ConvertTo-HtmlText $r.Id)</span><h3>$(ConvertTo-HtmlText $r.Name)</h3><span class='badge $cls'>$($r.Status)</span></header>")
        if ($r.Note) { [void]$sb.Append("<p class='note'>$(ConvertTo-HtmlText $r.Note)</p>") }
        [void]$sb.Append("<div class='label'>Command</div><pre class='cmd'>$(ConvertTo-HtmlText $r.Command)</pre>")
        [void]$sb.Append("<div class='meta'><span>Expected: <code>$(ConvertTo-HtmlText $r.Expected)</code></span><span>Actual: <code>$(ConvertTo-HtmlText $r.Actual)</code></span></div>")
        if ($r.Body) { [void]$sb.Append("<div class='label'>Response</div><pre class='out'>$(ConvertTo-HtmlText $r.Body)</pre>") }
        [void]$sb.Append("</article>")
    }
    return $sb.ToString()
}

if (-not $NoReport) {
    $overall = if ($failed -eq 0) { "ALL PASSED" } else { "$failed FAILED" }
    $overallCls = if ($failed -eq 0) { "pass" } else { "fail" }
    $duration = [int]((Get-Date) - $script:StartedAt).TotalSeconds
    $generated = $script:StartedAt.ToString('yyyy-MM-dd HH:mm:ss')
    $aHtml = New-ScenarioHtml $aRows
    $bHtml = New-ScenarioHtml $bRows

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Kong API Gateway - Verification Report</title>
<style>
:root { --bg:#0f1419; --panel:#182029; --line:#2a3542; --text:#dbe4ee; --muted:#8b9bb0;
        --pass:#3fb950; --fail:#f85149; --skip:#d29922; --accent:#58a6ff; }
* { box-sizing:border-box; }
body { margin:0; background:var(--bg); color:var(--text);
       font-family:'Segoe UI',system-ui,sans-serif; line-height:1.5; }
.wrap { max-width:1100px; margin:0 auto; padding:32px 24px 64px; }
h1 { font-size:26px; margin:0 0 4px; }
.sub { color:var(--muted); font-size:14px; margin-bottom:24px; }
.summary { display:grid; grid-template-columns:repeat(auto-fit,minmax(150px,1fr));
           gap:12px; margin-bottom:32px; }
.stat { background:var(--panel); border:1px solid var(--line); border-radius:8px; padding:16px; }
.stat .n { font-size:26px; font-weight:600; }
.stat .l { color:var(--muted); font-size:12px; text-transform:uppercase; letter-spacing:.5px; }
.stat.pass .n { color:var(--pass); } .stat.fail .n { color:var(--fail); }
.stat.skip .n { color:var(--skip); }
h2 { font-size:19px; margin:34px 0 6px; padding-bottom:8px; border-bottom:2px solid var(--line); }
h2 .count { float:right; font-size:13px; color:var(--muted); font-weight:400; }
.groupdesc { color:var(--muted); font-size:13px; margin:0 0 16px; }
.card { background:var(--panel); border:1px solid var(--line); border-left-width:4px;
        border-radius:8px; padding:14px 16px; margin-bottom:12px; }
.card.pass { border-left-color:var(--pass); }
.card.fail { border-left-color:var(--fail); }
.card.skip { border-left-color:var(--skip); }
.card header { display:flex; align-items:center; gap:10px; }
.card h3 { font-size:15px; margin:0; font-weight:600; flex:1; }
.id { background:#243040; color:var(--accent); font:600 12px/1 ui-monospace,monospace;
      padding:5px 8px; border-radius:4px; }
.badge { font:600 11px/1 sans-serif; padding:5px 9px; border-radius:4px; letter-spacing:.5px; }
.badge.pass { background:rgba(63,185,80,.15); color:var(--pass); }
.badge.fail { background:rgba(248,81,73,.15); color:var(--fail); }
.badge.skip { background:rgba(210,153,34,.15); color:var(--skip); }
.note { color:var(--muted); font-size:13px; margin:8px 0 0; }
.label { color:var(--muted); font-size:11px; text-transform:uppercase;
         letter-spacing:.5px; margin:12px 0 4px; }
pre { margin:0; padding:10px 12px; border-radius:6px; font:13px/1.5 ui-monospace,Consolas,monospace;
      white-space:pre-wrap; word-break:break-all; }
pre.cmd { background:#0b1017; color:#79c0ff; border:1px solid var(--line); }
pre.out { background:#0b1017; color:#a5d6a7; border:1px solid var(--line); max-height:220px; overflow:auto; }
.meta { display:flex; gap:18px; margin-top:10px; font-size:13px; color:var(--muted); flex-wrap:wrap; }
code { background:#243040; padding:2px 6px; border-radius:4px; font:12px ui-monospace,monospace; color:var(--text); }
footer { margin-top:40px; color:var(--muted); font-size:12px;
         border-top:1px solid var(--line); padding-top:16px; }
</style>
</head>
<body><div class="wrap">
<h1>Kong API Gateway &ndash; Verification Report</h1>
<p class="sub">
  Generated $generated &middot; completed in ${duration}s<br>
  Kong proxy <code>$KongUrl</code> &middot; admin <code>$AdminUrl</code> &middot; backend <code>$BackendUrl</code>
</p>

<div class="summary">
  <div class="stat $overallCls"><div class="n">$overall</div><div class="l">Result</div></div>
  <div class="stat pass"><div class="n">$passed</div><div class="l">Passed</div></div>
  <div class="stat fail"><div class="n">$failed</div><div class="l">Failed</div></div>
  <div class="stat skip"><div class="n">$skipped</div><div class="l">Skipped</div></div>
  <div class="stat"><div class="n">$aPass/$($aRows.Count)</div><div class="l">Part A</div></div>
  <div class="stat"><div class="n">$bPass/$($bRows.Count)</div><div class="l">Part B</div></div>
</div>

<h2>Part A &ndash; $GROUP_A <span class="count">$aPass / $($aRows.Count) passed</span></h2>
<p class="groupdesc">Scenarios explicitly required by the assignment brief.</p>
$aHtml

<h2>Part B &ndash; $GROUP_B <span class="count">$bPass / $($bRows.Count) passed</span></h2>
<p class="groupdesc">Additional cases covered beyond the brief: input handling, plugin scoping, error response shape, and upstream failure.</p>
$bHtml

<footer>Produced by test.ps1 in the kong-poc project.</footer>
</div></body></html>
"@

    $html | Set-Content -Path $ReportPath -Encoding UTF8
    $full = (Resolve-Path $ReportPath).Path
    $uri = ([System.Uri]$full).AbsoluteUri

    Write-Host ""
    Write-Host "  HTML report" -ForegroundColor Cyan
    Write-Host "    file  $full"
    Write-Host "    link  $uri" -ForegroundColor Blue
    if ($Open) {
        Start-Process $full
    }
    else {
        Write-Host "    (ctrl+click the link above, or re-run with -Open to launch it automatically)" -ForegroundColor DarkGray
    }
}

Write-Host ""
if ($failed -gt 0) { exit 1 }
exit 0
