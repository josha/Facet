# Wave REVEAL — fresh-context review

**VERDICT: CHANGES REQUESTED.** The mechanism is real, the proofs mostly bite, and both
suites reproduce. One release-blocking defect: **the framework now presents a modal that a
keyboard-only player cannot close** — reproduced, and it violates this repository's own
ADR-0013 sanctioned-dismissal rule. A second, related defect: the "Escape dismisses" claim
is false on this platform and is written into **`docs/reference/api.md` and the guide**,
which contradicts itself 163 lines earlier.

Reviewed against `task-reveal-brief.md` with the `reveal`→`expand` substitution (ca0bb6a).
Commits `66153fa ca0bb6a 0a3ebc7 d3e2514 8a2ab2f f7a3339 8940ce7 12476bf` on `d6c5b3c`,
plus RR `849d766` on `927b8047`. Note `2a24163` (RC-10 ledger) sits inside the wave range
and is **not** part of the wave; excluded from the breakage scan.

## Measurement discipline

Everything below was run in private exports built with `git archive` from the object
database (the live tree has an active writer and, at review time, uncommitted edits to
`src/blueprint.luau`, `src/class_contract.luau` and others — none of them mine). RR uses
the multi-repo shape (`<root>/GameStudio/ui/Facet` + `<root>/games/RascalRally/code`),
because RR requires Facet at `../../../../GameStudio/ui/Facet`. Nothing was written to
either live repo except this file.

| Suite | Base | Wave | Report claimed |
|---|---|---|---|
| Facet (private export) | **6467** | **6516** (+49) | 6516 / 6467 ✅ |
| RascalRally (private export) | **3417** | **3418** (+1) | 3418 / 3417 ✅ |

Both reproduced exactly.

---

## Per-contract-row verdicts

### 1. Resolution facts — **ADDRESSED** (with two classification gaps, below)

`activeForm` / `richestForm` / `formInteractive` / `expand` / `expandable` / `plate` all
ride `composition.dump`; `activeForm` is 0 on a dropped region so row 7 falls out by
arithmetic. `formInteractive` is derived from **`class_contract.isInteractive`**
(`focusRole == "focusable" or #actions > 0`) — the registry, not a name list; `ScrollView`
is correctly interactive on its `Scroll` action alone.

**Probe (deep nesting) — PASSES.** A `Button` five levels deep
(`VStack>HStack>ScrollView>VStack>ZStack>Button`) is seen: `interactive[2] = true`,
role `chevron`. A `Grip` five levels deep with `focusable = false` is also seen (the
registry answer is used, not the prop opt-out — deliberate and documented). The walk is
`formCarriesMeaning`, recursive over `node.children`, so a control nested at any depth in
the declared tree is found.

**Gap A (see findings): `UI.Foreign` is classified PASSIVE.** Probe: a compact form holding
a `UI.Foreign` reports `interactive[2] = false` and gets a **cover**. `class_contract`'s own
entry for `Foreign` says "the content's own engine input still works", and this repository
has measured that "a GuiButton SINKS input". So the framework lays a full-cover activation
surface over content that owns its own gestures — the exact collision the chevron exists to
prevent. The wave's stated principle ("the framework will not claim a form is passive when
it cannot see inside it", applied to `UI.When`/`ForEach`) is *not* applied to the one class
defined as content the framework has never seen. `UI.Stage` also reports cover, but Stage's
contract says it owns no input, so that one is correct.

