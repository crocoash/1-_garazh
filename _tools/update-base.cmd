@echo off
chcp 65001 >nul
title Обновление базы garazh-cp из GitHub

rem Запуск update-base.ps1 двойным щелчком. Ярлык на рабочем столе создаётся
rem командой из CLAUDE.md (раздел «Инструменты») и указывает сюда же.
rem Все аргументы этого файла передаются скрипту: можно сделать второй ярлык
rem с ключом -ТолькоЗагрузить или -БезPull.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update-base.ps1" %*

echo.
if errorlevel 1 (
    echo ================= ЗАВЕРШИЛОСЬ С ОШИБКОЙ =================
) else (
    echo ================= ГОТОВО =================
)
echo.
pause
