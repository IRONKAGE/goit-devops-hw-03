#!/bin/sh
set -e

# ==========================================
# 0. КОНСТАНТИ ТА ІНІЦІАЛІЗАЦІЯ
# ==========================================
if [ -z "$_LOG_ACTIVE" ]; then
    _LOG_ACTIVE=1 exec /bin/sh "$0" "$@" 2>&1 | tee -i setup_legacy.log
    exit $?
fi

PYTHON_MIN_MAJOR=3
PYTHON_MIN_MINOR=9  # Використовуємо форсоване вживлення (Necromancy)
DJANGO_VERSION="6.0.4"
VENV_DIR="ml_venv"
MIN_DISK_MB=5120  # 5 GB для Python та пакетів на старих Linux-системах

# ------------------------------------------
# INFRASTRUCTURE AS CODE (IaC) ANCHOR
# ------------------------------------------
printf "\n\033[1;35m=====================================================================================================\033[0m\n"
printf "\033[1;35m[LEGACY LINUX PROVISIONER] Graceful Degradation-розгортання для EOL-систем (End of Life).\033[0m\n"
printf "\033[1;35m                           Architect: IRONKAGE\033[0m\n"
printf "\033[1;35m-----------------------------------------------------------------------------------------------------\033[0m\n"
printf "\033[1;35m                           ОС: GNU/Linux (Kernel 2.6.32+) — Legacy Support Matrix:\033[0m\n"
printf "\033[1;35m                              [apt] Debian 8–10 | Ubuntu 14.04–19.10 (Mint 17–19)\033[0m\n"
printf "\033[1;35m                              [yum] RHEL/CentOS/Oracle Linux 7 | Fedora 25–34\033[0m\n"
printf "\033[1;35m                              [zyp] SLES 12–15 SP2 | openSUSE Leap 42.x–15.2\033[0m\n"
printf "\033[1;35m-----------------------------------------------------------------------------------------------------\033[0m\n"
printf "\033[1;35m                           Стек: Classic Docker, systemd/upstart, Форсований Python 3.9+ (PPA/Source)\033[0m\n"
printf "\033[1;35m                           Гарантує розгортання виключно на x86_64 (amd64).\033[0m\n"
printf "\033[1;31m                           ⚠️ УВАГА: СУЧАСНІ ОС ТА ROLLING RELEASES ЖОРСТКО БЛОКУЮТЬСЯ!\033[0m\n"
printf "\033[1;35m=====================================================================================================\033[0m\n\n"

print_msg() { printf "\n\033[1;36m===> %s\033[0m\n" "$1"; }
print_err() { printf "\033[1;31m❌ ПОМИЛКА: %s\033[0m\n" "$1"; }
print_succ() { printf "\033[1;32m✅ %s\033[0m\n" "$1"; }

# ==========================================
# 1. ПІДГОТОВКА (PRE-FLIGHT & SMART CHECK)
# ==========================================
print_msg "1. Підготовка: Перевірка архітектури та Legacy-середовища..."

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
if [ "$ARCH" != "x86_64" ] && [ "$ARCH" != "amd64" ]; then
    print_err "Legacy-скрипт підтримує лише x86_64 (amd64)!"
    printf "\033[1;33mℹ️ Екосистема старих пакетів (Python/Docker) для '$ARCH' не є стабільною.\033[0m\n"
    exit 1
fi
print_succ "Апаратна архітектура: OK ($ARCH)"

# 1.3 Аналіз дистрибутива, Пакетного менеджера та Gatekeeper
PKG_MANAGER=""
if [ -f /etc/os-release ]; then
    . /etc/os-release
    MAJOR_VER=$(echo "$VERSION_ID" | cut -d. -f1)

    case "$ID" in
        alpine)
            print_err "Виявлено Alpine Linux."
            printf "\033[1;33mℹ️ Alpine використовує OpenRC та musl. Запустіть спеціалізований install_dev_tools_alpine.sh\033[0m\n"
            exit 1
            ;;
        ubuntu)
            PKG_MANAGER="apt-get"
            if [ "$MAJOR_VER" -ge 20 ]; then
                print_err "Виявлено сучасну $PRETTY_NAME!"
                printf "\033[1;33mℹ️ Запустіть install_dev_tools_linux.sh\033[0m\n"
                exit 1
            fi ;;
        debian)
            PKG_MANAGER="apt-get"
            if [ "$MAJOR_VER" -ge 11 ]; then
                print_err "Виявлено сучасний $PRETTY_NAME!"
                printf "\033[1;33mℹ️ Запустіть install_dev_tools_linux.sh\033[0m\n"
                exit 1
            fi ;;
        centos|rhel|almalinux|rocky)
            PKG_MANAGER="yum"
            if [ "$MAJOR_VER" -ge 8 ]; then
                print_err "Виявлено сучасну Enterprise-систему ($PRETTY_NAME)!"
                printf "\033[1;33mℹ️ Запустіть install_dev_tools_linux.sh\033[0m\n"
                exit 1
            fi ;;
        linuxmint|pop)
            PKG_MANAGER="apt-get"
            if [ "$MAJOR_VER" -ge 20 ]; then
                print_err "Виявлено сучасну $PRETTY_NAME!"
                printf "\033[1;33mℹ️ Запустіть install_dev_tools_linux.sh\033[0m\n"
                exit 1
            fi ;;
        opensuse*|suse|sles)
            PKG_MANAGER="zypper"
            if [ "$MAJOR_VER" -ge 15 ] && [ "$(echo "$VERSION_ID" | cut -d. -f2)" -ge 3 ]; then
                print_err "Виявлено сучасну $PRETTY_NAME!"
                printf "\033[1;33mℹ️ Версії 15.3+ та SLES 15 SP3+ розгортаються через install_dev_tools_linux.sh\033[0m\n"
                exit 1
            fi ;;
        arch|manjaro|endeavouros)
            print_err "Виявлено $PRETTY_NAME (Rolling Release)!"
            printf "\033[1;33mℹ️ Rolling Releases не мають Legacy-версій. Використовуйте install_dev_tools_linux.sh\033[0m\n"
            exit 1 ;;
    esac
    print_succ "ОС пройшла Legacy-перевірку: $PRETTY_NAME"
