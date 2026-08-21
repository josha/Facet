# M2 fix round — scoped re-review of A-H1, A-H2, B-H1, A-M1

**Seat:** fresh-context re-review of the fix round for `task-m2-review.md`'s
findings A-H1, A-H2, B-H1 and A-M1. Read-only on the shared tree; every number
below was produced in private `git archive` exports under scratch. Commits
reviewed: `1f0b99d` `08eb931` `9a5ea84` `509d747` `1f9e32c` (`5e8c1d9`, the
report, skipped per brief). Implementer's report: `task-m2fix-report.md`.

**Verdict: all four findings CLOSED, plus the extra ledger repair. One new HIGH,
two new MEDIUMs, five LOWs — every one of them on an instrument, none on
behaviour.**

| finding | verdict |
|---|---|
| **A-H1** the two laziness pins do not bite | **CLOSED** |
| **A-H2** falsified idiom + retracted 831 KB asserted as fact | **CLOSED** |
| **B-H1** the fence measures the smaller rect; the expander unexamined | **CLOSED** — with a new HIGH on the guard that closes its second half |
| **A-M1** the false "kept and marked SUPERSEDED" | **CLOSED** |
| *(extra)* `surface-ledger-complete` red since `8202a9d` | **CLOSED** |

## Method

| export | commit | what |
|---|---|---|
| `HEAD` | `5e8c1d9` | round endpoint — **6883 passed** (full suite, 3m34s) |
| `BASE_DIR4` | `6628ebd` | the round's actual parent — **6881 passed** |
| `PRE` | `9a5ea84^` | region_expand 68, virtualization 12 |
| `A8202` | `8202a9d` | Round A's endpoint, for the ledger regression |

Toolchain as pinned (`rokit.toml`: `luau-lsp 1.69.0`), `lune`, `python3`,
`stylua`. Mutations planted in throwaway copies (`P1` `P2` `P4` `Ba` `Bb` `Bb2`
`Bb3` `Bb4` `Bb5` `Bc` `Bc2` `Bcount` `Bp` `Bt`). Single-spec runs used a
one-file runner (`tests/_one.luau`) planted in the export only.

Note: the shared tree has moved on since the endpoint — `2d1aed2` and `045de93`
landed after `5e8c1d9`. All measurement here is pinned at `5e8c1d9`.

---

# A-H1 — the laziness pins now watch the call — **CLOSED**

## The two review mutations reproduce exactly

**P1 — all four deferred requires restored to eager top-level** (four new
top-level `local` bindings; every one of the twelve deferred call sites in
`Controls`, the legacy `new<Control>` fields and `preload` rewritten to the
binding):

```
  ✗ requiring Facet loads the fifteen typed controls and defers exactly four (T15)
      :319: expected  to be @self/controls/async_image @self/controls/chip
                            @self/controls/virtual_grid @self/controls/virtual_list
  ✗ the deferred require fires at the construction seam and never in a frame (T15)
      :335: expected  to be @self/controls/virtual_list
  ✗ Facet.preload() force-loads exactly the deferred set, and twice is a cache hit (T15)
      :363: [never] expected  to be
3 failed, 9 passed
```

**P2 — `preload`'s body gutted to a bare `return 4`:**

```
  ✗ Facet.preload() force-loads exactly the deferred set, and twice is a cache hit (T15)
      :372: expected  to be @self/controls/async_image @self/controls/chip
                            @self/controls/virtual_grid @self/controls/virtual_list
1 failed, 11 passed
```

Both match the report's transcripts to the case count and the message text. The
mutations that made the *old* pins pass now redden the new ones.

## The interception is honest

I drove `loadInitUnderRecordingRequire`'s mechanism directly rather than through
the assertions.

- **The recorder really intercepts.** Loading `src/init.luau` under
  `luau.load(..., environment = { require = recorder }, injectGlobals = true)`
  logs **53 require calls**, of which **17** are `@self/controls/*`: the fifteen
  typed controls plus `value_model` and `path_shapes`. The four deferred ones are
  absent. So "fifteen typed controls at load" is measured, not asserted.
