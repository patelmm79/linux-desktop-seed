# Quick Deployment Reference

## TL;DR - Just Deploy It

```bash
# Step 1: Copy script to AWS
scp deploy-desktop.sh ubuntu@YOUR_AWS_IP:/tmp/
scp config.sh ubuntu@YOUR_AWS_IP:/tmp/

# Step 2: Run deployment
ssh ubuntu@YOUR_AWS_IP
sudo bash /tmp/deploy-desktop.sh

# Step 3: Test RDP connection
# Open Remote Desktop, connect to YOUR_AWS_IP:3389
# Use your Ubuntu username/password
```

**That's it!** You should see the GNOME desktop.

---

## If You Get Blank Blue Screen

```bash
# SSH to the VM and run diagnostics
bash /tmp/diagnose-rdp.sh

# Most common fix: restart xrdp
sudo systemctl restart xrdp xrdp-sesman
```

---

## AWS Security Group Setup (Required)

1. AWS EC2 Console → Your Instance
2. Security tab → Security group name
3. **Edit Inbound Rules** → **Add Rule**
   - Type: **RDP**
   - Protocol: **TCP**
   - Port: **3389**
   - Source: **Your IP** (or 0.0.0.0/0)
4. **Save rules**

---

## What Gets Installed

- ✓ GNOME Desktop (tablet-friendly UI)
- ✓ xrdp (RDP server on port 3389)
- ✓ VS Code (code editor)
- ✓ Claude Code (AI assistant)
- ✓ OpenRouter CLI (AI models)
- ✓ Chromium (web browser)
- ✓ GitHub CLI (git management)

---

## Connection Details

**From Windows:**
- Application: Remote Desktop Connection
- Address: `YOUR_AWS_IP:3389`
- Username: Ubuntu username
- Password: Ubuntu password

**From Android Tablet:**
- App: Microsoft Remote Desktop (from Play Store)
- Server: `YOUR_AWS_IP:3389`
- Username: Ubuntu username
- Password: Ubuntu password

---

## Troubleshooting One-Liners

```bash
# Check xrdp is running
sudo systemctl status xrdp

# Restart xrdp
sudo systemctl restart xrdp xrdp-sesman

# Check port 3389 is listening
sudo ss -tuln | grep 3389

# View xrdp logs
sudo tail -50 /var/log/xrdp-sesman.log

# Test GNOME session
gnome-session --version

# Fix permissions on startwm.sh
sudo chmod +x /etc/xrdp/startwm.sh
```

---

## Documentation

- **Full Guide:** See `DEPLOYMENT-GUIDE.md`
- **What Was Fixed:** See `RDP-FIX-SUMMARY.md`
- **Usage After Setup:** See `docs/usage-guide.md`
- **Diagnostic Tool:** Run `bash tests/diagnose-rdp.sh`

---

## Key Changes Made

The deployment script was updated to properly initialize the GNOME session for RDP:

```bash
# OLD (broken):
exec /usr/bin/gnome-session

# NEW (fixed):
export GNOME_SHELL_SESSION_MODE=ubuntu
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=GNOME
exec dbus-launch --exit-with-session /usr/bin/gnome-session
```

This ensures D-Bus (the desktop's message bus) is properly initialized, fixing the blank blue screen issue.

---

**Still having issues?** Run: `bash /tmp/diagnose-rdp.sh`
