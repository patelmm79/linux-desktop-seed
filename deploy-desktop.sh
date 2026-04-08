#!/bin/bash
set -euo pipefail

# Remote Linux Desktop Deployment Script
# Deploys: GNOME, xrdp, VS Code, Claude Code, Chromium, OpenRouter
# Target: Ubuntu 20.04/22.04/24.04

SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/deploy-desktop-$(date +%Y%m%d-%H%M%S).log"

# Dry run mode - preview what would be installed without actually installing
DRY_RUN=false
for arg in "$@"; do
    case "$arg" in
        --dry-run|--preview)
            DRY_RUN=true
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run, --preview  Show what would be installed without installing"
            echo "  --help, -h            Show this help message"
            echo ""
            exit 0
            ;;
    esac
done

# Helper function for dry-run mode
would_install() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would install: $1"
    fi
}

install_if_not_exists() {
    local cmd="$1"
    local name="$2"
    if [[ "$DRY_RUN" == "true" ]]; then
        if ! command -v "$cmd" &> /dev/null; then
            log_info "[DRY RUN] Would install: $name"
        else
            log_info "[DRY RUN] Already installed: $name"
        fi
        return 0
    fi
    return 1  # Return 1 to continue with actual install in normal mode
}

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

    # Fix nautilus desktop entry for xrdp display
    if [[ -f /usr/share/applications/org.gnome.Nautilus.desktop ]]; then
        sed -i 's/^Exec=nautilus --new-window/Exec=env DISPLAY=:16 nautilus --new-window/' /usr/share/applications/org.gnome.Nautilus.desktop
        log_info "Fixed nautilus desktop entry for xrdp"
    fi

    # Fix text editor desktop entry for xrdp display
    if [[ -f /usr/share/applications/org.gnome.TextEditor.desktop ]]; then
        sed -i 's/^Exec=gnome-text-editor/Exec=env DISPLAY=:16 gnome-text-editor/' /usr/share/applications/org.gnome.TextEditor.desktop
        log_info "Fixed text editor desktop entry for xrdp"
    fi
}

# Fix X server wrapper configuration
configure_xwrapper() {
    log_info "Configuring X server wrapper..."

    # Fix Xwrapper.config to allow non-root X server access (required for xrdp)
    if [[ -f /etc/X11/Xwrapper.config ]]; then
        # Replace invalid 'any' value with valid 'anybody'
        sed -i 's/^allowed_users=any$/allowed_users=anybody/' /etc/X11/Xwrapper.config

        # Ensure the correct value exists
        if ! grep -q "^allowed_users=" /etc/X11/Xwrapper.config; then
            echo "allowed_users=anybody" >> /etc/X11/Xwrapper.config
        fi

        log_info "X server wrapper configured"
    else
        log_warn "Xwrapper.config not found, creating it"
        if ! cat > /etc/X11/Xwrapper.config << 'EOF'
# Xwrapper.config - X server wrapper configuration
# Required for xrdp to function properly
allowed_users=anybody
EOF
        then
            log_error "Failed to create Xwrapper.config"
            return 1
        fi
    fi
}

