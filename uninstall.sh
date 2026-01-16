#!/bin/bash

##############################################################################
# PTERODACTYL PROTECTION UNINSTALLER v3.1
# Date: 2026-01-17
# Description: Reverts all protection changes to default
##############################################################################

set -euo pipefail

echo ""
echo "=========================================="
echo "🔧 PTERODACTYL PROTECTION UNINSTALLER v3.1"
echo "=========================================="
echo ""

PTERODACTYL_PATH="/var/www/pterodactyl"
ERROR_COUNT=0
RESTORED_ITEMS=()
DELETED_ITEMS=()
SKIPPED_ITEMS=()

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Functions
handle_error() { 
    echo -e "${RED}[ERROR] $1${NC}" 
    ERROR_COUNT=$((ERROR_COUNT + 1))
    SKIPPED_ITEMS+=("❌ $1")
}

handle_success() { 
    echo -e "${GREEN}[OK] $1${NC}" 
    RESTORED_ITEMS+=("✅ $1")
}

handle_info() { echo -e "${YELLOW}[INFO] $1${NC}"; }
handle_title() { echo -e "${BLUE}[UNINSTALL] $1${NC}"; }
handle_warning() { echo -e "${YELLOW}[WARNING] $1${NC}"; }

##############################################################################
# 1. RESTORE BACKUP FILES
##############################################################################
handle_title "Scanning for backup files..."

# Find all backup files created by installer (pattern: .bak_YYYYMMDD_HHMMSS)
BACKUP_FILES=$(find "${PTERODACTYL_PATH}" -name "*.bak_*" -type f 2>/dev/null || true)

if [[ -z "$BACKUP_FILES" ]]; then
    handle_warning "No backup files found - skipping restore"
else
    echo "Found $(echo "$BACKUP_FILES" | wc -l) backup files"
    
    while IFS= read -r backup_file; do
        original_file="${backup_file%.bak_*}"
        
        if [[ -f "$original_file" ]]; then
            # Check if original file was modified recently (by installer)
            if diff -q "$original_file" "$backup_file" >/dev/null 2>&1; then
                handle_info "No changes detected: $(basename "$original_file")"
                continue
            fi
            
            # Restore backup
            if cp -f "$backup_file" "$original_file" 2>/dev/null; then
                handle_success "Restored: $(basename "$original_file")"
            else
                handle_error "Failed to restore: $(basename "$original_file")"
            fi
        else
            # Original file missing, just remove backup
            handle_warning "Original missing, removing backup: $(basename "$backup_file")"
            rm -f "$backup_file"
        fi
    done <<< "$BACKUP_FILES"
fi

##############################################################################
# 2. DELETE PROTECTION FILES
##############################################################################
handle_title "Removing protection files..."

# List of files/directories to delete
PROTECTION_ITEMS=(
    "${PTERODACTYL_PATH}/app/Services/Protection"
    "${PTERODACTYL_PATH}/app/Http/Controllers/Admin/ProtectionController.php"
    "${PTERODACTYL_PATH}/app/Http/Controllers/Api/Client/ServerStoreController.php"
    "${PTERODACTYL_PATH}/resources/views/admin/protection"
    "${PTERODACTYL_PATH}/resources/views/errors/403.blade.php"
)

for item in "${PROTECTION_ITEMS[@]}"; do
    if [[ -e "$item" ]]; then
        if rm -rf "$item" 2>/dev/null; then
            DELETED_ITEMS+=("🗑️  $(basename "$item")")
            handle_success "Deleted: $(basename "$item")"
        else
            handle_error "Failed to delete: $(basename "$item")"
        fi
    else
        handle_info "Already removed: $(basename "$item")"
    fi
done

##############################################################################
# 3. REMOVE PROTECTION ROUTES
##############################################################################
handle_title "Removing protection routes..."

ROUTES_FILES=(
    "${PTERODACTYL_PATH}/routes/base/admin.php"
    "${PTERODACTYL_PATH}/routes/admin.php"
    "${PTERODACTYL_PATH}/routes/web.php"
)

for routes_file in "${ROUTES_FILES[@]}"; do
    if [[ -f "$routes_file" ]] && grep -q "admin.protection" "$routes_file"; then
        # Create backup before modification
        cp "$routes_file" "$routes_file.uninstall_bak_$(date +%Y%m%d_%H%M%S)"
        
        # Remove the protection routes block
        if sed -i '/^\/\/ Protection Settings (Admin Only) - Added by v3.1 Installer/,/^});\s*$/d' "$routes_file" 2>/dev/null; then
            handle_success "Removed routes from: $(basename "$routes_file")"
        else
            handle_warning "Could not auto-remove routes from: $(basename "$routes_file")"
            SKIPPED_ITEMS+=("⚠️  Manual: Remove protection routes from $routes_file")
        fi
    elif [[ -f "$routes_file" ]]; then
        handle_info "No protection routes found in: $(basename "$routes_file")"
    fi
done

