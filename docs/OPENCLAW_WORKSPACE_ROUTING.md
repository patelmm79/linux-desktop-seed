# OpenCLAW Workspace Routing Setup

This document describes how to configure OpenCLAW to route Discord channels to specific repo workspaces, enabling a single OpenCLAW instance to handle multiple repos without multiple VS Code instances.

## Overview

- **Problem:** Multiple repos require multiple VS Code instances (high memory/CPU)
- **Solution:** Single VS Code with workspace folders + OpenCLAW bindings that route each Discord channel to its corresponding repo workspace
- **Result:** 1 VS Code instance instead of N, all channels still work independently

## Architecture

```
Discord (1 bot)
    ├── #bond-nexus        →  /home/desktopuser/GithubProjects/bond-nexus
    ├── #resume-customizer →  /home/desktopuser/GithubProjects/resume-customizer
    ├── #elastica          →  /home/desktopuser/GithubProjects/elastica
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

| Channel ID | Channel Name | Repo Path |
|------------|-------------|-----------|
| 1487986866832805888 | bond-nexus | /home/desktopuser/GithubProjects/bond-nexus |
| 1489035741341155408 | resume-customizer | /home/desktopuser/GithubProjects/resume-customizer |
| 1489446562655637605 | dynamic-worlock | /home/desktopuser/GithubProjects/dynamic-worlock |
| 1488028570977828974 | elastica | /home/desktopuser/GithubProjects/elastica |
| 1488329838606549174 | globalbitings | /home/desktopuser/GithubProjects/GlobalBitings |
| 1489451199185817630 | rag-research-tool | /home/desktopuser/GithubProjects/rag_research_tool |
| 1488649282792980550 | dev-nexus-frontend | /home/desktopuser/GithubProjects/dev-nexus-frontend |
| 1488016789110526104 | dev-nexus | /home/desktopuser/GithubProjects/dev-nexus |

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
        "accountId": "1487986866832805888"
      },
      "workspace": "/home/desktopuser/GithubProjects/bond-nexus",
      "workspaceName": "bond-nexus"
    },
    {
      "type": "route",
      "agentId": "main",
      "match": {
        "channel": "discord",
        "accountId": "1489035741341155408"
      },
      "workspace": "/home/desktopuser/GithubProjects/resume-customizer",
      "workspaceName": "resume-customizer"
    }
    // ... additional channels
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
    { "path": "../bond-nexus" },
    { "path": "../resume-customizer" },
    { "path": "../dynamic-worlock" },
    { "path": "../elastica" },
    { "path": "../GlobalBitings" },
    { "path": "../rag_research_tool" },
    { "path": "../dev-nexus-frontend" },
    { "path": "../dev-nexus" }
  ],
  "settings": {}
}
```

Save as `.code-workspace` file, e.g., `desktop-seed.code-workspace`.

### Open in VS Code

```bash
code /path/to/desktop-seed.code-workspace
```

### Switch Between Projects

- Use VS Code sidebar to switch folders
- Or use `/project <name>` command if Claude Code is connected

## Finding Existing Channel Mappings

If channel IDs are already stored somewhere in OpenCLAW:

```bash
# From sessions.json
grep -o 'discord:1485047825967480862#[a-zA-Z0-9-]*' ~/.openclaw/agents/main/sessions/sessions.json | sort -u

# From cron jobs
cat ~/.openclaw/cron/jobs.json | jq '.jobs[] | .sessionKey'

# From all JSON files
find /home -name '*.json' -exec grep -l '1488[0-9]*' {} \; 2>/dev/null
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
| Before (per-repo) | 8 | 16-24 GB |
| After (workspace) | 1 | 2-3 GB |

Savings: ~85% memory reduction.
