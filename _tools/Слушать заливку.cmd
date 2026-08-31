@echo off
rem Окно ожидания заливки. Держать открытым, пока идёт работа с Claude:
rem он ставит метку [deploy] на коммит, когда вы сказали "залей", и окно
rem загружает этот коммит в тестовую базу. Закрыли окно - заливки прекратились.
title Ожидание заливки (тестовая база)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0wait-deploy.ps1" %*
echo.
pause
