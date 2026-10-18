@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0measure-kw.ps1" %*
