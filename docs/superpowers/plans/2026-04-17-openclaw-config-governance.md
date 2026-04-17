# OpenCLAW Configuration Governance Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a governance system that protects the OpenCLAW config from accidental corruption while enabling controlled changes through a strict approval process.

**Architecture:** Implement a multi-layer defense system with: (1) file permissions locking, (2) git-backed config versioning, (3) validation gates, (4) change request workflow, (5) automated backup before any modification.

**Tech Stack:** Bash scripts, systemd service overrides, git hooks, cron jobs

---

## Background

The OpenCLAW config (`~/.openclaw/openclaw.json`) controls Discord integration, agent routing, and API authentication. Recent incidents show:
- Running `openclaw doctor --fix` corrupted the config (April 15)
- Another development task accidentally modified the config
- The backup system exists but wasn't used in time

This governance plan creates barriers to prevent accidental changes while enabling controlled modifications.

---

## Files

- Modify: `docs/openclaw-config-management.md` (update with new governance process)
- Create: `/usr/local/bin/openclaw-lock-config.sh` (lock/unlock wrapper)
- Create: `/usr/local/bin/openclaw-validate-config.sh` (pre-flight validation)
- Create: `/usr/local/bin/openclaw-change-request.sh` (change request workflow)
- Create: `/usr/local/bin/openclaw-backup-config.sh` (automated backup)
- Create: `/home/desktopuser/.config/systemd/user/openclaw-gateway.service.d/override.conf` (environment persistence)
- Create: `config/openclaw-prod-config.json` (git-tracked reference, no secrets)
- Modify: `.github/workflows/openclaw-config-workflow.yml` (optional CI enforcement)

---

## Task 1: Lock Down Config File Permissions

**Files:**
- Create: `/usr/local/bin/openclaw-lock-config.sh`
- Modify: `/home/desktopuser/.openclaw/openclaw.json` (set permissions)

- [ ] **Step 1: Create the lock/unlock wrapper script**

```bash
#!/bin/bash
# /usr/local/bin/openclaw-lock-config.sh
# Locks or unlocks the OpenCLAW config file

set -euo pipefail

CONFIG_FILE="/home/desktopuser/.openclaw/openclaw.json"
ROOT_CONFIG_FILE="/root/.openclaw/openclaw.json"

show_usage() {
    echo "Usage: $0 [lock|unlock|status]"
    echo "  lock   - Make config read-only (444)"
    echo "  unlock - Make config writable (644) for changes"
    echo "  status - Show current permission state"
    exit 1
}

get_perms() {
    stat -c "%a" "$CONFIG_FILE" 2>/dev/null || echo "none"
}

do_status() {
    local perms
    perms=$(get_perms)
    echo "Config: $CONFIG_FILE"
    echo "Permissions: $perms"
    
    if [[ "$perms" == "444" ]]; then
        echo "Status: LOCKED (read-only)"
    elif [[ "$perms" == "644" ]]; then
        echo "Status: UNLOCKED (writable)"
    else
        echo "Status: UNKNOWN"
    fi
}

do_lock() {
    echo "Locking config..."
    chmod 444 "$CONFIG_FILE"
    chown desktopuser:desktopuser "$CONFIG_FILE"
    chmod 444 "$ROOT_CONFIG_FILE"
    chown root:root "$ROOT_CONFIG_FILE"
    echo "Config locked (read-only)"
    do_status
}

do_unlock() {
    echo "Unlocking config..."
    chmod 644 "$CONFIG_FILE"
    chown desktopuser:desktopuser "$CONFIG_FILE"
    chmod 644 "$ROOT_CONFIG_FILE"
    chown root:root "$ROOT_CONFIG_FILE"
    echo "Config unlocked (writable)"
    do_status
}

case "${1:-status}" in
    lock) do_lock ;;
    unlock) do_unlock ;;
    status) do_status ;;
    *) show_usage ;;
esac
```

- [ ] **Step 2: Make the script executable**

```bash
chmod +x /usr/local/bin/openclaw-lock-config.sh
```

