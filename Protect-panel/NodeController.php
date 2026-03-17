<?php

namespace Pterodactyl\Http\Controllers\Admin\Nodes;

use Illuminate\View\View;
use Illuminate\Http\Request;
use Illuminate\Http\RedirectResponse;
use Illuminate\Support\Facades\Auth;
use Illuminate\Contracts\View\Factory as ViewFactory;
use Pterodactyl\Models\Node;
use Spatie\QueryBuilder\QueryBuilder;
use Pterodactyl\Http\Controllers\Controller;
use Pterodactyl\Http\Requests\Admin\NodeFormRequest;
use Pterodactyl\Services\Nodes\NodeUpdateService;
use Pterodactyl\Services\Nodes\NodeCreationService;
use Pterodactyl\Services\Nodes\NodeDeletionService;
use Pterodactyl\Contracts\Repository\NodeRepositoryInterface;
use Prologue\Alerts\AlertsMessageBag;
use Pterodactyl\Exceptions\DisplayException;

class NodeController extends Controller
{
    public function __construct(
        protected ViewFactory $view,
        protected NodeRepositoryInterface $repository,
        protected NodeCreationService $creationService,
        protected NodeUpdateService $updateService,
        protected NodeDeletionService $deletionService,
        protected AlertsMessageBag $alert
    ) {
    }

    private function checkAdminAccess(): void
    {
        $user = Auth::user();
        if (!$user || $user->id !== 1) {
            abort(403, 'Akses ditolak! Hanya Admin utama (ID 1) yang dapat mengakses menu Nodes. ©Protect By @WiL Official');
        }
    }

    public function index(Request $request): View
    {
        $this->checkAdminAccess();

        $nodes = QueryBuilder::for(
            Node::query()->with('location')->withCount('servers')
        )
            ->allowedFilters(['uuid', 'name'])
            ->allowedSorts(['id'])
            ->paginate(25);

        return $this->view->make('admin.nodes.index', ['nodes' => $nodes]);
    }

    public function create(): View
    {
        $this->checkAdminAccess();
        return $this->view->make('admin.nodes.new');
    }

    public function store(NodeFormRequest $request): RedirectResponse
    {
        $this->checkAdminAccess();

        $node = $this->creationService->handle($request->normalize());
        $this->alert->success('Node berhasil dibuat.')->flash();

        return redirect()->route('admin.nodes.view', $node->id);
    }

    public function view(int $id): View
    {
        $this->checkAdminAccess();

        $node = $this->repository->getByIdWithAllocations($id);
        return $this->view->make('admin.nodes.view', ['node' => $node]);
    }

    public function edit(int $id): View
    {
        $this->checkAdminAccess();

        $node = $this->repository->getById($id);
        return $this->view->make('admin.nodes.edit', ['node' => $node]);
    }

    public function update(NodeFormRequest $request, int $id): RedirectResponse
    {
        $this->checkAdminAccess();

        $this->updateService->handle($id, $request->normalize());
        $this->alert->success('Node berhasil diperbarui.')->flash();

        return redirect()->route('admin.nodes.view', $id);
    }

    public function delete(int $id): RedirectResponse
    {
        $this->checkAdminAccess();

        try {
            $this->deletionService->handle($id);
            $this->alert->success('Node berhasil dihapus.')->flash();
            return redirect()->route('admin.nodes');
        } catch (DisplayException $ex) {
            $this->alert->danger($ex->getMessage())->flash();
        }

        return redirect()->route('admin.nodes.view', $id);
    }
}
