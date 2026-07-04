<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;
class Unit extends Model
{
    protected $guarded = [];
    protected $casts = ['contract_start' => 'date:Y-m-d', 'contract_end' => 'date:Y-m-d'];
}
