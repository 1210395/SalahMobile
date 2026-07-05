<?php
namespace App\Models;
use App\Models\Concerns\BelongsToBuilding;
use Illuminate\Database\Eloquent\Model;
class JoinRequest extends Model
{
    use BelongsToBuilding;

    protected $guarded = [];
}
