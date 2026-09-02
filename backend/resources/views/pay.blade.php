<!doctype html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    <title>الدفع — سكن برو</title>
    <style>
        /* Matches the app the payer just came from: the same dark surface and
           purple, so opening this page does not look like leaving the product. */
        :root {
            --page: #17121f; --surface: #211a2c; --line: #362c46;
            --ink: #f2eef8; --ink-dim: #a99cbb;
            --brand: #7e42b4; --brand-soft: #9a63cc;
            --ok: #3f9a72; --bad: #c1443d;
        }
        * { box-sizing: border-box; }
        body {
            margin: 0; background: var(--page); color: var(--ink);
            font-family: "Cairo", "Segoe UI", system-ui, sans-serif;
            min-height: 100vh; display: flex; align-items: center; justify-content: center;
            padding: 20px;
        }
        .card {
            width: 100%; max-width: 440px; background: var(--surface);
            border: 1px solid var(--line); border-radius: 18px; padding: 22px;
        }
        .brand { font-size: 1.35rem; font-weight: 700; margin: 0 0 2px; }
        .sub { color: var(--ink-dim); font-size: .86rem; margin: 0 0 18px; }
        .amount {
            display: flex; align-items: baseline; gap: 8px; justify-content: center;
            background: #1a1424; border: 1px solid var(--line); border-radius: 14px;
            padding: 16px; margin-bottom: 18px;
        }
        .amount b { font-size: 2rem; font-weight: 800; letter-spacing: -.5px; }
        .amount span { color: var(--ink-dim); font-size: .95rem; }
        .ref { color: var(--ink-dim); font-size: .74rem; text-align: center; margin-top: 6px; }
        /* CyberSource renders its own form inside these. */
        #buttonPaymentListContainer { min-height: 60px; }
        #embeddedPaymentContainer { margin-top: 14px; }
        .note { color: var(--ink-dim); font-size: .78rem; line-height: 1.7; margin-top: 18px; text-align: center; }
        .msg { padding: 14px; border-radius: 12px; font-size: .9rem; line-height: 1.7; margin-top: 14px; display: none; }
        .msg.show { display: block; }
        .msg.bad { background: rgba(193,68,61,.14); border: 1px solid rgba(193,68,61,.4); }
        .msg.ok  { background: rgba(63,154,114,.14); border: 1px solid rgba(63,154,114,.4); }
        .center { text-align: center; }
        .spinner {
            width: 22px; height: 22px; margin: 18px auto; border-radius: 50%;
            border: 3px solid var(--line); border-top-color: var(--brand-soft);
            animation: spin .8s linear infinite; display: none;
        }
        .spinner.show { display: block; }
        @keyframes spin { to { transform: rotate(360deg); } }
    </style>
</head>
<body>
<div class="card">
    <p class="brand">سكن برو</p>

    @if ($state !== 'ready')
        <p class="sub">الدفع الإلكتروني</p>
        <div class="msg bad show">{{ $message }}</div>
        <p class="note">يمكنك إغلاق هذه الصفحة والعودة إلى التطبيق.</p>
    @else
        <p class="sub">اشتراك إدارة العمارة</p>

        <div class="amount">
            <b>{{ $amount }}</b><span>{{ $currency }}</span>
        </div>
        <p class="ref">رقم العملية: {{ $reference }}</p>

        <div id="buttonPaymentListContainer"></div>
        <div id="embeddedPaymentContainer"></div>
        <div class="spinner" id="spin"></div>
        <div class="msg" id="msg"></div>

        <p class="note">
            تُدخل بيانات البطاقة مباشرة لدى مزوّد الدفع، ولا تمرّ عبر خوادم سكن برو.
        </p>

        @if ($library['url'])
            <script
                src="{{ $library['url'] }}"
                @if ($library['integrity']) integrity="{{ $library['integrity'] }}" crossorigin="anonymous" @endif
            ></script>
        @endif

        <script>
            (function () {
                var captureContext = @json($captureContext);
                var completeUrl = @json(route('pay.complete', ['token' => $token]));
                var csrf = @json(csrf_token());

                var msg = document.getElementById('msg');
                var spin = document.getElementById('spin');

                function say(text, kind) {
                    msg.textContent = text;
                    msg.className = 'msg show ' + (kind || 'bad');
                }
                function busy(on) { spin.className = on ? 'spinner show' : 'spinner'; }

                if (typeof Accept !== 'function') {
                    say('تعذّر تحميل نموذج الدفع. تحقّق من اتصالك وأعد المحاولة.');
                    return;
                }

                Accept(captureContext)
                    .then(function (accept) { return accept.unifiedPayments(); })
                    .then(function (up) {
                        return up.show({
                            containers: {
                                paymentSelection: '#buttonPaymentListContainer',
                                paymentScreen: '#embeddedPaymentContainer'
                            }
                        });
                    })
                    .then(function (transientToken) {
                        // The card itself never reaches us — this token stands in
                        // for it, for a few minutes, for this one payment.
                        busy(true);
                        return fetch(completeUrl, {
                            method: 'POST',
                            headers: {
                                'Content-Type': 'application/json',
                                'Accept': 'application/json',
                                'X-CSRF-TOKEN': csrf
                            },
                            body: JSON.stringify({ transient_token: transientToken })
                        }).then(function (r) {
                            return r.json().then(function (body) { return { ok: r.ok, body: body }; });
                        });
                    })
                    .then(function (res) {
                        busy(false);
                        if (res.body && res.body.paid) {
                            say('تم الدفع بنجاح. يمكنك العودة إلى التطبيق.', 'ok');
                            document.getElementById('buttonPaymentListContainer').style.display = 'none';
                            document.getElementById('embeddedPaymentContainer').style.display = 'none';
                            // The app watches for this to close the browser view.
                            if (window.SakanPro && window.SakanPro.postMessage) {
                                window.SakanPro.postMessage('paid');
                            }
                            location.hash = 'paid';
                        } else {
                            say((res.body && res.body.message) || 'تعذّر إتمام الدفع.');
                        }
                    })
                    .catch(function (e) {
                        busy(false);
                        // A payer who closes the card form is not an error worth shouting about.
                        if (e && (e.reason === 'CANCELLED' || e.message === 'CANCELLED')) { return; }
                        say('تعذّر إتمام الدفع. حاول مرة أخرى.');
                    });
            })();
        </script>
    @endif
</div>
</body>
</html>
