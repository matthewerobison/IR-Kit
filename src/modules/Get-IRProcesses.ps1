function Get-IRProcesses {
    param(
        [string]$OutputDir
    )

    $outfile = Join-Path $OutputDir "processes.txt"

    Get-CimInstance Win32_Process |
        Select-Object ProcessId, Name, CommandLine, ParentProcessId |
        Out-File $outfile

    Write-Host "[IR-Kit] Collected processes"
}
