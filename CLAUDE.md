# CLAUDE.md - Developer Instructions

This file provides guidance to Claude Code when working with this repository.

## Project Overview

**Remote Linux Desktop Deployment** - Production-ready automation for deploying a complete development environment on Ubuntu servers with RDP access, AI tools, automatic crash detection, and continuous monitoring.

**Key Achievement:** Reduced crash detection time from 3+ hours to **< 30 seconds** with full forensic data capture.

**OpenCLAW Version:** v2026.3.28 (MiniMax compatible) - See `deploy-desktop.sh` line 1133 for version pinning.

## What This Project Does

The deployment script (`deploy-desktop.sh`) installs and configures:

- **Desktop Environment:** GNOME Desktop (touch-friendly, tablet-optimized)
- **RDP Server:** xrdp with Xvnc for Windows/Android Remote Desktop access
- **Development Tools:** VS Code, Claude Code, OpenRouter CLI, Chromium
- **Infrastructure:** Terraform, Terragrunt for Infrastructure-as-Code
- **Reliability:** Automatic crash detection (30 sec response), memory management
- **Security:** GNOME Keyring for secure credential storage
- **Extensions:** Cascade Windows tool for window management
- **Monitoring:** Continuous health checks with threshold-based alerting

## Critical Implementation

### Crash Recovery System

**Problem Solved:** Session crashes took 3+ hours to detect with no root cause data.

**Solution Implemented:**
- EXIT trap in `startwm.sh` captures crash context immediately
- Monitoring service (`session-monitor.sh`) checks every 30 seconds
- Analysis tool (`analyze-session-logs.sh`) provides one-line diagnostics

**Performance:** < 30 seconds detection time vs. 3+ hours previously.

### Keyring Integration

**Problem Solved:** "OS keyring is not available for encryption" errors in VS Code.

**Solution Implemented:**
- Keyring daemon starts inside `dbus-launch` context
- D-Bus session properly initialized before keyring startup
- All child processes inherit environment variables automatically

**Key File:** `etc/xrdp/startwm.sh` (lines 89-104)

### VM Testing

All changes tested on a VM before commit. When reporting issues, always fix in repository scripts so future deployments benefit automatically.

## Architecture

### Modular Bash Script (~1200 lines)

```
deploy-desktop.sh
├── System setup (check_root, detect_ubuntu_version, update_system)
├── Desktop (install_gnome, configure_xwrapper, install_xrdp)
├── Applications (install_vscode, install_claude_code, etc.)
├── Configuration (setup_environment, configure_mcp_servers)
├── Reliability (setup_keyring, setup_monitoring, setup_gnome_extensions)
└── Deployment flow (main function orchestrates all steps)
```

**Principle:** Each function is idempotent and can run multiple times safely.

### Supporting Scripts

| Script | Purpose |
|--------|---------|
| `config.sh` | Component declarations (used by deployment and tests) |
| `tests/validate-install.sh` | Post-deployment validation |
| `scripts/session-monitor.sh` | Monitoring service installer |
| `scripts/analyze-session-logs.sh` | Crash and performance analysis |
| `etc/xrdp/startwm.sh` | Enhanced session startup with crash recovery |

## Common Commands

### Deployment
```bash
# Validate syntax
bash -n deploy-desktop.sh

# Deploy to remote server
scp deploy-desktop.sh user@server:/tmp/
ssh user@server
sudo bash /tmp/deploy-desktop.sh

# Validate installation
sudo bash tests/validate-install.sh
```

### Monitoring & Diagnostics
```bash
# Health check
bash scripts/analyze-session-logs.sh --summary

# Real-time monitor
tail -f /var/log/xrdp/session-monitor.log
tail -f /var/log/xrdp/session-alerts.log

# Crash analysis
bash scripts/analyze-session-logs.sh --crashes

# Memory trends
bash scripts/analyze-session-logs.sh --memory

# Session timeline
bash scripts/analyze-session-logs.sh --timeline
```

### Service Management
```bash
# Check services
systemctl status xrdp
systemctl status xrdp-session-monitor.service

# View logs
tail -50 /var/log/xrdp-sesman.log
journalctl -u xrdp-session-monitor.service -n 50

# Restart services
sudo systemctl restart xrdp
sudo systemctl restart xrdp-session-monitor.service
```

## Key Files

