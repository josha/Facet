# SwiftUI parity round 2 — design

The build plan for the mission stated in
[`swiftui-parity-round2-brief.md`](swiftui-parity-round2-brief.md). The brief is
binding; this document is the design it asked for — one section per phase, plus
the Phase 0 map that every later section rests on.

Milestones: **M1** = Phases 1–2, **M2** = Phases 3–4, **M3** = Phases 5–6.

## Four places this design departs from the brief, and why

Each is argued at the point it happens; collected here so nobody has to find
them. The brief wins wherever this document is merely different; these are the
places it is deliberately different.

1. **Table modifier-key selection is already shipped** — the brief scoped Phase 3
   to "finish or confirm" it, and the source says it is done, tested, and wired
   to real keys. What is left is a lying header comment. (§Phase 0, §3.4)
2. **`withAnimation` does not animate size this round.** The brief lists size
   among the properties the presentation layer would animate; the presentation
   channel has no size write, and adding one runs through `applyRect`, which also
   drives the hit expander, the focus ring, icon refit and Path2D points, and
   through clip hosts and canvas groups that crop rather than follow. The brief's
   own stated fallback is taken. (§Size is NOT animated this round)
3. **No `LazyVStack` / `LazyHStack` constructor ships — but the virtualizer gains
   a horizontal axis.** The locked decision is that they must be sugar over the
   existing virtualizer; that virtualizer demands a uniform row height and was
   vertical-only, so a constructor wearing SwiftUI's name would be a parity claim
   the code does not honor. The game director ruled on 2026-08-12: skip the
   names, ship the sideways axis (mechanical), record the variable-height gap
   (a design problem with no screen asking for it yet). (§2.3)
4. **The API is `presenter.withAnimation(class, fn)`**, not `UI.withAnimation`,
   and it takes a class *name* rather than `classOrSpec`. Naming and ownership
   both come from the constitution. (§Where it lives)

Everything else follows the brief as written.

---

## Phase 0 — the map, verified in source

Every claim below was read out of `src/` (not docs) on 2026-08-12 against
`main` @ `ff7501e`. Baseline suite at that commit: **4144 passed**
(`./run-tests.sh`).

| Brief's claim | Verdict | Evidence |
|---|---|---|
| `ProgressView` is determinate-bar only | **Confirmed** | `src/controls/progress_view.luau:2`; closed key set = `format, height, id, label, max, min, showValue, value` (`:47-56`); internal paint slots `barTrack`/`barFill` (`:107,111`) |
| `Label` has titleAndIcon / titleOnly / iconOnly | **Confirmed** | `src/controls/label.luau:30`, default `titleAndIcon` (`:56`); keys `gap, icon, iconSize, id, presentation, textSize, title` (`:34-42`); absent icon degrades to `titleOnly` (`:68-70`) |
| Feedback-bus taxonomy | **Confirmed, and CLOSED** | `src/present/feedback.luau:32-45` — `activate, select, adjust, pickup, commit, reject, cancel, arrive, land, dismiss, supersede, celebrate`. `bus.emit/subscribe/count/dispose` (`:68-73`), handlers quarantined (`:122-127`). **No haptics adapter exists** (`:4-5`: "Facet PLAYS NOTHING") |
| Table Shift-click ranges shipped? | **YES — shipped and tested** | `table.luau:2063` dispatches `mode = "range"`; anchor at `:544`, `rangeKeys` at `:1823-1834` (min/max, so reversed ranges work), applied at `:1895`, anchor pruned on row removal (`:726-728`). Real keys: `screen_target.luau:2728`. Tests: `tests/table.spec.luau:1004-1030`, `:1061-1075` |
| Table Cmd/Ctrl-click toggles shipped? | **YES — shipped and tested** | `table.luau:2061` dispatches `mode = "toggle"`; body `:1897-1905`. Cmd **and** Ctrl both map: `screen_target.luau:2729-2731`, `roblox_input.luau:29-32`, `input/actions.luau:262-267`. Test: `tests/table.spec.luau:1048-1059` |
| — the "Phase B" marker | **Stale comment, not deferred work** | `table.luau:8-10` header still says "modifier-key semantics are Phase B"; the implementation comment at `:1879` says the modes shipped. The header is a lie the next agent will believe — **Phase 3 fixes it** |
| Table double-click / primary action | **Absent** | Zero hits for `onPrimaryAction` / `onDoubleClick` / `primaryAction` in `src/` or `tests/`; `TABLE_KEYS` (`:217-238`) has no such field. Single activate is the only row semantic |
| No `layoutPriority` | **Confirmed** | Zero hits. The solver has **no shrink pass at all**: `fill` children take positive remainder only (`solver.luau:2004-2021`), `hug`/`content`/`fixed` never shrink, and overflow emits a diagnostic (`:1993-2001`) |
| No `containerRelativeFrame` | **Confirmed** | Only the `percent` dim, resolved against the **immediate parent's offer** (`solver.luau:515-529`) |
| No Lazy stacks | **Confirmed** | Substrate is `src/controls/virtual_list.luau` (`build` at `:298`), and it demands **fixed `rowHeight`** (`:310`), **vertical only**, explicit `key` (`:343`) and `cell` (`:344`), plus `viewportHeight` (`:341`) |
| No `GridRow` | **Confirmed** | `UI.Grid` (`blueprint.luau:568`, schema `blueprint_schema.luau:979-1024`) is one uniform flow grid: one shared column width for every column, row-major wrap, **no spans, no per-row cell shapes** (`solver.luau:434, 929, 1872`) |
| No `withAnimation` | **Confirmed** | Motion animates *values* (`motion.luau:453-668`), never property changes. Structural insert/remove lives in `render/transitions.luau` |

### Three facts the brief paraphrased loosely — the source wins

1. **The presentation channel is offsets, scale, rotation and group
   transparency — there is no size write.** `controller.setPresentationTransform`
   takes `{ x, y, scale?, rotation? }` (`renderer.luau:3646`);
   `setPresentationTransparency` requires `UI.Box{ canvasGroup = true }` and
   refuses loudly otherwise (`:3675-3695`). Phase 1 has to add a size channel or
   decline to animate size — see below.

2. **Hit geometry already follows a live presentation OFFSET; it does not follow
   scale or rotation.** `screenRectOf` adds `presentationShift` on purpose
   (`renderer.luau:1073-1142`) — platform-verifier finding PLAT-4: while the
   keyboard keep-visible shift or an enter slide was live, Facet's own drop
   verdicts disagreed with what the player saw, by exactly the offset. The
   comment at `:1100-1103` fixes the other half: scale/rotation would turn a hit
   rect into a quad, so a scaled node hit-tests at its solved size. The brief's
   "hit-testing and focus use solved geometry, never in-flight visuals" is
   therefore **half right**, and the shipped half is the ratified one. Phase 1
   follows the shipped rule and does not re-open PLAT-4.

3. **The "row-actions presentation slide" is not the presentation channel.** It
   is `offsetX`, an **arrange-only** blueprint prop honoured only by an
   `anchor`-kind parent (`blueprint_schema.luau:504`, `row_actions.luau:22-32`),
   so it re-arranges one node without re-measuring. It is prior art for *cheap
   motion*, not for *bypassing the solver*. The real prior art for the
   presentation channel is `render/transitions.luau` and keep-visible.

### Solver memoization — the cache key, for Phase 2

`ctx.measureCache[node][cacheKey]`, `cacheKey = "{maxW}|{maxH}|{hiddenDepth}"`
(`solver.luau:1141`, `maxH` dropped to `*` for offer-independent text leaves,
`:1131-1140`). It is **gated on `ctx.hasScroll`** (`:1108-1110`) and dies with
the solve (`:2140`). A cached entry replays published side-channel verdicts
(`textState`, `compact`, `textFacts`, `composition`, `:1169-1192`), not just
`(w, h)`. The composition cache is `ctx.compositions[node.id]` keyed by an
explicit `key` field (`:590-598`).

**The Phase 2 obligation:** the cache key must cover what it caches. Any new
solve-affecting input that is *not* already expressible as a different
`(node identity, maxW, maxH, hiddenDepth)` must be added to the key, and the
addition must be mutation-proved — break it deliberately, watch a test fail,
restore.

---
## Phase 1 — `withAnimation` [M1]

**Revision 3, 2026-08-12.** Revision 1 went to a fresh-context adversarial
reviewer before any code, per the brief, and came back `REJECT` — three blockers,
all real. Revision 2 fixed them and went back to the same reviewer, which
returned `CONCERNS 17`: blocker 3 verified genuinely closed, blocker 1 closed in
mechanism but mis-costed and holed, blocker 2 **not** closed, plus two new
blocker-severity defects introduced by the fixes. Revision 3 is the result. Every
finding from both rounds is folded in and named at the point it changed the
design, because the next agent needs the reasoning more than a clean-looking
document.

The two defects that arrived with the revision-2 fixes, and are now closed:
the armed commit drained **all** accumulated dirt so an unrelated *discrete*
change animated at full delta (fixed by the unarmed pre-drain); and a recycled
instance carries `lastRects` across paths, so a brand-new row would have animated
in from a dead row's position (fixed by not deriving liveness from `lastRects`).

### What it is, in one sentence

`presenter.withAnimation("container", function() open:set(true) end)` — the
layout lands exactly and instantly as it always did, and every node whose box
**moved** is *painted* travelling from where it used to be to where it now is,
over one spring.

### Where it lives — `presenter.withAnimation`, not `UI.` and not `motion.`

The brief writes `UI.withAnimation(classOrSpec, fn)`. Two narrowings, both
deliberate, both recorded here so the two documents do not quietly disagree:

1. **Not `UI.`** — constitution §2 reserves `UI.lowerCase(bp, …)` for *modifiers*,
   which take a blueprint and return a new frozen one. This takes no blueprint.
2. **Not a free function on `motion` either**, which is what revision 1 proposed.
   The reviewer's question 3 killed it: a free function has no motion clock, no
   controller scope to own records in, and no answer at all when a client has
   more than one presenter. The **presenter** has all three — it builds and owns
   the motion clock (`presenter.luau:461`), it owns the surfaces, and it is
   already the service that owns `refresh`. So `withAnimation` is a presenter
   method, which is where its collaborators actually live.
3. **A class NAME, not `classOrSpec`.** An inline `{ dampingRatio = … }` is
   refused everywhere else in the framework — "zero per-call magic numbers",
   `motion/classes.luau:5-11` — and `withAnimation` does not get to be the
   exception that starts the drift. `motion.registerClass` is the one dial.

### Blocker 1 — there is no "commit that closes a transaction"

Revision 1 said the renderer would diff "on the commit that closes an animated
transaction". **No such commit exists.** `core:transaction` closes by flushing
the reactive core and nothing else (`core/custom.luau:436-451`); the renderer's
commit is `presenter.refresh()` → `controller.refresh()` → `solveAndApply`
(`renderer.luau:2992-3055`), and production binds that to a **frame-coalesced**
connection (`examples/gallery/client/init.client.luau:840-842`;
`core/profile.luau:70-76`). Between a transaction closing and the next frame's
commit, arbitrary unrelated reactive work lands in the same dirty queue and the
same solve. Transaction identity is destroyed before the diff could run.

**The fix: `withAnimation` drains, then closes its own loop, synchronously.**

```
presenter.withAnimation(class, fn):
  presenter.refresh()                  -- UNARMED drain: queue empty, lastRects current
  nested = false
  arm { class, spring }                -- idempotent; installs records once
  core:transaction(function()
      scratch:set(scratch:get() + 1)   -- the nesting probe, see "Refusals"
      fn()
  end)
  if not probeFired then nested = true end
  presenter.refresh()                  -- the armed commit: exactly fn's consequences
  disarm                               -- in a finally, on every path including a throw
  if nested then error(…) end
```

**The unarmed pre-refresh is load-bearing, not belt-and-braces.**
`controller.refresh()` opens with `local dirty = root.takeDirty()`
(`renderer.luau:2993`) — it drains the *whole* queue. Without the pre-drain, the
armed commit commits everything dirtied since the last frame refresh, and a
*discrete* change that fired two milliseconds earlier — a network event, a
Heartbeat script's `set`, a timer, an async image landing that changed a label's
width — animates at its **full** delta. Revision 2's first draft claimed the
error was "bounded by one frame", which is true of a *continuous* mover and false
of a discrete one. The pre-drain converts "bounded by one frame" into "exactly
the transaction's consequences", which is what this design actually needs. It is
usually a no-op solve, because nothing is dirty.

The armed commit is then the only commit that ever installs records. The
frame-coalesced refresh, virtual-list windowing (`virtual_list.luau:2113`),
replication reverts (`replication/adapters.luau:197, 247`), async landings — all
unarmed, all untouched. That is the whole of **blocker 2**, which was a
consequence of blocker 1 rather than a separate defect.

**What is armed: every controller in the presenter's stack.** `presenter.refresh()`
walks every handle (`presenter.luau:3820`) and the signature carries no surface,
so arming is presenter-wide. That is safe *because* of the pre-drain: with the
queue already empty, another surface has no pending changes to animate by
accident.

**Cost, stated honestly rather than waved away.** The controller half is nearly
free on the second pass, but `refreshBody` (`presenter.luau:3819-3856`) runs
`syncContributions`, `coordinator.flush`, `feedGeometry`, `syncTextReveal`,
`syncFocusMap` and `syncTransientScopes` **unconditionally, per surface** — and
the focus-map walk alone is measured at 2.09 ms/frame at 360×691, which is why it
has its own profile scope (`core/profile.luau:70-80`). So one call costs **two
full presenter passes**, and the frame's own refresh pays a third. This is a real
budget item, it is measured in the perf lab, and it is the reason the cap
(below) is per *frame*.

**Two more consequences, written down rather than discovered later:**

- **Env-driven relayouts are never animated.** A theme swap, viewport resize or
  preferred-text change does not go through `refresh` at all — the renderer
  observes `env` and calls `solveAndApply()` directly at flush
  (`renderer.luau:2960-2966`). That path is deliberately **not** armed.
  Animating a whole-tree theme relayout is not a feature; it is a frame-budget
  accident.
- **Two feels in one frame work, and the test asserts two COMMITS.** Two
  sequential top-level calls each force their own. The assertion is on commit
  count, not on animation-set count — revision 1 made this same claim while
  blocker 1 falsified it, and a set-count assertion would not have caught that.

**Re-entrancy, because the armed refresh can fire early.** The precedent for a
synchronous refresh (`presenter.luau:487-497`) is a `core:effect`, and effects
fire *during* flush — so if any effect in the app calls `presenter.refresh()`,
the armed commit lands inside `core:transaction`'s own closing flush, before the
explicit call. That is still the right commit, so arming is **idempotent and
install-once**, and the disarm runs in a `finally`, never after the second
refresh call. `controller.refresh()` additionally guards re-entry: a refresh
requested while one is running does not start a second.

### Blocker 3 — records must be RELATIVE, and only at animation roots

Revision 1 installed an absolute per-node delta on every node whose rect moved.
That is provably wrong here, because **both** sides of the presentation channel
already accumulate ancestors: `presentationShift` sums the node's transform plus
every ancestor prefix's (`renderer.luau:1104-1126`), and the adapter's
`recomputePresentationOffset` does the same (`screen_target.luau:1772-1801`),
re-applying across `subtreeOf(path)` on every write (`:4119-4123`). A child's
solved delta already *contains* its parent's movement — the solver moved the
child because the parent moved. Install both and a panel sliding 100 px paints
its children 200 px off, 300 px three levels deep.

`transitions.luau` never hits this because exactly one node per transition
subtree carries a transform. So `withAnimation` adopts the same discipline:

> **Install a record only at an animation ROOT** — a path whose delta differs
> from the composed absolute delta of its nearest ancestor **changed in this
> diff** — and store the **relative** delta (own minus that composed ancestor
> delta). Every descendant that moved *with* its parent gets its motion free,
> through the accumulation that already exists.

Three precisions in that sentence, each of which is a certain defect if dropped:

- **"changed in this diff", never "nearest *recorded* ancestor".** A live record
  from an earlier call is not this diff's business. If ancestor A carries a live
  (100, 0) from call 1 and call 2 moves only child B by (30, 0), reading A's live
  record stores B's relative as (30 − 100) = **(−70, 0)** and B flies backwards.
  Reading "changed in this diff" gives A a delta of zero, stores (30, 0), and it
  composes with A's still-running flight correctly.
- **"composed absolute", never the ancestor's stored relative.** For a chain
  A(root, rel 100) → B(unrecorded) → C(moved 130), C's relative is 130 − 100,
  where 100 is A's *absolute*. At depth three with several recorded ancestors the
  stored relatives must be summed. Easy to get wrong once on a two-level fixture
  and never notice.
- **The predicate runs over the union of {changed paths} and {descendants of
  roots}, not over changed paths alone.** A path that did *not* move while its
  ancestor did has a delta of zero, which differs from the ancestor's — so it
  needs a **compensating** record of `−Δancestor` to hold it still. It is
  reachable: an `Anchor` child pinned by `anchor` + `offsetX` can resolve to the
  same absolute box while its parent moves (`solver.luau:1828`, `:1857-1866`).
  Without the compensating record the adapter's accumulation drags it along for
  the whole flight and snaps it back at settle.

**Root detection is top-down, so the ordering is not free.** The commit's
existing rect comparison is an unordered hash iteration
(`renderer.luau:2557-2565`), and you cannot classify a node before its ancestors.
The *comparison* rides work already being paid for; the *ordering* costs one tree
walk, on armed commits only, hosted in one of the two walks already in that
commit (`pushVisible` at `:2481-2503`, `pushHitRects` at `:2522-2555`).

**Liveness must NOT come from `lastRects[path] ~= nil`.** `restoreParkedProps`
writes `lastRects[path] = carried.rect` when a **new** path adopts a parked
instance (`renderer.luau:1712-1716`, `:2225-2244`), and recycling is on by
default. So a freshly-appeared `ForEach` row that adopted a pooled instance would
show a "previous rect" belonging to whatever row that instance used to be, and
would fly in from a dead occupant's position — verifier finding V10 in a new
costume, on the canonical demo (add a row inside `withAnimation`). The comment at
`renderer.luau:2872-2884` draws exactly this line: a cache describing the
*instance* may be carried; one describing the *node* may not. `lastRects` is
instance-describing for the write-diff and node-describing for this one. So
liveness comes from a separate set of paths alive at the previous commit (or the
`structureEpoch` at `:2819`), and there is a test that adds a row inside
`withAnimation` with recycling on and asserts the new row installs no record.

This is not only correctness. It collapses the record count from "every node
that moved" to "the few nodes that started moving", which is what defuses four
of the review's major findings at once:

| Review finding | Why roots-only defuses it |
|---|---|
| #6 — a `setProp` write **materialises** an elided container (`screen_target.luau:3894-3895`), and inert-container elision is a measured 40 % of GuiObjects | only roots are written, so a whole-screen animation de-elides a handful of nodes, not hundreds. Still tested, still capped |
| #7 — `parkEligible` **refuses** any handle carrying a live presentation transform (`screen_target.luau:4425-4436`), so recycling is defeated while records live | the refusal now touches roots only, and only for the flight's duration |
| #8 — write amplification: each write is `findNode` (a tree walk) plus `subtreeOf` + `applyRect` over every descendant | the amplifier is paid once per root instead of once per moved node, and nested animated nodes no longer multiply |
| #11 — two writers on one `lastTransform[path]` slot | far fewer paths carry records, and the precedence rule below closes the rest |

**One spring per call; records owned per PATH.** All of a call's records share one
progress spring (1 = at the old place, 0 = at the solved place), so every node's
absolute offset is `(its absolute delta) × p` for a single `p` — a uniform
interpolation that **provably cannot tear** a subtree. This is
`transitions.luau`'s ratified shape: one progress number, every visual form
derived from it (`transitions.luau:15-20`).

But the *record* belongs to the path, not to the call; the spring is merely the
driver a path is currently attached to. Otherwise a second call touching a path
the first is still animating puts **two live springs on one
`lastTransform[path]` slot** (`renderer.luau:3646-3667`), alternating by observer
registration order — and that is the common case, not an exotic one: a panel
toggled twice, a list re-sorted twice. So when call 2 claims a path it re-bases
that path's `from` to its current painted relative delta, detaches it from call
1's spring and attaches it to call 2's. Call 1's spring settles over whatever it
still owns, and its `onSettle` clears only the paths it **still** owns, never
call 2's fresh records.

### Size is NOT animated this round — and here is precisely why

Revision 1 proposed extending the presentation channel with a `dw/dh` size delta,
on the argument that the instance tree is flat so an interpolated size moves
nothing else. The flatness claim is true of Facet *nodes* and false of
everything else in the frame, and the review enumerated the cost:

- `applyRect` is not just Position and Size. The same function writes the **hit
  expander** (`screen_target.luau:1803-1822`), the **focus-ring float**
  (`:1849-1859`), `refitIconArt` (`:1863`) and `applyPathPoints` for Path2D
  (`:1864-1867`). An interpolated size re-fits icon art and re-scales normalized
  path control points **every frame of the flight**.
- The node's own interior is laid out by the engine inside `Size`: a wrapped
  `TextLabel` re-wraps and can ellipsize mid-flight, and a `Slice`/`Tile` image
  re-caps (`docs/lessons/roblox-slice-and-uicorner.md`).
- The flat-tree exceptions are all real parents that **crop**: clip hosts
  re-base children against the *solved* rect (`screen_target.luau:1830-1832`) so
  a shrunk host simply cuts them; a `canvasGroup` renders its subtree into a
  buffer sized to itself; `Stage`/ViewportFrame re-projects its scene.

So the brief's own stated fallback applies, and it is being taken deliberately
rather than discovered halfway through: **Phase 1 ships position animation** (and
the existing group-transparency channel), **size changes land instantly and
exactly**, and the gap is recorded with those five specific mechanisms as the
work a future size channel would have to do. A row that grows still reads
correctly — the rows below it slide.

The one piece of good news the review confirmed and that survives for that future
mission: `Size` is **not** in `NATIVE_SHEET_OWNED` (`render/authority.luau:195-223`),
and routing a size delta through the existing `transform` prop would leave the
authority manifest unchanged (`transform = "presentation"`, `size = "layout"`,
`:59-60`, `:28`). The contest was never with StyleSheets; it is with `applyRect`'s
four passengers.

### Nesting, refusals, and the error path

**Nesting rule: innermost wins, per call.** `withAnimation` keeps a frame stack;
the class recorded is the class of the deepest frame entered. A nested call whose
class differs emits an authoring diagnostic naming both classes and the winner.

The rule is per *call*, not per changed value, and the reason is architectural,
not lazy: `Core` exposes `transaction(body)` and nothing else
(`core/contract.luau:56-75`) — there is no per-signal write hook, and nested
transactions collapse by depth count (`custom.luau:437-447`). Per-value
attribution would mean changing the contract three core implementations satisfy.
The review verified this justification and it stands.

**Refusals, all loud:**

- **Nested inside another `withAnimation`** (added 2026-08-13, red-team R1) —
  refused **first**, before anything is resolved, refreshed, armed or mutated,
  via an explicit `inWithAnimation` re-entrancy flag. Arming is presenter-wide
  and disarming is a plain "off" rather than a counter, so an inner call that got
  as far as arming would disarm the controllers the *outer* call had armed, and
  the **outer** animation would silently not happen (its layout still lands
  exactly; only the flight is lost). Measured before the flag: the outer call's
  node landed at `rect.y = 200` painted at `presentedPosition.y = 200` where the
  flight should have started it at 100, with `animationRecordCount() == 0`. Under
  a `pcall` around the inner call — the shape `controls/row_actions.luau` uses
  for `action.onAction` — not even the inner raise was visible. Its message says
  so, and says that nothing was mutated by the refused call.
- **Inside an already-open transaction, or during a core commit** — refused,
  naming both. `withAnimation` needs its own flush boundary to force its own
  commit; inside an outer `core:transaction` nothing has flushed, so nothing is
  dirty, so the armed refresh installs **zero** records and the animation
  silently does not happen — on exactly the code shape RascalRally uses. A silent
  no-op is the worst outcome, which is why this is an error.

  **How, given the contract has no `inTransaction()`.** `Core`
  (`core/contract.luau:56-75`) exposes ten members and `txDepth` is a private
  local (`custom.luau:437`), so the refusal cannot simply ask. It uses a one-shot
  probe instead: one scratch signal and one observer, built **once per presenter**
  and reused, written as the first act inside the wrapped body. Observers fire
  post-flush, so if the observer has fired by the time `core:transaction` returns,
  depth was zero. Contract-only, no core change, and the raise happens after the
  `finally` disarm so a refused call leaves nothing latched.

  **What the probe CANNOT tell you** (2026-08-13, red-team R2). "Did not fire"
  means only "nothing flushed", and *two* situations produce that.
  `core/imperative.luau`'s `commit` opens `if committing then return end`, so a
  transaction opened by anything the commit itself dispatches — an observer, an
  effect, a settle chain, any handler — never flushes either. Reproduced from a
  plain `core:observe` handler, where the old message asserted an outer
  transaction that was **not open**. The message now names both causes.

  **And the hazard, because this raise is late.** `fn` has already run inside the
  transaction, so its mutation has landed. A caller that catches the raise (again,
  `pcall(action.onAction)`) sees "no animation" and must **not** retry the
  mutation, or it lands twice. The message says this explicitly.
- **An unknown class name** — the existing `motion.resolveClass` refusal, with a
  did-you-mean and the registered list (`classes.luau:166-189`).

**The error path unwinds.** `core:transaction` `pcall`s the body and re-raises
*after* the flush (`custom.luau:443-450`). The frame stack and the armed flag are
released in both directions, or a throwing `fn` would latch an animation class on
for the rest of the session. There is a test that throws.

### Reduced motion — an explicit branch, deliberately

Revision 1 claimed `withAnimation` needed no reduced-motion branch because the
motion authority places decorative values instantly. The parity half is true and
the review confirmed it (`motion.luau:332-337`, `:245-255`). The *cost* half was
wrong, and there was a trap under it:

- seeding a record and immediately clearing it is **two rounds of amplified
  subtree writes per root** for a visual no-op;
- because settle fires *synchronously inside* `setTarget` under reduced motion,
  an implementation that registers `onSettle` after `setTarget` never drops the
  record and the node stays painted at the full stale offset **forever**.

So: `withAnimation` **branches** on `clock:isReduced()` (public,
`motion/clock.luau:263-265`) and installs no records at all. `fn` still runs, the
transaction still commits, the layout is still exact — there is simply no
flight. One honest line of code beats a clever claim.

The motion is **decorative** (the instant layout already carries every fact; the
travel is pure continuity), which is what makes "no flight under reduced motion"
the correct policy rather than information deletion. Written into the module
header and the parity doc.

### Composition with the other motion systems

- **Structural insert/remove stays `transitions.luau`'s job.** `withAnimation`
  animates surviving paths only.
- **Precedence, because the channel has one slot per path.**
  `controller.setPresentationTransform` stores into a single `lastTransform[path]`
  with no notion of contributors, so two writers on one path alternate by
  observer-registration order. The rule: **a path another writer already owns —
  a structural transition, keep-visible — is excluded from `withAnimation`
  records.**

  **The exclusion is the PATH, not its subtree** (corrected by the Milestone-1
  RED-TEAM review, blocker 1; `tests/animation_precedence.spec.luau`). The
  whole-subtree form shipped first and was a **silent, permanent no-op on any
  surface holding a `UI.TextInput`**: every text field declares a
  `keepVisibleOffset`, `presenter.present` wires it eagerly, so
  `setPresentationOffset(0)` writes a zero transform onto the **root** at boot —
  and the root's subtree is the entire surface. `withAnimation` then installed
  zero records and snapped, with no error and no diagnostic. A slot belongs to
  one path; taking its descendants (each with its own uncontended slot) out of
  the diff protected nothing and cost everything.

  So the walk **skips the owned node and continues into its children with `inh`
  unchanged**. `inh` is the composed delta of records installed *in this diff*,
  and a foreign writer's shift is not one of them: both halves of the
  presentation channel accumulate every ancestor's transform independently, so
  the keep-visible or transition shift is already added on top of whatever a
  descendant's own record paints. Folding it into `inh` would subtract it from
  the descendant twice — a mutation that is run against that spec.

  **The remaining cost of the rule:** the excluded path P itself has no
  compensating record, so if it sits under a recorded ancestor A it rides A's
  delta and paints wrong by `|Δ_P − Δ_A|` until settle. Bounded and usually small
  (P is entering or exiting, so it is fading while it happens). Its
  *descendants* no longer pay that cost — they compute their relative delta
  against A's `inh` and each carries its own. Removing the last of it needs an
  additive per-path contributor stack in the presentation channel, which is a
  channel change and a separate mission.
- **The row-actions slide does not collide** — it is arrange-only, not a
  presentation write (Phase 0 fact 3), so the two mechanisms write different
  things. Its only interaction is the bounded one-frame ride-along above.

### Interruption

A second call while records are live re-targets rather than restarts: each
record's `from` is re-based to its **current painted relative delta**, the
progress spring is re-aimed, and its velocity is carried over. `MotionValue`
exposes `getVelocity()` (`motion.luau:138`, `:405-407`), which the review
confirmed makes the carry implementable rather than aspirational. Because one
spring serves the whole call, velocity is preserved in progress space scaled by
the ratio of the largest delta magnitude — an approximation that keeps the
*dominant* motion's speed continuous, at the cost of a small velocity kink on the
non-dominant records at the moment of re-target. Documented, not hidden. There is
no `restart` verb in the motion module (`motion.luau:20-21`) and none is added.

