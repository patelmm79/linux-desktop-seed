#!/bin/bash
set -euo pipefail

# Remote Linux Desktop Deployment Script - Modular Version
# Deploys: GNOME, xrdp, VS Code, Claude Code, Chromium, OpenRouter
# Target: Ubuntu 20.04/22.04/24.04

SCRIPT_VERSION="2.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
LOG_FILE="/tmp/deploy-desktop-$(date +%Y%m%d-%H%M%S).log"
TARGET_USER="desktopuser"

# Dry run mode - preview what would be installed without actually installing
DRY_RUN=false
for arg in "$@"; do
    case "$arg" in
        --dry-run|--preview)
            DRY_RUN=true
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run, --preview  Show what would be installed without installing"
            echo "  --help, -h            Show this help message"
            echo ""
            exit 0
            ;;
    esac
done

# Source all modules
source "$SCRIPT_DIR/scripts/deploy/lib.sh"
source "$SCRIPT_DIR/scripts/deploy/system.sh"
source "$SCRIPT_DIR/scripts/deploy/dev-tools.sh"
source "$SCRIPT_DIR/scripts/deploy/ai-tools.sh"
source "$SCRIPT_DIR/scripts/deploy/monitoring.sh"
source "$SCRIPT_DIR/scripts/deploy/configure.sh"

# Main function
main() {
    # Handle dry-run mode
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "========================================="
        echo "  DRY RUN MODE - No changes will be made"
        echo "========================================="
        echo ""
        log_info "This would install the following components:"
        log_info "  - GNOME Desktop"
        log_info "  - xrdp (RDP server)"
        log_info "  - Visual Studio Code"
        log_info "  - Claude Code"
        log_info "  - OpenRouter CLI"
        log_info "  - Claude Code Router"
        log_info "  - Chromium Browser"
        log_info "  - GitHub CLI"
        log_info "  - Bun runtime"
        log_info "  - OpenCLAW"
        log_info "  - Terraform & Terragrunt"
        log_info "  - Google Cloud SDK"
        log_info "  - Session monitoring"
        log_info "  - GNOME extensions"
        echo ""
        log_info "To run this deployment:"
        log_info "  sudo bash deploy-desktop.sh"
        echo ""
        exit 0
    fi

    log_info "Starting Remote Desktop Deployment v$SCRIPT_VERSION"
    log_info "Log file: $LOG_FILE"

    check_root
    detect_ubuntu_version

    # System setup
    update_system
    install_gnome
    configure_xwrapper
    install_xrdp
    create_desktop_user
    copy_desktop_configs

    # Development tools
    install_vscode
    install_claude_code
    install_claude_skills
    configure_claude_openrouter
    install_openrouter
    install_claude_code_router
    install_chromium
    install_ghcli
    install_bun
    install_terraform
    install_gcloud

    # AI tools
    install_openclaw
    setup_openclaw_wrapper
    setup_openclaw_config
    setup_openclaw_lock_config
    setup_openclaw_validate_config
    setup_openclaw_backup_config

    # Configuration
    setup_environment
    configure_mcp_servers
    create_desktop_shortcuts

    # Monitoring & reliability
    setup_keyring
    setup_monitoring
    setup_gnome_extensions

    # Optional features
    setup_token_rotation_cron
    setup_github_issues

    # Validation
    validate_deployment
    show_summary

    log_info "System ready for deployment"
}

main "$@"