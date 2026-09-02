<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

// سكن برو — complete the building_id refactor: give every building-scoped table a
// proper foreign key to buildings.id (was a denormalized building_key string).
// Additive + idempotent + backfilled, so it's safe on existing production data.
return new class extends Migration
{
    /** Tables that carry a building_key and need a building_id FK. */
    private array $tables = [
        'units', 'payments', 'expenses', 'workers', 'parking_spots', 'guards',
        'alerts', 'year_summaries', 'subscriptions', 'join_requests', 'notes',
    ];

    public function up(): void
    {
        foreach ($this->tables as $t) {
            if (! Schema::hasTable($t) || Schema::hasColumn($t, 'building_id')) {
                continue;
            }
            Schema::table($t, function (Blueprint $table) {
                $table->unsignedBigInteger('building_id')->nullable()->after('id')->index();
            });
            // Backfill from the existing building_key string.
            DB::statement("UPDATE {$t} SET building_id = (SELECT id FROM buildings WHERE buildings.key = {$t}.building_key LIMIT 1) WHERE building_id IS NULL AND building_key IS NOT NULL");
            // FK for referential integrity (restrict deletes of a claimed building).
            Schema::table($t, function (Blueprint $table) {
                $table->foreign('building_id')->references('id')->on('buildings')->onDelete('restrict');
            });
        }
    }

    public function down(): void
    {
        foreach ($this->tables as $t) {
            if (! Schema::hasTable($t) || ! Schema::hasColumn($t, 'building_id')) {
                continue;
            }
            Schema::table($t, function (Blueprint $table) {
                $table->dropForeign(['building_id']);
                $table->dropColumn('building_id');
            });
        }
    }
};
