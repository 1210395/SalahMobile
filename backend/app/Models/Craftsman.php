<?php
namespace App\Models;
use App\Models\Concerns\BelongsToBuilding;
use Illuminate\Database\Eloquent\Model;

// سكن برو — a building's own directory of trusted tradespeople.
class Craftsman extends Model
{
    use BelongsToBuilding;

    protected $guarded = [];
}
