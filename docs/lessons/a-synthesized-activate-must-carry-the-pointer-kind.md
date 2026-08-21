# A synthesized activate must carry the pointer kind

**Found:** 2026-08-13, by reading `Table`'s new touch branch against every caller
that can reach it. **Status: FIXED 2026-08-13** (redteam item 2, HIGH — re-found
with the destructive half measured, which is what moved it from owed to done).
The fix is `src/client/screen_target.luau`'s `pointerActivateMeta`, shared by the
host button's own `Activated` and by the minimum-target hit expander.

## The defect

`src/client/screen_target.luau` — the 44px minimum-target hit expander:

```lua
expander.Activated:Connect(function()
    if handle.activate ~= nil and handle.instance.Interactable ~= false and handle.instance.Visible then
        handle.activate({ source = "hitExpander" })
    end
end)
```

The meta named its **source** and nothing else. It carried **no `pointer` field**,
even though `Activated` fires for a finger and a mouse alike and the expander's own
`InputObject` — which that closure did not even accept as a parameter — says which.

## Why that is not harmless

Every control that adapts its semantics per input reads `meta.pointer`, and the
idiomatic shape of that read treats *absent meta* as touch — because a bare mount
with no adapter genuinely is the touch case. `src/controls/table.luau`:

```lua
if meta == nil or meta.pointer == "touch" then
    -- The convention: a plain tap OPENS; edit mode is the selection mode
```

A meta that **exists but is silent** satisfies neither half, so it fell through to
the mouse branch — `api.select(rowKey, { mode = "replace" })`, and the primary
action on a second press inside the 500 ms double-click window. Measured:

* **Edit-mode multi-select, three taps build `r1,r2,r3`; one tap in the 44px
  overhang leaves `r4`.** The whole selection discarded by a replace-select the
  player never asked for — the exact inverse of the additive rule edit mode
  promises, chosen by an omission three files away.
* **Two overhang taps within 500 ms opened the row on touch.** That hands a phone
  player a double-tap-to-open — the gesture the touch conventions reserve for zoom, and one the
  Table's own registry comment records as "never a candidate".

The original writeup called the exposure small, on the grounds that sibling row
buttons occlude most of the overhang. That argument is weakest exactly where the
damage is worst: the edit-mode leading gutter shifts every cell inboard, which is
what *creates* overhang under the player's thumb.

`{ source = "hitExpander" }` is worse than `nil` here. `nil` would have been right.

## The fix

One meta builder, `pointerActivateMeta(inputObject)`, called by both producers.
The expander is not a different KIND of activation — it is the same control being
pressed — so it sends the identical meta: `source = "pointer"`, the pointer kind
classified from the `InputObject`, the inset-corrected tap point, and the live
modifier state. `source = "hitExpander"` is retired rather than kept alongside:
`source` is the field controls read to tell a pointer press from a device Activate
(`meta.source == "action"`), a third value means neither to every one of them, and
nothing in the framework or the games ever read it.

Anchored by `tests/adaptive.spec.luau` ("both activate producers build their meta
through the one shared builder"), because `screen_target.luau` is engine-only.

## The rule this closes on

**An adapter that synthesizes an activate owes the same meta a real one carries.**
A partial meta is not a smaller truth than no meta — it is a *different* one, and
it silently defeats exactly the `meta == nil` fallbacks written to catch its
absence. When adding a new synthetic input path, list the fields the genuine path
fills and justify every one you leave out.

**Do not** teach each control to treat a missing `pointer` as touch. The control's
"no meta means touch" default is deliberate and correct for a bare mount; widening
it to absorb an adapter's omission would make every future omission invisible
instead of one of them wrong.

---

## Codicil, 2026-08-13: "no meta means touch" now implies "no meta means OPEN"

Raised as redteam item 10, framed as *decide, do not necessarily change*. The
default itself did not move; what moved is the size of the verb behind it. Before
parity round 2, a meta-less Activate on a Table row SELECTED. Now, on a table that
declares `onPrimaryAction` and is not editing, it **opens** — and that is reachable
from `ScreenTarget.driveActivate(path)` (the documented dev-drive seam) with no
meta at all, on any session, including a shipping one.

**Decision: keep it. `meta == nil` stays touch, and touch on a primary-action
table stays open.** The reasoning, in the order it decides the question:

1. **`nil` is not "unknown input", it is "no input facts at all".** The touch
   branch is the only one that assumes none: no modifier keys, no double-click
   window, no hover. Routing a fact-free activate to the MOUSE branch would make
   the framework invent the two facts that branch is built out of
   (`meta.toggle`/`meta.shift`, and a second press inside 500 ms) — it would read
   the absence of a shift key as "shift is up", which is a claim, not a default.
2. **The verb grew only where a consumer asked for it.** `onPrimaryAction` is a
   declaration that a plain press on a row means "open this". A table that does
   not declare it still selects on a bare activate, exactly as before. So the
   larger verb tracks a spec field, not a silent default.
3. **The dev-drive seam's whole value is that it is not a second path.**
   `driveActivate` invokes the identical closure the engine's `Activated` calls,
   so a scripted drive must resolve the same way a press does. A press on the live
   adapter now ALWAYS carries a full meta (both producers build it through
   `pointerActivateMeta` — above), so a meta-less call is a deliberately
   underspecified one, and answering it as a bare mount does is the consistent
   answer. A caller who wants the mouse semantics passes
   `{ source = "pointer", pointer = "mouse" }`: one field longer, and it says so.
4. **The alternatives are worse.** Refusing a meta-less activate trades a
   deterministic answer for a silent no-op — the failure mode this repo has been
   burned by repeatedly (a check that cannot fail, a verb that does nothing).
   Making `nil` mean "mouse" would break the bare-mount case the default exists
   for and quietly change every headless `api.handleActivate(path)` in the suite.

**What ships with the decision, so it is a decision and not a shrug:** the rule is
pinned by a test rather than only written down — `tests/table_input.spec.luau`,
"a meta-less Activate is the TOUCH verb: it opens a primary-action table" — and
`driveActivate`'s own comment in `screen_target.luau` names the consequence at the
seam a dev reaches for.

## Codicil, 2026-08-13 (second): the same two producers, one question later

This lesson is about the **meta** those two producers carry. A redteam pass the
next day found that the same enumeration answers a different question — *which
Activates arrive with no pointer-down in front of them* — and that a one-shot
gesture arm in `Table` and `VirtualList` had been written on the premise that none
do. Both producers named here (the host button's own `Activated`, the
minimum-target hit expander) plus the IAS device Activate are the counterexamples,
and a swipe that ended without an `Activated` was eating the next device press on
that row.

Recorded separately, because the rule it yields is about arms rather than metas:
[an-arm-set-by-a-gesture-must-name-what-may-spend-it.md](./an-arm-set-by-a-gesture-must-name-what-may-spend-it.md).