# Install and configure xrdp
install_xrdp() {
    log_info "Installing and configuring xrdp..."

    # Install xrdp and required display server
    if ! apt-get install -y xrdp xvfb tigervnc-standalone-server; then
        log_error "Failed to install xrdp and display servers"
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

    # Create minimal Xorg configuration for xrdp (uses dummy driver for virtual display)
    if ! cat > /etc/xrdp/xorg.conf << 'EOF'
# Minimal X11 configuration for xrdp
# Uses the dummy driver for virtual display

Section "Monitor"
    Identifier "Monitor0"
    HorizSync 31.5-37.9
    VertRefresh 50-70
EndSection

Section "Device"
    Identifier "Card0"
    Driver "dummy"
    VideoRam 256000
EndSection

Section "Screen"
    Identifier "Screen0"
    Device "Card0"
    Monitor "Monitor0"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "1280x1024" "1024x768" "800x600" "640x480"
    EndSubSection
EndSection
EOF
    then
        log_error "Failed to create xorg.conf"
        return 1
    fi

    # Configure xrdp to use GNOME via custom start script with Xvnc display server
    # NOTE: Starting gnome-shell directly instead of gnome-session works better
    # with xrdp on Ubuntu 24.04 (gnome-session has issues)
    if ! cat > /etc/xrdp/startwm.sh << 'EOF'
#!/bin/bash
# xrdp GNOME session script - start gnome-shell directly for xrdp compatibility
set -euo pipefail

# Defensive profile loading (handles unbound variables in some profile scripts)
set +u
[ -r /etc/profile ] && . /etc/profile 2>/dev/null || true
[ -r "$HOME/.profile" ] && . "$HOME/.profile" 2>/dev/null || true
set -u

echo "=== Starting RDP session at $(date) ===" >> ~/.xsession-errors

# Wait for X server (Xvnc) to be ready
_display_num="${DISPLAY#*:}"
for i in {1..30}; do
    [ -S "/tmp/.X11-unix/X${_display_num}" ] && break
    sleep 0.5
done
unset _display_num

[ -z "$DISPLAY" ] && { echo "ERROR: DISPLAY not set" >&2; exit 1; }

# Environment - CRITICAL: force X11, not Wayland (Xvnc doesn't support Wayland)
export GDK_BACKEND=x11
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=GNOME
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export GNOME_SHELL_SESSION_MODE=ubuntu
export GNOME_SHELL_WAYLANDRESTART=false

# Force scaling for high-DPI RDP displays
export GDK_SCALE=2
export GTK_SCALE=2

echo "DISPLAY=$DISPLAY, GDK_BACKEND=$GDK_BACKEND, GDK_SCALE=$GDK_SCALE" >> ~/.xsession-errors

# Start D-Bus session if not already running
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    eval $(dbus-launch --sh-syntax)
fi
echo "DBUS=$DBUS_SESSION_BUS_ADDRESS" >> ~/.xsession-errors

# Note: DPI/scaling must be configured AFTER gnome-shell starts, not before
# User can manually run: gsettings set org.gnome.desktop.interface text-scaling-factor 1.5
# Or configure via GNOME Settings → Accessibility → Text Size

# Start gnome-shell directly (bypasses gnome-session which has issues with xrdp)
exec nohup gnome-shell >> ~/.xsession-errors 2>&1
EOF
    then
        log_error "Failed to create startwm.sh"
        return 1
    fi

    # Make it executable
    chmod +x /etc/xrdp/startwm.sh

    # Configure sesman and xrdp to use Xvnc instead of Xorg (more reliable, fewer socket conflicts)
    if [[ -f /etc/xrdp/sesman.ini ]]; then
        # Use Python to properly configure Xvnc session in sesman.ini
        python3 << 'PYSCRIPT'
import re

with open('/etc/xrdp/sesman.ini', 'r') as f:
    content = f.read()

# Remove entire [Xorg] section
content = re.sub(r'\[Xorg\].*?(?=\[|\Z)', '', content, flags=re.DOTALL)

# Find and replace the [Xvnc] section with correct parameters
# NOTE: Do NOT include param=Xvnc as sesman automatically uses the type name as the binary
# Only add actual display parameters
xvnc_section = """[Xvnc]
type=Xvnc
param=-bs
param=-dpi
param=144
"""

# Replace existing [Xvnc] section
content = re.sub(r'\[Xvnc\].*?(?=\[|\Z)', xvnc_section, content, flags=re.DOTALL)

with open('/etc/xrdp/sesman.ini', 'w') as f:
    f.write(content)

print("Configured sesman.ini with proper Xvnc parameters (removed duplicate param=Xvnc)")
PYSCRIPT

        log_info "Configured sesman to use Xvnc sessions with correct parameters"
    fi

    # Configure xrdp.ini to remove Xorg and use only Xvnc
    if [[ -f /etc/xrdp/xrdp.ini ]]; then
        # Use Python to safely remove the Xorg section from xrdp.ini
        python3 << 'PYSCRIPT'
import re
try:
    with open('/etc/xrdp/xrdp.ini', 'r') as f:
        content = f.read()

    # Remove entire [Xorg] section (from [Xorg] to next section or end of file)
    content = re.sub(r'\[Xorg\].*?(?=\[|\Z)', '', content, flags=re.DOTALL)

    with open('/etc/xrdp/xrdp.ini', 'w') as f:
        f.write(content)

    print("Removed [Xorg] section from xrdp.ini")
except Exception as e:
    print(f"Error updating xrdp.ini: {e}")
PYSCRIPT

        log_info "Configured xrdp.ini to use only Xvnc"
    fi

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

    # Configure Xresources for DPI scaling on RDP sessions
    if [ -d /etc/xrdp ]; then
        cat > /etc/xrdp/Xresources << 'XRES'
! Set default DPI for xrdp sessions to fix small text/icons
Xft.dpi: 144
Xft.autohint: 0
Xft.lcdfilter:  lcddefault
Xft.hinting: 1
Xft.hintstyle:  hintslight
Xft.antialias: 1
Xft.rgba: rgb
XRES
        log_info "Configured Xresources for DPI scaling"
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
        # Fix execute permissions - GNOME shows red X on files without +x
        chmod +x "$user_home/Desktop"/* 2>/dev/null || true
    fi

    # Copy Claude config
    if [[ -d /root/.config/claude ]]; then
        mkdir -p "$user_home/.config/claude"
        cp -r /root/.config/claude/* "$user_home/.config/claude/" 2>/dev/null || true
        chown -R "$username:$username" "$user_home/.config/claude" 2>/dev/null || true
    fi

    # Copy OpenCLAW wrapper and symlink
    if [[ -f /root/.local/bin/openclaw ]]; then
        mkdir -p "$user_home/.local/bin"
        cp /root/.local/bin/openclaw "$user_home/.local/bin/" 2>/dev/null || true
        chown -R "$username:$username" "$user_home/.local" 2>/dev/null || true
        chmod +x "$user_home/.local/bin/openclaw" 2>/dev/null || true
    fi
    if [[ -L /usr/local/bin/openclaw ]]; then
        ln -sf /root/.local/bin/openclaw /usr/local/bin/openclaw 2>/dev/null || true
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
    chown "$username:$username" "$user_home/.config/autostart/unlock-keyring.desktop"

    # Create desktop permission fixer - ensures all desktop files have +x (prevents red X)
    # This runs on every session start as a defensive measure
    mkdir -p "$user_home/.config/autostart"
    cat > "$user_home/.config/autostart/fix-desktop-permissions.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Fix Desktop Permissions
Exec=bash -c 'chmod +x "$HOME/Desktop"/* 2>/dev/null || true'
Hidden=true
X-GNOME-Autostart-enabled=true
EOF
    chown "$username:$username" "$user_home/.config/autostart/fix-desktop-permissions.desktop"

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
  "apiUrl": "https://openrouter.ai/api/v1",
  "httpTitle": "desktop-seed"
}
EOF
        log_info "API key configured in settings.json"
    else
        cat > ~/.config/claude/settings.json << 'EOF'
{
  "apiKey": "",
  "apiUrl": "https://openrouter.ai/api/v1",
  "httpTitle": "desktop-seed"
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

    # Create wrapper script for dynamic per-repo OpenRouter billing
    # This detects the current git repo and sets httpTitle accordingly
    cat > ~/.local/bin/claude << 'WRAPPER'
#!/bin/bash
# Claude Code wrapper for dynamic OpenRouter billing by repo

# Detect git repo name from current directory
REPO_NAME=""
if git rev-parse --git-dir >/dev/null 2>&1; then
    # Get repo name from git remote or directory
    REPO_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null)
fi

# Fallback to hostname if not in a git repo
if [[ -z "$REPO_NAME" ]]; then
    REPO_NAME="${HOSTNAME:-desktop}"
fi

# Update settings.json with dynamic httpTitle
SETTINGS_FILE="$HOME/.config/claude/settings.json"
if [[ -f "$SETTINGS_FILE" ]]; then
    # Use python3 for reliable JSON manipulation
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import json
import os
settings_file = os.path.expanduser('$HOME/.config/claude/settings.json')
with open(settings_file, 'r') as f:
    settings = json.load(f)
settings['httpTitle'] = '$REPO_NAME'
with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)
"
    fi
fi

# Execute actual Claude Code
if command -v /usr/bin/claude >/dev/null 2>&1; then
    exec /usr/bin/claude "$@"
elif command -v claude >/dev/null 2>&1; then
    exec claude "$@"
else
    echo "Error: Claude Code not found" >&2
    exit 1
fi
WRAPPER
    chmod +x ~/.local/bin/claude
    log_info "Created dynamic repo-aware Claude wrapper at ~/.local/bin/claude"

    # Add ~/.local/bin to PATH in .bashrc if not present
    if ! grep -q '~/.local/bin' ~/.bashrc 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
        log_info "Added ~/.local/bin to PATH"
    fi

    log_info "Claude Code OpenRouter configuration complete"
}

# Setup OpenCLAW wrapper for per-repo OpenRouter billing
setup_openclaw_wrapper() {
    log_info "Setting up OpenCLAW wrapper for dynamic billing..."

    # Check if OpenCLAW is installed
    if ! command -v openclaw &> /dev/null; then
        log_warn "OpenCLAW not installed - skipping wrapper"
        return 0
    fi

    # Create wrapper script for dynamic per-repo OpenRouter billing for OpenCLAW
    # This detects the current git repo and sets HTTP-Referer/X-Title headers
    cat > ~/.local/bin/openclaw << 'WRAPPER'
#!/bin/bash
# OpenCLAW wrapper for dynamic OpenRouter billing by repo

# Detect git repo name from current directory
REPO_NAME=""
if git rev-parse --git-dir >/dev/null 2>&1; then
    REPO_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null)
fi

# Fallback to hostname if not in a git repo
if [[ -z "$REPO_NAME" ]]; then
    REPO_NAME="${HOSTNAME:-openclaw}"
fi

# Build referer URL based on repo
REFERER="https://github.com/patelmm79/${REPO_NAME}"

# Update OpenCLAW config with dynamic headers
OPENCLAW_CONFIG="$HOME/.openclaw/openclaw.json"
if [[ -f "$OPENCLAW_CONFIG" ]] && command -v python3 >/dev/null 2>&1; then
    python3 -c "
import json
import os

config_file = os.path.expanduser('$OPENCLAW_CONFIG')
with open(config_file, 'r') as f:
    config = json.load(f)

# Ensure models section exists
if 'models' not in config:
    config['models'] = {'mode': 'merge', 'providers': {}}
if 'providers' not in config['models']:
    config['models']['providers'] = {}

# Set OpenRouter provider with dynamic headers
config['models']['providers']['openrouter'] = {
    'apiKey': {'source': 'env', 'id': 'OPENROUTER_API_KEY'},
    'headers': {
        'HTTP-Referer': '$REFERER',
        'X-Title': '$REPO_NAME'
    }
}

with open(config_file, 'w') as f:
    json.dump(config, f, indent=2)
"
fi

# Execute actual OpenCLAW
if command -v /usr/bin/openclaw >/dev/null 2>&1; then
    exec /usr/bin/openclaw "$@"
elif command -v openclaw >/dev/null 2>&1; then
    exec openclaw "$@"
else
    echo "Error: OpenCLAW not found" >&2
    exit 1
fi
WRAPPER
    chmod +x ~/.local/bin/openclaw
    log_info "Created dynamic repo-aware OpenCLAW wrapper at ~/.local/bin/openclaw"

    # Also create symlink in /usr/local/bin for system-wide access
    ln -sf ~/.local/bin/openclaw /usr/local/bin/openclaw 2>/dev/null || true
    log_info "Symlinked wrapper to /usr/local/bin for PATH access"

    # Add ~/.local/bin to PATH in .bashrc if not present
    if ! grep -q '~/.local/bin' ~/.bashrc 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
        log_info "Added ~/.local/bin to PATH"
    fi

    log_info "OpenCLAW wrapper setup complete"
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

# Install Bun runtime
install_bun() {
    log_info "Installing Bun runtime..."

    # Check if already installed
    if command -v bun &> /dev/null; then
        local bun_version
        bun_version=$(bun --version 2>/dev/null)
        log_info "Bun already installed: v$bun_version"
        return 0
    fi

    # Install bun using official installer
    if curl -fsSL https://bun.sh/install 2>/dev/null | bash 2>&1; then
        # Source bun's shell env to get path
        if [ -f "$HOME/.bashrc" ]; then
            . "$HOME/.bashrc" 2>/dev/null || true
        fi

        # Create symlink to system location
        if [ -f "$HOME/.bun/bin/bun" ]; then
            ln -sf "$HOME/.bun/bin/bun" /usr/local/bin/bun 2>/dev/null || true
        fi

        if command -v bun &> /dev/null; then
            local bun_version
            bun_version=$(bun --version 2>/dev/null)
            log_info "Bun installed successfully: v$bun_version"
        else
            log_warn "Bun installed but command not found in PATH"
        fi
    else
        log_warn "Failed to install Bun (may retry on next deployment)"
    fi
}

# Install OpenCLAW AI client
install_openclaw() {
    log_info "Installing OpenCLAW..."

    # Check if already installed
    if command -v openclaw &> /dev/null; then
        local oc_version
        oc_version=$(openclaw --version 2>/dev/null || echo "installed")
        log_info "OpenCLAW already installed"
        return 0
    fi

    # Install via npm as global package
    # First ensure Node.js is available
    if ! command -v node &> /dev/null; then
        log_info "Installing Node.js for OpenCLAW..."
        if ! apt-get install -y nodejs npm 2>&1 | grep -q "Err\|Failed"; then
            log_info "Node.js installed"
        else
            log_warn "Failed to install Node.js"
        fi
    fi

    # Install openclaw globally
    if command -v npm &> /dev/null; then
        if npm install -g openclaw 2>&1; then
            # Verify installation
            if command -v openclaw &> /dev/null; then
                log_info "OpenCLAW installed successfully"
            else
                # Try to find and symlink
                local npm_global_path
                npm_global_path=$(npm root -g 2>/dev/null)
                if [ -f "$npm_global_path/openclaw/bin/openclaw.js" ]; then
                    ln -sf "$npm_global_path/openclaw/bin/openclaw.js" /usr/bin/openclaw 2>/dev/null || true
                fi
                if command -v openclaw &> /dev/null; then
                    log_info "OpenCLAW installed successfully"
                else
                    log_warn "OpenCLAW npm package installed but command not found"
                fi
            fi
        else
            log_warn "Failed to install OpenCLAW via npm"
        fi
    else
        log_warn "npm not available - cannot install OpenCLAW"
    fi
}

# Install Terraform and Terragrunt
install_terraform() {
    log_info "Installing Terraform and Terragrunt..."

    # First, check/install Terragrunt (always run this)
    if ! command -v terragrunt &> /dev/null; then
        log_info "Installing Terragrunt..."

        local terragrunt_version="v0.69.0"
        if curl -fsSL "https://github.com/gruntwork-io/terragrunt/releases/download/${terragrunt_version}/terragrunt_linux_amd64" -o /usr/local/bin/terragrunt 2>/dev/null; then
            chmod +x /usr/local/bin/terragrunt
            log_info "Terragrunt installed successfully"
        else
            log_warn "Failed to install Terragrunt"
        fi
    else
        local tg_version
        tg_version=$(terragrunt --version 2>/dev/null | head -1)
        log_info "Terragrunt already installed: $tg_version"
    fi

    # Then check/install Terraform (independent of Terragrunt state)
    if ! command -v terraform &> /dev/null; then
        log_info "Installing Terraform CLI..."

        # Add HashiCorp GPG key
        if [ ! -f /usr/share/keyrings/hashicorp-archive-keyring.gpg ]; then
            if ! curl -fsSL https://apt.releases.hashicorp.com/gpg 2>/dev/null | \
                gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg 2>/dev/null; then
                log_warn "Failed to add HashiCorp GPG key (continuing anyway)"
            fi
        fi

        # Add HashiCorp repository
        if [ ! -f /etc/apt/sources.list.d/hashicorp.list ]; then
            echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" > \
                /etc/apt/sources.list.d/hashicorp.list
        fi

        # Install Terraform
        if apt-get update -qq 2>/dev/null && apt-get install -y -qq terraform 2>/dev/null; then
            log_info "Terraform installed successfully"
        else
            log_warn "Failed to install Terraform from repo, trying direct download..."
            # Fallback: direct download
            if curl -fsSL https://releases.hashicorp.com/terraform/1.7.5/terraform_1.7.5_linux_amd64.zip -o /tmp/terraform.zip 2>/dev/null && \
               unzip -o /tmp/terraform.zip -d /usr/local/bin/ 2>/dev/null; then
                chmod +x /usr/local/bin/terraform
                rm -f /tmp/terraform.zip
                log_info "Terraform installed via direct download"
            else
                log_error "Failed to install Terraform"
            fi
        fi
    else
        local tf_version
        tf_version=$(terraform version 2>/dev/null | head -1)
        log_info "Terraform already installed: $tf_version"
    fi

    return 0
}

# Install Google Cloud CLI (gcloud)
install_gcloud() {
    log_info "Installing Google Cloud SDK..."

    # Check if gcloud is already properly installed and working
    if command -v gcloud &> /dev/null && gcloud version &> /dev/null; then
        local gcloud_version
        gcloud_version=$(gcloud version 2>/dev/null | head -1)
        log_info "Google Cloud SDK already installed: $gcloud_version"
        return 0
    fi

    # Remove broken gcloud installation if present
    if [ -f /usr/local/bin/gcloud ]; then
        # Check if it's the broken stub installer that doesn't work
        if ! /usr/local/bin/gcloud version &> /dev/null; then
            log_info "Removing broken gcloud installation..."
            rm -f /usr/local/bin/gcloud
        fi
    fi

    # Add Google Cloud SDK repository
    log_info "Adding Google Cloud SDK repository..."
    # Download and add Google Cloud GPG key
    if ! curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg 2>/dev/null | \
        gpg --dearmor -o /usr/share/keyrings/gcloud-keyring.gpg 2>/dev/null; then
        log_warn "Failed to add Google Cloud GPG key"
    fi

    # Add repository to sources (overwrite if exists, as it may be malformed)
    echo "deb [signed-by=/usr/share/keyrings/gcloud-keyring.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | \
        tee /etc/apt/sources.list.d/google-cloud-sdk.list > /dev/null
    log_info "Google Cloud SDK repository added"

    # Update package lists
    if ! apt-get update -y 2>&1 | grep -q "Err\|Failed"; then
        log_info "Package lists updated"
    else
        log_warn "Some package update warnings occurred"
    fi

    # Install Google Cloud SDK
    if ! apt-get install -y google-cloud-sdk 2>&1; then
        log_error "Failed to install Google Cloud SDK"
        return 1
    fi

    # Verify installation
    if command -v gcloud &> /dev/null && gcloud version &> /dev/null; then
        local gcloud_version
        gcloud_version=$(gcloud version 2>/dev/null | head -1)
        log_info "Google Cloud SDK installed successfully: $gcloud_version"
    else
        log_error "Google Cloud SDK installed but 'gcloud' command not working"
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

# Setup GNOME Keyring for secure credential storage
setup_keyring() {
    log_info "Setting up GNOME Keyring for credential storage..."

    # Install keyring packages
    if ! apt-get install -y -qq gnome-keyring libsecret-1-0 libpam-gnome-keyring; then
        log_error "Failed to install keyring packages"
        return 1
    fi

    # Verify keyring is available
    if ! command -v gnome-keyring-daemon &> /dev/null; then
        log_error "gnome-keyring-daemon not found after installation"
        return 1
    fi

    log_info "GNOME Keyring installed and configured"
}

# Setup session monitoring and crash recovery
setup_monitoring() {
    log_info "Setting up session monitoring and crash recovery..."

    # Copy the monitoring script
    if [ -f "scripts/session-monitor.sh" ]; then
        cp scripts/session-monitor.sh /tmp/session-monitor.sh
        chmod +x /tmp/session-monitor.sh

        # Run setup with --enable flag
        if bash /tmp/session-monitor.sh --enable 2>&1 | tee -a "$LOG_FILE"; then
            log_info "Session monitor service installed and started"
        else
            log_warn "Session monitor setup encountered issues (non-fatal)"
        fi
    else
        log_warn "Session monitor script not found in scripts/session-monitor.sh"
    fi

    # Setup session cleanup cron job
    if [ -f "scripts/cleanup-sessions.sh" ]; then
        cp scripts/cleanup-sessions.sh /tmp/cleanup-sessions.sh
        chmod +x /tmp/cleanup-sessions.sh

        # Create cron entry to run cleanup every 5 minutes
        CRON_ENTRY="*/5 * * * * /tmp/cleanup-sessions.sh >> /var/log/xrdp/session-cleanup.log 2>&1"

        # Add to crontab if not already present
        if ! crontab -l 2>/dev/null | grep -q "cleanup-sessions.sh"; then
            (crontab -l 2>/dev/null || true; echo "$CRON_ENTRY") | crontab -
            log_info "Session cleanup cron job installed (runs every 5 minutes)"
        else
            log_info "Session cleanup cron job already configured"
        fi
    else
        log_warn "Cleanup script not found in scripts/cleanup-sessions.sh"
    fi
}

