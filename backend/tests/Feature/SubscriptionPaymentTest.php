<?php

namespace Tests\Feature;

use App\Models\Building;
use App\Models\Subscription;
use App\Models\SubscriptionPayment;
use App\Models\User;
use App\Services\CyberSource;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Http;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

// سكن برو — taking real money for a subscription.
//
// The rules that matter are the ones that cost somebody money when they break:
// a card is charged once and only once, a decline never grants a subscription,
// and an unconfigured gateway offers no payment at all rather than a form that
// cannot work.
class SubscriptionPaymentTest extends TestCase
{
    use RefreshDatabase;

    private function configured(): void
    {
        config([
            'amarati.payments.merchant_id' => 'test_merchant',
            'amarati.payments.key_id' => 'test-key-id',
            'amarati.payments.secret_key' => base64_encode('test-secret'),
            'amarati.payments.amount' => '25.00',
            'amarati.payments.currency' => 'USD',
        ]);
    }

    private function manager(?Building $b = null): User
    {
        return User::create([
            'name' => 'مدير', 'email' => 'boss@test.app', 'password' => Hash::make('password'),
            'role' => 'admin', 'building_id' => $b?->id, 'building_key' => $b?->key,
        ]);
    }

    private function building(): Building
    {
        return Building::create([
            'key' => 'residential', 'name' => 'برج', 'address' => 'عنوان', 'type' => 'سكني',
            'subscription' => 40, 'currency' => 'NIS', 'floors' => 6, 'units_count' => 12,
            'exchange_rate' => 3.75, 'elevator_fee' => 0, 'summary' => [],
        ]);
    }

    /// A capture context is a JWT whose middle segment carries the SDK location.
    private function fakeContext(): string
    {
        $payload = base64_encode(json_encode(['ctx' => [['data' => [
            'clientLibrary' => 'https://apitest.cybersource.com/up/v1/assets/0.24.0/SDK.js',
            'clientLibraryIntegrity' => 'sha256-abc',
        ]]]]));

        return 'header.'.rtrim(strtr($payload, '+/', '-_'), '=').'.signature';
    }

    // ───────────────────────── it must not half-exist ─────────────────────────

    public function test_no_gateway_means_no_payment_is_offered(): void
    {
        config(['amarati.payments.merchant_id' => null, 'amarati.payments.key_id' => null,
            'amarati.payments.secret_key' => null]);
        Sanctum::actingAs($this->manager($this->building()));

        $this->postJson('/api/subscription/checkout')->assertStatus(503);
        $this->assertFalse(CyberSource::isConfigured());
    }

    public function test_a_price_of_zero_is_refused_rather_than_charged(): void
    {
        $this->configured();
        config(['amarati.payments.amount' => '0.00']);
        Sanctum::actingAs($this->manager($this->building()));

        $this->postJson('/api/subscription/checkout')->assertStatus(503);
    }

    public function test_checkout_needs_a_signed_in_manager(): void
    {
        $this->configured();
        $this->postJson('/api/subscription/checkout')->assertUnauthorized();
    }

    // ───────────────────────── the amount is ours ─────────────────────────

    /// The price comes from configuration and is never read from the request —
    /// otherwise a crafted call buys a year's subscription for one cent.
    public function test_the_caller_cannot_choose_what_to_pay(): void
    {
        $this->configured();
        Sanctum::actingAs($this->manager($this->building()));

        $this->postJson('/api/subscription/checkout', ['amount' => '0.01', 'currency' => 'XXX'])
            ->assertOk()
            ->assertJson(['amount' => '25.00', 'currency' => 'USD']);

        $this->assertSame(2500, SubscriptionPayment::first()->amount);
    }

    /// Starting again retires the previous link rather than refusing.
    ///
    /// Refusing dead-ended anyone who opened a checkout and closed the browser:
    /// they were told to wait a quarter of an hour with no way to start over.
    /// Retiring is also the safer half — exactly one live link exists per
    /// person, so there is never a second one left to be charged on.
    public function test_starting_again_retires_the_previous_link(): void
    {
        $this->configured();
        Sanctum::actingAs($this->manager($this->building()));

        $first = basename(parse_url(
            $this->postJson('/api/subscription/checkout')->json('url'), PHP_URL_PATH));
        $second = basename(parse_url(
            $this->postJson('/api/subscription/checkout')->assertOk()->json('url'), PHP_URL_PATH));

        $this->assertNotSame($first, $second);

        // The abandoned one is dead; only the new one can take a payment.
        $this->get("/pay/$first")->assertStatus(410);
        $this->assertTrue(SubscriptionPayment::forToken($second)->isPayable());

        Http::fake(['*/pts/v2/payments' => Http::response(['id' => 'P', 'status' => 'AUTHORIZED'], 201)]);
        $this->postJson("/pay/$first", ['transient_token' => 'tt.jwt'])->assertStatus(409);
        Http::assertNothingSent();
    }

