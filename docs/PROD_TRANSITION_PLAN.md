# OpenCLAW Prod to Test Config Transition Plan

## Overview
Transition the prod OpenCLAW configuration from the single-agent "main" structure to the per-repo agent routing structure used in test VM.

## Current Prod Config Structure
- Single agent: `main` 
- Default model: `openrouter/anthropic/claude-haiku-4-5`
- 17 Discord channels mapped to single agent via accountId binding
- Single binding: agentId "main" → accountId 1491445641581301760
- 3 models: MiniMax-M2.7, Claude Haiku, Claude Sonnet

## Channel Mapping - CRITICAL PATH

### Current Prod Channel List (all handled by `main` agent)
| Channel ID | Channel Name | Current Handler |
|------------|--------------|-----------------|
| 1485047827737612362 | general | main |
| 1487986866832805888 | bond-nexus | main |
| 1488016789110526104 | dev-nexus | main |
| 1488028570977828974 | elastica | main |
| 1488329838606549174 | globalbitings | main |
| 1488649282792980550 | dev-nexus-frontend | main |
| 1489035741341155408 | (unknown) | main |
| 1489446562655637605 | (unknown) | main |
| 1489451199185817630 | (unknown) | main |
| 1491175562348331209 | (unknown) | main |
| 1491445641581301760 | (unknown) | main |
| 1492017314693124106 | (unknown) | main |
| 1492701850217218268 | linux-desktop-seed | main → **migrate to linux-desktop-seed** |
| 1493278190540427395 | (unknown) | main |

### Migration Strategy
The key insight is that **the existing binding uses `accountId`** which means any message from that user (accountId) goes to the main agent. To add per-repo routing:

1. **Keep existing main binding intact** - This ensures all existing channels continue working
2. **Add new route binding** - The new `linux-desktop-seed` agent gets explicit channel routing
3. **Route precedence** - Explicit `type: route` with `peer.kind: channel` takes precedence over accountId binding

This is non-disruptive: existing channels still route to `main`, only channel 1492701850217218268 gets a new handler.

## Target Test Config Structure
- Two agents: `main` + `linux-desktop-seed` (per-repo)
- Default model: `openrouter/minimax/MiniMax-M2.7`
- Per-channel routing: linux-desktop-seed agent → channel 1492701850217218268
- Agent-specific workspace: `/home/desktopuser/Projects/linux-desktop-seed`
- 2 models: MiniMax-M2.7, Claude Haiku

## Transition Steps

### Phase 1: Pre-flight Checklist
- [ ] Backup current prod config: `cp /home/desktopuser/.openclaw/openclaw.json /home/desktopuser/.openclaw/openclaw.json.backup-prod-legacy`
- [ ] Verify test config is stable on test VM
- [ ] Note current prod Discord channel bindings

### Phase 2: Update Prod Config File
1. **Add browser config** (currently missing):
   ```json
   "browser": { "noSandbox": true }
   ```

2. **Update gateway config**:
   ```json
   "gateway": {
     "port": 18789,
     "mode": "local",
     "bind": "loopback",
     "controlUi": { "allowInsecureAuth": false },
     "auth": { "mode": "token", "token": "CURRENT_TOKEN" }
   }
   ```

3. **Update agents section**:
   ```json
   "agents": {
     "list": [
       { "id": "main" },
       { "id": "linux-desktop-seed", "name": "linux-desktop-seed", "workspace": "/home/desktopuser/Projects/linux-desktop-seed", "agentDir": "/home/desktopuser/.openclaw/agents/linux-desktop-seed/agent" }
     ],
     "defaults": {
       "model": "openrouter/minimax/MiniMax-M2.7",
       "thinkingDefault": "minimal",
       "compaction": {
         "mode": "safeguard",
         "reserveTokens": 15000,
         "keepRecentTokens": 4000,
         "reserveTokensFloor": 20000,
         "maxHistoryShare": 0.1,
         "model": "openrouter/anthropic/claude-haiku-4-5"
       }
     }
   }
   ```

