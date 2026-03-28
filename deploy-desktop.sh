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

        # Ensure X11 allows any user (needed for RDP)
        if [[ ! -f /etc/X11/Xwrapper.config ]] || ! grep -q "allowed_users" /etc/X11/Xwrapper.config 2>/dev/null; then
            echo "allowed_users=any" > /etc/X11/Xwrapper.config
        fi
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

    # Install xrdp, XFCE (more reliable than GNOME for RDP), and dbus-x11
    if ! apt-get install -y xrdp xfce4 xfce4-goodies dbus-x11; then
        log_error "Failed to install xrdp packages"
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

    # Configure xrdp to use XFCE via custom start script
    if ! cat > /etc/xrdp/startwm.sh << 'EOF'
#!/bin/sh
# xrdp XFCE session script

if [ -r /etc/profile ]; then
    . /etc/profile
fi

# Start XFCE session
exec startxfce4
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

    # Clean up stale X11 sockets to prevent session conflicts
    rm -rf /tmp/.X11-unix/X* /tmp/.X*-lock 2>/dev/null || true

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

# Create non-root user for RDP access
create_desktop_user() {
    local username="${DESKTOP_USER:-desktopuser}"
    local password="${DESKTOP_USER_PASSWORD:-}"
    local keyring_fix="${DESKTOP_USER_KEYRING_FIX:-true}"

    log_info "Creating desktop user: $username"

    # Check if user already exists
    if id "$username" &>/dev/null; then
        log_info "User $username already exists"
    else
        # Create user
        useradd -m -s /bin/bash -G sudo,adm,cdrom,dip,plugdev "$username" || {
            log_error "Failed to create user $username"
            return 1
        }
        log_info "User $username created"
    fi

    # Set password if provided
    if [[ -n "$password" ]]; then
        echo "$username:$password" | chpasswd || log_warn "Could not set password"
    fi

    # Allow passwordless sudo for convenience (optional, can be removed for security)
    if [[ ! -f /etc/sudoers.d/"$username" ]]; then
        echo "$username ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/"$username"
        chmod 440 /etc/sudoers.d/"$username"
    fi

    log_info "Desktop user configured: $username"
}

