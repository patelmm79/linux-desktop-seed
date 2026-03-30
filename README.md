# Remote Linux Desktop Deployment

Automated setup for a full Linux desktop environment on a remote Ubuntu server — accessible from anywhere via Remote Desktop (RDP). Designed for developers who want a cloud-based workstation pre-loaded with VS Code, AI tools, and a browser, without doing manual installation steps.

**Status:** Production-ready. Tested on Ubuntu 20.04, 22.04, and 24.04.

---

## What Problem Does This Solve?

Running a development environment on a cloud server (like an AWS EC2 instance) normally gives you only a terminal. This script turns that server into a **full graphical desktop** you can connect to from any Windows PC or Android tablet — just like using a remote computer. It also handles the painful parts automatically:

- Setting up the graphical desktop and RDP server (normally 30+ manual steps)
- Preventing and detecting session crashes (used to take 3+ hours to notice; now < 30 seconds)
- Storing credentials securely so VS Code doesn't throw keyring errors
- Pre-installing all development tools so you can start working immediately

---

## What Gets Installed

| Tool | What It Is | Why It's Here |
|------|-----------|---------------|
| **GNOME Desktop** | The graphical user interface (GUI) | Gives you a full desktop with windows, taskbar, and apps |
| **xrdp** | Remote Desktop Protocol server | Lets you connect to the desktop from Windows or Android |
| **VS Code** | Code editor | Full-featured editor with extensions, debugger, terminal |
| **Claude Code** | AI coding assistant (terminal-based) | AI pair programmer — run `claude` in any terminal |
| **OpenRouter CLI** | Access to AI models via API | Lets Claude Code use models like GPT-4, Gemini, etc. |
| **Chromium** | Open-source web browser | Full browser available inside the remote desktop |
| **GitHub CLI** | GitHub from the command line | Push/pull repos, manage PRs without browser auth |
| **GNOME Keyring** | Secure credential/password storage | Prevents "OS keyring not available" errors in VS Code |
| **Cascade Windows** | Window arrangement extension | Tiles and organizes windows on the desktop |
| **Session Monitor** | Background crash detection service | Alerts within 30 seconds if the desktop session crashes |

---

## Prerequisites

Before you start, you need:

1. **An Ubuntu server** — a cloud VM (AWS EC2, DigitalOcean, etc.) running Ubuntu 20.04 or newer
   - Minimum: 2 CPU cores, 4 GB RAM, 30 GB storage
   - Recommended: 4 CPU cores, 8 GB RAM for comfortable use
