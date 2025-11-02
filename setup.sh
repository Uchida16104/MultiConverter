#!/usr/bin/env bash
# MultiConverter universal setup script
# - Clones/downloads repo using git or curl/wget
# - Installs required tools where possible (Node, npm, PHP, Composer, TypeScript, tailwind, sql.js, sass, less)
# - Creates minimal composer.json if missing
# - Installs npm & composer dependencies
# - Runs `npm run dev`
#
# Run as: chmod +x setup.sh && sudo ./setup.sh
# (script will detect if sudo is needed; you may run it from a non-root account if your system allows sudo)

set -euo pipefail
IFS=$'\n\t'

REPO_URL="https://github.com/Uchida16104/MultiConverter"
REPO_ZIP_URL="$REPO_URL/archive/refs/heads/main.zip"
REPO_DIR="MultiConverter"
LOGFILE="./multiconverter-setup.log"

echo "=== MultiConverter Universal Setup ==="
echo "Logging to $LOGFILE"
exec > >(tee -a "$LOGFILE") 2>&1

# --- utilities ---
function hint_run_as_root() {
  echo ""
  echo "NOTE: this script will ask for sudo when needed. If you prefer to run part-by-part, do so manually."
  echo ""
}

function command_exists() {
  command -v "$1" >/dev/null 2>&1
}

function require_cmd() {
  if ! command_exists "$1"; then
    echo "Error: required command '$1' not found. Please install it and re-run the script."
    exit 1
  fi
}

# --- detect OS & package manager ---
PKG_MANAGER=""
OS_ID=""
function detect_os() {
  echo "Detecting OS and available package manager..."
  if [ "$(uname -s)" = "Darwin" ]; then
    OS_ID="macos"
    if command_exists brew; then
      PKG_MANAGER="brew"
    else
      PKG_MANAGER=""
    fi
  elif [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    if command_exists apt-get; then
      PKG_MANAGER="apt"
    elif command_exists dnf; then
      PKG_MANAGER="dnf"
    elif command_exists yum; then
      PKG_MANAGER="yum"
    elif command_exists pacman; then
      PKG_MANAGER="pacman"
    elif command_exists zypper; then
      PKG_MANAGER="zypper"
    elif command_exists apk; then
      PKG_MANAGER="apk"
    elif command_exists emerge; then
      PKG_MANAGER="emerge"
    else
      PKG_MANAGER=""
    fi
  elif [ -n "${TERMUX_VERSION:-}" ]; then
    OS_ID="termux"
    PKG_MANAGER="pkg"
  else
    OS_ID="$(uname -s)-unknown"
    PKG_MANAGER=""
  fi
  echo "Detected OS: $OS_ID, package manager: $PKG_MANAGER"
}
detect_os

# --- install helpers for different package managers ---
function install_pkg() {
  # install packages list passed as parameters
  local pkgs=("$@")
  echo "--- Installing packages: ${pkgs[*]} ---"
  case "$PKG_MANAGER" in
    apt)
      sudo apt-get update -y
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
      ;;
    dnf)
      sudo dnf install -y "${pkgs[@]}"
      ;;
    yum)
      sudo yum install -y "${pkgs[@]}"
      ;;
    pacman)
      sudo pacman -Sy --noconfirm "${pkgs[@]}"
      ;;
    apk)
      sudo apk add --no-cache "${pkgs[@]}"
      ;;
    zypper)
      sudo zypper --non-interactive install "${pkgs[@]}"
      ;;
    brew)
      for p in "${pkgs[@]}"; do
        brew list "$p" >/dev/null 2>&1 || brew install "$p"
      done
      ;;
    pkg) # Termux
      pkg install -y "${pkgs[@]}"
      ;;
    emerge)
      sudo emerge --ask "${pkgs[@]}"
      ;;
    *)
      echo "No known package manager detected; please install these packages manually: ${pkgs[*]}"
      return 1
      ;;
  esac
}

# --- Ensure basic build tools ---
echo "Ensuring basic dev tools (git, curl, wget, ca-certificates, build-essential where applicable)..."

case "$PKG_MANAGER" in
  apt) install_pkg git curl wget ca-certificates build-essential ;;
  dnf|yum) install_pkg git curl wget ca-certificates make gcc gcc-c++ ;;
  pacman) install_pkg git curl wget base-devel ca-certificates ;;
  apk) install_pkg git curl wget build-base ca-certificates ;;
  brew) install_pkg git curl wget ;;
  pkg) install_pkg git curl wget proot-distro ;;
  zypper) install_pkg git curl wget gcc make ;;
  emerge) install_pkg git net-misc/curl net-misc/wget sys-devel/gcc ;;
  *) echo "Please ensure git, curl and wget are installed manually." ;;
esac || true

