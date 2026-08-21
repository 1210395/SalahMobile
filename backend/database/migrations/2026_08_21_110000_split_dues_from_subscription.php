<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

// عمارتي — a payment now settles ONE named pot, never "the balance".
//
//   bucket = 'sub'   → اشتراكات شهرية (monthly dues accrued from billing_start)
//   bucket = 'dues'  → ذمم سابقة      (the debt entered when the unit was added)
//   bucket = 'none'  → إيراد فقط       (أخرى / ايراد خاص — settles nothing)
//
// The two pots are reported side by side and are NEVER added together: a
// resident who is ahead on this year's subscription while still owing old ذمم
// used to read as "credit", hiding the debt.
return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasColumn('payments', 'bucket')) {
            Schema::table('payments', function (Blueprint $t) {
                $t->string('bucket', 8)->default('sub')->after('kind')->index();
            });
        }

        // Backfill from what the rows already say: an "ذمم" line paid off old
        // debt, an income-only line settled nothing, everything else was a
        // monthly subscription payment.
        DB::table('payments')->where('kind', 'ذمم')->update(['bucket' => 'dues']);
        DB::table('payments')->where('applies_to_dues', false)->update(['bucket' => 'none']);
    }

    public function down(): void
    {
        if (Schema::hasColumn('payments', 'bucket')) {
            Schema::table('payments', function (Blueprint $t) {
                $t->dropColumn('bucket');
            });
        }
    }
};
