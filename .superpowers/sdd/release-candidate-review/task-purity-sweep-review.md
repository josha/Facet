# Declarative-purity sweep — fresh-context review

**Verdict: PASS WITH FINDINGS.** 1 high, 3 medium, 4 low. Nothing here warrants a revert.
The round is honest, the lint is a real standing guard, both reverts against the audit hold
up under re-measurement, and every defect fix is red-first. One regression escaped, in the
exact shape the brief pointed at: a swept literal that is pixel-identical at Studio Neutral
and **4 px wrong on a television**, in one of the seven swept files the always-on overflow
sweep does not cover.

**Seat:** read-only. Every number below was measured in content-pinned pairs built with
`tools/mkpair.sh` at refs resolved at measurement time. Nothing in either working tree was
modified. Note for the record: Facet `HEAD` moved from `878fd83` to `fe7c3db` (a
`progress.md` commit) *during* this review, and a staged modification to
`task-renderer-split-report.md` sits in the index — another seat is live in this repo.

| pin | sha | measured |
|---|---|---|
| `PIN_FACET` (report's pin) | `b3f9c89a46424d1122d9d78927e167fc652a953d` | **7057 passed**, exit 0 |
| `PIN_RR` | `ca50fdbdf1c3cf63ed26c6d01b85def7cc7420eb` | **3469 passed**, exit 0 |
| Facet `HEAD` at review time | `fe7c3db77add4f29b2fccc4b3ad363216e350032` | all guards PASS |

---

## 1. The lint flip — VERIFIED, and it is a real guard

**Red-first reproduces exactly.** The `HEAD` lint (`check_theme_drift.luau` +
`check_theme_drift_cli.luau` from `b3f9c89`) run unmodified against the pre-sweep tree:

```
theme drift: 365 violation(s) — 0 framework, 365 example
```

Identical at **both** `82b0406` (the report's stated baseline) and `67507f7` (the true
`a81beb2^`), so the baseline choice is not load-bearing. Green now, same command, byte-for-byte
the string the report quotes:

```
theme drift: clean — framework 45 files / 38158 lines (1 allowlisted);
             examples 165 files / 70460 lines
             (11 marked THEME-OPT-OUT, 4 PROBE-EXEMPT across 1 listed files)
```

**Exact token-value equality — proved completely, not sampled.** The brief asked for ten
spot-checks; a complete proof was cheaper. I normalised every one of the 48 files in
`a81beb2` on both sides by resolving `textSize` / `gap` / `rowGap` / `padding` name-strings
back to their neutral-snapshot numbers (`caption 12, label 14, body 16, heading 20, title 24,
control 18, strong 16, numeral 18; xs 4, s 8, m 16, l 24, xl 40, gutter 8`, read from
`src/themes/package` + `src/themes/snapshot`), stripped comments, flattened whitespace, and
diffed:

```
FILES WITH SEMANTIC RESIDUAL: 0 of 48
```

**Zero.** All 353 swaps are value-identical under Studio Neutral by construction, and nothing
else moved in those files. (The ten diverse swaps the brief asked for, taken from the seven
files the sweep does *not* cover, are: `padding 16→"m"`, `gap 8→"s"`, `textSize 24→"title"`,
`textSize 14→"label"`, `textSize 12→"caption"`, `padding 4→"xs"`, `gap 4→"xs"`,
`textSize 16→"body"`, `padding 24→"l"`, `padding 8→"s"` — every one exact.)

The mechanism is right in the source: `NAMES_FOR[vocabulary][n]` is an exact-value lookup, so
a literal no name resolves to is silent by design.

**Markers work and are counted.** Planted live against the pinned pair:

| plant | result |
|---|---|
| `gap = 8` in `flow_wrap.luau` (a taught example) | **1 violation** — red |
| …+ `-- THEME-OPT-OUT: <22-char reason>` | clean, `11 → 12 marked THEME-OPT-OUT` |
| …reason shortened to `short` (<12 chars) | **1 violation** — a suppression comment is refused |
| …`-- PROBE-EXEMPT: <reason>` instead | clean, `4 → 5 PROBE-EXEMPT` |
| `gap = 6` (no step names 6) | clean — the pending finding, silent on purpose |
| `gap = 8, padding = 16, textSize = 12` planted in **RR** `src/client/AssistPilot.luau` | clean — games are out of scope, permanently |

**The disclosed no-op check is real.** On the pre-sweep tree, `lune run
tools/lune/check_theme_drift` exits **0** while `check_theme_drift_cli` exits **1**. The
report was right to call the `d3a-help` row a check that proves nothing. See MED-1 for what
`878fd83` left behind.

---

## 2. The two reverts against the audit — BOTH HOLD

### `minColumnWidth`: the packing floor is real (LOW-1 on the count)

Setting the six sponsor `Controls` grids back to `"intrinsic"` on the final tree and running
the overflow sweep: **7 failed, 88 passed** — five sponsor scenarios plus *both* stale-ledger
guards ("every waived finding still fires", "every ledger row still fires").

| scenario | solver findings |
|---|---:|
| `sponsor_motion` | 70 |
| `sponsor_avatars` | 32 |
| `sponsor_celebration` | 25 |
| `sponsor_markers` | 12 |
| `sponsor_billboard` | 5 |
| **total** | **144** across **5** scenarios |

The "collapses the `fill` stage column to zero" claim is directly evidenced: 48 zero-width
boxes in the failure text (`0x44px` ×36, `0x48px` ×3, `0x38px` ×4, `0x36px` ×3, `0x32px`,
`0x22px`). The revert is correct and the audit's "17 stale sites" does not survive.

**LOW-1:** the report says *"70 solver findings across five scenarios."* 70 is exactly
`sponsor_motion`'s own count; the set is 144. One scenario's number was reported for the
whole. Direction and conclusion unaffected.

### The two non-reactive `:get()` sites: the null result holds, and the guard bites

`StoryFlow.luau:1290` — inside `StoryFlow:step(dt, nowS)`, the per-frame step — calls
`self:_refreshTicker()`, which is where `conditions.sizeClass:get()` lives. It is a live
per-frame read; the audit's "a rotation never updates them" does not reproduce. Confirmed by
source and by the guard:

**The guard case bites.** Applying the "obvious optimization" the commit message names —
deleting `self:_refreshTicker()` from `step` so the republish rides the feed instead —

```
✗ a rotation into compact re-publishes the ticker at the compact cap
    expected after the turn: 4 to be after the turn: 2
```

Exactly the defect the audit described, reintroduced and caught. (One neighbour,
"the age fade is ONE composite write", falls with it — the mutation is coarse, the pin is not.)

---

## 3. The six defect fixes — ALL SIX REPRODUCE RED-FIRST

Four Facet defects, reverting only the three source files to `5e50c47^` on the `b3f9c89` tree:
**4 failed, 7053 passed** — a precisely targeted set.

| # | defect | red-first, measured here |
|---|---|---|
| 1 | wardrobe turntable ignores reduced motion (`env:get(k) == true`) | `expected yaw moved under reduced motion: true to be … false` |
| 2 | wardrobe section names frozen at boot locale | `expected section label locales after the flip: en to be … xa` |
| 3 | shipped showcase clips its theme chip and not its demo chip | `expected chip shows the whole name: false to be … true` |
| 4 | `p2_cartwheel` per-frame `setPresentationTransform` | `expected imperative transform writes on the footer: 61 to be … 0` |
| 5 | RR ticker sits inside the card at large text | `@0 clears=true \| @4 clears=true \| @10 clears=false \| @14 clears=false` — the report's quoted string, verbatim, 1 failed / 3468 passed |
| 6 | RR autoscroll band | reds only under mutation — see **MED-3** |

**LOW-2:** the report and commit both say *"31 imperative writes in a 30-frame window"* and
*"31 writes; now 0"*. The shipped case runs 60 frames and reports **61**. Same mechanism (one
write per frame, plus one at arrival); the cited number came from a shorter window than the
case that ships. The `→ 0` half is correct.

---

## 4. The two bugs caught by reading the diff

Both shipped in the correct form — the literal **kept**, with a `-- THEME-OPT-OUT:` marker
carrying the reason at the site. I then measured whether the *wrong* form (the one the lint
would have demanded) is visible to the suite.

| site | wrong form | suite result |
|---|---|---|
| `variable_extents.luau` `METRICS.gap = 4` → `"xs"` | metric name added to a `text.lineBox` number | **11 failed** — `attempt to perform arithmetic (add) on number and string` |
| `foreign_content.luau` `textSize = 18` → `"control"` | role name written to a raw `TextLabel.TextSize` | **7057 passed, exit 0** — invisible |

So: the report's sentence *"The last two were caught by reading the diff, not by the suite"*
is exactly right for `foreign_content` and **wrong for `variable_extents`** (LOW-3), where a
suite-visible pin already exists and is strong.

**MED-2:** `foreign_content` has **no mechanical guard at all**. The wrong form passes the
whole suite *and* passes the lint (a name is what the lint asks for). The only thing standing
between this corpus and a live runtime type error is a comment that nothing checks. The
report is honest that a green suite would have shipped it, but it neither adds a pin nor
books one. A future author "tidying" that marker reintroduces the defect silently.

---

## 5. Numbers — RE-DERIVED, EXACT

Independent counter over `examples/**`, comment lines excluded, on the four prop patterns:

| ref | raw | named | total | raw % |
|---|---:|---:|---:|---:|
| `82b0406` (pre-sweep) | **519** | **797** | 1316 | **39.4 %** |
| `67507f7` (`a81beb2^`) | 519 | 797 | 1316 | 39.4 % |
| `b3f9c89` (post) | **166** | **1150** | 1316 | **12.6 %** |
| RR `ca50fdb` `src/**` | 20 | 62 | 82 | 24.4 % |

Every figure the report gives reproduces to the digit, and the set is internally exact:
519 − 166 = **353 swept**, 797 + 353 = 1150, total invariant at 1316. The showcase now
practises better than the game it teaches (12.6 % vs 24.4 %), which was the charge.

The audit's 539/799 differs from the report's 519/797 because the two used different counters;
the report's is the one that reconciles with the lint (364 reported + 147 unreachable + a few
zero-valued = the raw pool) and is the one I could reproduce.

