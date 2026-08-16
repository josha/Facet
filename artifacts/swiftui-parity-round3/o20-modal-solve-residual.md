# O-20 — "a presented modal still costs 2 solves per geometry change"

**Closed 2026-08-15 as a FIX, not a decision.** Shipped: **1 solve per geometry
change, every geometry change**, on the shipped Rascal Rally role-pick modal and
on the framework fixture that reproduces it.

**Evidence tier: 1 — headless Lune, a regression signal only.** No Studio session
and no device measurement was taken for this closure, and none is claimed. The
ms-per-solve prices this multiplies against are L-30's tier-3 device numbers
(arrange 9.136 ms/occurrence, measure 3.236 ms/occurrence on a Samsung SM-A102U1);
the *count* below is mine, the *price* is L-30's.

---

## 1. Was the residual real today?

Yes — and it was worse and differently caused than the ledger recorded.

**A/A control, stated before any delta.** The same measurement run twice with
nothing changed between them: `pres.refresh()` on a settled surface costs
**0 solves**, on every arm, in both the framework fixture and the game rig. The
control is in the shipped case (`tests/geometry_solve_coalescing.spec.luau`,
"is ONE solve, and stays one over repeated changes") so it cannot rot.

**Measured, four consecutive batched rotations, before the fix:**

| arm | per rotation |
|---|---|
| plain 12-row screen, `present` | 1, 1, 1, 1 |
| plain 12-row screen, `presentModal` | 1, 1, 1, 1 |
| plain screen, `rootPolicy = "edgeToEdge"` | 1, 1, 1, 1 |
| **shipped role-pick modal, `presentModal` + `ROLE_MODAL_OPTS`** | **2, 3, 3, 3** |
| **the same blueprint through plain `present`** | **2, 3, 3, 3** |
| framework fixture: one `Text` whose `width` is a memo over the viewport | **2, 3, 3, 3** |

Two things fall out of that table before any instrumentation:

* **It is not the modal.** `present` and `presentModal` of the same blueprint cost
  the same, and a modal over a plain tree costs 1. Nothing in `src/present/` is
  involved. The ledger's "a second solve site on the modal presentation path" was
  a guess, and the log said so at the time ("deliberately not guessed at") — the
  guess still ended up in the row and in the game's test comment.
* **It is not 2.** 2 is the first rotation of a freshly presented surface. The
  steady state is 3.

That second point is the test-design defect below in miniature: the rider measured
one rotation, so the number in the ledger was the number of the one rotation
nobody would ever perform twice.

---

## 2. What the second (and third) solve was

Probe recipe as the optimization log recorded it: tag the `solveAndApply()` call
sites, drive one rotation against a presented modal. Extended with a `pushDirty`
tag and a bound-prop write tag, since the call-site tag alone said *where* but not
*why*. Transcript, one non-size-class-crossing rotation, controller 1 = the modal:

```
PUSHDIRTY seq=5 class=measure prop=width path=/RolePick/Card/Primary/RaceNowSub
PUSHDIRTY seq=6 class=measure prop=width path=/RolePick/Card/Secondary/CauseChaosSub
[ctrl 1 dirtySeq=6]  renderer:2371 <- renderer:2789   -- resolveForFeedback, from the settle callback
[ctrl 1 dirtySeq=6]  renderer:2803                    -- the geometry settle solve
[ctrl 2 dirtySeq=0]  renderer:2803                    -- a sibling surface, not counted here
DIRTY[ctrl 1] class=measure prop=width path=/RolePick/Card/Primary/RaceNowSub
DIRTY[ctrl 1] class=measure prop=width path=/RolePick/Card/Secondary/CauseChaosSub
[ctrl 1 dirtySeq=6]  renderer:2958 <- presenter:3333  -- controller.refresh()
ARM[ctrl 1] mark=6 seq=6                              -- armed with NOTHING published
```

and the bound-prop tag on the two writes:

```
PROPWRITE /RolePick/Card/Primary/RaceNowSub.width   identity=false SAME-VALUE
PROPWRITE /RolePick/Card/Secondary/CauseChaosSub.width identity=false SAME-VALUE
```

### The trigger is the consumer's, and it is the by-identity class

