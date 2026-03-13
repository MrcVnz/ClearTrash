@echo off
setlocal

title ClearTrash
cd /d "%~dp0"

net session >nul 2>&1
if not "%errorlevel%"=="0" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'cmd.exe' -ArgumentList '/c','\"%~f0\"' -Verb RunAs -WorkingDirectory '%~dp0'"
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

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1_FILE%"
set "EXIT_CODE=%errorlevel%"
exit /b %EXIT_CODE%