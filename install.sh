#!/bin/bash

# Pterodactyl Protection Installer
# Protect By @WiL Official
# Version: 1.0

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PANEL_DIR="/var/www/pterodactyl"
BACKUP_DIR="/root/pterodactyl-backup-$(date +%Y%m%d-%H%M%S)"
GITHUB_RAW="https://raw.githubusercontent.com/YOUR_USERNAME/pterodactyl-protect/main/Panel-protek"
LOG_FILE="/root/pterodactyl-protect-install.log"

# Log function
log_message() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Check root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Jalankan sebagai root!"
        exit 1
    fi
}

# Check panel
check_panel() {
    if [[ ! -d "$PANEL_DIR" ]]; then
        print_error "Panel tidak ditemukan di $PANEL_DIR"
        exit 1
    fi
}

# Create backup
create_backup() {
    print_status "Membuat backup..."
    mkdir -p "$BACKUP_DIR"
    
    # Backup semua file yang akan diganti
    cp "$PANEL_DIR/app/Http/Controllers/Admin/UserController.php" "$BACKUP_DIR/" 2>/dev/null || true
    cp "$PANEL_DIR/app/Http/Controllers/Api/Client/TwoFactorController.php" "$BACKUP_DIR/" 2>/dev/null || true
    cp "$PANEL_DIR/app/Services/Servers/StartupModificationService.php" "$BACKUP_DIR/" 2>/dev/null || true
    cp "$PANEL_DIR/app/Http/Controllers/Admin/Servers/ServerTransferController.php" "$BACKUP_DIR/" 2>/dev/null || true
    cp "$PANEL_DIR/app/Http/Controllers/Admin/ServersController.php" "$BACKUP_DIR/" 2>/dev/null || true
    cp "$PANEL_DIR/app/Services/Servers/ServerDeletionService.php" "$BACKUP_DIR/" 2>/dev/null || true
    cp "$PANEL_DIR/app/Http/Controllers/Admin/Servers/ServerController.php" "$BACKUP_DIR/" 2>/dev/null || true
    cp "$PANEL_DIR/app/Services/Servers/ReinstallServerService.php" "$BACKUP_DIR/" 2>/dev/null || true
    cp "$PANEL_DIR/app/Http/Controllers/Admin/Nodes/NodeController.php" "$BACKUP_DIR/" 2>/dev/null || true
    cp "$PANEL_DIR/app/Http/Controllers/Admin/Nests/NestController.php" "$BACKUP_DIR/" 2>/dev/null || true
    cp "$PANEL_DIR/app/Http/Controllers/Admin/MountController.php" "$BACKUP_DIR/" 2>/dev/null || true
    cp "$PANEL_DIR/app/Http/Controllers/Admin/LocationController.php" "$BACKUP_DIR/" 2>/dev/null || true
    cp "$PANEL_DIR/app/Http/Controllers/Admin/Settings/IndexController.php" "$BACKUP_DIR/" 2>/dev/null || true
    cp "$PANEL_DIR/app/Http/Controllers/Api/Client/Servers/FileController.php" "$BACKUP_DIR/" 2>/dev/null || true
    cp "$PANEL_DIR/app/Services/Servers/DetailsModificationService.php" "$BACKUP_DIR/" 2>/dev/null || true
    cp "$PANEL_DIR/app/Services/Databases/DatabaseManagementService.php" "$BACKUP_DIR/" 2>/dev/null || true
    cp "$PANEL_DIR/app/Http/Controllers/Admin/DatabaseController.php" "$BACKUP_DIR/" 2>/dev/null || true
    cp "$PANEL_DIR/app/Http/Controllers/Api/Client/Servers/ClientServerController.php" "$BACKUP_DIR/" 2>/dev/null || true
    cp "$PANEL_DIR/app/Services/Servers/BuildModificationService.php" "$BACKUP_DIR/" 2>/dev/null || true
    cp "$PANEL_DIR/app/Http/Controllers/Api/Client/ApiKeyController.php" "$BACKUP_DIR/" 2>/dev/null || true
    cp "$PANEL_DIR/app/Http/Controllers/Admin/ApiController.php" "$BACKUP_DIR/" 2>/dev/null || true
    cp "$PANEL_DIR/resources/views/layouts/admin.blade.php" "$BACKUP_DIR/" 2>/dev/null || true
    
    print_success "Backup di: $BACKUP_DIR"
}

# Download and install file
install_file() {
    local filename="$1"
    local destination="$2"
    
    print_status "Downloading $filename..."
    
    if curl -s -f "$GITHUB_RAW/$filename" -o "$destination"; then
        print_success "✓ $filename terinstall"
        chmod 644 "$destination"
        chown www-data:www-data "$destination" 2>/dev/null || chown nginx:nginx "$destination" 2>/dev/null
    else
        print_error "✗ Gagal download $filename"
        return 1
    fi
}