| File | Purpose | Lines |
|------|---------|-------|
| `deploy-desktop.sh` | Main deployment script | ~1250 |
| `config.sh` | Component configuration | ~100 |
| `etc/xrdp/startwm.sh` | Enhanced session startup | ~110 |
| `scripts/session-monitor.sh` | Monitoring service | ~400 |
| `scripts/analyze-session-logs.sh` | Analysis tools | ~300 |
| `scripts/cleanup-sessions.sh` | Session cleanup (cron) | ~100 |
| `scripts/deploy-repo-to-vm.sh` | Repository deployment skill | ~100 |
| `config/openclaw-defaults.json` | OpenCLAW defaults | - |
| `tests/validate-install.sh` | Deployment validation | ~150 |

### Documentation
- `README.md` - User guide and quick start
- `docs/QUICK-DEPLOY.md` - 5-minute walkthrough
- `docs/crash-recovery-guide.md` - Crash detection details
- `docs/keyring-guide.md` - Credential storage setup
- `docs/INTEGRATION_GUIDE.md` - Component integration
- `docs/DEPLOYMENT_SUMMARY.md` - Architecture overview
- `docs/FINAL_SUMMARY.md` - Complete technical details
- `docs/README_MONITORING.md` - Monitoring reference

## Important Implementation Details

### Idempotency Pattern

All `install_*` functions check before installing:
```bash
install_vscode() {
    if command -v code &> /dev/null; then
        log_info "VS Code already installed"
        return 0
    fi
    # ... installation steps ...
}
```

### Error Handling

- Uses `set -euo pipefail` for immediate error exit
- Explicit error checking: `if ! command; then return 1; fi`
- Never use `|| true` for critical operations
- Log errors with context: `log_error "Failed to do X: reason"`

### Modern Practices

- **GPG keys:** Use `/etc/apt/keyrings/` instead of deprecated `apt-key`
- **Environment variables:** Store sensitive data in variables, not files
- **Bash version:** Compatible with bash 4.0+ (macOS, Linux)
- **Portability:** Avoid GNU-specific tools; use POSIX where possible

### Session Architecture

```
User connects via RDP (port 3389)
    ↓
xrdp-sesman launches startwm.sh
    ↓
Set environment variables (X11, memory limits)
    ↓
dbus-launch starts D-Bus session
    ↓
gnome-keyring-daemon starts (inside D-Bus context)
    ↓
gnome-session starts (inherits all variables)
    ↓
Applications run (VS Code, Chromium, etc.)
    ↓
Monitor service watches continuously
    ↓
If crash detected → context logged → operator alerted
```

### OpenCLAW Configuration Location

**IMPORTANT:** OpenCLAW config must be in `desktopuser`'s home, never root's home.

- Config path: `/home/desktopuser/.openclaw/openclaw.json`
- Deployment script now uses `getent passwd "$TARGET_USER"` to determine the correct home directory
- Never use `$HOME` when running as root - it resolves to `/root`

Common issues:
- Running `openclaw` as root creates `/root/.openclaw/` (wrong!)
- Gateway may check root's config instead of desktopuser's
- Fix: Always run openclaw commands as desktopuser or via `sudo -u desktopuser`

## Workflow for Bug Fixes

**CRITICAL RULE:** When user reports a VM issue, fix the **deployment scripts**, not just the remote machine.

### Steps

1. **Diagnose** - SSH into VM and gather logs/data
2. **Fix repository** - Update `deploy-desktop.sh` or supporting scripts
3. **Test on VM** - Verify fix works with reconnection or redeployment
4. **Future benefit** - Next deployment automatically includes fix

This ensures the deployment script continuously improves based on real-world experience.

## Testing

### Local Validation
```bash
bash -n deploy-desktop.sh           # Syntax check
grep -n "function " deploy-desktop.sh  # List functions
```

### Remote Validation
```bash
ssh user@server
sudo bash tests/validate-install.sh     # Comprehensive checks
bash scripts/analyze-session-logs.sh --summary  # Health check
```

### Test VM
Current test machine: configured via workflow_dispatch input
- Monitors: systemctl status xrdp-session-monitor.service
- Health: bash scripts/analyze-session-logs.sh --summary
- Logs: tail -50 /var/log/xrdp-sesman.log

## Coding Standards

### Bash Style
- `#!/bin/bash` at top
- `set -euo pipefail` early
- Quote variables: `"$var"` not `$var`
- Use `[[ ]]` for conditionals (not `[ ]`)
- Lowercase function names with underscores: `install_vscode()`
- 4-space indentation (not tabs)

### Error Handling
```bash
if ! some_command; then
    log_error "Descriptive message about what failed"
    return 1
fi
```

### Logging
```bash
log_info "Starting component X"        # Success/progress
log_warn "Component Y had issue"       # Non-fatal warning
log_error "Component Z failed"         # Fatal error
```

