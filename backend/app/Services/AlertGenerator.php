<?php

namespace App\Services;

use App\Models\Alert;
use App\Models\Building;
use App\Models\Payment;
use App\Models\Unit;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Log;

// عمارتي — automated alerts engine. Recomputes a building's alerts from live
// data (overdue units, recent payments) plus standing reminders, then "sends"
// each alert through its channel. Real SMS/WhatsApp/push providers plug into
// [send()] — by default delivery is logged so the engine is functional without
// external credentials.
class AlertGenerator
{
    /// Regenerate the full alert set for a building. Returns the number created.
    public function regenerate(?Building $building): int
    {
        if (! $building) {
            return 0;
        }
        $buildingId = $building->id;

        // Dues accrue with time but the cached balance/status is only rewritten on
        // a write — so refresh it first, or a unit that quietly went late this month
        // would be missed and its overdue amount under-reported.
        Unit::refreshLedgerCache($buildingId);

        // Refresh ONLY the auto-derived alerts. Manager-composed notifications
        // (type = 'notice', sent to residents) are real messages — regenerating
        // must not wipe them.
        Alert::where('building_id', $buildingId)->where('type', '!=', 'notice')->delete();

        // Money in an alert body must read in the BUILDING's currency (#6) — these
        // strings used to hardcode "$" while the rest of the app rendered "₪".
        $money = fn (int $n) => $this->money($n, $building->currency);

        $created = [];

        // 1) Overdue units — the two pots are reported apart, and the amount is
        // what is actually OWED: netting a subscription credit against an open
        // ذمة would understate the debt the message is chasing.
        $paid = Payment::sumsByBucket($buildingId);
        $late = Unit::where('building_id', $buildingId)
            ->where('status', 'late')->orderBy('no')->get();
        foreach ($late as $u) {
            $owedDues = max(0, -$u->duesBalance((int) ($paid['dues'][$u->no] ?? 0)));
            $owedSub = max(0, -$u->subBalance((int) ($paid['sub'][$u->no] ?? 0)));
            $parts = [];
            if ($owedSub > 0) {
                $parts[] = 'اشتراكات '.$money($owedSub);
            }
            if ($owedDues > 0) {
                $parts[] = 'ذمم سابقة '.$money($owedDues);
            }
            $created[] = $this->make($buildingId, [
                'type' => 'subscription', 'icon' => 'wallet', 'tone' => 'late',
                'title' => 'مستحقات متأخرة — وحدة '.$u->no,
                'body' => $u->resident.' عليه '.implode(' + ', $parts).'.',
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
            $created[] = $this->make($buildingId, [
                'type' => $a[0], 'icon' => $a[1], 'tone' => $a[2],
                'title' => $a[3], 'body' => $a[4], 'time_label' => 'اليوم', 'channel' => $a[5],
            ]);
        }

        // 2b) Elevator periodic-check reminder — only when the manager enabled
        // it AND the next check (last check + interval months) is due or within
        // two weeks. Makes the "تذكير الفحص" toggle actually do something.
        if ($building->elevator_check_notify && $building->elevator_last_check) {
            $due = Carbon::parse($building->elevator_last_check)
                ->addMonths((int) ($building->elevator_check_interval ?: 6));
            if ($due->isPast() || now()->diffInDays($due, false) <= 14) {
                $created[] = $this->make($buildingId, [
                    'type' => 'elevator_check', 'icon' => 'elevator', 'tone' => 'warn',
                    'title' => 'موعد الفحص الدوري للمصعد',
                    'body' => 'استحقّ الفحص الدوري للمصعد بتاريخ '.$due->toDateString().' — يُرجى ترتيبه.',
                    'time_label' => 'اليوم', 'channel' => 'internal',
                ]);
            }
        }

        // 3) Latest received payment (positive confirmation). An "ايراد خاص" row
        // carries no unit at all (#38/#39), so it is announced without one.
        $pay = Payment::where('building_id', $buildingId)->orderByDesc('date')->first();
        if ($pay) {
            $unitNo = (string) ($pay->unit_no ?? '');
            $created[] = $this->make($buildingId, [
                'type' => 'paid', 'icon' => 'checkCircle', 'tone' => 'ok',
                'title' => 'تم استلام دفعة',
                'body' => $unitNo === ''
                    ? $pay->name.' — إيراد خاص بمبلغ '.$money((int) $pay->amount).'.'
                    : $pay->name.' — وحدة '.$unitNo.' سدّد '.$money((int) $pay->amount).'.',
                'time_label' => 'مؤخراً', 'channel' => 'internal',
                // Payment confirmation is for that unit (+ the admin), not a
                // building-wide broadcast of who paid what. Special income has no
                // unit, so it stays admin-only.
                'target' => $unitNo === '' ? null : $unitNo,
            ]);
        }

        foreach ($created as $alert) {
            $this->send($alert);
        }

        return count($created);
    }

    /// Money rendered the way the app renders it: "$" prefixes, every other
    /// symbol suffixes ("1,200 ₪"). Mirrors fmtMoney() on the Flutter side.
    private function money(int $amount, ?string $currency): string
    {
        $symbols = [
            'NIS' => '₪', 'ILS' => '₪', 'JOD' => 'د.أ', 'JD' => 'د.أ', 'USD' => '$',
            'SAR' => 'ر.س', 'AED' => 'د.إ', 'EGP' => 'ج.م', 'KWD' => 'د.ك',
            'QAR' => 'ر.ق', 'BHD' => 'د.ب', 'OMR' => 'ر.ع', 'TRY' => '₺',
            'EUR' => '€', 'GBP' => '£',
        ];
        $code = $currency ?: 'NIS';
        $sym = $symbols[$code] ?? $code;
        $n = number_format($amount);

        return $sym === '$' ? $sym.$n : $n.' '.$sym;
    }

    private function make(int $buildingId, array $attrs): Alert
    {
        return Alert::create(array_merge(['building_id' => $buildingId], $attrs));
    }

    /// Delivery hook. Plug a real provider here (Twilio / Meta WhatsApp / FCM).
    /// For now delivery is logged so the engine runs without credentials.
    private function send(Alert $alert): void
    {
        Log::info('amarati.alert.dispatch', [
            'channel' => $alert->channel,
            'building' => $alert->building_id,
            'title' => $alert->title,
        ]);
    }
}
