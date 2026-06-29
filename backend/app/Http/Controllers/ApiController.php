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

    /// A short, unique, uppercase login code (QR / shareable) for a resident.
    private function loginCode(): string
    {
        do {
            $code = strtoupper(bin2hex(random_bytes(4)));
        } while (User::where('login_code', $code)->exists());

        return $code;
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

        // The dashboard period: a year (default current) and an optional month
        // (0-11). When a month is given the headline figures cover that month;
        // otherwise they cover the whole selected year.
        $year = (int) ($r->query('year') ?: $now->year);
        $month = $r->filled('month') ? (int) $r->query('month') : null;

        $payments = Payment::where('building_key', $bk)->get(['amount', 'month', 'year']);
        $expenses = Expense::where('building_key', $bk)->get(['amount', 'cat', 'date']);
        $units = Unit::where('building_key', $bk)->where('status', '!=', 'vacant')->get(['balance']);

        $expYM = fn ($e) => Carbon::parse($e->date)->year === $year
            && ($month === null || (int) Carbon::parse($e->date)->month === $month + 1);

        // Revenue/expense for the selected period (month or whole year).
        $revenueM = (int) $payments->where('year', $year)
            ->when($month !== null, fn ($c) => $c->where('month', $month))->sum('amount');
        $expenseM = (int) $expenses->filter($expYM)->sum('amount');
        $maintM = (int) $expenses->filter(fn ($e) => $e->cat === 'صيانة' && $expYM($e))->sum('amount');

        // Cash balance = opening + the whole selected YEAR's revenue − expenses.
        $yearRevenue = (int) $payments->where('year', $year)->sum('amount');
        $yearExpense = (int) $expenses->filter(fn ($e) => Carbon::parse($e->date)->year === $year)->sum('amount');
        $opening = (int) (YearSummary::where('building_key', $bk)->where('year', $year)->value('opening_balance') ?? 0);
        $balance = $opening + $yearRevenue - $yearExpense;

        // Residents' net dues (live, period-independent): owed by residents.
        $due = (int) $units->filter(fn ($u) => $u->balance < 0)->sum(fn ($u) => abs((int) $u->balance));

        $arShort = ['ينا', 'فبر', 'مار', 'أبر', 'ماي', 'يون', 'يول', 'أغس', 'سبت', 'أكت', 'نوف', 'ديس'];
        $trend = [];
        // Full 12-month trend for the selected year (Jan…Dec).
        for ($m0 = 0; $m0 < 12; $m0++) {
            $rev = (int) $payments->where('year', $year)->where('month', $m0)->sum('amount');
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
            'elevator_phone' => 'nullable|string|max:60',
            'elevator_company' => 'nullable|string|max:160',
            'elevator_contract_start' => 'nullable|date',
            'elevator_contract_end' => 'nullable|date',
            'elevator_last_check' => 'nullable|date',
            'elevator_check_notify' => 'nullable|boolean',
            'elevator_check_interval' => 'nullable|integer|min:1|max:60',
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
            'login_code' => $this->loginCode(),  // QR / shareable resident login
        ]);

        return response()->json(
            $user->only(['id', 'name', 'email', 'phone', 'role', 'building_key', 'unit_no', 'login_code']),
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
        $before = (int) $payment->amount;
        $payment->update(array_filter($data, fn ($v) => $v !== null));

        // Carry-over: shift the unit's balance by the change in (base) amount.
        $delta = (int) $payment->amount - $before;
        if ($delta !== 0) {
            $this->unitFor($payment)?->increment('balance', $delta);
        }

        return response()->json($payment->fresh());
    }

    public function deletePayment(Request $r, Payment $payment)
    {
        $this->requireAdmin($r);
        abort_unless($payment->building_key === $this->bk($r), 403);
        // Carry-over: removing a payment reverts its credit to the unit balance.
        $this->unitFor($payment)?->decrement('balance', (int) $payment->amount);
        $payment->delete();

        return response()->json(['ok' => true]);
    }

    /// The unit a payment belongs to (same building + unit_no), or null.
    private function unitFor(Payment $payment): ?Unit
    {
        return Unit::where('building_key', $payment->building_key)
            ->where('no', $payment->unit_no)->first();
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
            'original_amount' => 'nullable|integer',
            'currency' => 'nullable|string|max:8',
            'exchange_rate' => 'nullable|numeric|min:0',
            'date' => 'nullable|date',
            'description' => 'nullable|string',
            'icon' => 'nullable|string',
            'tone' => 'nullable|string',
        ]);

        // Re-convert if currency/original/rate were supplied (keep `amount` base).
        if (array_key_exists('currency', $data) || array_key_exists('original_amount', $data)) {
            $base = Building::where('key', $expense->building_key)->value('currency') ?: 'USD';
            $currency = $data['currency'] ?? $expense->currency ?? $base;
            $rate = $currency === $base ? 1.0 : (float) ($data['exchange_rate'] ?? $expense->exchange_rate ?? 1);
            $original = (int) ($data['original_amount'] ?? $expense->original_amount ?? $data['amount'] ?? $expense->amount);
            $data['currency'] = $currency;
            $data['exchange_rate'] = $rate;
            $data['original_amount'] = $original;
            $data['amount'] = (int) round($original * $rate);
        }

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
        $bk = $this->bk($r);
        $units = Unit::where('building_key', $bk)
            ->orderBy('floor')->orderBy('no')->get();

        // Attach each unit's resident login code (matched by building + unit_no),
        // so the admin can show a QR / share the code. Null if no such user.
        $codes = User::where('building_key', $bk)
            ->whereNotNull('unit_no')->whereNotNull('login_code')
            ->pluck('login_code', 'unit_no');

        return $units->map(fn ($u) => array_merge(
            $u->toArray(),
            ['login_code' => $codes[$u->no] ?? null],
        ));
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

        // Carry-over: a payment credits the unit's balance (base currency).
        $unit->increment('balance', $payment->amount);

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
            'original_amount' => 'nullable|integer',   // amount as entered
            'currency' => 'nullable|string|max:8',     // entered currency
            'exchange_rate' => 'nullable|numeric|min:0', // entered-currency → base
            'date' => 'required|date',
            'description' => 'nullable|string',
        ]);
        $bk = $this->bk($r);

        // Convert the entered amount to the building's base currency so reports
        // sum cleanly — mirrors payments. `amount` is always base currency.
        $base = Building::where('key', $bk)->value('currency') ?: 'USD';
        $currency = $data['currency'] ?? $base;
        $rate = $currency === $base ? 1.0 : (float) ($data['exchange_rate'] ?? 1);
        $original = (int) ($data['original_amount'] ?? $data['amount']);

        $data['building_key'] = $bk;
        $data['amount'] = (int) round($original * $rate);
        $data['original_amount'] = $original;
        $data['currency'] = $currency;
        $data['exchange_rate'] = $rate;
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

    /// Update a service worker — toggle attendance (came) + record payment
    /// status (full / partial / none) for the current cycle.
    public function updateWorker(Request $r, Worker $worker)
    {
        $this->requireAdmin($r);
        abort_unless($worker->building_key === $this->bk($r), 403);
        $data = $r->validate([
            'name' => 'nullable|string',
            'type' => 'nullable|string',
            'phone' => 'nullable|string',
            'address' => 'nullable|string',
            'cycle' => 'nullable|string',
            'amount' => 'nullable|integer',
            'came' => 'nullable|boolean',
            'last_visit' => 'nullable|date',
            'pay_status' => ['nullable', \Illuminate\Validation\Rule::in(['full', 'partial', 'none'])],
            'paid_amount' => 'nullable|integer|min:0',
            'last_payment' => 'nullable|date',
            'next_due' => 'nullable|date',
        ]);

        // A full payment records today + advances the due date by one cycle.
        if (($data['pay_status'] ?? null) === 'full') {
            $data['paid_amount'] = $data['amount'] ?? $worker->amount;
            $data['last_payment'] ??= now()->toDateString();
        }

        $worker->update(array_filter($data, fn ($v) => $v !== null));

        return response()->json($worker->fresh());
    }

    public function destroyWorker(Request $r, Worker $worker)
    {
        $this->requireAdmin($r);
        abort_unless($worker->building_key === $this->bk($r), 403);
        $worker->delete();

        return response()->json(['ok' => true]);
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
        $q = Alert::where('building_key', $this->bk($r));

        // Residents only see building-wide notices + ones addressed to their unit.
        $u = $r->user();
        if ($u && $u->role === 'resident' && $u->unit_no) {
            $q->whereIn('target', ['all', $u->unit_no]);
        }

        return $q->orderByDesc('id')->get();
    }

    /// Manager composes a notification to all residents or a chosen unit, from a
    /// preset choice or free text. Stored as an internal alert the residents read.
    public function storeNotification(Request $r)
    {
        $this->requireAdmin($r);
        $data = $r->validate([
            'title' => 'required|string|max:120',
            'body' => 'required|string|max:500',
            'target' => 'nullable|string|max:60',     // 'all' | unit_no
            'tone' => 'nullable|string|max:20',
            'icon' => 'nullable|string|max:40',
        ]);

        $alert = Alert::create([
            'building_key' => $this->bk($r),
            'type' => 'notice',
            'icon' => $data['icon'] ?? 'bell',
            'tone' => $data['tone'] ?? 'navy',
            'title' => $data['title'],
            'body' => $data['body'],
            'time_label' => 'الآن',
            'channel' => 'internal',
            'target' => $data['target'] ?: 'all',
        ]);

        return response()->json($alert, 201);
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
