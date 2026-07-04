<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>دعوة للانضمام — عمارتي</title>
    <style>
        :root { --navy:#232858; --navy700:#2b3168; --gold:#C2A24E; --ink:#1a1d33; --bg:#f4f5fa; }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { font-family: -apple-system, "Segoe UI", Tahoma, sans-serif; background: var(--bg); color: var(--ink);
               min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 20px; }
        .card { background: #fff; border-radius: 22px; max-width: 420px; width: 100%; padding: 32px 26px;
                box-shadow: 0 18px 50px rgba(35,40,88,.14); text-align: center; }
        .brand { color: var(--navy); font-size: 30px; font-weight: 800; letter-spacing: -.5px; }
        .sub { color: #6b6f88; font-size: 14px; margin-top: 6px; }
        .hero { background: linear-gradient(135deg, var(--navy), var(--navy700)); color: #fff;
                border-radius: 16px; padding: 22px 18px; margin: 22px 0; }
        .hero h1 { font-size: 19px; font-weight: 700; }
        .hero p { font-size: 13.5px; color: #c9cce4; margin-top: 8px; line-height: 1.7; }
        .code { font-family: ui-monospace, "SF Mono", monospace; letter-spacing: 2px; font-size: 20px;
                font-weight: 700; color: var(--gold); background: rgba(194,162,78,.12);
                border: 1px dashed var(--gold); border-radius: 12px; padding: 12px; margin-top: 14px; }
        .steps { text-align: right; margin: 20px 4px; }
        .steps li { list-style: none; display: flex; gap: 10px; align-items: flex-start; margin: 12px 0;
                    font-size: 14px; color: #33374f; line-height: 1.6; }
        .num { flex: 0 0 26px; height: 26px; border-radius: 50%; background: var(--navy); color: #fff;
               font-size: 13px; font-weight: 700; display: flex; align-items: center; justify-content: center; }
        .btn { display: block; background: var(--gold); color: #201a06; font-weight: 800; font-size: 15px;
               text-decoration: none; padding: 15px; border-radius: 14px; margin-top: 8px; }
        .foot { color: #9296b0; font-size: 12px; margin-top: 18px; }
    </style>
</head>
<body>
    <div class="card">
        <div class="brand">عمارتي</div>
        <div class="sub">إدارة العمارات السكنية والمجمعات التجارية</div>

        <div class="hero">
            <h1>تمّت دعوتك للانضمام إلى مبناك</h1>
            <p>حمّل تطبيق عمارتي، ثم سجّل الدخول عبر رمز الدخول (QR) الذي زوّدك به مسؤول العمارة.</p>
            @if(!empty($code))
                <div class="code">{{ $code }}</div>
            @endif
        </div>

        <ol class="steps">
            <li><span class="num">1</span><span>حمّل تطبيق عمارتي على هاتفك من الزر بالأسفل.</span></li>
            <li><span class="num">2</span><span>افتح التطبيق واختر «كود الدخول / QR».</span></li>
            <li><span class="num">3</span><span>امسح رمز الـ QR من مسؤول العمارة أو أدخل رمز الدخول الخاص بك.</span></li>
        </ol>

        <a class="btn" href="{{ $appUrl }}">تحميل التطبيق</a>
        <div class="foot">إن لم تكن لديك دعوة، تواصل مع مسؤول عمارتك للحصول على رمز الدخول.</div>
    </div>
</body>
</html>
