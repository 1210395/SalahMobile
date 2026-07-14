<?php

namespace Tests\Feature;

use App\Models\Building;
use App\Models\Subscription;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

// عمارتي — identity on the PUBLIC routes (GET /building, GET /subscription).
//
// Those two sit OUTSIDE the `auth:sanctum` group, so the app's default guard
// (session-based `web`) is the active one and `$r->user()` is null even when a
// valid Bearer token is present. Every caller therefore resolved to "the first
// building of this type" — someone else's building — no matter which building
// they actually owned.
//
// Two traps make this bug invisible to a careless test, and BOTH must be
// avoided or the test passes against broken code:
//
//  1. actingAs($u, 'sanctum') calls Auth::shouldUse('sanctum'), which swaps the
//     default guard for the whole request. Use a real Authorization header.
//  2. The app boots ONCE per test method and the AuthManager is shared across
//     the requests inside it — so ANY earlier request through an `auth:sanctum`
//     route (e.g. POST /building/setup) leaves the default guard set to sanctum
//     and the later public GET starts resolving tokens. In production each
//     request is a fresh process. So the public GET must be the FIRST request
//     of the test: set the world up through the models, not through the API.
class PublicRouteIdentityTest extends TestCase
{
    use RefreshDatabase;

    private function bearer(User $u): array
    {
        return ['Authorization' => 'Bearer '.$u->createToken('app')->plainTextToken];
    }

    private function building(string $name): Building
    {
        return Building::create([
            'key' => 'residential', 'name' => $name, 'address' => 'عنوان',
            'type' => 'سكني', 'subscription' => 40, 'currency' => 'NIS', 'floors' => 6,
            'units_count' => 12, 'exchange_rate' => 3.75, 'elevator_fee' => 0, 'summary' => [],
        ]);
    }

    /// A freshly-registered manager: no building of their own yet.
    private function pendingManager(string $email): User
    {
        return User::create([
            'name' => 'مدير جديد', 'email' => $email,
            'password' => Hash::make('password'), 'role' => 'resident',
        ]);
    }

    private function adminOf(Building $b, string $email): User
    {
        return User::create([
            'name' => 'مدير', 'email' => $email, 'password' => Hash::make('password'),
            'role' => 'admin', 'building_id' => $b->id, 'building_key' => 'residential',
        ]);
    }

    /// An admin must see THEIR building — not merely the first residential row.
    public function test_building_returns_the_callers_own_building_not_the_first_one(): void
    {
        $other = $this->building('عمارة شخص آخر');   // the first residential row
        $mine = $this->building('برج المدير الجديد');
        $mgr = $this->adminOf($mine, 'mgr@test.app');

        $res = $this->withHeaders($this->bearer($mgr))
            ->getJson('/api/building?btype=residential')->assertOk();

        $this->assertSame($mine->id, $res->json('id'));
        $this->assertSame('برج المدير الجديد', $res->json('name'));
        $this->assertNotSame($other->id, $res->json('id'));
    }

    /// A resident is likewise locked to their own building.
    public function test_building_returns_a_residents_own_building(): void
    {
        $this->building('عمارة شخص آخر');
        $mine = $this->building('برج الساكن');
        $resident = User::create([
            'name' => 'ساكن', 'email' => 'res@test.app', 'password' => Hash::make('password'),
            'role' => 'resident', 'building_id' => $mine->id, 'building_key' => 'residential',
            'unit_no' => '101',
        ]);

        $this->withHeaders($this->bearer($resident))
            ->getJson('/api/building?btype=residential')
            ->assertOk()->assertJsonPath('name', 'برج الساكن');
    }

    /// The subscription status must be the caller's own, not the first building's.
    public function test_subscription_reflects_the_callers_own_building(): void
    {
        $other = $this->building('عمارة شخص آخر');
        Subscription::create([
            'building_id' => $other->id, 'building_key' => 'residential',
            'status' => 'inactive', 'plan' => 'سنوي', 'amount' => 299,
        ]);
        $mine = $this->building('برجي');
        Subscription::create([
            'building_id' => $mine->id, 'building_key' => 'residential',
            'status' => 'active', 'plan' => 'سنوي', 'amount' => 299,
            'activated_at' => now(), 'expires_at' => now()->addYear(),
        ]);
        $mgr = $this->adminOf($mine, 'mgr2@test.app');

        $this->withHeaders($this->bearer($mgr))->getJson('/api/subscription')
            ->assertOk()->assertJsonPath('status', 'active');
    }

    /// A guest belongs to no building — so they get an EMPTY shell, never a real
    /// one. This used to hand `curl /api/building` (no token whatsoever) a real
    /// customer's name, address and elevator phone.
    public function test_guest_without_a_token_gets_an_empty_shell_not_a_real_building(): void
    {
        $this->building('عمارة شخص آخر');
        Building::where('name', 'عمارة شخص آخر')
            ->update(['address' => 'شارع سرّي 12', 'elevator_phone' => '+970599000111']);

        $res = $this->getJson('/api/building?btype=residential')->assertOk();

        $this->assertSame(0, $res->json('id'));
        $this->assertSame('', $res->json('name'));
        $this->assertSame('', $res->json('address'));
        $this->assertSame('', $res->json('elevator_phone'));
        $this->assertStringNotContainsString('شارع سرّي', $res->getContent());
        $this->assertStringNotContainsString('+970599000111', $res->getContent());
    }

    /// Same for a signed-in manager who hasn't set a building up yet: mid-onboarding
    /// is not a licence to see someone else's building.
    public function test_a_manager_without_a_building_gets_an_empty_shell(): void
    {
        $this->building('عمارة شخص آخر');
        $pending = $this->pendingManager('pending@test.app');

        $res = $this->withHeaders($this->bearer($pending))
            ->getJson('/api/building?btype=residential')->assertOk();

        $this->assertSame(0, $res->json('id'));
        $this->assertSame('', $res->json('name'));
    }

    /// The join picker's directory: names + types only, and never public.
    public function test_building_directory_requires_auth_and_exposes_no_addresses(): void
    {
        $b = $this->building('برج النخيل');
        Building::where('id', $b->id)->update([
            'address' => 'شارع سرّي 12', 'elevator_phone' => '+970599000111',
        ]);

        $this->getJson('/api/buildings')->assertUnauthorized();

        $res = $this->withHeaders($this->bearer($this->pendingManager('picker@test.app')))
            ->getJson('/api/buildings')->assertOk();

        $this->assertSame('برج النخيل', $res->json('0.name'));
        $this->assertSame($b->id, $res->json('0.id'));
        $this->assertStringNotContainsString('شارع سرّي', $res->getContent());
        $this->assertStringNotContainsString('+970599000111', $res->getContent());
    }

    /// A building nobody has set up yet (an empty seeded shell) is not joinable, so
    /// it must not clutter the picker.
    public function test_building_directory_omits_nameless_shells(): void
    {
        $this->building('برج حقيقي');
        Building::create([
            'key' => 'commercial', 'name' => '', 'address' => '', 'type' => 'تجاري',
            'subscription' => 0, 'currency' => 'NIS', 'floors' => 0, 'units_count' => 0,
            'exchange_rate' => 3.75, 'elevator_fee' => 0, 'summary' => [],
        ]);

        $res = $this->withHeaders($this->bearer($this->pendingManager('picker2@test.app')))
            ->getJson('/api/buildings')->assertOk();

        $this->assertCount(1, $res->json());
        $this->assertSame('برج حقيقي', $res->json('0.name'));
    }
}
