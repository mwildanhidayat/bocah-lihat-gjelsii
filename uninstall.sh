#!/bin/bash

echo "=========================================="
echo "🔄 PTERODACTYL PROTECTION RESET (SMART)"
echo "=========================================="
echo ""

PTERO_PATH="/var/www/pterodactyl"

if [ ! -d "$PTERO_PATH" ]; then
  echo "❌ Folder Pterodactyl tidak ditemukan!"
  exit 1
fi

cd "$PTERO_PATH" || exit 1

echo "🔍 Mencari file backup (.bak_*)..."

BACKUPS=$(find . -name "*.bak_*")

if [ -z "$BACKUPS" ]; then
  echo "⚠️ Tidak ada file backup ditemukan."
  echo "Mungkin proteksi tidak pernah di-install atau backup sudah dihapus."
  exit 0
fi

echo "♻️ Mengembalikan file ke versi asli..."

for f in $BACKUPS; do
  ORIGINAL=$(echo "$f" | sed 's/\.bak_.*//')
  mv "$f" "$ORIGINAL"
  echo "✅ Restored: $ORIGINAL"
done

echo ""
echo "🧹 Membersihkan cache Laravel..."

php artisan optimize:clear
php artisan view:clear
php artisan config:clear
php artisan route:clear

echo ""
echo "🔎 Mendeteksi PHP-FPM..."

PHP_FPM=$(systemctl list-units --type=service --no-pager | grep -oE "php[0-9.]+-fpm" | head -n 1)

if [ -z "$PHP_FPM" ]; then
  echo "⚠️ PHP-FPM tidak ditemukan. Restart manual mungkin diperlukan."
else
  echo "🔁 Restarting $PHP_FPM ..."
  systemctl restart "$PHP_FPM"
fi

echo "🔁 Restarting Nginx..."
systemctl restart nginx

echo ""
echo "=========================================="
echo "✅ RESET SELESAI"
echo "Panel kembali ke kondisi NORMAL"
echo "=========================================="