The composition cases were worked through by the reviewer and hold: a **new root
above an old one** composes correctly (a child still finishing its own flight
while riding its parent's is exactly right); an **old root no longer moving**
keeps running on its own spring and is ignored by the new call; and **two sibling
subtrees with different deltas under a moved common ancestor** cannot tear,
because one shared `p` makes every node's absolute offset a uniform
`(absolute delta) × p`. The case that needed the fix was a path claimed by two
calls, handled by per-path record ownership above.

### Implementation details the review pinned, and that the code must honor

- **Seed the delta synchronously inside the commit.** `presenter.tick` runs on
  PreRender (`client/motion_driver.luau:38`) while `refresh` runs on Heartbeat
  (`init.client.luau:840`), so a record installed but not written until the next
  PreRender paints one frame at the new position and then jumps back. The
  precedent is `transitions.luau:321` — seed the absent place before the first
  step.
- **Read `lastRects[path]` before the commit overwrites it.** The commit already
  iterates every solved rect and compares it to `lastRects`
  (`renderer.luau:2557-2565`), which is why the diff is genuinely free — it is
  work already being paid for. The hook must sit *before* line 2562. (Revision 1
  cited `presentationLive == 0` at `:1105` as the precedent; that is a hit-test
  early-out, not a commit hook. Corrected.)
- **Do not blanket-drop records in `structuralSync`.** Structural syncs are
  frequent — virtual-list windowing, `When` branches — so dropping everything
  would snap unrelated in-flight animations. Per-path clearing already exists at
  removal (`renderer.luau:2889-2926`, `lastTransform` at `:2923-2926`); reuse it,
  as `transitions.luau:290-294` does. The V10 hazard (a recycled instance
  inheriting a previous occupant's delta, `renderer.luau:1077-1080`) is closed by
  the per-path clear, not by a blanket one.
- **Studio captures must quiesce.** A matrix capture taken mid-flight is
  non-deterministic; the gate steps the clock to settle before capturing.
  (Headless dumps are unaffected — `dump.fromSolve` re-solves and reads no
  presentation state, `layout/dump.luau:53-71`, and `controller.diagnostics()`
  returns solver diagnostics only, `renderer.luau:3770-3772`.)

### Cost, and what the cap is measured against

Off-path cost is genuinely ~zero: no call means nothing is armed, and the
*comparison* rides work the commit already performs (the *ordering* costs one
tree walk, on armed commits only — see §Blocker 3).

The **cap is per frame, not per call**, because two calls in a frame are now a
supported shape and each costs two presenter passes. It is measured against the
amplifiers the review identified — subtree `applyRect` calls, elision
materialisations, and park refusals — not against spring count, and the chosen
number's derivation is written down beside it. Beyond the cap the commit lands
instantly and emits a diagnostic naming the count, because silently animating 800
roots is a frame-budget bug and silently animating 40 of them is a correctness
lie.

### Reachability — a deliberate boundary, and its escape hatch

`presenter.withAnimation` is reachable exactly where a screen mutates state: a
handler closure created at screen assembly has the presenter (RascalRally holds
`self._presenter` per GUI module, `GaragePilotGui.luau:45` and siblings; gallery
scenarios get `ctx.presenter`). It is **not** reachable inside a control or
composite — controls receive the presenter's *products* through contributions,
never the presenter itself (`slider.luau:278-286`,
`disclosure_group.luau:195-207`, `table.luau:545`).

That is the right boundary and it matches SwiftUI, where `withAnimation` is
called by the app at the mutation site, not by the control. The consequence is
that `row_actions`, `table` and `disclosure_group` cannot animate their own
internal state through this API — and the first request after shipping will be
"make the disclosure group animate its own open/close". If that turns out to be
too tight, the named escape hatch is a `presenter.animator()` handle: a
class-bound closure a screen can pass *down* into a composite, keeping clock and
scope ownership on the presenter while making the verb portable. Named now rather
than reinvented under pressure. Not built this round.

### Proof

Perf-lab scenes before/after with budgets held — including the two-presenter-pass
cost above, measured rather than asserted. No new interactive behavior, so the
four-input rule does not apply, but the public surface gets its conformance
entry, its api.md entry, and a gallery scenario `examples_gallery.spec` runs
headlessly. The headless target already publishes painted position
(`tests/lib/fake_target.luau:237-279`, `presentedPosition`, with precedent in
`tests/presentation_channel.spec.luau:79, 112`), so every claim above is
assertable without Studio.

Two things headless **cannot** show, which therefore get Studio canaries:

1. **A button that closes its own panel inside `withAnimation`.** A synchronous
   refresh from inside an `Activated` handler (`screen_target.luau:2694`) moves
   `structuralSync`'s `adapter.remove` → `Destroy` (`renderer.luau:2886`)
   *inside* the event dispatch, so a control can destroy itself while its own
   handler frame is live. The re-entrancy guard above is the defence; only a real
   adapter can prove it holds.
2. **An extra refresh mid-flick is a no-op for row-actions.** `feedGeometry` runs
   every refresh (`presenter.luau:3838`, `:2378-2393`) and row-actions has
   already produced two review fixes rooted in refresh cadence. The framework
   asserts every `syncGeometry` is idempotent (`presenter.luau:2374`), so this is
   a test obligation confirming an existing claim, not a predicted defect.

RascalRally: additive, zero call sites, with a guard test proven to bite.

## Phase 2 — layout vocabulary [M1]

### 2.1 Stacks parity audit — done, and it found a defect class

Audited in source on 2026-08-12 (`blueprint.luau`, `blueprint_schema.luau`,
every stack arrange branch in `solver.luau`).

**Covered already:** cross-axis alignment (`align` on H/VStack, `alignH`/`alignV`
on ZStack and its children — the nine-position `Alignment` is expressible),
content-hugging default sizing, weighted `fill` distribution with
largest-remainder rounding (`solver.luau:3209-3234`), per-child `margin`,
`Spacer` main-axis fill (`solver.luau:284-292`), `Divider` axis inference.
Facet's `align = "stretch"` is a **superset** — SwiftUI needs a frame trick for it.

**Intentional divergences, to be written down rather than closed:**

| Divergence | Detail |
|---|---|
| Absent `gap` is `0`, not an adaptive default | `solver.luau:570, 1080, 2421` (`node.gap or 0`). SwiftUI's `nil` spacing is a platform-standard value. Changing it now would move every shipped screen, so it is documented, not "fixed" |
| No baseline alignment | `.firstTextBaseline` / `.lastTextBaseline` have no `alignV` value and the solver computes no per-child baseline. Closing it needs the text-measure pass to publish an ascent per child plus a new arrange term — a solver change, not a cheap one |
| No `.alignmentGuide` / custom `AlignmentID` | Needs a per-axis guide-resolution pass threaded through arrange |
| `Spacer(minLength:)` | Already expressible today as `width/height = { type = "minMax", min = X }` on the Spacer; a first-class prop would be sugar. YAGNI |

**The one thing that gets fixed: silently inert placement props.** The audit
generalized a trap this repo already knew about in one narrow form. The seven
placement props are **shared BOX props, legal on every child**
(`blueprint_schema.luau:476-686`), but each is read only by particular parent
arrange branches.

> **HISTORICAL — the defect as it stood on 2026-08-12.** The table below is what
> the audit *found*; it is not the shipped state. The mechanism landed on
> 2026-08-13 (see "Shipped" further down), every live call site was cleared, and
> the read table now lives in `solver.luau` next to the branches it describes —
> which is the only copy that cannot go stale. **Read
> `solver.PLACEMENT_READS`, not this table**, for what is true today. Two
> corrections are folded in below: the original printed `—`/`n/a` in ten cells,
> which read as exemptions and were nothing of the kind, and it omitted the three
> rank/region containers and two of its own props entirely.

| Prop on a child | Anchor | ScrollView | ZStack | H/VStack | flow Grid | GridRow | ViewThatFits / Region |
|---|---|---|---|---|---|---|---|
| `anchor` | honoured (`solver.luau:2882`) | **inert** | **inert** | **inert** | **inert** | *schema-refused* | **inert** |
| `offsetX` / `offsetY` | honoured (`:2911-2912`) | honoured, nudge-only (`:2670-2671`) | **inert** | **inert** | **inert** | *schema-refused* | **inert** |
| `alignH` / `alignV` | **inert** | **inert** | honoured (`:2870, 2873`) | **inert** | honoured per cell (`:3062`) | honoured per cell (`:2974`) | **inert** |
| `lineAlign` | **inert** | **inert** | **inert** | honoured (`:3316`) | **inert** | **inert** | **inert** |
| `gridSpan` | **inert** | **inert** | **inert** | **inert** | **inert** | honoured | **inert** |

Three things that table now states which the first one hid:

* **There are no blank cells.** Every one of the seven props is *authorable* on
  every node, so every (parent, prop) pair is either honoured or inert. `—` and
  `n/a` were shorthand for "I did not check".
  **…and there were never seven — there were nine** (Milestone-1 architecture
  review, C2). `layoutPriority` and `shrinkWeight` (§2.4) are the same kind of
  prop, declared in the same schema paragraph as `lineAlign`, read by nothing but
  a `vstack`/`hstack` shrink pass, and they were left out of this table AND out of
  the read table and the renderer's fast reject — so `UI.Text{ shrinkWeight = 2 }`
  under a ZStack was accepted and silently did nothing, which is the very defect
  this section was written to end, re-committed by the change that ended it. Both
  are in `PLACEMENT_PROPS` / `PLACEMENT_READS` / `placementProps` now, with a
  stacks-only read entry; the audit found no live call site for either.
* **`UI.GridRow` and `UI.Region` are closed by the schema instead.** Both prop
  sets are paint-only/structural, so a placement prop on one is a *construction*
  error — the louder answer. That is why `solver.auditPlacement` carries no
  `gridrow` or `composition` branch: an unreachable branch cannot be tested.
  `tests/placement_audit.spec.luau` pins both schemas so loosening either goes red.
* **A `Composition` and a `Region` are different rows.** A Composition's children
  can only be Regions (schema-closed); a Region's chosen *form* is an ordinary box,
  so `region` is a real, reachable, tested branch.

Every "inert" cell is a property the framework **accepts and then ignores**,
which is the exact thing constitution §4 forbids ("a property that is *accepted*
must *do something*") and the exact failure mode investment 1 of the roadmap was
written to end. `align` and `gap` are the counter-example done right: they are
scoped tightly enough in the schema that using them on the wrong container fails
loudly at construction (`blueprint_schema.luau:734` `GAP`, `:748` `ALIGN`).

**One correction before that refusal is written, from the flex parity audit
(2026-08-12), and it is a dependency rather than an addition.** Refusing
`alignH`/`alignV` under an H/VStack would close off Facet's only leaf-level
route to Roblox's `ItemLineAlignment` — per-child cross-axis alignment — and
ship a refusal that has to be un-shipped the moment that gap is closed. The
audit also found the ambiguity underneath: the solver reads `child.align`
(`solver.luau:3316`), but `align` is a container-only prop, so it is refused on
`UI.Text`/`Box`/`Spacer`/`Image` and only works on a child that is *itself* a
stack — where the one word then means two different things at once (a nested
`VStack{ align = "center" }` both centers its own children **and** centers itself
in its parent's line).

So the fix is: promote per-child cross-axis alignment to a **shared BOX prop
under a distinct name** — `lineAlign` — read at `solver.luau:3316` in preference
to `child.align`. That closes the `ItemLineAlignment` gap, disambiguates the
overloaded word, and leaves `alignH`/`alignV` genuinely inert under a stack and
therefore correctly refusable. One change, two defects.

The schema itself cannot fix the rest: `align` and `gap` are scoped per class
(`blueprint_schema.luau:734-762`), but a placement prop lives on the **child**,
and a child does not know its parent at its own construction. So the check
belongs to the **container**, which does know its children — two tiers:

1. **Construction-time refusal** for direct children. `UI.ZStack{ children = … }`
   inspects each child for props its arrange branch will never read and refuses,
   naming the parent kind, the inert property and the property that *does* work
   there (`anchor` under a ZStack → "use `alignH`/`alignV`"; `offsetX` under an
   HStack → "wrap it in `UI.Anchor`"). This is the house refusal shape from
   constitution §4, verbatim.
2. **A solver diagnostic** for children spliced in later by `UI.When` /
   `UI.ForEach`, whose parent kind is not known at construction. It joins the
   existing `controller.diagnostics()` channel beside the overflow diagnostic —
   the channel `docs/lessons/the-solver-already-told-you.md` exists to make
   people actually read.

Cheap, the house pattern, and it converts a silent wrong result into an immediate
error, which is priority rule 1 of the roadmap.

#### SHIPPED 2026-08-13 — the diagnostic tier, the twelve call sites, and the one tier that was NOT taken

Landed as `solver.auditPlacement` + `Node.inertPlacement` + `Node.placementProps`,
one call in `renderer.toLayoutNode`, one report in `arrange`, and
`tests/placement_audit.spec.luau` (28 cases, all mutation-proved — 25 at first
landing, plus the three that came with the shrink pair on 2026-08-13). The read table
lives in `solver.luau` **next to the arrange branches it describes** — a copy kept
anywhere else goes stale the first time a branch learns a new prop, which is
exactly what happened to the table above it.

**Tier 1 (construction-time refusal) was NOT taken and is not queued.** Its
exposure was measured before it was written, as the mission required, and it turned
out to redden the Rascal Rally build from five live screens. A construction error
is the loudest possible game behaviour change and the standing rule needs separate
authorization for one. Tier 2 — the diagnostic — carries the same information
without that cost, and now that the twelve call sites are clear the channel is
silent on every shipped surface, so tier 1 could be revisited cheaply later.

**What landed in the two seams, and why each is the only one that works.**

* `renderer.toLayoutNode` runs the audit, because that is where `class` has already
  become the layout `kind` (so the audit asks what the **solver** will read, not
  what the constructor was called) and where `appendChild` has already spliced
  `UI.When`/`UI.ForEach`/`UI.ErrorBoundary` children into the real parent's flow —
  the case a construction-time check structurally cannot see.
* `arrange` reports the findings, because that is what buys them the `hiddenDepth`
  gate (a losing `ViewThatFits` candidate does not shout) and the incremental-layout
  reuse replay — the same two properties the overflow diagnostic beside it has.
  **The reuse replay needed one correction** (Milestone-1 RED-TEAM review, HIGH 2;
  `tests/diagnostic_replay.spec.luau`). `solve` replays a skipped subtree's
  previous findings by testing `ctx.skippedIds[d.node]`, and this is the only
  diagnostic in the solver filed under a node **other than the one that files it**:
  the parent files, the child is named. So a walked parent beside a skipped
  audited child filed the finding *fresh* **and** had it replayed — one extra copy
  per layout-dirty frame, unbounded, with the whole list copied forward each solve
  (O(n²) work, a real table leak on a long-lived surface, and every count-based
  assertion on `controller.diagnostics()` made frame-dependent). Each finding now
  carries `filedBy` — the filing parent's id, stamped by `auditPlacement` — and the
  replay gate reads `d.filedBy or d.node`. Both halves are pinned: the duplicate
  stops, and a finding whose *filing* parent really was skipped is still replayed.
* A one-field fast reject (`placementProps`, set on the line that already reads all
  seven values) is what makes it affordable: the overwhelming majority of nodes
  carry no placement prop and cost one comparison instead of seven table lookups.

**The twelve live call sites, all cleared.** Every one set a prop the solver never
reads. Per the director's ruling the inert prop was **deleted** in each — deleting
something inert moves zero pixels by definition, so this was not a behaviour change
— and every deletion whose intent was *unfulfilled* is queued in
[`unfulfilled-placement-intents.md`](unfulfilled-placement-intents.md) with the
migration that would deliver it and the measured pixel move it would cost. That
file is the decision queue; the summary is:

| Node | Parent kind | Prop(s) deleted | Verdict |
|---|---|---|---|
| `src/controls/row_actions.luau` `…/Menu` | `vstack` | `anchor`, `offsetX`, `offsetY` | **REAL DEFECT — already fixed** in the hosted-row-actions round; re-verified silent |
| RR `…/Split/ListBand` | AdaptiveStack | `alignH`, `alignV` | redundant — the stack's `align = "stretch"` + a `fill` on both axes already do it |
| RR `…/CtaFit/CtaRow` | `fits` | `alignH` | redundant — `width = FILL` already spends the whole offer |
| RR `…/ChipBand` | `anchor` | `alignH` | redundant — the two `fill` Spacers already centre it |
| RR `…/ChipBand/ChipRow` | `hstack` | `anchor`, `offsetY` (+ the dead `bandOffsetY` option) | **queued** — §6's reflow was never implemented; superseded by amendment A8 |
| RR `…/WatchedCard/WatchedText` | `hstack` | `alignH` | redundant *as measured* — the card hugs 60+260+60 and the column solves to x=60, already centred |
| RR `…/AutoscrollChevron_{top,bottom}` | `zstack` | `offsetY` | **queued** — the 2 px edge inset never applied |
| RR `/Omen/OmenStack/{HelpCap,HinderCap,Tail}` | `vstack` | `alignH` | **queued** — cap and tail sit at x=0 in a 120px column; `lineAlign` moves them +49/+55 px |
| RR `/Omen/OmenStack/OmenCaption` | `vstack` | `alignH` | redundant — `width = FILL` fills the line, so `lineAlign` has nothing to move |
| `p1_glade/ui/overview.luau` `…/Line/TwoLines` | `fits` | `alignH` | redundant — inert twice, and `start` is already a stack's default |
| `p1_glade/ui/shop.luau` `…/BestValue` | `vstack` | `alignH` | **queued** — `lineAlign = "end"` would move the chip ~1045 px at 1200 px wide |
| `theme_picker.luau` `…/Dock/Shell` | `anchor` | `alignH` | **queued** — `align = "end"` would move the collapsed chip +457 px |
| `init.client.luau` `…/Dock/Bar` | `anchor` | `alignH` | redundant — inert twice, and the column is `width = FILL` |

**The third blocker cleared itself, as predicted, and was verified rather than
assumed.** `games/RascalRally/code/tests/facet_sponsor_results.spec.luau:3739` and
`tests/reference/glade_spec.luau:1466,1489` assert an *empty* `diagnostics()` list.
With the inert props deleted those screens emit nothing and all three pass
**unedited** — no test was weakened, skipped or changed.

**Two props of the same defect class shipped by this same phase are in the watched
set:** `lineAlign` is inert anywhere but an hstack/vstack, and `gridSpan` anywhere
but a `UI.GridRow`. `gridSpan`'s inertness was *documented in
`blueprint_schema.luau`* as though it were part of the feature — the §4 violation
written down. That doc line is corrected in place and both props are policed and
mutation-proved.

**Perf: no delta is claimable, and the noise floor is stated first.** A same-arm
A/A of four consecutive identical runs (`tools/perf.sh`, 100 scene × profile cells
aggregated as the sum of `phases.total.p50_ms`, no edit between runs) spread
**1.16 %**. Interleaved OFF/ON/OFF/ON/OFF/ON then gave per-pair deltas of
**−1.51 %, +2.30 %, +2.05 %** — mean **+0.93 %** against within-arm spreads of
**2.48 % (OFF)** and **1.55 % (ON)**. The deltas cross zero and the mean is inside
the floor. Budgets still `PASS` (100 runs, 20 scenes, all `ok`; worst scene 4.90 ms
p95 against the 8.333 ms ceiling). This agrees with the pre-landing read
(+0.88 %/+1.41 %/−0.01 %, mean +0.76 %); that round also recorded a
**false signal** from a non-interleaved A/B (+1.46 %/+2.36 %) taken when the
same-arm floor had drifted from 0.31 % to 1.88 % across a session — interleave, and
state the floor, or do not report a number.

**One correction to the existing parity doc found here:** its ZStack row claims
"no per-child `.zIndex` override", but `blueprint_schema.luau:678-688` defines
`zIndex` as a shared BOX prop with real documented sort behavior. Phase 5
re-verifies it against the renderer rather than copying either claim forward.


### 2.2 `GridRow`

`UI.Grid` stays exactly what it is — a uniform flow grid — for every existing
caller. When a Grid's children are `UI.GridRow` nodes it switches to **row mode**:
each row declares its cells in order, column *n* is as wide as the widest natural
cell in column *n* across all rows (SwiftUI's rule, not today's single shared
width, `solver.luau:434` `colW = (innerMaxW − gap × (cols − 1)) / cols`), and a
cell may declare `gridSpan = n` to cover several columns.

Mechanically: `GridRow` is a new blueprint **primitive** — a node class the
solver understands natively, per the constitution's kind ladder — so it gets a
schema class, a `class_contract.luau` registry row (`focusRole = "none"`, a
layout container, like `Grid`'s), and its own solver branch. Row mode is selected
by the Grid's children, not by a mode prop: a Grid whose children are all
`GridRow` is a row grid, a Grid with no `GridRow` child is today's flow grid, and
**a mix is an authoring error** naming the fix, because silently picking one
reading is how a screen ends up laid out by a coin flip.

Column widths in row mode are a two-pass measure: measure every cell at its
natural size, take the per-column maximum, then arrange. A spanning cell
contributes to no single column's maximum (SwiftUI's rule — a span cannot widen
one column on its own) and is fitted to the sum of the columns it covers plus the
gaps between them.

Existing callers touch nothing, which is the constraint the brief set, and the
two live RascalRally `UI.Grid` call sites (`ResultsScreen.luau:2495, :2546`) are
pinned by a test that fails if row mode changes flow-mode geometry by a pixel.

#### Shipped 2026-08-13 — and two things the design above did not say

`tests/grid_row.spec.luau` (framework) and
`games/RascalRally/code/tests/facet_grid_row_contract.spec.luau` (consumer pin,
which reads the two declarations out of `ResultsScreen.luau` so the replica cannot
drift from the call site). Both halves mutation-proved: a shared column width, a
span that widens its first column, a span that forgets the gaps it crosses, a mix
that silently picks row mode, and a one-pixel change to the flow grid's own column
arithmetic each redden a named case.

Two decisions the design left open, taken in the implementation and written down
because they are the kind that get rediscovered:

- **`GridRow`'s prop set is tiny, and the omissions are the point.** `width`,
  `height`, `padding` and `margin` are construction errors on it, not
  accepted-and-ignored: each would be a second authority against the grid that owns
  the columns and the row pitch, and a padded row would inset its cells out of the
  columns every other row aligns to. What a row does own is its paint (`surface`,
  `shadow`, `gradient`, `corners`, `stroke`, `zIndex`) — the striped-row case.
- **Naturals that do not fit are reduced proportionally**, rather than overflowing.
  The flow grid cannot overflow (its column width is derived from the offer), and
  a row grid that could would have broken that property under the same name.

And one thing outside the layout branch that row mode forced: the focus map derives
a Grid's rows from its `columns` prop, which a row grid does not have — so a 2x2
board read as one four-wide row and Down went nowhere. `emitGridGroups` now reads
the declared `GridRow` children (through structural regions) when the Grid has them,
falling back to the `columns` inference otherwise. Proved by a D-pad case in
`grid_row.spec`, mutation-proved by disabling the declared-row branch.

### 2.3 Lazy stacks: no new names, but the substrate gains a horizontal axis

The locked decision is that Lazy stacks are thin sugar over the existing
virtualized substrate and that no second virtualizer gets built. Holding to that,
the substrate turns out not to leave room for the sugar:

`newVirtualList` requires a **uniform** `rowHeight` for the whole list, and the
refusal explains why — "the windowing arithmetic is index×height and a per-row
wrap difference would silently mis-window at the largest text offset"
(`virtual_list.luau:300-312`). It also requires an explicit `key`, an explicit
`cell`, and a `viewportHeight` (`:341-344`), and its canvas is a full-height
`Anchor` windowed by `CanvasPosition.Y` — **vertical only**.

SwiftUI's `LazyVStack` is the opposite of all of that: arbitrary heterogeneous
content, no declared height, no key function. A constructor named `LazyVStack`
that demanded a uniform row height would be a **false parity claim**, and the
constitution is explicit that "a claim the code does not honor is a defect of the
same severity as the reverse" (§14). Stripped of the name, the sugar adds nothing
but different words for the same fields, and the constitution also says to prefer
updating an existing module over adding a parallel one.

**So neither `LazyVStack` nor `LazyHStack` ships as a name** (game-director
decision, 2026-08-12). `newVirtualList` stays the one lazy-collection surface and
the parity doc records it as Facet's equivalent, with its divergences named
rather than papered over. The brief sanctions this ("document the gap precisely
and stop — that is an acceptable phase outcome").

**But the horizontal axis DOES ship** (game-director decision, same date, after
the two halves were costed separately). Of SwiftUI's two missing capabilities,
sideways scrolling is mechanical and variable heights is a design problem; the
director's call was to take the cheap one now and record the expensive one.

`newVirtualList` gains **`axis = "y" | "x"`**, construction-only for the reason
`ScrollView.axis` is construction-only — a reactive engine scroll axis would
rebuild native scroll state mid-gesture (constitution §16 E-6). The windowing
arithmetic is unchanged; it reads `CanvasPosition.X` and a full-width canvas
instead of `.Y` and a full-height one.

The work is not in the arithmetic, it is in everything that quietly assumed
"down". Each of these is a case in the spec, not a hope:

| Assumes vertical today | What `axis = "x"` needs |
|---|---|
| Naming: `rowHeight`, `viewportHeight` | `itemExtent` / `viewportExtent` as the axis-neutral names, with `rowHeight` / `viewportHeight` kept working as deprecated aliases per ADR-0011 (≥ one MINOR) and registered in `Facet.DEPRECATIONS`. A `rowHeight` on a sideways list is a lying name, and this codebase punishes those |
| Focus navigation walks Up/Down | the list declares its axis to the focus graph so Navigate maps to Left/Right; the focus map stays **one** map read two ways (constitution §9) |
| Keyboard/gamepad: arrows and DPad | the same binding move, gated the same way |
| Edge autoscroll during a drag | drives the axis the list actually scrolls |
| **Row actions are a horizontal swipe** | **refused at construction on a horizontal list**, naming the conflict. A sideways swipe cannot mean both "scroll the list" and "open the tray"; picking one silently is how a gesture becomes unpredictable |

**The variable-height gap is recorded, not built.** Today's window is
`index × pitch`, which is O(1) and exact. Variable heights need a running-offset
index, and the honest problem underneath is that a row's height is only known by
building it — which is the thing virtualization exists to avoid. The two standard
answers each cost something real: estimate and correct (the scroll thumb jumps as
estimates are replaced by measurements) or measure every row up front (laziness
survives for instance creation but not for measurement, so a very long list pays
at mount). Choosing between them needs a screen that actually wants it, and there
is none — every Rascal Rally list is uniform. The parity doc carries the
requirement and both candidate designs so a future mission starts from the
problem statement rather than rediscovering it.

RascalRally rider: its two `newVirtualList` callers are vertical and stay on the
default axis; the deprecated aliases mean they need no edit at all, and a test
pins that a list declaring no `axis` builds exactly what it always did.

#### The gallery scenario the horizontal axis owes

`tests/virtual_list_axis.spec.luau` proves the control; the standing obligation
("every new public API appears in at least one gallery scenario that
`examples_gallery.spec` runs headlessly") is met by
`examples/gallery/scenarios/card_rail.luau` — catalogue entry `card-rail`
("Card rail"), 400 cards on one row, Left/Right and D-pad stepping, a viewport
width re-derived live rather than pinned to a constant, and no `rowActions`
(refused on this axis, and the vertical `row_actions` fixture is where trays are
demonstrated instead). Registered in `scenarios/init.luau`'s `ORDER` and in
`demo_picker.DEMOS`; swept at eight viewports by
`tests/overflow_sweep.spec.luau`.

### 2.4 `layoutPriority`

`layoutPriority: number` (default `0`) as a **shared BOX property**, not a
modifier. It is a placement fact a stack parent reads off its children, which is
exactly what `anchor`, `alignH`, `alignV`, `offsetX` and `offsetY` already are
(`blueprint_schema.luau:494-539`); and the constitution's positional-scalar
modifier family (`UI.offset`, `UI.aspectRatio`, `UI.alignment`) is declared
**closed** (§16 E-18), so adding a sixth member there would need an exception
this does not deserve. Reactive (`dirty = { "measure" }`), since a priority
change can change the arrangement.

Today the solver has no shrink pass; this adds one, and only on the overflow
path:

- positive remainder is distributed to `fill` children exactly as it is today —
  unchanged, so nothing on the happy path moves;
- when the main axis is short, children shrink in **ascending priority order**
  (lowest first), each down to its own floor (`minMax.min`, a text node's
  minimum wrap width, or zero), until the overflow is absorbed;
- if everything is at its floor the existing overflow diagnostic still fires,
  with the priority order it tried appended.

**Amended 2026-08-12 after the flex parity audit — the spec above had a hole on
its own default path.** `layoutPriority` defaults to `0`, so in the overwhelmingly
common case **every child sits in the same tier**, and "ascending priority order"
says nothing about what happens inside a tier. Left to document order, the first
of three equal overflowing chips would absorb the entire deficit and collapse to
its floor while its two siblings stayed full size. That is a visibly wrong result,
and it is what the default path would have produced.

So the shrink pass takes **two** inputs, and they are two levels of one
algorithm:

| Input | Default | Role |
|---|---|---|
| `layoutPriority: number` | `0` | **outer sort** — tiers. Consume the deficit tier by tier, lowest first (SwiftUI's model) |
| `shrinkWeight: number` | `0` | **inner distribution** — within a tier, shrink proportionally by weight; `0` means "never shrink" (Roblox's `UIFlexMode.Grow`, CSS `flex-shrink: 0`) |

CSS has only the inner level; SwiftUI has only the outer; composing them costs
one sort and yields both. Building the ordered half now and retrofitting
proportionality later would re-open the same measure/arrange/cache-key/perf-budget
surface twice.

**`shrinkWeight` defaults to `0`, and that is both the conservative choice and
the native-parity one** — Roblox's own `Enum.UIFlexMode.None` is the default and
is documented as "neither shrinks nor grows". So today's geometry is preserved
byte-for-byte, no shipped screen moves, and no consumer that currently relies on
overflow-and-scroll is disturbed. Setting `shrinkWeight = 1` on a row gives
Roblox `Fill`/CSS `flex-shrink: 1` semantics.

Two algorithm details Roblox's docs leave undefined, so Facet decides them
explicitly and records the decision as its own (not as parity):

- **Shrink weight is multiplied by the child's basis size**, as CSS does. Without
  basis-weighting a 400px child and a 40px child give up the same pixels, which
  collapses the small one first.
- **The floor stack** is `minMax.min` → a text node's minimum wrap width → `0`,
  in that order.

Interplay to define and test: `hug`/`fill`/`minMax` dims, `ViewThatFits`, and
`Composition.rank` (a different mechanism at a different altitude — it degrades
or drops whole screen regions; this negotiates sizes inside one stack, and the
parity doc says so rather than letting the next agent conflate them).

**Cache-key obligation.** The shrink pass re-measures a child at a *reduced
offer*, which is already a distinct `maxW`/`maxH` and therefore already a
distinct cache key. That is the claim, and a claim is not a check: the phase
ships a mutation test that deliberately makes the shrink pass reuse the natural
measurement, proves a test fails, and restores. If the pass ever needs an input
that is not the offer, that input goes in the key in the same commit.

> **CORRECTED 2026-08-13 (round 3) — this section used to say `ViewThatFits`
> "picks its candidate *before* any of this and is therefore unaffected". That is
> FALSE, and it was falsified by the very amendment printed immediately below.**
>
> The claim was true of the arrange-only shrink it was written for. PASS 1.5 —
> the measure-side shrink amended in one day later — invalidated it, and nobody
> went back to the sentence. `chosenCandidate` picks the first candidate whose
> **measure** fits the offer; if that candidate is a stack whose children declare
> `shrinkWeight`, its measure reaches PASS 1.5, absorbs the deficit and reports
> the **shrunk** extent — so it fits where it otherwise would not, and wins.
>
> Measured 2026-08-13: swept 150–420px in 10px steps, adding `shrinkWeight = 1`
> to a wide candidate's children flips the winner at **10 of 28 widths (290–380)**.
>
> **RULED 2026-08-14 (ruling 2, director: "follow swiftui's behavior") — the
> section's original CONCLUSION is now true again, for a reason it did not know.**
> SwiftUI selects "the first child whose *ideal size* on the constrained axes fits
> within the proposed size", and an ideal size is what a view reports when nothing
> is proposed to it; truncation, `lineLimit` and `minimumScaleFactor` are all
> invisible to that choice. `shrinkWeight` belongs to that family, so
> `chosenCandidate` now measures candidates with the shrink pass suppressed
> (`ctx.fitProbe`) and `ViewThatFits` is once again unaffected by it. The winner
> is still shrunk after it wins, which is SwiftUI's other half.
>
> So the sentence "`ViewThatFits` picks its candidate before any of this and is
> therefore unaffected" is once more accurate — but it was FALSE ON DISK for two
> days, and the reason it was false is the reason this correction stays here: a
> design document that asserts a consequence of another section is only true until
> that section is amended, and nothing links the two.
>
> Pinned by `tests/layout_vocabulary.spec.luau`, "(b) shrinkWeight DOES NOT change
> which ViewThatFits candidate wins, at ANY width" (the whole 28-width sweep, not
> a sample), "(c) ...and the candidate that WINS is still shrunk", and "(d) the
> fit probe is part of the MEASURE MEMO's key". Evidence and citations:
> `docs/lessons/a-candidate-is-judged-at-its-ideal-size.md`.

**Amended 2026-08-12 (second time) — the pass runs in the MEASURE pass too, and
that is a different cache-key claim.** The spec above was arrange-only, on the
reasoning that measure reports what a stack would *like* and a `hug`/`content`
parent offers exactly that back, so a deficit can only exist at arrange time. That
is true of a hugging parent and false of a **definite** offer smaller than the
content — a `fill`-width toolbar in a fixed screen, which is the canonical use of
the feature. There the squeeze is knowable at measure time, and skipping it made
the measure pass reserve the cross extent of a wrap that will not happen: a label
squeezed to its floor wrapped onto eight lines inside a row that had reserved one
(pinned as "A NAMED SEAM" the day the arrange side shipped, closed the next day).
Shipping a new layout feature with a known member of the "painted at a size nobody
measured" family inside it is shipping the next member.

So the stack **measure** branch gains PASS 1.5: the same `shrinkStack`, run
against the offer, with the squeezed children re-measured at their reduced offer
and the reported main extent reduced by what was absorbed (report and reservation
have to move together, or a `content` parent hands the pre-shrink width back and
arrange finds no deficit at all). It mirrors the `fill` re-measure that PASS 2
already was, for the same reason.

Two properties this owes, and both are proved rather than argued:

- **the cache-key claim is re-verified for the new caller**, not inherited. It
  holds — the measure-side pass also varies only the offer — but the memo is gated
  on `ctx.hasScroll`, so the test that proves it has to put the fixture under a
  `ScrollView` or it runs uncached and proves nothing. Dropping `maxW` from the key
  reddens it.
- **zero added allocation and zero added work when nothing declares
  `shrinkWeight`**: the basis map is built lazily by the opt-in child itself, so
  the inert path pays one `~= nil` field read per child and nothing else. Measured
  A/B/B/A/A/B/B/A over the 20-scene × 5-profile perf suite: +0.36% on the summed
  p95 against a same-arm noise floor of −0.41% (A vs A) and +1.64% (B vs B) — no
  signal.

### 2.6 `distribute` — main-axis distribution (added 2026-08-12)

The flex parity audit found the gap that most clearly puts Facet *behind* the
native controls, and it is one prop wide.

The solver packs stack children from the start of the axis, unconditionally —
`local cursor = if isH then innerX else innerY` (`solver.luau:2044`), with no
distribution term anywhere in the branch. Roblox's `UIFlexAlignment` offers
`SpaceBetween`, `SpaceAround` and `SpaceEvenly`; Facet can reproduce all three
**pixel-exactly** today by hand-placing bare `Spacer`s between children (verified
by solver probe: three 100px children in a 500px stack land at x = 0/200/400 with
Spacers between, and 33/67/67/33 with weighted Spacers at the ends).

**But only for a static child list.** `children` is a static array
(`blueprint.luau:475-487`); a variable-count list must go through `UI.ForEach`,
whose `row` returns exactly **one** blueprint — so separators cannot be
interleaved at the parent's main axis at all, and wrapping each item in a nested
stack does not work because the inner Spacer resolves against the inner stack's
width rather than the outer remainder. A tab bar whose tab count varies — which
is the native documentation's own motivating example — is currently
**inexpressible**.

So: `distribute` on `HStack` / `VStack` / `AdaptiveStack` / `Screen`, values
`"start" | "center" | "end" | "spaceBetween" | "spaceAround" | "spaceEvenly"`,
default `"start"` — byte-identical to today. It is one initial-cursor offset plus
a per-gap increment at `solver.luau:2044`, and it closes the static *and* the
dynamic case together, plus whole-group main-axis centering, which today also
needs hand-placed Spacers.

One composition rule to write down: `distribute` acts on what `fill` children did
not take (`remaining` at `:2004`). When `fillWeightSum > 0` there is no leftover
to distribute, and a `distribute` other than `"start"` in that situation is an
authoring mistake — it gets a diagnostic naming the conflict rather than silently
doing nothing.

### 2.7 Flow-wrap — recorded, not built

Roblox's `UIListLayout.Wraps` packs "as many as fit per line" with ragged item
widths. Facet cannot express it: `Grid` is a **uniform-pitch** layout
(`solver.luau:1875-1876`) where every cell gets `innerW / cols`, and
`minColumnWidth = "intrinsic"` sizes every column to the widest child — a
different and wastefu shape.

This one is genuinely its own mission, not a prop. It is a new arrange branch
with line breaking, per-line cross extent, and a cross-axis line-distribution
rule that **the Roblox docs do not define** — so Facet would have to define it —
plus non-trivial interaction with incremental layout, instance recycling and
virtualization, each of which carries a live perf budget. It gets the same
treatment as variable-height virtualization in §2.3: the requirement and the open
design question recorded in the parity doc, built when a screen wants it.

### 2.5 `containerRelativeFrame`

Scoped form, per the locked decision:

```lua
UI.containerRelativeFrame(bp, { axis = "horizontal", fraction = 0.5 })
UI.containerRelativeFrame(bp, { axis = "horizontal", count = 3, span = 1, spacing = 8 })
```

The **container** is the nearest ancestor that owns a viewport — a `ScrollView`'s
content viewport, else the surface root — not the immediate parent, which is what
distinguishes it from the existing `percent` dim. Paging form matches SwiftUI:
`size = (viewport − spacing × (count − 1)) / count × span + spacing × (span − 1)`.
Closed spec keys; strict schema; exported types.

Mechanically, the solve carries the nearest container's inner size down the
arrange as a `ctx` field, pushed and popped at each `scroll` node — the same
shape `ctx.hiddenDepth` already has.

**And this is the input the cache key does not cover — the concrete case §Phase 0
warned about.** The measure memo is keyed
`"{maxW}|{maxH}|{hiddenDepth}"` per node identity (`solver.luau:1141`). A
`containerRelativeFrame` node resolves its dimension from the **container**
viewport, which is not the parent's offer, so two subtrees under *different*
containers can be offered identical `maxW`/`maxH` and legitimately want different
answers — a silent stale hit. Unlike `layoutPriority` (§2.4), which only ever
varies the offer and is therefore already covered, this one genuinely widens the
key: the container's inner size joins it. Mutation-proved in the same commit —
remove the container term, watch a test go red, restore.

Perf: incremental layout stays incremental; the layout perf scenes run
before/after and their budgets hold.

#### Shipped 2026-08-13 — and the cache-key widening cost more than "one more field"

`tests/container_relative_frame.spec.luau`; the memo case sits under a ScrollView
because the memo is gated on `ctx.hasScroll`, and it is mutation-proved BOTH ways
(drop the container from the key: the case reports the measure-time 200 where 63 is
painted; skip the arrange-side container push: 8 of 13 cases fail).

**The widening is CONDITIONAL, and that condition is not a micro-optimisation.**
The container is `ctx.scopeKey`'s second and third segments, and `scopeKey` carries
the container only once a `containerRelative` dimension has actually been measured
(`armContainer`). Unconditionally, the key was correct and the cache was dead: a
scroller's container is its OFFER's inner size at measure and its RECT's at arrange,
so every child of every scroller got a different key in the arrange pass and the
memo missed on all of them — which is the exact second measure the memo exists to
remove. Measured, 4 ABBA blocks per arm: **+14.3% / +18.9% / +22.8%** p95 on
`lab-dense-scroll` / `virtual-list-scroll` / `lab-collection-churn` against a
same-arm noise floor of 2.9 / 8.1 / 11.2%. Conditioned: **+0.8% / +1.5% / +2.4%**
against 5.2 / 5.4 / 6.0%, i.e. inside the noise, whole-suite median −0.7%.

The late arm cannot go stale, and the argument is in `rebuildScopeKey`: a stale hit
needs a container-dependent node read under a container-free key, and a node's size
can only depend on the container through a `containerRelative` descendant, whose
measure arms the flag. Pre-arm entries become unreachable, not stale.

**THE ARRANGE REUSE SKIP HAD TO BE WIDENED TOO, and the first round widened only
the memo** (Milestone-1 RED-TEAM review, HIGH 3;
`tests/container_relative_incremental.spec.luau`). Incremental layout — the
shipped default — replays a subtree when nothing inside it is dirty *and it lands
on the rect it already had*. That argument is sound for every dimension the solver
had before this section, because each resolves against the parent's **offer**,
which the rect carries. A `containerRelative` dimension is the first one that is
not a function of its ancestor's rect at all, so a wrapper whose own rect never
moves replayed a descendant sized against a container that had since narrowed —
measured at 4px stale on a scroller whose bar reserve armed, and it stayed stale.
The fix mirrors the audit's shape: `renderer.toLayoutNode` marks every subtree
holding a `containerRelative` dimension (`containerRelativeInside`), `arrange`
records the container it resolved each marked subtree against, and the skip is
refused when the enclosing container has moved. **The mark stops at a `scroll`
node** — a scroller pushes its own inner size, derived from its own replayed rect,
so a `containerRelative` node under an inner scroller is genuinely insulated from
the enclosing container; that stop is its own mutation-proved case.

Two smaller decisions taken in the implementation: the container is written as a new
**dim type** (`{ type = "containerRelative", … }`) rather than a parallel prop, so it
inherits dim validation, `axisAbsorbs` (it absorbs — it reads neither content nor
offer) and the incremental-layout boundary predicate for free; and an unbounded
container — a scroller nested inside another scroller's own axis — files a diagnostic
and falls back to content, which is exactly what `percent` does on an unbounded axis.

---

## Phase 3 — indicators, label, feedback, table [M2]

### 3.1 Indeterminate progress and a spinner

`ProgressView` gains an indeterminate mode and a
`presentation = "bar" | "spinner"` selector, painted through the existing
`barTrack`/`barFill` theme slots plus one spinner slot. No new styling system.

Indeterminate is selected by **`value = nil`**, which is SwiftUI's own rule
(`ProgressView()` with no value is indeterminate) and needs no second flag that
could disagree with the value. `value` is currently required
(`progress_view.luau:34-43`); it becomes optional, and the existing determinate
path is untouched — pinned by a test and by the one live RascalRally caller
(`ResultsScreen.luau:1471`).

**Reduced motion — decided deliberately.** A loading indicator is the one piece
of motion in this mission that *carries information*: it is the only thing on
screen saying "work is still happening". So it is registered
`kind = "informational"`, which under reduced motion keeps it advancing on the
authority's quantized 250 ms tick rather than freezing or vanishing
(`motion.luau:31-42`). Decorative motion snaps; informational motion steps;
nothing is deleted. Written into the control's header comment and the parity doc.

#### Shipped 2026-08-13 — and one shape the design above got wrong

Shipped as described, with `motionClock` taken as a spec key the way
`newVirtualList` takes it, and deliberately NOT through an input contribution:
`check_registration` derives "interactive" from the presence of
`contribution.attach`, so attaching one would have obliged a four-input proof for
a control that accepts no input at all.

**The spinner's pulse is PAINT, not geometry, and the solver is what decided
that.** The first shape sized each dot as a `percent` of its row — solver-owned
geometry, in the spirit of the determinate bar's percent fill. Every fixture was
green until the surface was mounted where a loading indicator actually lives:
inside a vertical `ScrollView`. Then the solver said what it always says —
`percent size on an unbounded axis (inside scroll axis?)` — five times, once per
dot, and a fraction of an unbounded axis is not a size
(`docs/lessons/the-solver-already-told-you.md`). The dots are fixed squares now
and the travelling bump rides the `tint` channel, which is `dirty = { "paint" }`:
the ring animates for **zero re-solves** and can be dropped into any container
without asking what its parent's axis is. The slot rules still own the dot's
shape; the tint claims only its colour, which is the layering the tint channel
exists for.

Two narrowings written down rather than smuggled: `presentation = "spinner"`
requires `value = nil` (a determinate spinner is an arc, and there is no rotation
or trim channel to draw one with), and `min`/`max`/`format`/`showValue` on an
indeterminate view are refused rather than silently dropped. One new decoration
slot, `spinner`, and one optional theme metric, `controls.progress.spinnerDotSize`
(filled by `snapshot.resolve` from the theme's own space scale, so no existing
package's authored metrics — and therefore no package's content stamp — move).

### 3.2 Label — audited; nothing to build

Audited in source on 2026-08-12. `Label(title:icon:)`, `Label(_:systemImage:)`,
`Label(_:image:)`, the whole `.titleOnly`/`.iconOnly`/`.titleAndIcon`
presentation ladder, and composition inside `Button` are all **covered**
(`label.luau:19-113`, `blueprint.luau:722-793`). The `iconOnly`-with-no-icon
degradation (`label.luau:65-70`) is better than SwiftUI's, which shows nothing.

Three findings, and none of them is a Label change:

- **`LabelStyle` conformances** — locked decision, not built. The mapping the
  parity doc records: Facet's `newLabel` *is* the default style, and a bespoke
  arrangement is hand-authored `UI.HStack`/`UI.VStack` content, not a pluggable
  style object.
- **Bindable `title`** — construction-fixed today (`label.luau:111-113`, static
  memo, deliberate). Already a known follow-on; no shipped screen needs a
  live-relabelling Label. Documented, not built.
- **`Toggle` cannot compose a Label** — `Toggle` is a non-container leaf with a
  flat `label` (`blueprint_schema.luau:1522-1565`), so an icon+title toggle needs
  a hand-rolled composite that would duplicate Toggle's focus and activation
  wiring. This is a **real** gap and an ordinary settings-screen pattern, but
  closing it means making `Toggle` a container the way `Button` became one —
  control-authoring work outside this mission's scope. It is recorded as a named
  gap in the Phase 5 parity doc and flagged for a future mission rather than
  smuggled in here.

One item the audit could not verify from its file set: whether `Label` composes
into `newPopupButton` (SwiftUI's `Menu`). Phase 5 checks it rather than asserting
either way.

### 3.3 `sensoryFeedback` and the haptics adapter

`UI.sensoryFeedback(bp, { trigger, event })`: when the `trigger` Readable
changes, emit `{ type = event, path = … }` on the presenter's feedback bus. The
taxonomy is **closed** (`feedback.luau:32-45`), so an unregistered `event` name
is an authoring error with the twelve valid names listed. Facet still plays
nothing.

**The platform research changed the adapter's design.** Checked against the live
Roblox docs and the current API dump (client `0.734.0.7340915`) on 2026-08-12,
because `ENGINEERING.md` says never to trust training-cutoff memory about what a
platform has. The full record, with sources, is
[`../research/2026-08-12-haptics-engine-facts.md`](../research/2026-08-12-haptics-engine-facts.md).
Findings:

- **`HapticService:SetMotor` is superseded.** Roblox's own class reference says
  so: *"This service has been superseded by `HapticEffect` … For new work, use
  `HapticEffect` instead."* `SetMotor`'s value range, persistence and zeroing
  requirement are **undocumented**, which alone disqualifies it — a motor you
  cannot prove stops is a stuck-rumble bug you cannot write a test for.
- **`HapticEffect` is a released Instance class** (full release 2025-09-16) with
  `Play` / `Stop` / `Ended` / `SetWaveformKeys` and a first-party preset
  vocabulary, `Enum.HapticEffectType` = `Custom`, `UIHover`, `UIClick`,
  `UINotification`, `GameplayExplosion`, `GameplayCollision`. So the adapter
  cites presets and never hand-rolls motor pulses.
- **`GuiButton` carries `HoverHapticEffect` and `PressHapticEffect`** — assignable
  `HapticEffect` references the **engine** fires. Facet already materializes
  `TextButton`s, so the `activate` verb takes this **property route**: the
  framework assigns a reference and never calls `Play()`, which keeps "Facet
  plays nothing" literally rather than nearly true. The bus subscription covers
  only the verbs with no engine hook. This was not in the brief's design and is
  strictly better than what the brief described.
- **Not gamepad-only, but say so carefully.** The `HapticEffect` class reference
  lists haptic-capable iOS and Android phones alongside PlayStation, Xbox and
  Quest; the gamepad input guide lists only the controllers, in equally absolute
  phrasing. The doc conflict is recorded rather than resolved by preference, and
  the honest ledger claim is "gamepad: documented and physically verifiable;
  phone: documented, not verifiable from here."
- **There is no capability API for `HapticEffect` at all** — no `IsSupported`,
  nothing on `UserInputService`. The only probe on the platform belongs to the
  superseded service and is boolean, which is exactly the shape
  `docs/lessons/capability-probes-must-be-tri-state.md` says lies: `false` means
  both "no motor" and "no gamepad connected *yet*". So the probe is a lattice —
  `supported | unsupported | unknown | blocked | absent` — with **`unknown` the
  default for touch and for the pre-first-gamepad state**, and it re-probes on
  `GamepadConnected` / `GamepadDisconnected` / `LastInputTypeChanged` rather than
  caching once at boot.

**The mapping is total over the twelve verbs, and five map to nothing** —
`arrive` (fires on every chase settle; a haptic there is per-frame noise),
`cancel` (absence of feedback *is* the signal for "nothing happened"), `dismiss`
and `supersede` (not player-caused; buzzing at a self-retiring toast is a
phantom). The map is asserted **total**, explicit `nil` included, so a future
taxonomy addition shows up as a visible gap instead of a silent drop. `adjust` is
rate-limited: sliders and steppers fire per tick, and unthrottled that is a
buzzsaw that also blows the documented "fewer than 100 simultaneous effects"
budget. Effects are **pooled**, one per mapped verb, never constructed per fire.

**Evidence, split honestly.** Headless proves: default-off produces zero
constructions and zero plays; mapping totality; `adjust` coalescing under a fake
clock; the probe returning `unknown` rather than `false` for touch; re-probe on
device change; enum resolution never throwing and never silently falling back to
`Custom` (a defect this repo has already been bitten by, game-side); pool
bounded; and a grep test that no haptics symbol is reachable from `src/present/`,
`src/layout/` or any server path. **This dev machine cannot produce positive
evidence** — Roblox documents controllers on macOS 15+ as unsupported — so a
Studio canary here proves only "never throws", and perceptible feedback on a
gamepad, on a phone, and the player's own haptics toggle are honest
`PENDING_PHYSICAL` rows, one each, that only a device closes.

### 3.4 Table

**Modifier-key selection needs no work — it shipped.** Phase 0 settled the
contested question in source: Shift-click ranges and Cmd/Ctrl-click toggles are
implemented, anchor-tracked, and covered by passing tests. What is broken is the
file's own header at `table.luau:8-10`, which still says "modifier-key semantics
are Phase B" while the implementation comment 1800 lines below says they shipped.
A stale comment is a bug — the next agent will believe the header — so it is
fixed, and the fix is the whole of this item.

**`onPrimaryAction` is the real work.** Zero hits in `src/` or `tests/` today,
and no field on `TABLE_KEYS`. Reachable on all four inputs with no invented
gesture:

| Input | Gesture |
|---|---|
| Pointer | double-click |
| Keyboard | `Return` on the focused row |
| Gamepad | A / Cross on the focused row |
| Touch | tap an **already-selected** row; with `selection = "none"`, any tap |

The touch rule is the one that needed a decision. A blanket "single tap fires it"
would make every selection open a row, and a double-tap is not a touch idiom.
Tap-to-select then tap-again-to-open is a real, common mobile pattern, it needs
no new gesture, and it keeps touch fully reachable rather than telling a phone
player to find some other affordance. Written down as a divergence from the
pointer idiom, with a four-input proof and a conformance-registry entry.

> **SUPERSEDED 2026-08-13 — the touch row of that table is wrong, and the
> `#### Shipped` note below it describes the rule it replaced.** Read
> `#### Corrected 2026-08-13` at the end of this section, which is the live
> contract; the two blocks above and below are kept as the record of what was
> shipped first and why it changed.

#### Shipped 2026-08-13 — and the touch rule has a price, which is now on the record

The header at `table.luau:8-10` is fixed and now says what shipped, citing
`docs/lessons/a-header-comment-describes-the-path-it-was-written-for.md`.

`onPrimaryAction(item, key)` shipped with the gesture table above. Three things
the design did not say:

- **The double-click window needs a clock, and Table had none.** It takes the
  `now` half of the existing `bindMotion` contribution seam (the additive second
  argument), ignoring the clock itself, and falls back to `os.clock` when no
  presenter bound one. Without a scripted `now` the pointer cases assert nothing:
  two `adapter.tap` calls in a spec are microseconds apart, so the window is
  satisfied by the test's own speed rather than by the code. The slow-pair case
  only bites with the injected clock, and that was mutation-checked.
- **In `selection = "multi"`, the touch rule SPENDS the tap-to-deselect gesture.**
  A tap on a selected row used to toggle it off; with `onPrimaryAction` declared
  it opens instead, and deliberately does not re-toggle (deselecting the row you
  just opened is the one outcome nobody means). The plan's rule has no carve-out
  for `multi` and this is the consequence; the alternatives were worse — dropping
  the touch rule in `multi` leaves a phone player with no way to OPEN a row at
  all, which is the reachability failure the four-input bar exists to prevent.
  It costs nothing in `single` (where re-selecting a selected row was already a
  no-op) or in `none`. Pinned by its own test rather than left to be discovered.
- **A modified click never opens**, on any input: Shift / Cmd / Ctrl is a
  selection gesture, even if it lands twice inside the window.

#### Corrected 2026-08-13 — the touch rule is Apple's, and we had invented one

**This block supersedes the touch row above and the second bullet of the
`Shipped` note.** Game-director authorised, after the API was checked against
live `developer.apple.com` rather than memory. Pointer, keyboard and gamepad are
unchanged.

**What Apple documents.** There is **no `onPrimaryAction` symbol in SwiftUI at
all** — ours is our own name; SwiftUI delivers the verb as `primaryAction:` on
`contextMenu(forSelectionType:menu:primaryAction:)`, whose text reads: *"In macOS,
a single click on a row in a selectable container selects that row, and a double
click performs the primary action. In iOS and iPadOS, tapping on the row
activates the primary action. To select a row without performing an action,
either enter edit mode or hold shift or command on a keyboard while tapping the
row."*

| Input | Live contract | Was |
|---|---|---|
| Touch, normal mode, action declared | **a plain single tap on any row activates it** | tap a row that was already selected |
| Touch, **edit mode** | **tap toggles selection; activation is unreachable** | activation competed with deselect |
| Touch, no action declared | unchanged — tap selects exactly as before | unchanged |
| Pointer / Keyboard / Gamepad | unchanged — double-click / `Return` / A-Cross | |

**Edit mode is the touch selection mode, and that is what makes the first row
affordable.** `EditMode`: *"On devices without an attached keyboard and mouse or
trackpad, people can make multiple selections in lists only when edit mode is
active."* HIG Lists and tables: *"In iOS and iPadOS, people must enter an edit
mode before they can select table items."* So the gesture the first shipped rule
*spent* — `multi`'s tap-to-**deselect** — is given back, in the mode a player is
deliberately in to manage selection.

**And the route into that mode is guaranteed, not assumed** (correction landed
2026-08-13 — see §3.4.1 below). The auto Edit/Done toggle appears whenever edit
mode is the only route to a capability the table declares: `reorderable`, **or a
selectable table that declares `onPrimaryAction`**. `spec.editing` /
`api.editing` is the seam for a consumer who wants to own the affordance.

**The honest cost, documented rather than hidden.** With a primary action
declared, touch loses tap-to-select in **normal mode entirely** — including the
single selection iOS 16+ would otherwise allow (`List`: *"When people make a
single selection by tapping or clicking, the selected cell changes its
appearance… To enable multiple selections with tap gestures, put the list into
edit mode"* — declaring a primary action is exactly what forces that retreat).
Apple accepts it deliberately. **The corollary is the author's call: if a table's
dominant touch use is selecting rather than opening, do not declare
`onPrimaryAction` on it at all.**

**What the first round got right:** avoiding the double-*tap*. The HIG's Gestures
documents double tap as **zoom**, and watchOS warns it conflicts with list
navigation.

**Two documentation corrections this forced**, both applied: keyboard `Return` is
**not** SwiftUI parity (Apple documents no key for row activation; it is a
convention that matches `NSTableView` practice), and `onPrimaryAction` is **our**
name, not SwiftUI's. Both were claimed as parity in
`docs/reference/swiftui-parity.md` and implied in `table.luau`'s own field
comment.

#### 3.4.1 Corrected 2026-08-13 (same day, second pass) — the touch rule needed a door, and it needed a principle rather than a clause

Moving touch selection into edit mode **relocated** a four-input reachability
failure instead of removing it. The auto Edit/Done toggle appeared only for
`spec.reorderable == true`, so a table that was `selection = "single"|"multi"`,
declared `onPrimaryAction`, and was **not** reorderable had no route into edit
mode at all — and since every plain tap now opens, its own `selection` was
unreachable on touch, entirely, unless the consumer wired `spec.editing`
themselves. Nothing in the shipped tree was in that shape (both example tables are
`reorderable`, and one owns its `editing` signal), which is exactly why the suite
stayed green over a hole.

**The shipped predicate**, in `table.luau` beside the toggle:

```lua
local reorderNeedsEditMode = spec.reorderable == true
local touchSelectionNeedsEditMode = selectionMode ~= "none" and spec.onPrimaryAction ~= nil
local autoEditRoute = spec.editing == nil and (reorderNeedsEditMode or touchSelectionNeedsEditMode)
```

It is deliberately a **union over the edit-mode-only capability set**, not a rule
about `onPrimaryAction`: the toggle appears when the table declares *any*
capability reachable only in edit mode, and a future one joins by adding a named
clause. The set was audited against every `editingSignal` read in the file and is
exactly two today — the ≡ reorder handle (`condition = editingSignal`, and the
only touch route to a reorder, since a touch drag on the row body is declined so
native scroll owns the pan; gamepad grab refuses unless editing is true), and
touch selection. `spec.rowActions`' edit-mode leading minus was considered and
**excluded**: it is a second route to a destructive action the swipe tray and the
Task-8 keyboard/gamepad menu already reach in normal mode, so it is an affordance,
not a capability. Only "no other route exists" earns a clause.

**Auto-showing the toggle at all is ours, not Apple's** — and the brief that
commissioned this assumed otherwise, so it is worth stating. Verified against
developer.apple.com on 2026-08-13:

| Symbol | Availability | What Apple actually says |
|---|---|---|
| `EditButton` | iOS/iPadOS/Mac Catalyst 13.0, visionOS 1.0 — **no macOS, tvOS or watchOS** | "A button that toggles the edit mode environment value… for content within a container that supports edit mode." Apple's example places one in a `.toolbar` **unconditionally**. **No documented rule for when it should appear** |
| `EditMode` | iOS 13.0 | "a `List` with a `ForEach` that's configured with the `onDelete(perform:)` or `onMove(perform:)` modifier provides controls to delete or move list items while in edit mode. On devices without an attached keyboard and mouse or trackpad, people can make multiple selections in lists only when edit mode is active" |
| `onDelete(perform:)` / `onMove(perform:)` / `onInsert(of:perform:)` | iOS 13 / 13 / 14 | capabilities are declared by **attaching a handler**, never by one boolean |
| `deleteDisabled(_:)` / `moveDisabled(_:)` / `selectionDisabled(_:)` | iOS 13 / 13 / **17** (macOS 14) | the per-row opt-outs are **per capability**, one modifier each |

So the capability→edit-mode half *is* Apple's, and it is precisely the principle
above: edit mode surfaces whichever capabilities exist. The **auto-show** is ours,
forced by a bar SwiftUI does not carry — Facet's four-input rule makes every
declared verb reachable on every input, so a consumer who simply forgot to place a
toggle must not be able to ship a table no finger can select in.

Proved in `tests/table_input.spec.luau` from all four sides (the shape that needs
it, plus mouse-session / `selection = "none"` / no-`onPrimaryAction` / consumer-owned
`editing`), cited as a fourth Table×touch case in `tests/conformance/controls_registry.luau`,
and pinned game-side in RascalRally's `tests/facet_racer_list.spec.luau` — its racer
list is `single`-select with no primary action and must never grow an Edit button.
The interaction-class CANCEL block now shares the same `autoEditRoute` predicate, so
the widened toggle cannot strand a widened set of tables in edit mode.

##### Owed, not fixed here — the hit expander drops the pointer kind

`src/client/screen_target.luau:3312` fires the 44px minimum-target expander's
activate as `handle.activate({ source = "hitExpander" })` with **no `pointer`
field**. `Table.handleActivate` branches on `meta == nil or meta.pointer ==
"touch"` for the touch rule and falls through to the mouse branch otherwise, so a
finger landing in the *overhang* of a row shorter than 44px is routed as a mouse
click: it **replace-selects instead of opening**, which is the opposite of the
rule this section ships.

*Exposure today is small* — sibling row buttons occlude most of the overhang, and
RascalRally's only `newTable` is single-select with no primary action, so both
branches do the same thing there. *Reproduction*: a `rowHeight` under 44 on a
table with `selection` + `onPrimaryAction`, tapped in the expanded band rather
than on the row. *Fix direction is adapter-side*: carry the originating pointer
kind into the expander's meta (the expander already knows which input opened the
capture) rather than teaching each control to treat a missing `pointer` as touch —
the control's default is deliberately "no meta means touch", and widening that to
cover an adapter's omission would hide the next one. Written up in full, with the
general rule it teaches, at
[`docs/lessons/a-synthesized-activate-must-carry-the-pointer-kind.md`](../lessons/a-synthesized-activate-must-carry-the-pointer-kind.md).


### The motion demo and the global reduced-motion toggle

Game-director requirement, 2026-08-12: **at least one showcase example must
demonstrate animation, and carry a reduced-motion toggle so the difference is
visible.**

**Where it goes was settled by adversarial review, not by taste** (2026-08-12,
`[SHOWCASE-CHROME]: CONCERNS 16`). The obvious answer — a third chip beside the
demo and theme pickers — was **rejected**, and the reasoning is worth keeping:

- **It does not fit, by the strip's own arithmetic.** `CHIP_LABEL_CHARS = 14` is
  documented as "what fits beside the demo picker's chip on the narrowest phone
  portrait (320px)" — that constant *is* a two-chip budget written down as a
  number. At 320px the chrome has ~304px of inner width and the two chips plus
  their gap use ~284. Twenty pixels of slack; a chip needs ninety. Two chips at
  320px under a large font is already the failure case **today**.
- **The hierarchy is wrong.** "Which demo" is a verb you use constantly; theme
  and motion are settings you set once. Giving all three permanent equal-width
  space on the smallest supported viewport is the design error, and "one chip per
  axis" is a growth law with no terminating condition — locale, `nativeStyle` and
  `forceScrollFallback` are all queued behind it.

**The shape instead:** chrome carries exactly **two** targets forever — *which
demo*, and *settings* — with a `ViewThatFits` ladder stepping them down to
icon-only rather than clipping labels by character count (the reference proof
`p4_foyer` already ships that ladder correctly). Motion lives in the settings
surface beside the theme panel. The motion demo *additionally* carries its own
inline Full/Reduced control, which is not duplication — it is the demo teaching
its own subject.

**The control is `Full | Reduced`, never "on/off".** The environment fact is
genuinely binary (`env/environment.luau:47, 166-167`), but the *effect* is not:
decorative motion snaps while informational motion keeps running and quantizes
(`motion.luau:31-42`). A control labelled "Motion: Off" teaches the opposite of
the framework's proudest accessibility claim. The nuance belongs in the demo,
shown — decorative and informational side by side under one spring — not in the
label.

The toggle is deliberately **global**, not local to that one scenario. Three
reasons, and the second is the one that earns it:

1. it makes the animation demo self-explanatory, which is what was asked for;
2. it lets **every** demo be checked under reduced motion on a real device, and
   the showcase rule forbids reaching new behavior through a workspace-attribute
   edit plus a republish — so without an in-experience toggle there is no honest
   way to run the reduced-motion axis of a device canary at all;
3. reduced motion is a live environment fact (`env:set("reducedMotion", …)`,
   with `motionPolicy` derived from it and read live, `env/environment.luau:166-167`),
   so flipping it must re-solve without a remount — which is itself a claim worth
   a device proof rather than a headless assertion.

The scenario shows the three things `withAnimation` actually does — something
moving, something appearing beside it, and a re-order — all under one spring, so
the shared-progress behavior is visible rather than described. Under reduced
motion the same interactions land instantly and exactly, which is the whole point
of the accessibility policy: nothing is deleted, only the travel.

It ships in the same `.rbxl` rebuild as the device-bug round
([`device-bug-round-2026-08-12.md`](device-bug-round-2026-08-12.md)) so the
showcase is rebuilt once, not twice.

#### Shipped as `with_animation` — and one place the code is narrower than the paragraph above

`examples/gallery/scenarios/with_animation.luau`, catalogue entry `with-animation`
("Animation"), registered in `scenarios/init.luau`'s `ORDER` and in
`demo_picker.DEMOS`, swept by `tests/overflow_sweep.spec.luau` and driven
headlessly by `tests/examples_gallery.spec.luau`. It does what this section asks:
one `withAnimation("container", …)` call moving a puck, revealing a panel and
re-ordering four keyed chips under one shared spring, with an informational
`clock:glide` bar running beside it so the two reduced-motion categories are
visible at once. The control is `newPicker(presentation = "segmented")` labelled
`Full | Reduced`.

**The scope of "global" is narrower than the three reasons above imply, and
deliberately so.** The inline control writes the REAL environment fact
(`env:set("reducedMotion", …)`) while the demo is mounted — reason 3's live
re-solve is therefore genuinely exercised — but the fixture **restores whatever
it found on dispose**. Reason 2 (checking *every* demo under reduced motion on a
device) is consequently **still owed**, and it is owed by the settings surface,
not by this fixture: a demo that left every other demo in reduced motion after
you walked away from it is a trap, not a setting. The settings surface is the
larger restructure `[SHOWCASE-CHROME]: CONCERNS 16` scoped and it is **not
built** — until it is, the reduced-motion axis of a device canary is reachable
only while this demo is the one on screen.

**The `.rbxl` was not rebuilt by this task** (game-director instruction): the
places are rebuilt once at phase end. That rebuild has since happened — see
"Shipped 2026-08-13" at the end of this section — so the checked-in showcase now
carries this demo. Between the two commits a showcase predating this entry was
expected, not a regression.

### The rest of Phase 4

Update the natural homes first: the motion scenario for `withAnimation`,
`adaptive_controls` for `layoutPriority` and `containerRelativeFrame`, the
playlist table for `onPrimaryAction`, and a loading scenario for the
indeterminate indicators plus `sensoryFeedback`. New scenarios only where no
natural home exists.

Then the **showcase rule** in full, per the brief §"Showcase rule": register in
`scenarios/init.luau` `ORDER` and in `demo_picker.DEMOS`; update
`tests/gallery_demo_picker.spec.luau` and `tests/examples_gallery.spec.luau`;
rebuild `examples/places/Facet-Showcase.rbxl` with `tools/build_places.sh` and
commit it; drive the device canary — including the 320×640 sweep — through the
in-experience picker, never through a workspace attribute.

#### Shipped 2026-08-13 — the coverage audit, and why NO new scenario was added

The audit ran the round's whole public surface against the scenarios rather than
against this document, and it closed the gaps **in existing natural homes**.
That is the outcome the section above asked for, and the reason it is worth
writing down is that the tempting alternative — one new `layout_vocabulary`
scenario carrying six props — would have added a fortieth surface to the sweep,
a fifteenth row to the picker, and a demo whose subject is a *prop list* rather
than a thing a player can do. Every gap had a home.

| Round-2 public API | Gallery scenario that executes it headlessly | Where |
|---|---|---|
| `presenter.withAnimation` | `with_animation` | shipped earlier in Phase 4 |
| `ProgressView` indeterminate bar + `presentation = "spinner"` | `with_animation` | shipped earlier in Phase 4 |
| `newVirtualList{ axis = "x" }` | `card_rail` | shipped earlier in Phase 4 |
| Table `onPrimaryAction` | `row_actions` **and** tutorial example `02_playlist_table` | the tutorial half is new |
| `distribute` | `adaptive_controls` — the `Legend` row | new |
| `layoutPriority` + `shrinkWeight` | `adaptive_controls` — the `Shrink` row | new |
| `lineAlign` | `adaptive_controls` — `VocabEssential` on the `Shrink` row | new |
| `UI.GridRow` + `gridSpan` | `adaptive_controls` — the `Specs` grid | new |
| `UI.containerRelativeFrame` | `adaptive_controls` — the `Page` card | new |
| `UI.sensoryFeedback` | `adaptive_controls` — the volume stepper (`adjust`) and the quality picker (`select`) | new |

`adaptive_controls` is the home this section named for the adaptive members, and
it earned the rest for the same reason: it is already driven from 320×640 to a
ten-foot console by both the always-on overflow sweep and the five-view device
matrix, so a prop whose entire subject is "what happens when the space changes"
is under observation at every width without a new surface to maintain.

**Three implementation notes, each of which is a defect if it is dropped.**

1. **The shrink row is sized so the deficit is REAL.** Three 140px bars plus two
   6px gaps is 432, which fits the HUD column on a desktop and does not fit the
   280px that column gets at 320×640. A row that always fitted would have
   declared `layoutPriority` and never once executed it — the "fixture that never
   reaches the state it means to measure" shape. The row's total floor is
   24 + 0 + 140 + 12 = 176, so it absorbs its deficit at every swept viewport
   rather than falling through to the overflow diagnostic.
2. **The spanning grid cell declares `fill`.** A hugging cell is its own natural
   width whether it spans one column or two, so `gridSpan` would have been
   accepted and invisible — an assertion its own starting value already
   satisfies.
3. **`containerRelativeFrame` is only *distinguishable* on a desktop.** At
   320×640 the Body stacks, so the HUD column IS the scroller's viewport and a
   `percent` dim would return the identical number. The case that proves which
   container was measured therefore runs at 1232×1067, where the column is 588
   and the viewport 1192.

Thirteen headless cases in `tests/examples_gallery.spec.luau` cover the table
above, and all thirteen are mutation-proved: dropping `shrinkWeight`, flipping
`distribute` to `"start"`, moving `layoutPriority` into the shared tier, dropping
`lineAlign`, zeroing the container spacing, replacing `containerRelativeFrame`
with a percent-of-parent dim, dropping `gridSpan`, renaming the sensory verb,
capping the shrink row so it squeezes on a desktop too, making the example's
`onPrimaryAction` inert, widening the framework's double-click window, and
dropping `restore`'s `nowPlaying:set(nil)` each redden a named case.

**No picker or `ORDER` change was needed**, because both surfaces were already
registered: "All controls" (`adaptive_controls`) and "Playlist table"
(`02_playlist_table`) are `demo_picker.DEMOS` entries 1 and 6. The sweep stays at
39 surfaces × 8 viewports and is green, 320×640 and 640×320 included. The
`.rbxl` is rebuilt and committed with this change.

---

## Phase 5 — parity doc rewrite [M3]

One fresh draft of `docs/reference/swiftui-parity.md`, not a patch set. Keep the
Covered / Partial / Composable / Missing taxonomy and the honest-summary
section. Every claim carries a source path or a test file. Record this round's
decisions explicitly:

- no `*Style` protocols — native StyleSheets and theme packages own paint, and
  the doc carries the mapping a SwiftUI author needs instead;
- **no Lazy stack names**; `newVirtualList` is the lazy-collection surface, now
  with both axes;
- **the variable-height gap gets its own section**, not a table row — the
  requirement, why `index × pitch` cannot express it, and both candidate designs
  (estimate-and-correct versus measure-up-front) with what each costs, so the
  next mission starts from the problem rather than the symptom;
- `sensoryFeedback` is a semantic bus event and Facet plays nothing;
- the `Toggle`-cannot-compose-a-Label gap (§3.2) and the baseline-alignment and
  `alignmentGuide` gaps (§2.1) as named, deliberate non-deliveries.

Update the milestone/status table in
[`swiftui-parity-next.md`](swiftui-parity-next.md) to match reality.

---

## Phase 6 — test-suite efficiency [M3]

In order, and the order matters:

1. **Measure.** Time every spec file; publish the slowest-20 table in this
   document. Baseline for the mission: 4144 cases green at `ff7501e`.
2. **Tier.** A fast tier — smoke, core, and the areas this mission touched —
   targeting under 25 % of full runtime, for inner-loop use. The full suite
   stays the gate default. Nothing is deleted at this step.
3. **Consolidate.** Audit overlap (matrix-expansion specs, near-duplicate layout
   specs) and merge or parameterize **only** where a mutation test proves
   coverage survived: break the guarded code deliberately, watch the surviving
   test fail, restore. A check must bite before it is trusted
   (`docs/lessons/` — the gate-integrity sweep found seven checks that could not
   fail).
4. **Propose.** A one-page proposal for a small rendered-canary set in Studio
   over the existing `tools/studio/matrix_capture.sh` + `tools/check_matrix_rows.py`
   path: which scenarios, how many captures, gates-only cadence. **Proposal
   only — nothing built without approval.**

Delivered below. Step 4 is
[`rendered-canary-set-proposal.md`](rendered-canary-set-proposal.md) —
six canaries, eight captures, gates-only, **unbuilt and awaiting a decision**.

### 6.0 The noise floor, before any number below it

Every "improvement" this mission measured without one turned out to be noise, so
the floor comes first. Six **unchanged** `./run-tests.sh` runs at `f476b63`, one
after another, nothing else running:

| run | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|
| wall (s) | 42.38 | 42.65 | 42.66 | 42.87 | 42.64 | 43.35 |

**min 42.38 s, max 43.35 s, mean 42.76 s — spread 2.29 %.** Nothing below ~2.5 %
is a signal at whole-suite scale. All six transcripts are **byte-identical**
(`cmp` against run 1, 5/5) — not merely equal counts, equal bytes. That
independently confirms the determinism claim rather than trusting it, and it
rules the suite out as the source of the drifting counts seen earlier in the
mission (the diagnosis at the time, concurrent agents editing underneath, is
consistent with a frozen tree producing identical output).

Per-spec, from three harness runs and over the 44 specs above 50 ms: median
spread **2.3 %**, worst **8.5 %** (`large_text_matrix`, 83 ms; then
`toast_presentation` 8.4 %, `smoke` 6.9 %). Every spec in the slowest-20 table
below spreads under 3.5 %. Sub-50 ms specs are noise-dominated and no decision
here rests on one.

### 6.1 Measure — the harness, and what it cannot see

`tests/run.luau` is an explicit require list with no per-file structure, so
attribution needs an instrument: **`tools/lune/time_specs.luau`**, run as
`lune run tools/lune/time_specs [out.json] > /dev/null`. It writes `out.json`
and `out.json.tsv`.

It **parses the require list out of `tests/run.luau`** (so it cannot time a
different set than the suite runs), then:

- **`load`** — `os.clock()` around each `require`, in the suite's own order.
  That is the module body plus every fixture built at `describe()` scope, since
  a describe body runs at require time.
- **`cases`** — `os.clock()` around each case function, attributed to whichever
  file was being required when `it()` registered it. Collected by wrapping
  `testkit.it` **before the first spec is required**, so the `local it =
  testkit.it` capture every spec does picks up the wrapper.
- **`total` = load + cases.**

Same specs, same order, one process, same `testkit.run()`; measured overhead is
inside the noise floor (harness wall 42.58 / 42.72 / 42.62 s against the
unchanged suite's 42.38–43.35 s), and **99.95 % of wall clock is attributed**
(42.56 s of 42.58 s).

**What it cannot see.** (a) *First-toucher bias* — a `src/` module loads once and
whoever requires it first pays all of it; `smoke.spec`'s 169 ms load is the
library's own load, and deleting `smoke.spec` would not return it. (b) *GC skew*
— an allocating spec can be charged inside a later spec's case. (c) testkit's
printing, process start and teardown, which appear only in the `unattributed`
remainder (~20 ms). (d) Anything below case granularity — although the harness
does also print the **30 slowest individual cases**, which is how the perf-lab
finding below was found.

### 6.2 The slowest 20 (median of three runs, at `f476b63`, 4562 cases)

| # | spec | median ms | spread | load ms | cases | % of suite | cumulative |
|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | `tests/perf_lab.spec.luau` | **16,024** | 0.7 % | 23 | 56 | 37.6 % | 37.6 % |
| 2 | `tests/example_drift.spec.luau` | **4,182** | 0.9 % | 2 | 15 | 9.8 % | 47.4 % |
| 3 | `tests/reference/sipworks_spec.luau` | **3,222** | 2.1 % | 8 | 70 | 7.6 % | 54.9 % |
| 4 | `tests/extension_checker.spec.luau` | **2,701** | 1.7 % | 5 | 29 | 6.3 % | 61.3 % |
| 5 | `tests/reference/glade_spec.luau` | **1,979** | 2.3 % | 11 | 82 | 4.6 % | 65.9 % |
| 6 | `tests/reference/cartwheel_spec.luau` | **1,874** | 2.0 % | 11 | 62 | 4.4 % | 70.3 % |
| 7 | `tests/theme_drift.spec.luau` | **1,356** | 1.1 % | 1 | 8 | 3.2 % | 73.5 % |
| 8 | `tests/overflow_sweep.spec.luau` | **1,036** | 0.4 % | 181 | 39 | 2.4 % | 75.9 % |
| 9 | `tests/virtual_list_row_actions.spec.luau` | **999** | 0.3 % | 13 | 57 | 2.3 % | 78.2 % |
| 10 | `tests/reference/foyer_spec.luau` | **978** | 2.0 % | 5 | 24 | 2.3 % | 80.5 % |
| 11 | `tests/row_actions_scenario.spec.luau` | **695** | 2.3 % | 4 | 29 | 1.6 % | 82.2 % |
| 12 | `tests/sponsor_scenarios.spec.luau` | **667** | 1.6 % | 9 | 83 | 1.6 % | 83.7 % |
| 13 | `tests/instance_recycling.spec.luau` | **602** | 2.2 % | 2 | 8 | 1.4 % | 85.1 % |
| 14 | `tests/table.spec.luau` | **432** | 0.5 % | 19 | 111 | 1.0 % | 86.2 % |
| 15 | `tests/gallery_theme_picker.spec.luau` | **414** | 3.0 % | 10 | 41 | 1.0 % | 87.1 % |
| 16 | `tests/theme_matrix_audit.spec.luau` | **363** | 2.2 % | 358 | 14 | 0.9 % | 88.0 % |
| 17 | `tests/theme_docs.spec.luau` | **343** | 2.5 % | 4 | 33 | 0.8 % | 88.8 % |
| 18 | `tests/reference/wardrobe_spec.luau` | **326** | 3.1 % | 2 | 13 | 0.8 % | 89.5 % |
| 19 | `tests/examples_gallery.spec.luau` | **313** | 1.6 % | 22 | 91 | 0.7 % | 90.3 % |
| 20 | `tests/row_actions_input.spec.luau` | **282** | 3.5 % | 17 | 79 | 0.7 % | 90.9 % |

**The remaining 158 files are 3.87 s together — 9.1 %.** The suite is not slow
in general; it is slow in twenty places, and mostly in four.

The published run of the harness is **`artifacts/spec-timings.json.tsv`** (the
`.json` beside it is regenerable and falls under the `artifacts/**/*.json`
ignore), re-measured after the tier landed: 179 specs, 4569 cases,
`green: true`. Its wall
(44.4 s) sits in session B's slower band; the *ranking* is unchanged from the
table above, `tier.spec` itself costs **4.9 ms**, and the only movement inside the
top 20 is `theme_matrix_audit` and `theme_docs` swapping places.

Three facts from the same run decide everything after this:

1. **Three cases are 13.7 s — 32 % of the whole suite.** All in `perf_lab.spec`:
   *"the identity workload walks its whole collection cleanly at every phone
   width"* (7.14 s), *"Run all sweeps every workload and ONE failure does not end
   the sweep"* (3.34 s), *"Run all ends by saying how to take the dump"* (3.23 s).
2. **`example_drift`'s 15 cases re-lint the whole tutorial tree each** —
   ~160 ms per scan, and the negative controls scan once per injection, so one
   case costs 951 ms. `extension_checker` (2.70 s) and `theme_drift` (1.36 s) are
   the same shape over `src/` and `docs/`.
3. **Total file-load across all 178 files is 1.49 s — 3.5 %**, and 707 ms of
   that is three files (`theme_matrix_audit` 358 ms and `overflow_sweep` 181 ms
   of *fixture*, `smoke` 169 ms of *library load*). Every other spec file costs
   1–22 ms to load. **File count is not the cost.** That number is the whole
   consolidation argument, and it is measured, not assumed.

### 6.3 Tier — `./run-tests.sh --fast`, measured at 19 %

**The gate default is unchanged**: `./run-tests.sh` with no arguments runs
`tests/run.luau`, every file, and that is the only thing that may be called
green. `tools/test.sh` still calls exactly that.

The fast tier is **not a second list**. `tests/lib/tiers.luau` parses the require
list out of `tests/run.luau` and subtracts eleven named exclusions;
`tests/run_fast.luau` requires what is left, in the same order. A spec added to
`run.luau` joins the fast tier by existing.

| | full suite | fast tier |
|---|---|---|
| command | `./run-tests.sh` | `./run-tests.sh --fast` |
| spec files | 179 | **168** |
| cases | 4569 | **4163** |
| wall, session A (6 / 3 runs) | 42.38–43.35 s | **8.12 / 8.18 / 8.19 s** → **19.1 %** |
| wall, session B (3 / 3 runs) | 43.71 / 44.31 / 45.98 s | **8.62 / 8.65 / 8.84 s** → **19.5 %** |

Two sessions, because the second one drifted ~4 % slower *in both arms* — which
is the reason a share must be computed against a **contemporaneous** full run and
not against a remembered constant. The ratio held at 19–20 % across that drift.
(The closing banner does compare against the recorded 42.7 s, deliberately: when
the machine is slow it over-states the share and warns early, which is the safe
direction for a budget.)

The eleven exclusions are the measured-costliest files and nothing else —
34.3 s of the 42.7 s — and each is either a **workload** (`perf_lab`,
`overflow_sweep`, `instance_recycling`, the five reference proofs) or a **source
scanner** (`example_drift`, `extension_checker`, `theme_drift`). Each carries its
measured cost and a written reason in `tiers.SLOW`. Nothing is deleted, skipped
or weakened: all eleven run in full on `./run-tests.sh`.

**A fast tier mistaken for the suite is worse than no fast tier**, so it is loud
and it is refused where it matters:

- the runner prints a `FACET-FAST-TIER` banner **before and after** the run,
  naming the file count and repeating that the gate runs `./run-tests.sh`;
- the closing banner prints its own share of the recorded 42.7 s baseline and
  **reddens over 25 %**, so the tier's own budget is self-policing;
- **`tools/test.sh` FAILs outright** on a transcript containing that marker
  ("fast tier transcript — tools/test.sh gates on the FULL suite only"), so the
  fast tier cannot become `artifacts/test.json`;
- `./run-tests.sh <anything else>` exits 2 rather than guessing.

Seven guards in `tests/tier.spec.luau` (in the gate suite) hold that structure,
and every one was proved to bite — see 6.5.

### 6.4 Consolidate — audited, and DECLINED, with the numbers

**No spec was merged, parameterised or deleted.** The audit says the prize does
not exist:

- **Merging files can only recover file-load time, and that is 1.49 s total
  (3.5 %)** — of which 707 ms belongs to three fixtures that a merge would still
  have to build. Merging *every* spec file in the suite into one would save
  under 0.8 s (1.8 %), because the case bodies still run either way.
- **The named candidates are small or not duplicates.** The
  matrix-expansion class (`overflow_sweep`, `theme_matrix_audit`, `matrix_rows`,
  `large_text_matrix`, `large_text_layout`, `large_text_hot_swap`, `adaptive`) is
  1.63 s / 3.8 % *in total*, and 1.04 s of it is `overflow_sweep` — the
  always-on device-bug guard added on 2026-08-12, which nothing else duplicates
  (`overflow_sweep` asks *does anything overflow its box*, `theme_matrix_audit`
  asks *does any chrome paint on a neighbour, any value display solve to zero
  area, any text go unfit*; the first cites the second as the source of its
  viewport list). The near-duplicate layout family (`layout`, `layout_v1`,
  `layout_vocabulary`, `incremental_layout`, `grid_measure_arrange`,
  `container_relative_frame`, `container_relative_incremental`,
  `placement_audit`, `stack_distribution`, `grid_row`) is **189 ms — 0.44 % —
  with 42 ms of load between them**. They are three historical layers
  (UI-LAYOUT-001 spike, UI-LAYOUT-002 v1 completion, A-LV1..A-LV4 vocabulary)
  over one solver: merging them is a rename that saves nothing.
- **No duplicated coverage was found to remove.** Two searches: (i) exact
  case-name collisions across files — 19 names, every one a per-fixture
  lifecycle proof over a *different* subject (five reference apps each prove
  "mounts and renders headlessly with no runtime error"; dropping four would
  drop four apps' proofs); (ii) clustering every spec file by its `src/`
  dependency set. The broad clusters are an artifact of the method (16 specs
  "require the library root" and share nothing else); the tight ones are pairs —
  `paradigm_popup`/`popup_button`, `paradigm_textinput`/`text_input`,
  `navigation_groups`/`traversal_order`, `theme_assets`/`theme_variants` — and
  every pair is an input-paradigm spec beside a control spec, or two halves of a
  theme model, asserting different things. Each is single-digit milliseconds.

So consolidation's ceiling is ~2 % of runtime, paid for with the one risk the
brief names — deleting redundancy that is not redundant. **Declined.** The tier
delivered 81 % off the inner loop without touching a single assertion.

**Where the real time is, for whoever takes it next** (a follow-up, deliberately
not taken here because it is optimisation of guarded code, not tiering):

1. `perf_lab.spec`, three cases, **13.7 s / 32 %**. The 7.14 s case walks a whole
   collection at *every* phone width; the two `Run all` cases each sweep all nine
   workloads. A shared mounted fixture, or narrowing the width set to the ones
   that discriminate, is worth ~10 s — but each change needs its own mutation
   proof that the workload still fails when the layout breaks.
2. The three source scanners, **8.2 s / 19 %**. Each case re-reads and re-lints
   the same tree; only the injection cases need a fresh scan. A memoised
   baseline scan (pure function of file contents) is worth ~5 s.

### 6.5 The tier guards, and every mutation that proved them

Nine mutations, each applied to the *guarded* code, run, and reverted; the
control (restored tree) is green. Every one reddened the named case:

| # | mutation | what reddened |
|---|---|---|
| M1 | the require-list parser drops the `.spec` suffix | *the full order is parsed from tests/run.luau and every entry is a real file* (+3 more) |
| M2 | the parser stops descending into `reference/` | *EVERY exclusion names a spec the suite actually runs* (+2 more) |
| M3 | an exclusion renamed to `theme_driftXX.spec` | *EVERY exclusion names a spec the suite actually runs*, *…strict subset…* |
| M4 | `with_animation.spec` added to `tiers.SLOW` | *smoke, the core spine and every parity-round-2 area are IN the fast tier* |
| M5 | an exclusion's `ms` set to 0 | *every exclusion carries a measured cost and a reason* |
| M5b | (found, not injected) two exclusions written with a 26-character reason | the same case — it reddened on first run and the reasons were written properly |
| M6 | `tools/test.sh` greps for a marker the runner never prints | *the fast runner announces itself with the marker tools/test.sh refuses* |
| M7 | `tests/run_fast.luau` grows a literal `require("./smoke.spec")` | *the fast runner does not hand-list specs* |
| M8 | `tiers.fastOrder()` returns the list reversed | *the fast tier is a strict subset of the suite, in the same relative order* |
| M9 | `./run-tests.sh` with no arguments quietly execs the fast tier | `tools/test.sh` → `FAIL … fast tier transcript` |

**M9 caught a real defect in this phase's own work, of exactly the class the
gate-integrity sweep exists for.** The guard was first written as
`printf '%s' "$plain" | grep -q 'FACET-FAST-TIER'` — and `tools/test.sh` runs
under `set -o pipefail`. `grep -q` exits at the first match, `printf` takes
SIGPIPE, and the pipeline reports **141**, so the `if` fell through and
`tools/test.sh` **PASSED a fast-tier transcript as a suite result** (4163 cases,
`status: PASS`). It is now a bash `[[ == * ]]` match with no pipeline, and M9
FAILs as it must. Had this guard not been mutation-tested it would have shipped
as a check that could never fire.

### 6.6 Also found — one fixed, one reported

**Fixed.** `stylua --check src tests tools bench examples` — a check inside five
gate stages — was **already red at `f476b63`**, on two files from earlier phases
of this mission (`src/controls/progress_view.luau`,
`src/client/screen_chrome.luau`; stylua 2.5.2, no `.stylua.toml`).
Formatting-only, fixed here, both suites re-run after, and proved inert:
`check_flat_baseline` reports the **same 382 deltas** with the two edits present
and with them stashed.

**Reported, NOT fixed — `lune run tools/lune/check_flat_baseline` is red at
`f476b63`**, 382 uncharacterized deltas, none of them caused by anything in this
phase (identical count with this phase's only `src/` edits stashed). It compares
the stored `artifacts/rich-skinning-v2/rows/neutral-render-dump.json` against the
0.6.0 baseline, and the deltas are all example-fixture geometry:
`02_playlist_table` rows shifted ~25–42 px, and `06_tile_game`'s `Stats/Score`
and `Stats/Progress` nodes absent from the flat render at all three viewports.
That checker is named in the `swiftui-reference-app-validation` and
`example-quality-pass` prior-gates checks, so it blocks those gates as it stands.
Resolving it — regenerate the current dump and re-characterize, or find the
regression the disappeared Tile-game nodes may be — belongs to whoever owns this
mission's example changes, and it wants a look before anyone stamps a fresh
baseline over it. Named here rather than papered over.

### 6.7 Counts, floors and cadence

Suite **4562 → 4569** (`tests/tier.spec.luau`, +7). Nothing was removed, so **no
gate floor moves**: `tools/lune/gate_manifest.luau` compares with
`passed >= min_expected` and its highest floor is 4136 (`row-actions`). The fast
tier's 4163 can never be written into `artifacts/test.json` (M9).

**Cadence.** `./run-tests.sh --fast` between edits; `./run-tests.sh` before any
green claim, every commit, and every gate. Re-run `lune run tools/lune/time_specs`
when the closing banner says the tier is over budget.

---

## Rascal Rally exposure, measured up front

Grepped across every `*.luau` in `games/RascalRally/code` on 2026-08-12. Nothing
this mission adds has an existing call site, which means the rider is about
*proving* compatibility rather than migrating callers — and the precedent for
what that proof has to look like is
[`artifacts/row-actions/consumer-impact.md`](../../artifacts/row-actions/consumer-impact.md):
a per-change exposure table, a grep that earns the zero, and guard tests each
verified to **bite** against a deliberately-unconditional framework mutation.

| Round-2 surface | RR call sites | What the rider owes |
|---|---|---|
| `withAnimation`, `layoutPriority`, `GridRow`, `LazyVStack`, `containerRelativeFrame`, `sensoryFeedback`, `onPrimaryAction` | **0** each | a biting guard test that RR's screens animate/compress/select exactly as they do today |
| `newProgressView` | **1** — `src/client/FacetSponsor/ResultsScreen.luau:1471` | the determinate bar's behavior is byte-identical after the indeterminate mode lands |
| `UI.Grid` | **2** — `ResultsScreen.luau:2495, :2546` | GridRow's row mode must leave these flow-grid callers untouched; that is the phase's own constraint, pinned by an RR test |
| `newTable` / `newVirtualList` | `FacetRacerListScreen.luau`, `FacetSponsor/RacerList.luau` | already covered by the three row-actions guard tests; extended for `onPrimaryAction`, and — since §3.4.1 widened the auto Edit/Done toggle — for the pin that the racer list (single-select, no primary action, not reorderable, and built with **no `env`**, so an unwanted toggle would show on every session) grows **no** Edit button |

No game behavior changes without separate authorization.

## Standing obligations, every phase

TDD; full suite green with no skips; strict blueprint schema and exported Luau
types for every new public property; every new public API in a gallery scenario
that `examples_gallery.spec` runs headlessly; four-input proof and a
conformance-registry entry for new interactive behavior; a deliberate,
written-down reduced-motion decision for anything that moves; player-visible
text surviving ~1.4× pseudo-localization; and the Rascal Rally rider — inspect
affected callers and land compatibility evidence that bites, with no game
behavior change without separate authorization.

Phase end: fresh-context `facet-architecture-verifier` every phase, plus
`facet-reactive-runtime-verifier` for Phase 1. Milestone end:
`facet-phase-gate-verifier`, a fresh-context RED-TEAM `code-reviewer`, confirmed
findings fixed, and a report in the `GameStudio/STUDIO.md` mission format.
