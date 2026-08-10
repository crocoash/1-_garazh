# Обновление базы из репозитория одной командой. Запускать НА МАШИНЕ С 1С.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File _tools\update-base.ps1
#
# Что делает по шагам:
#   1. git pull  — забирает новую выгрузку из GitHub;
#   2. проверяет штрихкоды в макетах (битый макет калечит объект в базе необратимо);
#   3. Конфигуратор: «Загрузить конфигурацию из файлов»;
#   4. Конфигуратор: «Обновить конфигурацию базы данных»;
#   5. Конфигуратор: «Сохранить конфигурацию в файл» — .cf на Рабочий стол,
#      каждый раз поверх прежнего.
#
# Ключи:
#   -ТолькоЗагрузить          остановиться после шага 4, .cf не выгружать
#   -БезPull                  не тянуть из git (файлы уже лежат как надо)
#   -ПропуститьПроверкуШтрихкодов   загрузить, даже если макет битый (осознанно)
#
# Обновление конфигурации базы требует монопольного доступа: пользователи должны
# выйти из базы, иначе шаг 4 упадёт с «Не удалось заблокировать информационную базу».

param(
    [switch]$ТолькоЗагрузить,
    [switch]$БезPull,
    [switch]$ПропуститьПроверкуШтрихкодов
)

# ==============================================================================
#  НАСТРОЙКИ — править здесь
# ==============================================================================

# Пользователь базы и его пароль. Права нужны административные.
$Пользователь = ""
$Пароль       = ""

# Строка соединения с базой. Серверная база: /S <кластер>\<имя базы>.
# Файловая была бы: /F "C:\Users\...\InfoBase"
$База = "/S app1\garazh-cp"

# Куда класть .cf. По умолчанию — Рабочий стол текущего пользователя.
$ФайлCf = Join-Path ([Environment]::GetFolderPath("Desktop")) "garazh-cp.cf"

# Путь к 1cv8.exe. Пусто — ищем сами самую свежую платформу в Program Files.
$Платформа = ""

# ==============================================================================
#  Локальные настройки (не уезжают в git).
#  Если рядом лежит update-base.local.ps1 — он подключается ЗДЕСЬ и может
#  переопределить любую переменную выше. Так пароль не попадёт в репозиторий:
#     $Пользователь = "Иванов"
#     $Пароль       = "12345"
# ==============================================================================
$локальные = Join-Path $PSScriptRoot "update-base.local.ps1"
if (Test-Path $локальные) {
    . $локальные
    Write-Host "Настройки взяты из update-base.local.ps1" -ForegroundColor DarkGray
}

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$git = "C:\Program Files\Git\cmd\git.exe"
if (-not (Test-Path $git)) { $git = "git" }

$шелл = (Get-Process -Id $PID).Path
if (-not $шелл) { $шелл = "powershell" }

$началоВсего = Get-Date

function Шаг($текст) {
    Write-Host ""
    Write-Host "== $текст" -ForegroundColor Cyan
}

function Отказ($текст) {
    Write-Host ""
    Write-Host $текст -ForegroundColor Red
    Write-Host "База НЕ обновлена." -ForegroundColor Red
    exit 1
}

# Лог Конфигуратора пишется то в UTF-8, то в кодировке системы — читаем с запасом.
function ПрочитатьЛог($путь) {
    if (-not (Test-Path $путь)) { return "" }
    $текст = [System.IO.File]::ReadAllText($путь, [System.Text.Encoding]::UTF8)
    if ($текст -match "\uFFFD") {
        $текст = [System.IO.File]::ReadAllText($путь, [System.Text.Encoding]::Default)
    }
    return $текст.Trim()
}

