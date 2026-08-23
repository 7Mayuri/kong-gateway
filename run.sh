#!/usr/bin/env bash
# One command for a reviewer: build, start Kong, run the Jenkins pipeline,
# then open the HTML report.
#
#   ./run.sh

REPORT_PORT="${REPORT_PORT:-8090}"

echo "Building and starting the stack..."
docker-compose up -d --build || { echo "docker-compose failed."; exit 1; }

echo ""
echo "Waiting for the Jenkins pipeline to finish (a few minutes on first run)..."
EXIT_CODE=$(docker wait kong-pipeline)

echo ""
docker logs kong-pipeline 2>&1

URL="http://localhost:${REPORT_PORT}"
echo ""
echo "  Test report: $URL"

if [ -z "$NO_OPEN" ]; then
  if command -v xdg-open > /dev/null 2>&1; then xdg-open "$URL" > /dev/null 2>&1 &
  elif command -v open > /dev/null 2>&1; then open "$URL" > /dev/null 2>&1 &
  fi
fi

echo ""
echo "Kong is still on http://localhost:8000, Jenkins on http://localhost:8080 (admin/admin)."
echo "Stop everything with: docker-compose down"

[ "$EXIT_CODE" != "0" ] && exit 1
exit 0
