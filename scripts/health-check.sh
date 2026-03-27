#!/bin/bash
# Health Check - Monitor desktop status
# Usage: bash scripts/health-check.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[FAIL]${NC} $1"; }

ERRORS=0
WARNINGS=0

echo "========================================="
echo "  Desktop Health Check"
echo "========================================="
echo ""

# System info
echo -e "${BLUE}=== System Information ===${NC}"
echo "Hostname: $(hostname)"
echo "Uptime: $(uptime -p)"
echo "Load: $(cat /proc/loadavg | awk '{print $1, $2, $3}')"
echo ""

# Disk space
echo -e "${BLUE}=== Disk Space ===${NC}"
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
if [[ "$DISK_USAGE" -lt 80 ]]; then
    log_info "Root partition: ${DISK_USAGE}% used"
elif [[ "$DISK_USAGE" -lt 95 ]]; then
    log_warn "Root partition: ${DISK_USAGE}% used"
    ((WARNINGS++))
else
    log_error "Root partition: ${DISK_USAGE}% used - CRITICAL"
    ((ERRORS++))
fi
echo ""

# Memory
echo -e "${BLUE}=== Memory ===${NC}"
MEMORY_USED=$(free | awk '/Mem:/ {printf "%.0f", ($3/$2) * 100}')
if [[ "$MEMORY_USED" -lt 80 ]]; then
    log_info "Memory: ${MEMORY_USED}% used"
elif [[ "$MEMORY_USED" -lt 95 ]]; then
    log_warn "Memory: ${MEMORY_USED}% used"
    ((WARNINGS++))
else
    log_error "Memory: ${MEMORY_USED}% used - CRITICAL"
    ((ERRORS++))
fi
echo ""

# Services
echo -e "${BLUE}=== Services ===${NC}"

# xrdp
if systemctl is-active --quiet xrdp; then
    log_info "xrdp (RDP server)"
else
    log_error "xrdp is NOT running"
    ((ERRORS++))
fi

# ssh
if systemctl is-active --quiet ssh; then
    log_info "SSH"
else
    log_warn "SSH is NOT running"
    ((WARNINGS++))
fi

# gdm (display manager)
if systemctl is-active --quiet gdm3 || systemctl is-active --quiet gdm; then
    log_info "GNOME Display Manager"
else
    log_warn "GNOME Display Manager not running"
    ((WARNINGS++))
fi
echo ""

# RDP port
echo -e "${BLUE}=== Network Ports ===${NC}"
if ss -tuln 2>/dev/null | grep -q ":3389 "; then
    log_info "RDP port 3389 is listening"
else
    log_error "RDP port 3389 is NOT listening"
    ((ERRORS++))
fi

if ss -tuln 2>/dev/null | grep -q ":22 "; then
    log_info "SSH port 22 is listening"
else
    log_warn "SSH port 22 is NOT listening"
    ((WARNINGS++))
fi
echo ""

# Applications
echo -e "${BLUE}=== Applications ===${NC}"

# Claude Code
if command -v claude &> /dev/null; then
    CLAUDE_VERSION=$(claude --version 2>&1 | head -1 || echo "installed")
    log_info "Claude Code: $CLAUDE_VERSION"
else
    log_error "Claude Code is NOT installed"
    ((ERRORS++))
fi

# VS Code
if command -v code &> /dev/null; then
    log_info "VS Code"
else
    log_warn "VS Code not found"
    ((WARNINGS++))
fi

# Chromium
if command -v chromium &> /dev/null || command -v chromium-browser &> /dev/null; then
    log_info "Chromium"
else
    log_warn "Chromium not found"
    ((WARNINGS++))
fi
echo ""

# MCP Servers
echo -e "${BLUE}=== MCP Servers ===${NC}"
if [[ -f "$HOME/.config/desktop-seed/mcp-servers" ]]; then
    MCP_SERVERS=$(wc -l < "$HOME/.config/desktop-seed/mcp-servers")
    log_info "$MCP_SERVERS MCP server(s) configured"

    # Try to check their health
    if command -v claude &> /dev/null; then
        echo "Checking MCP server health..."
        claude mcp list 2>&1 | grep -v "^$" | head -5 || true
    fi
else
    log_info "No MCP servers configured"
fi
echo ""

# Recent errors
echo -e "${BLUE}=== Recent Errors (last 24h) ===${NC}"
RECENT_ERRORS=$(journalctl --since "24 hours ago" --priority=err --no-pager -q | wc -l)
if [[ "$RECENT_ERRORS" -eq 0 ]]; then
    log_info "No errors in last 24 hours"
else
    log_warn "$RECENT_ERRORS errors in last 24 hours"
    ((WARNINGS++))
fi
echo ""

# Recent deploy logs
echo -e "${BLUE}=== Recent Deploy Logs ===${NC}"
if ls /tmp/deploy-desktop-*.log &> /dev/null; then
    LATEST_LOG=$(ls -t /tmp/deploy-desktop-*.log | head -1)
    log_info "Latest: $LATEST_LOG"
    LAST_RUN=$(stat -c %y "$LATEST_LOG" | cut -d' ' -f1,2 | cut -d'.' -f1)
    log_info "Run at: $LAST_RUN"
else
    log_info "No deploy logs found"
fi
echo ""

# Summary
echo "========================================="
echo -e "Summary: ${GREEN}$ERRORS errors${NC}, ${YELLOW}$WARNINGS warnings${NC}"
echo "========================================="

if [[ "$ERRORS" -gt 0 ]]; then
    exit 2
elif [[ "$WARNINGS" -gt 0 ]]; then
    exit 1
else
    exit 0
fi
