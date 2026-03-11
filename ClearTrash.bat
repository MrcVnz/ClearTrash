@echo off
setlocal EnableExtensions

net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

set "PS1_FILE=%~dp0ClearTrash.ps1"

if not exist "%PS1_FILE%" (
    cls
    echo Running as Administrator...
    echo.
    echo PowerShell script not found:
    echo %PS1_FILE%
    echo.
    echo Put ClearTrash.bat and ClearTrash.ps1 in the same folder.
    timeout /t 3 >nul
    exit /b 1
)

cls
echo Running as Administrator...
echo.
echo Using script:
echo %PS1_FILE%
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1_FILE%"

exit /b