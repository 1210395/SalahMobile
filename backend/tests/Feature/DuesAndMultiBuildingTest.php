<?php

namespace Tests\Feature;

use App\Models\Building;
use App\Models\PayType;
use App\Models\Unit;
use Carbon\Carbon;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

// عمارتي — the ذمم/اشتراكات split, the editable ذمة, the resident statement,
// and the same person held in more than one building.
class DuesAndMultiBuildingTest extends TestCase
{
    use RefreshDatabase;

    private function building(string $name = 'عمارة أ', string $key = 'residential'): Building
    {
        $b = Building::create([
            'key' => $key, 'name' => $name, 'address' => 'عنوان', 'type' => 'سكني',
            'subscription' => 40, 'currency' => 'NIS', 'floors' => 4, 'units_count' => 8,
            'exchange_rate' => 3.75, 'elevator_fee' => 0, 'summary' => [],
        ]);
        PayType::seedDefaults($b->id);

        return $b;
    }

    private function admin(Building $b, string $email = 'admin@test.app'): User
    {
        return User::create([
            'name' => 'مدير', 'email' => $email, 'password' => Hash::make('password'),
            'role' => 'admin', 'building_key' => $b->key, 'building_id' => $b->id,
        ]);
    }

    /// A unit owing [dues] (the entered ذمة, passed positive) and billed [sub] a
    /// month from [billingStart].
    private function unit(Building $b, int $dues = 0, int $sub = 0, ?string $billingStart = null): Unit
    {
        return Unit::create([
            'building_key' => $b->key, 'building_id' => $b->id, 'ext_id' => 'A1', 'no' => '101',
            'floor' => 1, 'resident' => 'ساكن', 'kind' => 'مستأجر', 'phone' => '0599000001',
            'sub' => $sub, 'status' => 'ok', 'balance' => -$dues, 'opening_balance' => -$dues,
            'billing_start' => $billingStart, 'payer' => 'الساكن',
        ]);
    }

    private function pay(User $admin, array $attrs): array
    {
        return $this->actingAs($admin, 'sanctum')->postJson('/api/payments', array_merge([
            'unit_no' => '101', 'month' => 0, 'year' => (int) now()->year,
            'date' => now()->toDateString(), 'method' => 'نقداً',
        ], $attrs))->assertCreated()->json();
    }

    // ─────────────── فصل الذمم عن الاشتراك الشهري ───────────────

    // The whole point of the split: being ahead on the subscription must not make
    // an open ذمة disappear. Netted into one number, this unit read "credit".
    public function test_a_subscription_credit_never_hides_an_open_dues_debt(): void
    {
        $b = $this->building();
        $admin = $this->admin($b);
        $this->unit($b, dues: 700, sub: 100, billingStart: now()->startOfMonth()->toDateString());

        $this->pay($admin, ['amount' => 400, 'kind' => 'دفعة شهرية', 'bucket' => 'sub']);

        $u = $this->actingAs($admin, 'sanctum')->getJson('/api/units')->json()[0];
        $this->assertSame(-700, (int) $u['dues_balance']);   // ذمة untouched
        $this->assertSame(300, (int) $u['sub_balance']);     // 400 paid − 100 accrued
        $this->assertSame('late', $u['status']);             // owes on a pot ⇒ late
    }

    public function test_each_pot_is_settled_only_by_its_own_payments(): void
    {
        $b = $this->building();
        $admin = $this->admin($b);
        $this->unit($b, dues: 700, sub: 100, billingStart: now()->startOfMonth()->toDateString());

        $this->pay($admin, ['amount' => 200, 'kind' => 'ذمم', 'bucket' => 'dues']);
        $u = $this->actingAs($admin, 'sanctum')->getJson('/api/units')->json()[0];
        $this->assertSame(-500, (int) $u['dues_balance']);
        $this->assertSame(-100, (int) $u['sub_balance']);

        $this->pay($admin, ['amount' => 100, 'kind' => 'دفعة شهرية', 'bucket' => 'sub']);
        $u = $this->actingAs($admin, 'sanctum')->getJson('/api/units')->json()[0];
        $this->assertSame(-500, (int) $u['dues_balance']);
        $this->assertSame(0, (int) $u['sub_balance']);
    }

