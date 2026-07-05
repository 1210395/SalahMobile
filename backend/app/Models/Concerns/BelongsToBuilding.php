<?php

namespace App\Models\Concerns;

use App\Models\Building;

// عمارتي — a building-scoped model. Keeps building_id (the FK) in sync with the
// denormalized building_key string automatically, so every create/seed/test that
// sets building_key gets a correct building_id without extra code. building_id is
// the authoritative scope key; building_key remains a readable label.
trait BelongsToBuilding
{
    public static function bootBelongsToBuilding(): void
    {
        static::creating(function ($model) {
            if (empty($model->building_id) && ! empty($model->building_key)) {
                $model->building_id = Building::idForKey($model->building_key);
            }
        });
    }

    public function building()
    {
        return $this->belongsTo(Building::class);
    }
}
