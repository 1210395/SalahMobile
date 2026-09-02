<?php

namespace App\Http\Controllers;

use App\Models\Setting;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;

// سكن برو — editable brand / app settings (name, slogan, description, colors,
// logo). Public read so every client can theme itself; admin-only write.
class SettingsController extends Controller
{
    private const DEFAULTS = [
        'app_name' => 'سكن برو',
        'slogan' => 'إدارة عمارتك بسهولة',
        'description' => 'برنامج متكامل لإدارة شؤون العمارات السكنية والمجمعات التجارية — المستحقات، المصروفات، التقارير والتنبيهات في مكان واحد.',
        'tagline' => 'سكن برو … إدارة عمارتك بسهولة',
        'primary' => '#7E42B4',
        'accent' => '#937135',
        'logo_url' => '',
    ];

    public function index()
    {
        $stored = Setting::pluck('value', 'key')->toArray();
        $merged = array_merge(self::DEFAULTS, $stored);

        // Not a stored setting, and never overridable from the settings table —
        // it reflects the SMS provider actually configured on this box, so any
        // client can warn the user up front rather than after a failed OTP.
        $merged['sms'] = [
            'available' => \App\Services\Notifier::channelIsLive('sms'),
            'coverage' => \App\Services\Notifier::smsCoverage(),
        ];

        // Same idea for the subscription price: it is what the platform charges,
        // never a building's own setting, so it is read from configuration and
        // cannot be edited through this endpoint. The app shows it on the
        // subscription screen instead of carrying a number of its own that
        // silently disagreed with what the card would actually be charged.
        $merged['subscription'] = [
            'payable' => \App\Services\CyberSource::isConfigured()
                && (float) config('amarati.payments.amount') > 0,
            'amount' => (string) config('amarati.payments.amount'),
            'currency' => (string) config('amarati.payments.currency'),
            'period_days' => (int) config('amarati.payments.period_days'),
        ];

        return response()->json($merged);
    }

    public function update(Request $r)
    {
        // Platform branding (app name, logo, colours) is shared by EVERY building, so
        // only the super-admin may change it — not an individual building manager.
        abort_unless($r->user()->role === 'superadmin', 403, 'يتطلب صلاحية المسؤول العام');
        $data = $r->validate([
            'app_name' => 'nullable|string|max:60',
            'slogan' => 'nullable|string|max:120',
            'description' => 'nullable|string|max:400',
            'tagline' => 'nullable|string|max:120',
            // Brand colours must be valid hex (#RGB / #RRGGBB / #RRGGBBAA) so a
            // garbage value can't reach the theming layer.
            'primary' => ['nullable', 'string', 'regex:/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/'],
            'accent' => ['nullable', 'string', 'regex:/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/'],
        ]);
        foreach ($data as $k => $v) {
            if ($v !== null) {
                Setting::put($k, $v);
            }
        }

        return $this->index();
    }

    public function uploadLogo(Request $r)
    {
        // Platform branding (app name, logo, colours) is shared by EVERY building, so
        // only the super-admin may change it — not an individual building manager.
        abort_unless($r->user()->role === 'superadmin', 403, 'يتطلب صلاحية المسؤول العام');
        // NOT a bare `image` rule: that accepts SVG, which is an XSS payload
        // served from our own origin once it lands on the public disk.
        $r->validate(['logo' => 'required|image|mimes:jpg,jpeg,png,webp|max:4096']);
        $path = $r->file('logo')->store('brand', 'public');
        $url = Storage::disk('public')->url($path);
        Setting::put('logo_url', $url);

        return $this->index();
    }
}
