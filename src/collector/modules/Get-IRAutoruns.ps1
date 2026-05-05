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

function ConvertTo-IRIsoDateTimeUtc {
    param(
        [AllowNull()]
        [datetime]$Value
    )

    if ($null -eq $Value) {
        return $null
    }

    return $Value.ToUniversalTime().ToString("o")
}

function Get-IRAutoruns {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputDir
    )

    $moduleName = "Autoruns"
    $moduleOutputDir = Join-Path $OutputDir "Autoruns"
    $outputFiles = @(
        (Join-Path $moduleOutputDir "registry_autoruns.json"),
        (Join-Path $moduleOutputDir "registry_autoruns.csv"),
        (Join-Path $moduleOutputDir "startup_folder_inventory.json"),
        (Join-Path $moduleOutputDir "startup_folder_inventory.csv")
    )

    $errors = New-Object System.Collections.Generic.List[string]
    $registryEntries = @()
    $startupEntries = @()

    $registryLocations = @(
        @{ Path = "Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run"; DisplayPath = "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"; Hive = "HKCU"; UserContext = "CurrentUser" },
        @{ Path = "Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\RunOnce"; DisplayPath = "HKCU\Software\Microsoft\Windows\CurrentVersion\RunOnce"; Hive = "HKCU"; UserContext = "CurrentUser" },
        @{ Path = "Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run"; DisplayPath = "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run"; Hive = "HKCU"; UserContext = "CurrentUser" },
        @{ Path = "Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Run"; DisplayPath = "HKLM\Software\Microsoft\Windows\CurrentVersion\Run"; Hive = "HKLM"; UserContext = "LocalMachine" },
        @{ Path = "Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\RunOnce"; DisplayPath = "HKLM\Software\Microsoft\Windows\CurrentVersion\RunOnce"; Hive = "HKLM"; UserContext = "LocalMachine" },
        @{ Path = "Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run"; DisplayPath = "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run"; Hive = "HKLM"; UserContext = "LocalMachine" },
        @{ Path = "Registry::HKEY_LOCAL_MACHINE\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Run"; DisplayPath = "HKLM\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Run"; Hive = "HKLM"; UserContext = "LocalMachine" },
        @{ Path = "Registry::HKEY_LOCAL_MACHINE\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\RunOnce"; DisplayPath = "HKLM\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\RunOnce"; Hive = "HKLM"; UserContext = "LocalMachine" }
    )

    $startupFolders = @(
        @{ Path = (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup") },
        @{ Path = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup" }
    )

    try {
        if (-not (Test-Path -LiteralPath $moduleOutputDir)) {
            New-Item -ItemType Directory -Path $moduleOutputDir -Force -ErrorAction Stop | Out-Null
        }

        foreach ($location in $registryLocations) {
            try {
                if (-not (Test-Path -LiteralPath $location.Path)) {
                    continue
                }

                $itemProperty = Get-ItemProperty -LiteralPath $location.Path -ErrorAction Stop
                $key = Get-Item -LiteralPath $location.Path -ErrorAction Stop

                $valueProperties = @(
                    $itemProperty.PSObject.Properties |
                        Where-Object { $_.MemberType -eq "NoteProperty" }
                )

                foreach ($property in $valueProperties) {
                    try {
                        $valueKind = $key.GetValueKind($property.Name)
                    }
                    catch {
                        $valueKind = $null
                    }

                    $registryEntries += [PSCustomObject]@{
                        Location    = $location.DisplayPath
                        Name        = ConvertTo-IRNullIfEmpty -Value $property.Name
                        Value       = ConvertTo-IRNullIfEmpty -Value ([string]$property.Value)
                        ValueType   = ConvertTo-IRNullIfEmpty -Value ([string]$valueKind)
                        Hive        = $location.Hive
                        UserContext = $location.UserContext
                    }
                }
            }
            catch {
                $errors.Add("Failed to read registry key $($location.DisplayPath): $($_.Exception.Message)")
            }
        }

        foreach ($folder in $startupFolders) {
            try {
                if (-not (Test-Path -LiteralPath $folder.Path)) {
                    continue
                }

                $files = @(Get-ChildItem -LiteralPath $folder.Path -File -ErrorAction Stop)
                foreach ($file in $files) {
                    $startupEntries += [PSCustomObject]@{
                        FileName         = $file.Name
                        FullPath         = $file.FullName
                        SizeBytes        = $file.Length
                        CreationTimeUtc  = ConvertTo-IRIsoDateTimeUtc -Value $file.CreationTimeUtc
                        LastWriteTimeUtc = ConvertTo-IRIsoDateTimeUtc -Value $file.LastWriteTimeUtc
                    }
                }
            }
            catch {
                $errors.Add("Failed to read startup folder $($folder.Path): $($_.Exception.Message)")
            }
        }

        $registryEntries = @($registryEntries | Sort-Object Location, Name)
        $startupEntries = @($startupEntries | Sort-Object FullPath)

        $registryEntries |
            ConvertTo-Json -Depth 4 |
            Set-Content -LiteralPath $outputFiles[0] -Encoding UTF8

        $registryEntries |
            Export-Csv -LiteralPath $outputFiles[1] -NoTypeInformation -Encoding UTF8

        $startupEntries |
            ConvertTo-Json -Depth 4 |
            Set-Content -LiteralPath $outputFiles[2] -Encoding UTF8

        $startupEntries |
            Export-Csv -LiteralPath $outputFiles[3] -NoTypeInformation -Encoding UTF8

        Write-Host "[IR-Kit] Collected autoruns"

        [PSCustomObject]@{
            ModuleName         = $moduleName
            Success            = $true
            OutputDirectory    = $moduleOutputDir
            OutputFiles        = $outputFiles
            RegistryEntryCount = $registryEntries.Count
            StartupFileCount   = $startupEntries.Count
            Error              = if ($errors.Count -gt 0) { $errors -join "; " } else { $null }
            Errors             = @($errors)
        }
    }
    catch {
        $message = $_.Exception.Message
        Write-Error "[IR-Kit] $moduleName failed: $message"

        [PSCustomObject]@{
            ModuleName         = $moduleName
            Success            = $false
            OutputDirectory    = $moduleOutputDir
            OutputFiles        = $outputFiles
            RegistryEntryCount = 0
            StartupFileCount   = 0
            Error              = $message
            Errors             = if ($errors.Count -gt 0) { @($errors) } else { @($message) }
        }
    }
}
