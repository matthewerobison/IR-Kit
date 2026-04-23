function Get-IRNetConnections {
    param(
        [string]$OutputDir
    )

    $outfile = Join-Path $OutputDir "network_connections.txt"

    netstat -ano | Out-File $outfile

    Write-Host "[IR-Kit] Collected network connections"
}
