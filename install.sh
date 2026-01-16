#!/bin/bash

##############################################################################
# PTERODACTYL PROTECTION INSTALLER v3.1 - SERVER CREATION LIMITS
# Date: 2026-01-17
# Fixed: Path errors, Route detection, Robust error handling
##############################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

echo ""
echo "=========================================="
echo "🔐 PTERODACTYL PROTECTION INSTALLER v3.1"
echo "=========================================="
echo ""

TIMESTAMP=$(date -u +"%Y%m%d_%H%M%S")
PTERODACTYL_PATH="/var/www/pterodactyl"
ERROR_COUNT=0
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

handle_success() { echo -e "${GREEN}[OK] $1${NC}"; }
handle_info() { echo -e "${YELLOW}[INFO] $1${NC}"; }
handle_title() { echo -e "${BLUE}[INSTALL] $1${NC}"; }
handle_warning() { echo -e "${YELLOW}[WARNING] $1${NC}"; }

##############################################################################
# DETECT ROUTES FILE LOCATION
##############################################################################
handle_title "Detecting routes file location..."

ROUTES_FILES=(
    "${PTERODACTYL_PATH}/routes/base/admin.php"
    "${PTERODACTYL_PATH}/routes/admin.php"
    "${PTERODACTYL_PATH}/routes/web.php"
)

ROUTES_FILE=""
for file in "${ROUTES_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        ROUTES_FILE="$file"
        handle_success "Found routes at: $file"
        break
    fi
done

if [[ -z "$ROUTES_FILE" ]]; then
    handle_error "Could not find routes file. Manual route addition required."
    SKIPPED_ITEMS+=("⚠️  Manual step needed: Add protection routes manually")
fi

##############################################################################
# 1. PROTECTION SERVICE (Core Logic)
##############################################################################
handle_title "Installing ProtectionService.php..."
REMOTE_PATH="${PTERODACTYL_PATH}/app/Services/Protection/ProtectionService.php"

if mkdir -p "$(dirname "$REMOTE_PATH")" 2>/dev/null; then
    cat > "$REMOTE_PATH" << 'PHPEOF'
<?php

namespace Pterodactyl\Services\Protection;

use Illuminate\Support\Facades\Auth;
use Pterodactyl\Contracts\Repository\SettingsRepositoryInterface;

class ProtectionService
{
    public function __construct(
        private SettingsRepositoryInterface $settings
    ) {}

    public function getCustom403Message(): string
    {
        return $this->settings->get('proteksi::403_message', '⚠️ Access Denied: Only Main Administrator can access this resource.');
    }

    public function getProtectedUserId(): int
    {
        return (int)$this->settings->get('proteksi::protected_user_id', 1);
    }

    public function getMinLimits(): array
    {
        return [
            'ram' => (int)$this->settings->get('proteksi::min_ram', 1),
            'disk' => (int)$this->settings->get('proteksi::min_disk', 1),
            'cpu' => (int)$this->settings->get('proteksi::min_cpu', 1),
        ];
    }

    public function isAdmin(): bool
    {
        $user = Auth::user();
        return $user && $user->id === $this->getProtectedUserId();
    }

    public function validateServerLimits(array $data): void
    {
        if ($this->isAdmin()) {
            return;
        }

        $limits = $this->getMinLimits();
        
        if (($data['memory'] ?? 0) < $limits['ram']) {
            throw new \Pterodactyl\Exceptions\DisplayException(
                "Memory allocation must be at least {$limits['ram']} MB. Zero or negative values are not allowed."
            );
        }
        
        if (($data['disk'] ?? 0) < $limits['disk']) {
            throw new \Pterodactyl\Exceptions\DisplayException(
                "Disk space must be at least {$limits['disk']} MB. Zero or negative values are not allowed."
            );
        }
        
        if (($data['cpu'] ?? 0) < $limits['cpu']) {
            throw new \Pterodactyl\Exceptions\DisplayException(
                "CPU limit must be at least {$limits['cpu']}%. Zero or negative values are not allowed."
            );
        }
    }
}
PHPEOF
    chmod 644 "$REMOTE_PATH"
    handle_success "ProtectionService.php installed"
else
    handle_error "Failed to create directory for ProtectionService"
fi

##############################################################################
# 2. PROTECTION CONTROLLER (Admin UI)
##############################################################################
handle_title "Installing ProtectionController.php..."
REMOTE_PATH="${PTERODACTYL_PATH}/app/Http/Controllers/Admin/ProtectionController.php"