    // ───────────────────────── the link is a credential ─────────────────────────

    /// The secret in the URL opens a payment, so it is stored hashed — a leaked
    /// database must not yield working payment links.
    public function test_the_checkout_secret_is_never_stored_in_the_clear(): void
    {
        $this->configured();
        Sanctum::actingAs($this->manager($this->building()));

        $url = $this->postJson('/api/subscription/checkout')->json('url');
        $token = basename(parse_url($url, PHP_URL_PATH));

        $row = SubscriptionPayment::first();
        $this->assertNotSame($token, $row->token_hash);
        $this->assertSame(hash('sha256', $token), $row->token_hash);
    }

    public function test_an_unknown_or_spent_link_says_the_same_thing(): void
    {
        $this->configured();
        $this->get('/pay/'.str_repeat('a', 48))->assertStatus(410)->assertSee('انتهت صلاحية', false);
    }

    // ───────────────────────── charging ─────────────────────────

    private function openCheckout(): string
    {
        Sanctum::actingAs($this->manager($this->building()));
        $url = $this->postJson('/api/subscription/checkout')->json('url');

        return basename(parse_url($url, PHP_URL_PATH));
    }

    public function test_an_approved_card_activates_the_subscription(): void
    {
        $this->configured();
        $token = $this->openCheckout();

        Http::fake(['*/pts/v2/payments' => Http::response(
            ['id' => 'PAY123', 'status' => 'AUTHORIZED'], 201)]);

        $this->postJson("/pay/$token", ['transient_token' => 'tt.jwt.here'])
            ->assertOk()->assertJson(['paid' => true]);

        $row = SubscriptionPayment::first();
        $this->assertSame('paid', $row->status);
        $this->assertSame('PAY123', $row->gateway_id);
        $this->assertNotNull($row->paid_at);

        $sub = Subscription::where('building_id', $row->building_id)->first();
        $this->assertSame('active', $sub->status);
        $this->assertSame($row->reference, $sub->payment_ref);
    }

    public function test_a_declined_card_grants_nothing(): void
    {
        $this->configured();
        $token = $this->openCheckout();

        Http::fake(['*/pts/v2/payments' => Http::response(
            ['id' => 'PAY124', 'status' => 'DECLINED',
                'errorInformation' => ['reason' => 'INSUFFICIENT_FUND']], 402)]);

        $this->postJson("/pay/$token", ['transient_token' => 'tt.jwt.here'])
            ->assertStatus(402)->assertJson(['paid' => false]);

        $this->assertSame('failed', SubscriptionPayment::first()->status);
        $this->assertSame(0, Subscription::where('status', 'active')->count());
    }

    /// A hold is not money taken. Treating it as paid hands out a subscription
    /// the bank may still reverse.
    public function test_a_review_hold_is_not_treated_as_paid(): void
    {
        $this->configured();
        $token = $this->openCheckout();

        Http::fake(['*/pts/v2/payments' => Http::response(
            ['id' => 'PAY125', 'status' => 'AUTHORIZED_PENDING_REVIEW'], 201)]);

        $this->postJson("/pay/$token", ['transient_token' => 'tt.jwt.here'])->assertStatus(402);
        $this->assertSame(0, Subscription::where('status', 'active')->count());
    }

    /// The one that actually costs somebody money: a card must be charged once.
    public function test_the_same_link_cannot_charge_a_card_twice(): void
    {
        $this->configured();
        $token = $this->openCheckout();

        Http::fake(['*/pts/v2/payments' => Http::response(
            ['id' => 'PAY126', 'status' => 'AUTHORIZED'], 201)]);

        $this->postJson("/pay/$token", ['transient_token' => 'tt.jwt.here'])->assertOk();
        $this->postJson("/pay/$token", ['transient_token' => 'tt.jwt.here'])->assertStatus(409);

        Http::assertSentCount(1);
    }

    /// An unreachable gateway leaves the payment payable rather than stranding it.
    public function test_an_unreachable_gateway_leaves_the_payment_retryable(): void
    {
        $this->configured();
        $token = $this->openCheckout();

        Http::fake(fn () => throw new \Illuminate\Http\Client\ConnectionException('down'));

        $this->postJson("/pay/$token", ['transient_token' => 'tt.jwt.here'])->assertStatus(502);
        $this->assertTrue(SubscriptionPayment::first()->isPayable());
    }

    // ───────────────────────── request signing ─────────────────────────