    // A fielded APK predates `bucket` and only sends kind + applies_to_dues.
    public function test_an_older_client_still_files_its_payments_correctly(): void
    {
        $b = $this->building();
        $admin = $this->admin($b);
        $this->unit($b, dues: 700, sub: 100, billingStart: now()->startOfMonth()->toDateString());

        $this->pay($admin, ['amount' => 100, 'kind' => 'ذمم']);                 // → dues
        $this->pay($admin, ['amount' => 100, 'kind' => 'دفعة شهرية']);          // → sub
        $this->pay($admin, ['amount' => 50, 'kind' => 'أخرى', 'applies_to_dues' => false]); // → none

        $u = $this->actingAs($admin, 'sanctum')->getJson('/api/units')->json()[0];
        $this->assertSame(-600, (int) $u['dues_balance']);
        $this->assertSame(0, (int) $u['sub_balance']);
    }

    public function test_an_income_only_line_settles_neither_pot(): void
    {
        $b = $this->building();
        $admin = $this->admin($b);
        $this->unit($b, dues: 300, sub: 0);

        $this->pay($admin, ['amount' => 500, 'kind' => 'أخرى', 'bucket' => 'none']);

        $u = $this->actingAs($admin, 'sanctum')->getJson('/api/units')->json()[0];
        $this->assertSame(-300, (int) $u['dues_balance']);
        $this->assertSame(0, (int) $u['sub_balance']);
    }

    // ─────────────── تعديل الذمة / الدفعة ───────────────

    public function test_an_entered_dues_figure_can_be_corrected_after_the_fact(): void
    {
        $b = $this->building();
        $admin = $this->admin($b);
        $unit = $this->unit($b, dues: 700);

        $this->actingAs($admin, 'sanctum')->putJson("/api/units/{$unit->id}", [
            'no' => '101', 'floor' => 1, 'opening_balance' => -250,
        ])->assertOk();

        $u = $this->actingAs($admin, 'sanctum')->getJson('/api/units')->json()[0];
        $this->assertSame(-250, (int) $u['dues_balance']);
        $this->assertSame(-250, (int) $u['opening_balance']);
    }

    public function test_a_payment_filed_against_the_wrong_pot_can_be_moved(): void
    {
        $b = $this->building();
        $admin = $this->admin($b);
        $this->unit($b, dues: 700, sub: 100, billingStart: now()->startOfMonth()->toDateString());
        $p = $this->pay($admin, ['amount' => 300, 'kind' => 'دفعة شهرية', 'bucket' => 'sub']);

        $this->actingAs($admin, 'sanctum')
            ->putJson("/api/payments/{$p['id']}", ['bucket' => 'dues', 'amount' => 250])
            ->assertOk();

        $u = $this->actingAs($admin, 'sanctum')->getJson('/api/units')->json()[0];
        $this->assertSame(-450, (int) $u['dues_balance']);   // 700 − 250
        $this->assertSame(-100, (int) $u['sub_balance']);    // the month is owed again
    }

    // ─────────────── كشف حساب الساكن ───────────────

