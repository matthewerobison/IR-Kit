function Get-IRProcessOwner {
    param(
        [Parameter(Mandatory = $true)]
        [Microsoft.Management.Infrastructure.CimInstance]$Process
    )

    try {
        $owner = Invoke-CimMethod -InputObject $Process -MethodName GetOwner -ErrorAction Stop

        if ($owner.ReturnValue -eq 0 -and -not [string]::IsNullOrWhiteSpace($owner.User)) {
            if ([string]::IsNullOrWhiteSpace($owner.Domain)) {
                return $owner.User
            }

            return "$($owner.Domain)\$($owner.User)"
        }

        if ($owner.ReturnValue -eq 2 -or $owner.ReturnValue -eq 3) {
            return "AccessDenied"
        }
    }
    catch {
        if ($_.Exception.Message -match "access|denied|unauthorized|privilege") {
            return "AccessDenied"
        }

        return "Unknown"
    }

    return "Unknown"
}

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
        [datetime]$Value
    )

    if ($null -eq $Value) {
        return $null
    }

    return $Value.ToString("o")
}

function New-IRProcessTree {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Processes
    )

    $childrenByParent = @{}
    $processById = @{}

    foreach ($process in $Processes) {
        $processById[[int]$process.ProcessId] = $process
    }

    foreach ($process in $Processes) {
        $processId = [int]$process.ProcessId
        $parentId = [int]$process.ParentProcessId

        if ($parentId -eq $processId) {
            continue
        }

        if (-not $childrenByParent.ContainsKey($parentId)) {
            $childrenByParent[$parentId] = New-Object System.Collections.Generic.List[object]
        }

        $childrenByParent[$parentId].Add($process)
    }

    $roots = New-Object System.Collections.Generic.List[object]
    foreach ($process in $Processes) {
        $processId = [int]$process.ProcessId
        $parentId = [int]$process.ParentProcessId

        if ($parentId -eq 0 -or $parentId -eq $processId -or -not $processById.ContainsKey($parentId)) {
            $roots.Add($process)
        }
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $visited = @{}

    function Add-ProcessTreeNode {
        param(
            [Parameter(Mandatory = $true)]
            [object]$Node,

            [Parameter(Mandatory = $true)]
            [int]$Depth
        )

        $nodeId = [int]$Node.ProcessId
        if ($visited.ContainsKey($nodeId)) {
            return
        }

        $visited[$nodeId] = $true
        $indent = "  " * $Depth
        $lines.Add("$indent$($Node.ProcessId) $($Node.Name)")

        if (-not $childrenByParent.ContainsKey($nodeId)) {
            return
        }

        $children = $childrenByParent[$nodeId] | Sort-Object @{ Expression = { [int]$_.ProcessId } }
        foreach ($child in $children) {
            Add-ProcessTreeNode -Node $child -Depth ($Depth + 1)
        }
    }

    foreach ($root in ($roots | Sort-Object @{ Expression = { [int]$_.ProcessId } })) {
        Add-ProcessTreeNode -Node $root -Depth 0
    }

    # Include any process missed because of unusual parent relationships.
    foreach ($process in ($Processes | Sort-Object @{ Expression = { [int]$_.ProcessId } })) {
        if (-not $visited.ContainsKey([int]$process.ProcessId)) {
            Add-ProcessTreeNode -Node $process -Depth 0
        }
    }

    return $lines
}

function Get-IRProcesses {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputDir
    )

    $moduleName = "Get-IRProcesses"
    $outputFiles = @(
        (Join-Path $OutputDir "processes.json"),
        (Join-Path $OutputDir "processes.csv"),
        (Join-Path $OutputDir "process_tree.txt")
    )

    try {
        if (-not (Test-Path -LiteralPath $OutputDir)) {
            New-Item -ItemType Directory -Path $OutputDir -Force -ErrorAction Stop | Out-Null
        }

        try {
            $rawProcesses = @(Get-CimInstance Win32_Process -ErrorAction Stop)
        }
        catch {
            throw "Process enumeration failed: $($_.Exception.Message)"
        }

        $processLookup = @{}
        foreach ($process in $rawProcesses) {
            $processLookup[[int]$process.ProcessId] = $process
        }

        $processes = foreach ($process in $rawProcesses) {
            $parentProcessName = "Unknown"
            $parentProcessId = [int]$process.ParentProcessId

            if ($processLookup.ContainsKey($parentProcessId)) {
                $parentProcessName = $processLookup[$parentProcessId].Name
            }

            [PSCustomObject]@{
                ProcessId         = [int]$process.ProcessId
                Name              = $process.Name
                CommandLine       = ConvertTo-IRNullIfEmpty -Value $process.CommandLine
                ParentProcessId   = $parentProcessId
                ParentProcessName = $parentProcessName
                ExecutablePath    = ConvertTo-IRNullIfEmpty -Value $process.ExecutablePath
                CreationDate      = ConvertTo-IRIsoDateTime -Value $process.CreationDate
                Owner             = Get-IRProcessOwner -Process $process
            }
        }

        $processes = @($processes | Sort-Object ProcessId)

        $jsonPath = $outputFiles[0]
        $csvPath = $outputFiles[1]
        $treePath = $outputFiles[2]

        $processes |
            ConvertTo-Json -Depth 4 |
            Set-Content -LiteralPath $jsonPath -Encoding UTF8

        $processes |
            Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

        New-IRProcessTree -Processes $processes |
            Set-Content -LiteralPath $treePath -Encoding UTF8

        Write-Host "[IR-Kit] Collected processes"

        [PSCustomObject]@{
            ModuleName      = $moduleName
            Success         = $true
            OutputDirectory = $OutputDir
            OutputFiles     = $outputFiles
            ProcessCount    = $processes.Count
            Error           = $null
        }
    }
    catch {
        $message = $_.Exception.Message
        Write-Error "[IR-Kit] $moduleName failed: $message"

        [PSCustomObject]@{
            ModuleName      = $moduleName
            Success         = $false
            OutputDirectory = $OutputDir
            OutputFiles     = $outputFiles
            ProcessCount    = 0
            Error           = $message
        }
    }
}
