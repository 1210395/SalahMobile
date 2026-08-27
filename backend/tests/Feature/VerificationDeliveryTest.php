<?php

namespace Tests\Feature;

use App\Models\Building;
use App\Models\EmailCode;
use App\Models\User;
use App\Services\Notifier;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Mail;
use Tests\TestCase;

// عمارتي — real delivery of verification codes, and the password recovery that
// depends on it. The rule these tests protect: a code is either DELIVERED or
// echoed, never both, and never neither in silence.
class VerificationDeliveryTest extends TestCase
{
    use RefreshDatabase;

    private function building(string $name = 'عمارة أ'): Building
    {
        return Building::create([
            'key' => 'residential', 'name' => $name, 'address' => 'عنوان', 'type' => 'سكني',
            'subscription' => 40, 'currency' => 'NIS', 'floors' => 4, 'units_count' => 8,
            'exchange_rate' => 3.75, 'elevator_fee' => 0, 'summary' => [],
        ]);
    }

    private function manager(Building $b, string $email = 'manager@test.app'): User
    {
        return User::create([
            'name' => 'مدير', 'email' => $email, 'password' => Hash::make('password'),
            'role' => 'admin', 'building_key' => $b->key, 'building_id' => $b->id,
        ]);
    }

    // ─────────────── the code is delivered, and only echoed when it isn't ───────────────

    public function test_requesting_an_email_code_actually_sends_a_message(): void
    {
        Mail::fake();

        $this->postJson('/api/auth/request-email-code', ['email' => 'new@test.app'])
            ->assertOk()->assertJson(['sent' => true]);

        Mail::assertSentCount(1);
        // Stored hashed, never in the clear.
        $row = EmailCode::where('email', 'new@test.app')->first();
        $this->assertNotNull($row);
        $this->assertNotSame('123456', $row->code);
        $this->assertTrue(strlen($row->code) > 20);
    }

    public function test_a_configured_mailer_stops_the_code_being_echoed(): void
    {
        Mail::fake();

        // No provider: the echo is what keeps development usable.
        config(['mail.default' => 'log']);
        $this->assertFalse(Notifier::channelIsLive('mail'));
        $this->postJson('/api/auth/request-email-code', ['email' => 'a@test.app'])
            ->assertOk()->assertJsonStructure(['sent', 'dev_code']);

        // A real mailer wins over the flag — no env change required.
        config(['mail.default' => 'smtp', 'amarati.expose_otp_dev_code' => true]);
        $this->assertTrue(Notifier::channelIsLive('mail'));
        $this->postJson('/api/auth/request-email-code', ['email' => 'b@test.app'])
            ->assertOk()->assertJsonMissingPath('dev_code');
    }

    public function test_a_configured_sms_provider_stops_the_otp_being_echoed(): void
    {
        config(['amarati.sms.driver' => 'log']);
        $this->assertFalse(Notifier::channelIsLive('sms'));
        $this->postJson('/api/auth/request-otp', ['phone' => '0599111000'])
            ->assertOk()->assertJsonStructure(['sent', 'dev_code']);

        // Provider named but unusable (no credentials): the send fails AND the
        // echo is off, so the caller is told plainly rather than left waiting.
        config(['amarati.sms.driver' => 'twilio', 'amarati.sms.twilio.sid' => null]);
        $this->assertTrue(Notifier::channelIsLive('sms'));
        $this->postJson('/api/auth/request-otp', ['phone' => '0599111001'])
            ->assertStatus(503);
    }

    public function test_local_numbers_are_normalised_for_the_gateway(): void
    {
        $n = new Notifier();
        $this->assertSame('+970599123456', $n->normalisePhone('0599123456'));
        $this->assertSame('+970599123456', $n->normalisePhone('059 912 3456'));
        $this->assertSame('+970599123456', $n->normalisePhone('00970599123456'));
        $this->assertSame('+970599123456', $n->normalisePhone('+970599123456'));
    }

    // ─────────────── registration really confirms the address ───────────────

