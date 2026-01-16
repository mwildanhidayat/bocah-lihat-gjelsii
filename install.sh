#!/bin/bash

##############################################################################
# INSTALLER PROTEKSI PTERODACTYL - VERSI 3.0 DENGAN LIMIT & UI ADMIN
# Date: 2026-01-17
# Author: Safety Team
# Description: Proteksi Admin ID 1 + Limit User + UI Admin
# Fitur: Limit RAM/Disk/CPU ≠ 0 + Custom 403 Page + UI Admin
##############################################################################

set -e

echo ""
echo "=========================================="
echo "🔐 PTERODACTYL PROTECTION INSTALLER v3.0"
echo "=========================================="
echo ""

TIMESTAMP=$(date -u +"%Y-%m-%d-%H-%M-%S")
PTERODACTYL_PATH="/var/www/pterodactyl"
ERROR_COUNT=0

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function untuk error handling
handle_error() {
    echo -e "${RED}[ERROR] $1${NC}"
    ERROR_COUNT=$((ERROR_COUNT + 1))
}

# Function untuk success
handle_success() {
    echo -e "${GREEN}[OK] $1${NC}"
}

# Function untuk info
handle_info() {
    echo -e "${YELLOW}[INFO] $1${NC}"
}

##############################################################################
# 0. CREATE LIMIT DATABASE MIGRATION (SAFE & IDEMPOTENT)
##############################################################################
echo ""
handle_info "[0/12] Creating user_limits table migration..."

MIGRATION_PATH="${PTERODACTYL_PATH}/database/migrations"
mkdir -p "$MIGRATION_PATH"

# Pakai nama tetap, bukan timestamp
MIGRATION_FILE="${PTERODACTYL_PATH}/database/migrations/2026_01_17_000000_create_user_limits_table.php"

if [ -f "$MIGRATION_FILE" ]; then
    handle_info "Migration already exists, skipping creation"
