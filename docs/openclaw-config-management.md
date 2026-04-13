# OpenCLAW Configuration Management

## Overview

OpenCLAW configuration is managed through a strict lockdown process to prevent accidental breakage that causes service outages.

## Files

| File | Location | Purpose |
|------|----------|---------|
| Ideal config | `config/openclaw-ideal-config.json` | Reference config in git (no secrets) |
| Active config | `~/.openclaw/openclaw.json` | Live config on VM (read-only) |
| Validation | `/usr/local/bin/validate-openclaw-config.sh` | Config validation before start |
| Wrapper | `/home/desktopuser/bin/openclaw-start.sh` | Starts OpenCLAW with validation |

## Lockdown Rules

### Never Do
- ❌ Edit config without understanding current state
- ❌ Restart without validating first
- ❌ Make unprompted config changes
- ❌ Leave root config out of sync with desktopuser config

### Always Do
- ✅ Propose changes with justification
- ✅ Explain failure risk
- ✅ Run validation before restart
- ✅ Test after any change

## Validation

The validation script (`/usr/local/bin/validate-openclaw-config.sh`) checks:
1. Valid JSON syntax
2. Required `agents.defaults.model` exists
3. Model format is valid (alphanumeric, `/`, `.`, `-`, `_`)
4. Required `.models.providers` fields (baseUrl, apiKey, models)

### Run Validation
```bash
ssh hetzner "/usr/local/bin/validate-openclaw-config.sh"
```

### Start with Validation
```bash
ssh hetzner "/home/desktopuser/bin/openclaw-start.sh"
```

## Restarting Gateway

After config changes, restart the gateway:

```bash
# Sync config to root (required - service runs as root)
ssh hetzner "cp /home/desktopuser/.openclaw/openclaw.json /root/.openclaw/openclaw.json"

# Restart as user
ssh hetzner "systemctl --user restart openclaw-gateway.service"

# Verify
ssh hetzner "systemctl --user status openclaw-gateway.service --no-pager | head -8"
```

## Making Config Changes

1. **Propose** - Explain what field, why, failure risk
2. **Get approval** - Wait for explicit permission
3. **Validate first** - Run validation script
4. **Make minimal change** - Only what's approved
5. **Test** - Health check after restart

## Backup & Rollback

Config is read-only (`chmod 444`) to prevent accidental modification. To make changes:

```bash
# Temporarily make writable (requires explicit permission)
ssh hetzner "sudo chmod 644 /home/desktopuser/.openclaw/openclaw.json"

# Edit config
ssh hetzner "nano /home/desktopuser/.openclaw/openclaw.json"

# Restore read-only
ssh hetzner "sudo chmod 444 /home/desktopuser/.openclaw/openclaw.json"
```

## Environment-Only Secrets

The ideal config contains NO secrets. Sensitive data comes from:

- Environment variables (set in wrapper or systemd)
- Or `~/.openclaw/runtime.env` (outside git)

This allows the config file to be public without security risk.

## If Config Breaks

1. **Check validation** - Run validation script for specific error
2. **Restore from .bak** - ALWAYS use `~/.openclaw/openclaw.json.bak` as the source of truth
3. **Reset to ideal** - Copy from `config/openclaw-ideal-config.json`
4. **Test** - Health check after any fix

## Emergency Recovery (Critical)

**When OpenCLAW stops responding to Discord:**

### Step 1: Get the authoritative config
```bash
# ALWAYS start here - the .bak file is the source of truth
cat ~/.openclaw/openclaw.json.bak
```

### Step 2: Check what's currently active
```bash
openclaw config get bindings
openclaw config get channels.discord
```

### Step 3: Restore from .bak if unsure
```bash
# Kill existing gateway first
pkill -f openclaw-gateway

# Restore from known-good backup
cp ~/.openclaw/openclaw.json.bak ~/.openclaw/openclaw.json
chown desktopuser:desktopuser ~/.openclaw/openclaw.json

# Sync to root (required - service runs as root)
cp ~/.openclaw/openclaw.json /root/.openclaw/openclaw.json
```

### Step 4: Start with correct environment
```bash
# CRITICAL: Set HOME to desktopuser, not root
HOME=/home/desktopuser XDG_CONFIG_HOME=/home/desktopuser/.config openclaw gateway
```

### Step 5: Verify
```bash
# Check Discord connected
tail -50 openclaw.log | grep -i discord

# Verify channel binding
openclaw config get bindings
```

## Common Breakage Causes

| Cause | Prevention |
|-------|------------|
| Running as root creates `/root/.openclaw` | Always set `HOME=/home/desktopuser` |
| Manually editing instead of using .bak | ALWAYS restore from `.bak` first |
| Guessing channel IDs | Use `.bak` file to get correct channel |
| Missing environment vars | Use `XDG_CONFIG_HOME` and `HOME` |

## Key Insight

The `.bak` file contains the **exact working config** including correct Discord channel IDs. When in doubt:
- **Read .bak first** - it's the authoritative source
- **Verify with CLI second** - `openclaw config get`
- **Test third** - send a message to the Discord channel

Never guess at channel IDs or config values. The .bak has the answers.

## Autostart

OpenCLAW starts via XDG autostart (`~/.config/autostart/openclaw-gateway.desktop`) which calls the wrapper script with validation.

---

**Last Updated:** 2026-04-10