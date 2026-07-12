<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// P4b — cheque details (when the method is شيك) + `applies_to_dues`, so an
// "أخرى" line is recorded as income but does NOT settle the resident's dues (#28).
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('payments', function (Blueprint $table) {
            $table->date('cheque_date')->nullable()->after('method');
            $table->string('cheque_number', 60)->nullable()->after('cheque_date');
            // true = settles monthly/dues charges; false = other income (أخرى).
            $table->boolean('applies_to_dues')->default(true)->after('cheque_number');
        });
    }

    public function down(): void
    {
        Schema::table('payments', function (Blueprint $table) {
            $table->dropColumn(['cheque_date', 'cheque_number', 'applies_to_dues']);
        });
    }
};
