#!/bin/bash
# Development tools module: VS Code, Claude Code, Node, Chromium, GitHub CLI, Bun
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

# Install Visual Studio Code
install_vscode() {
    log_step "Installing Visual Studio Code..."

    # Check if already installed
    if command -v code &> /dev/null; then
        log_warn "VS Code already installed, version: $(code --version | head -1)"
        return 0
    fi

    # Create keyrings directory if it doesn't exist
    mkdir -p /etc/apt/keyrings

    # Download and add Microsoft GPG key using modern method
    if ! wget -q https://packages.microsoft.com/keys/microsoft.asc -O- | gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg 2>/dev/null; then
        log_error "Failed to add Microsoft GPG key"
        return 1
    fi

    # Add VS Code repository with signed-by option
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | tee /etc/apt/sources.list.d/vscode.list > /dev/null

    # Update and install
    if ! apt-get update -y; then
        log_error "Failed to update package lists"
        return 1
    fi

    if ! apt-get install -y code; then
        log_error "Failed to install VS Code"
        return 1
    fi

    log_info "VS Code installed successfully"
}

# Install Claude Code CLI
install_claude_code() {
    log_step "Installing Claude Code..."

    # Check if already installed
    if command -v claude &> /dev/null; then
        log_warn "Claude Code already installed"
        return 0
    fi

    # Ensure Node.js and npm are available
    if ! command -v node &> /dev/null; then
        log_info "Installing Node.js..."
        if ! apt-get install -y nodejs npm 2>/dev/null; then
            # Fallback to NodeSource if Ubuntu repos fail
            log_info "Using NodeSource for Node.js..."
            if ! curl -fsSL https://deb.nodesource.com/setup_22.x | bash -; then
                log_error "Failed to setup NodeSource repository"
                return 1
            fi
            if ! apt-get install -y nodejs npm; then
                log_error "Failed to install Node.js"
                return 1
            fi
        fi
    fi

    # Verify npm is available
    if ! command -v npm &> /dev/null; then
        log_error "npm not available"
        return 1
    fi

    # Install Claude Code via npm
    if ! npm install -g @anthropic-ai/claude-code 2>&1; then
        log_error "Failed to install Claude Code"
        return 1
    fi

    # Verify installation
    if ! command -v claude &> /dev/null; then
        log_error "Claude Code installation failed - command not found"
        return 1
    fi

    log_info "Claude Code installed successfully"
}

# Install Claude Code skills
install_claude_skills() {
    log_step "Installing Claude Code skills..."

    # Ensure npm/npx is available
    if ! command -v npx &> /dev/null; then
        if ! command -v node &> /dev/null; then
            log_info "Installing Node.js for skill installation..."
            if ! apt-get install -y nodejs npm 2>/dev/null; then
                log_warn "Node.js not available - skipping skill installation"
                return 0
            fi
        fi
    fi

    if ! command -v npx &> /dev/null; then
        log_warn "npx not available - skipping skill installation"
        return 0
    fi

    local skills_dir="$HOME/.claude/skills"
    if [[ -d "$HOME/.claude" ]]; then
        log_info "Claude skills directory exists"
    else
        mkdir -p "$skills_dir"
    fi

    log_info "Claude skills installation skipped (manual installation recommended)"
}

# Configure Claude Code with OpenRouter
configure_claude_openrouter() {
    log_step "Configuring Claude Code with OpenRouter..."

    # Create Claude config directory
    local claude_dir="$HOME/.config/claude"
    mkdir -p "$claude_dir"

    # Create or update settings
    local settings_file="$claude_dir/settings.json"
    if [[ -f "$settings_file" ]]; then
        log_info "Claude settings already exist"
    else
        cat > "$settings_file" << 'EOF'
{
  "apiKey": "OPENROUTER_API_KEY",
  "model": "openrouter/minimax/MiniMax-M2.7"
}
EOF
        log_info "Created Claude settings with OpenRouter"
    fi

    # Add to .bashrc for persistence
    if ! grep -q "OPENROUTER_API_KEY" "$HOME/.bashrc" 2>/dev/null; then
        echo 'export OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"' >> "$HOME/.bashrc"
    fi

    log_info "Claude OpenRouter configuration complete"
}

# Install OpenRouter CLI
install_openrouter() {
    log_step "Installing OpenRouter CLI..."

    # Check if already installed
    if command -v orc &> /dev/null || command -v openrouter &> /dev/null; then
        log_warn "OpenRouter CLI already installed"
        return 0
    fi

    # Install via npm
    if ! command -v npm &> /dev/null; then
        log_info "Installing Node.js for OpenRouter CLI..."
        if ! apt-get install -y nodejs npm; then
            log_error "Failed to install Node.js"
            return 1
        fi
    fi

    if ! npm install -g openrouter-cli 2>&1; then
        log_error "Failed to install OpenRouter CLI"
        return 1
    fi

    log_info "OpenRouter CLI installed successfully"
}

# Install Claude Code Router (CCR)
install_claude_code_router() {
    log_step "Installing Claude Code Router..."

    # Check if already installed
    if command -v ccr &> /dev/null; then
        log_warn "Claude Code Router already installed"
        return 0
    fi

    # Ensure Node.js is available
    if ! command -v node &> /dev/null; then
        log_info "Installing Node.js for CCR..."
        if ! apt-get install -y nodejs npm; then
            log_error "Failed to install Node.js"
            return 1
        fi
    fi

    # Try to install from npm
    if npm list -g ccr &>/dev/null; then
        log_warn "CCR already installed"
        return 0
    fi

    # Create a simple wrapper script as fallback
    local ccr_dir="/usr/local/bin"
    cat > "$ccr_dir/ccr" << 'EOF'
#!/bin/bash
# Claude Code Router - simple wrapper
# This is a placeholder - real CCR would be installed separately

if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
    echo "Error: OPENROUTER_API_KEY not set"
    exit 1
fi

# Route to Claude Code with OpenRouter
claude "$@"
EOF

    chmod +x "$ccr_dir/ccr"
    log_info "Claude Code Router wrapper installed (placeholder)"
}

