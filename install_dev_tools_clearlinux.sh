#!/bin/sh
set -e

# ==========================================
# 0. КОНСТАНТИ ТА ІНІЦІАЛІЗАЦІЯ
# ==========================================
if [ -z "$_LOG_ACTIVE" ]; then
    _LOG_ACTIVE=1 exec /bin/sh "$0" "$@" 2>&1 | tee -i setup_clear.log
    exit $?
fi

PYTHON_MIN_MAJOR=3
PYTHON_MIN_MINOR=9
DJANGO_VERSION="6.0.4"
VENV_DIR="ml_venv"
MIN_DISK_MB=5120  # 5 GB для Docker та Python на Clear Linux (оптимізований, але все ж вимагає місця)

# ------------------------------------------
# INFRASTRUCTURE AS CODE (IaC) ANCHOR
# ------------------------------------------
printf "\n\033[1;35m===================================================================================\033[0m\n"
printf "\033[1;35m[INTEL CLEAR LINUX PROVISIONER] Детерміністичне IaC-розгортання для Clear Linux OS.\033[0m\n"
printf "\033[1;35m                                Architect: IRONKAGE\033[0m\n"
printf "\033[1;35m-----------------------------------------------------------------------------------\033[0m\n"
printf "\033[1;35m                                ОС: Clear Linux OS (Stateless Continuous Release)\033[0m\n"
printf "\033[1;35m                                Стек: swupd (Bundles), systemd, Python (venv)\033[0m\n"
printf "\033[1;35m                                Гарантує розгортання виключно на x86_64 (amd64).\033[0m\n"
printf "\033[1;35m===================================================================================\033[0m\n\n"

print_msg() { printf "\n\033[1;36m===> %s\033[0m\n" "$1"; }
print_err() { printf "\033[1;31m❌ ПОМИЛКА: %s\033[0m\n" "$1"; }
print_succ() { printf "\033[1;32m✅ %s\033[0m\n" "$1"; }

# ==========================================
# 1. ПІДГОТОВКА (PRE-FLIGHT & SMART CHECK)
# ==========================================
print_msg "1. Підготовка: Перевірка архітектури Clear Linux..."

# 1.1 Захист операційної системи та маршрутизація
OS_TYPE=$(uname -s)
if [ "$OS_TYPE" != "Linux" ]; then
    print_err "Цей скрипт призначений виключно для Linux-систем."
    if [ "$OS_TYPE" = "Darwin" ]; then
        printf "\033[1;33mℹ️ Знайдено macOS. Будь ласка, запустіть install_dev_tools_mac.sh\033[0m\n"
    elif [ "$OS_TYPE" = "SunOS" ]; then
        printf "\033[1;33mℹ️ Знайдено SunOS. Будь ласка, запустіть install_dev_tools_illumos.sh або ips.sh\033[0m\n"
    else
        printf "\033[1;33mℹ️ Знайдено %s. Спробуйте install_dev_tools_unix.sh\033[0m\n" "$OS_TYPE"
    fi
    exit 1
fi

if ! command -v swupd >/dev/null 2>&1; then
    print_err "Це не Clear Linux OS (відсутній менеджер бандлів swupd)!"
    printf "\033[1;33mℹ️ Для інших дистрибутивів використовуйте install_dev_tools_linux.sh\033[0m\n"
    exit 1
fi

# 1.2 Перевірка апаратної архітектури (Clear Linux = strictly x86_64)
ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ] && [ "$ARCH" != "amd64" ]; then
    print_err "Архітектура '$ARCH' не підтримується!"
    printf "\033[1;33mℹ️ Clear Linux OS агресивно оптимізована виключно під x86_64.\033[0m\n"
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

SUDO_CMD="sudo"
if [ "$(id -u)" -eq 0 ]; then SUDO_CMD=""; fi
REAL_USER=${SUDO_USER:-$USER}

# 1.4 Smart Check (Швидкий вихід)
PYTHON_BIN=""
if command -v python3 >/dev/null 2>&1; then PYTHON_BIN="python3"
elif command -v python >/dev/null 2>&1; then PYTHON_BIN="python"; fi

