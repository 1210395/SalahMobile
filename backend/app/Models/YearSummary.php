<?php
namespace App\Models;
use App\Models\Concerns\BelongsToBuilding;
use Illuminate\Database\Eloquent\Model;
class YearSummary extends Model
{
    use BelongsToBuilding;

    protected $guarded = [];
    protected $casts = ['months' => 'array'];
}
