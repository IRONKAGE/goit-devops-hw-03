#Requires -RunAsAdministrator
#Requires -Version 5.1

# ------------------------------------------
# INFRASTRUCTURE AS CODE (IaC) ANCHOR
# ------------------------------------------
Write-Host "`n========================================================================================" -ForegroundColor Magenta
Write-Host "[ENTERPRISE RUNTIME PROVISIONER] Детерміністичне IaC-розгортання для Windows Server." -ForegroundColor Magenta
Write-Host "                                 Architect: IRONKAGE" -ForegroundColor Magenta
Write-Host "----------------------------------------------------------------------------------------" -ForegroundColor Magenta
Write-Host "                                 ОС: Windows Server 2016 / 2019 / 2022 / 2025+" -ForegroundColor Magenta
Write-Host "                                 Стек: Нативний Docker Engine (LCOW), ізольований Python" -ForegroundColor Magenta
Write-Host "                                 Оптимізовано для серверних ворклоудів (AMD64)." -ForegroundColor Magenta
Write-Host "========================================================================================`n" -ForegroundColor Magenta

# ==========================================
# 0. КОНСТАНТИ ТА ІНІЦІАЛІЗАЦІЯ
# ==========================================
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Start-Transcript -Path "$PSScriptRoot\setup_server.log" -Append -Force | Out-Null

# --------------------------------------------------------------------
# РЕЖИМ КОНТЕЙНЕРІВ (TARGET CONTAINER OS)
# Доступні значення: "Auto", "Windows", "Linux"
# Auto = Windows для Server 2016 / Linux для Server 2019+
# Windows = Використовує Windows контейнери (працює з усіма ОС)
# Linux = Використовує Linux (LCOW) контейнери (працює з Server 2019+)
# --------------------------------------------------------------------
$CONTAINER_OS_PREFERENCE = "Auto"

# ------------------------------------------------------------------
# ENTERPRISE ROUTING TABLE (Матриця версій Python)
# Оновлюйте ці посилання тут, коли тестуєте нові версії для Production
# ------------------------------------------------------------------
$PY_URL_MODERN = "https://www.python.org/ftp/python/3.12.3/python-3.12.3-amd64.exe" # Для Server 2022, 2025 та майбутніх ОС
$PY_URL_2019 = "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe" # Для Server 2019
$PY_URL_2016 = "https://www.python.org/ftp/python/3.10.11/python-3.10.11-amd64.exe" # Для Server 2016

$MIN_PYTHON_MAJOR = 3
$MIN_PYTHON_MINOR = 9
$DJANGO_VERSION = "6.0.4"
$VENV_DIR = "ml_venv"
$MIN_DISK_MB = 10240 # 10 GB для Windows Server та Docker

function Write-Step { param([string]$Message); Write-Host "`n===> $Message" -ForegroundColor Cyan }
function Write-Success { param([string]$Message); Write-Host "✅ $Message" -ForegroundColor Green }
function Write-ErrorMsg { param([string]$Message); Write-Host "❌ ПОМИЛКА: $Message" -ForegroundColor Red }

# ==========================================
# 1. ПІДГОТОВКА (SMART CHECK ТА РОУТИНГ)
# ==========================================
Write-Step "1. Аналіз серверної архітектури..."

# 1.0 Перевірка базової операційної системи (Захист від запуску на Mac/Linux)
if ([System.Environment]::OSVersion.Platform -ne "Win32NT") {
    Write-ErrorMsg "Цей скрипт призначений виключно для операційних систем Windows."
    $currentOS = "Unix-подібній системі"

    if ($null -ne $IsMacOS -and $IsMacOS) { $currentOS = "macOS" }
    elseif ($null -ne $IsLinux -and $IsLinux) { $currentOS = "Linux" }

    Write-Host "Ви намагаєтесь запустити його на ОС: $currentOS (через PowerShell Core)." -ForegroundColor Yellow
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null; Exit 1
}