**Gap B: `formInteractive` over-reports under a `UI.When` splice.** Probe (3 declared forms,
middle one gated off): with the gate OFF the standing form is a passive Box but the dump
reports `formInteractive = true`; with the gate ON it reports `false` for the *same* node.
This is the documented count-mismatch fallback (fall back to the affordance's role), and it
is the safe direction — but the caveat lives only in `solver.luau`'s comment, not in the
dump's docstring or `api.md`, where a consumer reads it.

### 2. Reveal (the plate) — **ADDRESSED**, with one row **NOT ADDRESSED** and one **CONTESTED-ACCEPTED**

- Content **by identity** (`forms[1]`), sized by the pure pass, `plate.sheet` fallback:
  proved (`EXPAND 2`, `EXPAND 8`). The report's own concern 2 stands — **no mounted
  end-to-end sheet proof exists**; I did not close it either.
- **Tap-away — ADDRESSED, driven for real.** My probe taps `pres.topScrimPath()` outside the
  panel: depth 2 → 1. A tap *inside* the panel does not dismiss. (The shipped spec only
  asserts the `outsideTapCancel` option.)
- **Gamepad B — ADDRESSED, driven for real** (`EXPAND 9`, and again in my probe).
- **Escape — NOT ADDRESSED, and cannot be.** My probe drives `deviceKey("Escape")` on an
  open plate: **depth stays 2**. `presenter.luau:2419` and ADR-0013 §Justified exceptions
  record that Escape is permanently bound to the Roblox CoreGui menu and the engine
  VirtualInput refuses it outright (verified live 2026-07-19, D1). `cancel.bind` binds
  `ButtonB` only. This is not a wave defect in *behaviour* — it is the platform truth — but
  the wave asserts the route as shipped in four places (below), so the row must be recorded
  as CONTESTED, not DONE.
- **Focus loss → modal — CONTESTED-ACCEPTED. The cited stranding measurement is real and I
  verified it.** It exists at `artifacts/navigation-and-menus/h4a-paint-probe.md:110` and is
  pinned by a *live, passing* spec (`tests/hud_paint_probe.spec.luau:580`, "a second base
  surface's control is in NEITHER traversal ring"). My own ring probe reproduces the shape:
  with the plate open the traversal ring contains **only** the plate's stop (or is empty when
  the plate has none), so a non-trapping plate would indeed strand its contents.
- **Epoch change — ADDRESSED.** `EXPAND 11` drives a real width-only viewport change (which
  correctly rules out the "climbed back to richest" branch) and asserts the plate closed and
  the screen underneath survived. Mutation M7 (disable the rect comparison) reddens 2.
- **Reduced motion — ADDRESSED.** No `transition` is declared and
  `presenter.luau:2586` (`transition = (opts and opts.transition) or nil`) applies no default,
  so there is no travel for anyone. Honest by construction rather than by a branch.
- **Teardown — ADDRESSED, and I verified it independently of the engine's own counter.**
  30 mounted open/close cycles: `paths` delta **0**, plate nodes left **0**, and
  `core:counters()` deltas **0** on every one of scopes / effects / memos / observers /
  signals / settles. Mutation M8 (drop the counter in `close`) reddens 2.

### 3. One gesture, one meaning — **ADDRESSED** (one unproven line; one gap from row 1)

- Conflict-mode specs run green (`EXPAND 5`, `EXPAND 6`, 47 cases in the file).
- **Chevron is genuinely RESERVED, not overlaid**, on the arrange side: mutation M1
  (`formW = innerW`) reddens. `EXPAND 7` asserts `form.x + form.w <= chevron.x` on a `fill`
  compact form, which is the only shape that can prove it.
- **The measure-side reservation is NOT proved.** Mutation M2 — delete
  `measure(ctx, child, availW - mw, availH)` and hand the form the full width when the ladder
  is choosing a rung — passes the **entire 6516-case suite**. The line whose comment says
  "the form was CHOSEN against the width it is now being handed" has no witness.
- **44px band — ADDRESSED, and stronger than the sweep asserts.** The sweep's own floor is
  `24`, not 44. I raised it to 44 and re-ran: **still 85 passed** across the whole matrix, so
  the shipped affordances do meet the Button contract's 44px hit floor everywhere. The check
  is loose; the geometry is not.
- **Focus stop AFTER the form's stops — ADDRESSED.** `EXPAND 10` measures ring indices;
  mutation M3 (insert the affordance first instead of last) reddens **12** cases.
- Mutation M4 (`role` pinned to `"cover"`, i.e. overloading a live control) reddens 3.
- Carry-over from row 1: the `UI.Foreign` cover is a real one-gesture-two-meanings hole.

### 4. Authoring surface — **ADDRESSED**, CONTESTED-2 accepted but should be tightened

`expand = "auto" | "none" | function`, validated at the schema boundary (`expandSpec`),
refused on a one-form region with a message that teaches the "don't collapse" answer,
unknown mode refused at the call site. `UI.Region{ reveal = … }` is refused as an unknown
key and `UI.Text{ reveal = "auto" }` still works — the rename is collision-free, verified
both directions.

CONTESTED-2 (`expand` defaults to `"none"` under `recover = "none"`) is a sound refinement,
**but it is only a default.** An author who writes `recover = "none", expand = "auto"`
explicitly is accepted in silence, and that pair produces the row-5 edge below. The wave
already knows the combination is contradictory; it should be a **refusal**, not a default.

### 5. The census stays one and truthful — **ADDRESSED**, with one edge

Joined once, on the same dump, by the path both halves are keyed on: dropped zones keep
their content inline, simplified zones get a `— Simplified, open to expand` row that calls
`presenter.expand(path)` and reaches the region's own contribution by longest-prefix
dispatch. Both reversibility cases now run **through the real tap path** and read the task
panel's names/rewards/three bars off `/Expand:Tasks` — that is a genuine end-to-end proof,
not an assertion.

**Edge (LOW):** the "nothing is hidden" line prints when `unshown` is empty, and
`unshown` excludes `recover = "none"`. Probe E3: a region with `recover = "none",
expand = "auto"` resolves to `activeForm = 2, expandable = true, #unshown = 0` — so the
census would print "Nothing is hidden — every zone is showing everything it has" while a
zone stands stepped down with a live affordance on it. Contract row 5 says the line prints
"only when there are neither drops nor step-downs". Unreachable without the self-
contradicting declaration in row 4; closed by the same one-line refusal.

### 6. Key information stays in the collapse — **ADDRESSED**

Written twice and in the right places: `docs/guide/01-concepts.md` §"Adapting without dead
ends", beside the mechanism, and `docs/extending/new-control.md` step 3, where an author
designing a compact representation is standing. Both state the rule the same way (the
minimum form carries the essential value; the expand is for the rest; a player must know
there is something to ask for). Documentation row, correctly discharged.

### 7. No reveal at richest; drops stay sheet-only; haptics standard — **ADDRESSED**

`activeForm = 0` on a dropped region makes `expandable` false by arithmetic rather than by
a rule anyone must remember (`EXPAND 1`). At the richest form the affordance takes a zero
rect and the hidden mark (`EXPAND 7`), which is the existing mechanism losing forms already
use. The affordance is an ordinary `UI.Button`, so press/release haptics ride the standard
bus with no special-casing anywhere in the diff.

### The extended sweep's dead-end guarantee — **ADDRESSED**

Re-ran clean: **85 passed**, `deadEndViolations` reports zero across the matrix.

The three-probe control is genuine, and I checked it for the way a zero-report control goes
vacuous: probe (2) mutates the *live* resolution table (`stepped.expandable = false`) and
asserts a report, which can only pass if the mutation persists across the next
`compositionAt` call — so probe (3) (`stepped.expand = "none"` → silent) is discriminating
one field, not observing a rebuilt dump. Not vacuous.

**Broken on purpose:** `markStanding = false` in the solver's region branch (a planted
dead end — the resolution still claims a route, the affordance never stands). Result:
**6 failed / 79 passed**, reddening five real viewports plus the control. The guarantee
watches the matrix, not itself.

