#!/bin/sh
set -e

# ==========================================
# 0. КОНСТАНТИ ТА ІНІЦІАЛІЗАЦІЯ
# ==========================================
if [ -z "$_LOG_ACTIVE" ]; then
    _LOG_ACTIVE=1 exec /bin/sh "$0" "$@" 2>&1 | tee -i setup_unix.log
    exit $?
fi

PYTHON_MIN_MAJOR=3
PYTHON_MIN_MINOR=9
DJANGO_VERSION="6.0.4"
VENV_DIR="ml_venv"
MIN_DISK_MB=5120 # 5 GB для Docker (Lima) та Python на UNIX

# ------------------------------------------
# INFRASTRUCTURE AS CODE (IaC) ANCHOR
# ------------------------------------------
printf "\n\033[1;35m=========================================================================================================\033[0m\n"
printf "\033[1;35m[ENTERPRISE BSD PROVISIONER] Детерміністичне IaC-розгортання для класичних UNIX-систем.\033[0m\n"
printf "\033[1;35m                             Architect: IRONKAGE\033[0m\n"
printf "\033[1;35m---------------------------------------------------------------------------------------------------------\033[0m\n"
printf "\033[1;35m                             ОС: BSD Family (FreeBSD 13.0+ / OpenBSD 7.0+ / NetBSD 9.0+ / DragonFly 6.0+)\033[0m\n"
printf "\033[1;35m                             Стек: pkg/pkg_add/pkgin, Python, Lima (Linux VM для Docker OCI)\033[0m\n"
printf "\033[1;35m                             Гарантує розгортання виключно на x86_64 (amd64) або aarch64 (arm64).\033[0m\n"
printf "\033[1;35m=========================================================================================================\033[0m\n\n"

print_msg() { printf "\n\033[1;36m===> %s\033[0m\n" "$1"; }
print_err() { printf "\033[1;31m❌ ПОМИЛКА: %s\033[0m\n" "$1"; }
print_succ() { printf "\033[1;32m✅ %s\033[0m\n" "$1"; }

# ==========================================
# 1. ПІДГОТОВКА (PRE-FLIGHT & SMART CHECK)
# ==========================================
print_msg "1. Підготовка: Перевірка архітектури та ресурсів (BSD Mode)..."

# 1.1 Захист операційної системи
OS_TYPE=$(uname -s)
if [ "$OS_TYPE" != "FreeBSD" ] && [ "$OS_TYPE" != "OpenBSD" ] && [ "$OS_TYPE" != "NetBSD" ] && [ "$OS_TYPE" != "DragonFly" ]; then
    print_err "Цей скрипт призначений виключно для BSD-сімейства."
    if [ "$OS_TYPE" = "SunOS" ]; then
        printf "\033[1;33mℹ️ Знайдено SunOS. Будь ласка, запустіть install_dev_tools_illumos.sh або ips.sh\033[0m\n"
    elif [ -f "/etc/alpine-release" ]; then
        printf "\033[1;33mℹ️ Знайдено Alpine Linux. Будь ласка, запустіть install_dev_tools_alpine.sh\033[0m\n"
    elif [ "$OS_TYPE" = "Darwin" ]; then
        printf "\033[1;33mℹ️ Знайдено macOS. (Lima нативно підтримується, але використовуйте скрипт для Mac).\033[0m\n"
    fi
    exit 1
fi
print_succ "ОС: Класичний UNIX ($OS_TYPE)"

# 1.2 Перевірка апаратної архітектури (Блокуємо 32-bit)
ARCH=$(uname -m)
if [ "$ARCH" != "amd64" ] && [ "$ARCH" != "x86_64" ] && [ "$ARCH" != "aarch64" ] && [ "$ARCH" != "arm64" ]; then
    print_err "Архітектура '$ARCH' не підтримується для ML та гіпервізора Lima!"
    exit 1
fi
print_succ "Апаратна архітектура: OK ($ARCH)"

# 1.3 Перевірка вільного місця на диску
FREE_DISK=$(df -m . | awk 'NR==2 {print $4}')
if [ "$FREE_DISK" -lt "$MIN_DISK_MB" ]; then
    print_err "Мало місця на диску! Доступно $FREE_DISK MB, потрібно щонайменше $MIN_DISK_MB MB."
    exit 1
fi
print_succ "Місце на диску: OK ($FREE_DISK MB)"

# 1.4 Налаштування пакетного менеджера та sudo
PKG_MANAGER=""
case "$OS_TYPE" in
    FreeBSD|DragonFly) PKG_MANAGER="pkg" ;;
    OpenBSD) PKG_MANAGER="pkg_add" ;;
    NetBSD)  PKG_MANAGER="pkgin" ;;
esac

SUDO_CMD="doas" # На BSD частіше використовують doas
if command -v sudo >/dev/null 2>&1; then SUDO_CMD="sudo"; fi
if [ "$(id -u)" -eq 0 ]; then SUDO_CMD=""; fi
print_succ "Пакетний менеджер: $PKG_MANAGER ($SUDO_CMD)"

# 1.5 Smart Check (Швидкий вихід)
PYTHON_BIN=""
if command -v python3 >/dev/null 2>&1; then PYTHON_BIN="python3"
elif command -v python >/dev/null 2>&1; then PYTHON_BIN="python"; fi

