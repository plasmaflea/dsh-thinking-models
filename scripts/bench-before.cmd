@echo off
rem Toggle the control-group environment (bypasses PowerShell execution policy)
rem Usage:
rem   bench-before.cmd            arm (remove skills + AGENTS.md)
rem   bench-before.cmd -Status    show current state
rem   bench-before.cmd -Restore   restore everything
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0bench-before.ps1" %*
