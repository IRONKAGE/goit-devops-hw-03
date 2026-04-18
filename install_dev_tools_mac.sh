#!/bin/zsh -f
set -e
setopt pipefail

# ==========================================
# 0. КОНСТАНТИ ТА ІНІЦІАЛІЗАЦІЯ
# ==========================================
if [[ -z "$_LOG_ACTIVE" ]]; then
    set -o pipefail
    _LOG_ACTIVE=1 exec /bin/zsh -f "$0" "$@" 2>&1 | tee -i setup_macos_legacy.log
    exit $?
fi

PYTHON_MIN_MAJOR=3
PYTHON_MIN_MINOR=9
DJANGO_VERSION="6.0.4"
VENV_DIR="ml_venv"
MIN_DISK_MB=10240  # 10 GB (Homebrew та Docker Desktop вимагають простору)

# ------------------------------------------
# INFRASTRUCTURE AS CODE (IaC) ANCHOR
# ------------------------------------------
printf "\n\033[1;35m=================================================================================================\033[0m\n"
printf "\033[1;35m[MACOS HYBRID PROVISIONER] Детерміністичне IaC-розгортання для macOS (10.15 Catalina - 26 Tahoe).\033[0m\n"
printf "\033[1;35m                           Architect: IRONKAGE\033[0m\n"
printf "\033[1;35m-------------------------------------------------------------------------------------------------\033[0m\n"
printf "\033[1;35m                           ОС: macOS (Catalina 10.15 - Tahoe 26)\033[0m\n"
printf "\033[1;35m                           Стек: Pure Homebrew, Docker Desktop (Cask), Python (venv)\033[0m\n"
printf "\033[1;35m                           Архітектура: Автовизначення (Apple Silicon / Intel)\033[0m\n"
printf "\033[1;35m=================================================================================================\033[0m\n\n"

print_msg() { printf "\n\033[1;36m===> %s\033[0m\n" "$1"; }
print_err() { printf "\033[1;31m❌ ПОМИЛКА: %s\033[0m\n" "$1"; }
print_succ() { printf "\033[1;32m✅ %s\033[0m\n" "$1"; }

# ==========================================
# 1. ПІДГОТОВКА (PRE-FLIGHT & SMART CHECK)
# ==========================================
print_msg "1. Підготовка: Перевірка архітектури та екосистеми macOS..."

# 1.1 Захист операційної системи
OS_TYPE=$(uname -s)
if [[ "$OS_TYPE" != "Darwin" ]]; then
    print_err "Цей скрипт призначений виключно для macOS (Darwin)."
    if [[ "$OS_TYPE" == "Linux" ]]; then
        printf "\033[1;33mℹ️ Знайдено Linux. Будь ласка, запустіть install_dev_tools_linux.sh\033[0m\n"
    elif [[ "$OS_TYPE" == "SunOS" ]]; then
        printf "\033[1;33mℹ️ Знайдено SunOS. Будь ласка, запустіть install_dev_tools_illumos.sh\033[0m\n"
    fi
    exit 1
fi