### Comments
Add comments for:
- Non-obvious logic
- Complex shell expansions
- Important constraints or workarounds
- Anything that took > 5 minutes to understand

Don't comment obvious code.

## Configuration Points

### Memory Limits

Edit `etc/xrdp/startwm.sh` (line 64):
```bash
ulimit -v 2097152  # ~2GB virtual memory per process
```

### Monitor Thresholds

Edit `/var/lib/xrdp/session-monitor-config.sh`:
```bash
MEMORY_THRESHOLD=80      # Alert at 80% memory
CPU_THRESHOLD=75         # Alert at 75% CPU
```

### Keyring

Auto-configured during deployment. Located in:
- Daemon: `gnome-keyring-daemon`
- Config: `~/.local/share/gnome-online-accounts/`
- Storage: `~/.local/share/keyrings/`

### RDP Configuration

- Port: 3389 (set in `/etc/xrdp/xrdp.ini`)
- Server: Xvnc (not Xorg, set in `/etc/xrdp/sesman.ini`)
- Session: Ubuntu GNOME (set in `startwm.sh`)

## Performance Targets

Typical resource usage:
- **Idle memory:** 2-3 GB
- **Monitor overhead:** < 1% CPU (30 sec checks)
- **Monitor memory:** ~5 MB
- **Startup time:** 5-15 minutes (depends on internet)
- **Crash detection:** < 30 seconds
- **RDP bandwidth:** ~100 KB/s typical

## When to Add Features

✅ **Good candidates:**
- Features that improve core mission (RDP desktop access)
- Reliability improvements (monitoring, crash recovery)
- Security enhancements (credential storage)
- Well-integrated tools (GNOME extensions)

❌ **Avoid:**
- Unnecessary bloat or random tools
- Features conflicting with RDP/GNOME
- Heavy applications consuming resources
- Changes breaking idempotency

## Documentation Organization

All user-facing docs in `docs/` folder:

| Doc | Audience | Purpose |
|-----|----------|---------|
| `QUICK-DEPLOY.md` | New users | 5-minute walkthrough |
| `usage-guide.md` | End users | Using installed tools |
| `ssh-setup-guide.md` | Windows users | SSH configuration |
| `crash-recovery-guide.md` | Operators | Understanding crash detection |
| `keyring-guide.md` | Developers | Credential storage API |
| `INTEGRATION_GUIDE.md` | Developers | Component interaction |
| `DEPLOYMENT_SUMMARY.md` | Architects | High-level design |
| `FINAL_SUMMARY.md` | Technical | Detailed implementation |
| `README_MONITORING.md` | Operators | Monitoring operations |
| `openclaw-config-management.md` | Operators | OpenCLAW config lockdown procedures |

## Git Workflow

### Commits

Use imperative form and explain why:
```
feat: add Cascade Windows GNOME extension
  - Installs window management tool
  - Available via GNOME extensions menu
  - Improves window organization on large screens

fix: ensure keyring daemon inherits dbus-launch context
  - Resolves "OS keyring not available" errors
  - Keyring now starts inside D-Bus session
  - All child processes inherit environment variables
```

### Branches

Main branch workflow:
1. Make changes locally
2. Test on a VM if possible
3. Commit with detailed message
4. Push to main

## Important Constraints

### Security
- Never hardcode credentials
- Use environment variables: `$OPENROUTER_API_KEY`
- Prefer system keyrings over config files
- Validate input at system boundaries

### Compatibility
- Target Ubuntu 20.04+
- Test on 20.04, 22.04, 24.04
- Maintain backward compatibility
- Document version-specific requirements

### Reliability
- All operations must be idempotent
- Explicit error handling always
- Comprehensive logging for debugging
- Graceful degradation for optional features

### Performance
- Startup time < 15 minutes
- Monitor overhead < 1% CPU
- No unnecessary background processes
- Clean up temporary files

## Git History

Major milestones:
```
d6d6e06 feat: add Cascade Windows GNOME extension
04f48c9 fix: ensure keyring daemon inherits dbus-launch context
c5a7ca9 feat: add enhanced debugging to startwm.sh
```

See `git log` for complete history.

## Future Enhancements

Potential improvements:
- [ ] More GNOME extensions (Dash to Dock, etc.)
- [ ] Performance monitoring dashboard
- [ ] Automated backup system
- [ ] Multi-user support
- [ ] Container/Docker integration
- [ ] Cloud provider optimizations
- [ ] Automated testing suite

---

**Last Updated:** March 31, 2026
**Status:** Production Ready ✅
**Test Machine:** Configured via GitHub workflow
**Crash Detection:** < 30 seconds
**Uptime:** Continuous monitoring active