<?php

namespace App\Http\Controllers;

use App\Models\Building;
use App\Models\JoinRequest;
use App\Models\Subscription;
use App\Models\User;
use Illuminate\Http\Request;

// عمارتي — onboarding flow: subscription, building setup (which CREATES the
// manager's own building and promotes them to its admin), and resident join
// requests + admin approvals. Multi-building: every manager owns their own
// building (building_id), so setups never collide ('already managed' is gone).
class OnboardingController extends Controller
{
    private function bk(Request $r): string
    {
        $u = $r->user();
        if ($u && $u->role !== 'admin') {
            return $u->building_key === 'commercial' ? 'commercial' : 'residential';
        }

        return $r->query('btype') === 'commercial' || $r->input('btype') === 'commercial'
            ? 'commercial' : 'residential';
    }

    /// The building this request is scoped to — the acting user's own building.
    private function buildingId(Request $r): ?int
    {
        $u = $r->user();

        return $u && $u->building_id ? (int) $u->building_id : Building::idForKey($this->bk($r));
    }

    private function userPayload(User $u): array
    {
        return $u->only(['id', 'name', 'email', 'phone', 'role', 'building_id', 'building_key', 'unit_no']);
    }

    /// A short, unique, uppercase login code (QR / shareable) for a resident.
    private function loginCode(): string
    {
        do {
            $code = strtoupper(bin2hex(random_bytes(16)));
        } while (User::where('login_code', $code)->exists());

        return $code;
    }

    // ───────────── Subscription ─────────────

    public function subscription(Request $r)
    {
        $u = $r->user();
        // A manager's subscription is tied to THEIR building. Before they've set
        // one up, they simply aren't subscribed yet.
        if ($u && $u->building_id) {
            $sub = Subscription::firstOrCreate(
                ['building_id' => $u->building_id],
                ['building_key' => $u->building_key, 'status' => 'inactive'],
            );

            return response()->json($sub);
        }

        return response()->json(['status' => 'inactive']);
    }

    /// Simulated card payment. SECURITY: there is no real gateway yet (the signed
    /// webhook integration is the deliberately-deferred next step). The real
    /// subscription row is created together with the building at setup, so this
    /// just acknowledges the simulated payment succeeded.
    public function activateSubscription(Request $r)
    {
        $r->validate(['btype' => 'required|in:residential,commercial']);

        return response()->json(['status' => 'active']);
    }

    // ───────────── Building setup (CREATES + promotes actor to admin) ─────────────

    public function setupBuilding(Request $r)
    {
        $data = $r->validate([
            'btype' => 'required|in:residential,commercial',
            'name' => 'required|string|max:160',
            'address' => 'required|string|max:200',
            'floors' => 'required|integer|min:-50|max:300',
            'units_count' => 'required|integer|min:0|max:2000',
        ]);
        $type = $data['btype'];
        $u = $r->user();

        // SECURITY: only a PENDING manager (no building yet) may create a building,
        // or an existing admin may edit their OWN. A resident who was assigned to a
        // manager's building must NOT be able to 'set up' (and thereby take over /
        // become admin of) that building.
        abort_if($u->building_id && $u->role !== 'admin', 403,
            'لا يمكنك إعداد مبنى — أنت مرتبط بمبنى قائم');

        // Multi-building: the manager gets THEIR OWN building. Reuse it if they
        // already set one up (idempotent re-submit); otherwise create a fresh one
        // — a new manager never collides with someone else's building.
        $building = $u->building_id ? Building::find($u->building_id) : null;
        if ($building) {
            $building->update([
                'name' => $data['name'],
                'address' => $data['address'],
                'type' => $type === 'residential' ? 'سكني' : 'تجاري',
                'floors' => $data['floors'],
                'units_count' => $data['units_count'],
            ]);
        } else {
            $building = Building::create([
                'key' => $type,   // the TYPE now (not a unique id)
                'name' => $data['name'],
                'address' => $data['address'],
                'type' => $type === 'residential' ? 'سكني' : 'تجاري',
                'subscription' => 0,
                'currency' => 'NIS',
                'floors' => $data['floors'],
                'units_count' => $data['units_count'],
                'exchange_rate' => 3.75,
                'elevator_fee' => 0,
                'summary' => [],
            ]);
            // The manager "paid" in the subscribe step — activate this building's
            // subscription (simulated).
            Subscription::create([
                'building_id' => $building->id,
                'building_key' => $type,
                'status' => 'active',
                'plan' => 'سنوي',
                'amount' => 299,
                'payment_ref' => 'SIM-'.strtoupper(bin2hex(random_bytes(4))),
                'activated_at' => now(),
                'expires_at' => now()->addYear(),
            ]);
        }

        // SECURITY (role model): you become an admin by setting up a building, not
        // by self-declaring the role at sign-up.
        $u->update(['role' => 'admin', 'building_id' => $building->id, 'building_key' => $type]);

        return response()->json([
            'building' => $building->fresh(),
            'user' => $this->userPayload($u->fresh()),
        ]);
    }