# --- Платформа ---------------------------------------------------------------
if (-not $Платформа) {
    $кандидаты = @()
    foreach ($папка in @("$env:ProgramFiles\1cv8", "${env:ProgramFiles(x86)}\1cv8")) {
        if (Test-Path $папка) {
            $кандидаты += Get-ChildItem -Path $папка -Directory |
                Where-Object { Test-Path (Join-Path $_.FullName "bin\1cv8.exe") }
        }
    }
    if ($кандидаты.Count -eq 0) {
        Отказ "Не найден 1cv8.exe. Пропишите путь в настройке `$Платформа в начале скрипта."
    }
    # Имена версий вида 8.3.24.1234 — сортируем как версии, берём самую свежую.
    $свежая = $кандидаты |
        Sort-Object { try { [version]$_.Name } catch { [version]"0.0.0.0" } } |
        Select-Object -Last 1
    $Платформа = Join-Path $свежая.FullName "bin\1cv8.exe"
}
if (-not (Test-Path $Платформа)) { Отказ "Не найден файл платформы: $Платформа" }

if (-not $Пользователь) {
    Отказ "Не заполнен `$Пользователь. Впишите пользователя базы в настройки в начале скрипта (или в update-base.local.ps1)."
}

Write-Host "Платформа: $Платформа" -ForegroundColor DarkGray
Write-Host "База:      $База" -ForegroundColor DarkGray
Write-Host "Файлы:     $root" -ForegroundColor DarkGray

# --- 1. git pull -------------------------------------------------------------
if ($БезPull) {

    Шаг "git pull пропущен (ключ -БезPull)"

} else {

    Шаг "Забираю изменения из GitHub"

    $грязно = & $git -c core.quotepath=false status --porcelain
    if ($грязно) {
        Write-Host "В рабочей папке есть незакоммиченные изменения:" -ForegroundColor Red
        $грязно | Select-Object -First 15 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        Write-Host ""
        Write-Host "Это может быть ваша выгрузка из Конфигуратора, ещё не уехавшая в git." -ForegroundColor Yellow
        Write-Host "Сначала снимок: _tools\snapshot.ps1 ""сообщение"" -Всё" -ForegroundColor Yellow
        Отказ "Pull делать нельзя — правки затрёт."
    }

    $былоНа = (& $git rev-parse HEAD).Trim()

    & $git pull --ff-only 2>&1 | Write-Host
    if ($LASTEXITCODE -ne 0) {
        Отказ "git pull не прошёл (см. выше). Разобрать вручную."
    }

    $сталоНа = (& $git rev-parse HEAD).Trim()

    if ($былоНа -eq $сталоНа) {
        Write-Host "Новых коммитов нет — файлы уже последние. Загружаю то, что лежит." -ForegroundColor Yellow
    } else {
        Write-Host ""
        Write-Host "Приехало:" -ForegroundColor Green
        & $git log --oneline "$былоНа..$сталоНа" | ForEach-Object { Write-Host "  $_" }
        Write-Host ""
        & $git diff --stat "$былоНа..$сталоНа" | Select-Object -Last 1 | ForEach-Object { Write-Host "  $_" }
    }
}

Write-Host ""
Write-Host "Загружается коммит: $((& $git log -1 --oneline).Trim())" -ForegroundColor DarkGray

# --- 2. Штрихкоды ------------------------------------------------------------
# Выгрузка в файлы теряет base64-блоб ActiveX-объекта в макете. Загрузка такого
# файла сносит объект уже в базе — на месте штрихкода пустая рамка, и обратно
# оно само не восстанавливается. Поэтому проверяем ДО загрузки.
if ($ПропуститьПроверкуШтрихкодов) {

    Шаг "Проверка штрихкодов пропущена (ключ -ПропуститьПроверкуШтрихкодов)"

} else {

    Шаг "Проверяю штрихкоды в макетах"

    $проверка = Join-Path $PSScriptRoot "check-barcodes.ps1"
    if (Test-Path $проверка) {

        & $шелл -NoProfile -ExecutionPolicy Bypass -File $проверка
        if ($LASTEXITCODE -ne 0) {
            Write-Host ""
            Write-Host "В файлах битый макет штрихкода. Если такое загрузить, объект пропадёт" -ForegroundColor Red
            Write-Host "и в базе — восстановить можно будет только из .cf." -ForegroundColor Red
            Write-Host ""
            Write-Host "Починить: powershell -File _tools\fix-barcodes.ps1 -Применить" -ForegroundColor Yellow
            Write-Host "и повторить. Осознанно пропустить: ключ -ПропуститьПроверкуШтрихкодов." -ForegroundColor Yellow
            Отказ "Загрузка остановлена."
        }

    } else {
        Write-Host "check-barcodes.ps1 не найден — пропускаю." -ForegroundColor Yellow
    }
}

