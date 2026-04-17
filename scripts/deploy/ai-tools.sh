#!/bin/bash
# AI tools module: OpenCLAW, OpenRouter
# Source this from the main deploy script

set -euo pipefail

# Import common library
# SCRIPT_DIR is inherited from the main script
# If not set, detect it
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
# Resolve lib.sh path relative to THIS script (not inherited SCRIPT_DIR)
_lib_sh_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [[ -f "$_lib_sh_dir/lib.sh" ]]; then
    source "$_lib_sh_dir/lib.sh"
else
    echo "ERROR: Could not find lib.sh in $_lib_sh_dir"
    exit 1
fi
unset _lib_sh_dir

# Clean up old OpenCLAW npm artifacts to prevent deprecated dependency warnings
cleanup_openclaw_npm() {
    log_info "Cleaning up old OpenCLAW npm artifacts..."

    local npm_global_path
    npm_global_path=$(npm root -g 2>/dev/null || echo "/usr/lib/node_modules")

    # Remove old OpenCLAW npm package directory
    if [[ -d "$npm_global_path/openclaw" ]]; then
        rm -rf "$npm_global_path/openclaw"
        log_info "Removed old OpenCLAW npm package"
    fi

    # Remove any orphaned symlinks
    rm -f /usr/bin/openclaw 2>/dev/null || true
    rm -f /usr/local/bin/openclaw 2>/dev/null || true

    # Clean npm cache to remove stale dependency references
    npm cache clean --force 2>/dev/null || true

    log_info "NPM cleanup complete"
}

# Get the latest available OpenCLAW version from npm
get_latest_openclaw_version() {
    npm show openclaw version 2>/dev/null || echo ""
}

# Install OpenCLAW AI client
install_openclaw() {
    log_step "Installing OpenCLAW..."

    # Default to pinned version for stability (especially for MiniMax model compatibility)
    # Override via OPENCLAW_VERSION environment variable to get latest
    local OPENCLAW_VERSION="${OPENCLAW_VERSION:-2026.04.11}"

    # Check if already installed with correct version
    if command -v openclaw &> /dev/null; then
        local oc_version
        oc_version=$(openclaw --version 2>/dev/null || echo "installed")
        if [[ "$oc_version" == *"$OPENCLAW_VERSION"* ]]; then
            log_info "OpenCLAW already installed: $oc_version"
            return 0
        else
            log_warn "OpenCLAW version mismatch: $oc_version, reinstalling to $OPENCLAW_VERSION..."
            # Clean up old npm artifacts before reinstalling to avoid deprecated dependency warnings
            cleanup_openclaw_npm
        fi
    fi

    # Install via npm as global package
    # First ensure Node.js is available
    if ! command -v node &> /dev/null; then
        log_info "Installing Node.js for OpenCLAW..."
        if ! apt-get install -y nodejs npm 2>&1 | grep -q "Err\|Failed"; then
            log_info "Node.js installed"
            # Clean up any pre-existing npm artifacts from the nodejs package
            cleanup_openclaw_npm
        else
            log_warn "Failed to install Node.js"
        fi
    fi

    # Install openclaw globally with pinned version
    if command -v npm &> /dev/null; then
        if npm install -g "openclaw@$OPENCLAW_VERSION" 2>&1; then
            # Verify installation
            if command -v openclaw &> /dev/null; then
                log_info "OpenCLAW installed successfully"
            else
                # Try to find and symlink
                local npm_global_path
                npm_global_path=$(npm root -g 2>/dev/null)
                if [ -f "$npm_global_path/openclaw/bin/openclaw.js" ]; then
                    ln -sf "$npm_global_path/openclaw/bin/openclaw.js" /usr/bin/openclaw 2>/dev/null || true
                fi
                if command -v openclaw &> /dev/null; then
                    log_info "OpenCLAW installed successfully"
                else
                    log_warn "OpenCLAW npm package installed but command not found"
                fi
            fi
        else
            log_warn "Failed to install OpenCLAW via npm"
        fi
    else
        log_warn "npm not available - cannot install OpenCLAW"
    fi
}

