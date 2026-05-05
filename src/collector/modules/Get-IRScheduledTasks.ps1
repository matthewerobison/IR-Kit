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
        $dateTimeValue = [datetime]$Value
    }
    catch {
        return $null
    }

    if ($dateTimeValue -eq [datetime]::MinValue) {
        return $null
    }

    return $dateTimeValue.ToString("o")
}

function ConvertTo-IRScheduledTaskAction {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Action
    )

    return [PSCustomObject]@{
        Execute          = ConvertTo-IRNullIfEmpty -Value $Action.Execute
        Arguments        = ConvertTo-IRNullIfEmpty -Value $Action.Arguments
        WorkingDirectory = ConvertTo-IRNullIfEmpty -Value $Action.WorkingDirectory
    }
}

function ConvertTo-IRScheduledTaskTrigger {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Trigger
    )

    return [PSCustomObject]@{
        Type          = $Trigger.GetType().Name
        Enabled       = $Trigger.Enabled
        StartBoundary = ConvertTo-IRNullIfEmpty -Value $Trigger.StartBoundary
        EndBoundary   = ConvertTo-IRNullIfEmpty -Value $Trigger.EndBoundary
    }
}

function ConvertTo-IRCompactJson {
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return $null
    }

    return ($Value | ConvertTo-Json -Depth 6 -Compress)
}

function Get-IRScheduledTasks {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputDir
    )

    $moduleName = "ScheduledTasks"
    $moduleOutputDir = Join-Path $OutputDir "ScheduledTasks"
    $outputFiles = @(
        (Join-Path $moduleOutputDir "scheduled_tasks.json"),
        (Join-Path $moduleOutputDir "scheduled_tasks.csv")
    )

    $errors = New-Object System.Collections.Generic.List[string]

    try {
        if (-not (Test-Path -LiteralPath $moduleOutputDir)) {
            New-Item -ItemType Directory -Path $moduleOutputDir -Force -ErrorAction Stop | Out-Null
        }

        try {
            $rawTasks = @(Get-ScheduledTask -ErrorAction Stop)
        }
        catch {
            throw "Scheduled task collection failed: $($_.Exception.Message)"
        }

        $tasks = foreach ($task in $rawTasks) {
            $actions = @($task.Actions | Where-Object { $null -ne $_ } | ForEach-Object { ConvertTo-IRScheduledTaskAction -Action $_ })
            $triggers = @($task.Triggers | Where-Object { $null -ne $_ } | ForEach-Object { ConvertTo-IRScheduledTaskTrigger -Trigger $_ })

            $taskInfo = $null
            try {
                $taskInfo = Get-ScheduledTaskInfo -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction Stop
            }
            catch {
                $errors.Add("Task info lookup failed for $($task.TaskPath)$($task.TaskName): $($_.Exception.Message)")
            }

            [PSCustomObject]@{
                TaskName                = ConvertTo-IRNullIfEmpty -Value $task.TaskName
                TaskPath                = ConvertTo-IRNullIfEmpty -Value $task.TaskPath
                State                   = ConvertTo-IRNullIfEmpty -Value ([string]$task.State)
                Author                  = ConvertTo-IRNullIfEmpty -Value $task.Author
                Description             = ConvertTo-IRNullIfEmpty -Value $task.Description
                URI                     = ConvertTo-IRNullIfEmpty -Value $task.URI
                Date                    = ConvertTo-IRNullIfEmpty -Value $task.Date
                Source                  = ConvertTo-IRNullIfEmpty -Value $task.Source
                Actions                 = $actions
                Triggers                = $triggers
                PrincipalUserId         = ConvertTo-IRNullIfEmpty -Value $task.Principal.UserId
                PrincipalRunLevel       = ConvertTo-IRNullIfEmpty -Value ([string]$task.Principal.RunLevel)
                PrincipalLogonType      = ConvertTo-IRNullIfEmpty -Value ([string]$task.Principal.LogonType)
                SettingsEnabled         = $task.Settings.Enabled
                SettingsHidden          = $task.Settings.Hidden
                SettingsAllowDemandStart = $task.Settings.AllowDemandStart
                LastRunTime             = if ($null -ne $taskInfo) { ConvertTo-IRIsoDateTime -Value $taskInfo.LastRunTime } else { $null }
                LastTaskResult          = if ($null -ne $taskInfo) { $taskInfo.LastTaskResult } else { $null }
                NextRunTime             = if ($null -ne $taskInfo) { ConvertTo-IRIsoDateTime -Value $taskInfo.NextRunTime } else { $null }
                NumberOfMissedRuns      = if ($null -ne $taskInfo) { $taskInfo.NumberOfMissedRuns } else { $null }
                ActionsCsv              = ConvertTo-IRCompactJson -Value $actions
                TriggersCsv             = ConvertTo-IRCompactJson -Value $triggers
            }
        }

        $tasks = @($tasks | Sort-Object TaskPath, TaskName)

        $jsonTasks = @(
            $tasks | Select-Object TaskName, TaskPath, State, Author, Description, URI, Date, Source,
                Actions, Triggers, PrincipalUserId, PrincipalRunLevel, PrincipalLogonType,
                SettingsEnabled, SettingsHidden, SettingsAllowDemandStart,
                LastRunTime, LastTaskResult, NextRunTime, NumberOfMissedRuns
        )

        $csvTasks = @(
            $tasks | Select-Object TaskName, TaskPath, State, Author, Description, URI, Date, Source,
                @{ Name = "Actions"; Expression = { $_.ActionsCsv } },
                @{ Name = "Triggers"; Expression = { $_.TriggersCsv } },
                PrincipalUserId, PrincipalRunLevel, PrincipalLogonType,
                SettingsEnabled, SettingsHidden, SettingsAllowDemandStart,
                LastRunTime, LastTaskResult, NextRunTime, NumberOfMissedRuns
        )

        $jsonTasks |
            ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath $outputFiles[0] -Encoding UTF8

        $csvTasks |
            Export-Csv -LiteralPath $outputFiles[1] -NoTypeInformation -Encoding UTF8

        Write-Host "[IR-Kit] Collected scheduled tasks"

        [PSCustomObject]@{
            ModuleName      = $moduleName
            Success         = $true
            OutputDirectory = $moduleOutputDir
            OutputFiles     = $outputFiles
            TaskCount       = $jsonTasks.Count
            Error           = if ($errors.Count -gt 0) { $errors -join "; " } else { $null }
            Errors          = @($errors)
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
            TaskCount       = 0
            Error           = $message
            Errors          = @($message)
        }
    }
}
