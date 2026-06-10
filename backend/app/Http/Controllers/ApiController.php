<?php

namespace App\Http\Controllers;

use App\Models\Alert;
use App\Models\Building;
use App\Models\Craftsman;
use App\Models\Expense;
use App\Models\Guard;
use App\Models\ParkingSpot;
use App\Models\PayType;
use App\Models\Payment;
use App\Models\Unit;
use App\Models\WaTemplate;
use App\Models\Worker;
use App\Models\YearSummary;
use Illuminate\Http\Request;

// عمارتي — read + write endpoints for all building data. Every list is scoped
// by ?btype=residential|commercial (defaults to residential).
class ApiController extends Controller
{
    /// Building scope for the request.
    /// - Non-admins are locked to their own building (prevents cross-tenant IDOR).
    /// - Admins (and public/guest endpoints with no user) may select via ?btype=.
    private function bk(Request $r): string
    {
        $user = $r->user();
        if ($user && $user->role !== 'admin') {
            return $user->building_key === 'commercial' ? 'commercial' : 'residential';
        }

        return $r->query('btype') === 'commercial' ? 'commercial' : 'residential';
    }

    /// Only an admin may perform writes.
    private function requireAdmin(Request $r): void
    {
        abort_unless(optional($r->user())->role === 'admin', 403, 'يتطلب صلاحية المسؤول');
    }

    public function building(Request $r)
    {
        return Building::where('key', $this->bk($r))->firstOrFail();
    }

    public function summary(Request $r)
    {
        return response()->json(Building::where('key', $this->bk($r))->firstOrFail()->summary);
    }

    public function units(Request $r)
    {
        return Unit::where('building_key', $this->bk($r))
            ->orderBy('floor')->orderBy('no')->get();
    }

    public function payments(Request $r)
    {
        $q = Payment::where('building_key', $this->bk($r));
        if ($r->filled('month')) {
            $q->where('month', (int) $r->query('month'));
        }

        return $q->orderByDesc('date')->get();
    }

    public function storePayment(Request $r)
    {
        $this->requireAdmin($r);
        $data = $r->validate([
            'unit_no' => 'required|string',
            'name' => 'nullable|string',
            'amount' => 'required|integer',
            'kind' => 'required|string',
            'month' => 'required|integer|min:0|max:11',
            'year' => 'required|integer',
            'date' => 'required|date',
            'method' => 'required|string',
            'notes' => 'nullable|string',
        ]);
        $data['building_key'] = $this->bk($r);
        // The unit must exist in the scoped building.
        $unit = Unit::where('building_key', $data['building_key'])
            ->where('no', $data['unit_no'])->first();
        abort_unless($unit !== null, 422, 'الوحدة غير موجودة في هذا المبنى');
        $data['name'] ??= $unit->resident;

        return response()->json(Payment::create($data), 201);
    }

    /// The authenticated resident's own payment history (their unit only).
    public function myPayments(Request $r)
    {
        $user = $r->user();
        $q = Payment::where('building_key', $user->building_key);
        if ($user->unit_no) {
            $q->where('unit_no', $user->unit_no);
        } else {
            $q->whereRaw('1 = 0'); // no unit assigned yet → empty history
        }

        return $q->orderByDesc('date')->get();
    }

    public function payTypes()
    {
        return PayType::orderBy('sort')->get();
    }

    public function expenses(Request $r)
    {
        $q = Expense::where('building_key', $this->bk($r));
        if ($r->filled('cat') && $r->query('cat') !== 'all') {
            $q->where('cat', $r->query('cat'));
        }

        return $q->orderByDesc('date')->get();
    }

    public function storeExpense(Request $r)
    {
        $this->requireAdmin($r);
        $data = $r->validate([
            'cat' => 'required|string',
            'icon' => 'nullable|string',
            'tone' => 'nullable|string',
            'supplier' => 'required|string',
            'amount' => 'required|integer',
            'date' => 'required|date',
            'description' => 'nullable|string',
        ]);
        $data['building_key'] = $this->bk($r);
        $data['icon'] ??= 'receipt';
        $data['tone'] ??= 'gold';
        $data['description'] ??= '';

        return response()->json(Expense::create($data), 201);
    }

    public function workers(Request $r)
    {
        return Worker::where('building_key', $this->bk($r))->get();
    }

    public function storeWorker(Request $r)
    {
        $this->requireAdmin($r);
        $data = $r->validate([
            'name' => 'required|string',
            'type' => 'nullable|string',
            'phone' => 'required|string',
            'address' => 'nullable|string',
            'cycle' => 'required|string',
            'amount' => 'required|integer',
            'last_payment' => 'nullable|date',
            'next_due' => 'nullable|date',
        ]);
        $data['building_key'] = $this->bk($r);
        $data['type'] ??= 'عامل';
        $data['address'] ??= '';
        $data['last_payment'] ??= now()->toDateString();
        $data['next_due'] ??= now()->addMonth()->toDateString();

        return response()->json(Worker::create($data), 201);
    }

    public function parking(Request $r)
    {
        return ParkingSpot::where('building_key', $this->bk($r))->orderBy('no')->get();
    }

    public function guard(Request $r)
    {
        return Guard::where('building_key', $this->bk($r))->firstOrFail();
    }

    public function craftsmen(Request $r)
    {
        $q = Craftsman::query();
        if ($r->filled('job') && $r->query('job') !== 'all') {
            $q->where('job', $r->query('job'));
        }
        if ($r->filled('q')) {
            $term = $r->query('q');
            $q->where(fn ($w) => $w->where('name', 'like', "%$term%")->orWhere('job', 'like', "%$term%"));
        }

        return $q->orderBy('id')->get();
    }

    public function storeCraftsman(Request $r)
    {
        $this->requireAdmin($r);
        $data = $r->validate([
            'name' => 'required|string',
            'job' => 'required|string',
            'phone' => 'required|string',
            'note' => 'nullable|string',
        ]);

        return response()->json(Craftsman::create($data), 201);
    }

    public function alerts(Request $r)
    {
        return Alert::where('building_key', $this->bk($r))->orderBy('id')->get();
    }

    public function waTemplates()
    {
        return WaTemplate::orderBy('id')->get();
    }

    public function yearSummary(Request $r)
    {
        $year = (int) ($r->query('year') ?: 2026);

        return YearSummary::where('building_key', $this->bk($r))
            ->where('year', $year)->firstOrFail();
    }
}
