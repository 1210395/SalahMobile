<?php

namespace Tests\Feature;

use App\Models\Building;
use App\Models\JoinRequest;
use App\Models\PayType;
use App\Models\Payment;
use App\Models\Unit;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Laravel\Sanctum\Sanctum;
use RuntimeException;
use Tests\TestCase;

// عمارتي — the "first building of this type" class of bug.
//
// building_key holds a TYPE ('residential'), not a unique id, so several
// buildings share one. Anywhere the code resolved a building from a key alone —
// Building::idForKey(), where('key', …)->first(), or the BelongsToBuilding hook
// — it silently landed on building #1 and quietly cross-wired tenants. Each test
// below pins one of those sites.
class MultiBuildingIsolationTest extends TestCase
{
    use RefreshDatabase;

    private function building(string $name, string $key = 'residential'): Building
    {
        return Building::create([
            'key' => $key, 'name' => $name, 'address' => 'عنوان',
            'type' => $key === 'residential' ? 'سكني' : 'تجاري',
            'subscription' => 40, 'currency' => 'NIS', 'floors' => 6, 'units_count' => 12,
            'exchange_rate' => 3.75, 'elevator_fee' => 0, 'summary' => [],
        ]);
    }

    private function adminOf(Building $b, string $email): User
    {
        return User::create([
            'name' => 'مدير', 'email' => $email, 'password' => Hash::make('password'),
            'role' => 'admin', 'building_id' => $b->id, 'building_key' => $b->key,
        ]);
    }

    // ───────────── the model hook must never guess ─────────────

    /// With two buildings of a type, a building_key cannot identify one — creating
    /// a row without building_id must fail loudly instead of picking building #1.
    public function test_the_trait_refuses_to_guess_a_building_when_the_key_is_ambiguous(): void
    {
        $this->building('الأولى');
        $this->building('الثانية');

        $this->expectException(RuntimeException::class);

        Unit::create([
            'building_key' => 'residential', 'ext_id' => 'A1', 'no' => '101', 'floor' => 1,
            'resident' => 'ساكن', 'kind' => 'مالك', 'phone' => '—', 'sub' => 40,
            'status' => 'ok', 'balance' => 0, 'opening_balance' => 0, 'payer' => 'الساكن',
        ]);
    }

    /// A single building of that type is unambiguous — the seeder and a fresh
    /// install depend on this still working.
    public function test_the_trait_still_derives_a_building_when_the_key_is_unambiguous(): void
    {
        $only = $this->building('الوحيدة');

        $unit = Unit::create([
            'building_key' => 'residential', 'ext_id' => 'A1', 'no' => '101', 'floor' => 1,
            'resident' => 'ساكن', 'kind' => 'مالك', 'phone' => '—', 'sub' => 40,
            'status' => 'ok', 'balance' => 0, 'opening_balance' => 0, 'payer' => 'الساكن',
        ]);

        $this->assertSame($only->id, $unit->building_id);
    }

    // ───────────── join requests ─────────────

    /// A join request must reach the building it names — not the first one.
    public function test_join_request_is_filed_against_the_named_building(): void
    {
        $other = $this->building('عمارة الغريب');   // first residential
        $mine = $this->building('عمارتي');
        $applicant = User::create([
            'name' => 'طالب', 'email' => 'applicant@test.app',
            'password' => Hash::make('password'), 'role' => 'resident',
        ]);

        $this->actingAs($applicant, 'sanctum')->postJson('/api/join-requests', [
            'btype' => 'residential', 'building_id' => $mine->id,
            'name' => 'طالب', 'phone' => '0599', 'unit_no' => '3',
        ])->assertCreated();

        $jr = JoinRequest::sole();
        $this->assertSame($mine->id, $jr->building_id);
        $this->assertNotSame($other->id, $jr->building_id);

        // ...and the right admin sees it, while the stranger's admin does not.
        $mineAdmin = $this->adminOf($mine, 'mine@test.app');
        $otherAdmin = $this->adminOf($other, 'other@test.app');
        $this->assertCount(1, $this->actingAs($mineAdmin, 'sanctum')
            ->getJson('/api/join-requests')->json());
        $this->assertCount(0, $this->actingAs($otherAdmin, 'sanctum')
            ->getJson('/api/join-requests')->json());
    }