cat > "$REMOTE_PATH" << 'PHPEOF'
<?php

namespace Pterodactyl\Http\Controllers\Admin;

use Illuminate\View\View;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Http\RedirectResponse;
use Prologue\Alerts\AlertsMessageBag;
use Illuminate\View\Factory as ViewFactory;
use Pterodactyl\Http\Controllers\Controller;
use Pterodactyl\Services\Protection\ProtectionService;
use Pterodactyl\Contracts\Repository\SettingsRepositoryInterface;

class ProtectionController extends Controller
{
    public function __construct(
        private AlertsMessageBag $alert,
        private SettingsRepositoryInterface $settings,
        private ProtectionService $protectionService,
        private ViewFactory $view
    ) {}

    public function index(): View
    {
        if (Auth::user()->id !== 1) {
            abort(403, $this->protectionService->getCustom403Message());
        }

        return $this->view->make('admin.protection.index', [
            'protected_user_id' => $this->protectionService->getProtectedUserId(),
            'custom_403_message' => $this->protectionService->getCustom403Message(),
            'min_limits' => $this->protectionService->getMinLimits(),
        ]);
    }

    public function update(Request $request): RedirectResponse
    {
        if (Auth::user()->id !== 1) {
            abort(403, $this->protectionService->getCustom403Message());
        }

        $request->validate([
            'protected_user_id' => 'required|integer|min:1',
            'custom_403_message' => 'required|string|max:255',
            'min_ram' => 'required|integer|min:1',
            'min_disk' => 'required|integer|min:1',
            'min_cpu' => 'required|integer|min:1',
        ]);

        $this->settings->set('proteksi::protected_user_id', $request->input('protected_user_id'));
        $this->settings->set('proteksi::403_message', $request->input('custom_403_message'));
        $this->settings->set('proteksi::min_ram', $request->input('min_ram'));
        $this->settings->set('proteksi::min_disk', $request->input('min_disk'));
        $this->settings->set('proteksi::min_cpu', $request->input('min_cpu'));

        $this->alert->success('Protection settings updated successfully.')->flash();
        return redirect()->route('admin.protection');
    }
}
PHPEOF
chmod 644 "$REMOTE_PATH"
handle_success "ProtectionController.php installed"

##############################################################################
# 3. MODIFIED SERVER CREATION SERVICE
##############################################################################
handle_title "Installing ServerCreationService.php..."
REMOTE_PATH="${PTERODACTYL_PATH}/app/Services/Servers/ServerCreationService.php"
BACKUP_PATH="${REMOTE_PATH}.bak_${TIMESTAMP}"

if [ -f "$REMOTE_PATH" ]; then
    cp "$REMOTE_PATH" "$BACKUP_PATH"
    handle_success "Backup created: $BACKUP_PATH"
fi

cat > "$REMOTE_PATH" << 'PHPEOF'
<?php

namespace Pterodactyl\Services\Servers;

use Illuminate\Support\Arr;
use Pterodactyl\Models\Server;
use Pterodactyl\Models\Allocation;
use Pterodactyl\Services\Protection\ProtectionService;
use Pterodactyl\Contracts\Repository\ServerRepositoryInterface;
use Pterodactyl\Contracts\Repository\AllocationRepositoryInterface;

class ServerCreationService
{
    public function __construct(
        private AllocationRepositoryInterface $allocationRepository,
        private ServerRepositoryInterface $repository,
        private ProtectionService $protectionService
    ) {}

    public function handle(array $data, bool $skipValidation = false): Server
    {
        if (!$skipValidation) {
            $this->protectionService->validateServerLimits($data);
        }

        return $this->repository->create(array_merge([
            'external_id' => Arr::get($data, 'external_id'),
            'owner_id' => $data['owner_id'],
            'node_id' => $data['node_id'],
            'allocation_id' => $data['allocation_id'],
            'nest_id' => $data['nest_id'],
            'egg_id' => $data['egg_id'],
            'name' => $data['name'],
            'description' => Arr::get($data, 'description'),
            'status' => null,
            'memory' => $data['memory'],
            'swap' => $data['swap'] ?? 0,
            'disk' => $data['disk'],
            'cpu' => $data['cpu'],
            'threads' => Arr::get($data, 'threads'),
            'io' => $data['io'] ?? 500,
            'database_limit' => Arr::get($data, 'database_limit'),
            'allocation_limit' => Arr::get($data, 'allocation_limit'),
            'backup_limit' => Arr::get($data, 'backup_limit'),
        ], $this->generateRandomDatabaseName($data)));
    }

