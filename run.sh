#!/usr/bin/env bash
# One command: build, start everything, wait for the suite, then open the report.
#
#   ./run.sh

REPORT_PORT="${REPORT_PORT:-8090}"

echo "Building and starting the stack..."
docker-compose up -d --build || { echo "docker-compose failed."; exit 1; }

echo ""
echo "Waiting for the test suite to finish..."
EXIT_CODE=$(docker wait kong-tests)

echo ""
docker logs kong-tests 2>&1

URL="http://localhost:${REPORT_PORT}"
echo ""
echo "  Report: $URL"

if [ -z "$NO_OPEN" ]; then
  if command -v xdg-open > /dev/null 2>&1; then xdg-open "$URL" > /dev/null 2>&1 &
  elif command -v open > /dev/null 2>&1; then open "$URL" > /dev/null 2>&1 &
  fi
fi

echo ""
echo "The gateway is still running. Stop everything with: docker-compose down"

[ "$EXIT_CODE" != "0" ] && exit 1
exit 0
