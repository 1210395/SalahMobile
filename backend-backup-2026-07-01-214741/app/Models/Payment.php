<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;
class Payment extends Model
{
    protected $guarded = [];
    protected $casts = ['date' => 'date:Y-m-d', 'exchange_rate' => 'float'];
}
