# Remote Linux Desktop Deployment

A complete automation script for deploying a full Linux desktop environment on a remote Ubuntu server. Designed for persistent, always-on remote development using RDP access from Windows or Android tablets.

## Purpose

This project addresses the need for a **constantly-on remote development environment** that:

- **Reduces local resource usage** - Offloads coding, compilation, and AI assistance to a remote server
- **Provides tablet access** - Full desktop experience from Android tablets via Microsoft Remote Desktop
- **Stays always-on** - No need to keep your local machine running for development tasks
- **Integrates AI tools** - Pre-configured with Claude Code and OpenRouter for AI-assisted development

## Why This Stack?

| Component | Rationale |
|-----------|-----------|
| **GNOME Desktop** | Best tablet experience - touch-friendly, on-screen keyboard support, modern gestures |
| **RDP (xrdp)** | Works natively with Microsoft Remote Desktop on Windows and Android - better compression than VNC |
| **VS Code** | Industry-standard code editor with extensive extension ecosystem |
| **Claude Code** | AI assistant that integrates into the terminal workflow |
| **OpenRouter** | Unified API providing access to multiple AI models (minimax2.5 default) |
| **Chromium** | Full-featured browser for documentation and testing |

## Prerequisites

Before you can deploy, you need:

1. **An Ubuntu server (18.04 LTS or newer)** - Either a fresh cloud instance or existing server
   - Common providers: AWS EC2, DigitalOcean, Linode, Azure, Google Cloud
   - Recommended: 2+ CPU cores, 4+ GB RAM (smaller works but slower)

2. **Your server's IP address or hostname**
   - Example: `203.0.113.42` or `myserver.example.com`
   - If using a cloud provider, find this in your dashboard

3. **Your Ubuntu username and password**
   - Usually `ubuntu` (cloud instances) or your custom account name
   - You need password/SSH key access to connect

4. **SSH access working from your local machine**
   - On Windows: Use PowerShell or WSL
   - On Mac/Linux: Use terminal
   - Quick test: `ssh user@your-server-ip` (it should prompt for password or connect)

### Find Your Server Details

**From your cloud provider dashboard:**
- Log in to AWS/DigitalOcean/Linode/etc.
- Find your instance → look for **Public IP** or **IPv4 Address**
- This is your `your-server-ip`

**To find your username:**
- Cloud instances typically use `ubuntu` as default user
- Custom VMs might use a different name (check provider docs)

**Test your connection:**
```bash
# Replace 203.0.113.42 with your actual server IP
ssh ubuntu@203.0.113.42
# When prompted: type your password and press Enter
# If it works, you'll see a command prompt. Type 'exit' to disconnect.
```

If this fails, your SSH isn't set up yet (see Troubleshooting section).

## Quick Install

Now that you can connect to your server:

```bash
# Step 1: Download this script to your local machine
# (Run this on YOUR computer, not on the server)
git clone https://github.com/yourusername/desktop-seed.git
cd desktop-seed

# Step 2: Upload the script to your server
# Replace 203.0.113.42 with your server IP, ubuntu with your username
scp deploy-desktop.sh ubuntu@203.0.113.42:/tmp/

# Step 3: Connect to your server and run the installation
ssh ubuntu@203.0.113.42
sudo bash /tmp/deploy-desktop.sh

# Step 4: Wait for the script to complete (5-15 minutes depending on server speed)
# You'll see output as it installs components. When done, you'll see "Installation complete!"
```

**What each command does:**
- `git clone` - Downloads this project to your computer
- `scp` - Securely copies the script to your server (like file upload via SSH)
- `ssh` - Opens a remote terminal session on your server
- `sudo bash` - Runs the script with admin privileges (needed to install software)

## Post-Installation Setup

After the deployment script completes, you need to set up two things:

### 1. Get and Configure Your OpenRouter API Key

Claude Code uses OpenRouter to access AI models. You need an API key:

**Get your free API key:**
1. Go to https://openrouter.ai/
2. Click "Sign Up" (or "Log In" if you have an account)
3. Complete the sign-up process
4. Navigate to your account dashboard
5. Find "API Keys" section and click "Create New"
6. Copy the key (looks like `sk-or-v1-...something-long`)

**Add the key to your server:**
```bash
# While connected to your server (via SSH)
echo 'export OPENROUTER_API_KEY="sk-or-v1-YOUR_ACTUAL_KEY_HERE"' >> ~/.bashrc
source ~/.bashrc

# Verify it worked:
echo $OPENROUTER_API_KEY
# Should print your key, not empty
```

**What this does:**
- Saves your API key so Claude Code can access it every time you log in
- The script already configured Claude Code to look for this variable

### 2. Connect via Remote Desktop

Now your desktop is ready. Connect from your tablet or Windows PC:

**From Windows 10/11:**
1. Open "Remote Desktop Connection" (search in Start menu)
2. In "Computer:" box, type: `203.0.113.42:3389` (replace with YOUR server IP)
3. Click "Connect"
4. When prompted for credentials: use your Ubuntu username and password
5. Click "OK" and wait for the desktop to appear

