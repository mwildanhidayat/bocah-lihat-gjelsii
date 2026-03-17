#!/usr/bin/env bash

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

# URL download file proteksi - PASTIKAN URL INI BENAR
PROTEK_URL="https://github.com/mwildanhidayat/installer-pterodactyl/raw/refs/heads/main/proteksi/Protect-panel.zip"
PANEL_DIR="/var/www/pterodactyl"
TEMP_DIR="/tmp/pterodactyl-proteksi-$$"

# Cek apakah dijalankan sebagai root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}❌ Script ini harus dijalankan sebagai root (sudo)${NC}" 
   exit 1
fi

# Cek apakah panel terinstall
if [[ ! -d "$PANEL_DIR" ]]; then
    echo -e "${RED}❌ Error: Pterodactyl panel tidak ditemukan di $PANEL_DIR${NC}"
    echo "Pastikan panel sudah terinstall sebelum menjalankan installer ini."
    exit 1
fi

# Cek dan install dependencies jika diperlukan
echo -e "${YELLOW}🔍 Memeriksa dependencies...${NC}"

if ! command -v unzip &> /dev/null; then
    echo -e "${YELLOW}📦 Menginstall unzip...${NC}"
    apt-get update && apt-get install -y unzip
fi

if ! command -v curl &> /dev/null; then
    echo -e "${YELLOW}📦 Menginstall curl...${NC}"
    apt-get update && apt-get install -y curl
fi

if ! command -v php &> /dev/null; then
    echo -e "${RED}❌ Error: PHP tidak ditemukan${NC}"
    exit 1
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

# Download file proteksi dengan progress bar
echo -e "${YELLOW}📥 Mendownload file proteksi...${NC}"
if curl -L --progress-bar -o Protect-panel.zip "$PROTEK_URL"; then
    echo -e "${GREEN}✅ Download berhasil${NC}"
else
    echo -e "${RED}❌ Error: Gagal mendownload file proteksi${NC}"
    echo "Cek URL: $PROTEK_URL"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Cek ukuran file download
if [[ ! -f "Protect-panel.zip" ]] || [[ $(stat -c%s "Protect-panel.zip") -lt 1000 ]]; then
    echo -e "${RED}❌ Error: File download korup atau terlalu kecil${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Ekstrak file zip
echo -e "${YELLOW}📦 Mengekstrak file proteksi...${NC}"
if unzip -o Protect-panel.zip -d extracted; then
    echo -e "${GREEN}✅ Ekstrak berhasil${NC}"
else
    echo -e "${RED}❌ Error: Gagal mengekstrak file zip${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Pindah ke folder extracted
cd extracted

# Cek apakah ada file PHP
php_files=$(find . -name "*.php" | wc -l)
if [[ $php_files -eq 0 ]]; then
    echo -e "${RED}❌ Error: Tidak ada file PHP dalam zip${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo -e "${YELLOW}📂 Menginstal file proteksi (${php_files} file)...${NC}"

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
copied=0
failed=0

# Copy file satu per satu
for src in "${!FILES[@]}"; do
    dest="${FILES[$src]}"
    full_dest="$PANEL_DIR/$dest"
    
    if [[ -f "$src" ]]; then
        mkdir -p "$(dirname "$full_dest")"
        if cp -f "$src" "$full_dest"; then
            current=$((current + 1))
            copied=$((copied + 1))
            echo -e "${GREEN}✓${NC} [$current/$total_files] $src → $dest"
        else
            failed=$((failed + 1))
            echo -e "${RED}✗${NC} [$current/$total_files] Gagal copy: $src"
        fi
    else
        echo -e "${YELLOW}⚠${NC} File $src tidak ditemukan dalam zip"
    fi
done

