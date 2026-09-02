<?php

namespace App\Console\Commands;

use App\Models\User;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rules\Password;
use Illuminate\Support\Facades\Validator;

// سكن برو — create (or re-password) the platform owner account.
//
// The super-admin role is built and enforced, but no account held it, so
// platform branding and the all-buildings report were unreachable and a new
// customer's manager could only be created straight in the database. Seeding
// was the documented way in, and DEPLOY.md rightly tells you never to run the
// seeder on a live database — hence this: it touches exactly one row.
class CreateSuperAdmin extends Command
{
    protected $signature = 'amarati:superadmin
        {--email= : the owner account address}
        {--password= : leave empty to generate a strong one and print it}
        {--name=مدير المنصة : display name}
        {--force : allow taking over an EXISTING non-super-admin account}';

    protected $description = 'Create or update the platform super-admin';

    public function handle(): int
    {
        $email = $this->option('email') ?: env('AMARATI_SUPERADMIN_EMAIL');
        if (! $email) {
            $this->error('  Give --email (or set AMARATI_SUPERADMIN_EMAIL).');

            return self::FAILURE;
        }

        $password = $this->option('password') ?: env('AMARATI_SUPERADMIN_PASSWORD');
        $generated = false;
        if (! $password) {
            // Readable enough to type once from a screen, long enough to be worth
            // typing: 24 URL-safe characters.
            $password = rtrim(strtr(base64_encode(random_bytes(18)), '+/', 'Aa'), '=');
            $generated = true;
        }

        $check = Validator::make(
            ['email' => $email, 'password' => $password],
            ['email' => 'required|email', 'password' => ['required', Password::min(12)]],
        );
        if ($check->fails()) {
            foreach ($check->errors()->all() as $e) {
                $this->error("  $e");
            }

            return self::FAILURE;
        }

        // A super-admin belongs to the PLATFORM, not to a building.
        $user = User::where('email', $email)->whereNull('building_id')->first();
        $existed = (bool) $user;

        // Promoting somebody's existing account would hand their address the
        // whole platform AND change their password out from under them. Only ever
        // on purpose.
        if ($user && $user->role !== 'superadmin' && ! $this->option('force')) {
            $this->error("  {$user->email} already belongs to a {$user->role} account (id {$user->id}).");
            $this->line('  Use a different address, or pass --force to take that account over.');

            return self::FAILURE;
        }

        if ($user) {
            $user->forceFill([
                'role' => 'superadmin',
                'password' => Hash::make($password),
                'disabled_at' => null,
                'email_verified_at' => $user->email_verified_at ?? now(),
            ])->save();
            $user->tokens()->delete();   // a new password ends the old sessions
        } else {
            $user = User::create([
                'name' => $this->option('name'),
                'email' => $email,
                'password' => Hash::make($password),
                'role' => 'superadmin',
                'building_key' => null,
                'building_id' => null,
                'email_verified_at' => now(),
            ]);
        }

        $this->line('');
        $this->info(($existed ? '  ✓ updated ' : '  ✓ created ')."super-admin  $email  (id {$user->id})");
        if ($generated) {
            $this->line('');
            $this->warn('  password: '.$password);
            $this->line('  Store it now — it is hashed on save and cannot be shown again.');
        }
        $this->line('');

        return self::SUCCESS;
    }
}
