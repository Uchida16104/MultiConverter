#!/usr/bin/env bash
# setup.sh
#
# Purpose: Cross-platform bootstrapper and analyzer for the GitHub repository
# https://github.com/Uchida16104/MultiConverter/tree/main
#
# What this script does (best-effort, idempotent):
# 1. Detect host platform (macOS, many Linux distros, Windows (WSL/Cygwin), Android/Termux).
# 2. Install or ensure presence of developer packages required to run a typical
#    modern JavaScript/Vite project with `npm run dev` (Node.js LTS, npm, git,
#    build tools, Python where needed for native modules, make, gcc/clang, etc.).
# 3. Optionally generate CI/hosting helper files for GitHub Actions (GitHub Pages),
#    Vercel and Render.com minimal configuration to deploy the repo's build.
# 4. Perform a static inspection of the repository (file list, package.json analysis),
#    then run `npm ci` or `npm install` and start the dev server with `npm run dev`.
#
# Limitations / Important notes (please read):
# - This script is intentionally conservative and attempts to avoid destructive operations.
# - It cannot magically fix every environment-specific failure (hardware, locked package
#   managers, corporate proxies, missing privileges). It makes best-effort installs.
# - On Windows native, this script is written for environments that provide a Unix shell
#   (Git Bash, MSYS2, WSL). Native PowerShell/Command Prompt support is limited.
# - For Android, Termux is required; this script will attempt Termux package installs.
# - Some systems (Gentoo, NixOS, Fedora Silverblue, immutable OSes) require manual
#   admin steps; this script will print instructions when automation is not possible.
#
# USAGE:
#  1) Place this script at the root of the cloned repo (MultiConverter).
#  2) Make executable: chmod +x setup.sh
#  3) Run as a user with sudo privileges when installation is required:
#       sudo ./setup.sh
#     (or run without sudo to perform analysis + local npm steps if system already has tools)
#
# Exit on any error so failures are obvious
set -euo pipefail
IFS=$'\n\t'

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
NODE_MIN_VERSION_MAJOR=18
NPM_MIN_VERSION=8
SCRIPT_NAME=$(basename "$0")

log(){ echo "[INFO] $*"; }
err(){ echo "[ERROR] $*" >&2; }
warn(){ echo "[WARN] $*" >&2; }

require_cmd(){ command -v "$1" >/dev/null 2>&1 || { err "command '$1' not found"; return 1; } }

# --- Platform detection ---
OS_TYPE="unknown"
if [[ "$OSTYPE" == darwin* ]]; then
  OS_TYPE="macos"
elif grep -qi microsoft /proc/version 2>/dev/null || grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
  OS_TYPE="wsl"
elif [[ "$(uname -s)" == Linux* ]]; then
  # check distro
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    ID_LC=${ID,,}
    case "$ID_LC" in
      ubuntu|debian|linuxmint)
        OS_TYPE="debian"
        ;;
      fedora)
        OS_TYPE="fedora"
        ;;
      centos|rhel)
        OS_TYPE="centos"
        ;;
      gentoo)
        OS_TYPE="gentoo"
        ;;
      arch|manjaro)
        OS_TYPE="arch"
        ;;
      alpine)
        OS_TYPE="alpine"
        ;;
      *)
        OS_TYPE="linux"
        ;;
    esac
  else
    OS_TYPE="linux"
  fi
elif [[ "$OSTYPE" == cygwin* || "$OSTYPE" == msys* ]]; then
  OS_TYPE="windows"   # Git Bash / MSYS
elif [[ "$OSTYPE" == android* ]]; then
  OS_TYPE="termux"
else
  OS_TYPE="unknown"
fi
log "Detected platform: $OS_TYPE"

# --- Helper installers per distro ---
apt_install(){
  sudo apt-get update -y && sudo apt-get install -y "$@"
}

dnf_install(){
  sudo dnf install -y "$@"
}

yum_install(){
  sudo yum install -y "$@"
}

