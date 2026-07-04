<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;
class EmailCode extends Model
{
    protected $guarded = [];
    protected $casts = ['expires_at' => 'datetime', 'used' => 'boolean'];
}
