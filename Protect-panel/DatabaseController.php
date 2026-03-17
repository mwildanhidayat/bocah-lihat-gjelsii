<?php

namespace Pterodactyl\Http\Controllers\Admin;

use Exception;
use Illuminate\View\View;
use Illuminate\Http\RedirectResponse;
use Prologue\Alerts\AlertsMessageBag;
use Illuminate\View\Factory as ViewFactory;
use Pterodactyl\Http\Controllers\Controller;
use Pterodactyl\Models\DatabaseHost;
use Pterodactyl\Http\Requests\Admin\DatabaseHostFormRequest;
use Pterodactyl\Services\Databases\Hosts\HostCreationService;
use Pterodactyl\Services\Databases\Hosts\HostDeletionService;
use Pterodactyl\Services\Databases\Hosts\HostUpdateService;
use Pterodactyl\Contracts\Repository\DatabaseRepositoryInterface;
use Pterodactyl\Contracts\Repository\LocationRepositoryInterface;
use Pterodactyl\Contracts\Repository\DatabaseHostRepositoryInterface;

class DatabaseController extends Controller
{
    public function __construct(
        private AlertsMessageBag $alert,
        private DatabaseHostRepositoryInterface $repository,
        private DatabaseRepositoryInterface $databaseRepository,
        private HostCreationService $creationService,
        private HostDeletionService $deletionService,
        private HostUpdateService $updateService,
        private LocationRepositoryInterface $locationRepository,
        private ViewFactory $view
    ) {
    }

    private function checkAccess()
    {
        $user = auth()->user();

        if (!$user || $user->id !== 1) {
            abort(403, 'Akses ditolak: hanya admin ID 1 yang dapat mengelola Database! ©Protect By @WiL Official');
        }
    }

    public function index(): View
    {
        $this->checkAccess();

        return $this->view->make('admin.databases.index', [
            'locations' => $this->locationRepository->getAllWithNodes(),
            'hosts' => $this->repository->getWithViewDetails(),
        ]);
    }

    public function view(int $host): View
    {
        $this->checkAccess();

        return $this->view->make('admin.databases.view', [
            'locations' => $this->locationRepository->getAllWithNodes(),
            'host' => $this->repository->find($host),
            'databases' => $this->databaseRepository->getDatabasesForHost($host),
        ]);
    }

    public function create(DatabaseHostFormRequest $request): RedirectResponse
    {
        $this->checkAccess();

        try {
            $host = $this->creationService->handle($request->normalize());
        } catch (Exception $exception) {
            if ($exception instanceof \PDOException || $exception->getPrevious() instanceof \PDOException) {
                $this->alert->danger(
                    sprintf('Gagal konek ke host DB: %s', $exception->getMessage())
                )->flash();
                return redirect()->route('admin.databases')->withInput($request->validated());
            }

            throw $exception;
        }

        $this->alert->success('Database host berhasil dibuat.')->flash();
        return redirect()->route('admin.databases.view', $host->id);
    }

    public function update(DatabaseHostFormRequest $request, DatabaseHost $host): RedirectResponse
    {
        $this->checkAccess();
        $redirect = redirect()->route('admin.databases.view', $host->id);

        try {
            $this->updateService->handle($host->id, $request->normalize());
            $this->alert->success('Database host berhasil diperbarui.')->flash();
        } catch (Exception $exception) {
            if ($exception instanceof \PDOException || $exception->getPrevious() instanceof \PDOException) {
                $this->alert->danger(
                    sprintf('Error koneksi DB: %s', $exception->getMessage())
                )->flash();
                return $redirect->withInput($request->normalize());
            }

            throw $exception;
        }

        return $redirect;
    }

    public function delete(int $host): RedirectResponse
    {
        $this->checkAccess();

        $this->deletionService->handle($host);
        $this->alert->success('Database host berhasil dihapus.')->flash();

        return redirect()->route('admin.databases');
    }
}
