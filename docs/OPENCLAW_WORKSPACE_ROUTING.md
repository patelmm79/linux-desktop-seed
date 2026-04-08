# OpenCLAW Workspace Routing

Route Discord channels to specific Git repos using a single OpenCLAW instance and a single VS Code window — no matter how many repos you manage.

## The Problem

If you work across multiple repos, the naive setup is one VS Code instance per repo. That works, but each instance uses 2–3 GB of RAM. Three repos means 6–9 GB just for editors.

## The Solution

Run one VS Code window with a multi-root workspace, and configure OpenCLAW **bindings** so that each Discord channel routes to its own repo directory. Every channel behaves independently; only one editor process runs.

```
Discord (1 bot)
    ├── #project-alpha  →  ~/Projects/alpha
    ├── #project-beta   →  ~/Projects/beta
    └── #project-gamma  →  ~/Projects/gamma
```

## Step 1 — Find Your Channel IDs

Channel IDs are Discord snowflakes (17–19 digit numbers). To copy one:

1. Open Discord → Settings → Advanced → turn on **Developer Mode**
2. Right-click a channel → **Copy Channel ID**

Alternatively, open Discord in a browser. The URL looks like:
```
https://discord.com/channels/<guild-id>/<channel-id>
```
The second number is the channel ID.

If you already have sessions in OpenCLAW, you can extract channel IDs from existing files:

```bash
# From the sessions index
grep -o 'discord:[0-9]*#[^"]*' ~/.openclaw/agents/main/sessions/sessions.json | sort -u

# From scheduled jobs
jq '.jobs[].sessionKey' ~/.openclaw/cron/jobs.json

# Broad scan for anything that looks like a snowflake
find /home -name '*.json' -exec grep -l '[0-9]\{17,19\}' {} \; 2>/dev/null
```

## Step 2 — Find Your Repo Paths

```bash
ssh <your-server> "find /home -maxdepth 3 -type d -name '.git' 2>/dev/null"
```

This prints every Git repo root under `/home`, up to three levels deep.

## Step 3 — Configure OpenCLAW Bindings

Edit `~/.openclaw/openclaw.json` and add a `bindings` array. Each entry maps one Discord channel to one workspace directory:

```json
{
  "bindings": [
    {
      "type": "route",
      "agentId": "main",
      "match": {
        "channel": "discord",
        "accountId": "123456789012345678"
      },
      "workspace": "/home/youruser/Projects/alpha",
      "workspaceName": "alpha"
    },
    {
      "type": "route",
      "agentId": "main",
      "match": {
        "channel": "discord",
        "accountId": "987654321098765432"
      },
      "workspace": "/home/youruser/Projects/beta",
      "workspaceName": "beta"
    }
  ]
}
```

Replace the `accountId` values with your real channel IDs, and update the `workspace` paths to match your server.

Then restart the daemon:

```bash
openclaw daemon restart
```

## Step 4 — Set Up a VS Code Multi-Root Workspace

Create a `.code-workspace` file that includes all your repos as folders:

```json
{
  "folders": [
    { "path": "/home/youruser/Projects/alpha" },
    { "path": "/home/youruser/Projects/beta" },
    { "path": "/home/youruser/Projects/gamma" }
  ],
  "settings": {}
}
```

Save it somewhere convenient (e.g., `~/Projects/all.code-workspace`) and open it:

```bash
code ~/Projects/all.code-workspace
```

You can switch between repos using the VS Code Explorer sidebar, or with `/project <name>` if Claude Code is attached to the session.

## Step 5 — Per-Repo API Keys (Optional)

For separate OpenRouter tracking and billing per repository, create a dedicated agent with its own API key.

### Why Per-Repo Keys?

- **Separate tracking** — Each repo shows as its own "app" in OpenRouter analytics
- **Cost attribution** — Know exactly which repo is consuming API credits
- **Key rotation** — Replace a key for one repo without affecting others

### Create a New Repo Agent

