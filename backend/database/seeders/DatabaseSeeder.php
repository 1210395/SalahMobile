<?php

namespace Database\Seeders;

use App\Models\Alert;
use App\Models\Building;
use App\Models\Craftsman;
use App\Models\Expense;
use App\Models\Guard;
use App\Models\ParkingSpot;
use App\Models\PayType;
use App\Models\Payment;
use App\Models\Subscription;
use App\Models\Unit;
use App\Models\User;
use App\Models\WaTemplate;
use App\Models\Worker;
use App\Models\YearSummary;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

// عمارتي — seeds the prototype's sample data so the app looks identical but
// is now backed by MySQL. Mirrors lib/data/sample_data.dart.
class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        // Runs every boot (idempotent): ensure existing buildings have an active
        // subscription — covers upgrades where the subscriptions table is new but
        // the buildings/users already exist.
        $this->seedSuperAdmin();
        $this->seedSubscriptions();
        $this->backfillLoginCodes();

        // Idempotent: skip the bulk sample data if already seeded. Keyed on
        // buildings (the canonical seed marker) — NOT users, since the helpers
        // above create the super-admin user before this guard runs.
        if (Building::query()->exists()) {
            return;
        }

        // PRODUCTION: set SEED_DEMO=false in .env so a real deployment starts
        // with EMPTY building shells (no demo apartments, no demo admin) — a
        // manager then registers, onboards, and adds their own units without
        // colliding with seeded numbers or a pre-claimed building. Defaults to
        // true so local dev, the guest demo, and the test suite are unchanged.
        if (! filter_var(env('SEED_DEMO', true), FILTER_VALIDATE_BOOLEAN)) {
            $this->seedEssentials();
            $this->seedSubscriptions();

            return;
        }

        $summary = [
            'balance' => 25840, 'due' => 12650, 'revenueM' => 3200, 'expenseM' => 1860,
            'bars' => [
                ['label' => 'إيرادات', 'value' => 3200, 'color' => 'navy600'],
                ['label' => 'مستحقات', 'value' => 2400, 'color' => 'gold500'],
                ['label' => 'مصروفات', 'value' => 1860, 'color' => 'late'],
                ['label' => 'صيانة', 'value' => 880, 'color' => 'ok'],
            ],
            'trend' => [
                ['label' => 'ينا', 'value' => 2800, 'color' => 'navy600'],
                ['label' => 'فبر', 'value' => 3100, 'color' => 'navy600'],
                ['label' => 'مار', 'value' => 2950, 'color' => 'navy600'],
                ['label' => 'أبر', 'value' => 3300, 'color' => 'navy600'],
                ['label' => 'ماي', 'value' => 3200, 'color' => 'navy600'],
            ],
        ];

        Building::create([
            'key' => 'residential', 'name' => 'عمارة الياسمين',
            'address' => 'حي النرجس، شارع 12، الرياض', 'type' => 'سكني',
            'subscription' => 40, 'currency' => 'USD', 'floors' => 6, 'units_count' => 12,
            'exchange_rate' => 3.75, 'elevator_fee' => 15, 'summary' => $summary,
            'elevator_phone' => '+966 92 000 1234',
            'elevator_company' => 'شركة أوتيس للمصاعد',
            'elevator_contract_start' => '2026-01-01', 'elevator_contract_end' => '2026-12-31',
            'elevator_last_check' => '2026-05-04',
            'elevator_check_notify' => true, 'elevator_check_interval' => 6,
        ]);
        Building::create([
            'key' => 'commercial', 'name' => 'مجمع التجارة الذهبي',
            'address' => 'طريق الملك فهد، الرياض', 'type' => 'تجاري',
            'subscription' => 120, 'currency' => 'USD', 'floors' => 3, 'units_count' => 10,
            'exchange_rate' => 3.75, 'elevator_fee' => 15, 'summary' => $summary,
            'elevator_phone' => '+966 92 000 1234',
            'elevator_company' => 'شركة أوتيس للمصاعد',
            'elevator_contract_start' => '2026-01-01', 'elevator_contract_end' => '2026-12-31',
            'elevator_last_check' => '2026-05-04',
            'elevator_check_notify' => true, 'elevator_check_interval' => 6,
        ]);
        $this->seedSubscriptions();

        $apartments = [
            ['A1', '101', 1, 'أحمد العامري', 'مالك', '+966 50 123 4567', 40, 'ok', 0, 'الساكن'],
            ['A2', '102', 1, 'سارة المطيري', 'مستأجر', '+966 55 987 6543', 40, 'late', -80, 'المالك'],
            ['A3', '201', 2, 'خالد الزهراني', 'مالك', '+966 54 222 1188', 40, 'ok', 0, 'الساكن'],
            ['A4', '202', 2, 'نورة القحطاني', 'مستأجر', '+966 56 778 9900', 40, 'credit', 40, 'الساكن'],
            ['A5', '301', 3, 'فهد الدوسري', 'مالك', '+966 50 445 6677', 40, 'late', -40, 'الساكن'],
            ['A6', '302', 3, 'ليان السبيعي', 'مستأجر', '+966 53 119 2233', 40, 'ok', 0, 'المالك'],
            ['A7', '401', 4, 'شقة شاغرة', 'شاغر', '—', 40, 'vacant', 0, '—'],
            ['A8', '402', 4, 'ماجد الحربي', 'مالك', '+966 59 332 4455', 40, 'ok', 0, 'الساكن'],
        ];
        $shops = [
            ['S1', 'M-01', 1, 'صيدلية الشفاء', 'مستأجر', '+966 50 200 3040', 120, 'ok', 0, 'المستأجر'],
            ['S2', 'M-02', 1, 'مقهى لافندر', 'مستأجر', '+966 55 600 1020', 120, 'late', -240, 'المستأجر'],
            ['S3', 'M-03', 1, 'بقالة المدينة', 'مالك', '+966 54 700 8090', 120, 'ok', 0, 'المالك'],
            ['S4', 'M-04', 2, 'مكتب محاماة العدل', 'مستأجر', '+966 56 808 1122', 120, 'credit', 120, 'المستأجر'],
            ['S5', 'M-05', 2, 'صالون الأناقة', 'مستأجر', '+966 53 909 3344', 120, 'ok', 0, 'المستأجر'],
            ['S6', 'M-06', 3, 'محل شاغر', 'شاغر', '—', 120, 'vacant', 0, '—'],
        ];
        $this->seedUnits('residential', $apartments);
        $this->seedUnits('commercial', $shops);

        $payments = [
            ['102', 'سارة المطيري', 40, 'الاشتراك الشهري', 4, 2026, '2026-05-03', 'تحويل بنكي'],
            ['201', 'خالد الزهراني', 55, 'اشتراك + مصعد', 4, 2026, '2026-05-02', 'نقداً'],
            ['101', 'أحمد العامري', 40, 'الاشتراك الشهري', 4, 2026, '2026-05-01', 'محفظة رقمية'],
            ['302', 'ليان السبيعي', 40, 'الاشتراك الشهري', 3, 2026, '2026-04-28', 'تحويل بنكي'],
            ['402', 'ماجد الحربي', 70, 'اشتراك + باركينج', 3, 2026, '2026-04-26', 'نقداً'],
            ['202', 'نورة القحطاني', 80, 'اشتراك (شهرين)', 3, 2026, '2026-04-20', 'تحويل بنكي'],
        ];
        $shopPayments = [
            ['M-01', 'صيدلية الشفاء', 120, 'الاشتراك الشهري', 4, 2026, '2026-05-03', 'تحويل بنكي'],
            ['M-03', 'بقالة المدينة', 135, 'اشتراك + مصعد', 4, 2026, '2026-05-02', 'نقداً'],
            ['M-05', 'صالون الأناقة', 120, 'الاشتراك الشهري', 4, 2026, '2026-05-01', 'محفظة رقمية'],
            ['M-04', 'مكتب محاماة العدل', 120, 'الاشتراك الشهري', 3, 2026, '2026-04-27', 'تحويل بنكي'],
        ];
        $this->seedPayments('residential', $payments);
        $this->seedPayments('commercial', $shopPayments);

        $this->seedPayTypes();

        $expenses = [
            ['مصعد', 'elevator', 'navy', 'شركة أوتيس للمصاعد', 350, '2026-05-04', 'عقد صيانة دورية'],
            ['نظافة', 'broom', 'ok', 'مؤسسة النظافة المثالية', 200, '2026-05-01', 'أجور شهر مايو'],
            ['كهرباء', 'alert', 'warn', 'شركة الكهرباء', 180, '2026-04-29', 'فاتورة الأجزاء المشتركة'],
            ['صيانة', 'wrench', 'credit', 'سباك - عبدالله', 90, '2026-04-22', 'إصلاح تسرب الطابق 3'],
            ['أخرى', 'receipt', 'gold', 'متجر مواد', 60, '2026-04-18', 'لمبات وأدوات'],
        ];
        foreach (['residential', 'commercial'] as $bk) {
            foreach ($expenses as $e) {
                Expense::create(['building_key' => $bk, 'cat' => $e[0], 'icon' => $e[1],
                    'tone' => $e[2], 'supplier' => $e[3], 'amount' => $e[4], 'date' => $e[5],
                    'description' => $e[6]]);
            }
        }

        $workers = [
            ['مؤسسة النظافة المثالية', 'شركة نظافة', '+966 50 111 2233', 'حي العليا', 'شهري', 200, '2026-05-01', '2026-06-01'],
            ['سعيد - عامل نظافة', 'عامل', '+966 56 444 5566', 'حي النخيل', 'أسبوعي', 50, '2026-05-02', '2026-05-09'],
        ];
        foreach (['residential', 'commercial'] as $bk) {
            foreach ($workers as $w) {
                Worker::create(['building_key' => $bk, 'name' => $w[0], 'type' => $w[1],
                    'phone' => $w[2], 'address' => $w[3], 'cycle' => $w[4], 'amount' => $w[5],
                    'last_payment' => $w[6], 'next_due' => $w[7]]);
            }
            Guard::create(['building_key' => $bk, 'name' => 'محمد عبدالرحمن',
                'phone' => '+966 50 777 8899', 'address' => 'سكن الحارس - الدور الأرضي',
                'fee' => 10, 'last_payment' => '2026-05-01', 'next_due' => '2026-06-01']);
        }

        $parkingRes = [
            ['P-01', 'مشغول', '101', '4471', 'سيارة بيضاء'],
            ['P-02', 'مشغول', '201', '2290', ''],
            ['P-03', 'شاغر', null, '—', 'متاح للإيجار'],
            ['P-04', 'مشغول', '402', '8813', 'سيارة عائلية'],
            ['P-05', 'صيانة', null, '—', 'إصلاح أرضية'],
            ['P-06', 'شاغر', null, '—', ''],
        ];
        $parkingCom = [
            ['P-01', 'مشغول', 'M-01', '5521', 'سيارة توصيل'],
            ['P-02', 'مشغول', 'M-03', '7780', ''],
            ['P-03', 'شاغر', null, '—', 'متاح للإيجار'],
            ['P-04', 'صيانة', null, '—', 'إصلاح بوابة'],
        ];
        $this->seedParking('residential', $parkingRes);
        $this->seedParking('commercial', $parkingCom);

        foreach ([
            ['عبدالله السباك', 'سباكة', '+966 50 321 0011', 'متوفر 24 ساعة'],
            ['يوسف الكهربائي', 'كهرباء', '+966 55 432 0022', 'خبرة 10 سنوات'],
            ['ورشة النجار', 'نجارة', '+966 54 543 0033', 'أبواب وأثاث'],
            ['فني التكييف', 'تكييف', '+966 56 654 0044', 'صيانة وتعبئة فريون'],
            ['صباغ المحترف', 'دهان', '+966 53 765 0055', ''],
        ] as $c) {
            Craftsman::create(['name' => $c[0], 'job' => $c[1], 'phone' => $c[2], 'note' => $c[3]]);
        }

        $alerts = [
            ['subscription', 'wallet', 'late', 'اشتراك متأخر — شقة 102', 'سارة المطيري متأخرة عن دفع شهرين ($80).', 'قبل ساعة', 'whatsapp'],
            ['contract', 'elevator', 'warn', 'عقد صيانة المصعد', 'ينتهي عقد الصيانة بعد 8 أيام. جدّد العقد.', 'اليوم', 'internal'],
            ['cleaning', 'broom', 'navy', 'استحقاق أجور النظافة', 'دفعة شركة النظافة مستحقة في 1 يونيو.', 'أمس', 'internal'],
            ['insurance', 'shield', 'warn', 'تأمين المبنى', 'وثيقة التأمين تنتهي خلال 21 يوم.', 'قبل 3 أيام', 'internal'],
            ['paid', 'checkCircle', 'ok', 'تم استلام دفعة', 'أحمد العامري — شقة 101 سدّد $40.', 'قبل 4 أيام', 'internal'],
        ];
        foreach (['residential', 'commercial'] as $bk) {
            foreach ($alerts as $a) {
                Alert::create(['building_key' => $bk, 'type' => $a[0], 'icon' => $a[1],
                    'tone' => $a[2], 'title' => $a[3], 'body' => $a[4], 'time_label' => $a[5],
                    'channel' => $a[6]]);
            }
            YearSummary::create(['building_key' => $bk, 'year' => 2026, 'opening_balance' => 8200,
                'months' => [
                    ['m' => 0, 'paid' => 8, 'total' => 8], ['m' => 1, 'paid' => 8, 'total' => 8],
                    ['m' => 2, 'paid' => 7, 'total' => 8], ['m' => 3, 'paid' => 6, 'total' => 8],
                    ['m' => 4, 'paid' => 5, 'total' => 8], ['m' => 5, 'paid' => 0, 'total' => 8],
                ]]);
        }

        foreach ([
            ['تذكير اشتراك', 'السلام عليكم، نذكّركم بسداد اشتراك الصيانة الشهري ($40) لشهر مايو. شكراً لتعاونكم 🌿'],
            ['إشعار تأخر', 'تنبيه: لديكم مبلغ متأخر بقيمة $80. يرجى السداد لتفعيل خدمات المبنى.'],
            ['استلام دفعة', 'تم استلام دفعتكم بنجاح. شكراً لكم — لجنة المبنى.'],
        ] as $t) {
            WaTemplate::create(['label' => $t[0], 'text' => $t[1]]);
        }

        // Demo accounts (password = "password"). RESIDENTIAL has a demo admin so
        // the demo + e2e suite work out of the box; COMMERCIAL is left unclaimed
        // so the register → subscribe → building-setup flow stays testable.
        $residentialBuilding = Building::where('key', 'residential')->first();
        User::create(['name' => 'مدير اللجنة', 'email' => 'admin@amarati.app',
            'phone' => '+966500000001', 'password' => Hash::make('password'),
            'role' => 'admin', 'building_id' => $residentialBuilding?->id,
            'building_key' => 'residential']);
        User::create(['name' => 'أحمد العامري', 'email' => 'resident@amarati.app',
            'phone' => '+966500000002', 'password' => Hash::make('password'),
            'role' => 'resident', 'building_id' => $residentialBuilding?->id,
            'building_key' => 'residential', 'unit_no' => '101',
            'login_code' => $this->loginCode()]);

        // Make sure every seeded resident has a QR / login code.
        $this->backfillLoginCodes();
    }

    /// Give every resident without a login code a unique one (QR / shareable).
    private function backfillLoginCodes(): void
    {
        User::where('role', 'resident')->whereNull('login_code')->get()
            ->each(fn ($u) => $u->update(['login_code' => $this->loginCode()]));
    }

    private function loginCode(): string
    {
        do {
            // 128-bit, matching the runtime generators (Auth/Api controllers).
            $code = strtoupper(bin2hex(random_bytes(16)));
        } while (User::where('login_code', $code)->exists());

        return $code;
    }

    /// The default fee items every building starts with (needed by the payment
    /// sheet). Shared by the demo seed and the clean production seed.
    private function seedPayTypes(): void
    {
        foreach ([
            ['sub', 'الاشتراك الشهري', 40, true, false],
            ['elev', 'رسوم المصعد', 0, true, false],
            ['guard', 'أجرة الحارس', 0, true, true],
            ['park', 'أجرة الباركينج', 0, false, true],
        ] as $i => $p) {
            PayType::create(['key' => $p[0], 'label' => $p[1], 'amount' => $p[2],
                'enabled' => $p[3], 'optional' => $p[4], 'sort' => $i]);
        }
    }

    /// Clean production seed: two EMPTY building shells + fee items. A manager
    /// fills in the name/details by onboarding; no demo units or demo admin, so
    /// nothing collides with their first real apartment.
    private function seedEssentials(): void
    {
        foreach ([['residential', 'سكني'], ['commercial', 'تجاري']] as [$key, $type]) {
            Building::create([
                'key' => $key, 'name' => '', 'address' => '', 'type' => $type,
                'subscription' => 0, 'currency' => 'USD', 'floors' => 0, 'units_count' => 0,
                'exchange_rate' => 3.75, 'elevator_fee' => 0, 'elevator_phone' => '',
                'summary' => [],
            ]);
        }
        $this->seedPayTypes();
    }

    private function seedSuperAdmin(): void
    {
        // SECURITY: never create a platform-owner account with a known password
        // in production. Use AMARATI_SUPERADMIN_PASSWORD (+ optional _EMAIL); if
        // it's not provided, only fall back to the dev default OUTSIDE production
        // (local/demo/tests). A real deployment must set the env var so no weak
        // super-admin ever exists.
        $password = env('AMARATI_SUPERADMIN_PASSWORD');
        if (! $password) {
            if (app()->environment('production')) {
                return;
            }
            $password = 'password'; // local / demo / test convenience only
        }

        User::firstOrCreate(
            ['email' => env('AMARATI_SUPERADMIN_EMAIL', 'superadmin@amarati.app')],
            [
                'name' => 'المدير العام', 'phone' => '+966500000000',
                'password' => Hash::make($password),
                'role' => 'superadmin', 'building_key' => 'residential',
            ],
        );
    }

    private function seedSubscriptions(): void
    {
        foreach (Building::pluck('key') as $bk) {
            Subscription::firstOrCreate(
                ['building_key' => $bk],
                [
                    'status' => 'active', 'plan' => 'سنوي', 'amount' => 299,
                    'payment_ref' => 'SEED', 'activated_at' => now(),
                    'expires_at' => now()->addYear(),
                ],
            );
        }
    }

    private function seedUnits(string $bk, array $rows): void
    {
        foreach ($rows as $r) {
            Unit::create([
                'building_key' => $bk, 'ext_id' => $r[0], 'no' => $r[1], 'floor' => $r[2],
                'resident' => $r[3], 'kind' => $r[4], 'phone' => $r[5], 'sub' => $r[6],
                'status' => $r[7], 'balance' => $r[8], 'payer' => $r[9],
                'contract_start' => $r[7] === 'vacant' ? null : '2026-01-01',
                'contract_end' => $r[7] === 'vacant' ? null : '2026-12-31',
                'notes' => $r[4] === 'شاغر' ? 'الوحدة متاحة للإيجار.' : 'يفضل التواصل عبر واتساب بعد الساعة 5 مساءً.',
            ]);
        }
    }

    private function seedPayments(string $bk, array $rows): void
    {
        foreach ($rows as $p) {
            Payment::create(['building_key' => $bk, 'unit_no' => $p[0], 'name' => $p[1],
                'amount' => $p[2], 'kind' => $p[3], 'month' => $p[4], 'year' => $p[5],
                'date' => $p[6], 'method' => $p[7]]);
        }
    }

    private function seedParking(string $bk, array $rows): void
    {
        foreach ($rows as $p) {
            ParkingSpot::create(['building_key' => $bk, 'no' => $p[0], 'status' => $p[1],
                'unit_no' => $p[2], 'code' => $p[3], 'note' => $p[4]]);
        }
    }
}
