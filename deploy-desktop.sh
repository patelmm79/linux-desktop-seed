#!/bin/bash
set -euo pipefail

# Remote Linux Desktop Deployment Script
# Deploys: GNOME, xrdp, VS Code, Claude Code, Chromium, OpenRouter
# Target: Ubuntu 20.04/22.04/24.04

SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/deploy-desktop-$(date +%Y%m%d-%H%M%S).log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"; }

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Detect Ubuntu version
detect_ubuntu_version() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "$ID" != "ubuntu" ]]; then
            log_error "This script only supports Ubuntu, detected: $ID"
            exit 1
        fi
        UBUNTU_VERSION="$VERSION_ID"
        log_info "Detected Ubuntu $UBUNTU_VERSION"

        # Check supported versions
        case "$UBUNTU_VERSION" in
            20.04|22.04|24.04)
                log_info "Ubuntu version $UBUNTU_VERSION is supported"
                ;;
            *)
                log_warn "Ubuntu $UBUNTU_VERSION may not be fully tested"
                ;;
        esac
    else
        log_error "Cannot detect OS version"
        exit 1
    fi
}

# Update package lists and upgrade system
update_system() {
    log_info "Updating package lists and upgrading system..."

    export DEBIAN_FRONTEND=noninteractive

    # Update package lists
    log_info "Running apt-get update..."
    if ! apt-get update -y; then
        log_error "Failed to update package lists"
        return 1
    fi

    # Upgrade existing packages
    log_info "Upgrading existing packages..."
    if ! apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"; then
        log_error "Failed to upgrade packages"
        return 1
    fi

    # Install essential dependencies
    log_info "Installing essential dependencies..."
    if ! apt-get install -y \
        curl \
        wget \
        gnupg2 \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        lsb-release \
        jq; then
        log_error "Failed to install dependencies"
        return 1
    fi

    # Clean up
    log_info "Cleaning up package cache..."
    apt-get autoremove -y
    apt-get clean

    # Verify critical dependencies
    log_info "Verifying critical tools..."
    for cmd in curl wget jq; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "Critical command '$cmd' not found after installation"
            return 1
        fi
    done

    log_info "System updated successfully"
}

# Install GNOME Desktop
install_gnome() {
    log_info "Installing GNOME Desktop..."

    # Check if already installed
    if dpkg -l gnome-shell 2>/dev/null | grep -q "^ii"; then
        log_warn "GNOME already installed, skipping"
        return 0
    fi

    # Install GNOME Desktop and essential packages
    if ! apt-get install -y \
        gnome-shell \
        gnome-session \
        gnome-terminal \
        gnome-control-center \
        gnome-tweaks \
        gnome-software \
        ubuntu-desktop \
        ubuntu-desktop-minimal \
        nautilus \
        gdm3; then
        log_error "Failed to install GNOME Desktop packages"
        return 1
    fi

    # Install additional GNOME utilities
    if ! apt-get install -y \
        gedit \
        file-roller \
        eog \
        evince; then
        log_error "Failed to install GNOME utilities"
        return 1
    fi

    log_info "GNOME Desktop installed successfully"
}

# Install and configure xrdp
install_xrdp() {
    log_info "Installing and configuring xrdp..."

    # Install xrdp
    if ! apt-get install -y xrdp; then
        log_error "Failed to install xrdp"
        return 1
    fi

    # Add user to ssl-cert group (required for xrdp)
    if ! usermod -aG ssl-cert xrdp 2>/dev/null; then
        log_warn "Could not add xrdp user to ssl-cert group (may already exist)"
    fi

    # Backup original xrdp.ini
    if [[ -f /etc/xrdp/xrdp.ini ]]; then
        cp /etc/xrdp/xrdp.ini /etc/xrdp/xrdp.ini.bak || log_warn "Could not backup xrdp.ini"
    fi

    # Configure xrdp to use GNOME via custom start script
    if ! cat > /etc/xrdp/startwm.sh << 'EOF'
#!/bin/sh
# xrdp GNOME session script

if [ -r /etc/profile ]; then
    . /etc/profile
fi

# Start GNOME session
exec /usr/bin/gnome-session
EOF
    then
        log_error "Failed to create startwm.sh"
        return 1
    fi

    # Make it executable
    chmod +x /etc/xrdp/startwm.sh

    # Enable and start xrdp
    systemctl enable xrdp
    systemctl enable xrdp-sesman

    if ! systemctl restart xrdp; then
        log_error "Failed to start xrdp service"
        return 1
    fi

    # Verify xrdp is running
    if ! systemctl is-active --quiet xrdp; then
        log_error "xrdp service is not running after restart"
        return 1
    fi

    # Configure firewall (if ufw is active)
    if command -v ufw &> /dev/null; then
        ufw allow 3389/tcp comment "Allow RDP" 2>/dev/null || log_warn "Could not configure firewall"
    fi

    log_info "xrdp configured successfully"
    log_info "RDP access: Port 3389"
}

# Install Visual Studio Code
install_vscode() {
    log_info "Installing Visual Studio Code..."

    # Check if already installed
    if command -v code &> /dev/null; then
        log_warn "VS Code already installed, version: $(code --version | head -1)"
        return 0
    fi

    # Create keyrings directory if it doesn't exist
    mkdir -p /etc/apt/keyrings

    # Download and add Microsoft GPG key using modern method
    if ! wget -q https://packages.microsoft.com/keys/microsoft.asc -O- | gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg 2>/dev/null; then
        log_error "Failed to add Microsoft GPG key"
        return 1
    fi

    # Add VS Code repository with signed-by option
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | tee /etc/apt/sources.list.d/vscode.list > /dev/null

    # Update and install
    if ! apt-get update -y; then
        log_error "Failed to update package lists"
        return 1
    fi

    if ! apt-get install -y code; then
        log_error "Failed to install VS Code"
        return 1
    fi

    log_info "VS Code installed successfully"
}