```bash
# Set your repo name (used as agent ID)
REPO_NAME="alpha"

# Create agent directory structure
mkdir -p ~/.openclaw/agents/$REPO_NAME/agent
mkdir -p ~/.openclaw/agents/$REPO_NAME/sessions

# Create auth-profiles.json with repo-specific API key
cat > ~/.openclaw/agents/$REPO_NAME/agent/auth-profiles.json << EOF
{
  "version": 1,
  "profiles": {
    "openrouter:default": {
      "type": "api_key",
      "provider": "openrouter",
      "key": "sk-or-v2-YOUR_API_KEY_HERE"
    }
  }
}
EOF
chmod 600 ~/.openclaw/agents/$REPO_NAME/agent/auth-profiles.json
```

### Update Bindings to Use the New Agent

Edit your bindings to reference the new agent:

```json
{
  "bindings": [
    {
      "type": "route",
      "agentId": "alpha",
      "match": {
        "channel": "discord",
        "accountId": "123456789012345678"
      },
      "workspace": "/home/user/Projects/alpha",
      "workspaceName": "alpha"
    }
  ]
}
```

### Restart OpenCLAW

```bash
openclaw daemon restart
```

### Verify the Agent is Active

```bash
# Check agent directories exist
ls -la ~/.openclaw/agents/

# Check auth profile is configured
cat ~/.openclaw/agents/alpha/agent/auth-profiles.json | jq '.profiles'
```

### Script: Add New Repo

Here's a convenience script to add a new repo with its own API key:

```bash
#!/bin/bash
# add-openclaw-repo.sh - Add a new repo with dedicated OpenRouter key

set -euo pipefail

# Defaults
DEFAULT_REPO_PATH="$HOME/Projects"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 <repo-name> [options]"
    echo ""
    echo "Arguments:"
    echo "  repo-name           Name of the repo (used as agent ID)"
    echo ""
    echo "Options:"
    echo "  -k, --api-key      OpenRouter API key (required)"
    echo "  -p, --path         Repo path (default: ~/Projects/<repo-name>)"
    echo "  -c, --channel      Discord channel ID or name"
    echo "  -h, --help         Show this help"
    exit 1
}

# Parse arguments
REPO_NAME=""
API_KEY=""
REPO_PATH=""
CHANNEL=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -k|--api-key)
            API_KEY="$2"
            shift 2
            ;;
        -p|--path)
            REPO_PATH="$2"
            shift 2
            ;;
        -c|--channel)
            CHANNEL="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            REPO_NAME="$1"
            shift
            ;;
    esac
done

# Validate required args
if [[ -z "$REPO_NAME" ]]; then
    echo -e "${RED}Error: repo-name is required${NC}"
    usage
fi

if [[ -z "$API_KEY" ]]; then
    echo -e "${RED}Error: OpenRouter API key is required (use -k or --api-key)${NC}"
    usage
fi

# Default repo path
if [[ -z "$REPO_PATH" ]]; then
    REPO_PATH="$DEFAULT_REPO_PATH/$REPO_NAME"
fi

echo -e "${GREEN}Adding repo: $REPO_NAME${NC}"
echo "  Path: $REPO_PATH"

# Check for existing Discord channel
if [[ -z "$CHANNEL" ]]; then
    echo -e "${YELLOW}Checking for existing Discord channel named '$REPO_NAME'...${NC}"
    
    # Try to find channel from existing config
    EXISTING_CHANNEL=$(jq -r '.channels.discord.guilds[].channels | to_entries[] | select(.key | contains("'"$REPO_NAME"'")) | .key' ~/.openclaw/openclaw.json 2>/dev/null | head -1 || true)
    
    if [[ -n "$EXISTING_CHANNEL" ]]; then
        CHANNEL="$EXISTING_CHANNEL"
        echo -e "${GREEN}Found existing channel: $CHANNEL${NC}"
    else
        echo -e "${YELLOW}No channel found matching '$REPO_NAME'${NC}"
        echo ""
        echo "Please create a Discord channel for this repo, then provide the channel ID:"
        echo "  1. Enable Developer Mode in Discord (Settings → Advanced → Developer Mode)"
        echo "  2. Right-click the channel → Copy Channel ID"
        echo ""
        read -p "Enter Discord channel ID: " CHANNEL
        
        if [[ -z "$CHANNEL" ]]; then
            echo -e "${RED}Error: channel ID is required${NC}"
            exit 1
        fi
    fi
fi

# Extract accountId from channel (channel ID format)
ACCOUNT_ID="$CHANNEL"

echo "  Channel: $ACCOUNT_ID"

# Create agent directory structure
echo -e "${GREEN}Creating agent '$REPO_NAME'...${NC}"
mkdir -p ~/.openclaw/agents/$REPO_NAME/agent
mkdir -p ~/.openclaw/agents/$REPO_NAME/sessions

# Create auth-profiles.json
cat > ~/.openclaw/agents/$REPO_NAME/agent/auth-profiles.json << EOF
{
  "version": 1,
  "profiles": {
    "openrouter:default": {
      "type": "api_key",
      "provider": "openrouter",
      "key": "$API_KEY"
    }
  }
}
EOF
chmod 600 ~/.openclaw/agents/$REPO_NAME/agent/auth-profiles.json

# Copy models.json from main agent
if [[ -f ~/.openclaw/agents/main/agent/models.json ]]; then
    cp ~/.openclaw/agents/main/agent/models.json ~/.openclaw/agents/$REPO_NAME/agent/
fi

# Add binding to config
echo -e "${GREEN}Adding binding to config...${NC}"

# Check if bindings exist
if jq -e '.bindings' ~/.openclaw/openclaw.json >/dev/null 2>&1; then
    jq --arg agent "$REPO_NAME" --arg channel "$ACCOUNT_ID" --arg path "$REPO_PATH" --arg name "$REPO_NAME" \
        '.bindings += [{"type": "route", "agentId": $agent, "match": {"channel": "discord", "accountId": $channel}, "workspace": $path, "workspaceName": $name}]' \
        ~/.openclaw/openclaw.json > /tmp/openclaw.json.tmp
else
    jq --arg agent "$REPO_NAME" --arg channel "$ACCOUNT_ID" --arg path "$REPO_PATH" --arg name "$REPO_NAME" \
        '. + {"bindings": [{"type": "route", "agentId": $agent, "match": {"channel": "discord", "accountId": $channel}, "workspace": $path, "workspaceName": $name}]}' \
        ~/.openclaw/openclaw.json > /tmp/openclaw.json.tmp
fi
mv /tmp/openclaw.json.tmp ~/.openclaw/openclaw.json

# Restart OpenCLAW
echo -e "${GREEN}Restarting OpenCLAW...${NC}"
openclaw daemon restart

echo ""
echo -e "${GREEN}Done! Repo '$REPO_NAME' has been configured.${NC}"
echo ""
echo "Bindings:"
jq ".bindings" ~/.openclaw/openclaw.json
```

Usage:
```bash
chmod +x add-openclaw-repo.sh

# Minimal usage (will prompt for channel)
./add-openclaw-repo.sh my-repo -k "sk-or-v2-..."

# Full usage
./add-openclaw-repo.sh my-repo -k "sk-or-v2-..." -p /home/user/Projects/my-repo -c "123456789012345678"
```

## Troubleshooting

**List active sessions:**
```bash
ls -la ~/.openclaw/agents/main/sessions/
```

**Check which directory a session is using:**
```bash
head -1 ~/.openclaw/agents/main/sessions/<session-id>.jsonl | jq '.cwd'
```

**Verify your bindings were loaded correctly:**
```bash
jq '.bindings' ~/.openclaw/openclaw.json
```

**Stream live logs:**
```bash
tail -f ~/.openclaw/logs/*.log
```

## Memory Impact

| Setup | VS Code instances | Approximate RAM |
|-------|:-----------------:|----------------:|
| One instance per repo (N repos) | N | N × 2–3 GB |
| Multi-root workspace | 1 | 2–3 GB |

For three repos that's roughly a 66–75% reduction in editor memory usage.
