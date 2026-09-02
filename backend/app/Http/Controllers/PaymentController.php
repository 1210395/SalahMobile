<?php

namespace App\Http\Controllers;

use App\Models\Subscription;
use App\Models\SubscriptionPayment;
use App\Services\CyberSource;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

// سكن برو — taking the subscription payment.
//
// The card is entered on a page WE serve but a form CYBERSOURCE renders, inside
// its own iframe. We never receive a card number: the browser hands back a
// transient token that stands for the card for a few minutes, and that is what
// gets charged. The app opens this page in a browser rather than embedding a
// card form, which is what keeps the mobile build out of PCI scope entirely.
class PaymentController extends Controller
{
    /// Begin a checkout. Returns the URL the app should open.
    ///
    /// Only a manager pays, and only for their own building — the amount comes
    /// from configuration, never from the request, so a crafted call cannot buy
    /// a subscription for a penny.
    public function checkout(Request $r)
    {
        abort_unless(CyberSource::isConfigured(), 503,
            'الدفع الإلكتروني غير متاح حالياً — تواصل مع مسؤول النظام');

        $user = $r->user();
        $amount = CyberSource::configuredAmount();
        abort_if($amount === null, 503, 'لم يتم تحديد قيمة الاشتراك بعد');

        // Somebody who opened a checkout and closed the browser used to be told
        // to wait a quarter of an hour, with no way to start again. Their older
        // links are retired instead — which also means only ONE live link exists
        // per person at a time, so there is never a second one to be charged on.
        SubscriptionPayment::where('user_id', $user->id)
            ->where('status', 'pending')->where('expires_at', '>', now())
            ->update(['expires_at' => now()->subSecond()]);

        [$payment, $token] = SubscriptionPayment::start(
            $user->building_id, $user->id, $amount,
            config('amarati.payments.currency'),
            (int) config('amarati.payments.checkout_ttl_minutes'),
        );

        return response()->json([
            'url' => route('pay.show', ['token' => $token]),
            'reference' => $payment->reference,
            'amount' => $payment->majorAmount(),
            'currency' => $payment->currency,
            'expires_at' => $payment->expires_at,
        ]);
    }

    /// How the caller's most recent checkout ended.
    ///
    /// The payment happens in a browser, so the app cannot see the outcome — it
    /// asks here when it comes back. During onboarding there is no building and
    /// therefore no subscription row yet, so this is the only place the answer
    /// exists.
    public function status(Request $r)
    {
        $payment = SubscriptionPayment::where('user_id', $r->user()->id)
            ->latest('id')->first();

        if (! $payment) {
            return response()->json(['status' => 'none', 'paid' => false]);
        }

        return response()->json([
            'status' => $payment->status,
            'paid' => $payment->status === 'paid',
            'reference' => $payment->reference,
            'amount' => $payment->majorAmount(),
            'currency' => $payment->currency,
            'paid_at' => $payment->paid_at,
        ]);
    }

    /// The hosted card page.
    public function show(string $token)
    {
        $payment = SubscriptionPayment::forToken($token);

        if (! $payment || ! $payment->isPayable()) {
            // Deliberately identical for "never existed", "already paid" and
            // "expired": a stranger guessing links learns nothing from the
            // difference, and the honest user is told what to do either way.
            return response()->view('pay', [
                'state' => 'unavailable',
                'message' => 'انتهت صلاحية رابط الدفع أو تم استخدامه — ابدأ عملية دفع جديدة من التطبيق.',
            ], 410);
        }

        try {
            $context = app(CyberSource::class)->captureContext(
                rtrim(config('app.url'), '/'),
                $payment->reference,
                $payment->majorAmount(),
                $payment->currency,
            );
        } catch (\Throwable $e) {
            Log::error('amarati.pay.context', ['reference' => $payment->reference, 'error' => $e->getMessage()]);

            return response()->view('pay', [
                'state' => 'unavailable',
                'message' => 'تعذّر بدء عملية الدفع حالياً — حاول مرة أخرى بعد قليل.',
            ], 503);
        }

        return view('pay', [
            'state' => 'ready',
            'captureContext' => $context,
            'library' => CyberSource::clientLibrary($context),
            'token' => $token,
            'amount' => $payment->majorAmount(),
            'currency' => $payment->currency,
            'reference' => $payment->reference,
        ]);
    }

