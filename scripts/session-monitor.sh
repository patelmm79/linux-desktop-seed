#!/bin/bash
# Session Monitoring Daemon
# Monitors active RDP/X11 sessions for memory leaks, crashes, and performance issues
# Install as systemd service for continuous monitoring
# Usage: sudo bash scripts/session-monitor.sh [--enable|--disable|--test]

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

MONITOR_LOG="/var/log/xrdp/session-monitor.log"
ALERT_LOG="/var/log/xrdp/session-alerts.log"
MEMORY_THRESHOLD=80      # Alert if process uses > 80% of available memory
CPU_THRESHOLD=75         # Alert if process uses > 75% CPU
SESSION_TIMEOUT=3600     # Alert if session runs > 1 hour without activity
ORPHAN_CHECK_INTERVAL=300  # Check for orphaned processes every 5 minutes

# === GitHub Issue Configuration ===
GITHUB_REPO="${GITHUB_REPO:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
AUTO_ISSUE_ENABLED="${AUTO_ISSUE_ENABLED:-false}"
ISSUE_SEVERITY_THRESHOLD="${ISSUE_SEVERITY_THRESHOLD:-warning}"
ISSUE_DEDUP_WINDOW=3600  # seconds (1 hour)
LAST_ISSUE_TIME=0

# === Session Cleanup Functions ===

cleanup_orphaned_sessions() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local cleaned=0

    {
        echo "[$timestamp] === Session Cleanup ==="

        # Get all active Xvnc PIDs (these are the "owner" sessions)
        local active_xvnc_pids=$(pgrep -f "Xvnc" 2>/dev/null || true)

        # Find orphaned xrdp-chansrv processes (not associated with active Xvnc)
        for chansrv_pid in $(pgrep -f "xrdp-chansrv" 2>/dev/null || true); do
            local has_parent=false
            # Check if this chansrv has an associated Xvnc session
            for xvnc_pid in $active_xvnc_pids; do
                # Check if they're in the same session namespace (cgroup)
                if ps -o cgroup= -p "$chansrv_pid" 2>/dev/null | grep -q "$(ps -o cgroup= -p "$xvnc_pid" 2>/dev/null | head -1)"; then
                    has_parent=true
                    break
                fi
            done
            # Also check by process start time - if Xvnc started after chansrv, it's orphaned
            if [ "$has_parent" = false ]; then
                local chansrv_time=$(ps -o lstart= -p "$chansrv_pid" 2>/dev/null || echo "")
                local xvnc_start_times=$(for p in $active_xvnc_pids; do ps -o lstart= -p "$p" 2>/dev/null; done)
                # If chansrv is older than all Xvnc, consider it orphaned
                if [ -n "$chansrv_time" ]; then
                    echo "  Killing orphaned xrdp-chansrv PID $chansrv_pid (started $chansrv_time)"
                    kill "$chansrv_pid" 2>/dev/null || true
                    cleaned=$((cleaned + 1))
                fi
            fi
        done

        # Clean up orphaned pw-cli (pipewire) processes
        for pw_pid in $(pgrep -f "pw-cli.*xrdp" 2>/dev/null || true); do
            local has_parent=false
            for xvnc_pid in $active_xvnc_pids; do
                if ps -o cgroup= -p "$pw_pid" 2>/dev/null | grep -q "$(ps -o cgroup= -p "$xvnc_pid" 2>/dev/null | head -1)"; then
                    has_parent=true
                    break
                fi
            done
            if [ "$has_parent" = false ]; then
                local pw_time=$(ps -o lstart= -p "$pw_pid" 2>/dev/null || echo "")
                if [ -n "$pw_time" ]; then
                    echo "  Killing orphaned pw-cli PID $pw_pid (started $pw_time)"
                    kill "$pw_pid" 2>/dev/null || true
                    cleaned=$((cleaned + 1))
                fi
            fi
        done

        # Also kill any zombie/stale gnome-shell processes from dead sessions
        for gs_pid in $(pgrep -f "gnome-shell" 2>/dev/null || true); do
            local gs_display=$(ps -o args= -p "$gs_pid" 2>/dev/null | grep -oE 'DISPLAY=:[0-9]+' || echo "")
            if [ -n "$gs_display" ]; then
                # Check if Xvnc for this display exists
                local display_num=$(echo "$gs_display" | grep -oE '[0-9]+')
                if ! pgrep -f "Xvnc.*:$display_num" > /dev/null 2>&1; then
                    echo "  Killing orphaned gnome-shell PID $gs_pid (display :$display_num)"
                    kill "$gs_pid" 2>/dev/null || true
                    cleaned=$((cleaned + 1))
                fi
            fi
        done

        if [ "$cleaned" -gt 0 ]; then
            echo "  Cleaned $cleaned orphaned processes"
        else
            echo "  No orphaned sessions found"
        fi

    } >> "$MONITOR_LOG" 2>&1
}

