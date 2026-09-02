<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// سكن برو — every attempt to take money, recorded before it is attempted.
//
// The subscriptions table keeps only the current state ("active"). That is not
// enough once real cards are involved: a payment that was declined, or taken
// twice, or taken and then reversed, has to be answerable afterwards from our
// own records rather than from the bank's. So each checkout gets a row the
// moment it starts, and the gateway's own identifiers are written back onto it.
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('subscription_payments', function (Blueprint $t) {
            $t->id();
            $t->foreignId('building_id')->nullable()->constrained('buildings')->nullOnDelete();
            $t->foreignId('user_id')->nullable()->constrained('users')->nullOnDelete();

            // Our own order id, sent to the gateway as the merchant reference so
            // a transaction can be traced from either side.
            $t->string('reference', 64)->unique();

            // The one-time secret in the checkout URL. It is a bearer credential
            // for one payment, so it is hashed exactly like a password would be.
            $t->string('token_hash', 64)->unique();

            // Minor units (agora/cents). Money is never a float.
            $t->unsignedBigInteger('amount');
            $t->string('currency', 3);

            // pending -> charging (claimed, bank called) -> paid | failed
            $t->string('status', 20)->default('pending');
            $t->string('gateway_id')->nullable();
            $t->string('gateway_status')->nullable();
            $t->string('failure_reason')->nullable();

            $t->timestamp('expires_at')->nullable();
            $t->timestamp('paid_at')->nullable();
            $t->timestamps();

            $t->index(['building_id', 'status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('subscription_payments');
    }
};