    /// Charge the transient token the card form produced.
    public function complete(Request $r, string $token)
    {
        $data = $r->validate(['transient_token' => 'required|string|max:8000']);

        $payment = SubscriptionPayment::forToken($token);
        if (! $payment) {
            return response()->json(['paid' => false, 'message' => 'رابط دفع غير صالح'], 404);
        }

        // Claim the row before talking to the bank. Two taps that arrive at once
        // would otherwise both pass isPayable() and both charge the card; the
        // second one now finds the row already claimed and stops.
        $claimed = DB::transaction(function () use ($payment) {
            $fresh = SubscriptionPayment::whereKey($payment->id)->lockForUpdate()->first();
            if (! $fresh || ! $fresh->isClaimable()) {
                return null;
            }
            $fresh->update(['status' => 'charging']);

            return $fresh;
        });

        if (! $claimed) {
            return response()->json([
                'paid' => false,
                'message' => 'هذه العملية غير قابلة للدفع — قد تكون اكتملت أو انتهت صلاحيتها',
            ], 409);
        }

        try {
            $result = app(CyberSource::class)->pay(
                $data['transient_token'], $claimed->reference,
                $claimed->majorAmount(), $claimed->currency,
            );
        } catch (\Throwable $e) {
            // The charge never left, so the payment goes back to payable rather
            // than being stranded in 'charging' forever.
            $claimed->update(['status' => 'pending', 'failure_reason' => 'gateway_unreachable']);
            Log::error('amarati.pay.unreachable', ['reference' => $claimed->reference, 'error' => $e->getMessage()]);

            return response()->json(['paid' => false, 'message' => 'تعذّر الوصول إلى بوابة الدفع — حاول مرة أخرى'], 502);
        }

        if (! $result['paid']) {
            $claimed->update([
                'status' => 'failed',
                'gateway_id' => $result['id'],
                'gateway_status' => $result['status'],
                'failure_reason' => $result['reason'],
            ]);

            return response()->json([
                'paid' => false,
                'message' => 'لم تتم الموافقة على البطاقة — جرّب بطاقة أخرى أو تواصل مع البنك',
            ], 402);
        }

        $claimed->update([
            'status' => 'paid',
            'gateway_id' => $result['id'],
            'gateway_status' => $result['status'],
            'paid_at' => now(),
        ]);
        $this->activate($claimed);

        return response()->json(['paid' => true, 'reference' => $claimed->reference]);
    }

    /// Attach a payment made before the building existed, and activate it.
    ///
    /// Called from building setup. Without it, a manager who paid during
    /// onboarding would have the money taken and no subscription to show for
    /// it — the payment row had nowhere to point.
    public static function claimForBuilding(int $userId, int $buildingId): void
    {
        $paid = SubscriptionPayment::where('user_id', $userId)
            ->whereNull('building_id')->where('status', 'paid')
            ->latest('id')->first();

        if (! $paid) {
            return;
        }

        $paid->update(['building_id' => $buildingId]);
        (new self)->activate($paid->fresh());
    }

    /// Turn a settled payment into an active subscription.
    private function activate(SubscriptionPayment $payment): void
    {
        if (! $payment->building_id) {
            // Paid during onboarding, before the building exists. There is
            // nothing to attach it to yet, so claimForBuilding() below picks it
            // up the moment the building is created — otherwise the money is
            // taken and the subscription never turns on.
            return;
        }

        $days = (int) config('amarati.payments.period_days', 365);
        $current = Subscription::where('building_id', $payment->building_id)->first();

        // Renewing early EXTENDS rather than restarts. Setting expiry to
        // now()+period would quietly bin whatever was left of the term they had
        // already paid for — the person who renews a month early loses a month.
        $from = ($current?->expires_at && $current->expires_at->isFuture())
            ? $current->expires_at
            : now();

        Subscription::updateOrCreate(
            ['building_id' => $payment->building_id],
            [
                'status' => 'active',
                'amount' => (int) round($payment->amount / 100),
                'payment_ref' => $payment->reference,
                'activated_at' => $current?->activated_at ?? now(),
                'expires_at' => $from->copy()->addDays($days),
            ],
        );
    }
}
