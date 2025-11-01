#!/usr/bin/env bash

################################################################################
# MultiConverter Universal Setup Script
# Compatible with: Windows (Git Bash/WSL), macOS, Linux, GitHub Actions, Render, Vercel
# Description: Comprehensive environment setup with rigorous validation
################################################################################

set -euo pipefail
IFS=$'\n\t'

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color
readonly BOLD='\033[1m'

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/setup-$(date +%Y%m%d-%H%M%S).log"
ERROR_COUNT=0
WARNING_COUNT=0
SUCCESS_COUNT=0

# Environment detection
OS_TYPE=""
ARCH=""
IS_CI=false
CI_PLATFORM=""
PACKAGE_MANAGER=""
PHP_VERSION="8.2"
NODE_VERSION="20"
COMPOSER_VERSION="2"

################################################################################
# Utility Functions
################################################################################

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "${timestamp} [${level}] ${message}" >> "${LOG_FILE}"
    
    case "${level}" in
        INFO)
            echo -e "${BLUE}[INFO]${NC} ${message}"
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${NC} ${message}"
            ((SUCCESS_COUNT++))
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} ${message}"
            ((WARNING_COUNT++))
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} ${message}"
            ((ERROR_COUNT++))
            ;;
        STEP)
            echo -e "${CYAN}${BOLD}[STEP]${NC} ${message}"
            ;;
    esac
}

print_banner() {
    echo -e "${MAGENTA}${BOLD}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║           MultiConverter Setup Script                     ║
║                                                           ║
║   Universal Environment Configuration & Validation        ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

detect_os() {
    log INFO "Detecting operating system..."
    
    case "$(uname -s)" in
        Linux*)
            OS_TYPE="Linux"
            if [ -f /etc/os-release ]; then
                . /etc/os-release
                OS_TYPE="${OS_TYPE}-${ID}"
            fi
            ;;
        Darwin*)
            OS_TYPE="macOS"
            ;;
        CYGWIN*|MINGW*|MSYS*)
            OS_TYPE="Windows"
            ;;
        *)
            OS_TYPE="Unknown"
            ;;
    esac
    
    ARCH="$(uname -m)"
    
    # Detect CI environment
    if [ -n "${CI:-}" ] || [ -n "${GITHUB_ACTIONS:-}" ]; then
        IS_CI=true
        if [ -n "${GITHUB_ACTIONS:-}" ]; then
            CI_PLATFORM="GitHub Actions"
        elif [ -n "${RENDER:-}" ]; then
            CI_PLATFORM="Render"
        elif [ -n "${VERCEL:-}" ]; then
            CI_PLATFORM="Vercel"
        else
            CI_PLATFORM="Generic CI"
        fi
    fi
    
    log SUCCESS "OS: ${OS_TYPE}, Architecture: ${ARCH}"
    if [ "${IS_CI}" = true ]; then
        log INFO "Running in CI environment: ${CI_PLATFORM}"
    fi
}

detect_package_manager() {
    log INFO "Detecting package manager..."
    
    case "${OS_TYPE}" in
        macOS)
            if command_exists brew; then
                PACKAGE_MANAGER="brew"
            else
                log WARN "Homebrew not found. Will install it."
            fi
            ;;
        Linux-ubuntu|Linux-debian)
            PACKAGE_MANAGER="apt"
            ;;
        Linux-fedora|Linux-rhel|Linux-centos)
            PACKAGE_MANAGER="dnf"
            ;;
        Linux-arch)
            PACKAGE_MANAGER="pacman"
            ;;
        Windows)
            if command_exists choco; then
                PACKAGE_MANAGER="choco"
            elif command_exists scoop; then
                PACKAGE_MANAGER="scoop"
            else
                log WARN "No Windows package manager found. Manual installation required."
            fi
            ;;
    esac
    
    log SUCCESS "Package manager: ${PACKAGE_MANAGER:-manual}"
}

################################################################################
# Installation Functions
################################################################################