### RascalRally lockstep — **ADDRESSED**

- RR is a **single** composition consumer: `grep` finds `UI.Region` in exactly one file
  (`src/client/FacetSponsor/ResultsScreen.luau`), reached through one `region()` helper at
  line 2827 with **22** call sites feeding **both** `UI.Composition` builders in
  `ResultsScreen.build`. No other RR file constructs a Facet composition or region; nothing
  else silently gained a surface.
- The decline is real (`expand = "none"` defaulted on every multi-form region) and the
  positive control in the new rider is the part that keeps it honest.
- **Mutation, run:** removing the opt-out from `region()` reddens **2** — the new REVEAL
  rider *and* the pre-existing S16.2 declaration contract ("TWELVE ranked regions…", which
  still reads `forms = #r.children`). The report's claim is exactly reproduced.
- The wave's D7.2 relaxation does **not** loosen RR: because RR opts out, the
  `recover = "self"` focusable requirement still fires there exactly as before.

### `ca0bb6a`'s sweep of `adapt-audit/matrix.md` — **attribution-only, confirmed**

844 insertions / **0** deletions; the file was *added* in that commit and its content is the
concurrent auditor's adaptation matrix, unrelated to the wave (its only `reveal`/`expand`
hits are about `UI.Text{ reveal }` and 44px hit expanders). No functional impact; the
disclosure in the report is accurate. Residual risk is only that the concurrent agent will
find its own file already committed under someone else's authorship.

---

## New breakage introduced by the wave diffs

Scan restricted to the wave commits. Counts by severity:

| Severity | Count |
|---|---|
| HIGH | 1 |
| MEDIUM | 2 |
| LOW | 3 |
| Proof gaps (no behaviour change) | 3 |

### HIGH-1 — a keyboard-only player is trapped inside the expand plate

Reproduced end to end. Screen with a passive stepped-down region; focus the affordance,
press Return (opens, depth 2), then:

```
after Return:  depth=2  focused=nil
stops reachable while the plate is open: []
after Return again: depth=2
after Escape:       depth=2
VERDICT keyboard-only exit exists?  false
```