    public function test_the_statement_keeps_the_pots_apart_and_never_returns_a_password(): void
    {
        $b = $this->building();
        $admin = $this->admin($b);
        $unit = $this->unit($b, dues: 700, sub: 100, billingStart: now()->startOfMonth()->toDateString());
        User::create([
            'name' => 'ساكن', 'phone' => '0599000001', 'password' => Hash::make('secret123'),
            'role' => 'resident', 'building_key' => $b->key, 'building_id' => $b->id,
            'unit_no' => '101', 'login_code' => 'ABCDEF0123456789ABCDEF0123456789',
        ]);
        $this->pay($admin, ['amount' => 200, 'kind' => 'ذمم', 'bucket' => 'dues']);

        $res = $this->actingAs($admin, 'sanctum')->getJson("/api/units/{$unit->id}/statement");
        $res->assertOk();

        $this->assertSame(-500, (int) $res->json('dues.balance'));
        $this->assertSame(-100, (int) $res->json('sub.balance'));
        $this->assertCount(1, $res->json('dues.payments'));
        $this->assertCount(0, $res->json('sub.payments'));
        $this->assertTrue($res->json('resident.has_password'));
        $this->assertSame('ABCDEF0123456789ABCDEF0123456789', $res->json('resident.login_code'));
        // The hash itself must never leave the server.
        $res->assertJsonMissingPath('resident.password');
        $this->assertStringNotContainsString('$2y$', $res->getContent());

        // A dated statement: the ذمة, the month's charge, then the payment.
        $this->assertSame(-700, (int) $res->json('entries.0.amount'));
        $this->assertSame(-500, (int) $res->json('entries.2.running_dues'));
    }

    public function test_a_resident_cannot_read_a_statement(): void
    {
        $b = $this->building();
        $unit = $this->unit($b, dues: 100);
        $resident = User::create([
            'name' => 'ساكن', 'phone' => '0599000009', 'password' => Hash::make('secret123'),
            'role' => 'resident', 'building_key' => $b->key, 'building_id' => $b->id, 'unit_no' => '101',
        ]);

        $this->actingAs($resident, 'sanctum')
            ->getJson("/api/units/{$unit->id}/statement")->assertForbidden();
    }

    // ─────────────── نفس الشخص في أكثر من بناية ───────────────

    public function test_the_same_person_can_be_added_to_two_buildings(): void
    {
        $a = $this->building('عمارة أ');
        $b = $this->building('عمارة ب');
        $adminA = $this->admin($a, 'a@test.app');
        $adminB = $this->admin($b, 'b@test.app');

        $this->actingAs($adminA, 'sanctum')->postJson('/api/residents', [
            'name' => 'سالم', 'phone' => '0599111222', 'password' => 'secret123',
        ])->assertCreated();

        // The same number, in a different building — this used to be refused.
        $this->actingAs($adminB, 'sanctum')->postJson('/api/residents', [
            'name' => 'سالم', 'phone' => '0599111222', 'password' => 'secret456',
        ])->assertCreated();

        // …but still only once WITHIN a building.
        $this->actingAs($adminB, 'sanctum')->postJson('/api/residents', [
            'name' => 'سالم مكرر', 'phone' => '0599111222', 'password' => 'secret789',
        ])->assertStatus(422);
    }

    public function test_login_offers_a_building_choice_when_one_number_opens_several(): void
    {
        $a = $this->building('عمارة أ');
        $b = $this->building('عمارة ب');
        foreach ([$a, $b] as $bld) {
            User::create([
                'name' => 'سالم', 'phone' => '0599111222', 'password' => Hash::make('secret123'),
                'role' => 'resident', 'building_key' => $bld->key, 'building_id' => $bld->id,
            ]);
        }

        $res = $this->postJson('/api/auth/login', ['phone' => '0599111222', 'password' => 'secret123']);
        $res->assertOk()->assertJsonMissingPath('token');
        $this->assertCount(2, $res->json('choose'));
        $this->assertSame('عمارة ب', $res->json('choose.1.building_name'));

        // Naming the building signs that account in.
        $picked = $this->postJson('/api/auth/login', [
            'phone' => '0599111222', 'password' => 'secret123', 'building_id' => $b->id,
        ])->assertOk();
        $this->assertNotEmpty($picked->json('token'));
        $this->assertSame($b->id, $picked->json('user.building_id'));
        $this->assertSame('عمارة ب', $picked->json('user.building_name'));
    }

