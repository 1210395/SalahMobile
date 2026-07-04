<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// عمارتي — domain tables. Rows are scoped by `building_key`
// (residential | commercial) to mirror the app's سكني/تجاري toggle.
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('otp_codes', function (Blueprint $table) {
            $table->id();
            $table->string('phone')->index();
            $table->string('code', 8);
            $table->timestamp('expires_at');
            $table->boolean('used')->default(false);
            $table->timestamps();
        });

        Schema::create('buildings', function (Blueprint $table) {
            $table->id();
            $table->string('key')->unique();          // residential | commercial
            $table->string('name');
            $table->string('address');
            $table->string('type');                   // سكني | تجاري
            $table->unsignedInteger('subscription');
            $table->string('currency')->default('USD');
            $table->unsignedInteger('floors');
            $table->unsignedInteger('units_count');
            $table->decimal('exchange_rate', 8, 2)->default(3.75);
            $table->unsignedInteger('elevator_fee')->default(0);
            $table->string('elevator_phone')->default('');
            // Elevator maintenance contract + periodic-inspection reminder.
            $table->string('elevator_company')->nullable();
            $table->date('elevator_contract_start')->nullable();
            $table->date('elevator_contract_end')->nullable();
            $table->date('elevator_last_check')->nullable();   // آخر فحص دوري
            $table->boolean('elevator_check_notify')->default(false);
            $table->unsignedInteger('elevator_check_interval')->default(6); // months
            $table->json('summary');                  // balance/due/revenueM/expenseM/bars/trend
            $table->timestamps();
        });

        Schema::create('units', function (Blueprint $table) {
            $table->id();
            $table->string('building_key')->index();
            $table->string('ext_id');                 // A1, S1…
            $table->string('no');
            $table->unsignedInteger('floor');
            $table->string('resident');
            $table->string('kind');                   // مالك | مستأجر | شاغر
            $table->string('phone');
            $table->unsignedInteger('sub');
            $table->string('status');                 // ok | late | credit | vacant
            $table->integer('balance');
            $table->string('payer');
            $table->date('contract_start')->nullable();
            $table->date('contract_end')->nullable();
            $table->text('notes')->nullable();
            $table->timestamps();
        });

        Schema::create('payments', function (Blueprint $table) {
            $table->id();
            $table->string('building_key')->index();
            $table->string('unit_no');
            $table->string('name');
            $table->integer('amount');
            $table->string('kind');
            $table->unsignedTinyInteger('month');
            $table->unsignedSmallInteger('year');
            $table->date('date');
            $table->string('method');
            $table->text('notes')->nullable();
            $table->timestamps();
        });

        Schema::create('pay_types', function (Blueprint $table) {
            $table->id();
            $table->string('key');                    // sub | elev | guard | park
            $table->string('label');
            $table->unsignedInteger('amount');
            $table->boolean('enabled')->default(true);
            $table->boolean('optional')->default(false);
            $table->unsignedInteger('sort')->default(0);
            $table->timestamps();
        });

        Schema::create('expenses', function (Blueprint $table) {
            $table->id();
            $table->string('building_key')->index();
            $table->string('cat');
            $table->string('icon');
            $table->string('tone');
            $table->string('supplier');
            $table->integer('amount');                 // base currency (for totals)
            $table->integer('original_amount')->nullable(); // amount as entered
            $table->string('currency', 8)->nullable();      // entered currency
            $table->decimal('exchange_rate', 12, 4)->nullable(); // entered → base
            $table->date('date');
            $table->string('description');
            $table->timestamps();
        });

        Schema::create('workers', function (Blueprint $table) {
            $table->id();
            $table->string('building_key')->index();
            $table->string('name');
            $table->string('type');
            $table->string('phone');
            $table->string('address');
            $table->string('cycle');                  // يومي | أسبوعي | شهري
            $table->integer('amount');
            $table->date('last_payment');
            $table->date('next_due');
            $table->boolean('came')->default(false);     // حضر هذه الدورة؟
            $table->date('last_visit')->nullable();      // تاريخ آخر حضور
            $table->string('pay_status')->default('none'); // full | partial | none
            $table->integer('paid_amount')->default(0);    // إن كان جزئياً
            $table->timestamps();
        });

        Schema::create('parking_spots', function (Blueprint $table) {
            $table->id();
            $table->string('building_key')->index();
            $table->string('no');
            $table->string('status');                 // مشغول | شاغر | صيانة
            $table->string('unit_no')->nullable();
            $table->string('code')->nullable();
            $table->string('note')->nullable();
            $table->timestamps();
        });

        Schema::create('guards', function (Blueprint $table) {
            $table->id();
            $table->string('building_key')->index();
            $table->string('name');
            $table->string('phone');
            $table->string('address');
            $table->integer('fee');
            $table->date('last_payment');
            $table->date('next_due');
            $table->timestamps();
        });

        Schema::create('craftsmen', function (Blueprint $table) {
            $table->id();
            $table->string('name');
            $table->string('job');
            $table->string('phone');
            $table->string('note')->nullable();
            $table->timestamps();
        });

        Schema::create('alerts', function (Blueprint $table) {
            $table->id();
            $table->string('building_key')->index();
            $table->string('type');
            $table->string('icon');
            $table->string('tone');
            $table->string('title');
            $table->string('body');
            $table->string('time_label');
            $table->string('channel');                // whatsapp | internal
            $table->string('target')->default('all'); // 'all' | unit_no (recipient)
            $table->timestamps();
        });

        Schema::create('wa_templates', function (Blueprint $table) {
            $table->id();
            $table->string('label');
            $table->text('text');
            $table->timestamps();
        });

        Schema::create('year_summaries', function (Blueprint $table) {
            $table->id();
            $table->string('building_key')->index();
            $table->unsignedSmallInteger('year');
            $table->unsignedInteger('opening_balance')->default(0);
            $table->json('months');                   // [{m,paid,total}…]
            $table->timestamps();
        });
    }

    public function down(): void
    {
        foreach ([
            'year_summaries', 'wa_templates', 'alerts', 'craftsmen', 'guards',
            'parking_spots', 'workers', 'expenses', 'pay_types', 'payments',
            'units', 'buildings', 'otp_codes',
        ] as $t) {
            Schema::dropIfExists($t);
        }
    }
};