# Install Claude Code CLI
install_claude_code() {
    log_info "Installing Claude Code..."

    # Check if already installed
    if command -v claude &> /dev/null; then
        log_warn "Claude Code already installed"
        return 0
    fi

    # Create installation directory
    mkdir -p ~/.local/bin

    # Download and run the official Claude Code installer
    # Using the official installer script from Anthropic
    if ! curl -sSfL https://docs.anthropic.com/claude-code/installer.sh | sh; then
        log_error "Failed to install Claude Code"
        return 1
    fi

    # Verify installation
    if ! command -v claude &> /dev/null; then
        log_error "Claude Code installation failed - command not found"
        return 1
    fi

    log_info "Claude Code installed successfully"
}

# Configure Claude Code to use OpenRouter
configure_claude_openrouter() {
    log_info "Configuring Claude Code to use OpenRouter..."

    # Create Claude Code config directory
    mkdir -p ~/.config/claude

    # Determine API key to use
    local api_key=""
    if [[ -n "${OPENROUTER_API_KEY:-}" ]]; then
        api_key="$OPENROUTER_API_KEY"
        log_info "Using OpenRouter API key from environment"
    elif [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        api_key="$ANTHROPIC_API_KEY"
        log_info "Using Anthropic API key from environment"
    else
        log_warn "No API key found - Claude Code will need manual configuration"
        log_warn "Set OPENROUTER_API_KEY or ANTHROPIC_API_KEY environment variable"
    fi

    # Configure OpenRouter as API provider
    # Create Claude Code settings with OpenRouter endpoint
    if [[ -n "$api_key" ]]; then
        cat > ~/.config/claude/settings.json << EOF
{
  "apiKey": "$api_key",
  "apiUrl": "https://openrouter.ai/api/v1"
}
EOF
        log_info "API key configured in settings.json"
    else
        cat > ~/.config/claude/settings.json << 'EOF'
{
  "apiKey": "",
  "apiUrl": "https://openrouter.ai/api/v1"
}
EOF
    fi

    # Create environment setup script for OpenRouter
    cat > ~/.config/claude/openrouter-env.sh << 'EOF'
# Claude Code OpenRouter Configuration
# Source this file or add to your ~/.bashrc

# Set OpenRouter as the API endpoint
export ANTHROPIC_API_BASE="https://openrouter.ai/api/v1"

# Set your API key (replace with your actual key or use environment variable)
# export OPENROUTER_API_KEY="your_api_key_here"
# export ANTHROPIC_API_KEY="$OPENROUTER_API_KEY"
EOF

    # Add to .bashrc if not already present
    local bashrc_entry='[[ -f ~/.config/claude/openrouter-env.sh ]] && source ~/.config/claude/openrouter-env.sh'
    if ! grep -q "openrouter-env.sh" ~/.bashrc 2>/dev/null; then
        echo "$bashrc_entry" >> ~/.bashrc
        log_info "Added OpenRouter environment to ~/.bashrc"
    fi

    log_info "Claude Code OpenRouter configuration complete"
}

# Install OpenRouter CLI
install_openrouter() {
    log_info "Installing OpenRouter CLI..."

    # Check if already installed
    if command -v openrouter &> /dev/null; then
        log_warn "OpenRouter CLI already installed"
        return 0
    fi

    # Install Node.js and npm from Ubuntu repositories (more secure)
    if ! command -v node &> /dev/null; then
        log_info "Installing Node.js..."

        # Try Ubuntu repositories first
        if ! apt-get install -y nodejs npm 2>/dev/null; then
            # Fallback to NodeSource if Ubuntu repos fail
            log_info "Ubuntu Node.js not available, using NodeSource..."
            if ! curl -fsSL https://deb.nodesource.com/setup_20.x | bash -; then
                log_error "Failed to setup NodeSource repository"
                return 1
            fi
            if ! apt-get install -y nodejs; then
                log_error "Failed to install Node.js"
                return 1
            fi
        fi
    fi

    # Verify npm is available
    if ! command -v npm &> /dev/null; then
        log_error "npm not available after Node.js installation"
        return 1
    fi

    # Install OpenRouter CLI (with proper error handling)
    if ! npm install -g openrouter 2>&1; then
        log_error "Failed to install OpenRouter CLI"
        return 1
    fi

    # Verify installation
    if ! command -v openrouter &> /dev/null; then
        log_error "OpenRouter CLI installation failed"
        return 1
    fi

    # Configure default model to minimax2.5
    mkdir -p ~/.config/openrouter
    cat > ~/.config/openrouter/config.json << 'EOF'
{
  "default_model": "minimax2.5"
}
EOF

    log_info "OpenRouter CLI installed with default model: minimax2.5"
}

# Main function
main() {
    log_info "Starting Remote Desktop Deployment v$SCRIPT_VERSION"
    log_info "Log file: $LOG_FILE"

    check_root
    detect_ubuntu_version
    update_system
    install_gnome
    install_xrdp
    install_vscode
    install_claude_code
    configure_claude_openrouter
    install_openrouter

    log_info "System ready for deployment"
}

main "$@"