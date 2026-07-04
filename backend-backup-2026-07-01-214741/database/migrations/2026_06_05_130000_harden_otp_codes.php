<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// Widen the OTP code column to hold a bcrypt hash and track verify attempts.
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('otp_codes', function (Blueprint $table) {
            $table->string('code', 100)->change();
            $table->unsignedTinyInteger('attempts')->default(0)->after('code');
        });
    }

    public function down(): void
    {
        Schema::table('otp_codes', function (Blueprint $table) {
            $table->string('code', 8)->change();
            $table->dropColumn('attempts');
        });
    }
};