##############################################################################
# 4. REMOVE PROTECTION MENU FROM SIDEBAR
##############################################################################
handle_title "Removing protection menu..."

SIDEBAR_FILE="${PTERODACTYL_PATH}/resources/views/layouts/admin.blade.php"
if [[ -f "$SIDEBAR_FILE" ]] && grep -q "admin.protection" "$SIDEBAR_FILE"; then
    # Create backup
    cp "$SIDEBAR_FILE" "$SIDEBAR_FILE.uninstall_bak_$(date +%Y%m%d_%H%M%S)"
    
    # Remove menu line
    if sed -i '/admin\.protection/d' "$SIDEBAR_FILE" 2>/dev/null; then
        handle_success "Removed protection menu from sidebar"
    else
        handle_warning "Could not auto-remove menu from sidebar"
        SKIPPED_ITEMS+=("⚠️  Manual: Remove menu item with 'admin.protection' from $SIDEBAR_FILE")
    fi
else
    handle_info "No protection menu found in sidebar"
fi

##############################################################################
# 5. CLEAR LARAVEL CACHE
##############################################################################
handle_title "Clearing Laravel cache..."
cd "${PTERODACTYL_PATH}" || exit 1

php artisan cache:clear 2>/dev/null && handle_success "Cache cleared" || handle_info "Cache clear skipped"
php artisan config:clear 2>/dev/null && handle_success "Config cache cleared" || handle_info "Config clear skipped"
php artisan view:clear 2>/dev/null && handle_success "View cache cleared" || handle_info "View clear skipped"

##############################################################################
# 6. REMOVE DATABASE SETTINGS
##############################################################################
handle_title "Removing database settings..."

# Remove proteksi::* settings from DB
if php artisan tinker --execute="DB::table('settings')->where('key', 'like', 'proteksi::%')->delete(); echo \"Done\";" >/dev/null 2>&1; then
    handle_success "Removed protection settings from database"
else
    handle_warning "Could not remove DB settings via tinker"
    
    # Try direct SQL as fallback
    DB_CONNECTION=$(grep DB_CONNECTION .env | cut -d'=' -f2)
    DB_DATABASE=$(grep DB_DATABASE .env | cut -d'=' -f2)
    
    if [[ "$DB_CONNECTION" == "mysql" ]] && command -v mysql >/dev/null; then
        DB_USER=$(grep DB_USERNAME .env | cut -d'=' -f2)
        DB_PASS=$(grep DB_PASSWORD .env | cut -d'=' -f2)
        
        mysql -u"$DB_USER" -p"$DB_PASS" -D"$DB_DATABASE" -e "DELETE FROM settings WHERE key LIKE 'proteksi::%';" 2>/dev/null && \
            handle_success "Removed DB settings via MySQL" || \
            handle_info "Could not remove DB settings via MySQL"
    else
        SKIPPED_ITEMS+=("⚠️  Manual: Remove settings with key LIKE 'proteksi::%' from settings table")
    fi
fi

##############################################################################
# 7. RESTORE PERMISSIONS
##############################################################################
handle_title "Restoring permissions..."
sudo chown -R www-data:www-data "${PTERODACTYL_PATH}" 2>/dev/null && \
    handle_success "Permissions restored to www-data" || \
    handle_info "Permission restore skipped (run manually if needed)"

##############################################################################
# SUMMARY
##############################################################################
echo ""
echo "=========================================="
echo "✅ UNINSTALLATION COMPLETE - v3.1"
echo "=========================================="
echo ""

if [[ ${#RESTORED_ITEMS[@]} -gt 0 ]]; then
    echo "📦 FILES RESTORED:"
    printf "   %s\n" "${RESTORED_ITEMS[@]}"
    echo ""
fi

if [[ ${#DELETED_ITEMS[@]} -gt 0 ]]; then
    echo "🗑️  FILES DELETED:"
    printf "   %s\n" "${DELETED_ITEMS[@]}"
    echo ""
fi

if [[ ${#SKIPPED_ITEMS[@]} -gt 0 ]]; then
    echo "⚠️  MANUAL STEPS NEEDED:"
    printf "   %s\n" "${SKIPPED_ITEMS[@]}"
    echo ""
fi

echo "🔙 SYSTEM STATUS:"
echo "   ✓ Backup files restored (if found)"
echo "   ✓ Protection files removed"
echo "   ✓ Routes cleaned (if found)"
echo "   ✓ Menu items removed (if found)"
echo "   ✓ Cache cleared"
echo "   ✓ Database settings removed (if accessible)"
echo ""
echo "📌 NOTE:"
echo "   Your Pterodactyl panel is now back to DEFAULT state"
echo "   All custom 403 pages and server limits have been removed"
echo ""
echo "=========================================="

if [ $ERROR_COUNT -eq 0 ]; then
    handle_success "Uninstallation completed successfully!"
    handle_info "Your panel is now running in normal mode"
    exit 0
else
    handle_error "Uninstall completed with $ERROR_COUNT error(s)"
    handle_info "Please fix the issues manually"
    exit 1
fi