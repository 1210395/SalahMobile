<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

// سكن برو — pre-production hardening of the schema itself.
//
//  * users.phone / users.email got no usable index when identity became unique
//    per building: the unique is (building_id, phone), and MySQL cannot use it
//    for the `where phone = ?` that EVERY login does.
//  * pay_types.building_id never had a foreign key, so deleting a building left
//    its fee rows behind — 28 such orphans exist on the live database.
//  * the ledger's hot lookups (a unit's payments, a unit by number) scan on
//    building_id alone.
return new class extends Migration
{
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
            // Login looks accounts up by identifier ALONE (the building is only
            // known afterwards), which the composite unique cannot serve.
            if (! $this->hasIndex('users', 'users_phone_index')) {
                $t->index('phone');
            }
            if (! $this->hasIndex('users', 'users_email_index')) {
                $t->index('email');
            }
        });

        Schema::table('payments', function (Blueprint $t) {
            if (! $this->hasIndex('payments', 'payments_building_id_unit_no_index')) {
                $t->index(['building_id', 'unit_no']);
            }
        });

        Schema::table('units', function (Blueprint $t) {
            if (! $this->hasIndex('units', 'units_building_id_no_index')) {
                $t->index(['building_id', 'no']);
            }
        });

        // Fee rows whose building is long gone. They are unreachable (every read
        // is scoped by building_id) but they are also the reason a stale
        // catalogue can never be told apart from a real one.
        DB::table('pay_types')
            ->whereNotIn('building_id', DB::table('buildings')->select('id'))
            ->delete();

        Schema::table('pay_types', function (Blueprint $t) {
            if (! $this->hasIndex('pay_types', 'pay_types_building_id_foreign')) {
                $t->foreign('building_id')->references('id')->on('buildings')->cascadeOnDelete();
            }
        });
    }

    public function down(): void
    {
        Schema::table('pay_types', function (Blueprint $t) {
            if ($this->hasIndex('pay_types', 'pay_types_building_id_foreign')) {
                $t->dropForeign(['building_id']);
            }
        });
        Schema::table('users', function (Blueprint $t) {
            $t->dropIndex('users_phone_index');
            $t->dropIndex('users_email_index');
        });
        Schema::table('payments', fn (Blueprint $t) => $t->dropIndex('payments_building_id_unit_no_index'));
        Schema::table('units', fn (Blueprint $t) => $t->dropIndex('units_building_id_no_index'));
    }
};
