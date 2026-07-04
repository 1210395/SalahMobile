<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;
class Worker extends Model
{
    protected $guarded = [];
    protected $casts = ['last_payment' => 'date:Y-m-d', 'next_due' => 'date:Y-m-d'];
}
