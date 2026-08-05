# Снимок текущей выгрузки конфигурации в git.
# Запускать ПОСЛЕ того, как залил новую полную выгрузку файлов поверх этой папки,
# и после каждой законченной задачи.
#
# Что коммитить — указывается явно, иначе скрипт останавливается. Причина:
# в репозитории может работать вторая сессия (вкладка), и «git add -A» заберёт
# её недописанную правку в этот коммит и отправит на машину с 1С.
#
# Свои правки:
#   powershell -File _tools\snapshot.ps1 "сообщение" -Пути "CommonModules/Х,Documents/У.xml"
#   pwsh -NoProfile -File _tools/snapshot.ps1 "сообщение" -Пути "CommonModules/Х"
# Вся выгрузка (после «Выгрузить конфигурацию в файлы» меняются тысячи файлов):
#   pwsh -NoProfile -File _tools/snapshot.ps1 "сообщение" -Всё
#
# Изменённые файлы вне указанных путей скрипт печатает отдельным списком
# «НЕ вошло в снимок» и оставляет незакоммиченными.

param(
    [string]$Message = "",
    # Пути относительно этой папки — что именно коммитить.
    [string[]]$Пути = @(),
    # Коммитить всё дерево целиком. Нужно после новой выгрузки из Конфигуратора,
    # когда меняются тысячи файлов сразу.
    [switch]$Всё,
    # Разрешить снимок, даже если в корне репозитория лежит второй комплект выгрузки.
    [switch]$РазрешитьДубльВКорне
)

$ErrorActionPreference = "Stop"
$git = "C:\Program Files\Git\cmd\git.exe"
if (-not (Test-Path $git)) { $git = "git" }

# Хост-шелл: на Windows это powershell.exe, на macOS/Linux — pwsh. Нужен для вызова
# вложенных скриптов тем же интерпретатором, которым запущен этот.
$шелл = (Get-Process -Id $PID).Path
if (-not $шелл) { $шелл = if ($IsWindows -eq $false) { "pwsh" } else { "powershell" } }

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# --- Дубль выгрузки в корне репозитория -------------------------------------
# Конфигуратор умеет выгрузить файлы не в эту папку, а в корень репозитория —
# тогда в дереве оказывается второй, никем не поддерживаемый комплект.
# Ловим это до коммита: иначе дубль уезжает в git и путает обе стороны.
$верх = (& $git rev-parse --show-toplevel).Trim()
if ($верх) { $верх = (Resolve-Path $верх).Path }
$текущая = (Resolve-Path $root).Path

if ($верх -and $верх -ne $текущая) {

    $признаки = @("Configuration.xml", "CommonModules", "Documents")
    $найдено  = @()

    foreach ($признак in $признаки) {
        if (Test-Path (Join-Path $верх $признак)) { $найдено += $признак }
    }

    if ($найдено.Count -eq $признаки.Count) {

        Write-Host "В КОРНЕ РЕПОЗИТОРИЯ ЛЕЖИТ ВТОРАЯ ВЫГРУЗКА КОНФИГУРАЦИИ." -ForegroundColor Red
        Write-Host "  корень: $верх" -ForegroundColor Red
        Write-Host "  рабочая папка: $текущая" -ForegroundColor Red
        Write-Host ""
        Write-Host "Похоже, Конфигуратор выгрузил файлы не в эту папку. Пока не разобрались," -ForegroundColor Red
        Write-Host "снимок не создаётся: дубль уедет в git и разойдётся с рабочей папкой." -ForegroundColor Red
        Write-Host ""
        Write-Host "Что делать: перенести нужное в «$(Split-Path -Leaf $текущая)» и удалить лишнее из корня," -ForegroundColor Yellow
        Write-Host "либо, если дубль нужен осознанно, запустить с ключом -РазрешитьДубльВКорне." -ForegroundColor Yellow

        if (-not $РазрешитьДубльВКорне) { exit 1 }

        Write-Host ""
        Write-Host "Ключ -РазрешитьДубльВКорне задан — продолжаю." -ForegroundColor Yellow
        Write-Host ""
    }
}

# Выгрузка выборочно теряет base64-блоб <object> у рисунков-штрихкодов.
# Сначала восстанавливаем потерянные объекты, затем проверяем результат.
$починка = Join-Path $PSScriptRoot "fix-barcodes.ps1"
if (Test-Path $починка) { & $шелл -NoProfile -ExecutionPolicy Bypass -File $починка -Применить }

# Проверка встроенных объектов в макетах (штрихкоды) — выгрузка их иногда теряет.
$проверка = Join-Path $PSScriptRoot "check-barcodes.ps1"
if (Test-Path $проверка) {
    & $шелл -NoProfile -ExecutionPolicy Bypass -File $проверка
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ВНИМАНИЕ: в выгрузке битые макеты штрихкодов (см. выше)." -ForegroundColor Yellow
        Write-Host "Снимок всё равно будет создан — он фиксирует то, что реально лежит в файлах." -ForegroundColor Yellow
    }
    Write-Host ""
}

