<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// عمارتي — onboarding, brand, resident-notes + subscription tables.
return new class extends Migration
{
    public function up(): void
    {
        // Editable brand / app settings (key → value). Public read, admin write.
        Schema::create('settings', function (Blueprint $table) {
            $table->id();
            $table->string('key')->unique();
            $table->text('value')->nullable();
            $table->timestamps();
        });

        // One subscription per building (residential | commercial).
        Schema::create('subscriptions', function (Blueprint $table) {
            $table->id();
            $table->string('building_key')->unique();
            $table->string('status')->default('inactive');   // active | inactive
            $table->string('plan')->nullable();
            $table->unsignedInteger('amount')->default(0);
            $table->string('payment_ref')->nullable();        // simulated gateway ref
            $table->timestamp('activated_at')->nullable();
            $table->timestamp('expires_at')->nullable();
            $table->timestamps();
        });

        // Resident requests to join a building/unit; admin approves.
        Schema::create('join_requests', function (Blueprint $table) {
            $table->id();
            $table->string('building_key')->index();
            $table->foreignId('user_id')->nullable()->index();
            $table->string('name');
            $table->string('phone')->nullable();
            $table->unsignedInteger('floor')->nullable();
            $table->string('unit_no')->nullable();
            $table->string('status')->default('pending');     // pending | approved | rejected
            $table->string('note')->nullable();
            $table->timestamps();
        });

        // Short notes a resident sends to the building admin.
        Schema::create('notes', function (Blueprint $table) {
            $table->id();
            $table->string('building_key')->index();
            $table->foreignId('user_id')->nullable()->index();
            $table->string('name');
            $table->string('unit_no')->nullable();              // sender's unit
            $table->string('phone')->nullable();
            $table->string('body', 280);
            $table->string('status')->default('new');          // new | read
            $table->timestamps();
        });
    }

    public function down(): void
    {
        foreach (['notes', 'join_requests', 'subscriptions', 'settings'] as $t) {
            Schema::dropIfExists($t);
        }
    }
};
