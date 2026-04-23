# IR-Kit

IR-Kit is a lightweight incident response triage toolkit built for small and medium businesses and MSPs.

## Purpose
Provide fast, actionable endpoint triage that can be executed remotely with minimal overhead.

## Key Principles
- Simple to run
- No heavy dependencies
- Actionable output (not just raw data)
- Designed for real-world incidents

## MVP Direction
- PowerShell-based CLI
- Modular collectors
- Structured outputs (JSON + text)
- Basic detection logic

## Example Usage
```powershell
.\src\IR-Kit.ps1 -Mode Triage -Case phishing -OutputDir C:\IR-Kit\Cases\Case-001
```

## Repo Structure (Planned)
```
src/
  modules/
  detections/
docs/
```

## Status
🚧 Initial scaffolding phase
