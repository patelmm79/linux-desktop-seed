#!/bin/bash
# Deploy GitHub repository to VM and notify Discord
# Usage: ./deploy-repo-to-vm.sh <repo> [branch]
# Example: ./deploy-repo-to-vm.sh patelmm79/dev-nexus-action-agent main

set -euo pipefail

REPO="${1:-}"
BRANCH="${2:-main}"
DISCORD_WEBHOOK_URL="${DISCORD_WEBHOOK_URL:-}"
DISCORD_CHANNEL_ID="1491175562348331209"

# Logging
log_info() { echo "[INFO] $*"; }
log_error() { echo "[ERROR] $*" >&2; }

# Validate input
if [[ -z "$REPO" ]]; then
    log_error "Usage: $0 <repo> [branch]"
    exit 1
fi

# Parse owner/repo from various formats
parse_repo() {
    local input="$1"
    # Remove .git suffix if present
    input="${input%.git}"
    # Extract owner/repo from URLs or plain format
    if [[ "$input" =~ github\.com[:/]([^/]+/[^/]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ "$input" =~ ^([^/]+/[^/]+)$ ]]; then
        echo "$input"
    else
        echo ""
    fi
}

# Send Discord notification
send_discord() {
    local message="$1"
    local color="${2:-3066993}"  # Green default

    if [[ -z "$DISCORD_WEBHOOK_URL" ]]; then
        log_info "Discord webhook not configured, skipping notification"
        log_info "Message: $message"
        return 0
    fi

    local payload
    payload=$(cat <<EOF
{
  "embeds": [{
    "title": "Repository Deployment",
    "description": "$message",
    "color": $color,
    "timestamp": "$(date -Iseconds)"
  }]
}
EOF
)

    curl -s -X POST "$DISCORD_WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "$payload" || true
}

# Main deployment logic
main() {
    local owner repo

    # Parse and validate repo
    local parsed
    parsed=$(parse_repo "$REPO")
    if [[ -z "$parsed" ]]; then
        send_discord "❌ Invalid repository format: $REPO. Use owner/repo or full GitHub URL" "15158332"
        log_error "Invalid repository format: $REPO"
        exit 1
    fi

    owner=$(echo "$parsed" | cut -d'/' -f1)
    repo=$(echo "$parsed" | cut -d'/' -f2)

    local target_dir="$HOME/repos/$owner/$repo"

    # Check if already exists (idempotency)
    if [[ -d "$target_dir" ]]; then
        local message="ℹ️ Repository already deployed: $owner/$repo\nLocation: $target_dir"
        send_discord "$message" "9807273"
        log_info "$message"
        exit 0
    fi

    # Create parent directory
    mkdir -p "$HOME/repos/$owner"

    # Clone repository
    log_info "Cloning $owner/$repo (branch: $BRANCH) to $target_dir..."
    if git clone --depth 1 -b "$BRANCH" "https://github.com/$owner/$repo.git" "$target_dir" 2>&1; then
        local message="✅ Repository deployed to VM: $owner/$repo ($BRANCH)\nLocation: $target_dir"
        send_discord "$message" "3066993"
        log_info "$message"
    else
        local message="❌ Failed to deploy $owner/$repo: Clone failed"
        send_discord "$message" "15158332"
        log_error "$message"
        exit 1
    fi
}

main "$@"