# --- clone or download repo ---
function get_repo() {
  echo "Fetching repository..."
  if command_exists git; then
    if [ -d "$REPO_DIR" ]; then
      echo "Directory $REPO_DIR exists. Attempting to git pull..."
      (cd "$REPO_DIR" && git pull --ff-only) || true
    else
      git clone "$REPO_URL.git" "$REPO_DIR" || {
        echo "git clone failed, will attempt to download zip via curl/wget..."
        download_zip
      }
    fi
  else
    echo "git not available; downloading zip..."
    download_zip
  fi
}

function download_zip() {
  if command_exists curl; then
    curl -L -o main.zip "$REPO_ZIP_URL"
  elif command_exists wget; then
    wget -O main.zip "$REPO_ZIP_URL"
  else
    echo "Neither git, curl, nor wget are available to fetch the repo. Install one and retry."
    exit 1
  fi
  # unzip extraction
  if command_exists unzip; then
    unzip -o main.zip
  elif command_exists bsdtar; then
    bsdtar -xf main.zip
  else
    echo "unzip not found. Attempting to use python to extract zip..."
    python3 - <<PY
import zipfile, sys
with zipfile.ZipFile('main.zip','r') as z:
    z.extractall()
PY
  fi
  # extracted folder name likely MultiConverter-main
  if [ -d "${REPO_DIR}-main" ]; then
    mv -f "${REPO_DIR}-main" "$REPO_DIR"
  fi
  rm -f main.zip
}

get_repo

cd "$REPO_DIR" || { echo "Cannot cd into $REPO_DIR"; exit 1; }
echo "Now in $(pwd) -- repository contents:"
ls -la

# --- Create composer.json if missing ---
if [ ! -f composer.json ]; then
  echo "composer.json not found. Creating a minimal composer.json to allow composer install."
  cat > composer.json <<'JSON'
{
  "name": "multiconverter/multiconverter",
  "description": "Minimal composer.json created by setup script",
  "type": "project",
  "require": {
    "php": ">=7.4"
  },
  "autoload": {
    "psr-4": {
      "MultiConverter\\": "src/"
    }
  }
}
JSON
  echo "composer.json created."
fi

# --- Install Node.js & npm if missing ---
if ! command_exists node || ! command_exists npm; then
  echo "Node.js/npm not found. Attempting to install Node.js and npm..."
  case "$PKG_MANAGER" in
    apt)
      # Install NodeSource LTS and npm
      curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
      sudo apt-get install -y nodejs
      ;;
    dnf)
      curl -fsSL https://rpm.nodesource.com/setup_lts.x | sudo bash -
      sudo dnf install -y nodejs
      ;;
    yum)
      curl -fsSL https://rpm.nodesource.com/setup_lts.x | sudo bash -
      sudo yum install -y nodejs
      ;;
    pacman)
      sudo pacman -Sy --noconfirm nodejs npm
      ;;
    brew)
      brew install node
      ;;
    apk)
      sudo apk add --no-cache nodejs npm
      ;;
    pkg)
      pkg install nodejs-lts
      ;;
    zypper)
      sudo zypper install -y nodejs npm
      ;;
    *)
      echo "Automatic Node.js installation not supported on this system by the script. Please install Node.js >= 16 and npm, then re-run."
      ;;
  esac
fi

echo "Node version: $(node -v || true), npm version: $(npm -v || true)"

# --- Install PHP & Composer if missing ---
if ! command_exists php; then
  echo "PHP not detected. Installing PHP..."
  case "$PKG_MANAGER" in
    apt) install_pkg php php-cli php-xml php-mbstring php-curl php-zip || true ;;
    dnf|yum) install_pkg php php-cli php-xml php-mbstring php-curl php-zip || true ;;
    pacman) install_pkg php php-apache php-intl || true ;;
    apk) install_pkg php php-phar php-openssl php-json php-mbstring || true ;;
    brew) brew install php ;;
    pkg) pkg install php ;;
    zypper) install_pkg php php-xml php-mbstring || true ;;
    emergE) echo "Please install PHP manually on Gentoo (emerge dev-lang/php)." ;;
    *) echo "Please install PHP (7.4+) manually." ;;
  esac
fi
echo "PHP version: $(php -v | head -n1 || true)"

if ! command_exists composer; then
  echo "Composer not found. Installing composer (system-wide if possible)..."
  if command_exists php; then
    curl -sS https://getcomposer.org/installer -o composer-setup.php
    php composer-setup.php --install-dir=/usr/local/bin --filename=composer || {
      echo "Global install failed, installing locally."
      php composer-setup.php --install-dir=.
      mv composer.phar composer
    }
    rm -f composer-setup.php
  else
    echo "php is required to install composer. Please install php and re-run."
  fi
fi
echo "Composer version: $(composer --version || true)"

# --- Composer install if composer.json present ---
if [ -f composer.json ]; then
  echo "Running composer install (if vendor not present)..."
  if [ -d vendor ]; then
    echo "Vendor directory already exists; skipping composer install."
  else
    composer install --no-interaction --optimize-autoloader || echo "composer install returned non-zero status; please inspect output."
  fi
