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
use App\Models\User;
use App\Models\YearSummary;
use App\Services\AlertGenerator;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Hash;

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
        // Admins + super-admins may select the building; everyone else is locked
        // to their own (prevents cross-tenant IDOR).
        if ($user && ! in_array($user->role, ['admin', 'superadmin'])) {
            return $user->building_key === 'commercial' ? 'commercial' : 'residential';
        }

        return $r->query('btype') === 'commercial' ? 'commercial' : 'residential';
    }

    /// Only an admin (or super-admin) may perform writes.
    private function requireAdmin(Request $r): void
    {
        abort_unless(in_array(optional($r->user())->role, ['admin', 'superadmin']),
            403, 'يتطلب صلاحية المسؤول');
    }

    public function building(Request $r)
    {
        return Building::where('key', $this->bk($r))->firstOrFail();
    }

    public function summary(Request $r)
    {
        // Computed LIVE from the building's real payments/expenses/units so the
        // dashboard always reflects current data (the old stored JSON went stale
        // and never updated when payments/expenses were recorded).
        $bk = $this->bk($r);
        Building::where('key', $bk)->firstOrFail();
        $now = now();
        $curYear = (int) $now->year;
        $curMonth0 = (int) $now->month - 1; // app months are 0-indexed

        $payments = Payment::where('building_key', $bk)->get(['amount', 'month', 'year']);
        $expenses = Expense::where('building_key', $bk)->get(['amount', 'cat', 'date']);
        $units = Unit::where('building_key', $bk)->where('status', '!=', 'vacant')->get(['balance']);

        $revenueTotal = (int) $payments->sum('amount');
        $expenseTotal = (int) $expenses->sum('amount');
        $revenueM = (int) $payments->where('year', $curYear)->where('month', $curMonth0)->sum('amount');

        $inCurMonth = fn ($e) => Carbon::parse($e->date)->year === $curYear
            && (int) Carbon::parse($e->date)->month === $curMonth0 + 1;
        $expenseM = (int) $expenses->filter($inCurMonth)->sum('amount');
        $maintM = (int) $expenses->filter(fn ($e) => $e->cat === 'صيانة' && $inCurMonth($e))->sum('amount');

        $due = (int) $units->filter(fn ($u) => $u->balance < 0)->sum(fn ($u) => abs((int) $u->balance));
        $opening = (int) (YearSummary::where('building_key', $bk)->where('year', $curYear)->value('opening_balance') ?? 0);
        $balance = $opening + $revenueTotal - $expenseTotal;

        $arShort = ['ينا', 'فبر', 'مار', 'أبر', 'ماي', 'يون', 'يول', 'أغس', 'سبت', 'أكت', 'نوف', 'ديس'];
        $trend = [];
        for ($i = 5; $i >= 0; $i--) {
            $d = $now->copy()->subMonths($i);
            $m0 = (int) $d->month - 1;
            $rev = (int) $payments->where('year', (int) $d->year)->where('month', $m0)->sum('amount');
            $trend[] = ['label' => $arShort[$m0], 'value' => $rev, 'color' => 'navy600'];
        }

        return response()->json([
            'balance' => $balance,
            'due' => $due,
            'revenueM' => $revenueM,
            'expenseM' => $expenseM,
            'bars' => [
                ['label' => 'إيرادات', 'value' => $revenueM, 'color' => 'navy600'],
                ['label' => 'مستحقات', 'value' => $due, 'color' => 'gold500'],
                ['label' => 'مصروفات', 'value' => $expenseM, 'color' => 'late'],
                ['label' => 'صيانة', 'value' => $maintM, 'color' => 'ok'],
            ],
            'trend' => $trend,
        ]);
    }

    /// Edit building settings (admin only) — name, address, defaults, rates.
    public function updateBuilding(Request $r)
    {
        $this->requireAdmin($r);
        $data = $r->validate([
            'name' => 'nullable|string|max:160',
            'address' => 'nullable|string|max:200',
            'floors' => 'nullable|integer|min:-50|max:300',
            'units_count' => 'nullable|integer|min:0|max:2000',
            'subscription' => 'nullable|integer|min:0',
            'elevator_fee' => 'nullable|integer|min:0',
            'exchange_rate' => 'nullable|numeric|min:0',
            'currency' => 'nullable|string|max:8',   // building base currency
        ]);
        $building = Building::where('key', $this->bk($r))->firstOrFail();
        $building->update(array_filter($data, fn ($v) => $v !== null));

        return response()->json($building->fresh());
    }

    /// Admin creates a resident (renter) account directly for their building.
    /// The renter signs in by phone (OTP) or, if email + password are given, by
    /// email + password. Optionally bound to a unit.
    public function storeResident(Request $r)
    {
        $this->requireAdmin($r);
        $bk = $r->user()->building_key ?: $this->bk($r);
        $data = $r->validate([
            'name' => 'required|string|max:120',
            'phone' => 'required|string|max:32|unique:users,phone',
            'email' => 'nullable|email|unique:users,email',
            'password' => 'nullable|string|min:6',
            'unit_no' => 'nullable|string|max:20',
        ]);

        $user = User::create([
            'name' => $data['name'],
            'phone' => $data['phone'],
            'email' => $data['email'] ?? null,
            'password' => isset($data['password']) ? Hash::make($data['password']) : null,
            'role' => 'resident',
            'building_key' => $bk,
            'unit_no' => $data['unit_no'] ?? null,
        ]);

        return response()->json(
            $user->only(['id', 'name', 'email', 'phone', 'role', 'building_key', 'unit_no']),
            201,
        );
    }

    /// A building admin creates a co-admin for THEIR OWN building (building_key
    /// is forced to the requester's — they cannot grant access to another building).
    public function createCoAdmin(Request $r)
    {
        $this->requireAdmin($r);
        $bk = $r->user()->building_key ?: $this->bk($r);
        $data = $r->validate([
            'name' => 'required|string|max:120',
            'email' => 'required|email|unique:users,email',
            'password' => 'required|string|min:6',
        ]);

        $user = User::create([
            'name' => $data['name'],
            'email' => $data['email'],
            'password' => Hash::make($data['password']),
            'role' => 'admin',
            'building_key' => $bk,
        ]);

        return response()->json(
            $user->only(['id', 'name', 'email', 'role', 'building_key']),
            201,
        );
    }

    // ─────────── Payments edit / delete ───────────
    public function updatePayment(Request $r, Payment $payment)
    {
        $this->requireAdmin($r);
        abort_unless($payment->building_key === $this->bk($r), 403);
        $data = $r->validate([
            'amount' => 'nullable|integer',
            'name' => 'nullable|string',
            'kind' => 'nullable|string',
            'month' => 'nullable|integer|min:0|max:11',
            'year' => 'nullable|integer',
            'date' => 'nullable|date',
            'method' => 'nullable|string',
        ]);
        $payment->update(array_filter($data, fn ($v) => $v !== null));

        return response()->json($payment->fresh());
    }

    public function deletePayment(Request $r, Payment $payment)
    {
        $this->requireAdmin($r);
        abort_unless($payment->building_key === $this->bk($r), 403);
        $payment->delete();

        return response()->json(['ok' => true]);
    }

    // ─────────── Expenses edit / delete ───────────
    public function updateExpense(Request $r, Expense $expense)
    {
        $this->requireAdmin($r);
        abort_unless($expense->building_key === $this->bk($r), 403);
        $data = $r->validate([
            'cat' => 'nullable|string',
            'supplier' => 'nullable|string',
            'amount' => 'nullable|integer',
            'date' => 'nullable|date',
            'description' => 'nullable|string',
            'icon' => 'nullable|string',
            'tone' => 'nullable|string',
        ]);
        $expense->update(array_filter($data, fn ($v) => $v !== null));

        return response()->json($expense->fresh());
    }

    public function deleteExpense(Request $r, Expense $expense)
    {
        $this->requireAdmin($r);
        abort_unless($expense->building_key === $this->bk($r), 403);
        $expense->delete();

        return response()->json(['ok' => true]);
    }

    // ─────────── Guard set / edit (upsert, one per building) ───────────
    public function storeGuard(Request $r)
    {
        $this->requireAdmin($r);
        $data = $r->validate([
            'name' => 'nullable|string|max:120',
            'phone' => 'nullable|string|max:32',
            'address' => 'nullable|string|max:200',
            'fee' => 'nullable|integer|min:0',
        ]);
        $bk = $this->bk($r);
        $cur = Guard::where('building_key', $bk)->first();
        // All guard columns are NOT NULL — fill every one (keep existing where not edited).
        $guard = Guard::updateOrCreate(['building_key' => $bk], [
            'name' => $data['name'] ?? $cur->name ?? '',
            'phone' => $data['phone'] ?? $cur->phone ?? '—',
            'address' => $data['address'] ?? $cur->address ?? '',
            'fee' => $data['fee'] ?? $cur->fee ?? 0,
            'last_payment' => $cur->last_payment ?? now()->toDateString(),
            'next_due' => $cur->next_due ?? now()->addMonth()->toDateString(),
        ]);

        return response()->json($guard->fresh());
    }

    // ─────────── Parking CRUD ───────────
    public function storeParking(Request $r)
    {
        $this->requireAdmin($r);
        $data = $r->validate([
            'no' => 'required|string|max:20',
            'status' => 'nullable|string|max:20',
            'unit_no' => 'nullable|string|max:20',
            'code' => 'nullable|string|max:20',
            'note' => 'nullable|string|max:200',
        ]);
        $data['building_key'] = $this->bk($r);
        $data['status'] ??= 'شاغر';

        return response()->json(ParkingSpot::create($data), 201);
    }

    public function updateParking(Request $r, ParkingSpot $parking)
    {
        $this->requireAdmin($r);
        abort_unless($parking->building_key === $this->bk($r), 403);
        $data = $r->validate([
            'no' => 'nullable|string|max:20',
            'status' => 'nullable|string|max:20',
            'unit_no' => 'nullable|string|max:20',
            'code' => 'nullable|string|max:20',
            'note' => 'nullable|string|max:200',
        ]);
        $parking->update(array_filter($data, fn ($v) => $v !== null));

        return response()->json($parking->fresh());
    }

    public function deleteParking(Request $r, ParkingSpot $parking)
    {
        $this->requireAdmin($r);
        abort_unless($parking->building_key === $this->bk($r), 403);
        $parking->delete();

        return response()->json(['ok' => true]);
    }

    // ─────────── Pay-type edit (amounts / enabled) ───────────
    public function updatePayType(Request $r, PayType $payType)
    {
        $this->requireAdmin($r);
        $data = $r->validate([
            'label' => 'nullable|string|max:120',
            'amount' => 'nullable|integer|min:0',
            'enabled' => 'nullable|boolean',
            'optional' => 'nullable|boolean',
        ]);
        $payType->update(array_filter($data, fn ($v) => $v !== null));

        return response()->json($payType->fresh());
    }

    /// Recompute alerts from live data and "dispatch" them (admin only).
    public function regenerateAlerts(Request $r, AlertGenerator $gen)
    {
        $this->requireAdmin($r);
        $bk = $this->bk($r);
        $count = $gen->regenerate($bk);

        return response()->json([
            'generated' => $count,
            'alerts' => Alert::where('building_key', $bk)->orderBy('id')->get(),
        ]);
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
            'amount' => 'nullable|integer',            // base amount (legacy/optional)
            'original_amount' => 'nullable|integer',   // amount as entered
            'currency' => 'nullable|string|max:8',     // entered currency
            'exchange_rate' => 'nullable|numeric|min:0', // entered-currency → base
            'kind' => 'required|string',
            'month' => 'required|integer|min:0|max:11',
            'year' => 'required|integer',
            'date' => 'required|date',
            'method' => 'required|string',
            'notes' => 'nullable|string',
        ]);
        $bk = $this->bk($r);
        $unit = Unit::where('building_key', $bk)->where('no', $data['unit_no'])->first();
        abort_unless($unit !== null, 422, 'الوحدة غير موجودة في هذا المبنى');

        // Convert the entered amount to the building's base currency. `amount` is
        // always stored in the base currency so totals/reports sum cleanly.
        $base = Building::where('key', $bk)->value('currency') ?: 'USD';
        $currency = $data['currency'] ?? $base;
        $rate = $currency === $base ? 1.0 : (float) ($data['exchange_rate'] ?? 1);
        $original = (int) ($data['original_amount'] ?? $data['amount'] ?? 0);

        $payment = Payment::create([
            'building_key' => $bk,
            'unit_no' => $data['unit_no'],
            'name' => $data['name'] ?? $unit->resident,
            'amount' => (int) round($original * $rate),  // base currency
            'currency' => $currency,
            'original_amount' => $original,
            'exchange_rate' => $rate,
            'kind' => $data['kind'],
            'month' => $data['month'],
            'year' => $data['year'],
            'date' => $data['date'],
            'method' => $data['method'],
            'notes' => $data['notes'] ?? null,
        ]);

        return response()->json($payment, 201);
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
        // An empty building has no guard yet — return a blank default (not a 404)
        // so the app's bundle load never breaks.
        $guard = Guard::where('building_key', $this->bk($r))->first();

        return response()->json($guard ?? [
            'name' => '', 'phone' => '', 'address' => '',
            'fee' => 0, 'last_payment' => null, 'next_due' => null,
        ]);
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
        $ys = YearSummary::where('building_key', $this->bk($r))
            ->where('year', $year)->first();

        return response()->json($ys ?? [
            'year' => $year, 'opening_balance' => 0, 'months' => [],
        ]);
    }
}
