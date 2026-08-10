@echo off
rem ---------------------------------------------------------------------------
rem Launcher for deploy.ps1 (double-click / desktop shortcut):
rem   GitHub -> test base -> merge into working base.
rem
rem ASCII ONLY, on purpose: Cyrillic plus "chcp" breaks cmd parsing.
rem All Russian output comes from the PowerShell scripts themselves.
rem ---------------------------------------------------------------------------

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy.ps1" %*
set RC=%ERRORLEVEL%

echo.
if not "%RC%"=="0" (
    echo ================= ERROR - see output above =================
) else (
    echo ================= OK =================
)
echo.
pause