else
    print_msg "⚠️ Файл /etc/os-release відсутній. Система дуже стара. Визначаємо пакетний менеджер..."
fi

if [ -z "$PKG_MANAGER" ]; then
    if command -v apt-get >/dev/null 2>&1; then PKG_MANAGER="apt-get"
    elif command -v yum >/dev/null 2>&1; then PKG_MANAGER="yum"
    elif command -v zypper >/dev/null 2>&1; then PKG_MANAGER="zypper"
    else print_err "Знайдено невідому систему. Потрібен apt-get, yum або zypper."; exit 1; fi
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
if command -v python3.9 >/dev/null 2>&1; then PYTHON_BIN="python3.9"
elif command -v python3 >/dev/null 2>&1; then PYTHON_BIN="python3"
elif command -v python >/dev/null 2>&1; then PYTHON_BIN="python"; fi

if command -v docker >/dev/null 2>&1 && [ -n "$PYTHON_BIN" ] && [ -d "$VENV_DIR" ]; then
    VENV_PYTHON="$VENV_DIR/bin/python"
    PYTHON_OK=$($PYTHON_BIN -c "import sys; print('1' if sys.version_info >= ($PYTHON_MIN_MAJOR, $PYTHON_MIN_MINOR) else '0')" 2>/dev/null || echo "0")
    DJANGO_OK=$($VENV_PYTHON -c "import django; print('1' if django.__version__ == '$DJANGO_VERSION' else '0')" 2>/dev/null || echo "0")

    if [ "$PYTHON_OK" = "1" ] && [ "$DJANGO_OK" = "1" ]; then
        print_succ "СЕРЕДОВИЩЕ ВЖЕ НАЛАШТОВАНЕ ТА ІЗОЛЬОВАНЕ У '$VENV_DIR'!"
        printf -- "--------------------------------------------------------\n"
        printf "🐳 Docker Engine: " && docker --version 2>/dev/null || echo "\033[1;31mНе знайдено\033[0m"
        printf "🐙 Docker Compose (Legacy): " && docker-compose --version 2>/dev/null || echo "\033[1;31mНе знайдено\033[0m"
        if command -v systemctl >/dev/null 2>&1; then INIT_SYS="systemd"; else INIT_SYS="sysvinit/upstart"; fi
        printf "⚙️ Init System: \033[1;32m%s (Active)\033[0m\n" "$INIT_SYS"
        printf "   ↳ 🔐 Access Note: \033[1;35mЯкщо Docker потребує sudo, виконайте: newgrp docker\033[0m\n"
        printf "🐍 Python (Система): " && $PYTHON_BIN --version 2>/dev/null
        printf "🌍 Django (у VENV): " && "$VENV_PYTHON" -m django --version 2>/dev/null
        printf "\033[1;36m📂 Активація: . %s/bin/activate\033[0m\n" "$VENV_DIR"
        printf -- "--------------------------------------------------------\n"
        exit 0
    fi
fi

# ==========================================
# 2. ВСТАНОВЛЕННЯ DOCKER
# ==========================================
print_msg "2. Оновлення репозиторіїв та встановлення Legacy Docker..."
case "$PKG_MANAGER" in
    apt-get)
        $SUDO_CMD apt-get update -y -qq || printf "\033[1;33m⚠️ Деякі репозиторії недоступні (EOL). Продовжуємо...\033[0m\n"
        $SUDO_CMD apt-get install -y docker.io docker-compose
        ;;
    yum)
        $SUDO_CMD yum makecache fast -q || true
        if ! rpm -q epel-release >/dev/null 2>&1; then $SUDO_CMD yum install -y epel-release || true; fi
        $SUDO_CMD yum install -y docker docker-compose
        ;;
    zypper)
        $SUDO_CMD zypper refresh -q || true
        $SUDO_CMD zypper install -y docker docker-compose
        ;;
