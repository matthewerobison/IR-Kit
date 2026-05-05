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

function Get-IRNetworkProcessLookup {
    $lookup = @{}

    try {
        $processes = @(Get-CimInstance Win32_Process -ErrorAction Stop)
    }
    catch {
        return $lookup
    }

    foreach ($process in $processes) {
        $lookup[[int]$process.ProcessId] = [PSCustomObject]@{
            ProcessName        = ConvertTo-IRNullIfEmpty -Value $process.Name
            ProcessPath        = ConvertTo-IRNullIfEmpty -Value $process.ExecutablePath
            ProcessCommandLine = ConvertTo-IRNullIfEmpty -Value $process.CommandLine
        }
    }

    return $lookup
}

function Get-IRNetworkProcessDetails {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$ProcessLookup,

        [AllowNull()]
        [int]$OwningProcess
    )

    if ($null -eq $OwningProcess -or -not $ProcessLookup.ContainsKey([int]$OwningProcess)) {
        return [PSCustomObject]@{
            ProcessName        = "Unknown"
            ProcessPath        = $null
            ProcessCommandLine = $null
        }
    }

    return $ProcessLookup[[int]$OwningProcess]
}

function New-IRNetworkTextOutput {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Connections
    )

    $lines = New-Object System.Collections.Generic.List[string]

    foreach ($connection in ($Connections | Sort-Object Protocol, OwningProcess, LocalAddress, LocalPort, RemoteAddress, RemotePort)) {
        $lines.Add("Protocol: $($connection.Protocol)")
        $lines.Add("LocalAddress: $($connection.LocalAddress)")
        $lines.Add("LocalPort: $($connection.LocalPort)")
        $lines.Add("RemoteAddress: $($connection.RemoteAddress)")
        $lines.Add("RemotePort: $($connection.RemotePort)")
        $lines.Add("State: $($connection.State)")
        $lines.Add("OwningProcess: $($connection.OwningProcess)")
        $lines.Add("ProcessName: $($connection.ProcessName)")
        $lines.Add("ProcessPath: $($connection.ProcessPath)")
        $lines.Add("ProcessCommandLine: $($connection.ProcessCommandLine)")
        $lines.Add("")
    }

    return $lines
}

function New-IREstablishedConnectionsTextOutput {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Connections
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $establishedConnections = @(
        $Connections |
            Where-Object { $_.Protocol -eq "TCP" -and $_.State -eq "Established" } |
            Sort-Object OwningProcess, LocalAddress, LocalPort, RemoteAddress, RemotePort
    )

    foreach ($connection in $establishedConnections) {
        $lines.Add("$($connection.LocalAddress):$($connection.LocalPort) -> $($connection.RemoteAddress):$($connection.RemotePort) PID=$($connection.OwningProcess) ProcessName=$($connection.ProcessName)")
    }

    return $lines
}

function Get-IRNetConnections {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputDir
    )

    $moduleName = "Get-IRNetConnections"
    $moduleOutputDir = Join-Path $OutputDir "Network"
    $outputFiles = @(
        (Join-Path $moduleOutputDir "network_connections.json"),
        (Join-Path $moduleOutputDir "network_connections.csv"),
        (Join-Path $moduleOutputDir "network_connections.txt"),
        (Join-Path $moduleOutputDir "network_connections_established.txt")
    )

    $errors = New-Object System.Collections.Generic.List[string]
    $connections = New-Object System.Collections.Generic.List[object]
    $tcpCount = 0
    $udpCount = 0

    try {
        if (-not (Test-Path -LiteralPath $moduleOutputDir)) {
            New-Item -ItemType Directory -Path $moduleOutputDir -Force -ErrorAction Stop | Out-Null
        }

        $processLookup = Get-IRNetworkProcessLookup

        try {
            $tcpConnections = @(Get-NetTCPConnection -ErrorAction Stop)
        }
        catch {
            $tcpConnections = @()
            $errors.Add("TCP collection failed: $($_.Exception.Message)")
        }

        foreach ($connection in $tcpConnections) {
            $processDetails = Get-IRNetworkProcessDetails -ProcessLookup $processLookup -OwningProcess $connection.OwningProcess

            $connections.Add([PSCustomObject]@{
                Protocol           = "TCP"
                LocalAddress       = ConvertTo-IRNullIfEmpty -Value ([string]$connection.LocalAddress)
                LocalPort          = $connection.LocalPort
                RemoteAddress      = ConvertTo-IRNullIfEmpty -Value ([string]$connection.RemoteAddress)
                RemotePort         = $connection.RemotePort
                State              = ConvertTo-IRNullIfEmpty -Value ([string]$connection.State)
                OwningProcess      = $connection.OwningProcess
                ProcessName        = $processDetails.ProcessName
                ProcessPath        = $processDetails.ProcessPath
                ProcessCommandLine = $processDetails.ProcessCommandLine
            })
        }

        $tcpCount = $tcpConnections.Count

        try {
            $udpEndpoints = @(Get-NetUDPEndpoint -ErrorAction Stop)
        }
        catch {
            $udpEndpoints = @()
            $errors.Add("UDP collection failed: $($_.Exception.Message)")
        }

        foreach ($endpoint in $udpEndpoints) {
            $processDetails = Get-IRNetworkProcessDetails -ProcessLookup $processLookup -OwningProcess $endpoint.OwningProcess

            $connections.Add([PSCustomObject]@{
                Protocol           = "UDP"
                LocalAddress       = ConvertTo-IRNullIfEmpty -Value ([string]$endpoint.LocalAddress)
                LocalPort          = $endpoint.LocalPort
                RemoteAddress      = $null
                RemotePort         = $null
                State              = $null
                OwningProcess      = $endpoint.OwningProcess
                ProcessName        = $processDetails.ProcessName
                ProcessPath        = $processDetails.ProcessPath
                ProcessCommandLine = $processDetails.ProcessCommandLine
            })
        }

        $udpCount = $udpEndpoints.Count

        $records = @($connections | Sort-Object Protocol, OwningProcess, LocalAddress, LocalPort, RemoteAddress, RemotePort)

        $records |
            ConvertTo-Json -Depth 4 |
            Set-Content -LiteralPath $outputFiles[0] -Encoding UTF8

        $records |
            Export-Csv -LiteralPath $outputFiles[1] -NoTypeInformation -Encoding UTF8

        New-IRNetworkTextOutput -Connections $records |
            Set-Content -LiteralPath $outputFiles[2] -Encoding UTF8

        New-IREstablishedConnectionsTextOutput -Connections $records |
            Set-Content -LiteralPath $outputFiles[3] -Encoding UTF8

        Write-Host "[IR-Kit] Collected network connections"

        [PSCustomObject]@{
            ModuleName      = $moduleName
            Success         = ($tcpCount -gt 0 -or $udpCount -gt 0 -or $errors.Count -eq 0)
            OutputDirectory = $moduleOutputDir
            OutputFiles     = $outputFiles
            ConnectionCount = $records.Count
            TcpCount        = $tcpCount
            UdpCount        = $udpCount
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
            ConnectionCount = 0
            TcpCount        = 0
            UdpCount        = 0
            Error           = $message
            Errors          = @($message)
        }
    }
}
