#!/bin/sh
set -e

# ==========================================
# 0. КОНСТАНТИ ТА ІНІЦІАЛІЗАЦІЯ
# ==========================================
if [ -z "$_LOG_ACTIVE" ]; then
    _LOG_ACTIVE=1 exec /bin/sh "$0" "$@" 2>&1 | tee -i setup_mac_legacy.log
    exit $?
fi

# Налаштування політики забезпечення Python (Python Provisioning Strategy)
#   "LATEST_SUPPORTED" - Автоматично встановлює найсвіжішу версію Python, яку фізично може скомпілювати поточна OS X.
#   "STRICT_3_9"       - Жорстко вимагає базовий Python 3.9.
#   "STRICT_3_10"      - Жорстко вимагає Python 3.10.
#   "STRICT_3_11"      - Жорстко вимагає Python 3.11.
PYTHON_PROVISIONING_STRATEGY="LATEST_SUPPORTED"
MACPORTS_VER="2.12.4"
DJANGO_VERSION="6.0.4"
VENV_DIR="ml_venv"
DOCKER_MACHINE_VER="v0.16.2"

# ------------------------------------------
# INFRASTRUCTURE AS CODE (IaC) ANCHOR
# ------------------------------------------
printf "\n\033[1;35m============================================================================================================\033[0m\n"
printf "\033[1;35m[MACOS NECROMANCY PROVISIONER] Некромантія для OS X/ OS X Server / macOS (10.6 Snow Leopard - 10.14 Mojave).\033[0m\n"
printf "\033[1;35m                               Architect: IRONKAGE\033[0m\n"
printf "\033[1;35m------------------------------------------------------------------------------------------------------------\033[0m\n"
printf "\033[1;35m                               ОС: OS X та macOS Client / Server Edition (x86_64 Only)\033[0m\n"
printf "\033[1;35m                               Стек: MacPorts, VirtualBox, docker-machine (boot2docker), Python Backport\033[0m\n"
printf "\033[1;31m                               ⚠️ УВАГА: DOCKER ПРАЦЮВАТИМЕ ЧЕРЕЗ VIRTUALBOX МІСТ!\033[0m\n"
printf "\033[1;35m============================================================================================================\033[0m\n\n"

print_msg() { printf "\n\033[1;36m===> %s\033[0m\n" "$1"; }
print_err() { printf "\033[1;31m❌ ПОМИЛКА: %s\033[0m\n" "$1"; }
print_succ() { printf "\033[1;32m✅ %s\033[0m\n" "$1"; }

# ==========================================
# 1. ПІДГОТОВКА (PRE-FLIGHT & SMART CHECK)
# ==========================================
print_msg "1. Перевірка архітектури та екосистеми Mac..."

OS_TYPE=$(uname -s)
if [ "$OS_TYPE" != "Darwin" ]; then
    print_err "Цей скрипт призначений виключно для OS X / OS X Server / macOS."
    if [ "$OS_TYPE" = "Linux" ]; then
        printf "\033[1;33mℹ️ Знайдено Linux. Будь ласка, запустіть install_dev_tools_linux.sh\033[0m\n"
    elif [ "$OS_TYPE" = "SunOS" ]; then
        printf "\033[1;33mℹ️ Знайдено SunOS. Будь ласка, запустіть install_dev_tools_illumos.sh\033[0m\n"
    elif echo "$OS_TYPE" | grep -qE "MINGW|CYGWIN|MSYS"; then
        printf "\033[1;33mℹ️ Знайдено Windows. Будь ласка, запустіть install_dev_tools_windows.ps1\033[0m\n"
    fi
    exit 1
fi

if [ "$(uname -m)" != "x86_64" ]; then
    print_err "Legacy macOS потребує 64-бітного Intel процесора (x86_64)."
    exit 1
fi

# 1.2 Отримуємо мажорну та мінорну версії ОС
MAC_NAME=$(sw_vers -productName)
MAC_MAJOR=$(sw_vers -productVersion | cut -d. -f1)
MAC_VERS=$(sw_vers -productVersion | cut -d. -f2)

