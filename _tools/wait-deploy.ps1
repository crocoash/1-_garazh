# Ожидание одной заливки по требованию. Запускать НА МАШИНЕ С 1С.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File _tools\wait-deploy.ps1
#
# Зачем: между правкой и базой стоят два шага — push отсюда и pull там, — а на
# машину с 1С попадает только пользователь. Это окно открывается на время работы
# и ловит коммиты с меткой [deploy] в начале сообщения, загружая их в ТЕСТОВУЮ
# базу. Метку ставит Claude и только тогда, когда вы сказали «залей», — сами по
# себе правки в базу не едут. Фонового цикла нет: окно закрыто — ничего не
# происходит, автозапуска у скрипта нет.
#
# Что делает, поймав метку:
#   1. update-base.ps1 — pull, проверка штрихкодов, загрузка из файлов,
#      обновление конфигурации БД, выгрузка .cf на Рабочий стол;
#   2. кладёт весь вывод в _tools/deploy-result.log и пушит его в GitHub,
#      чтобы результат было видно с другой машины.
#
# Рабочую базу НЕ трогает никогда: объединение .cf с рабочей базой остаётся
# ручным шагом через «Обновить базу.cmd».
#
# Ключи:
#   -ОдинРаз         выйти после первой же заливки (по умолчанию окно работает,
#                    пока его не закрыли, и ловит сколько угодно меток подряд)
#   -Минут <N>       ограничить время работы; 0 — без ограничения (по умолчанию)
#   -Секунд <N>      как часто спрашивать GitHub, по умолчанию 20
#   -БезОбновленияБД только загрузить конфигурацию из файлов, без /UpdateDBCfg
#                    (не потребует монопольного доступа, но правка не заработает,
#                    пока обновление БД не примут руками)

param(
    [switch]$ОдинРаз,
    [int]$Минут  = 0,
    [int]$Секунд = 20,
    [switch]$БезОбновленияБД
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

# Git ищем так же, как в update-base.ps1: в PATH его на этой машине нет,
# он приезжает вместе с клиентом Fork, и в пути стоит номер версии.
function НайтиGit {

    $варианты = @(
        "$env:ProgramFiles\Git\cmd\git.exe"
        "${env:ProgramFiles(x86)}\Git\cmd\git.exe"
    )
    foreach ($путь in $варианты) {
        if ($путь -and (Test-Path $путь)) { return $путь }
    }

    if ($env:LOCALAPPDATA) {
        $fork = Join-Path $env:LOCALAPPDATA "Fork\gitInstance"
        if (Test-Path $fork) {
            $свежий = Get-ChildItem $fork -Directory -ErrorAction SilentlyContinue |
                Where-Object { Test-Path (Join-Path $_.FullName "cmd\git.exe") } |
                Sort-Object { try { [version]$_.Name } catch { [version]"0.0" } } |
                Select-Object -Last 1
            if ($свежий) { return (Join-Path $свежий.FullName "cmd\git.exe") }
        }
    }

    if (Get-Command git -ErrorAction SilentlyContinue) { return "git" }
    return $null
}

$git = НайтиGit
if (-not $git) {
    Write-Host "Не найден git. Установить: https://git-scm.com/download/win" -ForegroundColor Red
    exit 1
}

# git пишет нормальный вывод в stderr; под Windows PowerShell при
# $ErrorActionPreference = "Stop" это роняет скрипт на успешной команде.
function ГитТихо {
    $прежний = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $вывод = & $git @args 2>&1
        return ($вывод | Out-String)
    } finally {
        $ErrorActionPreference = $прежний
    }
}

$шелл = (Get-Process -Id $PID).Path
if (-not $шелл) { $шелл = "powershell" }

$ФайлРезультата = Join-Path $PSScriptRoot "deploy-result.log"
$Метка = "[deploy]"

function Сообщение($sha) {
    $текст = & $git log -1 --format=%s $sha 2>$null
    if (-not $текст) { return "" }
    return ($текст | Out-String).Trim()
}

Write-Host ""
Write-Host "Ожидание заливки по метке $Метка" -ForegroundColor Cyan
Write-Host "База: тестовая (из настроек update-base.ps1). Рабочая база не трогается." -ForegroundColor DarkGray
$сколько = if ($Минут -gt 0) { "не дольше $Минут мин" } else { "пока окно открыто" }
Write-Host "Опрос GitHub раз в $Секунд с, $сколько. Закрыть окно — прекратить ожидание." -ForegroundColor DarkGray
Write-Host ""