# Copy desktop configuration to user
copy_desktop_configs() {
    local username="${DESKTOP_USER:-desktopuser}"
    local user_home="/home/$username"

    log_info "Copying desktop configurations to $username..."

    # Copy desktop shortcuts
    if [[ -d /root/Desktop ]]; then
        cp -r /root/Desktop "$user_home/" 2>/dev/null || true
        chown -R "$username:$username" "$user_home/Desktop" 2>/dev/null || true
    fi

    # Copy Claude config
    if [[ -d /root/.config/claude ]]; then
        mkdir -p "$user_home/.config/claude"
        cp -r /root/.config/claude/* "$user_home/.config/claude/" 2>/dev/null || true
        chown -R "$username:$username" "$user_home/.config/claude" 2>/dev/null || true
    fi

    # Copy MCP config
    if [[ -d /root/.config/desktop-seed ]]; then
        mkdir -p "$user_home/.config/desktop-seed"
        cp -r /root/.config/desktop-seed/* "$user_home/.config/desktop-seed/" 2>/dev/null || true
        chown -R "$username:$username" "$user_home/.config/desktop-seed" 2>/dev/null || true
    fi

    # Copy Claude JSON config
    if [[ -f /root/.claude.json ]]; then
        cp /root/.claude.json "$user_home/" 2>/dev/null || true
        chown "$username:$username" "$user_home/.claude.json" 2>/dev/null || true
    fi

    # Copy MCP servers config file
    if [[ -f /root/.config/desktop-seed/mcp-servers ]]; then
        mkdir -p "$user_home/.config/desktop-seed"
        cp /root/.config/desktop-seed/mcp-servers "$user_home/.config/desktop-seed/" 2>/dev/null || true
        chown "$username:$username" "$user_home/.config/desktop-seed/mcp-servers" 2>/dev/null || true
    fi

    # Create keyring auto-unlock for the user
    mkdir -p "$user_home/.config/autostart"
    cat > "$user_home/.config/autostart/unlock-keyring.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Unlock Keyring
Exec=bash -c 'echo -n | gnome-keyring-daemon --unlock --components=secrets'
Hidden=true
X-GNOME-Autostart-enabled=true
EOF

    # Create .xsession for XFCE (required for xrdp to work properly)
    cat > "$user_home/.xsession" << 'EOF'
#!/bin/sh
exec startxfce4
EOF
    chmod 700 "$user_home/.xsession"
    chown "$username:$username" "$user_home/.xsession"
    chown "$username:$username" "$user_home/.config/autostart/unlock-keyring.desktop"

    log_info "Desktop configurations copied to $username"
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

    # Ensure Node.js and npm are available
    if ! command -v node &> /dev/null; then
        log_info "Installing Node.js..."
        if ! apt-get install -y nodejs npm 2>/dev/null; then
            # Fallback to NodeSource if Ubuntu repos fail
            log_info "Using NodeSource for Node.js..."
            if ! curl -fsSL https://deb.nodesource.com/setup_22.x | bash -; then
                log_error "Failed to setup NodeSource repository"
                return 1
            fi
            if ! apt-get install -y nodejs npm; then
                log_error "Failed to install Node.js"
                return 1
            fi
        fi
    fi

    # Verify npm is available
    if ! command -v npm &> /dev/null; then
        log_error "npm not available"
        return 1
    fi

    # Install Claude Code via npm
    if ! npm install -g @anthropic-ai/claude-code 2>&1; then
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

    # Check if already installed (package provides 'orc' command)
    if command -v orc &> /dev/null || command -v openrouter &> /dev/null; then
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
            if ! curl -fsSL https://deb.nodesource.com/setup_22.x | bash -; then
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
    if ! npm install -g openrouter-cli 2>&1; then
        log_error "Failed to install OpenRouter CLI"
        return 1
    fi

    # Verify installation
    if ! command -v orc &> /dev/null && ! command -v openrouter &> /dev/null; then
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

# Install Claude Code Router
install_claude_code_router() {
    log_info "Installing Claude Code Router..."

    # Check if already installed
    if command -v ccr &> /dev/null; then
        log_warn "Claude Code Router already installed"
        return 0
    fi

    # Install Node.js 22+ if needed (required for ccr)
    if ! command -v node &> /dev/null; then
        log_info "Installing Node.js 22..."
        if ! curl -fsSL https://deb.nodesource.com/setup_22.x | bash -; then
            log_error "Failed to setup NodeSource repository"
            return 1
        fi
        if ! apt-get install -y nodejs; then
            log_error "Failed to install Node.js"
            return 1
        fi
    fi

    # Verify Node.js version is 20+
    local node_version=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
    if [[ "$node_version" -lt 20 ]]; then
        log_warn "Node.js version $node_version is too old, upgrading to Node.js 22..."
        curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
        apt-get install -y nodejs
    fi

    # Install claude-code-router
    if ! npm install -g @musistudio/claude-code-router 2>&1; then
        log_error "Failed to install Claude Code Router"
        return 1
    fi

    # Verify installation
    if ! command -v ccr &> /dev/null; then
        log_error "Claude Code Router installation failed - command not found"
        return 1
    fi

    log_info "Claude Code Router installed successfully"
}

# Install Claudish (Claude Code proxy for any AI model)
install_claudish() {
    log_info "Installing Claudish..."

    # Check if already installed
    if command -v claudish &> /dev/null; then
        log_warn "Claudish already installed"
        return 0
    fi

    # Install Claudish via npm
    if ! npm install -g claudish 2>&1; then
        log_error "Failed to install Claudish"
        return 1
    fi

    # Verify installation
    if ! command -v claudish &> /dev/null; then
        log_error "Claudish installation failed - command not found"
        return 1
    fi

    log_info "Claudish installed successfully"
}

# Install Chromium/Chrome Browser
install_chromium() {
    log_info "Installing Browser..."

    # Check if already installed (prefer Google Chrome)
    if command -v google-chrome-stable &> /dev/null; then
        log_warn "Google Chrome already installed"
        return 0
    fi

    if command -v chromium &> /dev/null || command -v chromium-browser &> /dev/null; then
        log_warn "Chromium already installed"
        return 0
    fi

    # Remove problematic snap versions if present
    if command -v snap &> /dev/null; then
        snap remove chromium firefox 2>/dev/null || true
    fi

    # Install Google Chrome (more reliable than snap chromium)
    log_info "Installing Google Chrome..."

    # Add Google Chrome repository
    if ! wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /etc/apt/keyrings/google-chrome.gpg 2>/dev/null; then
        log_error "Failed to add Google Chrome GPG key"
        return 1
    fi

    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" | tee /etc/apt/sources.list.d/google-chrome.list > /dev/null

    if ! apt-get update -y; then
        log_error "Failed to update package lists"
        return 1
    fi

    if ! apt-get install -y google-chrome-stable; then
        log_error "Failed to install Google Chrome"
        return 1
    fi

    log_info "Browser installed successfully"
}

# Install GitHub CLI
install_ghcli() {
    log_info "Installing GitHub CLI..."

    # Check if already installed
    if command -v gh &> /dev/null; then
        local current_version
        current_version=$(gh --version 2>/dev/null | head -1)
        log_warn "GitHub CLI already installed: $current_version"
        return 0
    fi

    local ghcli_repo_added=false
    local gh_version=""

    # Try to add official GitHub CLI repository
    log_info "Adding GitHub CLI official repository..."
    if wget -q -O - https://cli.github.com/packages/githubcli-archive-keyring.gpg 2>&1 | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null; then
        if echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null; then
            ghcli_repo_added=true
            log_info "GitHub CLI repository added successfully"
        else
            log_warn "Failed to configure GitHub CLI repository source"
        fi
    else
        log_warn "Failed to download GitHub CLI GPG key (network issue?)"
    fi

    # Update package lists
    if ! apt-get update -y 2>&1 | grep -q "Err\|Failed\|WARN"; then
        log_info "Package lists updated"
    else
        log_warn "Some package update warnings occurred"
    fi

    # Install GitHub CLI
    if ! apt-get install -y gh 2>&1; then
        log_error "Failed to install GitHub CLI"
        return 1
    fi

    # Verify installation and get version
    if command -v gh &> /dev/null; then
        gh_version=$(gh --version 2>/dev/null | head -1)
        log_info "GitHub CLI installed successfully: $gh_version"

        # Check if we got the official version or fell back to Ubuntu repo
        if [[ "$gh_version" == *"2.45"* ]]; then
            log_warn "Installed from Ubuntu repo (v2.45.0). Official repo version is newer (2.86+)"
            log_warn "To upgrade: run the same deploy-desktop.sh script after fixing network access to cli.github.com"
        fi
    else
        log_error "GitHub CLI installed but 'gh' command not found"
        return 1
    fi
}

# Set up environment variables and system-wide configuration
setup_environment() {
    log_info "Setting up environment variables..."

    # Create environment file for desktop applications
    cat > /etc/profile.d/remote-desktop.sh << 'EOF'
# Remote Desktop Environment Configuration

# Claude Code configuration
export ANTHROPIC_API_BASE="${ANTHROPIC_API_BASE:-https://openrouter.ai/api/v1}"
export OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"

# Editor configuration
export EDITOR=gedit
export VISUAL=gedit

# Desktop environment hints
export XDG_CURRENT_DESKTOP=GNOME
export XDG_SESSION_TYPE=x11
EOF

    # Make it executable
    chmod +x /etc/profile.d/remote-desktop.sh

    log_info "Environment configured"
}

# Configure MCP (Model Context Protocol) servers for Claude Code
configure_mcp_servers() {
    log_info "Configuring MCP servers..."

    # MCP servers can be configured via:
    # 1. CLAUDE_MCP_SERVERS environment variable (passed to script)
    # 2. ~/.config/desktop-seed/mcp-servers file (one per line: name:transport:url)

    local mcp_servers=""

    # First check env variable
    if [[ -n "${CLAUDE_MCP_SERVERS:-}" ]]; then
        mcp_servers="$CLAUDE_MCP_SERVERS"
    # Then check config file
    elif [[ -f "$HOME/.config/desktop-seed/mcp-servers" ]]; then
        mcp_servers=$(tr '\n' ',' < "$HOME/.config/desktop-seed/mcp-servers" | sed 's/,$//')
    fi

    if [[ -z "$mcp_servers" ]]; then
        log_info "No MCP servers configured (set CLAUDE_MCP_SERVERS or create ~/.config/desktop-seed/mcp-servers)"
        return 0
    fi

    # Ensure claude config directory exists
    mkdir -p ~/.claude

    # Create or read existing config
    local config_file="$HOME/.claude.json"
    local config_json

    if [[ -f "$config_file" ]]; then
        config_json=$(cat "$config_file")
    else
        config_json='{}'
    fi

    # Parse and add each MCP server
    IFS=',' read -ra SERVERS <<< "$mcp_servers"
    for server in "${SERVERS[@]}"; do
        # Parse: name:transport:url
        local name transport url
        IFS=':' read -r name transport url <<< "$server"

        if [[ -z "$name" || -z "$transport" || -z "$url" ]]; then
            log_warn "Invalid MCP server format: $server (expected name:transport:url)"
            continue
        fi

        log_info "Adding MCP server: $name"

        # Add to user-level mcpServers using jq
        if command -v jq &> /dev/null; then
            config_json=$(echo "$config_json" | jq --arg name "$name" --arg transport "$transport" --arg url "$url" \
                '.mcpServers = (.mcpServers // {}) + {($name): {"type": $transport, "url": $url}}')
        else
            log_warn "jq not installed, cannot configure MCP servers"
            return 1
        fi
    done

    # Write updated config
    echo "$config_json" > "$config_file"

    log_info "MCP servers configured: $mcp_servers"
}

# Create desktop shortcuts for installed applications
create_desktop_shortcuts() {
    log_info "Creating desktop shortcuts..."

    local desktop_dir="$HOME/Desktop"
    mkdir -p "$desktop_dir"

    # VS Code shortcut
    cat > "$desktop_dir/VS Code.desktop" << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Visual Studio Code
Comment=Code Editor
Exec=code
Icon=code
Terminal=false
Categories=Development;IDE;
EOF

    # Claude Code shortcut (terminal-based)
    cat > "$desktop_dir/Claude Code.desktop" << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Claude Code
Comment=AI Assistant
Exec=gnome-terminal -- claude
Icon=utilities-terminal
Terminal=true
Categories=Development;AI;
EOF

    # Chromium/Chrome shortcut - prefer Google Chrome (more reliable)
    local browser_exec="google-chrome-stable"
    if ! command -v google-chrome-stable &> /dev/null; then
        browser_exec="chromium-browser"
    fi

    # Browser shortcut
    local browser_name="Google Chrome"
    local browser_icon="google-chrome"
    if [[ "$browser_exec" == "chromium-browser" ]]; then
        browser_name="Chromium Browser"
        browser_icon="chromium-browser"
    fi

    cat > "$desktop_dir/Browser.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$browser_name
Comment=Web Browser
Exec=$browser_exec
Icon=$browser_icon
Terminal=false
Categories=Network;WebBrowser;
EOF

    # Make shortcuts executable
    chmod +x "$desktop_dir"/*.desktop

    log_info "Desktop shortcuts created"
}

# Display post-installation summary
show_summary() {
    log_info "========================================="
    log_info "  Remote Desktop Deployment Complete!"
    log_info "========================================="
    log_info ""
    log_info "Installed Components:"
    log_info "  - GNOME Desktop"
    log_info "  - xrdp (RDP server on port 3389)"
    log_info "  - Visual Studio Code"
    log_info "  - Claude Code"
    log_info "  - OpenRouter CLI (default model: minimax2.5)"
    log_info "  - Claude Code Router"
    log_info "  - Claudish (AI model proxy)"
    log_info "  - Chromium Browser"
    log_info ""
    log_info "Connection Information:"
    log_info "  - RDP Port: 3389"
    log_info "  - From Windows: Use Microsoft Remote Desktop"
    log_info "  - From Android: Use Microsoft Remote Desktop app"
    log_info ""
    log_info "To connect:"
    log_info "  1. Ensure port 3389 is open in firewall"
    log_info "  2. Use RDP client to connect to this machine's IP"
    log_info "  3. Login with your Ubuntu username/password"
    log_info ""
    log_info "Environment Variables (set before running Claude Code):"
    log_info "  export OPENROUTER_API_KEY=your_api_key_here"
    log_info ""
    log_info "Log file: $LOG_FILE"
    log_info "========================================="
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
    create_desktop_user
    copy_desktop_configs
    install_vscode
    install_claude_code
    configure_claude_openrouter
    install_openrouter
    install_claude_code_router
    install_chromium
    install_claudish
    install_ghcli
    setup_environment
    configure_mcp_servers
    create_desktop_shortcuts
    show_summary

    log_info "System ready for deployment"
}

main "$@"