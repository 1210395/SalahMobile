<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// عمارتي — multi-building: building_id is now the authoritative FK, so the
// denormalized building_key label becomes optional (some rows — e.g. generated
// alerts — carry only building_id).
return new class extends Migration
{
    private array $tables = [
        'units', 'payments', 'expenses', 'workers', 'parking_spots', 'guards',
        'alerts', 'year_summaries', 'subscriptions', 'join_requests', 'notes',
    ];

    public function up(): void
    {
        foreach ($this->tables as $t) {
            if (Schema::hasTable($t) && Schema::hasColumn($t, 'building_key')) {
                Schema::table($t, function (Blueprint $table) {
                    $table->string('building_key')->nullable()->change();
                });
            }
        }
    }

    public function down(): void
    {
        // Left nullable — reverting could fail on rows that only have building_id.
    }
};
