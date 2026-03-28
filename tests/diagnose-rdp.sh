#!/bin/bash
# Diagnostic script for RDP/GNOME session issues
# Run this if you're experiencing blank blue screen or other RDP problems

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  RDP/GNOME Session Diagnostics${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# 1. Check xrdp service status
echo -e "${BLUE}[1/7] Checking xrdp service...${NC}"
if sudo systemctl is-active --quiet xrdp; then
    echo -e "${GREEN}✓ xrdp service is running${NC}"
else
    echo -e "${RED}✗ xrdp service is NOT running${NC}"
    echo "  Fix: sudo systemctl restart xrdp"
fi
echo ""

# 2. Check xrdp-sesman service status
echo -e "${BLUE}[2/7] Checking xrdp-sesman service...${NC}"
if sudo systemctl is-active --quiet xrdp-sesman; then
    echo -e "${GREEN}✓ xrdp-sesman service is running${NC}"
else
    echo -e "${RED}✗ xrdp-sesman service is NOT running${NC}"
    echo "  Fix: sudo systemctl restart xrdp-sesman"
fi
echo ""

# 3. Check startwm.sh exists and is executable
echo -e "${BLUE}[3/7] Checking startwm.sh configuration...${NC}"
if [[ -f /etc/xrdp/startwm.sh ]]; then
    if [[ -x /etc/xrdp/startwm.sh ]]; then
        echo -e "${GREEN}✓ startwm.sh exists and is executable${NC}"
        echo "  Content:"
        sudo head -5 /etc/xrdp/startwm.sh | sed 's/^/    /'
    else
        echo -e "${RED}✗ startwm.sh exists but is NOT executable${NC}"
        echo "  Fix: sudo chmod +x /etc/xrdp/startwm.sh"
    fi
else
    echo -e "${RED}✗ startwm.sh does NOT exist${NC}"
    echo "  Fix: See DEPLOYMENT-GUIDE.md for recreating it"
fi
echo ""

# 4. Check for dbus-launch
echo -e "${BLUE}[4/7] Checking dbus-launch availability...${NC}"
if command -v dbus-launch &> /dev/null; then
    echo -e "${GREEN}✓ dbus-launch is available${NC}"
else
    echo -e "${RED}✗ dbus-launch is NOT available${NC}"
    echo "  Fix: sudo apt-get install -y dbus"
fi
echo ""

# 5. Check for gnome-session
echo -e "${BLUE}[5/7] Checking gnome-session...${NC}"
if command -v gnome-session &> /dev/null; then
    echo -e "${GREEN}✓ gnome-session is available${NC}"
    gnome-session --version
else
    echo -e "${RED}✗ gnome-session is NOT available${NC}"
    echo "  Fix: sudo apt-get install -y gnome-session"
fi
echo ""

# 6. Check port 3389 is listening
echo -e "${BLUE}[6/7] Checking RDP port 3389...${NC}"
if sudo netstat -tuln 2>/dev/null | grep -q ":3389 " || sudo ss -tuln 2>/dev/null | grep -q ":3389 "; then
    echo -e "${GREEN}✓ Port 3389 is listening${NC}"
else
    echo -e "${YELLOW}⚠ Port 3389 is not listening${NC}"
    echo "  Check firewall: sudo ufw status"
    echo "  Allow RDP: sudo ufw allow 3389/tcp"
fi
echo ""

# 7. Show recent xrdp logs
echo -e "${BLUE}[7/7] Recent xrdp logs...${NC}"
if [[ -f /var/log/xrdp-sesman.log ]]; then
    echo "  Last 10 lines of /var/log/xrdp-sesman.log:"
    sudo tail -10 /var/log/xrdp-sesman.log | sed 's/^/    /'
else
    echo -e "${YELLOW}⚠ /var/log/xrdp-sesman.log not found${NC}"
fi
echo ""

# Summary
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  Diagnosis Complete${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo -e "If you see ${RED}✗${NC} marks above:"
echo "1. Run the suggested fixes"
echo "2. Run this diagnostic again"
echo "3. Try RDP connection again"
echo ""
echo "If still having issues:"
echo "1. Check AWS security group allows port 3389"
echo "2. Review DEPLOYMENT-GUIDE.md troubleshooting section"
echo "3. Check xrdp logs: sudo tail -50 /var/log/xrdp.log"
echo ""
