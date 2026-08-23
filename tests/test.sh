#!/usr/bin/env bash
# Run scenarios and write an HTML report.

KONG_URL="${KONG_URL:-http://localhost:8000}"
ADMIN_URL="${ADMIN_URL:-http://localhost:8001}"
BACKEND_URL="${BACKEND_URL:-http://localhost:5000}"
REPORT_PATH="${REPORT_PATH:-test-report.html}"

GROUP_A="Assignment Scenarios"
GROUP_B="Edge Cases (beyond the assignment)"

GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; CYAN=$'\033[0;36m'
YELLOW=$'\033[1;33m'; GREY=$'\033[0;90m'; WHITE=$'\033[1;37m'; NC=$'\033[0m'

R_GROUP=(); R_ID=(); R_NAME=(); R_CMD=(); R_EXP=(); R_ACT=(); R_BODY=(); R_STATUS=(); R_NOTE=()
STARTED_EPOCH=$(date +%s)
STARTED_AT=$(date '+%Y-%m-%d %H:%M:%S')

# Define test helpers.

fmt_cmd() {
  local out="curl -i" a
  for a in "$@"; do
    case "$a" in
      *[[:space:]\"]*) out="$out \"${a//\"/\\\"}\"" ;;
      *)               out="$out $a" ;;
    esac
  done
  printf '%s' "$out"
}

# Capture the response.
req() {
  local raw
  raw=$(curl -s -w $'\n%{http_code}' "$@" 2>/dev/null)
  REQ_CODE="${raw##*$'\n'}"
  REQ_BODY="${raw%$'\n'*}"
  [ "$REQ_BODY" = "$REQ_CODE" ] && REQ_BODY=""
}

add_result() {
  local group="$1" id="$2" name="$3" cmd="$4" expected="$5" actual="$6" body="$7" status="$8" note="$9"

  R_GROUP+=("$group"); R_ID+=("$id"); R_NAME+=("$name"); R_CMD+=("$cmd")
  R_EXP+=("$expected"); R_ACT+=("$actual"); R_BODY+=("$body"); R_STATUS+=("$status"); R_NOTE+=("$note")

  local color="$YELLOW"
  [ "$status" = "PASS" ] && color="$GREEN"
  [ "$status" = "FAIL" ] && color="$RED"

  printf '\n%s[%s] %s%s\n' "$WHITE" "$id" "$name" "$NC"
  printf '%s      $ %s%s\n' "$GREY" "$cmd" "$NC"
  [ -n "$actual" ] && printf '      -> HTTP %s   (expected %s)\n' "$actual" "$expected"
  if [ -n "$body" ]; then
    # Preserve the final output line.
    printf '%s\n' "$body" | head -n 4 | while IFS= read -r line; do
      printf '%s      %s%s\n' "$CYAN" "$line" "$NC"
    done
  fi
  [ -n "$note" ] && printf '%s      %s%s\n' "$GREY" "$note" "$NC"
  printf '%s      %s%s\n' "$color" "$status" "$NC"
}

# Run an HTTP scenario.
scenario() {
  local group="$1" id="$2" name="$3" expected="$4" contains="$5" note="$6"
  shift 6
  [ "$1" = "--" ] && shift

  local cmd; cmd=$(fmt_cmd "$@")
  req "$@"

  local status="PASS" detail="$note"
  if [ "$REQ_CODE" != "$expected" ]; then
    status="FAIL"
  elif [ -n "$contains" ] && [[ "$REQ_BODY" != *"$contains"* ]]; then
    status="FAIL"; detail="expected body to contain: $contains"
  fi

  add_result "$group" "$id" "$name" "$cmd" "$expected" "$REQ_CODE" "$REQ_BODY" "$status" "$detail"
}

group_header() {
  printf '\n%s%s\n  %s\n%s%s\n' "$CYAN" "==============================================================================" "$1" "==============================================================================" "$NC"
}

# Print the verification header.
printf '\n%sKong API Gateway - verification run%s\n' "$WHITE" "$NC"
echo "Kong proxy : $KONG_URL"
echo "Kong admin : $ADMIN_URL"
echo "Backend    : $BACKEND_URL"
echo "Started    : $STARTED_AT"

req "$BACKEND_URL/health"
if [ "$REQ_CODE" != "200" ]; then
  printf '\n%sBackend is not responding. Start the stack with "docker-compose up -d" first.%s\n' "$RED" "$NC"
  exit 1
