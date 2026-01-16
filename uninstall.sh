#!/bin/bash

##############################################################################
# PTERODACTYL PROTECTION UNINSTALLER v3.0
# Remove all protection system & restore backups
##############################################################################

set -e

PTERODACTYL_PATH="/var/www/pterodactyl"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${YELLOW}[INFO] $1${NC}"; }
ok() { echo -e "${GREEN}[OK] $1${NC}"; }
err() { echo -e "${RED}[ERROR] $1${NC}"; }

echo ""
echo "=========================================="
echo "🧹 PTERODACTYL PROTECTION UNINSTALLER"
echo "=========================================="
echo ""

##############################################################################
# 1. REMOVE PROTECTION SERVICE
##############################################################################
info "Removing ProtectionService..."
rm -rf "${PTERODACTYL_PATH}/app/Services/Protection"
ok "ProtectionService removed"

##############################################################################
# 2. REMOVE PROTECTION CONTROLLER
##############################################################################
info "Removing ProtectionController..."
rm -f "${PTERODACTYL_PATH}/app/Http/Controllers/Admin/ProtectionController.php"
ok "ProtectionController removed"

##############################################################################
# 3. RESTORE BACKUPS (ServerCreationService, API, Admin ServerController)
##############################################################################
info "Restoring backups..."

find "${PTERODACTYL_PATH}" -type f -name "*.bak_*" | while read file; do
    original="${file%.bak_*}"
    mv "$file" "$original"
    echo "Restored: $original"
done

ok "All backup files restored"

##############################################################################
# 4. REMOVE CUSTOM 403 PAGE
##############################################################################
info "Removing custom 403 error page..."
rm -f "${PTERODACTYL_PATH}/resources/views/errors/403.blade.php"
ok "403 page removed"

##############################################################################
# 5. REMOVE PROTECTION SETTINGS UI
##############################################################################
info "Removing protection settings UI..."
rm -rf "${PTERODACTYL_PATH}/resources/views/admin/protection"
ok "Protection UI removed"

##############################################################################
# 6. REMOVE ROUTES
##############################################################################
ROUTES_FILE="${PTERODACTYL_PATH}/routes/base/admin.php"

info "Cleaning protection routes..."
sed -i '/Protection Settings (Admin Only)/,/});/d' "$ROUTES_FILE"
ok "Protection routes removed"

##############################################################################
# 7. REMOVE SIDEBAR MENU
##############################################################################
SIDEBAR_FILE="${PTERODACTYL_PATH}/resources/views/layouts/admin.blade.php"

info "Removing sidebar menu..."
sed -i "/admin.protection/d" "$SIDEBAR_FILE"
ok "Sidebar menu removed"

##############################################################################
# 8. CLEAR CACHE
##############################################################################
info "Clearing cache..."
cd "$PTERODACTYL_PATH"
php artisan cache:clear || true
php artisan config:clear || true
php artisan view:clear || true
ok "Cache cleared"

##############################################################################
# 9. PERMISSIONS
##############################################################################
chown -R www-data:www-data "$PTERODACTYL_PATH"

##############################################################################
# DONE
##############################################################################
echo ""
echo "=========================================="
echo "✅ UNINSTALL COMPLETE"
echo "=========================================="
echo ""
echo "All protection system has been removed."
echo "Panel restored to original state."
echo ""