# Setup OpenCLAW wrapper
setup_openclaw_wrapper() {
    log_step "Setting up OpenCLAW wrapper..."

    # Create wrapper script for OpenCLAW
    local wrapper_path="/usr/local/bin/openclaw-wrapper"
    cat > "$wrapper_path" << 'EOF'
#!/bin/bash
# OpenCLAW wrapper - ensures environment variables are set

# Source user's environment if available
if [[ -f "$HOME/.bashrc" ]]; then
    source "$HOME/.bashrc" 2>/dev/null || true
fi

# Ensure required environment variables
if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
    echo "Error: OPENROUTER_API_KEY not set"
    exit 1
fi

# Run openclaw with any passed arguments
exec openclaw "$@"
EOF

    chmod +x "$wrapper_path"
    log_info "OpenCLAW wrapper created at $wrapper_path"
}

# Setup OpenCLAW config lock/unlock wrapper
setup_openclaw_lock_config() {
    log_step "Setting up OpenCLAW config lock script..."

    local lock_script="/usr/local/bin/openclaw-lock-config.sh"

    cat > "$lock_script" << 'EOF'
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
EOF

    chmod +x "$lock_script"
    log_info "OpenCLAW lock config script created at $lock_script"
}

# Setup OpenCLAW config validation script
setup_openclaw_validate_config() {
    log_step "Setting up OpenCLAW config validation script..."

    local validate_script="/usr/local/bin/openclaw-validate-config.sh"

    cat > "$validate_script" << 'EOF'
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
for section in meta models channels bindings; do
    if ! jq -e ".$section" "$CONFIG_FILE" >/dev/null 2>&1; then
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
EOF

    chmod +x "$validate_script"
    log_info "OpenCLAW config validation script created at $validate_script"
}

# Setup OpenCLAW config backup script
setup_openclaw_backup_config() {
    log_step "Setting up OpenCLAW config backup script..."

    local backup_script="/usr/local/bin/openclaw-backup-config.sh"

    cat > "$backup_script" << 'EOF'
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
EOF

    chmod +x "$backup_script"
    log_info "OpenCLAW config backup script created at $backup_script"
}

# Setup OpenCLAW change request governance workflow
setup_openclaw_change_request() {
    log_step "Setting up OpenCLAW change request governance script..."

    local change_request_script="/usr/local/bin/openclaw-change-request.sh"

    cat > "$change_request_script" << 'EOF'
#!/bin/bash
# /usr/local/bin/openclaw-change-request.sh
# Enforces governance process for config changes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="/home/desktopuser/.openclaw/openclaw.json"
ROOT_CONFIG_FILE="/root/.openclaw/openclaw.json"
CONFIG_DIR="/home/desktopuser/.openclaw"
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

    # Create request tracking directory
    mkdir -p "$CONFIG_DIR/requests"

    # Create request file
    cat > "$CONFIG_DIR/requests/$request_id.json" << REQEOF
{
  "request_id": "$request_id",
  "description": "$description",
  "requested_by": "$(whoami)",
  "timestamp": "$(date -Iseconds)",
  "status": "pending"
}
REQEOF

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
    echo "Request saved to: $CONFIG_DIR/requests/$request_id.json"
}

