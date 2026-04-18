#!/bin/sh
set -e

# ==========================================
# 0. КОНСТАНТИ ТА ІНІЦІАЛІЗАЦІЯ
# ==========================================
if [ -z "$_LOG_ACTIVE" ]; then
    _LOG_ACTIVE=1 exec /bin/sh "$0" "$@" 2>&1 | tee -i setup_alpine.log  # Записувати всі дії у файл (Alpine-специфічний лог)
    exit $?
fi

PYTHON_MIN_MAJOR=3
PYTHON_MIN_MINOR=9
DJANGO_VERSION="6.0.4"
VENV_DIR="ml_venv"
MIN_DISK_MB=5120  # 5 GB для Docker, Python та пакетів

# ------------------------------------------
# INFRASTRUCTURE AS CODE (IaC) ANCHOR
# ------------------------------------------
printf "\n\033[1;35m==============================================================================================\033[0m\n"
printf "\033[1;35m[EDGE RUNTIME BOOTSTRAP] Детерміністичне IaC-розгортання для Alpine Linux.\033[0m\n"
printf "\033[1;35m                         Architect: IRONKAGE\033[0m\n"
printf "\033[1;35m----------------------------------------------------------------------------------------------\033[0m\n"
printf "\033[1;35m                         ОС: Alpine Linux (v3.16+ / musl libc)\033[0m\n"
printf "\033[1;35m                         Стек: OCI-рушій (Docker), ізольований Python, C/C++ toolchain\033[0m\n"
printf "\033[1;35m                         Гарантує апаратну агностичність (x86_64 / aarch64) для AI-ворклоудів.\033[0m\n"
printf "\033[1;35m==============================================================================================\033[0m\n\n"

print_msg() { printf "\n\033[1;36m===> %s\033[0m\n" "$1"; }
print_err() { printf "\033[1;31m❌ ПОМИЛКА: %s\033[0m\n" "$1"; }
print_succ() { printf "\033[1;32m✅ %s\033[0m\n" "$1"; }

# ==========================================
# 1. ПІДГОТОВКА (PRE-FLIGHT & SMART CHECK)
# ==========================================
print_msg "1. Підготовка: Перевірка ресурсів та ОС (Alpine/musl)..."

# 1.1 Перевірка ОС (тільки Alpine) та її версії (Мінімум 3.16)
if [ ! -f "/etc/alpine-release" ]; then
    print_err "Цей скрипт призначений виключно для Alpine Linux."

    if [ -f "/etc/os-release" ]; then
        CURRENT_OS=$(grep -E '^PRETTY_NAME=' /etc/os-release | cut -d '=' -f 2 | tr -d '"')
    else
        RAW_OS=$(uname -s)
        if [ "$RAW_OS" = "Darwin" ]; then
            if command -v sw_vers >/dev/null 2>&1; then
                CURRENT_OS="macOS $(sw_vers -productVersion)"
            else
                CURRENT_OS="macOS (Darwin Core)"
            fi
        else
            CURRENT_OS="$RAW_OS"
        fi
    fi

    printf "\033[1;33mВи намагаєтесь запустити його на ОС: %s\033[0m\n" "${CURRENT_OS:-Невідома система}"
    exit 1
fi

# 1.2 Перевірка ядра Linux (Мінімум 3.10 для Docker)
KERNEL_VER=$(uname -r | cut -d- -f1)
K_MAJOR=$(echo "$KERNEL_VER" | cut -d. -f1)
K_MINOR=$(echo "$KERNEL_VER" | cut -d. -f2)

if [ "$K_MAJOR" -lt 3 ] || { [ "$K_MAJOR" -eq 3 ] && [ "$K_MINOR" -lt 10 ]; }; then
    print_err "Версія ядра ($KERNEL_VER) занадто стара для Docker. Потрібно >= 3.10."
    exit 1
fi
print_succ "Ядро Linux: OK ($KERNEL_VER)"

# 1.3 Перевірка оперативної пам'яті (Мінімум 2048 MB)
TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
if [ "$TOTAL_RAM" -lt 2048 ]; then
    print_err "Критично мало RAM ($TOTAL_RAM MB). Для Docker та ML потрібно мінімум 2048 MB."
    exit 1
fi
print_succ "Пам'ять (RAM): OK ($TOTAL_RAM MB)"

# 1.4 Перевірка архітектури (Блокуємо 32-бітні та старі ARM)
SYS_ARCH=$(uname -m)
if [ "$SYS_ARCH" != "x86_64" ] && [ "$SYS_ARCH" != "aarch64" ]; then
    print_err "Архітектура $SYS_ARCH не підтримується! Потрібно x86_64 або aarch64."
    exit 1
fi
print_succ "Архітектура: OK ($SYS_ARCH)"

# 1.5 Перевірка вільного місця на диску
FREE_DISK=$(df -m . | awk 'NR==2 {print $4}')
if [ "$FREE_DISK" -lt "$MIN_DISK_MB" ]; then
    print_err "Мало місця на диску! Доступно $FREE_DISK MB, потрібно щонайменше $MIN_DISK_MB MB."
    exit 1