# 1.1 Перевірка вільного місця на диску C: (10 GB мінімум)
$driveC = Get-Volume -DriveLetter $env:SystemDrive.TrimEnd(':')
$freeDiskMB = [math]::Round($driveC.SizeRemaining / 1MB)
if ($freeDiskMB -lt $MIN_DISK_MB) {
    Write-ErrorMsg "Критично мало місця на диску C:! Доступно $freeDiskMB MB, потрібно мінімум $MIN_DISK_MB MB."
    Write-Host "Базові образи Windows Server Core для Docker займають дуже багато місця." -ForegroundColor Yellow
    Stop-Transcript | Out-Null; Exit 1
}
Write-Success "Диск C: Доступно $freeDiskMB MB"

# 1.2 Перевірка Архітектури та Терміналу
$arch = $env:PROCESSOR_ARCHITECTURE
if ($arch -eq "x86") {
    if ($env:PROCESSOR_ARCHITEW6432 -eq "AMD64") {
        Write-ErrorMsg "Ви запустили 32-бітну версію PowerShell (x86) на 64-бітному сервері!"
        Write-Host "Будь ласка, закрийте це вікно і відкрийте стандартний 64-бітний PowerShell." -ForegroundColor Yellow
    }
    else {
        Write-ErrorMsg "32-бітна архітектура (x86) фізично не підтримується."
    }
    Stop-Transcript | Out-Null; Exit 1
}
if ($arch -ne "AMD64") {
    Write-ErrorMsg "Непідтримувана архітектура: $arch."
    Write-Host "Цей скрипт оптимізовано виключно під AMD64 (x64), оскільки інсталятори Python прив'язані до цієї архітектури." -ForegroundColor Yellow
    Stop-Transcript | Out-Null; Exit 1
}

# 1.3 Перевірка наявності Hyper-V (для LCOW)
$osBuild = [Environment]::OSVersion.Version.Build
if ($osBuild -lt 14393) {
    Write-ErrorMsg "Ця ОС занадто стара (Build $osBuild). Вимагається мінімум Server 2016 (14393)."
    Stop-Transcript | Out-Null; Exit 1
}

# 1.4 Визначення фінальної ОС для контейнерів
$TARGET_OS = $CONTAINER_OS_PREFERENCE
if ($CONTAINER_OS_PREFERENCE -eq "Auto") {
    if ($osBuild -lt 17763) { $TARGET_OS = "Windows" } else { $TARGET_OS = "Linux" }
}

if ($TARGET_OS -eq "Linux" -and $osBuild -lt 17763) {
    Write-ErrorMsg "Linux-контейнери не підтримуються нативною службою Server 2016."
    Write-Host "Змініть `$CONTAINER_OS_PREFERENCE на 'Windows' або оновіть сервер до 2019+." -ForegroundColor Yellow
    Stop-Transcript | Out-Null; Exit 1
}

Write-Success "ОС: Build $osBuild | Цільові контейнери: $TARGET_OS"

# 1.5 Smart Check
$venvPython = "$PSScriptRoot\$VENV_DIR\Scripts\python.exe"
if ((Get-Service -Name docker -ErrorAction SilentlyContinue) -and (Test-Path $venvPython)) {
    $djVerOk = & $venvPython -c "import django; print('1' if django.__version__ == '$DJANGO_VERSION' else '0')" 2>$null
    if ($djVerOk -eq "1") {
        Write-Success "СЕРЕДОВИЩЕ ВЖЕ НАЛАШТОВАНЕ ТА ІЗОЛЬОВАНЕ У '$VENV_DIR'!"
        Write-Host "--------------------------------------------------------"
        Write-Host -NoNewline "🐳 Docker Engine: "; Write-Host (docker --version) -ForegroundColor Yellow

        $compVer = (docker compose version 2>$null); if (-not $compVer) { $compVer = "Не знайдено" }
        Write-Host -NoNewline "🐙 Docker Compose: "; Write-Host $compVer -ForegroundColor Yellow

        Write-Host -NoNewline "🐍 Python (Система): "; Write-Host (python --version) -ForegroundColor Yellow
        Write-Host -NoNewline "🌍 Django (у VENV): "; Write-Host (& $venvPython -m django --version) -ForegroundColor Yellow
        Write-Host -NoNewline "📂 Активація: "; Write-Host ".\$VENV_DIR\Scripts\Activate.ps1" -ForegroundColor Cyan
        Write-Host "--------------------------------------------------------"
        Stop-Transcript | Out-Null; Exit 0
    }
}

