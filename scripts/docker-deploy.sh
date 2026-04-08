#!/bin/bash
# Docker deployment script for OpenCLAW
# Validates .env has required keys, then deploys via docker compose

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_ROOT/.env"

# Required environment variables
REQUIRED_VARS=(
    "OPENROUTER_API_KEY"
    "DISCORD_BOT_TOKEN"
    "DISCORD_ALLOWLIST_IDS"
    "DISCORD_CHANNEL_ID"
)

# Logging
log_info() { echo "[INFO] $*"; }
log_warn() { echo "[WARN] $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }

# Validate .env file
validate_env() {
    log_info "Validating environment file..."

    if [ ! -f "$ENV_FILE" ]; then
        log_error ".env file not found at $ENV_FILE"
        log_info "Copy .env.example to .env and fill in your values"
        return 1
    fi

    # Source the env file to check values
    set -a
    source "$ENV_FILE"
    set +a

    local missing=()
    for var in "${REQUIRED_VARS[@]}"; do
        local value="${!var}"
        if [ -z "$value" ]; then
            missing+=("$var")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing required environment variables:"
        for var in "${missing[@]}"; do
            log_error "  - $var"
        done
        return 1
    fi

    log_info "Environment validation passed"
    return 0
}

# Build and start containers
deploy() {
    log_info "Building and starting OpenCLAW container..."

    cd "$PROJECT_ROOT"

    if ! docker compose up -d --build; then
        log_error "Failed to start containers"
        return 1
    fi

    log_info "Container started successfully"

    # Wait for health check
    log_info "Waiting for container to become healthy..."
    sleep 10

    # Show status
    docker compose ps

    log_info "OpenCLAW is running!"
    log_info "View logs: docker compose logs -f openclaw"
    log_info "Stop: docker compose down"

    return 0
}

# Main
main() {
    log_info "OpenCLAW Docker Deployment"

    if ! validate_env; then
        exit 1
    fi

    if ! deploy; then
        exit 1
    fi
}

main "$@"