# Захист СТЕЛІ: відхиляємо новіші включно з Catalina (10.15+)
if [ "$MAC_MAJOR" -gt 10 ] || [ "$MAC_VERS" -gt 14 ]; then
    print_err "Ця система належить до епохи захищеного ядра (macOS 10.15+)."
    printf "\033[1;33mℹ️ Використовуйте сучасний install_dev_tools_mac.sh (Homebrew-based)!\033[0m\n"
    exit 1
fi

# Захист ПІДЛОГИ: відхиляємо старіші за Snow Leopard (10.6)
if [ "$MAC_MAJOR" -lt 10 ] || { [ "$MAC_MAJOR" -eq 10 ] && [ "$MAC_VERS" -lt 6 ]; }; then
    print_err "Критична архітектурна несумісність (OS X $MAC_MAJOR.$MAC_VERS)."
    printf "\033[1;31m   [FATAL] Незважаючи на 64-бітний процесор, ядро системи (XNU) та драйвери (kexts) є строго 32-бітними.\033[0m\n"
    printf "\033[1;31m   [FATAL] Гіпервізор VirtualBox 4.3+ (необхідний міст для Docker) не підтримує 32-бітні хост-ядра.\033[0m\n"
    printf "\033[1;31m   [FATAL] Сучасні компілятори для Python 3.9+ несумісні з гібридною 32/64-бітною екосистемою.\033[0m\n"
    printf "\033[1;33mℹ️ Мінімальний поріг для розгортання: OS X 10.6 (Snow Leopard) з повноцінним 64-бітним ядром системи.\033[0m\n"
    exit 1
fi

# Детекція Enterprise-середовища
if echo "$MAC_NAME" | grep -qi "Server"; then
    print_succ "Версія ОС: $MAC_MAJOR.$MAC_VERS (Server Edition)"
    printf "\033[1;34m   [ENTERPRISE] Виявлено серверне середовище. MacPorts безпечно ізолює стек у /opt/local/, не ламаючи вбудовані служби Apple.\033[0m\n"
else
    print_succ "Версія ОС: $MAC_MAJOR.$MAC_VERS (Client Edition)"
fi

print_succ "Версія OS X: $MAC_MAJOR.$MAC_VERS (Сумісно з Necromancy)"

# 1.3 Матриця сумісності Python (The Necromancer's Matrix)
if [ "$MAC_VERS" -ge 9 ]; then
    # Mavericks (10.9) - Mojave (10.14)
    MAX_PY_VER="311"
    MAX_PY_DOT="3.11"
elif [ "$MAC_VERS" -ge 7 ]; then
    # Lion (10.7) та Mountain Lion (10.8)
    MAX_PY_VER="310"
    MAX_PY_DOT="3.10"
else
    # Snow Leopard (10.6)
    MAX_PY_VER="39"
    MAX_PY_DOT="3.9"
fi

# 1.4 Застосування політики
case "$PYTHON_PROVISIONING_STRATEGY" in
    "LATEST_SUPPORTED") SELECTED_PY_VER=$MAX_PY_VER; SELECTED_PY_DOT=$MAX_PY_DOT ;;
    "STRICT_3_9")       SELECTED_PY_VER="39";  SELECTED_PY_DOT="3.9" ;;
    "STRICT_3_10")      SELECTED_PY_VER="310"; SELECTED_PY_DOT="3.10" ;;
    "STRICT_3_11")      SELECTED_PY_VER="311"; SELECTED_PY_DOT="3.11" ;;
    *) print_err "Невідомий режим PYTHON_PROVISIONING_STRATEGY='$PYTHON_PROVISIONING_STRATEGY'"; exit 1 ;;
esac

# 1.5 Перевірка оперативної пам'яті (RAM)
MIN_RAM_MB=4096 # Мінімум 4 ГБ для компіляції та запуску Boot2Docker VM

TOTAL_RAM_BYTES=$(sysctl -n hw.memsize)
TOTAL_RAM_MB=$((TOTAL_RAM_BYTES / 1024 / 1024))

