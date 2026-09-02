<?php

namespace App\Mail;

use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

// عمارتي — the verification / password-reset code e-mail.
class VerificationCodeMail extends Mailable
{
    use Queueable, SerializesModels;

    public function __construct(
        public string $code,
        public string $purpose = 'register',
        public int $minutes = 10,
    ) {}

    public function envelope(): Envelope
    {
        return new Envelope(subject: $this->purpose === 'reset'
            ? 'سكن برو — رمز إعادة تعيين كلمة المرور'
            : 'سكن برو — رمز التحقق');
    }

    public function content(): Content
    {
        return new Content(view: 'emails.code', with: [
            'code' => $this->code,
            'purpose' => $this->purpose,
            'minutes' => $this->minutes,
        ]);
    }
}
