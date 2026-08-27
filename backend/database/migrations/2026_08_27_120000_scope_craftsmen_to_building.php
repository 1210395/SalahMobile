<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// عمارتي — الصنايعية belong to a building, like everything else.
//
// The craftsmen table was the ONE table with no tenancy: any manager's entry
// appeared in every building on the platform, and nothing could remove it. A
// directory of "trusted numbers" that strangers can write to is worth less than
// no directory at all.
//
// The column is nullable so the rows that predate it (none on the live
// database) would stay visible everywhere rather than vanish from a building
// that had come to rely on them.
return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasColumn('craftsmen', 'building_id')) {
            Schema::table('craftsmen', function (Blueprint $t) {
                $t->foreignId('building_id')->nullable()->after('id')
                    ->constrained('buildings')->cascadeOnDelete();
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasColumn('craftsmen', 'building_id')) {
            Schema::table('craftsmen', function (Blueprint $t) {
                $t->dropConstrainedForeignId('building_id');
            });
        }
    }
};
