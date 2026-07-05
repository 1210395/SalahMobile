<?php
namespace App\Models;
use App\Models\Concerns\BelongsToBuilding;
use Illuminate\Database\Eloquent\Model;
class Unit extends Model
{
    use BelongsToBuilding;

    protected $guarded = [];
    protected $casts = ['contract_start' => 'date:Y-m-d', 'contract_end' => 'date:Y-m-d'];
}
