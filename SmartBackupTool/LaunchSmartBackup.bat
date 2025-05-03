@echo off
REM Smart Backup Tool Launcher
REM This script launches the Smart Backup Tool with PowerShell execution policy bypass

echo Starting Smart Backup Tool v2.0...
PowerShell -NoProfile -ExecutionPolicy Bypass -File "%~dp0SmartBackup.ps1"