if [ "$TOTAL_RAM_MB" -lt "$MIN_RAM_MB" ]; then
    print_err "Критична нестача оперативної пам'яті!"
    printf "\033[1;31m   [FATAL] Знайдено: %s MB. Вимагається щонайменше: %s MB.\033[0m\n" "$TOTAL_RAM_MB" "$MIN_RAM_MB"
    printf "\033[1;33mℹ️ VirtualBox та процеси компіляції (MacPorts) викличуть Kernel Panic або OOM (Out of Memory) на цій системі.\033[0m\n"
    exit 1
fi
print_succ "Оперативна пам'ять: OK ($TOTAL_RAM_MB MB)"

# 1.6 Захист від перевищення можливостей ОС (Math Logic)
if [ "$SELECTED_PY_VER" -gt "$MAX_PY_VER" ]; then
    print_err "Політика вимагає Python $SELECTED_PY_DOT, але дана система підтримує максимум $MAX_PY_DOT!"
    printf "\033[1;33mℹ️ Змініть політику на LATEST_SUPPORTED або оновіть ОС.\033[0m\n"
    exit 1
fi
print_succ "Цільова версія Python згідно з політикою: $SELECTED_PY_DOT"

# 1.7 Smart Check (Швидкий вихід)
if command -v docker >/dev/null 2>&1 && command -v docker-machine >/dev/null 2>&1 && [ -d "$VENV_DIR" ]; then
    VENV_PYTHON="$VENV_DIR/bin/python"
    PYTHON_OK=$($VENV_PYTHON -c "import sys; print('1' if sys.version_info >= (3, 9) else '0')" 2>/dev/null || echo "0")
    DJANGO_OK=$($VENV_PYTHON -c "import django; print('1' if django.__version__ == '$DJANGO_VERSION' else '0')" 2>/dev/null || echo "0")

    if [ "$PYTHON_OK" = "1" ] && [ "$DJANGO_OK" = "1" ]; then
        print_msg "СЕРЕДОВИЩЕ ВЖЕ НАЛАШТОВАНЕ! Перевірка мосту Docker..."

        if [ "$(docker-machine status default 2>/dev/null)" != "Running" ]; then
            print_msg "Пробудження віртуальної машини Boot2Docker..."
            docker-machine start default >/dev/null 2>&1 || true
        fi

        print_succ "СЕРЕДОВИЩЕ NECROMANCY ВЖЕ НАЛАШТОВАНЕ ТА ІЗОЛЬОВАНЕ У '$VENV_DIR'!"
        printf -- "--------------------------------------------------------\n"
        printf "📦 Package Manager: " && port version
        printf "🐳 Docker Engine (VM): " && docker --version 2>/dev/null
        printf "⚙️ Bridge: \033[1;32mdocker-machine (VirtualBox)\033[0m\n"
        printf "   ↳ ⚠️ КРИТИЧНО: Виконайте цю команду зараз: \033[1;33meval \$(docker-machine env default)\033[0m\n"
        printf "🐍 Python (у VENV): " && "$VENV_PYTHON" --version 2>/dev/null
        printf "🌍 Django (у VENV): " && "$VENV_PYTHON" -m django --version 2>/dev/null
        printf "\033[1;36m📂 Активація: . %s/bin/activate\033[0m\n" "$VENV_DIR"
        printf -- "--------------------------------------------------------\n"
        exit 0
    fi
fi

# ==========================================
# 2. ВСТАНОВЛЕННЯ СИСТЕМНИХ ЗАЛЕЖНОСТЕЙ
# ==========================================
print_msg "2. Перевірка та встановлення системних залежностей..."