install_homebrew() {
    if [ "${OS_TYPE}" = "macOS" ] && ! command_exists brew; then
        log STEP "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        
        if [ "${ARCH}" = "arm64" ]; then
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
        
        log SUCCESS "Homebrew installed successfully"
    fi
}

install_nodejs() {
    log STEP "Checking Node.js installation..."
    
    if command_exists node; then
        local current_version=$(node --version | sed 's/v//' | cut -d. -f1)
        if [ "${current_version}" -ge "${NODE_VERSION}" ]; then
            log SUCCESS "Node.js ${current_version} is already installed"
            return 0
        else
            log WARN "Node.js ${current_version} found, but version ${NODE_VERSION}+ recommended"
        fi
    fi
    
    log INFO "Installing Node.js ${NODE_VERSION}..."
    
    case "${PACKAGE_MANAGER}" in
        brew)
            brew install node@${NODE_VERSION}
            ;;
        apt)
            curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | sudo -E bash -
            sudo apt-get install -y nodejs
            ;;
        dnf)
            curl -fsSL https://rpm.nodesource.com/setup_${NODE_VERSION}.x | sudo bash -
            sudo dnf install -y nodejs
            ;;
        pacman)
            sudo pacman -S --noconfirm nodejs npm
            ;;
        choco)
            choco install nodejs -y
            ;;
        scoop)
            scoop install nodejs
            ;;
        *)
            # Use nvm as fallback
            if ! command_exists nvm; then
                curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
                export NVM_DIR="$HOME/.nvm"
                [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
            fi
            nvm install ${NODE_VERSION}
            nvm use ${NODE_VERSION}
            ;;
    esac
    
    if command_exists node; then
        log SUCCESS "Node.js $(node --version) installed successfully"
    else
        log ERROR "Failed to install Node.js"
        return 1
    fi
}

install_php() {
    log STEP "Checking PHP installation..."
    
    if command_exists php; then
        local current_version=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
        log SUCCESS "PHP ${current_version} is already installed"
        
        # Check for required extensions
        local required_extensions=("mbstring" "xml" "curl" "zip" "sqlite3" "pdo_sqlite")
        for ext in "${required_extensions[@]}"; do
            if php -m | grep -q "^${ext}$"; then
                log SUCCESS "PHP extension ${ext} is installed"
            else
                log WARN "PHP extension ${ext} is missing"
            fi
        done
        return 0
    fi
    
    log INFO "Installing PHP ${PHP_VERSION}..."
    
    case "${PACKAGE_MANAGER}" in
        brew)
            brew install php@${PHP_VERSION}
            brew link php@${PHP_VERSION} --force
            ;;
        apt)
            sudo apt-get update
            sudo apt-get install -y software-properties-common
            sudo add-apt-repository ppa:ondrej/php -y
            sudo apt-get update
            sudo apt-get install -y \
                php${PHP_VERSION} \
                php${PHP_VERSION}-cli \
                php${PHP_VERSION}-common \
                php${PHP_VERSION}-mbstring \
                php${PHP_VERSION}-xml \
                php${PHP_VERSION}-curl \
                php${PHP_VERSION}-zip \
                php${PHP_VERSION}-sqlite3 \
                php${PHP_VERSION}-mysql \
                php${PHP_VERSION}-pgsql
            ;;
        dnf)
            sudo dnf install -y \
                php \
                php-cli \
                php-common \
                php-mbstring \
                php-xml \
                php-json \
                php-mysqlnd \
                php-pdo \
                php-pgsql
            ;;
        pacman)
            sudo pacman -S --noconfirm php php-sqlite
            ;;
        choco)
            choco install php -y
            ;;
        *)
            log WARN "Please install PHP ${PHP_VERSION} manually"
            ;;
    esac
    
    if command_exists php; then
        log SUCCESS "PHP $(php -v | head -n1 | awk '{print $2}') installed successfully"
    else
        log ERROR "Failed to install PHP"
        return 1
    fi
}

