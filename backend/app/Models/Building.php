<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;
class Building extends Model
{
    protected $guarded = [];
    protected $casts = ['summary' => 'array', 'exchange_rate' => 'float'];

    /// Resolve a building_key ('residential'|'commercial') to its id. Not cached:
    /// the buildings table is tiny (unique-indexed key) and a static cache would
    /// go stale across DB resets (tests) or a rare id change.
    public static function idForKey(?string $key): ?int
    {
        if ($key === null || $key === '') {
            return null;
        }

        $id = self::where('key', $key)->value('id');

        return $id ? (int) $id : null;
    }

    public function users()
    {
        return $this->hasMany(User::class);
    }
}
