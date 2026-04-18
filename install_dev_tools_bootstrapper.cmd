@echo off
setlocal EnableDelayedExpansion
title MLOps Bootstrapper

:: Вмикаємо підтримку UTF-8 та ANSI-кольорів
chcp 65001 >nul
for /F "delims=#" %%E in ('"prompt #$E# & for %%a in (1) do rem"') do set "ESC=%%E"
set "cRED=%ESC%[1;31m"
set "cGREEN=%ESC%[1;32m"
set "cCYAN=%ESC%[1;36m"
set "cRESET=%ESC%[0m"

:: ------------------------------------------
:: INFRASTRUCTURE AS CODE (IaC) ANCHOR
:: ------------------------------------------
echo %cMAGENTA%==========================================================================%cRESET%
echo %cMAGENTA%[IaC BOOTSTRAPPER] Ініціалізація екосистеми для Windows Modern MLOps...%cRESET%
echo %cMAGENTA%                   Architect: IRONKAGE%cRESET%
echo %cMAGENTA%--------------------------------------------------------------------------%cRESET%
echo %cMAGENTA%                   Функція: UAC Bypass та безпечна маршрутизація виконання%cRESET%
echo %cMAGENTA%                   Стек: Запуск флагманського PowerShell-провіжинера%cRESET%
echo %cMAGENTA%                   Гарантує запуск із найвищими системними привілеями.%cRESET%
echo %cMAGENTA%==========================================================================%cRESET%

:: ------------------------------------------
:: MLOPS BOOTSTRAPPER (ЛАУНЧЕР)
:: ------------------------------------------
echo =======================================================================
echo %cCYAN%[LAUNCHER] Підготовка середовища для запуску Modern MLOps Script...%cRESET%
echo =======================================================================

:: 1. Автоматичний запит прав Адміністратора (UAC Bypass)
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [INFO] Потрібні права Адміністратора. Запит дозволу (UAC)...
    :: Перезапуск від імені Адміна з обробкою шляхів із пробілами
    powershell -Command "Start-Process cmd -ArgumentList '/c ^\"%~dpnx0^\"' -Verb RunAs"
    exit /b 0
)

:: ПОВЕРНЕННЯ РОБОЧОЇ ДИРЕКТОРІЇ (Ліки від System32 синдрому)
cd /d "%~dp0"

:: 2. Перевірка наявності головного PowerShell скрипта
set "PS_SCRIPT=%~dp0install_dev_tools.ps1"
if not exist "%PS_SCRIPT%" (
    echo.
    echo %cRED%[ПОМИЛКА] Файл "install_dev_tools.ps1" не знайдено!%cRESET%
    echo %cRED%Будь ласка, переконайтеся, що він лежить у тій самій папці.%cRESET%
    echo.
    pause
    exit /b 1
)

:: 3. Запуск PowerShell з обходом Execution Policy
echo %cGREEN%[OK] Права Адміністратора підтверджено.%cRESET%
echo [INFO] Передача керування до PowerShell...
echo.

:: Викликаємо наш флагманський скрипт
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"

:: 4. Обробка помилок
if %errorLevel% neq 0 (
    echo.
    echo %cRED%[ПОМИЛКА] Виконання PowerShell-скрипта завершилося з критичною помилкою.%cRESET%
    pause
    exit /b %errorLevel%
)

:: Успішне завершення. Пауза не потрібна, бо PS1 сам тримає екран.
exit /b 0
