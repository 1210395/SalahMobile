<?php
namespace App\Models;
use App\Models\Concerns\BelongsToBuilding;
use Illuminate\Database\Eloquent\Model;
class Guard extends Model
{
    use BelongsToBuilding;

    protected $guarded = [];
    protected $casts = ['last_payment' => 'date:Y-m-d', 'next_due' => 'date:Y-m-d'];
}
