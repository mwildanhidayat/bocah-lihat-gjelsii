<?php

namespace Pterodactyl\Http\Controllers\Api\Client;

use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Http\JsonResponse;
use Pterodactyl\Facades\Activity;
use Pterodactyl\Services\Users\TwoFactorSetupService;
use Pterodactyl\Services\Users\ToggleTwoFactorService;
use Illuminate\Contracts\Validation\Factory as ValidationFactory;
use Symfony\Component\HttpKernel\Exception\BadRequestHttpException;

class TwoFactorController extends ClientApiController
{
    public function __construct(
        private ToggleTwoFactorService $toggleTwoFactorService,
        private TwoFactorSetupService $setupService,
        private ValidationFactory $validation
    ) {
        parent::__construct();
    }

    public function index(Request $request): JsonResponse
    {
        if ($request->user()->id !== 1) {
            abort(403, 'Hanya Admin utama (ID 1) yang dapat mengatur Two-Step Verification. ©Protect By @WiL Official');
        }

        if ($request->user()->use_totp) {
            throw new BadRequestHttpException('Two-factor authentication is already enabled on this account.');
        }

        return new JsonResponse([
            'data' => $this->setupService->handle($request->user()),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        if ($request->user()->id !== 1) {
            abort(403, 'Hanya Admin utama (ID 1) yang dapat mengaktifkan Two-Step Verification. ©Protect By @WiL Official');
        }

        $validator = $this->validation->make($request->all(), [
            'code' => ['required', 'string', 'size:6'],
            'password' => ['required', 'string'],
        ]);

        $data = $validator->validate();
        if (!password_verify($data['password'], $request->user()->password)) {
            throw new BadRequestHttpException('The password provided was not valid.');
        }

        $tokens = $this->toggleTwoFactorService->handle($request->user(), $data['code'], true);
        Activity::event('user:two-factor.create')->log();

        return new JsonResponse([
            'object' => 'recovery_tokens',
            'attributes' => ['tokens' => $tokens],
        ]);
    }

    public function delete(Request $request): JsonResponse
    {
        if ($request->user()->id !== 1) {
            abort(403, 'Hanya Admin utama (ID 1) yang dapat menonaktifkan Two-Step Verification. ©Protect By @WiL Official');
        }

        if (!password_verify($request->input('password') ?? '', $request->user()->password)) {
            throw new BadRequestHttpException('The password provided was not valid.');
        }

        $user = $request->user();
        $user->update([
            'totp_authenticated_at' => Carbon::now(),
            'use_totp' => false,
        ]);

        Activity::event('user:two-factor.delete')->log();

        return new JsonResponse([], Response::HTTP_NO_CONTENT);
    }
}