    public function test_registration_requires_a_confirmed_email_when_it_can_be_confirmed(): void
    {
        Mail::fake();
        config(['amarati.require_email_verification' => true]);

        $this->postJson('/api/auth/register', [
            'name' => 'مدير جديد', 'email' => 'boss@test.app', 'password' => 'secret123',
        ])->assertStatus(422)->assertJsonValidationErrors('email_code');

        $code = $this->postJson('/api/auth/request-email-code', ['email' => 'boss@test.app'])
            ->json('dev_code');

        $this->postJson('/api/auth/register', [
            'name' => 'مدير جديد', 'email' => 'boss@test.app', 'password' => 'secret123',
            'email_code' => $code,
        ])->assertCreated();

        $this->assertNotNull(User::where('email', 'boss@test.app')->value('email_verified_at'));
    }

    // ─────────────── password recovery ───────────────

    public function test_a_manager_can_recover_a_forgotten_password(): void
    {
        Mail::fake();
        $b = $this->building();
        $user = $this->manager($b);
        $oldToken = $user->createToken('old')->plainTextToken;

        $code = $this->postJson('/api/auth/forgot-password', ['email' => 'manager@test.app'])
            ->assertOk()->json('dev_code');
        $this->assertNotNull($code);

        // A wrong code changes nothing.
        $this->postJson('/api/auth/reset-password', [
            'email' => 'manager@test.app', 'code' => '000000', 'password' => 'brandnew1',
        ])->assertStatus(422);
        $this->assertTrue(Hash::check('password', $user->fresh()->password));

        $this->postJson('/api/auth/reset-password', [
            'email' => 'manager@test.app', 'code' => $code, 'password' => 'brandnew1',
        ])->assertOk()->assertJsonStructure(['token', 'user']);

        $this->assertTrue(Hash::check('brandnew1', $user->fresh()->password));
        // Every old session dies with the old password.
        $this->assertSame(0, $user->fresh()->tokens()->where('name', 'old')->count());
        $this->getJson('/api/me', ['Authorization' => "Bearer $oldToken"])->assertUnauthorized();
    }

    public function test_forgot_password_does_not_reveal_whether_an_account_exists(): void
    {
        Mail::fake();

        $known = $this->postJson('/api/auth/forgot-password', ['email' => 'nobody@test.app']);
        $known->assertOk()->assertJson(['sent' => true]);

        // Nothing was issued for an address with no account…
        $this->assertSame(0, EmailCode::where('email', 'nobody@test.app')->count());
        // …and the answer is indistinguishable from the real one.
        $this->assertNull($known->json('dev_code'));
        Mail::assertNothingSent();
    }

    public function test_reset_asks_which_building_when_one_email_has_several_accounts(): void
    {
        Mail::fake();
        $a = $this->building('عمارة أ');
        $b = $this->building('عمارة ب');
        $this->manager($a, 'shared@test.app');
        $this->manager($b, 'shared@test.app');

        $code = $this->postJson('/api/auth/forgot-password', ['email' => 'shared@test.app'])->json('dev_code');

        $choose = $this->postJson('/api/auth/reset-password', [
            'email' => 'shared@test.app', 'code' => $code, 'password' => 'brandnew1',
        ])->assertOk();
        $this->assertCount(2, $choose->json('choose'));

        // The code survived the question — the second call still works.
        $this->postJson('/api/auth/reset-password', [
            'email' => 'shared@test.app', 'code' => $code, 'password' => 'brandnew1',
            'building_id' => $b->id,
        ])->assertOk();

        $this->assertTrue(Hash::check('brandnew1',
            User::where('email', 'shared@test.app')->where('building_id', $b->id)->value('password')));
        // The other building's account is untouched.
        $this->assertTrue(Hash::check('password',
            User::where('email', 'shared@test.app')->where('building_id', $a->id)->value('password')));
    }

    public function test_the_sms_echo_can_be_closed_while_email_stays_usable(): void
    {
        // The live shape after this audit: no provider on either channel, but the
        // SMS echo (the account-takeover path) switched off on its own.
        config([
            'amarati.expose_sms_dev_code' => false,
            'amarati.expose_email_dev_code' => true,
            'amarati.sms.driver' => 'log',
            'mail.default' => 'array',
        ]);
        $this->app['env'] = 'production';   // the echo's local/testing shortcut is off

        $this->postJson('/api/auth/request-otp', ['phone' => '0599111222'])
            ->assertOk()->assertJsonMissingPath('dev_code');

        $this->postJson('/api/auth/request-email-code', ['email' => 'x@test.app'])
            ->assertOk()->assertJsonStructure(['sent', 'dev_code']);
    }
}
