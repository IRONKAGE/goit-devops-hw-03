#Requires -RunAsAdministrator
#Requires -Version 5.1

# ------------------------------------------
# INFRASTRUCTURE AS CODE (IaC) ANCHOR
# ------------------------------------------
Write-Host "`n==================================================================================" -ForegroundColor Magenta
Write-Host "[MODERN RUNTIME PROVISIONER] Детерміністичне IaC-розгортання для Windows 10/11." -ForegroundColor Magenta
Write-Host "                             Architect: IRONKAGE" -ForegroundColor Magenta
Write-Host "----------------------------------------------------------------------------------" -ForegroundColor Magenta
Write-Host "                             ОС: Win 10 Build 17763+ (v1809) / Win 11 Build 22000+" -ForegroundColor Magenta
Write-Host "                             Стек: Docker Desktop (WSL2), нативний Python (winget)" -ForegroundColor Magenta
Write-Host "                             Гарантує апаратну агностичність (AMD64 / ARM64)." -ForegroundColor Magenta
Write-Host "==================================================================================`n" -ForegroundColor Magenta

# ==========================================
# 0. КОНСТАНТИ ТА ІНІЦІАЛІЗАЦІЯ
# ==========================================
$ErrorActionPreference = "Stop"

Start-Transcript -Path "$PSScriptRoot\setup_modern.log" -Append -Force | Out-Null

$MIN_PYTHON_MAJOR = 3
$MIN_PYTHON_MINOR = 9
$DJANGO_VERSION = "6.0.4"
$VENV_DIR = "ml_venv"
$MIN_DISK_MB = 5120  # 5 GB для WSL2, Docker та образів

function Write-Step { param([string]$Message); Write-Host "`n===> $Message" -ForegroundColor Cyan }
function Write-Success { param([string]$Message); Write-Host "✅ $Message" -ForegroundColor Green }
function Write-ErrorMsg { param([string]$Message); Write-Host "❌ ПОМИЛКА: $Message" -ForegroundColor Red }

# ==========================================
# 1. ПІДГОТОВКА (PRE-FLIGHT & SMART CHECK)
# ==========================================
Write-Step "1. Аналіз системи та апаратного забезпечення..."

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
    Write-ErrorMsg "Мало місця на диску C:! Доступно $freeDiskMB MB, потрібно $MIN_DISK_MB MB."
    Write-Host "Сучасний Docker Desktop та віртуальні машини потребують вільного простору." -ForegroundColor Yellow
    Stop-Transcript | Out-Null; Exit 1
}

# 1.2 ЗАХИСТ ВІД СЕРВЕРІВ (Explicit Server Ban)
$osInfo = Get-CimInstance Win32_OperatingSystem
if ($osInfo.ProductType -ne 1) {
    Write-ErrorMsg "Це серверна ОС. Даний скрипт призначений для десктопних Windows 10/11."
    Write-Host "Будь ласка, використовуйте спеціальний інструмент: install_dev_tools_server.ps1" -ForegroundColor Yellow
    Stop-Transcript | Out-Null; Exit 1
}

# 1.2.1 ЗАХИСТ ВІД WINDOWS S MODE
$skuPolicy = Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\CI\Policy" -Name "SkuPolicyRequired" -ErrorAction SilentlyContinue
if ($null -ne $skuPolicy -and $skuPolicy.SkuPolicyRequired -eq 1) {
    Write-ErrorMsg "Ваша система знаходиться у Windows 10/11 'S Mode' (Безпечний режим)."
    Write-Host "У цьому режимі заблоковано WSL, Docker та будь-який інструментарій розробника." -ForegroundColor Yellow
    Write-Host "Будь ласка, безкоштовно вийдіть з S Mode через Microsoft Store (Шукайте 'Switch out of S mode')." -ForegroundColor Cyan
    Stop-Transcript | Out-Null; Exit 1
}

# 1.3 Перевірка Білда ОС (Мінімум 17763)
$osBuild = [Environment]::OSVersion.Version.Build
if ($osBuild -lt 17763) {
    Write-ErrorMsg "Ваша збірка Windows (Build $osBuild) занадто стара для сучасного MLOps стека."
    Write-Host "Цей скрипт вимагає мінімум Build 17763 (Windows 10 версії 1809)." -ForegroundColor Yellow
    Write-Host "`nДля старих збірок використовуйте скрипт: .\install_dev_tools_legacy.cmd" -ForegroundColor Cyan
    Stop-Transcript | Out-Null; Exit 1
}

