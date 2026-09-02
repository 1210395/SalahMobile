<?php

namespace Tests\Feature;

use App\Models\Building;
use App\Models\EmailCode;
use App\Models\JoinRequest;
use App\Models\Payment;
use App\Models\Unit;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class AmaratiOverhaulTest extends TestCase
{
    use RefreshDatabase;

    /// A residential building (currency USD) + an admin to act as.
    private function seedBuilding(string $currency = 'USD'): Building
    {
        return Building::create([
            'key' => 'residential', 'name' => 'عمارة الاختبار', 'address' => 'عنوان',
            'type' => 'سكني', 'subscription' => 40, 'currency' => $currency,
            'floors' => 6, 'units_count' => 12, 'exchange_rate' => 3.75,
            'elevator_fee' => 15, 'summary' => [],
        ]);
    }

    private function admin(): User
    {
        return User::create([
            'name' => 'مدير', 'email' => 'admin@test.app',
            'password' => Hash::make('password'), 'role' => 'admin',
            'building_key' => 'residential',
        ]);
    }

    private function makeUnit(array $attrs = []): Unit
    {
        $attrs = array_merge([
            'building_key' => 'residential', 'ext_id' => 'A1', 'no' => '101',
            'floor' => 1, 'resident' => 'ساكن', 'kind' => 'مالك', 'phone' => '—',
            'sub' => 40, 'status' => 'ok', 'balance' => 0, 'payer' => 'الساكن',
        ], $attrs);
        // Derived ledger: the intended `balance` is the opening; with no
        // billing_start there is no monthly accrual, so derived balance = opening
        // + payments (mirrors how a test unit is meant to behave).
        $attrs['opening_balance'] ??= $attrs['balance'];

        return Unit::create($attrs);
    }

    /// A commercial building + its own admin — for cross-tenant (IDOR) tests.
    private function seedCommercial(): Building
    {
        Building::create([
            'key' => 'commercial', 'name' => 'مجمع تجاري', 'address' => 'عنوان',
            'type' => 'تجاري', 'subscription' => 80, 'currency' => 'USD',
            'floors' => 3, 'units_count' => 5, 'exchange_rate' => 3.75,
            'elevator_fee' => 0, 'summary' => [],
        ]);

        return Building::where('key', 'commercial')->first();
    }

    private function commercialAdmin(): User
    {
        return User::create([
            'name' => 'مدير تجاري', 'email' => 'cadmin@test.app',
            'password' => Hash::make('password'), 'role' => 'admin',
            'building_key' => 'commercial',
        ]);
    }

    // ─────────────── Authorization / cross-tenant (IDOR) ───────────────

    public function test_resident_reads_are_scoped_and_never_leak_login_codes(): void
    {
        // A resident must NOT see other units (nor any login code — a credential),
        // other units' payments, building expenses, or the worker roster.
        $this->seedBuilding();
        $admin = $this->admin();
        $this->makeUnit(['no' => '101']);
        $this->makeUnit(['no' => '202']);
        $me = User::create([
            'name' => 'ساكن', 'phone' => '0590', 'role' => 'resident',
            'building_key' => 'residential', 'unit_no' => '101', 'login_code' => 'MYCODE1234',
        ]);
        // a neighbour on 202 with their own code
        User::create([
            'name' => 'جار', 'phone' => '0591', 'role' => 'resident',
            'building_key' => 'residential', 'unit_no' => '202', 'login_code' => 'NEIGHBOUR99',
        ]);
        foreach (['101', '202'] as $no) {
            Payment::create([
                'building_key' => 'residential', 'unit_no' => $no, 'name' => 'x', 'amount' => 50,
                'currency' => 'USD', 'original_amount' => 50, 'exchange_rate' => 1, 'kind' => 'k',
                'month' => 0, 'year' => 2026, 'date' => '2026-01-05', 'method' => 'نقداً',
            ]);
        }
        $this->actingAs($admin, 'sanctum')->postJson('/api/expenses', ['cat' => 'x', 'supplier' => 'y', 'amount' => 10, 'date' => '2026-01-01']);
        $this->actingAs($admin, 'sanctum')->postJson('/api/workers', ['name' => 'w', 'phone' => '0', 'cycle' => 'شهري', 'amount' => 100]);

        // Resident reads:
        $units = $this->actingAs($me, 'sanctum')->getJson('/api/units')->json();
        $this->assertCount(1, $units); // only their own unit
        $this->assertSame('101', $units[0]['no']);
        $unitsJson = json_encode($units);
        $this->assertStringNotContainsString('NEIGHBOUR99', $unitsJson); // no other code
        $this->assertStringNotContainsString('MYCODE1234', $unitsJson);  // not even their own

        $pays = $this->actingAs($me, 'sanctum')->getJson('/api/payments')->json();
        $this->assertCount(1, $pays); // only their unit's payment
        $this->assertSame('101', $pays[0]['unit_no']);

        $this->assertCount(0, $this->actingAs($me, 'sanctum')->getJson('/api/expenses')->json());
        $this->assertCount(0, $this->actingAs($me, 'sanctum')->getJson('/api/workers')->json());
        $this->assertCount(0, $this->actingAs($me, 'sanctum')->getJson('/api/parking')->json());

        // Admin still sees everything + login codes.
        $adminUnits = $this->actingAs($admin, 'sanctum')->getJson('/api/units')->json();
        $this->assertCount(2, $adminUnits);
        $this->assertStringContainsString('MYCODE1234', json_encode($adminUnits));
    }

    public function test_building_id_is_auto_populated_from_building_key(): void
    {
        // The BelongsToBuilding trait must set building_id from building_key on
        // create, and scoping now runs on the FK.
        $b = $this->seedBuilding(); // residential
        $unit = $this->makeUnit(['no' => '101']); // created with building_key only
        $this->assertSame($b->id, (int) $unit->fresh()->building_id);

        $pay = Payment::create([
            'building_key' => 'residential', 'unit_no' => '101', 'name' => 'x', 'amount' => 10,
            'currency' => 'USD', 'original_amount' => 10, 'exchange_rate' => 1, 'kind' => 'k',
            'month' => 0, 'year' => 2026, 'date' => '2026-01-05', 'method' => 'نقداً',
        ]);
        $this->assertSame($b->id, (int) $pay->fresh()->building_id);

        // Admin list scoping (now by building_id) still returns the row.
        $units = $this->actingAs($this->admin(), 'sanctum')->getJson('/api/units')->json();
        $this->assertCount(1, $units);
    }

    public function test_resident_cannot_take_over_a_building_via_setup(): void
    {
        // A resident assigned to a manager's building must NOT be able to call
        // building/setup and become its admin (privilege escalation).
        $b = $this->seedBuilding();
        $resident = User::create([
            'name' => 'ساكن', 'phone' => '0590', 'role' => 'resident',
            'building_id' => $b->id, 'building_key' => 'residential', 'unit_no' => '101',
        ]);

        $this->actingAs($resident, 'sanctum')->postJson('/api/building/setup', [
            'btype' => 'residential', 'name' => 'اختطاف', 'address' => 'x', 'floors' => 5, 'units_count' => 10,
        ])->assertStatus(403);

        $this->assertSame('resident', $resident->fresh()->role); // still a resident
        $this->assertSame('عمارة الاختبار', $b->fresh()->name);   // building unchanged
    }

    public function test_two_managers_each_create_their_own_building_no_already_managed(): void
    {
        // Multi-building: a second manager setting up the SAME type must get their
        // OWN building, never a 403 'already managed'.
        $setup = function (string $email, string $name) {
            $tok = $this->postJson('/api/auth/register', [
                'name' => $name, 'email' => $email, 'password' => 'secret123',
            ])->json('token');
            $u = User::where('email', $email)->first();
            $this->actingAs($u, 'sanctum')->postJson('/api/subscription/activate', ['btype' => 'residential'])->assertOk();

            return $this->actingAs($u, 'sanctum')->postJson('/api/building/setup', [
                'btype' => 'residential', 'name' => $name, 'address' => 'ع', 'floors' => 5, 'units_count' => 10,
            ]);
        };

        $a = $setup('a@mgr.app', 'مبنى أ');
        $a->assertOk();
        $b = $setup('b@mgr.app', 'مبنى ب');
        $b->assertOk(); // ← the bug: this used to 403 'already managed'

        $bidA = (int) $a->json('building.id');
        $bidB = (int) $b->json('building.id');
        $this->assertNotSame($bidA, $bidB); // two distinct buildings
        $this->assertSame('admin', User::where('email', 'a@mgr.app')->first()->role);
        $this->assertSame($bidA, (int) User::where('email', 'a@mgr.app')->first()->building_id);
        $this->assertSame($bidB, (int) User::where('email', 'b@mgr.app')->first()->building_id);

        // Each admin's data is isolated: A adds a unit; B must not see it.
        $ua = User::where('email', 'a@mgr.app')->first();
        $ub = User::where('email', 'b@mgr.app')->first();
        $this->actingAs($ua, 'sanctum')->postJson('/api/units', ['no' => 'A1', 'floor' => 1, 'sub' => 40, 'status' => 'ok'])->assertCreated();
        $this->assertCount(1, $this->actingAs($ua, 'sanctum')->getJson('/api/units')->json());
        $this->assertCount(0, $this->actingAs($ub, 'sanctum')->getJson('/api/units')->json()); // isolated
    }

    public function test_resident_cannot_create_a_payment(): void
    {
        $this->seedBuilding();
        $this->makeUnit(['no' => '101']);
        $resident = User::create([
            'name' => 'ساكن', 'phone' => '0590', 'role' => 'resident',
            'building_key' => 'residential', 'unit_no' => '101',
        ]);

        $this->actingAs($resident, 'sanctum')->postJson('/api/payments', [
            'unit_no' => '101', 'amount' => 100, 'kind' => 'اشتراك', 'month' => 0,
            'year' => 2026, 'date' => '2026-01-05', 'method' => 'نقداً',
        ])->assertStatus(403);
    }

    public function test_admin_cannot_delete_another_buildings_payment(): void
    {
        // A residential admin must not delete a commercial building's payment.
        $this->seedBuilding();
        $this->seedCommercial();
        $resAdmin = $this->admin();
        $commPay = Payment::create([
            'building_key' => 'commercial', 'unit_no' => 'S1', 'name' => 'محل',
            'amount' => 300, 'currency' => 'USD', 'original_amount' => 300,
            'exchange_rate' => 1, 'kind' => 'اشتراك', 'month' => 0, 'year' => 2026,
            'date' => '2026-01-05', 'method' => 'نقداً',
        ]);

        // Even naming ?btype=commercial, a residential admin is blocked by the
        // building_key ownership check on the bound model.
        $this->actingAs($resAdmin, 'sanctum')
            ->deleteJson("/api/payments/{$commPay->id}?btype=residential")
            ->assertStatus(403);
        $this->assertDatabaseHas('payments', ['id' => $commPay->id]);
    }

    public function test_admin_cannot_edit_another_buildings_unit(): void
    {
        $this->seedBuilding();
        $this->seedCommercial();
        $commUnit = Unit::create([
            'building_key' => 'commercial', 'ext_id' => 'C1', 'no' => 'S1',
            'floor' => 0, 'resident' => 'محل', 'kind' => 'مالك', 'phone' => '—',
            'sub' => 80, 'status' => 'ok', 'balance' => 0, 'payer' => 'الساكن',
        ]);

        $this->actingAs($this->admin(), 'sanctum')
            ->putJson("/api/units/{$commUnit->id}?btype=residential", [
                'no' => 'HACK', 'floor' => 0, 'sub' => 1, 'status' => 'ok',
            ])->assertStatus(403);
        $this->assertSame('S1', $commUnit->fresh()->no);
    }

    public function test_note_mark_read_across_buildings_is_forbidden(): void
    {
        $this->seedBuilding();
        $this->seedCommercial();
        $commNote = \App\Models\Note::create([
            'building_key' => 'commercial', 'name' => 'ساكن', 'body' => 'رسالة', 'status' => 'new',
        ]);

        $this->actingAs($this->admin(), 'sanctum')
            ->postJson("/api/notes/{$commNote->id}/read?btype=residential")
            ->assertStatus(403);
    }

    // ─────────────── Money bounds ───────────────

    public function test_update_payment_rejects_oversized_value(): void
    {
        $this->seedBuilding();
        $unit = $this->makeUnit(['no' => '101']);
        $pay = Payment::create([
            'building_key' => 'residential', 'unit_no' => '101', 'name' => 'ساكن',
            'amount' => 100, 'currency' => 'USD', 'original_amount' => 100,
            'exchange_rate' => 1, 'kind' => 'اشتراك', 'month' => 0, 'year' => 2026,
            'date' => '2026-01-05', 'method' => 'نقداً',
        ]);
        $unit->increment('balance', 100);
        $admin = $this->admin();

        $this->actingAs($admin, 'sanctum')
            ->putJson("/api/payments/{$pay->id}", ['amount' => 9999999999])
            ->assertStatus(422);
        // A hugely-negative value is also rejected (INT underflow guard).
        $this->actingAs($admin, 'sanctum')
            ->putJson("/api/payments/{$pay->id}", ['amount' => -9999999999])
            ->assertStatus(422);
        $this->assertSame(100, (int) $pay->fresh()->amount);
    }

    // ─────────────── Summary / dues ───────────────

    public function test_vacant_units_are_excluded_from_dues(): void
    {
        $this->seedBuilding();
        $this->makeUnit(['no' => '101', 'status' => 'late', 'balance' => -200]);
        $this->makeUnit(['no' => '102', 'status' => 'vacant', 'balance' => -999]);

        $sum = $this->actingAs($this->admin(), 'sanctum')->getJson('/api/summary')->json();
        // Only the occupied late unit's 200 counts; the vacant -999 is ignored.
        $this->assertSame(200, (int) $sum['due']);
    }

    public function test_global_report_balance_includes_the_opening(): void
    {
        // The platform-owner balance must be cash on hand (opening + collected −
        // expenses), consistent with the dashboard — not just collected−expenses.
        $this->seedBuilding();
        \App\Models\YearSummary::create([
            'building_key' => 'residential', 'year' => 2026, 'opening_balance' => 1000, 'months' => [],
        ]);
        $admin = $this->admin();
        $this->makeUnit(['no' => '101']);
        $this->actingAs($admin, 'sanctum')->postJson('/api/payments', [
            'unit_no' => '101', 'amount' => 500, 'kind' => 'k', 'month' => 0, 'year' => 2026, 'date' => '2026-01-05', 'method' => 'x',
        ])->assertCreated();
        $this->actingAs($admin, 'sanctum')->postJson('/api/expenses', [
            'cat' => 'x', 'supplier' => 'y', 'amount' => 300, 'date' => '2026-02-01',
        ])->assertCreated();

        $super = User::create([
            'name' => 'مالك', 'email' => 'sa@test.app', 'password' => Hash::make('password'), 'role' => 'superadmin',
        ]);
        $report = $this->actingAs($super, 'sanctum')->getJson('/api/reports/global')->json();
        $res = collect($report['buildings'])->firstWhere('key', 'residential');
        $this->assertSame(1200, (int) $res['balance']); // 1000 + 500 - 300
    }

    public function test_year_summary_months_are_computed_live_with_all_twelve(): void
    {
        // The year-transfer grid must reflect real payments across all 12 months,
        // not a stale/partial stored JSON.
        $this->seedBuilding();
        $admin = $this->admin();
        $this->makeUnit(['no' => '101', 'sub' => 100]);
        $this->actingAs($admin, 'sanctum')->postJson('/api/payments', [
            'unit_no' => '101', 'amount' => 5000, 'kind' => 'k', 'month' => 7, 'year' => 2026, 'date' => '2026-08-01', 'method' => 'x',
        ])->assertCreated();

        $ys = $this->actingAs($admin, 'sanctum')->getJson('/api/year-summary?year=2026')->json();
        $this->assertCount(12, $ys['months']); // full year, not partial
        $m7 = collect($ys['months'])->firstWhere('m', 7);
        $this->assertSame(5000, (int) $m7['paid']); // reflects the live payment
        $this->assertSame(100, (int) $m7['total']); // expected = active-unit dues
    }

    public function test_settings_reject_a_non_hex_colour(): void
    {
        $this->seedBuilding();
        // Platform branding is super-admin only now — a building manager can't
        // rebrand the whole product for every other building.
        $admin = $this->admin();
        $this->actingAs($admin, 'sanctum')->putJson('/api/settings', ['primary' => '#123456'])->assertStatus(403);

        $super = User::create([
            'name' => 'عام', 'email' => 'super@test.app', 'password' => Hash::make('password'), 'role' => 'superadmin',
        ]);
        $this->actingAs($super, 'sanctum')->putJson('/api/settings', ['primary' => 'not-a-hex'])->assertStatus(422);
        $this->actingAs($super, 'sanctum')->putJson('/api/settings', ['primary' => '#123456'])->assertOk();
    }

    public function test_year_balance_carries_forward_to_the_next_year(): void
    {
        // The next year's opening must carry the prior year's closing balance —
        // cash must not reset to zero every January.
        $this->seedBuilding();
        $admin = $this->admin();
        \App\Models\YearSummary::create([
            'building_key' => 'residential', 'year' => 2026, 'opening_balance' => 1000, 'months' => [],
        ]);
        $this->makeUnit(['no' => '101']);
        // 2026: +500 revenue, -300 expense → closing 1200.
        $this->actingAs($admin, 'sanctum')->postJson('/api/payments', [
            'unit_no' => '101', 'amount' => 500, 'kind' => 'k', 'month' => 0, 'year' => 2026, 'date' => '2026-01-05', 'method' => 'x',
        ])->assertCreated();
        $this->actingAs($admin, 'sanctum')->postJson('/api/expenses', [
            'cat' => 'x', 'supplier' => 'y', 'amount' => 300, 'date' => '2026-02-01',
        ])->assertCreated();

        // 2026 explicit opening is unchanged.
        $s2026 = $this->actingAs($admin, 'sanctum')->getJson('/api/summary?year=2026')->json();
        $this->assertSame(1200, (int) $s2026['balance']); // 1000 + 500 - 300

        // 2027 has no stored opening → opens at 2026's closing (1200).
        $this->actingAs($admin, 'sanctum')->postJson('/api/payments', [
            'unit_no' => '101', 'amount' => 200, 'kind' => 'k', 'month' => 0, 'year' => 2027, 'date' => '2027-01-05', 'method' => 'x',
        ])->assertCreated();
        $s2027 = $this->actingAs($admin, 'sanctum')->getJson('/api/summary?year=2027')->json();
        $this->assertSame(1400, (int) $s2027['balance']); // opening 1200 + 200 - 0
    }

    public function test_summary_balance_is_opening_plus_revenue_minus_expenses(): void
    {
        $this->seedBuilding();
        $admin = $this->admin();
        \App\Models\YearSummary::create([
            'building_key' => 'residential', 'year' => 2026,
            'opening_balance' => 1000, 'months' => [],
        ]);
        $this->makeUnit(['no' => '101']);
        $this->actingAs($admin, 'sanctum')->postJson('/api/payments', [
            'unit_no' => '101', 'amount' => 500, 'kind' => 'اشتراك', 'month' => 0,
            'year' => 2026, 'date' => '2026-01-05', 'method' => 'نقداً',
        ])->assertCreated();
        $this->actingAs($admin, 'sanctum')->postJson('/api/expenses', [
            'cat' => 'صيانة', 'supplier' => 'مورّد', 'amount' => 300, 'date' => '2026-02-01',
        ])->assertCreated();

        $sum = $this->actingAs($admin, 'sanctum')->getJson('/api/summary?year=2026')->json();
        $this->assertSame(1200, (int) $sum['balance']); // 1000 + 500 - 300
    }

    // ───────── #9/#10 — dues split into this year vs carried over ─────────

    // A unit billed from Jan of LAST year owes 12 months of carry-over plus every
    // month elapsed this year (inclusive accrual, #21/#25).
    public function test_summary_splits_dues_into_carried_over_and_this_year(): void
    {
        $this->seedBuilding();
        $year = (int) now()->year;
        $this->makeUnit([
            'no' => '101', 'sub' => 100, 'balance' => 0,
            'billing_start' => ($year - 1).'-01-01',
        ]);

        $sum = $this->actingAs($this->admin(), 'sanctum')
            ->getJson('/api/summary?year='.$year)->json();

        $thisYear = (int) now()->month * 100;   // Jan…current month, inclusive
        $this->assertSame(1200, (int) $sum['duePrev']);
        $this->assertSame($thisYear, (int) $sum['dueYear']);
        $this->assertSame(1200 + $thisYear, (int) $sum['due']);
    }

    // Payments settle the OLDEST debt first: clearing last year's 1200 leaves only
    // this year's own charges standing. The debt here is unpaid SUBSCRIPTION, so
    // it takes a subscription payment — a "ذمم" line settles the ذمم pot, which
    // this unit does not have (the two pots never net against each other).
    public function test_a_payment_this_year_clears_the_carried_over_dues_first(): void
    {
        $this->seedBuilding();
        $admin = $this->admin();
        $year = (int) now()->year;
        $this->makeUnit([
            'no' => '101', 'sub' => 100, 'balance' => 0,
            'billing_start' => ($year - 1).'-01-01',
        ]);
        $this->actingAs($admin, 'sanctum')->postJson('/api/payments', [
            'unit_no' => '101', 'amount' => 1200, 'kind' => 'دفعة شهرية', 'month' => 0,
            'year' => $year, 'date' => now()->toDateString(), 'method' => 'نقداً',
        ])->assertCreated();

        $sum = $this->actingAs($admin, 'sanctum')->getJson('/api/summary?year='.$year)->json();

        $thisYear = (int) now()->month * 100;
        $this->assertSame(0, (int) $sum['duePrev']);
        $this->assertSame($thisYear, (int) $sum['dueYear']);
        $this->assertSame($thisYear, (int) $sum['due']);
    }

    // The cash carried into the year is reported on its own (مرحل من السنوات السابقة).
    public function test_summary_reports_the_cash_carried_over_from_previous_years(): void
    {
        $this->seedBuilding();
        \App\Models\YearSummary::create([
            'building_key' => 'residential', 'year' => 2026,
            'opening_balance' => 800, 'months' => [],
        ]);

        $sum = $this->actingAs($this->admin(), 'sanctum')->getJson('/api/summary?year=2026')->json();
        $this->assertSame(800, (int) $sum['carried']);
        $this->assertSame(800, (int) $sum['balance']); // nothing else moved yet
    }

    // ─────────────── Redeem code round-trip ───────────────

    // Vacating then un-vacating a unit must NOT corrupt its ledger. Nulling
    // billing_start on vacate used to make the round-trip resurface old payments as
    // a phantom credit (or silently erase accrued debt).
    public function test_vacate_then_unvacate_preserves_the_ledger(): void
    {
        $this->seedBuilding();
        $admin = $this->admin();
        $year = (int) now()->year;
        // Billed from Jan this year; the accrued charge is settled to exactly 0.
        $unit = $this->makeUnit(['no' => '101', 'sub' => 100, 'balance' => 0,
            'billing_start' => $year.'-01-01']);
        $months = (int) now()->month; // Jan..now inclusive
        $this->actingAs($admin, 'sanctum')->postJson('/api/payments', [
            'unit_no' => '101', 'amount' => $months * 100, 'kind' => 'ذمم', 'month' => 0,
            'year' => $year, 'date' => now()->toDateString(), 'method' => 'نقداً',
        ])->assertCreated();
        $this->assertSame(0, (int) $unit->fresh()->balance); // settled

        // Vacate, then bring it back.
        $this->actingAs($admin, 'sanctum')->putJson("/api/units/{$unit->id}", [
            'no' => '101', 'floor' => 1, 'kind' => 'شاغر', 'status' => 'vacant', 'sub' => 100,
        ])->assertOk();
        $this->actingAs($admin, 'sanctum')->putJson("/api/units/{$unit->id}", [
            'no' => '101', 'floor' => 1, 'kind' => 'مالك', 'sub' => 100,
        ])->assertOk();

        // Still settled — not a phantom +N00 credit, not erased debt.
        $this->assertSame(0, (int) $unit->fresh()->balance);
        $this->assertSame('ok', $unit->fresh()->status);
    }

    // Renaming a unit must cascade to EVERYTHING keyed by its number, or those
    // records dangle (and a private notice to old "101" resurfaces for a new "101").
    public function test_renaming_a_unit_cascades_parking_and_alerts(): void
    {
        $this->seedBuilding();
        $admin = $this->admin();
        $unit = $this->makeUnit(['no' => '101']);
        \App\Models\ParkingSpot::create(['building_key' => 'residential', 'no' => 'P1',
            'status' => 'مشغول', 'unit_no' => '101']);
        \App\Models\Alert::create(['building_key' => 'residential', 'type' => 'notice',
            'icon' => 'bell', 'tone' => 'navy', 'title' => 'خاص', 'body' => 'رسالة',
            'time_label' => 'الآن', 'channel' => 'internal', 'target' => '101']);

        $this->actingAs($admin, 'sanctum')->putJson("/api/units/{$unit->id}", [
            'no' => '202', 'floor' => 1, 'sub' => (int) $unit->sub,
        ])->assertOk();

        $this->assertDatabaseHas('parking_spots', ['no' => 'P1', 'unit_no' => '202']);
        $this->assertDatabaseHas('alerts', ['title' => 'خاص', 'target' => '202']);
        $this->assertDatabaseMissing('parking_spots', ['unit_no' => '101']);
        $this->assertDatabaseMissing('alerts', ['target' => '101']);
    }

    // Residents must not read building-wide finances.
    public function test_a_resident_cannot_read_the_building_summary(): void
    {
        $this->seedBuilding();
        $admin = $this->admin();
        $this->addRenter($admin, '101', '+970599666000');
        $token = $this->postJson('/api/auth/login',
            ['phone' => '+970599666000', 'password' => 'secret6789'])->json('token');

        // addRenter() used actingAs(); forget the sticky test guard so the bearer
        // token below actually resolves as the resident, not the admin.
        $this->app['auth']->forgetGuards();
        $this->withToken($token)->getJson('/api/summary')->assertStatus(403);
        $this->app['auth']->forgetGuards();
        $this->withToken($token)->getJson('/api/year-summary?year=2026')->assertStatus(403);
    }

    // ───────── Tenant turnover: the old login must stop working ─────────

    private function addRenter(User $admin, string $no, string $phone, string $pw = 'secret6789'): array
    {
        return $this->actingAs($admin, 'sanctum')->postJson('/api/units', [
            'no' => $no, 'floor' => 1, 'resident' => 'ساكن', 'phone' => $phone,
            'sub' => 100, 'status' => 'ok', 'password' => $pw,
        ])->json();
    }

    // Marking a unit vacant = the tenant moved out. Their login must die.
    public function test_vacating_a_unit_disables_the_tenant_login(): void
    {
        $this->seedBuilding();
        $admin = $this->admin();
        $unit = $this->addRenter($admin, '101', '+970599111000');
        $this->postJson('/api/auth/login', ['phone' => '+970599111000', 'password' => 'secret6789'])->assertOk();

        $this->actingAs($admin, 'sanctum')->putJson("/api/units/{$unit['id']}", [
            'no' => '101', 'floor' => 1, 'kind' => 'شاغر', 'status' => 'vacant', 'sub' => 100,
        ])->assertOk();

        // Neither the password nor an OTP can sign the moved-out tenant back in.
        $this->postJson('/api/auth/login', ['phone' => '+970599111000', 'password' => 'secret6789'])
            ->assertStatus(422);
        $req = $this->postJson('/api/auth/request-otp', ['phone' => '+970599111000'])->json();
        $this->postJson('/api/auth/verify-otp',
            ['phone' => '+970599111000', 'code' => $req['dev_code'] ?? '000000'])->assertStatus(422);

        // Un-vacating + a new password re-enables the same account.
        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/units/{$unit['id']}/password", ['password' => 'again6'])->assertOk();
        $this->postJson('/api/auth/login', ['phone' => '+970599111000', 'password' => 'again6'])->assertOk();
    }

    // Replacing a tenant disables the previous one's login (a stale credential
    // into the building is exactly what we're closing).
    public function test_reassigning_a_unit_disables_the_previous_tenant(): void
    {
        $this->seedBuilding();
        $admin = $this->admin();
        $this->addRenter($admin, '101', '+970599222000'); // tenant A
        $this->postJson('/api/auth/login', ['phone' => '+970599222000', 'password' => 'secret6789'])->assertOk();

        // Tenant B onto the same unit via /residents.
        $this->actingAs($admin, 'sanctum')->postJson('/api/residents', [
            'name' => 'تينانت B', 'phone' => '+970599333000', 'unit_no' => '101', 'password' => 'secret6789',
        ])->assertCreated();

        // A is out; B is in.
        $this->postJson('/api/auth/login', ['phone' => '+970599222000', 'password' => 'secret6789'])
            ->assertStatus(422);
        $this->postJson('/api/auth/login', ['phone' => '+970599333000', 'password' => 'secret6789'])->assertOk();
    }

    // A disabled tenant's live session is revoked immediately, not just future logins.
    // (Uses real bearer tokens throughout — actingAs() would set a sticky test user
    // that masks the very token check we're asserting.)
    public function test_disabling_revokes_the_tenants_active_token(): void
    {
        $this->seedBuilding();
        $admin = $this->admin();
        $unit = $this->addRenter($admin, '101', '+970599444000');
        $adminToken = $this->postJson('/api/auth/login',
            ['email' => 'admin@test.app', 'password' => 'password'])->json('token');
        $token = $this->postJson('/api/auth/login',
            ['phone' => '+970599444000', 'password' => 'secret6789'])->json('token');

        // addRenter() used actingAs(), whose sticky test user would mask the bearer
        // token below — forget the guards so /me really resolves via the token.
        $this->app['auth']->forgetGuards();
        $this->withToken($token)->getJson('/api/me')->assertOk();

        $this->app['auth']->forgetGuards();
        $this->withToken($adminToken)->putJson("/api/units/{$unit['id']}", [
            'no' => '101', 'floor' => 1, 'kind' => 'شاغر', 'status' => 'vacant', 'sub' => 100,
        ])->assertOk();

        $this->app['auth']->forgetGuards();
        $this->withToken($token)->getJson('/api/me')->assertStatus(401); // session cut off
    }

    // ───────── Renter login: created WITH the unit, atomically ─────────

    // Adding a renter creates their login in the SAME request as the unit.
    public function test_creating_a_unit_with_a_password_creates_the_renter_login(): void
    {
        $this->seedBuilding();
        $this->actingAs($this->admin(), 'sanctum')->postJson('/api/units', [
            'no' => '101', 'floor' => 1, 'resident' => 'سارة', 'kind' => 'مستأجر',
            'phone' => '+970599111222', 'sub' => 100, 'status' => 'ok', 'password' => 'secret6789',
        ])->assertCreated();

        $this->assertDatabaseHas('users', ['unit_no' => '101', 'role' => 'resident']);
        $this->postJson('/api/auth/login', ['phone' => '+970599111222', 'password' => 'secret6789'])
            ->assertOk()->assertJsonPath('user.role', 'resident');
    }

    // A phone already in use must leave NOTHING behind — not a half-made unit with
    // no account, which is exactly what two separate requests would have produced.
    public function test_a_duplicate_phone_creates_neither_the_unit_nor_the_account(): void
    {
        $this->seedBuilding();
        $admin = $this->admin();
        $this->actingAs($admin, 'sanctum')->postJson('/api/units', [
            'no' => '101', 'floor' => 1, 'resident' => 'الأول', 'phone' => '+970599111222',
            'sub' => 100, 'status' => 'ok', 'password' => 'secret6789',
        ])->assertCreated();

        $this->actingAs($admin, 'sanctum')->postJson('/api/units', [
            'no' => '102', 'floor' => 1, 'resident' => 'الثاني', 'phone' => '+970599111222',
            'sub' => 100, 'status' => 'ok', 'password' => 'secret6789',
        ])->assertStatus(422);

        $this->assertDatabaseMissing('units', ['no' => '102']); // no orphaned unit
    }

    // A login needs a phone: it IS the username.
    public function test_creating_a_unit_with_a_password_but_no_phone_is_rejected(): void
    {
        $this->seedBuilding();
        $this->actingAs($this->admin(), 'sanctum')->postJson('/api/units', [
            'no' => '101', 'floor' => 1, 'resident' => 'بلا هاتف', 'sub' => 100,
            'status' => 'ok', 'password' => 'secret6789',
        ])->assertStatus(422);

        $this->assertDatabaseMissing('units', ['no' => '101']);
    }

    // The phone IS the renter's username — the add form says so. Editing it on the
    // unit must follow through to the login, or the unit shows the new number while
    // the renter can still only sign in with the old one.
    public function test_editing_a_units_phone_moves_the_renter_login_to_it(): void
    {
        $this->seedBuilding();
        $admin = $this->admin();
        $unit = $this->actingAs($admin, 'sanctum')->postJson('/api/units', [
            'no' => '101', 'floor' => 1, 'resident' => 'سارة', 'phone' => '+970599111222',
            'sub' => 100, 'status' => 'ok', 'password' => 'secret6789',
        ])->json();

        $this->actingAs($admin, 'sanctum')->putJson("/api/units/{$unit['id']}", [
            'no' => '101', 'floor' => 1, 'resident' => 'سارة', 'phone' => '+970599999888',
            'sub' => 100,
        ])->assertOk();

        // The new number signs in; the old one is gone.
        $this->postJson('/api/auth/login', ['phone' => '+970599999888', 'password' => 'secret6789'])
            ->assertOk()->assertJsonPath('user.role', 'resident');
        $this->postJson('/api/auth/login', ['phone' => '+970599111222', 'password' => 'secret6789'])
            ->assertStatus(422);
    }

    public function test_editing_a_unit_to_a_taken_phone_is_rejected(): void
    {
        $this->seedBuilding();
        $admin = $this->admin();
        $this->actingAs($admin, 'sanctum')->postJson('/api/units', [
            'no' => '101', 'floor' => 1, 'resident' => 'الأول', 'phone' => '+970599111222',
            'sub' => 100, 'status' => 'ok', 'password' => 'secret6789',
        ])->assertCreated();
        $second = $this->actingAs($admin, 'sanctum')->postJson('/api/units', [
            'no' => '102', 'floor' => 1, 'resident' => 'الثاني', 'phone' => '+970599333444',
            'sub' => 100, 'status' => 'ok', 'password' => 'secret6789',
        ])->json();

        $this->actingAs($admin, 'sanctum')->putJson("/api/units/{$second['id']}", [
            'no' => '102', 'floor' => 1, 'resident' => 'الثاني', 'phone' => '+970599111222',
            'sub' => 100,
        ])->assertStatus(422);
    }

    // ───────── Renter login: set / reset the password from the unit ─────────

    // A renter could be created before logins were mandatory, and the edit sheet
    // had no password field — so they could never log in at all. Setting a password
    // on such a unit must CREATE the account from the unit's own name + phone.
    public function test_setting_a_password_creates_the_login_for_a_unit_without_one(): void
    {
        $this->seedBuilding();
        $admin = $this->admin();
        $unit = $this->makeUnit(['no' => '101', 'resident' => 'سارة', 'phone' => '+970599111222']);

        $this->assertDatabaseMissing('users', ['unit_no' => '101', 'role' => 'resident']);

        $res = $this->actingAs($admin, 'sanctum')
            ->postJson("/api/units/{$unit->id}/password", ['password' => 'secret6789'])
            ->assertOk();

        $this->assertSame('101', $res->json('unit_no'));
        $this->assertSame(32, strlen((string) $res->json('login_code'))); // a QR to share

        // The renter can now actually sign in with phone + password.
        $this->postJson('/api/auth/login', ['phone' => '+970599111222', 'password' => 'secret6789'])
            ->assertOk()->assertJsonPath('user.role', 'resident');
    }

    // Resetting rotates the QR too, so the admin can share a working one at once.
    public function test_resetting_a_password_replaces_the_old_one_and_reissues_the_qr(): void
    {
        $this->seedBuilding();
        $admin = $this->admin();
        $unit = $this->makeUnit(['no' => '101']);
        $code = $this->actingAs($admin, 'sanctum')->postJson('/api/residents', [
            'name' => 'ساكن', 'phone' => '+970599333444', 'unit_no' => '101', 'password' => 'old123',
        ])->json('login_code');

        $new = $this->actingAs($admin, 'sanctum')
            ->postJson("/api/units/{$unit->id}/password", ['password' => 'new456'])
            ->assertOk()->json('login_code');

        $this->assertNotSame($code, $new);              // fresh QR
        $this->postJson('/api/auth/login', ['phone' => '+970599333444', 'password' => 'old123'])
            ->assertStatus(422);                        // the old password is dead
        $this->postJson('/api/auth/login', ['phone' => '+970599333444', 'password' => 'new456'])
            ->assertOk();
    }

    public function test_setting_a_password_needs_a_phone_and_six_characters(): void
    {
        $this->seedBuilding();
        $admin = $this->admin();
        $noPhone = $this->makeUnit(['no' => '101', 'phone' => '—']);
        $ok = $this->makeUnit(['no' => '102', 'phone' => '+970599555666']);

        // The phone IS the username — without one there is nothing to log in as.
        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/units/{$noPhone->id}/password", ['password' => 'secret6789'])
            ->assertStatus(422);
        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/units/{$ok->id}/password", ['password' => '123'])
            ->assertStatus(422);
    }

    public function test_a_resident_cannot_set_a_password_on_a_unit(): void
    {
        $this->seedBuilding();
        $unit = $this->makeUnit(['no' => '101', 'phone' => '+970599777888']);
        $resident = User::create([
            'name' => 'ساكن', 'phone' => '+970599000111', 'password' => Hash::make('secret6'),
            'role' => 'resident', 'building_key' => 'residential',
        ]);

        $this->actingAs($resident, 'sanctum')
            ->postJson("/api/units/{$unit->id}/password", ['password' => 'hacked'])
            ->assertStatus(403);
    }

    public function test_manager_created_resident_can_redeem_their_code(): void
    {
        $this->seedBuilding();
        $this->makeUnit(['no' => '101']);
        $code = $this->actingAs($this->admin(), 'sanctum')->postJson('/api/residents', [
            'name' => 'ساكن جديد', 'phone' => '+966500009999', 'unit_no' => '101', 'password' => 'secret6789',
        ])->json('login_code');

        $this->assertSame(32, strlen($code));
        $res = $this->postJson('/api/auth/redeem-code', ['code' => $code]);
        $res->assertOk();
        $this->assertNotEmpty($res->json('token'));
        $this->assertSame('resident', $res->json('user.role'));
    }

    // ─────────────── Guard / craftsman / parking CRUD ───────────────

    public function test_guard_save_and_fetch(): void
    {
        $this->seedBuilding();
        $admin = $this->admin();
        $this->actingAs($admin, 'sanctum')->putJson('/api/guard', [
            'name' => 'حارس', 'phone' => '0599', 'fee' => 150,
        ])->assertOk();

        $guard = $this->actingAs($admin, 'sanctum')->getJson('/api/guard')->json();
        $this->assertSame('حارس', $guard['name']);
        $this->assertSame(150, (int) $guard['fee']);
    }

    public function test_craftsman_create_and_list(): void
    {
        $this->seedBuilding();
        $admin = $this->admin();
        $this->actingAs($admin, 'sanctum')->postJson('/api/craftsmen', [
            'name' => 'كهربائي', 'job' => 'كهرباء', 'phone' => '0599',
        ])->assertCreated();

        $list = $this->actingAs($admin, 'sanctum')->getJson('/api/craftsmen')->json();
        $this->assertNotEmpty($list);
        $this->assertSame('كهربائي', $list[0]['name']);
    }

    public function test_parking_crud_and_building_scope(): void
    {
        $this->seedBuilding();
        $this->seedCommercial();
        $admin = $this->admin();
        $spot = $this->actingAs($admin, 'sanctum')->postJson('/api/parking', [
            'no' => 'P1', 'status' => 'مشغول', 'unit_no' => '101',
        ])->assertCreated()->json();

        // Update it.
        $this->actingAs($admin, 'sanctum')
            ->putJson("/api/parking/{$spot['id']}", ['status' => 'شاغر'])
            ->assertOk()->assertJson(['status' => 'شاغر']);

        // A commercial admin cannot delete the residential spot.
        $this->actingAs($this->commercialAdmin(), 'sanctum')
            ->deleteJson("/api/parking/{$spot['id']}?btype=commercial")
            ->assertStatus(403);

        // The owner can.
        $this->actingAs($admin, 'sanctum')
            ->deleteJson("/api/parking/{$spot['id']}")
            ->assertOk();
        $this->assertDatabaseMissing('parking_spots', ['id' => $spot['id']]);
    }

    public function test_assigning_a_unit_unlinks_the_previous_resident(): void
    {
        // A unit has one resident account. Adding a new resident to an occupied
        // unit must unlink the old one so they can't see the new tenant's data.
        $this->seedBuilding();
        $admin = $this->admin();
        $this->makeUnit(['no' => '101']);

        $old = $this->actingAs($admin, 'sanctum')->postJson('/api/residents', [
            'name' => 'قديم', 'phone' => '+966500000011', 'unit_no' => '101', 'password' => 'secret6789',
        ])->json();
        $this->actingAs($admin, 'sanctum')->postJson('/api/residents', [
            'name' => 'جديد', 'phone' => '+966500000022', 'unit_no' => '101', 'password' => 'secret6789',
        ])->assertCreated();

        // The old resident is unlinked; only one account remains on unit 101.
        $this->assertNull(User::find($old['id'])->unit_no);
        $this->assertSame(1, User::where('building_key', 'residential')->where('unit_no', '101')->count());
    }

    public function test_join_approval_unlinks_the_previous_resident(): void
    {
        $this->seedBuilding();
        $admin = $this->admin();
        $this->makeUnit(['no' => '101']);
        $old = User::create([
            'name' => 'قديم', 'phone' => '+966500000033', 'role' => 'resident',
            'building_key' => 'residential', 'unit_no' => '101',
        ]);
        $applicant = User::create([
            'name' => 'جديد', 'phone' => '+966500000044', 'role' => 'resident',
            'building_key' => 'residential',
        ]);
        $jr = JoinRequest::create([
            'building_key' => 'residential', 'user_id' => $applicant->id,
            'name' => 'جديد', 'unit_no' => '101', 'status' => 'pending',
        ]);

        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/join-requests/{$jr->id}/approve")->assertOk();

        $this->assertNull($old->fresh()->unit_no);
        $this->assertSame('101', $applicant->fresh()->unit_no);
    }

    public function test_store_resident_rejects_duplicate_phone(): void
    {
        $this->seedBuilding();
        $admin = $this->admin();
        $this->actingAs($admin, 'sanctum')->postJson('/api/residents', [
            'name' => 'أول', 'phone' => '+966500001234', 'password' => 'secret6789',
        ])->assertCreated();
        $this->actingAs($admin, 'sanctum')->postJson('/api/residents', [
            'name' => 'ثانٍ', 'phone' => '+966500001234', 'password' => 'secret6789',
        ])->assertStatus(422);
    }

    public function test_approving_an_anonymous_join_request_does_not_crash(): void
    {
        // A join request with no user_id (guest) should approve without error and
        // without promoting a phantom user.
        $this->seedBuilding();
        $jr = JoinRequest::create([
            'building_key' => 'residential', 'user_id' => null,
            'name' => 'زائر', 'unit_no' => '101', 'status' => 'pending',
        ]);
        $this->actingAs($this->admin(), 'sanctum')
            ->postJson("/api/join-requests/{$jr->id}/approve")
            ->assertOk()->assertJson(['status' => 'approved']);
    }

    public function test_expense_delete_removes_it(): void
    {
        $this->seedBuilding();
        $admin = $this->admin();
        $exp = $this->actingAs($admin, 'sanctum')->postJson('/api/expenses', [
            'cat' => 'صيانة', 'supplier' => 'مورّد', 'amount' => 100, 'date' => '2026-02-01',
        ])->json();
        $this->actingAs($admin, 'sanctum')->deleteJson("/api/expenses/{$exp['id']}")->assertOk();
        $this->assertDatabaseMissing('expenses', ['id' => $exp['id']]);
    }

    // ─────────────── Edge cases surfaced by the adversarial probe ───────────────

    public function test_oversized_string_field_is_rejected_not_a_500(): void
    {
        // An over-long string must 422 at validation, not overflow the varchar
        // column into a raw MySQL 500.
        $this->seedBuilding();
        $this->actingAs($this->admin(), 'sanctum')->postJson('/api/expenses', [
            'cat' => 'صيانة', 'supplier' => str_repeat('A', 5000), 'amount' => 10, 'date' => '2026-01-01',
        ])->assertStatus(422);
    }

    public function test_negative_expense_amount_is_rejected(): void
    {
        // A negative expense would silently inflate the cash balance.
        $this->seedBuilding();
        $this->actingAs($this->admin(), 'sanctum')->postJson('/api/expenses', [
            'cat' => 'صيانة', 'supplier' => 'مورّد', 'amount' => -999, 'date' => '2026-01-01',
        ])->assertStatus(422);
    }

    public function test_cannot_delete_a_unit_with_payments_or_a_resident(): void
    {
        $this->seedBuilding();
        $admin = $this->admin();
        // Unit with a payment → delete blocked (422).
        $withPay = $this->makeUnit(['no' => '101']);
        Payment::create([
            'building_key' => 'residential', 'unit_no' => '101', 'name' => 'x', 'amount' => 50,
            'currency' => 'USD', 'original_amount' => 50, 'exchange_rate' => 1, 'kind' => 'k',
            'month' => 0, 'year' => 2026, 'date' => '2026-01-05', 'method' => 'نقداً',
        ]);
        $this->actingAs($admin, 'sanctum')->deleteJson("/api/units/{$withPay->id}")->assertStatus(422);
        $this->assertDatabaseHas('units', ['id' => $withPay->id]);

        // Unit with a linked resident → delete blocked (422).
        $withRes = $this->makeUnit(['no' => '102']);
        User::create([
            'name' => 'ساكن', 'phone' => '0599', 'role' => 'resident',
            'building_key' => 'residential', 'unit_no' => '102',
        ]);
        $this->actingAs($admin, 'sanctum')->deleteJson("/api/units/{$withRes->id}")->assertStatus(422);

        // An empty unit (no payments, no resident) still deletes cleanly.
        $empty = $this->makeUnit(['no' => '103']);
        $this->actingAs($admin, 'sanctum')->deleteJson("/api/units/{$empty->id}")->assertOk();
        $this->assertDatabaseMissing('units', ['id' => $empty->id]);
    }

    public function test_paying_off_a_late_unit_clears_its_status_and_stops_alerts(): void
    {
        // A resident who pays in full must stop showing as 'late' AND stop
        // generating an overdue alert — status must track the balance.
        $this->seedBuilding();
        $admin = $this->admin();
        // The unit's debt is an entered ذمة, so it is settled from the ذمم pot.
        $unit = $this->makeUnit(['no' => '101', 'status' => 'late', 'balance' => -100]);

        $this->actingAs($admin, 'sanctum')->postJson('/api/payments', [
            'unit_no' => '101', 'amount' => 100, 'kind' => 'ذمم', 'month' => 0,
            'year' => 2026, 'date' => '2026-01-05', 'method' => 'نقداً',
        ])->assertCreated();

        $fresh = $unit->fresh();
        $this->assertSame(0, (int) $fresh->balance);
        $this->assertSame('ok', $fresh->status); // no longer 'late'

        $this->actingAs($admin, 'sanctum')->postJson('/api/alerts/regenerate')->assertOk();
        $this->assertDatabaseMissing('alerts', ['type' => 'subscription']);
    }

    // #6 — an alert body must quote money in the BUILDING's currency. These strings
    // used to hardcode "$" while every other label rendered "₪".
    public function test_alert_bodies_quote_money_in_the_buildings_currency(): void
    {
        $this->seedBuilding();
        \App\Models\Building::where('key', 'residential')->update(['currency' => 'NIS']);
        $this->makeUnit(['no' => '101', 'status' => 'late', 'balance' => -1200]);

        $this->actingAs($this->admin(), 'sanctum')->postJson('/api/alerts/regenerate')->assertOk();

        $body = (string) \App\Models\Alert::where('type', 'subscription')->value('body');
        $this->assertStringContainsString('1,200 ₪', $body);
        $this->assertStringNotContainsString('$', $body);
    }

    public function test_overpaying_makes_a_unit_credit_and_deleting_reverts_to_late(): void
    {
        $this->seedBuilding();
        $admin = $this->admin();
        $unit = $this->makeUnit(['no' => '101', 'status' => 'late', 'balance' => -100]);

        $pay = $this->actingAs($admin, 'sanctum')->postJson('/api/payments', [
            'unit_no' => '101', 'amount' => 150, 'kind' => 'ذمم', 'month' => 0,
            'year' => 2026, 'date' => '2026-01-05', 'method' => 'نقداً',
        ])->json();
        $this->assertSame('credit', $unit->fresh()->status); // +50 → credit

        $this->actingAs($admin, 'sanctum')->deleteJson("/api/payments/{$pay['id']}")->assertOk();
        $this->assertSame('late', $unit->fresh()->status); // back to owing 100
    }

    public function test_a_back_debt_unit_is_created_late_not_ok(): void
    {
        $this->seedBuilding();
        $past = now()->subMonths(3)->toDateString();
        $res = $this->actingAs($this->admin(), 'sanctum')->postJson('/api/units', [
            'no' => 'BD1', 'floor' => 1, 'sub' => 100, 'status' => 'ok',
            'contract_start' => $past, 'back_debt' => true,
        ]);
        $res->assertCreated();
        // 3 months ago → 4 billed months (start month through current, inclusive) × 100.
        $this->assertSame(-400, (int) $res->json('balance'));
        $this->assertSame('late', $res->json('status')); // owes → late, despite status:ok input
    }

    public function test_back_debt_ignores_a_future_contract_start(): void
    {
        // A lease that starts in the future owes nothing yet — the month diff must
        // not go negative and fabricate a phantom credit/debit.
        $this->seedBuilding();
        $future = now()->addMonths(6)->toDateString();
        $res = $this->actingAs($this->admin(), 'sanctum')->postJson('/api/units', [
            'no' => 'F1', 'floor' => 1, 'sub' => 100, 'status' => 'ok',
            'contract_start' => $future, 'back_debt' => true,
        ]);
        $res->assertCreated();
        $this->assertSame(0, (int) $res->json('balance'));
    }

    public function test_back_debt_accrues_for_a_past_contract_start(): void
    {
        // Sanity companion: a 6-months-ago start with sub 100 → 7 inclusive months.
        $this->seedBuilding();
        $past = now()->subMonths(6)->toDateString();
        $res = $this->actingAs($this->admin(), 'sanctum')->postJson('/api/units', [
            'no' => 'P9', 'floor' => 1, 'sub' => 100, 'status' => 'ok',
            'contract_start' => $past, 'back_debt' => true,
        ]);
        $res->assertCreated();
        $this->assertSame(-700, (int) $res->json('balance'));
    }

    public function test_payment_with_zero_exchange_rate_is_rejected(): void
    {
        $this->seedBuilding('USD');
        $this->makeUnit(['no' => '101']);
        $this->actingAs($this->admin(), 'sanctum')->postJson('/api/payments', [
            'unit_no' => '101', 'original_amount' => 500, 'currency' => 'ILS', 'exchange_rate' => 0,
            'kind' => 'k', 'month' => 0, 'year' => 2026, 'date' => '2026-01-05', 'method' => 'x',
        ])->assertStatus(422);
    }

    public function test_contract_end_before_start_is_rejected(): void
    {
        $this->seedBuilding();
        $this->actingAs($this->admin(), 'sanctum')->postJson('/api/units', [
            'no' => 'CE1', 'floor' => 1, 'sub' => 100, 'status' => 'ok',
            'contract_start' => '2026-06-01', 'contract_end' => '2026-01-01',
        ])->assertStatus(422);
    }

    public function test_building_and_money_fields_reject_out_of_range_values(): void
    {
        $this->seedBuilding();
        $admin = $this->admin();
        // Oversized subscription/elevator_fee would overflow the unsigned column.
        $this->actingAs($admin, 'sanctum')->putJson('/api/building', ['subscription' => 9999999999])->assertStatus(422);
        $this->actingAs($admin, 'sanctum')->putJson('/api/building', ['elevator_fee' => 9999999999])->assertStatus(422);
        // Elevator contract end before start is rejected.
        $this->actingAs($admin, 'sanctum')->putJson('/api/building', [
            'elevator_contract_start' => '2026-06-01', 'elevator_contract_end' => '2026-01-01',
        ])->assertStatus(422);
    }

    public function test_duplicate_parking_number_is_rejected(): void
    {
        $this->seedBuilding();
        $admin = $this->admin();
        $this->actingAs($admin, 'sanctum')->postJson('/api/parking', ['no' => 'P1', 'status' => 'شاغر'])->assertCreated();
        $this->actingAs($admin, 'sanctum')->postJson('/api/parking', ['no' => 'P1', 'status' => 'شاغر'])->assertStatus(422);
    }

    public function test_editing_a_payment_amount_resyncs_currency_to_base(): void
    {
        // Editing a foreign-currency payment's (base) amount must not leave a
        // stale original-currency figure on the record.
        $this->seedBuilding('USD');
        $admin = $this->admin();
        $this->makeUnit(['no' => '101']);
        $pay = $this->actingAs($admin, 'sanctum')->postJson('/api/payments', [
            'unit_no' => '101', 'original_amount' => 350, 'currency' => 'ILS', 'exchange_rate' => 0.27,
            'kind' => 'اشتراك', 'month' => 0, 'year' => 2026, 'date' => '2026-01-05', 'method' => 'نقداً',
        ])->json();
        $this->assertSame('ILS', $pay['currency']);

        $edited = $this->actingAs($admin, 'sanctum')
            ->putJson("/api/payments/{$pay['id']}", ['amount' => 500])->json();
        $this->assertSame(500, (int) $edited['amount']);
        $this->assertSame(500, (int) $edited['original_amount']); // resynced
        $this->assertSame('USD', $edited['currency']);            // base, not stale ILS
    }

    // ─────────────── Email verification ───────────────

    public function test_email_code_request_returns_dev_code_locally(): void
    {
        $this->app['env'] = 'local';
        $res = $this->postJson('/api/auth/request-email-code', ['email' => 'a@b.com']);
        // `sent` is false with no mail provider behind it — the dev echo below is
        // what makes the flow usable, and saying "sent" would be a lie.
        $res->assertOk()->assertJson(['sent' => false]);
        $this->assertNotEmpty($res->json('dev_code'));
        $this->assertDatabaseHas('email_codes', ['email' => 'a@b.com', 'used' => false]);
    }

    public function test_email_code_verify_marks_user_verified(): void
    {
        $this->app['env'] = 'local';
        $user = User::create([
            'name' => 'ساكن', 'email' => 'v@b.com', 'role' => 'resident',
            'building_key' => 'residential',
        ]);
        $code = $this->postJson('/api/auth/request-email-code', ['email' => 'v@b.com'])->json('dev_code');

        $this->postJson('/api/auth/verify-email-code', ['email' => 'v@b.com', 'code' => $code])
            ->assertOk()->assertJson(['verified' => true]);

        $this->assertNotNull($user->fresh()->email_verified_at);
    }

    public function test_email_code_verify_rejects_wrong_code(): void
    {
        $this->app['env'] = 'local';
        $this->postJson('/api/auth/request-email-code', ['email' => 'w@b.com']);
        $this->postJson('/api/auth/verify-email-code', ['email' => 'w@b.com', 'code' => '000000'])
            ->assertStatus(422);
    }

    // Repro: enter the code wrong, then right — the right one MUST be accepted.
    public function test_email_code_wrong_then_right_is_accepted(): void
    {
        $this->app['env'] = 'local';
        $code = $this->postJson('/api/auth/request-email-code', ['email' => 'wr@b.com'])->json('dev_code');
        $wrong = $code === '000000' ? '111111' : '000000';

        $this->postJson('/api/auth/verify-email-code', ['email' => 'wr@b.com', 'code' => $wrong])
            ->assertStatus(422);
        // Now the correct code should succeed — NOT still say "wrong".
        $this->postJson('/api/auth/verify-email-code', ['email' => 'wr@b.com', 'code' => $code])
            ->assertOk()->assertJson(['verified' => true]);
    }

    // The core fix: register verifies the code atomically. A duplicate phone
    // must fail WITHOUT consuming the code, so the user can fix the phone and
    // retry with the SAME code — instead of the correct code reading as "wrong".
    public function test_register_dup_phone_does_not_consume_email_code(): void
    {
        $this->app['env'] = 'local';
        // An existing user already owns this phone.
        User::create(['name' => 'قديم', 'email' => 'old@b.com', 'phone' => '0599',
            'password' => Hash::make('secret6'), 'role' => 'resident', 'building_key' => 'residential']);

        $code = $this->postJson('/api/auth/request-email-code', ['email' => 'new@b.com'])->json('dev_code');

        // 1) register with the DUP phone + correct code → fails, code NOT consumed.
        $this->postJson('/api/auth/register', [
            'name' => 'جديد', 'email' => 'new@b.com', 'password' => 'secret6789',
            'phone' => '0599', 'email_code' => $code,
        ])->assertStatus(422);

        // 2) retry with a FREE phone + the SAME code → succeeds (code still valid).
        $this->postJson('/api/auth/register', [
            'name' => 'جديد', 'email' => 'new@b.com', 'password' => 'secret6789',
            'phone' => '0577', 'email_code' => $code,
        ])->assertCreated();

        $this->assertNotNull(User::where('email', 'new@b.com')->first()->email_verified_at);
    }

    public function test_register_wrong_code_is_rejected_and_creates_no_user(): void
    {
        $this->app['env'] = 'local';
        $code = $this->postJson('/api/auth/request-email-code', ['email' => 'z@b.com'])->json('dev_code');
        $wrong = $code === '000000' ? '111111' : '000000';

        $this->postJson('/api/auth/register', [
            'name' => 'ز', 'email' => 'z@b.com', 'password' => 'secret6789',
            'phone' => '0588', 'email_code' => $wrong,
        ])->assertStatus(422);
        $this->assertNull(User::where('email', 'z@b.com')->first()); // no half-created account

        // The correct code still works afterwards (wrong attempt didn't consume it).
        $this->postJson('/api/auth/register', [
            'name' => 'ز', 'email' => 'z@b.com', 'password' => 'secret6789',
            'phone' => '0588', 'email_code' => $code,
        ])->assertCreated();
    }

    // Renters can't self-register: an OTP for an unknown phone must be rejected,
    // NOT silently create a resident account.
    public function test_otp_for_unknown_phone_creates_no_account(): void
    {
        $this->app['env'] = 'local';
        $code = $this->postJson('/api/auth/request-otp', ['phone' => '0500999'])->json('dev_code');

        $this->postJson('/api/auth/verify-otp', ['phone' => '0500999', 'code' => $code])
            ->assertStatus(422);
        $this->assertNull(User::where('phone', '0500999')->first());
    }

    // Similar-bug fix: a phone OTP for a password-protected account is rejected
    // WITHOUT consuming the OTP (the check now runs before the code is spent).
    public function test_otp_not_consumed_for_password_account(): void
    {
        $this->app['env'] = 'local';
        User::create(['name' => 'مدير', 'phone' => '0599', 'password' => Hash::make('secret6'),
            'role' => 'admin', 'building_key' => 'residential']);

        $code = $this->postJson('/api/auth/request-otp', ['phone' => '0599'])->json('dev_code');
        $this->postJson('/api/auth/verify-otp', ['phone' => '0599', 'code' => $code])
            ->assertStatus(422);

        // The OTP must still be unused (not wasted on a login that can't succeed).
        $this->assertDatabaseHas('otp_codes', ['phone' => '0599', 'used' => false]);
    }

    // Repro: type old code wrong, request a NEW code, enter the new one — accepted.
    public function test_email_code_resend_after_wrong_is_accepted(): void
    {
        $this->app['env'] = 'local';
        $first = $this->postJson('/api/auth/request-email-code', ['email' => 're@b.com'])->json('dev_code');
        $wrong = $first === '000000' ? '111111' : '000000';
        $this->postJson('/api/auth/verify-email-code', ['email' => 're@b.com', 'code' => $wrong])
            ->assertStatus(422);

        $second = $this->postJson('/api/auth/request-email-code', ['email' => 're@b.com'])->json('dev_code');
        $this->postJson('/api/auth/verify-email-code', ['email' => 're@b.com', 'code' => $second])
            ->assertOk()->assertJson(['verified' => true]);
    }

    // ─────────────── QR / redeem-code login ───────────────

    public function test_redeem_code_returns_token(): void
    {
        $user = User::create([
            'name' => 'ساكن', 'email' => 'r@b.com', 'role' => 'resident',
            'building_key' => 'residential', 'login_code' => 'ABCD1234',
        ]);

        // Case-insensitive match (codes are uppercased server-side).
        $res = $this->postJson('/api/auth/redeem-code', ['code' => 'abcd1234']);
        $res->assertOk();
        $this->assertNotEmpty($res->json('token'));
        $this->assertSame($user->id, $res->json('user.id'));
    }

    public function test_redeem_code_rejects_unknown(): void
    {
        $this->postJson('/api/auth/redeem-code', ['code' => 'NOPE0000'])->assertStatus(422);
    }

    // ─────────────── Register: phone + whatsapp ───────────────

    public function test_register_accepts_phone_and_whatsapp(): void
    {
        $res = $this->postJson('/api/auth/register', [
            'name' => 'جديد', 'email' => 'new@b.com', 'password' => 'secret1234',
            'phone' => '+966500000099', 'whatsapp' => '+966500000088',
        ]);
        $res->assertCreated();
        $this->assertDatabaseHas('users', [
            'email' => 'new@b.com', 'phone' => '+966500000099', 'whatsapp' => '+966500000088',
        ]);
    }

    public function test_login_by_phone_works(): void
    {
        User::create([
            'name' => 'هاتف', 'phone' => '+966500000077', 'email' => 'p@b.com',
            'password' => Hash::make('secret1234'), 'role' => 'resident',
            'building_key' => 'residential',
        ]);

        $this->postJson('/api/auth/login', [
            'phone' => '+966500000077', 'password' => 'secret1234',
        ])->assertOk()->assertJsonStructure(['token', 'user']);
    }

    // ─────────────── Residents: login_code in response ───────────────

    public function test_store_resident_returns_login_code(): void
    {
        $this->seedBuilding();
        $res = $this->actingAs($this->admin(), 'sanctum')->postJson('/api/residents', [
            'name' => 'ساكن جديد', 'phone' => '+966500001111', 'unit_no' => '101', 'password' => 'secret6789',
        ]);
        $res->assertCreated();
        $this->assertNotEmpty($res->json('login_code'));
        $this->assertDatabaseHas('users', [
            'phone' => '+966500001111', 'login_code' => $res->json('login_code'),
        ]);
    }

    public function test_join_approval_mints_a_strong_login_code(): void
    {
        // A resident admitted via join-request approval must get the same
        // high-entropy (128-bit → 32 hex char) login code as one added directly
        // by the manager — the join path must not mint a weak short code.
        $this->seedBuilding();
        $applicant = User::create([
            'name' => 'مُنضم', 'phone' => '+966500003333', 'role' => 'resident',
            'building_key' => 'residential',
        ]);
        $jr = JoinRequest::create([
            'building_key' => 'residential', 'user_id' => $applicant->id,
            'name' => 'مُنضم', 'unit_no' => '101', 'status' => 'pending',
        ]);

        $this->actingAs($this->admin(), 'sanctum')
            ->postJson("/api/join-requests/{$jr->id}/approve")
            ->assertOk();

        $code = $applicant->fresh()->login_code;
        $this->assertSame(32, strlen($code), 'join-approval login code must be 128-bit');
    }

    public function test_editing_a_unit_without_renaming_still_works(): void
    {
        // The common case: edit fields WITHOUT changing the number. Must not trip
        // the rename collision guard or cascade — just a plain update.
        $this->seedBuilding();
        $unit = $this->makeUnit(['no' => '101', 'sub' => 50, 'status' => 'ok']);

        $this->actingAs($this->admin(), 'sanctum')
            ->putJson("/api/units/{$unit->id}", [
                'no' => '101', 'floor' => 2, 'sub' => 75, 'status' => 'late', 'balance' => -75,
            ])->assertOk();

        $fresh = $unit->fresh();
        $this->assertSame('101', $fresh->no);
        $this->assertSame(75, (int) $fresh->sub);
        // Balance/status are DERIVED (#19): the sent 'balance'/'status' are ignored.
        // With no opening/charges/payments here, the derived balance is 0.
        $this->assertSame(0, (int) $fresh->balance);
    }

    public function test_admin_still_sees_a_units_overdue_alert(): void
    {
        // The privacy fix targets per-unit alerts to their unit. The ADMIN must
        // still see them (admin's feed is unfiltered) — the fix must not hide a
        // unit's overdue notice from the manager.
        $this->seedBuilding();
        $this->makeUnit(['no' => '305', 'resident' => 'مدين', 'status' => 'late', 'balance' => -500]);

        $admin = $this->admin();
        $this->actingAs($admin, 'sanctum')->postJson('/api/alerts/regenerate')->assertOk();
        $seen = $this->actingAs($admin, 'sanctum')->getJson('/api/alerts')->json();

        $titles = collect($seen)->pluck('title')->implode(' | ');
        $this->assertStringContainsString('305', $titles, 'admin must still see unit 305 overdue');
    }

    public function test_renaming_a_unit_cascades_to_payments_and_resident(): void
    {
        // Renaming a unit's number must carry its payment history and the linked
        // resident's account along — not orphan them under the old number.
        $this->seedBuilding();
        $unit = $this->makeUnit(['no' => '101']);
        $resident = User::create([
            'name' => 'ساكن', 'phone' => '+966500004444', 'role' => 'resident',
            'building_key' => 'residential', 'unit_no' => '101',
        ]);
        Payment::create([
            'building_key' => 'residential', 'unit_no' => '101', 'name' => 'ساكن',
            'amount' => 100, 'currency' => 'USD', 'original_amount' => 100,
            'exchange_rate' => 1, 'kind' => 'اشتراك', 'month' => 0, 'year' => 2026,
            'date' => '2026-01-05', 'method' => 'نقداً',
        ]);

        $this->actingAs($this->admin(), 'sanctum')
            ->putJson("/api/units/{$unit->id}", [
                'no' => '202', 'floor' => 1, 'sub' => 50, 'status' => 'ok',
            ])->assertOk();

        $this->assertDatabaseHas('payments', ['unit_no' => '202', 'amount' => 100]);
        $this->assertDatabaseMissing('payments', ['unit_no' => '101']);
        $this->assertSame('202', $resident->fresh()->unit_no);
    }

    public function test_units_payload_includes_login_code(): void
    {
        $this->seedBuilding();
        $this->makeUnit(['no' => '101']);
        User::create([
            'name' => 'ساكن', 'phone' => '+966500002222', 'role' => 'resident',
            'building_key' => 'residential', 'unit_no' => '101', 'login_code' => 'UNIT1010',
        ]);

        $res = $this->actingAs($this->admin(), 'sanctum')->getJson('/api/units');
        $res->assertOk();
        $row = collect($res->json())->firstWhere('no', '101');
        $this->assertSame('UNIT1010', $row['login_code']);
    }

    // ─────────────── Payments: currency + carry-over ───────────────

    public function test_payment_in_non_base_currency_stores_converted_amount(): void
    {
        $this->seedBuilding('USD');
        $unit = $this->makeUnit(['no' => '101', 'balance' => 0]);

        $res = $this->actingAs($this->admin(), 'sanctum')->postJson('/api/payments', [
            'unit_no' => '101', 'original_amount' => 100, 'currency' => 'SAR',
            'exchange_rate' => 3.75, 'kind' => 'الاشتراك الشهري', 'month' => 4,
            'year' => 2026, 'date' => '2026-05-01', 'method' => 'نقداً',
        ]);
        $res->assertCreated();
        // 100 SAR * 3.75 → would be base; here exchange_rate is SAR→base, so
        // amount = round(100 * 3.75) = 375 in base currency.
        $this->assertSame(375, $res->json('amount'));
        $this->assertSame('SAR', $res->json('currency'));
        $this->assertSame(100, $res->json('original_amount'));
        // Carry-over: balance credited by the base amount.
        $this->assertSame(375, (int) $unit->fresh()->balance);
    }

    public function test_payment_create_then_delete_reverts_balance(): void
    {
        $this->seedBuilding('USD');
        // Unit starts owing 200 (ذمم سابقة → negative balance).
        $unit = $this->makeUnit(['no' => '101', 'balance' => -200]);
        $admin = $this->admin();

        $res = $this->actingAs($admin, 'sanctum')->postJson('/api/payments', [
            'unit_no' => '101', 'amount' => 200, 'currency' => 'USD',
            'kind' => 'الاشتراك الشهري', 'month' => 4, 'year' => 2026,
            'date' => '2026-05-01', 'method' => 'نقداً',
        ]);
        $res->assertCreated();
        // -200 + 200 → 0 (cleared).
        $this->assertSame(0, (int) $unit->fresh()->balance);

        $paymentId = $res->json('id');
        $this->actingAs($admin, 'sanctum')->deleteJson("/api/payments/{$paymentId}")->assertOk();
        // Deleting reverts the credit → back to -200 (carry-over preserved).
        $this->assertSame(-200, (int) $unit->fresh()->balance);
    }

    public function test_payment_update_applies_balance_delta(): void
    {
        $this->seedBuilding('USD');
        $unit = $this->makeUnit(['no' => '101', 'balance' => 0]);
        $admin = $this->admin();

        $res = $this->actingAs($admin, 'sanctum')->postJson('/api/payments', [
            'unit_no' => '101', 'amount' => 40, 'currency' => 'USD',
            'kind' => 'الاشتراك الشهري', 'month' => 4, 'year' => 2026,
            'date' => '2026-05-01', 'method' => 'نقداً',
        ]);
        $this->assertSame(40, (int) $unit->fresh()->balance);

        $id = $res->json('id');
        $this->actingAs($admin, 'sanctum')->putJson("/api/payments/{$id}", ['amount' => 100])->assertOk();
        // Balance shifted by the +60 delta.
        $this->assertSame(100, (int) $unit->fresh()->balance);
    }

    // ─────────────── Summary: 12-month trend ───────────────

    public function test_summary_trend_has_twelve_months(): void
    {
        $this->seedBuilding();
        $res = $this->actingAs($this->admin(), 'sanctum')->getJson('/api/summary');
        $res->assertOk();
        $this->assertCount(12, $res->json('trend'));
    }

    public function test_join_invite_url_serves_a_landing_page_not_a_404(): void
    {
        // The shared invite link must resolve to a helpful page (was a 404).
        $res = $this->get('/join/AMR-1206');
        $res->assertOk();
        $res->assertSee('عمارتي', false);
        $res->assertSee('AMR-1206', false);
    }

    public function test_summary_requires_authentication(): void
    {
        // Financials must not be public — an unauthenticated request is rejected.
        $this->seedBuilding();
        $this->getJson('/api/summary')->assertStatus(401);
    }

    // ─────────────── New overhaul endpoints ───────────────

    public function test_unit_back_debt_seeds_opening_balance_from_contract(): void
    {
        $this->seedBuilding();
        $admin = $this->admin();
        // 100/month, contract started 5 months ago → 6 inclusive billed months.
        $start = now()->subMonthsNoOverflow(5)->toDateString();
        $res = $this->actingAs($admin, 'sanctum')->postJson('/api/units', [
            'no' => '202', 'floor' => 2, 'resident' => 'بلال', 'kind' => 'مستأجر',
            'sub' => 100, 'contract_start' => $start, 'back_debt' => true,
        ]);
        $res->assertCreated();
        $this->assertSame(-600, (int) $res->json('balance'));
    }

    public function test_open_ended_contract_stays_null_not_forced_end_date(): void
    {
        $this->seedBuilding();
        $admin = $this->admin();
        // The Flutter "مستمر" toggle sends contract_end '' (→ null). It must NOT
        // be overridden with a default end date.
        $res = $this->actingAs($admin, 'sanctum')->postJson('/api/units', [
            'no' => '301', 'floor' => 3, 'resident' => 'ساكن', 'kind' => 'مالك',
            'contract_start' => '2026-07-01', 'contract_end' => null,
        ]);
        $res->assertCreated();
        $this->assertNull($res->json('contract_end'));

        // A real end date is preserved.
        $fixed = $this->actingAs($admin, 'sanctum')->postJson('/api/units', [
            'no' => '302', 'floor' => 3, 'resident' => 'مستأجر', 'kind' => 'مستأجر',
            'contract_start' => '2026-01-01', 'contract_end' => '2026-12-31',
        ]);
        $this->assertSame('2026-12-31', $fixed->json('contract_end'));

        // Editing a fixed contract to open-ended clears the end date.
        $id = $fixed->json('id');
        $edit = $this->actingAs($admin, 'sanctum')->putJson("/api/units/{$id}", [
            'no' => '302', 'floor' => 3, 'kind' => 'مستأجر', 'contract_end' => null,
        ]);
        $edit->assertOk();
        $this->assertNull($edit->json('contract_end'));
    }

    public function test_oversized_amount_is_rejected_not_a_500(): void
    {
        $this->seedBuilding('USD');
        $unit = $this->makeUnit(['no' => '101']);
        $admin = $this->admin();

        // Beyond the signed-INT column: must be a clean 422, not a MySQL 500.
        $this->actingAs($admin, 'sanctum')->postJson('/api/payments', [
            'unit_no' => '101', 'amount' => 9999999999, 'currency' => 'USD',
            'kind' => 'x', 'month' => 4, 'year' => 2026, 'date' => '2026-05-01', 'method' => 'نقداً',
        ])->assertStatus(422);

        // Conversion overflow (1B entered × rate 5) is also caught.
        $this->actingAs($admin, 'sanctum')->postJson('/api/payments', [
            'unit_no' => '101', 'original_amount' => 1000000000, 'currency' => 'SAR',
            'exchange_rate' => 5, 'kind' => 'x', 'month' => 4, 'year' => 2026,
            'date' => '2026-05-01', 'method' => 'نقداً',
        ])->assertStatus(422);

        $this->assertSame(0, (int) $unit->fresh()->balance); // nothing was written
    }

    public function test_expense_converts_entered_currency_to_base(): void
    {
        $this->seedBuilding('USD');
        $admin = $this->admin();
        // 100 ILS at 0.27 → 27 USD stored as the base amount.
        $res = $this->actingAs($admin, 'sanctum')->postJson('/api/expenses', [
            'cat' => 'صيانة', 'supplier' => 'مورّد', 'amount' => 100,
            'original_amount' => 100, 'currency' => 'ILS', 'exchange_rate' => 0.27,
            'date' => '2026-06-30',
        ]);
        $res->assertCreated();
        $this->assertSame(27, (int) $res->json('amount'));
        $this->assertSame('ILS', $res->json('currency'));
    }

    public function test_notification_targets_a_single_unit(): void
    {
        $this->seedBuilding();
        $admin = $this->admin();
        $resident = User::create([
            'name' => 'ساكن', 'phone' => '0599', 'password' => Hash::make('password'),
            'role' => 'resident', 'building_key' => 'residential', 'unit_no' => '101',
        ]);

        $this->actingAs($admin, 'sanctum')->postJson('/api/notifications', [
            'title' => 'تذكير', 'body' => 'يرجى الدفع', 'target' => '101',
        ])->assertCreated();
        $this->actingAs($admin, 'sanctum')->postJson('/api/notifications', [
            'title' => 'إعلان', 'body' => 'للجميع', 'target' => 'all',
        ])->assertCreated();

        // The resident on unit 101 sees both; a 999 resident would see only 'all'.
        $seen = $this->actingAs($resident, 'sanctum')->getJson('/api/alerts')->json();
        $this->assertCount(2, $seen);
    }

    public function test_regenerating_alerts_preserves_manager_notifications(): void
    {
        // A manager-composed notification is a real message. Refreshing the
        // auto-derived alerts (the "refresh" button) must NOT delete it.
        $this->seedBuilding();
        $admin = $this->admin();
        $this->actingAs($admin, 'sanctum')->postJson('/api/notifications', [
            'title' => 'إعلان مهم', 'body' => 'اجتماع السكان الجمعة', 'target' => 'all',
        ])->assertCreated();

        $this->actingAs($admin, 'sanctum')->postJson('/api/alerts/regenerate')->assertOk();

        $this->assertDatabaseHas('alerts', [
            'building_key' => 'residential', 'type' => 'notice', 'title' => 'إعلان مهم',
        ]);
    }

    public function test_resident_does_not_see_a_neighbours_overdue_alert(): void
    {
        // Auto-derived overdue alerts embed a named resident + their debt. They
        // must be addressed to that unit only, never broadcast to every resident.
        $this->seedBuilding();
        $this->makeUnit(['no' => '101', 'resident' => 'ساكن 101', 'status' => 'ok']);
        $this->makeUnit(['no' => '305', 'resident' => 'جار مدين', 'status' => 'late', 'balance' => -500]);
        $r101 = User::create([
            'name' => 'ساكن 101', 'phone' => '0591', 'role' => 'resident',
            'building_key' => 'residential', 'unit_no' => '101',
        ]);

        $this->actingAs($this->admin(), 'sanctum')->postJson('/api/alerts/regenerate')->assertOk();

        $seen = $this->actingAs($r101, 'sanctum')->getJson('/api/alerts')->json();
        $titles = collect($seen)->pluck('title')->implode(' | ');
        $this->assertStringNotContainsString('305', $titles, 'resident 101 must not see unit 305 overdue');
    }

    public function test_full_worker_payment_advances_the_due_date_by_a_cycle(): void
    {
        // Recording a full payment must move next_due forward by the cycle — not
        // leave it stale on the same past date.
        $this->seedBuilding();
        $admin = $this->admin();
        $worker = $this->actingAs($admin, 'sanctum')->postJson('/api/workers', [
            'name' => 'عامل', 'phone' => '0599', 'cycle' => 'شهري', 'amount' => 200,
            'next_due' => '2026-01-01',
        ])->json();

        $updated = $this->actingAs($admin, 'sanctum')
            ->putJson("/api/workers/{$worker['id']}", ['pay_status' => 'full'])->json();

        // Monthly cycle → next_due ~ one month from today, i.e. in the future.
        $this->assertTrue(now()->lt(\Illuminate\Support\Carbon::parse($updated['next_due'])),
            'next_due should advance into the future');
        $this->assertNotSame('2026-01-01', $updated['next_due']);
    }

    public function test_elevator_check_reminder_fires_only_when_enabled_and_due(): void
    {
        $this->seedBuilding();
        $admin = $this->admin();
        // Enable the reminder with a last check well past the interval → overdue.
        $this->actingAs($admin, 'sanctum')->putJson('/api/building', [
            'elevator_check_notify' => true,
            'elevator_check_interval' => 6,
            'elevator_last_check' => now()->subMonths(12)->toDateString(),
        ])->assertOk();
        $this->actingAs($admin, 'sanctum')->postJson('/api/alerts/regenerate')->assertOk();
        $this->assertDatabaseHas('alerts', ['type' => 'elevator_check']);

        // Disable it → the reminder disappears on the next regenerate.
        $this->actingAs($admin, 'sanctum')->putJson('/api/building', ['elevator_check_notify' => false])->assertOk();
        $this->actingAs($admin, 'sanctum')->postJson('/api/alerts/regenerate')->assertOk();
        $this->assertDatabaseMissing('alerts', ['type' => 'elevator_check']);
    }

    public function test_partial_worker_payment_is_clamped_to_the_fee(): void
    {
        $this->seedBuilding();
        $admin = $this->admin();
        $worker = $this->actingAs($admin, 'sanctum')->postJson('/api/workers', [
            'name' => 'عامل', 'phone' => '0599', 'cycle' => 'شهري', 'amount' => 200,
        ])->json();
        $updated = $this->actingAs($admin, 'sanctum')
            ->putJson("/api/workers/{$worker['id']}", ['pay_status' => 'partial', 'paid_amount' => 999999])
            ->json();
        $this->assertSame(200, (int) $updated['paid_amount']); // clamped to the fee
    }

    public function test_worker_update_records_attendance_and_full_payment(): void
    {
        $this->seedBuilding();
        $admin = $this->admin();
        $worker = $this->actingAs($admin, 'sanctum')->postJson('/api/workers', [
            'name' => 'عامل النظافة', 'phone' => '0599', 'cycle' => 'شهري', 'amount' => 200,
        ])->json();

        $res = $this->actingAs($admin, 'sanctum')->putJson("/api/workers/{$worker['id']}", [
            'came' => true, 'pay_status' => 'full',
        ]);
        $res->assertOk();
        $this->assertTrue((bool) $res->json('came'));
        $this->assertSame('full', $res->json('pay_status'));
        $this->assertSame(200, (int) $res->json('paid_amount'));
    }

    // ─────────────── Salah feedback regressions (v1.3.4) ───────────────

    public function test_back_debt_adds_previous_dues_on_top(): void
    {
        // #1: enabling 'احتساب الإيجار من بداية العقد' must ADD any previous dues
        // (ذمم سابقة) to the from-contract debt, not replace them.
        $this->seedBuilding();
        $admin = $this->admin();
        $start = now()->subMonths(6)->toDateString();
        $this->actingAs($admin, 'sanctum')->postJson('/api/units', [
            'no' => '101', 'floor' => 1, 'resident' => 'ساكن', 'kind' => 'مستأجر',
            'sub' => 100, 'contract_start' => $start, 'back_debt' => true,
            'balance' => -250, // frontend pre-negates the ذمم سابقة
        ])->assertCreated();

        // Charges accrue from the contract-start month THROUGH the current month
        // (inclusive) — a start N months ago bills N+1 months — plus the ذمم سابقة.
        $s = \Illuminate\Support\Carbon::parse($start)->startOfMonth();
        $nowM = now()->startOfMonth();
        $months = ($nowM->year - $s->year) * 12 + ($nowM->month - $s->month) + 1;
        $this->assertGreaterThan(0, $months);
        $this->assertSame(-(100 * $months) - 250, (int) Unit::where('no', '101')->first()->balance);
    }

    public function test_payment_can_be_recorded_for_a_previous_year(): void
    {
        // #2: the payment sheet's year selector lets a manager record months of a
        // PREVIOUS year; the row must land in that year's totals, not the current.
        $this->seedBuilding();
        $admin = $this->admin();
        $this->makeUnit(['no' => '101', 'balance' => 0]);
        $this->actingAs($admin, 'sanctum')->postJson('/api/payments', [
            'unit_no' => '101', 'amount' => 50, 'kind' => 'الاشتراك الشهري',
            'month' => 11, 'year' => 2024, 'date' => '2026-08-01', 'method' => 'نقداً',
        ])->assertCreated();

        $this->assertSame(2024, (int) Payment::where('unit_no', '101')->first()->year);
        $s24 = $this->actingAs($admin, 'sanctum')->getJson('/api/summary?year=2024')->json();
        $this->assertSame(50, (int) $s24['revenueM']);
        $s26 = $this->actingAs($admin, 'sanctum')->getJson('/api/summary?year=2026')->json();
        $this->assertSame(0, (int) $s26['revenueM']);
    }

    public function test_multi_month_payment_sums_to_the_full_total(): void
    {
        // #4: recording 100 across 7 months (the multi-month flow saves one row
        // per month) must total 700 in the whole-year summary — not one month's 100.
        $this->seedBuilding();
        $admin = $this->admin();
        $this->makeUnit(['no' => '101', 'sub' => 100, 'balance' => 0]);
        for ($m = 0; $m < 7; $m++) {
            $this->actingAs($admin, 'sanctum')->postJson('/api/payments', [
                'unit_no' => '101', 'amount' => 100, 'kind' => 'الاشتراك الشهري',
                'month' => $m, 'year' => 2026, 'date' => '2026-08-01', 'method' => 'نقداً',
            ])->assertCreated();
        }
        $this->assertSame(7, Payment::where('unit_no', '101')->count());
        $this->assertSame(700, (int) Unit::where('no', '101')->first()->balance);

        $all = $this->actingAs($admin, 'sanctum')->getJson('/api/summary?year=2026')->json();
        $this->assertSame(700, (int) $all['revenueM']); // whole year = 7 × 100
        $jan = $this->actingAs($admin, 'sanctum')->getJson('/api/summary?year=2026&month=0')->json();
        $this->assertSame(100, (int) $jan['revenueM']); // a single month is still 100
    }

    // ─────────────── Auth/session hardening (Phase 1) ───────────────

    public function test_resident_creation_requires_a_password(): void
    {
        // #15: residents need a durable phone+password login, so /residents must
        // reject a passwordless account.
        $this->seedBuilding();
        $this->makeUnit(['no' => '101']);
        $this->actingAs($this->admin(), 'sanctum')->postJson('/api/residents', [
            'name' => 'بلا كلمة', 'phone' => '+966500007777', 'unit_no' => '101',
        ])->assertStatus(422);
    }

    public function test_resident_can_log_in_with_phone_and_password(): void
    {
        // #15 "test ساكن": a manager-created resident can sign in with phone+password.
        $this->seedBuilding();
        $this->makeUnit(['no' => '101']);
        $this->actingAs($this->admin(), 'sanctum')->postJson('/api/residents', [
            'name' => 'ساكن', 'phone' => '+966500008888', 'unit_no' => '101', 'password' => 'secret6789',
        ])->assertCreated();

        $res = $this->postJson('/api/auth/login', ['phone' => '+966500008888', 'password' => 'secret6789']);
        $res->assertOk();
        $this->assertNotEmpty($res->json('token'));
        $this->assertSame('resident', $res->json('user.role'));
    }

    public function test_login_code_is_single_use_and_rotates_on_redeem(): void
    {
        // #1: the QR/login-code must not be a permanent multi-device credential.
        // Redeeming rotates it, so the same code can't be reused on another device.
        $this->seedBuilding();
        $this->makeUnit(['no' => '101']);
        $code = $this->actingAs($this->admin(), 'sanctum')->postJson('/api/residents', [
            'name' => 'ساكن', 'phone' => '+966500006666', 'unit_no' => '101', 'password' => 'secret6789',
        ])->json('login_code');

        $this->postJson('/api/auth/redeem-code', ['code' => $code])->assertOk();     // first use works
        $this->postJson('/api/auth/redeem-code', ['code' => $code])->assertStatus(422); // reuse blocked
    }

    // ─────────────── Derived ledger (P4a) ───────────────

    public function test_charges_start_from_the_current_month_when_back_debt_off(): void
    {
        // #21: without "احتساب من بداية العقد", billing starts THIS month — so a
        // long-past contract still owes only the current month's fee (inclusive).
        $this->seedBuilding();
        $past = now()->subMonths(6)->toDateString();
        $res = $this->actingAs($this->admin(), 'sanctum')->postJson('/api/units', [
            'no' => 'NB1', 'floor' => 1, 'sub' => 100, 'status' => 'ok',
            'contract_start' => $past, 'back_debt' => false,
        ]);
        $res->assertCreated();
        $this->assertSame(-100, (int) $res->json('balance')); // one month, not seven
    }

    public function test_a_payment_settles_derived_charges(): void
    {
        // A payment reduces the DERIVED balance (opening − charges + payments);
        // it is not a free credit on a stored number.
        $this->seedBuilding();
        $admin = $this->admin();
        $start = now()->subMonthsNoOverflow(2)->toDateString(); // 3 inclusive months
        $this->actingAs($admin, 'sanctum')->postJson('/api/units', [
            'no' => 'PS1', 'floor' => 1, 'sub' => 100, 'status' => 'ok',
            'contract_start' => $start, 'back_debt' => true,
        ])->assertCreated();
        // Owes 300 (3 × 100). Pay 300 → settled.
        $unit = Unit::where('no', 'PS1')->first();
        $this->assertSame(-300, (int) $unit->balance);

        $this->actingAs($admin, 'sanctum')->postJson('/api/payments', [
            'unit_no' => 'PS1', 'amount' => 300, 'kind' => 'الاشتراك الشهري',
            'month' => 0, 'year' => 2026, 'date' => '2026-01-05', 'method' => 'نقداً',
        ])->assertCreated();

        $fresh = Unit::where('no', 'PS1')->first();
        $this->assertSame(0, (int) $fresh->balance); // 300 charges − 300 paid
        $this->assertSame('ok', $fresh->status);
    }

    public function test_an_other_line_is_income_but_does_not_settle_dues(): void
    {
        // #28: choosing "أخرى" records income but must NOT reduce the resident's ذمم.
        $this->seedBuilding();
        $admin = $this->admin();
        $this->makeUnit(['no' => 'OT1', 'sub' => 100, 'balance' => -500]); // owes 500

        $this->actingAs($admin, 'sanctum')->postJson('/api/payments', [
            'unit_no' => 'OT1', 'amount' => 200, 'kind' => 'أخرى',
            'month' => 0, 'year' => 2026, 'date' => '2026-01-05', 'method' => 'نقداً',
            'applies_to_dues' => false,
        ])->assertCreated();

        // Dues unchanged (still owes 500) …
        $this->assertSame(-500, (int) Unit::where('no', 'OT1')->first()->balance);
        // … but it IS counted as revenue.
        $sum = $this->actingAs($admin, 'sanctum')->getJson('/api/summary?year=2026')->json();
        $this->assertSame(200, (int) $sum['revenueM']);
    }

    public function test_a_cheque_payment_requires_a_future_date_and_number(): void
    {
        // #26: method شيك ⇒ cheque date (future only) + cheque number are required.
        $this->seedBuilding();
        $admin = $this->admin();
        $this->makeUnit(['no' => 'CH1', 'sub' => 100]);
        $base = [
            'unit_no' => 'CH1', 'amount' => 100, 'kind' => 'الاشتراك الشهري',
            'month' => 0, 'year' => 2026, 'date' => '2026-01-05', 'method' => 'شيك',
        ];

        // Missing cheque details → rejected.
        $this->actingAs($admin, 'sanctum')->postJson('/api/payments', $base)->assertStatus(422);
        // A PAST cheque date → rejected.
        $this->actingAs($admin, 'sanctum')->postJson('/api/payments', $base + [
            'cheque_date' => now()->subDay()->toDateString(), 'cheque_number' => 'C-1',
        ])->assertStatus(422);
        // A future date + number → accepted.
        $res = $this->actingAs($admin, 'sanctum')->postJson('/api/payments', $base + [
            'cheque_date' => now()->addMonth()->toDateString(), 'cheque_number' => 'C-1',
        ]);
        $res->assertCreated();
        $this->assertSame('C-1', $res->json('cheque_number'));
    }

    public function test_special_income_needs_no_unit_and_never_settles_dues(): void
    {
        // #38: "ايراد خاص" (e.g. دفعة برج جوال) is building income with NO renter.
        $this->seedBuilding();
        $admin = $this->admin();
        $this->makeUnit(['no' => 'SI1', 'sub' => 100, 'balance' => -300]); // owes 300

        // A unit-less line must be labelled.
        $this->actingAs($admin, 'sanctum')->postJson('/api/payments', [
            'amount' => 500, 'kind' => 'ايراد خاص',
            'month' => 0, 'year' => 2026, 'date' => '2026-01-10', 'method' => 'نقداً',
        ])->assertStatus(422);

        $res = $this->actingAs($admin, 'sanctum')->postJson('/api/payments', [
            'name' => 'دفعة برج جوال', 'amount' => 500, 'kind' => 'ايراد خاص',
            'month' => 0, 'year' => 2026, 'date' => '2026-01-10', 'method' => 'نقداً',
        ]);
        $res->assertCreated();
        $this->assertNull($res->json('unit_no'));
        $this->assertFalse((bool) $res->json('applies_to_dues'));

        // Counted as revenue, but nobody's dues change.
        $sum = $this->actingAs($admin, 'sanctum')->getJson('/api/summary?year=2026')->json();
        $this->assertSame(500, (int) $sum['revenueM']);
        $this->assertSame(300, (int) $sum['due']);
        $this->assertSame(-300, (int) Unit::where('no', 'SI1')->first()->balance);
    }
}