# Setup OpenCLAW configuration
setup_openclaw_config() {
    log_info "Setting up OpenCLAW configuration..."

    # Only configure if OpenCLAW is installed
    if ! command -v openclaw &> /dev/null; then
        log_warn "OpenCLAW not installed - skipping config"
        return 0
    fi

    OPENCLAW_CONFIG_DIR="$HOME/.openclaw"
    OPENCLAW_CONFIG_FILE="$OPENCLAW_CONFIG_DIR/openclaw.json"
    DEFAULTS_FILE="config/openclaw-defaults.json"

    # Create config directory if it doesn't exist
    mkdir -p "$OPENCLAW_CONFIG_DIR"
    chmod 700 "$OPENCLAW_CONFIG_DIR"

    # Check if defaults file exists
    if [ ! -f "$DEFAULTS_FILE" ]; then
        log_warn "OpenCLAW defaults not found - skipping config"
        return 0
    fi

    # If no existing config, copy defaults
    if [ ! -f "$OPENCLAW_CONFIG_FILE" ]; then
        cp "$DEFAULTS_FILE" "$OPENCLAW_CONFIG_FILE"
        chmod 600 "$OPENCLAW_CONFIG_FILE"
        log_info "OpenCLAW configured from defaults (new install)"
    else
        # Existing config found - merge with defaults preserving channels
        log_info "Merging OpenCLAW config with existing settings..."

        # Use jq to merge configs, keeping existing channels if they exist
        if command -v jq &> /dev/null; then
            # Merge agents, messages, commands sections from defaults
            # Preserve existing channels and gateway settings
            jq -s '.[0] * .[1]' "$OPENCLAW_CONFIG_FILE" "$DEFAULTS_FILE" > "$OPENCLAW_CONFIG_FILE.tmp" 2>/dev/null && \
                mv "$OPENCLAW_CONFIG_FILE.tmp" "$OPENCLAW_CONFIG_FILE" || \
                cp "$DEFAULTS_FILE" "$OPENCLAW_CONFIG_FILE"
            log_info "OpenCLAW config merged with defaults"
        else
            # If jq not available, backup existing and use defaults
            cp "$OPENCLAW_CONFIG_FILE" "$OPENCLAW_CONFIG_FILE.backup.$(date +%Y%m%d)"
            cp "$DEFAULTS_FILE" "$OPENCLAW_CONFIG_FILE"
            log_warn "jq not available - backed up existing config and used defaults"
        fi
        chmod 600 "$OPENCLAW_CONFIG_FILE"
    fi

    log_info "OpenCLAW configuration complete"
}