install_composer() {
    log STEP "Checking Composer installation..."
    
    if command_exists composer; then
        log SUCCESS "Composer $(composer --version | awk '{print $3}') is already installed"
        return 0
    fi
    
    log INFO "Installing Composer..."
    
    # Download and install Composer
    EXPECTED_CHECKSUM="$(php -r 'copy("https://composer.github.io/installer.sig", "php://stdout");')"
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
    ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"

    if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]; then
        log ERROR "Composer installer corrupt"
        rm composer-setup.php
        return 1
    fi

    php composer-setup.php --quiet
    rm composer-setup.php
    
    # Move to global location
    case "${OS_TYPE}" in
        Windows)
            mv composer.phar /usr/local/bin/composer || sudo mv composer.phar /usr/local/bin/composer
            ;;
        *)
            sudo mv composer.phar /usr/local/bin/composer
            sudo chmod +x /usr/local/bin/composer
            ;;
    esac
    
    if command_exists composer; then
        log SUCCESS "Composer installed successfully"
    else
        log ERROR "Failed to install Composer"
        return 1
    fi
}

install_laravel() {
    log STEP "Checking Laravel installer..."
    
    if command_exists laravel; then
        log SUCCESS "Laravel installer is already installed"
        return 0
    fi
    
    if command_exists composer; then
        log INFO "Installing Laravel installer via Composer..."
        composer global require laravel/installer
        
        # Add composer global bin to PATH if not already there
        local composer_bin="$HOME/.composer/vendor/bin"
        if [ -d "${composer_bin}" ] && [[ ":$PATH:" != *":${composer_bin}:"* ]]; then
            export PATH="${composer_bin}:$PATH"
            echo "export PATH=\"${composer_bin}:\$PATH\"" >> ~/.bashrc
            echo "export PATH=\"${composer_bin}:\$PATH\"" >> ~/.zshrc 2>/dev/null || true
        fi
        
        log SUCCESS "Laravel installer installed successfully"
    else
        log WARN "Composer not available, skipping Laravel installer"
    fi
}

install_hhvm_hack() {
    log STEP "Checking HHVM/Hack installation..."
    
    if command_exists hhvm; then
        log SUCCESS "HHVM $(hhvm --version | head -n1 | awk '{print $3}') is already installed"
        return 0
    fi
    
    log INFO "Installing HHVM..."
    
    case "${OS_TYPE}" in
        macOS)
            log WARN "HHVM is not officially supported on macOS. Skipping."
            log INFO "Consider using Docker: docker pull hhvm/hhvm:latest"
            ;;
        Linux-ubuntu|Linux-debian)
            # HHVM installation for Ubuntu/Debian
            sudo apt-get update
            sudo apt-get install -y software-properties-common apt-transport-https
            
            # Import HHVM GPG key
            wget -O - https://dl.hhvm.com/conf/hhvm.gpg.key | sudo apt-key add -
            
            # Add HHVM repository
            echo "deb https://dl.hhvm.com/ubuntu $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hhvm.list
            
            sudo apt-get update
            sudo apt-get install -y hhvm
            ;;
        *)
            log WARN "HHVM automatic installation not supported on ${OS_TYPE}"
            log INFO "Please install manually or use Docker"
            ;;
    esac
    
    if command_exists hhvm; then
        log SUCCESS "HHVM installed successfully"
    else
        log WARN "HHVM not installed. This is optional for the project."
    fi
}

install_typescript() {
    log STEP "Checking TypeScript installation..."
    
    if command_exists tsc; then
        log SUCCESS "TypeScript $(tsc --version) is already installed"
        return 0
    fi
    
    log INFO "Installing TypeScript globally..."
    npm install -g typescript
    
    if command_exists tsc; then
        log SUCCESS "TypeScript installed successfully"
    else
        log ERROR "Failed to install TypeScript"
        return 1
    fi
}