- **The deferred set is derived, not hand-listed.** `probe.deferred()` is
  (every `@self/` path the source names) minus (every path the load asked for):
  54 distinct paths in source, 50 at load, difference exactly the four.
  **Positive control (P4, mine):** deferring a *fifth* control — `label` moved out
  of its top-level binding into `require("@self/controls/label")` at both its
  `Controls` entry and its legacy `newLabel` field — reddens **two** pins, naming
  the new member:

  ```
  ✗ ...defers exactly four (T15)
      expected @self/controls/async_image @self/controls/chip @self/controls/label
               @self/controls/virtual_grid @self/controls/virtual_list to be …(the four)
  ✗ Facet.preload() force-loads exactly the deferred set…
      expected …(the four) to be …(the five)
  ```

  A fifth deferral joins the pin *and* is caught escaping `preload`. That is the
  property the report claims and it holds.
- **The positive control is a real threshold.** `#probe.atLoad >= 40` sits
  against a measured 53, and is backed by two named modules (`table`,
  `row_actions`). A recorder wired to nothing gives 0 and fails; it also makes
  `deferred()` return all 54, so the set pin is self-guarding in both directions.
- **No load-time side effects.** `src/init.luau`'s top level is 33 requires,
  type exports, three table literals and `library = Facet` — nothing registers
  into shared state, so loading it a second time cannot pollute the suite.
  Confirmed by the file's own registry-baseline case still passing after the
  three new ones.

**Residual, disclosed by the report and confirmed:** the steady-state half has no
production mutation reachable by editing `src/init.luau` alone (the file runs no
per-frame code). The comment in the file says so.

---

# A-H2 — the falsified idiom and the retracted number — **CLOSED**

## Tree-wide grep at the endpoint

`grep -rn "typeof(require"` and `grep -rn "831"` over the whole export
(excluding `vendor/`). **No surviving site asserts either as current.** Every
survivor is one of three shapes:

| shape | sites |
|---|---|
| an explicit retraction naming 831 as retracted | `tools/check_types.py:11,17` · `src/init.luau:36` · `examples/performance/client/init.client.luau:33` · `artifacts/…/capture-plan.md:62` · `artifacts/…/requalification.md:341,426` |
| a falsification table (the idiom listed as answering `Unknown type 'M.Spec'`) | `tools/check_types.py:14-16` · `artifacts/…/requalification.md:381-382` · `tests/types/controls_witness.luau:8` · `task-15-report.md:272-279` |
| inside the new SUPERSEDED block, or a dated historical log line | `artifacts/…/requalification.md:465` · `progress.md:836,848` |

Unrelated `831` hits (`gate_manifest.luau:3341` "4831 passed", asset hashes,
`reuse.md` line numbers, an adapt-matrix cell) are coincidental digit strings.
`check_types.py:182`'s failure text no longer points the next maintainer at the
disproved remedy. The two extra sites the report found beyond the review's six
(`check_types.py:218,295`) are real — `:295` prints on every selftest run.

## The instrument still passes, and restores its targets

```
check_types: PASS — 19 Controls entries (15 typed, 4 declared `any`);
             2 target files carry 0 diagnostics; 246 graph diagnostics ignored
check_types --selftest: PASS   [ok] unmutated / M1 / M2 / M3
```

Both target files verified **byte-identical to `HEAD`** after the selftest
(`md5` of `src/init.luau` and `tests/types/controls_witness.luau` match
`git show HEAD:` exactly). `check_source_size` PASS, `check_comment_codes` PASS
(0 orphans, ceiling 0; 25 codes, ceiling 25), `check_doc_style` PASS,
`stylua --check` clean on all three edited `.luau` files.

`docs/reference/api.md`'s two consumer-facing sentences — the two A-H1 named as
unguarded — now read **228 KB** and are the exact claims the three new pins
mechanise.

---

# B-H1 — the fence reads both rects — **CLOSED**, and a new HIGH on the guard

## All three claimed mutations reproduce, plus a fourth I planted

**(a) the compact form's Button given `width = fill`** (`ringScreen(true)`,
line 1055):

```
  ✗ no framework instance covers any node of the screen, painted OR reachable (R18)
      :1707: expected /S/C/Clock/Compact/Live under the mark's 44px floor by 12x44: FORBIDDEN (R18)
                   to be /S/C/Clock/Compact/Live under the mark's 44px floor by 12x44: allowed (R18)
1 failed, 68 passed
```

Verbatim the claimed message, including the 12x44.

**(b) `CollectionService:AddTag(expander, "facet-surface-base")` in
`setHitRect`:**

```
  ✗ the hit expander is paint-INERT by construction, not by transparency (R18)
      :1788: expected paint channels reaching the hit expander:
             AddTag: CollectionService:AddTag(expander, "facet-surface-base") |
             CollectionService: … to be paint channels reaching the hit expander:
```