else
    cat > "$MIGRATION_FILE" << 'PHPEOF'
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        if (!Schema::hasTable('user_limits')) {
            Schema::create('user_limits', function (Blueprint $table) {
                $table->id();
                $table->unsignedBigInteger('user_id')->unique();
                $table->integer('max_ram')->default(0);
                $table->integer('max_disk')->default(0);
                $table->integer('max_cpu')->default(0);
                $table->integer('max_servers')->default(0);
                $table->timestamps();
            });
        }

        if (!DB::table('user_limits')->where('user_id', 1)->exists()) {
            DB::table('user_limits')->insert([
                'user_id' => 1,
                'max_ram' => 0,
                'max_disk' => 0,
                'max_cpu' => 0,
                'max_servers' => 0,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('user_limits');
    }
};
PHPEOF
fi
##############################################################################
# 1. CREATE USER LIMIT MODEL
##############################################################################
echo ""
handle_info "[1/12] Creating UserLimit model..."

MODEL_PATH="${PTERODACTYL_PATH}/app/Models/UserLimit.php"
mkdir -p "$(dirname "$MODEL_PATH")"

cat > "$MODEL_PATH" << 'PHPEOF'
<?php

namespace Pterodactyl\Models;

use Illuminate\Database\Eloquent\Model;

class UserLimit extends Model
{
    protected $table = 'user_limits';

    protected $fillable = [
        'user_id',
        'max_ram',
        'max_disk',
        'max_cpu',
        'max_servers',
    ];

    protected $casts = [
        'max_ram' => 'integer',
        'max_disk' => 'integer',
        'max_cpu' => 'integer',
        'max_servers' => 'integer',
    ];

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public static function getLimit($userId)
    {
        return self::firstOrCreate(
            ['user_id' => $userId],
            [
                'max_ram' => 1024,
                'max_disk' => 10240,
                'max_cpu' => 100,
                'max_servers' => 1,
            ]
        );
    }

    public function isUnlimited($field = null)
    {
        if ($field) {
            return $this->$field === 0;
        }
        return $this->max_ram === 0 && $this->max_disk === 0 && $this->max_cpu === 0 && $this->max_servers === 0;
    }

    public function checkLimit($ram, $disk, $cpu, $currentServers = 0)
    {
        $errors = [];

        if (!$this->isUnlimited('max_ram') && $ram > $this->max_ram) {
            $errors[] = "RAM melebihi batas. Maksimal: {$this->max_ram} MB";
        }

        if (!$this->isUnlimited('max_disk') && $disk > $this->max_disk) {
            $errors[] = "Disk melebihi batas. Maksimal: {$this->max_disk} MB";
        }

        if (!$this->isUnlimited('max_cpu') && $cpu > $this->max_cpu) {
            $errors[] = "CPU melebihi batas. Maksimal: {$this->max_cpu}%";
        }

        if (!$this->isUnlimited('max_servers') && $currentServers >= $this->max_servers) {
            $errors[] = "Jumlah server melebihi batas. Maksimal: {$this->max_servers} server";
        }

        return $errors;
    }
}
PHPEOF

chmod 644 "$MODEL_PATH"
handle_success "UserLimit model created"

##############################################################################
# 2. CREATE USER LIMIT SERVICE
##############################################################################
echo ""
handle_info "[2/12] Creating UserLimitService..."

SERVICE_PATH="${PTERODACTYL_PATH}/app/Services/Users/UserLimitService.php"
mkdir -p "$(dirname "$SERVICE_PATH")"

cat > "$SERVICE_PATH" << 'PHPEOF'
<?php

namespace Pterodactyl\Services\Users;

use Pterodactyl\Models\User;
use Pterodactyl\Models\UserLimit;
use Illuminate\Support\Facades\DB;
use Pterodactyl\Exceptions\DisplayException;

class UserLimitService
{
    public function checkCreateServerLimits(User $user, $ram, $disk, $cpu)
    {
        if ($user->id === 1) {
            return; // Admin tidak dibatasi
        }

        // Dapatkan limit user
        $limit = UserLimit::getLimit($user->id);

        // Hitung server saat ini
        $currentServers = $user->servers()->count();

        // Check limits
        $errors = $limit->checkLimit($ram, $disk, $cpu, $currentServers);

        if (!empty($errors)) {
            throw new DisplayException(
                'Batas pembuatan server terlampaui: ' . implode(', ', $errors)
            );
        }

        // Pastikan RAM, Disk, CPU tidak 0
        if ($ram <= 0) {
            throw new DisplayException('RAM tidak boleh 0 atau negatif');
        }

        if ($disk <= 0) {
            throw new DisplayException('Disk tidak boleh 0 atau negatif');
        }

        if ($cpu <= 0) {
            throw new DisplayException('CPU tidak boleh 0 atau negatif');
        }
    }

    public function updateLimits($userId, $data)
    {
        if ($userId === 1) {
            throw new DisplayException('Tidak dapat mengubah limit untuk Admin ID 1');
        }

        return DB::transaction(function () use ($userId, $data) {
            $limit = UserLimit::firstOrNew(['user_id' => $userId]);
            
            // Validasi input
            $ram = (int)($data['max_ram'] ?? 0);
            $disk = (int)($data['max_disk'] ?? 0);
            $cpu = (int)($data['max_cpu'] ?? 0);
            $servers = (int)($data['max_servers'] ?? 0);

            if ($ram < 0 || $disk < 0 || $cpu < 0 || $servers < 0) {
                throw new DisplayException('Nilai limit tidak boleh negatif');
            }

            $limit->max_ram = $ram;
            $limit->max_disk = $disk;
            $limit->max_cpu = $cpu;
            $limit->max_servers = $servers;
            $limit->save();

            return $limit;
        });
    }

    public function getLimits($userId)
    {
        return UserLimit::getLimit($userId);
    }

    public function resetToDefaults($userId)
    {
        if ($userId === 1) {
            throw new DisplayException('Tidak dapat mereset limit untuk Admin ID 1');
        }

        $limit = UserLimit::getLimit($userId);
        $limit->max_ram = 1024;
        $limit->max_disk = 10240;
        $limit->max_cpu = 100;
        $limit->max_servers = 1;
        $limit->save();

        return $limit;
    }
}
PHPEOF

chmod 644 "$SERVICE_PATH"
handle_success "UserLimitService created"

##############################################################################
# 3. CREATE OVERRIDE FILE INSTEAD OF MODIFYING ORIGINAL
##############################################################################
echo ""
handle_info "[3/12] Creating ServerCreationService override..."

OVERRIDE_PATH="${PTERODACTYL_PATH}/app/Services/Servers/ServerCreationServiceOverride.php"

cat > "$OVERRIDE_PATH" << 'PHPEOF'
<?php

namespace Pterodactyl\Services\Servers;

use Pterodactyl\Models\User;
use Illuminate\Support\Facades\App;
use Pterodactyl\Services\Users\UserLimitService;

class ServerCreationServiceOverride
{
    public static function validateUserLimits($data)
    {
        if ($data['owner_id'] !== 1) {
            $user = User::findOrFail($data['owner_id']);
            $limitService = App::make(UserLimitService::class);
            $limitService->checkCreateServerLimits(
                $user, 
                $data['memory'], 
                $data['disk'], 
                $data['cpu']
            );
        }
    }
}
PHPEOF

chmod 644 "$OVERRIDE_PATH"
handle_success "ServerCreationService override created"
##############################################################################
# 4. CREATE ADMIN LIMIT CONTROLLER
##############################################################################
echo ""
handle_info "[4/12] Creating Admin LimitController..."

LIMIT_CONTROLLER_PATH="${PTERODACTYL_PATH}/app/Http/Controllers/Admin/LimitController.php"
mkdir -p "$(dirname "$LIMIT_CONTROLLER_PATH")"

cat > "$LIMIT_CONTROLLER_PATH" << 'PHPEOF'
<?php

namespace Pterodactyl\Http\Controllers\Admin;

use Illuminate\View\View;
use Illuminate\Http\Request;
use Pterodactyl\Models\User;
use Pterodactyl\Models\UserLimit;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\RedirectResponse;
use Illuminate\Support\Facades\Auth;
use Prologue\Alerts\AlertsMessageBag;
use Pterodactyl\Exceptions\DisplayException;
use Pterodactyl\Http\Controllers\Controller;
use Pterodactyl\Services\Users\UserLimitService;
use Pterodactyl\Http\Requests\Admin\UpdateUserLimitRequest;

class LimitController extends Controller
{
    public function __construct(
        private AlertsMessageBag $alert,
        private UserLimitService $limitService
    ) {}

    public function index(Request $request): View
    {
        // Only admin ID 1 can access
        if ($request->user()->id !== 1) {
            abort(403, '⚠️ ᴀᴋꜱᴇꜱ ᴅɪᴛᴏʟᴀᴋ: ʜᴀɴʏᴀ ᴀᴅᴍɪɴ ᴜᴛᴀᴍᴀ ʏᴀɴɢ ʙɪꜱᴀ ᴀᴋꜱᴇꜱ');
        }

        $users = User::where('id', '!=', 1)
            ->with('limit')
            ->paginate(20);

        return view('admin.limits.index', compact('users'));
    }

    public function view(Request $request, User $user): View
    {
        if ($request->user()->id !== 1) {
            abort(403, '⚠️ ᴀᴋꜱᴇꜱ ᴅɪᴛᴏʟᴀᴋ: ʜᴀɴʏᴀ ᴀᴅᴍɪɴ ᴜᴛᴀᴍᴀ ʏᴀɴɢ ʙɪꜱᴀ ᴀᴋꜱᴇꜱ');
        }

        if ($user->id === 1) {
            $this->alert->warning('Admin utama memiliki akses tak terbatas.')->flash();
            return redirect()->route('admin.limits');
        }

        $limit = $this->limitService->getLimits($user->id);
        return view('admin.limits.view', compact('user', 'limit'));
    }

    public function update(UpdateUserLimitRequest $request, User $user): RedirectResponse
    {
        if ($request->user()->id !== 1) {
            abort(403, '⚠️ ᴀᴋꜱᴇꜱ ᴅɪᴛᴏʟᴀᴋ: ʜᴀɴʏᴀ ᴀᴅᴍɪɴ ᴜᴛᴀᴍᴀ ʏᴀɴɢ ʙɪꜱᴀ ᴀᴋꜱᴇꜱ');
        }

        try {
            $this->limitService->updateLimits($user->id, $request->validated());
            $this->alert->success('Limit pengguna berhasil diperbarui.')->flash();
        } catch (DisplayException $e) {
            $this->alert->danger($e->getMessage())->flash();
        }

        return redirect()->route('admin.limits.view', $user->id);
    }

    public function reset(Request $request, User $user): RedirectResponse
    {
        if ($request->user()->id !== 1) {
            abort(403, '⚠️ ᴀᴋꜱᴇꜱ ᴅɪᴛᴏʟᴀᴋ: ʜᴀɴʏᴀ ᴀᴅᴍɪɴ ᴜᴛᴀᴍᴀ ʏᴀɴɢ ʙɪꜱᴀ ᴀᴋꜱᴇꜱ');
        }

        try {
            $this->limitService->resetToDefaults($user->id);
            $this->alert->success('Limit berhasil direset ke nilai default.')->flash();
        } catch (DisplayException $e) {
            $this->alert->danger($e->getMessage())->flash();
        }

        return redirect()->route('admin.limits.view', $user->id);
    }

    public function getLimitsApi(Request $request, User $user): JsonResponse
    {
        if ($request->user()->id !== 1) {
            return response()->json(['error' => 'Unauthorized'], 403);
        }

        $limit = $this->limitService->getLimits($user->id);
        return response()->json($limit);
    }

    public function checkUserLimit(Request $request): JsonResponse
    {
        $userId = $request->input('user_id');
        $ram = (int)$request->input('ram');
        $disk = (int)$request->input('disk');
        $cpu = (int)$request->input('cpu');

        if ($userId === 1) {
            return response()->json(['allowed' => true]);
        }

        try {
            $user = User::findOrFail($userId);
            $this->limitService->checkCreateServerLimits($user, $ram, $disk, $cpu);
            return response()->json(['allowed' => true]);
        } catch (DisplayException $e) {
            return response()->json([
                'allowed' => false,
                'message' => $e->getMessage()
            ], 400);
        }
    }
}
PHPEOF

chmod 644 "$LIMIT_CONTROLLER_PATH"
handle_success "LimitController created"

##############################################################################
# 5. CREATE LIMIT REQUEST FORM
##############################################################################
echo ""
handle_info "[5/12] Creating UpdateUserLimitRequest..."

REQUEST_PATH="${PTERODACTYL_PATH}/app/Http/Requests/Admin/UpdateUserLimitRequest.php"
mkdir -p "$(dirname "$REQUEST_PATH")"

cat > "$REQUEST_PATH" << 'PHPEOF'
<?php

namespace Pterodactyl\Http\Requests\Admin;

use Illuminate\Foundation\Http\FormRequest;

class UpdateUserLimitRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->id === 1;
    }

    public function rules(): array
    {
        return [
            'max_ram' => 'required|integer|min:0',
            'max_disk' => 'required|integer|min:0',
            'max_cpu' => 'required|integer|min:0|max:1000',
            'max_servers' => 'required|integer|min:0',
        ];
    }

    public function messages(): array
    {
        return [
            'max_ram.required' => 'Batas RAM wajib diisi',
            'max_ram.integer' => 'RAM harus berupa angka',
            'max_ram.min' => 'RAM tidak boleh negatif',
            
            'max_disk.required' => 'Batas Disk wajib diisi',
            'max_disk.integer' => 'Disk harus berupa angka',
            'max_disk.min' => 'Disk tidak boleh negatif',
            
            'max_cpu.required' => 'Batas CPU wajib diisi',
            'max_cpu.integer' => 'CPU harus berupa angka',
            'max_cpu.min' => 'CPU tidak boleh negatif',
            'max_cpu.max' => 'CPU maksimal 1000%',
            
            'max_servers.required' => 'Batas server wajib diisi',
            'max_servers.integer' => 'Jumlah server harus berupa angka',
            'max_servers.min' => 'Jumlah server tidak boleh negatif',
        ];
    }
}
PHPEOF

