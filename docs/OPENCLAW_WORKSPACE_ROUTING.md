# OpenCLAW Workspace Routing Setup

This document describes how to configure OpenCLAW to route Discord channels to specific repo workspaces, enabling a single OpenCLAW instance to handle multiple repos without multiple VS Code instances.

## Overview

- **Problem:** Multiple repos require multiple VS Code instances (high memory/CPU)
- **Solution:** Single VS Code with workspace folders + OpenCLAW bindings that route each Discord channel to its corresponding repo workspace
- **Result:** 1 VS Code instance instead of N, all channels still work independently

## Architecture

```
Discord (1 bot)
    ├── #channel-one   →  /home/user/Projects/repo-one
    ├── #channel-two   →  /home/user/Projects/repo-two
    └── ... (per channel)
```

OpenCLAW routes messages from each channel to an isolated session with the correct workspace.

## Finding Channel IDs

Channel IDs are Discord snowflakes. To find them:

1. Enable Developer Mode: Discord → Settings → Advanced → Developer Mode → ON
2. Right-click channel → Copy Channel ID
3. Or open Discord in browser and check the URL:
   ```
   https://discord.com/channels/GUILD_ID/CHANNEL_ID
   ```

## Finding Repo Paths

```bash
ssh <host> "find /home -maxdepth 3 -type d -name '.git' 2>/dev/null"
```

## Configuration

### Step 1: Map Channel IDs to Repos

Create a mapping of your Discord channel IDs to repo paths:

| Channel ID | Channel Name | Repo Path |
|------------|-------------|-----------|
| CHANNEL_ID_1 | channel-one | /home/user/Projects/repo-one |
| CHANNEL_ID_2 | channel-two | /home/user/Projects/repo-two |
| CHANNEL_ID_N | channel-n | /home/user/Projects/repo-n |

### Step 2: Create Bindings

Add bindings to `~/.openclaw/openclaw.json`:

```json
{
  "bindings": [
    {
      "type": "route",
      "agentId": "main",
      "match": {
        "channel": "discord",
        "accountId": "CHANNEL_ID_1"
      },
      "workspace": "/home/user/Projects/repo-one",
      "workspaceName": "repo-one"
    },
    {
      "type": "route",
      "agentId": "main",
      "match": {
        "channel": "discord",
        "accountId": "CHANNEL_ID_2"
      },
      "workspace": "/home/user/Projects/repo-two",
      "workspaceName": "repo-two"
    }
  ]
}
```

### Step 3: Restart OpenCLAW

```bash
openclaw daemon restart
```

## VS Code Workspace Setup

### Create Workspace File

```json
{
  "folders": [
    { "path": "../repo-one" },
    { "path": "../repo-two" },
    { "path": "../repo-n" }
  ],
  "settings": {}
}
```

Save as `.code-workspace` file, e.g., `projects.code-workspace`.

### Open in VS Code

```bash
code /path/to/projects.code-workspace
```

### Switch Between Projects

- Use VS Code sidebar to switch folders
- Or use `/project <name>` command if Claude Code is connected

## Finding Existing Channel Mappings

If channel IDs are already stored somewhere in OpenCLAW:

```bash
# From sessions.json
grep -o 'discord:GUILD_ID#CHANNEL_NAME' ~/.openclaw/agents/main/sessions/sessions.json | sort -u

# From cron jobs
cat ~/.openclaw/cron/jobs.json | jq '.jobs[] | .sessionKey'

# From all JSON files
find /home -name '*.json' -exec grep -l '1[0-9]\{16,19\}' {} \; 2>/dev/null
```

## Troubleshooting

### Check Active Sessions

```bash
ls -la ~/.openclaw/agents/main/sessions/
```

### Check Which Workspace a Session Uses

```bash
cat ~/.openclaw/agents/main/sessions/<session-id>.jsonl | head | jq '.cwd'
```

### Verify Bindings

```bash
cat ~/.openclaw/openclaw.json | jq '.bindings'
```

### Check Logs

```bash
tail -f ~/.openclaw/logs/*.log
```

## Memory Savings

| Setup | VS Code Instances | Approx. Memory |
|-------|------------------|----------------|
| Before (per-repo) | N | N × 2-3 GB |
| After (workspace) | 1 | 2-3 GB |

Savings: ~85% memory reduction.