# ==========================================
# 2. ВСТАНОВЛЕННЯ СИСТЕМНИХ ЗАЛЕЖНОСТЕЙ
# ==========================================
Write-Step "2. Встановлення нативної служби Docker Engine..."
$needsReboot = $false

if (Get-Service -Name docker -ErrorAction SilentlyContinue) {
    Write-Success "Службу Docker вже встановлено."
}
else {
    Write-Host "Завантаження DockerMsftProvider..." -ForegroundColor Gray
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
    Install-Module -Name DockerMsftProvider -Repository PSGallery -Force | Out-Null
    Install-Package -Name docker -ProviderName DockerMsftProvider -Force | Out-Null
    Write-Success "Docker Engine базово встановлено."
    $needsReboot = $true
}

# Налаштування Linux Containers (LCOW) для Server 2019+
if ($TARGET_OS -eq "Linux") {
    Write-Step "2.1 Налаштування Linux Containers on Windows (LCOW)..."

    $hvFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -ErrorAction SilentlyContinue
    if ($null -ne $hvFeature -and $hvFeature.State -ne "Enabled") {
        Write-Host "Увімкнення ролі Hyper-V (необхідно для Linux ядра)..." -ForegroundColor Gray
        Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All -NoRestart | Out-Null
        $needsReboot = $true
    }

    # Прописуємо LCOW_SUPPORTED
    if ([Environment]::GetEnvironmentVariable("LCOW_SUPPORTED", "Machine") -ne "1") {
        [Environment]::SetEnvironmentVariable("LCOW_SUPPORTED", "1", "Machine")
        Write-Success "Змінну середовища LCOW_SUPPORTED встановлено."
    }

    # Налаштовуємо daemon.json
    $dockerConfigPath = "$env:ProgramData\docker\config"
    if (-not (Test-Path $dockerConfigPath)) { New-Item -ItemType Directory -Path $dockerConfigPath -Force | Out-Null }

    $daemonJsonPath = "$dockerConfigPath\daemon.json"
    $daemonConfig = @{}
    if (Test-Path $daemonJsonPath) {
        try { $daemonConfig = Get-Content $daemonJsonPath -Raw | ConvertFrom-Json -AsHashtable } catch {}
    }

    if ($daemonConfig["experimental"] -ne $true) {
        $daemonConfig["experimental"] = $true
        $daemonConfig | ConvertTo-Json -Depth 10 | Set-Content $daemonJsonPath
        Write-Success "Docker daemon переведено в Experimental режим (LCOW)."
        if (Get-Service -Name docker -ErrorAction SilentlyContinue) { Restart-Service docker -Force }
    }
    else {
        Write-Success "Docker daemon вже налаштовано на LCOW."
    }
}

if ($needsReboot) {
    Write-Host "`n⚠️ УВАГА: Для запуску служби Docker та Hyper-V потрібне перезавантаження сервера!" -ForegroundColor Yellow
    Write-Host "Після ребуту запустіть цей скрипт ще раз для встановлення Python." -ForegroundColor Yellow
    Stop-Transcript | Out-Null; Exit 0
}

Write-Step "2.2 Встановлення Docker Compose (v2)..."
$composeDir = "$env:ProgramFiles\Docker\cli-plugins"
if (-not (Test-Path $composeDir)) { New-Item -ItemType Directory -Path $composeDir -Force | Out-Null }

$composePath = "$composeDir\docker-compose.exe"
if (-not (Test-Path $composePath)) {
    Write-Host "Завантаження останньої версії Docker Compose з GitHub..." -ForegroundColor Gray
    $composeUrl = "https://github.com/docker/compose/releases/latest/download/docker-compose-windows-x86_64.exe"
    Invoke-WebRequest -Uri $composeUrl -OutFile $composePath
    Write-Success "Docker Compose встановлено як плагін."
}
else {
    Write-Success "Docker Compose вже присутній."
}

