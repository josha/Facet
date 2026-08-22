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

---

# Fix round 1 — the four Important findings, and the four minors

Appended 2026-08-22, after "Approved with findings". Everything below is
additional to the record above; where it CORRECTS something above, it says so.

## Important 1 — `check_brand_drift` was RED and absent from my gate table

**True, and the omission is the worse half.** I ran twelve gates and did not run
this one, so the table above is incomplete rather than wrong — which is the kind
of gap that makes a gate table untrustworthy. It is in the table now, and seven
of the eleven violations were this round's prose.

**Fixed by allowlisting, not by rewording**, because the checker's own doctrine
(the ADR-0038 and `gate_manifest` entries) is that *a comment which may not name
the retired vocabulary cannot record that it moved* — and every one of those
seven lines exists precisely to record which rename broke what.

Four entries, all against ONE new narrow pattern, `RENAME_ARROW`: a retired name,
an arrow, the current name. **Scoped to the sentence, not to the file**, which is
the R5 review §2-1 lesson these entries would otherwise have repeated. Proved
non-tautological by planting an ordinary `LuauUI` mention in `tests/run.luau`
and watching the checker fail on it:

```
check_brand_drift: FAIL — 1 old-brand match(es) outside the allowlist:
  tests/run.luau:74: -- PLANTED: an ordinary LuauUI mention, nothing to do with a rename
```

...then PASS with it removed. Two more entries cover the new handoff register
(one for the rename arrow, one for its citation of the pre-rename capture
`pl9-row3-luauui-1.json` by its real filename).

**A trap worth recording: `check_brand_drift` reads `git ls-files`,** exactly
like `check_comment_codes`, so `src/render/tag_sync.luau` was INVISIBLE to it
while untracked and would have gone red on the commit that added it. I
pre-flighted every new/edited file by importing the checker and calling
`scan_file` directly, which is how those entries exist before the commit rather
than after it. The other four hits (`virtual_list_hosted.luau`, "iOS parity")
were another lane's and are untouched.

## Important 2 — no automated behavioural regression for tag removal

**The strongest finding of the review, and it was right.** What shipped was a
source scan plus a hand-driven Studio artifact; neither would fail if the
predicate regressed in a way the text still satisfied.

The reviewer's diagnosis was the important part: **`tests/lib/fake_target.luau`
modelled no tags at all.** Tags are the ONLY channel by which Facet's surfaces,
states and roles reach native paint, and the headless twin had no witness for
any of it — which is why a dead removal loop survived 7,116 green cases and had
to be found by looking at a screen.