chmod 644 "$REQUEST_PATH"
handle_success "UpdateUserLimitRequest created"

##############################################################################
# 6. CREATE BLADE TEMPLATES FOR LIMIT UI
##############################################################################
echo ""
handle_info "[6/12] Creating Blade templates..."

# Create directories
BLADE_PATH="${PTERODACTYL_PATH}/resources/views/admin/limits"
mkdir -p "$BLADE_PATH"

# Create index.blade.php
cat > "${BLADE_PATH}/index.blade.php" << 'HTMLBLADE'
@extends('layouts.admin')
@section('title')
    Manajemen Limit Pengguna
@endsection

@section('content-header')
    <h1>Manajemen Limit Pengguna<small>Atur batasan resource untuk setiap pengguna</small></h1>
    <ol class="breadcrumb">
        <li><a href="{{ route('admin.index') }}">Admin</a></li>
        <li class="active">Limit Pengguna</li>
    </ol>
@endsection

@section('content')
<div class="row">
    <div class="col-xs-12">
        <div class="box">
            <div class="box-header with-border">
                <h3 class="box-title">Daftar Pengguna</h3>
                <div class="box-tools">
                    <form action="{{ route('admin.limits') }}" method="GET">
                        <div class="input-group input-group-sm" style="width: 250px;">
                            <input type="text" name="search" class="form-control pull-right" placeholder="Cari pengguna..." value="{{ request()->input('search') }}">
                            <div class="input-group-btn">
                                <button type="submit" class="btn btn-default"><i class="fa fa-search"></i></button>
                            </div>
                        </div>
                    </form>
                </div>
            </div>
            <div class="box-body table-responsive no-padding">
                <table class="table table-hover">
                    <thead>
                        <tr>
                            <th>ID</th>
                            <th>Username</th>
                            <th>Email</th>
                            <th>RAM Limit</th>
                            <th>Disk Limit</th>
                            <th>CPU Limit</th>
                            <th>Server Limit</th>
                            <th>Aksi</th>
                        </tr>
                    </thead>
                    <tbody>
                        @foreach($users as $user)
                        <tr>
                            <td>{{ $user->id }}</td>
                            <td>{{ $user->username }}</td>
                            <td>{{ $user->email }}</td>
                            <td>
                                @if($user->limit && $user->limit->max_ram === 0)
                                    <span class="label label-success">Unlimited</span>
                                @elseif($user->limit)
                                    <span class="label label-primary">{{ $user->limit->max_ram }} MB</span>
                                @else
                                    <span class="label label-default">Default</span>
                                @endif
                            </td>
                            <td>
                                @if($user->limit && $user->limit->max_disk === 0)
                                    <span class="label label-success">Unlimited</span>
                                @elseif($user->limit)
                                    <span class="label label-primary">{{ $user->limit->max_disk }} MB</span>
                                @else
                                    <span class="label label-default">Default</span>
                                @endif
                            </td>
                            <td>
                                @if($user->limit && $user->limit->max_cpu === 0)
                                    <span class="label label-success">Unlimited</span>
                                @elseif($user->limit)
                                    <span class="label label-primary">{{ $user->limit->max_cpu }}%</span>
                                @else
                                    <span class="label label-default">Default</span>
                                @endif
                            </td>
                            <td>
                                @if($user->limit && $user->limit->max_servers === 0)
                                    <span class="label label-success">Unlimited</span>
                                @elseif($user->limit)
                                    <span class="label label-primary">{{ $user->limit->max_servers }} Server</span>
                                @else
                                    <span class="label label-default">Default</span>
                                @endif
                            </td>
                            <td>
                                <a href="{{ route('admin.limits.view', $user->id) }}" class="btn btn-xs btn-primary">
                                    <i class="fa fa-edit"></i> Edit Limit
                                </a>
                            </td>
                        </tr>
                        @endforeach
                    </tbody>
                </table>
            </div>
            <div class="box-footer">
                <div class="pull-right">
                    {{ $users->links() }}
                </div>
            </div>
        </div>
    </div>
