<?php
namespace App\Models;
use App\Models\Concerns\BelongsToBuilding;
use Illuminate\Database\Eloquent\Model;
class Note extends Model
{
    use BelongsToBuilding;

    protected $guarded = [];
}
