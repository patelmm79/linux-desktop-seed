# OpenCLAW Configuration Governance

## Architecture: Single User Setup

The gateway runs as **desktopuser** (not root). All OpenCLAW artifacts live under desktopuser's home directory:

- **Service**: `/home/desktopuser/.config/systemd/user/openclaw-gateway.service`
- **Override**: `/home/desktopuser/.config/systemd/user/openclaw-gateway.service.d/override.conf`
- **Config**: `/home/desktopuser/.openclaw/openclaw.json`
- **Skills**: `/home/desktopuser/.openclaw/skills/`
- **Binary**: `/usr/local/bin/openclaw` → `/home/desktopuser/.npm-global/bin/openclaw`

**Why this matters:**
- Single source of truth: `/home/desktopuser/.openclaw/openclaw.json`
- No confusion between root and desktopuser configs
- Skills loaded from desktopuser's directory
- Gateway runs as desktopuser, reads desktopuser's config

## Overview

The OpenCLAW config (`/home/desktopuser/.openclaw/openclaw.json`) is **LOCKED BY DEFAULT** (444). This prevents accidental corruption from:
- `openclaw doctor --fix` auto-migrations
- Development tasks accidentally editing the file
- System updates modifying configuration

## The Golden Rule

**NEVER edit openclaw.json directly without following the governance process.**

## Quick Reference

| Action | Command |
|--------|---------|
| Check status | `/usr/local/bin/openclaw-lock-config.sh status` |
| Create request | `/usr/local/bin/openclaw-change-request.sh request "description"` |
| Approve change | `/usr/local/bin/openclaw-change-request.sh approve <id>` |
| Apply change | `/usr/local/bin/openclaw-change-request.sh apply <id>` |
| Validate & lock | `/usr/local/bin/openclaw-change-request.sh validate-and-lock <id>` |
| View change log | `/usr/local/bin/openclaw-change-request.sh show <id>` |

## Governance Process

### Normal Change Flow

1. **Request** - Agent creates change request with description
   ```bash
   /usr/local/bin/openclaw-change-request.sh request "Add new Discord channel"
   ```
   Returns request ID (e.g., `cr-20260417-215031`)

2. **Review** - Milan reviews the request

3. **Approve** - Milan approves the change
   ```bash
   /usr/local/bin/openclaw-change-request.sh approve cr-YYYYMMDD-HHMMSS
   ```
   Creates approval file with timestamp

4. **Apply** - Agent runs apply which:
   - Creates timestamped backup
   - Unlocks config (644)
   - Prompts for edit

5. **Validate & Lock** - After editing:
   ```bash
   /usr/local/bin/openclaw-change-request.sh validate-and-lock cr-YYYYMMDD-HHMMSS
   ```
   This:
   - Validates JSON is valid
   - Locks config (444)
   - Logs diff to approval file

6. **Restart** - Restart the gateway
   ```bash
   systemctl --user restart openclaw-gateway.service
   ```

7. **Verify** - Check Discord integration works
   ```bash
   journalctl --user -u openclaw-gateway.service | grep discord | tail -20
   ```

### Change Audit Trail

Every change is logged to the approval file:
```bash
# View what changed
/usr/local/bin/openclaw-change-request.sh show cr-YYYYMMDD-HHMMSS
```

The log includes:
- Approval timestamp
- Who approved
- Backup file used
- Full diff of changes

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
| Change logging | Diff logged to approval file | Full audit trail of what changed |

## API Key Management

The OpenRouter API key is stored in:
- **Systemd override**: `/home/desktopuser/.config/systemd/user/openclaw-gateway.service.d/override.conf`
- **NOT in config file**: Uses `ENV_PLACEHOLDER` which resolves to the env var

To update the API key:
```bash
# Edit the override
nano /home/desktopuser/.config/systemd/user/openclaw-gateway.service.d/override.conf

# Reload and restart
systemctl --user daemon-reload
systemctl --user restart openclaw-gateway.service
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

4. **Restart**
   ```bash
   systemctl --user restart openclaw-gateway.service
   ```

## Scripts Location

All governance scripts are in `/usr/local/bin/`:
- `openclaw-lock-config.sh` - Lock/unlock config
- `openclaw-validate-config.sh` - Validate config syntax
- `openclaw-backup-config.sh` - Create backups
- `openclaw-change-request.sh` - Change request workflow

## OpenCLAW Skills

Skills for agents are located at:
- `/home/desktopuser/.openclaw/skills/`

Example skill structure:
```
/home/desktopuser/.openclaw/skills/openclaw-usage/SKILL.md
```

## Previous Incidents

| Date | Issue | Root Cause | Fix |
|------|-------|------------|-----|
| 2026-04-15 | Gateway failed to start | Config corrupted by `openclaw doctor --fix` | Restored from backup |
| 2026-04-17 | Discord 401 errors | Missing API key after config restore | Added systemd override |
| 2026-04-17 | Gateway running as root | Dual config causing confusion | Migrated to single-user (desktopuser) setup |

---

**Last Updated:** 2026-04-17