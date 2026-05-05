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

function ConvertTo-IRIsoDateTime {
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return $null
    }

    try {
        return ([datetime]$Value).ToString("o")
    }
    catch {
        return $null
    }
}

function Get-IRSafeEventMessage {
    param(
        [Parameter(Mandatory = $true)]
        [object]$EventRecord
    )

    try {
        return ConvertTo-IRNullIfEmpty -Value $EventRecord.Message
    }
    catch {
        return $null
    }
}

function Get-IREventLogs {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputDir,

        [int]$MaxEvents = 5000
    )

    $moduleName = "EventLogs"
    $moduleOutputDir = Join-Path $OutputDir "EventLogs"
    $errors = New-Object System.Collections.Generic.List[string]
    $outputFiles = New-Object System.Collections.Generic.List[string]
    $logsAttempted = 4
    $logsExported = 0
    $eventsExported = 0

    $logDefinitions = @(
        @{ LogName = "Security"; BaseName = "security" },
        @{ LogName = "System"; BaseName = "system" },
        @{ LogName = "Application"; BaseName = "application" },
        @{ LogName = "Microsoft-Windows-Sysmon/Operational"; BaseName = "sysmon_operational" }
    )

    try {
        if (-not (Test-Path -LiteralPath $moduleOutputDir)) {
            New-Item -ItemType Directory -Path $moduleOutputDir -Force -ErrorAction Stop | Out-Null
        }

        foreach ($logDefinition in $logDefinitions) {
            $logName = $logDefinition.LogName
            $baseName = $logDefinition.BaseName
            $evtxPath = Join-Path $moduleOutputDir "$baseName.evtx"
            $jsonPath = Join-Path $moduleOutputDir "$baseName.json"
            $csvPath = Join-Path $moduleOutputDir "$baseName.csv"

            try {
                $null = Get-WinEvent -ListLog $logName -ErrorAction Stop
            }
            catch {
                $errors.Add("Log unavailable: $logName ($($_.Exception.Message))")
                continue
            }

            $logProducedOutput = $false

            try {
                & wevtutil epl "$logName" "$evtxPath"

                if (Test-Path -LiteralPath $evtxPath) {
                    $outputFiles.Add($evtxPath)
                    $logProducedOutput = $true
                }
                else {
                    $errors.Add("EVTX export did not create output for $logName")
                }
            }
            catch {
                    $errors.Add("EVTX export failed for ${logName}: $($_.Exception.Message)")
            }

            try {
                $rawEvents = @(Get-WinEvent -LogName $logName -MaxEvents $MaxEvents -ErrorAction Stop)
                $structuredEvents = foreach ($eventRecord in $rawEvents) {
                    [PSCustomObject]@{
                        LogName          = ConvertTo-IRNullIfEmpty -Value $eventRecord.LogName
                        ProviderName     = ConvertTo-IRNullIfEmpty -Value $eventRecord.ProviderName
                        Id               = $eventRecord.Id
                        LevelDisplayName = ConvertTo-IRNullIfEmpty -Value $eventRecord.LevelDisplayName
                        TimeCreated      = ConvertTo-IRIsoDateTime -Value $eventRecord.TimeCreated
                        MachineName      = ConvertTo-IRNullIfEmpty -Value $eventRecord.MachineName
                        UserId           = if ($null -ne $eventRecord.UserId) { [string]$eventRecord.UserId } else { $null }
                        ProcessId        = $eventRecord.ProcessId
                        ThreadId         = $eventRecord.ThreadId
                        RecordId         = $eventRecord.RecordId
                        Message          = Get-IRSafeEventMessage -EventRecord $eventRecord
                    }
                }

                $structuredEvents = @($structuredEvents)

                $structuredEvents |
                    ConvertTo-Json -Depth 4 |
                    Set-Content -LiteralPath $jsonPath -Encoding UTF8

                $structuredEvents |
                    Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

                $outputFiles.Add($jsonPath)
                $outputFiles.Add($csvPath)
                $logProducedOutput = $true
                $eventsExported += $structuredEvents.Count
            }
            catch {
                $errors.Add("Structured export failed for ${logName}: $($_.Exception.Message)")
            }

            if ($logProducedOutput) {
                $logsExported += 1
            }
        }

        if ($outputFiles.Count -eq 0) {
            throw "No event log output was created."
        }

        Write-Host "[IR-Kit] Collected event logs"

        [PSCustomObject]@{
            ModuleName    = $moduleName
            Success       = $true
            OutputDirectory = $moduleOutputDir
            OutputFiles   = @($outputFiles)
            LogsAttempted = $logsAttempted
            LogsExported  = $logsExported
            EventsExported = $eventsExported
            Error         = if ($errors.Count -gt 0) { $errors -join "; " } else { $null }
            Errors        = @($errors)
        }
    }
    catch {
        $message = $_.Exception.Message
        Write-Error "[IR-Kit] $moduleName failed: $message"

        [PSCustomObject]@{
            ModuleName     = $moduleName
            Success        = $false
            OutputDirectory = $moduleOutputDir
            OutputFiles    = @($outputFiles)
            LogsAttempted  = $logsAttempted
            LogsExported   = $logsExported
            EventsExported = $eventsExported
            Error          = $message
            Errors         = if ($errors.Count -gt 0) { @($errors) } else { @($message) }
        }
    }
}
