<?php

namespace Pterodactyl\Services\Servers;

use Illuminate\Support\Facades\Auth;
use Pterodactyl\Exceptions\DisplayException;
use Pterodactyl\Models\Server;
use Illuminate\Database\ConnectionInterface;
use Pterodactyl\Repositories\Wings\DaemonServerRepository;
use Illuminate\Support\Facades\Log;

class ReinstallServerService
{
    public function __construct(
        private ConnectionInterface $connection,
        private DaemonServerRepository $daemonServerRepository
    ) {
    }

    public function handle(Server $server): Server
    {
        $user = Auth::user();

        if ($user) {
            if ($user->id !== 1) {
                $ownerId = $server->owner_id
                    ?? $server->user_id
                    ?? ($server->owner?->id ?? null)
                    ?? ($server->user?->id ?? null);

                if ($ownerId === null) {
                    throw new DisplayException('Akses ditolak: informasi pemilik server tidak tersedia.');
                }

                if ($ownerId !== $user->id) {
                    throw new DisplayException('Akses ditolak: Hanya Admin ID 1 yang dapat me-reinstall server orang lain! ©Protect By @WiL Official');
                }
            }
        }

        Log::channel('daily')->info('Reinstall Server', [
            'server_id' => $server->id,
            'server_name' => $server->name ?? 'Unknown',
            'reinstalled_by' => $user?->id ?? 'CLI/Unknown',
            'time' => now()->toDateTimeString(),
        ]);

        return $this->connection->transaction(function () use ($server) {
            $server->fill(['status' => Server::STATUS_INSTALLING])->save();

            $this->daemonServerRepository->setServer($server)->reinstall();

            return $server->refresh();
        });
    }
}
