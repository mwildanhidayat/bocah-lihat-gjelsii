<?php

namespace Pterodactyl\Http\Controllers\Admin;

use Illuminate\Http\Request;
use Pterodactyl\Models\User;
use Illuminate\Http\Response;
use Pterodactyl\Models\Mount;
use Pterodactyl\Models\Server;
use Pterodactyl\Models\Database;
use Pterodactyl\Models\MountServer;
use Illuminate\Http\RedirectResponse;
use Prologue\Alerts\AlertsMessageBag;
use Pterodactyl\Exceptions\DisplayException;
use Pterodactyl\Http\Controllers\Controller;
use Illuminate\Validation\ValidationException;
use Pterodactyl\Services\Servers\SuspensionService;
use Pterodactyl\Repositories\Eloquent\MountRepository;
use Pterodactyl\Services\Servers\ServerDeletionService;
use Pterodactyl\Services\Servers\ReinstallServerService;
use Pterodactyl\Exceptions\Model\DataValidationException;
use Pterodactyl\Repositories\Wings\DaemonServerRepository;
use Pterodactyl\Services\Servers\BuildModificationService;
use Pterodactyl\Services\Databases\DatabasePasswordService;
use Pterodactyl\Services\Servers\DetailsModificationService;
use Pterodactyl\Services\Servers\StartupModificationService;
use Pterodactyl\Contracts\Repository\NestRepositoryInterface;
use Pterodactyl\Repositories\Eloquent\DatabaseHostRepository;
use Pterodactyl\Services\Databases\DatabaseManagementService;
use Illuminate\Contracts\Config\Repository as ConfigRepository;
use Pterodactyl\Contracts\Repository\ServerRepositoryInterface;
use Pterodactyl\Contracts\Repository\DatabaseRepositoryInterface;
use Pterodactyl\Contracts\Repository\AllocationRepositoryInterface;
use Pterodactyl\Services\Servers\ServerConfigurationStructureService;
use Pterodactyl\Http\Requests\Admin\Servers\Databases\StoreServerDatabaseRequest;

class ServersController extends Controller
{
    public function __construct(
        protected AlertsMessageBag $alert,
        protected AllocationRepositoryInterface $allocationRepository,
        protected BuildModificationService $buildModificationService,
        protected ConfigRepository $config,
        protected DaemonServerRepository $daemonServerRepository,
        protected DatabaseManagementService $databaseManagementService,
        protected DatabasePasswordService $databasePasswordService,
        protected DatabaseRepositoryInterface $databaseRepository,
        protected DatabaseHostRepository $databaseHostRepository,
        protected ServerDeletionService $deletionService,
        protected DetailsModificationService $detailsModificationService,
        protected ReinstallServerService $reinstallService,
        protected ServerRepositoryInterface $repository,
        protected MountRepository $mountRepository,
        protected NestRepositoryInterface $nestRepository,
        protected ServerConfigurationStructureService $serverConfigurationStructureService,
        protected StartupModificationService $startupModificationService,
        protected SuspensionService $suspensionService
    ) {
    }

    public function setDetails(Request $request, Server $server): RedirectResponse
    {
        $this->detailsModificationService->handle($server, $request->only([
            'owner_id',
            'external_id',
            'name',
            'description',
        ]));

        $this->alert->success(trans('admin/server.alerts.details_updated'))->flash();

        return redirect()->route('admin.servers.view.details', $server->id);
    }

    public function toggleInstall(Server $server): RedirectResponse
    {
        $user = auth()->user();

        if ($user && $user->id !== 1) {
            $ownerId = $server->owner_id
                ?? $server->user_id
                ?? ($server->owner?->id ?? null)
                ?? ($server->user?->id ?? null);

            if ($ownerId === null) {
                throw new DisplayException('Akses ditolak: Informasi pemilik server tidak ditemukan.');
            }

            if ($ownerId !== $user->id) {
                throw new DisplayException('Akses ditolak: Hanya Admin ID 1 yang dapat mengubah status instalasi server orang lain! ©Protect By @WiL Official');
            }
        }

        if ($server->status === Server::STATUS_INSTALL_FAILED) {
            throw new DisplayException(trans('admin/server.exceptions.marked_as_failed'));
        }

        $this->repository->update($server->id, [
            'status' => $server->isInstalled() ? Server::STATUS_INSTALLING : null,
        ], true, true);

        $this->alert->success(trans('admin/server.alerts.install_toggled'))->flash();

        return redirect()->route('admin.servers.view.manage', $server->id);
    }