- [ ] **Step 3: Lock the current config**

```bash
/usr/local/bin/openclaw-lock-config.sh lock
```

- [ ] **Step 4: Verify lock is in effect**

```bash
ls -la /home/desktopuser/.openclaw/openclaw.json
# Should show: -r--r--r--
```

- [ ] **Step 5: Commit**

```bash
git add /usr/local/bin/openclaw-lock-config.sh
git commit -m "feat: add openclaw config lock/unlock wrapper"
```

---

## Task 2: Create Pre-Flight Validation Script

**Files:**
- Create: `/usr/local/bin/openclaw-validate-config.sh`
- Modify: `docs/openclaw-config-management.md`

- [ ] **Step 1: Create the validation script**

```bash
#!/bin/bash
# /usr/local/bin/openclaw-validate-config.sh
# Validates OpenCLAW config before any change or restart

set -euo pipefail

CONFIG_FILE="${1:-/home/desktopuser/.openclaw/openclaw.json}"
ERRORS=0

echo "=== OpenCLAW Config Validation ==="
echo "Config: $CONFIG_FILE"
echo ""

# Check file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: Config file not found: $CONFIG_FILE"
    exit 1
fi

# Check valid JSON
echo "[1/7] Checking JSON validity..."
if ! jq -e '.' "$CONFIG_FILE" >/dev/null 2>&1; then
    echo "ERROR: Invalid JSON"
    ERRORS=$((ERRORS + 1))
else
    echo "  OK: Valid JSON"
fi

# Check required sections exist
echo "[2/7] Checking required sections..."
for section in "meta" "models" "channels" "bindings"; do
    if ! jq -e "has(\"$section\")" "$CONFIG_FILE" >/dev/null 2>&1; then
        echo "ERROR: Missing required section: $section"
        ERRORS=$((ERRORS + 1))
    else
        echo "  OK: Section '$section' exists"
    fi
done

# Check models.providers.openrouter
echo "[3/7] Checking provider configuration..."
if jq -e '.models.providers.openrouter | has("baseUrl")' "$CONFIG_FILE" >/dev/null 2>&1; then
    echo "  OK: baseUrl present"
else
    echo "ERROR: Missing models.providers.openrouter.baseUrl"
    ERRORS=$((ERRORS + 1))
fi

if jq -e '.models.providers.openrouter | has("models")' "$CONFIG_FILE" >/dev/null 2>&1; then
    MODEL_COUNT=$(jq '.models.providers.openrouter.models | length' "$CONFIG_FILE")
    echo "  OK: models array present ($MODEL_COUNT models)"
else
    echo "ERROR: Missing models.providers.openrouter.models"
    ERRORS=$((ERRORS + 1))
fi

# Check bindings format
echo "[4/7] Checking bindings..."
BINDING_COUNT=$(jq '.bindings | length' "$CONFIG_FILE" 2>/dev/null || echo "0")
echo "  Found $BINDING_COUNT bindings"

# Check Discord config
echo "[5/7] Checking Discord configuration..."
if jq -e '.channels.discord.enabled == true' "$CONFIG_FILE" >/dev/null 2>&1; then
    echo "  OK: Discord enabled"
else
    echo "WARNING: Discord not enabled"
fi

# Check Discord token exists (not placeholder)
DISCORD_TOKEN=$(jq -r '.channels.discord.token // empty' "$CONFIG_FILE")
if [[ -n "$DISCORD_TOKEN" && "$DISCORD_TOKEN" != "DISCORD_BOT_TOKEN_PLACEHOLDER" ]]; then
    echo "  OK: Discord token present"
else
    echo "WARNING: Discord token missing or is placeholder"
fi

# Check gateway config
echo "[6/7] Checking gateway configuration..."
if jq -e '.gateway.mode' "$CONFIG_FILE" >/dev/null 2>&1; then
    echo "  OK: Gateway mode: $(jq -r '.gateway.mode' "$CONFIG_FILE")"
else
    echo "ERROR: Missing gateway.mode - this will prevent startup!"
    ERRORS=$((ERRORS + 1))
fi

# Summary
echo "[7/7] Summary"
echo ""
if [[ $ERRORS -gt 0 ]]; then
    echo "RESULT: FAILED with $ERRORS error(s)"
    exit 1
else
    echo "RESULT: PASSED - Config is valid"
    exit 0
fi
```

