<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

// P4a — the derived ledger. A unit's balance is no longer a free-floating stored
// number nudged by each payment; it is computed = opening_balance − charges +
// payments, where charges = monthly fee × months since `billing_start`. This
// migration adds the two inputs and backfills them as a NO-OP so existing
// balances are preserved (opening = current balance − payments; billing_start
// null = no accrual for existing rows).
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('units', function (Blueprint $table) {
            // The one-time opening entry (previous dues at creation; − = owes).
            $table->integer('opening_balance')->default(0)->after('balance');
            // The month monthly charges begin accruing (null = no accrual).
            $table->date('billing_start')->nullable()->after('opening_balance');
        });

        // No-op backfill: opening = current balance − Σ payments, billing_start
        // null. So derived balance = (balance − Σpay) − 0 + Σpay = balance.
        foreach (DB::table('units')->get() as $u) {
            $paid = (int) DB::table('payments')
                ->where('building_id', $u->building_id)
                ->where('unit_no', $u->no)
                ->sum('amount');
            DB::table('units')->where('id', $u->id)->update([
                'opening_balance' => (int) $u->balance - $paid,
            ]);
        }
    }

    public function down(): void
    {
        Schema::table('units', function (Blueprint $table) {
            $table->dropColumn(['opening_balance', 'billing_start']);
        });
    }
};
