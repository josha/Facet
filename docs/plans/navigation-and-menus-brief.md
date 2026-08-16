# Brief — Navigation & Transient Menus (LuauUI)

**Status:** binding brief for the round. Written 2026-08-16 against LuauUI `0.9.0`
(`src/init.luau:135`), commit `37e9dad`.

**Origin:** the game director surveyed the shipping Roblox mobile app and named four
constructs LuauUI must be able to express, then added three tasks of his own — the sweep
optimization (§2 D0), the HUD repair (§2 D7) and the playlist-table consolidation (§2 D8). Reference media is checked in beside this
file at `docs/plans/reference-media/2026-08-16-roblox-app-navigation/`:

| File | What it shows |
|---|---|
| `f1-avatar-editor.jpeg` | An auto-popped **callout** with an arrow tail ("Post Avatars to Marketplace" — a coach mark, *not* a tooltip; see §2 D3); a horizontal icon-only segmented pill (top) and a **vertical** two-button pill (left rail); a floating icon+label action menu opened from a rail button; an overflowing horizontal tab strip |
| `r1-popup-list.mov` + 3 frames | A bordered "Top Trending ⌄" trigger; tap opens an icon+label option list as a scrimmed bottom sheet; picking one re-titles and re-populates the page |
| `r2-top-tab-bar.mov` + 2 frames | A **top** tab bar (For you / Charts, underline indicator) living *inside* a screen that is itself a tab of the app-level bottom bar. Content swaps and shows its own loading state |
| `r3-segmented-control.mov` + 2 frames | The icon segmented pill: the selection chip **slides** to the tapped segment and the whole page content changes. Also a scrollable underline tab strip below it |
| `hud-a-landscape.jpeg`, `hud-b-portrait.jpeg`, `hud-c-urlbar-open.jpeg` | **Our own** Screen-anchored HUD showcase (`examples/gallery/scenarios/hud.luau`) at three offers, added 2026-08-16 — the D7 evidence. Landscape shows the full HUD; portrait and URL-bar-open show information vanishing with no way back |

The director's framing on r1 is the standing constraint for the whole round:
**"this doesn't have to literally work this way — the key thing is a pop-up menu that
works across platforms."** Copy the *capability*, not the iOS chrome. Every construct
here resolves its presentation from space and live input class the way
`popup_button.resolvePresentation` and `adaptive.navPlacement` already do. A device
name must not appear in any new source file.

---

## 1. What LuauUI has today — verified, not remembered

Every row below was read in source at `37e9dad`.

| Capability | State | Evidence |
|---|---|---|
| Node kinds | `AdaptiveStack Anchor Box Button Composition Divider ErrorBoundary Flag ForEach Foreign Grid GridRow Grip HStack Image Path Region Screen ScrollView Spacer Stage Text TextField Toggle VideoFrame ViewThatFits VStack When ZStack` | `src/blueprint_schema.luau` — **no** TabView, Menu, Popover, Tooltip or SegmentedControl |
| Tab **placement policy** | Shipped | `adaptive.navPlacement(facts) -> "bottomBar" \| "bottomBarCompact" \| "topBar" \| "sidebar"` (`src/layout/adaptive.luau:146`), exposed on `conditions()` (`:319`) |
| Tab **construct** | **Missing** | `docs/plans/parity-completeness-audit-2026-08-13.md:195` — "all five reference apps build the bar by hand — the policy shipped, the construct did not". Confirmed: `examples/reference/p3_sipworks/views/shell.luau:481` reads `navPlacement` and assembles the bar itself |
| Segmented picker | Partial | `src/controls/picker.luau` — `presentation = automatic \| segmented \| inline`. `Option = { value, label }` (**no icon**). Segmented is **x-axis only**: `axis` memo returns `"x"` for segmented, `"y"` otherwise, and `"y"` is the *inline row list*, not a vertical pill (`:147`). Selection is a **style tag** on a Button (`:134`) — a static fill, no moving indicator |
| Popup / dropdown | Partial | `src/controls/popup_button.luau` — `presentation = automatic \| menu \| inline \| sheet`, resolved from option count / size class / live touch (`:67`). Anchors with `UI.Anchor` at `topLeft`/`bottomLeft` (`:263`). `Option = { id, label }` (**no icon**). `value` is a `Signal<string>` — it is a **value picker, not an action menu** |
| `.contextMenu` | **Missing** | `docs/reference/swiftui-parity.md:957` — "No `contextMenu` construct exists in source at all… zero occurrences of `contextMenu` in `src/`" |
| `.popover` | Partial | `swiftui-parity.md:1707` — `newPopupButton` plus `presenter.syncPopupCatcher`'s tap-away catcher. Bound to that one control; no arbitrary content |
| Tooltip / `.help()` | **Missing** | `parity-completeness-audit-2026-08-13.md:194` — "the mechanism is close, the capability is absent". `presenter.disclosure()` (`src/present/presenter.luau:1194`) is the adjacent presenter-private surface. "tooltip" appears in `src/` only in comments |
| `UI.Anchor` | Insufficient for popovers | `docs/reference/api.md:602,277` — free positioning **inside a parent** by corner + offset. No source-view screen rect, no edge flip, no arrow tail |
| Sliding shared indicator | **Missing** | No `matchedGeometryEffect` analogue. Every `indicator` hit in `src/` is a *scroll* indicator (`blueprint.luau:200`, `presenter.luau:501`) |
| Presenter surfaces | `present` `presentModal` `presentCritical` `presentToast` `disclosure` `dismiss` `back` `refresh` `withAnimation` | `src/present/presenter.luau:3074-3879`. None takes a source rect |