fi
print_succ "Місце на диску: OK ($FREE_DISK MB)"

# 1.6 Smart Check (Швидкий вихід)
PYTHON_BIN=""
if command -v python3 >/dev/null 2>&1; then PYTHON_BIN="python3"; fi

if command -v docker >/dev/null 2>&1 && [ -n "$PYTHON_BIN" ] && [ -d "$VENV_DIR" ]; then
    VENV_PYTHON="$VENV_DIR/bin/python"
    PYTHON_OK=$($PYTHON_BIN -c "import sys; print('1' if sys.version_info >= ($PYTHON_MIN_MAJOR, $PYTHON_MIN_MINOR) else '0')" 2>/dev/null || echo "0")
    DJANGO_OK=$($VENV_PYTHON -c "import django; print('1' if django.__version__ == '$DJANGO_VERSION' else '0')" 2>/dev/null || echo "0")

    if [ "$PYTHON_OK" = "1" ] && [ "$DJANGO_OK" = "1" ]; then
        print_succ "СЕРЕДОВИЩЕ ВЖЕ НАЛАШТОВАНЕ ТА ІЗОЛЬОВАНЕ У '$VENV_DIR'!"
        printf -- "--------------------------------------------------------\n"
        printf "🐳 Docker: " && docker --version 2>/dev/null || echo "Не знайдено"
        printf "🐙 Docker Compose: " && docker compose version 2>/dev/null || echo "Не знайдено"
        printf "🐍 Python (Система): " && $PYTHON_BIN --version 2>/dev/null
        printf "🌍 Django (у VENV): " && "$VENV_PYTHON" -m django --version 2>/dev/null
        printf "\033[1;36m📂 Для початку роботи виконайте: . %s/bin/activate\033[0m\n" "$VENV_DIR"
        printf -- "--------------------------------------------------------\n"
        exit 0
    fi
fi

# Визначення утиліти для підвищення прав
SUDO_CMD="doas"
if command -v sudo >/dev/null 2>&1; then SUDO_CMD="sudo"; fi
if [ "$(id -u)" -eq 0 ]; then SUDO_CMD=""; fi

# ==========================================
# 2. ВСТАНОВЛЕННЯ СИСТЕМНИХ ЗАЛЕЖНОСТЕЙ
# ==========================================
print_msg "2. Оновлення індексів пакетів (apk) та налаштування Docker..."
$SUDO_CMD apk update -q

if command -v docker >/dev/null 2>&1; then
    print_succ "Docker вже встановлено."
else
    # Alpine використовує OpenRC замість systemd
    $SUDO_CMD apk add docker docker-cli-compose
    $SUDO_CMD rc-update add docker boot
    $SUDO_CMD rc-service docker start || true
    print_succ "Docker встановлено."

    print_msg "Налаштування прав Docker (Post-install)..."
    $SUDO_CMD addgroup "${USER:-$(whoami)}" docker || true
    print_succ "Користувача додано до групи 'docker'."
fi

# ==========================================
# 3. ВСТАНОВЛЕННЯ PYTHON
# ==========================================
print_msg "3. Налаштування Python $PYTHON_MIN_MAJOR.$PYTHON_MIN_MINOR+ та Build-Tools..."
# gcc, musl-dev та linux-headers обов'язкові для збірки ML бібліотек (numpy, pandas тощо) на Alpine
$SUDO_CMD apk add -q python3 py3-pip python3-dev gcc musl-dev linux-headers
PYTHON_BIN="python3"
print_succ "Python та компілятори C/C++ готові."

# ==========================================
# 4. ІЗОЛЯЦІЯ (VIRTUAL ENVIRONMENT)
# ==========================================
print_msg "4. Створення віртуального середовища та встановлення Django..."
if [ ! -d "$VENV_DIR" ]; then
    $PYTHON_BIN -m venv "$VENV_DIR"
    print_succ "Створено venv: $VENV_DIR"
fi

VENV_PIP="$VENV_DIR/bin/pip"
$VENV_PIP install --upgrade pip -q
$VENV_PIP install "django==$DJANGO_VERSION" -q
print_succ "Django встановлено в ізольоване середовище."

# ==========================================
# 5. ФІНАЛЬНИЙ ЗВІТ
# ==========================================
print_msg "✅ СЕРЕДОВИЩЕ УСПІШНО НАЛАШТОВАНО! Ось ваш стек:"
printf -- "--------------------------------------------------------\n"
printf "🐳 Docker: " && docker --version 2>/dev/null || echo "Не знайдено"
printf "🐙 Docker Compose: " && docker compose version 2>/dev/null || echo "Не знайдено"
printf "🐍 Python (Система): " && $PYTHON_BIN --version 2>/dev/null
printf "🌍 Django (у VENV): " && "$VENV_DIR/bin/python" -m django --version 2>/dev/null
printf "\033[1;36m📂 Для початку роботи виконайте: . %s/bin/activate\033[0m\n" "$VENV_DIR"
printf -- "--------------------------------------------------------\n"
