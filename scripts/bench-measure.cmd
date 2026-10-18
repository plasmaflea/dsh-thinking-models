@echo off
rem Measure benchmark numbers (bypasses PowerShell execution policy)
rem Usage: bench-measure.cmd -Path .\docs\benchmark\after-v2 -Factors
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0bench-measure.ps1" %*