install_database_clients() {
    log STEP "Checking database client installations..."
    
    # MySQL/MariaDB
    if command_exists mysql; then
        log SUCCESS "MySQL client is already installed"
    else
        log INFO "Installing MySQL client..."
        case "${PACKAGE_MANAGER}" in
            brew)
                brew install mysql-client
                ;;
            apt)
                sudo apt-get install -y mysql-client
                ;;
            dnf)
                sudo dnf install -y mysql
                ;;
            pacman)
                sudo pacman -S --noconfirm mariadb-clients
                ;;
            choco)
                choco install mysql.utilities -y
                ;;
            *)
                log WARN "Please install MySQL client manually"
                ;;
        esac
    fi
    
    # PostgreSQL
    if command_exists psql; then
        log SUCCESS "PostgreSQL client is already installed"
    else
        log INFO "Installing PostgreSQL client..."
        case "${PACKAGE_MANAGER}" in
            brew)
                brew install postgresql@14
                ;;
            apt)
                sudo apt-get install -y postgresql-client
                ;;
            dnf)
                sudo dnf install -y postgresql
                ;;
            pacman)
                sudo pacman -S --noconfirm postgresql-libs
                ;;
            choco)
                choco install postgresql -y
                ;;
            *)
                log WARN "Please install PostgreSQL client manually"
                ;;
        esac
    fi
    
    # SQLite
    if command_exists sqlite3; then
        log SUCCESS "SQLite is already installed"
    else
        log INFO "Installing SQLite..."
        case "${PACKAGE_MANAGER}" in
            brew)
                brew install sqlite
                ;;
            apt)
                sudo apt-get install -y sqlite3 libsqlite3-dev
                ;;
            dnf)
                sudo dnf install -y sqlite sqlite-devel
                ;;
            pacman)
                sudo pacman -S --noconfirm sqlite
                ;;
            choco)
                choco install sqlite -y
                ;;
            *)
                log WARN "Please install SQLite manually"
                ;;
        esac
    fi
}

install_xampp() {
    log STEP "Checking XAMPP installation..."
    
    local xampp_dirs=(
        "/opt/lampp"
        "/Applications/XAMPP"
        "C:/xampp"
    )
    
    local xampp_found=false
    for dir in "${xampp_dirs[@]}"; do
        if [ -d "${dir}" ]; then
            log SUCCESS "XAMPP found at ${dir}"
            xampp_found=true
            break
        fi
    done
    
    if [ "${xampp_found}" = false ]; then
        log WARN "XAMPP not found. This is optional for local development."
        log INFO "Download from: https://www.apachefriends.org/download.html"
        log INFO "XAMPP includes Apache, MySQL/MariaDB, PHP, and phpMyAdmin"
    fi
}

install_css_preprocessors() {
    log STEP "Checking CSS preprocessor installations..."
    
    # Less
    if npm list -g less &>/dev/null; then
        log SUCCESS "Less is already installed"
    else
        log INFO "Installing Less..."
        npm install -g less
    fi
    
    # Sass
    if npm list -g sass &>/dev/null; then
        log SUCCESS "Sass is already installed"
    else
        log INFO "Installing Sass..."
        npm install -g sass
    fi
    
    log SUCCESS "CSS preprocessors ready"
}

################################################################################
# Project Setup Functions
################################################################################

setup_npm_packages() {
    log STEP "Installing npm dependencies..."
    
    cd "${SCRIPT_DIR}"
    
    if [ ! -f "package.json" ]; then
        log ERROR "package.json not found"
        return 1
    fi
    
    # Clean install
    if [ -d "node_modules" ]; then
        log INFO "Cleaning existing node_modules..."
        rm -rf node_modules
    fi
    
    if [ -f "package-lock.json" ]; then
        log INFO "Using package-lock.json for reproducible install..."
        npm ci
    else
        log INFO "Installing packages..."
        npm install
    fi
    
    # Install additional global packages
    local global_packages=(
        "sql.js"
        "phptojs"
    )
    
    for pkg in "${global_packages[@]}"; do
        if ! npm list -g "${pkg}" &>/dev/null; then
            log INFO "Installing global package: ${pkg}"
            npm install -g "${pkg}"
        else
            log SUCCESS "Global package ${pkg} already installed"
        fi
    done
    
    log SUCCESS "npm packages installed successfully"
}

