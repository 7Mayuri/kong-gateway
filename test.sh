#!/usr/bin/env bash
# Runs every scenario and edge case against the running stack.
# Start the stack first (docker-compose up), then run this in a second terminal.
#
#   ./test.sh                     # against localhost
#   SKIP_RESILIENCE=1 ./test.sh   # skip the stop/start backend test
#   SKIP_RATELIMIT=1 ./test.sh    # skip the throttling burst

KONG_URL="${KONG_URL:-http://localhost:8000}"
ADMIN_URL="${ADMIN_URL:-http://localhost:8001}"
BACKEND_URL="${BACKEND_URL:-http://localhost:5000}"

GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; CYAN=$'\033[0;36m'; YELLOW=$'\033[1;33m'; NC=$'\033[0m'

PASSED=0
FAILED=0
FAILED_NAMES=""

section() { printf '\n%s=== %s ===%s\n' "$CYAN" "$1" "$NC"; }

pass() { printf '  %sPASS%s  %-52s %s\n' "$GREEN" "$NC" "$1" "$2"; PASSED=$((PASSED + 1)); }
fail() {
  printf '  %sFAIL%s  %-52s %s\n' "$RED" "$NC" "$1" "$2"
  FAILED=$((FAILED + 1))
  FAILED_NAMES="${FAILED_NAMES}\n  - $1"
}

# Sets REQ_CODE and REQ_BODY from a curl call.
req() {
  local raw
  raw=$(curl -s -w $'\n%{http_code}' "$@" 2>/dev/null)
  REQ_CODE="${raw##*$'\n'}"
  REQ_BODY="${raw%$'\n'*}"
  [ "$REQ_BODY" = "$REQ_CODE" ] && REQ_BODY=""
}

# check <name> <expected-code> [expected-substring] -- <curl args...>
check() {
  local name="$1" expected="$2" contains="$3"
  shift 3
  [ "$1" = "--" ] && shift

  req "$@"

  if [ "$REQ_CODE" != "$expected" ]; then
    fail "$name" "[$REQ_CODE, expected $expected]"
    return
  fi
  if [ -n "$contains" ] && [[ "$REQ_BODY" != *"$contains"* ]]; then
    fail "$name" "[body missing '$contains']"
    return
  fi
  pass "$name" "[$REQ_CODE]"
}

echo "Kong POC - full scenario and edge case suite"
echo "Kong: $KONG_URL   Admin: $ADMIN_URL   Backend: $BACKEND_URL"

# ---------------------------------------------------------------------------
section "1. Preflight"

check "backend is reachable" 200 "" -- "$BACKEND_URL/health"
if [ "$REQ_CODE" != "200" ]; then
  echo "${RED}Backend is not up. Run 'docker-compose up -d' first.${NC}"
  exit 1
fi

check "kong admin api is reachable" 200 "" -- "$ADMIN_URL/status"
if [ "$REQ_CODE" != "200" ]; then
  echo "${RED}Kong is not up. Run 'docker-compose up -d' first.${NC}"
  exit 1
fi

# ---------------------------------------------------------------------------
section "2. Backend direct (bypassing Kong)"

check "GET /health"                       200 "ok"             -- "$BACKEND_URL/health"
check "GET /api/ping"                     200 "hello from app" -- "$BACKEND_URL/api/ping"
check "GET /api/hello defaults to World"  200 "Hello, World!"  -- "$BACKEND_URL/api/hello"
check "GET /api/hello?name=Kong"          200 "Hello, Kong!"   -- "$BACKEND_URL/api/hello?name=Kong"
check "GET /api/data"                     200 "Item A"         -- "$BACKEND_URL/api/data"
check "unknown path returns JSON 404"     404 "Not Found"      -- "$BACKEND_URL/does-not-exist"

# ---------------------------------------------------------------------------
section "3. Backend error handling (edge cases)"

check "malformed JSON body returns JSON 400" 400 "Malformed JSON body" \
  -- -X POST -H "Content-Type: application/json" --data '{"broken":' "$BACKEND_URL/api/ping"

BIG=$(mktemp)
printf '{"a":"%s"}' "$(head -c 20000 < /dev/zero | tr '\0' 'x')" > "$BIG"
check "oversized body returns JSON 413" 413 "Payload too large" \
  -- -X POST -H "Content-Type: application/json" --data "@$BIG" "$BACKEND_URL/api/ping"
rm -f "$BIG"

# ---------------------------------------------------------------------------
section "4. Kong routing"

check "GET /health through Kong (no auth needed)" 200 "ok"             -- "$KONG_URL/health"
check "GET /api/ping through Kong"                200 "hello from app" -- "$KONG_URL/api/ping"
check "unrouted path returns 404"                 404 ""               -- "$KONG_URL/nothing-here"
check "POST to a GET-only route returns 404"      404 ""               -- -X POST "$KONG_URL/api/hello"

# ---------------------------------------------------------------------------
section "5. x-environment validation (custom plugin)"

check "DEV is accepted"                200 "Hello" -- -H "x-environment: DEV"  "$KONG_URL/api/hello"
check "UAT is accepted"                200 "Hello" -- -H "x-environment: UAT"  "$KONG_URL/api/hello"
check "PROD is accepted"               200 "Hello" -- -H "x-environment: PROD" "$KONG_URL/api/hello"
check "lowercase dev is accepted"      200 ""      -- -H "x-environment: dev"  "$KONG_URL/api/hello"
check "mixed case Uat is accepted"     200 ""      -- -H "x-environment: Uat"  "$KONG_URL/api/hello"
check "padded '  PROD  ' is accepted"  200 ""      -- -H "x-environment:   PROD  " "$KONG_URL/api/hello"

