@echo off
rem Prefer PowerShell 7 when present: Windows PowerShell 5.1 autoloads
rem Microsoft.PowerShell.Utility from the PS7 module dirs (PSModulePath pollution
rem after installing PS7), which makes Get-FileHash unavailable and -Verify fail.
rem Fall back to 5.1 for clean machines.
setlocal
where pwsh >nul 2>nul
if not errorlevel 1 (
  pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0state.ps1" %*
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0state.ps1" %*
)
