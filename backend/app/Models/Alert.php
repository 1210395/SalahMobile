<?php
namespace App\Models;
use App\Models\Concerns\BelongsToBuilding;
use Illuminate\Database\Eloquent\Model;
class Alert extends Model
{
    use BelongsToBuilding;

    protected $guarded = [];
}