# --- Что берём в снимок ------------------------------------------------------
$былоГрязно = & $git -c core.quotepath=false status --porcelain

# При запуске через -File массив приходит одной строкой ("а,б"): командная
# строка не разбирается как выражение PowerShell. Разбираем запятые сами.
$список = @()
foreach ($элемент in $Пути) {
    foreach ($часть in ($элемент -split ',')) {
        if ($часть.Trim()) { $список += $часть.Trim() }
    }
}
$Пути = $список

if ($Пути.Count -eq 0 -and -not $Всё) {

    # Без явного выбора не коммитим: в репозитории может работать вторая
    # сессия, и «add -A» заберёт её недописанную правку в этот коммит.
    Write-Host "НЕ УКАЗАНО, ЧТО КОММИТИТЬ." -ForegroundColor Red
    Write-Host ""
    Write-Host "В репозитории может работать вторая сессия (вкладка) — снимок всего дерева" -ForegroundColor Yellow
    Write-Host "заберёт её незаконченные правки в ваш коммит и отправит их на машину с 1С." -ForegroundColor Yellow
    Write-Host ""

    $изменённые = @()
    foreach ($строка in $былоГрязно) {
        if (-not $строка) { continue }
        $файл = $строка.Substring(3).Trim('"')
        if ($файл -match ' -> ') { $файл = ($файл -split ' -> ')[1] }
        $изменённые += $файл
    }

    if ($изменённые.Count -gt 0) {
        Write-Host "Сейчас изменено файлов: $($изменённые.Count)" -ForegroundColor Cyan
        $изменённые | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }
        if ($изменённые.Count -gt 20) { Write-Host "  … и ещё $($изменённые.Count - 20)" }
        Write-Host ""
    }

    Write-Host "Свои правки:   snapshot.ps1 ""сообщение"" -Пути ""CommonModules/Х,Documents/У.xml""" -ForegroundColor Green
    Write-Host "Всю выгрузку:  snapshot.ps1 ""сообщение"" -Всё   (после выгрузки из Конфигуратора)" -ForegroundColor Green

    exit 1
}

if ($Пути.Count -gt 0) {

    foreach ($путь in $Пути) {
        if (-not (Test-Path $путь)) {
            Write-Host "Путь не найден: $путь" -ForegroundColor Red
            exit 1
        }
    }

    & $git add -A -- $Пути 2>&1 | Out-Null

} else {

    & $git add -A 2>&1 | Out-Null
}

$вСнимке = & $git -c core.quotepath=false diff --cached --name-only

if (-not $вСнимке) {
    Write-Host "Изменений нет — новый снимок не создан." -ForegroundColor Yellow
    exit 0
}

# Изменённые, но не попавшие в снимок файлы: при работе двух сессий это правки
# соседней вкладки, и коммитить их за неё нельзя.
$чужие = @()
foreach ($строка in $былоГрязно) {
    if (-not $строка) { continue }
    $файл = $строка.Substring(3).Trim('"')
    if ($файл -match ' -> ') { $файл = ($файл -split ' -> ')[1] }
    if ($вСнимке -notcontains $файл) { $чужие += $файл }
}

$stat = & $git diff --cached --shortstat
if (-not $Message) {
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm"
    $Message = "Выгрузка $stamp"
}

& $git commit -q -m $Message
Write-Host "Снимок создан: $Message" -ForegroundColor Green
Write-Host $stat
Write-Host ""
Write-Host "Что изменилось:" -ForegroundColor Cyan
& $git show --stat --oneline HEAD | Select-Object -First 40

if ($чужие.Count -gt 0) {
    Write-Host ""
    Write-Host "НЕ вошло в снимок (изменено, но вне указанных путей) — $($чужие.Count) файл(ов):" -ForegroundColor Yellow
    $чужие | Select-Object -First 15 | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
    if ($чужие.Count -gt 15) { Write-Host "  … и ещё $($чужие.Count - 15)" -ForegroundColor Yellow }
    Write-Host "Если это правки соседней вкладки — так и задумано, коммитить их должна она." -ForegroundColor Yellow
}

# Перенос на машину с 1С идёт через GitHub: без push снимок туда не попадёт.
Write-Host ""
$ветка = (& $git rev-parse --abbrev-ref HEAD).Trim()
& $git push origin $ветка 2>&1 | Write-Host
if ($LASTEXITCODE -eq 0) {
    Write-Host "Отправлено на origin/$ветка — можно делать pull на машине с 1С." -ForegroundColor Green
} else {
    Write-Host "PUSH НЕ ПРОШЁЛ. Снимок есть только локально, на машину с 1С он не попадёт." -ForegroundColor Red
    Write-Host "Разобраться и отправить вручную: git push origin $ветка" -ForegroundColor Red
    exit 1
}