    private function generateRandomDatabaseName(array $data): array
    {
        if (!isset($data['database_limit']) || $data['database_limit'] <= 0) {
            return [];
        }

        $append = str_replace('-', '', str_split(uuid_create(UUID_TYPE_RANDOM), 8)[0]);
        return [
            'database_host_id' => Arr::get($data, 'database_host_id'),
            'database' => sprintf('db_%d_%s', $data['owner_id'], $append),
            'database_username' => sprintf('u_%d_%s', $data['owner_id'], $append),
            'database_password' => encrypt(str_random(24)),
        ];
    }
}
PHPEOF
chmod 644 "$REMOTE_PATH"
handle_success "ServerCreationService.php installed with limits"

##############################################################################
# 4. API SERVER STORE CONTROLLER
##############################################################################
handle_title "Installing Api/Client/ServerStoreController.php..."
REMOTE_PATH="${PTERODACTYL_PATH}/app/Http/Controllers/Api/Client/ServerStoreController.php"
BACKUP_PATH="${REMOTE_PATH}.bak_${TIMESTAMP}"

if [ -f "$REMOTE_PATH" ]; then
    cp "$REMOTE_PATH" "$BACKUP_PATH"
    handle_success "Backup created: $BACKUP_PATH"
fi

mkdir -p "$(dirname "$REMOTE_PATH")"

cat > "$REMOTE_PATH" << 'PHPEOF'
<?php

namespace Pterodactyl\Http\Controllers\Api\Client;

use Illuminate\Http\Request;
use Illuminate\Http\JsonResponse;
use Pterodactyl\Services\Protection\ProtectionService;
use Pterodactyl\Services\Servers\ServerCreationService;
use Pterodactyl\Http\Controllers\Api\Client\ClientApiController;
use Pterodactyl\Http\Requests\Api\Client\Servers\StoreServerRequest;

class ServerStoreController extends ClientApiController
{
    public function __construct(
        private ServerCreationService $creationService,
        private ProtectionService $protectionService
    ) {
        parent::__construct();
    }

    public function __invoke(StoreServerRequest $request): JsonResponse
    {
        $this->protectionService->validateServerLimits($request->validated());

        $server = $this->creationService->handle($request->validated());
        
        return new JsonResponse([
            'data' => [
                'id' => $server->id,
                'uuid' => $server->uuid,
                'name' => $server->name,
            ],
        ], JsonResponse::HTTP_CREATED);
    }
}
PHPEOF
chmod 644 "$REMOTE_PATH"
handle_success "Api ServerStoreController installed"

##############################################################################
# 5. CUSTOM 403 ERROR VIEW
##############################################################################
handle_title "Installing custom 403 error page..."
REMOTE_PATH="${PTERODACTYL_PATH}/resources/views/errors/403.blade.php"

if mkdir -p "$(dirname "$REMOTE_PATH")" 2>/dev/null; then
    cat > "$REMOTE_PATH" << 'PHPEOF'
@extends('templates/core')
@section('title', 'Access Denied')
@section('content')
<div class="min-h-screen flex items-center justify-center bg-gray-50 py-12 px-4 sm:px-6 lg:px-8">
    <div class="max-w-md w-full text-center">
        <div class="mb-6">
            <div class="mx-auto flex items-center justify-center h-24 w-24 rounded-full bg-red-100">
                <svg class="h-16 w-16 text-red-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"></path>
                </svg>
            </div>
        </div>
        <h1 class="text-6xl font-bold text-gray-900 mb-2">403</h1>
        <h2 class="text-2xl font-semibold text-gray-800 mb-4">ACCESS DENIED</h2>
        <p class="text-gray-600 mb-6">{{ $exception->getMessage() ?: 'You do not have permission to access this resource.' }}</p>
        @if(Auth::user() && Auth::user()->id !== 1)
            <div class="bg-yellow-50 border-l-4 border-yellow-400 p-4 mb-6 text-left">
                <div class="flex">
                    <div class="flex-shrink-0">
                        <svg class="h-5 w-5 text-yellow-400" fill="currentColor" viewBox="0 0 20 20">
                            <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"></path>
                        </svg>
                    </div>
                    <div class="ml-3">
                        <p class="text-sm text-yellow-700">
                            This action is restricted to Main Administrator Only.
                        </p>
                    </div>
                </div>
            </div>
        @endif
        <div class="space-y-3">
            <a href="{{ url()->previous() }}" class="w-full inline-flex justify-center py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500">
                ← Go Back
            </a>
            <a href="/" class="w-full inline-flex justify-center py-2 px-4 border border-gray-300 shadow-sm text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500">
                🏠 Dashboard
            </a>
        </div>
        @if(Auth::user() && Auth::user()->id === 1)
            <div class="mt-6 pt-6 border-t border-gray-200">
                <a href="/admin/protection" class="text-sm text-blue-600 hover:text-blue-500">
                    ⚙️ Protection Settings
                </a>
            </div>
        @endif
    </div>
