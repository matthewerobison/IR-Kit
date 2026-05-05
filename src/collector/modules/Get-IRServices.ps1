function ConvertTo-IRNullIfEmpty {
    param(
        [AllowNull()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    return $Value
}

function Get-IRServices {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputDir
    )

    $moduleName = "Services"
    $moduleOutputDir = Join-Path $OutputDir "Services"
    $outputFiles = @(
        (Join-Path $moduleOutputDir "services.json"),
        (Join-Path $moduleOutputDir "services.csv")
    )

    try {
        if (-not (Test-Path -LiteralPath $moduleOutputDir)) {
            New-Item -ItemType Directory -Path $moduleOutputDir -Force -ErrorAction Stop | Out-Null
        }

        try {
            $rawServices = @(Get-CimInstance Win32_Service -ErrorAction Stop)
        }
        catch {
            throw "Service collection failed: $($_.Exception.Message)"
        }

        $services = foreach ($service in $rawServices) {
            [PSCustomObject]@{
                Name        = ConvertTo-IRNullIfEmpty -Value $service.Name
                DisplayName = ConvertTo-IRNullIfEmpty -Value $service.DisplayName
                State       = ConvertTo-IRNullIfEmpty -Value $service.State
                Status      = ConvertTo-IRNullIfEmpty -Value $service.Status
                StartMode   = ConvertTo-IRNullIfEmpty -Value $service.StartMode
                StartName   = ConvertTo-IRNullIfEmpty -Value $service.StartName
                PathName    = ConvertTo-IRNullIfEmpty -Value $service.PathName
                ProcessId   = $service.ProcessId
                ServiceType = ConvertTo-IRNullIfEmpty -Value $service.ServiceType
                Description = ConvertTo-IRNullIfEmpty -Value $service.Description
            }
        }

        $services = @($services | Sort-Object Name)

        $services |
            ConvertTo-Json -Depth 4 |
            Set-Content -LiteralPath $outputFiles[0] -Encoding UTF8

        $services |
            Export-Csv -LiteralPath $outputFiles[1] -NoTypeInformation -Encoding UTF8

        Write-Host "[IR-Kit] Collected services"

        [PSCustomObject]@{
            ModuleName      = $moduleName
            Success         = $true
            OutputDirectory = $moduleOutputDir
            OutputFiles     = $outputFiles
            ServiceCount    = $services.Count
            Error           = $null
        }
    }
    catch {
        $message = $_.Exception.Message
        Write-Error "[IR-Kit] $moduleName failed: $message"

        [PSCustomObject]@{
            ModuleName      = $moduleName
            Success         = $false
            OutputDirectory = $moduleOutputDir
            OutputFiles     = $outputFiles
            ServiceCount    = 0
            Error           = $message
        }
    }
}
