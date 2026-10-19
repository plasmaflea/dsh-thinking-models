@echo off
rem Thin wrapper: prefer PowerShell 7 when present, fall back to Windows PowerShell 5.1.
setlocal
where pwsh >nul 2>nul
if not errorlevel 1 (
  pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0verify-install.ps1" %*
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0verify-install.ps1" %*
)