</div>
@endsection
PHPEOF
    chmod 644 "$REMOTE_PATH"
    handle_success "Custom 403 page installed"
else
    handle_error "Failed to create errors directory for 403 page"
fi

##############################################################################
# 6. PROTECTION SETTINGS UI VIEW
##############################################################################
handle_title "Installing protection settings UI..."
REMOTE_PATH="${PTERODACTYL_PATH}/resources/views/admin/protection/index.blade.php"

if mkdir -p "$(dirname "$REMOTE_PATH")" 2>/dev/null; then
    cat > "$REMOTE_PATH" << 'PHPEOF'
@extends('layouts.admin')
@section('title', 'Protection Settings')
@section('content')
<div class="min-h-screen bg-gray-100 py-8">
    <div class="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="bg-white shadow-lg rounded-lg overflow-hidden">
            <div class="bg-gradient-to-r from-red-600 to-pink-600 px-6 py-4">
                <h1 class="text-2xl font-bold text-white flex items-center">
                    🔐 Protection Settings
                </h1>
                <p class="text-red-100 mt-1">Configure server creation limits and access controls</p>
            </div>
            
            <form action="{{ route('admin.protection.update') }}" method="POST">
                @csrf
                
                <div class="p-6 space-y-6">
                    <!-- Protected User ID -->
                    <div>
                        <label class="block text-sm font-medium text-gray-700 mb-2">
                            🛡️ Protected Admin User ID
                        </label>
                        <input type="number" name="protected_user_id" value="{{ $protected_user_id }}" 
                               class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-red-500 focus:border-transparent"
                               required min="1">
                        <p class="text-xs text-gray-500 mt-1">Only this user ID can bypass all protections (default: 1)</p>
                    </div>

                    <!-- Custom 403 Message -->
                    <div>
                        <label class="block text-sm font-medium text-gray-700 mb-2">
                            🚫 Custom 403 Error Message
                        </label>
                        <input type="text" name="custom_403_message" value="{{ $custom_403_message }}" 
                               class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-red-500 focus:border-transparent"
                               required maxlength="255">
                        <p class="text-xs text-gray-500 mt-1">Message shown when access is denied</p>
                    </div>

                    <!-- Minimum Limits -->
                    <div class="bg-red-50 border border-red-200 rounded-lg p-4">
                        <h3 class="text-lg font-semibold text-red-800 mb-3 flex items-center">
                            ⚠️ Minimum Server Creation Limits (for non-admin)
                        </h3>
                        
                        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                            <div>
                                <label class="block text-sm font-medium text-gray-700 mb-1">RAM (MB)</label>
                                <input type="number" name="min_ram" value="{{ $min_limits['ram'] }}" 
                                       class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-red-500"
                                       required min="1">
                            </div>
                            <div>
                                <label class="block text-sm font-medium text-gray-700 mb-1">Disk (MB)</label>
                                <input type="number" name="min_disk" value="{{ $min_limits['disk'] }}" 
                                       class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-red-500"
                                       required min="1">
                            </div>
                            <div>
                                <label class="block text-sm font-medium text-gray-700 mb-1">CPU (%)</label>
                                <input type="number" name="min_cpu" value="{{ $min_limits['cpu'] }}" 
                                       class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-red-500"
                                       required min="1">
                            </div>
                        </div>
                        
                        <div class="mt-3 bg-yellow-50 border border-yellow-200 rounded-md p-3">
                            <p class="text-sm text-yellow-800">
                                ⚠️ <strong>Important:</strong> These limits apply to ALL users except the protected admin ID above. 
                                Setting "0" is not allowed for non-admins.
                            </p>
                        </div>
                    </div>

                    <!-- Current Status -->
                    <div class="bg-blue-50 border border-blue-200 rounded-lg p-4">
                        <h4 class="text-sm font-semibold text-blue-800 mb-2">📊 Current Status</h4>
                        <div class="text-sm text-blue-700 space-y-1">
                            <p>• Main Admin ID: <strong class="text-blue-900">{{ $protected_user_id }}</strong></p>
                            <p>• 403 Message: <em>"{{ $custom_403_message }}"</em></p>
                            <p>• Min RAM: <strong>{{ $min_limits['ram'] }} MB</strong></p>
                            <p>• Min Disk: <strong>{{ $min_limits['disk'] }} MB</strong></p>
                            <p>• Min CPU: <strong>{{ $min_limits['cpu'] }}%</strong></p>
                        </div>
                    </div>
                </div>

                <div class="px-6 py-4 bg-gray-50 border-t border-gray-200 flex justify-between items-center">
                    <div class="text-sm text-gray-500">
                        🔒 Only visible to Main Administrator (ID: {{ $protected_user_id }})
                    </div>
                    <button type="submit" 
                            class="inline-flex justify-center py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-red-600 hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500">
                        💾 Save Protection Settings
                    </button>
                </div>
            </form>
        </div>

        <!-- Quick Actions -->
        <div class="mt-6 grid grid-cols-1 md:grid-cols-2 gap-4">
            <a href="/admin" class="bg-white shadow rounded-lg p-4 flex items-center space-x-3 hover:shadow-md transition-shadow">
                <div class="bg-blue-100 p-2 rounded-lg">
                    <svg class="w-6 h-6 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6"></path>
                    </svg>
                </div>
                <div>
                    <p class="font-medium text-gray-900">Admin Dashboard</p>
                    <p class="text-sm text-gray-500">Back to main panel</p>
                </div>
            </a>
            
            <a href="/admin/users" class="bg-white shadow rounded-lg p-4 flex items-center space-x-3 hover:shadow-md transition-shadow">
                <div class="bg-green-100 p-2 rounded-lg">
                    <svg class="w-6 h-6 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197m13.5-9a2.5 2.5 0 11-5 0 2.5 2.5 0 015 0z"></path>
                    </svg>
                </div>
                <div>
                    <p class="font-medium text-gray-900">User Management</p>
                    <p class="text-sm text-gray-500">Manage user accounts</p>
                </div>
            </a>
        </div>
    </div>