- [ ] **Step 2: Make executable and test**

```bash
chmod +x /usr/local/bin/openclaw-validate-config.sh
/usr/local/bin/openclaw-validate-config.sh
```

- [ ] **Step 3: Commit**

```bash
git add /usr/local/bin/openclaw-validate-config.sh
git commit -m "feat: add openclaw config validation script"
```

---

## Task 3: Create Automated Backup Script

**Files:**
- Create: `/usr/local/bin/openclaw-backup-config.sh`
- Modify: crontab (add backup job)

- [ ] **Step 1: Create the backup script**

```bash
#!/bin/bash
# /usr/local/bin/openclaw-backup-config.sh
# Creates timestamped backups of OpenCLAW config

set -euo pipefail

CONFIG_DIR="/home/desktopuser/.openclaw"
ROOT_CONFIG_DIR="/root/.openclaw"
BACKUP_DIR="$CONFIG_DIR"
TIMESTAMP=$(date +%Y-%m-%dT%H-%M-%S)

echo "=== OpenCLAW Config Backup ==="
echo "Timestamp: $TIMESTAMP"

# Backup desktopuser config
if [[ -f "$CONFIG_DIR/openclaw.json" ]]; then
    cp "$CONFIG_DIR/openclaw.json" "$BACKUP_DIR/openclaw-backup.$TIMESTAMP.json"
    echo "Backed up: $CONFIG_DIR/openclaw.json -> openclaw-backup.$TIMESTAMP.json"
fi

# Sync to root config
if [[ -f "$ROOT_CONFIG_DIR/openclaw.json" ]]; then
    cp "$ROOT_CONFIG_DIR/openclaw.json" "$BACKUP_DIR/openclaw-root-backup.$TIMESTAMP.json"
    echo "Backed up: $ROOT_CONFIG_DIR/openclaw.json -> openclaw-root-backup.$TIMESTAMP.json"
fi

# Keep only last 10 backups (rotate old ones)
cd "$BACKUP_DIR"
ls -1 openclaw-backup.*.json 2>/dev/null | tail -n +11 | xargs -r rm
ls -1 openclaw-root-backup.*.json 2>/dev/null | tail -n +11 | xargs -r rm

echo "Backup complete"
```

- [ ] **Step 2: Make executable and test**

```bash
chmod +x /usr/local/bin/openclaw-backup-config.sh
/usr/local/bin/openclaw-backup-config.sh
ls -la /home/desktopuser/.openclaw/openclaw-backup.*.json | tail -5
```

- [ ] **Step 3: Add to crontab (daily backup)**

```bash
# Add to crontab for daily backup at 3am
crontab -l | grep -v openclaw-backup || true
echo "0 3 * * * /usr/local/bin/openclaw-backup-config.sh >> /var/log/openclaw-backup.log 2>&1" | crontab -
```

- [ ] **Step 4: Commit**

```bash
git add /usr/local/bin/openclaw-backup-config.sh
git commit -m "feat: add automated openclaw config backup"
```

---

## Task 4: Create Change Request Workflow Script

**Files:**
- Create: `/usr/local/bin/openclaw-change-request.sh`

- [ ] **Step 1: Create the change request script**