if command -v docker >/dev/null 2>&1 && [ -n "$PYTHON_BIN" ] && [ -d "$VENV_DIR" ]; then
    VENV_PYTHON="$VENV_DIR/bin/python"
    PYTHON_OK=$($PYTHON_BIN -c "import sys; print('1' if sys.version_info >= ($PYTHON_MIN_MAJOR, $PYTHON_MIN_MINOR) else '0')" 2>/dev/null || echo "0")
    DJANGO_OK=$($VENV_PYTHON -c "import django; print('1' if django.__version__ == '$DJANGO_VERSION' else '0')" 2>/dev/null || echo "0")

    if [ "$PYTHON_OK" = "1" ] && [ "$DJANGO_OK" = "1" ]; then
        print_succ "СЕРЕДОВИЩЕ ВЖЕ НАЛАШТОВАНЕ ТА ІЗОЛЬОВАНЕ У '$VENV_DIR'!"
        printf -- "--------------------------------------------------------\n"
        printf "🐳 Docker Engine: " && docker --version 2>/dev/null || echo "\033[1;31mНе знайдено\033[0m"
        printf "🐙 Docker Compose: " && docker compose version 2>/dev/null || echo "\033[1;31mНе знайдено\033[0m"
        printf "⚙️ Init System: \033[1;32msystemd (Active)\033[0m\n"
        printf "   ↳ 🔐 Access Note: \033[1;35mЯкщо Docker потребує sudo, виконайте: newgrp docker\033[0m\n"
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
print_msg "2. Оновлення та встановлення Бандлів (swupd)..."
$SUDO_CMD swupd update
$SUDO_CMD swupd bundle-add containers-basic python-basic  # containers-basic містить Docker, python-basic містить Python

print_msg "Активація Docker демона (systemd)..."
$SUDO_CMD systemctl enable --now docker
print_succ "Docker встановлено та запущено."

print_msg "Налаштування прав Docker (Post-install)..."
$SUDO_CMD groupadd docker 2>/dev/null || true
$SUDO_CMD usermod -aG docker "$REAL_USER" || true
print_succ "Користувача '$REAL_USER' додано до групи 'docker'."

# ==========================================
# 3. ВСТАНОВЛЕННЯ PYTHON
# ==========================================
print_msg "3. Встановлення глобального Python $PYTHON_MIN_MAJOR.$PYTHON_MIN_MINOR+ ..."
# Python вже розгорнуто через bundle 'python-basic' на кроці 2
PYTHON_BIN="python3"
print_succ "Python рушій готовий: $($PYTHON_BIN --version 2>/dev/null)"

# ==========================================
# 4. ІЗОЛЯЦІЯ (VIRTUAL ENVIRONMENT)
# ==========================================
print_msg "4. Створення віртуального середовища..."
if [ ! -d "$VENV_DIR" ]; then
    $PYTHON_BIN -m venv "$VENV_DIR"
    print_succ "Створено venv: $VENV_DIR"
fi

VENV_PIP="$VENV_DIR/bin/pip"
$VENV_PIP install --upgrade pip -q
$VENV_PIP install "django==$DJANGO_VERSION" -q
print_succ "Django $DJANGO_VERSION встановлено в ізольоване середовище."

# ==========================================
# 5. ФІНАЛЬНИЙ ЗВІТ
# ==========================================
print_msg "✅ СЕРЕДОВИЩЕ CLEAR LINUX УСПІШНО НАЛАШТОВАНО! Ось ваш стек:"
printf -- "--------------------------------------------------------\n"
printf "🐳 Docker Engine: " && docker --version 2>/dev/null || echo "\033[1;31mНе знайдено\033[0m"
printf "🐙 Docker Compose: " && docker compose version 2>/dev/null || echo "\033[1;31mНе знайдено\033[0m"
printf "⚙️ Init System: \033[1;32msystemd (Active)\033[0m\n"
printf "   ↳ 🔐 Access Note: \033[1;35mЯкщо Docker потребує sudo, виконайте: newgrp docker\033[0m\n"
printf "🐍 Python (Система): " && $PYTHON_BIN --version 2>/dev/null
printf "🌍 Django (у VENV): " && "$VENV_DIR/bin/python" -m django --version 2>/dev/null
printf "\033[1;36m📂 Активація: . %s/bin/activate\033[0m\n" "$VENV_DIR"
printf -- "--------------------------------------------------------\n"
