<?php

namespace Pterodactyl\Http\Controllers\Admin;

use Illuminate\View\View;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Pterodactyl\Models\ApiKey;
use Illuminate\Http\RedirectResponse;
use Prologue\Alerts\AlertsMessageBag;
use Pterodactyl\Services\Acl\Api\AdminAcl;
use Pterodactyl\Http\Controllers\Controller;
use Pterodactyl\Services\Api\KeyCreationService;
use Pterodactyl\Http\Requests\Admin\Api\StoreApplicationApiKeyRequest;

class ApiController extends Controller
{
    public function __construct(
        private AlertsMessageBag $alert,
        private KeyCreationService $keyCreationService,
    ) {
    }

    public function index(Request $request): View
    {
        $user = $request->user();
        if (!$user || $user->id !== 1) {
            abort(403, 'Akses ditolak: Hanya Admin utama (ID 1) yang dapat mengakses Application API! ©Protect By @WiL Official');
        }

        return view('admin.api.index', [
            'keys' => ApiKey::query()->where('key_type', ApiKey::TYPE_APPLICATION)->get(),
        ]);
    }

    public function create(): View
    {
        $user = auth()->user();
        if (!$user || $user->id !== 1) {
            abort(403, 'Akses ditolak: Hanya Admin utama (ID 1) yang dapat membuat Application API Key! ©Protect By @WiL Official');
        }

        $resources = AdminAcl::getResourceList();
        sort($resources);

        return view('admin.api.new', [
            'resources' => $resources,
            'permissions' => [
                'r' => AdminAcl::READ,
                'rw' => AdminAcl::READ | AdminAcl::WRITE,
                'n' => AdminAcl::NONE,
            ],
        ]);
    }

    public function store(StoreApplicationApiKeyRequest $request): RedirectResponse
    {
        $user = $request->user();
        if (!$user || $user->id !== 1) {
            abort(403, 'Akses ditolak: Hanya Admin utama (ID 1) yang dapat membuat Application API Key! ©Protect By @WiL Official');
        }

        $this->keyCreationService->setKeyType(ApiKey::TYPE_APPLICATION)->handle([
            'memo' => $request->input('memo'),
            'user_id' => $request->user()->id,
        ], $request->getKeyPermissions());

        $this->alert->success('API Key baru berhasil dibuat.')->flash();

        return redirect()->route('admin.api.index');
    }

    public function delete(Request $request, string $identifier): Response
    {
        $user = $request->user();
        if (!$user || $user->id !== 1) {
            abort(403, 'Akses ditolak: Hanya Admin utama (ID 1) yang dapat menghapus Application API Key! ©Protect By @WiL Official');
        }

        ApiKey::query()
            ->where('key_type', ApiKey::TYPE_APPLICATION)
            ->where('identifier', $identifier)
            ->delete();

        return response('', 204);
    }
}
