# Nested instance trees — round brief

**Status:** queued. Run **after** SwiftUI-parity round 3 closes.
**Decided by the user, 2026-08-15:** *"switching to nested should come before
release."* That is settled. This round executes it; it does not re-open it.

---

## The binding statement

> Move LuauUI from a flat instance tree to a nested one — earning the
> compositing the flat tree cannot express and the arrange cost it cannot
> avoid — in stages that each ship green, without regressing what flat bought
> us and without breaking the live consumer.

---

## Read these first, in this order

1. **`docs/adr/` — the nested-tree ADR** produced by round 3. It is the
   authority for this round: the decision, the measurements, the staged order,
   the ordering finding, and the implementation sketch. **If it recommends a
   shape, follow it. If you disagree with it, say so with a measurement before
   you deviate** — it was written with live captures and you should assume it
   knows something you have not re-derived.
2. `GameStudio/ENGINEERING.md`, and the root `CLAUDE.md` **"LuauUI and Rascal
   Rally move together"** clause — which binds this round hard, see the rider.
3. `docs/adr/ADR-0024` (declarative 3-D) as the voice and structure precedent
   for any new ADR this round needs.
4. `src/render/renderer.luau`, `src/render/layout_node.luau`,
   `src/render/authority.luau`, and the screen-target adapter
   (`src/client/screen_target.luau` and its `screen_*.luau` siblings).

---

## The eight standing rules (unchanged, they bind every task here)

1. **Roblox-native first** — verify against the live engine, never against
   memory. This round is *entirely* about engine behaviour, so this rule is
   doing more work here than it has in any previous round.
2. **A general mechanism, never a special case.**
3. **Performance is measured with the real instrument** (MicroProfiler) and
   **labelled by tier** — headless Lune is a regression signal only, Studio is
   the real engine, a physical device is the only device claim.
4. **Every gap ships its showcase demo**, registered in
   `examples/gallery/scenarios/init.luau` `ORDER` **and** `demo_picker.DEMOS`,
   and swept.
5. **Docs in plain language, with §16 citations.**
6. **Commit as you go.**
7. **Adapt deliberately** — if the plan is wrong, say so and re-plan; do not
   push through.
8. **Verify in Studio** wherever only a real adapter can show it.

---

## What is already known — do not re-derive, but do re-verify anything
## load-bearing before you build on it

**The two arguments for nesting.**

- **Compositing.** `CanvasGroup.GroupTransparency`, `ClipsDescendants`, and
  rotation/scale all act on **descendants**. A flat tree has none. Fading a
  panel by writing transparency per node is *not* group opacity — overlapping
  children double-darken. `withAnimation` interpolates `{x,y,w,h,o,s,r}` and
  today `r`/`s` do not carry to a container's contents.
- **Arrange cost — MEASURED, and the win is real and large.** A container move
  with 120 descendants costs **123 rect writes + 120 engine `Position`
  writes**, and incremental layout — the one optimisation already shipped —
  skips **zero** nodes, so it is *structurally defeated by the commonest layout
  event*. Engine harness: flat is **O(N)** (0.0145 / 0.0625 / 0.2556 ms at
  N = 50/200/800); nested is **O(1)** (0.00022 ms at **every** N).
  **63×–1157×**, against a widest A/A control spread of 9.88%.
  **The honest caveat, which the round must close:** that is **Luau-side
  only**. The engine still walks descendants in C++, and the frame-time
  instrument **saturated at 66.7 ms in every arm** (Studio throttle), so *total
  frame cost is unmeasured and owed*. **Getting a real end-to-end frame number
  — ideally on device — is a deliverable of this round, not an optional
  extra.**

**The ordering question — RESOLVED by ADR-0032, and not the way this brief
originally guessed. Both of the guesses below were wrong; they are recorded
here so nobody re-derives them.**

- **WRONG:** *"the ScreenGui uses `ZIndexBehavior.Global`."* It is
  **`Sibling`** — measured on all three live ScreenGuis and pinned at
  `screen_target.luau:909`. Under `Sibling` a nested child **cannot** escape
  its ancestor's z-slot (pixel-confirmed). And `Global` is not the fix: it is
  **disqualifying** for a separate reason, ADR-0009's "verifier F1",
  reconfirmed live — a child at `ZIndex = 20` beneath a parent at `50` renders
  **invisible**, and LuauUI pins every button icon at a fixed `ZIndex = 20`.
- **WRONG:** *"a `CanvasGroup` is an ordering boundary."* **Refuted at pixel
  level**, including at `GroupTransparency = 0.5` where the offscreen buffer is
  demonstrably real. Frame nesting and `CanvasGroup` nesting order
  **identically**. The two-tier "nest for structure, `CanvasGroup` only for
  opacity" design rested on a distinction that does not exist — do not rebuild
  it.

