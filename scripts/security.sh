#!/bin/bash
# Security Hardening - Configure firewall and intrusion prevention
# Usage: sudo bash scripts/security.sh [--uninstall]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

source "$PROJECT_ROOT/config.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

UNINSTALL=false
if [[ "${1:-}" == "--uninstall" ]]; then
    UNINSTALL=true
fi

do_install() {
    log_info "Installing security tools..."

    # Install fail2ban
    log_info "Installing fail2ban..."
    apt-get update -qq
    apt-get install -y -qq fail2ban

    # Install UFW
    log_info "Installing UFW..."
    apt-get install -y -qq ufw

    log_info "Security tools installed"
}

configure_fail2ban() {
    log_info "Configuring fail2ban..."

    # Create fail2ban config
    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
destemail = root@localhost
sender = fail2ban@localhost
action = %(action_mwl)s

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
EOF

    # Restart fail2ban
    systemctl enable fail2ban
    systemctl restart fail2ban

    log_info "fail2ban configured"
}

configure_ufw() {
    log_info "Configuring UFW firewall..."

    # Reset to defaults
    ufw --force reset

    # Default policies
    ufw default deny incoming
    ufw default allow outgoing

    # Allow SSH
    ufw allow 22/tcp comment 'SSH'

    # Allow RDP
    ufw allow 3389/tcp comment 'RDP'

    # Enable UFW
    echo "y" | ufw enable

    log_info "UFW configured"
}

do_uninstall() {
    log_info "Removing security tools..."

    systemctl stop fail2ban || true
    systemctl disable fail2ban || true
    apt-get remove -y -qq fail2ban || true

    ufw disable || true
    apt-get remove -y -qq ufw || true

    log_info "Security tools removed"
}

# Main
if [[ "$UNINSTALL" == "true" ]]; then
    do_uninstall
else
    do_install
    configure_fail2ban
    configure_ufw

    echo ""
    echo "Security status:"
    echo "  fail2ban: $(systemctl is-active fail2ban)"
    echo "  UFW: $(ufw status | head -1)"
    echo ""
    echo "Allowed ports:"
    ufw status | grep -E "^\d" || true
fi
