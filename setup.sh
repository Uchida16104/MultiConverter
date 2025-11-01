#!/usr/bin/env bash
# MultiConverter-setup.sh
# Universal bootstrap & repository analyzer for https://github.com/Uchida16104/MultiConverter
# English: Detect OS/environment, attempt to install missing dev/runtime dependencies
# Targets: Linux (apt/yum/pacman), macOS (brew), Windows (WSL / Git Bash / Chocolatey when available),
# CI / hosting adaptors: GitHub Actions, Render, Vercel
# WARNING: Some operations require sudo/administrator privileges. Script will NOT force destructive changes.
# This script attempts best-effort automated installs where possible and prints explicit manual steps when not.

set -o pipefail
# Avoid 'set -e' to allow partial completion and give helpful messages; we will check return codes manually.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG() { printf "[%s] %s\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$*"; }
ERR() { printf "ERROR: %s\n" "$*" >&2; }

# Detect environment
OS_TYPE="unknown"
UNAME_OUT="$(uname -s 2>/dev/null || echo Unknown)"
case "$UNAME_OUT" in
  Linux*) OS_TYPE=linux ;;
  Darwin*) OS_TYPE=macos ;;
  *CYGWIN*|*MINGW*|*MSYS*) OS_TYPE=windows_shell ;;
  *) OS_TYPE=unknown ;;
esac

# Detect CI / host platform
IN_GITHUB_ACTIONS=false
IN_RENDER=false
IN_VERCEL=false
if [ "${GITHUB_ACTIONS:-}" = "true" ]; then IN_GITHUB_ACTIONS=true; fi
if [ -n "${RENDER:-}" ] || [ -n "${RENDER_SERVICE_ID:-}" ]; then IN_RENDER=true; fi
if [ -n "${VERCEL:-}" ] || [ -n "${VERCEL_ENV:-}" ]; then IN_VERCEL=true; fi

LOG "Environment detected: OS=$OS_TYPE, GITHUB_ACTIONS=$IN_GITHUB_ACTIONS, RENDER=$IN_RENDER, VERCEL=$IN_VERCEL"

# Helpers to check tools
has_cmd(){ command -v "$1" >/dev/null 2>&1; }
ask_sudo(){
  if has_cmd sudo; then
    SUDO=sudo
  else
    SUDO=""
  fi
}
ask_sudo

# Install via detected package manager
install_pkg_linux(){
  PKG="$1"
  if has_cmd apt-get; then
    LOG "Attempting apt-get install: $PKG (requires sudo)"
    $SUDO apt-get update && $SUDO apt-get install -y "$PKG"
    return $?
  elif has_cmd dnf; then
    LOG "Attempting dnf install: $PKG (requires sudo)"
    $SUDO dnf install -y "$PKG"
    return $?
  elif has_cmd yum; then
    LOG "Attempting yum install: $PKG (requires sudo)"
    $SUDO yum install -y "$PKG"
    return $?
  elif has_cmd pacman; then
    LOG "Attempting pacman install: $PKG (requires sudo)"
    $SUDO pacman -Sy --noconfirm "$PKG"
    return $?
  else
    ERR "No recognized Linux package manager found. Manual install required for $PKG"
    return 1
  fi
}

install_brew(){
  if ! has_cmd brew; then
    LOG "Homebrew not found. Installing Homebrew (macOS/Linux)"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || return 1
    # Add brew to PATH for non-interactive shells (attempt)
    eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null || true)"
  fi
  brew install "$@"
}

install_choco(){
  if ! has_cmd choco; then
    ERR "Chocolatey not found. Please install Chocolatey manually on Windows: https://chocolatey.org/install"
    return 1
  fi
  choco install -y "$@"
}