# 2.1 MacPorts
if ! command -v port >/dev/null 2>&1; then
    print_msg "Завантаження MacPorts v$MACPORTS_VER..."
    if [ "$MAC_VERS" -eq 6 ]; then MP_OS="SnowLeopard";
    elif [ "$MAC_VERS" -eq 7 ]; then MP_OS="Lion";
    elif [ "$MAC_VERS" -eq 8 ]; then MP_OS="MountainLion";
    elif [ "$MAC_VERS" -eq 9 ]; then MP_OS="Mavericks";
    elif [ "$MAC_VERS" -eq 10 ]; then MP_OS="Yosemite";
    elif [ "$MAC_VERS" -eq 11 ]; then MP_OS="ElCapitan";
    elif [ "$MAC_VERS" -eq 12 ]; then MP_OS="Sierra";
    elif [ "$MAC_VERS" -eq 13 ]; then MP_OS="HighSierra";
    else MP_OS="Mojave"; fi

    MP_PKG="MacPorts-${MACPORTS_VER}-10.${MAC_VERS}-${MP_OS}.pkg"
    MP_URL_GITHUB="https://github.com/macports/macports-base/releases/download/v${MACPORTS_VER}/${MP_PKG}"
    MP_URL_DIST="http://distfiles.macports.org/MacPorts/${MP_PKG}"

    if ! curl -L -f -s "$MP_URL_GITHUB" -o /tmp/macports.pkg; then
        printf "\033[1;33mℹ️ Використовуємо офіційне дзеркало MacPorts (HTTP обхід TLS)...\033[0m\n"
        curl -L -f -s "$MP_URL_DIST" -o /tmp/macports.pkg
    fi

    print_msg "Встановлення пакету..."
    sudo installer -pkg /tmp/macports.pkg -target / >/dev/null
    print_succ "MacPorts встановлено."
    export PATH="/opt/local/bin:/opt/local/sbin:$PATH"
fi

# 2.2 Встановлення VirtualBox (Silent DMG Install) та інтелектуальним обходом UAKEL
if ! command -v VBoxManage >/dev/null 2>&1; then
    print_msg "Завантаження VirtualBox для macOS 10.$MAC_VERS..."

    if [ "$MAC_VERS" -le 7 ]; then
        # 10.6 (Snow Leopard) та 10.7 (Lion)
        VB_VER="4.3.40"; VB_BUILD="110317"
    elif [ "$MAC_VERS" -eq 8 ]; then
        # 10.8 (Mountain Lion)
        VB_VER="5.0.40"; VB_BUILD="115130"
    elif [ "$MAC_VERS" -eq 9 ]; then
        # 10.9 (Mavericks)
        VB_VER="5.1.38"; VB_BUILD="122592"
    elif [ "$MAC_VERS" -le 11 ]; then
        # 10.10 (Yosemite) та 10.11 (El Capitan)
        VB_VER="5.2.44"; VB_BUILD="139111"
    elif [ "$MAC_VERS" -eq 12 ]; then
        # 10.12 (Sierra)
        VB_VER="6.0.24"; VB_BUILD="139119"
    else
        # 10.13 (High Sierra) та 10.14 (Mojave)
        VB_VER="6.1.50"; VB_BUILD="161033"
    fi

    VB_URL="https://download.virtualbox.org/virtualbox/${VB_VER}/VirtualBox-${VB_VER}-${VB_BUILD}-OSX.dmg"
    print_msg "Завантаження VirtualBox v$VB_VER..."
    curl -L -f -s "$VB_URL" -o /tmp/vbox.dmg || exit 1

    print_msg "Монтування та встановлення VirtualBox..."
    hdiutil attach /tmp/vbox.dmg -nobrowse -quiet
    sudo installer -pkg /Volumes/VirtualBox/VirtualBox.pkg -target / >/dev/null
    hdiutil detach /Volumes/VirtualBox -quiet

    # ПЕРЕБІЙ СИСТЕМИ БЕЗПЕКИ (UAKEL)
    if [ "$MAC_VERS" -ge 13 ]; then
        printf "\n\033[1;31m========================================================================\033[0m\n"
        printf "\033[1;31m 🚨 КРИТИЧНО ДЛЯ MACOS 10.%s (HIGH SIERRA / MOJAVE) 🚨 \033[0m\n" "$MAC_VERS"
        printf "\033[1;31m========================================================================\033[0m\n"
        printf "\033[1;33m Apple заблокувала ядро для нових драйверів (UAKEL). VirtualBox встановлено,\n"
        printf " але він не запуститься, доки ви не дозволите це вручну!\n\n"
        printf " 1. Відкрийте 'System Preferences' (Системні параметри).\n"
        printf " 2. Перейдіть до 'Security & Privacy' (Безпека та конфіденційність).\n"
        printf " 3. Внизу на вкладці 'General' натисніть кнопку 'Allow' (Дозволити) для 'Oracle America'.\n\n"
        printf " ⚠️ Натисніть ENTER після того, як надасте дозвіл...\033[0m"
        read -r dummy_var
    fi
    print_succ "VirtualBox інтегровано."
