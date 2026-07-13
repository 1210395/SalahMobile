<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// A renter who moves out (unit vacated) or is replaced by a new tenant must lose
// their login — otherwise a moved-out tenant keeps a working account into the
// building. Nulling the password alone isn't enough (the OTP path would still let
// them in), so an explicit "disabled" flag gates every auth entry point. Setting a
// new password re-enables the account.
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->timestamp('disabled_at')->nullable()->after('login_code');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('disabled_at');
        });
    }
};
