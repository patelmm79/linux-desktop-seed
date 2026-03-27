#!/bin/bash
# Update Desktop - System maintenance and updates
# Usage: sudo bash scripts/update-desktop.sh [--full]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

source "$PROJECT_ROOT/config.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

FULL_UPDATE=false
if [[ "${1:-}" == "--full" ]]; then
    FULL_UPDATE=true
fi

echo "========================================="
echo "  Desktop System Update"
echo "========================================="
echo ""

# Update package lists
log_info "Updating package lists..."
apt-get update -qq

# Check for upgrades
UPGRADES=$(apt list --upgradable 2>/dev/null | grep -c upgradable || true)
if [[ "$UPGRADES" -gt 0 ]]; then
    log_info "Found $UPGRADES packages with updates"
else
    log_info "No packages to upgrade"
fi

# Upgrade packages if requested or if there are security updates
if [[ "$FULL_UPDATE" == "true" || "$UPGRADES" -gt 0 ]]; then
    log_info "Upgrading packages..."
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
    log_info "Packages upgraded"
else
    log_info "Skipping package upgrade (no --full flag)"
fi

# Upgrade Node.js global packages
if command -v npm &> /dev/null; then
    log_info "Updating npm global packages..."
    npm update -g --silent 2>/dev/null || log_warn "Some npm packages failed to update"

    # Update specific packages if installed
    if command -v claude &> /dev/null; then
        log_info "Updating Claude Code..."
        npm update -g @anthropic-ai/claude-code --silent 2>/dev/null || log_warn "Claude Code update failed"
    fi
fi

# Clean up
log_info "Cleaning up..."
apt-get autoremove -y -qq
apt-get autoclean -qq

log_info "Update complete!"
echo ""
echo "Run 'sudo bash tests/validate-install.sh' to verify everything is working"
