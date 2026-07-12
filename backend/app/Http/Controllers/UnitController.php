<?php

namespace App\Http\Controllers;
use App\Models\Building;

use App\Models\Payment;
use App\Models\Unit;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

// عمارتي — unit CRUD (admin only). Adding/editing/removing apartments or shops,
// including marking a unit vacant (excluded from dues/payments).
class UnitController extends Controller
{
    private function bk(Request $r): string
    {
        $u = $r->user();
        if ($u && ! in_array($u->role, ['admin', 'superadmin'])) {
            return $u->building_key === 'commercial' ? 'commercial' : 'residential';
        }

        return $r->query('btype') === 'commercial' || $r->input('btype') === 'commercial'
            ? 'commercial' : 'residential';
    }

    private function requireAdmin(Request $r): void
    {
        abort_unless(in_array(optional($r->user())->role, ['admin', 'superadmin']),
            403, 'يتطلب صلاحية المسؤول');
    }

    /// The status label implied by a balance: owes → late, credit → credit,
    /// settled → ok. Keeps the badge consistent with what's actually owed.

    /// The building this request is scoped to — the acting user's own building.
    private function buildingId(Request $r): ?int
    {
        $u = $r->user();

        return $u && $u->building_id ? (int) $u->building_id : Building::idForKey($this->bk($r));
    }

    private static function statusForBalance(int $balance): string
    {
        return $balance < 0 ? 'late' : ($balance > 0 ? 'credit' : 'ok');
    }

    private function rules(): array
    {
        return [
            'no' => 'required|string|max:20',
            'floor' => 'required|integer|min:-50|max:300',
            'resident' => 'nullable|string|max:120',
            'kind' => 'nullable|string|max:20',
            'phone' => 'nullable|string|max:32',
            'sub' => 'nullable|integer|min:0|max:100000000',
            'status' => ['nullable', Rule::in(['ok', 'late', 'credit', 'vacant'])],
            'balance' => 'nullable|integer|min:-2000000000|max:2000000000', // frontend pre-negates ذمم سابقة
            'payer' => 'nullable|string|max:60',
            'contract_start' => 'nullable|date',
            // A lease can't end before it starts (open-ended = null end is fine).
            'contract_end' => 'nullable|date|after_or_equal:contract_start',
            'notes' => 'nullable|string|max:300',
            // When true, seed the opening debt as (sub × whole months since the
            // contract start) — "احتساب الإيجار من بداية العقد".
            'back_debt' => 'nullable|boolean',
        ];
    }

    public function store(Request $r)
    {
        $this->requireAdmin($r);
        $bk = $this->bk($r);
        $data = $r->validate($this->rules());

        abort_if(
            Unit::where('building_id', $this->buildingId($r))->where('no', $data['no'])->exists(),
            422, 'رقم الوحدة مستخدم بالفعل'
        );

        $vacant = ($data['kind'] ?? null) === 'شاغر' || ($data['status'] ?? null) === 'vacant';
        $sub = (int) ($data['sub'] ?? 0);
        $contractStart = $vacant ? null : ($data['contract_start'] ?? now()->startOfYear()->toDateString());

        // Derived ledger: opening_balance = previous dues entered (ذمم سابقة, sent
        // pre-negated in `balance`). Charges accrue monthly from billing_start =
        // the contract-start month when "احتساب من بداية العقد" is on, otherwise
        // the current month. The stored `balance` is a cache = opening − charges.
        $openingBalance = $vacant ? 0 : (int) ($data['balance'] ?? 0);
        $billingStart = $vacant
            ? null
            : ((($data['back_debt'] ?? false) && $contractStart) ? $contractStart : now()->startOfMonth()->toDateString());

        $balance = 0;
        if (! $vacant) {
            $start = Carbon::parse($billingStart)->startOfMonth();
            $nowM = now()->startOfMonth();
            $months = $start->greaterThan($nowM)
                ? 0
                : ($nowM->year - $start->year) * 12 + ($nowM->month - $start->month) + 1;
            $balance = $openingBalance - $sub * $months;
            // A very old contract × a large fee can exceed the INT column — reject
            // cleanly instead of a raw overflow 500.
            abort_if(abs($balance) > 2147483647, 422,
                'الرصيد المحتسب كبير جداً — تحقّق من الدفعة الشهرية وتاريخ بداية العقد');
        }

        $unit = Unit::create([
            'building_key' => $bk,
            'building_id' => $this->buildingId($r),
            'ext_id' => strtoupper(substr($bk, 0, 1)).'-'.$data['no'],
            'no' => $data['no'],
            'floor' => $data['floor'],
            'resident' => $vacant ? 'وحدة شاغرة' : ($data['resident'] ?? ''),
            'kind' => $vacant ? 'شاغر' : ($data['kind'] ?? 'مالك'),
            'phone' => $data['phone'] ?? '—',
            'sub' => $sub,
            // Status follows the balance (a unit with back-debt is 'late', not
            // 'ok') so the badge never contradicts what's owed. Vacant is manual.
            'status' => $vacant ? 'vacant' : self::statusForBalance($balance),
            'balance' => $balance,
            'opening_balance' => $openingBalance,
            'billing_start' => $billingStart,
            'payer' => $vacant ? '—' : ($data['payer'] ?? 'الساكن'),
            'contract_start' => $contractStart,
            // Empty/absent end date = open-ended ("مستمر") — do NOT force a
            // default end, or the مستمر toggle would be silently overridden.
            'contract_end' => $vacant ? null : ($data['contract_end'] ?? null),
            'notes' => $data['notes'] ?? null,
        ]);

        return response()->json($unit, 201);
    }

