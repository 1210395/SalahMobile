<?php

namespace App\Http\Controllers;

use App\Models\Building;
use App\Models\JoinRequest;
use App\Models\Subscription;
use App\Models\User;
use Illuminate\Http\Request;

// عمارتي — onboarding flow: subscription, building setup (which promotes the
// actor to admin of that building — the secure role path), and resident join
// requests + admin approvals.
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

    private function userPayload(User $u): array
    {
        return $u->only(['id', 'name', 'email', 'phone', 'role', 'building_key', 'unit_no']);
    }

    /// A short, unique, uppercase login code (QR / shareable) for a resident.
    private function loginCode(): string
    {
        do {
            $code = strtoupper(bin2hex(random_bytes(4)));
        } while (User::where('login_code', $code)->exists());

        return $code;
    }

    // ───────────── Subscription ─────────────

    public function subscription(Request $r)
    {
        $bk = $this->bk($r);
        $sub = Subscription::firstOrCreate(['building_key' => $bk], ['status' => 'inactive']);

        return response()->json($sub);
    }

    /// Simulated card payment → activate the building's subscription.
    ///
    /// SECURITY: this is a SIMULATION — there is no real payment gateway yet
    /// (that integration, e.g. Stripe/HyperPay with a signed webhook, is the
    /// deliberately-deferred next step). To keep the simulation safe:
    /// - the plan/amount are fixed server-side (client-supplied values are NOT
    ///   trusted as evidence of payment), and
    /// - a building already managed by another admin cannot be (re)activated by
    ///   a different user.
    public function activateSubscription(Request $r)
    {
        $data = $r->validate(['btype' => 'required|in:residential,commercial']);
        $bk = $data['btype'];
        $this->abortIfClaimedByAnother($r, $bk);

        $sub = Subscription::updateOrCreate(
            ['building_key' => $bk],
            [
                'status' => 'active',
                'plan' => 'سنوي',
                'amount' => 299,
                'payment_ref' => 'SIM-'.strtoupper(bin2hex(random_bytes(4))),
                'activated_at' => now(),
                'expires_at' => now()->addYear(),
            ],
        );

        return response()->json($sub);
    }

    /// A building may only be claimed/managed by one admin. Block any actor who
    /// is not already that admin from setting up / activating it.
    private function abortIfClaimedByAnother(Request $r, string $bk): void
    {
        $u = $r->user();
        abort_if(
            User::where('building_key', $bk)
                ->where('role', 'admin')
                ->where('id', '!=', $u->id)
                ->exists(),
            403, 'هذا المبنى مُدار بالفعل من قبل مسؤول آخر'
        );
        // An admin of one building can't claim a different one.
        abort_if($u->role === 'admin' && $u->building_key !== $bk, 403,
            'أنت مسؤول عن مبنى آخر بالفعل');
    }

    // ───────────── Building setup (promotes actor to admin) ─────────────

    public function setupBuilding(Request $r)
    {
        $data = $r->validate([
            'btype' => 'required|in:residential,commercial',
            'name' => 'required|string|max:160',
            'address' => 'required|string|max:200',
            'floors' => 'required|integer|min:-50|max:300',
            'units_count' => 'required|integer|min:0|max:2000',
        ]);
        $bk = $data['btype'];
        // SECURITY: a building with an existing admin cannot be taken over.
        $this->abortIfClaimedByAnother($r, $bk);

        $sub = Subscription::firstOrCreate(['building_key' => $bk], ['status' => 'inactive']);
        abort_unless($sub->status === 'active', 402, 'الاشتراك غير مفعّل — فعّل الاشتراك أولاً');

        $building = Building::where('key', $bk)->firstOrFail();
        $building->update([
            'name' => $data['name'],
            'address' => $data['address'],
            'type' => $bk === 'residential' ? 'سكني' : 'تجاري',
            'floors' => $data['floors'],
            'units_count' => $data['units_count'],
        ]);

        // SECURITY (role model): you become an admin by paying for + setting up a
        // building, not by self-declaring the role at sign-up.
        $u = $r->user();
        $u->update(['role' => 'admin', 'building_key' => $bk]);

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
            'floor' => 'nullable|integer',
            'unit_no' => 'nullable|string',
            'name' => 'nullable|string|max:120',
            'phone' => 'nullable|string|max:32',
            'note' => 'nullable|string|max:200',
        ]);
        $u = $r->user();
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

        return JoinRequest::where('building_key', $this->bk($r))
            ->orderByDesc('id')->get();
    }

    public function approveJoinRequest(Request $r, JoinRequest $joinRequest)
    {
        abort_unless($r->user()->role === 'admin', 403, 'يتطلب صلاحية المسؤول');
        abort_unless($joinRequest->building_key === $this->bk($r), 403);

        $joinRequest->update(['status' => 'approved']);
        if ($joinRequest->user_id && ($u = User::find($joinRequest->user_id))) {
            $u->update([
                'role' => 'resident',
                'building_key' => $joinRequest->building_key,
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
        abort_unless($joinRequest->building_key === $this->bk($r), 403);

        $joinRequest->update(['status' => 'rejected']);

        return response()->json($joinRequest->fresh());
    }
}
