<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// عمارتي — super-admin role + multi-currency payments.
return new class extends Migration
{
    public function up(): void
    {
        // Allow a 4th role: superadmin (the platform owner).
        Schema::table('users', function (Blueprint $table) {
            $table->string('role')->default('resident')->change();
        });

        // A payment may be entered in a currency other than the building's base;
        // `amount` always stores the BASE-currency value, while these record what
        // was actually entered + the rate used to convert.
        Schema::table('payments', function (Blueprint $table) {
            $table->string('currency', 8)->default('USD')->after('amount');
            $table->integer('original_amount')->nullable()->after('currency');
            $table->decimal('exchange_rate', 14, 4)->default(1)->after('original_amount');
        });
    }

    public function down(): void
    {
        Schema::table('payments', function (Blueprint $table) {
            $table->dropColumn(['currency', 'original_amount', 'exchange_rate']);
        });
        Schema::table('users', function (Blueprint $table) {
            $table->enum('role', ['admin', 'resident', 'guest'])->default('resident')->change();
        });
    }
};