fi

# 2.3 Docker Machine
print_msg "2.3 Налаштування Docker мосту (docker-machine)..."
DOCKER_MACHINE_URL="https://github.com/docker/machine/releases/download/$DOCKER_MACHINE_VER/docker-machine-Darwin-x86_64"
DOCKER_URL="https://get.docker.com/builds/Darwin/x86_64/docker-1.10.3"

if ! command -v docker-machine >/dev/null 2>&1; then
    # Використовуємо -k (insecure) для старих сертифікатів або сучасний curl з MacPorts
    sudo curl -k -L -f -s "$DOCKER_MACHINE_URL" -o /usr/local/bin/docker-machine || { print_err "TLS помилка завантаження Docker Machine!"; exit 1; }
    sudo chmod +x /usr/local/bin/docker-machine
fi

if ! command -v docker >/dev/null 2>&1; then
    sudo curl -k -L -f -s "$DOCKER_URL" -o /usr/local/bin/docker || { print_err "TLS помилка завантаження Docker Engine!"; exit 1; }
    sudo chmod +x /usr/local/bin/docker
fi

if ! docker-machine status default >/dev/null 2>&1; then
    print_msg "Створення віртуальної машини Boot2Docker..."
    docker-machine create --driver virtualbox default
fi

if [ "$(docker-machine status default)" != "Running" ]; then
    docker-machine start default
fi
eval $(docker-machine env default)
print_succ "Docker Bridge (Boot2Docker) запущено."

# ==========================================
# 3. ВСТАНОВЛЕННЯ PYTHON
# ==========================================
print_msg "3. Встановлення Python $SELECTED_PY_DOT..."
sudo port -q install "python$SELECTED_PY_VER" "py$SELECTED_PY_VER-virtualenv" "py$SELECTED_PY_VER-pip"
PYTHON_BIN="/opt/local/bin/python$SELECTED_PY_DOT"
print_succ "Python рушій готовий: $($PYTHON_BIN --version)"

# ==========================================
# 4. ІЗОЛЯЦІЯ (VIRTUAL ENVIRONMENT)
# ==========================================
print_msg "4. Створення віртуального середовища (venv)..."
if [ ! -d "$VENV_DIR" ]; then
    "virtualenv-$SELECTED_PY_DOT" "$VENV_DIR"
    print_succ "Створено venv: $VENV_DIR"
fi

VENV_PIP="$VENV_DIR/bin/pip"
$VENV_PIP install --upgrade pip -q
$VENV_PIP install "django==$DJANGO_VERSION" -q
print_succ "Django $DJANGO_VERSION встановлено в ізольоване середовище."

# ==========================================
# 5. ФІНАЛЬНИЙ ЗВІТ
# ==========================================
print_msg "✅ СЕРЕДОВИЩЕ MACOS LEGACY УСПІШНО НАЛАШТОВАНО!"
printf -- "--------------------------------------------------------\n"
printf "📦 Package Manager: " && port version
printf "🐳 Docker Engine (VM): " && docker --version 2>/dev/null
printf "⚙️ Bridge: \033[1;32mdocker-machine (VirtualBox)\033[0m\n"
printf "   ↳ ⚠️ УВАГА: У кожному новому терміналі виконуйте: \033[1;33meval \$(docker-machine env default)\033[0m\n"
printf "🐍 Python (Система): " && $PYTHON_BIN --version 2>/dev/null
printf "🌍 Django (у VENV): " && "$VENV_DIR/bin/python" -m django --version 2>/dev/null
printf "\033[1;36m📂 Активація: . %s/bin/activate\033[0m\n" "$VENV_DIR"
printf -- "--------------------------------------------------------\n"