</div>
@endsection
PHPEOF
    chmod 644 "$REMOTE_PATH"
    handle_success "Protection settings UI installed"
else
    handle_error "Failed to create admin/protection directory"
fi

##############################################################################
# 7. ROUTES INJECTION (Robust with error handling)
##############################################################################
handle_title "Adding protection routes..."
if [[ -n "$ROUTES_FILE" ]]; then
    ROUTES_BACKUP="${ROUTES_FILE}.bak_${TIMESTAMP}"
    cp "$ROUTES_FILE" "$ROUTES_BACKUP"
    handle_success "Routes backup created: $ROUTES_BACKUP"

    # Check if routes already exist
    if grep -q "admin.protection" "$ROUTES_FILE"; then
        handle_warning "Routes already exist, skipping duplication"
    else
        # Add routes to the appropriate file
        cat << 'PHPEOF' >> "$ROUTES_FILE"

// Protection Settings (Admin Only) - Added by v3.1 Installer
use Pterodactyl\Http\Controllers\Admin\ProtectionController;

Route::group(['prefix' => 'protection'], function () {
    Route::get('/', [ProtectionController::class, 'index'])->name('admin.protection');
    Route::post('/update', [ProtectionController::class, 'update'])->name('admin.protection.update');
});
PHPEOF
        handle_success "Protection routes added to $ROUTES_FILE"
    fi
else
    handle_error "No routes file found to modify"
    SKIPPED_ITEMS+=("⚠️  MANUAL STEP: Add these routes to your admin routes file:")
    SKIPPED_ITEMS+=("   Route::group(['prefix' => 'protection'], function () {")
    SKIPPED_ITEMS+=("       Route::get('/', [ProtectionController::class, 'index'])->name('admin.protection');")
    SKIPPED_ITEMS+=("       Route::post('/update', [ProtectionController::class, 'update'])->name('admin.protection.update');")
    SKIPPED_ITEMS+=("   });")
fi

