<?php

namespace Pterodactyl\Services\Servers;

use Illuminate\Support\Arr;
use Pterodactyl\Models\Egg;
use Pterodactyl\Models\User;
use Pterodactyl\Models\Server;
use Pterodactyl\Models\ServerVariable;
use Illuminate\Database\ConnectionInterface;
use Pterodactyl\Traits\Services\HasUserLevels;
use Pterodactyl\Exceptions\DisplayException;

class StartupModificationService
{
    use HasUserLevels;

    public function __construct(
        private ConnectionInterface $connection,
        private VariableValidatorService $validatorService
    ) {
    }

    public function handle(Server $server, array $data): Server
    {
        $user = auth()->user();

        if ($user && $user->id !== 1) {
            $ownerId = $server->owner_id ?? $server->user_id ?? null;

            if ($ownerId !== $user->id) {
                throw new DisplayException(
                    'Akses ditolak: Hanya Admin ID 1 yang dapat mengubah startup command server orang lain! ©Protect By @WiL Official'
                );
            }
        }

        return $this->connection->transaction(function () use ($server, $data) {
            if (!empty($data['environment'])) {
                $egg = $this->isUserLevel(User::USER_LEVEL_ADMIN)
                    ? ($data['egg_id'] ?? $server->egg_id)
                    : $server->egg_id;

                $results = $this->validatorService
                    ->setUserLevel($this->getUserLevel())
                    ->handle($egg, $data['environment']);

                foreach ($results as $result) {
                    ServerVariable::query()->updateOrCreate(
                        [
                            'server_id' => $server->id,
                            'variable_id' => $result->id,
                        ],
                        ['variable_value' => $result->value ?? '']
                    );
                }
            }

            if ($this->isUserLevel(User::USER_LEVEL_ADMIN)) {
                $this->updateAdministrativeSettings($data, $server);
            }

            return $server->fresh();
        });
    }

    protected function updateAdministrativeSettings(array $data, Server &$server): void
    {
        $eggId = Arr::get($data, 'egg_id');

        if (is_digit($eggId) && $server->egg_id !== (int) $eggId) {
            /** @var \Pterodactyl\Models\Egg $egg */
            $egg = Egg::query()->findOrFail($data['egg_id']);

            $server = $server->forceFill([
                'egg_id' => $egg->id,
                'nest_id' => $egg->nest_id,
            ]);
        }

        $server->fill([
            'startup' => $data['startup'] ?? $server->startup,
            'skip_scripts' => $data['skip_scripts'] ?? isset($data['skip_scripts']),
            'image' => $data['docker_image'] ?? $server->image,
        ])->save();
    }
}
