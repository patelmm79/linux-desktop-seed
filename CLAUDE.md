# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **remote Linux desktop deployment automation** project. The main deliverable is a single bash script (`deploy-desktop.sh`) that installs a complete desktop environment on a remote Ubuntu server for always-on development access via RDP.

## What This Project Does

The deployment script installs and configures:
- GNOME Desktop (tablet-friendly UI)
- xrdp (RDP server on port 3389)
- Visual Studio Code
- Claude Code (AI assistant)
- OpenRouter CLI (default model: minimax2.5)
- Chromium browser

## Common Commands

```bash
# Validate script syntax (run locally before deploying)
bash -n deploy-desktop.sh

# Run deployment script on remote server
sudo bash /tmp/deploy-desktop.sh

# Validate installation on remote server
sudo bash tests/validate-install.sh

# Monitor session health (on remote server)
tail -f /var/log/xrdp/session-monitor.log
tail -f /var/log/xrdp/session-alerts.log

# Analyze crashes and issues
sudo bash scripts/analyze-session-logs.sh --summary
sudo bash scripts/analyze-session-logs.sh --crashes
sudo bash scripts/analyze-session-logs.sh --memory
```

## Architecture

The deployment script is a **modular bash script** with ~600 lines organized into functions. Components are declared in `config.sh` for both deployment and validation.

### Key Functions

- **System functions**: `check_root()`, `detect_ubuntu_version()`, `update_system()`
- **Desktop functions**: `install_gnome()`, `install_xrdp()`
- **Application functions**: `install_vscode()`, `install_claude_code()`, `configure_claude_openrouter()`, `install_openrouter()`, `install_chromium()`, `install_ghcli()`
- **Final functions**: `setup_environment()`, `create_desktop_shortcuts()`, `show_summary()`

Each function is idempotent - it checks if a component is already installed before proceeding.

### Component Configuration (config.sh)

Components are declared in `config.sh` with:
- Display name
- Verification command (how to check if installed)
- Required flag (whether failure should stop deployment)

Both `deploy-desktop.sh` and `tests/validate-install.sh` source this file. When adding new components, just update `config.sh` - no test code changes needed.

## Key Files

| File | Purpose |
|------|---------|
| `deploy-desktop.sh` | Main deployment script |
| `config.sh` | Shared component configuration (declarative list of components with verification methods) |
| `tests/validate-install.sh` | Post-deployment validation (sources config.sh automatically) |
| `scripts/session-monitor.sh` | Session monitoring service installation/management |
| `scripts/analyze-session-logs.sh` | Quick analysis tool for crashes, memory, and system health |
| `etc/xrdp/startwm.sh` | Enhanced session startup script with crash recovery |
| `docs/usage-guide.md` | Detailed user documentation |
| `docs/ssh-setup-guide.md` | SSH setup guide for Windows |
| `docs/crash-recovery-guide.md` | Crash recovery and monitoring guide |

## Important Implementation Details

- **Idempotency**: All `install_*` functions check for existing installations with `command -v` or `dpkg -l`
- **Error handling**: Uses `set -euo pipefail` and explicit error checking with `if ! ...; then return 1; fi`
- **Modern GPG**: Uses `/etc/apt/keyrings/` instead of deprecated `apt-key add`
- **OpenRouter config**: Creates `~/.config/claude/settings.json` with API endpoint and writes API key from environment
- **Desktop shortcuts**: Creates `.desktop` files in `$HOME/Desktop/` for VS Code, Claude Code, and Chromium
- **RDP configuration**: Uses custom `/etc/xrdp/startwm.sh` to launch GNOME session

## Remote Server Workflow

1. Upload script: `scp deploy-desktop.sh user@server:/tmp/`
2. Run with sudo: `sudo bash /tmp/deploy-desktop.sh`
3. Set API key: `export OPENROUTER_API_KEY="your_key"`
4. Connect via RDP on port 3389 from Windows or Android tablet