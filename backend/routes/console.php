<?php

use App\Models\Building;
use App\Services\AlertGenerator;
use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

// عمارتي — regenerate every building's alerts from live data.
Artisan::command('amarati:alerts {--btype=}', function (AlertGenerator $gen) {
    $keys = $this->option('btype')
        ? [$this->option('btype')]
        : Building::pluck('key')->all();
    foreach ($keys as $bk) {
        $n = $gen->regenerate($bk);
        $this->info("[$bk] generated $n alerts");
    }
})->purpose('Regenerate building alerts from live data');

// Automated daily run (the alerts engine).
Schedule::command('amarati:alerts')->dailyAt('06:00');
