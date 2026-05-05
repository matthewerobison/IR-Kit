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

function ConvertTo-IRDnsCacheData {
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [System.Array]) {
        return (($Value | ForEach-Object { [string]$_ }) -join "; ")
    }

    return ConvertTo-IRNullIfEmpty -Value ([string]$Value)
}

function Get-IRDnsCache {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputDir
    )

    $moduleName = "DnsCache"
    $moduleOutputDir = Join-Path $OutputDir "DnsCache"
    $outputFiles = @(
        (Join-Path $moduleOutputDir "dns_cache_raw.txt"),
        (Join-Path $moduleOutputDir "dns_cache.json"),
        (Join-Path $moduleOutputDir "dns_cache.csv")
    )

    $errors = New-Object System.Collections.Generic.List[string]
    $rawOutputCaptured = $false
    $structuredOutputCaptured = $false
    $recordCount = 0

    try {
        if (-not (Test-Path -LiteralPath $moduleOutputDir)) {
            New-Item -ItemType Directory -Path $moduleOutputDir -Force -ErrorAction Stop | Out-Null
        }

        try {
            $rawOutput = & ipconfig /displaydns 2>&1
            $rawOutputText = ($rawOutput | Out-String)

            if (-not [string]::IsNullOrWhiteSpace($rawOutputText)) {
                $rawOutputText | Set-Content -LiteralPath $outputFiles[0] -Encoding UTF8
                $rawOutputCaptured = $true
            }
            else {
                $errors.Add("Raw DNS cache output was empty.")
            }
        }
        catch {
            $errors.Add("Raw DNS cache collection failed: $($_.Exception.Message)")
        }

        $structuredRecords = @()
        try {
            if (-not (Get-Command Get-DnsClientCache -ErrorAction Stop)) {
                throw "Get-DnsClientCache is unavailable on this system."
            }

            $rawStructuredRecords = @(Get-DnsClientCache -ErrorAction Stop)
            $structuredRecords = foreach ($record in $rawStructuredRecords) {
                [PSCustomObject]@{
                    Entry      = ConvertTo-IRNullIfEmpty -Value ([string]($record | Select-Object -ExpandProperty Entry -ErrorAction SilentlyContinue))
                    RecordName = ConvertTo-IRNullIfEmpty -Value ([string]($record | Select-Object -ExpandProperty Entry -ErrorAction SilentlyContinue))
                    RecordType = ConvertTo-IRNullIfEmpty -Value ([string]($record | Select-Object -ExpandProperty Type -ErrorAction SilentlyContinue))
                    Status     = ConvertTo-IRNullIfEmpty -Value ([string]($record | Select-Object -ExpandProperty Status -ErrorAction SilentlyContinue))
                    Section    = ConvertTo-IRNullIfEmpty -Value ([string]($record | Select-Object -ExpandProperty Section -ErrorAction SilentlyContinue))
                    TimeToLive = ($record | Select-Object -ExpandProperty TimeToLive -ErrorAction SilentlyContinue)
                    DataLength = ($record | Select-Object -ExpandProperty DataLength -ErrorAction SilentlyContinue)
                    Data       = ConvertTo-IRDnsCacheData -Value ($record | Select-Object -ExpandProperty Data -ErrorAction SilentlyContinue)
                }
            }

            $structuredRecords = @($structuredRecords | Sort-Object RecordName, RecordType, Data)
            $recordCount = $structuredRecords.Count

            $structuredRecords |
                ConvertTo-Json -Depth 4 |
                Set-Content -LiteralPath $outputFiles[1] -Encoding UTF8

            $structuredRecords |
                Export-Csv -LiteralPath $outputFiles[2] -NoTypeInformation -Encoding UTF8

            $structuredOutputCaptured = $true
        }
        catch {
            $errors.Add("Structured DNS cache collection failed: $($_.Exception.Message)")
        }

        if (-not $rawOutputCaptured -and -not $structuredOutputCaptured) {
            throw ($errors -join "; ")
        }

        Write-Host "[IR-Kit] Collected DNS cache"

        [PSCustomObject]@{
            ModuleName               = $moduleName
            Success                  = $true
            OutputDirectory          = $moduleOutputDir
            OutputFiles              = $outputFiles
            RecordCount              = $recordCount
            RawOutputCaptured        = $rawOutputCaptured
            StructuredOutputCaptured = $structuredOutputCaptured
            Error                    = if ($errors.Count -gt 0) { $errors -join "; " } else { $null }
            Errors                   = @($errors)
        }
    }
    catch {
        $message = $_.Exception.Message
        Write-Error "[IR-Kit] $moduleName failed: $message"

        [PSCustomObject]@{
            ModuleName               = $moduleName
            Success                  = $false
            OutputDirectory          = $moduleOutputDir
            OutputFiles              = $outputFiles
            RecordCount              = 0
            RawOutputCaptured        = $rawOutputCaptured
            StructuredOutputCaptured = $structuredOutputCaptured
            Error                    = $message
            Errors                   = if ($errors.Count -gt 0) { @($errors) } else { @($message) }
        }
    }
}
