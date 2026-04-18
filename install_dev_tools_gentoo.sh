#!/bin/sh
set -e

# ==========================================
# 0. КОНСТАНТИ ТА ІНІЦІАЛІЗАЦІЯ
# ==========================================
if [ -z "$_LOG_ACTIVE" ]; then
    _LOG_ACTIVE=1 exec /bin/sh "$0" "$@" 2>&1 | tee -i setup_gentoo.log
    exit $?
fi

PYTHON_MIN_MAJOR=3
PYTHON_MIN_MINOR=9
DJANGO_VERSION="6.0.4"
VENV_DIR="ml_venv"
MIN_DISK_MB=10240  # 10 GB (Компіляція з вихідного коду (Portage) вимагає значно більше місця)
# Налаштування цільової архітектури (Architecture Policy Engine) - чисто для демонстрації гнучкості Gentoo у порівнянні з іншими дистрибутивами:
# Доступні політики:
#   "ML_SET"  - Тільки x86_64 (amd64) та aarch64 (arm64). Ідеально для Machine Learning (Docker + Python Wheels).
#   "ALL_64"  - Будь-які 64-бітні системи (x86_64, aarch64, ppc64le, sparc64, mips64, riscv64, alpha, s390x).
#   "ANY"     - Абсолютно всі платформи, що підтримуються Gentoo (вкл. IA-32, m68k, PA-RISC, ARM 32).
#   "..."     - Або вкажіть конкретну архітектуру (наприклад, "riscv64", "ppc64le", "loongarch64").
TARGET_ARCH_MODE="ML_SET"

# ------------------------------------------
# INFRASTRUCTURE AS CODE (IaC) ANCHOR
# ------------------------------------------
printf "\n\033[1;35m===============================================================================================\033[0m\n"
printf "\033[1;35m[GENTOO LINUX PROVISIONER] Детерміністичне IaC-розгортання для Gentoo Linux (Source-based).\033[0m\n"
printf "\033[1;35m                           Architect: IRONKAGE\033[0m\n"
printf "\033[1;35m-----------------------------------------------------------------------------------------------\033[0m\n"
printf "\033[1;35m                           ОС: Gentoo Linux (Rolling Release / Meta-distribution)\033[0m\n"
printf "\033[1;35m                           Стек: Portage (emerge), OpenRC / systemd, Python (venv)\033[0m\n"
printf "\033[1;35m                           Гарантує розгортання виключно на x86_64 (amd64) або aarch64 (arm64).\033[0m\n"
printf "\033[1;31m                           ⚠️ ІНШІ АРХІТЕКТУРИ: ppc, sparc, risc-v та інші... (Here be dragons).\033[0m\n"
printf "\033[1;31m                           Архітектура визначається на свій страх і ризик: [TARGET_ARCH_MODE].\033[0m\n"
printf "\033[1;31m                           ⚠️ УВАГА: ВСТАНОВЛЕННЯ DOCKER ПОТРЕБУЄ КОМПІЛЯЦІЇ З ВИХІДНОГО КОДУ!\033[0m\n"
printf "\033[1;35m===============================================================================================\033[0m\n\n"

print_msg() { printf "\n\033[1;36m===> %s\033[0m\n" "$1"; }
print_err() { printf "\033[1;31m❌ ПОМИЛКА: %s\033[0m\n" "$1"; }
print_succ() { printf "\033[1;32m✅ %s\033[0m\n" "$1"; }

# ==========================================
# 1. ПІДГОТОВКА (PRE-FLIGHT & SMART CHECK)
# ==========================================
print_msg "1. Підготовка: Перевірка архітектури Gentoo Linux..."

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

if ! command -v emerge >/dev/null 2>&1; then
    print_err "Це не Gentoo Linux (відсутній пакетний менеджер emerge/Portage)!"
    printf "\033[1;33mℹ️ Для інших дистрибутивів використовуйте install_dev_tools_linux.sh\033[0m\n"
    exit 1
fi

# 1.2 Перевірка апаратної архітектури згідно з політикою (Policy Engine)
ARCH=$(uname -m)
print_msg "Перевірка архітектурної політики: [$TARGET_ARCH_MODE] (Поточна ОС: $ARCH)..."

case "$TARGET_ARCH_MODE" in
    "ML_SET")
        case "$ARCH" in
            x86_64|amd64|aarch64|arm64) print_succ "Архітектура $ARCH підтримується політикою ML_SET." ;;
            *) print_err "Політика ML_SET вимагає x86_64 або arm64! Знайдено: $ARCH"
               printf "\033[1;33mℹ️ Екосистема Machine Learning (Docker, PyTorch) є нестабільною на цій платформі.\033[0m\n"
               exit 1 ;;
        esac
        ;;
    "ALL_64")
        # Шукаємо "64" у назві, плюс обробляємо специфічні 64-бітні мейнфрейми (alpha, s390x)
        case "$ARCH" in
            *64*|aarch64|amd64|alpha|s390x) print_succ "64-бітна архітектура $ARCH підтверджена." ;;
            *) print_err "Політика ALL_64 вимагає 64-бітний процесор! Знайдено: $ARCH"
               exit 1 ;;
        esac
        ;;
    "ANY")
        printf "\033[1;33m⚠️ УВАГА: Архітектурний контроль ВИМКНЕНО. Підтримується повна матриця платформ.\033[0m\n"
        ;;
    *)
        # Режим точного співпадіння (Specific Architecture) з урахуванням синонімів
        if [ "$ARCH" = "$TARGET_ARCH_MODE" ] || \
           ([ "$TARGET_ARCH_MODE" = "amd64" ] && [ "$ARCH" = "x86_64" ]) || \
           ([ "$TARGET_ARCH_MODE" = "arm64" ] && [ "$ARCH" = "aarch64" ]); then
            print_succ "Архітектура точно відповідає заданій політиці: $ARCH"
        else
            print_err "Політика вимагає строго '$TARGET_ARCH_MODE', але знайдено '$ARCH'."
            exit 1
        fi
        ;;
