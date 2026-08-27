<?php
namespace App\Models;
use App\Models\Concerns\BelongsToBuilding;
use Illuminate\Database\Eloquent\Model;

// عمارتي — a building's own directory of trusted tradespeople.
class Craftsman extends Model
{
    use BelongsToBuilding;

    protected $guarded = [];
}
