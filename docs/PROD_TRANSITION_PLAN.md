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

### Current Prod Channel List
| Channel ID | Channel Name | GitHub Owner | Repo | Current Handler |
|------------|--------------|--------------|------|-----------------|
| 1485047827737612362 | general | patelmm79 | — | main (no repo) |
| 1487986866832805888 | bond-nexus | DarojaAI | — | main → migrate |
| 1488016789110526104 | dev-nexus | DarojaAI | — | main → migrate |
| 1488028570977828974 | elastica | patelmm79 | — | main → migrate |
| 1488329838606549174 | globalbitings | patelmm79 | — | main → migrate |
| 1488649282792980550 | dev-nexus-frontend | DarojaAI | — | main → migrate |
| 1489035741341155408 | resume-customizer | patelmm79 | patelmm79/resume-customizer | resume-customizer ✅ MIGRATED |
| 1489446562655637605 | dynamic-worlock | patelmm79 | — | main → migrate |
| 1489451199185817630 | rag-research-tool | DarojaAI | — | main → migrate |
| 1491175562348331209 | dev-nexus-action-agent | DarojaAI | — | main → migrate |
| 1491445641581301760 | intelligent-feed | patelmm79 | — | main → migrate |
| 1492017314693124106 | research-orchestrator | DarojaAI | — | main → migrate |
| 1492701850217218268 | linux-desktop-seed | patelmm79 | patelmm79/linux-desktop-seed | linux-desktop-seed ✅ MIGRATED |
| 1493278190540427395 | test-agent | patelmm79 | — | main (no repo) |

### Migration Strategy
The key insight is that **the existing binding uses `accountId`** which means any message from that user (accountId) goes to the main agent. To add per-repo routing:

1. **Keep existing main binding intact** - This ensures all existing channels continue working
2. **Add new route binding** - The new `linux-desktop-seed` agent gets explicit channel routing
3. **Route precedence** - Explicit `type: route` with `peer.kind: channel` takes precedence over accountId binding

This is non-disruptive: existing channels still route to `main`, only channel 1492701850217218268 gets a new handler.

## Target Test Config Structure
- Three agents: `main` + `linux-desktop-seed` + `resume-customizer` (per-repo)
- Default model: `openrouter/minimax/MiniMax-M2.7`
- Per-channel routing:
  - linux-desktop-seed agent → channel 1492701850217218268
  - resume-customizer agent → channel 1489035741341155408 ✅ MIGRATED
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
   
   **Target bindings** (route FIRST, then main):
   ```json
   "bindings": [
     {
       "type": "route",
       "agentId": "linux-desktop-seed",
       "match": {
         "channel": "discord",
         "peer": { "kind": "channel", "id": "1492701850217218268" }
       }
     },
     {
       "agentId": "main",
       "match": {
         "channel": "discord",
         "accountId": "1491445641581301760"
       }
     }
   ]
   ```

   **CRITICAL: Route binding must come FIRST** - Explicit `type: route` with `peer.kind: channel` must be placed before the accountId binding. The gateway evaluates bindings in order and uses the first match.

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

### Phase 3: Create Agent Directory Structure with Memory
On prod VM:
```bash
# Create agent directory with ALL required subdirectories
mkdir -p /home/desktopuser/.openclaw/agents/linux-desktop-seed/agent
mkdir -p /home/desktopuser/.openclaw/agents/linux-desktop-seed/agent/memory    # ← CRITICAL: per-agent memory
mkdir -p /home/desktopuser/.openclaw/agents/linux-desktop-seed/sessions
mkdir -p /home/desktopuser/.openclaw/agents/linux-desktop-seed/mcp-servers

# Copy models.json from main agent (required for model availability)
cp /home/desktopuser/.openclaw/agents/main/agent/models.json \
   /home/desktopuser/.openclaw/agents/linux-desktop-seed/agent/models.json

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

# Copy auth profiles from main (or create repo-specific)
cp /home/desktopuser/.openclaw/agents/main/agent/auth-profiles.json \
   /home/desktopuser/.openclaw/agents/linux-desktop-seed/agent/auth-profiles.json 2>/dev/null || true

# Set ownership - CRITICAL for security
chown -R desktopuser:desktopuser /home/desktopuser/.openclaw/agents/linux-desktop-seed
chmod -R 700 /home/desktopuser/.openclaw/agents/linux-desktop-seed/agent/memory  # ← private memory

# Create workspace directory
mkdir -p /home/desktopuser/Projects/linux-desktop-seed
chown desktopuser:desktopuser /home/desktopuser/Projects
```

**Directory Structure After Setup:**
```
/home/desktopuser/.openclaw/agents/linux-desktop-seed/
├── agent/
│   ├── config.json        # agent-specific settings (model, compaction, workspace)
│   ├── models.json        # copied from main
│   ├── auth-profiles.json # copied from main (or repo-specific key)
│   ├── memory/            # ← ISOLATED PER-AGENT MEMORY (currently empty)
│   └── sessions/          # ← ISOLATED PER-AGENT SESSIONS
├── mcp-servers/
└── (other runtime dirs)
```

**Key Points:**
- Each agent's `memory/` directory is completely isolated
- The linux-desktop-seed agent will ONLY read/write to its own memory/
- This ensures one repo's conversation history doesn't leak to another repo
- Memory is stored as: `agents/{agent-id}/agent/memory/`

