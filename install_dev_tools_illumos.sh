#!/bin/sh
set -e

# ==========================================
# 0. КОНСТАНТИ ТА ІНІЦІАЛІЗАЦІЯ
# ==========================================
if [ -z "$_LOG_ACTIVE" ]; then
    _LOG_ACTIVE=1 exec /bin/sh "$0" "$@" 2>&1 | tee -i setup_illumos.log
    exit $?
fi

PYTHON_MIN_MAJOR=3
PYTHON_MIN_MINOR=9
DJANGO_VERSION="6.0.4"
VENV_DIR="ml_venv"
MIN_DISK_MB=5120  # 5 GB для Python та пакетів на illumos / SmartOS

# ------------------------------------------
# INFRASTRUCTURE AS CODE (IaC) ANCHOR
# ------------------------------------------
printf "\n\033[1;35m===================================================================================================\033[0m\n"
printf "\033[1;35m[ENTERPRISE RUNTIME PROVISIONER] Детерміністичне IaC-розгортання для illumos / SmartOS.\033[0m\n"
printf "\033[1;35m                                 Architect: IRONKAGE\033[0m\n"
printf "\033[1;35m---------------------------------------------------------------------------------------------------\033[0m\n"
printf "\033[1;35m                                 ОС: SunOS 5.11 (illumos: SmartOS 2021+)\033[0m\n"
printf "\033[1;35m                                 Стек: Hardware-Isolated Zones, Python (pkgsrc)\033[0m\n"
printf "\033[1;35m                                 Гарантує розгортання виключно на x86_64 (amd64) у Non-Global Zone.\033[0m\n"
printf "\033[1;35m===================================================================================================\033[0m\n\n"

print_msg() { printf "\n\033[1;36m===> %s\033[0m\n" "$1"; }
print_err() { printf "\033[1;31m❌ ПОМИЛКА: %s\033[0m\n" "$1"; }
print_succ() { printf "\033[1;32m✅ %s\033[0m\n" "$1"; }

# ==========================================
# 1. ПІДГОТОВКА (PRE-FLIGHT & SMART CHECK)
# ==========================================
print_msg "1. Підготовка: Перевірка архітектури SunOS / illumos..."

# 1.1 Захист операційної системи
if [ "$(uname -s)" != "SunOS" ]; then
    print_err "Цей скрипт призначений виключно для SunOS (illumos / SmartOS)."
    if [ -f "/etc/os-release" ]; then
        CURRENT_OS=$(grep -E '^PRETTY_NAME=' /etc/os-release | cut -d '=' -f 2 | tr -d '"')
    else
        RAW_OS=$(uname -s)
        if [ "$RAW_OS" = "Darwin" ]; then
            if command -v sw_vers >/dev/null 2>&1; then CURRENT_OS="macOS $(sw_vers -productVersion)"
            else CURRENT_OS="macOS (Darwin Core)"; fi
        else CURRENT_OS="$RAW_OS"; fi
    fi
    printf "\033[1;33mВи намагаєтесь запустити його на ОС: %s\033[0m\n" "${CURRENT_OS:-Невідома система}"
    exit 1
fi
print_succ "ОС: SunOS (illumos архітектура)"

# 1.2 Перевірка апаратної архітектури (Блокуємо SPARC та 32-bit)
SYS_ARCH=$(isainfo -n 2>/dev/null || uname -p)
if [ "$SYS_ARCH" != "amd64" ]; then
    print_err "Апаратна архітектура '$SYS_ARCH' не підтримується!"
    printf "\033[1;33mℹ️ Сучасний ML-стек вимагає архітектури x86_64 (amd64).\033[0m\n"
    printf "\033[1;33mℹ️ Процесори SPARC або 32-бітні ядра не підтримуються цим провіжинером.\033[0m\n"
    exit 1
fi
print_succ "Апаратна архітектура: OK ($SYS_ARCH)"

# 1.3 Захист екосистеми пакетів
if ! command -v pkgin >/dev/null 2>&1; then
    print_err "Менеджер пакетів 'pkgin' не знайдено!"
    if command -v pkg >/dev/null 2>&1; then
        printf "\033[1;33mℹ️ Знайдено IPS (pkg). Будь ласка, запустіть install_dev_tools_ips.sh\033[0m\n"
    fi
    exit 1
fi
print_succ "Знайдено менеджер: pkgsrc (pkgin)"

# 1.4 Перевірка ізоляції (SmartOS Zones)
ZONENAME=$(zonename)
if [ "$ZONENAME" = "global" ]; then
    print_err "КРИТИЧНО: Ви знаходитесь у Global Zone!"
    printf "\033[1;33mВстановлення ПЗ у Global Zone заборонено архітектурою SmartOS.\033[0m\n"
    printf "\033[1;33mБудь ласка, перейдіть у Non-Global Zone (Joyent SmartMachine).\033[0m\n"
    exit 1
fi
print_succ "Локація: Hardware-Isolated Zone ($ZONENAME)"

# 1.5 Перевірка вільного місця на диску
FREE_DISK=$(df -m . | awk 'NR==2 {print $4}')
if [ "$FREE_DISK" -lt "$MIN_DISK_MB" ]; then
    print_err "Мало місця на диску! Доступно $FREE_DISK MB, потрібно щонайменше $MIN_DISK_MB MB."
    exit 1