# High-level installers for requested tools
ensure_node_npm(){
  if has_cmd node && has_cmd npm; then
    LOG "node and npm already installed: $(node -v), $(npm -v)"
    return 0
  fi
  LOG "node/npm missing: attempting to install"
  case "$OS_TYPE" in
    macos) install_brew node || return 1 ;;
    linux) install_pkg_linux nodejs || install_pkg_linux nodejs || return 1 ;;
    windows_shell) if has_cmd choco; then install_choco nodejs.install || return 1; else ERR "Install Node.js manually on Windows." ; return 1; fi ;;
  esac
}

ensure_npm_global(){
  PKG="$1"
  if npm list -g --depth=0 "$PKG" >/dev/null 2>&1; then
    LOG "npm global package $PKG already installed"
  else
    LOG "Installing npm global package: $PKG"
    npm install -g "$PKG" || { ERR "npm install -g $PKG failed"; return 1; }
  fi
}

ensure_php(){
  if has_cmd php; then
    LOG "PHP detected: $(php -v | head -n1)"
    return 0
  fi
  LOG "PHP not found: attempting install"
  case "$OS_TYPE" in
    macos) install_brew php || return 1 ;;
    linux) install_pkg_linux php-cli || install_pkg_linux php || return 1 ;;
    windows_shell) if has_cmd choco; then install_choco php; else ERR "Please install PHP for Windows via https://windows.php.net or Chocolatey." ; return 1; fi ;;
  esac
}

ensure_composer(){
  if has_cmd composer; then
    LOG "Composer detected: $(composer --version)"
    return 0
  fi
  LOG "Installing Composer (global)"
  if has_cmd php; then
    EXPECTED_SIG="" # skipping signature check for portability; user can verify manually
    php -r "copy('https://getcomposer.org/installer','composer-setup.php');" || return 1
    php composer-setup.php --install-dir=/usr/local/bin --filename=composer || php composer-setup.php --install-dir=
    rm -f composer-setup.php
    if has_cmd composer; then LOG "Composer installed: $(composer --version)"; return 0; fi
  fi
  ERR "Composer install failed or PHP missing."
  return 1
}

ensure_laravel_installer(){
  if has_cmd laravel; then
    LOG "Laravel installer present: $(laravel --version 2>/dev/null || true)"
    return 0
  fi
  if has_cmd composer; then
    LOG "Installing laravel installer via composer global require laravel/installer"
    composer global require laravel/installer || { ERR "composer global require laravel/installer failed"; return 1; }
    # Ensure composer global bin is in PATH
    if [ -d "$HOME/.composer/vendor/bin" ]; then
      PATH="$PATH:$HOME/.composer/vendor/bin"
    fi
    return 0
  fi
  ERR "Composer not available to install laravel installer."
  return 1
}

ensure_hhvm(){
  if has_cmd hhvm; then
    LOG "HHVM detected: $(hhvm --version 2>/dev/null || true)"
    return 0
  fi
  LOG "HHVM installation is platform-sensitive and not always available. Attempting to install on supported Linux (Debian/Ubuntu)"
  if [ "$OS_TYPE" = "linux" ] && has_cmd apt-get; then
    LOG "Adding HHVM repository and installing (Debian/Ubuntu)"
    $SUDO apt-get install -y software-properties-common ca-certificates apt-transport-https || true
    wget -O - https://dl.hhvm.com/conf/hhvm.gpg.key 2>/dev/null | $SUDO apt-key add - || true
    DISTRO_CODENAME=$(lsb_release -sc 2>/dev/null || echo focal)
    echo "deb http://dl.hhvm.com/ubuntu $(lsb_release -sc) main" | $SUDO tee /etc/apt/sources.list.d/hhvm.list >/dev/null || true
    $SUDO apt-get update && $SUDO apt-get install -y hhvm || { ERR "hhvm apt install failed"; return 1; }
    return 0
  fi
  ERR "HHVM install skipped: unsupported platform or manual steps required. See https://hhvm.com/ for instructions."
  return 1
}