**From Android tablet:**
1. Install "Microsoft Remote Desktop" from Google Play Store
2. Tap the "+" to add a connection
3. In "PC name" field: enter `203.0.113.42:3389` (replace with YOUR server IP)
4. Username: your Ubuntu username
5. Tap "Save"
6. Tap the connection to connect
7. When prompted: enter your Ubuntu password

**Troubleshooting connection:**
- Double-check you're using the right server IP (should match what you used for SSH)
- Wait 30-60 seconds after the script completes - RDP needs time to start
- If it says "connection refused" or "can't connect", check Troubleshooting section below

## Installed Components

| Component | Description |
|-----------|-------------|
| GNOME Desktop | Modern, tablet-friendly desktop environment |
| xrdp | Remote desktop protocol (RDP) server |
| VS Code | Full-featured code editor |
| Claude Code | AI assistant (configured for OpenRouter) |
| OpenRouter | API provider with minimax2.5 default model |
| Chromium | Web browser |

## Usage Tips

### Getting Started After Connecting

Once you're connected via RDP, you'll see the GNOME desktop with several applications available:
- **VS Code** - Click icon on desktop or find in Applications menu for coding
- **Chromium** - Click icon on desktop to open web browser
- **Terminal** - Right-click desktop → Open Terminal, or search in Applications

### Tablet Workflow (Best Practices)

If you're using an Android tablet:
- **Rotate to landscape** - This gives you more screen real estate for coding
- **Enable on-screen keyboard** - From the desktop, open Settings → Accessibility → Keyboard → On-Screen Keyboard (toggle ON)
- **Quick app access** - Three-finger swipe up shows all running apps
- **Switch workspaces** - Three-finger swipe left/right to move between workspaces (helpful for organizing windows)
- **Use tablet stand** - A stand makes landscape mode much more comfortable for coding

### Claude Code in Practice

Claude Code is pre-configured and ready to use after you set the OpenRouter API key. Here's how to use it:

**In a terminal window:**
```bash
# Check that Claude Code is installed
claude --version

# Start an interactive Claude session for asking questions
claude

# Example: Ask Claude to write code
claude < (cat << 'EOF'
Create a simple Python script that prints "Hello, World!"
EOF
)
```

**Common workflows:**
- **Quick code generation** - `claude "write a bash script that does X"`
- **Explain code** - `claude "explain what this function does" < myfile.py`
- **Debugging** - `claude "why am I getting this error?" < error.log`
- **Problem solving** - Just type `claude` and have a conversation

### Development Workflow

A typical day working with your remote desktop:

1. **Connect** - Use Remote Desktop on tablet/PC to log in (server stays running 24/7)
2. **Code** - Open VS Code, navigate to your projects, make changes
3. **AI Help** - Open a terminal and use `claude` for code review, generation, or debugging
4. **Test** - Run your code directly in the terminal or use VS Code's built-in terminal
5. **Research** - Use Chromium browser for documentation and references
6. **Disconnect** - Close Remote Desktop app. Everything stays running on the server
7. **Reconnect later** - Open Remote Desktop again - your files and projects are still there

**Key benefit:** The server keeps running even when you disconnect. Unlike your laptop, you don't need to keep anything powered on - just connect when you need it.

## Validation

Run the validation script to verify all components:

```bash
sudo bash tests/validate-install.sh
```

## Project Structure

```
.
├── deploy-desktop.sh         # Main deployment script
├── config.sh                 # Shared component configuration (declarative)
├── tests/
│   └── validate-install.sh  # Post-installation validation
├── scripts/
│   ├── update-desktop.sh    # System updates and package upgrades
│   ├── health-check.sh      # Health monitoring
│   ├── backup.sh            # Configuration backup/restore
│   ├── security.sh          # Firewall and fail2ban setup
│   ├── monitor.sh           # Log rotation and alerts
│   └── enhance-rdp.sh       # RDP enhancements (sound, clipboard)
├── docs/
│   ├── usage-guide.md       # Detailed usage documentation
│   └── ssh-setup_guide.md   # SSH setup guide for Windows
└── README.md                # This file
```

## How It Works

### Component-Based Design

Components are declared in `config.sh` with their verification method. Both the deployment script and validation script source this file:

- **Deploy**: Loops through components and installs each one
- **Test**: Loops through same components and verifies each one

This means adding new components to deploy requires only adding an entry to `config.sh` - the test automatically validates it.

### Verification

```bash
# Run deployment
sudo bash deploy-desktop.sh

# Validate (automatically checks all components)
sudo bash tests/validate-install.sh
```

## Why This Approach?

Most existing solutions for remote Linux desktops require complex infrastructure:

- **Ansible/Terraform** - Great for infrastructure, but overkill for personal desktop setup
- **Docker/containers** - Adds complexity without benefit for a desktop environment
- **NoMachine/Guacamole** - Browser-based alternatives, but different use cases

This project takes a simpler path:

