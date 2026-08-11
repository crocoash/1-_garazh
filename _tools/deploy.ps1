# Весь путь правки одним запуском: GitHub → тестовая база → рабочая база.
# Запускать НА МАШИНЕ С 1С.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File _tools\deploy.ps1
#
# Цепочка:
#   ЧАСТЬ 1 (update-base.ps1, тестовая база)
#     git pull → проверка штрихкодов → /LoadConfigFromFiles → /UpdateDBCfg
#     → /DumpCfg на Рабочий стол
#   ЧАСТЬ 2 (merge-cf.ps1, рабочая база)
#     точка отката → /MergeCfg с этим .cf и файлом настроек → /UpdateDBCfg
#
# Свой код здесь только на склейку: обе части — те же скрипты, что работают
# по отдельности. Правки логики вносить в них, не сюда.
#
# ЧТО НУЖНО ОДИН РАЗ, ИНАЧЕ ЧАСТЬ 2 НЕ ПОЙДЁТ:
#   1. В _tools\update-base.local.ps1 дописать строку соединения рабочей базы:
#        $БазаРабочая = "/S app1\garazh"
#   2. Подготовить файл настроек объединения — в Конфигураторе, подключённом
#      к РАБОЧЕЙ базе: Конфигурация → Сравнить, объединить с конфигурацией
#      из файла… (выбрать .cf с Рабочего стола) → расставить флажки →
#      Действия → Сохранить настройки объединения в файл…
#      Сохранить как _tools\merge-settings.txt (именно .txt, см. merge-cf.ps1).
#
# Обе базы обновляются с монопольным доступом: пользователи должны выйти
# и из тестовой, и из рабочей.
#
# Ключи:
#   -ТолькоТест     остановиться после части 1 (рабочую базу не трогать)
#   -ТолькоМерж     пропустить часть 1, объединить рабочую с готовым .cf
#   -БезPull        не тянуть из git
#   -БезПаузы       не спрашивать подтверждение перед изменением рабочей базы

param(
    [switch]$ТолькоТест,
    # Пропустить часть 1 и сразу объединить рабочую базу с .cf, который уже
    # лежит на Рабочем столе. Нужно, когда часть 1 отработала раньше — например,
    # людей из рабочей базы удалось выгнать только сейчас.
    [switch]$ТолькоМерж,
    [switch]$БезPull,
    [switch]$БезПаузы
)

$ErrorActionPreference = "Stop"

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

$шелл = (Get-Process -Id $PID).Path
if (-not $шелл) { $шелл = "powershell" }

# Строка соединения рабочей базы живёт в локальном файле — в git её нет,
# как и пароля.
$БазаРабочая = ""
$локальные = Join-Path $PSScriptRoot "update-base.local.ps1"
if (Test-Path $локальные) { . $локальные }

$ФайлCf = Join-Path ([Environment]::GetFolderPath("Desktop")) "garazh-cp.cf"

function Заголовок($текст) {
    Write-Host ""
    Write-Host "###############################################################" -ForegroundColor Magenta
    Write-Host "  $текст" -ForegroundColor Magenta
    Write-Host "###############################################################" -ForegroundColor Magenta
}

# --- Часть 1: тестовая база --------------------------------------------------
if ($ТолькоМерж) {

    Заголовок "ЧАСТЬ 1 пропущена (ключ -ТолькоМерж)"

    if (-not (Test-Path $ФайлCf)) {
        Write-Host "Нет файла для объединения: $ФайлCf" -ForegroundColor Red
        Write-Host "Сначала прогоните часть 1 — она его и делает." -ForegroundColor Yellow
        exit 1
    }

    $когда = (Get-Item $ФайлCf).LastWriteTime
    Write-Host "Объединять буду с $ФайлCf (выгружен $когда)." -ForegroundColor DarkGray

} else {

    Заголовок "ЧАСТЬ 1 из 2 — тестовая база (загрузка из GitHub)"

    $аргументы1 = @()
    if ($БезPull) { $аргументы1 += "-БезPull" }

    & $шелл -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "update-base.ps1") @аргументы1
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "Часть 1 не прошла — рабочую базу не трогаю." -ForegroundColor Red
        exit 1
    }

    if ($ТолькоТест) {
        Write-Host ""
        Write-Host "Ключ -ТолькоТест: остановился после тестовой базы." -ForegroundColor Green
        exit 0
    }
}

