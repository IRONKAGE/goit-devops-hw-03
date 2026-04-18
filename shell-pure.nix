/* MLOps Development Shell (Pure)
   Provides a reproducible environment with Python, Django, and Docker CLI.
   Usage: nix-shell shell-pure.nix
*/

{ pkgs ? import <nixpkgs> {} }:

let
  djangoVersion = "6.0.4";
  venvDir = ".venv";

  pythonEnv = pkgs.python3.withPackages (ps: [
    ps.pip
    ps.virtualenv
  ]);
in
pkgs.mkShell {
  name = "mlops-shell";

  buildInputs = with pkgs; [
    pythonEnv
    docker
    docker-compose
  ];

  shellHook = ''
    # Bootstrap the virtual environment if it doesn't exist
    if [ ! -d "${venvDir}" ]; then
      echo "⚙️  Bootstrapping venv with Django ${djangoVersion}..."
      python -m venv ${venvDir}
      ${venvDir}/bin/pip install -U pip -q
      ${venvDir}/bin/pip install "django==${djangoVersion}" -q
    fi

    source ${venvDir}/bin/activate

    # Minimalist status output
    echo "❄️  Nix Shell Active [Py: $(python -c 'import platform; print(platform.python_version())') | Django: $(django-admin --version)]"
  '';
}
