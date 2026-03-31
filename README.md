# Remote Linux Desktop Deployment

Automated setup for a full Linux desktop environment on a remote Ubuntu server — accessible from anywhere via Remote Desktop (RDP). Designed for developers who want a cloud-based workstation pre-loaded with VS Code, AI tools, and a browser, without doing manual installation steps.

**Status:** Validated for personal/developer use. Tested on Ubuntu 20.04, 22.04, and 24.04.

---

## Table of Contents

- [What Problem Does This Solve?](#what-problem-does-this-solve)
- [Disclaimer](#disclaimer)
- [What Gets Installed](#what-gets-installed)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Quick Start](#quick-start)
  - [Connecting from Different Devices](#connecting-from-different-devices)
- [Using the Installed Tools](#using-the-installed-tools)
- [Reliability & Monitoring](#reliability--monitoring)
  - [How Crash Detection Works](#how-crash-detection-works)
  - [How Credential Storage Works](#how-credential-storage-works)
  - [Services & Log Files](#services--log-files)
- [Reference](#reference)
  - [Troubleshooting](#troubleshooting)
  - [Configuration](#configuration)
  - [Performance & Limitations](#performance--limitations)
  - [Documentation](#documentation)
- [Contributing & License](#contributing--license)

---

## What Problem Does This Solve?

Running a development environment on a cloud server (like an AWS EC2 instance or Hetzner VPS) normally gives you only a terminal. This script turns that server into a **full graphical desktop** you can connect to from any Windows PC or Android tablet — just like using a remote computer.

It also handles the painful parts automatically:

- Setting up the graphical desktop and RDP server (normally 30+ manual steps)
- Preventing and detecting session crashes (used to take 3+ hours to notice; now < 30 seconds)
- Storing credentials securely so VS Code doesn't throw keyring errors
- Pre-installing all development tools so you can start working immediately

---

## Disclaimer

**Use at your own risk.** This project was built by someone learning Linux as they went — not a Linux expert. It works for my specific use case, but your setup, server provider, or Ubuntu version may behave differently.

- No guarantees of stability, security, or fitness for any particular purpose
- Review the scripts before running them — they require root access and make significant system changes
- The [MIT license](LICENSE) applies: this software is provided "as is", without warranty of any kind

If you find something broken or risky, [open an issue](https://github.com/patelmm79/linux-desktop-seed/issues) — improvements are welcome.

---

## Tested On: Hetzner CPX32

This setup has been validated on a **[Hetzner CPX32](https://www.hetzner.com/cloud/)** cloud instance — a solid mid-range option for this workload:

| Spec | Value |
|------|-------|
| **CPU** | 4 vCPUs (AMD) |
| **RAM** | 8 GB |
| **Storage** | 160 GB SSD |
| **Price** | max. $12.59/month ($0.0202/hour) |
| **Location** | Choice of EU/US datacenters |

> **Tip:** Stop the server when not in use to avoid billing. Hetzner charges hourly, so stopping an idle server saves significant costs.

### Why This Hardware?

The use case driving this project: running **~6 simultaneous VS Code instances**, each with Claude Code active, while connecting to remote Discord instances via [OpenClaw](https://openclaw.app/) — all through a single RDP session.

**What this solves:**

- **Local laptop performance** — Running 6 VS Code windows with AI assistants was grinding the local machine to a halt. Offloading to a cloud server with dedicated RAM and CPU eliminates the bottleneck entirely.
- **Always-on availability** — The laptop would frequently restart overnight (updates, lid-close sleep). The cloud server stays up 24/7, so work-in-progress is never interrupted.
- **Single coordination interface** — All VS Code instances, Claude Code sessions, and Discord connections run on one remote desktop, accessible from any device — useful for managing multiple coding workstreams on the go.

The CPX32 handles this load comfortably at idle (~3 GB RAM used), with headroom for heavier workloads. Check current pricing at [hetzner.com/cloud](https://www.hetzner.com/cloud/regular-performance).

---

## What Gets Installed

| Tool | What It Is | Why It's Here |
|------|-----------|---------------|
| [**GNOME Desktop**](https://www.gnome.org/) | The graphical user interface (GUI) | Gives you a full desktop with windows, taskbar, and apps |
| [**xrdp**](http://xrdp.org/) | Remote Desktop Protocol server | Lets you connect to the desktop from Windows or Android |
| [**VS Code**](https://code.visualstudio.com/) | Code editor | Full-featured editor with extensions, debugger, terminal |
| [**Claude Code**](https://claude.ai/code) | AI coding assistant (terminal-based) | AI pair programmer — run `claude` in any terminal |
| [**OpenRouter CLI**](https://openrouter.ai/) | Access to AI models via API | Lets Claude Code connect to AI models |
| [**Chromium**](https://www.chromium.org/chromium-projects/) | Open-source web browser | Full browser available inside the remote desktop |
| [**OpenCLAW**](https://openclaw.app/) | Remote Discord client | Connects to remote Discord instances from the desktop |
| [**GitHub CLI**](https://cli.github.com/) | GitHub from the command line | Push/pull repos, manage PRs without browser auth |
| [**GNOME Keyring**](https://wiki.gnome.org/Projects/GnomeKeyring) | Secure credential/password storage | Prevents "OS keyring not available" errors in VS Code |
| [**Cascade Windows**](https://extensions.gnome.org/extension/1267/cascade-windows/) | Window arrangement extension | Tiles and organizes windows on the desktop |
| **Session Monitor** | Background crash detection service | Alerts within 30 seconds if the desktop session crashes |

---

## Getting Started

### Prerequisites

Before you start, you need:

1. **An Ubuntu server** — a cloud VM running Ubuntu 20.04 or newer
   - Minimum: 2 CPU cores, 4 GB RAM, 30 GB storage
   - Recommended: **[Hetzner CPX32](https://www.hetzner.com/cloud/regular-performance)** — 4 vCPUs, 8 GB RAM, 160 GB SSD, max. $12.59/month. Comfortably runs 6+ VS Code instances with Claude Code.
2. **SSH access** to that server (a username and either a password or SSH key)
3. **Your server's public IP address**
4. **An OpenRouter API key** — get one free at [openrouter.ai](https://openrouter.ai/) (needed for Claude Code)
5. **Port 3389 open** in your server's firewall or security group (for RDP connections)

> **AWS users:** In your EC2 instance's Security Group, add an inbound rule: Type = RDP, Port = 3389, Source = your IP address.
>
> **Hetzner users:** In your server's Firewall rules, allow TCP port 3389 inbound.

### Security Note: Sudo Access

The deployment script requires `sudo` access and adds a **NOPASSWD** entry to `/etc/sudoers` for the deploying user. This is required because:
- xrdp runs as the user and needs to configure display settings
- The session monitor service needs to restart xrdp on crash
- GNOME keyring needs D-Bus session initialization

**To remove after deployment** (if desired):
```bash
sudo visudo
# Remove the line: username ALL=(ALL) NOPASSWD: ALL
```
Then reboot — the desktop will continue to work without sudo access.

### Quick Start

#### Step 1 — Download and upload the scripts

Run this from your local machine (replace `ubuntu` and `YOUR_SERVER_IP` with your values):

```bash
git clone https://github.com/patelmm79/linux-desktop-seed.git
cd desktop-seed

scp deploy-desktop.sh ubuntu@YOUR_SERVER_IP:/tmp/
scp config.sh ubuntu@YOUR_SERVER_IP:/tmp/
```

#### Step 2 — SSH into your server and run the installer

```bash
ssh ubuntu@YOUR_SERVER_IP
sudo bash /tmp/deploy-desktop.sh
```

Installation takes **5–15 minutes** depending on your server's internet speed. You'll see progress messages as each component is installed.

#### Step 3 — Connect via Remote Desktop

Once installation finishes, open **Remote Desktop Connection** on Windows (search for it in the Start menu) or install **Microsoft Remote Desktop** from the Google Play Store on Android:

1. Add a new connection
2. Server address: `YOUR_SERVER_IP` (port 3389 is used automatically)
3. Username and password: your Ubuntu account credentials
4. Connect — the GNOME desktop should appear

#### Step 4 — Set up your API key

Inside the remote desktop, open a terminal and run:

```bash
echo 'export OPENROUTER_API_KEY="your_api_key_here"' >> ~/.bashrc
source ~/.bashrc
```

Then test Claude Code works:

```bash
claude --version
claude   # starts an interactive AI session
```

### Connecting from Different Devices

#### Windows
- Use **Remote Desktop Connection** (search in the Start menu) or **Microsoft Remote Desktop** from the Microsoft Store
- Address: `YOUR_SERVER_IP:3389`
- Login with your Ubuntu username and password

#### Android Tablet
- Install **Microsoft Remote Desktop** from the Google Play Store
- Tap **+** to add a PC, enter your server IP
- GNOME is touch-friendly — landscape mode works best
- Enable the on-screen keyboard: Settings → Accessibility → Keyboard → On-Screen Keyboard

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

### OpenCLAW
```bash
openclaw   # connect to remote Discord instances
```

### Chromium Browser
Type `chromium-browser` in a terminal, or find it in Applications → Internet.

For more detail on using each tool, see [Usage Guide](docs/usage-guide.md).

---

## Reliability & Monitoring

### How Crash Detection Works

A background service (`xrdp-session-monitor.service`) checks the session every 30 seconds. If something goes wrong, it captures memory usage, CPU load, and running processes at the moment of the problem — so you have real data instead of guessing.

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
```

### How Credential Storage Works

VS Code and other apps use the operating system's keyring (a secure password vault) to store things like GitHub tokens and API keys. On a plain Ubuntu server, this keyring doesn't exist — so you'd see errors like "OS keyring is not available for encryption."

This project fixes that by starting `gnome-keyring-daemon` at the right point in the session startup sequence. All apps that start afterwards automatically get access to the keyring.

See [Keyring Guide](docs/keyring-guide.md) for more detail.

### Services & Log Files

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

| Log File | What It Contains |
|----------|-----------------|
| `/tmp/deploy-desktop-*.log` | Output from the deployment script |
| `/var/log/xrdp-sesman.log` | xrdp session connection and error log |
| `/var/log/xrdp/session-monitor.log` | Continuous health check results |
| `/var/log/xrdp/session-alerts.log` | Threshold alerts (memory, CPU, crashes) |
| `~/.xsession-errors` | GNOME session errors for the current user |

---

## Reference

### Troubleshooting

### Quick checks after deployment

```bash
sudo bash tests/validate-install.sh
```

This checks that all services are running, all tools are installed, and configuration is correct.

### Common problems

| Problem | First thing to try |
|---------|-------------------|
| Can't connect via RDP | `systemctl status xrdp` — is the service running? |
| Blank blue screen on connect | `sudo systemctl restart xrdp xrdp-sesman` |
| Keyring errors in VS Code | Reconnect via RDP (restarts the session properly) |
| Claude Code not working | `echo $OPENROUTER_API_KEY` — is the key set? |
| High memory usage | `bash scripts/analyze-session-logs.sh --memory` |

For detailed troubleshooting steps, see [Troubleshooting Guide](docs/TROUBLESHOOTING.md).

### Configuration

#### Adjust memory limits per process

Edit `/etc/xrdp/startwm.sh`, find the `ulimit` line:

```bash
ulimit -v 2097152  # 2097152 KB = approximately 2 GB per process
```

#### Adjust monitoring thresholds

Edit `/var/lib/xrdp/session-monitor-config.sh`:

```bash
MEMORY_THRESHOLD=80   # send alert when system memory reaches 80%
CPU_THRESHOLD=75      # send alert when CPU reaches 75%
```

### Performance & Limitations

| Metric | Typical Value |
|--------|--------------|
| Idle memory usage | 2–3 GB |
| Monitor CPU overhead | < 1% |
| Disk usage after install | 25–30 GB |
| RDP network bandwidth | ~100 KB/s |
| Deployment time | 5–15 minutes |
| Crash detection time | < 30 seconds |

**Known limitations:**

- **Wayland not supported** — this deployment uses Xvnc which only supports X11; GNOME is forced to X11 mode
- **Single-user only** — designed for one desktop user; multi-user support is not implemented
- **No sound via RDP** — audio forwarding over RDP is not configured
- **No printer sharing** — printer redirection is not set up

### Documentation

| Guide | Who It's For | What It Covers |
|-------|-------------|----------------|
| [Quick Deploy](docs/QUICK-DEPLOY.md) | Everyone | Condensed deployment steps on one page |
| [Usage Guide](docs/usage-guide.md) | Beginners | Using VS Code, Claude Code, GitHub CLI after setup |
| [SSH Setup](docs/ssh-setup-guide.md) | Windows beginners | Setting up SSH key authentication |
| [Troubleshooting](docs/TROUBLESHOOTING.md) | Everyone | Fixes for common problems, symptom-by-symptom |
| [Crash Recovery](docs/crash-recovery-guide.md) | Operators | Understanding crash detection and session monitoring |
| [Keyring Guide](docs/keyring-guide.md) | Developers | How credential storage works and how to use it |
| [Monitoring Reference](docs/README_MONITORING.md) | Operators | Full monitoring configuration and commands |
| [Technical Reference](docs/TECHNICAL-REFERENCE.md) | Developers | Architecture, component integration, known issues |

---

## Contributing & License

### Script Structure

```
deploy-desktop.sh          ← Run this to deploy everything (~1200 lines)
config.sh                  ← Component list (used by deploy + tests)
tests/
  validate-install.sh      ← Run after deploy to verify everything works
scripts/
  session-monitor.sh       ← Installs the crash monitoring service
  analyze-session-logs.sh  ← Tools to analyze crash and health logs
etc/xrdp/
  startwm.sh               ← Session startup script (keyring + env setup)
docs/                      ← Guides (see table above)
```

Each install function in `deploy-desktop.sh` is **idempotent** — you can run the script multiple times safely. It checks whether each component is already installed and skips it if so.

### Contributing

The main script (`deploy-desktop.sh`) follows these conventions:

- All install functions check before installing (idempotency)
- `set -euo pipefail` at the top — any unhandled error stops the script
- Variables always quoted: `"$var"` not `$var`
- `[[ ]]` for conditionals, not `[ ]`
- 4-space indentation

When fixing issues found on a real server, update the repository scripts — not just the remote machine. This ensures future deployments automatically include the fix.

### License

MIT — see [LICENSE](LICENSE) for the full text.