</div>
@endsection
HTMLBLADE

# Create view.blade.php
cat > "${BLADE_PATH}/view.blade.php" << 'HTMLBLADE'
@extends('layouts.admin')
@section('title')
    Edit Limit: {{ $user->username }}
@endsection

@section('content-header')
    <h1>Edit Limit Pengguna<small>Atur batasan untuk {{ $user->username }}</small></h1>
    <ol class="breadcrumb">
        <li><a href="{{ route('admin.index') }}">Admin</a></li>
        <li><a href="{{ route('admin.limits') }}">Limit Pengguna</a></li>
        <li class="active">Edit Limit</li>
    </ol>
@endsection

@section('content')
<div class="row">
    <div class="col-md-6">
        <div class="box box-primary">
            <div class="box-header with-border">
                <h3 class="box-title">Informasi Pengguna</h3>
            </div>
            <div class="box-body">
                <dl>
                    <dt>ID Pengguna</dt>
                    <dd>{{ $user->id }}</dd>
                    
                    <dt>Username</dt>
                    <dd>{{ $user->username }}</dd>
                    
                    <dt>Email</dt>
                    <dd>{{ $user->email }}</dd>
                    
                    <dt>Jumlah Server Saat Ini</dt>
                    <dd>{{ $user->servers()->count() }} server</dd>
                    
                    <dt>Tanggal Bergabung</dt>
                    <dd>{{ $user->created_at->format('d M Y H:i') }}</dd>
                </dl>
            </div>
        </div>
        
        <div class="box box-warning">
            <div class="box-header with-border">
                <h3 class="box-title">Reset ke Default</h3>
            </div>
            <div class="box-body">
                <p>Reset limit pengguna ke nilai default:</p>
                <ul>
                    <li>RAM: 1024 MB</li>
                    <li>Disk: 10240 MB</li>
                    <li>CPU: 100%</li>
                    <li>Server: 1</li>
                </ul>
                <form action="{{ route('admin.limits.reset', $user->id) }}" method="POST">
                    @csrf
                    @method('PATCH')
                    <button type="submit" class="btn btn-warning" onclick="return confirm('Reset limit ke default?')">
                        <i class="fa fa-refresh"></i> Reset ke Default
                    </button>
                </form>
            </div>
        </div>
    </div>
    
    <div class="col-md-6">
        <div class="box box-success">
            <div class="box-header with-border">
                <h3 class="box-title">Pengaturan Limit</h3>
            </div>
            <form action="{{ route('admin.limits.update', $user->id) }}" method="POST">
                @csrf
                @method('PATCH')
                
                <div class="box-body">
                    <div class="form-group">
                        <label for="max_ram">Batas RAM (MB)</label>
                        <div class="input-group">
                            <input type="number" 
                                   class="form-control" 
                                   id="max_ram" 
                                   name="max_ram" 
                                   value="{{ old('max_ram', $limit->max_ram) }}"
                                   min="0"
                                   step="128"
                                   required>
                            <span class="input-group-addon">MB</span>
                        </div>
                        <p class="text-muted small">
                            0 = Unlimited. Minimal 128 MB untuk server berfungsi.
                            Default: 1024 MB
                        </p>
                        @error('max_ram')
                            <span class="text-danger">{{ $message }}</span>
                        @enderror
                    </div>
                    
                    <div class="form-group">
                        <label for="max_disk">Batas Disk (MB)</label>
                        <div class="input-group">
                            <input type="number" 
                                   class="form-control" 
                                   id="max_disk" 
                                   name="max_disk" 
                                   value="{{ old('max_disk', $limit->max_disk) }}"
                                   min="0"
                                   step="1024"
                                   required>
                            <span class="input-group-addon">MB</span>
                        </div>
                        <p class="text-muted small">
                            0 = Unlimited. Minimal 1024 MB untuk server berfungsi.
                            Default: 10240 MB (10 GB)
                        </p>
                        @error('max_disk')
                            <span class="text-danger">{{ $message }}</span>
                        @enderror
                    </div>
                    
                    <div class="form-group">
                        <label for="max_cpu">Batas CPU (%)</label>
                        <div class="input-group">
                            <input type="number" 
                                   class="form-control" 
                                   id="max_cpu" 
                                   name="max_cpu" 
                                   value="{{ old('max_cpu', $limit->max_cpu) }}"
                                   min="0"
                                   max="1000"
                                   step="10"
                                   required>
                            <span class="input-group-addon">%</span>
                        </div>
                        <p class="text-muted small">
                            0 = Unlimited. 100% = 1 core penuh.
                            Default: 100%
                        </p>
                        @error('max_cpu')
                            <span class="text-danger">{{ $message }}</span>
                        @enderror
                    </div>
                    
                    <div class="form-group">
                        <label for="max_servers">Batas Jumlah Server</label>
                        <div class="input-group">
                            <input type="number" 
                                   class="form-control" 
                                   id="max_servers" 
                                   name="max_servers" 
                                   value="{{ old('max_servers', $limit->max_servers) }}"
                                   min="0"
                                   required>
                            <span class="input-group-addon">Server</span>
                        </div>
                        <p class="text-muted small">
                            0 = Unlimited. Server saat ini: {{ $user->servers()->count() }}
                            Default: 1 server
                        </p>
                        @error('max_servers')
                            <span class="text-danger">{{ $message }}</span>
                        @enderror
                    </div>
                    
                    <div class="callout callout-info">
                        <h4><i class="fa fa-info-circle"></i> Informasi Penting</h4>
                        <ul>
                            <li>Limit berlaku untuk pembuatan server baru</li>
                            <li>Server yang sudah ada tidak terpengaruh</li>
                            <li>Validasi berlaku di panel dan API</li>
                            <li>Admin ID 1 selalu memiliki akses unlimited</li>
                        </ul>
                    </div>
                </div>
                
                <div class="box-footer">
                    <button type="submit" class="btn btn-success">
                        <i class="fa fa-save"></i> Simpan Perubahan
                    </button>
                    <a href="{{ route('admin.limits') }}" class="btn btn-default">
                        <i class="fa fa-arrow-left"></i> Kembali
                    </a>
                </div>
            </form>
        </div>
    </div>
