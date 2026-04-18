#Requires -RunAsAdministrator
#Requires -Version 5.1

# ------------------------------------------
# INFRASTRUCTURE AS CODE (IaC) ANCHOR
# ------------------------------------------
Write-Host "`n===============================================================================================" -ForegroundColor Magenta
Write-Host "[BRIDGE RUNTIME PROVISIONER] Детерміністичне IaC-розгортання для Windows 10 через WSL 1 Bridge." -ForegroundColor Magenta
Write-Host "                             Architect: IRONKAGE" -ForegroundColor Magenta
Write-Host "-----------------------------------------------------------------------------------------------" -ForegroundColor Magenta
Write-Host "                             ОС: Windows 10 Build 15063 - 17762 (Перехідні збірки)" -ForegroundColor Magenta
Write-Host "                             Стек: Ubuntu 20.04 LTS, Docker CLI (TCP-Міст), Python" -ForegroundColor Magenta
Write-Host "                             Гарантує роботу ML-середовища без VirtualBox (AMD64)." -ForegroundColor Magenta
Write-Host "===============================================================================================`n" -ForegroundColor Magenta

# ==========================================
# 0. КОНСТАНТИ ТА ІНІЦІАЛІЗАЦІЯ
# ==========================================
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Start-Transcript -Path "$PSScriptRoot\setup_wsl1_bridge.log" -Append -Force | Out-Null

$DJANGO_VERSION = "6.0.4"
$VENV_DIR = "ml_venv"
$UBUNTU_APPX_URL = "https://aka.ms/wslubuntu2004"  # Стабільна Ubuntu 20.04 LTS для WSL 1
$UBUNTU_FILE = "Ubuntu2004.appx"
$MIN_DISK_MB = 5120  # 5 GB для WSL, Ubuntu та пакетів

function Write-Step { param([string]$Message); Write-Host "`n===> $Message" -ForegroundColor Cyan }
function Write-Success { param([string]$Message); Write-Host "✅ $Message" -ForegroundColor Green }
function Write-ErrorMsg { param([string]$Message); Write-Host "❌ ПОМИЛКА: $Message" -ForegroundColor Red }

# ==========================================
# 1. ПІДГОТОВКА (PRE-FLIGHT & SMART CHECK)
# ==========================================
Write-Step "1. Аналіз системи та архітектури..."

# 1.0 Перевірка базової операційної системи (Захист від запуску на Mac/Linux)
if ([System.Environment]::OSVersion.Platform -ne "Win32NT") {
    Write-ErrorMsg "Цей скрипт призначений виключно для операційних систем Windows."
    $currentOS = "Unix-подібній системі"

    if ($null -ne $IsMacOS -and $IsMacOS) { $currentOS = "macOS" }
    elseif ($null -ne $IsLinux -and $IsLinux) { $currentOS = "Linux" }

    Write-Host "Ви намагаєтесь запустити його на ОС: $currentOS (через PowerShell Core)." -ForegroundColor Yellow
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null; Exit 1
}

# 1.1 Перевірка вільного місця на диску C:
$driveC = Get-Volume -DriveLetter $env:SystemDrive.TrimEnd(':')
$freeDiskMB = [math]::Round($driveC.SizeRemaining / 1MB)
if ($freeDiskMB -lt $MIN_DISK_MB) {
    Write-ErrorMsg "Мало місця на диску C:! Доступно $freeDiskMB MB, потрібно щонайменше $MIN_DISK_MB MB."
    Write-Host "WSL підсистема та образ Ubuntu потребують значного дискового простору." -ForegroundColor Yellow
    Stop-Transcript | Out-Null; Exit 1
}

$osBuild = [Environment]::OSVersion.Version.Build
$arch = $env:PROCESSOR_ARCHITECTURE

# 1.2 Перевірка Архітектури та Терміналу (WOW64)
if ($arch -eq "x86") {
    if ($env:PROCESSOR_ARCHITEW6432 -eq "AMD64") {
        Write-ErrorMsg "Ви запустили 32-бітну версію PowerShell (x86) на 64-бітній ОС!"
        Write-Host "Для роботи з WSL потрібен стандартний 64-бітний PowerShell." -ForegroundColor Yellow
    }
    else {
        Write-ErrorMsg "32-бітна архітектура (x86) фізично не підтримується."
    }
    Stop-Transcript | Out-Null; Exit 1
}
if ($arch -ne "AMD64") {
    Write-ErrorMsg "Непідтримувана архітектура: $arch. Вимагається AMD64 (x64)."
    Stop-Transcript | Out-Null; Exit 1
}

