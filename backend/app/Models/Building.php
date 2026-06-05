<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;
class Building extends Model
{
    protected $guarded = [];
    protected $casts = ['summary' => 'array', 'exchange_rate' => 'float'];
}
