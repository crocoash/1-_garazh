@echo off
rem ---------------------------------------------------------------------------
rem Launcher for update-base.ps1 (double-click / desktop shortcut).
rem
rem ASCII ONLY, on purpose. Cyrillic here breaks cmd: "chcp 65001" switches the
rem codepage in the middle of parsing, cmd loses its byte offset in the file and
rem starts executing garbage ("'ho' is not recognized as..."). All Russian output
rem comes from the PowerShell script itself, which sets UTF-8 for the console.
rem
rem Any arguments are passed through, so a second shortcut can carry
rem the "load only" or "no pull" switches.
rem ---------------------------------------------------------------------------

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update-base.ps1" %*
set RC=%ERRORLEVEL%

echo.
if not "%RC%"=="0" (
    echo ================= ERROR - see output above =================
) else (
    echo ================= OK =================
)
echo.
pause
