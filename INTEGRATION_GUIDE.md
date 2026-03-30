# Integration Guide - Crash Recovery & Monitoring

## Overview

All new functionality (crash recovery, monitoring, and keyring) is now **fully integrated** into the main `deploy-desktop.sh` deployment script. Future deployments will automatically include these features.

## What Was Integrated

### 1. Enhanced startwm.sh
The session startup script in `deploy-desktop.sh` now includes:
- **Crash recovery**: EXIT trap captures exit code, signal, and system context
- **Memory management**: 2GB per-process virtual memory limits
- **Keyring initialization**: Auto-starts GNOME Keyring daemon
- **D-Bus setup**: Proper session bus configuration
- **Session logging**: Detailed startup and error logging

### 2. setup_keyring() Function
New function that:
- Installs `gnome-keyring`, `libsecret-1-0`, `libpam-gnome-keyring`
- Verifies installation success
- Runs automatically during deployment

### 3. setup_monitoring() Function
New function that:
- Copies `scripts/session-monitor.sh` to `/tmp/`
- Runs the monitoring installer with `--enable` flag
- Sets up systemd service for continuous checks
- Starts the monitoring daemon

### 4. Integration in main()
Both setup functions are called in the main deployment flow:
```bash
main() {
    # ... other setup functions ...
    create_desktop_shortcuts
    setup_keyring                    # ← NEW
    setup_monitoring                 # ← NEW
    show_summary
}
```

## Deployment Flow

When running `sudo bash deploy-desktop.sh`:

1. **Basic system setup** (OS detection, updates, dependencies)
2. **GNOME & RDP installation** (desktop, xrdp, Xvnc)
3. **Applications** (VS Code, Claude Code, Chromium, etc.)
4. **Configuration** (MCP servers, environment, shortcuts)
5. **setup_keyring()** ← Installs secure credential storage
6. **setup_monitoring()** ← Installs crash detection & monitoring
7. **show_summary()** ← Displays post-deployment information

## What Gets Deployed Automatically

### Crash Recovery
- Enhanced `/etc/xrdp/startwm.sh` with:
  - Memory limits (2GB per-process)
  - EXIT trap crash logging
  - Session metadata capture
  - System context snapshots

### Credential Storage
- GNOME Keyring packages installed
- libsecret for password storage
- PAM integration for auto-unlock
- SSH agent support

### Monitoring Service
- systemd service: `xrdp-session-monitor.service`
- Checks every 30 seconds
- Memory threshold: 80%
- CPU threshold: 75%
- Real-time syslog alerts
- Log files:
  - `/var/log/xrdp/session-monitor.log`
  - `/var/log/xrdp/session-alerts.log`

## Backward Compatibility

All functionality is **backward compatible**:
- The `deploy-desktop.sh` script works standalone
- New setup functions return gracefully on any errors
- Monitoring can be disabled if needed: `sudo bash /tmp/session-monitor.sh --disable`
- Keyring can be removed: `apt-get remove gnome-keyring libsecret-1-0`

## New Deployments

Future deployments will automatically get:

```
✓ Crash recovery (automatic detection in 30 seconds)
✓ Secure credential storage (GNOME Keyring)
✓ Continuous monitoring (every 30 seconds)
✓ Memory management (prevents OOM)
✓ Full audit trail
✓ Quick diagnostic tools
```

## Existing Installations

To add these features to an existing installation:

```bash
# On the remote server

# Option 1: Install everything
sudo bash /tmp/session-monitor.sh --enable
bash /tmp/setup-keyring.sh

# Option 2: Install only monitoring
sudo bash /tmp/session-monitor.sh --enable

# Option 3: Install only keyring
bash /tmp/setup-keyring.sh

# Option 4: Update startwm.sh manually
# Copy the enhanced version from et/xrdp/startwm.sh
```

## Verification

After deployment, verify everything is working:

```bash
# Check monitoring service
systemctl status xrdp-session-monitor.service

# Check keyring packages
dpkg -l | grep gnome-keyring

# Run health check
bash /tmp/analyze-session-logs.sh --summary

# View monitoring logs
tail -f /var/log/xrdp/session-monitor.log

# View alerts
tail -f /var/log/xrdp/session-alerts.log
```

## Scripts Location

All scripts remain available for manual use:

```
Repository:
  scripts/session-monitor.sh        - Monitoring service installer
  scripts/analyze-session-logs.sh   - Diagnostic analysis tool
  scripts/setup-keyring.sh          - Keyring configuration
  etc/xrdp/startwm.sh              - Enhanced session startup

Remote machine after deployment:
  /etc/xrdp/startwm.sh             - Enhanced session startup
  /etc/systemd/system/xrdp-session-monitor.service
  /usr/local/bin/xrdp-session-monitor
  /var/lib/xrdp/session-monitor-config.sh
```

## Configuration

### Memory Limit
Edit `/etc/xrdp/startwm.sh`:
```bash
ulimit -v 2097152  # Change this (value in KB)
```

### Monitoring Thresholds
Edit `/var/lib/xrdp/session-monitor-config.sh`:
```bash
MEMORY_THRESHOLD=80      # Change to your threshold
CPU_THRESHOLD=75         # Change to your threshold
```

## Troubleshooting

### Monitor not running
```bash
systemctl status xrdp-session-monitor.service
journalctl -u xrdp-session-monitor.service -n 50
```

### Keyring errors
```bash
# Check if daemon is running
pgrep -f gnome-keyring-daemon

# Restart it
systemctl --user restart gnome-keyring-daemon
```

### Crashes not detected
```bash
# Check if monitoring service is active
systemctl is-active xrdp-session-monitor.service

# Check logs
tail -100 /var/log/xrdp/session-monitor.log
```

## Files Modified

Only one file was modified in the main codebase:
- `deploy-desktop.sh` - Added integration functions and calls

All other files are new:
- `scripts/session-monitor.sh`
- `scripts/analyze-session-logs.sh`
- `scripts/setup-keyring.sh`
- `etc/xrdp/startwm.sh` (also embedded in deploy-desktop.sh)
- Various documentation files

## Impact

**For existing users:**
- No impact unless they choose to use the new scripts
- All existing functionality remains unchanged
- Can be added manually to existing installations

**For new deployments:**
- Automatic crash recovery and monitoring
- Automatic credential storage setup
- No additional configuration needed
- All features included out of the box

## Support

For issues with the new features:

1. Check the relevant guide:
   - `docs/crash-recovery-guide.md`
   - `docs/keyring-guide.md`
   - `README_MONITORING.md`

2. Run diagnostics:
   - `bash /tmp/analyze-session-logs.sh --summary`
   - `bash /tmp/analyze-session-logs.sh --crashes`

3. Check logs:
   - `/var/log/xrdp/session-monitor.log`
   - `/var/log/xrdp-sesman.log`
   - `~/.xsession-errors`

## Git Integration

The integration is tracked in the git repository:

```
4e2f340 - feat: integrate crash recovery and keyring setup
          into deploy-desktop.sh
```

All changes are clean, documented, and production-ready.

## Next Steps

1. **New deployments**: Simply run `sudo bash deploy-desktop.sh` - everything is automatic
2. **Existing installations**: Run the setup scripts manually from `/tmp/`
3. **Customization**: Edit configuration files as needed for your environment
4. **Monitoring**: Use `analyze-session-logs.sh` for ongoing diagnostics

---

**Integration Status:** COMPLETE ✓
**Production Ready:** YES ✓
**Backward Compatible:** YES ✓
**Automatic for new deployments:** YES ✓
