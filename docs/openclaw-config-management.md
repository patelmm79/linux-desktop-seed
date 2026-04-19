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

## Current Configuration (2026-04-19)

### Models

Three models configured via OpenRouter:

| Model ID | Name | Type | Context | Alias |
|----------|------|------|---------|-------|
| `openrouter/minimax/MiniMax-M2.7` | MiniMax-M2.7 | Reasoning | 100K | `coder` |
| `openrouter/anthropic/claude-haiku-4-5` | Claude Haiku | Fast | 200K | `poet` |
| `openrouter/anthropic/claude-sonnet-4-5` | Claude Sonnet | Balanced | 200K | `burns` |

**Default:** MiniMax-M2.7

**Aliases location:** `agents.defaults.models` (not in model definition - schema doesn't support it there)

### Agents

12 agents configured, one per Discord channel. Channel IDs stored in private config only.

| Agent | Model |
|-------|-------|
| linux-desktop-seed | MiniMax |
| research-orchestrator | MiniMax |
| intelligent-feed | MiniMax |
| dev-nexus-action-agent | MiniMax |
| rag-research-tool | MiniMax |
| dynamic-worlock | MiniMax |
| dev-nexus-frontend | MiniMax |
| globalbitings | MiniMax |
| elastica | MiniMax |
| dev-nexus | MiniMax |
| bond-nexus | MiniMax |
| resume-customizer | MiniMax |

### Discord

- **Bot:** `@coder` (user ID: 1494956104340476077)
- **Token:** `MTQ5NDk1NjEwNDM0MDQ3NjA3Nw...`
- **requireMention:** false (auto-respond to all messages)
- **Allow from:** user:1162240440322502656

### Config File Location

```
/home/desktopuser/.openclaw/openclaw.json
```

### Starting/Restarting Gateway

```bash
# Kill existing
pkill -f openclaw-gateway || true

# Start as desktopuser
HOME=/home/desktopuser sudo -u desktopuser nohup /home/desktopuser/.npm-global/bin/openclaw gateway run > /tmp/openclaw.log 2>&1 &

# Check logs
tail -50 /tmp/openclaw.log
```

## Previous Incidents

| Date | Issue | Root Cause | Fix |
|------|-------|------------|-----|
| 2026-04-15 | Gateway failed to start | Config corrupted by `openclaw doctor --fix` | Restored from backup |
| 2026-04-17 | Discord 401 errors | Missing API key after config restore | Added systemd override |
| 2026-04-17 | Gateway running as root | Dual config causing confusion | Migrated to single-user (desktopuser) setup |
| 2026-04-19 | Model alias validation failed | `alias` field in models array | Moved aliases to `agents.defaults.models` |

---

**Last Updated:** 2026-04-19