# Точка отсчёта: всё, что уже лежит на origin/main, заливкой не считаем —
# иначе окно поймало бы старую метку и залило вчерашний коммит.
ГитТихо fetch --quiet origin main | Out-Null
$последний = (& $git rev-parse origin/main).Trim()
Write-Host "Текущий origin/main: $($последний.Substring(0,9))  $(Сообщение $последний)" -ForegroundColor DarkGray

$дедлайн = if ($Минут -gt 0) { (Get-Date).AddMinutes($Минут) } else { [datetime]::MaxValue }
$заливокСделано = 0

while ((Get-Date) -lt $дедлайн) {

    Start-Sleep -Seconds $Секунд

    ГитТихо fetch --quiet origin main | Out-Null
    $сейчас = (& $git rev-parse origin/main).Trim()

    if ($сейчас -eq $последний) { continue }

    $тема = Сообщение $сейчас
    $последний = $сейчас

    if (-not $тема.StartsWith($Метка)) {
        Write-Host "Новый коммит без метки — пропускаю: $тема" -ForegroundColor DarkGray
        continue
    }

    Write-Host ""
    Write-Host "== Поймана метка: $тема" -ForegroundColor Cyan
    Write-Host ""

    $аргументы = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "update-base.ps1"))
    if ($БезОбновленияБД) { $аргументы += "-ТолькоЗагрузить" }

    $началось = Get-Date
    # Вывод нужен и на экране, и в файле: файл уезжает в GitHub как отчёт.
    $вывод = & $шелл @аргументы 2>&1 | ForEach-Object { Write-Host $_; $_ }
    $кодВозврата = $LASTEXITCODE

    $итог = if ($кодВозврата -eq 0) { "УСПЕХ" } else { "ОШИБКА (код $кодВозврата)" }

    $отчёт = @()
    $отчёт += "Заливка $итог"
    $отчёт += "Коммит:  $($сейчас.Substring(0,9))  $тема"
    $отчёт += "Начало:  $($началось.ToString('yyyy-MM-dd HH:mm:ss'))"
    $отчёт += "Конец:   $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))"
    $отчёт += "Машина:  $env:COMPUTERNAME"
    $отчёт += ""
    $отчёт += ($вывод | Out-String)

    [System.IO.File]::WriteAllText($ФайлРезультата, ($отчёт -join [Environment]::NewLine), (New-Object System.Text.UTF8Encoding $true))

    # Отчёт кладём в git, иначе результат заливки виден только в этом окне.
    # -f потому, что /_tools/* под .gitignore, а исключение сделано только
    # для скриптов, которые должны ехать на эту машину.
    ГитТихо add -f -- $ФайлРезультата | Out-Null
    ГитТихо commit -m "Результат заливки: $итог" -- $ФайлРезультата | Out-Null
    $пуш = ГитТихо push origin main
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Отчёт закоммичен, но push не прошёл:" -ForegroundColor Yellow
        Write-Host $пуш -ForegroundColor Yellow
    } else {
        Write-Host ""
        Write-Host "Отчёт отправлен в GitHub: _tools/deploy-result.log" -ForegroundColor DarkGray
        # После своего push origin/main ушёл вперёд — иначе следующий круг
        # принял бы собственный коммит с отчётом за новую метку.
        ГитТихо fetch --quiet origin main | Out-Null
        $последний = (& $git rev-parse origin/main).Trim()
    }

    Write-Host ""
    Write-Host "== $итог" -ForegroundColor $(if ($кодВозврата -eq 0) { "Green" } else { "Red" })

    $заливокСделано++

    if ($ОдинРаз) {
        Write-Host ""
        Write-Host "Заливка выполнена, ожидание закончено (ключ -ОдинРаз)." -ForegroundColor Cyan
        exit $кодВозврата
    }

    Write-Host ""
    Write-Host "Жду следующую метку. Закрыть окно — прекратить." -ForegroundColor Cyan
    if ($Минут -gt 0) { $дедлайн = (Get-Date).AddMinutes($Минут) }
}

Write-Host ""
if ($заливокСделано -eq 0) {
    Write-Host "Время вышло, метки $Метка не было — ничего не заливалось." -ForegroundColor Yellow
} else {
    Write-Host "Время ожидания вышло. Заливок сделано: $заливокСделано." -ForegroundColor Cyan
}
exit 0
