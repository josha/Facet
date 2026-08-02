# 6. Client and server

The interface runs on each player's own machine, but the *data that matters* is
owned by the server. This chapter covers the three replication adapters
(`LuauUI.replication`, in `src/replication/adapters.luau`), how they recover from
an imperfect network, how to show a change instantly and reconcile it, and the
firm list of things that must never travel over the network.

A ground rule first: **LuauUI does not move bytes.** Your game already has a way
to send data between server and client (remote events, or whatever transport you
use). The adapters sit *on top of* that transport: your networking code calls the
adapter's `ingest`/`confirm`/`reject` functions, and the adapter turns the raw
messages into consistent, well-ordered signals your UI can read. This keeps
LuauUI transport-agnostic.

## 6.1 Receiving whole-state: the snapshot adapter

The simplest case: the server owns a chunk of semantic state and sends the whole
thing each time it changes. `LuauUI.replication.snapshot(core, initialRevision,
initialData)` gives you:

- `snapshot.binding` — a signal holding the current data. Read it from blueprints
  like any signal.
- `snapshot.ingest(revision, data)` — call this from your networking code when the
  server sends an update.
- `snapshot.revision()` — the current revision number.

The adapter enforces **monotonic revisions**. Every update carries an
ever-increasing revision number. `ingest` returns one of three strings so your
networking layer knows what happened:

- `"applied"` — a newer revision; the signal was updated.
- `"duplicate"` — the same revision you already have; ignored.
- `"stale"` — an *older* revision (arrived out of order); ignored.

Because out-of-order and duplicate messages are dropped rather than applied, a
flaky network cannot make the UI flicker backward to old state.

## 6.2 Receiving a keyed set: the collection adapter, with gap recovery

For a set of keyed items (a leaderboard, an inventory) the server often sends
small **patches** — "item 7 changed, item 3 was removed" — instead of the whole
set each time. `LuauUI.replication.collection(core, initialRevision, initialItems,
requestResnapshot)` handles this, and it is stricter about ordering because a
missed patch would silently corrupt the set.

- `collection.binding` — a signal holding the current `{ key -> item }` table.
- `collection.ingestPatch(revision, patch)` — apply a patch. A patch is
  `{ set = { [key] = value }, remove = { key, ... } }` and must arrive at
  *exactly* the next revision.
- `collection.ingestResnapshot(revision, items)` — apply a full authoritative set
  (used for recovery and reconnect).
- `collection.revision()`.

The interesting part is **gap detection**. `ingestPatch` returns `"applied"`,
`"duplicate"`, `"stale"`, or `"gap"`:

- If a patch arrives for a revision *beyond* the next one, a patch was dropped in
  transit. Applying it would leave the set inconsistent, so the adapter **refuses
  it**, returns `"gap"`, and calls the `requestResnapshot(fromRevision)` function
  you supplied — your cue to ask the server for a full resend.
- While it is waiting for that resnapshot, it keeps refusing further patches
  (returning `"gap"`), so the set never diverges from the server.
- When the full set arrives via `ingestResnapshot`, the adapter catches up and
  resumes accepting patches.

**While a gap is outstanding, an equal revision re-bases.** You are handed the
client's *current* revision, so the natural answer when nothing has changed since
the gap is a resnapshot at exactly that revision — and it applies, clears the
gap, and resumes patching. (Outside a gap the rule is stricter: a resnapshot has
to be strictly newer, and an equal one is refused as `"stale"`.)

This is also the reconnect path: after any disconnect, feed the client a fresh
`ingestResnapshot` at whatever revision the server is now at, and it re-bases
cleanly.

Two failure paths are contained rather than latching. A `requestResnapshot` that
**throws** does not leave the gap flag set — the next patch asks again, so a
transient error in your remote-fire path cannot turn a recoverable gap into a
dead collection.

## 6.3 Sending a change: the mutation adapter

A client must **never** change authoritative state directly. It sends a request
and waits for the server's verdict. `LuauUI.replication.mutation(core, opts?)`
models this:

- `mutation.status` — a signal moving through `"idle" → "pending" →
  "confirmed"` or `"rejected"`.
- `mutation.lastResult` — a signal holding the server's result or rejection
  reason.
- `mutation.send(payload, expectedRevision?)` — begin a request. Returns an
  **envelope** `{ requestId, payload, expectedRevision }` that *your* networking
  code sends to the server. The `expectedRevision` rides along so the server can
  validate ordering; the client does not interpret it.
