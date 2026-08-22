# Task SCREEN-X report — the owed vocabulary extraction, then the sticky-tag fix

**Status: BOTH PHASES DONE, in the required order, as separate commits.** The
extraction landed first and behavior-neutral; the fix landed on top of it and is
proved RED-then-GREEN, headlessly and in a live Roblox engine. The sweep the
brief asked for is NOT a clean negative: it found **two more** live instances of
the same defect class, both from the other half of the same ADR-0038 rename.

| commit | subject |
|---|---|
| `a4e3224` | the words the adapter knows before its closure opens are their own file now |
| `b296b2e` | a prefix test that counts to five can never find a six-character prefix |
| `e4b0615` | the fixed removal loop runs its own probe, and the engine agrees |

---

## Phase 1 — the extraction, and its neutrality evidence

`src/client/screen_vocabulary.luau` (7,694 chars at the split; 9,077 after phase
2 added the tag predicate) takes exactly what the `SOURCE_CAP_LEDGER` row named:
`CLASS_TO_INSTANCE`, `TEXT_ALIGN_MAP`, `SCALE_MODE_ENGINE`,
`TINT_REPAINTING_PROPS`, the pure `toColor3` and `fontFaceFor`, the two
`FacetStage*` instance names, and the three stage/foreign helpers
(`writeStageProp`, `markStageDisposed`, `markForeignDisposed`).

`src/client/screen_target.luau` **193,795 -> 189,988** — out of the 190,000
warning band, and 4,012 clear of the 194,000 trigger that made the extraction
owed. Every block moved VERBATIM with the comment that explains it; the host
bound the same eleven local names off the sibling, so **no call site changed a
character**.

### Neutrality: a diff of verdicts, not a diff of counts

Both arms are content-pinned `mkpair` pairs, refs resolved at measurement time,
and they differ by exactly this one commit:

| arm | `PIN_FACET` | Facet | RascalRally |
|---|---|---|---|
| before | `cc430da` (= `a4e3224^`) | **7116 passed**, exit 0 | **3481 passed**, exit 0 |
| after | `a4e3224` | **7116 passed**, exit 0 | **3481 passed**, exit 0 |

The `✓`/`✗` line of every case, in suite order, extracted from both transcripts
and `diff`ed: **empty diff on both repositories** (7116 lines and 3481 lines
compared). Zero verdict changes — not "the same total", the same verdicts.

Evidence on disk (scratchpad, session-local):
`sx/pre_facet.txt` / `sx/post_facet.txt` / `sx/pre_rr.txt` / `sx/post_rr.txt`
and the four `.verdicts` extractions beside them; pairs `sx_pair_pre`,
`sx_pair_post`.

### What the extraction cost — the tax, and three pins nobody had counted

The ledger row predicted the `adapter_source` part. Four more readers had to be
taught, and two of them were **already half-blind before I moved anything**:

* `tests/lib/adapter_source.luau` — the new part. Its `live()` is what the
  source-scanning specs read; a sibling missing from that list makes every pin
  naming moved code quietly stop seeing it.
* `tools/lune/check_primitives.luau` (`ADAPTER_SOURCE`) and
  `tests/primitive_registration.spec.luau` read `CLASS_TO_INSTANCE` as TEXT, by
  path. Taught the new address — which is what that reader's own assert
  ("teach this reader about it rather than letting the check pass vacuously")
  asks of anyone who moves the table.
* `tools/lune/gate_manifest.luau` — one row greps
  `ScrollView = "ScrollingFrame"` by path. Re-pointed.
* `tests/stage.spec.luau`'s "the live adapter makes NO bespoke write to a
  seam-owned property" read `screen_target.luau` **alone**. It now reads
  `adapter_source.live()`. That is strictly stronger and the reason it had to
  change is the reason it should have been written that way: a pin that reads
  one file of a six-file adapter was blind to the other five.
* `tests/control_feedback.spec.luau` reads the vocabulary for
  `TextField = "TextBox"` and keeps reading `screen_target.luau` for the
  mirror's indentation — two facts, two files now.

The ledger row moved to **"Cleared the band"**, re-recorded, with the
uncomfortable number stated plainly: twelve characters of daylight under
190,000, so the row STAYS and the next trigger is 192,000.

---

## Phase 2 — the fix

### RED, on the pre-fix tree

New spec `tests/prefix_tests.spec.luau`, run against the pair pinned at
`a4e3224` (post-extraction, pre-fix):

