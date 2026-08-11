@echo off
title Конфигурация 1С

rem Меню запуска обновления. Скрипты ищем сначала рядом с этим файлом, потом по
rem обычному пути репозитория - чтобы .cmd работал и как есть, и скопированным
rem на рабочий стол.
rem
rem ВНИМАНИЕ: файл сохранён в кодировке cp866 (OEM 866). Иначе кириллица в окне
rem cmd превращается в мусор. Править только редактором, который её сохраняет,
rem либо через скрипт с явной перекодировкой.

set TOOLS=%~dp0
if not exist "%TOOLS%deploy.ps1" set TOOLS=%USERPROFILE%\Documents\fork\1-_garazh\_tools\
if not exist "%TOOLS%deploy.ps1" (
  echo Не найден deploy.ps1 ни рядом с этим файлом, ни в
  echo %USERPROFILE%\Documents\fork\1-_garazh\_tools
  echo Проверьте, где лежит репозиторий, и сделайте git pull.
  pause
  exit /b 1
)

:menu
cls
echo ==========================================
echo   Обновление конфигурации 1С из GitHub
echo ==========================================
echo.
echo   ТЕСТОВАЯ база (garazh-cp)
echo   1  - Обновить из GitHub + выгрузить .cf
echo   2  - То же, но без git pull
echo   3  - Только загрузить и обновить БД (без .cf)
echo.
echo   РАБОЧАЯ база (garazh) - все выходят из базы
echo   4  - Весь цикл: тест, затем объединение с рабочей
echo   5  - Только объединение с рабочей (.cf уже готов)
echo.
echo   ПРОЧЕЕ
echo   6  - Проверить штрихкоды в макетах
echo   7  - Ярлык этого меню на рабочий стол
echo.
echo   0  - Выход
echo.
set OPT=
set /p OPT=Введите номер и нажмите Enter: 
if "%OPT%"=="1" set SCRIPT=update-base.ps1& set ARGS=& goto run
if "%OPT%"=="2" set SCRIPT=update-base.ps1& set ARGS=-БезPull& goto run
if "%OPT%"=="3" set SCRIPT=update-base.ps1& set ARGS=-ТолькоЗагрузить& goto run
if "%OPT%"=="4" set SCRIPT=deploy.ps1& set ARGS=& goto run
if "%OPT%"=="5" set SCRIPT=deploy.ps1& set ARGS=-ТолькоМерж& goto run
if "%OPT%"=="6" set SCRIPT=check-barcodes.ps1& set ARGS=& goto run
if "%OPT%"=="7" set SCRIPT=make-shortcut.ps1& set ARGS=-Файл "Обновить базу.cmd" -Имя "Обновление 1С"& goto run
if "%OPT%"=="0" exit /b
goto menu

:run
cls
echo Запуск. Шаг загрузки из файлов идёт молча несколько минут - это нормально,
echo окно не закрывать и не прерывать.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%TOOLS%%SCRIPT%" %ARGS%
echo.
echo ------------------------------------------
echo Нажмите любую клавишу, чтобы вернуться в меню.
pause >nul
goto menu
