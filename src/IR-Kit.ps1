param(
    [string]$Mode = "Triage",
    [string]$Case = "default",
    [string]$OutputDir = ".\output",
    [string[]]$Modules = @("Processes", "Network")
)

# Backwards compatibility wrapper. Prefer src\collector\Invoke-IRKitCollector.ps1.
& (Join-Path $PSScriptRoot "collector\Invoke-IRKitCollector.ps1") `
    -CaseName $Case `
    -OutputDir $OutputDir `
    -Modules $Modules
