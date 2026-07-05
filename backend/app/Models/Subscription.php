<?php
namespace App\Models;
use App\Models\Concerns\BelongsToBuilding;
use Illuminate\Database\Eloquent\Model;
class Subscription extends Model
{
    use BelongsToBuilding;

    protected $guarded = [];
    protected $casts = ['activated_at' => 'datetime', 'expires_at' => 'datetime'];
}
