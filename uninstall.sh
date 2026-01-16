#!/bin/bash

PTERO="/var/www/pterodactyl"
TS=$(date +%Y-%m-%d-%H-%M-%S)

echo "====================================="
echo "🧹 UNINSTALL PTERODACTYL PROTECTION"
echo "====================================="

# 1. Drop database table
echo "[1] Dropping user_limits table..."
mysql -u root -p panel -e "DROP TABLE IF EXISTS user_limits;"

# 2. Remove migration
echo "[2] Removing migration files..."
rm -f $PTERO/database/migrations/*create_user_limits_table.php

# 3. Remove model
echo "[3] Removing UserLimit model..."
rm -f $PTERO/app/Models/UserLimit.php

# 4. Remove service
echo "[4] Removing UserLimitService..."
rm -f $PTERO/app/Services/Users/UserLimitService.php

# 5. Remove middleware
echo "[5] Removing LimitValidationMiddleware..."
rm -f $PTERO/app/Http/Middleware/LimitValidationMiddleware.php

# 6. Remove controller
echo "[6] Removing LimitController..."
rm -f $PTERO/app/Http/Controllers/Admin/LimitController.php

# 7. Remove request
echo "[7] Removing UpdateUserLimitRequest..."
rm -f $PTERO/app/Http/Requests/Admin/UpdateUserLimitRequest.php

# 8. Remove blade UI
echo "[8] Removing blade UI..."
rm -rf $PTERO/resources/views/admin/limits

# 9. Restore routes
if ls $PTERO/routes/admin.php.bak_* 1> /dev/null 2>&1; then
  echo "[9] Restoring routes..."
  cp $(ls -t $PTERO/routes/admin.php.bak_* | head -1) $PTERO/routes/admin.php
fi

# 10. Restore sidebar
if ls $PTERO/resources/views/admin/partials/navigation.blade.php.bak_* 1> /dev/null 2>&1; then
  echo "[10] Restoring sidebar..."
  cp $(ls -t $PTERO/resources/views/admin/partials/navigation.blade.php.bak_* | head -1) \
     $PTERO/resources/views/admin/partials/navigation.blade.php
fi

# 11. Restore Kernel
if ls $PTERO/app/Http/Kernel.php.bak_* 1> /dev/null 2>&1; then
  echo "[11] Restoring Kernel..."
  cp $(ls -t $PTERO/app/Http/Kernel.php.bak_* | head -1) \
     $PTERO/app/Http/Kernel.php
fi

# 12. Clear cache
echo "[12] Clearing cache..."
cd $PTERO || exit
php artisan optimize:clear

echo "====================================="
echo "✅ UNINSTALL COMPLETE"
echo "====================================="