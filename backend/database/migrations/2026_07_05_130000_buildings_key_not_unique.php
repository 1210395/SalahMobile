<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

// سكن برو — multi-building: a building's `key` is now its TYPE (residential /
// commercial), no longer a unique identifier. Each manager creates their own
// building (identified by id), so many buildings can share a key. Drops the
// unique index on buildings.key.
return new class extends Migration
{
    public function up(): void
    {
        // The unique index was created by ->unique() as 'buildings_key_unique'.
        // Guarded so the migration is safe if the index was already removed.
        try {
            Schema::table('buildings', function ($table) {
                $table->dropUnique('buildings_key_unique');
            });
        } catch (\Throwable $e) {
            // index already gone (fresh installs / re-runs) — ignore.
        }
        // Keep a NON-unique index for scoping lookups by type.
        try {
            Schema::table('buildings', function ($table) {
                $table->index('key', 'buildings_key_index');
            });
        } catch (\Throwable $e) {
        }

        // subscriptions.building_key was unique (one sub per residential/commercial)
        // — multi-building has one subscription per BUILDING, so drop it.
        try {
            Schema::table('subscriptions', function ($table) {
                $table->dropUnique('subscriptions_building_key_unique');
            });
        } catch (\Throwable $e) {
        }
    }

    public function down(): void
    {
        try {
            Schema::table('buildings', function ($table) {
                $table->dropIndex('buildings_key_index');
            });
        } catch (\Throwable $e) {
        }
    }
};