pacman_install(){
  sudo pacman -Sy --noconfirm "$@"
}

apk_install(){
  sudo apk add --no-cache "$@"
}

emerge_install(){
  sudo emerge --ask "$@"
}

choco_install(){
  if command -v choco >/dev/null 2>&1; then
    choco install -y "$@"
  else
    warn "choco not found. Skipping choco install."
  fi
}

winget_install(){
  if command -v winget >/dev/null 2>&1; then
    winget install --id "$1" --silent || warn "winget failed for $1"
  else
    warn "winget not found. Skipping winget install."
  fi
}

# --- Ensure essential build tools ---
install_build_tools(){
  log "Installing essential build tools for $OS_TYPE"
  case "$OS_TYPE" in
    debian|wsl)
      apt_install build-essential git curl ca-certificates gnupg lsb-release python3 python3-pip
      ;;
    fedora)
      dnf_install @development-tools git curl ca-certificates python3 python3-pip
      ;;
    centos)
      yum_install gcc gcc-c++ make git curl python3 python3-pip
      ;;
    arch)
      pacman_install base-devel git curl python python-pip
      ;;
    alpine)
      apk_install build-base git curl python3 py3-pip
      ;;
    gentoo)
      emerge_install sys-devel/gcc net-misc/curl dev-vcs/git >=dev-lang/python-3
      ;;
    macos)
      if ! command -v brew >/dev/null 2>&1; then
        log "Homebrew not detected. Installing Homebrew (non-interactive)."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || true
      fi
      brew update || true
      brew install git curl python node || true
      ;;
    termux)
      pkg update -y || true
      pkg install -y git curl clang python nodejs build-essential openssl
      ;;
    windows)
      warn "For native Windows please install Git for Windows, Node.js (LTS), and a MSYS2/MinGW or WSL environment. Attempting choco/winget if present."
      choco_install git
      ;;
    *)
      warn "Unknown Linux variant: try installing build-essential, git, curl, python3 and node manually."
      ;;
  esac
}

# --- Node.js and npm: use nvm for user install ---
install_node_with_nvm(){
  if command -v node >/dev/null 2>&1; then
    NODE_VER=$(node -v | sed 's/v//')
    log "Node present: v${NODE_VER}"
  else
    # Install NVM non-interactively
    if [ -z "${NVM_DIR-}" ]; then
      export NVM_DIR="$HOME/.nvm"
    fi
    if [ ! -d "$NVM_DIR" ]; then
      log "Installing nvm"
      curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash
    fi
    # shellcheck source=/dev/null
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    nvm install --lts
    nvm use --lts
  fi

  # ensure npm exists
  if ! command -v npm >/dev/null 2>&1; then
    err "npm not found after node install"
    return 1
  fi

  # check versions
  NPM_VER=$(npm -v || echo "0")
  log "npm version: $NPM_VER"
}

# --- Global JS toolchain helpers ---
install_global_js_tools(){
  if command -v npm >/dev/null 2>&1; then
    log "Ensuring pnpm and vite are available (global installs are optional)."
    npm install -g pnpm@latest || true
    npm install -g serve || true
    # do NOT enforce global vite; projects should have devDependencies
  fi
}

# --- Repo analysis ---
analyze_repo(){
  log "Analyzing repository structure in $REPO_ROOT"
  pushd "$REPO_ROOT" >/dev/null
  echo "--- top-level files ---"
  ls -la | sed -n '1,200p'
  echo "\n--- tree (up to depth 4) ---"
  if command -v tree >/dev/null 2>&1; then
    tree -L 4 || true
  else
    find . -maxdepth 4 -print | sed -n '1,500p'
  fi

  # package.json inspection
  if [ -f package.json ]; then
    log "Found package.json — extracting scripts and dependencies"
    cat package.json | sed -n '1,200p'
    # show scripts quickly
    node -e "const p=require('./package.json'); console.log('scripts:\n', p.scripts||{}); console.log('\ndependencies:\n', p.dependencies||{}); console.log('\ndevDependencies:\n', p.devDependencies||{});" || true
  else
    warn "No package.json found at repo root — ensure you are at the correct path."
  fi
  popd >/dev/null
}

