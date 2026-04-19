#!/bin/sh
set -e

# ==========================================
# 0. КОНСТАНТИ ТА ІНІЦІАЛІЗАЦІЯ
# ==========================================
if [ -z "$_LOG_ACTIVE" ]; then
    _LOG_ACTIVE=1 exec /bin/sh "$0" "$@" 2>&1 | tee -i setup_linux.log
    exit $?
fi

PYTHON_MIN_MAJOR=3
PYTHON_MIN_MINOR=9
DJANGO_VERSION="6.0.4"
VENV_DIR="ml_venv"
MIN_DISK_MB=5120 # 5 GB для Docker Engine та Python на Linux

# ------------------------------------------
# INFRASTRUCTURE AS CODE (IaC) ANCHOR
# ------------------------------------------
printf "\n\033[1;35m===================================================================================================\033[0m\n"
printf "\033[1;35m[ENTERPRISE LINUX PROVISIONER] Детерміністичне IaC-розгортання для GNU/Linux (systemd).\033[0m\n"
printf "\033[1;35m                               Architect: IRONKAGE\033[0m\n"
printf "\033[1;35m---------------------------------------------------------------------------------------------------\033[0m\n"
printf "\033[1;35m                               ОС: GNU/Linux (Kernel 3.10+) — Support Matrix:\033[0m\n"
printf "\033[1;35m                                  [apt] Debian 11+, Ubuntu 20.04+ (Mint 20+, Pop!_OS 20.04+)\033[0m\n"
printf "\033[1;35m                                  [dnf] RHEL/CentOS 8+, Fedora 35+ (AlmaLinux 8.3+, Rocky 8.4+)\033[0m\n"
printf "\033[1;35m                                  [pac] Arch Linux, Manjaro, EndeavourOS (Rolling Releases)\033[0m\n"
printf "\033[1;35m                                  [zyp] openSUSE Leap 15.3+, SLES 15 SP3+, Tumbleweed (Rolling)\033[0m\n"
printf "\033[1;35m---------------------------------------------------------------------------------------------------\033[0m\n"
printf "\033[1;35m                               Стек: Native Docker Engine, systemd, Python (venv)\033[0m\n"
printf "\033[1;35m                               Гарантує розгортання виключно на x86_64 (amd64) або aarch64 (arm64).\033[0m\n"
printf "\033[1;35m===================================================================================================\033[0m\n\n"

print_msg() { printf "\n\033[1;36m===> %s\033[0m\n" "$1"; }
print_err() { printf "\033[1;31m❌ ПОМИЛКА: %s\033[0m\n" "$1"; }
print_succ() { printf "\033[1;32m✅ %s\033[0m\n" "$1"; }

# ==========================================
# 1. ПІДГОТОВКА (PRE-FLIGHT & SMART CHECK)
# ==========================================
print_msg "1. Підготовка: Перевірка архітектури та дистрибутива Linux..."

# 1.1 Захист операційної системи
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

# 1.2 Перевірка апаратної архітектури
ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ] && [ "$ARCH" != "amd64" ] && [ "$ARCH" != "aarch64" ] && [ "$ARCH" != "arm64" ]; then
    print_err "Архітектура '$ARCH' не підтримується! Потрібно x86_64 або aarch64."
    exit 1
fi
print_succ "Апаратна архітектура: OK ($ARCH)"

# 1.3 Аналіз дистрибутива та пакетного менеджера
PKG_MANAGER=""
if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
        alpine)
            print_err "Виявлено Alpine Linux."
            printf "\033[1;33mℹ️ Alpine використовує OpenRC та musl. Запустіть спеціалізований install_dev_tools_alpine.sh\033[0m\n"
            exit 1 ;;
        ubuntu|debian|linuxmint|pop) PKG_MANAGER="apt-get" ;;
        fedora|centos|rhel|almalinux|rocky)
            if command -v dnf >/dev/null 2>&1; then PKG_MANAGER="dnf"; else PKG_MANAGER="yum"; fi ;;
        arch|manjaro|endeavouros) PKG_MANAGER="pacman" ;;
        opensuse*|suse) PKG_MANAGER="zypper" ;;
        *) print_err "Непідтримуваний дистрибутив: $PRETTY_NAME"; exit 1 ;;
    esac
    print_succ "ОС: $PRETTY_NAME ($PKG_MANAGER)"
else
    print_err "Не вдалося визначити дистрибутив (відсутній /etc/os-release)."
    exit 1
fi

# 1.4 Перевірка вільного місця на диску
FREE_DISK=$(df -m . | awk 'NR==2 {print $4}')
if [ "$FREE_DISK" -lt "$MIN_DISK_MB" ]; then
    print_err "Мало місця на диску! Доступно $FREE_DISK MB, потрібно щонайменше $MIN_DISK_MB MB."
    exit 1