The plate is modal with a transparent catching scrim. The only sanctioned exits are
**gamepad B** and a **pointer tap on the scrim**. Escape is impossible (ADR-0013 D1).
ADR-0013 names the keyboard route explicitly: *"a **focusable close affordance** inside the
modal … Screens that present a modal should always include a visible close affordance for
exactly this reason."* Until this wave, that obligation fell on the screen author. This wave
makes the **framework** the thing presenting the modal, and its content is the author's
form 1 — which in the director's own headline case (the clock) contains no focus stop at
all. Adding a focusable to form 1 does not help either: my probe shows the ring then
contains only that stop, and activating it is the author's action, not a dismissal.

CONTESTED-1 ("a plate that does not trap focus strands its own contents") is correct as far
as it goes, and the evidence behind it is real. But the trade was analysed in one direction
only: trapping focus fixes stranding of the *contents* and creates stranding of the
*player*. The fix is small and lives in this wave's own code — the plate is built by
`region_expand.new`, so it can put a framework close affordance (or a `cancelPolicy`-driven
stop) inside its own panel wrapper, the same `ExpandPanel` `VStack` that already exists in
`blueprint.luau`.

### MEDIUM-1 — "Escape dismisses" is written into the public API reference and the guide

Four shipped locations state a dismissal route that does not exist on this platform:

- `docs/reference/api.md:857` — *"Dismissal is the presented surface's: tap-away, Escape, gamepad B"*
- `docs/guide/01-concepts.md:419` — *"It closes on a tap outside, on Escape, on gamepad B"*
- `src/region_expand.luau:24` and `:144` — the module header and the present-options comment
- (plus `tests/region_expand.spec.luau:814` and the implementer report)

`docs/guide/01-concepts.md:256` — **the same file, 163 lines earlier** — states *"One
platform fact baked into the presenter: the **Escape key cannot be bound**"*. A reader who
reads the document in order is told both things.

### MEDIUM-2 — a `UI.Foreign` compact form gets a cover laid over live engine content

See Gap A under row 1. `interactive = false`, role `cover`, and the cover Button is the
region's last child so it is walked last and sits on top. Per this repository's own recorded
measurement a GuiButton sinks input, so the adopted instance's own gestures stop arriving.
No shipped consumer puts a `Foreign` in a region form today, so this is a boundary defect
rather than a live break — but it is a one-line fix in `formCarriesMeaning` (treat
`Foreign`, like `When`/`ForEach`, as content the framework cannot see into) and the
principle for that treatment is already written three lines above it.

### LOW-1 — an author-declared `expandTarget` silently eats a ladder rung

`expandTarget` is a public prop with no construction guard. Probe E1: a region with
`expand = "none"` whose **last form** is a Button carrying `expandTarget = { role = "cover" }`
is accepted; the solver then identifies that form as the affordance
(`kids[#kids].expandTarget ~= nil`), computes `formCount = 1`, and the ladder never steps
down — measured at 400×30, a 60px-tall rich form stays standing in a 30px box with
`activeForm = 1`. Documented as framework-only; not enforced.

### LOW-2 — the census can print "nothing is hidden" over a stepped-down region

Probe E3, described under row 5.

### LOW-3 — `formInteractive` in the dump can be wrong under a `UI.When` splice

Gap B under row 1. Diagnostic-only, conservative direction, but the caveat is not in the
dump's docstring or `api.md`.

### Proof gaps (no behaviour change, but nothing would catch a regression)

- **PG-1: the measure-side chevron reservation is unwitnessed.** M2 passes 6516/6516.
- **PG-2: the declared-vs-mounted count-mismatch fallback is unwitnessed.** M9 — replace the
  whole fallback with `interactive = record.interactive` — passes **6516/6516**. The
  `UI.When`-spliced-form case that both `blueprint.luau` and `solver.luau` spend their
  longest comments justifying has **no test**. I built one by hand and it behaves correctly
  (gate off → `activeForm = 2`, chevron 20×22 standing; gate on → `activeForm = 3`; roomy →
  `activeForm = 1`, 0×0 hidden), so this is a missing witness, not a defect.
- **PG-3: the sweep's thumb floor is 24px, not 44.** Raising it to 44 keeps the sweep green
  today, so the check is merely loose.

### Measured and cleared (recorded so it is not re-litigated)

- **Perf of the new per-solve plate measure: negligible.** It runs once per expandable
  region per solve and measures the *richest* form at a novel width (a memo miss). Counted
  on the HUD: 0 on an idle refresh, 9 per real re-solve at 320×640 with 3 expandable
  regions. A/B wall clock over 200 forced re-solves: **414.0 ms with, 410.9 ms without**
  (best of 3) — 0.8%, inside noise. The wave shipped no perf evidence; it did not need to.
- **The `text_audit` `region` layering relaxation is sound.** A region paints exactly one
  form and `isHidden` prunes the rest, so the only painted-sibling pair a region can produce
  is the framework's own cover over the form it discloses. It is broader than strictly
  necessary (it exempts the container kind rather than the specific pair), but there is no
  author-authored pair inside a region for the rule to have been protecting.
