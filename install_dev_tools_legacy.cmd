@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul

:: ------------------------------------------
:: INFRASTRUCTURE AS CODE (IaC) ANCHOR
:: ------------------------------------------
echo.
echo ====================================================================================================
echo [LEGACY RUNTIME PROVISIONER] Deterministic IaC Deployment for Windows Legacy/Bridge.
echo                              Architect: IRONKAGE
echo ----------------------------------------------------------------------------------------------------
echo                              OS: Windows Vista SP2, 7, 8.1, 10 (up to Build 17762), Server 2008/2012
echo                              Stack: Docker Toolbox (VirtualBox), Custom Python Backport
echo                              Guarantees compatibility with NT 6.0 - 6.3 kernels (AMD64).
echo.
echo                              ^>^> NOTE: For modern Windows 10/11, use install_dev_tools.ps1
echo ====================================================================================================
echo.

:: ==========================================
:: 0. КОНСТАНТИ ТА ІНІЦІАЛІЗАЦІЯ
:: ==========================================
set "DJANGO_VERSION=6.0.4"
set "VENV_DIR=ml_venv"

:: 5 GB мінімум для Docker Toolbox VM + Python + VENV
set "MIN_DISK_GB=5"
set "MIN_DISK_BYTES=5368709120"

set "DOCKER_TOOLBOX_URL=https://github.com/docker/toolbox/releases/download/v19.03.1/DockerToolbox-19.03.1.exe"
set "PYTHON_BACKPORT_URL=https://github.com/vladimir-andreevich/cpython-windows-vista-and-7/releases/download/v3.9.13/python-3.9.13-amd64.zip"
set "PYTHON_OFFICIAL_URL=https://www.python.org/ftp/python/3.9.13/python-3.9.13-amd64.exe"

:: Магія TLS 1.2 для старого PowerShell 2.0 (Код 3072 = Tls12)
set "PS_TLS_HACK=[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]3072;"

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [ERROR] CRITICAL: Run this script as Administrator!
    pause
    exit /b 1
)

:: ==========================================
:: 1. ПІДГОТОВКА ТА SMART CHECK
:: ==========================================
echo ===^> 1. Strict System Checks...

:: 1.0 Захист від Ultra-Legacy (Windows 95/98/ME/DOS/OS2)
if not "%OS%"=="Windows_NT" (
    echo.
    echo [ERROR] This script requires a Windows NT-based operating system.
    echo         You are trying to run it on:
    ver
    echo.
    echo [ACTION] Please use a modern environment ^(Windows Vista or newer^).
    pause
    exit
)

:: 1.1 Перевірка диска (Чистий VBScript для обходу ліміту CMD у 2 ГБ)
echo set objFS = CreateObject("Scripting.FileSystemObject") > chk_disk.vbs
echo set objDrive = objFS.GetDrive("%SystemDrive%") >> chk_disk.vbs
echo if objDrive.FreeSpace ^< %MIN_DISK_BYTES% then WScript.Quit(1) else WScript.Quit(0) >> chk_disk.vbs

cscript //nologo chk_disk.vbs
set "DISK_ERR=%errorLevel%"
del chk_disk.vbs

if %DISK_ERR% neq 0 (
    echo [ERROR] Not enough disk space on %SystemDrive%.
    echo [INFO] At least %MIN_DISK_GB% GB of free space is required for the Docker Toolbox VM.
    exit /b 1
)
echo [OK] Sufficient disk space available.

:: 1.2 Безпечний парсинг версії ОС через WMI (Абсолютно стійкий до локалізації)
for /f "tokens=2 delims==" %%I in ('wmic os get version /value 2^>nul') do (
    for /f "delims=" %%A in ("%%I") do set "FULL_VER=%%A"
)
for /f "tokens=1,2,3 delims=." %%a in ("%FULL_VER%") do (
    set "MAJOR=%%a"
    set "MINOR=%%b"
    set "BUILD=%%c"
)
echo [INFO] Detected Windows Kernel: %MAJOR%.%MINOR% Build %BUILD%

:: 1.3 Маршрутизація ОС
set "USE_OFFICIAL_PYTHON=0"

