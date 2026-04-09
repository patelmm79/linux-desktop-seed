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

# Install OpenCLAW AI client
install_openclaw() {
    log_step "Installing OpenCLAW..."

    # Pin to specific version to avoid breaking changes (especially for MiniMax model compatibility)
    local OPENCLAW_VERSION="2026.3.28"

    # Check if already installed with correct version
    if command -v openclaw &> /dev/null; then
        local oc_version
        oc_version=$(openclaw --version 2>/dev/null || echo "installed")
        if [[ "$oc_version" == *"$OPENCLAW_VERSION"* ]]; then
            log_info "OpenCLAW already installed: $oc_version"
            return 0
        else
            log_warn "OpenCLAW version mismatch: $oc_version, reinstalling to $OPENCLAW_VERSION..."
            npm uninstall -g openclaw 2>/dev/null || true
        fi
    fi

    # Install via npm as global package
    # First ensure Node.js is available
    if ! command -v node &> /dev/null; then
        log_info "Installing Node.js for OpenCLAW..."
        if ! apt-get install -y nodejs npm 2>&1 | grep -q "Err\|Failed"; then
            log_info "Node.js installed"
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

# Setup OpenCLAW configuration
setup_openclaw_config() {
    log_step "Setting up OpenCLAW configuration..."

    local openclaw_dir="$HOME/.openclaw"
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
    "lastTouchedVersion": "2026.3.28"
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

    # Set ownership
    if [[ -n "$TARGET_USER" ]]; then
        chown -R "$TARGET_USER:$TARGET_USER" "$openclaw_dir"
    fi

    log_info "OpenCLAW configuration complete"
}

# Export functions for use in main script
export -f install_openclaw setup_openclaw_wrapper setup_openclaw_config