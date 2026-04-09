#!/bin/bash
# Configuration module: environment, MCP servers, token rotation, GitHub issues
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

# Setup environment
setup_environment() {
    log_step "Setting up environment..."

    local username="desktopuser"
    local user_home=$(getent passwd "$username" | cut -d: -f6)

    if [[ -z "$user_home" ]]; then
        log_error "Cannot find home directory for $username"
        return 1
    fi

    # Create config directory
    local config_dir="$user_home/.config/desktop-seed"
    mkdir -p "$config_dir"

    # Copy environment example if it exists
    local repo_config="$(dirname "$SCRIPT_DIR")/.env.example"
    if [[ -f "$repo_config" ]]; then
        cp "$repo_config" "$config_dir/.env.example"
    fi

    # Create .bashrc additions
    local bashrc_additions="$user_home/.bashrc.desktop-seed"
    cat > "$bashrc_additions" << 'EOF'
# Desktop Seed Environment Configuration

# OpenRouter API (required for Claude Code)
export OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"

# Claude Code Router configuration
export CCR_CONFIG_PATH="$HOME/.config/claude-code-router.json"

# MCP Servers configuration
export MCP_CONFIG_DIR="$HOME/.config/mcp-servers"

# Desktop Seed configuration
export DESKTOP_SEED_DIR="$HOME/.config/desktop-seed"
EOF

    # Add to .bashrc if not already present
    if ! grep -q "desktop-seed" "$user_home/.bashrc" 2>/dev/null; then
        echo "" >> "$user_home/.bashrc"
        echo "# Desktop Seed environment" >> "$user_home/.bashrc"
        echo "if [[ -f ~/.bashrc.desktop-seed ]]; then" >> "$user_home/.bashrc"
        echo "    source ~/.bashrc.desktop-seed" >> "$user_home/.bashrc"
        echo "fi" >> "$user_home/.bashrc"
    fi

    # Set ownership
    chown -R "$username:$username" "$user_home"

    log_info "Environment configured"
}

# Configure MCP servers
configure_mcp_servers() {
    log_step "Configuring MCP servers..."

    local username="desktopuser"
    local user_home=$(getent passwd "$username" | cut -d: -f6)

    if [[ -z "$user_home" ]]; then
        log_error "Cannot find home directory for $username"
        return 1
    fi

    # Create MCP config directory
    local mcp_dir="$user_home/.config"
    mkdir -p "$mcp_dir"

    # Create MCP servers file (empty by default, user adds their own)
    local mcp_file="$mcp_dir/mcp-servers"
    if [[ ! -f "$mcp_file" ]]; then
        touch "$mcp_file"
        log_info "Created MCP servers config (add your servers to $mcp_file)"
    fi

    # Set ownership
    chown "$username:$username" "$mcp_file"

    log_info "MCP servers configured"
}

# Setup token rotation cron
setup_token_rotation_cron() {
    log_step "Setting up token rotation cron..."

    local cron_file="/etc/cron.d/openclaw-token-rotation"

    # Check if token rotation is enabled
    if [[ "${TOKEN_ROTATION_ENABLED:-false}" != "true" ]]; then
        log_info "Token rotation disabled (set TOKEN_ROTATION_ENABLED=true to enable)"
        return 0
    fi

    # Create cron job for token rotation
    cat > "$cron_file" << EOF
# Token rotation for OpenCLAW
# Runs daily at 2 AM
0 2 * * * root /usr/local/bin/rotate-openclaw-tokens.sh >> /var/log/token-rotation.log 2>&1
EOF

    chmod 644 "$cron_file"
    log_info "Token rotation cron configured"
}

# Setup GitHub issues automation
setup_github_issues() {
    log_step "Setting up GitHub issues..."

    local username="desktopuser"
    local user_home=$(getent passwd "$username" | cut -d: -f6)

    if [[ -z "$user_home" ]]; then
        log_error "Cannot find home directory for $username"
        return 1
    fi

    # Create GitHub issues script directory
    local scripts_dir="$user_home/.local/bin"
    mkdir -p "$scripts_dir"

    # Check if GitHub CLI is available
    if ! command -v gh &> /dev/null; then
        log_warn "GitHub CLI not available - skipping GitHub issues setup"
        return 0
    fi

    # Create a simple issue creator script
    cat > "$scripts_dir/create-issue.sh" << 'EOF'
#!/bin/bash
# Create a GitHub issue from the command line

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <title> <body>"
    exit 1
fi

gh issue create --title "$1" --body "$2"
EOF

    chmod +x "$scripts_dir/create-issue.sh"
    chown "$username:$username" "$scripts_dir/create-issue.sh"

    log_info "GitHub issues configured"
}

# Validate deployment
validate_deployment() {
    log_step "Validating deployment..."

    local errors=0

    # Check critical services
    local services=("xrdp" "ssh")
    for svc in "${services[@]}"; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            log_info "Service $svc: running"
        else
            log_warn "Service $svc: not running"
            ((errors++))
        fi
    done

    # Check critical commands
    local commands=("code" "claude" "chromium" "gh")
    for cmd in "${commands[@]}"; do
        if command -v "$cmd" &> /dev/null; then
            log_info "Command $cmd: installed"
        else
            log_warn "Command $cmd: not found"
            ((errors++))
        fi
    done

    if [[ $errors -eq 0 ]]; then
        log_info "Deployment validation passed"
    else
        log_warn "Deployment validation: $errors issues found"
    fi

    return $errors
}

# Show deployment summary
show_summary() {
    log_step "Deployment Complete!"

    echo ""
    echo "========================================="
    echo "  Remote Desktop Deployed Successfully"
    echo "========================================="
    echo ""
    echo "Access:"
    echo "  - RDP: <SERVER_IP>:3389"
    echo "  - Username: desktopuser"
    echo "  - Password: desktop"
    echo ""
    echo "Installed Tools:"
    echo "  - GNOME Desktop"
    echo "  - xrdp (RDP server)"
    echo "  - Visual Studio Code"
    echo "  - Claude Code"
    echo "  - OpenRouter CLI"
    echo "  - Claude Code Router"
    echo "  - Chromium Browser"
    echo "  - GitHub CLI"
    echo "  - Bun runtime"
    echo "  - OpenCLAW"
    echo "  - Terraform & Terragrunt"
    echo "  - Google Cloud SDK"
    echo ""
    echo "Next Steps:"
    echo "  1. Connect via RDP"
    echo "  2. Set your API keys in ~/.config/desktop-seed/.env"
    echo "  3. Run: source ~/.bashrc"
    echo ""
}

# Export functions for use in main script
export -f setup_environment configure_mcp_servers setup_token_rotation_cron
export -f setup_github_issues validate_deployment show_summary