```
$ cd <pair>/GameStudio/ui/Facet && lune run tests/_sx_red     # registers only this spec
a prefix test cannot disagree with the prefix it tests (ADR-0038 fallout)
  ✗ no comparison in src/, tools/ or examples/ counts differently from its own literal
      expected violations:
      examples/gallery/scenarios/runner.luau:687 compares 6 characters against "Facet" (#5)
      src/client/screen_target.luau:474 compares 5 characters against "facet-" (#6)
      tools/studio/device_matrix.luau:796 compares 6 characters against "Facet" (#5) to be violations:
  ✓ the scan BITES — a synthetic mismatch is reported with both numbers
the adapter's facet-* tag ownership is one named fact (SCREEN-X)
  ✗ the removal loop asks a NAMED prefix and derives the length from it
      expected the adapter names its tag prefix: false to be ... true
  ✗ every tag the classifier can mint is one that predicate claims
      expected nil to be string
3 failed, 1 passed
```

**Why that is the expected failure.** `string.sub(tag, 1, 5)` is `"facet"`,
which is never `"facet-"`, so the comparison is CONSTANT and the tag-REMOVAL
half of `syncTags` — the one function that owns every `facet-*` tag on an
instance — has been dead code since `36d1883`. The case that names the adapter's
prefix fails because pre-fix there is no named prefix to find; the cross-module
case fails on the same nil. The one case that PASSES is the negative control,
which is the point: the scanner bites before the fix as well as after it.

### GREEN

```
  ✓ no comparison in src/, tools/ or examples/ counts differently from its own literal
  ✓ the scan BITES — a synthetic mismatch is reported with both numbers
  ✓ the removal loop asks a NAMED prefix and derives the length from it
  ✓ every tag the classifier can mint is one that predicate claims
4 passed
```

Full suite, work copy = pair at `a4e3224` + the phase-2 diff:
**Facet 7116 -> 7120** and the verdict diff is exactly those four added lines,
nothing else moved. **RascalRally 3481 -> 3481**, unchanged.

### The fix itself, and why it is not the one-character one

`5 -> 6` is correct and would have been correct on 2026-08-18 too — which is the
problem: a hand-counted length beside a literal is one fact stored twice.
`src/client/screen_vocabulary.luau` now holds

```lua
local TAG_PREFIX = "facet-"

local function ownsTag(tag: string): boolean
	return string.sub(tag, 1, #TAG_PREFIX) == TAG_PREFIX
end
```

and `syncTags` asks `screen_vocabulary.ownsTag(tag)`. The length is read off the
literal, so a future rename can change the string and cannot desynchronise the
number. This is not a new idiom: `screen_chrome.luau:475` was already doing
`string.sub(existing, 1, #prefix) == prefix` with
`chrome_slots.ICON_TAG_PREFIX`, one file over.

The predicate lives in `screen_vocabulary` and **not** in `sheet_model`, which
is the tag AUTHORITY and would otherwise be the better home. `src/tokens/` is
lane R1a's in this campaign and the brief says stay out. Flagged as a concern
below.

The call is shorter than the `string.sub` it replaced, so `screen_target.luau`
went **189,988 -> 189,985** and stayed out of the warning band. No comment was
cut to achieve that: the explanation lives with the fact, in the sibling, and
the call site reads as prose.

### Live engine proof (`e4b0615`)

`artifacts/framework-gaps-phase2/screenx-tag-removal-live.txt`. Studio EDIT
datamodel, `Facet-Showcase.rbxl`, source injected via `studio_sync` +
`tools/studio/inject.luau` (`patched 36, created 2, staleModules 0, refused []`
— nothing over the Source cap, so nothing is evidence about older code).

The session was a RED witness when it was opened: `len=193795`,
`string.sub(tag, 1, 5)` present, no `screen_vocabulary`. After the inject:
`189985` + `9077`, old form absent, `ownsTag` call present.

Then the FIX-SHOW round's **clean-room adapter probe re-run line for line** —
the SHIPPED adapter driving its own `syncTags`, in an Edit datamodel because
`opts.parent` takes a Folder instead of reaching for `Players.LocalPlayer`:

```
create:            [facet-interactive,facet-surface-control]
selected=true:     [facet-interactive,facet-selected,facet-surface-control]
selected=false:    [facet-interactive,facet-surface-control]     <- RED kept facet-selected
surface=plain:     []                                            <- RED kept selected + surface-control
surface=accent:    [facet-interactive,facet-surface-accent]      <- RED carried TWO surface tags
role=destructive:  [facet-interactive,facet-role-destructive,facet-surface-accent]
role=default:      [facet-interactive,facet-surface-accent]      <- RED kept role-destructive
class=TextButton
```