    public function test_a_wrong_password_is_still_refused_when_the_number_repeats(): void
    {
        $a = $this->building('عمارة أ');
        $b = $this->building('عمارة ب');
        foreach ([$a, $b] as $bld) {
            User::create([
                'name' => 'سالم', 'phone' => '0599111222', 'password' => Hash::make('secret123'),
                'role' => 'resident', 'building_key' => $bld->key, 'building_id' => $bld->id,
            ]);
        }

        $this->postJson('/api/auth/login', ['phone' => '0599111222', 'password' => 'nope'])
            ->assertStatus(422);
    }

    // ─────────────── الصنايعية: a building's own directory ───────────────

    public function test_the_craftsmen_directory_is_scoped_to_the_building(): void
    {
        $a = $this->building('عمارة أ');
        $b = $this->building('عمارة ب');
        $adminA = $this->admin($a, 'a@test.app');
        $adminB = $this->admin($b, 'b@test.app');

        $made = $this->actingAs($adminA, 'sanctum')->postJson('/api/craftsmen', [
            'name' => 'أبو علي', 'job' => 'كهربائي', 'phone' => '0599000123',
        ])->assertCreated()->json();

        // A's entry is A's alone — it used to appear in every building.
        $this->assertCount(1, $this->actingAs($adminA, 'sanctum')->getJson('/api/craftsmen')->json());
        $this->assertCount(0, $this->actingAs($adminB, 'sanctum')->getJson('/api/craftsmen')->json());

        // …and B cannot delete it through the URL.
        $this->actingAs($adminB, 'sanctum')
            ->deleteJson("/api/craftsmen/{$made['id']}")->assertForbidden();

        // A can — a wrong number was previously permanent.
        $this->actingAs($adminA, 'sanctum')
            ->deleteJson("/api/craftsmen/{$made['id']}")->assertOk();
        $this->assertCount(0, $this->actingAs($adminA, 'sanctum')->getJson('/api/craftsmen')->json());
    }

    public function test_an_account_holding_the_buildings_money_needs_a_longer_password(): void
    {
        $b = $this->building();
        $admin = $this->admin($b);

        $this->actingAs($admin, 'sanctum')->postJson('/api/co-admins', [
            'name' => 'شريك', 'email' => 'partner@test.app', 'password' => 'short1',
        ])->assertStatus(422)->assertJsonValidationErrors('password');

        $this->actingAs($admin, 'sanctum')->postJson('/api/co-admins', [
            'name' => 'شريك', 'email' => 'partner@test.app', 'password' => 'longenough1',
        ])->assertCreated();

        // A renter's password stays short on purpose — the manager hands it over.
        $this->actingAs($admin, 'sanctum')->postJson('/api/residents', [
            'name' => 'ساكن', 'phone' => '0599777888', 'password' => 'six123',
        ])->assertCreated();
    }

    // ─────────────── the building's month is the LOCAL month ───────────────

    /// A unit is billed by whole months, so which month "now" falls in decides
    /// what every resident owes. On a UTC clock the first three hours after
    /// local midnight on the 1st still belong to the previous month, and every
    /// balance in the building read one month light until breakfast.
    public function test_a_new_month_starts_at_local_midnight_not_utc_midnight(): void
    {
        $this->assertSame('Asia/Hebron', config('app.timezone'),
            'the platform bills in Palestine local time');

        $b = $this->building();
        $unit = Unit::create([
            'building_id' => $b->id, 'building_key' => $b->key, 'ext_id' => 'A1',
            'no' => '101', 'floor' => 1, 'resident' => 'ساكن', 'kind' => 'مالك',
            'phone' => '-', 'sub' => 100, 'status' => 'ok', 'balance' => 0,
            'opening_balance' => 0, 'payer' => 'الساكن', 'billing_start' => '2026-01-01',
        ]);

        // 00:30 on 1 March, Palestine - which is still 22:30 on 28 February UTC.
        Carbon::setTestNow(Carbon::parse('2026-03-01 00:30:00', 'Asia/Hebron'));

        // January, February AND March: three months, not two.
        $this->assertSame(3, $unit->monthsBilled());
        $this->assertSame(300, $unit->charges());

        Carbon::setTestNow();
    }
}