fi
print_succ "Місце на диску: OK ($FREE_DISK MB)"

# Налаштування sudo та визначення реального користувача
SUDO_CMD="sudo"
if [ "$(id -u)" -eq 0 ]; then SUDO_CMD=""; fi
REAL_USER=${SUDO_USER:-$USER}

# 1.5 Smart Check (Швидкий вихід)
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
        printf "🐙 Docker Compose: " && (docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || echo "\033[1;31mНе знайдено\033[0m")
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
print_msg "2. Оновлення індексів пакетів ($PKG_MANAGER) та налаштування Docker..."
case "$PKG_MANAGER" in
    apt-get) $SUDO_CMD apt-get update -y -qq ;;
    dnf|yum) $SUDO_CMD $PKG_MANAGER check-update -q || true ;;
    pacman)  $SUDO_CMD pacman -Sy --noconfirm -q ;;
    zypper)  $SUDO_CMD zypper refresh -q ;;
esac

if command -v docker >/dev/null 2>&1; then
    print_succ "Docker вже встановлено."
else
    print_msg "Встановлення Docker Engine через $PKG_MANAGER..."
    case "$PKG_MANAGER" in
        apt-get)
            DOCKER_ID="$ID"
            DOCKER_CODENAME="$VERSION_CODENAME"
            if [ "$ID" = "linuxmint" ] || [ "$ID" = "pop" ]; then
                DOCKER_ID="ubuntu"
                DOCKER_CODENAME="$UBUNTU_CODENAME"
            fi

            $SUDO_CMD apt-get install -y ca-certificates curl gnupg
            $SUDO_CMD install -m 0755 -d /etc/apt/keyrings
            if [ ! -f /etc/apt/keyrings/docker.asc ]; then
                $SUDO_CMD curl -fsSL "https://download.docker.com/linux/$DOCKER_ID/gpg" -o /etc/apt/keyrings/docker.asc
                $SUDO_CMD chmod a+r /etc/apt/keyrings/docker.asc
            fi

            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$DOCKER_ID $DOCKER_CODENAME stable" | $SUDO_CMD tee /etc/apt/sources.list.d/docker.list > /dev/null
            $SUDO_CMD apt-get update -y -qq
            $SUDO_CMD apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        dnf|yum)
            $SUDO_CMD $PKG_MANAGER install -y yum-utils
            $SUDO_CMD yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            $SUDO_CMD $PKG_MANAGER install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        pacman)  $SUDO_CMD pacman -S --noconfirm docker docker-compose ;;
        zypper)  $SUDO_CMD zypper install -y docker docker-compose ;;
    esac

    print_msg "Активація Docker демона (systemd)..."
    $SUDO_CMD systemctl enable --now docker
    print_succ "Docker встановлено та запущено."
fi

print_msg "Налаштування прав Docker (Post-install)..."
$SUDO_CMD groupadd docker 2>/dev/null || true
$SUDO_CMD usermod -aG docker "$REAL_USER"
print_succ "Користувача '$REAL_USER' додано до групи 'docker'."

# ==========================================
# 3. ВСТАНОВЛЕННЯ PYTHON
# ==========================================
print_msg "3. Встановлення глобального Python $PYTHON_MIN_MAJOR.$PYTHON_MIN_MINOR+ ..."
case "$PKG_MANAGER" in
    apt-get) $SUDO_CMD apt-get install -y python3 python3-pip python3-venv ;;
    dnf|yum) $SUDO_CMD $PKG_MANAGER install -y python3 python3-pip ;;
    pacman)  $SUDO_CMD pacman -S --noconfirm python python-pip ;;
    zypper)  $SUDO_CMD zypper install -y python3 python3-pip ;;
esac
PYTHON_BIN="python3"
print_succ "Python рушій готовий: $($PYTHON_BIN --version)"

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
print_msg "✅ СЕРЕДОВИЩЕ УСПІШНО НАЛАШТОВАНО! Ось ваш стек:"
printf -- "--------------------------------------------------------\n"
printf "🐳 Docker Engine: " && docker --version 2>/dev/null || echo "\033[1;31mНе знайдено\033[0m"
printf "🐙 Docker Compose: " && (docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || echo "\033[1;31mНе знайдено\033[0m")
printf "⚙️ Init System: \033[1;32msystemd (Active)\033[0m\n"
printf "   ↳ 🔐 Access Note: \033[1;35mЯкщо Docker потребує sudo, виконайте: newgrp docker\033[0m\n"
printf "🐍 Python (Система): " && $PYTHON_BIN --version 2>/dev/null
printf "🌍 Django (у VENV): " && "$VENV_DIR/bin/python" -m django --version 2>/dev/null
printf "\033[1;36m📂 Активація: . %s/bin/activate\033[0m\n" "$VENV_DIR"
printf -- "--------------------------------------------------------\n"
