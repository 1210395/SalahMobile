<?php

namespace App\Http\Controllers;

use App\Models\Note;
use Illuminate\Http\Request;

// عمارتي — short notes a resident sends to the building admin (≤ 280 chars),
// and the admin's inbox.
class NoteController extends Controller
{
    private function bk(Request $r): string
    {
        $u = $r->user();
        if ($u && $u->role !== 'admin') {
            return $u->building_key === 'commercial' ? 'commercial' : 'residential';
        }

        return $r->query('btype') === 'commercial' ? 'commercial' : 'residential';
    }

    public function store(Request $r)
    {
        $data = $r->validate([
            'body' => 'required|string|max:280',
            'phone' => 'nullable|string|max:32',
        ]);
        $u = $r->user();
        $note = Note::create([
            'building_key' => $u->building_key ?: 'residential',
            'user_id' => $u->id,
            'name' => $u->name,
            'unit_no' => $u->unit_no,
            'phone' => $data['phone'] ?? $u->phone,
            'body' => $data['body'],
            'status' => 'new',
        ]);

        return response()->json($note, 201);
    }

    public function index(Request $r)
    {
        abort_unless($r->user()->role === 'admin', 403, 'يتطلب صلاحية المسؤول');

        return Note::where('building_key', $this->bk($r))->orderByDesc('id')->get();
    }

    public function markRead(Request $r, Note $note)
    {
        abort_unless($r->user()->role === 'admin', 403, 'يتطلب صلاحية المسؤول');
        abort_unless($note->building_key === $this->bk($r), 403);
        $note->update(['status' => 'read']);

        return response()->json($note->fresh());
    }
}