- **`tests/run.luau` is clean at HEAD.** The rename corruption the report discloses was fully
  reverted: the only diff against base is the `require` plus its comment block; the AUTO
  REVEAL note (lines 118-121) and the row-actions "static reveal" note (line 487) are intact.
- **Duplicate "reachable" definitions in `blueprint.luau` are deliberate.**
  `CONTENT_FOCUSABLE`/`containsFocusable` (a hardcoded three-class list, D7.2) sits fifteen
  lines above `formCarriesMeaning` (registry-driven). They answer different questions and
  disagree on `Grip{focusable=false}` and `ScrollView` by design. Worth one cross-reference
  comment; not a defect.

---

## Mutation ledger

Every mutation was applied to a pristine private export and reverted immediately after.

| # | Mutation | Target | Result |
|---|---|---|---|
| M1 | arrange stops reserving the chevron's width (`formW = innerW`) | `solver.luau` | **1 red** ✅ |
| M2 | measure stops reserving it (`availW` not `availW - mw`) | `solver.luau` | **0 red, full suite 6516** ❌ |
| M3 | affordance inserted FIRST instead of last | `blueprint.luau` | **12 red** ✅ |
| M4 | `role` pinned to `"cover"` (overload a live control) | `blueprint.luau` | **3 red** ✅ |
| M5 | `modal = false` on the plate | `region_expand.luau` | **3 red** ✅ |
| M6 | `outsideTapCancel = false` | `region_expand.luau` | **1 red** ✅ |
| M7 | epoch rect comparison disabled | `region_expand.luau` | **2 red** ✅ |
| M8 | `close()` stops counting teardowns | `region_expand.luau` | **2 red** ✅ |
| M9 | count-mismatch fallback deleted | `solver.luau` | **0 red, full suite 6516** ❌ |
| M10 | `markStanding = false` (planted dead end) | `solver.luau` | **6 red incl. 5 viewports** ✅ |
| M11 | sweep floor raised 24 → 44 | `overflow_sweep.spec` | still green (geometry holds) |
| M12 | RR `region()` opt-out removed | `ResultsScreen.luau` | **2 red** (new rider + S16.2) ✅ |

## Recommended before merge

1. **HIGH-1** — give the plate a keyboard exit. A framework-supplied close stop inside
   `ExpandPanel` (and inside the sheet fallback) is the smallest fix consistent with
   ADR-0013; a spec that Tabs to it and activates it is the witness.
2. **MEDIUM-1** — delete "Escape" from `api.md`, the guide, both `region_expand.luau`
   comments and the spec comment; replace with the ADR-0013 sanctioned list.
3. **MEDIUM-2** — add `Foreign` to `LAZY_CONTENT` in `blueprint.luau` (rename it to say what
   it means: content the framework cannot see into).
4. **Row 4/5 edge** — refuse `expand = "auto"` under `recover = "none"` rather than
   defaulting around it; that closes LOW-2 at the same time.
5. **PG-1 / PG-2** — one case each: a ladder whose rung choice turns on the chevron's width,
   and a `UI.When`-spliced middle form. Both are ~20 lines; the second already exists as my
   throwaway probe.
6. Consider raising the sweep's thumb floor from 24 to 44 (PG-3) — it is green there today.