fi

# --- Install global npm packages commonly required by this project ---
echo "Installing common npm global packages (typescript, tsc, tailwindcss, vite, phptojs if available)..."
# phptojs may or may not exist as an npm package; we will try to install it but ignore failure
NPM_GLOBALS=(typescript tsc tailwindcss vite sql.js less sass postcss-cli)
for pkg in "${NPM_GLOBALS[@]}"; do
  if ! npm list -g --depth=0 "$pkg" >/dev/null 2>&1; then
    echo "Attempting to npm install -g $pkg ..."
    npm install -g "$pkg" || echo "npm global install for $pkg failed (OK if unavailable)."
  else
    echo "Global npm package $pkg already installed."
  fi
done

# Try phptojs (best-effort)
if ! npm list -g --depth=0 phptojs >/dev/null 2>&1; then
  echo "Attempting to install phptojs (if available)..."
  npm install -g phptojs || echo "phptojs global install failed or not available (non-fatal)."
fi

# Ensure node_modules can be installed: prefer npm ci if lockfile exists
if [ -f package-lock.json ] || [ -f npm-shrinkwrap.json ]; then
  echo "Detected lockfile, running npm ci..."
  npm ci || {
    echo "npm ci failed; attempting npm install..."
    npm install
  }
else
  echo "No lockfile detected, running npm install..."
  npm install || { echo "npm install failed. Inspect logs in $LOGFILE"; }
fi

# --- If repository has a setup.sh, run it (after making executable) ---
if [ -f setup.sh ]; then
  echo "Found repository-provided setup.sh. Making executable and running it..."
  chmod +x setup.sh
  # Run in a subshell to capture errors but don't stop entire script if it returns non-zero
  if ! bash ./setup.sh; then
    echo "Repository setup.sh returned non-zero. Continuing; check repository-specific setup."
  fi
fi

# --- Build / run dev server ---
echo "Starting dev server: npm run dev"
# Try to start in background and wait to detect port 5173
if npm run dev -- --port 5173 & then
  DEV_PID=$!
  echo "npm run dev started with PID $DEV_PID. Waiting briefly to detect server..."
  sleep 4
  # check server
  if command_exists curl; then
    if curl -sI http://localhost:5173 | head -n1 | grep -q "200\|302\|301"; then
      echo "Dev server is up at http://localhost:5173"
    else
      echo "Dev server may not be serving 5173 or not yet ready. Check 'npm run dev' output above."
    fi
  else
    echo "curl not available to check server. If server started you can open http://localhost:5173"
  fi
else
  echo "Failed to start npm run dev directly. Try running 'npm run dev' manually to see errors."
fi

# --- Post-setup notes and recommendations ---
echo ""
echo "=== Setup script completed (or attempted) ==="
echo "What I did:"
echo "- Fetched the repository (git clone or ZIP download)"
echo "- Ensured node/npm and PHP + composer (best effort) were present or attempted install"
echo "- Created a minimal composer.json if none existed"
echo "- Attempted global npm installs for typescript, tailwindcss, vite, sql.js, less, sass"
echo "- Ran npm ci / npm install"
echo "- Ran repository setup.sh (if present)"
echo "- Attempted to run 'npm run dev' and detect http://localhost:5173"

cat <<EOF

Important caveats and manual follow-ups (read them):

1) HHVM / Hack: HHVM and Hack support is distro-specific and often not available or deprecated on many systems. If your project requires HHVM, please install it following official HHVM docs for your OS.

2) XAMPP / MAMP / WAMP / LAMP:
   - XAMPP/MAMP/WAMP are large bundles with GUI installers; this script does not run GUI installers.
   - On Linux, LAMP stacks should be installed via the system package manager or packages like tasksel (Debian/Ubuntu).
   - If you need XAMPP specifically, download from https://www.apachefriends.org and run the installer manually.

3) Windows:
   - This script is a POSIX/Bash script. For Windows, use Git Bash or WSL or convert steps to PowerShell.
   - For Windows package installs, consider choco/winget instructions (not fully automated here).

4) When package installs fail:
   - Check the log at $LOGFILE for errors.
   - Note that some distros require enabling extra repos (EPEL, etc.) before installing php extensions.

5) If `npm run dev` fails with port or build errors:
   - Run `npm run dev` manually and inspect terminal errors.
   - Typical fixes: missing Node version, missing devDependencies, missing PHP tools (if build step converts PHP sources).

EOF

echo "Setup finished. If you want, I can now:"
echo " - produce a Windows PowerShell version of this script,"
echo " - produce minimal docker-compose + Dockerfile to guarantee a predictable environment,"
echo " - or produce per-distro trimmed commands (Debian/Ubuntu, Fedora/CentOS, macOS) for manual execution."

exit 0
