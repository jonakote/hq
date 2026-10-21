#!/usr/bin/env bash
# ==============================================================================
# Jenkins Restore Script
# Restores Jenkins from a backup archive
# ==============================================================================
set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
JENKINS_HOME="${JENKINS_HOME:-./jenkins-home}"
BACKUP_DIR="${BACKUP_DIR:-./backups}"

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }

# ── Usage ────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
${BOLD}Jenkins Restore Script${NC}

${BOLD}USAGE${NC}
    $0 <backup-file>

${BOLD}EXAMPLES${NC}
    # Restore from specific backup
    $0 backups/jenkins_backup_20240101_120000.tar.gz

    # Restore latest backup
    $0 latest

${BOLD}OPTIONS${NC}
    latest    Restore the most recent backup
    list      List available backups
    help      Show this help message
EOF
}

# ── List Backups ─────────────────────────────────────────────────────────────
list_backups() {
    info "Available backups:"
    echo ""
    
    if ! ls -1 "${BACKUP_DIR}"/jenkins_backup_*.tar.gz &>/dev/null; then
        warn "No backups found in ${BACKUP_DIR}"
        exit 1
    fi
    
    ls -lh "${BACKUP_DIR}"/jenkins_backup_*.tar.gz | awk '{print "  " $9 " (" $5 ")"}'
    echo ""
}

# ── Restore ──────────────────────────────────────────────────────────────────
restore() {
    local backup_file="$1"
    
    # Handle "latest" keyword
    if [[ "$backup_file" == "latest" ]]; then
        backup_file=$(ls -1t "${BACKUP_DIR}"/jenkins_backup_*.tar.gz 2>/dev/null | head -1)
        if [[ -z "$backup_file" ]]; then
            error "No backups found in ${BACKUP_DIR}"
            exit 1
        fi
        info "Using latest backup: $backup_file"
    fi
    
    # Verify backup exists
    if [[ ! -f "$backup_file" ]]; then
        error "Backup file not found: $backup_file"
        exit 1
    fi
    
    # Confirm
    echo ""
    echo -e "${YELLOW}${BOLD}WARNING: This will overwrite your current Jenkins data!${NC}"
    echo -e "Backup file: ${backup_file}"
    echo -e "Target:      ${JENKINS_HOME}"
    echo ""
    echo -en "Are you sure? [y/N]: "
    read -r confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "Restore cancelled"
        exit 0
    fi
    
    # Stop Jenkins
    info "Stopping Jenkins container..."
    docker stop jenkins-master 2>/dev/null || warn "Jenkins container not running"
    
    # Backup current state
    if [[ -d "$JENKINS_HOME" ]]; then
        info "Creating backup of current state..."
        local current_backup="${JENKINS_HOME}_before_restore_$(date +%Y%m%d_%H%M%S)"
        mv "$JENKINS_HOME" "$current_backup"
        success "Current state saved to: $current_backup"
    fi
    
    # Restore
    info "Restoring from backup..."
    mkdir -p "$JENKINS_HOME"
    
    if tar -xzf "$backup_file" -C "$(dirname "$JENKINS_HOME")" --strip-components=1; then
        success "Backup restored successfully!"
    else
        error "Restore failed!"
        
        # Try to restore previous state
        if [[ -d "$current_backup" ]]; then
            warn "Restoring previous state..."
            rm -rf "$JENKINS_HOME"
            mv "$current_backup" "$JENKINS_HOME"
        fi
        
        # Restart Jenkins
        docker start jenkins-master 2>/dev/null || true
        exit 1
    fi
    
    # Fix permissions
    info "Fixing permissions..."
    if [[ "$(uname -s)" != "Darwin" ]]; then
        chown -R "$(id -u):$(id -g)" "$JENKINS_HOME" 2>/dev/null || true
    fi
    
    # Start Jenkins
    info "Starting Jenkins container..."
    docker start jenkins-master
    
    echo ""
    success "Jenkins has been restored from backup!"
    echo -e "${BLUE}[INFO]${NC}  Jenkins will be available at: http://localhost:8080"
    echo -e "${BLUE}[INFO]${NC}  Wait ~30 seconds for Jenkins to fully start"
    echo ""
}

# ── Main ─────────────────────────────────────────────────────────────────────
case "${1:-help}" in
    latest)
        restore "latest"
        ;;
    list)
        list_backups
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        if [[ -f "$1" ]] || [[ "$1" == latest ]]; then
            restore "$1"
        else
            error "Unknown command or file: $1"
            usage
            exit 1
        fi
        ;;
esac
