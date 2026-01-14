#!/bin/bash

echo "======================================="
echo "  YUGI PROTECT INSTALLER v2.0"
echo "  Admin Only: ID 1 & 2"
echo "======================================="

ADMIN_CHECK='
$user = Auth::user();
if (!$user || !in_array($user->id, [1, 2])) {
    abort(403, "⚠️ ᴀᴋꜱᴇꜱ ᴅɪᴛᴏʟᴀᴋ: ʜᴀɴʏᴀ ᴀᴅᴍɪɴ ʏᴜɢɪ ᴅᴀɴ ᴍᴇᴍʙᴇʀ ʏᴜɢɪ.");
}
'

backup_file() {
  if [ -f "$1" ]; then
    mv "$1" "$1.bak_$(date +%Y%m%d_%H%M%S)"
    echo "📦 Backup: $1"
  fi
}

write_file() {
  mkdir -p "$(dirname "$1")"
  backup_file "$1"
  cat > "$1" << EOF
$2
EOF
  chmod 644 "$1"
  echo "✅ Installed: $1"
}

# 1. Anti Modify Server
write_file "/var/www/pterodactyl/app/Services/Servers/DetailsModificationService.php" "<?php
namespace Pterodactyl\Services\Servers;

use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Arr;
use Pterodactyl\Models\Server;

class DetailsModificationService {
    public function handle(Server \$server, array \$data): Server {
        $ADMIN_CHECK
        \$server->forceFill([
            'name' => Arr::get(\$data, 'name'),
            'description' => Arr::get(\$data, 'description') ?? '',
        ])->saveOrFail();
        return \$server;
    }
}
"

# 2. Anti Intip Server
write_file "/var/www/pterodactyl/app/Http/Controllers/Api/Client/Servers/ServerController.php" "<?php
namespace Pterodactyl\Http\Controllers\Api\Client\Servers;

use Illuminate\Support\Facades\Auth;

class ServerController {
    public function index(\$request, \$server) {
        $ADMIN_CHECK
        return [];
    }
}
"

# 3. File Manager Protect
write_file "/var/www/pterodactyl/app/Http/Controllers/Api/Client/Servers/FileController.php" "<?php
namespace Pterodactyl\Http\Controllers\Api\Client\Servers;

use Illuminate\Support\Facades\Auth;

class FileController {
    private function check(\$request, \$server) {
        $ADMIN_CHECK
    }
}
"

# 4. Settings Protect
write_file "/var/www/pterodactyl/app/Http/Controllers/Admin/Settings/IndexController.php" "<?php
namespace Pterodactyl\Http\Controllers\Admin\Settings;

use Illuminate\Support\Facades\Auth;

class IndexController {
    public function index() {
        $ADMIN_CHECK
    }
}
"

# 5. Nest Protect
write_file "/var/www/pterodactyl/app/Http/Controllers/Admin/Nests/NestController.php" "<?php
namespace Pterodactyl\Http\Controllers\Admin\Nests;

use Illuminate\Support\Facades\Auth;

class NestController {
    public function index() {
        $ADMIN_CHECK
    }
}
"

# 6. Location Protect
write_file "/var/www/pterodactyl/app/Http/Controllers/Admin/LocationController.php" "<?php
namespace Pterodactyl\Http\Controllers\Admin;

use Illuminate\Support\Facades\Auth;

class LocationController {
    public function index() {
        $ADMIN_CHECK
    }
}
"

# 7. User Protect
write_file "/var/www/pterodactyl/app/Http/Controllers/Admin/UserController.php" "<?php
namespace Pterodactyl\Http\Controllers\Admin;

use Illuminate\Support\Facades\Auth;
use Pterodactyl\Exceptions\DisplayException;

class UserController {
    public function delete(\$request, \$user) {
        if (!in_array(\$request->user()->id, [1,2])) {
            throw new DisplayException('Hanya admin utama.');
        }
    }
}
"

# 8. Node Protect
write_file "/var/www/pterodactyl/app/Http/Controllers/Admin/Nodes/NodeController.php" "<?php
namespace Pterodactyl\Http\Controllers\Admin\Nodes;

use Illuminate\Support\Facades\Auth;

class NodeController {
    public function index() {
        $ADMIN_CHECK
    }
}
"

# 9. Anti Delete Server
write_file "/var/www/pterodactyl/app/Services/Servers/ServerDeletionService.php" "<?php
namespace Pterodactyl\Services\Servers;

use Illuminate\Support\Facades\Auth;
use Pterodactyl\Exceptions\DisplayException;

class ServerDeletionService {
    public function handle(\$server) {
        \$user = Auth::user();
        if (\$user && !in_array(\$user->id, [1,2]) && \$server->owner_id !== \$user->id) {
            throw new DisplayException('Tidak diizinkan.');
        }
    }
}
"

echo "======================================="
echo "YUGI PROTECT INSTALLED SUCCESSFULLY"
echo "Admin Allowed: ID 1 & 2"
echo "======================================="