MAC_FULL_VER=$(sw_vers -productVersion)
MAC_MAJOR=${MAC_FULL_VER%%.*}
_TMP_VERS=${MAC_FULL_VER#*.}
MAC_VERS=${_TMP_VERS%%.*}

# Захист ПІДЛОГИ (Епоха Некромантії)
if [[ "$MAC_MAJOR" -lt 10 ]] || { [[ "$MAC_MAJOR" -eq 10 ]] && [[ "$MAC_VERS" -lt 15 ]]; }; then
    print_err "Ця macOS належить до епохи 'Некромантії' (до 10.15)."
    printf "\033[1;33mℹ️ Знайдено старе ядро. Будь ласка, запустіть install_dev_tools_mac_necromancy.sh\033[0m\n"
    exit 1
fi

# Захист СТЕЛІ (Епоха Майбутнього)
if [[ "$MAC_MAJOR" -ge 27 ]]; then
    print_err "Ця система належить до епохи чистого Apple Silicon (macOS $MAC_MAJOR+)."
    printf "\033[1;33mℹ️ Знайдено сучасну macOS. Будь ласка, запустіть install_dev_tools_mac.sh\033[0m\n"
    exit 1
fi

print_succ "ОС: Apple macOS ($MAC_FULL_VER)"

# 1.2 Автовизначення апаратної архітектури (Zero-Config)
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    print_succ "Апаратна архітектура: Apple Silicon (M-серія)"
    BREW_PATH="/opt/homebrew/bin/brew"
elif [[ "$ARCH" == "x86_64" ]]; then
    print_succ "Апаратна архітектура: Intel Mac"
    BREW_PATH="/usr/local/bin/brew"
else
    print_err "Невідома архітектура: $ARCH"
    exit 1
fi

# 1.3 Перевірка вільного місця
FREE_DISK=$(df -m . | awk 'NR==2 {print $4}')
if [[ "$FREE_DISK" -lt "$MIN_DISK_MB" ]]; then
    print_err "Мало місця на диску! Доступно $FREE_DISK MB, потрібно щонайменше $MIN_DISK_MB MB."
    exit 1
fi
print_succ "Місце на диску: OK ($FREE_DISK MB)"

# 1.4 Ініціалізація Homebrew (якщо він вже є в системі)
if [[ -x "$BREW_PATH" ]]; then
    eval "$("$BREW_PATH" shellenv)"
    print_succ "Пакетний менеджер: Homebrew ($(brew --version | head -n1))"
else
    printf "\033[1;33mℹ️ Homebrew не знайдено. Буде встановлено автоматично.\033[0m\n"
fi

# 1.5 Smart Check (Швидкий вихід)
PYTHON_BIN=""
if command -v python3 >/dev/null 2>&1; then PYTHON_BIN="python3"; fi

if command -v brew >/dev/null 2>&1 && command -v docker >/dev/null 2>&1 && [[ -n "$PYTHON_BIN" ]] && [[ -d "$VENV_DIR" ]]; then
    VENV_PYTHON="$VENV_DIR/bin/python"
    PYTHON_OK=$($PYTHON_BIN -c "import sys; print('1' if sys.version_info >= ($PYTHON_MIN_MAJOR, $PYTHON_MIN_MINOR) else '0')" 2>/dev/null || echo "0")
    DJANGO_OK=$($VENV_PYTHON -c "import django; print('1' if django.__version__ == '$DJANGO_VERSION' else '0')" 2>/dev/null || echo "0")

    if [[ "$PYTHON_OK" == "1" ]] && [[ "$DJANGO_OK" == "1" ]]; then
        print_succ "СЕРЕДОВИЩЕ MACOS ВЖЕ НАЛАШТОВАНЕ ТА ІЗОЛЬОВАНЕ У '$VENV_DIR'!"
        printf -- "-------------------------------------------------------------------------------------------------\n"
        printf "🍺 Homebrew: " && brew --version | head -n1
        printf "🐳 Docker Desktop: " && docker --version 2>/dev/null || printf "\033[1;31mНе запущено. Відкрийте Launchpad!\033[0m\n"
        printf "🐙 Docker Compose: " && (docker compose version 2>/dev/null || docker-compose --version 2>/dev/null)
        printf "   ↳ 🏗️ Ops Note: \033[1;35mЯкщо Docker не відповідає, запустіть 'Docker' через Launchpad (Spotlight).\033[0m\n"
        printf "🐍 Python (Система): " && $PYTHON_BIN --version 2>/dev/null
        printf "🌍 Django (у VENV): " && "$VENV_PYTHON" -m django --version 2>/dev/null
        printf "\033[1;36m📂 Активація: . %s/bin/activate\033[0m\n" "$VENV_DIR"
        printf -- "-------------------------------------------------------------------------------------------------\n"
        exit 0
    fi
fi

# ==========================================
# 2. ВСТАНОВЛЕННЯ СИСТЕМНИХ ЗАЛЕЖНОСТЕЙ
# ==========================================
print_msg "2. Перевірка та встановлення Homebrew..."
if ! command -v brew >/dev/null 2>&1; then
    print_msg "Починаємо автоматичне встановлення Homebrew (може знадобитися пароль sudo)..."
    NONINTERACTIVE=1 /bin/zsh -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    eval "$("$BREW_PATH" shellenv)"
    print_succ "Homebrew успішно встановлено."
else
    print_succ "Homebrew вже встановлено. Оновлення індексів..."
    brew update -q
fi

print_msg "Встановлення Docker Desktop (через Homebrew Cask)..."
if ! brew list --cask docker &>/dev/null; then
    brew install --cask docker
    print_succ "Docker Desktop встановлено."
    printf "\033[1;33m⚠️ УВАГА: На macOS Docker не є фоновою службою. Вам потрібно запустити 'Docker' з папки Applications (Launchpad) хоча б один раз!\033[0m\n"
else
    print_succ "Docker Desktop вже встановлено (Skip)."
fi

# ==========================================
# 3. ВСТАНОВЛЕННЯ PYTHON
# ==========================================
print_msg "3. Встановлення/оновлення Python $PYTHON_MIN_MAJOR.$PYTHON_MIN_MINOR+ ..."
# Ставимо стабільну версію для ML
if ! brew list python@3.11 &>/dev/null; then
    brew install python@3.11 -q
else
    print_succ "Python 3.11 вже встановлено через Homebrew (Skip)."
fi

PYTHON_BIN="python3.11"

if ! command -v $PYTHON_BIN >/dev/null 2>&1; then
    PYTHON_BIN="python3" # Fallback
fi
print_succ "Python рушій готовий: $($PYTHON_BIN --version)"

# ==========================================
# 4. ІЗОЛЯЦІЯ (VIRTUAL ENVIRONMENT)
# ==========================================
print_msg "4. Створення віртуального середовища..."
if [[ ! -d "$VENV_DIR" ]]; then
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
print_msg "✅ СЕРЕДОВИЩЕ MACOS УСПІШНО НАЛАШТОВАНО! Ось ваш стек:"
printf -- "-------------------------------------------------------------------------------------------------\n"
printf "🍺 Homebrew: " && brew --version | head -n1
printf "🐳 Docker Desktop: " && docker --version 2>/dev/null || printf "\033[1;31mНе запущено. Відкрийте Docker з Launchpad!\033[0m\n"
printf "🐙 Docker Compose: " && (docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || printf "\033[1;31mНе знайдено\033[0m\n")
printf "   ↳ 🏗️ Ops Note: \033[1;35mЯкщо Docker не відповідає, запустіть 'Docker' через Launchpad (Spotlight).\033[0m\n"
printf "🐍 Python (Система): " && $PYTHON_BIN --version 2>/dev/null
printf "🌍 Django (у VENV): " && "$VENV_DIR/bin/python" -m django --version 2>/dev/null
printf "\033[1;36m📂 Активація: . %s/bin/activate\033[0m\n" "$VENV_DIR"
printf -- "-------------------------------------------------------------------------------------------------\n"
