@echo off
setlocal

title ClearTrash

net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

set "SCRIPT_DIR=%~dp0"
set "PS1_FILE=%SCRIPT_DIR%ClearTrash.ps1"

if not exist "%PS1_FILE%" (
    cls
    echo ==================================
    echo            CLEARTRASH
    echo ==================================
    echo.
    echo ClearTrash.ps1 was not found.
    echo.
    echo Expected file:
    echo %PS1_FILE%
    echo.
    echo Put both files in the same folder.
    echo.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1_FILE%"
exit /b %errorlevel%