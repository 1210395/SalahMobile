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
        $amount = (int) round(((float) config('amarati.payments.amount')) * 100);
        abort_if($amount <= 0, 503, 'لم يتم تحديد قيمة الاشتراك بعد');

        // An unpaid checkout that is still valid is reused rather than piling up
        // half-finished payments every time somebody taps the button twice.
        $existing = SubscriptionPayment::where('user_id', $user->id)
            ->where('status', 'pending')->where('expires_at', '>', now())
            ->latest('id')->first();
        abort_if($existing !== null, 409,
            'هناك عملية دفع جارية — أكملها أو انتظر انتهاء صلاحيتها');

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
            if (! $fresh || ! $fresh->isPayable()) {
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

    /// Turn a settled payment into an active subscription.
    private function activate(SubscriptionPayment $payment): void
    {
        if (! $payment->building_id) {
            // The manager pays during onboarding, before their building exists.
            // setupBuilding() creates the subscription row; the payment is
            // already recorded against them and is what unlocks that step.
            return;
        }

        $days = (int) config('amarati.payments.period_days', 365);

        Subscription::updateOrCreate(
            ['building_id' => $payment->building_id],
            [
                'status' => 'active',
                'amount' => (int) round($payment->amount / 100),
                'payment_ref' => $payment->reference,
                'activated_at' => now(),
                'expires_at' => now()->addDays($days),
            ],
        );
    }
}