fi
req "$ADMIN_URL/status"
if [ "$REQ_CODE" != "200" ]; then
  printf '\n%sKong is not responding. Start the stack with "docker-compose up -d" first.%s\n' "$RED" "$NC"
  exit 1
fi

group_header "PART A - $GROUP_A"

scenario "$GROUP_A" A1 "Sample app is deployed and reachable through Docker" \
  200 "ok" "Requirement 1: dockerized backend responds" \
  -- "$BACKEND_URL/health"

scenario "$GROUP_A" A2 "Kong service and route proxy traffic to the backend" \
  200 "hello from app" "Requirement 2: service and route configured in kong.yml" \
  -- "$KONG_URL/api/ping"

scenario "$GROUP_A" A3 "Key authentication accepts a registered consumer key" \
  200 "Item A" "Requirement 3: key-auth plugin, consumer demo-user" \
  -- -H "apikey: demo-api-key-12345" "$KONG_URL/api/data"

scenario "$GROUP_A" A4 "Key authentication rejects a request with no key" \
  401 "No API key found" "Requirement 3: key-auth plugin" \
  -- "$KONG_URL/api/data"

scenario "$GROUP_A" A5 "Key authentication rejects an unknown key" \
  401 "" "Requirement 3: key-auth plugin" \
  -- -H "apikey: not-a-real-key" "$KONG_URL/api/data"

scenario "$GROUP_A" A6 "Custom plugin allows x-environment: DEV" \
  200 "Hello" "Requirement 4: valid value passes through" \
  -- -H "x-environment: DEV" "$KONG_URL/api/hello"

scenario "$GROUP_A" A7 "Custom plugin allows x-environment: UAT" \
  200 "Hello" "Requirement 4: valid value passes through" \
  -- -H "x-environment: UAT" "$KONG_URL/api/hello"

scenario "$GROUP_A" A8 "Custom plugin allows x-environment: PROD" \
  200 "Hello" "Requirement 4: valid value passes through" \
  -- -H "x-environment: PROD" "$KONG_URL/api/hello"

scenario "$GROUP_A" A9 "Missing x-environment returns HTTP 400 with a JSON error" \
  400 "Missing x-environment header" "Requirement 4: missing header gives 400" \
  -- "$KONG_URL/api/hello"

scenario "$GROUP_A" A10 "Invalid x-environment returns HTTP 403 with a JSON error" \
  403 "Allowed values: DEV, UAT, PROD" "Requirement 4: invalid header gives 403" \
  -- -H "x-environment: STAGING" "$KONG_URL/api/hello"

printf '\n%s  (A11, the rate limiting burst, runs at the end because it uses up the route quota)%s\n' "$GREY" "$NC"

group_header "PART B - $GROUP_B"

scenario "$GROUP_B" B1 "Lowercase value is accepted (case-insensitive match)" \
  200 "Hello" "Plugin uppercases before comparing" \
  -- -H "x-environment: dev" "$KONG_URL/api/hello"

scenario "$GROUP_B" B2 "Mixed case value is accepted" \
  200 "Hello" "" \
  -- -H "x-environment: Uat" "$KONG_URL/api/hello"

scenario "$GROUP_B" B3 "Value padded with spaces is accepted" \
  200 "Hello" "Plugin trims the header value" \
  -- -H "x-environment:   PROD  " "$KONG_URL/api/hello"

scenario "$GROUP_B" B4 "Header present but empty is treated as missing (400)" \
  400 "Missing x-environment header" "An empty value carries no more meaning than an absent one" \
  -- -H "x-environment;" "$KONG_URL/api/hello"

scenario "$GROUP_B" B5 "Duplicate x-environment headers are rejected (400)" \
  400 "Duplicate x-environment header" "Ambiguous intent, so it is rejected rather than silently using the first value" \
  -- -H "x-environment: DEV" -H "x-environment: PROD" "$KONG_URL/api/hello"

scenario "$GROUP_B" B6 "Numeric value is rejected (403)" \
  403 "" "" \
  -- -H "x-environment: 12345" "$KONG_URL/api/hello"

scenario "$GROUP_B" B7 "Near miss DEVELOPMENT is rejected (403)" \
  403 "" "Match is exact, not a prefix match" \
  -- -H "x-environment: DEVELOPMENT" "$KONG_URL/api/hello"

scenario "$GROUP_B" B8 "A route without the plugin ignores a bad x-environment value" \
  200 "hello from app" "Confirms the plugin is scoped per route, not global" \
  -- -H "x-environment: NONSENSE" "$KONG_URL/api/ping"