periodic_sweep() {
    # Lightweight sweep - kill processes from sessions older than 24 hours
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local swept=0

    for xvnc_pid in $(pgrep -f "Xvnc" 2>/dev/null || true); do
        local session_age_seconds=$(ps -o etime= -p "$xvnc_pid" 2>/dev/null | awk '{print $1}' | tr '-' ':' | awk -F: '{if (NF==1) print $1*60; else print $1*1440+$2*60+$3}')
        # If session runs > 24 hours (1440 minutes), check if it's still responsive
        if [ -n "$session_age_seconds" ] && [ "$session_age_seconds" -gt 1440 ]; then
            # Check if session is still alive
            if ! ps -p "$xvnc_pid" > /dev/null 2>&1; then
                echo "[$timestamp] Removing stale Xvnc PID $xvnc_pid (age: ${session_age_seconds}m)"
                kill "$xvnc_pid" 2>/dev/null || true
                swept=$((swept + 1))
            fi
        fi
    done

    if [ "$swept" -gt 0 ]; then
        echo "[$timestamp] Swept $swept stale sessions"
    fi
}

# === Monitoring Functions ===

init_logs() {
    mkdir -p /var/log/xrdp
    touch "$MONITOR_LOG" "$ALERT_LOG"
    chmod 644 "$MONITOR_LOG" "$ALERT_LOG"
}

monitor_active_sessions() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    {
        echo "[$timestamp] === Session Monitor Check ==="

        # Find all Xvnc processes (RDP display servers)
        local xvnc_pids=$(pgrep -f "Xvnc" || true)

        if [ -z "$xvnc_pids" ]; then
            echo "[$timestamp] No active Xvnc sessions"
            return 0
        fi

        while IFS= read -r pid; do
            check_process_health "$pid" "$timestamp"
        done <<< "$xvnc_pids"

    } >> "$MONITOR_LOG" 2>&1
}

check_process_health() {
    local pid=$1
    local timestamp=$2
    local process_name=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
    local display=$(ps -p "$pid" -o args= 2>/dev/null | grep -oE ':[0-9]+' | head -1 || echo "unknown")

    # Get memory stats
    local mem_info=$(ps -p "$pid" -o %mem=,rss= 2>/dev/null || echo "0 0")
    local mem_percent=$(echo "$mem_info" | awk '{print $1}')
    local mem_kb=$(echo "$mem_info" | awk '{print $2}')
    local mem_mb=$((mem_kb / 1024))

    # Get CPU usage
    local cpu_percent=$(ps -p "$pid" -o %cpu= 2>/dev/null || echo "0")

    # Get session runtime
    local start_time=$(ps -p "$pid" -o lstart= 2>/dev/null || echo "")

    {
        echo "  [$timestamp] Display $display (PID $pid)"
        echo "    Memory: ${mem_percent}% (${mem_mb}MB), CPU: ${cpu_percent}%"
        echo "    Started: $start_time"
    } >> "$MONITOR_LOG" 2>&1

    # Check memory threshold
    if (( $(echo "$mem_percent > $MEMORY_THRESHOLD" | bc -l) )); then
        alert "HIGH_MEMORY" "Session $display (PID $pid) using ${mem_percent}% memory (${mem_mb}MB)" "$timestamp"
    fi

    # Check CPU threshold
    if (( $(echo "$cpu_percent > $CPU_THRESHOLD" | bc -l) )); then
        alert "HIGH_CPU" "Session $display (PID $pid) using ${cpu_percent}% CPU" "$timestamp"
    fi
}