The report's own five concerns are all accurate and none of them was overstated. Concern 2
(no mounted sheet proof) and concern 4 (the chevron's glyph is a device judgement) remain
open and belong in the controller's batched Studio pass along with the touch tap on the
cover, real pad A/B on the chevron, and — now — a keyboard-only pass on the plate.

---

# Review — DIR3: "the transient was under the screen it was opened over, and the pad had no way in" (`48b6e7b`)

Fresh-context scoped review, 2026-08-21. Reviewed by its own diff (`git show 48b6e7b`),
not by HEAD (HEAD is `3ad40b0`, one commit later). All measurement in two private
`git archive` exports — `48b6e7b` and its parent `130dcae` — never in the working tree,
one lune process at a time.

**Verdict: spec ✅ (both director items implemented literally). Quality ⚠️ — merge blocked
on MAJOR-1.** 3 MAJOR, 7 MINOR. The z-order mechanism is real, measured, and correctly
fixed for the showcase; the two shipped guards do bite for the things they were mutated
against. What the round did not do is check the two new bindings against the framework's
own key map, and the compensating fix makes the framework hazard it reports arrive twice
as fast.

## What reproduces

| Claim | Measured | Result |
|---|---|---|
| Suite tail 6864 | `./run-tests.sh` in the `48b6e7b` export | **6864 passed, exit 0** ✅ |
| Root cause: re-present climbs past a live transient | new `gallery_chrome (10)` run against the **parent** | `expected panel 10400 over demo 11000: false` ✅ exactly the reported numbers |
| Mutation: opaque `surface = "base"` on the anchored LAYER (`anchored.luau` `LAYER_ID`) | `transient_over_live.spec` | **2 failed, 3 passed** ✅ as claimed |
| Mutation: drop the `watchRaise` registration | `gallery_chrome.spec` | **2 failed** ✅ as claimed |
| Mutation: drop `action.bind({ keyCode = SECTION_GAMEPAD[kind] })` | `gallery_chrome.spec` | **3 failed** ✅ as claimed |
| `stylua --check` on all four touched sources | clean | ✅ |
| No file inside the source-cap band touched | diff is `examples/` + `tests/` only | ✅ |
| Re-entrancy: choose a demo from inside the open panel | probe | panel closes, `core:lastError()` nil ✅ |
| `scope:own(unsubscribe)` releases | `scope_impl.luau:61` accepts a function | ✅ |

Everything the report claimed as measured, measured.

## MAJOR-1 — `ButtonL1`/`ButtonR1` are the FRAMEWORK's Adjust keys, and the showcase now takes them

`presenter.luau:2292-2293` binds `ButtonL1`/`ButtonR1` to **Adjust** on any surface that
declares `onAdjust`, and `:2394-2395` binds the same pair DYNAMICALLY whenever the focused
node is a declared `adjustTargets` member — slider, stepper, table column grip, tab strip,
level picker, rating. Six shipped spec files drive it (`paradigm_input_axis`,
`paradigm_table`, `rating`, `playlist_columns`, `level_picker`, `tab_view_scenario`), and
four demos in `demo_picker.DEMOS` contain such a control (`tab-view`, `table-virtualized`,
`level-picker`, `all-controls`).

The commit's justification is therefore false where it is load-bearing:

> `showcase_chrome.luau:136` — "bound on the same non-sinking context (they claim two
> buttons nothing else in the place binds)"

**Measured, same probe, both exports** — the real `examples/gallery/scenarios/tab_view`
demo mounted inside the showcase harness at 320x640, focus on the page tab strip
(`.../TopBand/Strip/Indicator/Options/Opt1`), one `ButtonR1` press:

```
parent  130dcae : page pages/avatars -> pages/body  | chromeOpen false
commit  48b6e7b : page pages/avatars -> pages/avatars | chromeOpen true  kind settings
```

The shoulder no longer pages the tab view; it opens the chrome instead. On a surface that
declares `onAdjust` (the consumer opt-in path) it is worse — **both** fire on one press:

```
focus /Demo/D2 | adjustHits 1 | chromeOpen true | kind demos
```

i.e. the value under the player's ring moves AND the panel steals focus on top of it.
The context is non-sinking as claimed, so this is not a sink defect — it is a key-choice
defect, and the file's own doc header (which audits `ButtonA`, `ButtonB`, `ButtonX`,
`ButtonStart`, `ButtonSelect` for exactly this) simply does not mention the pair the
framework already owns.

The director asked for L1/R1 by name, so this is not a spec deviation — but it is the
implementer's job to report a collision this size rather than ship it. **`ButtonL2` and
`ButtonR2` appear nowhere in `src/`, `examples/` or `tests/`** and are the obvious
replacement; binding the pair only while the focused path is NOT an adjust target is the
alternative if the shoulder position is the point. Either way the fix needs a case that
presses the shoulder with an adjustable focused — the shipped `showcase()` harness mounts
a two-button stand-in with no adjustable in it, which is why the suite is green.

## MAJOR-2 — the fix doubles the climb rate of the very counter it compensates for

`displayLayer += 100` per present, reset only when the stack EMPTIES — and the showcase's
stack never empties, because the backdrop is permanent. The new `raisePanel` adds a
dismiss+present of the panel to every demo swap, so a swap now costs +200 instead of +100.
Measured, 100 swaps with the panel open, same probe in both exports:

```
parent  130dcae : n=6 demo=11000 | n=30 demo=13400 | n=60 demo=16400 | n=100 demo=20400
commit  48b6e7b : n=6 demo=11500 | n=30 demo=16300 | n=60 demo=22300 | n=100 demo=30300
                        (panel tracks +100 above the demo throughout)
```

`SURFACE_LAYER.toast` is 20000 and `dragProxy` is 30000. **At `48b6e7b` the base band
crosses the toast band at roughly 48 swaps and the drag-proxy band at roughly 98** — where
the parent needed ~96 and ~196. A player who swaps demos for a few minutes with the panel
open gets demos painting over every toast, then over the drag proxy, then (~148) over
modals. The new spec checks 6 swaps, so nothing sees it.