scenario "$GROUP_B" B9 "Plugin errors are JSON, never an HTML error page" \
  403 '"error"' "Uses kong.response.exit() from the Kong PDK" \
  -- -H "x-environment: STAGING" "$KONG_URL/api/hello"

scenario "$GROUP_B" B10 "API key supplied as a query string is accepted" \
  200 "Item A" "key-auth accepts the key in the query string by default" \
  -- "$KONG_URL/api/data?apikey=demo-api-key-12345"

scenario "$GROUP_B" B11 "Empty API key is rejected (401)" \
  401 "" "" \
  -- -H "apikey;" "$KONG_URL/api/data"

scenario "$GROUP_B" B12 "Second registered consumer key also works" \
  200 "Item A" "Consumer test-user" \
  -- -H "apikey: test-api-key-67890" "$KONG_URL/api/data"

scenario "$GROUP_B" B13 "Key-auth route is unaffected by x-environment" \
  200 "Item A" "Plugins are independent per route" \
  -- -H "apikey: demo-api-key-12345" -H "x-environment: NONSENSE" "$KONG_URL/api/data"

scenario "$GROUP_B" B14 "Unrouted path returns 404 from Kong" \
  404 "" "" \
  -- "$KONG_URL/nothing-here"

scenario "$GROUP_B" B15 "Wrong HTTP method on a GET-only route returns 404" \
  404 "" "Routes are constrained by method in kong.yml" \
  -- -X POST "$KONG_URL/api/hello"

scenario "$GROUP_B" B16 "Backend returns a JSON 404 for an unknown path" \
  404 "Not Found" "" \
  -- "$BACKEND_URL/does-not-exist"

scenario "$GROUP_B" B17 "Malformed JSON body returns a JSON 400" \
  400 "Malformed JSON body" "Express default HTML error page is never exposed" \
  -- -X POST -H "Content-Type: application/json" --data '{"broken":' "$BACKEND_URL/api/ping"

BIG=$(mktemp)
printf '{"a":"%s"}' "$(head -c 20000 < /dev/zero | tr '\0' 'x')" > "$BIG"
scenario "$GROUP_B" B18 "Oversized request body returns a JSON 413" \
  413 "Payload too large" "Body limit is 10 kB, which also bounds per-request memory" \
  -- -X POST -H "Content-Type: application/json" --data "@$BIG" "$BACKEND_URL/api/ping"
rm -f "$BIG"

if [ -n "$SKIP_RATELIMIT" ]; then
  add_result "$GROUP_B" B19 "Rate limit headers are returned to the client" "(skipped)" "RateLimit-* present" "" "" "SKIP" "SKIP_RATELIMIT was set"
else
  HDR_CMD="curl -i -H \"x-environment: DEV\" $KONG_URL/api/hello    # inspect RateLimit-* headers"
  MATCHED=$(curl -s -D - -o /dev/null -H "x-environment: DEV" "$KONG_URL/api/hello" 2>/dev/null \
            | grep -iE "RateLimit-Limit|RateLimit-Remaining" | tr -d '\r')
  if [ -n "$MATCHED" ]; then ST="PASS"; else ST="FAIL"; fi
  add_result "$GROUP_B" B19 "Rate limit headers are returned to the client" "$HDR_CMD" "RateLimit-* present" "200" "$MATCHED" "$ST" "Lets clients back off before they are throttled"
fi

if [ -n "$SKIP_RESILIENCE" ] || ! command -v docker > /dev/null 2>&1; then
  add_result "$GROUP_B" B20 "Kong returns 502 when the backend is down"      "(skipped)" "502 or 503" "" "" "SKIP" "docker unavailable or SKIP_RESILIENCE set"
  add_result "$GROUP_B" B21 "Kong stays healthy while the backend is down"   "(skipped)" "200" "" "" "SKIP" "docker unavailable or SKIP_RESILIENCE set"
  add_result "$GROUP_B" B22 "Traffic recovers after the backend restarts"    "(skipped)" "200" "" "" "SKIP" "docker unavailable or SKIP_RESILIENCE set"
