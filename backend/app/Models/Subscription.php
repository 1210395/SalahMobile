<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;
class Subscription extends Model
{
    protected $guarded = [];
    protected $casts = ['activated_at' => 'datetime', 'expires_at' => 'datetime'];
}