# --- Create minimal GitHub Actions workflow for Pages (deploy) ---
create_github_actions_workflow(){
  WORKFLOW_DIR="$REPO_ROOT/.github/workflows"
  mkdir -p "$WORKFLOW_DIR"
  cat > "$WORKFLOW_DIR/deploy-gh-pages.yml" <<'YML'
name: Deploy to GitHub Pages
on:
  push:
    branches: [ main ]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Use Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '18'
      - run: npm ci
      - run: npm run build
      - name: Deploy
        uses: peaceiris/actions-gh-pages@v4
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: ./dist
YML
  log "Created GitHub Actions workflow at $WORKFLOW_DIR/deploy-gh-pages.yml"
}

# --- Create Vercel configuration file ---
create_vercel_conf(){
  cat > "$REPO_ROOT/vercel.json" <<'JSON'
{
  "version": 2,
  "builds": [
    { "src": "package.json", "use": "@vercel/static-build", "config": { "distDir": "dist" } }
  ],
  "routes": [
    { "src": "/(.*)", "dest": "/index.html" }
  ]
}
JSON
  log "Created vercel.json"
}

# --- Create Render service file (render.yaml) for static site ---
create_render_conf(){
  cat > "$REPO_ROOT/render.yaml" <<'YAML'
# Minimal Render static site configuration (manual creation in Render dashboard may still be required)
services:
  - type: web
    name: multiconverter
    env: node
    plan: free
    buildCommand: npm ci && npm run build
    startCommand: npm run serve
    staticPublishPath: dist
YAML
  log "Created render.yaml"
}

# --- Run npm install and dev ---
install_and_run_dev(){
  pushd "$REPO_ROOT" >/dev/null
  if [ -f package-lock.json ]; then
    log "Using npm ci (package-lock.json present)"
    npm ci || { warn "npm ci failed, attempting npm install"; npm install; }
  else
    npm install || true
  fi

  # Ensure there's a dev script that starts Vite on port 5173 or default
  if node -e "const p=require('./package.json'); console.log(p.scripts&&p.scripts.dev?1:0)" 2>/dev/null | grep -q 1; then
    log "Found npm run dev script — starting it in background and piping logs to ./dev-server.log"
    # try to start dev server in background; user may press Ctrl-C to stop
    npm run dev -- --port 5173 > ./dev-server.log 2>&1 &
    sleep 2
    DEV_PID=$!
    log "Started dev server (PID: $DEV_PID). Logs: $REPO_ROOT/dev-server.log"
    # wait a few seconds and attempt to curl localhost:5173
    sleep 3
    if curl -sSf http://localhost:5173/ >/dev/null 2>&1; then
      log "Dev server appears to be serving at http://localhost:5173"
    else
      warn "Unable to confirm dev server on http://localhost:5173. Check $REPO_ROOT/dev-server.log"
    fi
  else
    warn "No npm dev script found. Please inspect package.json scripts."
  fi
  popd >/dev/null
}

# --- Main orchestration ---
main(){
  log "Beginning setup"
  install_build_tools || warn "install_build_tools failed or partial"

  # Node via nvm
  install_node_with_nvm || warn "install_node_with_nvm encountered issues"
  install_global_js_tools || warn "global js tools had issues"

  analyze_repo || warn "repo analysis had issues"

  # Create helpful CI config files
  create_github_actions_workflow || warn "creating GH Actions workflow failed"
  create_vercel_conf || warn "creating vercel.json failed"
  create_render_conf || warn "creating render.yaml failed"

  # Final npm install and run
  install_and_run_dev || warn "install_and_run_dev encountered issues"

  log "Setup finished. If the dev server is running, open http://localhost:5173 in your browser."
  log "If something failed, inspect the log files and the printed warnings above."
}

# Execute main
main
