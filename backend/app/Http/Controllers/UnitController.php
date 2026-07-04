<?php

namespace App\Http\Controllers;

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
            'contract_end' => 'nullable|date',
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
            Unit::where('building_key', $bk)->where('no', $data['no'])->exists(),
            422, 'رقم الوحدة مستخدم بالفعل'
        );

        $vacant = ($data['kind'] ?? null) === 'شاغر' || ($data['status'] ?? null) === 'vacant';
        $sub = (int) ($data['sub'] ?? 0);
        $contractStart = $vacant ? null : ($data['contract_start'] ?? now()->startOfYear()->toDateString());
        $balance = $vacant ? 0 : (int) ($data['balance'] ?? 0);

        // Auto opening debt from the contract start (− = owes). Unchecked → start
        // from the current month (no back-debt, keep any provided balance).
        if (! $vacant && ($data['back_debt'] ?? false) && $contractStart) {
            $months = (int) Carbon::parse($contractStart)->diffInMonths(now());
            $balance = -1 * $sub * $months;
            // A very old contract × a large fee can exceed the INT column — reject
            // cleanly instead of a raw MySQL overflow 500.
            abort_if(abs($balance) > 2147483647, 422,
                'الرصيد المحتسب كبير جداً — تحقّق من الدفعة الشهرية وتاريخ بداية العقد');
        }

        $unit = Unit::create([
            'building_key' => $bk,
            'ext_id' => strtoupper(substr($bk, 0, 1)).'-'.$data['no'],
            'no' => $data['no'],
            'floor' => $data['floor'],
            'resident' => $vacant ? 'وحدة شاغرة' : ($data['resident'] ?? ''),
            'kind' => $vacant ? 'شاغر' : ($data['kind'] ?? 'مالك'),
            'phone' => $data['phone'] ?? '—',
            'sub' => $sub,
            'status' => $vacant ? 'vacant' : ($data['status'] ?? 'ok'),
            'balance' => $balance,
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
        abort_unless($unit->building_key === $this->bk($r), 403);
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
                Unit::where('building_key', $unit->building_key)
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
                // A vacant unit is excluded from dues: balance zeroed, status vacant.
                'status' => $vacant ? 'vacant' : ($data['status'] ?? ($unit->status === 'vacant' ? 'ok' : $unit->status)),
                'balance' => $vacant ? 0 : ($data['balance'] ?? $unit->balance),
                'payer' => $vacant ? '—' : ($data['payer'] ?? $unit->payer),
                'contract_start' => $vacant ? null : ($data['contract_start'] ?? $unit->contract_start),
                // Sent null (empty "مستمر") clears the end date; only an ABSENT key
                // keeps the current value — so toggling مستمر on edit works.
                'contract_end' => $vacant
                    ? null
                    : (array_key_exists('contract_end', $data) ? $data['contract_end'] : $unit->contract_end),
                'notes' => $data['notes'] ?? $unit->notes,
            ]);

            // Cascade the rename so payment history and the resident's account
            // stay linked to the unit.
            if ($renamed) {
                Payment::where('building_key', $unit->building_key)
                    ->where('unit_no', $oldNo)->update(['unit_no' => $newNo]);
                User::where('building_key', $unit->building_key)
                    ->where('unit_no', $oldNo)->update(['unit_no' => $newNo]);
            }
        });

        return response()->json($unit->fresh());
    }

    public function destroy(Request $r, Unit $unit)
    {
        abort_unless($r->user()->role === 'admin', 403, 'يتطلب صلاحية المسؤول');
        abort_unless($unit->building_key === $this->bk($r), 403);

        // Deleting a unit would orphan its payment history and leave a resident
        // account pointing at a gone unit. Block it and steer the admin to mark
        // the unit vacant instead (which excludes it from dues but keeps records).
        $hasPayments = Payment::where('building_key', $unit->building_key)
            ->where('unit_no', $unit->no)->exists();
        $hasResident = User::where('building_key', $unit->building_key)
            ->where('unit_no', $unit->no)->exists();
        abort_if($hasPayments || $hasResident, 422,
            'لا يمكن حذف وحدة لها دفعات أو ساكن مرتبط — اجعلها شاغرة بدلاً من ذلك');

        $unit->delete();

        return response()->json(['ok' => true]);
    }
}
