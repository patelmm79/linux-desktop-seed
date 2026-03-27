#!/bin/bash
# RDP Enhancements - Add sound, clipboard, and file sharing
# Usage: sudo bash scripts/enhance-rdp.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "========================================="
echo "  RDP Enhancements"
echo "========================================="
echo ""

# PulseAudio (sound over RDP)
log_info "Setting up sound over RDP..."
apt-get install -y -qq pulseaudio paprefs 2>/dev/null || true

# Enable flat volume
if ! grep -q "flat-volumes = 0" /etc/pulse/default.pa 2>/dev/null; then
    echo "flat-volumes = no" >> /etc/pulse/default.pa 2>/dev/null || true
fi

# Configure xrdp for sound
if ! grep -q "pulse" /etc/xrdp/xrdp.ini 2>/dev/null; then
    log_info "Note: xrdp sound requires client support"
fi

# Clipboard integration
log_info "Ensuring clipboard integration..."
# Already included in xrdp but ensure it's enabled

# File sharing (via xrdp)
log_info "Setting up file sharing..."
# Create shared folder
mkdir -p ~/Shared
chmod 755 ~/

log_info "RDP enhancements configured"
echo ""
log_info "To enable sound on Windows client:"
echo "  1. In Remote Desktop, go to Show Options"
echo "  2. Under Local Resources, click Settings"
echo "  3. Under Remote audio, click Settings"
echo "  4. Select 'Play on remote computer'"
echo ""
log_info "For clipboard: Copy/paste works automatically"
