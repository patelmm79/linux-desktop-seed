# OpenCLAW Configuration Governance

## Architecture: Single Config Source

The gateway runs as root but reads config from **desktopuser's home**. This is configured via systemd override:

```
# /home/desktopuser/.config/systemd/user/openclaw-gateway.service.d/override.conf
[Service]
Environment=HOME=/home/desktopuser
Environment=OPENROUTER_API_KEY=sk-or-v1-...
```

**Why this matters:**
- Single source of truth: `/home/desktopuser/.openclaw/openclaw.json`
- No sync step needed between desktopuser and root
- Config is locked (444) and governed by the scripts below

## Overview

The OpenCLAW config (`/home/desktopuser/.openclaw/openclaw.json`) is **LOCKED BY DEFAULT**. This prevents accidental corruption from:
- `openclaw doctor --fix` auto-migrations
- Development tasks accidentally editing the file
- System updates modifying configuration

## The Golden Rule

**NEVER edit openclaw.json directly without following the governance process.**

## Quick Reference

| Action | Command |
|--------|---------|
| Check status | `/usr/local/bin/openclaw-lock-config.sh status` |
| Unlock for changes | `/usr/local/bin/openclaw-lock-config.sh unlock` |
| Lock after changes | `/usr/local/bin/openclaw-lock-config.sh lock` |
| Validate config | `/usr/local/bin/openclaw-validate-config.sh` |
| Create backup | `/usr/local/bin/openclaw-backup-config.sh` |
| Change request | `/usr/local/bin/openclaw-change-request.sh request "description"` |
| Approve change | `/usr/local/bin/openclaw-change-request.sh approve <id>` |

## Governance Process

### Normal Change Flow

1. **Request** - Create change request with description
   ```bash
   /usr/local/bin/openclaw-change-request.sh request "Add new Discord channel"
   ```

2. **Review** - Milan reviews the request

3. **Approve** - Milan approves the change
   ```bash
   /usr/local/bin/openclaw-change-request.sh approve cr-YYYYMMDD-HHMMSS
   ```

4. **Backup** - Automated backup created before any changes

5. **Unlock** - Config is temporarily unlocked
   ```bash
   /usr/local/bin/openclaw-lock-config.sh unlock
   ```

6. **Validate** - Run pre-flight validation
   ```bash
   /usr/local/bin/openclaw-validate-config.sh
   ```

7. **Edit** - Make the required changes
   ```bash
   nano /home/desktopuser/.openclaw/openclaw.json
   ```

8. **Validate Again** - Ensure changes are valid
   ```bash
   /usr/local/bin/openclaw-validate-config.sh
   ```

9. **Sync to Root** - Copy to root's config (required)
   ```bash
   cp /home/desktopuser/.openclaw/openclaw.json /root/.openclaw/openclaw.json
   ```

10. **Lock** - Re-lock the config
    ```bash
    /usr/local/bin/openclaw-lock-config.sh lock
    ```

11. **Restart** - Restart the gateway
    ```bash
    systemctl --user restart openclaw-gateway.service
    ```

12. **Verify** - Check Discord integration works
    ```bash
    journalctl --user -u openclaw-gateway.service -f | grep discord
    ```

### Emergency Change Flow

For urgent fixes (production down):

1. Make the fix
2. Run validation
3. Restart service
4. Get post-hoc approval from Milan
5. Document the change

## Protection Layers

| Layer | Mechanism | Purpose |
|-------|-----------|---------|
| File permissions | `chmod 444` (read-only) | Prevents accidental writes |
| Validation | `jq` schema checks | Catches config errors before restart |
| Backup | Timestamped copies | Enables rollback |
| Audit | Git commit history | Tracks all changes |

## API Key Management

The OpenRouter API key is stored in:
- **Systemd override**: `/home/desktopuser/.config/systemd/user/openclaw-gateway.service.d/override.conf`
- **NOT in config file**: Uses `ENV_PLACEHOLDER` which resolves to the env var

To update the API key:
```bash
# Edit the override (requires unlock first)
sudo /usr/local/bin/openclaw-lock-config.sh unlock
nano /home/desktopuser/.config/systemd/user/openclaw-gateway.service.d/override.conf

# Reload and restart
systemctl --user daemon-reload
systemctl --user restart openclaw-gateway.service

# Lock it back
sudo /usr/local/bin/openclaw-lock-config.sh lock
```

## If Config Breaks

1. **Check the lock status**
   ```bash
   /usr/local/bin/openclaw-lock-config.sh status
   ```

2. **Restore from backup**
   ```bash
   ls -lt /home/desktopuser/.openclaw/openclaw-backup.*.json | head -1
   cp /home/desktopuser/.openclaw/openclaw-backup.2026-04-17T17-00-00.json /home/desktopuser/.openclaw/openclaw.json
   ```

3. **Validate**
   ```bash
   /usr/local/bin/openclaw-validate-config.sh
   ```

4. **Sync and restart**
   ```bash
   cp /home/desktopuser/.openclaw/openclaw.json /root/.openclaw/openclaw.json
   systemctl --user restart openclaw-gateway.service
   ```

## Scripts Location

All governance scripts are in `/usr/local/bin/`:
- `openclaw-lock-config.sh` - Lock/unlock config
- `openclaw-validate-config.sh` - Validate config syntax
- `openclaw-backup-config.sh` - Create backups
- `openclaw-change-request.sh` - Change request workflow

## Previous Incidents

| Date | Issue | Root Cause | Fix |
|------|-------|------------|-----|
| 2026-04-15 | Gateway failed to start | Config corrupted by `openclaw doctor --fix` | Restored from backup |
| 2026-04-17 | Discord 401 errors | Missing API key after config restore | Added systemd override |

---

**Last Updated:** 2026-04-17