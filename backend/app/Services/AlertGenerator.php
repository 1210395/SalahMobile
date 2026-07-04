<?php

namespace App\Services;

use App\Models\Alert;
use App\Models\Payment;
use App\Models\Unit;
use Illuminate\Support\Facades\Log;

// عمارتي — automated alerts engine. Recomputes a building's alerts from live
// data (overdue units, recent payments) plus standing reminders, then "sends"
// each alert through its channel. Real SMS/WhatsApp/push providers plug into
// [send()] — by default delivery is logged so the engine is functional without
// external credentials.
class AlertGenerator
{
    /// Regenerate the full alert set for [bk]. Returns the number created.
    public function regenerate(string $bk): int
    {
        // Refresh ONLY the auto-derived alerts. Manager-composed notifications
        // (type = 'notice', sent to residents) are real messages — regenerating
        // must not wipe them.
        Alert::where('building_key', $bk)->where('type', '!=', 'notice')->delete();

        $created = [];

        // 1) Overdue subscriptions — derived from current unit balances.
        $late = Unit::where('building_key', $bk)
            ->where('status', 'late')->orderBy('no')->get();
        foreach ($late as $u) {
            $created[] = $this->make($bk, [
                'type' => 'subscription', 'icon' => 'wallet', 'tone' => 'late',
                'title' => 'اشتراك متأخر — وحدة '.$u->no,
                'body' => $u->resident.' متأخر عن السداد بمبلغ $'.number_format(abs($u->balance)).'.',
                'time_label' => 'الآن', 'channel' => 'whatsapp',
                // Addressed to that unit only — a resident must never see a
                // neighbour's name + debt in their own notifications.
                'target' => $u->no,
            ]);
        }

        // 2) Standing operational reminders.
        foreach ([
            ['contract', 'elevator', 'warn', 'عقد صيانة المصعد', 'يُنصح بمراجعة عقد صيانة المصعد دورياً.', 'internal'],
            ['insurance', 'shield', 'warn', 'تأمين المبنى', 'تأكد من سريان وثيقة تأمين المبنى.', 'internal'],
            ['cleaning', 'broom', 'navy', 'أجور النظافة', 'استحقاق دفعة شركة النظافة قريباً.', 'internal'],
        ] as $a) {
            $created[] = $this->make($bk, [
                'type' => $a[0], 'icon' => $a[1], 'tone' => $a[2],
                'title' => $a[3], 'body' => $a[4], 'time_label' => 'اليوم', 'channel' => $a[5],
            ]);
        }

        // 3) Latest received payment (positive confirmation).
        $pay = Payment::where('building_key', $bk)->orderByDesc('date')->first();
        if ($pay) {
            $created[] = $this->make($bk, [
                'type' => 'paid', 'icon' => 'checkCircle', 'tone' => 'ok',
                'title' => 'تم استلام دفعة',
                'body' => $pay->name.' — وحدة '.$pay->unit_no.' سدّد $'.number_format($pay->amount).'.',
                'time_label' => 'مؤخراً', 'channel' => 'internal',
                // Payment confirmation is for that unit (+ the admin), not a
                // building-wide broadcast of who paid what.
                'target' => $pay->unit_no,
            ]);
        }

        foreach ($created as $alert) {
            $this->send($alert);
        }

        return count($created);
    }

    private function make(string $bk, array $attrs): Alert
    {
        return Alert::create(array_merge(['building_key' => $bk], $attrs));
    }

    /// Delivery hook. Plug a real provider here (Twilio / Meta WhatsApp / FCM).
    /// For now delivery is logged so the engine runs without credentials.
    private function send(Alert $alert): void
    {
        Log::info('amarati.alert.dispatch', [
            'channel' => $alert->channel,
            'building' => $alert->building_key,
            'title' => $alert->title,
        ]);
    }
}