    public function update(Request $r, Unit $unit)
    {
        $this->requireAdmin($r);
        abort_unless($unit->building_id === $this->buildingId($r), 403);
        $data = $r->validate($this->rules());

        $vacant = ($data['kind'] ?? $unit->kind) === 'شاغر' || ($data['status'] ?? null) === 'vacant';

        // Renaming a unit's number must cascade: payments and the resident's login
        // both reference the unit by its `no` string. Without this, a rename
        // silently orphans the payment history and the resident's account.
        $oldNo = $unit->no;
        $newNo = $data['no'];
        $renamed = $newNo !== $oldNo;
        if ($renamed) {
            abort_if(
                Unit::where('building_id', $unit->building_id)
                    ->where('no', $newNo)->where('id', '!=', $unit->id)->exists(),
                422, 'رقم الوحدة مستخدم بالفعل'
            );
        }

        DB::transaction(function () use ($unit, $vacant, $data, $renamed, $oldNo, $newNo) {
            $unit->update([
                'no' => $data['no'],
                'floor' => $data['floor'],
                'resident' => $vacant ? 'وحدة شاغرة' : ($data['resident'] ?? $unit->resident),
                'kind' => $vacant ? 'شاغر' : ($data['kind'] ?? $unit->kind),
                'phone' => $vacant ? '—' : ($data['phone'] ?? $unit->phone),
                'sub' => $data['sub'] ?? $unit->sub,
                'payer' => $vacant ? '—' : ($data['payer'] ?? $unit->payer),
                'contract_start' => $vacant ? null : ($data['contract_start'] ?? $unit->contract_start),
                // Sent null (empty "مستمر") clears the end date; only an ABSENT key
                // keeps the current value — so toggling مستمر on edit works.
                'contract_end' => $vacant
                    ? null
                    : (array_key_exists('contract_end', $data) ? $data['contract_end'] : $unit->contract_end),
                'notes' => $data['notes'] ?? $unit->notes,
                // A vacant unit stops accruing charges (excluded from dues).
                'billing_start' => $vacant ? null : $unit->billing_start,
            ]);

            // Cascade the rename so payment history and the resident's account
            // stay linked to the unit.
            if ($renamed) {
                Payment::where('building_id', $unit->building_id)
                    ->where('unit_no', $oldNo)->update(['unit_no' => $newNo]);
                User::where('building_id', $unit->building_id)
                    ->where('unit_no', $oldNo)->update(['unit_no' => $newNo]);
            }

            // Recompute the DERIVED balance + status cache — sub/vacant may have
            // changed the charges. Balance is never free-set (#19).
            $unit->refresh();
            if ($vacant) {
                $unit->update(['status' => 'vacant', 'balance' => 0]);
            } else {
                // Only dues-settling payments reduce charges (an "أخرى" line is
                // income only — #28).
                $paid = (int) Payment::where('building_id', $unit->building_id)
                    ->where('unit_no', $unit->no)->where('applies_to_dues', true)->sum('amount');
                $bal = $unit->derivedBalance($paid);
                $unit->update(['balance' => $bal, 'status' => self::statusForBalance($bal)]);
            }
        });

        return response()->json($unit->fresh());
    }

    public function destroy(Request $r, Unit $unit)
    {
        abort_unless($r->user()->role === 'admin', 403, 'يتطلب صلاحية المسؤول');
        abort_unless($unit->building_id === $this->buildingId($r), 403);

        // Deleting a unit would orphan its payment history and leave a resident
        // account pointing at a gone unit. Block it and steer the admin to mark
        // the unit vacant instead (which excludes it from dues but keeps records).
        $hasPayments = Payment::where('building_id', $unit->building_id)
            ->where('unit_no', $unit->no)->exists();
        $hasResident = User::where('building_id', $unit->building_id)
            ->where('unit_no', $unit->no)->exists();
        abort_if($hasPayments || $hasResident, 422,
            'لا يمكن حذف وحدة لها دفعات أو ساكن مرتبط — اجعلها شاغرة بدلاً من ذلك');

        $unit->delete();

        return response()->json(['ok' => true]);
    }
}
