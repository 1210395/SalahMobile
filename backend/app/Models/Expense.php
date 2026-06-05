<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;
class Expense extends Model
{
    protected $guarded = [];
    protected $casts = ['date' => 'date:Y-m-d'];
}