    // ───────────── fee catalogue ─────────────

    /// Each building owns its fees: editing one must not move another's.
    public function test_editing_fees_does_not_touch_another_buildings_fees(): void
    {
        $a = $this->building('أ');
        $b = $this->building('ب');
        PayType::seedDefaults($a->id);
        PayType::seedDefaults($b->id);
        $adminA = $this->adminOf($a, 'a@test.app');

        $subA = PayType::where('building_id', $a->id)->where('key', 'sub')->sole();
        $subB = PayType::where('building_id', $b->id)->where('key', 'sub')->sole();

        $this->actingAs($adminA, 'sanctum')
            ->putJson("/api/pay-types/{$subA->id}", ['amount' => 999])->assertOk();

        $this->assertSame(999, (int) $subA->fresh()->amount);
        $this->assertSame(40, (int) $subB->fresh()->amount, 'building ب fees moved');
    }

    /// An admin must not be able to edit another building's fee row by id (IDOR).
    public function test_admin_cannot_edit_another_buildings_fee_row_by_id(): void
    {
        $a = $this->building('أ');
        $b = $this->building('ب');
        PayType::seedDefaults($a->id);
        PayType::seedDefaults($b->id);
        $adminA = $this->adminOf($a, 'a2@test.app');
        $subB = PayType::where('building_id', $b->id)->where('key', 'sub')->sole();

        $this->actingAs($adminA, 'sanctum')
            ->putJson("/api/pay-types/{$subB->id}", ['amount' => 777])->assertForbidden();

        $this->assertSame(40, (int) $subB->fresh()->amount);
    }

    /// GET /pay-types returns the caller's own catalogue.
    public function test_pay_types_are_scoped_to_the_caller(): void
    {
        $a = $this->building('أ');
        $b = $this->building('ب');
        PayType::seedDefaults($a->id);
        PayType::seedDefaults($b->id);
        PayType::where('building_id', $b->id)->where('key', 'sub')->update(['amount' => 555]);
        $adminB = $this->adminOf($b, 'b@test.app');

        $rows = $this->actingAs($adminB, 'sanctum')->getJson('/api/pay-types')->json();

        $this->assertCount(count(PayType::DEFAULTS), $rows);
        foreach ($rows as $row) {
            $this->assertSame($b->id, $row['building_id']);
        }
        $sub = collect($rows)->firstWhere('key', 'sub');
        $this->assertSame(555, (int) $sub['amount']);
    }

    /// Setting up a building gives it its own catalogue (the payment sheet needs it).
    public function test_building_setup_creates_that_buildings_own_fee_catalogue(): void
    {
        $this->building('عمارة قائمة');   // makes 'residential' ambiguous
        $mgr = User::create([
            'name' => 'مدير جديد', 'email' => 'new@test.app',
            'password' => Hash::make('password'), 'role' => 'resident',
        ]);

        $res = $this->actingAs($mgr, 'sanctum')->postJson('/api/building/setup', [
            'btype' => 'residential', 'name' => 'برج جديد', 'address' => 'ع',
            'floors' => 3, 'units_count' => 5,
        ])->assertOk();

        $newId = $res->json('building.id');
        $this->assertCount(
            count(PayType::DEFAULTS),
            PayType::where('building_id', $newId)->get(),
        );
    }

    // ───────────── super-admin ─────────────

