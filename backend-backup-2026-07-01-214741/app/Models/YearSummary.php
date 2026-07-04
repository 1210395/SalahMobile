<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;
class YearSummary extends Model
{
    protected $guarded = [];
    protected $casts = ['months' => 'array'];
}