# --- Проверки перед рабочей базой --------------------------------------------
if (-not $БазаРабочая) {
    Write-Host ""
    Write-Host "НЕ ЗАДАНА РАБОЧАЯ БАЗА." -ForegroundColor Red
    Write-Host ""
    Write-Host "Тестовая база обновлена, а дальше идти некуда: неизвестно, с чем объединять." -ForegroundColor Yellow
    Write-Host "Допишите в _tools\update-base.local.ps1 строку вида:" -ForegroundColor Yellow
    Write-Host '    $БазаРабочая = "/S app1\garazh"' -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Имя базы можно подсмотреть тут:" -ForegroundColor Yellow
    Write-Host '    Get-Content "$env:APPDATA\1C\1CEStart\ibases.v8i"' -ForegroundColor Yellow
    exit 1
}

$настройки = Join-Path $PSScriptRoot "merge-settings.txt"
if (-not (Test-Path $настройки)) {
    Write-Host ""
    Write-Host "НЕТ ФАЙЛА НАСТРОЕК ОБЪЕДИНЕНИЯ — $настройки" -ForegroundColor Red
    Write-Host ""
    Write-Host "Тестовая база обновлена, объединение с рабочей не делаю: без настроек" -ForegroundColor Yellow
    Write-Host "платформа примет решения «чей объект берём» за вас и может взять не ту сторону." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Подготовить один раз в Конфигураторе РАБОЧЕЙ базы:" -ForegroundColor Yellow
    Write-Host "  Конфигурация → Сравнить, объединить с конфигурацией из файла… → $ФайлCf" -ForegroundColor Yellow
    Write-Host "  → расставить флажки → Действия → Сохранить настройки объединения в файл…" -ForegroundColor Yellow
    Write-Host "  → сохранить как $настройки" -ForegroundColor Yellow
    exit 1
}

if (-not $БезПаузы) {
    Write-Host ""
    Write-Host "Дальше меняется РАБОЧАЯ база: $БазаРабочая" -ForegroundColor Yellow
    Write-Host "Пользователи должны выйти из неё — иначе шаг обновления БД не пройдёт." -ForegroundColor Yellow
    Write-Host "Точка отката будет сохранена автоматически перед объединением." -ForegroundColor Yellow
    Write-Host ""
    $ответ = Read-Host "Продолжаем? (д/н)"
    if ($ответ -notmatch '^\s*(д|y|да|yes)\s*$') {
        Write-Host "Остановлено. Тестовая база обновлена, рабочая не тронута." -ForegroundColor Yellow
        Write-Host "Продолжить позже, не повторяя часть 1:" -ForegroundColor Yellow
        Write-Host "  powershell -NoProfile -ExecutionPolicy Bypass -File _tools\merge-cf.ps1 -ПрименитьКБазе" -ForegroundColor Yellow
        exit 0
    }
}

# --- Часть 2: рабочая база ---------------------------------------------------
Заголовок "ЧАСТЬ 2 из 2 — рабочая база (объединение)"

& $шелл -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "merge-cf.ps1") `
    -Файл $ФайлCf -База $БазаРабочая -Настройки $настройки -ПрименитьКБазе
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Часть 2 не прошла. Тестовая база обновлена, рабочая — смотрите вывод выше." -ForegroundColor Red
    Write-Host "Точка отката лежит в: $(Join-Path ([Environment]::GetFolderPath('Desktop')) '1c-до-объединения')" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "ВСЁ ГОТОВО: тестовая база обновлена из GitHub, рабочая объединена с результатом." -ForegroundColor Green