**Net:** r1 is ~70% covered by `newPopupButton`. The other three are new constructs.

---

## 2. What to build

Nine deliverables. **D0 is tooling and goes first** — it removes ~3h44m of duplicated
suite time from every sweep the rest of the round will run. D1-D6 are new constructs, each
with a closed spec (constitution §4 / ARCH-1), registered, themed off existing tokens, and
reachable on every input class. D7 is a repair to shipped layout machinery plus the
showcase that exposed it. D8 is a showcase consolidation needing no framework change.

### D0 — Stop re-running the whole suite once per gate (do this FIRST)

Director task, 2026-08-16: *"when we do test sweeps, it re-runs the whole suite per gate.
that's inefficient. let's optimize this."* Correct, and the size of it is worth stating.

**Measured, not estimated** (2026-08-16, this machine):

| Fact | Number | How |
|---|---|---|
| One full suite run | **83.4 s** wall, 5618 passed | `/usr/bin/time -p ./run-tests.sh` |
| Gate checks that invoke the LuauUI suite | **161** | `run =` strings in `tools/lune/gate_manifest.luau` |
| …of which the capture-then-grep form | **144** | `out="$(./run-tests.sh 2>&1)"` |
| `grep -q` assertions riding those captures | **1074** | — |
| Gate checks that invoke the Rascal Rally suite | **39** | `cd ../../../games/RascalRally/code && ./run-tests.sh` |
| Suite time in one full 28-gate sweep | **161 x 83.4 s ≈ 3 h 44 min** | and every run produces a byte-identical transcript |

So a sweep spends the better part of four hours regenerating the same transcript 161
times in order to `grep` it for 1074 lines. **The suite is not the problem; running it
161 times is.** Nothing about the checks' meaning requires a fresh run — they all assert
against the same tree.

**The fix: run it once per sweep, cache the transcript, grep the cache.**
`tools/test.sh` is already the right home — it runs the suite, judges whether the
transcript is trustworthy (fast-tier refusal, truncation guard, exit code, pass/fail
counts) and writes `artifacts/test.json`. Extend that, do not build a second thing.

- Persist the **plain transcript** (ANSI already stripped) beside `artifacts/test.json`,
  with the suite's **exit code**, the **tier marker**, and a **tree fingerprint**.
- Add one small helper — `tools/suite_transcript.sh` — that prints a valid cached
  transcript on a fingerprint hit and otherwise runs the suite once and caches it.
- Rewrite the 144 checks from `out="$(./run-tests.sh 2>&1)"` to
  `out="$(tools/suite_transcript.sh)"`. Mechanical, and the greps are untouched.
- Do the same for the 39 Rascal Rally invocations in its own repo.

**Five correctness guards, every one of them drawn from this repo's own scar tissue.**
A cache is exactly the shape that turns a real check into one that cannot fail, so these
are the deliverable, not caveats on it:

1. **The exit code must ride with the transcript.** `gate_manifest.luau:25-29` documents
   FORM A vs FORM B precisely because a pipeline loses `run-tests.sh`'s status. A helper
   that prints a cached transcript and exits 0 over a **red** suite converts 144 checks
   into decoration in one commit. The helper exits non-zero for a red, truncated, absent
   or fast-tier cache, so the existing `&&` chains keep working unchanged.
2. **Fingerprint on CONTENT, not time.** Hash `src/`, `tests/`, `examples/` and the
   toolchain pins. A clock- or session-keyed cache outliving an edit is the
   "reads two checked-in files and executes nothing" shape that `tools/prior_gates.sh`
   exists to have removed (PG-2, ledger C-08). Any edit busts it or the sweep proves
   nothing.
3. **Refuse the fast tier, exactly as today.** `run-tests.sh --fast` skips eleven files
   and prints `LUAUUI-FAST-TIER`; `tools/test.sh` already refuses that transcript, and
   the guard has already been broken once by a `printf | grep -q` pipeline returning 141
   under `pipefail` (mutation M9, 2026-08-13). Reuse the bash-match form, do not rewrite it.
4. **Standalone stays honest.** `tools/gate.sh <one-gate>` outside a sweep must still run
   the suite on a miss. The cache is hit-or-run, never trust-the-file.
5. **Prove the invalidation BITES.** Mutate a spec, confirm the fingerprint changes and
   the sweep re-runs; mutate the transcript on disk, confirm the checks go red. The
   gate-integrity sweep's standing rule is that a check is worthless until a mutation has
   been seen to fail it — and a cache that never invalidates is the purest example of one.

**Why first.** Every deliverable after this one runs gates, and D1-D8 will run many. Land
D0 and the rest of the round costs minutes per sweep instead of hours; land it last and
the round has already paid the tax it was meant to remove.

**Not in scope:** making the suite itself faster. 83 s for 5618 specs is fine. The
`--fast` tier already exists for the inner loop, and the settle-between-gates policy in
`tools/prior_gates.sh` stays exactly as it is — it exists because bench checks measure the
previous gate's tail, which caching does not change.