    /// The bank rejects anything mis-signed, so the signature is worth pinning:
    /// an HMAC over exactly these headers, in this order, keyed with the
    /// base64-DECODED secret.
    public function test_requests_are_signed_the_way_the_bank_expects(): void
    {
        $this->configured();
        Http::fake(['*/pts/v2/payments' => Http::response(['id' => 'X', 'status' => 'AUTHORIZED'], 201)]);

        app(CyberSource::class)->pay('tt.jwt', 'SP-REF', '25.00', 'USD');

        Http::assertSent(function ($request) {
            $sig = $request->header('Signature')[0] ?? '';
            $digest = $request->header('Digest')[0] ?? '';
            $date = $request->header('Date')[0] ?? '';

            $this->assertStringContainsString('keyid="test-key-id"', $sig);
            $this->assertStringContainsString('algorithm="HmacSHA256"', $sig);
            $this->assertStringContainsString(
                'headers="host date (request-target) digest v-c-merchant-id"', $sig);

            // The digest must cover the body that was actually sent.
            $this->assertSame('SHA-256='.base64_encode(hash('sha256', $request->body(), true)), $digest);

            // Recompute the MAC independently.
            preg_match('/signature="([^"]+)"/', $sig, $m);
            $expected = base64_encode(hash_hmac('sha256', implode("\n", [
                'host: apitest.cybersource.com',
                'date: '.$date,
                '(request-target): post /pts/v2/payments',
                'digest: '.$digest,
                'v-c-merchant-id: test_merchant',
            ]), 'test-secret', true));
            $this->assertSame($expected, $m[1]);

            return true;
        });
    }

    public function test_the_sdk_location_is_read_from_the_capture_context(): void
    {
        $lib = CyberSource::clientLibrary($this->fakeContext());

        $this->assertSame('https://apitest.cybersource.com/up/v1/assets/0.24.0/SDK.js', $lib['url']);
        $this->assertSame('sha256-abc', $lib['integrity']);
    }

    // ═══════════════ the edges where money actually goes wrong ═══════════════

    /// The dangerous case is not a decline, it is a LOST ANSWER: the card is
    /// charged and the response never arrives. The retry that follows must
    /// carry an idempotency key, or it charges the card a second time.
    public function test_a_charge_carries_an_idempotency_key(): void
    {
        $this->configured();
        Http::fake(['*/pts/v2/payments' => Http::response(['id' => 'X', 'status' => 'AUTHORIZED'], 201)]);

        app(CyberSource::class)->pay('tt.jwt', 'SP-ABC123', '25.00', 'USD');

        Http::assertSent(fn ($request) => ($request->header('v-c-idempotency-id')[0] ?? null) === 'SP-ABC123');
    }

    /// A process that dies between claiming the row and hearing back leaves it
    /// "charging". Refusing forever strands the payer with a dead link and money
    /// that may or may not have moved; retrying is safe because of the key above.
    public function test_a_payment_stuck_mid_charge_becomes_retryable(): void
    {
        $this->configured();
        $token = $this->openCheckout();
        $payment = SubscriptionPayment::first();

        // It died mid-charge, moments ago.
        $payment->update(['status' => 'charging']);
        $this->assertFalse($payment->fresh()->isClaimable(), 'too soon to assume it is dead');

        $this->postJson("/pay/$token", ['transient_token' => 'tt.jwt'])->assertStatus(409);

        // …and after the grace period another attempt may take it.
        $payment->forceFill(['updated_at' => now()->subMinutes(
            SubscriptionPayment::STUCK_AFTER_MINUTES + 1)])->saveQuietly();

        Http::fake(['*/pts/v2/payments' => Http::response(['id' => 'PAY9', 'status' => 'AUTHORIZED'], 201)]);
        $this->postJson("/pay/$token", ['transient_token' => 'tt.jwt'])->assertOk();
        $this->assertSame('paid', SubscriptionPayment::first()->status);
    }

    /// A thousand-dollar price written with a comma, read through a plain float
    /// cast, is 1.0 — charged as one dollar, silently, and never in our favour.
    public function test_a_price_that_cannot_be_read_exactly_is_refused(): void
    {
        $this->configured();
        Sanctum::actingAs($this->manager($this->building()));

        foreach (['1,000.00', '25.999', 'free', '', '-25.00', '25,00'] as $bad) {
            config(['amarati.payments.amount' => $bad]);
            $this->assertNull(CyberSource::configuredAmount(), "[$bad] must not parse as a price");
            $this->postJson('/api/subscription/checkout')->assertStatus(503);
        }

        config(['amarati.payments.amount' => '1000.00']);
        $this->assertSame(100000, CyberSource::configuredAmount());
    }