# 1.3 ЗАХИСТ ВІД СЕРВЕРІВ (Explicit Server Ban)
$osInfo = Get-CimInstance Win32_OperatingSystem
if ($osInfo.ProductType -ne 1) {
    Write-ErrorMsg "Це серверна ОС. Міст WSL 1 призначений виключно для десктопних Windows 10."
    Write-Host "Будь ласка, використовуйте спеціальний інструмент: install_dev_tools_server.ps1" -ForegroundColor Yellow
    Stop-Transcript | Out-Null; Exit 1
}

# 1.4 Перевірка версії Windows 10 (Bridge Window)
if ($osBuild -lt 15063) {
    Write-ErrorMsg "Ця ОС занадто стара (Build $osBuild). Підсистема WSL 1 відсутня."
    Write-Host "Використовуйте install_dev_tools_legacy.cmd" -ForegroundColor Yellow
    Stop-Transcript | Out-Null; Exit 1
}

if ($osBuild -ge 17763) {
    Write-ErrorMsg "Це сучасна ОС (Build $osBuild). Вам не потрібен міст WSL 1."
    Write-Host "Використовуйте сучасний install_dev_tools.cmd або .ps1" -ForegroundColor Yellow
    Stop-Transcript | Out-Null; Exit 1
}

Write-Success "ОС: Десктопна, Build $osBuild (Bridge Mode) | Архітектура: $arch | Диск: $freeDiskMB MB"

# 1.5 Smart Check для WSL 1
$wslInstalled = (wsl -l -q 2>$null) -match "Ubuntu"
$venvExists = (wsl -- bash -c "[ -f $VENV_DIR/bin/python3 ] && echo '1' || echo '0'" 2>$null)
if ($wslInstalled -and ($venvExists -eq "1")) {
    Write-Success "СЕРЕДОВИЩЕ ВЖЕ НАЛАШТОВАНЕ В UBUNTU!"
    Write-Host "--------------------------------------------------------"
    Write-Host -NoNewline "🐧 ОС Контейнерів: "; Write-Host "Ubuntu 20.04 LTS (WSL 1)" -ForegroundColor Yellow
    Write-Host -NoNewline "🐳 Docker CLI: "; Write-Host (wsl -- bash -c "docker --version 2>/dev/null") -ForegroundColor Yellow
    Write-Host -NoNewline "🐙 Docker Compose: "; Write-Host (wsl -- bash -c "docker-compose --version 2>/dev/null") -ForegroundColor Yellow
    Write-Host -NoNewline "🐍 Python (у Linux): "; Write-Host (wsl -- bash -c "source $VENV_DIR/bin/activate && python3 --version 2>/dev/null") -ForegroundColor Yellow
    Write-Host -NoNewline "🌍 Django (у VENV): "; Write-Host (wsl -- bash -c "source $VENV_DIR/bin/activate && python3 -m django --version 2>/dev/null") -ForegroundColor Yellow
    Write-Host -NoNewline "📂 Активація: "; Write-Host "wsl" -ForegroundColor Cyan
    Write-Host "              source ./$VENV_DIR/bin/activate" -ForegroundColor Cyan
    Write-Host "--------------------------------------------------------"
    Stop-Transcript | Out-Null; Exit 0
}

# ==========================================
# 2. ВСТАНОВЛЕННЯ СИСТЕМНИХ ЗАЛЕЖНОСТЕЙ
# ==========================================
Write-Step "2. Налаштування підсистеми WSL 1 та Ubuntu..."
$wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -ErrorAction SilentlyContinue
if ($wslFeature.State -ne "Enabled") {
    Write-Host "Увімкнення WSL 1..." -ForegroundColor Gray
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -All -NoRestart | Out-Null

    Write-Host "`n⚠️ УВАГА: Для запуску ядра WSL потрібне перезавантаження ПК!" -ForegroundColor Yellow

    $reboot = Read-Host "Бажаєте перезавантажити ПК прямо зараз? (Y/N)"
    if ($reboot -match "^[Yy]$") {
        Write-Host "Перезавантаження системи через 3 секунди..." -ForegroundColor Red
        Start-Sleep -Seconds 3
        Restart-Computer -Force
    }
    else {
        Write-Host "Добре... Після ручного перезавантаження запустіть цей скрипт ще раз." -ForegroundColor Yellow
        Stop-Transcript | Out-Null; Exit 0
    }
}
Write-Success "Підсистема WSL 1 активна."