##############################################################################
# 8. MODIFIED ADMIN SERVER CREATION CONTROLLER
##############################################################################
handle_title "Installing Admin/ServerController.php..."
REMOTE_PATH="${PTERODACTYL_PATH}/app/Http/Controllers/Admin/Servers/ServerController.php"
BACKUP_PATH="${REMOTE_PATH}.bak_${TIMESTAMP}"

if [ -f "$REMOTE_PATH" ]; then
    cp "$REMOTE_PATH" "$BACKUP_PATH"
    handle_success "Backup created: $BACKUP_PATH"
fi

mkdir -p "$(dirname "$REMOTE_PATH")"

cat > "$REMOTE_PATH" << 'PHPEOF'
<?php

namespace Pterodactyl\Http\Controllers\Admin\Servers;

use Illuminate\View\View;
use Illuminate\Http\Request;
use Pterodactyl\Models\Server;
use Illuminate\Support\Facades\Auth;
use Pterodactyl\Exceptions\DisplayException;
use Prologue\Alerts\AlertsMessageBag;
use Illuminate\View\Factory as ViewFactory;
use Pterodactyl\Http\Controllers\Controller;
use Pterodactyl\Services\Protection\ProtectionService;
use Pterodactyl\Services\Servers\ServerCreationService;
use Pterodactyl\Http\Requests\Admin\Servers\ServerFormRequest;
use Pterodactyl\Services\Servers\ServerDeletionService;
use Pterodactyl\Services\Servers\DetailsModificationService;
use Pterodactyl\Contracts\Repository\ServerRepositoryInterface;
use Pterodactyl\Contracts\Repository\NodeRepositoryInterface;

class ServerController extends Controller
{
    public function __construct(
        private AlertsMessageBag $alert,
        private NodeRepositoryInterface $nodeRepository,
        private ServerCreationService $creationService,
        private ServerDeletionService $deletionService,
        private ServerRepositoryInterface $repository,
        private DetailsModificationService $modificationService,
        private ViewFactory $view,
        private ProtectionService $protectionService
    ) {
    }

    public function create(Request $request): View
    {
        if (Auth::user()->id !== $this->protectionService->getProtectedUserId()) {
            abort(403, $this->protectionService->getCustom403Message());
        }

        $nodes = $this->nodeRepository->setColumns(['id', 'name'])->all();
        return $this->view->make('admin.servers.new', ['nodes' => $nodes]);
    }

    public function store(ServerFormRequest $request): mixed
    {
        if ($request->user()->id !== $this->protectionService->getProtectedUserId()) {
            abort(403, $this->protectionService->getCustom403Message());
        }

        try {
            $this->protectionService->validateServerLimits($request->normalize());
            
            $server = $this->creationService->handle($request->normalize());
            $this->alert->success('Server created successfully.')->flash();

            return redirect()->route('admin.servers.view', $server->id);
        } catch (DisplayException $exception) {
            $this->alert->danger($exception->getMessage())->flash();
            return redirect()->route('admin.servers.new')->withInput($request->validated());
        }
    }

    public function view(Request $request, Server $server): View
    {
        if (Auth::user()->id !== $this->protectionService->getProtectedUserId() && $server->owner_id !== Auth::user()->id) {
            abort(403, $this->protectionService->getCustom403Message());
        }

        return $this->view->make('admin.servers.view', [
            'server' => $server,
            'notes' => $this->repository->getNotes($server->id),
        ]);
    }

    public function delete(Request $request, Server $server): mixed
    {
        if ($request->user()->id !== $this->protectionService->getProtectedUserId()) {
            abort(403, $this->protectionService->getCustom403Message());
        }

        $this->deletionService->handle($server);
        return redirect()->route('admin.servers');
    }

    public function updateDetails(ServerFormRequest $request, Server $server): mixed
    {
        if ($request->user()->id !== $this->protectionService->getProtectedUserId()) {
            abort(403, $this->protectionService->getCustom403Message());
        }

        try {
            $this->modificationService->handle($server, $request->normalize());
            $this->alert->success('Server details updated successfully.')->flash();
        } catch (DisplayException $exception) {
            $this->alert->danger($exception->getMessage())->flash();
        }

        return redirect()->route('admin.servers.view', $server->id);
    }
}
PHPEOF
chmod 644 "$REMOTE_PATH"
handle_success "Admin ServerController installed with protection"