check "missing header returns 400"     400 "Missing x-environment header"      -- "$KONG_URL/api/hello"
check "unknown value returns 403"      403 "Allowed values: DEV, UAT, PROD"    -- -H "x-environment: STAGING" "$KONG_URL/api/hello"
check "empty header value returns 400" 400 "Missing x-environment header"      -- -H "x-environment;" "$KONG_URL/api/hello"
check "duplicate headers return 400"   400 "Duplicate x-environment header"    -- -H "x-environment: DEV" -H "x-environment: PROD" "$KONG_URL/api/hello"
check "numeric value returns 403"          403 "" -- -H "x-environment: 12345"       "$KONG_URL/api/hello"
check "near miss 'DEVELOPMENT' returns 403" 403 "" -- -H "x-environment: DEVELOPMENT" "$KONG_URL/api/hello"
check "route without the plugin ignores a bad value" 200 "" -- -H "x-environment: NONSENSE" "$KONG_URL/api/ping"
check "plugin errors are JSON, not HTML"   403 '"error"' -- -H "x-environment: STAGING" "$KONG_URL/api/hello"

# ---------------------------------------------------------------------------
section "6. Key authentication"

check "valid demo key is accepted"          200 "Item A" -- -H "apikey: demo-api-key-12345" "$KONG_URL/api/data"
check "valid test key is accepted"          200 "Item A" -- -H "apikey: test-api-key-67890" "$KONG_URL/api/data"
check "key passed as query string is accepted" 200 ""    -- "$KONG_URL/api/data?apikey=demo-api-key-12345"
check "missing key returns 401"             401 ""       -- "$KONG_URL/api/data"
check "invalid key returns 401"             401 ""       -- -H "apikey: not-a-real-key" "$KONG_URL/api/data"
check "empty key returns 401"               401 ""       -- -H "apikey;" "$KONG_URL/api/data"
check "key auth route ignores x-environment" 200 ""      -- -H "apikey: demo-api-key-12345" -H "x-environment: NONSENSE" "$KONG_URL/api/data"

# ---------------------------------------------------------------------------
section "7. Upstream failure handling"

if [ -n "$SKIP_RESILIENCE" ] || ! command -v docker > /dev/null 2>&1; then
  printf '  %sSKIP%s  (docker unavailable or SKIP_RESILIENCE set)\n' "$YELLOW" "$NC"
else
  echo "  stopping backend container..."
  docker stop kong-backend > /dev/null 2>&1

  req "$KONG_URL/api/ping"
  if [ "$REQ_CODE" = "502" ] || [ "$REQ_CODE" = "503" ]; then
    pass "Kong returns a gateway error when backend is down" "[$REQ_CODE]"
  else
    fail "Kong returns a gateway error when backend is down" "[$REQ_CODE, expected 502 or 503]"
  fi

  check "Kong itself stays up while backend is down" 200 "" -- "$ADMIN_URL/status"

  echo "  restarting backend container..."
  docker start kong-backend > /dev/null 2>&1

  RECOVERED=0
  for _ in $(seq 1 30); do
    sleep 1
    req "$KONG_URL/api/ping"
    [ "$REQ_CODE" = "200" ] && { RECOVERED=1; break; }
  done
  if [ "$RECOVERED" = "1" ]; then
    pass "traffic recovers after backend restarts" "[200]"
  else
    fail "traffic recovers after backend restarts" ""
  fi
fi

# ---------------------------------------------------------------------------
section "8. Rate limiting"

if [ -n "$SKIP_RATELIMIT" ]; then
  printf '  %sSKIP%s  (SKIP_RATELIMIT set)\n' "$YELLOW" "$NC"
else
  if curl -s -D - -o /dev/null -H "x-environment: DEV" "$KONG_URL/api/hello" | grep -qi "RateLimit-Limit"; then
    pass "rate limit headers are returned" ""
  else
    fail "rate limit headers are returned" ""
  fi

  # /api/data allows 30/min, so a burst of 40 must trip the limiter.
  echo "  sending 40 requests to /api/data (limit is 30/min)..."
  THROTTLED=0
  SERVED=0
  for _ in $(seq 1 40); do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "apikey: demo-api-key-12345" "$KONG_URL/api/data")
    [ "$CODE" = "429" ] && THROTTLED=$((THROTTLED + 1))
    [ "$CODE" = "200" ] && SERVED=$((SERVED + 1))
  done

  if [ "$THROTTLED" -gt 0 ]; then
    pass "burst is throttled with 429" "[$SERVED x 200, $THROTTLED x 429]"
  else
    fail "burst is throttled with 429" "[no 429 seen in 40 requests]"
  fi

  req -H "apikey: demo-api-key-12345" "$KONG_URL/api/data"
  if [ "$REQ_CODE" = "429" ]; then
    if [[ "$REQ_BODY" == *'"message"'* ]]; then
      pass "429 response body is JSON" "[429]"
    else
      fail "429 response body is JSON" "[body was: $REQ_BODY]"
    fi
  else
    printf '  %sNOTE%s  limiter window already reset, skipping 429 body check\n' "$YELLOW" "$NC"
  fi

  echo "  note: /api/data quota is now used up for this minute"
fi

# ---------------------------------------------------------------------------
echo ""
echo "=============================================="
echo "Passed: $PASSED   Failed: $FAILED"
if [ "$FAILED" -gt 0 ]; then
  printf '%sFailed checks:%s' "$RED" "$NC"
  printf "$FAILED_NAMES\n"
  exit 1
fi
printf '%sAll checks passed.%s\n' "$GREEN" "$NC"
exit 0
