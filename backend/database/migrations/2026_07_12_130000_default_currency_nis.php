<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// #6 — the app's market is Palestine: a new building (and any money row that
// doesn't name a currency) defaults to NIS, not USD. Existing rows keep whatever
// currency they were created with; only the column DEFAULT moves.
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('buildings', function (Blueprint $table) {
            $table->string('currency')->default('NIS')->change();
        });
        Schema::table('payments', function (Blueprint $table) {
            $table->string('currency', 8)->default('NIS')->change();
        });
        Schema::table('expenses', function (Blueprint $table) {
            $table->string('currency', 8)->nullable()->default('NIS')->change();
        });
    }

    public function down(): void
    {
        Schema::table('buildings', function (Blueprint $table) {
            $table->string('currency')->default('USD')->change();
        });
        Schema::table('payments', function (Blueprint $table) {
            $table->string('currency', 8)->default('USD')->change();
        });
        Schema::table('expenses', function (Blueprint $table) {
            $table->string('currency', 8)->nullable()->change();
        });
    }
};