```bash
#!/bin/bash
# /usr/local/bin/openclaw-change-request.sh
# Enforces governance process for config changes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="/home/desktopuser/.openclaw/openclaw.json"
ROOT_CONFIG_FILE="/root/.openclaw/openclaw.json"
LOCK_SCRIPT="$SCRIPT_DIR/openclaw-lock-config.sh"
VALIDATE_SCRIPT="$SCRIPT_DIR/openclaw-validate-config.sh"
BACKUP_SCRIPT="$SCRIPT_DIR/openclaw-backup-config.sh"

show_usage() {
    cat <<EOF
OpenCLAW Configuration Change Request

Usage: $0 [request|approve|apply|status]

Workflow:
  1. request <description>  - Create a change request (requires approval)
  2. approve <request_id>   - Approve a pending change (Milan only)
  3. apply <request_id>     - Apply an approved change
  4. status                 - Show pending requests

Governance Rules:
  - Config is LOCKED by default (read-only)
  - Any change requires: backup -> validate -> approve -> apply
  - Only Milan can approve changes
  - Emergency changes require post-hoc approval

Examples:
  $0 request "Add new Discord channel for dev-nexus"
  $0 approve cr-001
  $0 apply cr-001
EOF
    exit 1
}

do_request() {
    local description="$*"
    local request_id="cr-$(date +%Y%m%d-%H%M%S)"
    
    if [[ -z "$description" ]]; then
        echo "ERROR: Description required"
        exit 1
    fi
    
    echo "=== Change Request: $request_id ==="
    echo "Description: $description"
    echo "Requested by: $(whoami)"
    echo "Timestamp: $(date -Iseconds)"
    echo ""
    echo "NEXT STEPS:"
    echo "  1. Milan reviews the request"
    echo "  2. Milan runs: $0 approve $request_id"
    echo "  3. After approval, changes can be applied"
    echo ""
    echo "To cancel this request, delete: $CONFIG_DIR/requests/$request_id.json"
}

do_approve() {
    local request_id="$1"
    
    if [[ -z "$request_id" ]]; then
        echo "ERROR: Request ID required"
        echo "Usage: $0 approve <request_id>"
        exit 1
    fi
    
    # Verify approver is Milan
    local approver="$(whoami)"
    if [[ "$approver" != "root" && "$approver" != "desktopuser" ]]; then
        echo "ERROR: Only Milan can approve changes"
        exit 1
    fi
    
    echo "=== Approving: $request_id ==="
    echo "Approved by: $approver"
    echo "Approval timestamp: $(date -Iseconds)"
    echo ""
    echo "To apply this change:"
    echo "  $0 apply $request_id"
}

do_apply() {
    local request_id="$1"
    
    if [[ -z "$request_id" ]]; then
        echo "ERROR: Request ID required"
        echo "Usage: $0 apply <request_id>"
        exit 1
    fi
    
    echo "=== Applying Change: $request_id ==="
    
    # Step 1: Create backup
    echo "[1/5] Creating backup..."
    $BACKUP_SCRIPT
    
    # Step 2: Unlock config
    echo "[2/5] Unlocking config..."
    $LOCK_SCRIPT unlock
    
    # Step 3: Validate before changes
    echo "[3/5] Pre-change validation..."
    if ! $VALIDATE_SCRIPT; then
        echo "ERROR: Pre-validation failed. Re-locking config."
        $LOCK_SCRIPT lock
        exit 1
    fi
    
    # Step 4: User makes their changes now
    echo "[4/5] Config unlocked for modification"
    echo "Make your changes to: $CONFIG_FILE"
    echo "When done, run: $0 validate-and-lock"
    echo ""
    echo "OR run this to edit in place:"
    echo "  nano $CONFIG_FILE"
}

do_validate_and_lock() {
    echo "[5/5] Post-change validation..."
    
    if ! $VALIDATE_SCRIPT; then
        echo "ERROR: Post-validation FAILED"
        echo "Config changes are invalid. Fix errors before continuing."
        echo ""
        echo "To rollback: cp /home/desktopuser/.openclaw/openclaw-backup.*.json /home/desktopuser/.openclaw/openclaw.json"
        exit 1
    fi
    
    # Sync to root
    echo "Syncing to root config..."
    cp "$CONFIG_FILE" "$ROOT_CONFIG_FILE"
    
    # Lock it back down
    echo "Re-locking config..."
    $LOCK_SCRIPT lock
    
    echo ""
    echo "SUCCESS: Change applied and config locked"
}

do_status() {
    echo "=== OpenCLAW Config Governance Status ==="
    echo ""
    echo "Config file: $CONFIG_FILE"
    $LOCK_SCRIPT status
    echo ""
    echo "Recent backups:"
    ls -1t /home/desktopuser/.openclaw/openclaw-backup.*.json 2>/dev/null | head -5 || echo "  (none)"
}

# Main
case "${1:-status}" in
    request) shift; do_request "$@" ;;
    approve) shift; do_approve "$@" ;;
    apply) shift; do_apply "$@" ;;
    validate-and-lock) do_validate_and_lock ;;
    status) do_status ;;
    *) show_usage ;;
esac
```