setup_project_structure() {
    log STEP "Verifying project structure..."
    
    cd "${SCRIPT_DIR}"
    
    local required_dirs=(
        "Before/PHP"
        "Before/Laravel"
        "Before/Hack"
        "Before/TypeScript"
        "Before/Scss"
        "Before/Sass"
        "Before/Less"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [ ! -d "${dir}" ]; then
            log WARN "Creating missing directory: ${dir}"
            mkdir -p "${dir}"
        else
            log SUCCESS "Directory exists: ${dir}"
        fi
    done
    
    # Create After directories if they don't exist
    local after_dirs=(
        "After/HTMX"
        "After/JavaScript"
        "After/Tailwind"
        "After/CSS"
    )
    
    for dir in "${after_dirs[@]}"; do
        if [ ! -d "${dir}" ]; then
            log INFO "Creating output directory: ${dir}"
            mkdir -p "${dir}"
        fi
    done
    
    log SUCCESS "Project structure verified"
}

create_database() {
    log STEP "Setting up database..."
    
    cd "${SCRIPT_DIR}"
    
    if [ ! -f "database.sql" ]; then
        log WARN "database.sql not found, creating sample database..."
        cat > database.sql << 'EOF'
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

INSERT OR IGNORE INTO users (name, email) VALUES 
    ('Alice', 'alice@example.com'),
    ('Bob', 'bob@example.com'),
    ('Charlie', 'charlie@example.com');

CREATE TABLE IF NOT EXISTS posts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER,
    title TEXT NOT NULL,
    content TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users (id)
);

INSERT OR IGNORE INTO posts (user_id, title, content) VALUES 
    (1, 'First Post', 'This is the first post by Alice'),
    (2, 'Second Post', 'Bob shares his thoughts'),
    (1, 'Another Post', 'Alice writes again');
EOF
        log SUCCESS "Sample database.sql created"
    else
        log SUCCESS "database.sql exists"
    fi
}

################################################################################
# Validation Functions
################################################################################

validate_installation() {
    log STEP "Validating all installations..."
    
    local validation_passed=true
    
    # Node.js
    if command_exists node; then
        log SUCCESS "Node.js: $(node --version)"
    else
        log ERROR "Node.js not found"
        validation_passed=false
    fi
    
    # npm
    if command_exists npm; then
        log SUCCESS "npm: $(npm --version)"
    else
        log ERROR "npm not found"
        validation_passed=false
    fi
    
    # PHP
    if command_exists php; then
        log SUCCESS "PHP: $(php -v | head -n1 | awk '{print $2}')"
    else
        log WARN "PHP not found (optional for full functionality)"
    fi
    
    # Composer
    if command_exists composer; then
        log SUCCESS "Composer: $(composer --version --no-ansi | awk '{print $3}')"
    else
        log WARN "Composer not found (optional)"
    fi
    
    # TypeScript
    if command_exists tsc; then
        log SUCCESS "TypeScript: $(tsc --version)"
    else
        log ERROR "TypeScript not found"
        validation_passed=false
    fi
    
    # Git
    if command_exists git; then
        log SUCCESS "Git: $(git --version | awk '{print $3}')"
    else
        log WARN "Git not found (recommended)"
    fi
    
    # Database clients
    if command_exists sqlite3; then
        log SUCCESS "SQLite: $(sqlite3 --version | awk '{print $1}')"
    else
        log WARN "SQLite not found (optional)"
    fi
    
    if [ "${validation_passed}" = false ]; then
        log ERROR "Some critical components are missing"
        return 1
    fi
    
    log SUCCESS "All critical components validated successfully"
    return 0
}