**(c) the hit sweep reverted to `mark.rect`** — reddens **with (a) in place**
(`:1719: expected false to be true`, the non-vacuity line) **and on the
unmutated tree** (same line). The report's stronger claim — that reverting to the
smaller rect makes the sweep see *nothing* — holds independently of (a).

**(d) mine — `expander.Text = ""` deleted from `setHitRect`:** reddens half 1
(`setHitRect writes 'expander.Text = ""': false`).

## Non-vacuity is real

Instrumented the sweep at HEAD. It counts **three** passive overlaps across the
two fixtures:

```
PASSIVE-OVERLAP interactive=false /S/C/After           32x11
PASSIVE-OVERLAP interactive=false /S/C/Before          32x11
PASSIVE-OVERLAP interactive=true  /S/C/Clock/Compact   12x44
```

The last is the M2 review's counterexample, measured. `expect(passiveOverlaps >= 1)`
is therefore satisfied by real geometry, and mutation (c) proves the line is
load-bearing.

## The paint-inert guard's three halves

| half | bites? | evidence |
|---|---|---|
| 1 — born writing five inert properties | **yes** | mutation (d) |
| 2a — `PAINT_CHANNELS` scan of every adapter line naming an expander | **yes** | mutation (b) |
| 2b — every property written to an expander vs the declared inert set | **PARTIAL** | see NEW-H1 |
| 3 — the sheet's tagless-reachable rules enumerated by name | **yes** | adding `{ name = "Button paint", selector = "TextButton", props = { BackgroundTransparency = num(0) } }` to `sheet_model.luau` reddens it: `expected Button paint BackgroundTransparency: 0 to be … 1` |

Half 3's enumeration is accurate: I enumerated all **79** rules in the built
model; the **12** with no class token are the six `BackgroundTransparency`
defaults, three text defaults, `Scroll bar`, and the two `:NonInteractable`
rules — of which exactly the four pinned names carry `TextButton`.

Half 2b's INERT list is honest for the current tree: the enumeration finds
exactly **13** properties (`Active AutoButtonColor BackgroundTransparency
BorderSizePixel Interactable Name Parent Position Selectable Size Text Visible
ZIndex`) and the declared set is those 13 with no dead entries.

---

# A-M1 — the claim made true — **CLOSED**

`requalification.md` §7 now carries a `### SUPERSEDED` block whose **first
sentence** is *"Every figure below is RETRACTED as a saving"* and whose third
sentence is *"Nothing in this block may be quoted as a saving, a share or a
headline; the numbers that mean something are in 'The measurement' above."* So
yes — it forbids quoting the figures as savings, explicitly and up front.

It contains what `84b38bb`'s message said it kept: the five-row subset table with
a **per-row** retraction reason, the superseded method with both defects named,
the 19-row inventory kept explicitly *as an ORDER*, and the candidate ranking with
its KB column marked superseded and its **verdict column marked as standing**. It
states it is a restoration, not a re-measurement, and dates itself to the finding.

The survivor at `task-15-report.md:83-88` is genuinely bannered: a blockquote at
`:79-88` opens `> **RETRACTED 2026-08-21 (M2-review finding A-M1).**`, names both
defects, points at the current pair, and says the table is kept unedited because
it is what the report said on the day. The banner sits above the table inside the
same section (`## The memory table — headline`, lines 77-116). See NEW-L4 for the
one sentence in that section the banner's wording does not reach.

---

# The extra — `surface-ledger-complete` — **CLOSED**

