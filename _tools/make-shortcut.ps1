# Кладёт на Рабочий стол ярлык «Обновить базу из GitHub» → _tools\update-base.cmd.
# Запускать один раз:
#   powershell -NoProfile -ExecutionPolicy Bypass -File _tools\make-shortcut.ps1
#
# Ключом -Имя можно сделать второй ярлык под другой режим, например:
#   ... -File _tools\make-shortcut.ps1 -Имя "Обновить базу без .cf" -Аргументы "-ТолькоЗагрузить"

param(
    [string]$Имя = "Обновить базу из GitHub",
    [string]$Аргументы = ""
)

$ErrorActionPreference = "Stop"

$цель = Join-Path $PSScriptRoot "update-base.cmd"
if (-not (Test-Path $цель)) {
    Write-Host "Не найден $цель — сделайте git pull." -ForegroundColor Red
    exit 1
}

$ярлык = Join-Path ([Environment]::GetFolderPath("Desktop")) "$Имя.lnk"

$shell = New-Object -ComObject WScript.Shell
$л = $shell.CreateShortcut($ярлык)
$л.TargetPath       = $цель
$л.Arguments        = $Аргументы
$л.WorkingDirectory = (Split-Path -Parent $PSScriptRoot)
$л.Description      = "git pull, загрузка конфигурации в базу, выгрузка .cf на Рабочий стол"

# Иконка 1С, если платформа на месте — чтобы ярлык не выглядел как чёрное окно cmd.
$иконка = Get-ChildItem "$env:ProgramFiles\1cv8" -Directory -ErrorAction SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName "bin\1cv8.exe") } |
    Sort-Object { try { [version]$_.Name } catch { [version]"0.0" } } |
    Select-Object -Last 1
if ($иконка) { $л.IconLocation = (Join-Path $иконка.FullName "bin\1cv8.exe") + ",0" }

$л.Save()

Write-Host "Ярлык создан: $ярлык" -ForegroundColor Green
Write-Host "Запуск — двойной щелчок. Окно останется открытым до нажатия клавиши." -ForegroundColor Green