run_tests() {
    log STEP "Running project tests..."
    
    cd "${SCRIPT_DIR}"
    
    # Test TypeScript compilation
    if [ -f "Before/TypeScript/main.ts" ]; then
        log INFO "Testing TypeScript compilation..."
        if tsc Before/TypeScript/main.ts --outFile /tmp/test-output.js --noEmit; then
            log SUCCESS "TypeScript compilation test passed"
        else
            log WARN "TypeScript compilation test failed"
        fi
    fi
    
    # Test if all required files exist
    local required_files=(
        "package.json"
        "vite.config.js"
        "tailwind.config.js"
        "postcss.config.js"
        "App.js"
        "App.css"
        "index.html"
    )
    
    for file in "${required_files[@]}"; do
        if [ -f "${file}" ]; then
            log SUCCESS "Required file exists: ${file}"
        else
            log ERROR "Required file missing: ${file}"
        fi
    done
    
    # Test npm scripts
    if npm run --silent 2>&1 | grep -q "build"; then
        log SUCCESS "npm build script available"
    else
        log WARN "npm build script not found"
    fi
    
    log SUCCESS "Project tests completed"
}

################################################################################
# Build and Deployment Functions
################################################################################

build_project() {
    log STEP "Building project..."
    
    cd "${SCRIPT_DIR}"
    
    # Run the custom build script
    if [ -f "build.js" ]; then
        log INFO "Running custom build script..."
        node build.js
    fi
    
    # Run Vite build
    log INFO "Running Vite build..."
    npm run build
    
    if [ -d "dist" ]; then
        log SUCCESS "Build completed successfully. Output in ./dist"
        
        # List build artifacts
        log INFO "Build artifacts:"
        find dist -type f | head -20 | while read file; do
            log INFO "  - ${file}"
        done
    else
        log ERROR "Build failed - dist directory not created"
        return 1
    fi
}

setup_ci_environment() {
    if [ "${IS_CI}" = false ]; then
        return 0
    fi
    
    log STEP "Setting up CI environment: ${CI_PLATFORM}"
    
    case "${CI_PLATFORM}" in
        "GitHub Actions")
            log INFO "GitHub Actions detected"
            # GitHub Actions typically has most tools pre-installed
            ;;
        "Render")
            log INFO "Render detected"
            # Set build command: npm install && npm run build
            ;;
        "Vercel")
            log INFO "Vercel detected"
            # Set build command: npm run build
            # Set output directory: dist
            ;;
    esac
    
    log SUCCESS "CI environment configured"
}

################################################################################
# Main Execution
################################################################################

main() {
    print_banner
    
    log INFO "Starting MultiConverter setup..."
    log INFO "Script directory: ${SCRIPT_DIR}"
    log INFO "Log file: ${LOG_FILE}"
    
    # Environment detection
    detect_os
    detect_package_manager
    
    # CI-specific setup
    setup_ci_environment
    
    # Install system dependencies
    install_homebrew
    install_nodejs
    install_php
    install_composer
    install_laravel
    install_hhvm_hack
    install_typescript
    install_database_clients
    install_xampp
    install_css_preprocessors
    
    # Project setup
    setup_npm_packages
    setup_project_structure
    create_database
    
    # Validation
    validate_installation
    run_tests
    
    # Build (optional, can be skipped for dev setup)
    if [ "${IS_CI}" = true ] || [ "${1:-}" = "--build" ]; then
        build_project
    else
        log INFO "Skipping build. Run with --build flag or use: npm run build"
    fi
    
    # Summary
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}                    Setup Summary                          ${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Successes: ${SUCCESS_COUNT}${NC}"
    echo -e "${YELLOW}Warnings:  ${WARNING_COUNT}${NC}"
    echo -e "${RED}Errors:    ${ERROR_COUNT}${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ ${ERROR_COUNT} -eq 0 ]; then
        log SUCCESS "Setup completed successfully!"
        echo ""
        echo -e "${CYAN}Next steps:${NC}"
        echo -e "  1. Start development server: ${BOLD}npm run dev${NC}"
        echo -e "  2. Build for production: ${BOLD}npm run build${NC}"
        echo -e "  3. View logs: ${BOLD}cat ${LOG_FILE}${NC}"
        echo ""
        return 0
    else
        log ERROR "Setup completed with ${ERROR_COUNT} error(s)"
        echo -e "${YELLOW}Please check the log file for details: ${LOG_FILE}${NC}"
        return 1
    fi
}

# Trap errors
trap 'log ERROR "Script failed at line $LINENO"' ERR

# Execute main function
main "$@"
