# An arm set by a gesture must name what may spend it

**Found:** 2026-08-13, by a redteam pass over the fix that shipped the day before.
**Status: FIXED 2026-08-13** (redteam NEW-1, BLOCKER, and NEW-2, MEDIUM). The fix
is in `src/controls/virtual_list.luau` and `src/controls/table.luau`; the sibling
lesson on the meta those Activates carry is
[a-synthesized-activate-must-carry-the-pointer-kind.md](./a-synthesized-activate-must-carry-the-pointer-kind.md).

## The engine fact both controls are built around

A row's `Hit` is a real `GuiButton`. The pointer sequence that **drags or swipes**
it therefore does not end at `InputEnded` — the engine also fires that button's
`Activated`, and it lands on **either side** of `InputEnded` depending on nothing
the control can see. A drag, a swipe and a tap are indistinguishable to that
signal. So every gesture-bearing control keeps a one-shot arm — `suppressActivatePath`
— that swallows exactly one Activate on the origin path.

Two questions decide whether that arm is correct, and until this round only the
first was being asked.

## 1. WHERE is it armed? (NEW-1, BLOCKER)

`table.luau` was fixed on 2026-08-13 to arm at the **axis lock** rather than at the
release, because an `Activated` landing *before* `InputEnded` is already dispatched
by the time any `onPointerUp` could arm anything. The hosted `VirtualList` was not,
and nobody looked: its arm lived in `hostedDispatch.onPointerUp`'s `unresolved`
branch — the branch for a **tap on an already-open row**. A gesture that resolved
*horizontal* (every real swipe) armed nothing at all.

Table's defect was order-dependent. This one was not. Measured on a clean-room
hosted list through the real adapter seam, **8 of 12 combinations red** — both
orders, both edges, both pointer kinds; only the four *silent* releases were green:

```
vlist touch/trailing/NONE     tray=true  onActivateFired=0   ok
vlist touch/trailing/after     tray=true  onActivateFired=1   FAIL
vlist touch/trailing/before    tray=true  onActivateFired=1   FAIL
… leading, and mouse, both orders — 8 of 12 RED
```

On the shipped playlist analogue that reads: *swipe to reveal Remove, and the track
plays.*

**The rule:** arm at the one place the control decides the gesture went sideways.
For the hosted list that is `hostedResolveAxis`; for Table it is its host
dispatcher's own lock test. Anywhere later is too late for half the orderings, and
a second copy of the lock rule is a second thing to keep in step.

## 2. WHO may spend it? (NEW-2, MEDIUM)

The `table.luau` fix cleared the arm in exactly one place — the next pointer-down —
on this stated premise:

> "A real Activated always fires between a pointer-up and the next pointer-down, so
> a still-live suppression can never legitimately survive to see another down."

**The premise is false**, and stating it so confidently is what made the hole
invisible. Two Activate producers carry **no pointer-down at all**:

* an **IAS device Activate** — gamepad A, keyboard Return, `meta.source == "action"`,
  dispatched by the action system with no pointer event anywhere;
* the **minimum-target hit expander** — a *separate* `GuiButton` overlapping a short
  row, whose press fires the row's activate handler and produces no pointer event on
  the row's own `Hit`.

So any swipe that ended **without** an `Activated` — a cancel (capture loss, row
unmount, scroll steal), or a release landing off the translated `Hit` — left the arm
standing, and the next device press on that row was swallowed whole. Measured with
one probe against both trees:

| | pre-fix `13fd3c6` | post-fix `a6229e0` |
|---|---|---|
| swipe cancelled mid-gesture, then gamepad A | fired 0 → 1 ✅ | fired 0 → **0** ❌ |
| swipe with silent release, then device Activate on the open row | tray closes ✅ | tray **stays open** ❌ |

**The rule, in both controls:** a pointer gesture's artifact is a **pointer's**
(`screen_target.luau`'s `pointerActivateMeta` — `source == "pointer"`). So the arm

* is **cleared on a cancel**, because the engine fires no `Activated` for a capture
  it took away; and
* **is never spent on a device Activate**: `meta.source == "action"` cannot be the
  artifact under any ordering, since by the time the action system dispatches one the
  gesture's own `Activated` has either arrived (and cleared the arm) or is never
  coming.

The clears do not weaken the suppression, and that is pinned rather than asserted:
`a swipe whose release DID Activate still swallows that artifact` and `the arm is one
activate wide` are the counterweights, so "clear it more often" cannot pass by never
arming at all.

## Why the suite could not see any of it

`tests/lib/fake_target`'s `pointerUp` never synthesized an `Activated`. Every swipe
case in the repo — the hosted ones included — drove a release sequence the engine
does not produce, so cases written specifically to assert *"a swipe is not a tap"*
were satisfied by their own starting value. `pointerUpActivating(x, y, order)` (added
with the Table fix) is what makes the question askable; the twelve-combination matrix
in `tests/virtual_list_row_actions.spec.luau` is what asks it on the hosted surface.

One more shape of the same failure, found in the same pass: a proof case can be
**vacuous for its own combination**. `RowActions mouse: … (before)` asserted
tray-open, not-editing, nothing-opened and order-unchanged — four verdicts a *mouse*
`Activated` leaves entirely alone, because a mouse single click REPLACE-SELECTS
rather than opening. It stayed green against unfixed source while its touch twins
reddened. The fix is a **selection** assertion, which is the one thing that moves:
`{"m1"}` unfixed, `{}` fixed.

## The standing rule

**Every one-shot arm owes three answers, written down where it is set:** where it is
armed, what clears it, and *what class of event may spend it*. An arm with only the
first two answered will eventually meet an event from a producer nobody enumerated —
and the comment claiming that cannot happen is the thing to distrust first.
