# Task G4+G5 report — self-measuring viewports, theme-token gaps, and the extraction that had to precede them

**Lane:** R1b (writer). **Status:** DONE_WITH_CONCERNS.
**Facet commits:** `5b66dea`, `9c76f99`, `15fe21d`, `cc430da`, `d65a1b5`, `83a7b81`, `e0e8847`.
**Rascal Rally commit:** `64069fc`.
**Final measured suites (content-pinned pair, refs resolved at measurement time —
`PIN_FACET e0e88472`, `PIN_RR 7a2b3a2e`):** Facet **7,124 passed / 0 failed**,
Rascal Rally **3,483 passed / 0 failed**.

---

## 1. The hard prerequisite: the hosted-block extraction (`5b66dea`)

`docs/handoff/SOURCE_CAP_LEDGER.md`'s row for `src/controls/virtual_list.luau`
named this block, sized it, and made it a **precondition rather than a
companion**: "the next change of any size to this file is PRECEDED by the
extraction, not accompanied by it". The file was 192,187 characters — 805 from
the 193,000 the row set as its own last warning.

`src/controls/virtual_list_hosted.luau` (56,887 chars) carries
`hostedItemExtentIn` through `hostedRestoreFocusOnDisengage`: the swipe
dispatcher and its axis lock, the per-row `row_actions` engine cache and its
retention policy, the shared tray overlay's item list, the presentation slide,
the commit collapse, the list-wide Delete/menu key context and the focus restore
on disengage. **192,187 → 145,913**, i.e. out of the 190,000 warning band
entirely.

### What made it one-way

The block read **seven reassigned locals of its host** — the six contribution
handoffs (`hostedMotionClock`, `hostedNow`, `hostedActionSystem`,
`hostedFocusGraph`, `hostedPresentModal`, `hostedDismiss`) plus
`boundController` — and a reassigned local cannot be shared by reference at all.
They are one `hostedDelivery` record both halves hold: `table.luau`'s
`rowGesture` technique, exactly as the brief and the ledger row prescribed.

**Writing it found two cells the analysis had missed**, both the same class:

* `mountedScrollPath` — the focus-group derivation and `syncGeometry` both write
  it, and every overlay path is spelled from it;
* `suppressActivatePath` — the one-Activate swallow, and the **only cell BOTH
  halves write**, which is why it could not have been an accessor instead (the
  alternative technique this same file already ships for `virtual_reorder`).

### Extraction neutrality evidence (before/after suite diff)

Measured in content-pinned `mkpair` copies, never a live tree:

| pair | Facet suite |
|---|---|
| baseline `PIN_FACET a39146bd` | **7,062 passed, 0 failed** |
| extraction `PIN_FACET 5b66deae` | **7,077 passed, 0 failed** |

The verdict SETS were diffed line for line (`✓`/`✗` lines, stripped of colour,
sorted, `comm`):

* **removed: 0** — nothing re-verdicted, nothing lost;
* **added: 15** — every one of them `tests/virtual_list_hosted_seam.spec.luau`'s
  own case titles, listed in full in the run log.

### The seam spec, and the two rules that reported before the commit landed

`tests/virtual_list_hosted_seam.spec.luau` (14 cases) mechanises READ ==
DECLARED == PASSED as set comparisons over the live sources, the shared WRITE
surface pinned to **one dep and one field inside it**, a NO-STALE-TWIN rule over
the nine historic names, the one-way require, the single spelling of the two
mounted-path ids, and "no module-level mutable state". Each rule carries a
negative control.

**Two of them were findings, not drills**, which is the only evidence a seam spec
is not decoration:

1. the write scan read a table constructor's `id = \`{id}:{key}\`,` as a dep
   *reassignment*. A statement assignment does not end in a comma; a constructor
   field does. The scan is line-based now and the negative control feeds it both
   shapes;
2. the surface pin caught that **three of the twelve returned names are ABSENT**
   on a list with no `rowActions` (`engagedKey`, `engagedOffset`,
   `overlayItems` are nil until the feature is on). That became its own case —
   and it is the proof the construction site may be called unconditionally, with
   `core` and `listScope` passed as method-less tables so any reactive call on
   that path would raise.

### What the extraction owed on the way out, and what that cost

Per the ledger's head, the file left `check_comment_codes`' `EXTRACTION_LOCKED`
tuple. That surfaced **sixteen** private codes, not the fourteen orphans alone,
because a file leaving the tuple brings its **resolvable** codes into a count
that is a **ratchet** — "make the orphans resolvable" would have moved the total
from 25 to 41 and failed anyway. All sixteen became prose, which is what the
`solver.luau` round did one file over.

**A trap worth recording, and it cost a red run:** `check_comment_codes` reads
`git ls-files`, so a **brand-new module is invisible to it until the commit that
adds it lands**. It passed on the split commit for exactly that reason, then went
red on the next run with four codes that had ridden out of a file whose exemption
had just ended. Run it *again after* the commit, not only on it. (Swept in
`cc430da`.)

---

## 2. Gap 4 — self-measuring viewports (`15fe21d`)