# ==========================================
# 3. ВСТАНОВЛЕННЯ PYTHON
# ==========================================
Write-Step "3. Перевірка та встановлення глобального Python $MIN_PYTHON_MAJOR.$MIN_PYTHON_MINOR+ ..."
$pythonGlobalOk = $false

# 3.1 Перевірка наявної версії Python
if (Get-Command python -ErrorAction SilentlyContinue) {
    $verString = (python --version 2>&1) -join " "
    if ($verString -match "(\d+)\.(\d+)") {
        $major = [int]$Matches[1]; $minor = [int]$Matches[2]
        if ($major -eq $MIN_PYTHON_MAJOR -and $minor -ge $MIN_PYTHON_MINOR) {
            $pythonGlobalOk = $true
            Write-Success "Знайдено сумісну версію: $verString"
        }
        else {
            Write-Host "Знайдено застарілу версію: $verString (Потрібно $MIN_PYTHON_MAJOR.$MIN_PYTHON_MINOR+)" -ForegroundColor Yellow
        }
    }
}

# 3.2 Динамічне визначення оптимальної версії Python для поточного сервера
if (-not $pythonGlobalOk) {
    Write-Host "Визначення оптимальної версії Python для вашої ОС (Build $osBuild)..." -ForegroundColor Gray

    $dynamicPythonUrl = ""
    $osTargetLabel = ""
    if ($osBuild -ge 20348) {
        # Server 2022 / 2025 / Будь-які нові майбутні ОС
        $dynamicPythonUrl = $PY_URL_MODERN
        $osTargetLabel = "Server 2022 / 2025+"
    }
    elseif ($osBuild -ge 17763) {
        # Server 2019
        $dynamicPythonUrl = $PY_URL_2019
        $osTargetLabel = "Server 2019"
    }
    else {
        # Server 2016
        $dynamicPythonUrl = $PY_URL_2016
        $osTargetLabel = "Server 2016"
    }

    $parsedVer = "Невідомо"
    if ($dynamicPythonUrl -match "python-(\d+\.\d+\.\d+)") {
        $parsedVer = $Matches[1]
    }

    Write-Host "Обрано: Python $parsedVer ($osTargetLabel)" -ForegroundColor Cyan
    Write-Host "Завантаження інсталятора..." -ForegroundColor Gray
    Invoke-WebRequest -Uri $dynamicPythonUrl -OutFile "python_installer.exe"

    Write-Host "Тихе встановлення для всіх користувачів (AllUsers)..." -ForegroundColor Gray
    Start-Process -FilePath ".\python_installer.exe" -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 Include_test=0" -Wait
    Remove-Item -Path ".\python_installer.exe" -Force

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
Write-Success "Django встановлено."

# ==========================================
# 5. ФІНАЛЬНИЙ ЗВІТ
# ==========================================
Write-Step "✅ СЕРВЕРНЕ СЕРЕДОВИЩЕ УСПІШНО НАЛАШТОВАНО!"
Write-Host "--------------------------------------------------------"
$dockerVer = (docker --version 2>$null | Select-Object -First 1); if (-not $dockerVer) { $dockerVer = "Не знайдено" }
$composeVer = (docker compose version 2>$null | Select-Object -First 1); if (-not $composeVer) { $composeVer = "Не знайдено" }
$pyVer = (python --version 2>$null | Select-Object -First 1); if (-not $pyVer) { $pyVer = "Не знайдено" }

Write-Host -NoNewline "🐳 Docker Engine: "; Write-Host "$dockerVer (Image Target: $TARGET_OS)" -ForegroundColor Yellow
Write-Host -NoNewline "🐙 Docker Compose: "; Write-Host $composeVer -ForegroundColor Yellow
Write-Host -NoNewline "🐍 Python (Система): "; Write-Host $pyVer -ForegroundColor Yellow
Write-Host -NoNewline "🌍 Django (у VENV): "; Write-Host (& $venvPython -m django --version 2>$null) -ForegroundColor Yellow
Write-Host -NoNewline "📂 Активація: "; Write-Host ".\$VENV_DIR\Scripts\Activate.ps1" -ForegroundColor Cyan
Write-Host "--------------------------------------------------------"

Stop-Transcript | Out-Null
