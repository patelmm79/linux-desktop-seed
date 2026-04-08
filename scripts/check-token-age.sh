#!/bin/bash
# Check token ages and alert if any exceed 80 days
# Runs via cron: 0 9 * * 1

set -euo pipefail

TOKEN_AGES_FILE="$HOME/.config/desktop-seed/token-ages.json"
DISCORD_CHANNEL_ID="${DISCORD_CHANNEL_ID:-}"
ALERT_THRESHOLD_DAYS=80

# Logging
log_info() { echo "[INFO] $*"; }
log_warn() { echo "[WARN] $*"; }
log_error() { echo "[ERROR] $*" >&2; }

# Get days since a date
days_since() {
    local date_str="$1"
    local now=$(date +%s)
    local then=$(date -d "$date_str" +%s 2>/dev/null) || echo "$now"
    echo $(( (now - then) / 86400 ))
}

# Send Discord alert
send_alert() {
    local message="$1"

    if [[ -z "${DISCORD_CHANNEL_ID:-}" ]]; then
        log_warn "DISCORD_CHANNEL_ID not set, skipping Discord notification"
        return 0
    fi

    if ! command -v openclaw &> /dev/null; then
        log_warn "OpenCLAW not installed, skipping Discord notification"
        return 0
    fi

    if openclaw message send --channel discord --target "$DISCORD_CHANNEL_ID" --message "$message" 2>&1; then
        log_info "Discord alert sent"
    else
        log_warn "Failed to send Discord alert"
    fi
}

# Main check logic
main() {
    log_info "Checking token ages..."

    # Create token-ages.json if it doesn't exist (first run)
    if [[ ! -f "$TOKEN_AGES_FILE" ]]; then
        log_info "Token ages file not found, creating initial file..."
        mkdir -p "$(dirname "$TOKEN_AGES_FILE")"

        cat > "$TOKEN_AGES_FILE" << EOF
{
  "openrouter_api_key": "$(date +%Y-%m-%d)",
  "discord_bot_token": "$(date +%Y-%m-%d)",
  "discord_cve_webhook_url": "$(date +%Y-%m-%d)"
}
EOF
        log_info "Token ages file created. No alerts needed."
        return 0
    fi

    local alert_needed=false
    local alert_message="🔔 **Token Age Alert**\n\n"

    # Check each token
    for token in openrouter_api_key discord_bot_token discord_cve_webhook_url; do
        local rotation_date
        rotation_date=$(jq -r ".$token // empty" "$TOKEN_AGES_FILE" 2>/dev/null) || continue

        if [[ -z "$rotation_date" ]]; then
            continue
        fi

        local age_days
        age_days=$(days_since "$rotation_date")

        log_info "$token: $age_days days old"

        if [[ $age_days -ge $ALERT_THRESHOLD_DAYS ]]; then
            alert_needed=true
            alert_message+="• **$token**: $age_days days (exceeds $ALERT_THRESHOLD_DAYS day threshold)\n"
        fi
    done

    if [[ "$alert_needed" == "true" ]]; then
        alert_message+="\nPlease rotate these tokens per docs/token-rotation-policy.md"
        send_alert "$alert_message"
        log_warn "Token age alert sent"
    else
        log_info "All tokens within safe age threshold"
    fi
}

main "$@"