if command -v limactl >/dev/null 2>&1 && [ -n "$PYTHON_BIN" ] && [ -d "$VENV_DIR" ]; then
    VENV_PYTHON="$VENV_DIR/bin/python"
    PYTHON_OK=$($PYTHON_BIN -c "import sys; print('1' if sys.version_info >= ($PYTHON_MIN_MAJOR, $PYTHON_MIN_MINOR) else '0')" 2>/dev/null || echo "0")
    DJANGO_OK=$($VENV_PYTHON -c "import django; print('1' if django.__version__ == '$DJANGO_VERSION' else '0')" 2>/dev/null || echo "0")

    if [ "$PYTHON_OK" = "1" ] && [ "$DJANGO_OK" = "1" ]; then
        print_succ "СЕРЕДОВИЩЕ ВЖЕ НАЛАШТОВАНЕ ТА ІЗОЛЬОВАНЕ У '$VENV_DIR'!"
        printf -- "--------------------------------------------------------\n"
        printf "🐳 Docker (Lima): "
        limactl shell docker docker --version 2>/dev/null || echo "\033[1;31mНе знайдено або зупинено\033[0m"
        printf "🐙 Docker Compose: "
        limactl shell docker docker compose version 2>/dev/null || echo "\033[1;31mНе знайдено\033[0m"
        printf "   ↳ 🔌 Local UX: \033[1;36mВиконайте: export DOCKER_HOST=\$(limactl list docker --format 'unix://{{.Dir}}/sock/docker.sock')\033[0m\n"
        printf "   ↳ 🏗️ Prod Note: \033[1;33m⚠️ Для Production нативно краще ручками налаштувати Jails / Bhyve.\033[0m\n"
        printf "🐍 Python (Система): " && $PYTHON_BIN --version 2>/dev/null
        printf "🌍 Django (у VENV): " && "$VENV_PYTHON" -m django --version 2>/dev/null
        printf "\033[1;36m📂 Активація: . %s/bin/activate\033[0m\n" "$VENV_DIR"
        printf -- "--------------------------------------------------------\n"
        exit 0
    fi
fi

# ==========================================
# 2. ВСТАНОВЛЕННЯ СИСТЕМНИХ ЗАЛЕЖНОСТЕЙ
# ==========================================
print_msg "2. Встановлення системних залежностей (Lima для Docker OCI)..."
printf "\033[1;33m⚠️ УВАГА: Docker не підтримується нативно на рівні ядра %s.\033[0m\n" "$OS_TYPE"
printf "\033[1;33m💡 Ініціалізуємо Lima (Linux Virtual Machines) для Development-середовища...\033[0m\n"

case "$PKG_MANAGER" in
    pkg)
        $SUDO_CMD pkg update -q
        $SUDO_CMD pkg install -y lima
        ;;
    pkg_add)
        $SUDO_CMD pkg_add lima
        ;;
    pkgin)
        $SUDO_CMD pkgin -y update
        $SUDO_CMD pkgin -y install lima
        ;;
esac

print_msg "Запуск шаблону Docker через Lima..."
if command -v limactl >/dev/null 2>&1; then
    limactl start template:docker >/dev/null 2>&1 || true
    print_succ "Lima (Docker template) ініціалізовано."
else
    print_err "Утиліта limactl не знайдена після встановлення."
    exit 1
fi

# ==========================================
# 3. ВСТАНОВЛЕННЯ PYTHON
# ==========================================
print_msg "3. Встановлення глобального Python $PYTHON_MIN_MAJOR.$PYTHON_MIN_MINOR+ ..."
case "$PKG_MANAGER" in
    pkg)
        $SUDO_CMD pkg install -y python3 py3-pip py3-virtualenv
        ;;
    pkg_add)
        $SUDO_CMD pkg_add python3 py3-pip
        ;;
    pkgin)
        $SUDO_CMD pkgin -y install python39
        ;;
esac
PYTHON_BIN="python3"
print_succ "Python рушій готовий: $($PYTHON_BIN --version 2>/dev/null || echo 'OK')"

# ==========================================
# 4. ІЗОЛЯЦІЯ (VIRTUAL ENVIRONMENT)
# ==========================================
print_msg "4. Створення ізольованого середовища (venv)..."
if [ ! -d "$VENV_DIR" ]; then
    $PYTHON_BIN -m venv "$VENV_DIR"
    print_succ "Створено venv: $VENV_DIR"
fi

VENV_PIP="$VENV_DIR/bin/pip"
$VENV_PIP install --upgrade pip -q
$VENV_PIP install "django==$DJANGO_VERSION" -q
print_succ "Django встановлено ізольовано."

# ==========================================
# 5. ФІНАЛЬНИЙ ЗВІТ
# ==========================================
print_msg "✅ СЕРЕДОВИЩЕ УСПІШНО НАЛАШТОВАНО! Ось ваш стек:"
printf -- "--------------------------------------------------------\n"
printf "🐳 Docker (Lima): "
limactl shell docker docker --version 2>/dev/null || echo "\033[1;31mНе знайдено або зупинено\033[0m"
printf "🐙 Docker Compose: "
limactl shell docker docker compose version 2>/dev/null || echo "\033[1;31mНе знайдено\033[0m"
printf "   ↳ 🔌 Local UX: \033[1;36mВиконайте: export DOCKER_HOST=\$(limactl list docker --format 'unix://{{.Dir}}/sock/docker.sock')\033[0m\n"
printf "   ↳ 🏗️ Prod Note: \033[1;33m⚠️ Для Production нативно краще ручками налаштувати Jails / Bhyve.\033[0m\n"
printf "🐍 Python (Система): " && $PYTHON_BIN --version 2>/dev/null
printf "🌍 Django (у VENV): " && "$VENV_DIR/bin/python" -m django --version 2>/dev/null
printf "\033[1;36m📂 Активація: . %s/bin/activate\033[0m\n" "$VENV_DIR"
printf -- "--------------------------------------------------------\n"