**The real answer:** overlays escape by being **separate surfaces on banded
`DisplayOrder`s**, not by `ZIndex`. That mechanism already ships — Sponsor runs
four concurrent surfaces in production today. So the ordering risk this brief
was most worried about is *already solved*, and the round does not need to
solve it again.

**And the mechanism for nesting already exists.** `hostFor(path)` is a
**longest-path-prefix match over a host registry**, not a tree walk — proven
from the live tree, where `.../Body/Settings/Heading` parents straight past
three path segments to a `ScrollingFrame`. So switching to nested is a
**registration policy**, not a renderer rewrite: the render seam still takes no
parent handle.

**What flat bought us, and must not be quietly given back.**

- **Elision** — measured worse than the −34% on record: **61 of 142
  GuiObjects (43%)** are elided on a 20-row list, and un-eliding everything
  costs **+75.3%**. ADR-0032 resolves this by registering **only move and
  composite boundaries** as hosts, never every container — unregistered
  containers stay invisible to parenting, so **elision survives untouched**.
  Hold to that. **Report the GuiObject count against the 43% baseline at every
  stage**; a silent regression here is the most likely way this round does net
  harm.
- **The instance pool — THE OPEN PROBLEM, and it gates the first build step.**
  `parkEligible` **refuses** any handle where `clipHosts[path] ~= nil`, so
  **nesting disables recycling on the hosted node.** The virtualised row is
  simultaneously the best move boundary *and* the exact case the pool exists
  for. ADR-0032 leaves this **unpriced** and explicitly declines to assume rows
  are the obvious first target. **Price it before choosing the first boundary
  to convert.** There is a recorded pool-corpse crash in this codebase's
  history — read it before touching the pool.
- **Path naming, the diagnostics, and the cross-surface overlap alarm**, all of
  which currently reason about a flat set.
- **Focus and input routing.** Note the measured platform fact: Roblox delivers
  input to the **topmost interactive object only**, and a `GuiButton` **sinks**
  it — an `Active` object behind a button gets nothing. Nesting changes what
  "behind" means. Re-verify the row-actions swipe and the table column-resize
  gestures specifically; both have already been broken once by an ordering
  change and both are touch-critical.
- **The authority manifest** — exactly **one writer per engine property per
  class**, because on this platform a **second writer is silent**: an explicit
  write defeats a StyleSheet rule and fires no signal, and reading a styled
  property returns your own last write. Settle whether an engine-computed
  inherited effect (group transparency, inherited transform) counts as a second
  writer on the properties LuauUI already claims. **If it does, that is a
  manifest change and it needs an ADR, not a patch.**
- **Roblox's own layout objects** (`UIListLayout`, `UIPadding`) become tempting
  the moment there are parents. LuauUI solves layout itself for reasons —
  restate them and confirm they still hold before adopting any of them.

---

## Deliverables

1. **The staged migration**, in the ADR's order, **green at every step**. No
   big-bang renderer rewrite. Each stage: tests red first, then the change,
   then the suite, then a commit.
2. **Group opacity that actually composites** — the thing the user asked for —
   with a capture proving overlapping children no longer double-darken, and a
   before/after screenshot pair.
3. **Container rotation and scale carrying to contents**, since `withAnimation`
   already claims `r` and `s`.
4. **The escape-the-boundary answer**, with its demo and test.
5. **The arrange measurement, before and after**, MicroProfiler, tiered, with
   the **A/A control spread stated before any delta**. This is the round's
   headline number and it must be honest — including if it is disappointing.

   **Performance profiling belongs to THIS round, by the user's instruction
   (2026-08-15), and is not a prerequisite for starting it.** Nesting changes
   the profile, so there is no value in profiling the flat tree first — the
   captures taken now would describe code this round deletes. Fold the
   profiling into the staged work: when a stage is ready to measure, hand the
   user a note naming **the exact workload, which button, and what the status
   line should read before they spend the dump** (same shape as the notes they
   have already used; a capture that lands on `arrange=0` is worthless and they
   should be told to stop rather than spend it).

   The ADR's numbers are **Luau-side only** — the engine still walks
   descendants in C++, and the frame instrument **saturated at 66.7 ms in every
   arm**. So the round's real headline is a number nobody has yet: **total
   end-to-end frame cost**, ideally on device.
6. **The GuiObject count** against the −34% elision baseline.
7. **A showcase demo** for the compositing capability, swept and registered in
   both places.
