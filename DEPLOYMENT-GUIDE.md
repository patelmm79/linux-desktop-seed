# Deployment Guide with Error Resolution

## Quick Deployment

### Step 1: Upload the script to your AWS VM

From your local machine:
```bash
scp deploy-desktop.sh ubuntu@your-aws-ip:/tmp/
scp config.sh ubuntu@your-aws-ip:/tmp/
```

Or if you have direct shell access to AWS:
```bash
cd /path/to/desktop-seed
cp deploy-desktop.sh /tmp/
cp config.sh /tmp/
```

### Step 2: Run the deployment script

```bash
sudo bash /tmp/deploy-desktop.sh
```

The script will:
- Detect Ubuntu version (20.04, 22.04, or 24.04)
- Update system packages
- Install GNOME Desktop environment
- Install and configure xrdp (RDP server on port 3389)
- Install VS Code, Claude Code, Chromium, GitHub CLI
- Create a non-root user for RDP access
- Configure OpenRouter CLI with minimax2.5 as default model
- Set up desktop shortcuts
- Create a summary of installed components

**Estimated time:** 20-40 minutes (depends on internet speed and AWS instance type)

### Step 3: Test the installation

```bash
sudo bash /tmp/tests/validate-install.sh
```

This validates all components were installed correctly.

## Troubleshooting Common Errors

### Error: "Failed to install GNOME Desktop packages"

**Cause:** Package manager issue or insufficient disk space
**Solution:**
```bash
# Free up disk space
sudo apt-get clean
sudo apt-get autoclean

# Try installing individually
sudo apt-get install -y gnome-shell gnome-session gdm3

# Re-run deployment
sudo bash /tmp/deploy-desktop.sh
```

### Error: "Failed to create startwm.sh"

**Cause:** Permission issue writing to /etc/xrdp/
**Solution:**
```bash
# Verify directory exists and is writable
sudo ls -la /etc/xrdp/

# Create file manually
sudo bash -c 'cat > /etc/xrdp/startwm.sh << "EOF"
#!/bin/bash
# xrdp GNOME session script

# Load user environment
if [ -r /etc/profile ]; then
    . /etc/profile
fi

# Set up proper environment for GNOME under xrdp
export GNOME_SHELL_SESSION_MODE=ubuntu
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=GNOME

# Start GNOME session with dbus-launch for proper session initialization
# dbus-launch ensures the message bus is running and properly configured
exec dbus-launch --exit-with-session /usr/bin/gnome-session
EOF'

# Make it executable
sudo chmod +x /etc/xrdp/startwm.sh

# Restart xrdp
sudo systemctl restart xrdp
```

### Error: "Failed to start xrdp service"

**Cause:** Port 3389 already in use or service configuration issue
**Solution:**
```bash
# Check if xrdp is already running
sudo systemctl status xrdp

# Check logs for specific error
sudo tail -50 /var/log/xrdp-sesman.log
sudo tail -50 /var/log/xrdp.log

# Try restarting
sudo systemctl stop xrdp xrdp-sesman
sudo systemctl start xrdp xrdp-sesman

# Verify it's running
sudo systemctl is-active xrdp
```

### Error: "Failed to install VS Code" or "Failed to install Claude Code"

**Cause:** Network issue or repository unavailable
**Solution:**
```bash
# Update package lists
sudo apt-get update

# Try installing manually
sudo apt-get install -y code

# For Claude Code, install npm first if needed
sudo apt-get install -y npm
sudo npm install -g claude

# Re-run deployment
sudo bash /tmp/deploy-desktop.sh
```

## Post-Deployment Configuration

### 1. Create a user for RDP access (if not done by script)

```bash
sudo adduser rdp_user
# Set a strong password when prompted
```

### 2. Configure OpenRouter API key

The deployment should have created the config file at `~/.config/claude/settings.json`. To set your API key:

```bash
# For the current user
export OPENROUTER_API_KEY="your_api_key_here"
echo 'export OPENROUTER_API_KEY="your_api_key_here"' >> ~/.bashrc

# Verify configuration
cat ~/.config/claude/settings.json
```

### 3. Configure GitHub CLI

```bash
gh auth login
# Follow the prompts to authenticate with GitHub
```

### 4. Test RDP connection

From your local Windows machine:
1. Open **Remote Desktop Connection**
2. Enter the AWS VM's public IP address
3. Click **Connect**
4. Enter your Ubuntu username and password
5. You should see the GNOME desktop with taskbar and applications

## Verifying xrdp GNOME Session

If you get a blank blue screen after RDP connects:

### SSH into the VM and check:

```bash
# Check if xrdp service is running
sudo systemctl status xrdp

# Check xrdp session manager logs
sudo tail -100 /var/log/xrdp-sesman.log

# Check xrdp server logs
sudo tail -100 /var/log/xrdp.log

# Verify startwm.sh is correct
cat /etc/xrdp/startwm.sh

# Test GNOME session manually
export DISPLAY=:10
export GNOME_SHELL_SESSION_MODE=ubuntu
dbus-launch --exit-with-session /usr/bin/gnome-session &
```

### Restart xrdp if needed:

```bash
sudo systemctl restart xrdp
sudo systemctl restart xrdp-sesman
```

## AWS Security Group Configuration

Make sure your AWS security group allows inbound traffic on port 3389:

1. Go to AWS EC2 Console
2. Select your instance
3. Click **Security** tab
4. Click the security group name
5. **Edit inbound rules**:
   - Add rule: Type = RDP, Protocol = TCP, Port = 3389
   - Source = Your IP address (or 0.0.0.0/0 if behind corporate firewall, less secure)
   - Save rules

## Performance Tips

### For slower networks:
- Reduce color depth in RDP client (16-bit instead of 32-bit)
- Enable compression in RDP client settings
- Use 1280x1024 resolution instead of full screen

### For better performance on AWS:
- Use an instance with at least 2 vCPU and 4 GB RAM (t3.medium or better)
- Use EBS SSD storage (not magnetic)
- Connect from a region close to your AWS VM

## Uninstallation

To remove the desktop environment if needed:

```bash
sudo apt-get remove --purge gnome-shell gdm3 xrdp -y
sudo apt-get autoremove -y
sudo apt-get autoclean
```

This will remove GNOME, GDM3, and xrdp while preserving other applications.
