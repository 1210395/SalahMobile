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

    /// Whole months from billing_start through the current month, inclusive.
    /// 0 for a vacant unit, no billing_start, or a future start.
    public function monthsBilled(): int
    {
        if ($this->status === 'vacant' || ! $this->billing_start) {
            return 0;
        }
        $start = Carbon::parse($this->billing_start)->startOfMonth();
        $now = now()->startOfMonth();
        if ($start->greaterThan($now)) {
            return 0;
        }
        return ($now->year - $start->year) * 12 + ($now->month - $start->month) + 1;
    }

    /// Total charges accrued to date (monthly fee × months billed).
    public function charges(): int
    {
        return $this->status === 'vacant' ? 0 : (int) $this->sub * $this->monthsBilled();
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
