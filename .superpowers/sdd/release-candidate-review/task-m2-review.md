# M2 — the missing review seat: the lazy-Controls ship, and the DIR2 expand fixes

**Seat:** the independent review the final review's M2 found these two rounds had
closed without. Fresh context, read-only on the working tree; every number below
was produced in a private `git archive` export in scratch, so none of it touches
the DIR3 writer's in-flight work.

| round | commits | endpoint | verdict |
|---|---|---|---|
| **A — lazy Controls + review-fold** | `45fc2c6` `e3aeda4` `84b38bb` `8985ef9` `8202a9d` | `8202a9d` | **APPROVE WITH FINDINGS.** The shipped change is correct and its type half is genuinely mechanised. Its *laziness* half is pinned by nothing, and the wave's own retracted numbers and falsified idiom survive as present-tense fact in five live files. |
| **B — DIR2 expand fixes** | `9a32399` | `9a32399` | **APPROVE WITH FINDINGS.** All four root causes are real, all four claimed mutations bite at the claimed magnitudes. The headline rule the round names as its replacement is not true as shipped, and the instrument written to guard it is blind to the counterexample. |

Neither round is a revert candidate. Both leave a claim in the tree that is
stronger than what the tree enforces.

## Method

Endpoints exported with `git archive` into scratch and run there:

| export | commit | `./run-tests.sh` |
|---|---|---|
| `A` | `8202a9d` | **6854 passed** |
| `A1` | `45fc2c6` | **6853 passed** (commit claims 6844) |
| `B` | `9a32399` | **6851 passed** — matches the commit exactly |

Toolchain as pinned: `luau-lsp 1.69.0` from `rokit.toml`, `lune`, `python3`.
Mutations were planted in throwaway copies (`A_M1`, `A_P1`, `A_P2`, `A_cp`,
`A_types`, `B_blank`, `B_cover`, `B_tail`, `B_cap`, `B_td`, `B_probe`).

---

# Round A — the lazy-Controls ship + review-fold

## What reproduced, exactly as claimed

**1. `check_types.py` + selftest.** Reproduced in `A`:

```
check_types: PASS — 19 Controls entries (15 typed, 4 declared `any`);
             2 target files carry 0 diagnostics; 246 graph diagnostics ignored
check_types --selftest: PASS   [ok] unmutated / M1 / M2 / M3
```

Both target files verified restored byte-for-byte after the selftest.

**M1 planted independently** (not via `--selftest`): widening
`Controls.Table` to `spec: any` in a fresh copy —

```
check_types: FAIL
  - these Controls entries lost their spec type and now take `any`: Table
./run-tests.sh                                            6854 passed
```

The red-first claim holds exactly as written: the check reddens, the Luau suite
does not move, and the surface dump does not move. This is the round's strongest
piece of work and it is real.

**2. The typed-signature falsification.** Reproduced directly. Replacing
`local tableControl = require("@self/controls/table")` with
`type tableControl = typeof(require("@self/controls/table"))` and deferring the
call:

```
src/init.luau(370,36): TypeError: Unknown type 'tableControl.Spec'
```

So the four-entry line is drawn in the right place. The four deferred entries
(`Chip`, `VirtualList`, `VirtualGrid`, `AsyncImage`) are exactly the four that
already declared `spec: any`, and `check_types` pins that set both ways. I also
confirmed statically that **no other module under `src/` requires any of the
four**, so the deferral is not defeated transitively — the mechanism is real.

**3. The surface dump, both halves.** Regenerated from source in the export:

- the shipped dump reproduces **byte-identical** to the checked-in file;
- with `preload` removed and the lazy requires kept, the dump is **byte-identical
  to the pre-round dump** (`9a32399`'s copy) — laziness hides nothing;
- shipped vs lazy-only differs by **exactly one line**, `preload : function`.

Both halves verified. (The `baseline/public-surface.txt` at VERSION 0.9.0 is a
different, older frozen file and is correctly untouched.)

**4. The capture-plan parser.** Reverting the shape pass to the old silent
`continue` reddens its spec: `1 failed, 103 passed`, on
`a settings pair that is not 'key=value' is REFUSED, not silently dropped`.
The two-pass "shape first, then apply" structure is right, and the refusal names
both the offending text and the legal spelling.

**5. The three repaired gate rows, and the fourth.** All verified by extracting
each row's shell text and running it, and each proved to have been *genuinely
red* before `e3aeda4` by restoring the pre-image:

| row | at `8202a9d` | red before the fix? |
|---|---|---|
| `naming-adr-implemented` (extracted verbatim, 18 sub-commands) | **exit 0** | n/a — `45fc2c6` added exactly two sub-commands to it: `check_types.py --selftest` and `check_types.py`, nothing else in the run string |
| `product-language-scan-bites` / brand drift | **PASS + SELFTEST PASS** | yes — deleting the `MAINTAINERS.md` `GATE_IDS` entry reddens it naming 7 lines |
| `check_call_shape_drift` | **PASS + SELFTEST PASS** | yes — deleting the entry gives `_probe_t15_controls.luau:33: Facet.newProgressView(Facet, …)` |
| `comments-plain` | **exit 0**, 0 orphans, 25 codes | yes — restoring the three pre-image files gives `FAIL — 6 private code(s) … resolve nowhere`, i.e. 31 against a ceiling of 25 |

The allowlist entries are as narrow as claimed. The brand entry is a
`(path, re.compile(r"LuauUI/"))` pair with a reason and a removal trigger, and a
plain old-brand mention planted in that same file (`# … for LuauUI …`) still
reddens the check — the excuse is scoped to the prefix, not to the file. All 11
of that file's brand-matching lines genuinely contain `LuauUI/`. The call-shape
entry names one file, carries the stated trigger, and opens no directory or
prefix hole (a sibling `_probe_t15_controls_sibling.luau` and a
`_probe_t15_controls.luau.luau` each still fail). The fourth row is
`docs/MAINTAINERS.md` gaining the `GATE_IDS` vendor entry six other files
already carry, and it is load-bearing.

**6. The BLOCKED/deferred bookkeeping** for this round is complete (see Round B
for the DIR2 half).

## Findings

### A-H1 (HIGH) — the two new laziness pins do not bite

Both mutations leave the suite fully green:

| mutation | result |
|---|---|
| **P1** — all four `require`s restored to eager top-level, `preload` kept | **6854 passed**, and *both* T15 pins print ✓ |
| **P2** — `preload`'s body gutted to a bare `return 4` | **6854 passed** |

`tests/virtualization.spec.luau`'s two new cases cannot fail for the reasons they
name. `no lazy require fires during dense-scroll steady state` asserts
`rawequal(require(m), require(m))` across a scroll — true by the module cache
whether or not anything is deferred, and true even if a require *did* fire mid-
frame. `Facet.preload() force-loads the deferred four and is idempotent` asserts
that a function whose body is a hardcoded `return 4` returns 4 twice.

Consequence: `check_types` mechanises the **type** claim, and nothing mechanises
the **laziness** claim. The two sentences `docs/reference/api.md` sells to a
consumer — "228 KB a game that builds none of them never pays" and "the load
happens at a construction seam, never inside a frame's steady state" — are both
unguarded. A future edit that re-eagerises the four, or that moves a `require`
into a scroll path, passes every check in the repository.

This is the round's own standard, applied to the round: it is the "check that
proves nothing" class, and it is sitting under the wave's headline claim.

### A-H2 (HIGH) — the falsified idiom and the retracted number are still asserted as fact

The wave's two headline findings were that `typeof(require(x))` does not carry
exported types, and that the 831 KB memory headline was subset arithmetic and is
wrong. At the round's own endpoint, five live files still state both as current:

| file:line | what it says | status |
|---|---|---|
| `tools/check_types.py:5-8` | "`src/init.luau` defers each control's `require` … and keeps the parameter types through `typeof(require(...))` … that idiom is worth 831 KB" | **both halves false**; 15 of 19 are eager, and the idiom exists nowhere in the tree |
| `tests/types/controls_witness.luau:4-9` | same sentence, same idiom | same |
| `tools/check_types.py:182` | failure text: "this is what a lazy require without `typeof(require(...))` looks like" | points the next maintainer at the exact remedy this wave disproved |
| `src/init.luau:31, :50, :55` | "831 KB of it", "232 KB", "the remaining 599 KB" | superseded by 228 KB [131..313] and 632 KB |
| `artifacts/release-candidate-review/perf/capture-plan.md:61` | tells the Studio operator to record the device number against "**831 KB**" | a retracted figure in a live operator instruction — **edited in the same commit that retracted it** |
| `examples/performance/client/init.client.luau:30` | "the nineteen composite controls are 831 KB" | on the lab client the operator reads |

The instrument built to stop a claim no check could falsify carries, in its own
`WHY THIS EXISTS`, a claim its own first run falsified.

### A-M1 (MEDIUM) — the "kept and marked SUPERSEDED" claim is false

`84b38bb`'s message: *"The old subset table is kept and marked SUPERSEDED,
because its RANKING is still what found the four type-free entries."* Measured:
`grep -c supersed artifacts/release-candidate-review/perf/requalification.md`
→ **0**. The commit deletes the table block, the 20-row inventory and the
candidate ranking it names as the reason for keeping it; only a one-line
retraction survives at `:332`. Meanwhile the old table survives **unmarked** in
`.superpowers/sdd/release-candidate-review/task-15-report.md:83-88`, still
reading `−831 KB (−29.7%) ← whole saving`.

### A-M2 (MEDIUM) — the corrected method description overstates the probes

The corrected §7 says arms are run **interleaved**, n = **30 per arm**, split by
collector mode and compared low-mode to low-mode. The probes do not do this:

- `tools/lune/_probe_t15_lazy_all.luau` takes the arm from *whichever
  `src/init.luau` is in place*, so arms are necessarily separate process trees,
  not interleaved; its own header says samples are "paired by INDEX afterwards".
  `REPEATS` defaults to **15**.
- **No code anywhere splits collector modes.** `stat()` returns min/median/max
  over the whole sample; there is no threshold and no mode count.
- The header names an analysis tool `_probe_t15_lazy_pair` that **does not exist**
  in the tree, so the published mode counts have no producer.
- The surviving raw samples (`samples_eager.json`, `samples_lazy.json`,
  `samples_all19.json`, all pre-commit) are n = 15 per mode in three separate
  batches. Pooled, they give low-mode counts of 23-24 / 22-24 / 16-20 of 30 —
  **not** the published 19 / 17 / 14, and each published range traces to a
  different single 15-sample mode rather than to one n = 30 plan.

**The conclusion survives the audit.** Independent re-measurement of all three
arms reproduces every KB figure inside its published range (shipped 224 KB
[134..313] vs published 228 [131..313]; ceiling 857 [767..858] vs 860 [762..860]).
The physics is right; the described procedure is not the procedure that was run.

### A-M3 (MEDIUM) — the Rascal Rally A/B is prose, and carries none of the honesty upgrades

The six RR numbers exist in exactly one authored file
(`task-15-report.md:344-353`) as a four-row summary. There is no frozen artifact,
no per-round samples, no n, no spread, no mode-matching — in either repository,
tracked or untracked. "Five paired rounds" is supported by nothing on disk, and
`requalification.md:395-397` says the client number *was not taken*, which
contradicts the report one section later.

The arithmetic itself is honest (232 + 45.1 = 277.1 → 277; 209 + 58.6 = 267.6 →
268; the displayed −9 ms understates the true −9.5 ms). The **inference** is not
supported at the precision claimed: independent measurement puts the run-to-run
require-time spread on a *single* arm at **30.7 ms**, larger than the entire
23 ms require-time win the "cost moved, not added" reading rests on, and the heap
half is subject to the same bimodality §7 was rewritten to handle, with no
mode-matching applied. So §7 fixed a dishonest number and the next section
reproduced the same defect on the number the artifact itself calls decisive.

Separately: **Rascal Rally carries no test that would notice this change.** No
reference to `Facet.preload` anywhere in the game; no test iterates
`Facet.Controls`; nothing measures require time, heap or boot. A silent
regression to eager is invisible from the consumer side. (The RR suite at 3449 is
real — a 4,408-line transcript in the gitignored suite cache, `exit_code=0`,
stamped after `84b38bb` — but it is not evidence of the lazy path.) Both Rojo
projects do `$path` to `GameStudio/ui/Facet/src`, so the coupling is live.

### A-M4 (MEDIUM) — the published route to the remaining 632 KB is insufficient

`requalification.md:381-386` says the ceiling is reached by moving the fifteen
`export type Spec` declarations to a cheap module. It is not enough: the legacy
`new<Control>` fields for those fifteen are **module-level references**
(`newTable = tableControl.build`, `src/init.luau:491-597`), so deferring the
`Controls` entries alone still loads every module. Reproducing the ceiling arm
required closuring those sixteen fields too. The obstacle is unmentioned, so the
follow-up as scoped would not land the number it promises.

### A-M5 (MEDIUM) — `comments-plain` is green at zero headroom, and its "0 orphans" is 0-of-20-modules

Two things the round's tail (`check_comment_codes PASS — 0 orphans, 25 codes
(ceiling 25)`) does not say:

- **The count is exactly at the ceiling.** `TOTAL_CEILING = 25`, checked as
  `len(live) > 25`. The next private code added to any maintained `src/` module
  reddens the row. The round consumed the entire margin, having itself put the
  file at 31 before the fix.
- **The scan is `SCANNED = ("src",)` minus `EXTRACTION_LOCKED`** — 20 of 25 `src/`
  modules. Driving the scanner directly: maintained = 25 sites / 0 orphans;
  **extraction-locked = 185 sites / 150 orphans**, counted, printed and never
  gated. Among them, `src/present/presenter.luau:4090` carries
  `-- quarantined (verifier RR-12): …` — an `RR-12` of precisely the kind this
  commit swept, which the checker's own classifier calls an orphan and the gate
  cannot see. The 150 are declared in
  `artifacts/release-candidate-review/docs/comment-audit.md:153`, so this is not
  green-washing — but "0 orphans" needs its scope attached wherever it is quoted,
  and the sweep was not complete.

### A-L1 (LOW) — a suite number that does not reproduce

`45fc2c6` claims "Suite 6844 in an isolated clone of HEAD plus these files". A
clean export of that exact commit measures **6853**. The round's endpoint
(`8202a9d`) measures 6854 and is stated nowhere.

### A-L2 (LOW) — `check_types --selftest` mutates the live tree

The selftest writes mutated `src/init.luau` and
`tests/types/controls_witness.luau` in place and restores them in `finally`; an
interrupt or SIGKILL mid-run leaves a widened `Table` signature in the working
tree. `negative_probe()` also writes `tests/types/_negative_probe.luau` into the
mounted `tests/` tree while creating — and never using — a `TemporaryDirectory`
(`tmpdir` is dead: `_ = tmpdir` sits after a `return` inside `finally`). This
repository has already been bitten by a probe file under a Rojo-mounted path.

### A-L3 (LOW) — the capture plan itself is unchecked

The parser now refuses at runtime, but the plan document is only gated by
`test -f` (`perf-requalification` row). Nothing validates its settings strings
against `steps.select`, so the exact defect this commit fixed can reappear in the
document and stay silent until a human runs it.

### A-L5 (LOW) — the verification tail's two halves cannot come from one tree

`tools/check_call_shape_drift.py:48-49` and `check_brand_drift.py` both compute
`STUDIO_ROOT = REPO/../../..` and require the sibling Rascal Rally repo at
`games/RascalRally/code`, and both scan `git ls-files` — so **neither runs in a
bare Facet clone** (exit 2, `FAIL_ENVIRONMENT`). The suite number in the round's
tail was taken "in an isolated clone of HEAD plus these files"; the gate-row exit
codes beside it necessarily were not. Reproducing this row needs a studio-shaped
sandbox with both repos, which is worth writing into the row's note — it is a
direct descendant of the T15 review's finding that a verification tail must be
the gate-row set.

### A-L6 (LOW) — two pre-existing holes the new brand entry inherits

Not introduced by this round, but the round widened the allowlist and so now
depends on them:

- **The path rule is pattern-agnostic** (`check_brand_drift.py:617`):
  `allowed_path = any(matches(scope_path, p) for p, *_ in allowlist)` — any
  allowlist entry for a file exempts that file's *name* from the brand rule,
  regardless of the entry's pattern. Latent (the basename carries no brand), but
  a narrow content excuse silently buys a wide path exemption, for all ~30
  allowlisted paths.
- **Excuses are line-granular, not occurrence-granular.** Proved: appending
  `# LuauUI/arrange decoding, brought to you by LuauUI the product` to
  `microprofiler_aggregate.py` **passes** — an old-brand mention sharing a line
  with a legitimate `LuauUI/` occurrence is invisible.

Also worth a note: the call-shape allowlist is *file-wide* within its one file
(an unrelated old-form call appended to the probe still passes), which is looser
than the `(path, pattern)` discipline the brand guard uses — documented in the
guard's own docstring, so a difference in discipline rather than a defect.

### A-L4 (LOW) — traceability traded for the comments-plain row

The six `RR-5`/`RR-12` codes were deleted rather than made resolvable. The
comments now state their findings (which is the better half of the fix), but the
38-site set is no longer greppable back to the review that produced it, and the
alternative fixes (move the review under `docs/`, or teach the checker
`artifacts/`) were not considered in the message.

---

# Round B — the DIR2 expand fixes (`9a32399`)

## What reproduced, exactly as claimed

**Suite: 6851 passed** — the commit's number, to the case.

**All four claimed mutations bite, at the claimed magnitudes:**

| mutation | claimed | measured |
|---|---|---|
| cover role restored | 5 red | **5** in `region_expand.spec` (+3 collateral in the give-way/theme-swap sweeps that the message does not mention) |
| tail restored (`tail = true`) | 1 red | **1** — `…the plate contributes no opaque node of its own: no tail, no seam` |
| plate cap ignored | 1 red | **1** — `a fill-width richest form gets the whole plate, not its own content width` |
| tasks chip blanked | 5 cells | **5** — `compact-phone-landscape`, `compact-phone-portrait`, `narrow-landscape`, `narrow-portrait`, `phone-390x844` (+3 collateral localization/overflow reds) |

**The four root-cause claims all check out against the diff:**

1. *z-order cover* — the two-role decision is deleted from `blueprint.Region`; the
   affordance is unconditionally a `Caret` `UI.Text` beside the form.
2. *stale probe row* — `PROBE_ROWS` moves `…/Tasks/TasksChip` to
   `…/Tasks/TasksChip/Plate` after the wave turned the chip into a wrapper. The
   "1 of 11 NOT PAINTED" was an instrument asking a node with no paint to give.
   Correctly diagnosed and correctly labelled as an instrument defect, not a
   screen defect.
3. *tail band removal* — `tail = false`, and `rootPolicy` dropped with a checkable
   reason (`presentAnchored` forces `edgeToEdge` for every anchored surface).
   `EXPAND 16` asserts `Tail` and `TailSeam` are absent.
4. *plate `min(natural)`* — `composition.resolve` now reports `max` beside `w`,
   `RegionResolution.plate` and `composition.dump` both carry it, and `panelOf`
   takes the whole record so the `width = fill` case can claim the cap.

**`plate.max` second-consumer lockstep is genuinely covered.** I expected this to
be untested — `ColumnsPanel` appears in no spec by name — and it is not: breaking
`table_disclosure`'s `plate.w` read reddens **6** tests across the table
disclosure's keyboard/mouse/touch/pad/self-close paths. Both production consumers
and all three test consumers moved together.

**`EXPAND 16` is honestly scoped.** It says in its own header that it is a
regression fence, not proof the device symptom is gone, and that it passed before
the fix. That is the right way to record an unreproduced symptom.

**The X-icon close specs** (`EXPAND 17`) assert both halves: the glyph on screen
via `chromeSlots.attachHint(… { icon = "close" })`, and the verbal `label =
"Close"` for a reader, with the focus stop, activation verbs and 44px band
unchanged.

**The BLOCKED item is honestly recorded** — `progress.md:890` and
`artifacts/release-candidate-review/t16-triage.md:14`
(*Mark-yields-to-value (2 lines, solver) · BLOCKED on solver lock · extraction
charter (solver seam) · charter start*), with owner and trigger. Note both
records postdate the round: `9a32399` itself shipped no report and no ledger
entry, which is the M2 gap this seat exists to fill.

**New-breakage scan of the diff: clean.** The docs move with the code, the
fixture pays for the mark rather than the player (pill gutters 10→4, a third
timer rung), and `e3aeda4`'s three `src/` edits in Round A are comment-only.

## Findings

### B-H1 (HIGH) — the "nothing above the author's content" rule is not achieved, and the new fence cannot see the counterexample

**This is the most important issue in either round.**

The round retires the cover on a rule it states absolutely: *"THE FRAMEWORK PUTS
NOTHING OF ITS OWN ABOVE THE AUTHOR'S CONTENT … A mark beside the form cannot
occlude a pixel the author drew, whatever the engine does with transparency,
stacking contexts, hit expanders or instance recycling."*

Measured in an export, with the fixture's compact form declared `width = fill`
(the ordinary HUD case — a zone that fills its lane):

```
PROBE /S/C/Clock/Compact  rect=370.0x20.0@0.0,46.0    hit=nil
PROBE /S/C/Clock/Expand   rect=20.0x22.0@370.0,46.0   hit=44.0x44.0@358.0,35.0
PROBE-OVERLAP hitrect covers author node /S/C/Clock/Compact by 12.0x20.0
69 passed
```

The solver reserves the mark's 20px and gives the form `innerW - markW`, so the
form ends exactly where the mark begins. The **44×44 hit floor then reaches 12px
back over it** — the author's content, at its full 20px height — and 11px above
and below the region's own 22px box. Engine-side that rect is a real
`FacetHitExpander` `TextButton`, `Instance.new`'d as a **sibling at
`instance.ZIndex - 1`** (`src/client/screen_target.luau:2306-2312`), i.e. in
exactly the z band the device round measured (band 115 against the pill's text at
113) when it recorded the defect.

It is `BackgroundTransparency = 1`, `Text = ""`, so it *should* paint nothing.
That is verbatim the argument the round refused for the cover: *"'it is
transparent, so it is harmless' is a claim about the ENGINE that nothing in this
repository makes or can make."* The cover was retired on that reasoning; the band
it sat beside was not, and the mechanism was never identified ("I could not
reproduce the paint failure headlessly and did not try to guess its mechanism").

And the new instrument is structurally blind to it. `EXPAND 15`'s
`no framework instance covers any node of the standing form, at any depth`
compares author rects against **`mark.rect`** (20×22) and never against
**`mark.hitRect`** (44×44) — the file stays green at 69 passed with the overlap
above sitting in it. This is the same shape as the original defect: a
framework-owned instance over author content that every model-side check calls
fine.

**What I am not claiming:** that this reproduces the empty pills. It may well be
harmless. The finding is that the round's stated rule is not what shipped, its
new fence measures the smaller of the two rects, and the only object still
matching the retired role's description was left in place unexamined.

*Suggested close:* have `EXPAND 15` read `hitRectOf` as well as `rect`, and
decide explicitly — with a stated reason — whether the 44px floor is exempt from
the rule or has to be clamped to the mark's reserved column.

### B-M1 (MEDIUM) — the "closed set of one" is closed in one file only

`docs/reference/api.md:1210`: *"`role` is a closed set of one: `"cover"` was
retired."* The tree disagrees:

| file:line | what survives |
|---|---|
| `src/blueprint_schema.luau:319-320` | `if r.role ~= "cover" and r.role ~= "chevron" then … '`role` must be "cover" or "chevron"'` — **`"cover"` is still a legal value** |
| `src/blueprint_schema.luau:347-348` | same, on the resolved `expandSpec` record |
| `src/blueprint_schema.luau:316` | the validator's own error text still advertises `a target such as { role = "cover" }` |
| `src/blueprint_schema.luau:2094` | the public prop `doc` still teaches `{ role = "cover" } covers the compact form` |
| `src/layout/solver.luau:2991` | **the cover geometry is still implemented**: `if role == "cover" then rect = { innerX, innerY, innerW, innerH }` — the region's whole inner box |
| `src/layout/solver.luau:1088` | the ladder still relies on "A `cover` affordance reserves nothing: it is the form's own box" |
| `src/blueprint.luau:901, :1221` · `src/layout/text_audit.luau:72` | surviving comments describe the retired role as a live alternative |

The only thing preventing the retired behaviour is one hardcoded string literal
at `src/blueprint.luau:1196`. The round's own block header anticipates the second
member coming back "through it rather than through a new prop" — but a validated,
implemented, publicly documented `"cover"` is not a retired role, it is a
reachable one. **Mitigation, measured:** restoring the literal reddens 5
`region_expand` cases, so a framework-side restore *is* caught. What is not
caught is a `role = "cover"` arriving on the prop, which the schema accepts today.

*Suggested close:* make the schema reject `"cover"` by name with the device-round
reason, delete or `error()` the solver branch, and fix the `doc` string — then the
api.md sentence is true and the 5 red cases become a second fence rather than the
only one.

### B-L1 (LOW) — a green transcript line that teaches the retired rule

`tests/region_expand.spec.luau:412` keeps the title
`a PASSIVE form is the target itself — the affordance covers it and draws nothing`
while its body now asserts `role == "chevron"` and a `Caret` child. The suite
transcript therefore prints the retired behaviour as a passing line, and gate rows
in this repository grep transcript lines.

### B-L2 (LOW) — one confirmed root cause and one unconfirmed one, carried at the same weight

DIR2-1 (cover) was diagnosed with a live z measurement. DIR2-2 (base screen
disappears) was never reproduced; the tail-band removal is a plausible candidate
shipped as a fix, and `EXPAND 16` says so honestly in its header — but the commit
message presents the two with the same confidence. The ledger correctly keeps
DIR2-2 open to the device half; the message should have.

---

# Counts

| round | HIGH | MEDIUM | LOW | total |
|---|---|---|---|---|
| A — lazy Controls + review-fold | 2 | 5 | 6 | 13 |
| B — DIR2 expand fixes | 1 | 1 | 2 | 4 |
| **total** | **3** | **6** | **8** | **17** |

Of the LOWs, A-L6's two items are pre-existing holes the round inherited rather
than created; they are listed because the round's new allowlist entry now rests
on them.

No BLOCKER. Nothing found that is a correctness regression against the shipped
behaviour of either round; every finding is a claim wider than its evidence, or an
instrument narrower than the rule it is said to enforce.

# The single most important issue

**B-H1** — the framework still places its own instance over the author's content.
With a `width = fill` compact form the chevron's 44×44 hit expander covers the
author's node by 12×20px, realized on the engine as a `FacetHitExpander`
`TextButton` sibling at `hostZ - 1`; the round's new structural fence measures
`mark.rect` and never `mark.hitRect`, so the counterexample sits inside a green
suite. The cover was retired precisely because "it is transparent, so it is
harmless" is a claim this repository cannot make about the engine — and the
object that argument still applies to was left in place, in the same z band the
device round measured, with the paint mechanism never identified.

Runner-up, and the one to fix first if only one gets fixed: **A-H1**, the two
laziness pins that pass with the entire mechanism removed.
