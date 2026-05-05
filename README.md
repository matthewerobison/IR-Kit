# IR-Kit

IR-Kit is a lightweight PowerShell incident response triage toolkit for SMBs and MSPs.

## Architecture

IR-Kit is split into two major parts:

- `Collector`: runs on remote endpoints through RMM or remote execution and only collects and normalizes evidence
- `Analyzer`: runs later on the analyst workstation and will handle detection, correlation, and reporting

The analyzer side is only a placeholder right now. No detection logic is implemented yet.

## Project Structure

```text
src/
  collector/
    Invoke-IRKitCollector.ps1
    modules/
      Get-IRProcesses.ps1
      Get-IRNetConnections.ps1
  analyzer/
    Invoke-IRKitAnalyzer.ps1
    modules/
    rules/
  IR-Kit.ps1
```

## Collector Usage

Preferred entry point:

```powershell
.\src\collector\Invoke-IRKitCollector.ps1 -CaseName phishing -OutputDir C:\IR-Kit\Cases
```

Select specific modules:

```powershell
.\src\collector\Invoke-IRKitCollector.ps1 -CaseName phishing -OutputDir C:\IR-Kit\Cases -Modules Processes,Network
```

Backwards-compatible wrapper:

```powershell
.\src\IR-Kit.ps1 -Case phishing -OutputDir C:\IR-Kit\Cases
```

## Analyzer Placeholder Usage

```powershell
.\src\analyzer\Invoke-IRKitAnalyzer.ps1 -CasePath C:\IR-Kit\Cases\phishing_20260504_220000
```

## Output Structure

```text
OutputDir/
  CaseName_timestamp/
    collection_manifest.json
    Processes/
      processes.json
      processes.csv
      process_tree.txt
    Network/
      network_connections.json
      network_connections.csv
      network_connections.txt
      network_connections_established.txt
```

## Notes

- Collector modules are responsible for creating their own artifact subfolders
- Artifacts are written as structured JSON and CSV first, with responder-friendly text outputs alongside them
- The analyzer placeholder validates the case path and does not modify case data