if (-not $wslInstalled) {
    Write-Host "Завантаження Ubuntu 20.04 LTS (Близько 500 МБ)... Це може зайняти кілька хвилин." -ForegroundColor Gray
    if (-not (Test-Path $UBUNTU_FILE)) {
        $ProgressPreference = 'SilentlyContinue' # Прискорюємо завантаження у 10 разів, завдяки вимкненню графічного прогрес-бара PowerShell
        Invoke-WebRequest -Uri $UBUNTU_APPX_URL -OutFile $UBUNTU_FILE
        $ProgressPreference = 'Continue'
    }

    Write-Host "Встановлення Ubuntu Appx..." -ForegroundColor Gray
    Add-AppxPackage -Path .\$UBUNTU_FILE
    Write-Success "Ubuntu 20.04 встановлено."

    Write-Host "`n⚠️ ДІЯ ДЛЯ КОРИСТУВАЧА:" -ForegroundColor Yellow
    Write-Host "1. Відкрийте меню 'Пуск' та запустіть 'Ubuntu 20.04 LTS'."
    Write-Host "2. Створіть свій UNIX логін та пароль."
    Write-Host "3. Закрийте вікно Ubuntu і запустіть цей скрипт втретє."
    Stop-Transcript | Out-Null; Exit 0
}
Write-Success "Дистрибутив Ubuntu готовий."

# ==========================================
# 3. ВСТАНОВЛЕННЯ PYTHON
# ==========================================
Write-Step "3. Встановлення Python, Docker CLI та Compose в Linux..."

Write-Host "Оновлення apt та встановлення пакетів..." -ForegroundColor Gray
wsl -u root -- bash -c "apt-get update -y -q && apt-get install -y -q python3 python3-venv docker.io docker-compose"

Write-Host "Налаштування TCP-мосту до Windows Docker Daemon..." -ForegroundColor Gray
wsl -- bash -c "grep -q 'DOCKER_HOST' ~/.bashrc || echo 'export DOCKER_HOST=tcp://localhost:2375' >> ~/.bashrc"
wsl -- bash -c "grep -q 'DOCKER_CLI_BUILD' ~/.bashrc || echo 'export DOCKER_CLI_BUILD=1' >> ~/.bashrc"

Write-Host "Виправлення томів Docker (Volume Mount Fix) у /etc/wsl.conf..." -ForegroundColor Gray
$wslConf = "[automount]`nroot = /`noptions = `"metadata`""
wsl -u root -- bash -c "echo '$wslConf' > /etc/wsl.conf"

Write-Success "Клієнтські інструменти готові."

# ==========================================
# 4. ІЗОЛЯЦІЯ (VIRTUAL ENVIRONMENT)
# ==========================================
Write-Step "4. Створення віртуального середовища ($VENV_DIR)..."

wsl -- bash -c "python3 -m venv $VENV_DIR"
wsl -- bash -c "source $VENV_DIR/bin/activate && pip install --upgrade pip -q && pip install django==$DJANGO_VERSION -q"

Write-Success "Django встановлено в ізольоване середовище Ubuntu."

# ==========================================
# 5. ФІНАЛЬНИЙ ЗВІТ
# ==========================================
Write-Step "✅ СЕРЕДОВИЩЕ WSL 1 УСПІШНО НАЛАШТОВАНО!"
Write-Host "--------------------------------------------------------"
$pyVer = (wsl -- bash -c "source $VENV_DIR/bin/activate && python3 --version 2>/dev/null")
$djVer = (wsl -- bash -c "source $VENV_DIR/bin/activate && python3 -m django --version 2>/dev/null")
$docCliVer = (wsl -- bash -c "docker --version 2>/dev/null")
$compCliVer = (wsl -- bash -c "docker-compose --version 2>/dev/null")

Write-Host -NoNewline "🐧 ОС Контейнерів: "; Write-Host "Ubuntu 20.04 LTS (WSL 1)" -ForegroundColor Yellow
Write-Host -NoNewline "🐳 Docker CLI: "; Write-Host $docCliVer -ForegroundColor Yellow
Write-Host -NoNewline "🐙 Docker Compose: "; Write-Host $compCliVer -ForegroundColor Yellow
Write-Host -NoNewline "🐍 Python (у Linux): "; Write-Host $pyVer -ForegroundColor Yellow
Write-Host -NoNewline "🌍 Django (у VENV): "; Write-Host $djVer -ForegroundColor Yellow
Write-Host -NoNewline "📂 Активація: "; Write-Host "source ./$VENV_DIR/bin/activate" -ForegroundColor Cyan
Write-Host "--------------------------------------------------------"
Write-Host "⚠️ ДЛЯ РОБОТИ DOCKER ВІДКРИЙТЕ DOCKER DESKTOP (WINDOWS):" -ForegroundColor Red
Write-Host "   General -> Увімкніть 'Expose daemon on tcp://localhost:2375'"
Write-Host "--------------------------------------------------------"

Stop-Transcript | Out-Null