### D1 — Anchored surface seam (the substrate)

A presenter surface positioned against a **source view's screen rect**, not a parent
corner.

- New present option: an attachment describing the source (a mounted path or a rect),
  a preferred edge (`top|bottom|leading|trailing`), and an alignment along that edge.
- **Placement solver**: place on the preferred edge; if the surface would cross the
  safe-area inset, **flip** to the opposite edge; if it would cross a side, **shift**
  along the edge and keep the arrow over the source. Safe-area is already respected
  elsewhere (`presenter.luau:820` — "a tooltip under a notch or behind the home
  indicator is unreadable"); reuse that, do not re-derive it.
- **Arrow tail** as an optional decoration, drawn with `UI.Path` / `pathShapes`
  (`src/controls/path_shapes.luau`), themed, and **suppressed when the surface had to
  shift so far the tail would leave the source**.
- Reuses, does not fork: the tap-away catcher (`presenter.syncPopupCatcher`), the
  focus scope push/pop (`src/focus/focus_graph.luau`), and the modal-zone layering.
- **Follows a moving source.** `swiftui-parity.md:543` already names the case ("menu
  anchored to a moving row") and row actions already read scroll geometry on the
  scroll cadence — anchor to that same cadence rather than a new watcher.

**Fixture:** the callout in `f1-avatar-editor.jpeg` — anchored under a top-right `+`
button, arrow up, body shifted left to stay on screen.

### D2 — `Menu` construct (freestanding action menu)

- Items are **verbs with icons**, not values: `{ id, label, icon?, role? ("default"
  | "destructive"), enabled?, onSelect }`, plus a divider item and a submenu item.
  This is what `f1`'s Accessory Adjustment / Body Shape / Head Adjustment /
  Clothing Layering / Makeup Layering / Skin Color list is; `popup_button.Option`
  (`{ id, label }`) cannot express it.
- **Submenus ship in this round** (director ruling 2026-08-16). A submenu item carries
  `children` instead of `onSelect`; declaring both is a spec error, not a precedence
  rule. Consequences to design for, not discover:
  - **Opening.** Pointer opens a submenu on hover-dwell *and* on click; touch and
    gamepad require an explicit activate. A submenu row shows a **trailing chevron** —
    Apple: "A menu item indicates the presence of a submenu by displaying a symbol —
    like a chevron — after its label."
  - **Depth: follow SwiftUI, which sets no structural cap and one guidance level.**
    `Menu` nests inside `Menu` arbitrarily — Apple documents no limit — while the HIG
    says "It can be difficult for people to reveal multiple levels of hierarchical
    submenus, so it's **generally best to restrict them to a single level**", and for
    context menus "more than one level of submenu complicates the experience". So:
    **structurally unbounded, with a diagnostic at depth ≥ 2.** Do not hard-cap. An
    earlier draft of this brief capped at 2 and was wrong in both directions — it
    forbade what SwiftUI allows and permitted twice what the HIG advises.
  - **Two more HIG rules worth encoding**, both cheap and both authoring-time checks:
    "if a submenu contains more than about five items, consider creating a new menu",
    and "provide icons for all menu items in a group, or none of them" — the second
    makes D2's new `icon` field a per-group all-or-nothing lint, not a free-for-all.
  - **A menu with every item disabled still opens.** Apple: "If all of a menu's items
    are unavailable, the menu itself needs to remain available so people can open it
    and learn about the commands it contains." Do not silently swallow the trigger.
  - **Placement.** A submenu is a D1 surface anchored to its *parent row*, preferred
    edge trailing, flipping to leading at the screen edge.
  - **Focus and dismissal.** Each level pushes its own focus scope; Cancel / gamepad B
    closes **one** level, tap-away closes **all**. Keyboard: right/left arrow enters
    and leaves a submenu, matching the tab-strip document-order rule (`97e9d93`).
  - **Touch does not nest well.** When the presentation resolves to `sheet`, a submenu
    **replaces** the sheet's contents with a back affordance rather than floating a
    second panel over the first. Same tree, two presentations — the `resolvePresentation`
    pattern, not a device branch.
- Attaches to **any** blueprint, not just a built-in trigger.
- Presented on D1. Presentation resolves the way `popup_button.resolvePresentation`
  already does — sheet when touch is live or the list is long on a compact screen,
  floating panel otherwise. **Extract that rule to one shared place**; two copies
  will drift.
- **Triggers** (this closes `.contextMenu`, Missing today): primary activate; pointer
  **right-click**; touch **long-press**; gamepad a bindable button; keyboard the
  context key or a bound chord. The normalized gesture layer exists and nothing
  consumes it as a trigger (`swiftui-parity.md:1030-1032`) — consume it.
- **Add `icon` to `popup_button.Option`** in the same round so `r1`'s icon rows work
  and the two menus render from one row recipe.

### D3 — `help` **and** `Callout` — two constructs, not one

**The correction that shaped this deliverable.** The `f1` plate is *not* a tooltip.
Apple's docs, read 2026-08-16, separate two mechanisms that this brief originally
conflated, and the reference app is using the second one:

| | Tooltip | Tip / coach mark |
|---|---|---|
| Apple API | `.help(_:)` (iOS 14+, all platforms); `UIToolTipInteraction` (iOS 15+) | TipKit `.popoverTip(_:arrowEdge:action:)` (iOS 17+), `Tip` protocol |
| What Apple says | help "configures the view's accessibility hint **and its help tag (also called a tooltip) in macOS or visionOS**"; `UIToolTipInteraction` "makes it possible to show a tooltip **when hovering a pointer** over a view or control" | "Presents a popover tip on the modified view… present a tip as a popover **when the tip becomes eligible for display**" |
| On a touch phone | **Nothing appears.** `.help` degrades to a VoiceOver hint; there is no visible tooltip and **no long-press binding anywhere in Apple's API** | Appears normally, with an arrow tail — this is `f1` |
| Who decides | the player, by hovering | **the app**, from rules |

**The collision this avoids.** D2 binds touch **long-press** as the Menu trigger. Had
tooltips also claimed long-press — the shape the director floated, and a reasonable
guess — two constructs would fight for one gesture on the only input class where
neither has an alternative. Apple never binds it; neither do we.

So build both, on the same D1 surface:

**D3a `help` — player-pulled, never on touch.**

| Input class | Show | Hide |
|---|---|---|
| Mouse / pointer | hover after a dwell delay | pointer leaves, or the view is activated |
| Keyboard / gamepad | on focus | on blur |
| Touch | **nothing** — and this is correct, not a gap | — |

Because touch shows nothing, `help` is **never** the only route to information a player
needs; it is a convenience for pointer and stick users. A build check should be able to
find a `help` string that appears nowhere else — the touch player cannot read it.

**D3b `Callout` — app-pushed, on every input class.**

- Content is a blueprint, not only a string — `f1`'s plate is styled and carries an
  arrow tail. D1 already owns the tail, the edge flip and the safe-area shift.
- **Eligibility rules**, TipKit's actual contribution: show once per player, or after
  N sessions, or only until the feature is used. Apple's own warning is worth copying
  verbatim into the doc — *"Use tips sparingly… Don't use tips to guide people through
  your app, or for advertising and promotion purposes."*
- **Invalidation**: a callout dies permanently when its feature is used, when the player
  dismisses it, or on an explicit invalidate. Persistence is the **caller's**, not the
  framework's — LuauUI has no save layer and must not grow one here. The construct takes
  a "has this been seen" Readable and reports back when it should be retired.
- **Never blocks.** A callout is not a modal: it must not trap focus, and the control
  it points at stays operable underneath it (the tap-away catcher's non-consuming mode,
  `swiftui-parity.md:1707`, is exactly this).
- At most one callout on screen at a time; a queue, not a pile.

Text in both is player copy: survives ~1.4x pseudo-localization expansion, wraps rather
than clips.

### D4 — Sliding selection indicator seam

The r3 animation. A shared indicator that **animates from the previously selected
child's rect to the new one** instead of cross-fading two static fills.

- Needs the arrange pass to publish the selected child's rect to the indicator, and
  a motion class to drive the transition. Prefer a scope-owned geometry memo compared
  **by value** — the shape that made the solve-count work land (`8560f2b`); a fresh
  `{}` each pass re-fires forever.
- **Reduced motion snaps.** The renderer already pushes that fact
  (`adapter.setReducedMotion`); read it, do not re-plumb it.
- Two shapes from the media: the **underline** (r2, f1 bottom strip) and the **filled
  pill** (r3, f1 top rail). One mechanism, two skins.
- Consumed by D5 and D6. Build it first — it is the only piece both need.

### D5 — `TabView` construct

- Spec: `selection` (owner-held Signal), `tabs` = `{ id, label?, icon?, badge?,
  content }`, `placement` (default `"automatic"` → `adaptive.navPlacement`),
  `indicator` (`"underline" | "pill" | "none"`).
- **Nesting is load-bearing.** `r2` is a top tab bar inside a screen that is itself a
  tab of the app-level bottom bar. Two live TabViews must not fight over focus scope,
  the presenter's `back()` stack, or `navPlacement` — an inner TabView must not claim
  the app-level placement. Name the rule explicitly and test two levels.
- **Overflow scrolls.** `f1` and `r3` both run their strip off-screen
  (`Avatars / Body / Clothing / Accessories / Backgrounds`). The strip is a
  horizontal `ScrollView` that **auto-scrolls the selected tab into view**;
  `LuauUI.newAutoscroll` exists (`src/input/autoscroll.luau`).
- **Lazy content, evicted state** (director ruling 2026-08-16). Build only the selected
  tab's subtree, and **tear the previous tab's subtree down on switch** — do not retain
  it. This is the memory-cheap choice and it is the right default for a kart racer whose
  UI competes with a live race for frame budget.
  - **The accepted cost, stated so nobody reports it as a bug:** returning to a tab
    replays its entry cost. `r2`'s spinner comes back; a scroll position returns to the
    top; an in-progress text entry is lost.
  - **The escape hatch is ownership, not a flag.** State that must survive lives in a
    caller-owned Signal *outside* the TabView, exactly as `selected` already does for
    every control here. Document this as the pattern — it is the framework's existing
    answer, not a new mechanism.
  - **Eviction must be a real disposal**, not a hide: scopes disposed, effects stopped,
    Instances released to the pool. A tab that leaks on switch is the likeliest defect
    in this deliverable, so the gate needs a switch-N-times memory-neutrality spec, the
    shape the registry-neutrality specs already use.
  - **Do not evict the strip.** Only tab *content* is torn down; every tab's label,
    icon and badge stay live, because a badge on an unselected tab is the whole point
    of a badge.
- **Reachability:** gamepad shoulder buttons page between tabs; keyboard reaches the
  strip in document order (the Tab-order rule shipped in `97e9d93`); every tab is a
  44 px target; icon-only tabs still carry a semantic label for the dump.
- The five reference apps hand-build their bars. **Migrate at least one to the new
  construct in this round** — an unconsumed construct is unproven.

### D6 — Segmented control upgrades (`newPicker`)

- `Option` gains `icon` (icon-only and icon+label). `f1`'s top pill and left rail are
  both icon-only.
- A **vertical** segmented pill. Today `axis = "y"` means the inline row list; `f1`'s
  left rail is a vertical *pill* — a distinct shape, not a row list. Add it without
  overloading the existing meaning.
- Adopt D4's sliding indicator.
- **Do not build a second tab construct.** "Segmented used as a tab bar" (r3) is
  `TabView` with `indicator = "pill"`. Say so in the docs.

---

### D7 — Elision must **disclose**, not delete (the HUD showcase round)

Director task, 2026-08-16: fix the Screen-anchored HUD showcase, modifying the framework
as needed. Evidence is `hud-a/b/c` in the reference-media folder; the fixture is
`examples/gallery/scenarios/hud.luau` (1322 lines).

**First, the question the director asked: "I thought we built the latter at one point
a la SwiftUI?" — yes, twice, and both shipped.**

| Mechanism | What it is | Where |
|---|---|---|
| `layoutPriority` | SwiftUI's actual modifier. A shrink-order **tier** inside one stack: the deficit is consumed lowest-tier-first, so a higher number survives longer | `api.md:189`; `src/layout/shrink.luau` |
| `UI.Composition` / `UI.Region` `rank` ladder (ADR-0025) | The whole-screen version, and the one in these screenshots. Each region declares a `rank` (1 = last to give way), an ordered list of **forms** richest-first, an optional `floor`, and `mayDrop`. The resolver **steps down before it drops**, both descending rank | `src/layout/composition.luau:147,1549`; `docs/adr/ADR-0025-screen-anchored-hud.md` |

The HUD prints its own ladder on screen: *"Rank ladder, first to give way last: feed,
tasks, fps, weapon, health, rail, actions, clock, buttons."* **The prioritization
mechanism is not missing and is not broken — it is doing exactly what it was told.**
What it lacks is any notion of *where the elided content went*, and that is the defect.

**The three failures, traced to source:**

1. **A stepped-down form is a dead end.** `Tasks` (`hud.luau:839`, `rank = 8`,
   `mayDrop = true`) declares three forms: `TasksFull` → `TasksOne` → `TasksChip`. In
   portrait the ladder picks `TasksChip`, which renders "Tasks 1/3" — and `pill()`
   (`hud.luau:508`) is `glass(…)` wrapping an `HStack` of `UI.Text`. **It is not a
   Button.** Three tasks and their rewards are gone and the thing left behind cannot
   be tapped. Same story for the scores: the `Clock` region's second form is
   deliberately "the clock and the ring, WITHOUT the scores" (`hud.luau:1028-1032`),
   so `12` and `9` simply cease to exist.
2. **A dropped region is gone entirely.** With the URL bar open (`hud-c`), `Tasks`
   drops below even its chip, and `Health`, the kill feed and the weapon rail go with
   it. `RegionResolution` reports `dropped = true` and nothing else happens. A grep of
   `composition.luau` for a disclosure, overflow-sink or recovery concept returns
   nothing — `hugOverflow` is a *measurement* diagnostic, unrelated.
3. **The pseudo URL bar is about twice its real height.** `URL_BAR_PX = 200`
   (`hud.luau:129`), commented as "a fact about the SCREENSHOT". One number is doing
   two jobs — the height the chrome *steals* and the height it is *drawn at*
   (`hud.luau:481`: "the pseudo URL bar is as tall as the height it is taking") — so an
   over-stated steal also paints an absurd box. In `hud-c` it eats roughly half the
   viewport.

**What to build:**

- **D7.1 A recovery contract on `Region`.** A region states what becomes of content its
  chosen form stops showing. `recover = "none"` means genuinely nothing is lost and must
  be written explicitly — silence is not consent. Otherwise the region names a recovery
  route. `RegionResolution` gains `elided` (a form below the richest was chosen) beside
  the existing `dropped`, and `Resolution` gains the list of currently-unshown regions.
  **That list is the seam** the HUD reads to populate its overflow surface; without it,
  every consumer re-derives elision by hand and gets it subtly wrong.
- **D7.2 A terminal form must be actionable.** A region with a recovery route whose
  last-standing form contains no focusable element is an **authoring error**, caught at
  normalize time like every other closed-spec violation. In the fixture this turns
  `TasksChip` into a Button that opens the full task list — as a D2 Menu or a D1 panel,
  which is why D7 lands after them and reuses them rather than inventing a surface.
- **D7.3 An overflow sink for dropped content.** Rank-1 regions never drop, so a host
  always exists. The framework supplies the elision list (D7.1); the HUD supplies a
  "more" affordance in a rank-1 region that opens it. Dropping stops meaning deleting.
- **D7.4 Re-rank what the screenshots expose.** A team score outranks an FPS readout;
  `fps` currently sits above `tasks` in the ladder. Re-rank, and let the disclosure
  route carry the rest — a scoreboard is precisely the thing "tap for detail" is for.
- **D7.5 Split the URL-bar constant in two.** The modelled *steal* and the drawn
  *height* are different facts and need different names. Re-measure both against a real
  browser rather than inheriting the screenshot's number.
- **D7.6 The gate check that would have caught all three.** Sweep the device matrix and
  assert: **at every viewport, every elided or dropped region has a live recovery
  route.** Mechanical, cheap, and the only one of these deliverables that keeps the
  defect from coming back.

**The principle, stated once so it can be applied beyond this fixture:** adaptation may
change how much of something is shown, and may change what it costs to reach it. It may
not change *whether it can be reached at all*. A layout that silently deletes player
information at a viewport nobody tested is the defect class this deliverable closes.

### D8 — Sort + resize the playlist table, then retire `table_columns`

Director task, 2026-08-16: *"in the showcase, let's make the table in the playlist table
sortable and the columns resizable. that will let us remove the separate resize columns
example."*

**Good news first: both capabilities already ship.** This is an example task, not a
framework one.

| Capability | Where | Shape |
|---|---|---|
| Sorting | `src/controls/table.luau:146-150,2162-2165` | `sortOrder` is an owner-held Signal of `nil \| { column, ascending }`. Tapping a sortable header cycles it (new column → ascending, same → flips). **The table never sorts the data** — the owner observes and re-sorts. SwiftUI `Table(sortOrder:)` parity. A column is sortable when it carries `value` or opts in with `sortable = true` |
| Resize | `:107,3621`, `:1144`, `:2137`, `:3357` | Per-column `resizable`, model `api.setColumnWidth`, published state `api.columnWidthOverrides`. Three routes commit through one model: pointer drag on the header divider, keyboard ←/→ after Return on a heading, gamepad bumper. Widths clamp to `column.minWidth or 24` at read, at drag and at step |

**Two facts to know before executing, both discovered in source rather than assumed:**

1. **The playlist does not sort today.** `grep -c sortOrder examples/gallery/examples/02_playlist_table.luau` → **0**. Meanwhile `table_columns.luau:30` describes it as "the shipped tutorial for sorting, filtering and reordering". That comment is **stale** — filtering and reordering are there, sorting never was. Fix the comment in whichever file survives.
2. **A prior round considered this exact merge and rejected it**, in writing, at `table_columns.luau:28-33`: *"`02_playlist_table` … Its two columns are a `fill` Name and a Rating pinned to a measured 144px, with a long comment explaining why that number is not free to move; making either resizable fights that lesson, and a tutorial has no room for the width readout that makes a resize legible."* The director has now overruled that. Execute the merge — but the two objections are **facts about the measurement**, not preferences, so pay them rather than ignore them.

**What deletion actually costs.** `table_columns` is not only a demo. It is the fixture
behind `tests/table_columns.spec.luau` (~700 lines, six `describe` blocks: header
legibility, the three routes moving one column, the scenario contract, the divider's real
hit size, a press the divider forwards, and selected-column release on focus loss) — and
`tests/hit_expander_overhang.spec.luau:43` **requires the scenario module directly**.
Two more specs cite it by name (`scroll_window_clip`, `measure_publish_settle`). None of
that may be dropped; it has to be re-pointed.

**The work:**

- **Sort.** Add an owner-held `sortOrder` Signal to `02_playlist_table` and re-sort its
  own rows from it, composing with the existing filter memo — the filter and the sort are
  both derivations over one source list, and getting that composition right *is* the
  lesson. Name sorts by `value`; Rating opts in with `sortable = true` and sorts by the
  rating signal. Reordering by drag and a live sort are in tension: define which wins
  (a manual reorder should clear the sort, the iTunes behavior) rather than leaving it.
- **Resize — and the playlist needs a THIRD column before this works at all.** Director
  ask, 2026-08-16: *"can we make it so that the rating column is not resizable but the
  others are?"* Per-column `resizable` is exactly the right mechanism and `table_columns`
  already proves it (`best` declares no `resizable`, so it grows no divider and binds no
  Adjust key). **But the playlist has only two columns** — `name` (`fill`, weight 1) and
  `rating` (`fixed`, 144px) — so "the others" is one column, and that case is degenerate:

  `resolveDim` (`table.luau:1140-1144`) turns **any** resized column into
  `{ type = "fixed", px }`. Pin Name and *both* columns are fixed, their widths sum to
  whatever the drag left, and **nothing flexes to absorb the remainder** — the row
  under-fills and leaves dead space at the trailing edge. That is the "painted at a size
  nobody measured" family, shipped deliberately.

  `table_columns` does not have this problem because it runs **three `fill` columns**
  (weights 3/4/3, minWidths 90/80/70) — two resizable, one locked — so pinning one leaves
  two siblings to take up the slack. **Copy that shape.** The playlist gains a third
  column (Artist reads best for a music table; Length is the other candidate), `fill` with
  a `minWidth`, `resizable`. Final shape: **Name `fill` resizable + Artist `fill`
  resizable + Rating `fixed` 144 locked** — which is literally what the director asked
  for, and reproduces `table_columns`' "a column that REFUSES" lesson for free.

  **Two measurements this must clear, neither of them optional.** The playlist deleted its
  Length column for a *measured* reason (swipe-actions round, `02_playlist_table.luau:230-247`):
  a third **fixed** 70px column plus edit mode's two leading gutters left the Name cell 6px
  at 320x640, and the solver said "content box collapses to 0px on x" six times. A third
  **`fill`** column with a `minWidth` is a different animal from a fixed 70px one — but
  "different animal" is a hypothesis, so **re-measure at 320x640 in edit mode before
  keeping it**, and if it will not fit, fall back to two columns and say so in the file
  rather than shipping the degenerate resize.
  Second: give every resizable column an explicit `minWidth`, **never** the 24px default,
  which is legible for nothing — Name already measures only 60px at 320x640 in edit mode,
  so a drag to 24 re-opens the very collapse the swipe-actions round closed.
  **Rating stays locked** regardless: its 144 is measured against the widest touch
  star-run (136px), and that number is not free to move.
- **Carry over what a screenshot cannot show.** `table_columns` exists because *"a resize
  is a change, not a picture"* — a table whose first column is 218px and one that was
  always 218px are the same image. So the playlist gains the live width readout, read
  from `api.columnWidthOverrides` (never a local copy), and the hint line that names the
  selected column — because `api.selectedColumn` **paints nothing**, so after a gamepad
  Activate on a heading the stick silently means something new and the screen does not
  say so. That honest gap-report is the fixture's most valuable line; do not lose it.
- **Re-point the tests, then delete.** Move `tests/table_columns.spec.luau` onto the
  playlist fixture, fix `hit_expander_overhang.spec.luau:43`, update the two by-name
  citations, then remove `examples/gallery/scenarios/table_columns.luau` and its two
  registrations (`scenarios/init.luau:149`, `client/demo_picker.luau:243`). **Deleting
  the fixture before the specs are green somewhere else is the failure mode here.**

**Sequencing:** independent of D1-D7 — no new construct, no shared seam. Run it whenever
a lane is free.

## 3. Rules that apply to the whole round

- **No device branches.** Presentation resolves from size class, height class and
  live interaction classes. A grep for platform names in new source must come back
  empty.
- **Three axes** (constitution): every action reachable and visible on keyboard,
  gamepad and touch, phone through desktop. A menu that only opens on right-click is
  a defect.
- **Closed specs.** Unknown key = authoring error, never a silent no-op
  (`src/spec_guard.luau`).
- **Dumps.** Every construct gets a `dump()` with a schema string and semantic text,
  matching `picker.dump` / `popup_button` practice. Gate evidence comes from dumps
  and captures, not from assertion counts.
- **Themed off existing tokens.** Row heights come from the control-size ladder the
  way `popup_button` does (`SHEET_ROW_HEIGHT` etc.) — a theme that retunes the ladder
  retunes these constructs with it. No new bespoke metrics without a token.
- **Localization-safe.** All labels wrap or auto-fit at ~1.4x expansion; never clip.
- **Update the parity docs in the same round.** `swiftui-parity.md` rows for
  `.contextMenu` (Missing), `.popover` (Partial), `Picker` (Partial) and the audit's
  rows 14 and 15 all change. A stale parity table is worse than none.
- **Rascal Rally rides along** (root `CLAUDE.md`): it consumes `src` directly. Survey
  every affected caller, add or update a contract/integration test proving the live
  consumer is current, and run a Studio canary. Do not manufacture churn and do not
  change game behavior or flags.

## 4. Suggested stage order

**D0 first**, then D1 → D2 → D3a → D3b → D4 → D5 → D6 → D7 → rider (Rascal Rally, docs,
examples, parity rows). **D8 is independent** — no new construct, no shared seam — so run
it in any free lane rather than holding it behind D7.

D0 leads because every stage below it runs gates, and today each gate re-runs an 83-second
suite from scratch. Landing it first is the difference between a sweep costing minutes and
costing hours, repeated once per stage.

D1 is the substrate for D2, D3a and D3b. D4 is the substrate for D5 and D6. **D7 comes
last on purpose**: its terminal forms and overflow sink are built out of D1's anchored
surface and D2's Menu, so running it first would mean inventing a throwaway surface and
then deleting it. Each stage ships green on its own: tests red first, then the change,
then the suites, then a commit.

**Land D2's long-press trigger before D3a**, so the gesture ownership named in §2 D3 is
settled in code rather than in prose. `help` never binding long-press is a claim a spec
should be able to fail on.

## 5. Verification — run at the end of every stage, all green before moving on

```
cd GameStudio/ui/LuauUI
lune run tests/run                            # expect 5530+ passed / 0 failed
python3 tools/check_source_size.py            # PASS, KNOWN_OVER empty
lune run tools/lune/check_registration_cli    # PASS
lune run tools/lune/check_surface_ledger      # PASS
lune run tools/lune/check_prop_parity_cli
lune run tools/lune/check_docs
lune run tools/lune/check_theme_drift
lune run tools/lune/check_example_drift_cli
stylua --check src tests examples
cd ../../../games/RascalRally/code && lune run tests/run   # expect 3262+ / 0
```

Plus the GuiObject count against the 43%-elided baseline — these constructs add
surfaces, and a silent elision regression is the likeliest way this round does net
harm.

**Commit with `tools/commit_isolated.py`, never a bare `git commit`** — a stale shared
index silently reverts other agents' work (measured). Never `git reset` / `checkout` /
`stash` / `add -A`.

**Report tiered:** headless is a regression signal only, Studio is the real engine, a
physical device is the only device claim. Flag every gesture trigger (long-press,
right-click, hover dwell) for a physical-device pass — Studio cannot test touch.

## 6. Director rulings — 2026-08-16

All three questions this brief opened with are **closed**. Execute them; do not
re-litigate.

1. **Submenus ship** (D2). Nested menus are in scope, capped at 2 levels, with the
   sheet presentation replacing contents rather than stacking panels.
2. **Tooltips split into two constructs** (D3). The director asked what iOS does and
   whether a long-press should let a developer force one. Apple's docs answered it:
   a tooltip is **pointer-hover only and invisible on touch**, while the auto-popping
   plate in `f1` is a **TipKit coach mark** — a different mechanism the app pushes from
   rules. So: `help` is hover/focus only and never binds long-press (which D2 needs),
   and `Callout` is the app-pushed construct that reproduces `f1`.
3. **Tab state is evicted** (D5). Only the selected tab's subtree exists; switching
   disposes the previous one. Anything that must survive is held in a caller-owned
   Signal outside the TabView.

Ruling 2 grew the round by one construct. It also removed a gesture collision that
would have shipped otherwise, so the net is a smaller bug surface, not a bigger one.

**Follow-up rulings, same day, after the first draft:**

4. **Submenu depth follows SwiftUI, not this brief's first guess** — structurally
   unbounded, diagnostic at depth ≥ 2, per §2 D2. The original "cap at 2" was wrong
   against both the API (no cap) and the HIG (one level).
5. **D7 added**: fix the Screen-anchored HUD showcase, modifying the framework as
   needed. Elision must disclose rather than delete. See §2 D7.
6. **D0 added** (and moved to the front): one suite run per sweep instead of 161. See §2 D0.
7. **D8 added**: make the playlist table sortable and its columns resizable, then retire
   the standalone `table_columns` scenario. Both capabilities already ship, so this is an
   example task. It **overrules** a prior round's written decision not to merge them
   (`table_columns.luau:28-33`) — the merge proceeds, but that round's two objections were
   measurements, so §2 D8 pays them instead of discarding them. The deletion carries
   ~700 lines of spec that must be re-pointed first.

## 7. Sources

Apple documentation, read 2026-08-16 via the `developer.apple.com` documentation JSON:

- [`help(_:)`](https://developer.apple.com/documentation/swiftui/view/help(_:)-9lm7l) —
  iOS/iPadOS/Mac Catalyst/tvOS 14+, macOS 11+, watchOS 7+, visionOS 1+. "Adding help to
  a view configures the view's accessibility hint and its help tag (also called a
  tooltip) in macOS or visionOS."
- [`UIToolTipInteraction`](https://developer.apple.com/documentation/uikit/uitooltipinteraction) —
  iOS/iPadOS/Mac Catalyst 15+, visionOS 1+. "An interaction object that makes it
  possible to show a tooltip when hovering a pointer over a view or control."
- [`popoverTip(_:arrowEdge:action:)`](https://developer.apple.com/documentation/swiftui/view/popovertip(_:arrowedge:action:)) —
  iOS 17+, macOS 14+, tvOS 17+, visionOS 1+. "Presents a popover tip on the modified
  view… when the tip becomes eligible for display."
- [TipKit](https://developer.apple.com/documentation/tipkit) — "Use TipKit to show
  contextual tips that highlight new, interesting, or unused features people haven't
  discovered on their own yet… Use tips sparingly… Don't use tips to guide people
  through your app, or for advertising and promotion purposes."
- [`Tip`](https://developer.apple.com/documentation/tipkit/tip) — "A type that sets a
  tip's content, as well as the conditions for when it displays."
- [`Menu`](https://developer.apple.com/documentation/swiftui/menu) — "A control for
  presenting a menu of actions… presents a menu of three buttons and a submenu, which
  contains three buttons of its own." **No depth limit is documented.**
- [HIG: Menus](https://developer.apple.com/design/human-interface-guidelines/menus) —
  "It can be difficult for people to reveal multiple levels of hierarchical submenus, so
  it's generally best to restrict them to a single level. Also, if a submenu contains
  more than about five items, consider creating a new menu." / "A menu item indicates the
  presence of a submenu by displaying a symbol — like a chevron — after its label." /
  "provide icons for all menu items in a group, or none of them" / "If all of a menu's
  items are unavailable, the menu itself needs to remain available."
- [HIG: Context menus](https://developer.apple.com/design/human-interface-guidelines/context-menus)
  — "more than one level of submenu complicates the experience and can be difficult for
  people to navigate." / destructive items "list them at the end of the menu".