fi
print_succ "Місце на диску: OK ($FREE_DISK MB)"

# 1.6 Smart Check (Швидкий вихід)
PYTHON_BIN=""
if command -v python3 >/dev/null 2>&1; then PYTHON_BIN="python3"
elif command -v "python${PYTHON_MIN_MAJOR}.${PYTHON_MIN_MINOR}" >/dev/null 2>&1; then PYTHON_BIN="python${PYTHON_MIN_MAJOR}.${PYTHON_MIN_MINOR}"; fi

if [ -n "$PYTHON_BIN" ] && [ -d "$VENV_DIR" ]; then
    VENV_PYTHON="$VENV_DIR/bin/python"
    PYTHON_OK=$("$PYTHON_BIN" -c "import sys; print('1' if sys.version_info >= ($PYTHON_MIN_MAJOR, $PYTHON_MIN_MINOR) else '0')" 2>/dev/null || echo "0")
    DJANGO_OK=$("$VENV_PYTHON" -c "import django; print('1' if django.__version__ == '$DJANGO_VERSION' else '0')" 2>/dev/null || echo "0")

    if [ "$PYTHON_OK" = "1" ] && [ "$DJANGO_OK" = "1" ]; then
        print_succ "СЕРЕДОВИЩЕ ВЖЕ НАЛАШТОВАНЕ ТА ІЗОЛЬОВАНЕ У '$VENV_DIR'!"
        printf -- "--------------------------------------------------------\n"
        printf "🐳 Docker (OCI): \033[1;33mN/A (Використовується Zone: %s)\033[0m\n" "$ZONENAME"
        printf "⚙️ SMF (Init Daemon): \033[1;32mActive (Build: %s)\033[0m\n" "$(uname -v)"
        printf "   ↳ 🏗️ Ops Note: \033[1;35mДля демонізації мікросервісів використовуйте svcadm.\033[0m\n"
        printf "🐍 Python (Система): " && "$PYTHON_BIN" --version 2>/dev/null
        printf "🌍 Django (у VENV): " && "$VENV_PYTHON" -m django --version 2>/dev/null
        printf "\033[1;36m📂 Активація: . %s/bin/activate\033[0m\n" "$VENV_DIR"
        printf -- "--------------------------------------------------------\n"
        exit 0
    fi
fi

# Визначення утиліти для підвищення прав
SUDO_CMD="sudo"
if command -v pfexec >/dev/null 2>&1; then SUDO_CMD="pfexec"; fi
if [ "$(id -u)" -eq 0 ]; then SUDO_CMD=""; fi

# ==========================================
# 2. ВСТАНОВЛЕННЯ СИСТЕМНИХ ЗАЛЕЖНОСТЕЙ
# ==========================================
print_msg "2. Оновлення індексів пакетів (pkgin)..."
printf "\033[1;33mℹ️ Solaris Zones та SMF виступають гарантом ізоляції процесів.\033[0m\n"

$SUDO_CMD pkgin -y update -q

# ==========================================
# 3. ВСТАНОВЛЕННЯ PYTHON
# ==========================================
print_msg "3. Встановлення Python $PYTHON_MIN_MAJOR.$PYTHON_MIN_MINOR+ ..."
if [ -z "$PYTHON_BIN" ]; then
    $SUDO_CMD pkgin -y install "python${PYTHON_MIN_MAJOR}${PYTHON_MIN_MINOR}"
    PYTHON_BIN="python${PYTHON_MIN_MAJOR}.${PYTHON_MIN_MINOR}"
fi
print_succ "Python рушій готовий."

# ==========================================
# 4. ІЗОЛЯЦІЯ (VIRTUAL ENVIRONMENT)
# ==========================================
print_msg "4. Створення віртуального середовища..."
if [ ! -d "$VENV_DIR" ]; then
    "$PYTHON_BIN" -m venv "$VENV_DIR"
    print_succ "Створено venv: $VENV_DIR"
fi

VENV_PIP="$VENV_DIR/bin/pip"
"$VENV_PIP" install --upgrade pip -q
"$VENV_PIP" install "django==$DJANGO_VERSION" -q
print_succ "Django $DJANGO_VERSION встановлено в ізольоване середовище."

# ==========================================
# 5. ФІНАЛЬНИЙ ЗВІТ
# ==========================================
print_msg "✅ СЕРЕДОВИЩЕ УСПІШНО НАЛАШТОВАНО! Ось ваш стек:"
printf -- "--------------------------------------------------------\n"
printf "🐳 Docker (OCI): \033[1;33mN/A (Використовується Zone: %s)\033[0m\n" "$ZONENAME"
printf "⚙️ SMF (Init Daemon): \033[1;32mActive (Build: %s)\033[0m\n" "$(uname -v)"
printf "   ↳ 🏗️ Ops Note: \033[1;35mДля демонізації мікросервісів використовуйте svcadm.\033[0m\n"
printf "🐍 Python (Система): " && "$PYTHON_BIN" --version 2>/dev/null
printf "🌍 Django (у VENV): " && "$VENV_DIR/bin/python" -m django --version 2>/dev/null
printf "\033[1;36m📂 Активація: . %s/bin/activate\033[0m\n" "$VENV_DIR"
printf -- "--------------------------------------------------------\n"
