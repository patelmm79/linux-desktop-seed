#!/bin/bash
# Docker entrypoint for OpenCLAW container
# Merges defaults with environment variables, then starts OpenCLAW

set -euo pipefail

CONFIG_DIR="/root/.openclaw"
DEFAULTS_FILE="/defaults/openclaw-defaults.json"
CONFIG_FILE="$CONFIG_DIR/openclaw.json"

# Create config directory
mkdir -p "$CONFIG_DIR"

# Copy defaults if no config exists
if [ ! -f "$CONFIG_FILE" ]; then
    cp "$DEFAULTS_FILE" "$CONFIG_FILE"
fi

# Merge environment variables into config using jq
# Discord token from env
if [ -n "${DISCORD_BOT_TOKEN:-}" ]; then
    echo "$DISCORD_BOT_TOKEN" | jq -Rs '.' > /tmp/token.json
    jq --slurpfile token /tmp/token.json '.channels.discord.token = {"source": "env", "id": "DISCORD_BOT_TOKEN"}' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
    mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    rm -f /tmp/token.json
fi

# Discord allowlist from env
if [ -n "${DISCORD_ALLOWLIST_IDS:-}" ]; then
    ALLOWLIST_JSON=$(echo "$DISCORD_ALLOWLIST_IDS" | tr ',' '\n' | jq -R . | jq -s .)
    jq --argjson allowlist "$ALLOWLIST_JSON" '.channels.discord.allowlist = $allowlist' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
    mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
fi

# OpenRouter API key (should be set via env already in the config)
if [ -n "${OPENROUTER_API_KEY:-}" ]; then
    # API key is already configured via env source in defaults
    echo "OpenRouter API key will be loaded from environment"
fi

# Ensure proper permissions
chmod 600 "$CONFIG_FILE"

echo "OpenCLAW configuration initialized"
echo "Starting OpenCLAW..."

# Execute the main command
exec "$@"