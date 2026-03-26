#!/bin/bash
# Post-deployment validation script

echo "========================================="
echo "  Validating Remote Desktop Installation"
echo "========================================="
echo ""

errors=0

# Check GNOME
echo -n "Checking GNOME Desktop... "
if dpkg -l gnome-shell 2>/dev/null | grep -q "^ii"; then
    echo "✓ Installed"
else
    echo "✗ Not found"
    ((errors++))
fi

# Check xrdp
echo -n "Checking xrdp... "
if systemctl is-active --quiet xrdp; then
    echo "✓ Running"
else
    echo "✗ Not running"
    ((errors++))
fi

# Check VS Code
echo -n "Checking VS Code... "
if command -v code &> /dev/null; then
    echo "✓ Installed"
else
    echo "✗ Not found"
    ((errors++))
fi

# Check Claude Code
echo -n "Checking Claude Code... "
if command -v claude &> /dev/null; then
    echo "✓ Installed"
else
    echo "✗ Not found"
    ((errors++))
fi

# Check OpenRouter
echo -n "Checking OpenRouter CLI... "
if command -v openrouter &> /dev/null; then
    echo "✓ Installed"
else
    echo "✗ Not found"
    ((errors++))
fi

# Check Chromium
echo -n "Checking Chromium/Chrome... "
if command -v chromium &> /dev/null || command -v chromium-browser &> /dev/null || command -v google-chrome &> /dev/null || command -v google-chrome-stable &> /dev/null; then
    echo "✓ Installed"
else
    echo "✗ Not found"
    ((errors++))
fi

# Check RDP port
echo -n "Checking RDP port 3389... "
if ss -tuln 2>/dev/null | grep -q ":3389 " || netstat -tuln 2>/dev/null | grep -q ":3389 "; then
    echo "✓ Listening"
else
    echo "✗ Not listening"
    ((errors++))
fi

echo ""
echo "========================================="
if [[ $errors -eq 0 ]]; then
    echo "  ✓ All checks passed!"
else
    echo "  ✗ $errors check(s) failed"
fi
echo "========================================="

exit $errors