`RolePickScreen`'s `subBox` memo returns `{ type = "fixed", px = … }` — a **fresh
table** whose contents are **identical by value** to the last one, because `px` did
not move. The core's default equality is `a == b`, i.e. identity for tables, so the
memo notifies, the bound-prop observer writes `node.props.width` and pushes
`measure` dirt.

This is the same class as L-29's own fix (compare a geometry fact BY VALUE, not by
table identity) one layer down: an env fact there, a node prop here. The prompt's
hypothesis was right, and this is the confirmation transcript for it.

**That much is legitimate and costs one prop write.** What was not legitimate is
what the framework charged for it.

### Amplifier 1 — the solve-feedback arm outlived its flush

`feedbackArmed` is set by *any* settle-phase solve that finishes with a flush still
open, **including one whose `onSolved` listeners published nothing at all**. The
arm cannot be conditioned on a publication at the point it is set: a published
write is still sitting in the core's `writeSet` and is invisible from inside the
callback that made it. The `ARM[ctrl 1] mark=6 seq=6` line above is exactly that
case — mark equals seq, so nothing was published.

When nothing is published the core has nothing to drain, does not restart the
settle pass, and **the arm survives into the next flush**, where it fires against a
`feedbackMark` read during the previous one and buys a full re-solve of a tree
nobody fed anything back to. That is why the first rotation costs 2 and every later
one costs 3: the first one arms it, the rest pay for it.

**The fix is a second settle callback that clears the arm, registered after the
first.** A genuinely earned arm is *always* consumed inside its own flush — a
published write leaves the write set non-empty, so the core ends the pass and
restarts from the first settle callback. An arm still standing when the pass runs
to completion was, by construction, never earned. (`src/render/renderer.luau`,
`THE ARM DOES NOT OUTLIVE ITS FLUSH`.)

### Amplifier 2 — `refresh` re-solved for dirt a settle solve had already consumed

A settle-phase solve deliberately does not consume the dirty queue, so that the
structural sync, the paint commit and the appear/disappear ordering stay
byte-identical. The cost was that `controller.refresh()` then read `measure` off
that same queue and solved a **third** time — for dirt pushed at seq 5 and 6,
answered by a full solve that started at seq 6, with nothing having dirtied the
tree since (the trace shows `dirtySeq=6` at all three solves).

`root.dirtySeq()` is monotonic and survives `takeDirty`, so "has anything dirtied
this tree since the last full solve began" is one comparison. Deliberately
all-or-nothing rather than per-entry — one new dirty makes the whole queue live
again, which is the conservative direction and needs no sequence number on the
entries — and it gates only `measure`/`arrange`; `structure` still forces a solve,
because the structural sync has not run and last solve's rects were never
materialised. (`THE STALE-LAYOUT-DIRT TEST`.)

### Is it structural? No.

The presentation layer does not need a second pass, and 2 was never the right
answer. Both extra solves are FULL solves of a tree that had already been fully
solved, with the same props and the same dirt, inside the same flush. This closes
as a fix.

---

## 3. A second defect the first one was hiding

The leaked arm also made **the first bound-value change after any geometry change**
pay a full solve. Measured on `tests/perf_principles.spec`'s own 800-row fixture,
the case named *LAYOUT — a resize is allowed to cost the whole tree; ONE VALUE is
not*:

| | arranged nodes for one bound value | `feedbackSolves` |
|---|---:|---:|
| leaked arm (before) | 101 *(plus the 8-node incremental solve the case measured)* | 1 |
| after | 8 | 0 |

The case could not see it because `stats().lastArranged` reports the **last** solve
of a frame, not every solve in it: a full 101-node solve ran, then the incremental
8-node one, and only the second was read. Fixing the leak is what made the ratio
assertion in that case start reporting on the whole frame. This was never booked
anywhere; it is recorded here because it is the more expensive half on a real
screen, where a bound value changes far more often than a device rotates.

---

## 4. The instrument was as broken as the defect

The Rascal Rally rider's assertion was:

```lua
expect(afterOne - before <= 2).toBe(true)
expect(afterOne - before >= 1).toBe(true)
```

with a comment explaining that the ceiling was chosen so "the modal's own second
solve can be removed later without the check needing to move". That is precisely
the failure: **a range that spans both the good answer and the known-bad one is a
check that cannot report on its own subject.** It was green while the residual was
there and would have been green after the fix, so no run of it, at any point in the
defect's life, carried information.