if %MAJOR% GEQ 10 (
    if %BUILD% GEQ 17763 (
        echo [ERROR] OS Build %BUILD% is modern. Execution blocked.
        echo [ACTION] Please use 'install_dev_tools.cmd' or '.ps1'
        exit /b 1
    )
    if %BUILD% GEQ 15063 (
        echo.
        echo [BRIDGE MODE] Detected transitional Windows 10 ^(%BUILD%^).
        echo               WSL 1 is available here. If you want a lightweight Linux
        echo               experience without VirtualBox, cancel this script and run:
        echo               install_dev_tools_wsl1.ps1
        echo.
        echo               Proceeding with Legacy mode ^(Docker Toolbox^), but we
        echo               strongly recommend updating to Build 17763+ for modern MLOps.
        echo.
        echo               If you strictly need Docker, we will install Docker Toolbox
        echo               in 5 seconds...
        timeout /t 5 >nul
        echo.
    ) else if %BUILD% GEQ 14393 (
        echo.
        echo [WARNING] Using an old Windows 10 / Server 2016 build ^(%BUILD%^).
        echo           Proceeding with Legacy mode ^(Docker Toolbox^), but we
        echo           strongly recommend updating to Build 17763+ for modern MLOps.
        echo.
    )
    set "USE_OFFICIAL_PYTHON=1"
)
if %MAJOR% EQU 6 if %MINOR% GEQ 3 set "USE_OFFICIAL_PYTHON=1"
if %MAJOR% LSS 6 (
    echo.
    echo [ERROR] Your OS kernel ^(NT %MAJOR%.%MINOR%^) is physically unsupported by Docker.
    echo         You are trying to run it on: Windows XP / 2000 / Server 2003.
    echo         Docker Toolbox strictly requires at least NT 6.0 ^(Windows Vista^).
    echo.
    exit /b 1
)

:: 1.4 Визначення Архітектури ОС (Не пропустить, якщо це не x64, тож не пропустить x86, ARM, ARM64, IA64 тощо)
set "SYS_ARCH=%PROCESSOR_ARCHITECTURE%"
if /I "%PROCESSOR_ARCHITECTURE%"=="AMD64" set "SYS_ARCH=x64"
if defined PROCESSOR_ARCHITEW6432 set "SYS_ARCH=x64"

if not "%SYS_ARCH%"=="x64" (
    echo.
    echo [ERROR] Unsupported architecture detected: %SYS_ARCH%
    echo [INFO] Legacy Docker Toolbox and Python strictly require 64-bit ^(x64/AMD64^).
    exit /b 1
)
echo [INFO] Detected Architecture: x64

:: 1.5 Перевірка Hardware Virtualization (VT-X/AMD-V)
wmic cpu get VirtualizationFirmwareEnabled | find /I "TRUE" >nul
if %errorLevel% neq 0 (
    echo [ERROR] VT-X / AMD-V is DISABLED in BIOS! Docker cannot be installed.
    exit /b 1
)

:: 1.6 Smart Check
set "VENV_PYTHON=%~dp0%VENV_DIR%\Scripts\python.exe"
if exist "%VENV_PYTHON%" (
    "%VENV_PYTHON%" -c "import django; print('1' if django.__version__ == '%DJANGO_VERSION%' else '0')" > "%TEMP%\dj_chk.txt" 2>nul
    set /p DJ_OK=<"%TEMP%\dj_chk.txt"
    if "!DJ_OK!"=="1" (
        echo [OK] ENVIRONMENT ALREADY INITIALIZED IN '%VENV_DIR%'!
        call :PRINT_REPORT
        exit /b 0
    )
)

:: ==========================================
:: 2. ВСТАНОВЛЕННЯ СИСТЕМНИХ ЗАЛЕЖНОСТЕЙ
:: ==========================================
echo.
echo ===^> 2. Docker Toolbox Setup ^(For all builds ^< 17763^)...
where docker >nul 2>&1
if %errorLevel% equ 0 (
    echo [OK] Docker daemon components found.
) else (
    echo [INFO] Downloading DockerToolbox.exe...
    powershell -Command "%PS_TLS_HACK% (New-Object Net.WebClient).DownloadFile('%DOCKER_TOOLBOX_URL%', 'DockerToolbox.exe')"
    if exist DockerToolbox.exe (
        echo [INFO] Installing silently...
        start /wait DockerToolbox.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-
        echo [OK] Docker Toolbox installed.
    ) else ( echo [ERROR] Failed to download Toolbox. )
)

:: ==========================================
:: 3. ВСТАНОВЛЕННЯ PYTHON
:: ==========================================
echo.
if "%USE_OFFICIAL_PYTHON%"=="1" (
    echo ===^> 3. Official Python 3.9+ Installation...
) else (
    echo ===^> 3. Custom Python 3.9+ Extraction ^(Windows 7 / Vista^)...
)

set "CUSTOM_PY_EXE="

