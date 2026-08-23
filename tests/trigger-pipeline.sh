#!/usr/bin/env bash
# Waits for Jenkins, triggers the kong-poc-pipeline job, streams the result,
# and points at the generated report. Runs as the "pipeline" compose service.

JENKINS="${JENKINS_URL:-http://jenkins:8080}"
JOB="${JOB_NAME:-kong-poc-pipeline}"
USER_PASS="${JENKINS_AUTH:-admin:admin}"
REPORT_URL="${REPORT_URL:-http://localhost:8090}"

CYAN=$'\033[0;36m'; GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; WHITE=$'\033[1;37m'; NC=$'\033[0m'

say() { printf '%s%s%s\n' "$1" "$2" "$NC"; }

# ---------------------------------------------------------------------------
say "$CYAN" "Waiting for Jenkins to come up..."
for i in $(seq 1 120); do
  curl -sf -o /dev/null "$JENKINS/login" && break
  sleep 3
done
if ! curl -sf -o /dev/null "$JENKINS/login"; then
  say "$RED" "Jenkins did not become available in time."
  exit 1
fi

say "$CYAN" "Waiting for the $JOB job to be created..."
for i in $(seq 1 60); do
  curl -sf -o /dev/null -u "$USER_PASS" "$JENKINS/job/$JOB/api/json" && break
  sleep 3
done
if ! curl -sf -o /dev/null -u "$USER_PASS" "$JENKINS/job/$JOB/api/json"; then
  say "$RED" "The $JOB job was not created."
  exit 1
fi

# The build we are about to start.
BUILD=$(curl -s -u "$USER_PASS" "$JENKINS/job/$JOB/api/json" \
        | sed -n 's/.*"nextBuildNumber":\([0-9]*\).*/\1/p')
[ -z "$BUILD" ] && BUILD=1

# Crumb and session cookie must come from the same request for CSRF to pass.
curl -s -c /tmp/jenkins-cookies -u "$USER_PASS" "$JENKINS/crumbIssuer/api/json" -o /tmp/crumb.json
CRUMB=$(sed -n 's/.*"crumb":"\([^"]*\)".*/\1/p' /tmp/crumb.json)
FIELD=$(sed -n 's/.*"crumbRequestField":"\([^"]*\)".*/\1/p' /tmp/crumb.json)

say "$CYAN" "Triggering build #$BUILD..."
curl -s -o /dev/null -b /tmp/jenkins-cookies -u "$USER_PASS" \
  -X POST -H "$FIELD: $CRUMB" "$JENKINS/job/$JOB/build"

say "$CYAN" "Running the pipeline, this takes a couple of minutes..."
RESULT=""
for i in $(seq 1 300); do
  sleep 3
  INFO=$(curl -s -u "$USER_PASS" "$JENKINS/job/$JOB/$BUILD/api/json" 2>/dev/null)
  case "$INFO" in
    *'"building":false'*)
      RESULT=$(printf '%s' "$INFO" | sed -n 's/.*"result":"\([A-Z]*\)".*/\1/p')
      [ -n "$RESULT" ] && break
      ;;
  esac
done

echo ""
echo "=============================================================================="
echo "  JENKINS PIPELINE OUTPUT (build #$BUILD)"
echo "=============================================================================="
curl -s -u "$USER_PASS" "$JENKINS/job/$JOB/$BUILD/consoleText"

echo ""
echo ""
say "$WHITE" "###############################################################################"
say "$WHITE" "#"
if [ "$RESULT" = "SUCCESS" ]; then
  say "$GREEN" "#   ALL TESTS PASSED"
else
  say "$RED"   "#   PIPELINE RESULT: ${RESULT:-TIMED OUT}"
fi
say "$WHITE" "#"
say "$WHITE" "#   OPEN THE TEST REPORT:"
say "$CYAN"  "#   $REPORT_URL"
say "$WHITE" "#"
say "$WHITE" "###############################################################################"
echo ""

[ "$RESULT" = "SUCCESS" ] || exit 1
exit 0