    /// Renewing early must EXTEND. Setting expiry to now()+period quietly bins
    /// whatever was left of the term already paid for.
    public function test_renewing_early_extends_rather_than_restarts(): void
    {
        $this->configured();
        $b = $this->building();
        $user = $this->manager($b);
        $existing = Subscription::create([
            'building_id' => $b->id, 'building_key' => $b->key, 'status' => 'active',
            'activated_at' => now()->subDays(300), 'expires_at' => now()->addDays(65),
        ]);

        Sanctum::actingAs($user);
        $token = basename(parse_url($this->postJson('/api/subscription/checkout')->json('url'), PHP_URL_PATH));
        Http::fake(['*/pts/v2/payments' => Http::response(['id' => 'PAYR', 'status' => 'AUTHORIZED'], 201)]);
        $this->postJson("/pay/$token", ['transient_token' => 'tt.jwt'])->assertOk();

        // 65 days left plus a year, not a year from today.
        $this->assertEqualsWithDelta(
            365 + 65, now()->diffInDays($existing->fresh()->expires_at), 1,
            'renewing early threw away the remaining term');
    }

    // ─────────── a subscription must never be free once we charge ───────────

    /// Setting a building up used to activate its subscription outright, on the
    /// reasoning that reaching that screen meant the (simulated) payment had
    /// happened. Once real money is involved that is a free subscription for
    /// anyone who calls the endpoint directly instead of paying.
    public function test_setting_up_a_building_without_paying_grants_nothing(): void
    {
        $this->configured();
        Sanctum::actingAs(User::create([
            'name' => 'مدير', 'email' => 'new@test.app', 'password' => Hash::make('password'),
            'role' => 'resident',
        ]));

        $this->postJson('/api/building/setup', [
            'btype' => 'residential', 'name' => 'برج', 'address' => 'عنوان',
            'floors' => 5, 'units_count' => 10,
        ])->assertOk();

        $this->assertSame('inactive', Subscription::first()->status);
    }

    /// A manager pays BEFORE their building exists, so the payment has nowhere
    /// to point until setup. Without picking it up, the money is taken and the
    /// subscription never turns on.
    public function test_a_payment_made_during_onboarding_activates_the_new_building(): void
    {
        $this->configured();
        $user = User::create([
            'name' => 'مدير', 'email' => 'new@test.app', 'password' => Hash::make('password'),
            'role' => 'resident',
        ]);
        Sanctum::actingAs($user);

        // Paid with no building yet.
        $token = basename(parse_url($this->postJson('/api/subscription/checkout')->json('url'), PHP_URL_PATH));
        Http::fake(['*/pts/v2/payments' => Http::response(['id' => 'PAYO', 'status' => 'AUTHORIZED'], 201)]);
        $this->postJson("/pay/$token", ['transient_token' => 'tt.jwt'])->assertOk();
        $this->assertNull(SubscriptionPayment::first()->building_id);

        $this->postJson('/api/building/setup', [
            'btype' => 'residential', 'name' => 'برج', 'address' => 'عنوان',
            'floors' => 5, 'units_count' => 10,
        ])->assertOk();

        $sub = Subscription::first();
        $this->assertSame('active', $sub->status);
        $this->assertSame(SubscriptionPayment::first()->reference, $sub->payment_ref);
        $this->assertNotNull(SubscriptionPayment::first()->building_id);
    }

    /// With no gateway the platform is not charging, so setting a building up is
    /// what activates it — the behaviour that predates payments must survive.
    public function test_without_a_gateway_a_building_is_still_activated(): void
    {
        config(['amarati.payments.merchant_id' => null, 'amarati.payments.key_id' => null,
            'amarati.payments.secret_key' => null]);
        Sanctum::actingAs(User::create([
            'name' => 'مدير', 'email' => 'new@test.app', 'password' => Hash::make('password'),
            'role' => 'resident',
        ]));

        $this->postJson('/api/building/setup', [
            'btype' => 'residential', 'name' => 'برج', 'address' => 'عنوان',
            'floors' => 5, 'units_count' => 10,
        ])->assertOk();

        $this->assertSame('active', Subscription::first()->status);
    }

    /// The card page authenticates on the secret in its URL, not on a session.
    /// A CSRF token adds nothing there and can answer 419 AFTER the card form
    /// already succeeded, spending the transient token for nothing.
    public function test_the_card_page_does_not_need_a_session(): void
    {
        $this->configured();
        $token = $this->openCheckout();
        Http::fake(['*/pts/v2/payments' => Http::response(['id' => 'PAYC', 'status' => 'AUTHORIZED'], 201)]);

        $this->post("/pay/$token", ['transient_token' => 'tt.jwt'],
            ['Accept' => 'application/json'])->assertOk();
    }
}
