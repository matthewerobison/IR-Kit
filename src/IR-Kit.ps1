param(
    [string]$Mode = "Triage",
    [string]$Case = "default",
    [string]$OutputDir = ".\\output"
)

Write-Host "[IR-Kit] Starting..." -ForegroundColor Cyan

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$caseDir = Join-Path $OutputDir "${Case}_$timestamp"

New-Item -ItemType Directory -Path $caseDir -Force | Out-Null

Write-Host "[IR-Kit] Output Directory: $caseDir"

# Example module calls
. "$PSScriptRoot\\modules\\Get-IRProcesses.ps1"
. "$PSScriptRoot\\modules\\Get-IRNetConnections.ps1"

Get-IRProcesses -OutputDir $caseDir
Get-IRNetConnections -OutputDir $caseDir

Write-Host "[IR-Kit] Complete" -ForegroundColor Green
