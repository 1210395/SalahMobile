<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// Additive, data-preserving migration for the overhaul columns. The columns are
// also declared in the create-tables migration (for fresh installs); the
// hasColumn guards make this safe to run on an existing production DB that ran
// the OLD create migration — so hosts can `php artisan migrate` without a
// destructive migrate:fresh. Idempotent on already-migrated fresh installs.
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('expenses', function (Blueprint $t) {
            if (! Schema::hasColumn('expenses', 'original_amount')) $t->integer('original_amount')->nullable();
            if (! Schema::hasColumn('expenses', 'currency')) $t->string('currency', 8)->nullable();
            if (! Schema::hasColumn('expenses', 'exchange_rate')) $t->decimal('exchange_rate', 12, 4)->nullable();
        });

        Schema::table('workers', function (Blueprint $t) {
            if (! Schema::hasColumn('workers', 'came')) $t->boolean('came')->default(false);
            if (! Schema::hasColumn('workers', 'last_visit')) $t->date('last_visit')->nullable();
            if (! Schema::hasColumn('workers', 'pay_status')) $t->string('pay_status')->default('none');
            if (! Schema::hasColumn('workers', 'paid_amount')) $t->integer('paid_amount')->default(0);
        });

        Schema::table('buildings', function (Blueprint $t) {
            if (! Schema::hasColumn('buildings', 'elevator_company')) $t->string('elevator_company')->nullable();
            if (! Schema::hasColumn('buildings', 'elevator_contract_start')) $t->date('elevator_contract_start')->nullable();
            if (! Schema::hasColumn('buildings', 'elevator_contract_end')) $t->date('elevator_contract_end')->nullable();
            if (! Schema::hasColumn('buildings', 'elevator_last_check')) $t->date('elevator_last_check')->nullable();
            if (! Schema::hasColumn('buildings', 'elevator_check_notify')) $t->boolean('elevator_check_notify')->default(false);
            if (! Schema::hasColumn('buildings', 'elevator_check_interval')) $t->unsignedInteger('elevator_check_interval')->default(6);
        });

        Schema::table('alerts', function (Blueprint $t) {
            if (! Schema::hasColumn('alerts', 'target')) $t->string('target')->default('all');
        });
    }

    public function down(): void
    {
        Schema::table('expenses', function (Blueprint $t) {
            $t->dropColumn(['original_amount', 'currency', 'exchange_rate']);
        });
        Schema::table('workers', function (Blueprint $t) {
            $t->dropColumn(['came', 'last_visit', 'pay_status', 'paid_amount']);
        });
        Schema::table('buildings', function (Blueprint $t) {
            $t->dropColumn([
                'elevator_company', 'elevator_contract_start', 'elevator_contract_end',
                'elevator_last_check', 'elevator_check_notify', 'elevator_check_interval',
            ]);
        });
        Schema::table('alerts', function (Blueprint $t) {
            $t->dropColumn('target');
        });
    }
};
