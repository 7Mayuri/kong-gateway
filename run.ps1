# One command for a reviewer: build, start Kong, run the Jenkins pipeline,
# then open the HTML report.
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
Write-Host "Waiting for the Jenkins pipeline to finish (a few minutes on first run)..." -ForegroundColor Cyan
$exitCode = docker wait kong-pipeline

Write-Host ""
# 2>&1 | Out-Host keeps the container output in order with the lines below.
docker logs kong-pipeline 2>&1 | Out-Host

$url = "http://localhost:$ReportPort"
Write-Host ""
Write-Host "  Test report: $url" -ForegroundColor Cyan

if (-not $NoOpen) {
    Start-Process $url
}

Write-Host ""
Write-Host "Kong is still on http://localhost:8000, Jenkins on http://localhost:8080 (admin/admin)." -ForegroundColor DarkGray
Write-Host "Stop everything with: docker-compose down" -ForegroundColor DarkGray

if ([int]$exitCode -ne 0) { exit 1 }
exit 0