- [ ] **Step 2: Make executable**

```bash
chmod +x /usr/local/bin/openclaw-change-request.sh
```

- [ ] **Step 3: Commit**

```bash
git add /usr/local/bin/openclaw-change-request.sh
git commit -m "feat: add openclaw change request governance workflow"
```

---

## Task 5: Persist API Key in Systemd Override

**Files:**
- Create: `/home/desktopuser/.config/systemd/user/openclaw-gateway.service.d/override.conf`

- [ ] **Step 1: Create systemd override directory**

```bash
mkdir -p /home/desktopuser/.config/systemd/user/openclaw-gateway.service.d
```

- [ ] **Step 2: Create override.conf with API key**

```bash
cat > /home/desktopuser/.config/systemd/user/openclaw-gateway.service.d/override.conf << 'EOF'
[Service]
# Persist environment variables across restarts
Environment=OPENROUTER_API_KEY=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
Environment=HOME=/root
Environment=XDG_RUNTIME_DIR=/run/user/0
EOF
```

- [ ] **Step 3: Reload systemd and restart**

```bash
systemctl --user daemon-reload
systemctl --user restart openclaw-gateway.service
```

- [ ] **Step 4: Verify environment is set**

```bash
systemctl --user show-environment | grep OPENROUTER
```

- [ ] **Step 5: Document this in CLAUDE.md**

Add to the repo's CLAUDE.md:
```
## OpenCLAW Config Governance

The production OpenCLAW config is LOCKED by default. Any changes require:
1. Create backup: `/usr/local/bin/openclaw-backup-config.sh`
2. Unlock: `/usr/local/bin/openclaw-lock-config.sh unlock`
3. Validate: `/usr/local/bin/openclaw-validate-config.sh`
4. Make changes
5. Validate again
6. Lock: `/usr/local/bin/openclaw-lock-config.sh lock`

API key is persisted in systemd override:
`/home/desktopuser/.config/systemd/user/openclaw-gateway.service.d/override.conf`
```

- [ ] **Step 6: Commit**

```bash
git add docs/openclaw-config-management.md  # (updated CLAUDE.md reference)
git commit -m "docs: add openclaw config governance to CLAUDE.md"
```

---

## Task 6: Document Full Governance Process

**Files:**
- Modify: `docs/openclaw-config-management.md`

- [ ] **Step 1: Update the documentation with complete governance**

Replace the content with the comprehensive governance process:

```markdown
# OpenCLAW Configuration Governance

## Overview

The OpenCLAW config (`~/.openclaw/openclaw.json`) is **LOCKED BY DEFAULT**. This prevents accidental corruption from:
- `openclaw doctor --fix` auto-migrations
- Development tasks accidentally editing the file
- System updates modifying configuration

## The Golden Rule

**NEVER edit openclaw.json directly without following the governance process.**

## Quick Reference

| Action | Command |
|--------|---------|
| Check status | `openclaw-lock-config.sh status` |
| Unlock for changes | `openclaw-lock-config.sh unlock` |
| Lock after changes | `openclaw-lock-config.sh lock` |
| Validate config | `openclaw-validate-config.sh` |
| Create backup | `openclaw-backup-config.sh` |
| Change request | `openclaw-change-request.sh request "description"` |
| Approve change | `openclaw-change-request.sh approve <id>` |

## Governance Process

### Normal Change Flow

1. **Request** - Create change request with description
   ```bash
   openclaw-change-request.sh request "Add new Discord channel"
   ```

2. **Review** - Milan reviews the request

3. **Approve** - Milan approves the change
   ```bash
   openclaw-change-request.sh approve cr-YYYYMMDD-HHMMSS
   ```

4. **Backup** - Automated backup created before any changes

5. **Unlock** - Config is temporarily unlocked
   ```bash
   openclaw-lock-config.sh unlock
   ```

6. **Validate** - Run pre-flight validation
   ```bash
   openclaw-validate-config.sh
   ```

7. **Edit** - Make the required changes
   ```bash
   nano /home/desktopuser/.openclaw/openclaw.json
   ```

8. **Validate Again** - Ensure changes are valid
   ```bash
   openclaw-validate-config.sh
   ```

9. **Sync to Root** - Copy to root's config (required)
   ```bash
   cp /home/desktopuser/.openclaw/openclaw.json /root/.openclaw/openclaw.json
   ```

10. **Lock** - Re-lock the config
    ```bash
    openclaw-lock-config.sh lock
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
# Edit the override
nano /home/desktopuser/.config/systemd/user/openclaw-gateway.service.d/override.conf

# Reload and restart
systemctl --user daemon-reload
systemctl --user restart openclaw-gateway.service
```

## If Config Breaks

1. **Check the lock status**
   ```bash
   openclaw-lock-config.sh status
   ```

2. **Restore from backup**
   ```bash
   ls -lt /home/desktopuser/.openclaw/openclaw-backup.*.json | head -1
   cp /home/desktopuser/.openclaw/openclaw-backup.2026-04-17T17-00-00.json /home/desktopuser/.openclaw/openclaw.json
   ```

3. **Validate**
   ```bash
   openclaw-validate-config.sh
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

---

**Last Updated:** 2026-04-17
```

- [ ] **Step 2: Commit**

```bash
git add docs/openclaw-config-management.md
git commit -m "docs: add complete openclaw config governance process"
```

---

## Task 7: Deploy Scripts to Production VM

**Files:**
- Modify: deployment scripts (if applicable)

- [ ] **Step 1: Copy scripts to production**

```bash
scp /usr/local/bin/openclaw-lock-config.sh prod:/usr/local/bin/
scp /usr/local/bin/openclaw-validate-config.sh prod:/usr/local/bin/
scp /usr/local/bin/openclaw-backup-config.sh prod:/usr/local/bin/
scp /usr/local/bin/openclaw-change-request.sh prod:/usr/local/bin/

ssh prod "chmod +x /usr/local/bin/openclaw-*.sh"
```

- [ ] **Step 2: Copy systemd override**

```bash
scp /home/desktopuser/.config/systemd/user/openclaw-gateway.service.d/override.conf prod:/home/desktopuser/.config/systemd/user/openclaw-gateway.service.d/
```

- [ ] **Step 3: Reload and restart**

```bash
ssh prod "systemctl --user daemon-reload && systemctl --user restart openclaw-gateway.service"
```

- [ ] **Step 4: Verify governance is active**

```bash
ssh prod "/usr/local/bin/openclaw-lock-config.sh status"
ssh prod "/usr/local/bin/openclaw-validate-config.sh"
```

- [ ] **Step 5: Commit deployment changes**

```bash
git add -A
git commit -m "feat: deploy openclaw governance to production"
```

---

## Summary

This governance plan creates:

1. **Lockdown** - Config file is read-only (444) by default
2. **Validation** - Pre-flight checks catch errors before restart
3. **Backup** - Automated daily backups + manual backup before changes
4. **Approval workflow** - Change request process with Milan approval
5. **Persistence** - API key stored in systemd override, survives restarts
6. **Documentation** - Complete process in openclaw-config-management.md

The config can only be modified through the explicit unlock → validate → edit → validate → lock cycle, preventing silent corruption from any automated tool.