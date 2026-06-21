#!/bin/bash

# Backup script for vocabulary data
# Backs up JSON files and database

BACKUP_DIR="backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="vocabulary_backup_${DATE}"

echo "📦 Creating backup: ${BACKUP_NAME}"

# Create backup directory
mkdir -p ${BACKUP_DIR}

# Backup JSON files (master data)
echo "  ✓ Backing up JSON files..."
tar -czf ${BACKUP_DIR}/${BACKUP_NAME}_json.tar.gz content/packs/*.json

# Backup database
echo "  ✓ Backing up database..."
cp vocabulary.db ${BACKUP_DIR}/${BACKUP_NAME}_db.sqlite

# Get sizes
JSON_SIZE=$(du -h ${BACKUP_DIR}/${BACKUP_NAME}_json.tar.gz | cut -f1)
DB_SIZE=$(du -h ${BACKUP_DIR}/${BACKUP_NAME}_db.sqlite | cut -f1)

echo "✅ Backup complete!"
echo "   JSON backup: ${JSON_SIZE}"
echo "   Database backup: ${DB_SIZE}"
echo "   Location: ${BACKUP_DIR}/"

# Keep only last 5 backups
echo "🧹 Cleaning old backups..."
ls -t ${BACKUP_DIR}/*_json.tar.gz | tail -n +6 | xargs rm -f 2>/dev/null
ls -t ${BACKUP_DIR}/*_db.sqlite | tail -n +6 | xargs rm -f 2>/dev/null

echo "✅ Done!"