### Phase 3b: Verify Memory Isolation (Before Gateway Start)
```bash
# Verify memory directory exists and is empty BEFORE first use
ls -la /home/desktopuser/.openclaw/agents/linux-desktop-seed/agent/memory/
# Expected: empty (only . and ..)

# Verify ownership is correct
stat -c "%U:%G %a" /home/desktopuser/.openclaw/agents/linux-desktop-seed/agent/memory
# Expected: desktopuser:desktopuser 700
```

### Phase 4: Add Git Remote to Workspace
```bash
cd /home/desktopuser/Projects/linux-desktop-seed
git remote add origin https://github.com/patelmm79/linux-desktop-seed.git
git config --global --add safe.directory /home/desktopuser/Projects/linux-desktop-seed
```

### Phase 5: Restart Gateway
```bash
# CRITICAL: Remove old log file if root created it (desktopuser can't write to it)
sudo rm -f /tmp/openclaw-gateway.log

# Kill existing gateway
pkill -f 'openclaw gateway' || true

# Start as desktopuser (must run as desktopuser, not root)
sudo -u desktopuser bash -c "cd /home/desktopuser && nohup openclaw gateway > /tmp/openclaw-gateway.log 2>&1 &"

# Verify it's running
sleep 3 && ps aux | grep openclaw-gateway | grep -v grep

# If it fails with "Missing config", use --allow-unconfigured flag
# sudo -u desktopuser bash -c "cd /home/desktopuser && nohup openclaw gateway --allow-unconfigured > /tmp/openclaw-gateway.log 2>&1 &"
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

### Phase 9: Test ONE Repository with Rollback Plan

**Objective:** Validate the new per-repo agent structure with exactly ONE channel before committing to full migration.

#### Step 9.1: Verify Single Channel Works
```bash
# Send test message to #linux-desktop-seed channel (1492701850217218268)
# Format: "Hello, what repo am I working with?"
```

**Expected response should include:**
- Repo URL: `https://github.com/patelmm79/linux-desktop-seed.git`
- Local path: `/home/desktopuser/Projects/linux-desktop-seed`
- Model: `MiniMax-M2.7`

#### Step 9.2: Verify Memory Isolation
```bash
# Check that linux-desktop-seed agent created its own memory files
ls -la /home/desktopuser/.openclaw/agents/linux-desktop-seed/agent/memory/

# Verify main agent memory is SEPARATE
ls -la /home/desktopuser/.openclaw/agents/main/agent/memory/
```

**Expected:** Each agent has its own memory/ directory with separate files.

#### Step 9.3: Verify Existing Channels Unaffected
```bash
# Send test message to #general (1485047827737612362)
# Should still route to main agent
```

**Expected:** Existing channels continue working with main agent.

#### Step 9.4: IF ANYTHING FAILS → ROLLBACK
```bash
# IMMEDIATE ROLLBACK - restore backup
pkill -f 'openclaw gateway' || true

# Restore original config
cp /home/desktopuser/.openclaw/openclaw.json.backup-prod-legacy /home/desktopuser/.openclaw/openclaw.json

# Remove the new agent directory (optional cleanup)
rm -rf /home/desktopuser/.openclaw/agents/linux-desktop-seed

# Restart gateway with original config
sudo -u desktopuser openclaw gateway > /tmp/openclaw-gateway.log 2>&1 &

# Wait 30 seconds, check logs
sleep 30
tail -20 /home/desktopuser/.openclaw/logs/gateway.log
```

**Rollback Success Criteria:**
- [ ] Gateway starts without errors
- [ ] All 17 channels route to main agent
- [ ] No mention of "linux-desktop-seed" in logs
- [ ] Prod behavior identical to pre-migration

#### Step 9.5: IF SUCCESSFUL → Continue or Expand
Only after Phase 9 is fully validated:
- [ ] New channel routes correctly to linux-desktop-seed agent
- [ ] Agent responds with correct repo info
- [ ] Memory files created in agent-specific directory
- [ ] Existing channels still work with main agent

**Then you can:**
- Continue to Phase 10 (add more agents)
- Or leave as single-agent-test and monitor for 24-48 hours

### Phase 10: Expand to More Repos (Optional)
After successful test, add more per-repo agents:
```bash
# Example: Add bond-nexus agent
mkdir -p /home/desktopuser/.openclaw/agents/bond-nexus/agent/memory
mkdir -p /home/desktopuser/.openclaw/agents/bond-nexus/sessions
# ... copy config, update bindings, restart gateway
```

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
| Agents | 1 (main) | 3 (main + linux-desktop-seed + resume-customizer) |
| Default model | claude-haiku-4-5 | MiniMax-M2.7 |
| Compaction | none | safeguard mode |
| Commands | missing | present |
| Browser | missing | noSandbox: true |
| Gateway port | 18789 | 18789 (explicit) |
| Bindings | 1 (main→accountId) | 3 (main→accountId + 2 route→channel) |
| Channel requireMention | not set | set for 1489035741341155408, 1492701850217218268 |

## Migration Decision Points

### Option A: Non-Disruptive Migration (Recommended)
- Keep existing main agent binding intact
- Add linux-desktop-seed and resume-customizer as additional agents
- Only specific channels change handler (not all 17)
- Risk: **LOW** - existing channels unaffected
- **Status:** ✅ 2 channels migrated (1492701850217218268, 1489035741341155408)

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
- New `resume-customizer` agent handles channel 1489035741341155408 (MIGRATED ✅)
- New `linux-desktop-seed` agent handles only #linux-desktop-seed channel (1492701850217218268)
- This mirrors the test VM setup exactly
- Both configs can coexist - prod handles more channels, test is proof-of-concept
- **The key difference from prod current**: Adding per-channel routing without disrupting existing channel handlers