# Main installation
main() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════╗"
    echo "║   Pterodactyl Protection Installer       ║"
    echo "║        Protect By @WiL Official          ║"
    echo "╚══════════════════════════════════════════╝"
    echo -e "${NC}"
    
    check_root
    check_panel
    create_backup
    
    print_status "Memulai instalasi..."
    
    # Install Controllers
    print_status "Installing Controllers..."
    install_file "UserController.php" "$PANEL_DIR/app/Http/Controllers/Admin/UserController.php"
    install_file "TwoFactorController.php" "$PANEL_DIR/app/Http/Controllers/Api/Client/TwoFactorController.php"
    install_file "ServerTransferController.php" "$PANEL_DIR/app/Http/Controllers/Admin/Servers/ServerTransferController.php"
    install_file "ServersController.php" "$PANEL_DIR/app/Http/Controllers/Admin/ServersController.php"
    install_file "ServerController.php" "$PANEL_DIR/app/Http/Controllers/Admin/Servers/ServerController.php"
    install_file "NodeController.php" "$PANEL_DIR/app/Http/Controllers/Admin/Nodes/NodeController.php"
    install_file "NestController.php" "$PANEL_DIR/app/Http/Controllers/Admin/Nests/NestController.php"
    install_file "MountController.php" "$PANEL_DIR/app/Http/Controllers/Admin/MountController.php"
    install_file "LocationController.php" "$PANEL_DIR/app/Http/Controllers/Admin/LocationController.php"
    install_file "IndexController.php" "$PANEL_DIR/app/Http/Controllers/Admin/Settings/IndexController.php"
    install_file "FileController.php" "$PANEL_DIR/app/Http/Controllers/Api/Client/Servers/FileController.php"
    install_file "DatabaseController.php" "$PANEL_DIR/app/Http/Controllers/Admin/DatabaseController.php"
    install_file "ClientServerController.php" "$PANEL_DIR/app/Http/Controllers/Api/Client/Servers/ClientServerController.php"
    install_file "ApiKeyController.php" "$PANEL_DIR/app/Http/Controllers/Api/Client/ApiKeyController.php"
    install_file "ApiController.php" "$PANEL_DIR/app/Http/Controllers/Admin/ApiController.php"
    
    # Install Services
    print_status "Installing Services..."
    install_file "StartupModificationService.php" "$PANEL_DIR/app/Services/Servers/StartupModificationService.php"
    install_file "ServerDeletionService.php" "$PANEL_DIR/app/Services/Servers/ServerDeletionService.php"
    install_file "ReinstallServerService.php" "$PANEL_DIR/app/Services/Servers/ReinstallServerService.php"
    install_file "DetailsModificationService.php" "$PANEL_DIR/app/Services/Servers/DetailsModificationService.php"
    install_file "DatabaseManagementService.php" "$PANEL_DIR/app/Services/Databases/DatabaseManagementService.php"
    install_file "BuildModificationService.php" "$PANEL_DIR/app/Services/Servers/BuildModificationService.php"
    
    # Install Blade View
    print_status "Installing Blade View..."
    install_file "admin.blade.php" "$PANEL_DIR/resources/views/layouts/admin.blade.php"
    
    # Set permissions
    print_status "Mengatur permissions..."
    chown -R www-data:www-data "$PANEL_DIR" 2>/dev/null || chown -R nginx:nginx "$PANEL_DIR" 2>/dev/null
    chmod -R 755 "$PANEL_DIR/storage"
    chmod -R 755 "$PANEL_DIR/bootstrap/cache"
    
    # Clear cache
    print_status "Membersihkan cache..."
    cd "$PANEL_DIR"
    php artisan optimize:clear
    php artisan view:clear
    php artisan config:clear
    
    # Summary
    echo -e "\n${GREEN}══════════════════════════════════════════${NC}"
    print_success "Instalasi selesai!"
    echo -e "${BLUE}Backup:${NC} $BACKUP_DIR"
    echo -e "${BLUE}Log:${NC} $LOG_FILE"
    echo -e "\n${YELLOW}⚠  Logout dan login kembali untuk melihat perubahan${NC}"
    echo -e "${GREEN}══════════════════════════════════════════${NC}"
}

# Restore function
restore_backup() {
    if [[ -z "$2" ]]; then
        print_error "Gunakan: $0 restore /path/backup"
        exit 1
    fi
    
    local backup="$2"
    if [[ ! -d "$backup" ]]; then
        print_error "Backup tidak ditemukan: $backup"
        exit 1
    fi
    
    print_status "Merestore dari $backup..."
    cp "$backup"/*.php "$PANEL_DIR/app/Http/Controllers/Admin/" 2>/dev/null || true
    cp "$backup"/*.php "$PANEL_DIR/app/Http/Controllers/Api/Client/" 2>/dev/null || true
    cp "$backup"/*.php "$PANEL_DIR/app/Http/Controllers/Admin/Servers/" 2>/dev/null || true
    cp "$backup"/*.php "$PANEL_DIR/app/Http/Controllers/Admin/Nodes/" 2>/dev/null || true
    cp "$backup"/*.php "$PANEL_DIR/app/Http/Controllers/Admin/Nests/" 2>/dev/null || true
    cp "$backup"/*.php "$PANEL_DIR/app/Http/Controllers/Admin/Settings/" 2>/dev/null || true
    cp "$backup"/*.php "$PANEL_DIR/app/Http/Controllers/Api/Client/Servers/" 2>/dev/null || true
    cp "$backup"/*.php "$PANEL_DIR/app/Services/Servers/" 2>/dev/null || true
    cp "$backup"/*.php "$PANEL_DIR/app/Services/Databases/" 2>/dev/null || true
    cp "$backup/admin.blade.php" "$PANEL_DIR/resources/views/layouts/" 2>/dev/null || true
    
    print_success "Restore selesai!"
}

# Main
case "${1:-}" in
    restore)
        restore_backup "$@"
        ;;
    *)
        main
        ;;
esac
