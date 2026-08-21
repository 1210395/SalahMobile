<?php
namespace App\Models;
use App\Models\Concerns\BelongsToBuilding;
use Illuminate\Database\Eloquent\Model;
class Payment extends Model
{
    use BelongsToBuilding;

    protected $guarded = [];
    protected $casts = ['date' => 'date:Y-m-d', 'exchange_rate' => 'float'];

    /// The pot a payment settles: اشتراكات شهرية | ذمم سابقة | إيراد فقط.
    public const BUCKETS = ['sub', 'dues', 'none'];

    /// The bucket implied by a request, tolerating older clients that only ever
    /// sent `kind` + `applies_to_dues` (a fielded APK still posts those).
    public static function bucketFor(?string $bucket, ?string $kind, ?bool $appliesToDues): string
    {
        if (in_array($bucket, self::BUCKETS, true)) {
            return $bucket;
        }
        if (trim((string) $kind) === 'ذمم') {
            return 'dues';
        }

        return $appliesToDues === false ? 'none' : 'sub';
    }

    /// Per-unit payment totals split by pot, in ONE query:
    ///   ['sub' => [unit_no => total], 'dues' => [unit_no => total]]
    /// Every ledger consumer goes through here, so the two pots can never drift
    /// apart between the dashboard, the unit list and a resident's statement.
    public static function sumsByBucket(?int $buildingId, ?int $throughYear = null): array
    {
        $rows = self::where('building_id', $buildingId)
            ->whereIn('bucket', ['sub', 'dues'])
            // Capping at payments recorded FOR $throughYear or earlier is how dues
            // split into "this year" vs "carried over".
            ->when($throughYear !== null, fn ($q) => $q->where('year', '<=', $throughYear))
            ->selectRaw('bucket, unit_no, SUM(amount) as s')
            ->groupBy('bucket', 'unit_no')
            ->get();

        $out = ['sub' => [], 'dues' => []];
        foreach ($rows as $r) {
            if ($r->unit_no !== null) {
                $out[$r->bucket][$r->unit_no] = (int) $r->s;
            }
        }

        return $out;
    }
}