else
  docker stop kong-backend > /dev/null 2>&1

  req "$KONG_URL/api/ping"
  if [ "$REQ_CODE" = "502" ] || [ "$REQ_CODE" = "503" ]; then ST="PASS"; else ST="FAIL"; fi
  add_result "$GROUP_B" B20 "Kong returns 502 when the backend is down" \
    "docker stop kong-backend; curl -i $KONG_URL/api/ping" "502 or 503" "$REQ_CODE" "$REQ_BODY" "$ST" \
    "Upstream failure is contained and no stack trace is leaked"

  req "$ADMIN_URL/status"
  if [ "$REQ_CODE" = "200" ]; then ST="PASS"; else ST="FAIL"; fi
  add_result "$GROUP_B" B21 "Kong stays healthy while the backend is down" \
    "curl -i $ADMIN_URL/status" "200" "$REQ_CODE" "" "$ST" \
    "The gateway does not fail together with its upstream"

  docker start kong-backend > /dev/null 2>&1
  RECOVERED=0
  for _ in $(seq 1 30); do
    sleep 1
    req "$KONG_URL/api/ping"
    [ "$REQ_CODE" = "200" ] && { RECOVERED=1; break; }
  done
  if [ "$RECOVERED" = "1" ]; then ST="PASS"; ACT="200"; else ST="FAIL"; ACT="timeout"; fi
  add_result "$GROUP_B" B22 "Traffic recovers after the backend restarts" \
    "docker start kong-backend; curl -i $KONG_URL/api/ping" "200" "$ACT" "" "$ST" \
    "No manual gateway intervention is needed"
fi

# Run the rate-limit scenario last.
group_header "PART A (continued) - rate limiting"

if [ -n "$SKIP_RATELIMIT" ]; then
  add_result "$GROUP_A" A11 "Rate limiting throttles a burst with HTTP 429" "(skipped)" "some 429" "" "" "SKIP" "SKIP_RATELIMIT was set"
else
  SERVED=0; THROTTLED=0
  for _ in $(seq 1 40); do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "apikey: demo-api-key-12345" "$KONG_URL/api/data")
    [ "$CODE" = "200" ] && SERVED=$((SERVED + 1))
    [ "$CODE" = "429" ] && THROTTLED=$((THROTTLED + 1))
  done
  if [ "$THROTTLED" -gt 0 ]; then ST="PASS"; else ST="FAIL"; fi
  add_result "$GROUP_A" A11 "Rate limiting throttles a burst with HTTP 429" \
    "for i in \$(seq 1 40); do curl -H \"apikey: demo-api-key-12345\" $KONG_URL/api/data; done" \
    "some 429" "$THROTTLED x 429" \
    "$SERVED responses were 200, $THROTTLED were 429 (route limit is 30 per minute)" "$ST" \
    "Requirement 3: rate-limiting plugin on /api/data"
fi

# Print the test summary.

PASSED=0; FAILED=0; SKIPPED=0; A_PASS=0; A_TOTAL=0; B_PASS=0; B_TOTAL=0
for i in "${!R_ID[@]}"; do
  case "${R_STATUS[$i]}" in
    PASS) PASSED=$((PASSED + 1)) ;;
    FAIL) FAILED=$((FAILED + 1)) ;;
    SKIP) SKIPPED=$((SKIPPED + 1)) ;;
  esac
  if [ "${R_GROUP[$i]}" = "$GROUP_A" ]; then
    A_TOTAL=$((A_TOTAL + 1)); [ "${R_STATUS[$i]}" = "PASS" ] && A_PASS=$((A_PASS + 1))
  else
    B_TOTAL=$((B_TOTAL + 1)); [ "${R_STATUS[$i]}" = "PASS" ] && B_PASS=$((B_PASS + 1))
  fi
done

printf '\n%s==============================================================================\n' "$WHITE"
printf '  SUMMARY\n'
printf '==============================================================================%s\n' "$NC"
printf '  Part A  %-38s %s/%s passed\n' "$GROUP_A" "$A_PASS" "$A_TOTAL"
printf '  Part B  %-38s %s/%s passed\n' "$GROUP_B" "$B_PASS" "$B_TOTAL"
printf '\n  Passed %s   Failed %s   Skipped %s\n' "$PASSED" "$FAILED" "$SKIPPED"

if [ "$FAILED" -gt 0 ]; then
  printf '\n%s  Failed scenarios:%s\n' "$RED" "$NC"
  for i in "${!R_ID[@]}"; do
    [ "${R_STATUS[$i]}" = "FAIL" ] && printf '%s    [%s] %s%s\n' "$RED" "${R_ID[$i]}" "${R_NAME[$i]}" "$NC"
  done
fi

# Write the HTML report.

esc() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

