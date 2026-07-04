<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;
class OtpCode extends Model
{
    protected $guarded = [];
    protected $casts = ['expires_at' => 'datetime', 'used' => 'boolean'];
}
