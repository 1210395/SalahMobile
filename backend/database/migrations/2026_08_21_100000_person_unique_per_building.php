<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// سكن برو — the same PERSON may now appear in several buildings.
//
// phone/email were globally unique, so a man who rents a shop in one building
// and owns a flat in another simply could not be added twice: the second
// manager hit "رقم الموبايل مستخدم في حساب آخر" with no way forward. Identity
// is per-building now (one account per building, each with its own password),
// and login offers a building picker when a number matches more than one.
return new class extends Migration
{
    /// Whether [index] exists on [table] (idempotent re-runs / partial installs).
    /// Driver-agnostic: the suite runs on sqlite, production is MySQL.
    private function hasIndex(string $table, string $index): bool
    {
        foreach (Schema::getIndexes($table) as $i) {
            if (($i['name'] ?? '') === $index) {
                return true;
            }
        }

        return false;
    }

    public function up(): void
    {
        Schema::table('users', function (Blueprint $t) {
            if ($this->hasIndex('users', 'users_email_unique')) {
                $t->dropUnique('users_email_unique');
            }
            if ($this->hasIndex('users', 'users_phone_unique')) {
                $t->dropUnique('users_phone_unique');
            }
            // Unique WITHIN a building. NULLs repeat freely in MySQL, which is
            // what we want: many buildings' rows, and phone-less accounts.
            if (! $this->hasIndex('users', 'users_building_id_email_unique')) {
                $t->unique(['building_id', 'email']);
            }
            if (! $this->hasIndex('users', 'users_building_id_phone_unique')) {
                $t->unique(['building_id', 'phone']);
            }
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $t) {
            if ($this->hasIndex('users', 'users_building_id_email_unique')) {
                $t->dropUnique('users_building_id_email_unique');
            }
            if ($this->hasIndex('users', 'users_building_id_phone_unique')) {
                $t->dropUnique('users_building_id_phone_unique');
            }
            // Only restorable while no duplicate exists — a rollback after the
            // feature is used would fail here, which is the honest outcome.
            $t->unique('email');
            $t->unique('phone');
        });
    }
};
