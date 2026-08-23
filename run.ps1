# One command: build, start everything, wait for the suite, then open the report.
#
#   .\run.ps1

param(
    [int]$ReportPort = 8090,
    [switch]$NoOpen
)

Write-Host "Building and starting the stack..." -ForegroundColor Cyan
docker-compose up -d --build
if ($LASTEXITCODE -ne 0) {
    Write-Host "docker-compose failed." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Waiting for the test suite to finish..." -ForegroundColor Cyan
$exitCode = docker wait kong-tests

Write-Host ""
# 2>&1 | Out-Host keeps the container output in order with the lines below.
docker logs kong-tests 2>&1 | Out-Host

$url = "http://localhost:$ReportPort"
Write-Host ""
Write-Host "  Report: $url" -ForegroundColor Cyan

if (-not $NoOpen) {
    Start-Process $url
}

Write-Host ""
Write-Host "The gateway is still running. Stop everything with: docker-compose down" -ForegroundColor DarkGray

if ([int]$exitCode -ne 0) { exit 1 }
exit 0