ensure_phptojs(){
  # phptojs is assumed to be an npm package named phptojs
  if has_cmd phptojs; then
    LOG "phptojs cli present"
    return 0
  fi
  if has_cmd npm; then
    ensure_npm_global phptojs || { ERR "phptojs npm install failed"; return 1; }
    return 0
  fi
  ERR "npm missing; cannot install phptojs"
  return 1
}

ensure_typescript(){
  if has_cmd tsc; then
    LOG "TypeScript compiler detected: $(tsc -v 2>/dev/null || true)"
    return 0
  fi
  if has_cmd npm; then
    ensure_npm_global typescript || return 1
    return 0
  fi
  ERR "npm missing; cannot install TypeScript"
  return 1
}

ensure_sqljs(){
  # sql.js is an npm package typically used from node. We'll ensure it's available in project node_modules or global.
  if [ -f "${REPO_ROOT}/package.json" ]; then
    if grep -q "sql.js" "${REPO_ROOT}/package.json" 2>/dev/null; then
      LOG "sql.js referenced in package.json"
    else
      LOG "Adding sql.js to package.json devDependencies (local)"
      (cd "$REPO_ROOT" && npm install --no-audit --no-fund sql.js) || { ERR "npm install sql.js failed"; }
    fi
  else
    LOG "No package.json in repo root; installing sql.js globally"
    if has_cmd npm; then ensure_npm_global sql.js || ERR "sql.js global install failed"; fi
  fi
}

ensure_sql_servers(){
  # Try to install MySQL / MariaDB / Postgres if missing (best-effort). Many hosting platforms won't allow these installs.
  if has_cmd mysql; then LOG "MySQL client available: $(mysql --version)"; fi
  if has_cmd psql; then LOG "Postgres client available: $(psql --version)"; fi
  if has_cmd mysqld; then LOG "MySQL server appears installed."; fi
  # Attempt server install on Linux when apt is available
  if [ "$OS_TYPE" = "linux" ] && has_cmd apt-get; then
    if ! has_cmd mysql && ! has_cmd mysqld; then
      LOG "Attempting to install default-mysql-server (or mariadb-server)"
      $SUDO apt-get update
      $SUDO apt-get install -y mariadb-server default-mysql-server || $SUDO apt-get install -y mysql-server || ERR "mysql/mariadb install failed"
    fi
    if ! has_cmd psql; then
      LOG "Installing postgresql client/server"
      $SUDO apt-get install -y postgresql postgresql-contrib || ERR "postgres install failed"
    fi
  else
    LOG "Skipping automatic SQL server installation on non-Linux or unsupported package manager. Manual install recommended."
  fi
}

ensure_css_tools(){
  # Less, Sass/Scss (dart-sass) via npm or brew
  if has_cmd npm; then
    LOG "Ensuring less and sass (dart-sass) via npm"
    npm list -g --depth=0 less >/dev/null 2>&1 || npm install -g less || ERR "less install failed"
    npm list -g --depth=0 sass >/dev/null 2>&1 || npm install -g sass || ERR "sass install failed"
  else
    if [ "$OS_TYPE" = "macos" ]; then
      install_brew less || true
      brew install sass/sass/sass || true
    else
      LOG "npm missing, unable to install less/sass automatically."
    fi
  fi
}

ensure_xampp(){
  LOG "XAMPP: This script will only download XAMPP installers where available; interactive installation often required."
  case "$OS_TYPE" in
    linux)
      XAMPP_URL="https://www.apachefriends.org/xampp-files/8.1.25/xampp-linux-x64-8.1.25-0-installer.run" # example version; user should verify
      TMPFILE="/tmp/xampp-installer.run"
      LOG "Downloading XAMPP installer to $TMPFILE (you may need to run this part manually if permissions are restricted)"
      curl -L "$XAMPP_URL" -o "$TMPFILE" || { ERR "Failed to download XAMPP. Update URL manually."; return 1; }
      chmod +x "$TMPFILE" && $SUDO "$TMPFILE" || ERR "XAMPP installer execution may require interactive acceptance." ;;
    macos)
      LOG "Please download XAMPP for macOS from https://www.apachefriends.org/ and run the DMG installer manually."
      return 1 ;;
    windows_shell)
      LOG "Please download XAMPP for Windows from https://www.apachefriends.org/ and run the installer." ;;
    *) ERR "Unknown OS for XAMPP" ;;
  esac
}