### RED evidence

`tests/collection_self_measure.spec.luau` written first. Command:
`lune run tests/_runone.luau` (a one-file runner over the new spec).

```
✗ windows against the SOLVED host box, with no number handed in
    src/controls/virtual_list:684: VirtualList.viewportExtent … must be a positive number or a Readable<number>
✗ SEEDS FROM THE SCREEN, so the frame before a measurement over-fills      (same refusal)
✗ a RESIZE re-measures in place, and a settled tree writes nothing         (same refusal)
✗ newVirtualGrid takes it too, on its own scroll axis
    src/controls/virtual_grid:424: VirtualGrid.viewportExtent must be a positive number or a Readable<number>
✗ absent, the cross axis FILLS — every shipped list is untouched           (same list refusal)
✗ "hug" sizes to the content instead — the rail is as tall as its card
    Facet newVirtualList: unknown spec key 'crossExtent'. Known: … (35 names)
✗ "measured" keeps filling and REPORTS the box it was given               (unknown key)
✗ an unknown word is refused, naming the two that are legal               (expected false to be true)
8 failed, 1 passed
```

Expected exactly: `viewportExtent` was asserted required with no self-measuring
form (audit §4, `virtual_list.luau:672-679`), and `crossExtent` did not exist at
all, so the closed-spec guard named it.

### GREEN evidence

Same command after the implementation: **10 passed, 0 failed** (nine original
cases plus the self-review case in §6). Full-suite: no verdict lost.

### What shipped

* **`viewportExtent = "auto"`** on `newVirtualList` and `newVirtualGrid`. The
  host takes `fill` along its own axis and windows against what the solver gave
  it, read off `syncGeometry`. `newTable`'s technique promoted verbatim, with all
  three load-bearing parts: `fill` is what makes it converge (the host's size is
  decided by what contains it, so measuring cannot change what was measured); the
  equality guard is what keeps that a fact rather than a hope; the seed is the
  **screen** so the frame before a measurement **over-fills** (a strict superset)
  rather than mounting three rows and popping. Asserted, not assumed: the
  convergence case observes the published signal across two extra refreshes and
  expects **zero** writes.
* **`crossExtent = "hug" | "measured"`** on `newVirtualList`. Absent, the cross
  axis fills — every shipped list byte-identical. `"hug"` takes `content` on the
  host, its canvas and every row. `"measured"` fills and reports.
* Both publish a `Readable<number>` (`list.viewportExtent`, `list.crossExtent`,
  `grid.viewportExtent`) **only when the collection was asked to measure that
  axis**. A collection that declared its own numbers publishes neither.
* `crossExtent` is deliberately **not** a grid field: a grid's lane width is
  derived FROM its cross extent, so a hugging grid would be asking its lanes how
  wide they are in order to know how wide its lanes are. The grid's closed spec
  refuses the key by name; api.md says why.

---

## 3. Gap 5 — token-refusing gaps (`15fe21d`)

### RED evidence

`tests/collection_gap_tokens.spec.luau` written first:

```
✗ VirtualList.rowGap resolves a space step …      virtual_list:656: VirtualList.rowGap must be a non-negative number or a Readable<number>
✗ …and a DOTTED PATH into the metrics …          (same)
✗ VirtualGrid.rowGap and VirtualGrid.gap both take one
                                                  virtual_grid:393: VirtualGrid.rowGap must be a non-negative number or a Readable<number>
✗ VirtualGrid.gap takes a Readable — the field that refused even that
                                                  virtual_grid:406: VirtualGrid.gap must be a non-negative number
✗ a name that resolves NOWHERE is refused, and names itself   (expected false to be true)
✗ the gutter is LIVE: a theme swap moves it with no rebuild   (list refusal)
6 failed, 1 passed
```

Expected exactly: the three refusals the audit cites verbatim
(`virtual_list.luau:659-666`, `virtual_grid.luau:392-397`, `:405-409`).

### GREEN evidence

Same command after: **7 passed, 0 failed**.

### What shipped

`src/controls/gap_metric.luau` — one vocabulary, one refusal, one live read,
shared by both collections **so they cannot drift into two answers about what a
gutter may be** (the reason `controls/scroll_snap.luau` exists one file over).
All three fields (`VirtualList.rowGap`, `VirtualGrid.rowGap`,
`VirtualGrid.gap`) take a number, a theme metric name (`"xs"`..`"xl"` or a dotted
path), or a `Readable` of either.

**One deliberate divergence from `newTable`, and it is the stricter direction.**
An unresolvable name is REFUSED at construction, by name, rather than falling
back to `0`. `rowGap = "6"` is a number somebody quoted, and constitution §4's
rule for a spec field is that an unknown value is an authoring mistake and never
a silent no-op — which bites hardest on a field whose wrong answer is invisible,
because a gutter of zero looks exactly like a gutter nobody asked for. Every
spelling `newTable` accepts *and means* still works; the only thing refused is the
spelling that meant nothing there either. **This is a knowing deviation from the
brief's "exactly matching Table.rowGap's contract"** and is argued in ADR-0043
§3, with `newTable` adopting `gap_metric` recorded as owed (its file belonged to
a concurrent writer this round).