esac

print_msg "Запуск демона (Fallbacks: systemd -> sysvinit/upstart)..."
if command -v systemctl >/dev/null 2>&1; then
    $SUDO_CMD systemctl enable docker || true
    $SUDO_CMD systemctl start docker || true
else
    $SUDO_CMD service docker start || true
    if command -v chkconfig >/dev/null 2>&1; then $SUDO_CMD chkconfig docker on || true; fi
fi

$SUDO_CMD groupadd docker 2>/dev/null || true
$SUDO_CMD usermod -aG docker "$REAL_USER" || true
print_succ "Docker (Legacy) встановлено."

# ==========================================
# 3. ФОРСОВАНЕ ВСТАНОВЛЕННЯ PYTHON 3.9+ (NECROMANCER MODE)
# ==========================================
print_msg "3. Вживляємо Python $PYTHON_MIN_MAJOR.$PYTHON_MIN_MINOR у застарілу систему..."

case "$PKG_MANAGER" in
    apt-get)
        print_msg "Підключення PPA Deadsnakes для Ubuntu/Debian..."
        $SUDO_CMD apt-get install -y software-properties-common
        $SUDO_CMD add-apt-repository -y ppa:deadsnakes/ppa || true
        $SUDO_CMD apt-get update -y -qq || true
        $SUDO_CMD apt-get install -y python3.9 python3.9-venv python3.9-dev
        PYTHON_BIN="python3.9"
        ;;
    yum|zypper)
        print_msg "Компіляція Python 3.9 з вихідного коду для старих RPM-систем..."
        if [ "$PKG_MANAGER" = "yum" ]; then
            $SUDO_CMD yum install -y gcc openssl-devel bzip2-devel libffi-devel zlib-devel sqlite-devel make wget
        else
            $SUDO_CMD zypper install -y gcc libopenssl-devel bzip2 zlib-devel libffi-devel sqlite3-devel make wget
        fi
        if [ ! -f "/usr/local/bin/python3.9" ]; then
            wget -q https://www.python.org/ftp/python/3.9.18/Python-3.9.18.tgz
            tar -xzf Python-3.9.18.tgz
            cd Python-3.9.18
            ./configure --enable-optimizations >/dev/null
            $SUDO_CMD make altinstall >/dev/null
            cd .. && rm -rf Python-3.9.18*
        fi
        PYTHON_BIN="python3.9"
        ;;
esac

if ! command -v $PYTHON_BIN >/dev/null 2>&1; then
    print_err "Некромантія провалилася. Python 3.9 не встановлено."
    exit 1
fi
print_succ "Python рушій готовий: $($PYTHON_BIN --version 2>/dev/null)"

# ==========================================
# 4. ІЗОЛЯЦІЯ (VIRTUAL ENVIRONMENT)
# ==========================================
print_msg "4. Створення віртуального середовища..."
if ! $PYTHON_BIN -m venv "$VENV_DIR" 2>/dev/null; then
    print_msg "Вбудований модуль venv не спрацював. Fallback: virtualenv..."
    $SUDO_CMD $PKG_MANAGER install -y virtualenv >/dev/null 2>&1 || $SUDO_CMD $PYTHON_BIN -m pip install virtualenv -q
    virtualenv -p "$PYTHON_BIN" "$VENV_DIR" -q
fi
print_succ "Створено venv: $VENV_DIR"

VENV_PIP="$VENV_DIR/bin/pip"
$VENV_PIP install --upgrade pip -q
$VENV_PIP install "django==$DJANGO_VERSION" -q
print_succ "Django $DJANGO_VERSION встановлено в ізольоване середовище."

# ==========================================
# 5. ФІНАЛЬНИЙ ЗВІТ
# ==========================================
print_msg "✅ ЛЕГАСІ-СЕРЕДОВИЩЕ УСПІШНО РЕАНІМОВАНО! Ось ваш стек:"
printf -- "--------------------------------------------------------\n"
printf "🐳 Docker Engine: " && docker --version 2>/dev/null || echo "\033[1;31mНе знайдено\033[0m"
printf "🐙 Docker Compose (Legacy): " && docker-compose --version 2>/dev/null || echo "\033[1;31mНе знайдено\033[0m"

if command -v systemctl >/dev/null 2>&1; then INIT_SYS="systemd"; else INIT_SYS="sysvinit/upstart"; fi
printf "⚙️ Init System: \033[1;32m%s (Active)\033[0m\n" "$INIT_SYS"

printf "   ↳ 🔐 Access Note: \033[1;35mЯкщо Docker потребує sudo, виконайте: newgrp docker\033[0m\n"
printf "🐍 Python (Система): " && $PYTHON_BIN --version 2>/dev/null
printf "🌍 Django (у VENV): " && "$VENV_DIR/bin/python" -m django --version 2>/dev/null
printf "\033[1;36m📂 Активація: . %s/bin/activate\033[0m\n" "$VENV_DIR"
printf -- "--------------------------------------------------------\n"