emit_cards() {
  local want="$1" i cls
  for i in "${!R_ID[@]}"; do
    [ "${R_GROUP[$i]}" = "$want" ] || continue
    cls=$(printf '%s' "${R_STATUS[$i]}" | tr '[:upper:]' '[:lower:]')
    printf '<article class="card %s">' "$cls"
    printf '<header><span class="id">%s</span><h3>%s</h3><span class="badge %s">%s</span></header>' \
      "$(esc "${R_ID[$i]}")" "$(esc "${R_NAME[$i]}")" "$cls" "${R_STATUS[$i]}"
    [ -n "${R_NOTE[$i]}" ] && printf '<p class="note">%s</p>' "$(esc "${R_NOTE[$i]}")"
    printf '<div class="label">Command</div><pre class="cmd">%s</pre>' "$(esc "${R_CMD[$i]}")"
    printf '<div class="meta"><span>Expected: <code>%s</code></span><span>Actual: <code>%s</code></span></div>' \
      "$(esc "${R_EXP[$i]}")" "$(esc "${R_ACT[$i]}")"
    [ -n "${R_BODY[$i]}" ] && printf '<div class="label">Response</div><pre class="out">%s</pre>' "$(esc "${R_BODY[$i]}")"
    printf '</article>'
  done
}

if [ -z "$NO_REPORT" ]; then
  mkdir -p "$(dirname "$REPORT_PATH")"
  DURATION=$(( $(date +%s) - STARTED_EPOCH ))
  if [ "$FAILED" -eq 0 ]; then OVERALL="ALL PASSED"; OVERALL_CLS="pass"; else OVERALL="$FAILED FAILED"; OVERALL_CLS="fail"; fi

  {
    cat <<HTMLHEAD
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
  Generated $STARTED_AT &middot; completed in ${DURATION}s<br>
  Kong proxy <code>$KONG_URL</code> &middot; admin <code>$ADMIN_URL</code> &middot; backend <code>$BACKEND_URL</code>
</p>

<div class="summary">
  <div class="stat $OVERALL_CLS"><div class="n">$OVERALL</div><div class="l">Result</div></div>
  <div class="stat pass"><div class="n">$PASSED</div><div class="l">Passed</div></div>
  <div class="stat fail"><div class="n">$FAILED</div><div class="l">Failed</div></div>
  <div class="stat skip"><div class="n">$SKIPPED</div><div class="l">Skipped</div></div>
  <div class="stat"><div class="n">$A_PASS/$A_TOTAL</div><div class="l">Part A</div></div>
  <div class="stat"><div class="n">$B_PASS/$B_TOTAL</div><div class="l">Part B</div></div>
</div>

<h2>Part A &ndash; $GROUP_A <span class="count">$A_PASS / $A_TOTAL passed</span></h2>
<p class="groupdesc">Scenarios explicitly required by the assignment brief.</p>
HTMLHEAD

    emit_cards "$GROUP_A"

    cat <<HTMLMID

<h2>Part B &ndash; $GROUP_B <span class="count">$B_PASS / $B_TOTAL passed</span></h2>
<p class="groupdesc">Additional cases covered beyond the brief: input handling, plugin scoping, error response shape, and upstream failure.</p>
HTMLMID

    emit_cards "$GROUP_B"

    cat <<'HTMLTAIL'

<footer>Produced by test.sh in the kong-poc project.</footer>
</div></body></html>
HTMLTAIL
  } > "$REPORT_PATH"

  REPORT_DIR=$(cd "$(dirname "$REPORT_PATH")" && pwd)
  REPORT_FULL="$REPORT_DIR/$(basename "$REPORT_PATH")"
  # Encode spaces in the local report link.
  REPORT_URI="file://$(printf '%s' "$REPORT_FULL" | sed 's/ /%20/g')"

  printf '\n%s  HTML report%s\n' "$CYAN" "$NC"
  if [ -n "$REPORT_URL" ]; then
    # Print the hosted report link.
    printf '%s    open  %s%s\n' "$WHITE" "$REPORT_URL" "$NC"
  fi
  printf '    file  %s\n' "$REPORT_FULL"
  printf '%s    link  %s%s\n' "$CYAN" "$REPORT_URI" "$NC"

  if [ -n "$OPEN" ]; then
    if command -v xdg-open > /dev/null 2>&1; then xdg-open "$REPORT_FULL" > /dev/null 2>&1 &
    elif command -v open > /dev/null 2>&1; then open "$REPORT_FULL" > /dev/null 2>&1 &
    fi
  elif [ -z "$REPORT_URL" ]; then
    printf '%s    (ctrl+click the link above, or re-run with OPEN=1 to launch it automatically)%s\n' "$GREY" "$NC"
  fi
fi

echo ""
[ "$FAILED" -gt 0 ] && exit 1
exit 0