do_approve() {
    local request_id="$1"

    if [[ -z "$request_id" ]]; then
        echo "ERROR: Request ID required"
        echo "Usage: $0 approve <request_id>"
        exit 1
    fi

    local request_file="$CONFIG_DIR/requests/$request_id.json"
    if [[ ! -f "$request_file" ]]; then
        echo "ERROR: Request not found: $request_id"
        echo "Available requests:"
        ls -1 "$CONFIG_DIR/requests/" 2>/dev/null || echo "  (none)"
        exit 1
    fi

    # Verify approver is Milan (root or desktopuser on the VM)
    local approver="$(whoami)"
    if [[ "$approver" != "root" && "$approver" != "desktopuser" ]]; then
        echo "ERROR: Only Milan can approve changes"
        exit 1
    fi

    # Update request status to approved
    local approval_timestamp
    approval_timestamp=$(date -Iseconds)
    jq ".status = \"approved\" | .approved_by = \"$approver\" | .approval_timestamp = \"$approval_timestamp\"" "$request_file" > "$request_file.tmp" && mv "$request_file.tmp" "$request_file"

    echo "=== Approved: $request_id ==="
    echo "Approved by: $approver"
    echo "Approval timestamp: $approval_timestamp"
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

    local request_file="$CONFIG_DIR/requests/$request_id.json"
    if [[ ! -f "$request_file" ]]; then
        echo "ERROR: Request not found: $request_id"
        exit 1
    fi

    local status
    status=$(jq -r '.status' "$request_file")
    if [[ "$status" != "approved" ]]; then
        echo "ERROR: Request not approved. Status: $status"
        echo "Only approved requests can be applied."
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
    echo "Pending/approved requests:"
    if [[ -d "$CONFIG_DIR/requests" ]]; then
        for req in "$CONFIG_DIR/requests"/*.json; do
            [[ -f "$req" ]] || continue
            local req_id status description approved_by
            req_id=$(jq -r '.request_id' "$req")
            status=$(jq -r '.status' "$req")
            description=$(jq -r '.description' "$req")
            approved_by=$(jq -r '.approved_by // "N/A"' "$req")
            echo "  $req_id: $status"
            echo "    Description: $description"
            if [[ "$approved_by" != "N/A" ]]; then
                echo "    Approved by: $approved_by"
            fi
        done
    else
        echo "  (no requests)"
    fi
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
EOF

    chmod +x "$change_request_script"
    log_info "OpenCLAW change request governance script created at $change_request_script"
}

# Setup OpenCLAW configuration
# CRITICAL: Must use TARGET_USER's home, not $HOME, because this runs as root
setup_openclaw_config() {
    log_step "Setting up OpenCLAW configuration..."

    # Use TARGET_USER's home directory explicitly, not $HOME (which resolves to /root when running as root)
    local target_home
    target_home=$(getent passwd "$TARGET_USER" | cut -d: -f6)
    local openclaw_dir="$target_home/.openclaw"
    local config_file="$openclaw_dir/openclaw.json"
    local models_file="$openclaw_dir/agents/main/agent/models.json"

    # Create OpenCLAW directories
    mkdir -p "$openclaw_dir/agents/main/agent"

    # Copy default configuration if it doesn't exist
    if [[ ! -f "$config_file" ]]; then
        local repo_config="$(dirname "$SCRIPT_DIR")/config/openclaw-defaults.json"
        if [[ -f "$repo_config" ]]; then
            cp "$repo_config" "$config_file"
            log_info "Copied OpenCLAW default config"
        else
            # Create minimal config
            cat > "$config_file" << 'EOF'
{
  "meta": {
    "lastTouchedVersion": "2026.04.11"
  },
  "agents": {
    "defaults": {
      "model": "openrouter/minimax/MiniMax-M2.7",
      "thinkingDefault": "minimal"
    }
  }
}
EOF
            log_info "Created minimal OpenCLAW config"
        fi
    else
        log_info "OpenCLAW config already exists"
    fi

    # Copy models configuration if it doesn't exist
    if [[ ! -f "$models_file" ]]; then
        local repo_models="$(dirname "$SCRIPT_DIR")/config/openclaw-models-sample.json"
        if [[ -f "$repo_models" ]]; then
            cp "$repo_models" "$models_file"
            log_info "Copied OpenCLAW models config"
        fi
    fi

    # Set ownership to TARGET_USER
    chown -R "$TARGET_USER:$TARGET_USER" "$openclaw_dir"

    log_info "OpenCLAW configuration complete for user $TARGET_USER"
}

# Setup OpenCLAW systemd override for API key persistence
setup_openclaw_systemd_override() {
    log_step "Setting up OpenCLAW systemd override for API key persistence..."

    # Get the target user's home directory
    local target_home
    target_home=$(getent passwd "$TARGET_USER" | cut -d: -f6)
    local override_dir="$target_home/.config/systemd/user/openclaw-gateway.service.d"
    local override_file="$override_dir/override.conf"

    # API key value (hardcoded for deployment, should be injected via env var in production)
    local api_key="${OPENROUTER_API_KEY:-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}"

    # Create the directory structure
    mkdir -p "$override_dir"

    # Create the override.conf file
    cat > "$override_file" << EOF
[Service]
# Persist environment variables across restarts
Environment=OPENROUTER_API_KEY=$api_key
Environment=HOME=/root
Environment=XDG_RUNTIME_DIR=/run/user/0
EOF

    # Set ownership to TARGET_USER
    chown -R "$TARGET_USER:$TARGET_USER" "$target_home/.config"

    log_info "OpenCLAW systemd override created at $override_file"
}

# Export functions for use in main script
export -f install_openclaw setup_openclaw_wrapper setup_openclaw_config setup_openclaw_lock_config setup_openclaw_validate_config setup_openclaw_backup_config setup_openclaw_change_request cleanup_openclaw_npm get_latest_openclaw_version setup_openclaw_systemd_override