# Repository-specific analysis: look for expected files, frameworks
repo_analyze(){
  LOG "Analyzing repository at $REPO_ROOT"
  ls -la "$REPO_ROOT" || true
  echo
  LOG "Top-level files and folders (summary):"
  find "$REPO_ROOT" -maxdepth 2 -mindepth 1 -printf '%P\n' || true
  echo
  # Check for specific technologies
  grep -R --line-number "phptojs\|sql.js\|laravel\|hhvm\|typeScript\|tsc\|scss\|sass\|less\|php" "$REPO_ROOT" || true
  echo
  # Check package.json scripts
  if [ -f "$REPO_ROOT/package.json" ]; then
    LOG "package.json scripts:"; jq -r '.scripts // {}' "$REPO_ROOT/package.json" 2>/dev/null || cat "$REPO_ROOT/package.json" | sed -n '1,200p'
  fi
  # Check for Composer/laravel
  if [ -f "$REPO_ROOT/composer.json" ]; then
    LOG "composer.json found: dependencies:"; jq -r '.require // {}' composer.json 2>/dev/null || cat composer.json | sed -n '1,200p'
  fi
}

# CI / hosting adaptation: minimal and safe
adapt_for_ci(){
  if $IN_GITHUB_ACTIONS; then
    LOG "Running inside GitHub Actions runner. Prefer using action steps to install system packages."
    LOG "Recommended workflow excerpt (in your .github/workflows):\n uses: actions/setup-node@v4\n uses: shivammathur/setup-php@v2  # for PHP\n run: npm ci && npm run build"
  fi
  if $IN_RENDER; then
    LOG "Detected Render environment. Use Render build commands: npm install && npm run build. You cannot install system packages on managed services unless using Private Services." 
  fi
  if $IN_VERCEL; then
    LOG "Vercel detected. Use package.json build scripts. Vercel doesn't allow installing arbitrary system packages during build; use Node/npm-based toolchain and remote DB services."
  fi
}

# Main orchestration
main(){
  LOG "--- START MultiConverter bootstrap and analysis ---"

  # Ensure Node.js & npm
  ensure_node_npm || LOG "Node/npm install skipped or failed. Some features depend on Node."

  # Ensure basic npm packages used by project
  if has_cmd npm; then
    LOG "Installing repository npm dependencies (if package.json present)"
    if [ -f "$REPO_ROOT/package.json" ]; then
      (cd "$REPO_ROOT" && npm install --no-audit --no-fund) || ERR "npm install in repo failed"
    fi
  fi

  # Ensure TypeScript, phptojs, sql.js
  ensure_typescript || true
  ensure_phptojs || true
  ensure_sqljs || true

  # Ensure PHP and Composer
  ensure_php || LOG "PHP not installed automatically. Some features require PHP/XAMPP/Hack."
  ensure_composer || LOG "Composer not installed automatically."
  ensure_laravel_installer || LOG "Laravel installer not installed."

  # CSS preprocessor tooling
  ensure_css_tools || true

  # SQL servers (best-effort on Linux)
  ensure_sql_servers || true

  # Try HHVM/Hack only on supported linux
  ensure_hhvm || LOG "HHVM/Hack install skipped or failed."

  # XAMPP is optional and interactive
  LOG "XAMPP installation is manual-interactive on most platforms; invoking helper downloader..."
  # Commenting out automatic xampp call to avoid unexpected interactive installers. Uncomment to attempt download+run.
  # ensure_xampp || LOG "XAMPP not installed."

  # Repo analysis
  repo_analyze

  adapt_for_ci

  LOG "--- END bootstrap. Please review any errors above; some platforms require manual steps. ---"
}

main "$@" 