---

## 4. Consumer migrations (`cc430da`, `d65a1b5`)

**Four fixtures stop predicting geometry. Two LEAVE the theme-drift lint's
*coupled* set** — the lint's own criterion for "this file predicts its own box
from raw constants" no longer matches them, and the pinned coupled list in
`tests/theme_drift.spec.luau` shrinks by two rows.

| fixture | what went | what replaced it |
|---|---|---|
| `scenarios/row_actions.luau` | a `VLIST_PANE` path used for arithmetic, a `vlistWindow` signal seeded with a literal `336`, an `onGeometry` handler, and the **`vlistGap()` memo the audit named as this round's precedent** | `viewportExtent = "auto"`. The path survives *as a path* (two scripted steps aim the focus ring with it) |
| `scenarios/card_rail.luau` | a width memo subtracting `coreSafeInsets` + a Screen padding + a scrollbar guess (inside a PROBE-EXEMPT block whose comment said "the idiom a reader should copy does not exist yet"), and a **~45-line `cardHeight` memo** summing five terms incl. `chromeInsets`/`chromeOutsets` and `RAIL_SLACK` | `viewportExtent = "auto"` + `crossExtent = "hug"`; two module constants deleted |
| `scenarios/virtual_grid.luau`, `virtual_hgrid.luau` | `CELL_GAP`/`LINE_GAP = 6` literals; the hgrid's lane readout divided around its own copy | theme metric names; the readout reads the RESOLVED number off `grid.dump()` |

**`vlistGap()` and the `CELL_GAP`/`LINE_GAP` literals were in
`examples/gallery/scenarios/`, not in `src/controls/row_actions.luau`** — the
brief's file attribution was off by one directory. Same for the
`math.clamp(math.floor(h * fraction), min, max)` windows: they are the gallery's
`sponsor_drop`/`sponsor_list`, not Rascal Rally's (see §5).

### Not value-identical, and it could not be

The brief asked for the gap tokens to be "value-identical at neutral scale".
**No metric in any shipped package resolves to 6** (I enumerated the neutral
snapshot: the only 6s are `controls.label.gap`, `controls.progress.trackHeight`,
`controls.table.editTogglePadding`, `controls.slider.railHeight`,
`iconRunGap.medium.pointer` — every one of them semantically wrong for a grid
gutter). The two grid fixtures therefore move **6 → 4** (`"xs"`) at neutral. The
sweeps that would see it — the large-text matrix, the five-view matrix, the
overflow guard — are unmoved.

### One migration MEASURED AND REVERTED, which is a finding

