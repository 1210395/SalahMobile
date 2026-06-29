<?php

namespace App\Http\Controllers;

use App\Models\Unit;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
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
            'sub' => 'nullable|integer|min:0',
            'status' => ['nullable', Rule::in(['ok', 'late', 'credit', 'vacant'])],
            'balance' => 'nullable|integer',           // frontend pre-negates ذمم سابقة
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
            'contract_end' => $vacant ? null : ($data['contract_end'] ?? now()->endOfYear()->toDateString()),
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
            'contract_end' => $vacant ? null : ($data['contract_end'] ?? $unit->contract_end),
            'notes' => $data['notes'] ?? $unit->notes,
        ]);

        return response()->json($unit->fresh());
    }

    public function destroy(Request $r, Unit $unit)
    {
        abort_unless($r->user()->role === 'admin', 403, 'يتطلب صلاحية المسؤول');
        abort_unless($unit->building_key === $this->bk($r), 403);
        $unit->delete();

        return response()->json(['ok' => true]);
    }
}
