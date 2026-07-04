<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// Buildings/units can have basement floors (0, -1, -2, …). The floor columns
// were unsigned, which rejected negatives — make them signed integers.
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('buildings', function (Blueprint $t) {
            $t->integer('floors')->default(0)->change();
        });
        Schema::table('units', function (Blueprint $t) {
            $t->integer('floor')->default(0)->change();
        });
    }

    public function down(): void
    {
        Schema::table('buildings', function (Blueprint $t) {
            $t->unsignedInteger('floors')->default(0)->change();
        });
        Schema::table('units', function (Blueprint $t) {
            $t->unsignedInteger('floor')->default(0)->change();
        });
    }
};