This is the hazard the report's Concern 1 describes, and the report is right that it lives
in `presenter.luau`. What the report does not say is that the compensating fix makes it
arrive twice as fast, which changes the disposition from "known framework debt" to
"regression in this commit's own surface".

## MAJOR-3 — the standing-rule guard is green on the defect it was commissioned by

`tests/transient_over_live.spec.luau`, copied verbatim into the **parent** export and run
there: **5 passed**. It would not have caught the photographed defect, before or after.

That is not fatal by itself — a rule may guard a neighbouring family — but two of its own
claims do not hold:

* **Case 3 of 4 is inert.** `opaqueCovers` gates on the module-level constant
  `VIEWPORT = {w=390, h=844}` (`rect.w >= VIEWPORT.w*0.9 and rect.h >= VIEWPORT.h*0.9`)
  while the expand-plate case builds its world at **390x40**. `rect.h >= 759` can never be
  true there. Proof: the `surface = "base"` mutation on `anchored.luau`'s `LAYER_ID`
  reddens cases 1 and 2 and leaves case 3 green — even though `region_expand.luau:244`
  presents through that same `presentAnchored` layer. The file's "one predicate over four
  constructs" is one predicate over three; case 3's only live assertion is
  `pres.depth() == 2`. Fix: derive the threshold from the world's own viewport.
* **The predicate cannot see the fills that are actually on screen.** It reads
  `props.surface` against six role names and skips exactly one root (`baseId`). The
  opaque full-viewport fills in the real showcase are APP-DECLARED: the backdrop
  (`surface = "base"`, presented first) and demo roots that declare it themselves —
  measured, `examples/gallery/scenarios/row_actions.luau:695` mounts `/MailActions` with
  `surface = "base"` at **1232x1005**. Any paint that is not one of the six role names
  (an image skin, an explicit colour) is invisible to it too. The spec is honest that it
  is model-side; it is not honest that it is *role-name*-side.

**Non-preference opaque fills that still pass the guard** (the CONTESTED question, second
half): (a) an app-declared opaque base screen, as above — the exact class in the
photograph; (b) a theme package's own scrim. On (b) the last case is titled *"every shipped
package, not just the neutral one"* and reads **only** the neutral `default_style` +
`light_style` model. Measured: all eight shipped packages emit their own `SCRIM_RULE`
through `sheet_model.buildPackage` —

```
classic_desktop 0.4 | compact_pointer 0.3 | fantasy_ornate 0.55 | fantasy_parchment 0.5
glossy_mobile 0.35 | glossy_touch 0.35 | pixel_quest 0.5 | scifi_hud 0.55
```

— and the test reads none of them. A package shipping `scrimOpacity = 0` is a fully opaque
scrim that keeps the suite green. Six lines fixes it (loop the package list; my
`probe_scrim2` is the loop).

## The CONTESTED call: the accessibility reasoning is RIGHT

`backdropTransparency(base, preference) = clamp(base × clamp(preference,0,1))` with
`preference` = `GuiService.PreferredTransparency`, whose platform semantics are "reduce
transparency as it approaches 0" — 0 means the player has asked for an opaque backdrop.
Capping the product at some floor would be Facet overriding an accessibility preference
and would redden a shipped ADR-0035 spec. **Do not cap it.** `PREFERENCE_RULE_PROPS` is
correctly scoped to the one rule (`sheet_model.luau:129-132`), and the audit note beside it
explains why that list has exactly one entry. The implementer's refusal is the right call
and the escalation to the director is the right disposition.

The report's own aside — that at `PreferredTransparency = 0` any modal scrim composes to a
fully opaque full-screen fill "which looks exactly like what the director photographed" —
is a live alternative root cause that this round did not rule out, and it interacts with
MINOR-4 below.

## MINOR-4 — the causal story is mis-attributed, so "does it cover the photograph?" is unproven

The commit says: *"what shows through is the backdrop — a full-viewport `surface = "base"`
fill, which is precisely the flat opaque rectangle in the screenshot."* Measured at the
parent with a real demo whose root declares that surface:

```
panelZ=10400  demoZ=11000  demoAbove=true
demo  /MailActions   surface=base  1232x1005
panel /ShowcasePanel surface=nil   1232x1005
backdrop 10100
```

The backdrop is at 10100, **below both**, and cannot show through anything. The fill on top
is the DEMO's own base surface, and because it is above the panel the mechanism predicts
*the panel is covered*, not *the panel stands over a flat fill*. The director's description
(picker visible, screen behind it flat opaque, demo gone) is not the composite this
mechanism produces. After the fix the ordering inverts as intended —