It had a second, independent hole: it measured one rotation of a freshly presented
surface, which is the only rotation that costs 2 rather than 3. **Proven, not
asserted** — with the arm leak restored (mutation M1) the repaired check reports
`1,2,2,2`, and the old first-rotation ceiling of 2 passes on that sequence.

Repaired to an equality over four consecutive rotations, `"1,1,1,1"` compared as a
string so the failure message names the shape rather than a count. Both sides are
now equalities: above 1 is a re-fan-out or a returning residual, below 1 is
deafness. The neighbouring `>= 1 and <= 2` in the same file (the edgeToEdge
narrowing case) is now `toBe(1)` for the same reason.

---

## 5. Mutation evidence

Every check touched, deliberately broken, with the named case that reddened.

| # | Mutation | Result |
|---|---|---|
| **M1** | delete the disarm settle callback | **BITES.** LuauUI *is ONE solve, and stays one over repeated changes* (`expected 2 to be 1`); LuauUI *LAYOUT — a resize is allowed to cost the whole tree; ONE VALUE is not*; Rascal Rally *a rotation re-solves the role-pick modal without per-key fan-out* (`expected 1,2,2,2 to be 1,1,1,1`) |
| **M2** | `needsSolve = true` — the stale-layout-dirt test disabled | **BITES.** LuauUI *is ONE solve, and stays one over repeated changes* (`expected 2 to be 1`); Rascal Rally *…the two facts an edgeToEdge modal is DEFINED not to consume cost nothing* (`expected 2 to be 1`) and *a rotation re-solves the role-pick modal without per-key fan-out* (`expected 2,2,2,2 to be 1,1,1,1`) |
| **M3** | `layoutDirtIsStale = fullSolveSeq >= 0` — skip ALWAYS, the over-eager direction | **BITES, after the control was repaired.** 112 cases redden, including the named negative control *…and the prop is still LIVE: a px that really moves moves the rect* (`expected 120 to be 150`) |
| **M4** | delete `solvedEverything = false` at the incremental-reuse branch | **NULL RESULT — reddens nothing** (5554/0). Recorded, not hidden; see below |

**M3 is also a null result, and the reason it is listed as biting is that the
instrument was fixed rather than the report softened.** As first written, the
negative control moved the px *through the viewport* — and a viewport change is
answered by the settle-phase solve however `refresh` decides, so the control could
not see an over-eager skip at all. It stayed green while 108 other cases reddened:
the framework's own suite was the only thing standing between this change and a
surface that silently stops laying out. The control now moves the px through a
plain signal as well, which leaves `refresh` as the only thing that can put it on
screen, and it reddens.

**M4 is a null result that stands.** Deleting the full-solve guard reddens nothing,
and on today's code that is *correct* rather than a coverage hole: `dirtyContains`
is set only inside `refresh`, and that same `refresh` has already drained the
queue, so an incremental solve's mark can never be the one a later skip consults.
The three lines stay because they are what makes the variable's name true, and
because the day `dirtyContains` outlives one refresh the alternative is a surface
that silently stops laying out. It is documented as unproved at the declaration
site so the next agent does not read it as tested.

---

## 6. Suites, and what was NOT run

* LuauUI `lune run tests/run` — **5561 passed, 0 failed**. (The baseline handed to
  this task was 5530; three cases are mine, the rest arrived from two other agents
  working in this tree during the session.)
* Rascal Rally `lune run tests/run` — **3262 passed, 0 failed**, the required count.
* `python3 tools/check_source_size.py` — PASS, `KNOWN_OVER` empty.
* `stylua --check src tests tools bench examples` — clean.
* **Not run: Studio, and not run: a device.** Tier 1 only. The claim this artifact
  makes is a solve *count* in a headless engine-free harness, which is exactly what
  a headless harness can answer; nothing here is a frame-time claim.

## 7. Reproducing it

`lune run tools/lune/_probe_modal_solves` — the framework arms, including the two
bound-prop arms, printing solves per batched rotation with the A/A control first.
The game-side arm (the actual shipped modal, through the game's own rig) was a
throwaway probe; the rider case in
`games/RascalRally/code/tests/luauui_resize_solve_contract.spec.luau` is its
permanent form and asserts the same four numbers.
