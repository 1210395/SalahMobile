<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

// عمارتي — the fee catalogue (pay_types) was a single GLOBAL table shared by
// every building: one admin editing "الاشتراك الشهري" rewrote every other
// building's fees, and PUT /pay-types/{id} let any admin edit any row. Scope it
// to a building.
//
// The defaults are inlined rather than read from PayType::DEFAULTS on purpose —
// a migration must keep doing what it did the day it ran, even if the model's
// defaults change later.
return new class extends Migration
{
    private const DEFAULTS = [
        ['key' => 'sub', 'label' => 'الاشتراك الشهري', 'amount' => 40, 'enabled' => 1, 'optional' => 0],
        ['key' => 'elev', 'label' => 'رسوم المصعد', 'amount' => 0, 'enabled' => 1, 'optional' => 0],
        ['key' => 'guard', 'label' => 'أجرة الحارس', 'amount' => 0, 'enabled' => 1, 'optional' => 1],
        ['key' => 'park', 'label' => 'أجرة الباركينج', 'amount' => 0, 'enabled' => 0, 'optional' => 1],
    ];

    public function up(): void
    {
        Schema::table('pay_types', function (Blueprint $t) {
            $t->unsignedBigInteger('building_id')->nullable()->after('id')->index();
        });

        $buildings = DB::table('buildings')->orderBy('id')->pluck('id');
        $first = $buildings->first();
        if (! $first) {
            return;   // fresh install — the seeder creates a catalogue per building
        }

        // The pre-existing global catalogue keeps its edits and becomes the first
        // building's — that building is the one whose fees were actually in use.
        DB::table('pay_types')->whereNull('building_id')->update(['building_id' => $first]);

        // Every other building gets its own copy, so from now on an edit in one
        // building cannot move another building's fees.
        foreach ($buildings as $bid) {
            if ($bid === $first) {
                continue;
            }
            foreach (self::DEFAULTS as $sort => $p) {
                $exists = DB::table('pay_types')
                    ->where('building_id', $bid)->where('key', $p['key'])->exists();
                if ($exists) {
                    continue;
                }
                DB::table('pay_types')->insert($p + [
                    'building_id' => $bid,
                    'sort' => $sort,
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);
            }
        }
    }

    public function down(): void
    {
        Schema::table('pay_types', function (Blueprint $t) {
            $t->dropIndex(['building_id']);
            $t->dropColumn('building_id');
        });
    }
};