**Zero `src/**` changes** across `a81beb2^..fe7c3db` — `git diff --stat` on `src/` is empty.
No consumer migration is owed, and the lint's game exclusion is proved above rather than
asserted.

---

## 6. Held files and guards

`src/render/commit_walks.luau`, `src/render/renderer.luau` and
`tests/commit_walks_seam.spec.luau` are **untouched** across the whole range
(`a81beb2^..fe7c3db`, empty diff).

At `HEAD` (`fe7c3db` / RR `ca50fdb`), from inside a fresh pair:

| guard | result |
|---|---|
| `check_theme_drift_cli` | PASS |
| `check_example_drift_cli` | PASS (74 files, 25305 lines, 440 semantic role uses) |
| `check_docs_cli` | PASS |
| `check_registration_cli` | PASS |
| `check_prop_parity_cli` | PASS |
| `check_manifest_integrity.py` | PASS |
| `check_source_size.py` | PASS |
| `stylua --check src tests tools bench examples` | PASS |
| RR `stylua --check src tests tools` | PASS |
| RR suite | 3469 passed |

A note on the brief's "`check_theme_drift_cli` both repos": there is no RR copy and there
should not be — the lint is Facet-only and by design never scans a game. The RR-side surface
is the two gate rows that `cd` into RR, and the Facet CLI they now call passes.

