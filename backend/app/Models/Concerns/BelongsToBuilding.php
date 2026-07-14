<?php

namespace App\Models\Concerns;

use App\Models\Building;
use RuntimeException;

// عمارتي — a building-scoped model. building_id (the FK) is the authoritative
// scope key; building_key remains a readable label.
//
// building_key holds a TYPE ('residential' | 'commercial'), NOT a unique id —
// since multi-building, many buildings share one key. So a building_key alone
// CANNOT identify a building. This hook used to resolve it with "the first
// building of that type", which silently filed every tenant's rows into
// building #1. It now derives building_id only when the answer is unambiguous
// (exactly one building of that type — a fresh install, the seeder, most tests)
// and throws otherwise, so a missing building_id can never again be papered over
// with someone else's building. Callers that know the target must pass it.
trait BelongsToBuilding
{
    public static function bootBelongsToBuilding(): void
    {
        static::creating(function ($model) {
            if (! empty($model->building_id) || empty($model->building_key)) {
                return;
            }

            $ids = Building::where('key', $model->building_key)->orderBy('id')->pluck('id');

            if ($ids->count() > 1) {
                throw new RuntimeException(
                    'Ambiguous building_key "'.$model->building_key.'" on '.static::class.': '
                    .$ids->count().' buildings share it. Pass building_id explicitly.'
                );
            }

            $model->building_id = $ids->first();
        });
    }

    public function building()
    {
        return $this->belongsTo(Building::class);
    }
}