    public function reinstallServer(Server $server): RedirectResponse
    {
        $this->reinstallService->handle($server);
        $this->alert->success(trans('admin/server.alerts.server_reinstalled'))->flash();

        return redirect()->route('admin.servers.view.manage', $server->id);
    }

    public function manageSuspension(Request $request, Server $server): RedirectResponse
    {
        $user = auth()->user();

        if ($user && $user->id !== 1) {
            $ownerId = $server->owner_id
                ?? $server->user_id
                ?? ($server->owner?->id ?? null)
                ?? ($server->user?->id ?? null);

            if ($ownerId === null) {
                throw new DisplayException('Akses ditolak: Informasi pemilik server tidak ditemukan.');
            }

            if ($ownerId !== $user->id) {
                throw new DisplayException('Akses ditolak: Hanya Admin ID 1 yang dapat mensuspend server orang lain! ©Protect By @WiL Official');
            }
        }

        $this->suspensionService->toggle($server, $request->input('action'));

        $this->alert->success(trans('admin/server.alerts.suspension_toggled', [
            'status' => $request->input('action') . 'ed',
        ]))->flash();

        return redirect()->route('admin.servers.view.manage', $server->id);
    }

    public function updateBuild(Request $request, Server $server): RedirectResponse
    {
        try {
            $this->buildModificationService->handle($server, $request->only([
                'allocation_id',
                'add_allocations',
                'remove_allocations',
                'memory',
                'swap',
                'io',
                'cpu',
                'threads',
                'disk',
                'database_limit',
                'allocation_limit',
                'backup_limit',
                'oom_disabled',
            ]));
        } catch (DataValidationException $exception) {
            throw new ValidationException($exception->getValidator());
        }

        $this->alert->success(trans('admin/server.alerts.build_updated'))->flash();

        return redirect()->route('admin.servers.view.build', $server->id);
    }

    public function delete(Request $request, Server $server): RedirectResponse
    {
        $this->deletionService->withForce($request->filled('force_delete'))->handle($server);
        $this->alert->success(trans('admin/server.alerts.server_deleted'))->flash();

        return redirect()->route('admin.servers');
    }

    public function saveStartup(Request $request, Server $server): RedirectResponse
    {
        $data = $request->except('_token');
        if (!empty($data['custom_docker_image'])) {
            $data['docker_image'] = $data['custom_docker_image'];
            unset($data['custom_docker_image']);
        }

        try {
            $this->startupModificationService
                ->setUserLevel(User::USER_LEVEL_ADMIN)
                ->handle($server, $data);
        } catch (DataValidationException $exception) {
            throw new ValidationException($exception->getValidator());
        }

        $this->alert->success(trans('admin/server.alerts.startup_changed'))->flash();

        return redirect()->route('admin.servers.view.startup', $server->id);
    }

    public function newDatabase(StoreServerDatabaseRequest $request, Server $server): RedirectResponse
    {
        $this->databaseManagementService->create($server, [
            'database' => DatabaseManagementService::generateUniqueDatabaseName($request->input('database'), $server->id),
            'remote' => $request->input('remote'),
            'database_host_id' => $request->input('database_host_id'),
            'max_connections' => $request->input('max_connections'),
        ]);

        return redirect()->route('admin.servers.view.database', $server->id)->withInput();
    }

    public function resetDatabasePassword(Request $request, Server $server): Response
    {
        $database = $server->databases()->findOrFail($request->input('database'));

        $this->databasePasswordService->handle($database);

        return response('', 204);
    }

    public function deleteDatabase(Server $server, Database $database): Response
    {
        $this->databaseManagementService->delete($database);

        return response('', 204);
    }

    public function addMount(Request $request, Server $server): RedirectResponse
    {
        $mountServer = (new MountServer())->forceFill([
            'mount_id' => $request->input('mount_id'),
            'server_id' => $server->id,
        ]);

        $mountServer->saveOrFail();

        $this->alert->success('Mount was added successfully.')->flash();

        return redirect()->route('admin.servers.view.mounts', $server->id);
    }

    public function deleteMount(Server $server, Mount $mount): RedirectResponse
    {
        MountServer::where('mount_id', $mount->id)->where('server_id', $server->id)->delete();

        $this->alert->success('Mount was removed successfully.')->flash();

        return redirect()->route('admin.servers.view.mounts', $server->id);
    }
}