| commit | `lune run tools/lune/check_surface_ledger` |
|---|---|
| `8202a9d` (Round A's endpoint) | **exit 1** — `FAIL — 1 problem(s): top-level export 'preload' is not classified in the surface ledger` |
| `5e8c1d9` (this endpoint) | **exit 0** — `PASS (every public export and nested member is classified; constitution linked)` |

Genuinely red, genuinely pre-existing, genuinely repaired. The gate row
(`gate_manifest.luau:926-931`) runs the check with `&&`, so exit 1 reddened the
whole row — the round's characterisation is exact.

The row's **shape is correct**: five cells matching the table's
`Item | Kind | Pattern / exception | Dispositions | Fragment`, fragment `controls`
(the same fragment as the `Controls` row it sits under), dispositions citing
ADR-0037, the three new `virtualization.spec` pins and `check_types.py`. Content
is honest — `() -> number`, no arguments, no state, force-loads exactly the four,
228 KB [131..313], idempotent by the require cache, never calling it is the
default. **Nit:** this ledger has no `since` column, and the row cites
"ADR-0037 (wave T15)" where the sibling `Controls` row cites "ADR-0037 (0.10.0)".
Nothing is structurally missing (`VERSION = "0.10.0"` and ADR-0037 is the 0.10.0
ADR), but the version is spelled out one row up and not on this one.

---

# Suite arithmetic — **CONFIRMED, by a stronger method than the report's**

The report pins its baseline by content-reverting the other implementer's paths.
I did not need to: the round's commits are contiguous on top of `6628ebd`, so the
parent commit *is* the baseline.

| commit | suite |
|---|---|
| `6628ebd` — the round's parent (DIR4's work included) | **6881 passed** |
| `5e8c1d9` — the endpoint | **6883 passed** |
| delta | **+2** |

Per file, `9a5ea84^` → HEAD: `virtualization.spec` **11 → 12**,
`region_expand.spec` **68 → 69**. Exactly the two new cases, nothing else moved.
The report's number and method are both sound (see NEW-L3 for the one count in a
commit message that does not reproduce).

---

# New findings

## NEW-H1 (HIGH) — the paint-inert guard cannot see the paint properties

The half of the B-H1 close that proves the 44×44 band never paints enumerates
what the adapter writes with

```lua
for prop in string.gmatch(live, "xpander%.([%a]+)%s*=[^=]") do
```

`%a` is **letters only**. Every Roblox property whose name ends in a digit is
invisible to it — and those are precisely the paint properties:
`BackgroundColor3`, `BorderColor3`, `TextColor3`, `TextStrokeColor3`,
`ImageColor3`. The pattern matches `BackgroundColor` and then demands `%s*=`,
finds `3`, and drops the whole occurrence silently.

**Measured.** Adding one line to `src/client/screen_target.luau`'s `setHitRect`:

```lua
expander.BackgroundColor3 = Color3.new(1, 0, 0)
```

— a solid red fill on a framework-owned instance sitting at `hostZ - 1` over the
author's content, the exact object B-H1 is about —

```
region_expand.spec            69 passed
./run-tests.sh              6883 passed
```

**The entire suite stays green.** The same edit spelled
`expander.TextTransparency = 0` (no digit) *does* redden it:
`expected expander properties outside the paint-inert set: TextTransparency to be
…: `. So the guard bites on the properties that do not matter and is blind to the
ones that do. Half 2a does not cover the gap (`PAINT_CHANNELS` is
`AddTag/CollectionService/CLAIM_ATTRIBUTE/claimPaint/syncTags` and a direct
property write matches none) and half 3 enumerates sheet rules, not writes.

This is the same shape as B-H1 itself: an instrument narrower than the rule it is
said to enforce, sitting under a claim the round makes absolutely
("no paint channel EVER reaches it"), inside a green suite.

*Suggested close:* `[%w_]+` instead of `[%a]+`. I verified the permissive pattern
returns the **identical 13 properties** on the current tree, so the change is free
and its equivalence is immediately demonstrable — and it makes
`expander.BackgroundColor3 = …` redden the line instead of a device.

**Secondary, same case, latent:** half 3 skips every selector containing `::` on
the stated ground that "a pseudo-element rule addresses a child modifier this
instance does not have". In Roblox StyleSheets a `::UIStroke` pseudo-element
*creates* the modifier on any instance its base selector matches, so a future bare
`TextButton::UIStroke` paint rule would be excluded from the enumeration rather
than reddening it. I enumerated all 79 rules and none currently pairs a bare
selector with `::`, so this is latent today.

## NEW-M1 (MEDIUM) — the A-H2 purge widened A-M2 instead of leaving it alone