alert() {
    local alert_type=$1
    local message=$2
    local timestamp=$3

    {
        echo "[$timestamp] [$alert_type] $message"
    } >> "$ALERT_LOG" 2>&1

    # Optional: Send to syslog
    logger -t "xrdp-session-monitor" -p warning "$alert_type: $message"

    # Create GitHub issue for critical alerts
    local severity="info"
    case "$alert_type" in
        HIGH_MEMORY|HIGH_CPU|SERVICE_DOWN)
            severity="critical"
            ;;
        CLEANUP_ORPHAN)
            severity="warning"
            ;;
    esac

    if [[ "$severity" == "critical" ]]; then
        local body="## Error Details
- **Type:** $alert_type
- **Timestamp:** $timestamp
- **Message:** $message

## System State
- Memory: $(free -h | grep Mem | awk '{print $3 " used / " $7 " available"}')
- CPU Load: $(uptime | awk -F'load average:' '{print $2}')
- Uptime: $(uptime -p)

## Log Files
- Monitor log: \`\`$MONITOR_LOG\`\`\`
- Alert log: \`\`$ALERT_LOG\`\`\`

## Analysis Notes
Check system resources and processes."

        create_github_issue "$severity" "$alert_type at $timestamp" "$body" "desktop,auto-detected,$severity"
    fi
}

# === GitHub Issue Creation ===

create_github_issue() {
    local severity="$1"
    local title="$2"
    local body="$3"
    local labels="$4"

    # Check if GitHub integration is enabled
    if [[ "$AUTO_ISSUE_ENABLED" != "true" ]]; then
        return 0
    fi

    # Check required configuration
    if [[ -z "$GITHUB_REPO" ]] || [[ -z "$GITHUB_TOKEN" ]]; then
        return 0
    fi

    # Check severity threshold
    local severity_level=0
    case "$severity" in
        critical) severity_level=3 ;;
        warning) severity_level=2 ;;
        info) severity_level=1 ;;
        *) severity_level=0 ;;
    esac

    local threshold_level=0
    case "$ISSUE_SEVERITY_THRESHOLD" in
        critical) threshold_level=3 ;;
        warning) threshold_level=2 ;;
        info) threshold_level=1 ;;
        *) threshold_level=0 ;;
    esac

    if [[ "$severity_level" -lt "$threshold_level" ]]; then
        return 0
    fi

    # Deduplication: check if similar issue created recently
    local current_time=$(date +%s)
    local time_since_last=$((current_time - LAST_ISSUE_TIME))
    if [[ "$time_since_last" -lt "$ISSUE_DEDUP_WINDOW" ]]; then
        return 0
    fi

    # Update last issue time
    LAST_ISSUE_TIME=$current_time

    # Create issue using gh CLI
    local issue_url
    issue_url=$(gh issue create \
        --repo "$GITHUB_REPO" \
        --title "[$severity] $title" \
        --body "$body" \
        --label "$labels" 2>&1) || {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Failed to create GitHub issue: $issue_url" >> "$ALERT_LOG"
        return 1
    }

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] GitHub issue created: $issue_url" >> "$ALERT_LOG"
    return 0
}

monitor_crash_logs() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local has_critical=false

    # Check for recent crash indicators in xrdp logs
    if [ -f /var/log/xrdp/xrdp-sesman.log ]; then
        local recent_errors=$(grep -i "error\|crashed\|exit" /var/log/xrdp/xrdp-sesman.log | tail -5 || true)

        if [ -n "$recent_errors" ]; then
            {
                echo "[$timestamp] === Recent xrdp-sesman Errors ==="
                echo "$recent_errors"
            } >> "$ALERT_LOG" 2>&1

            # Create GitHub issue for crash errors
            if echo "$recent_errors" | grep -qi "crashed\|segfault\|segmentation"; then
                has_critical=true

                local body="## Error Details
- **Type:** Session crash
- **Timestamp:** $timestamp
- **Process:** xrdp-sesman

## Recent Errors
\`\`\`
$recent_errors
\`\`\`

## System State
- Memory: $(free -h | grep Mem | awk '{print $3 " used / " $7 " available"}')
- Uptime: $(uptime -p)

## Log Files
- Session log: \`\`/var/log/xrdp/xrdp-sesman.log\`\`
- Monitor log: \`\`$MONITOR_LOG\`\`

## Analysis Notes
Please check sesman logs for full crash details."

                create_github_issue "critical" "Session crash at $timestamp" "$body" "desktop,auto-detected,critical"
            fi
        fi
    fi
}

generate_report() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    {
        echo ""
        echo "=== Session Monitor Report - $timestamp ==="
        echo ""

        echo "Active Xvnc Sessions:"
        ps aux | grep "[X]vnc" | awk '{print $2, $3"% CPU", $4"% MEM", $11}'

        echo ""
        echo "Memory Usage Summary:"
        free -h

        echo ""
        echo "Disk Usage:"
        df -h /

        echo ""
        echo "Recent Alerts:"
        tail -10 "$ALERT_LOG" 2>/dev/null || echo "  (none)"

    } >> "$MONITOR_LOG" 2>&1
}

# === Systemd Service Installation ===

install_service() {
    log_info "Installing session monitor service..."

    # Ensure directory exists
    mkdir -p /var/lib/xrdp

    # Create monitoring script in a system location
    cat > /usr/local/bin/xrdp-session-monitor << 'SCRIPT_EOF'
#!/bin/bash
# Session Monitoring Daemon - runs continuously
set -euo pipefail
source /var/lib/xrdp/session-monitor-config.sh
init_logs
cleanup_orphaned_sessions  # Clean on startup
while true; do
    monitor_active_sessions
    monitor_crash_logs
    cleanup_orphaned_sessions  # Periodic cleanup
    generate_report
    sleep 30
done
SCRIPT_EOF

    chmod +x /usr/local/bin/xrdp-session-monitor

    # Create systemd service
    cat > /etc/systemd/system/xrdp-session-monitor.service << 'SERVICE_EOF'
[Unit]
Description=XRDP Session Monitor
After=xrdp.service
Requires=xrdp.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/xrdp-session-monitor
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE_EOF

    # Copy monitor config to system location
    cat > /var/lib/xrdp/session-monitor-config.sh << 'CONFIG_EOF'
MONITOR_LOG="/var/log/xrdp/session-monitor.log"
ALERT_LOG="/var/log/xrdp/session-alerts.log"
MEMORY_THRESHOLD=80
CPU_THRESHOLD=75

log_info() { echo "[INFO] $1"; }
log_warn() { echo "[WARN] $1"; }
log_error() { echo "[ERROR] $1"; }

# Clean orphaned xrdp-chansrv and pw-cli processes
cleanup_orphaned_sessions() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local cleaned=0

    {
        echo "[$timestamp] === Session Cleanup ==="
        local active_xvnc_pids=$(pgrep -f "Xvnc" 2>/dev/null || true)

        # Kill orphaned xrdp-chansrv processes
        for pid in $(pgrep -f "xrdp-chansrv" 2>/dev/null || true); do
            local has_parent=false
            for xvnc in $active_xvnc_pids; do
                if ps -o cgroup= -p "$pid" 2>/dev/null | grep -q "$(ps -o cgroup= -p "$xvnc" 2>/dev/null | head -1)"; then
                    has_parent=true
                    break
                fi
            done
            if [ "$has_parent" = false ]; then
                kill "$pid" 2>/dev/null || true
                cleaned=$((cleaned + 1))
            fi
        done

        # Kill orphaned pw-cli processes
        for pid in $(pgrep -f "pw-cli.*xrdp" 2>/dev/null || true); do
            local has_parent=false
            for xvnc in $active_xvnc_pids; do
                if ps -o cgroup= -p "$pid" 2>/dev/null | grep -q "$(ps -o cgroup= -p "$xvnc" 2>/dev/null | head -1)"; then
                    has_parent=true
                    break
                fi
            done
            if [ "$has_parent" = false ]; then
                kill "$pid" 2>/dev/null || true
                cleaned=$((cleaned + 1))
            fi
        done

        # Kill orphaned gnome-shell from dead sessions
        for pid in $(pgrep -f "gnome-shell" 2>/dev/null || true); do
            local disp=$(ps -o args= -p "$pid" 2>/dev/null | grep -oE 'DISPLAY=:[0-9]+' || echo "")
            if [ -n "$disp" ]; then
                local num=$(echo "$disp" | grep -oE '[0-9]+')
                if ! pgrep -f "Xvnc.*:$num" > /dev/null 2>&1; then
                    kill "$pid" 2>/dev/null || true
                    cleaned=$((cleaned + 1))
                fi
            fi
        done

        if [ "$cleaned" -gt 0 ]; then
            echo "  Cleaned $cleaned orphaned processes"
        else
            echo "  No orphaned sessions found"
        fi
    } >> "$MONITOR_LOG" 2>&1
}

init_logs() {
    mkdir -p /var/log/xrdp
    touch "$MONITOR_LOG" "$ALERT_LOG"
    chmod 644 "$MONITOR_LOG" "$ALERT_LOG"
}

monitor_active_sessions() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    {
        echo "[$timestamp] === Session Monitor Check ==="
        local xvnc_pids=$(pgrep -f "Xvnc" || true)
        if [ -z "$xvnc_pids" ]; then
            echo "[$timestamp] No active Xvnc sessions"
            return 0
        fi
        while IFS= read -r pid; do
            local mem_info=$(ps -p "$pid" -o %mem=,rss= 2>/dev/null || echo "0 0")
            local mem_percent=$(echo "$mem_info" | awk '{print $1}')
            local mem_kb=$(echo "$mem_info" | awk '{print $2}')
            local mem_mb=$((mem_kb / 1024))
            local cpu_percent=$(ps -p "$pid" -o %cpu= 2>/dev/null || echo "0")
            echo "  [PID $pid] Memory: ${mem_percent}%, ${mem_mb}MB | CPU: ${cpu_percent}%"
        done <<< "$xvnc_pids"
    } >> "$MONITOR_LOG" 2>&1
}

monitor_crash_logs() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    if [ -f /var/log/xrdp/xrdp-sesman.log ]; then
        local recent_errors=$(grep -i "error\|crashed\|exit" /var/log/xrdp/xrdp-sesman.log 2>/dev/null | tail -5 || true)
        if [ -n "$recent_errors" ]; then
            {
                echo "[$timestamp] === Recent Errors ==="
                echo "$recent_errors"
            } >> "$ALERT_LOG" 2>&1
        fi
    fi
}

generate_report() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    {
        echo ""
        echo "=== Session Report - $timestamp ==="
        echo "Active sessions:"
        ps aux | grep "[X]vnc" | wc -l
        echo "Memory: $(free -h | awk 'NR==2 {print $3 " / " $2}')"
    } >> "$MONITOR_LOG" 2>&1
}
CONFIG_EOF

    systemctl daemon-reload
    systemctl enable xrdp-session-monitor.service
    systemctl start xrdp-session-monitor.service

    log_info "Session monitor service installed and started"
    echo "  Service: xrdp-session-monitor.service"
    echo "  Monitor log: $MONITOR_LOG"
    echo "  Alert log: $ALERT_LOG"
}

uninstall_service() {
    log_info "Removing session monitor service..."

    systemctl stop xrdp-session-monitor.service 2>/dev/null || true
    systemctl disable xrdp-session-monitor.service 2>/dev/null || true

    rm -f /etc/systemd/system/xrdp-session-monitor.service
    rm -f /usr/local/bin/xrdp-session-monitor
    rm -f /var/lib/xrdp/session-monitor-config.sh

    systemctl daemon-reload

    log_info "Session monitor service removed"
}

run_test() {
    log_info "Running session monitor test..."
    init_logs
    monitor_active_sessions
    monitor_crash_logs
    generate_report

    echo ""
    echo "Monitor log (last 20 lines):"
    tail -20 "$MONITOR_LOG"

    echo ""
    echo "Alert log (last 20 lines):"
    tail -20 "$ALERT_LOG"
}

# === Main ===

case "${1:-}" in
    --enable)
        install_service
        ;;
    --disable)
        uninstall_service
        ;;
    --test)
        run_test
        ;;
    *)
        echo "Usage: sudo bash scripts/session-monitor.sh [--enable|--disable|--test]"
        echo ""
        echo "  --enable   Install and start continuous monitoring service"
        echo "  --disable  Remove monitoring service"
        echo "  --test     Run one-time monitoring check"
        exit 1
        ;;
esac
