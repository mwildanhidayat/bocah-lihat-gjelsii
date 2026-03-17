#!/usr/bin/env bash
# =============================================================================
# Pterodactyl Protect Installer
# Download langsung dari repository dan install semua proteksi
# ©Protect By @WiL Official
# =============================================================================

set -euo pipefail

# Warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}===========================================${NC}"
echo -e "${GREEN}🚀 Pterodactyl Protect Installer${NC}"
echo -e "${YELLOW}© Protect By @WiL Official${NC}"
echo -e "${BLUE}===========================================${NC}"

# URL download file proteksi
PROTEK_URL="https://github.com/mwildanhidayat/installer-pterodactyl/raw/refs/heads/main/proteksi/Protect-panel.zip"
PANEL_DIR="/var/www/pterodactyl"
TEMP_DIR="/tmp/pterodactyl-proteksi-$$"

# Cek apakah panel terinstall
if [[ ! -d "$PANEL_DIR" ]]; then
    echo -e "${RED}❌ Error: Pterodactyl panel tidak ditemukan di $PANEL_DIR${NC}"
    echo "Pastikan panel sudah terinstall sebelum menjalankan installer ini."
    exit 1
fi

# Cek apakah unzip tersedia
if ! command -v unzip &> /dev/null; then
    echo -e "${YELLOW}📦 Menginstall unzip...${NC}"
    apt-get update && apt-get install -y unzip
fi

# Cek apakah curl tersedia
if ! command -v curl &> /dev/null; then
    echo -e "${YELLOW}📦 Menginstall curl...${NC}"
    apt-get update && apt-get install -y curl
fi

# Backup otomatis
echo -e "${YELLOW}📦 Membuat backup panel...${NC}"
BACKUP_DIR="${PANEL_DIR}.bak.$(date +%Y%m%d-%H%M%S)"
cp -a "$PANEL_DIR" "$BACKUP_DIR"
echo -e "${GREEN}✅ Backup disimpan di: $BACKUP_DIR${NC}"

# Buat temporary directory
echo -e "${YELLOW}📂 Membuat temporary directory...${NC}"
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

# Download file proteksi
echo -e "${YELLOW}📥 Mendownload file proteksi...${NC}"
curl -L -o Protect-panel.zip "$PROTEK_URL"

# Cek apakah download berhasil
if [[ ! -f "Protect-panel.zip" ]]; then
    echo -e "${RED}❌ Error: Gagal mendownload file proteksi${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Ekstrak file zip
echo -e "${YELLOW}📦 Mengekstrak file proteksi...${NC}"
unzip -o Protect-panel.zip -d extracted

# Cek apakah ekstrak berhasil
if [[ ! -d "extracted" ]]; then
    echo -e "${RED}❌ Error: Gagal mengekstrak file zip${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Pindah ke folder extracted
cd extracted

echo -e "${YELLOW}📂 Menginstal file proteksi...${NC}"

# Mapping file PHP ke path tujuan
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

# Hitung total file
total_files=${#FILES[@]}
current=0

# Copy file satu per satu
for src in "${!FILES[@]}"; do
    dest="${FILES[$src]}"
    full_dest="$PANEL_DIR/$dest"
    
    if [[ -f "$src" ]]; then
        mkdir -p "$(dirname "$full_dest")"
        cp -f "$src" "$full_dest"
        current=$((current + 1))
        echo -e "${GREEN}✓${NC} [$current/$total_files] $src → $dest"
    else
        echo -e "${RED}⚠ File $src tidak ditemukan dalam zip${NC}"
    fi
done

# Copy file sidebar patcher
if [[ -f "admin.blade.php" ]]; then
    echo -e "${YELLOW}🛡️ Mengaplikasikan proteksi sidebar...${NC}"
    cp -f "admin.blade.php" "$PANEL_DIR/"
    cd "$PANEL_DIR"
    php admin.blade.php
    rm -f "$PANEL_DIR/admin.blade.php"
    echo -e "${GREEN}✓ Sidebar berhasil diproteksi (hanya Admin ID 1 yang terlihat)${NC}"
else
    echo -e "${RED}⚠ File admin.blade.php tidak ditemukan dalam zip${NC}"
fi

# Bersihkan temporary directory
echo -e "${YELLOW}🧹 Membersihkan temporary files...${NC}"
rm -rf "$TEMP_DIR"

# Optimasi Laravel
echo -e "${YELLOW}⚡ Mengoptimasi panel...${NC}"
cd "$PANEL_DIR"
php artisan optimize:clear
php artisan config:cache
php artisan route:cache
php artisan view:cache

# Atur permission
echo -e "${YELLOW}🔐 Mengatur permission...${NC}"
chown -R www-data:www-data "$PANEL_DIR"
find "$PANEL_DIR/storage" -type d -exec chmod 775 {} \;
find "$PANEL_DIR/bootstrap/cache" -type d -exec chmod 775 {} \;

# Output hasil
echo -e "${BLUE}===========================================${NC}"
echo -e "${GREEN}✅ INSTALASI SELESAI!${NC}"
echo ""
echo -e "${YELLOW}Fitur yang diproteksi (hanya Admin ID 1):${NC}"
echo "• Nodes, Nests, Locations"
echo "• Databases, Settings, API, Mounts"
echo "• Semua aksi admin pada server orang lain"
echo "  (transfer, delete, reinstall, dll.)"
echo ""
echo -e "${YELLOW}Untuk restart services:${NC}"
echo "sudo systemctl restart nginx"
echo "sudo systemctl restart php8.1-fpm    # atau versi PHP Anda"
echo ""
echo -e "${YELLOW}Backup panel lama:${NC} $BACKUP_DIR"
echo -e "${BLUE}===========================================${NC}"
echo -e "${GREEN}Terima kasih telah menggunakan ©Protect By @WiL Official${NC}"