4. **CRITICAL: Migrate existing channel bindings** - This is the key change:
   
   **Current prod binding** (single agent for all channels):
   ```json
   "bindings": [
     {
       "agentId": "main",
       "match": {
         "channel": "discord",
         "accountId": "1491445641581301760"
       }
     }
   ]
   ```
   
   **Target bindings** (main handles existing channels, linux-desktop-seed handles #linux-desktop-seed):
   ```json
   "bindings": [
     {
       "agentId": "main",
       "match": {
         "channel": "discord",
         "accountId": "1491445641581301760"
       }
     },
     {
       "type": "route",
       "agentId": "linux-desktop-seed",
       "match": {
         "channel": "discord",
         "peer": { "kind": "channel", "id": "1492701850217218268" }
       }
     }
   ]
   ```

5. **Add commands config**:
   ```json
   "commands": {
     "native": "auto",
     "nativeSkills": "auto",
     "restart": true,
     "ownerDisplay": "raw"
   }
   ```

6. **Update models** (simplify):
   - Keep: MiniMax-M2.7, Claude Haiku
   - Remove: Claude Sonnet (optional, per requirements)

### Phase 2b: Update Channels Configuration

The `channels.discord.guilds` section lists all allowed channels. For the migration:

**Current prod channels** (all under guild 1485047825967480862):
```json
"channels": {
  "1485047827737612362": {},
  "1487986866832805888": {},
  "1488016789110526104": {},
  "1488028570977828974": {},
  "1488329838606549174": {},
  "1488649282792980550": {},
  "1489035741341155408": {},
  "1489446562655637605": {},
  "1489451199185817630": {},
  "1491175562348331209": {},
  "1491445641581301760": {},
  "1492017314693124106": {},
  "1492701850217218268": {},    // <-- This is #linux-desktop-seed
  "1493278190540427395": {}
}
```

**Add per-channel requireMention for linux-desktop-seed channel**:
```json
"channels": {
  "1485047827737612362": {},
  "1487986866832805888": {},
  "1488016789110526104": {},
  "1488028570977828974": {},
  "1488329838606549174": {},
  "1488649282792980550": {},
  "1489035741341155408": {},
  "1489446562655637605": {},
  "1489451199185817630": {},
  "1491175562348331209": {},
  "1491445641581301760": {},
  "1492017314693124106": {},
  "1492701850217218268": {
    "requireMention": false   // <-- Add this for #linux-desktop-seed
  },
  "1493278190540427395": {}
}
```

This mirrors the test config exactly - the channel 1492701850217218268 has `requireMention: false` so the linux-desktop-seed agent responds without needing @mention.

### Phase 3: Create Agent Directory Structure
On prod VM:
```bash
# Create agent directory
mkdir -p /home/desktopuser/.openclaw/agents/linux-desktop-seed/agent

# Create agent config.json
cat > /home/desktopuser/.openclaw/agents/linux-desktop-seed/agent/config.json << 'EOF'
{
  "defaults": {
    "model": "minimax/MiniMax-M2.7",
    "thinkingDefault": "minimal",
    "compaction": {
      "mode": "safeguard",
      "reserveTokens": 15000,
      "keepRecentTokens": 4000,
      "reserveTokensFloor": 20000,
      "maxHistoryShare": 0.1,
      "model": "anthropic/claude-haiku-4-5"
    }
  },
  "workspace": {
    "path": "/home/desktopuser/Projects/linux-desktop-seed",
    "repoUrl": "https://github.com/patelmm79/linux-desktop-seed.git"
  }
}
EOF

# Set ownership
chown -R desktopuser:desktopuser /home/desktopuser/.openclaw/agents/linux-desktop-seed

# Create workspace directory
mkdir -p /home/desktopuser/Projects/linux-desktop-seed
chown desktopuser:desktopuser /home/desktopuser/Projects
```

### Phase 4: Add Git Remote to Workspace
```bash
cd /home/desktopuser/Projects/linux-desktop-seed
git remote add origin https://github.com/patelmm79/linux-desktop-seed.git
git config --global --add safe.directory /home/desktopuser/Projects/linux-desktop-seed
```

### Phase 5: Restart Gateway
```bash
# Kill existing gateway
pkill -f 'openclaw gateway' || true

# Start as desktopuser
sudo -u desktopuser openclaw gateway > /tmp/openclaw-gateway.log 2>&1 &
```

### Phase 6: Verify
- [ ] Gateway starts without errors
- [ ] Discord connected
- [ ] Test message to channel 1492701850217218268 routes to linux-desktop-seed agent
- [ ] Agent responds with its config (repo URL, local path, model)

### Phase 7: Channel Migration Verification

**Critical: Verify existing channels still work**
```bash
# Check gateway logs for any routing errors
tail -50 /home/desktopuser/.openclaw/logs/gateway.log | grep -i "route\|bind\|channel"

# Test that existing channels still route to main agent
# Send test message to #general (1485047827737612362) - should go to main

# Verify new channel routing
# Send test message to #linux-desktop-seed (1492701850217218268) - should go to linux-desktop-seed
```

**Expected behavior after migration**:
| Channel | Expected Handler | How to Verify |
|---------|------------------|---------------|
| 1485047827737612362 (general) | main agent | Check logs - should see "main" in routing |
| 1491445641581301760 | main agent | Check logs - should see "main" in routing |
| 1492701850217218268 (linux-desktop-seed) | linux-desktop-seed agent | Check logs - should see "linux-desktop-seed" in routing |

**What if existing channels break?**
- Restore backup: `cp /home/desktopuser/.openclaw/openclaw.json.backup-prod-legacy /home/desktopuser/.openclaw/openclaw.json`
- Restart gateway
- The backup keeps the original single-binding structure

### Phase 8: Post-Migration (Optional - After Verification)
Once verified, you can optionally:
- Add more per-repo agents (e.g., `bond-nexus` agent for bond-nexus repo)
- Migrate more channels to dedicated agents
- Remove the main agent entirely if all channels have dedicated agents

## Rollback Procedure
If issues occur:
```bash
# Restore backup
cp /home/desktopuser/.openclaw/openclaw.json.backup-prod-legacy /home/desktopuser/.openclaw/openclaw.json

# Restart gateway
pkill -f 'openclaw gateway' || true
sudo -u desktopuser openclaw gateway &
```

## Key Differences Summary

| Aspect | Prod Current | Prod Target |
|--------|--------------|-------------|
| Agents | 1 (main) | 2 (main + linux-desktop-seed) |
| Default model | claude-haiku-4-5 | MiniMax-M2.7 |
| Compaction | none | safeguard mode |
| Commands | missing | present |
| Browser | missing | noSandbox: true |
| Gateway port | 18789 | 18789 (explicit) |
| Bindings | 1 (main→accountId) | 2 (main→accountId + route→channel) |
| Channel requireMention | not set | set for 1492701850217218268 |

## Migration Decision Points

### Option A: Non-Disruptive Migration (Recommended)
- Keep existing main agent binding intact
- Add linux-desktop-seed as second agent
- Only #linux-desktop-seed channel changes handler
- Risk: **LOW** - existing channels unaffected

### Option B: Full Migration
- Remove main→accountId binding entirely
- Create explicit route for each of 17 channels
- Each channel gets specific agent assignment
- Risk: **HIGH** - all channels change behavior

**Recommendation**: Start with Option A (non-disruptive) to validate, then optionally move to Option B.

## Rollback Decision Tree

```
                    ┌─────────────────────┐
                    │ Migration Issues?   │
                    └──────────┬──────────┘
                               │
              ┌────────────────┼────────────────┐
              ▼                                 ▼
     ┌─────────────────┐               ┌─────────────────┐
     │ Existing channel│               │ New channel     │
     │ broken?         │               │ broken?         │
     └────────┬────────┘               └────────┬────────┘
              │                                 │
     ┌────────┴────────┐               ┌────────┴────────┐
     ▼                 ▼               ▼                 ▼
   YES → ROLLBACK   NO → Continue   YES → Check binding  NO → Continue
     (restore       (migration      (channel may need    (success!)
      backup)        complete)       explicit route)
```

## Notes
- Prod will maintain `main` agent for general channels (1491445641581301760, etc.)
- New `linux-desktop-seed` agent handles only #linux-desktop-seed channel (1492701850217218268)
- This mirrors the test VM setup exactly
- Both configs can coexist - prod handles more channels, test is proof-of-concept
- **The key difference from prod current**: Adding per-channel routing without disrupting existing channel handlers