# 1.4 Перевірка Архітектури та Терміналу (WOW64)
$arch = $env:PROCESSOR_ARCHITECTURE
if ($arch -eq "x86") {
    if ($env:PROCESSOR_ARCHITEW6432 -eq "AMD64" -or $env:PROCESSOR_ARCHITEW6432 -eq "ARM64") {
        Write-ErrorMsg "Ви запустили 32-бітну версію PowerShell (x86) на 64-бітній ОС!"
        Write-Host "Будь ласка, відкрийте стандартний 64-бітний PowerShell." -ForegroundColor Yellow
    }
    else {
        Write-ErrorMsg "32-бітна архітектура (x86) не підтримується. Вимагається AMD64 або ARM64."
    }
    Stop-Transcript | Out-Null; Exit 1
}
if ($arch -ne "AMD64" -and $arch -ne "ARM64") {
    Write-ErrorMsg "Непідтримувана архітектура: $arch. Вимагається AMD64 або ARM64."
    Stop-Transcript | Out-Null; Exit 1
}

Write-Success "ОС: Десктопна, Build $osBuild | Архітектура: $arch | Диск: $freeDiskMB MB"

# 1.5 Перевірка наявності Winget
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-ErrorMsg "Пакетний менеджер 'winget' не знайдено!"
    Write-Host "Оновіть 'App Installer' (Інсталятор програм) через Microsoft Store." -ForegroundColor Yellow
    Stop-Transcript | Out-Null; Exit 1
}

# 1.6 Smart Check (Швидкий вихід)
$venvPython = "$PSScriptRoot\$VENV_DIR\Scripts\python.exe"
if ((Get-Command docker -ErrorAction SilentlyContinue) -and (Test-Path $venvPython)) {
    $djVerOk = & $venvPython -c "import django; print('1' if django.__version__ == '$DJANGO_VERSION' else '0')" 2>$null
    if ($djVerOk -eq "1") {
        Write-Success "СЕРЕДОВИЩЕ ВЖЕ НАЛАШТОВАНЕ ТА ІЗОЛЬОВАНЕ У '$VENV_DIR'!"
        Write-Host "--------------------------------------------------------"

        # Розумний парсинг версії WSL (захист від спаму меню Help)
        $wslVer = "Не знайдено"
        if (Get-Command wsl -ErrorAction SilentlyContinue) {
            $wslOutput = (wsl --version 2>$null | Select-Object -First 1)
            if ($wslOutput -match "WSL|Windows Subsystem") { $wslVer = $wslOutput.Trim() } else { $wslVer = "Активно (Нативне ядро ОС)" }
        }

        $dockerVer = (docker --version 2>$null | Select-Object -First 1); if (-not $dockerVer) { $dockerVer = "Не знайдено або зупинено" }
        $composeVer = (docker compose version 2>$null | Select-Object -First 1); if (-not $composeVer) { $composeVer = "Не знайдено" }
        $pyVer = (python --version 2>$null | Select-Object -First 1); if (-not $pyVer) { $pyVer = "Не знайдено" }

        Write-Host -NoNewline "🐧 Ядро Linux: "; Write-Host $wslVer -ForegroundColor Yellow
        Write-Host -NoNewline "🐳 Docker Engine: "; Write-Host $dockerVer -ForegroundColor Yellow
        Write-Host -NoNewline "🐙 Docker Compose: "; Write-Host $composeVer -ForegroundColor Yellow
        Write-Host -NoNewline "🐍 Python (Система): "; Write-Host $pyVer -ForegroundColor Yellow
        Write-Host -NoNewline "🌍 Django (у VENV): "; Write-Host (& $venvPython -m django --version 2>$null | Select-Object -First 1) -ForegroundColor Yellow
        Write-Host -NoNewline "📂 Активація: "; Write-Host ".\$VENV_DIR\Scripts\Activate.ps1" -ForegroundColor Cyan
        Write-Host "--------------------------------------------------------"
        Stop-Transcript | Out-Null; Exit 0
    }
}

# ==========================================
# 2. ВСТАНОВЛЕННЯ СИСТЕМНИХ ЗАЛЕЖНОСТЕЙ
# ==========================================
Write-Step "2.1 Аналіз компонентів віртуалізації (WSL2)..."
$needsReboot = $false

# Перевіряємо, чи увімкнені компоненти для WSL2
$wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -ErrorAction SilentlyContinue
$vmpFeature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction SilentlyContinue

if (($wslFeature.State -ne "Enabled") -or ($vmpFeature.State -ne "Enabled")) {
    Write-Host "Увімкнення підсистеми Windows для Linux (WSL) та платформи віртуальних машин..." -ForegroundColor Gray
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -All -NoRestart | Out-Null
    Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All -NoRestart | Out-Null
    $needsReboot = $true
    Write-Success "Компоненти увімкнено."
}
else {
    Write-Success "WSL2/VirtualMachinePlatform вже активні."
}

# Примусово встановлюємо WSL 2 за замовчуванням (якщо користувач колись грався з WSL 1)
if (Get-Command wsl -ErrorAction SilentlyContinue) {
    wsl --set-default-version 2 > $null 2>&1
}

