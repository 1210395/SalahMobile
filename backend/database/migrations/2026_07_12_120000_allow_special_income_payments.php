<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// P4c — "ايراد خاص" (#38/#39): building income that is NOT tied to a renter
// (e.g. "دفعة برج جوال"). Such a payment has no unit, so unit_no becomes nullable.
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('payments', function (Blueprint $table) {
            $table->string('unit_no', 20)->nullable()->change();
        });
    }

    public function down(): void
    {
        Schema::table('payments', function (Blueprint $table) {
            $table->string('unit_no', 20)->nullable(false)->change();
        });
    }
};