**What I built, and one correction to the prescription.** The review said
"extract it beside `ownsTag` in `screen_vocabulary`". That module CANNOT be
required headlessly — it touches `Enum.TextXAlignment` at module scope, so a
spec loading it dies with `attempt to index nil with 'TextXAlignment'` (measured,
not assumed), and a ruling only the engine-side adapter can execute is a ruling
no spec can drive. So the pure half went one level out instead, into
**`src/render/tag_sync.luau`** — no requires at all — beside `render/authority`,
`render/stage_content` and `render/foreign_content`, which exist for exactly this
reason ("the PURE rulings the seam is made of ... shared with the headless twin
so the two adapters cannot disagree"). `TAG_PREFIX`/`ownsTag` moved OUT of
`screen_vocabulary` with it; there is no second copy anywhere.

It carries `PREFIX`, `owns(tag)` and `diff(current, desired) -> {add, remove}`,
and the adapter's `syncTags` is now:

```lua
local plan = tag_sync.diff(CollectionService:GetTags(instance), desired)
for _, tag in plan.remove do CollectionService:RemoveTag(instance, tag) end
for _, tag in plan.add do CollectionService:AddTag(instance, tag) end
```

which is also one fewer engine round-trip per tag (the old add loop asked
`HasTag` per desired tag; the plan already knows).

**`fake_target` gained the tag mirror.** The DECISION is not mirrored — both
targets call the same module — only the narrow bookkeeping around it: the
class default a `Button`/`Toggle` takes at create, and the three prop writes that
re-classify (`surface`, `role`, `selected`, mirroring
`screen_paint.applySurfaceNative` and `setProp`'s own branches). It is
deliberately not the adapter's whole classification surface, it says so in the
file, and a state it does not model produces no tag rather than a wrong one.
`adapter.tagsOf(path)` is the reader.

**RED-FIRST, twice.** First against the fake as it was:

```
tag_sync: mounted, state changed, tag removed
  ✗ a Button that stops being selected LOSES facet-selected
      tests/tag_sync.spec:104: attempt to call a nil value      <- there is no tagsOf
  ✗ a segment declared surface=plain ends up with NO tags — Bugs A and B
  ✗ a surface change swaps the surface tag rather than accumulating one
  ✗ a destructive Button returning to the default role LOSES the role tag
4 failed, 3 passed
```

Then, with the mirror in place and green, the mutation that matters — the ADR-0038
defect restored inside `tag_sync.owns` (`#tag_sync.PREFIX` -> `5`):

```
  ✗ owns a tag by the LENGTH OF ITS OWN PREFIX ...       expected false to be true
  ✗ a state change produces a REMOVAL ...                expected false to be true
  ✗ never removes a tag the game owns                    expected  to be facet-selected
  ✗ a Button that stops being selected LOSES facet-selected      expected true to be false
  ✗ a segment declared surface=plain ends up with NO tags — Bugs A and B
        expected facet-interactive,facet-surface-control to be
  ✗ a surface change swaps the surface tag rather than accumulating one
  ✗ a destructive Button returning to the default role LOSES the role tag
7 failed, 0 passed
```

Every case bites, and the `surface=plain` message is the shipped defect in one
line: `facet-interactive,facet-surface-control` where the answer is nothing at
all. `tests/tag_sync.spec.luau`, 7 cases, registered in `tests/run.luau`.

**Three existing specs bound a text window on the removal loop's own `for`** and
had to move to the new terminator (`local plan = tag_sync.diff(`):
`theme_layer_application.spec` (found by the suite, not by me guessing),
`native_style_scenario.spec` (two sites) and `theme_value_displays.spec`. Each is
the same region it always was.

## Important 3 — the owed work filed in the repo, and the artifacts marked

**`docs/handoff/SCREEN-X-OWED-LIVE-WORK.md`** — in the house style, with all four
items (tab-view on glass; the showcase sweep; the perf-lab re-capture; the
device-matrix run), the commands, what to compare against, and a closing section
of what is already done so nobody redoes it.

**The captures are marked in band.** All thirteen
`artifacts/performance-stress-places/studio/rc-requal-row*.json` rows — not the
seven I reported, THIRTEEN: every row reports `guiObjects 0 / screenGuis 0`, and
the seven with `Facet_PerfWorkload` in `foreign.roots` are merely the ones where
it is provable rather than the only ones affected. That is a correction to my
first report, which under-counted by calling the provable subset the whole set.
Each row now carries two ADDITIVE keys — `censusCorrection` (what is invalid, what
still stands, where the fix is) and `censusCorrectionCertainty` (`PROVEN` vs
`UNVERIFIABLE`, per row). **Nothing measured was altered and nothing was
reformatted**: the keys are spliced after the opening brace, so the diff is
`13 files changed, 13 insertions(+), 13 deletions(-)` and every other byte is the
byte that was captured. `check_perf_captures`, `check_perf_metrics` and
`check_perf_gate_evidence studio` all still pass.

`artifacts/performance-stress-places/studio-capture-2026-08-21.md` gains a
correction block above its headline table, and its row-01 `0 GuiObjects` headline
is struck through in place. The point the block makes is the one the reviewer was
after: the zero *might* also be true for an idle baseline, and **nothing in the
document could tell you which** — that is the defect, not the number.

## Important 4 — the capture survey, completed, and it changed my answer

My "none required" argument covered goldens and gate pins and never looked at the
pictures. Doing so falsified my own reasoning.

**The reasoning I had was wrong in a specific way.** I would have argued that a
static or first-mount capture is safe because the defect only bites after a state
change. It does not: a `Button` takes `facet-surface-control` as its CLASS
DEFAULT at create, so an authored `surface = "plain"` is a tag REMOVAL **on the
first mount**. `picker.luau:552` declares exactly that on every segment whenever
an indicator slides, and `automatic` resolves to `pill` for every non-inline
picker. So a first-mount capture of any sliding picker carries the defect.

**Four captures do.** `tv_corners_rounded.png`, `tv_corners_zoom_compare.png`,
`tv-paint-final-2026-08-21.png`, `console-tenfoot-2026-08-21.png`: the Quality
segmented picker shows three identical opaque plates and no pill, the icon-segment
row and the vertical rail the same — while `tv-paint-final`'s own caption reads
*"Selected: browse — the pill and the rail share this one signal"* — and the
All controls / Settings tab strip shows two plates and no underline. It is the
`tab-view` defect, in a frame nobody was looking at it in.

**ADR-0040 row B-17 is NOT invalidated, and I checked rather than assumed.** Its
claim is radii 12→18 on `panel` and 8→12 on `control` plus strokes 1→1.5, and
those numbers are read off the settings PANEL and the `–`/`+` stepper CONTROLS —
surfaces whose tags are class defaults nothing ever asked to remove, so an
additive-only bug cannot touch them. The row keeps its evidence and gains one
clause pointing at the correction; the IMAGES need a re-capture, booked as item 4
of the handoff register.

The other ten are unaffected, argued per family in
`artifacts/release-candidate-review/captures/CENSUS-AND-TAG-CORRECTIONS-2026-08-22.md`:
the `bugAB-*` pair IS the defect's evidence and stays exactly as it is; the
`bugC-*` pair measures a pixel gutter no tag decides; the five `plate_design`/
`plate-b-live` frames contain no picker, tab strip or selection indicator at all,
so the only visible consequence of a failed removal has nothing to hide behind;
and `rr-canary-2026-08-22.png` was taken for zero-box TEXT geometry. No image was
edited — they are dated evidence — and the note travels beside them.

## Minor 5 — the method form `x:sub(1, N)`

**Covered, not just stated.** The scanner reads four spellings now
(`string.sub(...)` and `x:sub(...)`, each in either operand order). The two live
sites (`roblox_env.luau:413` `"Gamepad"`, `studio_sync.luau:184` `"/file/"`) are
correct and are now counted rather than invisible. The mirrored method pattern
needed a full receiver class (`[%w_%.%[%]%(%)]*`) rather than the single character
the forward form gets away with — caught by the negative control expecting six
considered comparisons and getting five.

## Minor 6 — the comment skip was line-comments only

**Fixed, and it was not hypothetical.** The moment the ruling moved into
`src/render/tag_sync.luau`, whose header QUOTES `string.sub(tag, 1, 5) == "facet-"`
to explain the defect, the live scan reported the module's own explanation as a
violation:

```
✗ no comparison in src/, tools/ or examples/ counts differently from its own literal
    expected violations:
    src/render/tag_sync.luau:16 compares 5 characters against "facet-" (#6) to be violations:
```

`codeOf(line, inBlock)` now strips long-bracket comments across lines, levels
included (`--[=[`). A `--` inside a string literal is still not handled; that is
stated in the spec's header as a hole with a number beside it rather than a
silent gap. The negative control gained a two-line block comment quoting the bad
form in both spellings, and asserts neither is counted.

**And a small self-inflicted lesson**: my first draft of that header contained
the literal `]]` inside its own `--[[` block and closed the comment early.
Fifty parse errors, one cause.

## Minor 7 — commit `a4e3224`'s message quotes superseded numbers

**Correct, and the correction belongs here because a commit message cannot be
rewritten.** `a4e3224`'s body says "Facet 7114 passed before and after,
RascalRally 3470 before and after". Those are the numbers from my FIRST
neutrality arm — a pair pinned at `15fe21d` with the extraction applied by hand —
which I then superseded with the rigorous form: two `mkpair` pairs at `a4e3224^`
and `a4e3224`, **7116/7116 and 3481/3481, verdict lists byte-identical**. The
claim ("zero verdict changes") is unchanged and both arms support it; only the
absolute counts moved, because other lanes landed commits between the two
measurements. **The report above is authoritative; the commit body is stale on
those two numbers.**

## Minor 8 — Concern #1 under-counted the relocation's cost

**Correct, and the relocation happened this round anyway, so the concern is
closed rather than corrected.** I wrote that moving the predicate to its proper
home would cost "a one-line relocation plus one require"; the reviewer counted
three spec pins reading the adapter source. The real count came in higher still:
moving it to `render/tag_sync` touched **two adapter files, four spec files**
(`prefix_tests` ×3 pins, plus the three window-terminator specs above) **and the
ledger row**. The lesson is the reviewer's, not mine: a predicate read as TEXT by
source-scanning pins is never a one-line move, and estimating it as one is how a
"cheap follow-up" becomes a round.

It is also now in a BETTER home than the one I named: `sheet_model` would have
been the tag authority but is `src/tokens/`, another lane's this round, and
`render/` is where this repository already puts a pure ruling two adapters share.

## Files changed in this round

`src/render/tag_sync.luau` (new), `src/client/screen_target.luau`,
`src/client/screen_vocabulary.luau`, `tests/lib/fake_target.luau`,
`tests/tag_sync.spec.luau` (new), `tests/prefix_tests.spec.luau`,
`tests/run.luau`, `tests/theme_layer_application.spec.luau`,
`tests/native_style_scenario.spec.luau`, `tests/theme_value_displays.spec.luau`,
`tools/check_brand_drift.py`, `docs/handoff/SCREEN-X-OWED-LIVE-WORK.md` (new),
`docs/handoff/SOURCE_CAP_LEDGER.md`,
`docs/adr/ADR-0040-unreleased-breaking-changes.md`,
`artifacts/release-candidate-review/captures/CENSUS-AND-TAG-CORRECTIONS-2026-08-22.md`
(new), `artifacts/performance-stress-places/studio-capture-2026-08-21.md`,
`artifacts/performance-stress-places/studio/rc-requal-row01..13-*.json`.

## The ledger row went BACK into the band, on purpose

`src/client/screen_target.luau` **189,985 -> 190,181**, 181 characters over the
190,000 line, because the require and its three-line comment came back in when
the ruling left. **I did not trim the comment to get under it.** The band is not
a failure state — it is a requirement to hold a current seam analysis and a live
trigger, and this row holds both, re-read twice in one round. Trimming an
explanation to move a byte counter is the behaviour the ledger's own header warns
about. The row moved back to "The band" with that entry; the trigger stays
192,000, 1,819 characters away.

## Gate results — the full table this time, `check_brand_drift` included

Run in the working tree after both fix-round commits landed:

| check | result |
|---|---|
| `tools/check_brand_drift.py` | **PASS** — the gate that was red, with four sentence-scoped entries and a planted-mention proof that they are not file-wide |
| `tools/check_source_size.py` | **PASS** — `screen_target.luau` 190,181, inside the band with a re-read row; nothing at or over the cap |
| `tools/check_gate_pins.py` | **PASS** — 260 file pins, 487 run strings parse |
| `tools/check_comment_codes.py` | **PASS** — 0 orphans (ceiling 0), 25 resolvable (ceiling 25); re-run AFTER the commit, because `git ls-files` cannot see a new module before it lands |
| `tools/check_library_purity.py` | **PASS** |
| `tools/check_input_authority.py` | **PASS** |
| `tools/check_doc_style.py` | **PASS** — 23 documents |
| `tools/check_perf_captures.py` | **PASS** — 31 rows admissible, with the correction keys in place |
| `tools/check_perf_metrics.py` | **PASS** — 100 headless records carry all 7 metric rows |
| `tools/check_perf_gate_evidence.py studio` | **PASS** — preflight clean, capture admissible |
| `lune run tools/lune/check_boundary` | **PASS** — 163 src files (the new module counted), 413 consumer files |
| `lune run tools/lune/check_docs` | **PASS** |
| `lune run tools/lune/check_primitives` | **PASS** |
| `lune run tools/lune/check_prop_parity` | **PASS** |
| `lune run tools/lune/check_surface_ledger` | **PASS** |
| `lune run tools/lune/check_theme_drift_cli` | **PASS** |
| `lune run tools/lune/check_flat_baseline` | **PASS** — 1461 flat nodes byte-compared, no new deltas |
| `stylua --check` | clean on every file this round touched |

`tools/check_manifest_integrity.py --transcript` is reported with the suite
numbers below, since it runs the suite.

## Self-review of the fix round

1. *Is `render/tag_sync` the right home, or did I just pick the first loadable
   place?* `sheet_model` mints the tags and would be the authority, but it is
   `src/tokens/` — another lane's this round — and `render/` is where this
   repository already keeps a pure ruling two adapters share
   (`stage_content`, `foreign_content`, both with headers saying exactly that).
   It is the idiomatic home, not the convenient one.
2. *Does the fake's tag mirror re-create the lockstep problem the defect came
   from?* Partly, and it is bounded on purpose: the DECISION is shared code, so
   the two adapters cannot disagree about a sync. What is duplicated is the
   state map, four lines of it, declared in one block with a comment naming what
   it does not cover. A wider mirror would be a second classification engine.
3. *Is the mutation proof honest?* It restores the exact historical defect inside
   the shipped predicate and all seven cases fail, including the three pure ones.
   The failure text on `surface=plain` reproduces the shipped symptom verbatim.
4. *Did I widen the scanner enough?* Four spellings, both comment kinds. The
   remaining hole (a `--` inside a string literal) is stated in the spec header
   with the anti-vacuity count that would move if it ever mattered.
5. *Anything I still would not sign?* The four ten-foot captures are annotated
   rather than re-taken, because re-taking them needs a console session. That is
   flagged, not resolved.

## Concerns carried forward from this round

1. **The four ten-foot captures still show the defect.** Annotated in band and
   booked as handoff item 4; ADR-0040 B-17's decision is unaffected and says so.
2. **`screen_target.luau` is back inside the warning band** at 190,181, with the
   row re-read and the trigger at 192,000.
3. **`fake_target`'s tag mirror covers four classification inputs**, not the
   twenty-odd `classifyTags` accepts. A future defect in, say, the toggle or
   error tag has no headless witness yet — the shape is now there to extend.
4. **`tag_sync` is required by `fake_target`**, so a test-lib and a shipped
   module now share a file. That is the point, and it is also the first time the
   headless twin depends on `src/render/` for a DECISION rather than a type.

## Suite tails, BOTH repositories — the fix round

Content-pinned `mkpair` pair, `PIN_FACET 37b69f9e7791…` (the second fix-round
commit) / `PIN_RR 248b881a2afa…`:

```
GameStudio/ui/Facet      $ ./run-tests.sh      -> 7168 passed, 0 failed   (exit 0)
games/RascalRally/code   $ lune run tests/run  -> 3486 passed, 0 failed   (exit 0)
```

The RascalRally number is the one that matters most this round: **24 RR spec
files require Facet's `tests/lib/fake_target`**, which is the file that gained
the tag mirror, so RR's suite is a real lockstep check on that change rather
than a formality.

`tools/check_manifest_integrity.py --transcript` was run separately against the
working tree and reports **1518 suite greps, all anchored to the pass marker;
1518 matched a green transcript** — an independent confirmation, because that
tool re-derives the verdict and REFUSES a red, short, truncated or fast-tier
transcript. The transcript it validated carries the same 7168.

For reference, the clean tree immediately BEFORE the fix round (`e514ebc`, in
its own pair) was **7155 passed, 0 failed**; the +13 is the new
`tag_sync.spec` (7) plus the extra cases the four other lanes landed in the same
window. `prefix_tests.spec` stayed at 4 (one case gained assertions rather than
splitting).

**A measurement note worth keeping.** Four other agents were running full
suites on this machine concurrently (load average 7-8, one run 43 minutes long),
which stretched a ~90-second suite past 25 minutes and killed two harness-managed
runs outright. Nothing about the verdicts changed — the pair is content-pinned —
but "the suite hung" was the wrong first read of a machine that was simply
oversubscribed, and I made it twice before checking `ps`.
