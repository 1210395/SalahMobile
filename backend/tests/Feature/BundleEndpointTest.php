<?php

namespace Tests\Feature;

use App\Models\Building;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

// سكن برو — the app draws its first screen from ONE request now.
//
// If a section quietly disappears from /bundle the app renders an empty
// building and looks broken, so pin the section list; and pin the rule that a
// section the signed-in user may not read is ABSENT rather than fatal — that is
// what kept a resident's screen loading when the sections were separate calls.
class BundleEndpointTest extends TestCase
{
    use RefreshDatabase;

    private const SECTIONS = [
        'building', 'summary', 'units', 'payments', 'expenses', 'workers',
        'parking', 'guard', 'alerts', 'craftsmen', 'wa_templates',
        'pay_types', 'year_summary',
    ];

    private function building(): Building
    {
        return Building::create([
            'key' => 'residential', 'name' => 'برج التجربة', 'address' => 'عنوان',
            'type' => 'سكني', 'subscription' => 40, 'currency' => 'NIS',
            'floors' => 6, 'units_count' => 12, 'exchange_rate' => 3.75,
            'elevator_fee' => 0, 'summary' => [],
        ]);
    }

    private function userOf(Building $b, string $role, string $email): User
    {
        return User::create([
            'name' => 'مستخدم', 'email' => $email, 'password' => Hash::make('password'),
            'role' => $role, 'building_id' => $b->id, 'building_key' => $b->key,
        ]);
    }

    public function test_bundle_returns_every_section_the_app_needs(): void
    {
        Sanctum::actingAs($this->userOf($this->building(), 'admin', 'a@t.local'));

        $body = $this->getJson('/api/bundle')->assertOk()->json();

        foreach (self::SECTIONS as $section) {
            $this->assertArrayHasKey($section, $body, "/bundle dropped '$section'");
        }
        $this->assertSame('برج التجربة', $body['building']['name'] ?? null);
    }

    public function test_a_resident_still_gets_a_bundle_when_a_section_is_forbidden(): void
    {
        Sanctum::actingAs($this->userOf($this->building(), 'renter', 'r@t.local'));

        $body = $this->getJson('/api/bundle')->assertOk()->json();

        // Their building loads; anything they may not read is simply missing.
        $this->assertNotNull($body['building'] ?? null);
        foreach (self::SECTIONS as $section) {
            $this->assertArrayHasKey($section, $body);
        }
    }

    public function test_bundle_needs_a_token(): void
    {
        $this->getJson('/api/bundle')->assertUnauthorized();
    }
}