    // ───────────── Join requests ─────────────

    public function storeJoinRequest(Request $r)
    {
        $data = $r->validate([
            'btype' => 'required|in:residential,commercial',
            'floor' => 'nullable|integer|min:-50|max:300',
            'unit_no' => 'nullable|string|max:20',
            'name' => 'nullable|string|max:120',
            'phone' => 'nullable|string|max:32',
            'note' => 'nullable|string|max:200',
        ]);
        $u = $r->user();
        // building_id is auto-derived from building_key by the model trait.
        $jr = JoinRequest::create([
            'building_key' => $data['btype'],
            'user_id' => $u?->id,
            'name' => $data['name'] ?? $u?->name ?? 'ساكن',
            'phone' => $data['phone'] ?? $u?->phone,
            'floor' => $data['floor'] ?? null,
            'unit_no' => $data['unit_no'] ?? null,
            'status' => 'pending',
            'note' => $data['note'] ?? null,
        ]);

        return response()->json($jr, 201);
    }

    public function joinRequests(Request $r)
    {
        abort_unless($r->user()->role === 'admin', 403, 'يتطلب صلاحية المسؤول');

        return JoinRequest::where('building_id', $this->buildingId($r))
            ->orderByDesc('id')->get();
    }

    public function approveJoinRequest(Request $r, JoinRequest $joinRequest)
    {
        abort_unless($r->user()->role === 'admin', 403, 'يتطلب صلاحية المسؤول');
        abort_unless($joinRequest->building_id === $this->buildingId($r), 403);

        $joinRequest->update(['status' => 'approved']);
        if ($joinRequest->user_id && ($u = User::find($joinRequest->user_id))) {
            // A unit has at most one resident — disable + unlink any previous
            // occupant so a replaced tenant can't keep a working login.
            if ($joinRequest->unit_no) {
                User::where('building_id', $this->buildingId($r))
                    ->where('unit_no', $joinRequest->unit_no)
                    ->where('id', '!=', $u->id)
                    ->where('role', 'resident')
                    ->get()->each(function ($old) {
                        $old->disableLogin();
                        $old->update(['unit_no' => null]);
                    });
            }
            $u->update([
                'role' => 'resident',
                'building_id' => $this->buildingId($r),   // joins the admin's building
                'building_key' => $r->user()->building_key,
                'unit_no' => $joinRequest->unit_no,
                // Give the resident a QR / shareable login code if they lack one.
                'login_code' => $u->login_code ?: $this->loginCode(),
            ]);
        }

        return response()->json($joinRequest->fresh());
    }

    public function rejectJoinRequest(Request $r, JoinRequest $joinRequest)
    {
        abort_unless($r->user()->role === 'admin', 403, 'يتطلب صلاحية المسؤول');
        abort_unless($joinRequest->building_id === $this->buildingId($r), 403);

        $joinRequest->update(['status' => 'rejected']);

        return response()->json($joinRequest->fresh());
    }
}
