<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        // Add column if it doesn't exist
        if (!Schema::hasColumn('users', 'building_id')) {
            Schema::table('users', function (Blueprint $table) {
                $table->unsignedBigInteger('building_id')->nullable()->after('id');
                $table->foreign('building_id')->references('id')->on('buildings')->onDelete('restrict');
            });
        }

        // Backfill building_id from building_key
        DB::statement('UPDATE users SET building_id = (SELECT id FROM buildings WHERE buildings.key = users.building_key LIMIT 1) WHERE building_id IS NULL AND building_key IS NOT NULL');
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropForeign(['building_id']);
            $table->dropColumn('building_id');
        });
    }
};