8. **Docs**: `docs/reference/` updated in plain language; the parity, Fusion,
   and React-Lua comparison docs all describe the flat tree and will need
   their claims re-checked.
9. **Any ADR** the round turns out to need (manifest change, ordering rule).

---

## The Rascal Rally rider — not optional

Per the root `CLAUDE.md`: **LuauUI and Rascal Rally move together.** Rascal
Rally consumes `GameStudio/ui/LuauUI/src` directly through both of its Rojo
projects, so a change to the rendered instance shape is exactly the kind of
change that must include the consumer work **in the same task**.

`games/RascalRally/code` **is its own git repo** — commit there separately.

**ADR-0032 already surveyed this and the news is good: Rascal Rally needs
NO source changes.** Zero raw-tree access, zero tests depending on parenting,
zero baselines that move; its suite live-ran green at **3248 / 0**. So the
rider here is *not* a migration — it is proof of compatibility:

- **A contract/integration test** proving the live consumer is current under
  nesting. This is the deliverable; do not skip it because nothing needed
  changing. The root `CLAUDE.md` is explicit that a compatible internal change
  still owes the game-side test or evidence that proves the consumer is current.
- **A Studio canary** on the affected game.
- Re-verify the survey rather than trusting it — it was taken before the
  migration existed. If a caller *does* turn out to read instance paths or walk
  the UI tree, that is a finding, and it changes the shape of this round.
- Run both projects' relevant tests.
- **Preserve game behaviour and flags** unless the user separately authorises a
  product change. Anything that reads instance paths or walks the UI tree is a
  prime suspect.
- The Sponsor cutover stands (authorised 2026-08-03): LuauUI is the production
  default; `UseLuauUISponsor = false` is the legacy rollback; the legacy Sponsor
  modules stay shipped and untouched.

**Baselines to hold:** LuauUI **~5438 passed / 0 failed**; Rascal Rally
**~3234 passed / 0 failed**. Both must be green at the end of every stage, not
only at the end of the round.

---

## Verification discipline — the traps this project has actually hit

- **Mutation-prove every new check.** Deliberately break it and watch a
  **named** case redden. A check that cannot be shown to bite proves nothing. A
  mutation that reddens nothing is a **null result worth reporting**, not
  something to hide — this project has published two.
- **Studio is connected** on **34873** (Showcase) and **34874** (Performance
  Lab). Before trusting any live result, **check the datamodel carries a string
  you committed minutes ago**. `require` is **cached per datamodel**, so reading
  the right source does **not** prove you ran it — clone-and-require is the
  recorded workaround.
- **Probe hygiene:** destroy anything you mount, verified absent in the same
  call. Transient UI destroys its own evidence — capture before it goes.
- **A dump is not a witness for its own behaviour.** Neither is a screenshot of
  a thing you asked to be true.
- **The `>= 200,000`-character `Script.Source` write cap** breaks live sync
  silently. `tools/check_source_size.py` must stay **PASS** with `KNOWN_OVER`
  **empty**. Nesting will move code between modules — watch it.
- **Touch is the blind spot.** Studio's device simulator has a broken pointer
  mapping (`GetMouseLocation()` freezes), and injected MCP input arrives as
  `UserInputType.Touch`, not `MouseButton1`, and does not drive `Activated`.
  The worst defect of the previous round was a list that could not be swiped
  **at all** on a phone and looked perfect on desktop. **Anything gesture-
  related in this round must be flagged for a physical-device pass** rather
  than claimed verified.

---

## Concurrency and staging — read this even if you are running alone

- `git diff --stat <path>` **immediately before every commit**.
  `git commit -- <path>` carries the **same** hazard as `git add <path>`: both
  take the path's *current working-tree content*, not your changes to it. **The
  shared file is the one to watch, not your own.**
- **NEVER** `git reset`, `git checkout .`, `git checkout <path>`,
  `git stash`, or `git add -A`.
- If you fan out to subagents, **partition by file and say so explicitly** in
  each brief — disjoint files are the only real isolation. Two agents in one
  file is a scheduling decision, not an accident to discover later. Verify the
  partition with `git status` rather than trusting an assertion about who is
  where; that assertion has been wrong before.

---

## How to run it

Suggested: **Opus orchestrating**, with **sonnet/opus** work subagents and
**haiku** for read-only exploration — matching the standing model-routing
preference. This round is architecture-heavy and the expensive mistakes are
judgement calls, not typing.

Fan out only where files are genuinely disjoint. The renderer, the adapter, and
the solver are the hot shared files in this round and will not partition
cleanly — expect the core migration to be **one agent working in stages**, with
parallelism reserved for the demos, the docs, the Rascal Rally rider, and the
measurement harness.