    /// The platform report must cover EVERY building, not the first of each type.
    public function test_global_report_covers_every_building(): void
    {
        $this->building('سكني ١');
        $this->building('سكني ٢');
        $this->building('سكني ٣');
        $this->building('تجاري ١', 'commercial');
        $su = User::create([
            'name' => 'المدير العام', 'email' => 'su@test.app',
            'password' => Hash::make('password'), 'role' => 'superadmin',
        ]);

        $rows = $this->actingAs($su, 'sanctum')
            ->getJson('/api/reports/global')->assertOk()->json('buildings');

        $this->assertCount(4, $rows);
        $this->assertEqualsCanonicalizing(
            ['سكني ١', 'سكني ٢', 'سكني ٣', 'تجاري ١'],
            array_column($rows, 'name'),
        );
    }

    /// A new admin lands on the building the super-admin named...
    public function test_create_admin_attaches_to_the_named_building(): void
    {
        $this->building('الأولى');
        $target = $this->building('الهدف');
        $su = User::create([
            'name' => 'المدير العام', 'email' => 'su2@test.app',
            'password' => Hash::make('password'), 'role' => 'superadmin',
        ]);

        $this->actingAs($su, 'sanctum')->postJson('/api/admins', [
            'name' => 'مسؤول', 'email' => 'newadmin@test.app', 'password' => 'secret1234',
            'building_key' => 'residential', 'building_id' => $target->id,
        ])->assertCreated()->assertJsonPath('building_id', $target->id);
    }

    /// ...and when the type is ambiguous and no building is named, the request is
    /// refused rather than silently attached to building #1.
    public function test_create_admin_refuses_to_guess_between_buildings(): void
    {
        $this->building('الأولى');
        $this->building('الثانية');
        $su = User::create([
            'name' => 'المدير العام', 'email' => 'su3@test.app',
            'password' => Hash::make('password'), 'role' => 'superadmin',
        ]);

        $this->actingAs($su, 'sanctum')->postJson('/api/admins', [
            'name' => 'مسؤول', 'email' => 'newadmin2@test.app', 'password' => 'secret1234',
            'building_key' => 'residential',
        ])->assertStatus(422);

        $this->assertNull(User::where('email', 'newadmin2@test.app')->first());
    }

    // ─────────── money converts at the RIGHT building's currency ───────────

    /// The base currency decides what a foreign-currency payment is worth once
    /// stored, and it was resolved by building TYPE. With two residential
    /// buildings priced differently, one of them converted at the other's
    /// currency and banked the wrong number in the column its reports sum.
    public function test_a_payment_converts_at_its_own_buildings_currency(): void
    {
        // The FIRST residential building is the one a type lookup finds.
        $nis = $this->building('عمارة الشيكل');
        $jod = $this->building('عمارة الدينار');
        $jod->update(['currency' => 'JOD']);

        Unit::create([
            'building_id' => $jod->id, 'building_key' => $jod->key, 'ext_id' => 'B1',
            'no' => '201', 'floor' => 2, 'resident' => 'ساكن', 'kind' => 'مالك',
            'phone' => '-', 'sub' => 40, 'status' => 'ok', 'balance' => 0,
            'opening_balance' => 0, 'payer' => 'الساكن',
        ]);

        Sanctum::actingAs($this->adminOf($jod, 'jod@test.app'));

        // 100 NIS into a JOD building, at 5 NIS to the dinar → 500 dinars' worth
        // is NOT what was paid; the stored base amount must be the converted 500
        // only because the rate says so, and the currency kept must be NIS.
        $this->postJson('/api/payments', [
            'unit_no' => '201', 'name' => 'ساكن', 'amount' => 100,
            'original_amount' => 100, 'currency' => 'NIS', 'exchange_rate' => 5,
            'kind' => 'اشتراك شهري', 'month' => 0, 'year' => 2026,
            'date' => '2026-01-05', 'method' => 'نقداً', 'bucket' => 'sub',
        ])->assertCreated();

        $payment = Payment::where('building_id', $jod->id)->firstOrFail();

        // Converted, because NIS is not this building's base — the old code saw
        // the NIS building first, called them equal, and stored 100.
        $this->assertSame(500, (int) $payment->amount);
        $this->assertSame('NIS', $payment->currency);
        $this->assertSame(0, Payment::where('building_id', $nis->id)->count());
    }
}