```
48b6e7b: panelZ=11600 demoZ=11500 demoAbove=false
```

— so the fix is correct for the mechanism it names. Whether that mechanism is the
photograph is asserted, never demonstrated. Two candidates were left standing: the
`PreferredTransparency = 0` scrim (the report's own note), and a demo that fails to mount
(`demo_picker.luau:621-628` — "the previous demo has already been dismissed, so returning
here left a blank screen"), which produces *exactly* "the mounted demo gone, flat opaque
backdrop" with no z-order involved. The device packet should photograph the fixed build
before this item is called closed.

## Remaining MINOR findings

1. **Stale claim in the source.** `showcase_chrome.luau:536-539` still reads "it binds two
   keys nothing else in the place binds" — it is four keys now, and one pair is bound by
   the framework (MAJOR-1).
2. **`pcall(listener)` swallows silently.** `demo_picker.luau:803` runs each raise listener
   under `pcall` and drops the error; the module takes a `warn` option and uses it for the
   mount failure two screens up. `opts.onRaise` is called UNPROTECTED on the line above, so
   the host callback and the list have opposite failure semantics for no stated reason.
3. **`sectionActions` is dead.** `showcase_chrome.luau:554` builds the table and nothing
   reads it; the actions are released by `toggleContext.destroy()` like the toggle action.
4. **`raisePanel` resets focus.** It re-presents with `initialFocus = "first"`, so a demo
   change under an open panel puts the ring back on the panel's first row. Spec (10) case 2
   asserts only that focus is *inside* the panel, so neither behaviour is pinned. Reachable
   today only through `showNext` (the scripted API) and a settings re-apply, hence MINOR.
5. **The "framework RULE" is documentation-free.** The director asked for a rule; the diff
   touches no `docs/`, no ADR, no `api.md` line. A consumer building a menu has no way to
   find it. A rule that exists only inside one spec file is a test, not a rule.
6. **Guard skips exactly one root.** `opaqueCovers(w, baseId)` assumes one base screen. In
   any app with two live base surfaces (the showcase has exactly that: backdrop + demo) the
   predicate would report the second one as a violation. Harmless in the four fixtures,
   wrong as a reusable predicate.
7. **Pre-existing, free give-back.** `presenter.luau:3531-3553` carries the same twelve-line
   `REDTEAM FIX (item 3, MAJOR...)` comment block **twice, verbatim** — ~740 characters on a
   file sitting 3,361 characters from the 200,000 write cap.

## The presenter-hazard disposition: CORRECT

`docs/handoff/SOURCE_CAP_LEDGER.md` row for `src/present/presenter.luau` (196,647; export
measures 196,639) says the extraction is **OWED**, the 195,000 trigger has already fired,
and "the next change of any size to this file is PRECEDED by the extraction, not
accompanied by it". Reporting rather than editing is exactly what that lock requires, and
the round was right not to reach for it. Two riders:

* Concern 1 should be filed at the severity MAJOR-2 gives it, not as background debt.
* When the fix does land, the framework-side shape worth considering is the one the rule
  actually needs: an explicit `presenter.raise(handle)` (which the showcase's
  "re-present rather than teach the presenter a raise operation" comment concedes is the
  missing operation), or re-asserting the band on every present so present-order z means
  "presented later" rather than "presented later and never re-presented". Both are inside
  `makeHandle`'s dismissal region, i.e. after the extraction.

## Recommended before merge

1. **MAJOR-1** — move the two chips off `ButtonL1`/`ButtonR1` (`ButtonL2`/`ButtonR2` are
   unbound everywhere in the repo), or gate the pair on the focused path not being an adjust
   target. Add a `gallery_chrome` case that presses the shoulder with an adjustable focused —
   the real `tab_view` scenario mounted as the demo is a ten-line harness change and it
   reddens today.
2. **MAJOR-2** — either cap the re-present (raise only when the panel is actually below the
   demo: compare `rootDisplayOrder` before dismissing) or take the presenter fix after the
   owed extraction. Extend spec (10) from 6 swaps to a count that would cross the toast band.
3. **MAJOR-3** — derive `opaqueCovers`' size threshold from the world's viewport so case 3
   can fail; loop the eight shipped packages in the scrim case so its title becomes true.
4. **MINOR-4** — photograph the fixed build on device before closing item 1, and rule the
   `PreferredTransparency = 0` scrim and the failed-mount path in or out.
5. MINOR 1-3 and 5-7 are one-line cleanups; 5 (a documented rule) is the one worth a
   separate decision, since it is what the director actually asked for.
