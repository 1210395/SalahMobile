<?php

namespace App\Http\Controllers;

use App\Models\Setting;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;

// عمارتي — editable brand / app settings (name, slogan, description, colors,
// logo). Public read so every client can theme itself; admin-only write.
class SettingsController extends Controller
{
    private const DEFAULTS = [
        'app_name' => 'عمارتي',
        'slogan' => 'إدارة عماراتك بثقة وراحة',
        'description' => 'برنامج متكامل لإدارة شؤون العمارات السكنية والمجمعات التجارية — المستحقات، المصروفات، التقارير والتنبيهات في مكان واحد.',
        'tagline' => 'عمارتي … تنظيم اليوم، راحة تدوم',
        'primary' => '#232858',
        'accent' => '#C2A24E',
        'logo_url' => '',
    ];

    public function index()
    {
        $stored = Setting::pluck('value', 'key')->toArray();

        return response()->json(array_merge(self::DEFAULTS, $stored));
    }

    public function update(Request $r)
    {
        abort_unless($r->user()->role === 'admin', 403, 'يتطلب صلاحية المسؤول');
        $data = $r->validate([
            'app_name' => 'nullable|string|max:60',
            'slogan' => 'nullable|string|max:120',
            'description' => 'nullable|string|max:400',
            'tagline' => 'nullable|string|max:120',
            'primary' => 'nullable|string|max:9',
            'accent' => 'nullable|string|max:9',
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
        abort_unless($r->user()->role === 'admin', 403, 'يتطلب صلاحية المسؤول');
        $r->validate(['logo' => 'required|image|max:4096']);
        $path = $r->file('logo')->store('brand', 'public');
        $url = Storage::disk('public')->url($path);
        Setting::put('logo_url', $url);

        return $this->index();
    }
}