The overflow-sweep **waiver ledger was not touched** by any of the five commits
(`tests/overflow_sweep.spec.luau` changed only its route-census pin, 381 → 385). Its two
stale-waiver guards were seen to fire under the `minColumnWidth` mutation, so for the 41
scenarios the sweep does cover, its green is bidirectional: no new overflow, and no waived
overflow silently fixed.

---

## 7. New-breakage scan at the console rung

**HIGH-1 — a swept literal moved geometry on a television, and nothing in the suite can see it.**

*The sample.* 41 of the 48 files `a81beb2` touched are gallery scenarios, and all 41 appear in
`overflow_sweep.spec.luau`'s `SCENARIOS`, which sweeps `console-ten-foot 1920×1078 / Large /
Gamepad` × 4 text preferences × 7 theme packages on every run. **Seven do not**:
`performance/lab/{rows,overlay,levers,perf_lab}.luau`, `gallery/client/init.client.luau`,
`table_phaseb/client/init.client.luau`, and `themes/{custom_control,ornate_gauge}.luau` — the
last two are in fact reached through the `theme_authoring` scenario, so the real blind spot is
**six files, ~30 swapped sites**. That is the sample I took to the console rung.

*The measurement.* Same harness, same scenario, same seed; only the tree differs
(`67507f7` pre-sweep vs `b3f9c89` post):

| view | pre-sweep | post-sweep | delta |
|---|---|---|---|
| console-ten-foot 1920×1078 Large, slot 60 | content **77 px** (17 over) | content **81 px** (21 over) | **+4 px** |
| console-ten-foot 1920×1078 Large, slot 80 | content **82 px** (2 over) | content **86 px** (6 over) | **+4 px** |
| desktop-standard 1232×1067 Medium | 0 findings | 0 findings | none |

Pixel-identical at near, 4 px wrong at ten foot — the precise shape the brief named.

*Cause, isolated.* Reverting **only** `examples/performance/lab/rows.luau` restores 77/82
exactly. Reverting **only its two `padding = 4` → `padding = "xs"` swaps** — leaving the
`gap`/`textSize` swaps in place — also restores 77/82 exactly. `"xs"` is 4 at Studio Neutral
(so the lint's pixel-identity guarantee held) and **6** under the `Large` display class's 1.5×
ladder: 2 px per side, 4 px per row.

*Why the predictor did not follow.* `rows.heightFor(false, 1.5, nil, nil, 0) = 60` in **both**
trees. The slot is predicted from `rows.ROW_PADDING_V = 16`, a raw constant that `heightFor`
does **not** scale — and it sits inside the very `-- PROBE-EXEMPT BEGIN:` fence `b3f9c89`
added, whose own comment reads *"the record of getting the prediction wrong three times (the
type scale, then the theme, then the text preference)."* The sweep made it wrong a fourth
time, in the same commit range that fenced it, and the fence was written without re-measuring
the file the previous commit had just changed.

*Severity.* The perf lab already refused to mount at this rung pre-sweep (17 px over), so no
cell flipped from mounting to refusing in my sample, and this is instrument rather than
shipped product UI. But: the direction is the one `rows.luau`'s own header calls the dangerous
one — *"a slot a few px too short paints one row over the next, which is the defect this whole
constant exists to prevent"* — the lab's ten-foot calibration is now stale, and the round's own
claim (`a81beb2`: *"The overflow sweep runs every one of these surfaces … and it is what caught
every one of the nine"*) is **false for exactly the six files where the one regression landed**.

The systemic form, which is the part worth writing down: **the lint's "pixel-identical by
construction" guarantee is a Studio-Neutral, scale-1.0 guarantee only.** Any swept site whose
geometry is predicted by an adjacent *unswept* raw constant silently de-calibrates on the
ten-foot ladder. `rows.luau` is the proven instance; it is also the class to grep for.

**Recommended follow-up (not blocking):** either add `examples/performance/lab` to the sweep's
corpus, or teach `heightFor` to resolve `ROW_PADDING_V` from the same snapshot the row now
spends — and, in general, make "does a raw constant predict this box?" a question the swept-site
checklist asks.

---

## Other findings

**MED-1 — three gate rows still call a check that cannot fail.** The round found the class
and closed two thirds of it.

* Measured: `lune run tools/lune/check_theme_drift` exits **0** on a tree carrying 365
  violations; `check_theme_drift_cli` exits **1** on the same tree.
* `878fd83` ("two rows stop calling the check that cannot fail") re-pointed `d3a-help` and
  `d6-segmented`. At `HEAD` the row **`controls-semantic-roles` still spells the old form** —
  a third row, unreported.
* Same class, entirely unreported: `lune run tools/lune/check_docs` exits **0** on a tree
  where `check_docs_cli` exits **1** (measured by truncating `docs/reference/api.md` to half).
  Rows **`d3b-callout`** and **`d6-segmented`** both call the bare form. `check_docs.luau` ends
  in `return check_docs`, exactly like `check_theme_drift.luau` did.
* A one-line sweep — "every `lune run tools/lune/check_*` in `gate_manifest.luau` names a
  module that does not end in `return`" — would close the class instead of one row at a time.

**MED-2 — `foreign_content` has no guard.** See §4.

**MED-3 — the RR autoscroll red-first is a mutation, not the shipped pre-fix source.**
Reverting `RacerList.luau` + `TableMetrics.luau` + `init.luau` to `ca50fdb^` leaves
*"the autoscroll band is the HOST's 40, not the screen-class 44 this package used to force"*
**green**. Forcing `autoscroll = { bandH = 44 }` reds it with `expected 42px deep: dwelling to
be 42px deep: idle` — the report's quoted evidence, exactly. So the case is mutation-proven
and pins the new contract correctly, but at its own 844×390 fixture the deleted option already
resolved to the framework's 40, so it never witnessed the shipped defect. The commit's wording
("with `bandH = 44` …") is accurate and does not overclaim; what is missing is a case at a
configuration where the screen size class and the host shape actually disagree. Worth booking,
since sub-finding (a) — *"branched on the SCREEN's size class rather than the HOST's shape"* —
is the one of the three with no witness.

**LOW-1, LOW-2, LOW-3** — see §2, §3, §4.

**LOW-4 — small imprecisions in the write-up.**
* The report says `StoryFlow:tick`; the per-frame method is `StoryFlow:step` (`:1290`).
* "ONE MARKER COVERS ONE LITERAL" is really *one marker covers one reportable **line***:
  `optedOut += #found` lets a single marker excuse two nameable literals on the same line. No
  shipped site depends on it (the 11 opt-outs are 11 literals across 9 sites, matching the
  report's own table), and a marker is correctly *not* consumed by lines with nothing to report.
* `d489832`'s message says 364 at the flip; the report says 365 (364 literals + 1 header-guard
  finding). **365** is what reproduces.
* `a81beb2`'s message says "355 SITES"; the report says 353. 364 − 11 opted out = **353** is the
  figure that reconciles.

---

## What was verified and is clean

Suites at the stated pins (7057 / 3469, both exit 0, from a content-pinned pair). The
red-first lint at 365/0-framework. Complete value-identity of all 353 swaps (0 semantic
residual over 48 files). Marker semantics in six directions including two negative controls.
Game-tree exclusion, planted. Both audit refutations, re-measured. Six of six defect fixes
red-first. The null-result guard, mutated and seen to bite. Corpus share re-derived to the
digit by an independent counter. Zero `src/**` changes, so no consumer migration is owed.
Held files untouched. Every guard PASS at the final commits in both repos. And the
waiver ledger untouched, with its stale-waiver guards seen to fire.

The round's most valuable habit is the one it kept under pressure: it recorded two places the
audit was **wrong** (`minColumnWidth`, the two `:get()` sites) and guarded the null result
rather than dropping it. Both survive re-measurement. The one thing it did not do was ask
whether its own instrument could see the files it was changing — and that is where the single
regression is.
