@echo off
:: ─── Auto-elevate to Administrator ──────────────────────────────────────────
:: If not already running as admin, re-launch this batch file via UAC prompt.
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell.exe -Command "Start-Process cmd.exe -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

:: Now running as admin – launch the PowerShell script
powershell.exe -ExecutionPolicy Bypass -File "%~dp0ulli-windows-v090145.ps1"
pause