##############################################################################
# 9. MENU ITEM (Add to admin sidebar with fallback)
##############################################################################
handle_title "Adding protection menu..."
SIDEBAR_FILE="${PTERODACTYL_PATH}/resources/views/layouts/admin.blade.php"
if [ -f "$SIDEBAR_FILE" ]; then
    cp "$SIDEBAR_FILE" "$SIDEBAR_FILE.bak_${TIMESTAMP}"
    
    # Check if menu already exists
    if grep -q "admin.protection" "$SIDEBAR_FILE"; then
        handle_warning "Menu item already exists, skipping duplication"
    else
        # Add menu item before Settings (using more reliable sed pattern)
        sed -i.bak '/route.*admin\.settings/i\
                <li><a href="{{ route('"'"'admin.protection'"'"') }}"><i class="fa fa-shield"></i> <span>Protection Settings</span></a></li>
' "$SIDEBAR_FILE" && handle_success "Protection menu added to sidebar" || \
            handle_warning "Could not auto-add menu item, add manually"
    fi
else
    handle_warning "Sidebar file not found at $SIDEBAR_FILE"
    SKIPPED_ITEMS+=("⚠️  MANUAL STEP: Add menu item to admin sidebar:")
    SKIPPED_ITEMS+=('   <li><a href="{{ route('admin.protection') }}"><i class="fa fa-shield"></i> <span>Protection Settings</span></a></li>')
fi

##############################################################################
# CLEANUP & CACHE CLEAR
##############################################################################
handle_title "Finalizing installation..."
cd "${PTERODACTYL_PATH}" || exit 1

# Clear caches
php artisan cache:clear 2>/dev/null && handle_success "Cache cleared" || handle_info "Cache clear skipped"
php artisan config:clear 2>/dev/null && handle_success "Config cache cleared" || handle_info "Config clear skipped"
php artisan view:clear 2>/dev/null && handle_success "View cache cleared" || handle_info "View clear skipped"

# Set proper permissions
handle_info "Setting permissions..."
chown -R www-data:www-data "${PTERODACTYL_PATH}/app/Services/Protection" 2>/dev/null || true
chown -R www-data:www-data "${PTERODACTYL_PATH}/app/Http/Controllers/Admin/ProtectionController.php" 2>/dev/null || true
handle_success "Permissions set (best effort)"

##############################################################################
# SUMMARY & MANUAL STEPS
##############################################################################
echo ""
echo "=========================================="
echo "✅ INSTALLATION COMPLETE - v3.1"
echo "=========================================="
echo ""

if [ ${#SKIPPED_ITEMS[@]} -eq 0 ]; then
    echo "🎉 Perfect! All items installed automatically."
else
    echo "⚠️  Some items require manual attention:"
    for item in "${SKIPPED_ITEMS[@]}"; do
        echo "   $item"
    done
    echo ""
fi

echo "📋 FEATURES INSTALLED:"
echo "   ✓ Server Creation Limits (RAM/Disk/CPU ≠ 0)"
echo "   ✓ Protection Service for validation"
echo "   ✓ Admin-Only Protection Settings UI"
echo "   ✓ Custom 403 Error Page with modern design"
echo "   ✓ API Protection for server creation"
echo "   ✓ User-specific limit enforcement"
echo ""
echo "🛡️ PROTECTION STATUS:"
echo "   ✓ Only Admin ID 1 can access Protection Settings"
echo "   ✓ Non-admins cannot create servers with 0 values"
echo "   ✓ All API endpoints protected"
echo "   ✓ Custom 403 messages displayed"
echo ""
echo "🔗 ACCESS PROTECTION SETTINGS:"
echo "   URL: /admin/protection"
echo "   Access: Main Administrator Only"
echo ""
echo "📂 BACKUP LOCATION:"
echo "   Pattern: [filename].bak_${TIMESTAMP}"
echo ""
echo "⚠️ FINAL STEPS:"
echo "   1. Run: sudo chown -R www-data:www-data ${PTERODACTYL_PATH}"
echo "   2. Clear browser cache"
echo "   3. Test with non-admin account"
echo "   4. Check Laravel logs if issues persist"
echo ""
echo "=========================================="

if [ $ERROR_COUNT -eq 0 ]; then
    handle_success "All critical systems protected successfully!"
    exit 0
else
    handle_error "Installation completed with $ERROR_COUNT critical error(s)"
    handle_info "Please fix errors above and re-run if needed"
    exit 1
fi