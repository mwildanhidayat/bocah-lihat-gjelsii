<?php

namespace Pterodactyl\Http\Controllers\Admin\Servers;

use Illuminate\View\View;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Pterodactyl\Models\Server;
use Pterodactyl\Models\User;
use Pterodactyl\Models\Nest;
use Pterodactyl\Models\Location;
use Spatie\QueryBuilder\QueryBuilder;
use Spatie\QueryBuilder\AllowedFilter;
use Pterodactyl\Http\Controllers\Controller;
use Pterodactyl\Models\Filters\AdminServerFilter;
use Illuminate\Contracts\View\Factory as ViewFactory;

class ServerController extends Controller
{
    public function __construct(private ViewFactory $view)
    {
    }

    public function index(Request $request): View
    {
        $user = Auth::user();

        $query = Server::query()
            ->with(['node', 'user', 'allocation'])
            ->orderBy('id', 'asc');

        if ($user->id !== 1) {
            $query->where('owner_id', $user->id);
        }

        $servers = QueryBuilder::for($query)
            ->allowedFilters([
                AllowedFilter::exact('owner_id'),
                AllowedFilter::custom('*', new AdminServerFilter()),
            ])
            ->when($request->has('filter') && isset($request->filter['search']), function ($q) use ($request) {
                $search = $request->filter['search'];
                $q->where(function ($sub) use ($search) {
                    $sub->where('name', 'like', "%{$search}%")
                        ->orWhere('uuidShort', 'like', "%{$search}%")
                        ->orWhere('uuid', 'like', "%{$search}%");
                });
            })
            ->paginate(config('pterodactyl.paginate.admin.servers'))
            ->appends($request->query());

        return $this->view->make('admin.servers.index', ['servers' => $servers]);
    }

    public function create(): View
    {
        $user = Auth::user();

        if ($user->id === 1) {
            $users = User::all();
            $lock_owner = false;
            $auto_owner = null;
        } else {
            $users = collect([$user]);
            $lock_owner = true;
            $auto_owner = $user;
        }

        return $this->view->make('admin.servers.new', [
            'users' => $users,
            'lock_owner' => $lock_owner,
            'auto_owner' => $auto_owner,
            'locations' => Location::with('nodes')->get(),
            'nests' => Nest::with('eggs')->get(),
        ]);
    }

    public function view(Server $server): View
    {
        $user = Auth::user();

        if ($user->id !== 1 && $server->owner_id !== $user->id) {
            abort(403, 'Akses ditolak: Hanya admin ID 1 yang dapat melihat atau mengedit server ini! ©Protect By @WiL Official.');
        }

        return $this->view->make('admin.servers.view', ['server' => $server]);
    }

    public function update(Request $request, Server $server)
    {
        $user = Auth::user();

        if ($user->id !== 1 && $server->owner_id !== $user->id) {
            abort(403, 'Akses ditolak: Hanya admin ID 1 yang dapat mengubah server ini! ©Protect By @WiL Official.');
        }

        $data = $request->except(['owner_id']);

        $server->update($data);

        return redirect()->route('admin.servers.view', $server->id)
            ->with('success', 'Server berhasil diperbarui.');
    }

    public function destroy(Server $server)
    {
        $user = Auth::user();

        if ($user->id !== 1) {
            abort(403, 'Akses ditolak: Hanya admin ID 1 yang dapat menghapus server ini! ©Protect By @WiL Official.');
        }

        $server->delete();

        return redirect()->route('admin.servers')
            ->with('success', 'Server berhasil dihapus.');
    }
}
