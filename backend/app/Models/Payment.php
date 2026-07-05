<?php
namespace App\Models;
use App\Models\Concerns\BelongsToBuilding;
use Illuminate\Database\Eloquent\Model;
class Payment extends Model
{
    use BelongsToBuilding;

    protected $guarded = [];
    protected $casts = ['date' => 'date:Y-m-d', 'exchange_rate' => 'float'];
}
