#!/bin/bash
# Monitoring - Log rotation and alerts setup
# Usage: sudo bash scripts/monitor.sh [--disable]

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

DISABLE=false
if [[ "${1:-}" == "--disable" ]]; then
    DISABLE=true
fi

setup_log_rotation() {
    log_info "Setting up log rotation..."

    # Rotate deployment logs
    cat > /etc/logrotate.d/desktop-deploy << 'EOF'
/tmp/deploy-desktop-*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
}
EOF

    log_info "Log rotation configured"
}

setup_disk_alerts() {
    log_info "Setting up disk space alerts..."

    # Create cron job for disk check
    cat > /etc/cron.daily/disk-alert << 'EOF'
#!/bin/bash
# Daily disk space check

THRESHOLD=90
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | tr -d '%')

if [ "$DISK_USAGE" -ge "$THRESHOLD" ]; then
    echo "WARNING: Disk usage is at ${DISK_USAGE}% on $(hostname)" | \
        mail -s "Disk Alert: $(hostname)" root@localhost 2>/dev/null || true
fi
EOF

    chmod +x /etc/cron.daily/disk-alert

    log_info "Disk alerts configured"
}

setup_service_monitoring() {
    log_info "Setting up service monitoring..."

    # Create systemd service check timer
    cat > /etc/systemd/system/desktop-monitor.timer << 'EOF'
[Unit]
Description=Desktop health check timer

[Timer]
OnBootSec=5min
OnUnitActiveSec=15min
Unit=desktop-monitor.service

[Install]
WantedBy=timers.target
EOF

    cat > /etc/systemd/system/desktop-monitor.service << 'EOF'
[Unit]
Description=Desktop health check

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'systemctl is-active --quiet xrdp || echo "xrdp failed" | mail root@localhost'
EOF

    systemctl daemon-reload
    systemctl enable desktop-monitor.timer

    log_info "Service monitoring configured"
}

do_disable() {
    log_info "Removing monitoring..."

    rm -f /etc/logrotate.d/desktop-deploy
    rm -f /etc/cron.daily/disk-alert
    systemctl stop desktop-monitor.timer 2>/dev/null || true
    systemctl disable desktop-monitor.timer 2>/dev/null || true
    rm -f /etc/systemd/system/desktop-monitor.timer
    rm -f /etc/systemd/system/desktop-monitor.service
    systemctl daemon-reload

    log_info "Monitoring disabled"
}

# Main
if [[ "$DISABLE" == "true" ]]; then
    do_disable
else
    setup_log_rotation
    setup_disk_alerts
    setup_service_monitoring

    echo ""
    log_info "Monitoring configured:"
    echo "  - Log rotation: /etc/logrotate.d/desktop-deploy"
    echo "  - Disk alerts: /etc/cron.daily/disk-alert"
    echo "  - Service monitoring: desktop-monitor.timer"
fi
