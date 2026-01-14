#!/bin/bash

# Script Proteksi Admin ID 1 - VERSI AMAN (Tidak Rusak Panel)
# Dibuat:  2026-01-14
# Author: Safety Version

echo "=========================================="
echo "🔐 INSTALLER PROTEKSI AMAN PTERODACTYL"
echo "=========================================="

# ============================================
# FILE 1: ServerDeletionService.php
# ============================================
echo ""
echo "📝 [1/9] Install ServerDeletionService.php..."

REMOTE_PATH="/var/www/pterodactyl/app/Services/Servers/ServerDeletionService.php"
TIMESTAMP=$(date -u +"%Y-%m-%d-%H-%M-%S")
BACKUP_PATH="${REMOTE_PATH}.bak_${TIMESTAMP}"

if [ -f "$REMOTE_PATH" ]; then
  cp "$REMOTE_PATH" "$BACKUP_PATH"
  echo "   ✅ Backup:  $BACKUP_PATH"
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

        // PROTEKSI: Hanya admin ID 1 atau pemilik server yang bisa hapus
        if ($user && $user->id !== 1) {
            $ownerId = $server->owner_id ?? $server->user_id;
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
                    Log::warning($exception);
                }
            }
            $server->delete();
        });
    }
}
PHPEOF

chmod 644 "$REMOTE_PATH"
echo "   ✅ Selesai"

# ============================================
# FILE 2: UserController.php
# ============================================
echo ""
echo "📝 [2/9] Install UserController.php..."

REMOTE_PATH="/var/www/pterodactyl/app/Http/Controllers/Admin/UserController.php"
BACKUP_PATH="${REMOTE_PATH}. bak_${TIMESTAMP}"

