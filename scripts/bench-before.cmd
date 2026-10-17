@echo off
rem 对照组环境开关的入口（绕开 PowerShell 执行策略限制）
rem 用法：
rem   bench-before.cmd            武装（撤技能 + 撤 AGENTS.md）
rem   bench-before.cmd -Status    查看状态
rem   bench-before.cmd -Restore   恢复现场
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0bench-before.ps1" %*