if exist "%VENV_PYTHON%" (
    echo [OK] Python is already handling VENV.
    set "CUSTOM_PY_EXE=%VENV_PYTHON%"
) else (
    if "%USE_OFFICIAL_PYTHON%"=="1" (
        where python >nul 2>&1
        if !errorLevel! equ 0 (
            echo [OK] Official Python found in PATH.
            set "CUSTOM_PY_EXE=python"
        ) else (
            echo [INFO] Downloading Official Python 3.9 Installer...
            powershell -Command "%PS_TLS_HACK% (New-Object Net.WebClient).DownloadFile('%PYTHON_OFFICIAL_URL%', 'python_installer.exe')"
            echo [INFO] Installing silently (AllUsers)...
            start /wait "" python_installer.exe /quiet InstallAllUsers=1 PrependPath=1 Include_test=0
            set "CUSTOM_PY_EXE=%ProgramFiles%\Python39\python.exe"
            echo [OK] Official Python installed.
        )
    ) else (
        set "PYTHON_DEST=%~dp0python_legacy"
        if not exist "!PYTHON_DEST!\python.exe" (
            echo [INFO] Downloading Custom Python Backport...
            powershell -Command "%PS_TLS_HACK% (New-Object Net.WebClient).DownloadFile('%PYTHON_BACKPORT_URL%', 'python.zip')"
            echo [INFO] Extracting via VBScript API (Waiting for completion)...
            if not exist "!PYTHON_DEST!" mkdir "!PYTHON_DEST!"

            echo set objShell = CreateObject^("Shell.Application"^) > unzip.vbs
            echo set objSource = objShell.NameSpace^("%~dp0python.zip"^) >> unzip.vbs
            echo set objTarget = objShell.NameSpace^("!PYTHON_DEST!"^) >> unzip.vbs
            echo intCount = objSource.Items.Count >> unzip.vbs
            echo objTarget.CopyHere objSource.Items, 20 >> unzip.vbs
            echo Do Until objTarget.Items.Count = intCount >> unzip.vbs
            echo     WScript.Sleep 500 >> unzip.vbs
            echo Loop >> unzip.vbs

            cscript //nologo unzip.vbs
            del unzip.vbs
            del python.zip

            for /d %%d in ("!PYTHON_DEST!\*") do (
                xcopy /E /Y "%%d\*" "!PYTHON_DEST!\" >nul
                rmdir /S /Q "%%d"
            )
        )
        set "CUSTOM_PY_EXE=!PYTHON_DEST!\python.exe"
        echo [OK] Custom Python ready.
    )
)

:: ==========================================
:: 4. ІЗОЛЯЦІЯ (VIRTUAL ENVIRONMENT)
:: ==========================================
echo.
echo ===^> 4. Virtual Environment Setup...
if not exist "%VENV_DIR%" (
    "!CUSTOM_PY_EXE!" -m venv "%VENV_DIR%"
    echo [OK] Venv created: %VENV_DIR%
)

echo [INFO] Installing Django %DJANGO_VERSION%...
"%VENV_PYTHON%" -m pip install --upgrade pip -q
"%VENV_PYTHON%" -m pip install "django==%DJANGO_VERSION%" -q
echo [OK] Django installed successfully.

:: ==========================================
:: 5. ФІНАЛЬНИЙ ЗВІТ
:: ==========================================
echo.
echo ===^> ENVIRONMENT SETUP COMPLETE!
call :PRINT_REPORT
exit /b 0

:: ------------------------------------------
:: ФУНКЦІЯ: ДРУК ЗВІТУ
:: ------------------------------------------
:PRINT_REPORT
echo --------------------------------------------------------
set "DVER=Not Found"
for /f "delims=" %%i in ('docker --version 2^>nul') do set "DVER=%%i"
echo [Docker]   %DVER% (Toolbox)

set "DCVER=Not Found"
for /f "delims=" %%i in ('docker-compose --version 2^>nul') do set "DCVER=%%i"
echo [Compose]  %DCVER%

set "PVER=Not Found"
for /f "delims=" %%i in ('"%~dp0%VENV_DIR%\Scripts\python.exe" --version 2^>nul') do set "PVER=%%i"
echo [Python]   %PVER% (Isolated)

set "DJVER=Not Found"
for /f "delims=" %%i in ('"%~dp0%VENV_DIR%\Scripts\python.exe" -m django --version 2^>nul') do set "DJVER=%%i"
echo [Django]   %DJVER% (Inside VENV)

echo.
echo [Launch]   Run 'Docker Quickstart Terminal' on desktop for Docker.
echo [Activate] call %VENV_DIR%\Scripts\activate.bat
echo --------------------------------------------------------
exit /b 0
