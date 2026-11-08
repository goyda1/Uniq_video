@echo off
rem ============================================================
rem  Unique-Video.bat - launcher for Unique-Video.ps1
rem
rem  Usage (same parameters as the PowerShell script):
rem    Unique-Video.bat                  -> interactive wizard
rem    Unique-Video.bat -Help            -> full parameter reference
rem    Unique-Video.bat -Path video.mp4 -Count 3
rem    Unique-Video.bat -Count 5 -BorderMode pad -BorderWidth 10
rem
rem  Without parameters the interactive wizard starts.
rem  Any flags after the bat name are passed to the script.
rem ============================================================

set "SCRIPT_DIR=%~dp0"

if "%~1"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%Unique-Video.ps1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%Unique-Video.ps1" %*
)

echo.
pause
