<?php

namespace App\Models;

use App\Models\Concerns\BelongsToBuilding;
use Database\Factories\UserFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Attributes\Hidden;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

#[Fillable(['name', 'email', 'phone', 'whatsapp', 'login_code', 'disabled_at', 'password', 'role', 'building_id', 'building_key', 'unit_no', 'email_verified_at'])]
#[Hidden(['password', 'remember_token'])]
class User extends Authenticatable
{
    /** @use HasFactory<UserFactory> */
    use BelongsToBuilding, HasApiTokens, HasFactory, Notifiable;

    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'disabled_at' => 'datetime',
            'password' => 'hashed',
        ];
    }

    /// A disabled account cannot authenticate by any path (password, OTP, or QR).
    public function isDisabled(): bool
    {
        return $this->disabled_at !== null;
    }

    /// Cut off a renter's access after they move out or are replaced: revoke live
    /// tokens, clear the password + QR code so neither can sign in, and flag the
    /// account disabled so the OTP path refuses it too. Setting a new password
    /// (setUnitPassword) re-enables it.
    public function disableLogin(): void
    {
        $this->tokens()->delete();
        $this->forceFill([
            'password' => null,
            'login_code' => null,
            'disabled_at' => now(),
        ])->save();
    }
}
