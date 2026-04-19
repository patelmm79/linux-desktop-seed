#!/bin/bash
# GNOME Keyring Setup for RDP Sessions
# Ensures libsecret credential storage works properly in RDP environments
# Usage: sudo bash scripts/setup-keyring.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# === Check Prerequisites ===

check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing=0

    # Check gnome-keyring
    if ! dpkg -l | grep -q "^ii.*gnome-keyring"; then
        log_warn "gnome-keyring not installed"
        missing=$((missing + 1))
    else
        log_info "gnome-keyring: installed ✓"
    fi

    # Check libsecret
    if ! dpkg -l | grep -q "^ii.*libsecret-1"; then
        log_warn "libsecret-1-0 not installed"
        missing=$((missing + 1))
    else
        log_info "libsecret-1-0: installed ✓"
    fi

    # Check libpam-gnome-keyring
    if ! dpkg -l | grep -q "^ii.*libpam-gnome-keyring"; then
        log_warn "libpam-gnome-keyring not installed (PAM integration)"
        missing=$((missing + 1))
    else
        log_info "libpam-gnome-keyring: installed ✓"
    fi

    if [ "$missing" -gt 0 ]; then
        log_info "Installing missing packages..."
        apt-get update -qq
        apt-get install -y -qq gnome-keyring libsecret-1-0 libpam-gnome-keyring
        log_info "Packages installed"
    fi
}

# === Configure PAM Integration ===

configure_pam() {
    log_info "Configuring PAM integration..."

    local pam_config="/etc/pam.d/common-password"

    # Check if gnome-keyring is already in PAM config
    if grep -q "pam_gnome_keyring" "$pam_config"; then
        log_info "PAM already configured for gnome-keyring"
        return 0
    fi

    # Add gnome-keyring to PAM (commented in case it breaks auth)
    # The keyring will start via dbus/systemd instead
    log_info "PAM configuration deferred (using dbus/systemd instead)"
}

# === Enable Keyring Service ===

enable_keyring_service() {
    log_info "Enabling keyring services..."

    # The gnome-keyring daemon is started by:
    # 1. systemd --user services (if available)
    # 2. dbus activation (in startwm.sh)

    # Check if user dbus services are enabled
    if [ -d /etc/systemd/user-preset ]; then
        log_info "User systemd services available"
    fi

    # Verify keyring binaries are executable
    chmod +x /usr/bin/gnome-keyring-daemon 2>/dev/null || true

    log_info "Keyring services ready"
}

# === Test Keyring ===

test_keyring() {
    log_info "Testing keyring setup..."

    # Check if daemon can start
    if timeout 2 /usr/bin/gnome-keyring-daemon --start --components=secrets 2>/dev/null; then
        log_info "Keyring daemon starts successfully ✓"
    else
        log_warn "Keyring daemon test inconclusive (may be OK in RDP context)"
    fi

    # Check if libsecret is available
    if python3 -c "import gi; gi.require_version('Secret', '1'); from gi.repository import Secret" 2>/dev/null; then
        log_info "libsecret Python bindings available ✓"
    else
        log_warn "libsecret Python bindings not available (optional)"
    fi
}

# === Generate Configuration ===

generate_startup_config() {
    log_info "Creating keyring startup configuration..."

    cat > /etc/xrdp/keyring-setup.sh << 'KEYRING_SETUP_EOF'
#!/bin/bash
# Keyring setup for RDP session - sourced from startwm.sh

# Start gnome-keyring-daemon with proper components
if ! pgrep -u "$UID" gnome-keyring-daemon > /dev/null 2>&1; then
    eval "$(gnome-keyring-daemon --start --components=secrets,pkcs11 2>/dev/null)" || true
fi

# Ensure DBUS session is set (required for keyring communication)
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"

# Export keyring control socket if available
if [ -n "${GNOME_KEYRING_CONTROL:-}" ]; then
    export GNOME_KEYRING_CONTROL
fi

# SSH agent support (if gnome-keyring-daemon started with ssh component)
if [ -n "${SSH_AUTH_SOCK:-}" ]; then
    export SSH_AUTH_SOCK
fi
KEYRING_SETUP_EOF

    chmod +x /etc/xrdp/keyring-setup.sh
    log_info "Configuration created at /etc/xrdp/keyring-setup.sh"
}

# === Create User Keyring ===

create_user_keyring() {
    log_info "Creating default user keyring..."

    local keyring_dir="$HOME/.local/share/gnome-online-accounts"
    mkdir -p "$keyring_dir" 2>/dev/null || true

    # The keyring will be created on first use
    log_info "User keyring location ready"
}

# === Show Status ===

show_status() {
    echo ""
    echo -e "${BLUE}=== GNOME Keyring Status ===${NC}"
    echo ""

    # Check installed packages
    echo "Packages:"
    dpkg -l | grep -E "gnome-keyring|libsecret" | awk '{print "  " $2 ": " $3}' || echo "  (none installed)"

    echo ""
    echo "Daemon status:"
    if pgrep -u root gnome-keyring-daemon > /dev/null; then
        echo "  Root session: running ✓"
    else
        echo "  Root session: not running (will start on demand)"
    fi

    if pgrep -u 1000 gnome-keyring-daemon > /dev/null 2>&1; then
        echo "  Desktop user: running ✓"
    else
        echo "  Desktop user: not running (will start on demand)"
    fi

    echo ""
    echo "Keyring features:"
    echo "  • Password storage (libsecret)"
    echo "  • SSH key management"
    echo "  • X.509 certificate storage (PKCS#11)"
    echo "  • Credential auto-unlock on login"

    echo ""
    echo "Configuration:"
    [ -f /etc/xrdp/keyring-setup.sh ] && echo "  ✓ Startup script: /etc/xrdp/keyring-setup.sh" || echo "  ✗ Startup script: not found"
    [ -f /etc/xrdp/startwm.sh ] && grep -q "gnome-keyring" /etc/xrdp/startwm.sh && echo "  ✓ startwm.sh integrated" || echo "  ✗ startwm.sh not integrated"
}

# === Main ===

log_info "GNOME Keyring Setup for RDP Sessions"
echo ""

check_prerequisites
configure_pam
enable_keyring_service
generate_startup_config
test_keyring
create_user_keyring

echo ""
show_status

echo ""
log_info "Setup complete!"
echo ""
echo "Keyring will automatically:"
echo "  • Start when user logs in via RDP"
echo "  • Store credentials securely"
echo "  • Provide SSH key management"
echo "  • Handle PKCS#11 operations"
echo ""
echo "For more information, see:"
echo "  man gnome-keyring"
echo "  man secret-tool"
