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

function Get-IRPrefetch {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputDir
    )

    $moduleName = "Prefetch"
    $moduleOutputDir = Join-Path $OutputDir "Prefetch"
    $prefetchFilesOutputDir = Join-Path $moduleOutputDir "files"
    $sourcePrefetchPath = "C:\Windows\Prefetch"
    $outputFiles = @(
        (Join-Path $moduleOutputDir "prefetch_inventory.json"),
        (Join-Path $moduleOutputDir "prefetch_inventory.csv")
    )
    $errors = New-Object System.Collections.Generic.List[string]

    try {
        if (-not (Test-Path -LiteralPath $sourcePrefetchPath)) {
            throw "Prefetch source path does not exist or is inaccessible: $sourcePrefetchPath"
        }

        New-Item -ItemType Directory -Path $prefetchFilesOutputDir -Force -ErrorAction Stop | Out-Null

        try {
            $sourceFiles = @(Get-ChildItem -LiteralPath $sourcePrefetchPath -Filter *.pf -File -ErrorAction Stop)
        }
        catch {
            throw "Prefetch inventory failed: $($_.Exception.Message)"
        }

        $inventory = foreach ($file in $sourceFiles) {
            $destinationPath = Join-Path $prefetchFilesOutputDir $file.Name
            $copySuccess = $true
            $copyError = $null

            try {
                Copy-Item -LiteralPath $file.FullName -Destination $destinationPath -Force -ErrorAction Stop
            }
            catch {
                $copySuccess = $false
                $copyError = $_.Exception.Message
                $errors.Add("Copy failed for $($file.FullName): $copyError")
            }

            [PSCustomObject]@{
                FileName          = $file.Name
                SourcePath        = $file.FullName
                CopiedPath        = if ($copySuccess) { $destinationPath } else { $null }
                SizeBytes         = $file.Length
                CreationTimeUtc   = ConvertTo-IRIsoDateTimeUtc -Value $file.CreationTimeUtc
                LastWriteTimeUtc  = ConvertTo-IRIsoDateTimeUtc -Value $file.LastWriteTimeUtc
                LastAccessTimeUtc = ConvertTo-IRIsoDateTimeUtc -Value $file.LastAccessTimeUtc
                CopySuccess       = $copySuccess
                CopyError         = $copyError
            }
        }

        $inventory = @($inventory | Sort-Object FileName)
        $copiedCount = @($inventory | Where-Object { $_.CopySuccess }).Count
        $failedCopyCount = @($inventory | Where-Object { -not $_.CopySuccess }).Count

        $inventory |
            ConvertTo-Json -Depth 4 |
            Set-Content -LiteralPath $outputFiles[0] -Encoding UTF8

        $inventory |
            Export-Csv -LiteralPath $outputFiles[1] -NoTypeInformation -Encoding UTF8

        Write-Host "[IR-Kit] Collected prefetch inventory"

        [PSCustomObject]@{
            ModuleName      = $moduleName
            Success         = $true
            OutputDirectory = $moduleOutputDir
            OutputFiles     = $outputFiles
            PrefetchCount   = $inventory.Count
            CopiedCount     = $copiedCount
            FailedCopyCount = $failedCopyCount
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
            PrefetchCount   = 0
            CopiedCount     = 0
            FailedCopyCount = 0
            Error           = $message
            Errors          = @($message)
        }
    }
}
