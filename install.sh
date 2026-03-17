#!/usr/bin/env bash
# =============================================================================
# Pterodactyl Protect Installer
# Satu file bash untuk menginstal SEMUA proteksi ©Protect By @WiL Official
# Tidak mengandung kode PHP di dalamnya — hanya menyalin file-file yang ada
# di folder Panel-protek/
# =============================================================================

set -euo pipefail

echo "==========================================="
echo "🚀 Pterodactyl Protect Installer"
echo "© Protect By @WiL Official"
echo "==========================================="

PANEL_DIR="/var/www/pterodactyl"
PROTEK_DIR="./Protect-panel"

# Cek keberadaan panel dan folder protek
if [[ ! -d "$PANEL_DIR" ]]; then
    echo "❌ Error: Pterodactyl panel tidak ditemukan di $PANEL_DIR"
    echo "Pastikan panel sudah terinstall sebelum menjalankan installer ini."
    exit 1
fi

if [[ ! -d "$PROTEK_DIR" ]]; then
    echo "❌ Error: Folder tidak ditemukan!"
    echo "Pastikan Anda berada di root repo dan folder berisi semua file PHP."
    exit 1
fi

# Backup otomatis
echo "📦 Membuat backup panel..."
BACKUP_DIR="${PANEL_DIR}.bak.$(date +%Y%m%d-%H%M%S)"
cp -a "$PANEL_DIR" "$BACKUP_DIR"
echo "✅ Backup disimpan di: $BACKUP_DIR"

echo "📂 Menginstal file proteksi..."

# Mapping file → path tujuan (tidak ada duplikasi kode PHP)
declare -A FILES=(
    ["TwoFactorController.php"]="app/Http/Controllers/Api/Client/TwoFactorController.php"
    ["ServerTransferController.php"]="app/Http/Controllers/Admin/Servers/ServerTransferController.php"
    ["ServersController.php"]="app/Http/Controllers/Admin/ServersController.php"
    ["ReinstallServerService.php"]="app/Services/Servers/ReinstallServerService.php"
    ["NodeController.php"]="app/Http/Controllers/Admin/Nodes/NodeController.php"
    ["NestController.php"]="app/Http/Controllers/Admin/Nests/NestController.php"
    ["ServerDeletionService.php"]="app/Services/Servers/ServerDeletionService.php"
    ["MountController.php"]="app/Http/Controllers/Admin/MountController.php"
    ["StartupModificationService.php"]="app/Services/Servers/StartupModificationService.php"
    ["LocationController.php"]="app/Http/Controllers/Admin/LocationController.php"
    ["IndexController.php"]="app/Http/Controllers/Admin/Settings/IndexController.php"
    ["DetailsModificationService.php"]="app/Services/Servers/DetailsModificationService.php"
    ["ClientServerController.php"]="app/Http/Controllers/Api/Client/Servers/ServerController.php"
    ["BuildModificationService.php"]="app/Services/Servers/BuildModificationService.php"
    ["ApiController.php"]="app/Http/Controllers/Admin/ApiController.php"
    ["ApiKeyController.php"]="app/Http/Controllers/Api/Client/ApiKeyController.php"
    ["DatabaseManagementService.php"]="app/Services/Databases/DatabaseManagementService.php"
    ["FileController.php"]="app/Http/Controllers/Api/Client/Servers/FileController.php"
    ["UserController.php"]="app/Http/Controllers/Admin/UserController.php"
    ["DatabaseController.php"]="app/Http/Controllers/Admin/DatabaseController.php"
    ["ServerController.php"]="app/Http/Controllers/Admin/Servers/ServerController.php"
)

for src in "${!FILES[@]}"; do
    dest="${FILES[$src]}"
    full_dest="$PANEL_DIR/$dest"
    
    mkdir -p "$(dirname "$full_dest")"
    cp "$PROTEK_DIR/$src" "$full_dest"
    echo "✓ $src → $dest"
done

# Jalankan script proteksi sidebar (admin.blade.php adalah patcher, bukan blade asli)
echo "🛡️ Mengaplikasikan proteksi sidebar..."
php "$PROTEK_DIR/admin.blade.php"
echo "✓ Sidebar berhasil diproteksi (hanya ID 1 yang terlihat)"

# Optimasi Laravel
echo "⚡ Mengoptimasi panel..."
cd "$PANEL_DIR"
php artisan optimize:clear
php artisan config:cache
php artisan route:cache
php artisan view:cache

# Permission
echo "🔐 Mengatur permission..."
chown -R www-data:www-data "$PANEL_DIR"
find "$PANEL_DIR/storage" -type d -exec chmod 775 {} \;
find "$PANEL_DIR/bootstrap/cache" -type d -exec chmod 775 {} \;

echo "==========================================="
echo "✅ INSTALASI SELESAI!"
echo ""
echo "Hanya Admin ID 1 yang dapat mengakses:"
echo "• Nodes, Nests, Locations, Databases, Settings, API, Mounts"
echo "• Semua aksi admin pada server orang lain (transfer, delete, reinstall, dll.)"
echo ""
echo "Restart services:"
echo "sudo systemctl restart nginx"
echo "sudo systemctl restart php8.1-fpm    # atau php-fpm versi Anda"
echo ""
echo "Backup lama: $BACKUP_DIR"
echo "==========================================="
echo "Terima kasih telah menggunakan ©Protect By @WiL Official"
