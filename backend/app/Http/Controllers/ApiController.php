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
    /// Max accepted money input (well under the signed-INT column limit so a
    /// converted total can't overflow). Rejects fat-finger/garbage amounts with
    /// a clean 422 instead of a raw MySQL out-of-range 500.
    private const MONEY_MAX = 2000000000;

    /// Abort with 422 if a computed integer would overflow the DB INT column.
    private function guardIntRange(int $v): void
    {
        abort_if($v > 2147483647 || $v < -2147483648, 422, 'المبلغ خارج النطاق المسموح');
    }

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
        abort_unless($this->isAdmin($r), 403, 'يتطلب صلاحية المسؤول');
    }

    /// Whether the request actor is an admin (or super-admin). Used to scope
    /// list reads so residents can't see building-wide data (or login codes).
    private function isAdmin(Request $r): bool
    {
        return in_array(optional($r->user())->role, ['admin', 'superadmin']);
    }

    /// The building this request is scoped to (multi-building).
    /// - An authenticated user is locked to THEIR OWN building (building_id) — an
    ///   admin owns one building; a resident belongs to one. A user without a
    ///   building yet (a pending manager mid-onboarding) scopes to nothing.
    /// - A guest/public request resolves by type (first building of that type).
    private function buildingId(Request $r): ?int
    {
        $u = $r->user();
        if ($u) {
            return $u->building_id ? (int) $u->building_id : null;
        }

        return Building::idForKey($this->bk($r));
    }

    /// A short, unique, uppercase login code (QR / shareable) for a resident.
    private function loginCode(): string
    {
        do {
            // 128-bit CSPRNG code (resident's standing login credential; kept
            // readable so the admin can render the QR / share link — see units()).
            $code = strtoupper(bin2hex(random_bytes(16)));
        } while (User::where('login_code', $code)->exists());

        return $code;
    }

    public function building(Request $r)
    {
        // An authenticated user gets THEIR building; a guest gets the first of
        // the requested type (for the public preview / branding).
        $id = $this->buildingId($r);
        if ($id) {
            return Building::findOrFail($id);
        }

        return Building::where('key', $this->bk($r))->firstOrFail();
    }

    public function summary(Request $r)
    {
        // Computed LIVE from the building's real payments/expenses/units so the
        // dashboard always reflects current data (the old stored JSON went stale
        // and never updated when payments/expenses were recorded).
        $now = now();

        // The dashboard period: a year (default current) and an optional month
        // (0-11). When a month is given the headline figures cover that month;
        // otherwise they cover the whole selected year.
        $year = (int) ($r->query('year') ?: $now->year);
        $month = $r->filled('month') ? (int) $r->query('month') : null;

        $payments = Payment::where('building_id', $this->buildingId($r))->get(['amount', 'month', 'year']);
        $expenses = Expense::where('building_id', $this->buildingId($r))->get(['amount', 'cat', 'date']);
        $units = Unit::where('building_id', $this->buildingId($r))->where('status', '!=', 'vacant')->get(['balance']);

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

        $opening = $this->openingBalance($this->buildingId($r), $year, $payments, $expenses);
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
            'subscription' => 'nullable|integer|min:0|max:'.self::MONEY_MAX,
            'elevator_fee' => 'nullable|integer|min:0|max:'.self::MONEY_MAX,
            'elevator_phone' => 'nullable|string|max:60',
            'elevator_company' => 'nullable|string|max:160',
            'elevator_contract_start' => 'nullable|date',
            'elevator_contract_end' => 'nullable|date|after_or_equal:elevator_contract_start',
            'elevator_last_check' => 'nullable|date',
            'elevator_check_notify' => 'nullable|boolean',
            'elevator_check_interval' => 'nullable|integer|min:1|max:60',
            'exchange_rate' => 'nullable|numeric|min:0',
            'currency' => 'nullable|string|max:8',   // building base currency
        ]);
        $building = Building::findOrFail($this->buildingId($r));
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

        // A unit has at most one resident account. Unlink anyone currently on it
        // (e.g. the previous tenant) so they can't keep seeing the new tenant's
        // payments via /me/payments.
        if (! empty($data['unit_no'])) {
            User::where('building_id', $this->buildingId($r))->where('unit_no', $data['unit_no'])
                ->update(['unit_no' => null]);
        }

        $user = User::create([
            'name' => $data['name'],
            'phone' => $data['phone'],
            'email' => $data['email'] ?? null,
            'password' => isset($data['password']) ? Hash::make($data['password']) : null,
            'role' => 'resident',
            'building_key' => $bk,
            'building_id' => $this->buildingId($r),
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
            'building_id' => $this->buildingId($r),
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
        abort_unless($payment->building_id === $this->buildingId($r), 403);
        $data = $r->validate([
            // Bounded both ways so a huge (or hugely negative) value can't
            // overflow the INT column with a raw MySQL 500 — mirrors storePayment.
            'amount' => 'nullable|integer|max:'.self::MONEY_MAX.'|min:-'.self::MONEY_MAX,
            'name' => 'nullable|string|max:120',
            'kind' => 'nullable|string|max:80',
            'month' => 'nullable|integer|min:0|max:11',
            'year' => 'nullable|integer|min:2000|max:2100',
            'date' => 'nullable|date',
            'method' => 'nullable|string|max:40',
        ]);
        $before = (int) $payment->amount;
        $clean = array_filter($data, fn ($v) => $v !== null);

        // The edit form enters a BASE-currency amount. If the amount changed,
        // resync the original-currency fields so a receipt can't show a stale
        // "350 ILS" next to a freshly-edited base total.
        if (array_key_exists('amount', $clean) && (int) $clean['amount'] !== $before) {
            $base = Building::where('key', $payment->building_key)->value('currency') ?: 'USD';
            $clean['original_amount'] = (int) $clean['amount'];
            $clean['currency'] = $base;
            $clean['exchange_rate'] = 1;
        }
        $payment->update($clean);

        // Carry-over: shift the unit's balance by the change in (base) amount.
        $delta = (int) $payment->amount - $before;
        if ($delta !== 0) {
            $unit = $this->unitFor($payment);
            $unit?->increment('balance', $delta);
            $this->syncUnitStatus($unit);
        }

        return response()->json($payment->fresh());
    }

    public function deletePayment(Request $r, Payment $payment)
    {
        $this->requireAdmin($r);
        abort_unless($payment->building_id === $this->buildingId($r), 403);
        // Carry-over: removing a payment reverts its credit to the unit balance.
        $unit = $this->unitFor($payment);
        $unit?->decrement('balance', (int) $payment->amount);
        $this->syncUnitStatus($unit);
        $payment->delete();

        return response()->json(['ok' => true]);
    }

    /// The unit a payment belongs to (same building + unit_no), or null.
    private function unitFor(Payment $payment): ?Unit
    {
        return Unit::where('building_id', $payment->building_id)
            ->where('no', $payment->unit_no)->first();
    }

    /// Keep a unit's status label in sync with its (computed) balance so the
    /// badge, late-count, and overdue alerts never contradict what the resident
    /// actually owes. Vacant is a manual choice (excluded from dues) and is kept.
    private function syncUnitStatus(?Unit $unit): void
    {
        if (! $unit || $unit->status === 'vacant') {
            return;
        }
        $bal = (int) $unit->fresh()->balance;
        $status = $bal < 0 ? 'late' : ($bal > 0 ? 'credit' : 'ok');
        if ($unit->status !== $status) {
            $unit->update(['status' => $status]);
        }
    }

    // ─────────── Expenses edit / delete ───────────
    public function updateExpense(Request $r, Expense $expense)
    {
        $this->requireAdmin($r);
        abort_unless($expense->building_id === $this->buildingId($r), 403);
        $data = $r->validate([
            'cat' => 'nullable|string|max:120',
            'supplier' => 'nullable|string|max:160',
            'amount' => 'nullable|integer|min:0|max:'.self::MONEY_MAX,
            'original_amount' => 'nullable|integer|min:0|max:'.self::MONEY_MAX,
            'currency' => 'nullable|string|max:8',
            'exchange_rate' => 'nullable|numeric|gt:0|max:100000',
            'date' => 'nullable|date',
            'description' => 'nullable|string|max:255',
            'icon' => 'nullable|string|max:40',
            'tone' => 'nullable|string|max:20',
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
        abort_unless($expense->building_id === $this->buildingId($r), 403);
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
        $cur = Guard::where('building_id', $this->buildingId($r))->first();
        // All guard columns are NOT NULL — fill every one (keep existing where not edited).
        $guard = Guard::updateOrCreate(['building_id' => $this->buildingId($r)], [
            'building_key' => $bk,
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
        $data['building_id'] = $this->buildingId($r);
        // Parking numbers are unique per building — mirrors unit numbers.
        abort_if(
            ParkingSpot::where('building_id', $this->buildingId($r))
                ->where('no', $data['no'])->exists(),
            422, 'رقم الموقف مستخدم بالفعل'
        );
        $data['status'] ??= 'شاغر';

        return response()->json(ParkingSpot::create($data), 201);
    }

    public function updateParking(Request $r, ParkingSpot $parking)
    {
        $this->requireAdmin($r);
        abort_unless($parking->building_id === $this->buildingId($r), 403);
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
        abort_unless($parking->building_id === $this->buildingId($r), 403);
        $parking->delete();

        return response()->json(['ok' => true]);
    }

    // ─────────── Pay-type edit (amounts / enabled) ───────────
    public function updatePayType(Request $r, PayType $payType)
    {
        $this->requireAdmin($r);
        $data = $r->validate([
            'label' => 'nullable|string|max:120',
            'amount' => 'nullable|integer|min:0|max:'.self::MONEY_MAX,
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
        $count = $gen->regenerate(Building::find($this->buildingId($r)));

        return response()->json([
            'generated' => $count,
            'alerts' => Alert::where('building_id', $this->buildingId($r))->orderBy('id')->get(),
        ]);
    }

    public function units(Request $r)
    {
        $bk = $this->bk($r);

        // A resident sees ONLY their own unit, and never any login code (which is
        // a login credential — exposing all of them would let any resident take
        // over any other resident's account).
        if (! $this->isAdmin($r)) {
            return Unit::where('building_id', $this->buildingId($r))
                ->where('no', optional($r->user())->unit_no ?? '__none__')
                ->orderBy('no')->get();
        }

        $units = Unit::where('building_id', $this->buildingId($r))
            ->orderBy('floor')->orderBy('no')->get();

        // Attach each unit's resident login code (matched by building + unit_no),
        // so the admin can show a QR / share the code. Null if no such user.
        $codes = User::where('building_id', $this->buildingId($r))
            ->whereNotNull('unit_no')->whereNotNull('login_code')
            ->pluck('login_code', 'unit_no');

        return $units->map(fn ($u) => array_merge(
            $u->toArray(),
            ['login_code' => $codes[$u->no] ?? null],
        ));
    }

    public function payments(Request $r)
    {
        $q = Payment::where('building_id', $this->buildingId($r));
        // A resident only sees their OWN unit's payments — not the whole building.
        if (! $this->isAdmin($r)) {
            $q->where('unit_no', optional($r->user())->unit_no ?? '__none__');
        }
        if ($r->filled('month')) {
            $q->where('month', (int) $r->query('month'));
        }

        return $q->orderByDesc('date')->get();
    }

    public function storePayment(Request $r)
    {
        $this->requireAdmin($r);
        $data = $r->validate([
            'unit_no' => 'required|string|max:20',
            'name' => 'nullable|string|max:120',
            'amount' => 'nullable|integer|max:'.self::MONEY_MAX,   // base amount (legacy/optional)
            'original_amount' => 'nullable|integer|min:0|max:'.self::MONEY_MAX, // amount as entered
            'currency' => 'nullable|string|max:8',     // entered currency
            'exchange_rate' => 'nullable|numeric|gt:0|max:100000', // entered-currency → base
            'kind' => 'required|string|max:80',
            'month' => 'required|integer|min:0|max:11',
            'year' => 'required|integer|min:2000|max:2100',
            'date' => 'required|date',
            'method' => 'required|string|max:40',
            'notes' => 'nullable|string|max:1000',
        ]);
        $bk = $this->bk($r);
        $unit = Unit::where('building_id', $this->buildingId($r))->where('no', $data['unit_no'])->first();
        abort_unless($unit !== null, 422, 'الوحدة غير موجودة في هذا المبنى');

        // Convert the entered amount to the building's base currency. `amount` is
        // always stored in the base currency so totals/reports sum cleanly.
        $base = Building::where('key', $bk)->value('currency') ?: 'USD';
        $currency = $data['currency'] ?? $base;
        $rate = $currency === $base ? 1.0 : (float) ($data['exchange_rate'] ?? 1);
        $original = (int) ($data['original_amount'] ?? $data['amount'] ?? 0);
        // The converted total must fit the INT column — else MySQL 500s with a raw
        // overflow error. Reject cleanly instead (e.g. 1B entered × a big rate).
        $baseAmount = (int) round($original * $rate);
        $this->guardIntRange($baseAmount);

        $payment = Payment::create([
            'building_key' => $bk,
            'building_id' => $this->buildingId($r),
            'unit_no' => $data['unit_no'],
            'name' => $data['name'] ?? $unit->resident,
            'amount' => $baseAmount,  // base currency
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
        $this->syncUnitStatus($unit);

        return response()->json($payment, 201);
    }

    /// The authenticated resident's own payment history (their unit only).
    public function myPayments(Request $r)
    {
        $user = $r->user();
        $q = Payment::where('building_id', $user->building_id);
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
        // Building expenses are admin-only financial data — not for residents.
        if (! $this->isAdmin($r)) {
            return response()->json([]);
        }
        $q = Expense::where('building_id', $this->buildingId($r));
        if ($r->filled('cat') && $r->query('cat') !== 'all') {
            $q->where('cat', $r->query('cat'));
        }

        return $q->orderByDesc('date')->get();
    }

    public function storeExpense(Request $r)
    {
        $this->requireAdmin($r);
        $data = $r->validate([
            // String maxes keep input within the varchar(255) columns — an
            // over-long value would otherwise overflow into a raw MySQL 500.
            'cat' => 'required|string|max:120',
            'icon' => 'nullable|string|max:40',
            'tone' => 'nullable|string|max:20',
            'supplier' => 'required|string|max:160',
            'amount' => 'required|integer|min:0|max:'.self::MONEY_MAX,
            'original_amount' => 'nullable|integer|min:0|max:'.self::MONEY_MAX, // amount as entered
            'currency' => 'nullable|string|max:8',     // entered currency
            'exchange_rate' => 'nullable|numeric|gt:0|max:100000', // entered-currency → base
            'date' => 'required|date',
            'description' => 'nullable|string|max:255',
        ]);
        $bk = $this->bk($r);

        // Convert the entered amount to the building's base currency so reports
        // sum cleanly — mirrors payments. `amount` is always base currency.
        $base = Building::where('key', $bk)->value('currency') ?: 'USD';
        $currency = $data['currency'] ?? $base;
        $rate = $currency === $base ? 1.0 : (float) ($data['exchange_rate'] ?? 1);
        $original = (int) ($data['original_amount'] ?? $data['amount']);

        $data['building_key'] = $bk;
        $data['building_id'] = $this->buildingId($r);
        $data['amount'] = (int) round($original * $rate);
        $this->guardIntRange($data['amount']);
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
        // Worker roster + pay is admin-only — not for residents.
        if (! $this->isAdmin($r)) {
            return response()->json([]);
        }

        return Worker::where('building_id', $this->buildingId($r))->get();
    }

    public function storeWorker(Request $r)
    {
        $this->requireAdmin($r);
        $data = $r->validate([
            'name' => 'required|string|max:120',
            'type' => 'nullable|string|max:40',
            'phone' => 'required|string|max:32',
            'address' => 'nullable|string|max:200',
            'cycle' => 'required|string|max:20',
            'amount' => 'required|integer|min:0|max:'.self::MONEY_MAX,
            'last_payment' => 'nullable|date',
            'next_due' => 'nullable|date',
        ]);
        $data['building_key'] = $this->bk($r);
        $data['building_id'] = $this->buildingId($r);
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
        abort_unless($worker->building_id === $this->buildingId($r), 403);
        $data = $r->validate([
            'name' => 'nullable|string|max:120',
            'type' => 'nullable|string|max:40',
            'phone' => 'nullable|string|max:32',
            'address' => 'nullable|string|max:200',
            'cycle' => 'nullable|string|max:20',
            'amount' => 'nullable|integer|min:0|max:'.self::MONEY_MAX,
            'came' => 'nullable|boolean',
            'last_visit' => 'nullable|date',
            'pay_status' => ['nullable', \Illuminate\Validation\Rule::in(['full', 'partial', 'none'])],
            'paid_amount' => 'nullable|integer|min:0|max:'.self::MONEY_MAX,
            'last_payment' => 'nullable|date',
            'next_due' => 'nullable|date',
        ]);

        // A full payment records today + advances the due date by one cycle
        // (daily/weekly/monthly). Without this the "next due" date stays stale
        // and the worker looks perpetually due on the same past date.
        if (($data['pay_status'] ?? null) === 'full') {
            $data['paid_amount'] = $data['amount'] ?? $worker->amount;
            $data['last_payment'] ??= now()->toDateString();
            $cycle = $data['cycle'] ?? $worker->cycle;
            $next = match ($cycle) {
                'يومي' => now()->addDay(),
                'أسبوعي' => now()->addWeek(),
                default => now()->addMonth(),   // شهري / anything else
            };
            $data['next_due'] ??= $next->toDateString();
        }

        // A partial payment can't exceed the fee — clamp so paid_amount stays
        // within [0, fee] and can't imply the worker was overpaid "partially".
        if (($data['pay_status'] ?? null) === 'partial' && isset($data['paid_amount'])) {
            $fee = (int) ($data['amount'] ?? $worker->amount);
            $data['paid_amount'] = max(0, min((int) $data['paid_amount'], $fee));
        }

        $worker->update(array_filter($data, fn ($v) => $v !== null));

        return response()->json($worker->fresh());
    }

    public function destroyWorker(Request $r, Worker $worker)
    {
        $this->requireAdmin($r);
        abort_unless($worker->building_id === $this->buildingId($r), 403);
        $worker->delete();

        return response()->json(['ok' => true]);
    }

    public function parking(Request $r)
    {
        // The parking roster (spot → unit mapping + access codes) is admin-only;
        // residents have no parking screen and must not receive it.
        if (! $this->isAdmin($r)) {
            return response()->json([]);
        }

        return ParkingSpot::where('building_id', $this->buildingId($r))->orderBy('no')->get();
    }

    public function guard(Request $r)
    {
        // An empty building has no guard yet — return a blank default (not a 404)
        // so the app's bundle load never breaks.
        $guard = Guard::where('building_id', $this->buildingId($r))->first();

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
            'name' => 'required|string|max:120',
            'job' => 'required|string|max:80',
            'phone' => 'required|string|max:32',
            'note' => 'nullable|string|max:200',
        ]);

        return response()->json(Craftsman::create($data), 201);
    }

    public function alerts(Request $r)
    {
        $q = Alert::where('building_id', $this->buildingId($r));

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
            'building_id' => $this->buildingId($r),
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

    /// Opening cash balance for [year]. Uses an explicitly-stored opening if one
    /// exists; otherwise carries forward = genesis opening + net (revenue −
    /// expenses) of all prior years, so cash isn't reset to zero every January.
    /// Shared by the dashboard summary and the year-transfer screen.
    private function openingBalance(?int $buildingId, int $year, $payments, $expenses): int
    {
        $stored = YearSummary::where('building_id', $buildingId)->where('year', $year)->value('opening_balance');
        if ($stored !== null) {
            return (int) $stored;
        }
        $genesisYear = (int) (YearSummary::where('building_id', $buildingId)->min('year') ?? $year);
        $genesisOpening = (int) (YearSummary::where('building_id', $buildingId)->where('year', $genesisYear)->value('opening_balance') ?? 0);
        $priorRev = (int) $payments->filter(fn ($p) => $p->year >= $genesisYear && $p->year < $year)->sum('amount');
        $priorExp = (int) $expenses->filter(function ($e) use ($genesisYear, $year) {
            $y = Carbon::parse($e->date)->year;

            return $y >= $genesisYear && $y < $year;
        })->sum('amount');

        return $genesisOpening + $priorRev - $priorExp;
    }

    /// Year-transfer (الترحيل السنوي) data: opening balance + a LIVE 12-month grid
    /// of paid-vs-expected. Computed from real payments/units so it never goes
    /// stale (the stored `months` JSON did, and only held a partial set).
    public function yearSummary(Request $r)
    {
        $bk = $this->bk($r);
        $year = (int) ($r->query('year') ?: now()->year);

        $payments = Payment::where('building_id', $this->buildingId($r))->get(['amount', 'month', 'year']);
        $expenses = Expense::where('building_id', $this->buildingId($r))->get(['amount', 'date']);
        // Expected monthly collection = sum of active (non-vacant) unit dues.
        $monthlyExpected = (int) Unit::where('building_id', $this->buildingId($r))
            ->where('status', '!=', 'vacant')->sum('sub');

        $months = [];
        for ($m = 0; $m < 12; $m++) {
            $paid = (int) $payments->where('year', $year)->where('month', $m)->sum('amount');
            $months[] = ['m' => $m, 'paid' => $paid, 'total' => $monthlyExpected];
        }

        return response()->json([
            'year' => $year,
            'opening_balance' => $this->openingBalance($this->buildingId($r), $year, $payments, $expenses),
            'months' => $months,
        ]);
    }
}