`surface = "plain"` leaving NO tags is exactly Bugs A and B: `picker.luau:552`
declares that on every segment while an indicator slides, and it is the same
pair of tags the bug round removed BY HAND to produce
`bugAB-green-tags-removed.png`. The chain from that capture to this code path is
closed. Separately, on a real `Frame` with a real `CollectionService`: three
tags dressed, three removed, `left: []`, and **the old five-character test
claims 0 of the 3** — the dead branch, executed on the engine.

No pixels are claimed. See "owed to the director".

---

## The sweep — NOT a clean negative

`tests/prefix_tests.spec.luau` is the sweep, mechanised: it walks every `.luau`
file under `src/`, `tools/` and `examples/` (**392 files, 28 prefix comparisons
today**), reads both operand orders, skips comment lines, and fails any
comparison where `N ~= #literal`. It found two more, and they are the OTHER half
of the same rename — ADR-0038 also renamed the roots `LuauUI_<id>` ->
`Facet_<id>`, and `"LuauUI"` is six characters where `"Facet"` is five:

**1. `tools/studio/device_matrix.luau:796** — `string.sub(tree.root, 1, 6) ~=
"Facet"` was constantly TRUE, so **every** tree was skipped and `judgedTrees`
was always 0. The five-view device matrix has been unable to judge anything
since 2026-08-18. It never shipped a lie: its own anti-vacuity clause
(`judgedTrees > 0`) turns that into a red row. All 19 stored matrix artifacts
record `judgedTrees: 1` and are pre-rename.

**2. `examples/gallery/scenarios/runner.luau:687** — `string.sub(gui.Name, 1, 6)
== "Facet"` was constantly FALSE, so the M3 instance census filed Facet's own
`Facet_<id>` roots under `foreign` and reported ZERO GuiObjects for the
framework. **This one DID ship numbers**, and the artifacts prove both sides of
the rename:

* pre-rename `artifacts/performance-stress-places/studio/pl9-row3-luauui-1.json`
  — `screenGuis 1, guiObjects 470`, `foreign.roots = [Freecam, Chat, BubbleChat]`;
* post-rename, **seven** RC-requalification rows — `rc-requal-row02`, `-row04`,
  `-row05`, `-row06`, `-row11`, `-row12`, `-row13` — all
  `screenGuis 0, guiObjects 0` with `Facet_PerfWorkload` sitting in
  `foreign.roots`.