`scenarios/sponsor_drop.luau` was migrated to `viewportExtent = "auto"` and then
reverted **on measurement**, with the reason now stated at the site. Its premise
is a canvas end the drag can **reach**: the autoscroll arm drives the bottom band
for 1.2 s and the chevron arm asserts the canvas clamped *and returned to 0* in
the 1.2 s that follows. Both hold only while the overflow is **small**.
`FULL_COUNT = 12` at a 44 px row is calibrated against a window the clamp caps at
420; `"auto"` handed it the **673 px** pane the layout actually decided (measured
in the suite's own 900×760 world), twelve rows fit inside it, and the drag
reached the band with nothing to scroll. Raising the count to 40 fixed the
autoscroll arm and broke the chevron arm instead, because the canvas end went out
of the ramp's reach in 1.2 s. **The calibration is between the ROW COUNT and the
WINDOW, and a bounded window is what makes it hold at every swept viewport.**

`scenarios/sponsor_list.luau` keeps its clamp for a different, also-documented
reason: its list sits inside a **y-scrolling page**, whose content box is
unbounded on y by construction, so a `fill` child of it has nothing definite to
measure — which is `"auto"`'s one stated requirement.

---

## 5. Rascal Rally (`64069fc`)

**No production file needed an edit, and that is the claim that got evidence.**
`RacerList.luau` hands a `Readable` viewport derived from the split rect, and
`FacetSponsor/init.luau` derives it through `TableMetrics.listBand` — a
**measured** band, not a hand-rolled fraction. There is no
`math.clamp(math.floor(h * fraction), min, max)` viewport window in the game to
migrate. (`TableMetrics.luau` also belongs to the other lane this round.)

`tests/facet_collection_extent_contract.spec.luau` (11 cases) pins four things on
the game's side of the seam, on the game's own numbers (`TableMetrics`' 56 px
landscape row on a 6 px gutter — `RacerList`'s pitch):

1. **the spellings this package ships are unmoved** — a number `rowGap` and a
   `Readable` `viewportExtent` still window on the pitch (40 rows span
   `40×56 + 39×6`; a 200 px window mounts 6 with overscan 2, a 400 px one mounts
   9), and `newTable.rowGap = "xs"` — what `ResultsScreen.luau` declares — still
   constructs and mounts;
2. **the hosted extraction is invisible from here** — a list with `rowActions`
   still builds, publishes `engagedKey`/`engagedOffset` and windows on the pitch;
   a list without still publishes neither;
3. **the new forms are reachable on this require path**, so a partially-synced
   framework copy fails here rather than as a nil in a screen;
4. **widening a type did not turn a guard off** — a negative gutter, an
   unresolvable metric name and an unknown `crossExtent`/`viewportExtent` word
   are each still an error at the call site.

### RED evidence, game side

Content-pinned pair with **Facet at the pre-change baseline** and RR at the
commit carrying the spec (`PIN_FACET a39146bd`, `PIN_RR 64069fc0`):

```
✗ `viewportExtent = "auto"` is accepted and publishes the measured signal
    virtual_list:674: VirtualList.viewportExtent … must be a positive number or a Readable<number>
✗ `crossExtent` is accepted in both forms …
    Facet newVirtualList: unknown spec key 'crossExtent'.
✗ a gutter takes a theme metric NAME on both collections
    virtual_list:661: VirtualList.rowGap must be a non-negative number or a Readable<number>
3 failed, 8 passed
```

The eight that pass in both arms are the compatibility half — which is the point:
they would have caught the extraction moving something.

---

## 6. Bug-C row_actions half, controller-assigned (`9c76f99`)

Assigned mid-round by the controller from
`artifacts/framework-gaps-phase2/bugC-wrapped-row-blocked.txt` because
`src/controls/row_actions.luau` is this lane's file.

**RED first**, and the red is the packet's own prediction to the pixel. The
packet's spec case was not in `tests/table.spec.luau` (it had been carried as a
blocked NOTE instead), so I added it and ran it against the tree with the table
half already landed:

```
tests/table.spec:177: expected 68 to be 32
```

36 px = `controls.rowActions.editAffordance` (28) + `controls.rowActions.rowGutter`
(8), exactly as the packet predicted.

**The change**, one assignment plus its reasoning: `api.editGutterPx` moves out
of `if isHosted then` and is published in both modes. A hosted host spends the
gutter itself so it obviously needs the number; a WRAP host, where the composite
spends it on the caller's behalf, may still have **other chrome outside the
composite** that must reserve the same amount — and `newTable`'s heading band
does. There was no second route (`controls.rowActions.rowGutter` is not exported
from `row_actions_metrics.luau`) and re-deriving `28 + 8` in the table would be a
second implementation of a number the composite owns.

**GREEN:** `tests/table.spec` 134 passed, 0 failed. The blocked NOTE in that file
is replaced by the case it was standing in for.

**A defect this activated, and I did not catch it — the other lane did.**
`table_rows`' `noteEditGutter` subscribed to the newly-legible signal without
owning the subscription on a scope, so an edit-mode table with destructive
`rowActions` leaked one observer per dispose. Their spec ("disposing an
edit-mode table with destructive rowActions frees the edit-gutter observer")
caught it and their commit `8f174fe` fixed it. **My covering spec proved the
alignment and did not audit the disposal of the subscriber my publication
created** — see Concerns.

---

## 7. Paperwork

* **`docs/adr/ADR-0043-collections-measure-and-name.md`** — one ADR for the
  coupled pair, because §4 and §5 are one sentence twice. Records the four
  hand-rolled derivations with their measured pixels, the three load-bearing
  parts promoted from `newTable`, the one requirement `"auto"` places on its
  ancestor, the deliberate stricter divergence on an unresolvable name, and
  explicitly **why there is no ADR-0040 row**.
* **No ADR-0040 row.** Every clause widens or adds: `viewportExtent` gains a
  word; `crossExtent` absent reproduces previous behaviour exactly; the three
  gutters gain two accepted forms and a number behaves identically; the
  self-measured `Readable`s are published only when asked for, so no returned
  table gained a field a caller could collide with; and
  `newVirtualGrid.dump().gap` now reports the resolved gutter, which is
  byte-identical for every call that was legal before (the field only accepted a
  number). The one shipped-behaviour change in the round is bug-C's publication,
  which is a bug fix with its own red.
* **`docs/reference/api.md`** — a `Self-measuring extents` section under
  `newVirtualList` (the two forms, the convergence argument, the seed, the one
  requirement stated rather than implied), the widened `rowGap` /
  `viewportExtent` rows, the new `crossExtent` row, the conditional return
  fields, and the grid's own rows. `check_docs` PASS.
* **Surface ledger** — the two conditional returns recorded against
  `newVirtualList` / `newVirtualGrid`, with why the classification is unchanged.
  `check_surface_ledger` PASS.
* **`chromeInsets`/`chromeOutsets`** (the audit's aside): they remain
  public-reachable as snapshot fields (`Facet.text.facts().metrics.chromeInsets`;
  RR's `facet_racer_list.spec` reads one), so they are **not** retired. What is
  retired is the *example* reach — `card_rail`'s `cardHeight` was the framework's
  only fixture summing them by hand, and `crossExtent = "hug"` deleted it. They
  are still undocumented in api.md; see Concerns.
* **`docs/handoff/SOURCE_CAP_LEDGER.md`** — `virtual_list.luau` MOVES to
  "Cleared the band" at **157,291** (measured last, after the final `stylua`, and
  re-recorded once more in `e0e8847` when the self-review fix added 988 chars).
  `row_actions.luau` re-recorded **192,979 → 194,118** with what spent it and a
  trigger still 1,882 away — a number *above* the recorded size, which is that
  document's own rule for a trigger that can still warn someone.

---

## 8. Gates

| gate | result |
|---|---|
| `python3 tools/check_gate_pins.py` | PASS — 260 file pins, 487 run strings parse |
| `python3 tools/check_manifest_integrity.py` | 1,518 suite greps, all anchored to the pass marker |
| `lune run tools/lune/check_theme_drift_cli` | clean — framework 47 files, examples 164 files |
| `lune run tools/lune/check_surface_ledger` | PASS |
| `lune run tools/lune/check_docs_cli` | PASS |
| `lune run tools/lune/check_example_drift_cli` | clean |
| `lune run tools/lune/check_flat_baseline` | PASS |
| `python3 tools/check_comment_codes.py` | PASS — 0 orphans (ceiling 0), 25/25 resolvable |
| `python3 tools/check_comment_codes.py --selftest` | SELFTEST PASS |
| `python3 tools/check_source_size.py` | **PASS** — nothing waived; 2 modules in the band (`presenter` 196,639; `row_actions` 194,118), both with rows |
| `python3 tools/check_types.py` | PASS |
| `stylua --check src/ tests/ examples/` | clean |

**Source size result:** `virtual_list.luau` **192,187 → 157,291**, i.e. it ends
**below its band** (42,709 to the write cap, 32,709 below the warning line), with
an honest re-recorded advisory row. `row_actions.luau` 192,979 → 194,118, inside
the band with a re-recorded row and an un-fired trigger.

---

## 9. Files changed

**Framework source:** `src/controls/virtual_list.luau`,
`src/controls/virtual_list_hosted.luau` (new),
`src/controls/gap_metric.luau` (new), `src/controls/virtual_grid.luau`,
`src/controls/row_actions.luau`.

**Examples:** `examples/gallery/scenarios/{row_actions,card_rail,virtual_grid,virtual_hgrid,sponsor_drop,sponsor_list}.luau`.

**Tests:** `tests/virtual_list_hosted_seam.spec.luau` (new),
`tests/collection_gap_tokens.spec.luau` (new),
`tests/collection_self_measure.spec.luau` (new), `tests/table.spec.luau`,
`tests/gallery_demo_picker.spec.luau`, `tests/theme_drift.spec.luau`,
`tests/conformance/controls_registry.luau`, `tests/lib/large_text_fixtures.luau`,
`tests/run.luau`.

**Tools/docs:** `tools/check_comment_codes.py`,
`docs/adr/ADR-0043-collections-measure-and-name.md` (new),
`docs/reference/api.md`, `docs/handoff/SOURCE_CAP_LEDGER.md`,
`artifacts/api-architecture-consistency/surface-ledger.md`.

**Rascal Rally:** `tests/facet_collection_extent_contract.spec.luau` (new),
`tests/run.luau`.

---

## 10. Self-review findings (reading my own diff)

1. **`crossExtent = "hug"` beside an authored `width` was two answers to one
   dim** — `"hug"` replaces the cross dim with `content`, so on a vertical list
   an authored `width` would have been *silently discarded*. That is
   constitution §4's exact prohibition and the class this control already refuses
   `cards` and `estimatedItemExtent` for. **Fixed in `83a7b81`** with a refusal
   naming both exits, and a case that asserts the PAIR (each alone still builds,
   and `"measured"` composes with a width because it changes no dim, so a refusal
   that had swallowed the whole field would redden it).
2. **Every new reactive node is scope-owned** — `measuredViewport`/`measuredCross`
   on `listScope`, the grid's on `scope`, the grid's two band-prop memos on
   `scope`. `gap_metric.reader` creates none at all.
3. **The grid's band props are resolved pixels, not the raw spec.** A metric name
   handed straight to `UI.Grid` would be resolved a *second* time, by the
   renderer, against whatever snapshot it holds, while the index resolved it
   against the environment's — two numbers for a field whose own refusal says
   "the canvas, the window and the mounted band all read the same number". A
   static number stays a static number, so a plain grid's band props are
   byte-identical.
4. **The live gap read cannot throw.** A theme swap that drops a key falls back
   to the default rather than raising inside a memo, because a swap must not be
   able to tear down a mounted surface. The construction-time check is what makes
   that fallback rare rather than routine.
5. **Missed:** the disposal audit on bug-C's newly-legible signal (§6).

---

## 11. Concerns

1. **`crossExtent = "measured"` has no consumer.** `"hug"` is what `card_rail`
   migrated to and is deeply exercised; `"measured"` ships with its own spec case
   and nothing else. The audit named both forms, so both were built, but by the
   "build waits for a consumer" doctrine (ADR-0024) `"measured"` is the one clause
   in this round that is a claim rather than a fix. It is ~10 lines on machinery
   `"hug"` needed anyway.
2. **`crossExtent`'s two words were an architectural fork.** The audit's shape
   line (`crossExtent = "hug" | "measured"`) and its heading ("cannot measure the
   box it was given, **on either axis**") admit at least two readings of
   `"measured"`. I took the one where both words answer "where does my cross
   extent come from" — the content, or the box I was given — because it makes the
   enum coherent and matches the heading. A reviewer who reads `"measured"` as
   "the two-pass form of hug, for content the solver cannot resolve in one pass"
   would get a different module. Flagged rather than silently chosen.
3. **The gap-token contract is deliberately stricter than `newTable`'s**, against
   the brief's "exactly matching". Argued in §3 and ADR-0043; `newTable` adopting
   `gap_metric` is recorded as owed.
4. **The bug-C observer leak.** My change made a signal legible and a subscriber
   appeared for it; I proved the geometry and did not audit the subscriber's
   disposal. The other lane's spec caught it (`8f174fe`). The lesson for me:
   **publishing a signal is a lifetime change, not only a value change** — the
   covering spec for a publication should assert a dispose-neutral counter, not
   only the number that became readable.
5. **`stylua src/ tests/ examples/` was run tree-wide** while another lane had
   uncommitted edits in `src/themes/`, `src/controls/table*` and
   `examples/reference/p3_sipworks/`. Formatting is idempotent and the repo
   requires it, and `commit_isolated` kept my commits to my own paths, so no
   content of theirs was committed by me — but their working tree may have been
   reformatted under them. Next time: format only my own paths.
6. **`chromeInsets`/`chromeOutsets` remain undocumented in api.md.** The audit
   asked for them to be documented *if* they stay public-reachable. They do (a
   snapshot field, read by an RR spec), but documenting the metrics-snapshot
   surface is a `src/themes/snapshot.luau`-adjacent job and that file is the other
   lane's this round. Recorded as owed rather than done.
7. **`viewportExtent = "auto"` silently measures 0** inside a hugging parent or a
   scrolling page's content. It is documented in api.md and in both fixtures that
   declined the migration, but it is a footgun a refusal cannot catch (the
   framework cannot know at construction what its ancestor will do). A diagnostic
   — "a list declared `auto` and measured 0 while its data is non-empty" — would
   be the honest next step and is not built.

---

## 12. What the Studio/device half owes

Nothing in this round was device-verified; everything above is headless.
Specifically owed to a Studio/device pass:

1. **`card_rail` at every reference package and text preference.** Its height was
   a hand-summed five-term number precisely because three of those terms were
   discovered by *device* rounds (12 px under Compact Pointer at the default
   preference, 16 px under Fantasy Ornate at every preference, 8 px for the
   scrollbar). `crossExtent = "hug"` claims the solver knows all five. The
   headless large-text matrix and five-view matrix are green, but the original
   defects were found on a device.
2. **`row_actions`' vlist pane on a landscape phone.** The literal `336` painted
   227-245 px past its own pane there; `"auto"` is the third answer to that
   surface and deserves the same viewport that found the first two.
3. **The two grid fixtures at ten-foot**, where the gap moved from a fixed 6 to a
   scaling `"xs"` — the whole point of the token, and the rung where a scaling
   gutter changes the lane arithmetic.
4. **An RR Studio canary in the same session that verifies the RR-side change**
   (ruling R5). The RR contract spec is headless; the game's racer list and
   sponsor table ride the extracted hosted half, and R5 says the canary is
   captured in the verifying session rather than pre-frozen.

### Explicitly owed, because the headless suite is structurally blind to it

Added after fix round 1's review, so the device half inherits a list rather than
a paragraph. Every item here is a claim this round made that **no headless
assertion can check**:

* **`card_rail`'s chrome terms.** `crossExtent = "hug"` claims the solver knows
  the five terms the fixture used to sum, and two of them were only ever
  discovered by a device round: `chromeInsets.panel` (**12px short under Compact
  Pointer, at the DEFAULT text preference**) and `chromeOutsets.panel` (**16px
  short under Fantasy Ornate, at every preference**). The headless matrices are
  green; they were green before those two rounds as well.
* **The first painted frame's card width** (fix-round finding B). The fix is
  asserted by a dump on the frame before any solve — a real first frame on a real
  device is where "paints nothing, then the right arrangement" is either invisible
  or a flash.
* **Nested-scroller materialization** (fix-round finding A). The diagnostic is
  proved headlessly, but the *cliff* it names is a frame-time fact: 400 rows
  mounted instead of 6 is a number only a device profile puts a cost on. Worth a
  deliberate probe on the one surface most at risk of the shape.
* **The two grid fixtures at ten-foot**, where the gutter moved from a fixed 6 to
  a scaling `"xs"` — already listed above, repeated here because it is the same
  class: a metric that scales only on a rung the headless sweep does not stand on.

---
---

# Fix round 1 — the review's four Important findings, the spec miss, and the minors

**Commits:** `b72b1b0` (the round), `0ffce6c` (the allowlist entry the first
commit's hunk filter could not reach).
**Measured suites, fresh content-pinned pair (`PIN_FACET 0ffce6ce`,
`PIN_RR 7a2b3a2e`):** Facet **7,135 passed / 0 failed** (7,124 → 7,135; **+11**,
all of them the new cases below), Rascal Rally **3,483 passed / 0 failed**
(unchanged — nothing in this round touched a game-side surface).

Three of the five substantive findings were defects in what the round SHIPPED.
One was in what it TAUGHT, and it is the one worth reading first.

## A (Important) — the teaching was backwards, and the real failure is silent

**What I wrote:** api.md said a `fill` inside a scrolling page's own content "has
nothing definite to fill", i.e. measures 0.

**What is true**, traced by the reviewer and then **measured** rather than
inferred:

* an ancestor that **HUGS** on that axis does give nothing: measured **0**,
  window **0**. That half was right, and it is the loud half — obvious the moment
  you look at it;
* an ancestor that is **UNBOUNDED** on that axis — which is exactly what another
  scroller's own scroll axis is — hands the collection its **whole canvas**.
  `solver.luau:595-597` answers a `fill` dim with its *content* contribution;
  `:1395-1396` and `:2467-2471` offer a scroll node's children `math.huge` on the
  axis it scrolls; `:1389-1412` sums those children into the scroll node's own
  content measure. **Measured headlessly: 400 rows of 40px inside a y-scrolling
  page reported a 16,000px "viewport" and mounted all 400 rows.**

That is strictly worse than measuring 0. Virtualization is **silently off** —
stable across every frame, and invisible to any assertion about correctness,
because every row is present and correctly placed. It is a performance cliff
wearing a correct-looking layout, and this round would have shipped it documented
as the *other* failure.

**The fix, and why it is a diagnostic rather than a clamp.** The detection is the
seed's own argument turned around: the seed is sound because *a box is never
bigger than the surface that contains it*, so a measured extent that **exceeds
the screen** is not a viewport, it is a canvas. Both collections report it in
`dump().diagnostics`, naming both numbers and the fix, **once per state change**
rather than once per refresh (`newLevelPicker` is the precedent for where a
control's diagnostics live; `solver.luau:562-570`'s "percent size on an unbounded
axis (inside scroll axis?)" is the house idiom for the message shape).

It does **not** clamp. Clamping the window to the screen while the solver still
paints the host at canvas height would leave the bottom of the painted box empty
of rows — a *visible* defect traded for an invisible one.

**Not attempted, as instructed:** a solver-side fix (refusing to offer `math.huge`
to a scroll host's own `fill` child, or answering a bounded contribution).
`src/layout/solver.luau` has an extraction owed to another round.
**Deferred note addressed to the G2+G10 round:** the list-side detector reports
the *symptom* and cannot prevent it. The structural question — *should a scroll
node offer `math.huge` to a child that is itself a scroll host?* — lives in
`solver.luau`'s measure and belongs with whoever opens that file next.

**Covering cases** (`tests/collection_self_measure.spec.luau`):
`a list nested in another scroller's SCROLL axis measures its whole canvas, and
says so` (pins 16,000 / 400 / the message text), `a grid says the same thing
about the same shape`, and a **negative control** — the same 400 rows in a real
pane, reporting nothing — so the pair cannot pass by the diagnostic always firing
or by 400 rows being the trigger.

## B (Important) — the seed is a window argument, not an arrangement

`card_rail` derives `perView` and the card width from `ctx.viewportIn/Now`, which
under `"auto"` is the **screen seed** at build. **Measured before the fix:** a
300px rail on an 800px screen resolved a **three-up arrangement of 261px cards**
on its first painted frame and a **one-up 270px carousel** on its second. Not a
size that popped — a different answer to the paradigm question, on a module whose
own header says in capitals that it must be asked about *the rail's own extent*.

**Fix:** `itemExtent = "cards"` seeds **0** instead of the screen. A 0 viewport
windows to nothing, so the rail paints **nothing** on the pre-measure frame and
the right arrangement on the next. The superset argument is preserved exactly
where it applies — every other list keeps the screen seed — and that narrowing is
its own **negative control** (`a plain list still seeds from the screen and
over-fills`, pinning `600|15`), without which the fix could have been a blanket
change nobody noticed.

**Covering case:** `a card rail paints NOTHING before it has been measured, then
the right arrangement`. It needed a new harness hook (`beforePresent`), because
the frame before any solve is the only place a seed can be observed at all.

## C (spec miss) — `chromeInsets` / `chromeOutsets` documented

They stay public-reachable (a snapshot field; RR's `facet_racer_list.spec` reads
one), so the brief's condition applies and I had recorded it as owed instead of
doing it. `docs/reference/api.md`'s `themes` section now carries them: a table
saying what each of the three is and who spends it (**`chromeBleed` corrected
while writing it — it is a whole-package NUMBER, the deepest shadow reach, not a
per-slot map**), `hasChromeInsets` as the guard to read first (every slot
publishes an entry now, so `next(chromeInsets)` answers yes on every package and
tells you nothing), the ten-foot exemption, and the part that matters: **prefer
not to read them at all**, with the card rail's own two device rounds as the
evidence for why a prediction assembled out of them goes stale.

## D (Important, partial) — the owed list, made explicit

No device work attempted. Report §12 gains a named sub-list of everything the
headless suite is **structurally** blind to: `card_rail`'s chrome-inset (12px,
Compact Pointer, default preference) and chrome-outset (16px, Fantasy Ornate,
every preference) terms; the first painted frame's card width; nested-scroller
materialization as a frame-time cost; and the two grid fixtures at ten-foot.

## Minors

* **(E)** `sponsor_list.luau`'s comment said `sponsor_drop` "migrated in the same
  round"; it migrated **and was reverted**. Corrected — and while correcting it,
  the comment now names what its *own* tree would have suffered, which is finding
  A's silent shape rather than the 0 it previously claimed.
* **(F)** ADR-0043 said `card_rail` lost "two constants"; it lost **one**
  (`RAIL_SLACK`). `PADDING` survives as the padding the Screen is given.
  Corrected in the durable copy.
* **(G)** The `crossExtent = "hug"` + `width` refusal is documented in api.md,
  including why `"measured"` deliberately composes with a width.
* **(H)** `gap_metric` treated `env == nil` as "headless → neutral", but
  `surfaceEnv.find` also answers nil for an **ambiguous** core. Both collections
  distinguish them now and call `surfaceEnv.resolve` — the framework's one
  spelling of that refusal — **only when the build actually needs the
  environment**. Four cases, including the narrowing (`a build that needs NO
  environment is still built on an ambiguous core`) and the other nil (`NOTHING
  published is still the headless case`), so the refusal cannot pass by having
  swallowed every ambiguous core.
* **(I)** Every `"hug"` case was `axis = "x"`. A **vertical** case joins them,
  where the cross axis is the WIDTH: the list is its row's width, not the 800px
  pane's, and the scroll axis is untouched.

## The brand guard (raised mid-round by the coordinator)

`check_brand_drift` was red, four hits mine — vendor prose in
`virtual_list_hosted.luau`. **The cause is the rule this round had already been
taught once:** the guard's allowlist carried
`("src/controls/virtual_list.luau", VENDOR, "extraction-locked…", "when the
virtual-list extraction lands")`. The extraction landed, so the sweep it was
deferring came due, and the prose that rode out of the locked file was live the
moment the split commit did — **the identical shape `check_comment_codes` bit
this round with, for the identical reason.**

So the six sites were **reworded**, the `virtual_list.luau` entry **removed**, and
`virtual_list_hosted.luau` deliberately **not added**: an extraction inherits none
of its host's exemptions, and adding the sibling would have re-created the debt
under a new name. The removal is recorded as a note beside the remaining entries
so the next reader sees why the list got shorter.

**A tooling trap earned in the process, and it is worth the line:** the delete was
silently dropped by `commit_isolated`'s hunk filter, because the marker I chose
came from the note I *added* and the deleting hunk contains only what was
*removed*. The explanation landed while the file was still on the list. Fixed in
`0ffce6c`. **A marker chosen from what you added cannot select a hunk whose whole
content is what you removed** — check the `drop` lines in the tool's own output,
which said so plainly.

## Two shared pins that moved with the code

* **`newVirtualGrid` joins the refusing controls** (`adaptive_defaults.spec`,
  six → seven) because finding H's fix gave it a refusal. It is the first entry
  there that refuses only *sometimes*: it adapts nothing, and what it needs an
  environment for is two **facts** (the snapshot a metric name resolves against,
  the screen `"auto"` seeds from), so it refuses on an ambiguous core and only
  when the build asks for one of them. Its api.md section documents the refusal,
  as that guard requires.
* **`dump().diagnostics` returns ONE shared frozen empty table.** A fresh `{}` per
  call made two dumps of one list compare unequal by *identity*, which is exactly
  what `virtual_list_axis.spec`'s "the deprecated aliases agree field for field"
  case asserts. Frozen because it is shared. Same idiom, same reason, as the
  hosted overlay's empty item list one file over.

## Gates after the fix round

`check_brand_drift` **PASS** (added to the list at the coordinator's request —
the five remaining hits are another lane's and were left alone), `check_gate_pins`
PASS, `check_manifest_integrity` 1,518 greps anchored, `check_source_size` PASS,
`check_comment_codes` PASS (0 orphans, 25/25), `check_types` PASS,
`check_registration` PASS (270 specs registered), theme drift clean,
`check_surface_ledger` PASS, `check_docs` PASS, `check_doc_style` PASS,
`stylua --check src/ tests/ examples/` clean.

## What this round changes about my own confidence

Finding A is the one to carry forward. The round's whole thesis is *stop
predicting a number the framework already holds* — and the feature that
implements it had a failure mode where the framework hands over a number that is
confidently, stably wrong, and I documented the wrong failure mode for it. The
headless suite could not have caught it: **every assertion about correctness
passes**. What caught it was someone tracing the dim resolution by hand. The
lesson I would write for myself: **when a feature's value is "the framework
answers instead of you", the review that matters is of what the framework answers
at the edges of its own contract** — not of whether the happy path measures right.