esac

# 1.3 Перевірка вільного місця на диску (Portage потребує багато місця для tmpfs/build)
FREE_DISK=$(df -m . | awk 'NR==2 {print $4}')
if [ "$FREE_DISK" -lt "$MIN_DISK_MB" ]; then
    print_err "Мало місця на диску! Доступно $FREE_DISK MB, потрібно щонайменше $MIN_DISK_MB MB."
    exit 1
fi
print_succ "Місце на диску: OK ($FREE_DISK MB)"

# Налаштування sudo та ідентифікація Init-системи (OpenRC vs systemd)
SUDO_CMD="sudo"
if [ "$(id -u)" -eq 0 ]; then SUDO_CMD=""; fi
REAL_USER=${SUDO_USER:-$USER}

if [ -d /run/systemd/system ]; then INIT_SYS="systemd"
elif command -v rc-service >/dev/null 2>&1; then INIT_SYS="OpenRC"
else INIT_SYS="unknown"; fi

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
        printf "🐙 Docker Compose: " && (docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || echo "\033[1;31mНе знайдено\033[0m")
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
# 2. ВСТАНОВЛЕННЯ СИСТЕМНИХ ЗАЛЕЖНОСТЕЙ
# ==========================================
print_msg "2. Синхронізація дерева Portage та встановлення Docker..."
print_msg "⚠️ ЗВЕРНІТЬ УВАГУ: Компіляція Docker з вихідного коду може зайняти від 15 хвилин до кількох годин залежно від CPU!"

$SUDO_CMD emaint sync -A -q || $SUDO_CMD emerge --sync -q

if command -v docker >/dev/null 2>&1; then
    print_succ "Docker вже встановлено."
else
    # --quiet-build приховує нескінченний потік компіляції, залишаючи лише прогрес
    $SUDO_CMD emerge --ask=n --quiet-build=y app-containers/docker app-containers/docker-compose

    print_msg "Активація Docker демона ($INIT_SYS)..."
    if [ "$INIT_SYS" = "systemd" ]; then
        $SUDO_CMD systemctl enable --now docker || true
    elif [ "$INIT_SYS" = "OpenRC" ]; then
        $SUDO_CMD rc-update add docker default || true
        $SUDO_CMD rc-service docker start || true
    else
        printf "\033[1;33m⚠️ Не вдалося визначити Init-систему. Запустіть Docker-демон вручну.\033[0m\n"
    fi
    print_succ "Docker встановлено."
fi

print_msg "Налаштування прав Docker (Post-install)..."
$SUDO_CMD groupadd docker 2>/dev/null || true
$SUDO_CMD usermod -aG docker "$REAL_USER"
print_succ "Користувача '$REAL_USER' додано до групи 'docker'."

# ==========================================
# 3. ВСТАНОВЛЕННЯ PYTHON
# ==========================================
print_msg "3. Встановлення глобального Python $PYTHON_MIN_MAJOR.$PYTHON_MIN_MINOR+ ..."
# У Gentoo Python є завжди (це залежність самого Portage), але нам потрібен PIP
# --noreplace гарантує, що якщо пакет вже є, компіляція не почнеться заново
$SUDO_CMD emerge --ask=n --noreplace --quiet-build=y dev-lang/python dev-python/pip
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
print_msg "✅ СЕРЕДОВИЩЕ GENTOO УСПІШНО НАЛАШТОВАНО! Ось ваш стек:"
printf -- "--------------------------------------------------------\n"
printf "🐳 Docker Engine: " && docker --version 2>/dev/null || echo "\033[1;31mНе знайдено\033[0m"
printf "🐙 Docker Compose: " && (docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || echo "\033[1;31mНе знайдено\033[0m")
printf "⚙️ Init System: \033[1;32m%s (Active)\033[0m\n" "$INIT_SYS"
printf "   ↳ 🔐 Access Note: \033[1;35mЯкщо Docker потребує sudo, виконайте: newgrp docker\033[0m\n"
printf "🐍 Python (Система): " && $PYTHON_BIN --version 2>/dev/null
printf "🌍 Django (у VENV): " && "$VENV_DIR/bin/python" -m django --version 2>/dev/null
printf "\033[1;36m📂 Активація: . %s/bin/activate\033[0m\n" "$VENV_DIR"
printf -- "--------------------------------------------------------\n"