if [ -f "$REMOTE_PATH" ]; then
  cp "$REMOTE_PATH" "$BACKUP_PATH"
  echo "   ✅ Backup:  $BACKUP_PATH"
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

        return $this->view->make('admin.users.index', ['users' => $users]);
    }

    public function create(): View
    {
        return $this->view->make('admin.users.new', [
            'languages' => $this->getAvailableLanguages(true),
        ]);
    }

    public function view(User $user): View
    {
        return $this->view->make('admin.users.view', [
            'user' => $user,
            'languages' => $this->getAvailableLanguages(true),
        ]);
    }

    public function delete(Request $request, User $user): RedirectResponse
    {
        // PROTEKSI: Hanya admin ID 1 yang bisa hapus user
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
        $this->alert->success($this->translator->get('admin/user.notices.account_created'))->flash();
        return redirect()->route('admin.users.view', $user->id);
    }

    public function update(UserFormRequest $request, User $user): RedirectResponse
    {
        // PROTEKSI: Hanya admin ID 1 yang bisa ubah data penting
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
echo "   ✅ Selesai"

# ============================================
# FILE 3: LocationController.php
# ============================================
echo ""
echo "📝 [3/9] Install LocationController.php..."

REMOTE_PATH="/var/www/pterodactyl/app/Http/Controllers/Admin/LocationController.php"
BACKUP_PATH="${REMOTE_PATH}.bak_${TIMESTAMP}"

if [ -f "$REMOTE_PATH" ]; then
  cp "$REMOTE_PATH" "$BACKUP_PATH"
  echo "   ✅ Backup: $BACKUP_PATH"
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
        // PROTEKSI: Hanya admin ID 1
        if (Auth::user()->id !== 1) {
            abort(403);
        }

        return $this->view->make('admin.locations.index', [
            'locations' => $this->repository->getAllWithDetails(),
        ]);
    }

    public function view(int $id): View
    {
        // PROTEKSI:  Hanya admin ID 1
        if (Auth::user()->id !== 1) {
            abort(403);
        }

        return $this->view->make('admin.locations.view', [
            'location' => $this->repository->getWithNodes($id),
        ]);
    }

    public function create(LocationFormRequest $request): RedirectResponse
    {
        // PROTEKSI: Hanya admin ID 1
        if ($request->user()->id !== 1) {
            abort(403);
        }

        $location = $this->creationService->handle($request->normalize());
        $this->alert->success('Location was created successfully. ')->flash();
        return redirect()->route('admin.locations.view', $location->id);
    }

    public function update(LocationFormRequest $request, Location $location): RedirectResponse
    {
        // PROTEKSI: Hanya admin ID 1
        if ($request->user()->id !== 1) {
            abort(403);
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
        // PROTEKSI: Hanya admin ID 1
        if (Auth::user()->id !== 1) {
            abort(403);
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
echo "   ✅ Selesai"

# ============================================
# FILE 4: NodeController.php
# ============================================
echo ""
echo "📝 [4/9] Install NodeController.php..."

REMOTE_PATH="/var/www/pterodactyl/app/Http/Controllers/Admin/Nodes/NodeController.php"
BACKUP_PATH="${REMOTE_PATH}.bak_${TIMESTAMP}"

if [ -f "$REMOTE_PATH" ]; then
  cp "$REMOTE_PATH" "$BACKUP_PATH"
  echo "   ✅ Backup: $BACKUP_PATH"
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
        // PROTEKSI:  Hanya admin ID 1
        if (Auth::user()->id !== 1) {
            abort(403);
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
echo "   ✅ Selesai"

# ============================================
# FILE 5: NestController.php
# ============================================
echo ""
echo "📝 [5/9] Install NestController.php..."

REMOTE_PATH="/var/www/pterodactyl/app/Http/Controllers/Admin/Nests/NestController.php"
BACKUP_PATH="${REMOTE_PATH}.bak_${TIMESTAMP}"

if [ -f "$REMOTE_PATH" ]; then
  cp "$REMOTE_PATH" "$BACKUP_PATH"
  echo "   ✅ Backup: $BACKUP_PATH"
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
        // PROTEKSI: Hanya admin ID 1
        if (Auth:: user()->id !== 1) {
            abort(403);
        }

        return $this->view->make('admin.nests. index', [
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
echo "   ✅ Selesai"

# ============================================
# FILE 6: Settings IndexController.php
# ============================================
echo ""
echo "📝 [6/9] Install Admin Settings IndexController.php..."

REMOTE_PATH="/var/www/pterodactyl/app/Http/Controllers/Admin/Settings/IndexController.php"
BACKUP_PATH="${REMOTE_PATH}.bak_${TIMESTAMP}"

if [ -f "$REMOTE_PATH" ]; then
  cp "$REMOTE_PATH" "$BACKUP_PATH"
  echo "   ✅ Backup: $BACKUP_PATH"
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
        // PROTEKSI: Hanya admin ID 1
        if (Auth:: user()->id !== 1) {
            abort(403);
        }

        return $this->view->make('admin.settings.index', [
            'version' => $this->versionService,
            'languages' => $this->getAvailableLanguages(true),
        ]);
    }

    public function update(BaseSettingsFormRequest $request): RedirectResponse
    {
        // PROTEKSI: Hanya admin ID 1
        if ($request->user()->id !== 1) {
            abort(403);
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
echo "   ✅ Selesai"

# ============================================
# FILE 7: FileController.php
# ============================================
echo ""
echo "📝 [7/9] Install Client Servers FileController.php..."

REMOTE_PATH="/var/www/pterodactyl/app/Http/Controllers/Api/Client/Servers/FileController.php"
BACKUP_PATH="${REMOTE_PATH}.bak_${TIMESTAMP}"

if [ -f "$REMOTE_PATH" ]; then
  cp "$REMOTE_PATH" "$BACKUP_PATH"
  echo "   ✅ Backup: $BACKUP_PATH"
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
            abort(403);
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
echo "   ✅ Selesai"

# ============================================
# FILE 8: ServerController.php
# ============================================
echo ""
echo "📝 [8/9] Install Client Servers ServerController.php..."

REMOTE_PATH="/var/www/pterodactyl/app/Http/Controllers/Api/Client/Servers/ServerController.php"
BACKUP_PATH="${REMOTE_PATH}.bak_${TIMESTAMP}"

if [ -f "$REMOTE_PATH" ]; then
  cp "$REMOTE_PATH" "$BACKUP_PATH"
  echo "   ✅ Backup: $BACKUP_PATH"
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
        
        // PROTEKSI:  Cegah user akses server orang lain
        if ($authUser->id !== 1 && $server->owner_id !== $authUser->id) {
            abort(403);
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
echo "   ✅ Selesai"

# ============================================
# FILE 9: DetailsModificationService.php
# ============================================
echo ""
echo "📝 [9/9] Install DetailsModificationService.php..."

REMOTE_PATH="/var/www/pterodactyl/app/Services/Servers/DetailsModificationService.php"
BACKUP_PATH="${REMOTE_PATH}.bak_${TIMESTAMP}"

if [ -f "$REMOTE_PATH" ]; then
  cp "$REMOTE_PATH" "$BACKUP_PATH"
  echo "   ✅ Backup: $BACKUP_PATH"
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
        
        // PROTEKSI:  Hanya admin ID 1 yang bisa ubah detail server
        if ($user && $user->id !== 1) {
            abort(403);
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
                    // Abaikan
                }
            }

            return $server;
        });
    }
}
PHPEOF

chmod 644 "$REMOTE_PATH"
echo "   ✅ Selesai"

# ============================================
# CLEAR CACHE
# ============================================
echo ""
echo "🧹 Membersihkan cache Laravel..."
cd /var/www/pterodactyl
php artisan cache:clear 2>/dev/null || true
php artisan config:clear 2>/dev/null || true

echo ""
echo "=========================================="
echo "✅ PROTEKSI AMAN BERHASIL DIINSTALL!"
echo "=========================================="
echo ""
echo "📋 RINGKASAN:"
echo "   • ServerDeletionService.php - Proteksi delete server"
echo "   • UserController.php - Proteksi hapus/ubah user"
echo "   • LocationController.php - Proteksi akses location"
echo "   • NodeController.php - Proteksi akses node"
echo "   • NestController.php - Proteksi akses nest"
echo "   • Settings IndexController.php - Proteksi akses settings"
echo "   • FileController.php - Proteksi akses file server"
echo "   • ServerController.php - Proteksi akses API server"
echo "   • DetailsModificationService.php - Proteksi ubah detail server"
echo ""
echo "🔒 STATUS:  Hanya Admin (ID 1) yang bisa akses fitur-fitur di atas"
echo ""
echo "📂 BACKUP FILES:"
echo "   Semua file original sudah di-backup dengan format:"
echo "   [original_path]. bak_[TIMESTAMP]"
echo ""
echo "⚠️ CATATAN PENTING:"
echo "   • Proteksi ini menggunakan abort(403) standard Laravel"
echo "   • Tidak akan menyebabkan white screen atau 500 error"
echo "   • Panel akan menampilkan error 403 yang normal"
echo "   • Jika ada error, restore dari file backup"
echo ""
echo "=========================================="