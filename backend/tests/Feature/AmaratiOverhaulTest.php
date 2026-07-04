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
        return Unit::create(array_merge([
            'building_key' => 'residential', 'ext_id' => 'A1', 'no' => '101',
            'floor' => 1, 'resident' => 'ساكن', 'kind' => 'مالك', 'phone' => '—',
            'sub' => 40, 'status' => 'ok', 'balance' => 0, 'payer' => 'الساكن',
        ], $attrs));
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
        $admin = $this->admin();
        $this->actingAs($admin, 'sanctum')->putJson('/api/settings', ['primary' => 'not-a-hex'])->assertStatus(422);
        $this->actingAs($admin, 'sanctum')->putJson('/api/settings', ['primary' => '#123456'])->assertOk();
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

    // ─────────────── Redeem code round-trip ───────────────

    public function test_manager_created_resident_can_redeem_their_code(): void
    {
        $this->seedBuilding();
        $this->makeUnit(['no' => '101']);
        $code = $this->actingAs($this->admin(), 'sanctum')->postJson('/api/residents', [
            'name' => 'ساكن جديد', 'phone' => '+966500009999', 'unit_no' => '101',
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
            'name' => 'قديم', 'phone' => '+966500000011', 'unit_no' => '101',
        ])->json();
        $this->actingAs($admin, 'sanctum')->postJson('/api/residents', [
            'name' => 'جديد', 'phone' => '+966500000022', 'unit_no' => '101',
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
            'name' => 'أول', 'phone' => '+966500001234',
        ])->assertCreated();
        $this->actingAs($admin, 'sanctum')->postJson('/api/residents', [
            'name' => 'ثانٍ', 'phone' => '+966500001234',
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
        $unit = $this->makeUnit(['no' => '101', 'status' => 'late', 'balance' => -100]);

        $this->actingAs($admin, 'sanctum')->postJson('/api/payments', [
            'unit_no' => '101', 'amount' => 100, 'kind' => 'اشتراك', 'month' => 0,
            'year' => 2026, 'date' => '2026-01-05', 'method' => 'نقداً',
        ])->assertCreated();

        $fresh = $unit->fresh();
        $this->assertSame(0, (int) $fresh->balance);
        $this->assertSame('ok', $fresh->status); // no longer 'late'

        $this->actingAs($admin, 'sanctum')->postJson('/api/alerts/regenerate')->assertOk();
        $this->assertDatabaseMissing('alerts', ['building_key' => 'residential', 'type' => 'subscription']);
    }

    public function test_overpaying_makes_a_unit_credit_and_deleting_reverts_to_late(): void
    {
        $this->seedBuilding();
        $admin = $this->admin();
        $unit = $this->makeUnit(['no' => '101', 'status' => 'late', 'balance' => -100]);

        $pay = $this->actingAs($admin, 'sanctum')->postJson('/api/payments', [
            'unit_no' => '101', 'amount' => 150, 'kind' => 'k', 'month' => 0,
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
        $this->assertSame(-300, (int) $res->json('balance'));
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
        // Sanity companion: a 6-months-ago start with sub 100 owes ~600.
        $this->seedBuilding();
        $past = now()->subMonths(6)->toDateString();
        $res = $this->actingAs($this->admin(), 'sanctum')->postJson('/api/units', [
            'no' => 'P9', 'floor' => 1, 'sub' => 100, 'status' => 'ok',
            'contract_start' => $past, 'back_debt' => true,
        ]);
        $res->assertCreated();
        $this->assertSame(-600, (int) $res->json('balance'));
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
        $res->assertOk()->assertJson(['sent' => true]);
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
            'name' => 'جديد', 'email' => 'new@b.com', 'password' => 'secret6',
            'phone' => '0599', 'email_code' => $code,
        ])->assertStatus(422);

        // 2) retry with a FREE phone + the SAME code → succeeds (code still valid).
        $this->postJson('/api/auth/register', [
            'name' => 'جديد', 'email' => 'new@b.com', 'password' => 'secret6',
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
            'name' => 'ز', 'email' => 'z@b.com', 'password' => 'secret6',
            'phone' => '0588', 'email_code' => $wrong,
        ])->assertStatus(422);
        $this->assertNull(User::where('email', 'z@b.com')->first()); // no half-created account

        // The correct code still works afterwards (wrong attempt didn't consume it).
        $this->postJson('/api/auth/register', [
            'name' => 'ز', 'email' => 'z@b.com', 'password' => 'secret6',
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
            'name' => 'جديد', 'email' => 'new@b.com', 'password' => 'secret1',
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
            'password' => Hash::make('secret1'), 'role' => 'resident',
            'building_key' => 'residential',
        ]);

        $this->postJson('/api/auth/login', [
            'phone' => '+966500000077', 'password' => 'secret1',
        ])->assertOk()->assertJsonStructure(['token', 'user']);
    }

    // ─────────────── Residents: login_code in response ───────────────

    public function test_store_resident_returns_login_code(): void
    {
        $this->seedBuilding();
        $res = $this->actingAs($this->admin(), 'sanctum')->postJson('/api/residents', [
            'name' => 'ساكن جديد', 'phone' => '+966500001111', 'unit_no' => '101',
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
        $this->assertSame(-75, (int) $fresh->balance);
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
        // 100/month, contract started 5 full months ago → balance −500.
        $start = now()->subMonthsNoOverflow(5)->toDateString();
        $res = $this->actingAs($admin, 'sanctum')->postJson('/api/units', [
            'no' => '202', 'floor' => 2, 'resident' => 'بلال', 'kind' => 'مستأجر',
            'sub' => 100, 'contract_start' => $start, 'back_debt' => true,
        ]);
        $res->assertCreated();
        $this->assertSame(-500, (int) $res->json('balance'));
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
        $this->assertDatabaseHas('alerts', ['building_key' => 'residential', 'type' => 'elevator_check']);

        // Disable it → the reminder disappears on the next regenerate.
        $this->actingAs($admin, 'sanctum')->putJson('/api/building', ['elevator_check_notify' => false])->assertOk();
        $this->actingAs($admin, 'sanctum')->postJson('/api/alerts/regenerate')->assertOk();
        $this->assertDatabaseMissing('alerts', ['building_key' => 'residential', 'type' => 'elevator_check']);
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
}
