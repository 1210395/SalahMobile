{{-- عمارتي — verification / password-reset code. Deliberately plain: inline
     styles only, RTL, no images and no links, so it renders everywhere and
     nothing in it can be mistaken for a phishing call to action. --}}
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head><meta charset="utf-8"><title>عمارتي</title></head>
<body style="margin:0;padding:24px;background:#F4F6FA;font-family:Tahoma,Arial,sans-serif;color:#1B2233;">
  <div style="max-width:480px;margin:0 auto;background:#FFFFFF;border-radius:16px;padding:28px;">
    <div style="font-size:22px;font-weight:bold;color:#232858;">عمارتي</div>
    <div style="font-size:13px;color:#6B7280;margin-top:4px;">إدارة العمارات السكنية والمجمعات التجارية</div>

    <p style="font-size:15px;line-height:1.9;margin-top:24px;">
      @if($purpose === 'reset')
        وصلنا طلب لإعادة تعيين كلمة المرور لحسابك. استخدم الرمز التالي لإتمام العملية:
      @else
        استخدم الرمز التالي لتأكيد بريدك الإلكتروني:
      @endif
    </p>

    <div style="font-size:34px;font-weight:bold;letter-spacing:8px;color:#232858;background:#F4F6FA;
                border-radius:12px;padding:16px;text-align:center;margin:20px 0;">{{ $code }}</div>

    <p style="font-size:13px;color:#6B7280;line-height:1.9;">
      الرمز صالح لمدة {{ $minutes }} دقائق ويُستخدم مرة واحدة.
      لا تُشارك هذا الرمز مع أي شخص — فريق عمارتي لن يطلبه منك أبداً.
    </p>
    <p style="font-size:13px;color:#6B7280;line-height:1.9;">
      إذا لم تطلب هذا الرمز، تجاهل هذه الرسالة ولن يحدث أي تغيير على حسابك.
    </p>
  </div>
</body>
</html>
