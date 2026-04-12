# OpenCLAW Context Management Troubleshooting Log

**OpenCLAW Version:** v2026.3.28 (MiniMax compatible)
**Last Updated:** 2026-04-09
**Purpose:** Document context management issues and fixes for future reference

---

## Errors Encountered

### Error 1: Compaction Failed (233k tokens)
```
⚙️ Compaction failed: Summarization failed: 400 
This endpoint's maximum context length is 204800 tokens. 
However, you requested about 233412 tokens (169412 of text input, 64000 in the output).
Please reduce the length of either one, or use the context-compression plugin.
```

**Root Cause:** High token reserves (140k-200k) consumed all headroom. When compaction tried to run, there wasn't enough free space to perform compression. The system couldn't compress because it was already too full.

### Error 2: Context Limit Exceeded
```
Context limit exceeded. I've reset our conversation to start fresh - please try again.
To prevent this, increase your compaction buffer by setting agents.defaults.compaction.reserveTokensFloor to 20000 or higher in your config.
```

**Root Cause:** Compaction couldn't run due to Error 1, hitting the hard context limit.

### Error 3: Cost Issue
**Symptom:** Regular requests sending 80k-100k+ tokens
**Root Cause:** `maxHistoryShare: 0.3` (30%) allowed too much history retention

---

## Configuration Changes Applied

### Initial (Problematic) Settings
```json
{
  "compaction": {
    "reserveTokens": 140000,
    "reserveTokensFloor": 100000,
    "maxHistoryShare": 0.3,
    "keepRecentTokens": 8000
  }
}
```

### Final (Fixed) Settings
```json
{
  "compaction": {
    "mode": "default",
    "reserveTokens": 20000,
    "reserveTokensFloor": 20000,
    "maxHistoryShare": 0.03,
    "keepRecentTokens": 4000
  }
}
```

> **Note (2026-04-09):** Further reduced `maxHistoryShare` from 0.05 to 0.03 to prevent repeated compaction failures. This gives even more working room for compaction while still retaining context.

---

## Key Insights

1. **Higher reserves caused the problem, not solved it.** The error message "increase buffer" was misleading for this case. High reserves (140k-200k) consumed the headroom needed for compression to work.

2. **Compaction needs free space to run.** Think of reserves as "working room" for compression, not as a safety buffer.

3. **The tradeoff:**
   - Too little reserve → context reset (no buffer)
   - Too much reserve → compaction fails (no working room)
   - 20k reserve on 1M context = 2% = plenty of buffer AND working room

4. **maxHistoryShare controls cost.** 30% (300k) was too much. 10% (100k) is the cap.

---

## Testing Results

| Metric | Before | After |
|--------|--------|-------|
| Compaction failures | Yes | No |
| Context resets | Yes | No |
| Tokens per request | 80-100k | 20-40k average |
| Max history | 300k | 100k |

---

## Future Troubleshooting

### If context resets happen again:
- Increase reserveTokens by 5k-10k chunks
- Try: reserveTokens: 25000, reserveTokensFloor: 25000

### If compaction fails again:
- Reduce reserveTokens (not increase)
- The error message is misleading - more reserves = worse problem

### If cost is still too high:
- Lower maxHistoryShare: 0.05 (5% = 50k max)
- Or lower keepRecentTokens: 2000

### To verify running config on VM:
```bash
ssh hetzner "jq '.agents.defaults.compaction' ~/.openclaw/openclaw.json"
```

### To update VM config:
```bash
ssh hetzner "jq '.agents.defaults.compaction = {\"mode\": \"default\", \"reserveTokens\": 20000, \"reserveTokensFloor\": 20000, \"maxHistoryShare\": 0.03, \"keepRecentTokens\": 4000}' ~/.openclaw/openclaw.json > /tmp/openclaw.json.new && mv /tmp/openclaw.json.new ~/.openclaw/openclaw.json"
```

---

## Related Files

- `config/openclaw-defaults.json` - Repository defaults (should match working VM config)
- `~/.openclaw/openclaw.json` - Running config on VM (hetzner)

---

## Discord Integration Issues (2026-04-08)

### Problem
Discord messages to intelligent-feed channel (1491445641581301760) not being received/processed by OpenCLAW gateway.

### Errors Encountered

1. **Config validation failures**
   - Minimal configs kept failing validation
   - Missing required fields: `models.providers.openrouter.baseUrl`, `apiKey`, `models`
   - "bindings.0: Invalid input"

2. **Root config conflict**
   - Running `openclaw` commands as root created `/root/.openclaw/openclaw.json`
   - Gateway restart checked root's config, not desktopuser's
   - Root config had invalid format causing all restarts to fail

3. **Gateway status misleading**
   - `openclaw gateway status` showed "stopped" even when running
   - RPC probe failed but HTTP server was responding on port 18789
   - Systemd service kept restarting/terminating gateway

### Solution Applied

1. Removed root config: `rm /root/.openclaw/openclaw.json`
2. Restored working config from April 2 backup (`openclaw.json.bak.4`)
3. Updated Discord token to current valid token
4. Added bindings for channel routing:
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
5. Disabled systemd service and ran gateway directly

### deploy-desktop.sh Fix
Updated wrapper to use desktopuser's config path instead of `$HOME`:
```bash
# Before (broken)
OPENCLAW_CONFIG="$HOME/.openclaw/openclaw.json"

# After (fixed)
OPENCLAW_CONFIG="/home/desktopuser/.openclaw/openclaw.json"
```

Also fixed `setup_openclaw_config()` function to use:
```bash
OPENCLAW_CONFIG_DIR="/home/desktopuser/.openclaw"
```

### Key Takeaways

1. **Never run openclaw commands as root** - Creates conflicting config
2. **Restore from known-working backup** - Config format validation is strict; old working config is safer than minimal new ones
3. **Verify gateway is actually running** - Check port 18789 response, not just `gateway status`
4. **Systemd can cause instability** - Running gateway directly without systemd service is more reliable

### Working Config Structure
```json
{
  "meta": { "lastTouchedVersion": "2026.3.28" },
  "channels": {
    "discord": {
      "enabled": true,
      "token": "MTQ4...",
      "groupPolicy": "allowlist",
      "allowFrom": ["user:1162240440322502656"],
      "guilds": {
        "1485047825967480862": {
          "requireMention": false,
          "users": ["1162240440322502656"]
        }
      }
    }
  },
  "bindings": [
    {
      "agentId": "main",
      "match": {
        "channel": "discord",
        "accountId": "1491445641581301760"
      }
    }
  ],
  "agents": {
    "defaults": {
      "model": { "primary": "openrouter/minimax/minimax-m2.7" }
    }
  },
  "gateway": {
    "port": 18789,
    "mode": "local",
    "auth": { "mode": "token", "token": "..." }
  }
}
```