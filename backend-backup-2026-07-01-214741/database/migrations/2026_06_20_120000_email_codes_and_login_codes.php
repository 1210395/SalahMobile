<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// عمارتي — email confirmation codes + per-resident QR/login code.
return new class extends Migration
{
    public function up(): void
    {
        // WhatsApp contact + a short login code that lets a resident sign in by
        // scanning a QR (or typing the code) without a password.
        Schema::table('users', function (Blueprint $table) {
            $table->string('whatsapp')->nullable()->after('phone');
            $table->string('login_code')->nullable()->unique()->after('whatsapp');
        });

        // Mirrors otp_codes but keyed on email (verification, not login).
        Schema::create('email_codes', function (Blueprint $table) {
            $table->id();
            $table->string('email')->index();
            $table->string('code', 100);              // bcrypt hash, never the raw code
            $table->unsignedTinyInteger('attempts')->default(0);
            $table->timestamp('expires_at');
            $table->boolean('used')->default(false);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('email_codes');
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn(['whatsapp', 'login_code']);
        });
    }
};