Both sites now name a `Facet_` prefix once (which also covers the billboard
target's `Facet_BB_<id>`) and measure it with `#`. Both carry a comment naming
the date, the cause and this spec.

`git log -S 'string.sub(gui.Name, 1, 6)'` and `git log -S 'string.sub(tag, 1, 5)'`
each return only the initial commit: the lengths were never touched, in any of
the three.

Also swept, clean: no `"luau-"` prefix test survives anywhere in `src/`,
`tools/`, `examples/` or `tests/` (the only `luau-` strings left are
`tools/check_types.py`'s `luau-lsp` binary name and `check_brand_drift.py`'s own
synthetic mutation fixture). No `string.find(s, "^facet-")`-style prefix logic
exists to have the same problem. The other 25 comparisons in the tree all count
correctly (`"auto-"` 5, `"colors."` 7, `"Gamepad"` 7, `"@self/"` 6,
`"examples/"` 9, and so on).

---

## Capture re-baselines

**None were required, and that is a finding rather than an omission.**

* **No pixel goldens exist.** Nothing in `tools/` compares a PNG.
  `check_device_captures.py` reads `artifacts/cross-platform-proof/device/
  studio-emulated.json` for metric-ledger completeness, not images.
* **The device-matrix artifacts did not freeze the broken behavior.** All 19
  rows carrying `judgedTrees` record `1`, and every one predates the rename. The
  anti-vacuity clause means a post-rename run reddens rather than passing over
  an empty set, so there is no stale green to re-baseline.
* **The seven RC-requalification perf rows above DO carry a wrong number** — a
  zero Facet instance census — and they are Studio captures. I have not touched
  them: re-baselining them means re-running the performance lab live, which is a
  device/session round, not an edit. **Recorded as owed** rather than
  regenerated or quietly left unremarked. No gate reads those fields
  (`check_perf_gate_evidence.py` reads the PRE-rename `luauui` capture, whose
  `ownGuiObjects > 0` assertion is satisfied by real data).
* **`artifacts/framework-gaps-phase2/bugAB-*.png` stay exactly as they are.**
  They are the RED/GREEN evidence pair of the round that found the defect; the
  RED one is supposed to show the broken paint.

One artifact was ADDED, not re-baselined:
`artifacts/framework-gaps-phase2/screenx-tag-removal-live.txt`, the live GREEN
half of that same A/B (`e4b0615`).

---

## RascalRally lockstep

**No RR edit needed, and here is the grep.** RR names no `facet-*` classification
tag anywhere: `grep -rn '"facet-\|`facet-' src tests` in
`games/RascalRally/code` returns nine hits and every one is a dump SCHEMA string
(`facet-focus-order/1`, `facet-rating-dump/1`, `facet-anchored-dump/1`,
`facet-tab_view-dump/1`, `facet-picker-dump/1`), none of which this change
touches. RR's own `CollectionService` use is entirely `KartSim.TAG`
(`"RascalKart"`) on kart chassis — server-side gameplay, no Facet tag, no
prefix test. Nothing in RR relies on tag stickiness.

RR moves anyway in the measurement: both suites ran from the same `mkpair` pair
at every arm, and RR is green and unchanged in verdicts at each.

---

## Files changed

**Phase 1 (`a4e3224`)** — `src/client/screen_vocabulary.luau` (new),
`src/client/screen_target.luau`, `tests/lib/adapter_source.luau`,
`tests/stage.spec.luau`, `tests/control_feedback.spec.luau`,
`tests/primitive_registration.spec.luau`, `tools/lune/check_primitives.luau`,
`tools/lune/gate_manifest.luau`, `docs/handoff/SOURCE_CAP_LEDGER.md`.

**Phase 2 (`b296b2e`)** — `src/client/screen_vocabulary.luau`,
`src/client/screen_target.luau`, `tools/studio/device_matrix.luau`,
`examples/gallery/scenarios/runner.luau`, `tests/prefix_tests.spec.luau` (new),
`tests/run.luau`, `docs/handoff/SOURCE_CAP_LEDGER.md`.

**Evidence (`e4b0615`)** —
`artifacts/framework-gaps-phase2/screenx-tag-removal-live.txt` (new).

Every commit through `python3 tools/commit_isolated.py`; nothing published or
pushed. Places rebuilt at the end: `tools/build_places.sh`, 15 files, from
`f70250e+dirty` (the tree also carries the other lanes' in-flight work — the
build stamp says so).

---

## Suite tails, BOTH repositories

Final pair, `PIN_FACET b296b2e`, `PIN_RR 7a2b3a2`:

```
GameStudio/ui/Facet         $ ./run-tests.sh      -> 7123 passed   (exit 0)
games/RascalRally/code      $ lune run tests/run  -> 3483 passed   (exit 0)
```

(The absolute numbers are above the single-variable arms because other lanes
landed commits between the arms and the final pair. The single-variable
measurements are the ones in the two phase sections: 7116/7116 + 3481/3481 with
an empty verdict diff for the extraction, and 7116 -> 7120 / 3481 -> 3481 for the
fix.)

---

## Gate + source-size results

All run in the working tree after phase 2 landed:

| check | result |
|---|---|
| `tools/check_source_size.py` | **PASS** — nothing at/over 200,000; only `presenter.luau` (196,639) and `row_actions.luau` (194,118) inside the band, both with rows. `screen_target.luau` is out of the band at 189,985 |
| `tools/check_gate_pins.py` | **PASS** — 260 gate file pins match the tree, 487 run strings parse |
| `tools/check_manifest_integrity.py --transcript` | **PASS** — 1518 suite greps, all anchored to the pass marker, all 1518 matched a green transcript |
| `tools/check_comment_codes.py` (purity/comment lint) | **PASS** — 0 orphans (ceiling 0), 25 resolvable (ceiling 25). Re-run AFTER the split commit landed, because `git ls-files` cannot see a brand-new module before then |
| `tools/check_library_purity.py` | **PASS** |
| `tools/check_input_authority.py` | **PASS** |
| `lune run tools/lune/check_boundary` | **PASS** (161 src files, 413 consumer files) |
| `lune run tools/lune/check_primitives` | **PASS** (reading the new address) |
| `lune run tools/lune/check_prop_parity` | **PASS** |
| `lune run tools/lune/check_surface_ledger` | **PASS** |
| `lune run tools/lune/check_theme_drift_cli` | **PASS** |
| `lune run tools/lune/check_flat_baseline` | **PASS** — 1461 flat nodes byte-compared, no new deltas |
| `stylua --check` | clean on every changed file |

---

## Self-review

**What I would challenge if I were reviewing this.**

1. *The extraction changed two specs' reading habits — is that neutrality?* It
   is a change to what a pin READS, not to what it asserts, and both changes
   strengthen the pin (`stage.spec` went from one file to all six;
   `control_feedback.spec` now reads the file the fact lives in). The proof that
   nothing else moved is the empty verdict diff, which covers both specs' cases.
2. *The RED is partly "the function does not exist yet".* One of the three
   failing cases is the repository-wide scan, which fails on the DEFECT and
   names all three sites by file and line — that is the real red. The other two
   fail on the absent named prefix, which is ordinary TDD. The scan's negative
   control passes in both arms, so the instrument is proved independently of the
   fix.
3. *A source-scanning spec is a weak test of a behavior.* Agreed, and it is why
   the behavioral half went to a live engine instead: `e4b0615` drives the
   SHIPPED adapter's own `syncTags` and reads the tags off a real instance. The
   headless suite carries the invariant; the artifact carries the behavior.
4. *Is `TAG_PREFIX` in the right module?* No — `sheet_model` mints the tags and
   is the honest authority, and it is also pure, which would have bought a fully
   headless behavioral test. `src/tokens/` is another lane's this round. Booked
   below.
5. *Did I gold-plate the scan by including `examples/`?* It is what found the
   `runner.luau` census defect and the seven wrong perf captures, so no. It does
   mean another lane can redden my spec by writing a mismatched prefix test —
   which is the invariant doing its job, and the failure message names the file
   and both numbers.

**Simplicity ladder.** The fix is one call to a two-line predicate reusing an
idiom already present in a sibling. The extraction is a move, not a rewrite:
zero call sites changed. The sweep and the fix's regression pin are the SAME
test, which is the "invariant over spot checks" standard rather than three
separate greps.

---

## Concerns

1. **`TAG_PREFIX`/`ownsTag` should probably live in `src/tokens/sheet_model.luau`,
   not in `screen_vocabulary`.** `sheet_model.classifyTags` mints every tag; the
   predicate that claims them belongs beside it, and `sheet_model` is PURE, so
   the ownership test could then be driven headlessly instead of read as text.
   I kept out of `src/tokens/` because the brief assigns it to lane R1a. **A
   follow-up move is a one-line relocation plus one require** and the spec's
   cross-module case already reads the prefix out of the adapter source, so it
   survives the move unchanged.
2. **`screen_target.luau` is 15 characters under the 190,000 band.** It will be
   inside it again on the next comment anyone writes. The ledger row stays and
   says so; the next trigger is 192,000; the next seam (`setProp`'s per-class
   chain, which needs a parameter object first) is named in the row.
3. **Seven RC-requalification perf rows carry a zero Facet instance census.**
   The code is fixed; the captures are not, and they cannot be without a live
   perf-lab session. Anyone reading `guiObjects` in
   `artifacts/performance-stress-places/studio/rc-requal-row*.json` today is
   reading a measurement artifact of this bug.
4. **The five-view device matrix has judged nothing since 2026-08-18.** Its
   anti-vacuity clause means no false green shipped, but any matrix row closed
   in that window closed on a red or was not run. Worth a look by whoever owns
   the matrix rows.
5. **Another lane may write a mismatched prefix test and redden
   `prefix_tests.spec`.** By design. The message names the file, the line, the
   count and the literal.
6. **`examples/gallery/scenarios/runner.luau` is shared gallery infrastructure**,
   not one of the scenario files lane R1b owns, but it is in the same tree. The
   commit touches only the two hunks (`FACET_ROOT_PREFIX` + the M3 census line)
   and went through `commit_isolated`.

---

## What still owes a director live re-test

1. **The `tab-view` demo, on glass** — the app bar's underline indicator and the
   page bar's pill, at rest AND mid-flight, in a Play session. This is the one
   the FIX-SHOW round booked and it is still open: my proof reaches the TAG
   layer in a live engine (Edit datamodel, shipped adapter, real
   `CollectionService`) and stops there. `tools/build_places.sh` has been run,
   so `examples/places/Facet-Showcase.rbxl` carries this code.
2. **Anything else the sticky tags were covering.** The defect was framework-wide
   — selection, hover eligibility, button role, toggle value, error state, shape,
   typography role and skinned-slot tags were ALL sticky for four days. Every one
   of them now un-applies, which changes paint wherever removal was intended.
   The tab indicator is the one that was reported; a sweep of the showcase's
   other demos in the same session is cheap insurance.
3. **A performance-lab re-capture** if anyone wants the seven RC-requalification
   rows to carry a true instance census.
4. **A device-matrix run** to confirm `judgedTrees > 0` now, which is the first
   honest matrix result since the rename.