A-M2 (unfixed, correctly out of this round's scope) measured that **no code
anywhere splits collector modes**, that the arms are not interleaved, and that
`REPEATS` defaults to 15. This round wrote the adjective "mode-matched" into
**three new sites**:

| new site | text |
|---|---|
| `tools/check_types.py:24` | "**228 KB [131..313]** of Lua heap, mode-matched" |
| `src/init.luau:54` | "Measured mode-matched over paired rounds: 2,763 KB eager against 2,535 KB" |
| `tests/virtualization.spec.luau:90` | "(mode-matched over paired rounds: 228 KB [131..313] of Lua heap)" |

The *numbers* are the corrected ones and are right; A-M2 explicitly says the
conclusion survives. But "mode-matched over paired rounds" is one of the two
method claims A-M2 measured as not-performed, and a round whose thesis is *"do not
assert as current what this wave retracted"* propagated it into two files that did
not carry it before (including a spec header and a gate check's docstring). The
purge was scoped to 831 KB and the idiom; the sentence it replaced them with
inherits the adjacent open finding.

*Suggested close:* either drop the adjective to what §7's raw samples support, or
fix A-M2 first and keep it.

## NEW-M2 (MEDIUM) — the sweep's "or its own hit floor" arm measures nothing

EXPAND 15's R18 case checks each author node against
`{ n.rect, w.adapter.hitRectOf(path) }`, and the commit message and report both
present that second arm as part of what the case measures ("against that node's
own rect *or* its own hit floor"). Probed at HEAD over both fixtures:

```
NODE false /S/C/After         rect=390x46@0,68  hit=nil  interactive=false
NODE false /S/C/After/Last    rect=69x46@0,68   hit=nil  interactive=true
NODE false /S/C/Before        rect=390x46@0,0   hit=nil  interactive=false
NODE false /S/C/Before/First  rect=80x46@0,0    hit=nil  interactive=true
NODE false /S/C/Clock/Compact rect=40x20@0,46   hit=nil  interactive=false
NODE true  …/Compact/Live     rect=69x46@0,46   hit=nil  interactive=true
```

**Every author node's `hitRectOf` is nil** — the interactive ones are already
80×46 and 69×46, above the floor, so the renderer asks for no expander for any of
them. The arm is dead in both fixtures. It is defensible as a fence for a fixture
that does not exist yet, but the same case applies the "assert it non-zero"
discipline to `passiveOverlaps` and does not apply it here, so the claim reads
wider than the measurement. It is also unlabelled: nothing in the case says the
second arm is currently unexercised.

## NEW-L1 (LOW) — `passiveOverlaps >= 1` does not pin the review's counterexample

Of the three passive overlaps measured above, two (`/S/C/Before`, `/S/C/After`,
32×11 each) come from the chevron's floor reaching 11px into the *neighbouring
regions* and satisfy `>= 1` on their own. If the fill-width compact form ever
stopped sitting under the floor, the non-vacuity line would stay green while the
counterexample the M2 review measured quietly left the fixture. The report's
sentence — *"the exemption is exercised: a fill-width compact form DOES sit under
the floor, which is the counterexample the M2 review measured"* — is true of the
tree but not of the assertion.

## NEW-L2 (LOW) — `INTERACTIVE_SEAMS` is a hand list where a census already exists

`tests/lib/fake_target.luau:1903` already keeps `HANDLER_SLOTS` — the adapter-held
handler census — as `onActivate pointer scrollHandler scrollObserver dragDetector
touchGestures textHandlers hoverEnabled`. The new `INTERACTIVE_SEAMS` adds
`secondaryActivate` and `discloseZone` and **drops `textHandlers`,
`scrollObserver`, `hoverEnabled`**. A node holding only `textHandlers` would read
passive and be allowed under the floor.

Measured as **currently not exploitable**: I rebuilt `ringScreen(true)`'s compact
form as a fill-width `UI.TextField` and the case correctly reddened —
`interactive=true`, because the fake target gives a TextField an `onActivate`
(node keys: `alive class onActivate parentRoot path presentationOffset … z`). So
this is latent, not live. It is worth recording only because the *same round*
derived A-H1's deferred set from source rather than listing it, and did not apply
that discipline here.

## NEW-L3 (LOW) — two counts in the round's own prose do not reproduce

- `9a5ea84`'s message: *"region_expand 69 -> 70 cases"*. Measured: **68** at
  `9a5ea84^`, **69** at HEAD (`grep -c "it("` agrees at 69). The suite total and
  the +2 delta are both right, so this is message-only.
- The report: *"`grep -c supersed` on that file: **0 → 5**"*. Measured on
  `requalification.md` at HEAD: `grep -c supersed` = **2**, `grep -ci supersed` =
  **8**. Neither is 5.

Both are trivial in isolation. They are listed because this is the round whose
subject is numbers stated wider than their evidence, and it is the second round in
a row (`84b38bb`'s "kept and marked SUPERSEDED") where a commit message asserted a
count nobody re-ran.

## NEW-L4 (LOW) — the `task-15-report.md` banner is number-scoped, and the section's falsified-idiom claim survives it

The banner reads *"Every **number** in this section is SUPERSEDED and none of it
is a saving."* Ten lines below it, still inside the bannered section
(`:106-114`), the report states as measured fact:

> `type M = typeof(require("@self/controls/table"))` costs **0 KB and does not load
> the module** while keeping `M.Spec` as a type, so all 19 typed signatures survive a
> deferred require

That is the falsified idiom, and it is not a number, so the banner's own wording
does not reach it. The same document falsifies it 160 lines later (`:272-279`), so
a full reader is not misled — but A-H2's stated standard is "named as retracted
**where it was quoted**", and at this site it is not.

## NEW-L5 (LOW, informational) — the round shipped no ledger entry of its own

None of the five commits touches `progress.md` or `t16-triage.md`. The M2-fix
progress line (`progress.md:1008`) and the R18 solver-side booking
(`t16-triage.md:26`, *"the real fix reserves markW + the floor's overhang
SOLVER-side · extraction charter"*) arrived in `2d1aed2`, a later commit by
another agent. Same gap the M2 review recorded against `9a32399`; closed in
effect, but not by this round.

---

# New-breakage scan of these five diffs

**Clean.** Every hunk was read (`1f0b99d` 2 hunks, `08eb931` 5 files, `9a5ea84`
3 hunks, `509d747` and `1f9e32c` additive-only).

- Nothing in `src/` changed except comments — verified against the diffs; the
  only `src/` files touched are `init.luau` (comment/docstring text) and no
  behavioural line moved.
- **No stale grep pins.** The three removed/renamed test titles (`no lazy require
  fires during dense-scroll steady state`, `Facet.preload() force-loads the
  deferred four and is idempotent`, `covers any node of the standing form`) appear
  **nowhere** in `tools/`, `tests/`, `docs/`, `artifacts/` or `.superpowers/`.
- The `perf-requalification` gate row's full run string still exits 0 against the
  edited `requalification.md` and `capture-plan.md`.
- `check_surface_ledger` PASS · `check_source_size` PASS · `check_comment_codes`
  PASS (0 orphans / ceiling 0; 25 codes / ceiling 25) · `check_doc_style` PASS ·
  `check_types` PASS · `check_types --selftest` PASS with both targets restored
  byte-identical · `stylua --check` clean.
- `check_brand_drift` / `check_call_shape_drift` were not run: both compute
  `STUDIO_ROOT = REPO/../../..` and need the sibling Rascal Rally repo, so they
  are `FAIL_ENVIRONMENT` in a scratch export (the M2 review's A-L5, unchanged).
- The double-load instrument is safe: `src/init.luau` has no load-time side
  effects, the recorder delegates to the cached `require` so no module runs twice,
  and the file's own registry-baseline case still passes after the three new ones.
- **Rascal Rally:** untouched and correctly so — nothing in these five commits
  changes a public contract, default, behaviour or distribution output. `preload`
  gained a ledger row (documentation) and `docs/reference/api.md` was not edited
  by this round. A-M3's standing observation is unchanged: RR carries no test that
  would notice a silent revert to eager.

---

# Counts

| severity | n | ids |
|---|---|---|
| HIGH | 1 | NEW-H1 |
| MEDIUM | 2 | NEW-M1, NEW-M2 |
| LOW | 5 | NEW-L1 … NEW-L5 |

No BLOCKER. No correctness regression. Every finding is on an instrument, and
four of the eight are on the same case (`the hit expander is paint-INERT …` and
its sibling sweep).

# The single most important issue

**NEW-H1.** The guard written to prove structurally that the 44×44 hit expander
cannot paint enumerates its property writes with `[%a]+`, which silently drops
every property name ending in a digit — `BackgroundColor3` first among them.
Planting `expander.BackgroundColor3 = Color3.new(1, 0, 0)` in `setHitRect` leaves
the full suite at **6883 passed**: a framework-owned instance, at `hostZ - 1`,
painting a solid fill over the author's content, invisible to the very instrument
the round built to make that impossible. It is B-H1's own defect one layer down —
"the fence measured the smaller of the mark's two rects" became "the fence reads
the properties that cannot paint". The fix is one character class, and the
permissive pattern returns the identical thirteen properties today, so the change
can be shipped with its own equivalence proof.
