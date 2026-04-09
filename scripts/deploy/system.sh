#!/bin/bash
# System setup module: update, GNOME, xrdp, user setup
# Source this from the main deploy script

set -euo pipefail

# Import common library
# SCRIPT_DIR is inherited from the main script
# If not set, detect it
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Resolve lib.sh path relative to THIS script (not inherited SCRIPT_DIR)
_lib_sh_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [[ -f "$_lib_sh_dir/lib.sh" ]]; then
    source "$_lib_sh_dir/lib.sh"
else
    echo "ERROR: Could not find lib.sh in $_lib_sh_dir"
    exit 1
fi
unset _lib_sh_dir

# Update package lists and upgrade system
update_system() {
    log_step "Updating package lists and upgrading system..."

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
    log_step "Installing GNOME Desktop..."

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
    fi
}

# Configure X11 wrapper
configure_xwrapper() {
    log_step "Configuring X11 wrapper..."

    # Configure X11 to allow any user to start X servers
    if [[ ! -f /etc/X11/Xwrapper.config ]] || ! grep -q "allowed_users" /etc/X11/Xwrapper.config; then
        echo "allowed_users=any" > /etc/X11/Xwrapper.config
        echo "allowed_users=console" >> /etc/X11/Xwrapper.config
        log_info "Configured X11 wrapper for multi-user access"
    fi

    # Configure D-Bus to allow system-wide connections
    if [[ ! -f /etc/dbus-1/system.d/xrdp.conf ]]; then
        mkdir -p /etc/dbus-1/system.d
        cat > /etc/dbus-1/system.d/xrdp.conf << 'EOF'
<!DOCTYPE busconfig PUBLIC
 "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <policy user="root">
    <allow own="org.freedesktop.Notifications"/>
  </policy>
  <policy context="default">
    <allow send_destination="org.freedesktop.Notifications"/>
    <allow receive_sender="org.freedesktop.Notifications"/>
  </policy>
</busconfig>
EOF
        log_info "Configured D-Bus for notifications"
    fi
}

# Install xrdp
install_xrdp() {
    log_step "Installing xrdp..."

    # Install xrdp and dependencies
    if ! apt-get install -y xrdp xorgxrdp; then
        log_error "Failed to install xrdp"
        return 1
    fi

    # Configure xrdp
    log_info "Configuring xrdp..."

    # Set SSL TLS
    sed -i 's/^ssl_protocols=.*/ssl_protocols=TLSv1.2 TLSv1.3/' /etc/xrdp/xrdp.ini 2>/dev/null || true

    # Allow console users (also duplicate the username from the sesman.ini)
    sed -i 's/^allow_reconnect=true/allow_reconnect=true\nallow_console=true/' /etc/xrdp/xrdp.ini 2>/dev/null || true

    # Configure sesman to allow console login
    if ! grep -q "allow_reconnect=true" /etc/xrdp/sesman.ini; then
        sed -i '/\[Global\]/a allow_reconnect=true' /etc/xrdp/sesman.ini
    fi
    if ! grep -q "AllowRoot=true" /etc/xrdp/sesman.ini; then
        sed -i '/\[Security\]/a AllowRoot=true' /etc/xrdp/sesman.ini
    fi

    # Add desktop user to ssl-cert group
    if id -u desktopuser &>/dev/null; then
        usermod -aG ssl-cert desktopuser 2>/dev/null || true
    fi

    # Copy custom startwm.sh
    if [[ -f "$(dirname "$SCRIPT_DIR")/../etc/xrdp/startwm.sh" ]]; then
        cp "$(dirname "$SCRIPT_DIR")/../etc/xrdp/startwm.sh" /etc/xrdp/startwm.sh
        chmod +x /etc/xrdp/startwm.sh
        log_info "Installed custom startwm.sh"
    fi

    # Start and enable xrdp
    systemctl enable xrdp --now || true
    systemctl enable xrdp-sesman --now || true

    # Configure firewall
    if command -v ufw &> /dev/null; then
        ufw allow 3389/tcp 2>/dev/null || true
    fi

    log_info "xrdp installed and configured"
}

# Create desktop user
create_desktop_user() {
    log_step "Creating desktop user..."

    local username="desktopuser"

    if id "$username" &>/dev/null; then
        log_info "User $username already exists"
        return 0
    fi

    # Get current user for sudo group
    local sudo_group="sudo"
    if grep -q "admin" /etc/group; then
        sudo_group="admin"
    fi

    # Create user with home directory and bash shell
    useradd -m -s /bin/bash -G "$sudo_group" "$username"

    # Set default password (change in production!)
    echo "$username:desktop" | chpasswd

    log_info "Created user: $username (password: desktop)"
}

# Copy desktop configurations
copy_desktop_configs() {
    log_step "Copying desktop configurations..."

    local username="desktopuser"
    local user_home=$(getent passwd "$username" | cut -d: -f6)

    if [[ -z "$user_home" ]]; then
        log_error "Cannot find home directory for $username"
        return 1
    fi

    # Create necessary directories
    mkdir -p "$user_home/.config"
    mkdir -p "$user_home/.local/share"
    mkdir -p "$user_home/Desktop"

    # Set ownership
    chown -R "$username:$username" "$user_home"

    log_info "Desktop configurations copied"
}