- `mutation.confirm(requestId, result)` — call when the server accepts.
- `mutation.reject(requestId, reason)` — call when the server refuses.
- `mutation.reset()` — abandon whatever is going on and return to `"idle"`. It
  works **from any state, including pending**, because pending is the state a
  caller actually needs to escape: a request the server never answered. It rolls
  back the optimistic presentation (the request may still land server-side, so
  local state must not keep claiming a success nobody confirmed) and clears the
  active request id, which is what keeps a late confirm or reject for the
  abandoned request ignored.

Two safety properties are enforced:

- **One request in flight.** Calling `send` while a request is already pending is
  a hard error — you must wait for the confirm or reject. This prevents a
  double-submit.
- **Confirmations are matched and idempotent.** A `confirm`/`reject` only takes
  effect for the request id currently in flight; a late response to a superseded
  request, or a repeated confirmation, is ignored.

The cardinal rule this encodes: **`"pending"` is not success.** A pending
mutation means "the client has asked"; only `"confirmed"` — driven by the server
— means the change is real.

## 6.4 Optimistic UI and reconciliation

Waiting for a server round-trip before showing *any* change feels sluggish. The
mutation adapter supports **optimistic presentation**: show the expected result
immediately, then reconcile with what the server actually says. You opt in by
passing an `optimistic` handler to `mutation`:

```lua
local draftMusic = core:signal(false)   -- what the UI shows right now

local mutation = LuauUI.replication.mutation(core, {
    optimistic = {
        -- called the instant send() runs: show the expected result
        apply = function(payload) draftMusic:set(payload.music) end,
        -- called on confirm AND on reject: re-sync from authoritative truth
        restore = function() draftMusic:set(snapshot.binding:get().music) end,
    },
})
```

The lifecycle then reads:

1. The player flips the toggle. You call `mutation.send({ music = true }, rev)`.
2. `apply` runs immediately — the toggle visibly flips. Status is now `"pending"`.
3. Your networking code sends the envelope to the server.
4. **On accept:** the server sends new authoritative state (you `snapshot.ingest`
   it) and you call `mutation.confirm(id, result)`. `restore` re-syncs the draft
   from that authoritative snapshot, so the optimistic value and the truth agree.
5. **On reject:** you call `mutation.reject(id, reason)`. `restore` runs and the
   toggle snaps back to the last authoritative value.

One subtlety documented in the adapter itself: `restore` re-syncs from
authoritative state *as of now*. If a confirm outruns the snapshot that carries
its result, `restore` briefly restores to the older truth; convergence then
depends on the game reconciling again when the newer snapshot ingests. The robust
pattern — used by the reference gallery client — is to also observe the snapshot
binding and re-apply the draft when authoritative state lands, so the UI always
ends at the server's truth. The full working example is
`examples/gallery/client/init.client.luau`.

Both callbacks are **quarantined**. A throwing `apply` degrades that send to an
un-optimistic one — `restore` runs, the envelope still comes back, and the
request still goes out — so one bad line in the most consumer-authored code in
the adapter cannot leave the control permanently stuck.

## 6.5 What must never replicate

This is the hard line that keeps the client-local model sound. **Presentation
state is local to one screen on one device and must never be sent over the
network.** Specifically, never replicate:

- **Focus** — which control the keyboard/gamepad cursor is on. It is per-device
  and meaningless on another machine.
- **Hover** — which element the mouse is over.
- **Scroll position** — how far a list is scrolled.
- **Layout geometry** — the pixel rectangles the solver computed. These are a
  function of the local screen size and are recomputed locally; sending them would
  be both wrong (another device has a different screen) and wasteful.

Everything in that list is derived, locally, from the *semantic* state plus the
local device facts. Send the semantic state (the coin balance, the selected item's
*id*, the toggle's value); let each client compute its own presentation from it.
This is the same split introduced in [chapter 1](01-concepts.md), now stated as a
networking rule: **replicate meaning, never appearance.**

---

That completes the guide. To review: [chapter 1](01-concepts.md) for the ideas,
[chapter 2](02-architecture.md) for how the modules fit and why, [chapter
3](03-getting-started.md) for a working screen, [chapter
4](04-tutorial-examples.md) for the guided examples, and [chapter
5](05-styling.md) for the look.
