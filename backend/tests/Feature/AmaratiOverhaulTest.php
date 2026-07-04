<?php

namespace Tests\Feature;

use App\Models\Building;
use App\Models\EmailCode;
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
        $res = $this->getJson('/api/summary');
        $res->assertOk();
        $this->assertCount(12, $res->json('trend'));
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
