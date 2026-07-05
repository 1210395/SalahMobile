<?php
namespace App\Models;
use App\Models\Concerns\BelongsToBuilding;
use Illuminate\Database\Eloquent\Model;
class ParkingSpot extends Model
{
    use BelongsToBuilding;

    protected $table = 'parking_spots';
    protected $guarded = [];
}