# Install Chromium Browser
install_chromium() {
    log_step "Installing Chromium Browser..."

    # Check if already installed
    if command -v chromium &> /dev/null || command -v chromium-browser &> /dev/null || command -v google-chrome &> /dev/null; then
        log_warn "Browser already installed"
        return 0
    fi

    # Install Chromium
    if ! apt-get install -y chromium-browser 2>/dev/null; then
        # Try google-chrome-stable as fallback
        if ! apt-get install -y google-chrome-stable 2>/dev/null; then
            log_warn "Could not install Chromium/Chrome - skipping"
            return 0
        fi
    fi

    log_info "Chromium installed successfully"
}

# Install GitHub CLI
install_ghcli() {
    log_step "Installing GitHub CLI..."

    # Check if already installed
    if command -v gh &> /dev/null; then
        log_warn "GitHub CLI already installed"
        return 0
    fi

    # Add GitHub CLI repository
    if ! command -v gh &> /dev/null; then
        # Download and install the latest version
        local gh_version
        gh_version=$(curl -s https://api.github.com/repos/cli/cli/releases/latest | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4 | sed 's/v//')

        if [[ -n "$gh_version" ]]; then
            wget -q "https://github.com/cli/cli/releases/download/v${gh_version}/gh_${gh_version}_linux_amd64.tar.gz" -O /tmp/gh.tar.gz
            tar -xzf /tmp/gh.tar.gz -C /tmp
            cp /tmp/gh_"$gh_version"_linux_amd64/bin/gh /usr/local/bin/
            rm -rf /tmp/gh.tar.gz /tmp/gh_"$gh_version"_linux_amd64
            log_info "GitHub CLI v$gh_version installed"
        else
            log_error "Could not determine GitHub CLI version"
            return 1
        fi
    fi

    # Verify installation
    if ! command -v gh &> /dev/null; then
        log_error "GitHub CLI installation failed"
        return 1
    fi

    log_info "GitHub CLI installed successfully"
}

# Install Bun runtime
install_bun() {
    log_step "Installing Bun runtime..."

    # Check if already installed
    if command -v bun &> /dev/null; then
        log_warn "Bun already installed"
        return 0
    fi

    # Install Bun via official installer
    if ! curl -fsSL https://bun.sh/install | bash 2>&1; then
        log_error "Failed to install Bun"
        return 1
    fi

    # Source bun environment
    if [[ -f "$HOME/.bashrc" ]]; then
        if ! grep -q "bun.sh" "$HOME/.bashrc"; then
            echo 'export BUN_INSTALL="$HOME/.bun"' >> "$HOME/.bashrc"
            echo 'export PATH="$BUN_INSTALL/bin:$PATH"' >> "$HOME/.bashrc"
        fi
    fi

    # Export for current session
    export BUN_INSTALL="$HOME/.bun"
    export PATH="$BUN_INSTALL/bin:$PATH"

    # Verify installation
    if ! command -v bun &> /dev/null; then
        log_error "Bun installation failed"
        return 1
    fi

    log_info "Bun installed successfully"
}

# Install Terraform
install_terraform() {
    log_step "Installing Terraform..."

    # Check if already installed
    if command -v terraform &> /dev/null; then
        log_warn "Terraform already installed: $(terraform version | head -1)"
        return 0
    fi

    # Add HashiCorp repository
    if ! grep -q "hashicorp" /etc/apt/sources.list.d/* 2>/dev/null; then
        wget -q https://apt.releases.hashicorp.com/gpg -O /usr/share/keyrings/hashicorp-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list > /dev/null
        apt-get update -y
    fi

    # Install Terraform and Terragrunt
    if ! apt-get install -y terraform terragrunt; then
        log_error "Failed to install Terraform"
        return 1
    fi

    log_info "Terraform and Terragrunt installed successfully"
}

# Install Google Cloud SDK
install_gcloud() {
    log_step "Installing Google Cloud SDK..."

    # Check if already installed
    if command -v gcloud &> /dev/null; then
        log_warn "Google Cloud SDK already installed"
        return 0
    fi

    # Add Google Cloud SDK repository
    if ! grep -q "google-cloud-sdk" /etc/apt/sources.list.d/* 2>/dev/null; then
        echo "deb [signed-by=/usr/share/keyrings/google-cloud-sdk-archive-keyring.gpg] https://packages.cloud.google.com/apt $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/google-cloud-sdk.list

        wget -q https://packages.cloud.google.com/apt/doc/apt-key.gpg -O /usr/share/keyrings/google-cloud-sdk-archive-keyring.gpg
        apt-get update -y
    fi

    # Install Google Cloud SDK
    if ! apt-get install -y google-cloud-sdk; then
        log_error "Failed to install Google Cloud SDK"
        return 1
    fi

    log_info "Google Cloud SDK installed successfully"
}

# Export functions for use in main script
export -f install_vscode install_claude_code install_claude_skills configure_claude_openrouter
export -f install_openrouter install_claude_code_router install_chromium install_ghcli
export -f install_bun install_terraform install_gcloud