Write-Step "2.2. Налаштування Docker (через winget)..."
if (Get-Command docker -ErrorAction SilentlyContinue) {
    Write-Success "Docker вже встановлено."
}
else {
    Write-Host "Встановлення Docker Desktop..." -ForegroundColor Gray
    winget install -e --id Docker.DockerDesktop --accept-package-agreements --accept-source-agreements --silent
    Write-Success "Docker встановлено."
    $needsReboot = $true
}

# Якщо ми вмикали фічі ОС або ставили Docker на голій системі - пропонуємо керований ребут
if ($needsReboot) {
    Write-Host "`n⚠️ УВАГА: Для завершення налаштування віртуалізації Docker потрібне перезавантаження!" -ForegroundColor Yellow

    $reboot = Read-Host "Бажаєте перезавантажити ПК прямо зараз? (Y/N)"
    if ($reboot -match "^[Yy]$") {
        Write-Host "Перезавантаження системи через 3 секунди..." -ForegroundColor Red
        Start-Sleep -Seconds 3
        Restart-Computer -Force
    }
    else {
        Write-Host "Добре... Після ручного перезавантаження запустіть цей скрипт ще раз для встановлення Python." -ForegroundColor Yellow
        Stop-Transcript | Out-Null; Exit 0
    }
}

# ==========================================
# 3. ВСТАНОВЛЕННЯ PYTHON
# ==========================================
Write-Step "3. Встановлення глобального Python $MIN_PYTHON_MAJOR.$MIN_PYTHON_MINOR+ ..."
$pythonGlobalOk = $false

if (Get-Command python -ErrorAction SilentlyContinue) {
    $verString = (python --version 2>&1) -join " "
    if ($verString -match "(\d+)\.(\d+)") {
        $major = [int]$Matches[1]; $minor = [int]$Matches[2]
        if ($major -eq $MIN_PYTHON_MAJOR -and $minor -ge $MIN_PYTHON_MINOR) { $pythonGlobalOk = $true }
    }
}

if (-not $pythonGlobalOk) {
    Write-Host "Встановлення актуального Python 3 (нативна архітектура)..." -ForegroundColor Gray
    winget install -e --id Python.Python.3 --accept-package-agreements --accept-source-agreements --silent

    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
}
Write-Success "Python рушій готовий."

# ==========================================
# 4. ІЗОЛЯЦІЯ (VIRTUAL ENVIRONMENT)
# ==========================================
Write-Step "4. Створення віртуального середовища ($VENV_DIR)..."
if (-not (Test-Path $VENV_DIR)) {
    python -m venv $VENV_DIR
    Write-Success "Створено venv: $VENV_DIR"
}

& $venvPython -m pip install --upgrade pip --quiet
& $venvPython -m pip install "django==$DJANGO_VERSION" --quiet
Write-Success "Django встановлено в ізольоване середовище."

# ==========================================
# 5. ФІНАЛЬНИЙ ЗВІТ
# ==========================================
Write-Step "✅ СЕРЕДОВИЩЕ УСПІШНО НАЛАШТОВАНО!"
Write-Host "--------------------------------------------------------"

# Розумний парсинг версії WSL (захист від спаму меню Help)
$wslVer = "Не знайдено"
if (Get-Command wsl -ErrorAction SilentlyContinue) {
    $wslOutput = (wsl --version 2>$null | Select-Object -First 1)
    if ($wslOutput -match "WSL|Windows Subsystem") {
        $wslVer = $wslOutput.Trim()
    }
    else {
        $wslVer = "Активно (Нативне ядро ОС)"
    }
}

$dockerVer = (docker --version 2>$null | Select-Object -First 1); if (-not $dockerVer) { $dockerVer = "Не знайдено або зупинено" }
$composeVer = (docker compose version 2>$null | Select-Object -First 1); if (-not $composeVer) { $composeVer = "Не знайдено" }
$pyVer = (python --version 2>$null | Select-Object -First 1); if (-not $pyVer) { $pyVer = "Не знайдено" }
$djVer = (& $venvPython -m django --version 2>$null | Select-Object -First 1); if (-not $djVer) { $djVer = "Не знайдено" }

Write-Host -NoNewline "🐧 Ядро Linux: "; Write-Host $wslVer -ForegroundColor Yellow
Write-Host -NoNewline "🐳 Docker Engine: "; Write-Host $dockerVer -ForegroundColor Yellow
Write-Host -NoNewline "🐙 Docker Compose: "; Write-Host $composeVer -ForegroundColor Yellow
Write-Host -NoNewline "🐍 Python (Система): "; Write-Host $pyVer -ForegroundColor Yellow
Write-Host -NoNewline "🌍 Django (у VENV): "; Write-Host $djVer -ForegroundColor Yellow
Write-Host -NoNewline "📂 Активація: "; Write-Host ".\$VENV_DIR\Scripts\Activate.ps1" -ForegroundColor Cyan
Write-Host "--------------------------------------------------------"

Stop-Transcript | Out-Null
