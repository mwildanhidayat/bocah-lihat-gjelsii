<?php

namespace Pterodactyl\Http\Controllers\Admin;

use Illuminate\View\View;
use Illuminate\Http\Request;
use Pterodactyl\Models\User;
use Pterodactyl\Models\Model;
use Illuminate\Support\Collection;
use Illuminate\Http\RedirectResponse;
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
        $authUser = $request->user();

        $query = User::query()
            ->select('users.*')
            ->selectRaw('COUNT(DISTINCT(subusers.id)) as subuser_of_count')
            ->selectRaw('COUNT(DISTINCT(servers.id)) as servers_count')
            ->leftJoin('subusers', 'subusers.user_id', '=', 'users.id')
            ->leftJoin('servers', 'servers.owner_id', '=', 'users.id')
            ->groupBy('users.id');

        if ($authUser->id !== 1) {
            $query->where('users.id', $authUser->id);
        }

        $users = QueryBuilder::for($query)
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
        $authUser = $request->user();

        if ($authUser->id !== 1) {
            throw new DisplayException("Akses ditolak: hanya admin ID 1 yang dapat menghapus user! ©Protect By @WiL Official");
        }

        if ($authUser->id === $user->id) {
            throw new DisplayException("Tidak bisa menghapus akun Anda sendiri.");
        }

        $this->deletionService->handle($user);

        $this->alert->success("User berhasil dihapus.")->flash();
        return redirect()->route('admin.users');
    }

    public function store(NewUserFormRequest $request): RedirectResponse
    {
        $authUser = $request->user();
        $data = $request->normalize();

        if ($authUser->id !== 1 && isset($data['root_admin']) && $data['root_admin'] == true) {
            throw new DisplayException("Akses ditolak: Hanya admin ID 1 yang dapat membuat user admin! ©Protect By @WiL Official.");
        }

        if ($authUser->id !== 1) {
            $data['root_admin'] = false;
        }

        $user = $this->creationService->handle($data);

        $this->alert->success("Akun user berhasil dibuat (level: user biasa).")->flash();
        return redirect()->route('admin.users.view', $user->id);
    }

    public function update(UserFormRequest $request, User $user): RedirectResponse
    {
        $restrictedFields = ['email', 'first_name', 'last_name', 'password'];

        foreach ($restrictedFields as $field) {
            if ($request->filled($field) && $request->user()->id !== 1) {
                throw new DisplayException("Data hanya bisa diubah oleh admin ID 1. ©Protect By @WiL Official");
            }
        }

        if ($user->root_admin && $request->user()->id !== 1) {
            throw new DisplayException("Akses ditolak: Hanya admin ID 1 yang dapat menurunkan hak admin user ini! ©Protect By @WiL Official.");
        }

        if ($request->user()->id !== 1 && $request->user()->id !== $user->id) {
            throw new DisplayException("Akses ditolak: Hanya admin ID 1 yang dapat mengubah data user lain! ©Protect By @WiL Official.");
        }

        $data = $request->normalize();
        if ($request->user()->id !== 1) {
            unset($data['root_admin']);
        }

        $this->updateService
            ->setUserLevel(User::USER_LEVEL_ADMIN)
            ->handle($user, $data);

        $this->alert->success(trans('admin/user.notices.account_updated'))->flash();

        return redirect()->route('admin.users.view', $user->id);
    }

    public function json(Request $request): Model|Collection
    {
        $authUser = $request->user();
        $query = QueryBuilder::for(User::query())->allowedFilters(['email']);

        if ($authUser->id !== 1) {
            $query->where('id', $authUser->id);
        }

        $users = $query->paginate(25);

        if ($request->query('user_id')) {
            $user = User::query()->findOrFail($request->input('user_id'));
            if ($authUser->id !== 1 && $authUser->id !== $user->id) {
                throw new DisplayException("Akses ditolak: Hanya admin ID 1 yang dapat melihat data user lain! ©Protect By @WiL Official.");
            }
            $user->md5 = md5(strtolower($user->email));
            return $user;
        }

        return $users->map(function ($item) {
            $item->md5 = md5(strtolower($item->email));
            return $item;
        });
    }
}
