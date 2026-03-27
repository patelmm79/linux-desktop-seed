#!/bin/bash
# Backup - Backup desktop configuration
# Usage: sudo bash scripts/backup.sh [--restore]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

source "$PROJECT_ROOT/config.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

BACKUP_DIR="${BACKUP_DIR:-$HOME/.config/desktop-seed/backups}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="desktop-backup-$TIMESTAMP.tar.gz"

# Create backup directory
mkdir -p "$BACKUP_DIR"

do_backup() {
    log_info "Creating backup..."

    # Files to backup
    FILES=(
        "$HOME/.claude.json"
        "$HOME/.config/claude/"
        "$HOME/.config/desktop-seed/"
        "$HOME/.config/openrouter/"
        "$HOME/Desktop/*.desktop"
        "$HOME/.bashrc"
    )

    # Create tarball
    local tar_files=""
    for file in "${FILES[@]}"; do
        if ls $file &> /dev/null 2>&1; then
            tar_files="$tar_files $file"
        fi
    done

    if [[ -z "$tar_files" ]]; then
        log_warn "No files to backup"
        return 1
    fi

    cd "$HOME"
    tar -czf "$BACKUP_DIR/$BACKUP_FILE" $tar_files 2>/dev/null || true

    log_info "Backup created: $BACKUP_DIR/$BACKUP_FILE"

    # List contents
    log_info "Backup contains:"
    tar -tzf "$BACKUP_DIR/$BACKUP_FILE" | head -20 | while read -r line; do
        echo "  - $line"
    done

    # Clean old backups (keep last 10)
    local backup_count=$(ls -1 "$BACKUP_DIR"/desktop-backup-*.tar.gz 2>/dev/null | wc -l)
    if [[ "$backup_count" -gt 10 ]]; then
        log_info "Cleaning old backups (keeping 10 latest)..."
        ls -1t "$BACKUP_DIR"/desktop-backup-*.tar.gz | tail -n +11 | xargs -r rm
    fi
}

do_restore() {
    local latest_backup=$(ls -t "$BACKUP_DIR"/desktop-backup-*.tar.gz 2>/dev/null | head -1)

    if [[ -z "$latest_backup" ]]; then
        log_error "No backup found to restore"
        return 1
    fi

    log_info "Restoring from: $latest_backup"
    log_warn "This will overwrite existing files!"

    read -p "Continue? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        log_info "Restore cancelled"
        return 0
    fi

    cd "$HOME"
    tar -xzf "$latest_backup"

    log_info "Restore complete!"
    log_info "Restart Claude Code or reboot to apply changes"
}

# Main
if [[ "${1:-}" == "--restore" ]]; then
    do_restore
elif [[ "${1:-}" == "--list" ]]; then
    log_info "Available backups:"
    ls -lh "$BACKUP_DIR"/desktop-backup-*.tar.gz 2>/dev/null || log_info "No backups found"
else
    do_backup
fi
