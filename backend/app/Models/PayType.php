<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

// عمارتي — the fee catalogue of ONE building (the payment sheet's line items).
// It used to be a single global table, so an admin editing "الاشتراك الشهري"
// silently rewrote the fees of every other building on the platform.
class PayType extends Model
{
    protected $guarded = [];

    protected $casts = ['enabled' => 'boolean', 'optional' => 'boolean'];

    /// The fee items every building starts with. The payment sheet is built from
    /// these, so a building without them cannot record a payment.
    public const DEFAULTS = [
        ['key' => 'sub', 'label' => 'الاشتراك الشهري', 'amount' => 40, 'enabled' => true, 'optional' => false],
        ['key' => 'elev', 'label' => 'رسوم المصعد', 'amount' => 0, 'enabled' => true, 'optional' => false],
        ['key' => 'guard', 'label' => 'أجرة الحارس', 'amount' => 0, 'enabled' => true, 'optional' => true],
        ['key' => 'park', 'label' => 'أجرة الباركينج', 'amount' => 0, 'enabled' => false, 'optional' => true],
    ];

    /// Give a building its own catalogue. Idempotent — safe to re-run.
    public static function seedDefaults(int $buildingId): void
    {
        foreach (self::DEFAULTS as $sort => $p) {
            self::firstOrCreate(
                ['building_id' => $buildingId, 'key' => $p['key']],
                $p + ['sort' => $sort],
            );
        }
    }

    public function building()
    {
        return $this->belongsTo(Building::class);
    }
}
