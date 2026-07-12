<?php
namespace App\Models;
use App\Models\Concerns\BelongsToBuilding;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Carbon;
class Unit extends Model
{
    use BelongsToBuilding;

    protected $guarded = [];
    protected $casts = [
        'contract_start' => 'date:Y-m-d',
        'contract_end' => 'date:Y-m-d',
        'billing_start' => 'date:Y-m-d',
    ];

    // ───────────────────── Derived ledger (P4a) ─────────────────────
    // balance = opening_balance − charges + payments   (− = owes).
    // charges = monthly fee × months from billing_start through the current
    // month, inclusive (dues accrue at the START of each month, #21/#25).

    /// Whole months from billing_start through the month of $upTo, inclusive,
    /// never past the current month (the future is not billed yet).
    /// 0 for a vacant unit, no billing_start, or a start after $upTo.
    public function monthsBilledThrough(Carbon $upTo): int
    {
        if ($this->status === 'vacant' || ! $this->billing_start) {
            return 0;
        }
        $start = Carbon::parse($this->billing_start)->startOfMonth();
        $end = $upTo->copy()->startOfMonth();
        $now = now()->startOfMonth();
        if ($end->greaterThan($now)) {
            $end = $now;
        }
        if ($start->greaterThan($end)) {
            return 0;
        }
        return ($end->year - $start->year) * 12 + ($end->month - $start->month) + 1;
    }

    /// Whole months from billing_start through the current month, inclusive.
    public function monthsBilled(): int
    {
        return $this->monthsBilledThrough(now());
    }

    /// Charges accrued from billing_start through the month of $upTo.
    /// Used to split dues into "this year" vs "carried over" (#9/#10).
    public function chargesThrough(Carbon $upTo): int
    {
        return $this->status === 'vacant' ? 0 : (int) $this->sub * $this->monthsBilledThrough($upTo);
    }

    /// Total charges accrued to date (monthly fee × months billed).
    public function charges(): int
    {
        return $this->chargesThrough(now());
    }

    /// The derived balance given the unit's total payments (base currency).
    /// Vacant units are excluded from dues (always 0).
    public function derivedBalance(int $paymentsSum): int
    {
        if ($this->status === 'vacant') {
            return 0;
        }
        return (int) $this->opening_balance - $this->charges() + $paymentsSum;
    }

    /// Status implied by a balance: owes → late, credit → credit, settled → ok.
    public static function statusForBalance(int $balance): string
    {
        return $balance < 0 ? 'late' : ($balance > 0 ? 'credit' : 'ok');
    }
}