| Aspect | This Project | Typical Alternatives |
|--------|--------------|---------------------|
| **Dependencies** | Just bash + standard Linux tools | Requires Ansible, Terraform, Docker |
| **Code size** | Single ~600 line script | Hundreds/thousands of lines across multiple files |
| **Auditability** | Read one file, understand everything | Must understand multiple tools and their configs |
| **Flexibility** | Edit one config file to add components | Learn new syntax for each tool |
| **Test scaling** | Automatic - test uses same config | Must write new test code for each component |

This isn't a limitation—it's the design philosophy. For personal or team use, the ability to quickly audit, modify, and understand your deployment script matters more than enterprise-grade complexity.

### Related Tools

These exist in related spaces but solve different problems:
- **Apache Guacamole** - Browser-based remote desktop (no client needed)
- **NoMachine** - Commercial remote desktop with more features
- **TurnKey Linux** - Pre-configured server images (no desktop focus)

## Security Considerations

- **Firewall:** The script opens port 3389 (RDP). Consider restricting to specific IPs.
- **API Keys:** Store your OpenRouter API key securely. The script writes it to `~/.config/claude/settings.json`.
- **Strong Passwords:** Use strong passwords for your Ubuntu user account.
- **Updates:** Keep the server updated with `sudo apt update && sudo apt upgrade`.

## Maintenance Scripts

This project includes maintenance scripts in the `scripts/` directory:

### Update System
```bash
# Update packages
sudo bash scripts/update-desktop.sh

# Full update (upgrades all packages)
sudo bash scripts/update-desktop.sh --full
```

### Health Check
```bash
# Check system health
bash scripts/health-check.sh

# Exit codes: 0=healthy, 1=warnings, 2=errors
```

### Backup & Restore
```bash
# Backup configuration
sudo bash scripts/backup.sh

# List backups
sudo bash scripts/backup.sh --list

# Restore from backup
sudo bash scripts/backup.sh --restore
```

### Security Hardening
```bash
# Install firewall and fail2ban
sudo bash scripts/security.sh

# Remove security tools
sudo bash scripts/security.sh --uninstall
```

### Monitoring
```bash
# Enable log rotation, disk alerts, service monitoring
sudo bash scripts/monitor.sh

# Disable monitoring
sudo bash scripts/monitor.sh --disable
```

### RDP Enhancements
```bash
# Add sound, clipboard support
sudo bash scripts/enhance-rdp.sh
```

## Troubleshooting

### SSH Connection Issues

**Error: "Permission denied (publickey,password)" or "Connection refused"**
- Verify you have the correct server IP: `ssh ubuntu@YOUR_SERVER_IP`
- Check that your username is correct (might be `ec2-user` on AWS, not `ubuntu`)
- If using key-based auth (not password), ensure your SSH key is loaded
- Wait a minute after launching a new cloud instance - SSH takes time to start

**Test SSH is working:**
```bash
# Run on your local machine (not the server)
ssh -v ubuntu@203.0.113.42
# Should show connection details and eventually prompt for password
```

### Script Installation Fails

**Error during `sudo bash /tmp/deploy-desktop.sh`**
1. The script should be idempotent - run it again, it will skip already-installed components
2. If it still fails, check that your Ubuntu version is 18.04 LTS or newer:
   ```bash
   lsb_release -a
   ```
3. For detailed error information:
   ```bash
   sudo bash -x /tmp/deploy-desktop.sh 2>&1 | tee install-log.txt
   # This creates install-log.txt with all details
   ```

### RDP Connection Fails

**Error: "Can't connect to remote desktop" or "Connection timeout"**
1. Verify the server IP is correct - use the same IP you used for SSH
2. Check RDP is running:
   ```bash
   # SSH to your server, then:
   sudo systemctl status xrdp
   # Should show "active (running)" in green
   ```
3. Check the firewall allows port 3389:
   ```bash
   # On the server:
   sudo ufw status
   # If it shows "active", check if 3389 is allowed:
   sudo ufw allow 3389
   ```
4. Try reconnecting after 1-2 minutes (RDP needs time to fully initialize)

**Error: "Login failed" or "Authentication error"**
- Use your Ubuntu username and password (the ones for SSH login)
- If you've never logged in via RDP before, wait 30 seconds and try again
- Try connecting again - sometimes the first attempt fails

### Claude Code Not Working

**Claude Code commands not found or errors:**
1. Verify it's installed:
   ```bash
   # SSH to your server, then:
   command -v claude
   # Should print a path, not empty
   ```
2. Verify OpenRouter API key is set:
   ```bash
   echo $OPENROUTER_API_KEY
   # Should print your key, not empty
   ```
3. If the key is missing, you skipped Post-Installation Setup Step 1 - do that now

### Check What's Installed

Run the validation script (post-deployment):
```bash
# SSH to your server, then:
sudo bash tests/validate-install.sh
# Shows status of all components
```

For more detailed troubleshooting, see [docs/usage-guide.md](docs/usage-guide.md)