# Setup GitHub Issues integration
setup_github_issues() {
    log_info "Setting up GitHub Issues integration..."

    # Check if gh is installed
    if ! command -v gh &> /dev/null; then
        log_warn "GitHub CLI (gh) not installed - GitHub Issues disabled"
        return 0
    fi

    # Check if authenticated
    if ! gh auth status &> /dev/null; then
        log_warn "GitHub not authenticated - run 'gh auth login' to enable issues"
        log_info "  To enable GitHub Issues:"
        log_info "    1. Run: gh auth login"
        log_info "    2. Set environment variables:"
        log_info "       export GITHUB_REPO='username/desktop-seed'"
        log_info "       export AUTO_ISSUE_ENABLED=true"
        return 0
    fi

    log_info "GitHub CLI configured - issues can be enabled via environment variables"
}

setup_gnome_extensions() {
    log_info "Setting up GNOME extensions..."

    # Install gnome-shell-extensions if not already installed
    if ! command -v gnome-shell &> /dev/null; then
        log_info "Installing GNOME Shell extensions package..."
        apt-get install -y -qq gnome-shell-extensions 2>&1 | tee -a "$LOG_FILE" || true
    fi

    # Disable problematic extensions for RDP sessions
    # The 'ding' (Desktop Icons NG) extension crashes with file-roller in xrdp sessions
    if [ -d "/usr/share/gnome-shell/extensions/ding@rastersoft.com" ]; then
        log_info "Disabling problematic ding extension for RDP compatibility..."
        mv /usr/share/gnome-shell/extensions/ding@rastersoft.com \
           /usr/share/gnome-shell/extensions/ding@rastersoft.com.disabled 2>/dev/null || true
    fi

    # Install Cascade Windows extension (UUID: cascade-windows@fthx)
    # This extension rearranges windows into a cascade pattern
    local extension_uuid="cascade-windows@fthx"
    local extension_path="$HOME/.local/share/gnome-shell/extensions/$extension_uuid"

    # Check if extension is already installed
    if [ -d "$extension_path" ]; then
        log_info "Cascade Windows extension already installed"
    else
        log_info "Installing Cascade Windows extension..."

        # Clone the extension from GitHub
        mkdir -p "$HOME/.local/share/gnome-shell/extensions"
        if git clone https://github.com/Lytol/gnome-cascade-windows.git "$extension_path" 2>&1 | tee -a "$LOG_FILE"; then
            # Enable the extension for the desktop user using dconf
            # This uses the desktop user's dconf database
            if [ -d "$extension_path" ]; then
                log_info "Cascade Windows extension installed successfully"
                # Extension will be available after next login
            fi
        else
            log_warn "Failed to clone Cascade Windows extension (non-fatal)"
        fi
    fi
}

