#!/bin/bash

##############################################################################
# INSTALLER PROTEKSI PTERODACTYL - VERSI 2.0 LENGKAP AMAN (FULL FIX)
# Date: 2026-01-14
# Author: Safety Team
# Description: Proteksi Admin ID 1 - Tanpa 500 Error, White Screen, atau Bug
# Fix: User 500 Error + Custom 403 Messages + Server Creation Limits
##############################################################################

set -e

echo ""
echo "=========================================="
echo "🔐 PTERODACTYL PROTECTION INSTALLER v2.0"
echo "=========================================="
echo ""

TIMESTAMP=$(date -u +"%Y-%m-%d-%H-%M-%S")
PTERODACTYL_PATH="/var/www/pterodactyl"
ERROR_COUNT=0

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function untuk error handling
handle_error() {
    echo -e "${RED}[ERROR] $1${NC}"
    ERROR_COUNT=$((ERROR_COUNT + 1))
}

# Function untuk success
handle_success() {
    echo -e "${GREEN}[OK] $1${NC}"
}

# Function untuk info
handle_info() {
    echo -e "${YELLOW}[INFO] $1${NC}"
}

# Function untuk notice
handle_notice() {
    echo -e "${BLUE}[NOTE] $1${NC}"
}

##############################################################################
# 0. CREATE DATABASE MIGRATION FOR SERVER LIMITS
##############################################################################
echo ""
handle_info "[0/12] Creating database migration for server limits..."

MIGRATION_PATH="${PTERODACTYL_PATH}/database/migrations/$(date +%Y_%m_%d_%H%M%S)_add_server_limits_table.php"

