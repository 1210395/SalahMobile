<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Str;

// سكن برو — one attempt to take a subscription payment.
class SubscriptionPayment extends Model
{
    protected $guarded = [];

    protected $casts = [
        'expires_at' => 'datetime',
        'paid_at' => 'datetime',
        'amount' => 'integer',
    ];

    /// Start a payment and return it together with the one-time secret for the
    /// checkout link. The secret is returned ONCE and stored only as a hash —
    /// it opens a payment page, so a leaked database must not yield working
    /// links.
    public static function start(?int $buildingId, ?int $userId, int $amount, string $currency, int $ttlMinutes): array
    {
        $token = Str::random(48);

        $payment = static::create([
            'building_id' => $buildingId,
            'user_id' => $userId,
            'reference' => 'SP-'.strtoupper(Str::random(16)),
            'token_hash' => hash('sha256', $token),
            'amount' => $amount,
            'currency' => $currency,
            'status' => 'pending',
            'expires_at' => now()->addMinutes($ttlMinutes),
        ]);

        return [$payment, $token];
    }

    /// The payment a checkout link refers to, or null. Looked up by the hash of
    /// the presented secret, so the lookup is exact and constant-work.
    public static function forToken(string $token): ?self
    {
        return static::where('token_hash', hash('sha256', $token))->first();
    }

    /// Whether this link can still be paid. An expired or already-settled
    /// payment must not be re-openable — that is how a card gets charged twice.
    public function isPayable(): bool
    {
        return $this->status === 'pending'
            && $this->expires_at !== null
            && $this->expires_at->isFuture();
    }

    /// How long a row may sit mid-charge before another attempt may claim it.
    public const STUCK_AFTER_MINUTES = 3;

    /// Whether a charge attempt may take this row.
    ///
    /// A row is left in 'charging' if the process dies between claiming it and
    /// hearing back — a fatal, a timeout, a lost connection. Refusing forever
    /// would strand the payer with a link that can never be used and money that
    /// may or may not have moved. After a short grace period another attempt may
    /// take it, which is safe ONLY because the charge carries an idempotency key:
    /// if the first attempt did reach the bank, the second returns that same
    /// result rather than charging again.
    public function isClaimable(): bool
    {
        if ($this->isPayable()) {
            return true;
        }

        return $this->status === 'charging'
            && $this->updated_at !== null
            && $this->updated_at->lt(now()->subMinutes(self::STUCK_AFTER_MINUTES));
    }

    /// The amount as the gateway wants it: a decimal string in major units.
    public function majorAmount(): string
    {
        return number_format($this->amount / 100, 2, '.', '');
    }
}
