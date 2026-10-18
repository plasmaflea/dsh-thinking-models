@echo off
rem 实测对比表的数字（绕开 PowerShell 执行策略限制）
rem 用法：
rem   bench-measure.cmd -Path .\docs\benchmark\after-v2 -Factors
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0bench-measure.ps1" %*
