param(
    [string]$CaseName = "default",
    [string]$OutputDir = ".\output",
    [string[]]$Modules = @("Processes", "Network")
)

$moduleDefinitions = @{
    Processes = @{
        ScriptPath   = Join-Path $PSScriptRoot "modules\Get-IRProcesses.ps1"
        FunctionName = "Get-IRProcesses"
    }
    Network = @{
        ScriptPath   = Join-Path $PSScriptRoot "modules\Get-IRNetConnections.ps1"
        FunctionName = "Get-IRNetConnections"
    }
}

Write-Host "[IR-Kit] Collector starting..." -ForegroundColor Cyan

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$caseFolder = Join-Path $OutputDir "${CaseName}_$timestamp"
New-Item -ItemType Directory -Path $caseFolder -Force | Out-Null

Write-Host "[IR-Kit] Case Folder: $caseFolder"

$selectedModules = New-Object System.Collections.Generic.List[string]
foreach ($moduleName in $Modules) {
    if ($moduleDefinitions.ContainsKey($moduleName)) {
        $selectedModules.Add($moduleName)
    }
    else {
        Write-Warning "[IR-Kit] Unknown collector module requested: $moduleName"
    }
}

if ($selectedModules.Count -eq 0) {
    throw "No valid collector modules were selected."
}

foreach ($moduleName in $selectedModules) {
    . $moduleDefinitions[$moduleName].ScriptPath
}

$moduleResults = New-Object System.Collections.Generic.List[object]

foreach ($moduleName in $selectedModules) {
    $definition = $moduleDefinitions[$moduleName]
    Write-Host "[IR-Kit] Running collector module: $moduleName"

    try {
        $result = & $definition.FunctionName -OutputDir $caseFolder
    }
    catch {
        $result = [PSCustomObject]@{
            ModuleName      = $definition.FunctionName
            Success         = $false
            OutputDirectory = $caseFolder
            OutputFiles     = @()
            Error           = $_.Exception.Message
        }
    }

    $moduleResults.Add($result)

    if (-not $result.Success) {
        Write-Warning "[IR-Kit] $moduleName collection reported an error: $($result.Error)"
    }
}

$manifestPath = Join-Path $caseFolder "collection_manifest.json"
$selectedModulesArray = @($selectedModules.ToArray())
$moduleResultsArray = @($moduleResults.ToArray())
$failedModuleResults = @($moduleResultsArray | Where-Object { -not $_.Success })

$collectorResult = [PSCustomObject]@{
    CollectorName   = "IR-Kit Collector"
    Success         = ($failedModuleResults.Count -eq 0)
    CaseName        = $CaseName
    Timestamp       = (Get-Date).ToString("o")
    OutputDirectory = $caseFolder
    ModulesSelected = $selectedModulesArray
    ModuleResults   = $moduleResultsArray
}

$collectorResult |
    ConvertTo-Json -Depth 6 |
    Set-Content -LiteralPath $manifestPath -Encoding UTF8

Write-Host "[IR-Kit] Collector complete" -ForegroundColor Green

[PSCustomObject]@{
    CollectorName   = $collectorResult.CollectorName
    Success         = $collectorResult.Success
    CaseName        = $collectorResult.CaseName
    OutputDirectory = $collectorResult.OutputDirectory
    ManifestPath    = $manifestPath
    ModulesSelected = $collectorResult.ModulesSelected
    ModuleResults   = $collectorResult.ModuleResults
}