# Copy file sidebar patcher
if [[ -f "admin.blade.php" ]]; then
    echo -e "${YELLOW}🛡️ Mengaplikasikan proteksi sidebar...${NC}"
    if cp -f "admin.blade.php" "$PANEL_DIR/"; then
        cd "$PANEL_DIR"
        if php admin.blade.php; then
            echo -e "${GREEN}✅ Sidebar berhasil diproteksi (hanya Admin ID 1 yang terlihat)${NC}"
        else
            echo -e "${RED}⚠ Gagal menjalankan patcher sidebar${NC}"
        fi
        rm -f "$PANEL_DIR/admin.blade.php"
    else
        echo -e "${RED}⚠ Gagal copy admin.blade.php${NC}"
    fi
else
    echo -e "${YELLOW}⚠ File admin.blade.php tidak ditemukan dalam zip${NC}"
fi

# Bersihkan temporary directory
echo -e "${YELLOW}🧹 Membersihkan temporary files...${NC}"
cd /tmp
rm -rf "$TEMP_DIR"

# Optimasi Laravel
echo -e "${YELLOW}⚡ Mengoptimasi panel...${NC}"
cd "$PANEL_DIR"

# Backup .env dulu
if [[ -f ".env" ]]; then
    cp .env .env.backup
fi

# Jalankan optimasi
php artisan optimize:clear || echo -e "${YELLOW}⚠ optimize:clear gagal, melanjutkan...${NC}"
php artisan config:cache || echo -e "${YELLOW}⚠ config:cache gagal, melanjutkan...${NC}"
php artisan route:cache || echo -e "${YELLOW}⚠ route:cache gagal, melanjutkan...${NC}"
php artisan view:cache || echo -e "${YELLOW}⚠ view:cache gagal, melanjutkan...${NC}"

# Atur permission
echo -e "${YELLOW}🔐 Mengatur permission...${NC}"
if chown -R www-data:www-data "$PANEL_DIR"; then
    find "$PANEL_DIR/storage" -type d -exec chmod 775 {} \; 2>/dev/null || true
    find "$PANEL_DIR/bootstrap/cache" -type d -exec chmod 775 {} \; 2>/dev/null || true
    echo -e "${GREEN}✅ Permission berhasil diatur${NC}"
else
    echo -e "${RED}⚠ Gagal mengatur permission${NC}"
fi

# Deteksi versi PHP
PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
PHP_FPM="php$PHP_VERSION-fpm"

if systemctl list-units --full -all | grep -Fq "$PHP_FPM"; then
    PHP_SERVICE="$PHP_FPM"
elif systemctl list-units --full -all | grep -Fq "php-fpm"; then
    PHP_SERVICE="php-fpm"
else
    PHP_SERVICE="php8.1-fpm # atau sesuaikan versi PHP Anda"
fi

# Output ringkasan
echo -e "${BLUE}===========================================${NC}"
echo -e "${GREEN}✅ INSTALASI SELESAI!${NC}"
echo ""
echo -e "${YELLOW}📊 Ringkasan:${NC}"
echo "• File berhasil di-copy: $copied"
echo "• File gagal: $failed"
echo "• Backup panel: $BACKUP_DIR"
echo ""
echo -e "${YELLOW}🛡️ Fitur yang diproteksi (hanya Admin ID 1):${NC}"
echo "• Nodes, Nests, Locations"
echo "• Databases, Settings, API, Mounts"
echo "• Semua aksi admin pada server orang lain"
echo "  (transfer, delete, reinstall, dll.)"
echo ""
echo -e "${YELLOW}🔄 Untuk restart services:${NC}"
echo "sudo systemctl restart nginx"
echo "sudo systemctl restart $PHP_SERVICE"
echo ""
echo -e "${YELLOW}📁 Backup lama:${NC} $BACKUP_DIR"
echo -e "${BLUE}===========================================${NC}"
echo -e "${GREEN}Terima kasih telah menggunakan ©Protect By @WiL Official${NC}"
echo -e "${YELLOW}❗ Jika ada error, cek backup di: $BACKUP_DIR${NC}"
