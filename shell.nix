# ===========================================================================
# Environment: MLOps Development Shell
# Description: Declarative, reproducible environment for AI/ML engineering.
# Usage:       Run `nix-shell` in this directory to activate the workspace.
# ===========================================================================

{ pkgs ? import <nixpkgs> {} }:

let
  # ==========================================
  # 0. КОНСТАНТИ ТА ІНІЦІАЛІЗАЦІЯ
  # ==========================================
  minPythonVersion = "3.9";
  djangoVersion = "6.0.4";
  venvDir = "ml_venv";
  pythonBase = pkgs.python3;

  # ==========================================
  # 1. ПІДГОТОВКА (PRE-FLIGHT & SMART CHECK)
  # ==========================================
  pythonEnv = pythonBase.withPackages (ps: with ps; [
    pip
    virtualenv
  ]);
in
pkgs.mkShell {
  name = "mlops-dev-env";

  # ==========================================
  # 2. ВСТАНОВЛЕННЯ СИСТЕМНИХ ЗАЛЕЖНОСТЕЙ
  # ==========================================
  buildInputs = [
    pkgs.docker
    pkgs.docker-compose

    # ==========================================
    # 3. ВСТАНОВЛЕННЯ PYTHON
    # ==========================================
    pythonEnv
  ];

  shellHook = ''
    set -e
    set -o pipefail

    CURRENT_PY_VER=$(python -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    MARKER_FILE="${venvDir}/.ready"

    # ==========================================
    # 4. ІЗОЛЯЦІЯ (VIRTUAL ENVIRONMENT)
    # ==========================================
    if [ ! -f "$MARKER_FILE" ]; then
        echo -e "\n\033[1;35m⚙️ 4. Створення venv та встановлення Django ${djangoVersion}...\033[0m" | tee -a setup.log

        rm -rf "${venvDir}"

        python -m venv "${venvDir}" 2>&1 | tee -a setup.log

        source "${venvDir}/bin/activate"

        pip install --upgrade pip -q 2>&1 | tee -a setup.log
        pip install "django==${djangoVersion}" -q 2>&1 | tee -a setup.log

        touch "$MARKER_FILE"
        echo "✅ VENV створено успішно" >> setup.log
    else
        source "${venvDir}/bin/activate"
    fi

    # ==========================================
    # 5. ФІНАЛЬНИЙ ЗВІТ
    # ==========================================
    echo -e "\n\033[1;36m===> ✅ 5. СЕРЕДОВИЩЕ АКТИВОВАНО (Nix Native) <===\033[0m"
    echo "--------------------------------------------------------"
    echo -e "💡 Статус: Встановлено актуальний Python $CURRENT_PY_VER (Мін. вимога: ${minPythonVersion})"
    echo -n "🐳 Docker: "; docker --version 2>/dev/null || echo "Не знайдено"
    echo -n "🐙 Docker Compose: "; docker compose version 2>/dev/null || echo "Не знайдено"
    echo -n "🐍 Python (у VENV): "; python --version
    echo -n "🌍 Django (у VENV): "; python -m django --version
    echo "--------------------------------------------------------"
    echo -e "\033[1;33m Ops Note: Ви знаходитесь в ізольованому Nix Shell + VENV. Щоб вийти, введіть 'exit'. \033[0m\n"
  '';
}