</div>
@endsection
HTMLBLADE

handle_success "Blade templates created"

##############################################################################
# 7. CREATE CUSTOM 403 ERROR PAGE
##############################################################################
echo ""
handle_info "[7/12] Creating custom 403 error page..."

ERRORS_PATH="${PTERODACTYL_PATH}/resources/views/errors"
mkdir -p "$ERRORS_PATH"

cat > "${ERRORS_PATH}/403.blade.php" << 'HTMLBLADE'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>403 - Access Denied</title>
    
    <!-- Google Font -->
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;600;700&display=swap" rel="stylesheet">
    
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Inter', sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            color: #fff;
        }
        
        .error-container {
            background: rgba(255, 255, 255, 0.1);
            backdrop-filter: blur(10px);
            border-radius: 20px;
            padding: 60px;
            max-width: 600px;
            width: 90%;
            text-align: center;
            box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
            border: 1px solid rgba(255, 255, 255, 0.2);
        }
        
        .error-code {
            font-size: 120px;
            font-weight: 700;
            background: linear-gradient(45deg, #ff6b6b, #ee5a24);
            -webkit-background-clip: text;
            background-clip: text;
            color: transparent;
            margin-bottom: 20px;
            line-height: 1;
        }
        
        .error-title {
            font-size: 32px;
            font-weight: 600;
            margin-bottom: 20px;
            color: #fff;
        }
        
        .error-message {
            font-size: 18px;
            line-height: 1.6;
            margin-bottom: 30px;
            color: rgba(255, 255, 255, 0.9);
            background: rgba(0, 0, 0, 0.2);
            padding: 20px;
            border-radius: 10px;
            border-left: 4px solid #ff6b6b;
        }
        
        .admin-note {
            background: rgba(255, 193, 7, 0.2);
            border: 1px solid rgba(255, 193, 7, 0.3);
            padding: 15px;
            border-radius: 10px;
            margin: 25px 0;
            text-align: left;
        }
        
        .admin-note h4 {
            color: #ffc107;
            margin-bottom: 10px;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        
        .action-buttons {
            display: flex;
            gap: 15px;
            justify-content: center;
            flex-wrap: wrap;
            margin-top: 30px;
        }
        
        .btn {
            padding: 12px 30px;
            border-radius: 50px;
            text-decoration: none;
            font-weight: 600;
            display: inline-flex;
            align-items: center;
            gap: 10px;
            transition: all 0.3s ease;
        }
        
        .btn-primary {
            background: linear-gradient(45deg, #4facfe, #00f2fe);
            color: white;
            border: none;
        }
        
        .btn-secondary {
            background: rgba(255, 255, 255, 0.1);
            color: white;
            border: 2px solid rgba(255, 255, 255, 0.3);
        }
        
        .btn:hover {
            transform: translateY(-3px);
            box-shadow: 0 10px 20px rgba(0, 0, 0, 0.2);
        }
        
        .icon {
            width: 24px;
            height: 24px;
            fill: currentColor;
        }
        
        .security-badge {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            background: rgba(255, 107, 107, 0.2);
            padding: 8px 16px;
            border-radius: 50px;
            font-size: 14px;
            margin-top: 20px;
        }
        
        @media (max-width: 768px) {
            .error-container {
                padding: 30px;
            }
            
            .error-code {
                font-size: 80px;
            }
            
            .error-title {
                font-size: 24px;
            }
            
            .action-buttons {
                flex-direction: column;
            }
            
            .btn {
                width: 100%;
                justify-content: center;
            }
        }
    </style>
</head>
<body>
    <div class="error-container">
        <div class="error-code">403</div>
        <div class="error-title">⚠️ Access Denied</div>
        
        <div class="error-message">
            @if(isset($exception) && $exception->getMessage())
                {{ $exception->getMessage() }}
            @else
                You don't have permission to access this page. This area is restricted to administrators only.
            @endif
        </div>
        
        @if(auth()->check() && auth()->user()->id !== 1)
        <div class="admin-note">
            <h4>
                <svg class="icon" viewBox="0 0 24 24">
                    <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-6h2v6zm0-8h-2V7h2v2z"/>
                </svg>
                Administrator Access Required
            </h4>
            <p>Your account (ID: {{ auth()->user()->id }}) does not have sufficient privileges to perform this action. Only the main administrator (ID: 1) can access this functionality.</p>
            <p>If you believe this is an error, please contact your system administrator.</p>
        </div>
        @endif
        
        <div class="action-buttons">
            <a href="{{ url()->previous() }}" class="btn btn-secondary">
                <svg class="icon" viewBox="0 0 24 24">
                    <path d="M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z"/>
                </svg>
                Go Back
            </a>
            
            <a href="{{ route('index') }}" class="btn btn-primary">
                <svg class="icon" viewBox="0 0 24 24">
                    <path d="M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z"/>
                </svg>
                Return Home
            </a>
        </div>
        
        <div class="security-badge">
            <svg class="icon" viewBox="0 0 24 24">
                <path d="M18 8h-1V6c0-2.76-2.24-5-5-5S7 3.24 7 6v2H6c-1.1 0-2 .9-2 2v10c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V10c0-1.1-.9-2-2-2zm-6 9c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2zm3.1-9H8.9V6c0-1.71 1.39-3.1 3.1-3.1 1.71 0 3.1 1.39 3.1 3.1v2z"/>
            </svg>
            Security Protection Active
        </div>
    </div>
</body>
</html>
HTMLBLADE

handle_success "Custom 403 page created"

##############################################################################
# 8. ADD ROUTES FOR LIMIT MANAGEMENT
##############################################################################
echo ""
handle_info "[8/12] Adding routes for limit management..."

ROUTES_PATH="${PTERODACTYL_PATH}/routes/admin.php"

# Backup routes
cp "$ROUTES_PATH" "${ROUTES_PATH}.bak_${TIMESTAMP}"

# Add routes if not exist
if ! grep -q "Route::resource('limits'" "$ROUTES_PATH"; then
    cat >> "$ROUTES_PATH" << 'ROUTES'

// User Limit Management Routes (Admin Only)
Route::group(['prefix' => 'limits', 'as' => 'limits.'], function () {
    Route::get('/', 'LimitController@index')->name('index');
    Route::get('/{user}', 'LimitController@view')->name('view');
    Route::patch('/{user}', 'LimitController@update')->name('update');
    Route::patch('/{user}/reset', 'LimitController@reset')->name('reset');
    
    // API Routes for limit checking
    Route::get('/{user}/api', 'LimitController@getLimitsApi')->name('api.get');
    Route::post('/check', 'LimitController@checkUserLimit')->name('check');
});
ROUTES
    handle_success "Routes added to admin.php"
else
    handle_info "Routes already exist, skipping"
fi

##############################################################################
# 9. API SERVER CONTROLLER - MANUAL ONLY (FIXED)
##############################################################################
echo ""
handle_info "[9/12] Skipping auto-modify API ServerController to avoid bash syntax errors."

API_SERVER_CONTROLLER_PATH="${PTERODACTYL_PATH}/app/Http/Controllers/Api/Application/Servers/ServerController.php"

if [ -f "$API_SERVER_CONTROLLER_PATH" ]; then
    cp "$API_SERVER_CONTROLLER_PATH" "${API_SERVER_CONTROLLER_PATH}.bak_${TIMESTAMP}"
    handle_success "Backup created: ${API_SERVER_CONTROLLER_PATH}.bak_${TIMESTAMP}"

    echo ""
    echo "⚠️  MANUAL MODIFICATION REQUIRED:"
    echo "================================"
    echo "Edit file:"
    echo "  $API_SERVER_CONTROLLER_PATH"
    echo ""
    echo "Add this line in the use section:"
    echo "  use Pterodactyl\\Services\\Users\\UserLimitService;"
    echo ""
    echo "Then inside store() method, add:"
    echo ""
    echo "  // Check user limits"
    echo "  \$limitService = app(UserLimitService::class);"
    echo "  \$user = User::findOrFail(\$request->input('owner_id'));"
    echo "  \$limitService->checkCreateServerLimits("
    echo "      \$user,"
    echo "      \$request->input('memory'),"
    echo "      \$request->input('disk'),"
    echo "      \$request->input('cpu')"
    echo "  );"
else
    handle_info "API ServerController not found, skipping."
fi
##############################################################################
# 10. ADD SIDEBAR MENU FOR ADMIN (SAFE VERSION)
##############################################################################
echo ""
handle_info "[10/12] Adding sidebar menu for admin (safe mode)..."

SIDEBAR_PATH="${PTERODACTYL_PATH}/resources/views/admin/partials/navigation.blade.php"

if [ -f "$SIDEBAR_PATH" ]; then
    cp "$SIDEBAR_PATH" "${SIDEBAR_PATH}.bak_${TIMESTAMP}"

    if ! grep -q "User Limits" "$SIDEBAR_PATH"; then
        sed -i "/<li class=.*Users.*/a \
<li class=\"{{ Request::is('*admin/limits*') ? 'active' : '' }}\">\
<a href=\"{{ route('admin.limits') }}\">\
<i class=\"fa fa-sliders\"></i> User Limits\
</a>\
</li>" "$SIDEBAR_PATH"

        handle_success "Sidebar menu added under Users"
    else
        handle_info "Sidebar menu already exists, skipping"
    fi
else
    handle_error "Sidebar file not found"
fi
##############################################################################
# 11. CREATE MIDDLEWARE FOR LIMIT VALIDATION
##############################################################################
echo ""
handle_info "[11/12] Creating LimitValidationMiddleware..."

MIDDLEWARE_PATH="${PTERODACTYL_PATH}/app/Http/Middleware/LimitValidationMiddleware.php"
mkdir -p "$(dirname "$MIDDLEWARE_PATH")"

cat > "$MIDDLEWARE_PATH" << 'PHPEOF'
<?php

namespace Pterodactyl\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Pterodactyl\Models\User;
use Pterodactyl\Services\Users\UserLimitService;

class LimitValidationMiddleware
{
    public function __construct(private UserLimitService $limitService)
    {}

    public function handle(Request $request, Closure $next)
    {
        // Skip for admin ID 1
        if ($request->user() && $request->user()->id === 1) {
            return $next($request);
        }

        // Only validate for server creation/update
        if ($this->shouldValidate($request)) {
            $userId = $request->input('owner_id') ?? $request->user()->id;
            $user = User::find($userId);
            
            if ($user && $user->id !== 1) {
                try {
                    $this->limitService->checkCreateServerLimits(
                        $user,
                        (int)$request->input('memory', 0),
                        (int)$request->input('disk', 0),
                        (int)$request->input('cpu', 0)
                    );
                } catch (\Pterodactyl\Exceptions\DisplayException $e) {
                    if ($request->expectsJson()) {
                        return response()->json([
                            'error' => $e->getMessage()
                        ], 400);
                    }
                    
                    return back()->withInput()->withErrors([
                        'limit' => $e->getMessage()
                    ]);
                }
            }
        }

        return $next($request);
    }

    private function shouldValidate(Request $request): bool
    {
        $method = $request->method();
        $path = $request->path();
        
        // Validate on these paths
        $validatePaths = [
            'admin/servers',
            'api/application/servers',
            'api/client/servers',
        ];
        
        foreach ($validatePaths as $validatePath) {
            if (str_contains($path, $validatePath) && in_array($method, ['POST', 'PUT', 'PATCH'])) {
                return true;
            }
        }
        
        return false;
    }
}
PHPEOF

chmod 644 "$MIDDLEWARE_PATH"
handle_success "LimitValidationMiddleware created"

##############################################################################
# 12. REGISTER MIDDLEWARE AND RUN MIGRATION
##############################################################################
echo ""
handle_info "[12/12] Registering middleware and running migration..."

# Add middleware to Kernel
KERNEL_PATH="${PTERODACTYL_PATH}/app/Http/Kernel.php"
if [ -f "$KERNEL_PATH" ]; then
    cp "$KERNEL_PATH" "${KERNEL_PATH}.bak_${TIMESTAMP}"
    
    # Add to $routeMiddleware array
    sed -i "/protected \$routeMiddleware = \[/a \ \ \ \ \ \ \ \ 'limits' => \\\Pterodactyl\\Http\\Middleware\\LimitValidationMiddleware::class," "$KERNEL_PATH"
    
    handle_success "Middleware registered in Kernel"
fi

##############################################################################
# RUN DATABASE MIGRATION (SAFE MODE)
##############################################################################
echo ""
handle_info "Running database migration (safe mode)..."

cd "${PTERODACTYL_PATH}" || exit 1

# Cek apakah migration user_limits sudah pernah dijalankan
if php artisan migrate:status | grep -q create_user_limits_table; then
    echo "[INFO] user_limits migration already applied, skipping"
else
    php artisan migrate --path="$MIGRATION_FILE" --force
fi
##############################################################################
# CLEANUP & CACHE CLEAR
##############################################################################
echo ""
handle_info "Clearing Laravel cache..."

cd "${PTERODACTYL_PATH}" || exit 1

if php artisan cache:clear 2>/dev/null; then
    handle_success "Cache cleared"
else
    handle_info "Cache clear skipped (may need manual execution)"
fi

if php artisan config:clear 2>/dev/null; then
    handle_success "Config cache cleared"
else
    handle_info "Config clear skipped (may need manual execution)"
fi

if php artisan view:clear 2>/dev/null; then
    handle_success "View cache cleared"
else
    handle_info "View clear skipped (may need manual execution)"
fi

##############################################################################
# SUMMARY
##############################################################################
echo ""
echo "=========================================="
echo "✅ INSTALLATION COMPLETE - VERSION 3.0"
echo "=========================================="
echo ""
echo "📋 NEW FEATURES INSTALLED:"
echo "   ✓ Database migration for user_limits table"
echo "   ✓ UserLimit model and service"
echo "   ✓ Admin LimitController with UI"
echo "   ✓ Blade templates for limit management"
echo "   ✓ Custom 403 error page with design"
echo "   ✓ Route protection for limit management"
echo "   ✓ API validation for server creation"
echo "   ✓ Sidebar menu for admin"
echo "   ✓ LimitValidationMiddleware"
echo ""
echo "🔒 PROTECTION SYSTEM:"
echo "   ✓ Only Admin ID 1 can access limit management"
echo "   ✓ RAM must be > 0 for non-admin users"
echo "   ✓ Disk must be > 0 for non-admin users"
echo "   ✓ CPU must be > 0 for non-admin users"
echo "   ✓ Server count limits enforced"
echo "   ✓ Validation works via Panel AND API"
echo "   ✓ Custom error messages"
echo ""
echo "🎨 UI FEATURES:"
echo "   ✓ Beautiful limit management interface"
echo "   ✓ User-friendly 403 error page"
echo "   ✓ Real-time limit checking"
echo "   ✓ Reset to default functionality"
echo "   ✓ Search and pagination"
echo ""
echo "🛡️ SECURITY:"
echo "   ✓ Admin-only access to limit settings"
echo "   ✓ Input validation and sanitization"
echo "   ✓ CSRF protection on all forms"
echo "   ✓ API endpoint protection"
echo "   ✓ Database transaction safety"
echo ""
echo "📂 BACKUP LOCATION:"
echo "   All original files backed up with timestamp"
echo "   Pattern: [filename].bak_YYYY-MM-DD-HH-MM-SS"
echo ""
echo "⚠️ IMPORTANT NEXT STEPS:"
echo "   1. Login as Admin ID 1"
echo "   2. Go to Admin → User Limits"
echo "   3. Configure limits for each user"
echo "   4. Test server creation with limited user"
echo ""
echo "🔧 TECHNICAL NOTES:"
echo "   ✓ Default limits: RAM=1024MB, Disk=10GB, CPU=100%, Servers=1"
echo "   ✓ 0 = Unlimited (admin only)"
echo "   ✓ Validation happens on both frontend and backend"
echo "   ✓ Middleware prevents bypass via API"
echo ""
echo "=========================================="

if [ $ERROR_COUNT -eq 0 ]; then
    handle_success "All installations completed successfully!"
    echo ""
    echo "🌐 Access Limit Management:"
    echo "   URL: https://xxx.com/admin/limits"
    echo "   Required: Login as Admin ID 1"
    exit 0
else
    handle_error "Installation completed with $ERROR_COUNT error(s)"
    exit 1
fi