# Validate deployment - ensure RDP will work
validate_deployment() {
    log_info "Validating deployment..."

    # Check xrdp is running
    if systemctl is-active --quiet xrdp; then
        log_info "  - xrdp service is running"
    else
        log_warn "  - xrdp service is NOT running"
    fi

    # Check startwm.sh exists and is executable
    if [ -x /etc/xrdp/startwm.sh ]; then
        log_info "  - startwm.sh is configured and executable"
    else
        log_warn "  - startwm.sh is missing or not executable"
    fi

    # Verify key environment variables are set in startwm.sh
    if grep -q "GDK_BACKEND=x11" /etc/xrdp/startwm.sh 2>/dev/null; then
        log_info "  - GDK_BACKEND=x11 configured (forces X11, not Wayland)"
    else
        log_warn "  - GDK_BACKEND not configured - RDP may fail"
    fi

    # Check dbus is available
    if command -v dbus-launch &> /dev/null; then
        log_info "  - dbus-launch available for session initialization"
    else
        log_warn "  - dbus-launch not found"
    fi

    # Verify gnome-shell is available (used by startwm.sh)
    if command -v gnome-shell &> /dev/null; then
        log_info "  - gnome-shell is installed"
    else
        log_error "  - gnome-shell NOT found - Desktop will not start"
        return 1
    fi

    # Check for Xvnc (the RDP display server)
    if command -v Xvnc &> /dev/null; then
        log_info "  - Xvnc is installed"
    else
        log_warn "  - Xvnc not found - RDP may not work"
    fi

    # Check desktop user exists
    if id "desktopuser" &> /dev/null; then
        log_info "  - desktopuser account exists"
    else
        log_warn "  - desktopuser account not found"
    fi

    # Verify xrdp configuration
    if [ -f /etc/xrdp/xrdp.ini ]; then
        if grep -q "Xvnc" /etc/xrdp/xrdp.ini 2>/dev/null; then
            log_info "  - xrdp configured to use Xvnc"
        else
            log_warn "  - xrdp may not be properly configured"
        fi
    else
        log_warn "  - xrdp.ini not found"
    fi

    # Summary of installed components
    log_info "  - Installed components:"
    command -v code &> /dev/null && log_info "      * VS Code"
    command -v claude &> /dev/null && log_info "      * Claude Code"
    command -v gh &> /dev/null && log_info "      * GitHub CLI"
    command -v chromium &> /dev/null && log_info "      * Chromium"
    command -v bun &> /dev/null && log_info "      * Bun"
    command -v openclaw &> /dev/null && log_info "      * OpenCLAW"

    log_info "Deployment validation complete"
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
    log_info "  - Chromium Browser"
    log_info ""
    log_info "GNOME Extensions:"
    log_info "  - Cascade Windows (window arrangement tool)"
    log_info ""
    log_info "Security & Monitoring:"
    log_info "  - GNOME Keyring (secure credential storage)"
    log_info "  - Session monitoring (crash detection)"
    log_info "  - Memory management (prevents OOM)"
    log_info "  - Continuous health checks (every 30 seconds)"
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
    # Handle dry-run mode
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "========================================="
        echo "  DRY RUN MODE - No changes will be made"
        echo "========================================="
        echo ""
        log_info "This would install the following components:"
        log_info "  - GNOME Desktop"
        log_info "  - xrdp (RDP server)"
        log_info "  - Visual Studio Code"
        log_info "  - Claude Code"
        log_info "  - OpenRouter CLI"
        log_info "  - Claude Code Router"
        log_info "  - Chromium Browser"
        log_info "  - GitHub CLI"
        log_info "  - Bun runtime"
        log_info "  - OpenCLAW"
        log_info "  - Terraform & Terragrunt"
        log_info "  - Google Cloud SDK"
        log_info "  - Session monitoring"
        log_info "  - GNOME extensions"
        echo ""
        log_info "To run this deployment:"
        log_info "  sudo bash deploy-desktop.sh"
        echo ""
        exit 0
    fi

    log_info "Starting Remote Desktop Deployment v$SCRIPT_VERSION"
    log_info "Log file: $LOG_FILE"

    check_root
    detect_ubuntu_version
    update_system
    install_gnome
    configure_xwrapper
    install_xrdp
    create_desktop_user
    copy_desktop_configs
    install_vscode
    install_claude_code
    configure_claude_openrouter
    install_openrouter
    install_claude_code_router
    install_chromium
    install_ghcli
    install_bun
    install_openclaw
    setup_openclaw_wrapper
    install_terraform
    install_gcloud
    setup_environment
    configure_mcp_servers
    create_desktop_shortcuts
    setup_keyring
    setup_monitoring
    setup_openclaw_config
    setup_github_issues
    setup_gnome_extensions
    validate_deployment
    show_summary

    log_info "System ready for deployment"
}

main "$@"