2. **SSH access** to that server (username + password or SSH key)
3. **Your server's public IP address**
4. **An OpenRouter API key** — get one free at [openrouter.ai](https://openrouter.ai/) (needed for Claude Code)
5. **Port 3389 open** in your server's firewall/security group (for RDP connections)

> **AWS-specific:** In your EC2 instance's Security Group, add an inbound rule: Type = RDP, Port = 3389, Source = your IP address.

---

## Quick Start

### Step 1 — Upload the scripts to your server

Run this from your local machine (replace `ubuntu` and `YOUR_SERVER_IP`):

```bash
git clone https://github.com/patelmm79/desktop-seed.git
cd desktop-seed

scp deploy-desktop.sh ubuntu@YOUR_SERVER_IP:/tmp/
scp config.sh ubuntu@YOUR_SERVER_IP:/tmp/
```

### Step 2 — SSH into your server and run the installer

```bash
ssh ubuntu@YOUR_SERVER_IP
sudo bash /tmp/deploy-desktop.sh
```

Installation takes **5–15 minutes** depending on your server's internet speed. You'll see progress messages as each component is installed.

### Step 3 — Connect via Remote Desktop

Once installation completes, open **Microsoft Remote Desktop** on Windows (it's pre-installed) or install it on Android:

1. Add a new connection
2. Server address: `YOUR_SERVER_IP` (port 3389 is used automatically)
3. Username and password: your Ubuntu account credentials
4. Connect — the GNOME desktop should appear

### Step 4 — Configure your API key

Inside the remote desktop, open a terminal and run:

```bash
echo 'export OPENROUTER_API_KEY="your_api_key_here"' >> ~/.bashrc
source ~/.bashrc
```

Then test Claude Code:

```bash
claude --version
claude   # starts an interactive session
```

---

## Connecting from Different Devices

### Windows
- Use **Remote Desktop Connection** (search in Start menu) or **Microsoft Remote Desktop** from the Microsoft Store
- Address: `YOUR_SERVER_IP:3389`
- Login with your Ubuntu username and password

### Android Tablet
- Install **Microsoft Remote Desktop** from the Google Play Store
- Tap **+** to add a PC, enter your server IP
- GNOME is touch-friendly — landscape mode works best
- Enable the on-screen keyboard: Settings > Accessibility > Keyboard > On-Screen Keyboard

---

## Using the Installed Tools

### VS Code
```bash
code .          # open current folder in VS Code
code myfile.py  # open a specific file
```
Or click the VS Code icon on the desktop.

### Claude Code (AI assistant)
```bash
claude          # start an interactive AI session in the terminal
claude "explain this error: ..."  # one-shot question
```
Claude Code reads your codebase and helps you write, debug, and understand code.

### GitHub CLI
```bash
gh auth login   # authenticate with GitHub (first time only)
gh repo clone owner/repo-name
gh pr list
```

### Chromium Browser
Type `chromium-browser` in the terminal, or find it in Applications > Internet.

---

## How Crash Detection Works

One of the key improvements in this project is fast crash detection. Here's the problem it solves:

**Before:** If your GNOME session crashed while you were away, you'd come back hours later to a broken desktop, with no logs about what happened or when.

**After:** A background service (`xrdp-session-monitor.service`) checks the session every 30 seconds. If a crash is detected, it:
1. Captures memory usage, CPU load, and running processes at the time of crash
2. Writes forensic data to `/var/log/xrdp/session-monitor.log`
3. Writes an alert to `/var/log/xrdp/session-alerts.log`

You can check the health of the system at any time:

```bash
# Quick one-line health summary
bash scripts/analyze-session-logs.sh --summary

# View recent crashes with context
bash scripts/analyze-session-logs.sh --crashes

# Memory usage over time
bash scripts/analyze-session-logs.sh --memory

# Full session history timeline
bash scripts/analyze-session-logs.sh --timeline

# Live monitor log
tail -f /var/log/xrdp/session-monitor.log
```

---

## How Credential Storage Works

VS Code and other apps use the operating system's keyring (a secure password vault) to store things like GitHub tokens and API keys. On a plain Ubuntu server with no desktop, this keyring doesn't exist — so you'd see errors like "OS keyring is not available for encryption."

This project fixes that by starting `gnome-keyring-daemon` at the right point in the session startup sequence (inside the D-Bus session, before GNOME loads). All apps that start afterwards automatically inherit access to the keyring.

To use it manually:

```bash
# Store a secret
secret-tool store --label="My API Key" service myapp account myuser

# Retrieve it
secret-tool lookup service myapp account myuser
```

---

## Monitoring & Troubleshooting

### Check that everything is running after deployment

```bash
sudo bash tests/validate-install.sh
```

This checks that all services are running, all tools are installed, and configuration is correct.

### Services

```bash
# Check xrdp (the RDP server)
systemctl status xrdp
systemctl status xrdp-sesman

# Check the crash monitor
systemctl status xrdp-session-monitor.service

# Restart them if needed
sudo systemctl restart xrdp
sudo systemctl restart xrdp-session-monitor.service
```

### Can't connect via RDP

```bash
# Is xrdp running?
systemctl status xrdp

# Is port 3389 listening?
sudo ss -tuln | grep 3389

# Is the firewall blocking it?
sudo ufw status
sudo ufw allow 3389   # open the port if needed

# View the connection log
tail -50 /var/log/xrdp-sesman.log
```

### Blank blue screen on connect

The most common fix:

```bash
sudo systemctl restart xrdp xrdp-sesman
```

If that doesn't work, check the session log:

```bash
tail -50 /var/log/xrdp-sesman.log
cat ~/.xsession-errors
```

### Keyring errors in VS Code

```bash
# Is the keyring daemon running?
pgrep -af gnome-keyring-daemon

# Is D-Bus initialized?
echo $DBUS_SESSION_BUS_ADDRESS

# If empty, the session didn't start correctly — reconnect via RDP
```

### Claude Code not working

```bash
# Check API key is set
echo $OPENROUTER_API_KEY

# Check Claude is installed
claude --version

# If key is missing, set it
echo 'export OPENROUTER_API_KEY="your_key_here"' >> ~/.bashrc
source ~/.bashrc
```

### High memory usage

```bash
# See what's using the most memory
ps aux --sort=-%mem | head -10

# View memory trends from the monitor
bash scripts/analyze-session-logs.sh --memory
```

---

## Architecture Overview

### Session Startup Sequence

When you connect via RDP, here's what happens in order:

```
You connect → Microsoft Remote Desktop → your server's IP:3389
                                             ↓
                                    xrdp receives the connection
                                             ↓
                               xrdp-sesman launches startwm.sh
                                             ↓
                         startwm.sh sets environment variables
                         (memory limits, display settings, etc.)
                                             ↓
                              dbus-launch starts a D-Bus session
                         (D-Bus is the inter-process message bus
                          that desktop apps use to talk to each other)
                                             ↓
                        gnome-keyring-daemon starts inside D-Bus
                         (this is why credential storage works)
                                             ↓
                           gnome-session starts the full desktop
                          (VS Code, Chromium, etc. run from here)
                                             ↓
                  xrdp-session-monitor watches in the background
                         (alerts you if anything crashes)
```

### Script Structure

```
deploy-desktop.sh       ← Run this to deploy everything (~1200 lines)
config.sh               ← Component list (used by deploy + tests)
tests/
  validate-install.sh   ← Run after deploy to verify everything works
scripts/
  session-monitor.sh    ← Installs the crash monitoring service
  analyze-session-logs.sh ← Tools to analyze crash/health logs
etc/xrdp/
  startwm.sh            ← Session startup script (keyring + env setup)
docs/                   ← Detailed guides (see below)
```

Each install function in `deploy-desktop.sh` is **idempotent** — meaning you can run the script multiple times safely. It checks whether a component is already installed and skips it if so.

---

## Configuration

### Adjust memory limits per process

Edit `/etc/xrdp/startwm.sh`, find the `ulimit` line and change the value (in KB):

```bash
ulimit -v 2097152  # 2097152 KB = ~2 GB per process
```

### Adjust monitoring thresholds

Edit `/var/lib/xrdp/session-monitor-config.sh`:

```bash
MEMORY_THRESHOLD=80   # send alert when system memory reaches 80%
CPU_THRESHOLD=75      # send alert when CPU reaches 75%
```

---

## Log File Locations

| Log File | What It Contains |
|----------|-----------------|
| `/tmp/deploy-desktop-*.log` | Output from the deployment script |
| `/var/log/xrdp-sesman.log` | xrdp session connection and error log |
| `/var/log/xrdp/session-monitor.log` | Continuous health check results |
| `/var/log/xrdp/session-alerts.log` | Threshold alerts (memory, CPU, crashes) |
| `~/.xsession-errors` | GNOME session errors for the current user |

---

## Performance Expectations

| Metric | Typical Value |
|--------|--------------|
| Idle memory usage | 2–3 GB |
| Monitor CPU overhead | < 1% |
| Disk usage after install | 25–30 GB |
| RDP network bandwidth | ~100 KB/s |
| Deployment time | 5–15 minutes |
| Crash detection time | < 30 seconds |

---

## Documentation

| Guide | Who It's For | What It Covers |
|-------|-------------|----------------|
| [Quick Deploy](docs/QUICK-DEPLOY.md) | Everyone | Condensed deployment steps |
| [Usage Guide](docs/usage-guide.md) | End users | Using VS Code, Claude Code, GitHub CLI |
| [SSH Setup](docs/ssh-setup-guide.md) | Windows users | Setting up SSH key authentication |
| [Crash Recovery](docs/crash-recovery-guide.md) | Operators | Understanding and responding to crashes |
| [Keyring Guide](docs/keyring-guide.md) | Developers | Storing and retrieving credentials |
| [Monitoring Reference](docs/README_MONITORING.md) | Operators | Full monitoring configuration |
| [Deployment Summary](docs/DEPLOYMENT_SUMMARY.md) | Architects | What gets installed and where |
| [Integration Guide](docs/INTEGRATION_GUIDE.md) | Developers | How components interact |

---

## Contributing

The main script (`deploy-desktop.sh`) follows these conventions:

- All install functions check before installing (idempotency)
- `set -euo pipefail` at the top — any unhandled error stops the script
- Variables always quoted: `"$var"` not `$var`
- `[[ ]]` for conditionals, not `[ ]`
- 4-space indentation

When fixing issues found on a real VM, update the repository scripts — not just the remote machine. This ensures future deployments automatically include the fix.

```bash
# Validate script syntax before committing
bash -n deploy-desktop.sh
```

---

## License

Provided as-is for deployment and development use.

**Last Updated:** March 30, 2026
