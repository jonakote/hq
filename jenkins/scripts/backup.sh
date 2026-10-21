#!/usr/bin/env bash
# ==============================================================================
# Jenkins Backup Script
# Creates a timestamped backup of Jenkins configuration and data
# ==============================================================================
set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
JENKINS_HOME="${JENKINS_HOME:-./jenkins-home}"
BACKUP_DIR="${BACKUP_DIR:-./backups}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_NAME="jenkins_backup_${TIMESTAMP}"
BACKUP_FILE="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
RETENTION_DAYS="${RETENTION_DAYS:-7}"

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }

# ── Pre-flight Checks ───────────────────────────────────────────────────────
if [[ ! -d "$JENKINS_HOME" ]]; then
    error "Jenkins home directory not found: $JENKINS_HOME"
    error "Set JENKINS_HOME environment variable or run from the correct directory"
    exit 1
fi

# Create backup directory
mkdir -p "$BACKUP_DIR"

# ── Backup ───────────────────────────────────────────────────────────────────
info "Starting Jenkins backup..."
info "Jenkins home: $JENKINS_HOME"
info "Backup file:  $BACKUP_FILE"
echo ""

# Optional: Stop Jenkins container before backup
if [[ "${1:-}" == "--stop" ]]; then
    warn "Stopping Jenkins container for consistent backup..."
    docker stop jenkins-master 2>/dev/null || true
    STOPPED=true
fi

# Create backup
info "Creating archive..."
if tar -czf "$BACKUP_FILE" \
    --exclude='*.log' \
    --exclude='workspace/**' \
    --exclude='caches/**' \
    --exclude='*.tmp' \
    -C "$(dirname "$JENKINS_HOME")" \
    "$(basename "$JENKINS_HOME")" 2>/dev/null; then
    
    # Get file size
    BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    
    success "Backup created successfully!"
    echo ""
    echo -e "  File: ${BACKUP_FILE}"
    echo -e "  Size: ${BACKUP_SIZE}"
    echo ""
else
    error "Backup failed!"
    rm -f "$BACKUP_FILE"
    
    # Restart Jenkins if we stopped it
    if [[ "${STOPPED:-}" == "true" ]]; then
        info "Restarting Jenkins container..."
        docker start jenkins-master 2>/dev/null || true
    fi
    exit 1
fi

# Restart Jenkins if we stopped it
if [[ "${STOPPED:-}" == "true" ]]; then
    info "Restarting Jenkins container..."
    docker start jenkins-master 2>/dev/null || true
fi

# ── Cleanup Old Backups ──────────────────────────────────────────────────────
info "Cleaning up backups older than ${RETENTION_DAYS} days..."
DELETED=$(find "$BACKUP_DIR" -name "jenkins_backup_*.tar.gz" -mtime +${RETENTION_DAYS} -delete -print | wc -l)

if [[ "$DELETED" -gt 0 ]]; then
    success "Removed ${DELETED} old backup(s)"
else
    info "No old backups to remove"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}Backup Summary${NC}"
echo -e "  Total backups: $(ls -1 "$BACKUP_DIR"/jenkins_backup_*.tar.gz 2>/dev/null | wc -l)"
echo -e "  Total size:    $(du -sh "$BACKUP_DIR" | cut -f1)"
echo -e "  Latest backup: ${BACKUP_FILE}"
echo ""
