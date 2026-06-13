<?php

namespace App\Http\Controllers;

use App\Models\Unit;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

// عمارتي — unit CRUD (admin only). Adding/editing/removing apartments or shops,
// including marking a unit vacant (excluded from dues/payments).
class UnitController extends Controller
{
    private function bk(Request $r): string
    {
        $u = $r->user();
        if ($u && $u->role !== 'admin') {
            return $u->building_key === 'commercial' ? 'commercial' : 'residential';
        }

        return $r->query('btype') === 'commercial' || $r->input('btype') === 'commercial'
            ? 'commercial' : 'residential';
    }

    private function rules(): array
    {
        return [
            'no' => 'required|string|max:20',
            'floor' => 'required|integer|min:0|max:200',
            'resident' => 'nullable|string|max:120',
            'kind' => 'nullable|string|max:20',
            'phone' => 'nullable|string|max:32',
            'sub' => 'nullable|integer|min:0',
            'status' => ['nullable', Rule::in(['ok', 'late', 'credit', 'vacant'])],
            'balance' => 'nullable|integer',
            'payer' => 'nullable|string|max:60',
            'notes' => 'nullable|string|max:300',
        ];
    }

    public function store(Request $r)
    {
        abort_unless($r->user()->role === 'admin', 403, 'يتطلب صلاحية المسؤول');
        $bk = $this->bk($r);
        $data = $r->validate($this->rules());

        abort_if(
            Unit::where('building_key', $bk)->where('no', $data['no'])->exists(),
            422, 'رقم الوحدة مستخدم بالفعل'
        );

        $vacant = ($data['kind'] ?? null) === 'شاغر' || ($data['status'] ?? null) === 'vacant';
        $unit = Unit::create([
            'building_key' => $bk,
            'ext_id' => strtoupper(substr($bk, 0, 1)).'-'.$data['no'],
            'no' => $data['no'],
            'floor' => $data['floor'],
            'resident' => $vacant ? 'وحدة شاغرة' : ($data['resident'] ?? ''),
            'kind' => $vacant ? 'شاغر' : ($data['kind'] ?? 'مالك'),
            'phone' => $data['phone'] ?? '—',
            'sub' => $data['sub'] ?? 0,
            'status' => $vacant ? 'vacant' : ($data['status'] ?? 'ok'),
            'balance' => $vacant ? 0 : ($data['balance'] ?? 0),
            'payer' => $vacant ? '—' : ($data['payer'] ?? 'الساكن'),
            'contract_start' => $vacant ? null : now()->startOfYear()->toDateString(),
            'contract_end' => $vacant ? null : now()->endOfYear()->toDateString(),
            'notes' => $data['notes'] ?? null,
        ]);

        return response()->json($unit, 201);
    }

    public function update(Request $r, Unit $unit)
    {
        abort_unless($r->user()->role === 'admin', 403, 'يتطلب صلاحية المسؤول');
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