# --- Запуск Конфигуратора ----------------------------------------------------
$логи = Join-Path $env:TEMP "1c-update-base"
if (-not (Test-Path $логи)) { New-Item -ItemType Directory -Path $логи | Out-Null }

function ЗапуститьКонфигуратор($имяШага, $аргументы) {

    $лог = Join-Path $логи "$имяШага.log"
    if (Test-Path $лог) { Remove-Item $лог -Force }

    $общие = @(
        "DESIGNER"
        $База
        "/N", $Пользователь
        "/P", $Пароль
        "/DisableStartupDialogs"
        "/DisableStartupMessages"
        "/Out", $лог, "-NoTruncate"
    )

    $начало = Get-Date
    $процесс = Start-Process -FilePath $Платформа -ArgumentList ($общие + $аргументы) -Wait -PassThru
    $секунды = [int]((Get-Date) - $начало).TotalSeconds

    $текст = ПрочитатьЛог $лог
    if ($текст) { Write-Host $текст }

    if ($процесс.ExitCode -ne 0) {
        Отказ "Шаг «$имяШага» завершился с кодом $($процесс.ExitCode). Лог: $лог"
    }

    # Конфигуратор умеет вернуть 0 и написать ошибку в лог — смотрим и на текст.
    if ($текст -match "(?im)^\s*(Ошибка|Помилка|Error)") {
        Отказ "Шаг «$имяШага» вернул код 0, но в логе есть ошибка (см. выше). Лог: $лог"
    }

    Write-Host "  готово за $секунды с" -ForegroundColor Green
}

# --- 3. Загрузка конфигурации из файлов --------------------------------------
Шаг "Загружаю конфигурацию из файлов"
ЗапуститьКонфигуратор "load" @("/LoadConfigFromFiles", $root)

# --- 4. Обновление конфигурации базы данных ----------------------------------
# Нужен монопольный доступ: пользователи должны выйти из базы.
Шаг "Обновляю конфигурацию базы данных"
ЗапуститьКонфигуратор "update" @("/UpdateDBCfg")

if ($ТолькоЗагрузить) {
    Write-Host ""
    Write-Host "Готово (ключ -ТолькоЗагрузить): база обновлена, .cf не выгружался." -ForegroundColor Green
    exit 0
}

# --- 5. Выгрузка .cf на Рабочий стол -----------------------------------------
Шаг "Сохраняю конфигурацию в файл"

$папкаCf = Split-Path -Parent $ФайлCf
if ($папкаCf -and -not (Test-Path $папкаCf)) {
    New-Item -ItemType Directory -Path $папкаCf -Force | Out-Null
}

# Пишем во временный файл рядом и подменяем: если выгрузка упадёт на середине,
# прежний .cf останется целым, а не обрежется до половины.
$времCf = "$ФайлCf.new"
if (Test-Path $времCf) { Remove-Item $времCf -Force }

ЗапуститьКонфигуратор "dump" @("/DumpCfg", $времCf)

if (-not (Test-Path $времCf)) { Отказ "Конфигуратор отработал, но файл не появился: $времCf" }

Move-Item -Path $времCf -Destination $ФайлCf -Force

$размер = [math]::Round((Get-Item $ФайлCf).Length / 1MB, 1)
Write-Host "  $ФайлCf  ($размер МБ)" -ForegroundColor Green

# --- Итог --------------------------------------------------------------------
$всего = [int]((Get-Date) - $началоВсего).TotalSeconds
Write-Host ""
Write-Host "ГОТОВО за $всего с. База обновлена, конфигурация сохранена на Рабочий стол." -ForegroundColor Green
Write-Host "Коммит в базе: $((& $git log -1 --oneline).Trim())" -ForegroundColor Green