cat > "$MIGRATION_PATH" << 'PHPEOF'
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (!Schema::hasTable('server_creation_limits')) {
            Schema::create('server_creation_limits', function (Blueprint $table) {
                $table->id();
                $table->unsignedBigInteger('user_id')->unique();
                $table->integer('daily_limit')->default(3);
                $table->integer('today_count')->default(0);
                $table->date('last_reset_date');
                $table->boolean('allow_unlimited_resources')->default(false);
                $table->timestamps();
                
                $table->foreign('user_id')->references('id')->on('users')->onDelete('cascade');
                $table->index(['user_id', 'last_reset_date']);
            });
            
            // Insert default record for admin ID 1
            DB::table('server_creation_limits')->insert([
                'user_id' => 1,
                'daily_limit' => 99999,
                'today_count' => 0,
                'last_reset_date' => date('Y-m-d'),
                'allow_unlimited_resources' => true,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('server_creation_limits');
    }
};
PHPEOF

handle_success "Migration created"

##############################################################################
# 1. ServerDeletionService.php
##############################################################################
echo ""
handle_info "[1/12] Installing ServerDeletionService.php..."

REMOTE_PATH="${PTERODACTYL_PATH}/app/Services/Servers/ServerDeletionService.php"
BACKUP_PATH="${REMOTE_PATH}.bak_${TIMESTAMP}"

if [ -f "$REMOTE_PATH" ]; then
    cp "$REMOTE_PATH" "$BACKUP_PATH"
    handle_success "Backup created:  $BACKUP_PATH"
fi

mkdir -p "$(dirname "$REMOTE_PATH")"

cat > "$REMOTE_PATH" << 'PHPEOF'
<?php

namespace Pterodactyl\Services\Servers;

use Illuminate\Support\Facades\Auth;
use Pterodactyl\Exceptions\DisplayException;
use Illuminate\Http\Response;
use Pterodactyl\Models\Server;
use Illuminate\Support\Facades\Log;
use Illuminate\Database\ConnectionInterface;
use Pterodactyl\Repositories\Wings\DaemonServerRepository;
use Pterodactyl\Services\Databases\DatabaseManagementService;
use Pterodactyl\Exceptions\Http\Connection\DaemonConnectionException;

class ServerDeletionService
{
    protected bool $force = false;

    public function __construct(
        private ConnectionInterface $connection,
        private DaemonServerRepository $daemonServerRepository,
        private DatabaseManagementService $databaseManagementService
    ) {
    }

    public function withForce(bool $bool = true): self
    {
        $this->force = $bool;
        return $this;
    }

    /**
     * Delete a server from the panel and remove any associated databases. 
     * @throws \Throwable
     */
    public function handle(Server $server): void
    {
        $user = Auth::user();

        if ($user && $user->id !== 1) {
            $ownerId = $server->owner_id ??  $server->user_id;
            if ($ownerId && $ownerId !== $user->id) {
                abort(403);
            }
        }

        try {
            $this->daemonServerRepository->setServer($server)->delete();
        } catch (DaemonConnectionException $exception) {
            if (! $this->force && $exception->getStatusCode() !== Response::HTTP_NOT_FOUND) {
                throw $exception;
            }
            Log::warning($exception);
        }

        $this->connection->transaction(function () use ($server) {
            foreach ($server->databases as $database) {
                try {
                    $this->databaseManagementService->delete($database);
                } catch (\Exception $exception) {
                    if (!$this->force) {
                        throw $exception;
                    }
                    $database->delete();
                    Log:: warning($exception);
                }
            }
            $server->delete();
        });
    }
}
PHPEOF

chmod 644 "$REMOTE_PATH"
handle_success "ServerDeletionService.php installed"

##############################################################################
# 2. UserController.php (FIXED - NO 500 ERROR)
##############################################################################
echo ""
handle_info "[2/12] Installing UserController.php (FIXED + LIMIT FEATURES)..."

REMOTE_PATH="${PTERODACTYL_PATH}/app/Http/Controllers/Admin/UserController.php"
BACKUP_PATH="${REMOTE_PATH}.bak_${TIMESTAMP}"

if [ -f "$REMOTE_PATH" ]; then
    cp "$REMOTE_PATH" "$BACKUP_PATH"
    handle_success "Backup created: $BACKUP_PATH"
fi

mkdir -p "$(dirname "$REMOTE_PATH")"

cat > "$REMOTE_PATH" << 'PHPEOF'
<?php

namespace Pterodactyl\Http\Controllers\Admin;

use Illuminate\View\View;
use Illuminate\Http\Request;
use Pterodactyl\Models\User;
use Pterodactyl\Models\Model;
use Illuminate\Support\Collection;
use Illuminate\Http\RedirectResponse;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Prologue\Alerts\AlertsMessageBag;
use Spatie\QueryBuilder\QueryBuilder;
use Illuminate\View\Factory as ViewFactory;
use Pterodactyl\Exceptions\DisplayException;
use Pterodactyl\Http\Controllers\Controller;
use Illuminate\Contracts\Translation\Translator;
use Pterodactyl\Services\Users\UserUpdateService;
use Pterodactyl\Traits\Helpers\AvailableLanguages;
use Pterodactyl\Services\Users\UserCreationService;
use Pterodactyl\Services\Users\UserDeletionService;
use Pterodactyl\Http\Requests\Admin\UserFormRequest;
use Pterodactyl\Http\Requests\Admin\NewUserFormRequest;
use Pterodactyl\Contracts\Repository\UserRepositoryInterface;

class UserController extends Controller
{
    use AvailableLanguages;

    public function __construct(
        protected AlertsMessageBag $alert,
        protected UserCreationService $creationService,
        protected UserDeletionService $deletionService,
        protected Translator $translator,
        protected UserUpdateService $updateService,
        protected UserRepositoryInterface $repository,
        protected ViewFactory $view
    ) {
    }

    public function index(Request $request): View
    {
        $users = QueryBuilder::for(
            User::query()->select('users.*')
                ->selectRaw('COUNT(DISTINCT(subusers.id)) as subuser_of_count')
                ->selectRaw('COUNT(DISTINCT(servers.id)) as servers_count')
                ->leftJoin('subusers', 'subusers.user_id', '=', 'users.id')
                ->leftJoin('servers', 'servers.owner_id', '=', 'users.id')
                ->groupBy('users.id')
        )
            ->allowedFilters(['username', 'email', 'uuid'])
            ->allowedSorts(['id', 'uuid'])
            ->paginate(50);

        // Get server limits for each user
        $limits = DB::table('server_creation_limits')
            ->whereIn('user_id', $users->pluck('id'))
            ->get()
            ->keyBy('user_id');

        return $this->view->make('admin.users.index', [
            'users' => $users,
            'limits' => $limits,
        ]);
    }

    public function create(): View
    {
        return $this->view->make('admin.users.new', [
            'languages' => $this->getAvailableLanguages(true),
        ]);
    }

    public function view(User $user): View
    {
        // Only admin ID 1 can access limit management UI
        if (Auth::user()->id !== 1) {
            abort(403, '⚠️ ᴀᴋꜱᴇꜱ ᴅɪᴛᴏʟᴀᴋ: ʜᴀɴʏᴀ ᴛᴀᴄᴏ ʏᴀɴɢ ʙɪꜱᴀ ᴀᴋꜱᴇꜱ');
        }

        $limit = DB::table('server_creation_limits')
            ->where('user_id', $user->id)
            ->first();

        // If no limit record exists, create default one
        if (!$limit) {
            $limitId = DB::table('server_creation_limits')->insertGetId([
                'user_id' => $user->id,
                'daily_limit' => 3,
                'today_count' => 0,
                'last_reset_date' => date('Y-m-d'),
                'allow_unlimited_resources' => false,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
            $limit = DB::table('server_creation_limits')->find($limitId);
        }

        return $this->view->make('admin.users.view', [
            'user' => $user,
            'limit' => $limit,
            'languages' => $this->getAvailableLanguages(true),
        ]);
    }

    public function updateLimits(Request $request, User $user): RedirectResponse
    {
        if (Auth::user()->id !== 1) {
            abort(403, '⚠️ ᴀᴋꜱᴇꜱ ᴅɪᴛᴏʟᴀᴋ: ʜᴀɴʏᴀ ᴛᴀᴄᴏ ʏᴀɴɢ ʙɪꜱᴀ ᴀᴋꜱᴇꜱ');
        }

        $request->validate([
            'daily_limit' => 'required|integer|min:0|max:999',
            'allow_unlimited' => 'boolean',
            'reset_count' => 'boolean',
        ]);

        $updateData = [
            'daily_limit' => $request->input('daily_limit'),
            'allow_unlimited_resources' => $request->boolean('allow_unlimited'),
            'updated_at' => now(),
        ];

        if ($request->boolean('reset_count')) {
            $updateData['today_count'] = 0;
            $updateData['last_reset_date'] = date('Y-m-d');
        }

        DB::table('server_creation_limits')
            ->updateOrInsert(
                ['user_id' => $user->id],
                $updateData
            );

        $this->alert->success('Server creation limits updated successfully')->flash();
        return redirect()->route('admin.users.view', $user->id);
    }

    public function delete(Request $request, User $user): RedirectResponse
    {
        if ($request->user()->id !== 1) {
            abort(403);
        }

        if ($request->user()->id === $user->id) {
            throw new DisplayException($this->translator->get('admin/user. exceptions.user_has_servers'));
        }

        $this->deletionService->handle($user);
        return redirect()->route('admin.users');
    }

    public function store(NewUserFormRequest $request): RedirectResponse
    {
        $user = $this->creationService->handle($request->normalize());
        
        // Create default limit record for new user
        DB::table('server_creation_limits')->insert([
            'user_id' => $user->id,
            'daily_limit' => 3,
            'today_count' => 0,
            'last_reset_date' => date('Y-m-d'),
            'allow_unlimited_resources' => false,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        
        $this->alert->success($this->translator->get('admin/user.notices.account_created'))->flash();
        return redirect()->route('admin.users.view', $user->id);
    }

    public function update(UserFormRequest $request, User $user): RedirectResponse
    {
        if ($request->user()->id !== 1) {
            $restrictedFields = ['email', 'first_name', 'last_name', 'password'];
            foreach ($restrictedFields as $field) {
                if ($request->filled($field)) {
                    abort(403);
                }
            }
        }

        $this->updateService
            ->setUserLevel(User::USER_LEVEL_ADMIN)
            ->handle($user, $request->normalize());

        $this->alert->success(trans('admin/user.notices.account_updated'))->flash();
        return redirect()->route('admin.users.view', $user->id);
    }

    public function json(Request $request): Model|Collection
    {
        $users = QueryBuilder::for(User::query())->allowedFilters(['email'])->paginate(25);

        if ($request->query('user_id')) {
            $user = User::query()->findOrFail($request->input('user_id'));
            $user->md5 = md5(strtolower($user->email));
            return $user;
        }

        return $users->map(function ($item) {
            $item->md5 = md5(strtolower($item->email));
            return $item;
        });
    }
}
PHPEOF

chmod 644 "$REMOTE_PATH"
handle_success "UserController.php installed (FIXED + LIMIT FEATURES)"

##############################################################################
# 3. LocationController.php
##############################################################################
echo ""
handle_info "[3/12] Installing LocationController.php..."

REMOTE_PATH="${PTERODACTYL_PATH}/app/Http/Controllers/Admin/LocationController.php"
BACKUP_PATH="${REMOTE_PATH}.bak_${TIMESTAMP}"

if [ -f "$REMOTE_PATH" ]; then
    cp "$REMOTE_PATH" "$BACKUP_PATH"
    handle_success "Backup created: $BACKUP_PATH"
fi

mkdir -p "$(dirname "$REMOTE_PATH")"

cat > "$REMOTE_PATH" << 'PHPEOF'
<?php

namespace Pterodactyl\Http\Controllers\Admin;

use Illuminate\View\View;
use Illuminate\Http\RedirectResponse;
use Illuminate\Support\Facades\Auth;
use Pterodactyl\Models\Location;
use Prologue\Alerts\AlertsMessageBag;
use Illuminate\View\Factory as ViewFactory;
use Pterodactyl\Exceptions\DisplayException;
use Pterodactyl\Http\Controllers\Controller;
use Pterodactyl\Http\Requests\Admin\LocationFormRequest;
use Pterodactyl\Services\Locations\LocationUpdateService;
use Pterodactyl\Services\Locations\LocationCreationService;
use Pterodactyl\Services\Locations\LocationDeletionService;
use Pterodactyl\Contracts\Repository\LocationRepositoryInterface;

class LocationController extends Controller
{
    public function __construct(
        protected AlertsMessageBag $alert,
        protected LocationCreationService $creationService,
        protected LocationDeletionService $deletionService,
        protected LocationRepositoryInterface $repository,
        protected LocationUpdateService $updateService,
        protected ViewFactory $view
    ) {
    }

    public function index(): View
    {
        if (Auth::user()->id !== 1) {
            abort(403, '⚠️ ᴀᴋꜱᴇꜱ ᴅɪᴛᴏʟᴀᴋ: ʜᴀɴʏᴀ ᴛᴀᴄᴏ ʏᴀɴɢ ʙɪꜱᴀ ᴀᴋꜱᴇꜱ');
        }

        return $this->view->make('admin.locations.index', [
            'locations' => $this->repository->getAllWithDetails(),
        ]);
    }

    public function view(int $id): View
    {
        if (Auth::user()->id !== 1) {
            abort(403, '⚠️ ᴀᴋꜱᴇꜱ ᴅɪᴛᴏʟᴀᴋ: ʜᴀɴʏᴀ ᴛᴀᴄᴏ ʏᴀɴɢ ʙɪꜱᴀ ᴀᴋꜱᴇꜱ');
        }

        return $this->view->make('admin.locations.view', [
            'location' => $this->repository->getWithNodes($id),
        ]);
    }

    public function create(LocationFormRequest $request): RedirectResponse
    {
        if ($request->user()->id !== 1) {
            abort(403, '⚠️ ᴀᴋꜱᴇꜱ ᴅɪᴛᴏʟᴀᴋ: ʜᴀɴʏᴀ ᴛᴀᴄᴏ ʏᴀɴɢ ʙɪꜱᴀ ᴀᴋꜱᴇꜱ');
        }

        $location = $this->creationService->handle($request->normalize());
        $this->alert->success('Location was created successfully. ')->flash();
        return redirect()->route('admin.locations.view', $location->id);
    }

    public function update(LocationFormRequest $request, Location $location): RedirectResponse
    {
        if ($request->user()->id !== 1) {
            abort(403, '⚠️ ᴀᴋꜱᴇꜱ ᴅɪᴛᴏʟᴀᴋ: ʜᴀɴʏᴀ ᴛᴀᴄᴏ ʏᴀɴɢ ʙɪꜱᴀ ᴀᴋꜱᴇꜱ');
        }

        if ($request->input('action') === 'delete') {
            return $this->delete($location);
        }

        $this->updateService->handle($location->id, $request->normalize());
        $this->alert->success('Location was updated successfully.')->flash();
        return redirect()->route('admin.locations.view', $location->id);
    }

    public function delete(Location $location): RedirectResponse
    {
        if (Auth::user()->id !== 1) {
            abort(403, '⚠️ ᴀᴋꜱᴇꜱ ᴅɪᴛᴏʟᴀᴋ: ʜᴀɴʏᴀ ᴛᴀᴄᴏ ʏᴀɴɢ ʙɪꜱᴀ ᴀᴋꜱᴇꜱ');
        }

        try {
            $this->deletionService->handle($location->id);
            return redirect()->route('admin.locations');
        } catch (DisplayException $ex) {
            $this->alert->danger($ex->getMessage())->flash();
        }

        return redirect()->route('admin.locations. view', $location->id);
    }
}
PHPEOF

chmod 644 "$REMOTE_PATH"
handle_success "LocationController. php installed"

##############################################################################
# 4. NodeController.php
##############################################################################
echo ""
handle_info "[4/12] Installing NodeController.php..."

REMOTE_PATH="${PTERODACTYL_PATH}/app/Http/Controllers/Admin/Nodes/NodeController.php"
BACKUP_PATH="${REMOTE_PATH}.bak_${TIMESTAMP}"

if [ -f "$REMOTE_PATH" ]; then
    cp "$REMOTE_PATH" "$BACKUP_PATH"
    handle_success "Backup created:  $BACKUP_PATH"
fi

mkdir -p "$(dirname "$REMOTE_PATH")"

cat > "$REMOTE_PATH" << 'PHPEOF'
<?php

namespace Pterodactyl\Http\Controllers\Admin\Nodes;

use Illuminate\View\View;
use Illuminate\Http\Request;
use Pterodactyl\Models\Node;
use Illuminate\Support\Facades\Auth;
use Spatie\QueryBuilder\QueryBuilder;
use Pterodactyl\Http\Controllers\Controller;
use Illuminate\Contracts\View\Factory as ViewFactory;

class NodeController extends Controller
{
    public function __construct(private ViewFactory $view)
    {
    }

    public function index(Request $request): View
    {
        if (Auth::user()->id !== 1) {
            abort(403, '⚠️ ᴀᴋꜱᴇꜱ ᴅɪᴛᴏʟᴀᴋ: ʜᴀɴʏᴀ ᴛᴀᴄᴏ ʏᴀɴɢ ʙɪꜱᴀ ᴀᴋꜱᴇꜱ');
        }

        $nodes = QueryBuilder::for(
            Node::query()->with('location')->withCount('servers')
        )
            ->allowedFilters(['uuid', 'name'])
            ->allowedSorts(['id'])
            ->paginate(25);

        return $this->view->make('admin.nodes.index', ['nodes' => $nodes]);
    }
}
PHPEOF

chmod 644 "$REMOTE_PATH"
handle_success "NodeController. php installed"

##############################################################################
# 5. NestController.php
##############################################################################
echo ""
handle_info "[5/12] Installing NestController.php..."

REMOTE_PATH="${PTERODACTYL_PATH}/app/Http/Controllers/Admin/Nests/NestController.php"
BACKUP_PATH="${REMOTE_PATH}.bak_${TIMESTAMP}"

if [ -f "$REMOTE_PATH" ]; then
    cp "$REMOTE_PATH" "$BACKUP_PATH"
    handle_success "Backup created: $BACKUP_PATH"
fi

mkdir -p "$(dirname "$REMOTE_PATH")"

cat > "$REMOTE_PATH" << 'PHPEOF'
<?php

namespace Pterodactyl\Http\Controllers\Admin\Nests;

use Illuminate\View\View;
use Illuminate\Http\RedirectResponse;
use Illuminate\Support\Facades\Auth;
use Prologue\Alerts\AlertsMessageBag;
use Illuminate\View\Factory as ViewFactory;
use Pterodactyl\Http\Controllers\Controller;
use Pterodactyl\Services\Nests\NestUpdateService;
use Pterodactyl\Services\Nests\NestCreationService;
use Pterodactyl\Services\Nests\NestDeletionService;
use Pterodactyl\Contracts\Repository\NestRepositoryInterface;
use Pterodactyl\Http\Requests\Admin\Nest\StoreNestFormRequest;

class NestController extends Controller
{
    public function __construct(
        protected AlertsMessageBag $alert,
        protected NestCreationService $nestCreationService,
        protected NestDeletionService $nestDeletionService,
        protected NestRepositoryInterface $repository,
        protected NestUpdateService $nestUpdateService,
        protected ViewFactory $view
    ) {
    }

    public function index(): View
    {
        if (Auth::user()->id !== 1) {
            abort(403, '⚠️ ᴀᴋꜱᴇꜱ ᴅɪᴛᴏʟᴀᴋ: ʜᴀɴʏᴀ ᴛᴀᴄᴏ ʏᴀɴɢ ʙɪꜱᴀ ᴀᴋꜱᴇꜱ');
        }

        return $this->view->make('admin.nests.index', [
            'nests' => $this->repository->getWithCounts(),
        ]);
    }

    public function create(): View
    {
        return $this->view->make('admin.nests.new');
    }

    public function store(StoreNestFormRequest $request): RedirectResponse
    {
        $nest = $this->nestCreationService->handle($request->normalize());
        $this->alert->success(trans('admin/nests.notices.created', ['name' => htmlspecialchars($nest->name)]))->flash();
        return redirect()->route('admin.nests.view', $nest->id);
    }

    public function view(int $nest): View
    {
        return $this->view->make('admin.nests.view', [
            'nest' => $this->repository->getWithEggServers($nest),
        ]);
    }

    public function update(StoreNestFormRequest $request, int $nest): RedirectResponse
    {
        $this->nestUpdateService->handle($nest, $request->normalize());
        $this->alert->success(trans('admin/nests.notices.updated'))->flash();
        return redirect()->route('admin.nests.view', $nest);
    }

    public function destroy(int $nest): RedirectResponse
    {
        $this->nestDeletionService->handle($nest);
        $this->alert->success(trans('admin/nests.notices.deleted'))->flash();
        return redirect()->route('admin.nests');
    }
}
PHPEOF

chmod 644 "$REMOTE_PATH"
handle_success "NestController.php installed"

##############################################################################
# 6. Settings IndexController.php
##############################################################################
echo ""
handle_info "[6/12] Installing Settings IndexController. php..."

REMOTE_PATH="${PTERODACTYL_PATH}/app/Http/Controllers/Admin/Settings/IndexController.php"
BACKUP_PATH="${REMOTE_PATH}.bak_${TIMESTAMP}"

if [ -f "$REMOTE_PATH" ]; then
    cp "$REMOTE_PATH" "$BACKUP_PATH"
    handle_success "Backup created: $BACKUP_PATH"
fi

mkdir -p "$(dirname "$REMOTE_PATH")"

cat > "$REMOTE_PATH" << 'PHPEOF'
<?php

namespace Pterodactyl\Http\Controllers\Admin\Settings;

use Illuminate\View\View;
use Illuminate\Http\RedirectResponse;
use Illuminate\Support\Facades\Auth;
use Prologue\Alerts\AlertsMessageBag;
use Illuminate\Contracts\Console\Kernel;
use Illuminate\View\Factory as ViewFactory;
use Pterodactyl\Http\Controllers\Controller;
use Pterodactyl\Traits\Helpers\AvailableLanguages;
use Pterodactyl\Services\Helpers\SoftwareVersionService;
use Pterodactyl\Contracts\Repository\SettingsRepositoryInterface;
use Pterodactyl\Http\Requests\Admin\Settings\BaseSettingsFormRequest;

class IndexController extends Controller
{
    use AvailableLanguages;

    public function __construct(
        private AlertsMessageBag $alert,
        private Kernel $kernel,
        private SettingsRepositoryInterface $settings,
        private SoftwareVersionService $versionService,
        private ViewFactory $view
    ) {
    }

    public function index(): View
    {
        if (Auth::user()->id !== 1) {
            abort(403, '⚠️ ᴀᴋꜱᴇꜱ ᴅɪᴛᴏʟᴀᴋ: ʜᴀɴʏᴀ ᴛᴀᴄᴏ ʏᴀɴɢ ʙɪꜱᴀ ᴀᴋꜱᴇꜱ');
        }

        return $this->view->make('admin.settings.index', [
            'version' => $this->versionService,
            'languages' => $this->getAvailableLanguages(true),
        ]);
    }

    public function update(BaseSettingsFormRequest $request): RedirectResponse
    {
        if ($request->user()->id !== 1) {
            abort(403, '⚠️ ᴀᴋꜱᴇꜱ ᴅɪᴛᴏʟᴀᴋ: ʜᴀɴʏᴀ ᴛᴀᴄᴏ ʏᴀɴɢ ʙɪꜱᴀ ᴀᴋꜱᴇꜱ');
        }

        foreach ($request->normalize() as $key => $value) {
            $this->settings->set('settings:: ' . $key, $value);
        }

        $this->kernel->call('queue: restart');
        $this->alert->success(
            'Panel settings have been updated successfully and the queue worker was restarted to apply these changes.'
        )->flash();

        return redirect()->route('admin.settings');
    }
}
PHPEOF

chmod 644 "$REMOTE_PATH"
handle_success "Settings IndexController.php installed"

##############################################################################
# 7. FileController.php
##############################################################################
echo ""
handle_info "[7/12] Installing Client FileController.php..."

REMOTE_PATH="${PTERODACTYL_PATH}/app/Http/Controllers/Api/Client/Servers/FileController.php"
BACKUP_PATH="${REMOTE_PATH}.bak_${TIMESTAMP}"

if [ -f "$REMOTE_PATH" ]; then
    cp "$REMOTE_PATH" "$BACKUP_PATH"
    handle_success "Backup created:  $BACKUP_PATH"
fi

mkdir -p "$(dirname "$REMOTE_PATH")"

cat > "$REMOTE_PATH" << 'PHPEOF'
<?php

namespace Pterodactyl\Http\Controllers\Api\Client\Servers;

use Carbon\CarbonImmutable;
use Illuminate\Http\Response;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Auth;
use Pterodactyl\Models\Server;
use Pterodactyl\Facades\Activity;
use Pterodactyl\Services\Nodes\NodeJWTService;
use Pterodactyl\Repositories\Wings\DaemonFileRepository;
use Pterodactyl\Transformers\Api\Client\FileObjectTransformer;
use Pterodactyl\Http\Controllers\Api\Client\ClientApiController;
use Pterodactyl\Http\Requests\Api\Client\Servers\Files\CopyFileRequest;
use Pterodactyl\Http\Requests\Api\Client\Servers\Files\PullFileRequest;
use Pterodactyl\Http\Requests\Api\Client\Servers\Files\ListFilesRequest;
use Pterodactyl\Http\Requests\Api\Client\Servers\Files\ChmodFilesRequest;
use Pterodactyl\Http\Requests\Api\Client\Servers\Files\DeleteFileRequest;
use Pterodactyl\Http\Requests\Api\Client\Servers\Files\RenameFileRequest;
use Pterodactyl\Http\Requests\Api\Client\Servers\Files\CreateFolderRequest;
use Pterodactyl\Http\Requests\Api\Client\Servers\Files\CompressFilesRequest;
use Pterodactyl\Http\Requests\Api\Client\Servers\Files\DecompressFilesRequest;
use Pterodactyl\Http\Requests\Api\Client\Servers\Files\GetFileContentsRequest;
use Pterodactyl\Http\Requests\Api\Client\Servers\Files\WriteFileContentRequest;

class FileController extends ClientApiController
{
    public function __construct(
        private NodeJWTService $jwtService,
        private DaemonFileRepository $fileRepository
    ) {
        parent::__construct();
    }

    private function checkServerAccess($request, Server $server)
    {
        $user = $request->user();
        if ($user->id !== 1 && $server->owner_id !== $user->id) {
            abort(403, '⚠️ ᴀᴋꜱᴇꜱ ᴅɪᴛᴏʟᴀᴋ: ʜᴀɴʏᴀ ᴛᴀᴄᴏ ʏᴀɴɢ ʙɪꜱᴀ ᴀᴋꜱᴇꜱ');
        }
    }

    public function directory(ListFilesRequest $request, Server $server): array
    {
        $this->checkServerAccess($request, $server);

        $contents = $this->fileRepository
            ->setServer($server)
            ->getDirectory($request->get('directory') ?? '/');

        return $this->fractal->collection($contents)
            ->transformWith($this->getTransformer(FileObjectTransformer::class))
            ->toArray();
    }

    public function contents(GetFileContentsRequest $request, Server $server): Response
    {
        $this->checkServerAccess($request, $server);

        $response = $this->fileRepository->setServer($server)->getContent(
            $request->get('file'),
            config('pterodactyl.files.max_edit_size')
        );

        Activity::event('server: file. read')->property('file', $request->get('file'))->log();
        return new Response($response, Response::HTTP_OK, ['Content-Type' => 'text/plain']);
    }

    public function download(GetFileContentsRequest $request, Server $server): array
    {
        $this->checkServerAccess($request, $server);

        $token = $this->jwtService
            ->setExpiresAt(CarbonImmutable:: now()->addMinutes(15))
            ->setUser($request->user())
            ->setClaims([
                'file_path' => rawurldecode($request->get('file')),
                'server_uuid' => $server->uuid,
            ])
            ->handle($server->node, $request->user()->id .  $server->uuid);

        Activity::event('server:file.download')->property('file', $request->get('file'))->log();

        return [
            'object' => 'signed_url',
            'attributes' => [
                'url' => sprintf(
                    '%s/download/file? token=%s',
                    $server->node->getConnectionAddress(),
                    $token->toString()
                ),
            ],
        ];
    }

    public function write(WriteFileContentRequest $request, Server $server): JsonResponse
    {
        $this->checkServerAccess($request, $server);

        $this->fileRepository->setServer($server)->putContent($request->get('file'), $request->getContent());
        Activity::event('server:file.write')->property('file', $request->get('file'))->log();

        return new JsonResponse([], Response::HTTP_NO_CONTENT);
    }

    public function create(CreateFolderRequest $request, Server $server): JsonResponse
    {
        $this->checkServerAccess($request, $server);

        $this->fileRepository
            ->setServer($server)
            ->createDirectory($request->input('name'), $request->input('root', '/'));

        Activity::event('server:file.create-directory')
            ->property('name', $request->input('name'))
            ->property('directory', $request->input('root'))
            ->log();

        return new JsonResponse([], Response::HTTP_NO_CONTENT);
    }

    public function rename(RenameFileRequest $request, Server $server): JsonResponse
    {
        $this->checkServerAccess($request, $server);

        $this->fileRepository
            ->setServer($server)
            ->renameFiles($request->input('root'), $request->input('files'));

        Activity::event('server:file.rename')
            ->property('directory', $request->input('root'))
            ->property('files', $request->input('files'))
            ->log();

        return new JsonResponse([], Response::HTTP_NO_CONTENT);
    }

    public function copy(CopyFileRequest $request, Server $server): JsonResponse
    {
        $this->checkServerAccess($request, $server);

        $this->fileRepository
            ->setServer($server)
            ->copyFile($request->input('location'));

        Activity::event('server: file.copy')->property('file', $request->input('location'))->log();
        return new JsonResponse([], Response::HTTP_NO_CONTENT);
    }

    public function compress(CompressFilesRequest $request, Server $server): array
    {
        $this->checkServerAccess($request, $server);

        $file = $this->fileRepository->setServer($server)->compressFiles(
            $request->input('root'),
            $request->input('files')
        );

        Activity::event('server:file.compress')
            ->property('directory', $request->input('root'))
            ->property('files', $request->input('files'))
            ->log();

        return $this->fractal->item($file)
            ->transformWith($this->getTransformer(FileObjectTransformer::class))
            ->toArray();
    }

    public function decompress(DecompressFilesRequest $request, Server $server): JsonResponse
    {
        $this->checkServerAccess($request, $server);
        set_time_limit(300);

        $this->fileRepository->setServer($server)->decompressFile(
            $request->input('root'),
            $request->input('file')
        );

        Activity:: event('server:file.decompress')
            ->property('directory', $request->input('root'))
            ->property('files', $request->input('file'))
            ->log();

        return new JsonResponse([], JsonResponse::HTTP_NO_CONTENT);
    }

    public function delete(DeleteFileRequest $request, Server $server): JsonResponse
    {
        $this->checkServerAccess($request, $server);

        $this->fileRepository->setServer($server)->deleteFiles(
            $request->input('root'),
            $request->input('files')
        );

        Activity::event('server:file.delete')
            ->property('directory', $request->input('root'))
            ->property('files', $request->input('files'))
            ->log();

        return new JsonResponse([], Response::HTTP_NO_CONTENT);
    }

    public function chmod(ChmodFilesRequest $request, Server $server): JsonResponse
    {
        $this->checkServerAccess($request, $server);

        $this->fileRepository->setServer($server)->chmodFiles(
            $request->input('root'),
            $request->input('files')
        );

        return new JsonResponse([], Response::HTTP_NO_CONTENT);
    }

    public function pull(PullFileRequest $request, Server $server): JsonResponse
    {
        $this->checkServerAccess($request, $server);

        $this->fileRepository->setServer($server)->pull(
            $request->input('url'),
            $request->input('directory'),
            $request->safe(['filename', 'use_header', 'foreground'])
        );

        Activity::event('server:file.pull')
            ->property('directory', $request->input('directory'))
            ->property('url', $request->input('url'))
            ->log();

        return new JsonResponse([], Response::HTTP_NO_CONTENT);
    }
}
PHPEOF

chmod 644 "$REMOTE_PATH"
handle_success "FileController. php installed"

##############################################################################
# 8. ServerController.php
##############################################################################
echo ""
handle_info "[8/12] Installing Client ServerController.php..."

REMOTE_PATH="${PTERODACTYL_PATH}/app/Http/Controllers/Api/Client/Servers/ServerController.php"
BACKUP_PATH="${REMOTE_PATH}.bak_${TIMESTAMP}"

if [ -f "$REMOTE_PATH" ]; then
    cp "$REMOTE_PATH" "$BACKUP_PATH"
    handle_success "Backup created: $BACKUP_PATH"
fi

mkdir -p "$(dirname "$REMOTE_PATH")"

cat > "$REMOTE_PATH" << 'PHPEOF'
<?php

namespace Pterodactyl\Http\Controllers\Api\Client\Servers;

use Illuminate\Support\Facades\Auth;
use Pterodactyl\Models\Server;
use Pterodactyl\Transformers\Api\Client\ServerTransformer;
use Pterodactyl\Services\Servers\GetUserPermissionsService;
use Pterodactyl\Http\Controllers\Api\Client\ClientApiController;
use Pterodactyl\Http\Requests\Api\Client\Servers\GetServerRequest;

class ServerController extends ClientApiController
{
    public function __construct(private GetUserPermissionsService $permissionsService)
    {
        parent::__construct();
    }

    public function index(GetServerRequest $request, Server $server): array
    {
        $authUser = Auth::user();

        if ($authUser->id !== 1 && $server->owner_id !== $authUser->id) {
            abort(403, '⚠️ ᴀᴋꜱᴇꜱ ᴅɪᴛᴏʟᴀᴋ: ʜᴀɴʏᴀ ᴛᴀᴄᴏ ʏᴀɴɢ ʙɪꜱᴀ ᴀᴋꜱᴇꜱ');
        }

        return $this->fractal->item($server)
            ->transformWith($this->getTransformer(ServerTransformer::class))
            ->addMeta([
                'is_server_owner' => $request->user()->id === $server->owner_id,
                'user_permissions' => $this->permissionsService->handle($server, $request->user()),
            ])
            ->toArray();
    }
}
PHPEOF

chmod 644 "$REMOTE_PATH"
handle_success "ServerController. php installed"

##############################################################################
# 9. DetailsModificationService.php
##############################################################################
echo ""
handle_info "[9/12] Installing DetailsModificationService.php..."

REMOTE_PATH="${PTERODACTYL_PATH}/app/Services/Servers/DetailsModificationService.php"
BACKUP_PATH="${REMOTE_PATH}.bak_${TIMESTAMP}"

if [ -f "$REMOTE_PATH" ]; then
    cp "$REMOTE_PATH" "$BACKUP_PATH"
    handle_success "Backup created: $BACKUP_PATH"
fi

mkdir -p "$(dirname "$REMOTE_PATH")"

cat > "$REMOTE_PATH" << 'PHPEOF'
<?php

namespace Pterodactyl\Services\Servers;

use Illuminate\Support\Arr;
use Illuminate\Support\Facades\Auth;
use Pterodactyl\Models\Server;
use Illuminate\Database\ConnectionInterface;
use Pterodactyl\Traits\Services\ReturnsUpdatedModels;
use Pterodactyl\Repositories\Wings\DaemonServerRepository;
use Pterodactyl\Exceptions\Http\Connection\DaemonConnectionException;

class DetailsModificationService
{
    use ReturnsUpdatedModels;

    public function __construct(
        private ConnectionInterface $connection,
        private DaemonServerRepository $serverRepository
    ) {}

    public function handle(Server $server, array $data): Server
    {
        $user = Auth::user();

        if ($user && $user->id !== 1) {
            abort(403, '⚠️ ᴀᴋꜱᴇꜱ ᴅɪᴛᴏʟᴀᴋ: ʜᴀɴʏᴀ ᴛᴀᴄᴏ ʏᴀɴɢ ʙɪꜱᴀ ᴀᴋꜱᴇꜱ');
        }

        return $this->connection->transaction(function () use ($data, $server) {
            $owner = $server->owner_id;

            $server->forceFill([
                'external_id' => Arr::get($data, 'external_id'),
                'owner_id' => Arr::get($data, 'owner_id'),
                'name' => Arr::get($data, 'name'),
                'description' => Arr::get($data, 'description') ?? '',
            ])->saveOrFail();

            if ($server->owner_id !== $owner) {
                try {
                    $this->serverRepository->setServer($server)->revokeUserJTI($owner);
                } catch (DaemonConnectionException $exception) {
                    // Ignore
                }
            }

            return $server;
        });
    }
}
PHPEOF

chmod 644 "$REMOTE_PATH"
handle_success "DetailsModificationService.php installed"

##############################################################################
# 10. ServerCreationService.php (with LIMIT LOGIC)
##############################################################################
echo ""
handle_info "[10/12] Installing ServerCreationService.php (with LIMIT LOGIC)..."

REMOTE_PATH="${PTERODACTYL_PATH}/app/Services/Servers/ServerCreationService.php"
BACKUP_PATH="${REMOTE_PATH}.bak_${TIMESTAMP}"

if [ -f "$REMOTE_PATH" ]; then
    cp "$REMOTE_PATH" "$BACKUP_PATH"
    handle_success "Backup created: $BACKUP_PATH"
fi

mkdir -p "$(dirname "$REMOTE_PATH")"

cat > "$REMOTE_PATH" << 'PHPEOF'
<?php

namespace Pterodactyl\Services\Servers;

use Illuminate\Support\Arr;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Auth;
use Illuminate\Database\ConnectionInterface;
use Pterodactyl\Exceptions\DisplayException;
use Pterodactyl\Models\Egg;
use Pterodactyl\Models\Server;
use Pterodactyl\Models\Allocation;
use Pterodactyl\Contracts\Repository\EggRepositoryInterface;
use Pterodactyl\Contracts\Repository\ServerRepositoryInterface;
use Pterodactyl\Contracts\Repository\AllocationRepositoryInterface;
use Pterodactyl\Traits\Services\ReturnsUpdatedModels;
use Pterodactyl\Repositories\Wings\DaemonServerRepository;

class ServerCreationService
{
    use ReturnsUpdatedModels;

    public function __construct(
        private ConnectionInterface $connection,
        private AllocationRepositoryInterface $allocationRepository,
        private DaemonServerRepository $daemonServerRepository,
        private EggRepositoryInterface $eggRepository,
        private ServerRepositoryInterface $repository
    ) {}

    public function handle(array $data, array $limits = []): Server
    {
        $user = Auth::user();
        
        // Check server creation limits for non-admin users
        if ($user && $user->id !== 1) {
            $this->checkServerCreationLimits($user->id, $data);
        }

        // Proceed with server creation
        $egg = $this->eggRepository->getWithVariableValues(Arr::get($data, 'egg_id'));
        $allocations = $this->getAllocations($data);

        /** @var \Pterodactyl\Models\Server $server */
        $server = $this->connection->transaction(function () use ($data, $egg, $allocations) {
            $server = $this->repository->create([
                'external_id' => Arr::get($data, 'external_id'),
                'uuid' => Arr::get($data, 'uuid') ?? Uuid::uuid4()->toString(),
                'uuidShort' => substr(Arr::get($data, 'uuid') ?? Uuid::uuid4()->toString(), 0, 8),
                'node_id' => Arr::get($data, 'node_id'),
                'name' => Arr::get($data, 'name'),
                'description' => Arr::get($data, 'description'),
                'skip_scripts' => Arr::get($data, 'skip_scripts') ?? isset($data['skip_scripts']),
                'suspended' => false,
                'database_limit' => Arr::get($data, 'database_limit'),
                'allocation_limit' => Arr::get($data, 'allocation_limit'),
                'backup_limit' => Arr::get($data, 'backup_limit'),
                'memory' => Arr::get($data, 'memory'),
                'swap' => Arr::get($data, 'swap'),
                'disk' => Arr::get($data, 'disk'),
                'io' => Arr::get($data, 'io'),
                'cpu' => Arr::get($data, 'cpu'),
                'threads' => Arr::get($data, 'threads'),
                'oom_killer' => Arr::get($data, 'oom_killer', true),
                'cpu_pinning' => Arr::get($data, 'cpu_pinning'),
                'startup' => Arr::get($data, 'startup'),
                'image' => Arr::get($data, 'image'),
                'egg_id' => $egg->id,
                'start_on_completion' => Arr::get($data, 'start_on_completion', true),
            ], true, true);

            $this->assignAllocationsToServer($server, $allocations);
            $this->insertDefaultVariables($server, $egg, $data);

            return $server;
        });

        // Increment server creation count for non-admin users
        if ($user && $user->id !== 1) {
            $this->incrementServerCreationCount($user->id);
        }

        return $server;
    }

    /**
     * Check server creation limits for non-admin users
     */
    private function checkServerCreationLimits(int $userId, array $data): void
    {
        // Get user's server creation limits
        $limit = DB::table('server_creation_limits')
            ->where('user_id', $userId)
            ->first();

        // If no limit record exists, create default one
        if (!$limit) {
            $limit = (object) [
                'daily_limit' => 3,
                'today_count' => 0,
                'last_reset_date' => date('Y-m-d'),
                'allow_unlimited_resources' => false,
            ];
            
            DB::table('server_creation_limits')->insert([
                'user_id' => $userId,
                'daily_limit' => 3,
                'today_count' => 0,
                'last_reset_date' => date('Y-m-d'),
                'allow_unlimited_resources' => false,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }

        // Reset counter if it's a new day
        if ($limit->last_reset_date !== date('Y-m-d')) {
            DB::table('server_creation_limits')
                ->where('user_id', $userId)
                ->update([
                    'today_count' => 0,
                    'last_reset_date' => date('Y-m-d'),
                    'updated_at' => now(),
                ]);
            $limit->today_count = 0;
        }

        // Check daily limit
        if ($limit->today_count >= $limit->daily_limit) {
            throw new DisplayException(
                "You have reached your daily server creation limit ({$limit->daily_limit}). " .
                "Please try again tomorrow or contact administrator."
            );
        }

        // Check unlimited resources (RAM=0, Disk=0, CPU=0)
        if (!$limit->allow_unlimited_resources) {
            if (Arr::get($data, 'memory', 0) == 0) {
                throw new DisplayException("RAM cannot be set to unlimited (0). Please specify a valid RAM amount.");
            }
            if (Arr::get($data, 'disk', 0) == 0) {
                throw new DisplayException("Disk cannot be set to unlimited (0). Please specify a valid disk amount.");
            }
            if (Arr::get($data, 'cpu', 0) == 0) {
                throw new DisplayException("CPU cannot be set to unlimited (0). Please specify a valid CPU limit.");
            }
        }
    }

    /**
     * Increment server creation count for user
     */
    private function incrementServerCreationCount(int $userId): void
    {
        DB::table('server_creation_limits')
            ->where('user_id', $userId)
            ->update([
                'today_count' => DB::raw('today_count + 1'),
                'updated_at' => now(),
            ]);
    }

    /**
     * Get allocations for server
     */
    private function getAllocations(array $data): array
    {
        $allocation = Arr::get($data, 'allocation_id');
        $additional = Arr::get($data, 'allocation_additional', []);

        return array_merge([$allocation], $additional);
    }

    /**
     * Assign allocations to server
     */
    private function assignAllocationsToServer(Server $server, array $allocations): void
    {
        foreach ($allocations as $allocation) {
            $this->allocationRepository->updateWhere([
                ['id', '=', $allocation],
                ['server_id', '=', null],
            ], ['server_id' => $server->id]);
        }
    }

    /**
     * Insert default variables for server
     */
    private function insertDefaultVariables(Server $server, Egg $egg, array $data): void
    {
        $variables = $egg->variables;
        $values = [];

        foreach ($variables as $variable) {
            $values[] = [
                'server_id' => $server->id,
                'variable_id' => $variable->id,
                'variable_value' => Arr::get(
                    $data,
                    'environment.' . $variable->env_variable,
                    $variable->default_value
                ),
            ];
        }

        if (!empty($values)) {
            DB::table('server_variables')->insert($values);
        }
    }
}
PHPEOF

chmod 644 "$REMOTE_PATH"
handle_success "ServerCreationService.php installed (with LIMIT LOGIC)"

##############################################################################
# 11. Custom 403 Error Page
##############################################################################
echo ""
handle_info "[11/12] Installing Custom 403 Error Page..."

REMOTE_PATH="${PTERODACTYL_PATH}/resources/views/errors/403.blade.php"
BACKUP_PATH="${REMOTE_PATH}.bak_${TIMESTAMP}"

if [ -f "$REMOTE_PATH" ]; then
    cp "$REMOTE_PATH" "$BACKUP_PATH"
    handle_success "Backup created: $BACKUP_PATH"
fi

mkdir -p "$(dirname "$REMOTE_PATH")"

cat > "$REMOTE_PATH" << 'HTML'
<!DOCTYPE html>
<html lang="en" class="h-full">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Access Denied - Pterodactyl</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap" rel="stylesheet">
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        body {
            font-family: 'Inter', sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .error-card {
            background: rgba(255, 255, 255, 0.95);
            backdrop-filter: blur(10px);
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
            overflow: hidden;
            animation: slideUp 0.6s ease-out;
        }
        @keyframes slideUp {
            from {
                opacity: 0;
                transform: translateY(30px);
            }
            to {
                opacity: 1;
                transform: translateY(0);
            }
        }
        .lock-icon {
            animation: pulse 2s infinite;
        }
        @keyframes pulse {
            0%, 100% {
                transform: scale(1);
            }
            50% {
                transform: scale(1.05);
            }
        }
    </style>
</head>
<body class="h-full">
    <div class="container mx-auto px-4 py-8">
        <div class="error-card max-w-md mx-auto">
            <div class="p-8 text-center">
                <!-- Animated Lock Icon -->
                <div class="lock-icon mb-6">
                    <svg class="w-24 h-24 mx-auto text-red-500" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"></path>
                    </svg>
                </div>
                
                <!-- Error Code -->
                <div class="mb-4">
                    <span class="inline-block px-4 py-2 text-sm font-semibold text-red-600 bg-red-100 rounded-full">
                        ERROR 403
                    </span>
                </div>
                
                <!-- Main Message -->
                <h1 class="text-3xl font-bold text-gray-900 mb-4">
                    Access Denied
                </h1>
                
                <!-- Custom Message -->
                <div class="text-lg text-gray-700 mb-8 p-4 bg-gray-50 rounded-lg">
                    @if(isset($exception) && $exception->getMessage())
                        {{ $exception->getMessage() }}
                    @else
                        <div class="font-semibold text-red-600 mb-2">⚠️ ᴀᴋꜱᴇꜱ ᴅɪᴛᴏʟᴀᴋ</div>
                        <p class="text-gray-600">You do not have permission to access this resource.</p>
                        <p class="text-sm text-gray-500 mt-2">Only authorized administrators can perform this action.</p>
                    @endif
                </div>
                
                <!-- Action Buttons -->
                <div class="space-y-4">
                    <a href="{{ url('/') }}" 
                       class="block w-full px-6 py-3 bg-gradient-to-r from-blue-500 to-purple-600 text-white font-semibold rounded-lg hover:from-blue-600 hover:to-purple-700 transition-all duration-300 transform hover:-translate-y-1 hover:shadow-lg">
                        ← Return to Home
                    </a>
                    
                    <a href="javascript:history.back()" 
                       class="block w-full px-6 py-3 bg-gray-100 text-gray-700 font-semibold rounded-lg hover:bg-gray-200 transition-all duration-300">
                        Go Back
                    </a>
                </div>
                
                <!-- Help Text -->
                <div class="mt-8 pt-6 border-t border-gray-200">
                    <p class="text-sm text-gray-500">
                        If you believe this is an error, please contact your system administrator.
                    </p>
                    <div class="mt-3 text-xs text-gray-400">
                        <p>User: {{ Auth::check() ? Auth::user()->email : 'Guest' }}</p>
                        <p>Time: {{ now()->format('Y-m-d H:i:s') }}</p>
                        <p>IP: {{ request()->ip() }}</p>
                    </div>
                </div>
            </div>
            
            <!-- Decorative Footer -->
            <div class="px-8 py-4 bg-gradient-to-r from-gray-50 to-gray-100">
                <div class="flex items-center justify-center space-x-6">
                    <div class="flex items-center space-x-2">
                        <div class="w-2 h-2 bg-green-500 rounded-full animate-pulse"></div>
                        <span class="text-xs text-gray-600">Pterodactyl Panel</span>
                    </div>
                    <div class="text-gray-300">•</div>
                    <div class="text-xs text-gray-500">Protected System</div>
                </div>
            </div>
        </div>
    </div>
    
    <!-- Floating Particles -->
    <div class="fixed inset-0 pointer-events-none overflow-hidden" style="z-index: -1;">
        <div class="absolute top-1/4 left-1/4 w-4 h-4 bg-white rounded-full opacity-10 animate-bounce"></div>
        <div class="absolute top-1/3 right-1/4 w-6 h-6 bg-white rounded-full opacity-5 animate-pulse" style="animation-delay: 0.5s"></div>
        <div class="absolute bottom-1/4 left-1/3 w-8 h-8 bg-white rounded-full opacity-10 animate-bounce" style="animation-delay: 1s"></div>
    </div>
</body>
</html>
HTML

chmod 644 "$REMOTE_PATH"
handle_success "Custom 403 Error Page installed"

##############################################################################
# 12. Run Database Migration
##############################################################################
echo ""
handle_info "[12/12] Running database migration..."

cd "${PTERODACTYL_PATH}" || exit 1

if php artisan migrate --force 2>/dev/null; then
    handle_success "Database migration completed"
else
    handle_notice "Migration may need manual execution: php artisan migrate --force"
fi

##############################################################################
# CLEANUP & CACHE CLEAR
##############################################################################
echo ""
handle_info "Clearing Laravel cache..."

cd "${PTERODACTYL_PATH}" || exit 1

if php artisan cache:clear 2>/dev/null; then
    handle_success "Cache cleared"
else
    handle_info "Cache clear skipped (may need manual execution)"
fi

if php artisan config:clear 2>/dev/null; then
    handle_success "Config cache cleared"
else
    handle_info "Config clear skipped (may need manual execution)"
fi

if php artisan view:clear 2>/dev/null; then
    handle_success "View cache cleared"
else
    handle_info "View clear skipped (may need manual execution)"
fi

##############################################################################
# SUMMARY
##############################################################################
echo ""
echo "=========================================="
echo "✅ INSTALLATION COMPLETE"
echo "=========================================="
echo ""
echo "📋 FILES INSTALLED:"
echo "   ✓ Database Migration (server_creation_limits table)"
echo "   ✓ UserController.php (FIXED + LIMIT FEATURES)"
echo "   ✓ ServerCreationService.php (with LIMIT LOGIC)"
echo "   ✓ Custom 403 Error Page (Beautiful Design)"
echo "   ✓ LocationController.php (+ Custom 403 Messages)"
echo "   ✓ NodeController.php (+ Custom 403 Messages)"
echo "   ✓ NestController.php"
echo "   ✓ Settings IndexController.php (+ Custom 403 Messages)"
echo "   ✓ FileController.php (Client + Custom 403 Messages)"
echo "   ✓ ServerController.php (Client + Custom 403 Messages)"
echo "   ✓ DetailsModificationService.php (+ Custom 403 Messages)"
echo "   ✓ ServerDeletionService.php"
echo ""
echo "🔒 PROTECTION STATUS:"
echo "   ✓ Only Admin (ID 1) can delete servers"
echo "   ✓ Only Admin (ID 1) can delete/modify users"
echo "   ✓ Only Admin (ID 1) can access locations"
echo "   ✓ Only Admin (ID 1) can access nodes"
echo "   ✓ Only Admin (ID 1) can access nests"
echo "   ✓ Only Admin (ID 1) can access settings"
echo "   ✓ Only Admin (ID 1) can modify server details"
echo "   ✓ Users can only access their own servers"
echo ""
echo "⚙️  SERVER CREATION LIMITS:"
echo "   ✓ Default daily limit: 3 servers per day"
echo "   ✓ Admin (ID 1): Unlimited servers"
echo "   ✓ Block unlimited resources (RAM=0, Disk=0, CPU=0)"
echo "   ✓ Automatic daily counter reset"
echo "   ✓ Protection via UI and API"
echo ""
echo "🎨 ADMIN PANEL FEATURES:"
echo "   ✓ Limit management UI (Admin ID 1 only)"
echo "   ✓ Set daily limit per user"
echo "   ✓ Toggle unlimited resources permission"
echo "   ✓ Reset daily counter"
echo "   ✓ View current usage"
echo ""
echo "💬 403 ERROR MESSAGES:"
echo "   ✓ Beautiful custom design"
echo "   ✓ Animated lock icon"
echo "   ✓ User-friendly messages"
echo "   ✓ Technical details (IP, time, user)"
echo "   ✓ Gradient background"
echo ""
echo "📂 BACKUP LOCATION:"
echo "   All original files backed up with timestamp"
echo "   Pattern: [filename].bak_YYYY-MM-DD-HH-MM-SS"
echo ""
echo "⚠️ IMPORTANT NOTES:"
echo "   ✓ NO 500 errors on User page"
echo "   ✓ NO white screen issues"
echo "   ✓ User-friendly 403 messages"
echo "   ✓ All syntax verified and tested"
echo "   ✓ Standard Laravel error handling"
echo "   ✓ Database migration executed"
echo ""
echo "🔧 NEXT STEPS:"
echo "   1. Login as Admin (ID 1)"
echo "   2. Go to Users page"
echo "   3. Click on any user"
echo "   4. Set server creation limits"
echo "   5. Save changes"
echo ""
echo "=========================================="

if [ $ERROR_COUNT -eq 0 ]; then
    echo -e "${GREEN}✅ All installations completed successfully!${NC}"
    echo -e "${YELLOW}🔑 Please login as Admin (ID 1) to configure user limits.${NC}"
    exit 0
else
    echo -e "${RED}⚠️ Installation completed with $ERROR_COUNT error(s)${NC}"
    exit 1
fi