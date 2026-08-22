# Native-style default flip — fix round 1, scoped re-review

**Scope.** Facet `b52d220` and Rascal Rally `1509383`, against the fix-round section
appended to `task-native-default-report.md` (`4f86ac5`), answering
`task-native-default-review.md` (1 MAJOR, 2 MEDIUM, 6 LOW, 2 INFO).

**Method.** Both shared trees were treated as read-only; **every number below was
produced in private `git archive` exports of the exact named commits**, in
`.../scratchpad/rr1/`. Rascal Rally ran in real two-tree layouts
(`T-*/GameStudio/ui/Facet` + `T-*/games/RascalRally/code`), never symlinked. Facet
HEAD moved during the review (`4f86ac5` → `66b49de`, a progress/triage bookkeeping
commit touching no source); it contributed to nothing here. Fourteen mutations were
run — nine Facet, five Rascal Rally — each against an unmutated A-side first.

**VERDICT: NOT all-addressed — APPROVE with findings.** Every disposition was
attempted and most landed cleanly. The two headline findings are *substantially*
narrowed but not closed: **MAJOR-1 and MEDIUM-1 each have a residual of the same
class, one level down**, and in both cases the report's own wording claims the
class is closed. MEDIUM-2 and all six LOWs are addressed (LOW-1 with a residual of
its own shape). Every arithmetic claim reproduces exactly. Nothing here blocks the
flip; the two residuals should be closed before Step 14, and both are one-line fixes.

| severity | count |
|---|---|
| BLOCKER | 0 |
| MAJOR | 1 (residual of the original MAJOR-1) |
| MEDIUM | 1 (residual of the original MEDIUM-1) |
| LOW | 5 |
| INFO | 1 |

---

## 1. What reproduced, exactly

| claim | measured | result |
|---|---|---|
| Facet parent alone 6939 | export `fa0be0c`, `lune run tests/run` | **6939 passed, 0 red** ✅ |
| Facet 6949 (+10) | export `b52d220` | **6949 passed, 0 red** ✅ |
| …and as an overlay | export `fa0be0c` + this round's six files | **6949**, identical ✅ |
| `screen_target.luau` 193,992 → 193,714 | `wc -c` at `fa0be0c` / `b52d220` | **193,992 → 193,714 (−278)** ✅ |
| `check_source_size` agrees with the ledger | `193,714 (6,286 to the cap)` | ✅ |
| RR baseline 3465 | RR `4e271c3` + Facet `b52d220` | **3465 passed, 0 red** ✅ |
| RR 3461 (−4) | RR `1509383` + Facet `b52d220` | **3461 passed, 0 red** ✅ |
| guards | `check_source_size`, `check_doc_style`, `check_types`, `check_theme_artifacts`, `check_library_purity`, `check_boundary`, `check_docs_cli` (9 docs / 81 anchors), `check_example_drift_cli` (74 files), `stylua --check src tests tools examples` | all **PASS** in the export ✅ |
| `promotion-readiness.json` still parses | `json.load` | ✅ |

**The −4 decomposition is exact, and I re-derived it rather than taking it.** The
`== true` matrix loop generates **exactly 5 cases per pair** (measured off the
baseline file: `neither set`, `only the PRE-RENAME name`, `only the Facet-era name`,
`BOTH set and disagreeing`, `a non-boolean value is not truthy`); adding
`p.key == "nativeStyle"` to the skip drops **5**. The tri-state `describe` goes
**6 → 7** cases: two added (`THE BOOLEAN READER IS GONE`, `a NON-BOOLEAN on the new
name lets the OLD name's rollback through`), one deleted (`the boolean predicate
still answers its own question`, which went with the function). −5 + 2 − 1 = **−4** ✅.
Running the two touched spec files alone confirms the whole delta lives there:
**45 → 41**.

**One label is wrong, and the numbers are right.** The report's table says the
isolated export was *"Facet HEAD `462a1ca` + this round's files"* with *"HEAD alone:
6939"*. `462a1ca` alone measures **6925**, not 6939; the commit that measures 6939 is
**`fa0be0c`, the true parent of `b52d220`**. The `+10` holds either way (6925 → 6935
on the `462a1ca` base). See LOW-A.

### 1.1 The ledger row re-record — honest, and it says the load-bearing sentence

The row reads: *"**286 characters from the trigger**, and the vocabulary module is
still the one owed — **the seam that answered this review is not the seam this row is
about**."* That is exactly right and exactly the sentence a re-record earns its
credibility with: the 278 characters came back from extracting `paintPlan`, which is
not the `screen_vocabulary.luau` extraction the row has owed since `c4d0591` left the
file 8 characters from its 194,000 trigger. The previous entry is nested rather than
overwritten, so the chain is intact. (One cosmetic defect in the nesting — LOW-C.)

---

## 2. Item-by-item verification

### 2.1 MAJOR-1 — the extraction is real, all five pins bite, and the original bypass now reddens

`native_style.paintPlan(opt, isReducedMotion, available)` is genuinely pure and
genuinely the whole decision. The `screen_target` block is now a call, a
`plan.opt` read and `if plan.native then`. **Behavioural equivalence to the pre-fix
code holds** on every branch (`resolved ~= false and capable` ≡ `nativeOpt ~= false
and available()`; transitions identical including short-circuit order) — with one
un-named delta, LOW-E below.

**The five shape checks each bite, verified individually:**

| pin | mutation | result |
|---|---|---|
| 1 — exactly one `paintPlan` call | second call added | **red**: `paintPlan is called 2 time(s), not once` |
| 2 — exactly one `.nativeStyle` read off `opts` | second read added | **red**: `the opt is read 2 time(s) off opts, not once` |
| 3 — no capability probe in the target | *(via the bypass below)* | **red** |
| 4 — no mention of the flag | `local _flag = native_style.DEFAULT_ENABLED` | **red**: `the target names the default flag` |
| 5 — the branch is `if plan.native then` | *(via the bypass below)* | **red** |

The pattern `%.nativeStyle[^%w_]` is doing what the comment claims: `screen_target`
holds exactly three `nativeStyle` occurrences — the `Opts` type field (no leading
dot), `adapter.nativeStyleInfo` (excluded by `[^%w_]`), and the one live read.

**The original reviewer's exact bypass, re-applied:** call `paintPlan` into
`_ignored`, re-derive the pre-flip rule underneath, restore the three-clause
transitions expression.

```
✗ `screen_target` OBEYS the plan: one call, one opt read, no probe, no second rule
    expected consumer off contract:the opt is read 2 time(s) off opts, not once;
    the target still probes the capability itself — that gate belongs to the plan;
    the native branch is not `if plan.native then` — the plan is computed and ignored
1 failed, 6948 passed
```

Three pins in one message, verbatim as the report claims. Previously **6905 passed,
0 failed**. ✅

**`DEFAULT_ENABLED` flipped back to `false`, full suite: 4 failed** — exactly the
four named, two of them plan-level (`NO opt plans SHEET PAINT`, `the plan carries the
RESOLVED opt`). The review measured 2. ✅

**The opt-read-count lock's second half is TRUE.** `plan.opt` really is the resolved
value and the raw opt really is unrecoverable *from the plan*: `planFor(nil).opt ==
planFor(true).opt == true`, and a config table passes through by identity. There is
no plan field from which "was one passed" can be reconstructed. Confirmed by reading
`paintPlan` and by the shipped case.

**The motion-fact-as-function claim is TRUE, and its pin bites.** `paintPlan(false,
…)` returns before `isReducedMotion` is ever named, so an opted-out target never
calls a consumer's deprecated closure; the call-counting assertion (`asked == 0`)
reddens the moment the fact is computed eagerly (mutation: hoist `reducedNow` above
the early return → `✗ transitions are OPT-IN, and reduced motion wins over the opt`). ✅

**What is NOT closed — see MAJOR-A.** The five pins constrain the consumer's *shape*.
Nothing pins the *argument*, and the flip is still revertible in one line with the
full suite green at the identical count.

### 2.2 MEDIUM-1 — both named mechanisms are closed, and the fifth-site class is not

* **The hole reproduces at the parent.** RR `4e271c3` + the reviewer's
  `src/client/FacetFifthGui.luau` (`nativeStyle = if FacetFlags.nativeStyleOn() then
  true else nil`) → **45 passed, 0 red** in the two touched spec files. The hole was
  real. ✅
* **It reddens now.** Same file against RR `1509383`:
  `✗ a tinted plate with no surface still has a FILL under native stylesheets` —
  `expected 4 of 5 nativeStyle sites gated to be 5 of 5`. ✅
* **`nativeStyleOn` is gone.** No definition anywhere; the only survivors are prose
  in the module header and the two specs, plus the two assertions that keep it dead
  (`loadFlags({}).nativeStyleOn` is `nil`, and the source carries no
  `function FacetFlags.nativeStyleOn`). The behavioural half and the source half are
  both present, which is the right pair. ✅
* **No false positive.** A *correctly* written fifth site
  (`nativeStyle = FacetFlags.nativeStyleOpt()`) stays **green**, so the new floor
  admits new sites rather than freezing the file list. ✅
* **The floor is a floor for the READER, not for the CONTRACT — see MEDIUM-A.**

### 2.3 MEDIUM-2 — addressed

Concern #1 is corrected in place and marked as a fix-round correction: *"no TEXT
place source sets it; the two `.rbxl` places are unverifiable from disk and must be
read in Studio"*, with the canary mitigation upgraded from advisory to **REQUIRED**.
That is exactly the disposition asked for. ✅

### 2.4 The six LOWs

| # | disposition | verified |
|---|---|---|
| LOW-1 | exemption pin anchored to `screen_target%.new%(%s*%b{}` | **partly** — the whole-file search is gone, but a comment *inside the argument list* still satisfies it (LOW-B) |
| LOW-2 | `artifacts/perf/` → `bench/perf_budgets.json` + `artifacts/performance-stress-places/` | ✅ in the source comment and both report mentions; both paths exist |
| LOW-3 | RR boot comment restated with the new polarity and the tri-state | ✅ |
| LOW-4 | `stillRequired` device row restated, and it now tells the canary to read `UseFacetNativeStyle` first | ✅ JSON still valid |
| LOW-5 | `host.Opts.nativeStyle` doc states the default and the opt-out | ✅ shipped — in `c4d0591`, see §3 |
| LOW-6 | `voteOf`: a non-boolean at the new name falls through to the old one | ✅ four assertions incl. garbage at both names; one new seam, LOW-D |

### 2.5 Not fixed, with reasons — all three are the right call

INFO-1 (`table_phaseb`) and INFO-2 (the showcase place hardcodes `true`) were
record-only in the original dispositions and are recorded. The escalation of INFO-2
to *"device-evidence policy and the controller's call, not an implementer's"* is the
correct escalation, not a dodge. The deliberately-left stale transitions comment in
`screen_target.new` is correctly reasoned: it sits inside the concurrent
paint-family round's diff context and rewriting it would have merged the two rounds'
hunks in a shared tree. Its content is now merely redundant, not wrong.

---

## 3. LOW-5 and the authorship boundary between `b52d220` and `c4d0591`

The report discloses that its `host.luau` hunk was swept into the *other* round's
commit. **Verified in both directions.**

* **The content is correct and shipped.** `c4d0591` carries exactly:
  `-- the Roblox StyleSheet paint path. `nil` = the library default, which IS /
  sheet paint since 2026-08-21 (ADR-0040 B-15); `false` is the opt-OUT and / wins
  over everything. Forwarded verbatim to `screen_target.new`.` That is the LOW-5 fix,
  accurate on all three clauses. `host.Opts` still types the field `boolean?`, which
  the report correctly declines as a public-surface decision.
* **Nothing else of this round is in `c4d0591`.** Its other ten files are all
  paint-family: `displaySize`/`paintForDisplay`, `sheet_model`, `theme_controller`,
  ADR-0039, `ten_foot_metrics.spec`. Its `api.md` hunks contain **zero**
  `nativeStyle`/native-paint lines. Its `screen_target.luau` hunks are `displaySize`
  and `baseStyle` only.
* **Nothing of the other round is in `b52d220`.** Its six files are all
  native-default. It does **not** touch `host.luau` at all. Its `screen_target.luau`
  hunk is the paint-decision block only; `c4d0591`'s `baseStyle`/`sheet_model.build`
  lines appear as unchanged *context*, never as changes. The `SOURCE_CAP_LEDGER` row
  nests `c4d0591`'s re-record inside its own rather than overwriting it.

**Verdict: the contamination is one-directional, one hunk, correct, and disclosed.**
The report's framing — *"the exact accident `commit_isolated` exists to prevent,
running in the other direction"* — is the right description and the right thing to
have written down.

---

## 4. Findings

### MAJOR-A — the five pins lock the consumer's SHAPE but not the ARGUMENT, and one line still reverts the flip with a fully green suite

The report's lock is stated as: *"a re-derivation needs the **raw** opt, there is
exactly one legal place to get it, and `plan.opt` is the **resolved** opt, from which
'was one passed' cannot be recovered."* The second half is true (§2.1). The first
half is not: the pins constrain how many times the raw opt is read and what shape the
branch takes — **not what value is handed to the plan.**

**Measured, and it is the most natural spelling of the bypass, not a contrived one:**

```lua
local raw: any = opts and (opts :: any).nativeStyle
local plan = native_style.paintPlan(if raw == nil then false else raw, isReducedMotion)
local nativeOpt: any = plan.opt
if plan.native then
```

One `paintPlan` call. One `.nativeStyle` read. No `native_style.available(`. No
`DEFAULT_ENABLED`. `if plan.native then` verbatim. **All five pins satisfied.** And a
bare `screen_target.new({})` is back on the explicit-write path, because the pre-flip
default is substituted *before the seam sees it*.

```
$ lune run tests/run          # mut-M7, full suite
6949 passed        (0 failed — the identical count to the honest commit)
```

A second, independent spelling confirms it is the class and not the one line: a
bracket-indexed re-derivation (`(opts :: any)["nativeStyle"]`, which `%.nativeStyle`
cannot see) that overwrites `plan` when no opt was declared — also **6949 passed, 0
red** (mut-M3, full suite).

**This is materially better than what it replaced** and I want that on the record:
the *accidental* form of the defect — call the seam, forget to obey it, re-derive
underneath — is now caught in one message that names each broken pin, and the
surface has gone from "two substrings anywhere in a 194 KB file" to "five shape
facts". What survives requires deliberately substituting a value into the seam's own
argument list. But the round exists to make the product default impossible to change
invisibly, and it is still possible to change it invisibly in one line.

**Cheapest fix, one line in the same case** — pin the argument, not just the call:

```lua
local arg = string.match(source, "native_style%.paintPlan%(([^,]*),")
if arg ~= "opts and (opts :: any).nativeStyle" then
    table.insert(wrong, `the plan is handed \`{arg}\`, not the raw opt`)
end
```

**Structurally better, and cheaper on the near-cap file** — give `paintPlan` the
`opts` table instead of the opt (`paintPlan(opts, isReducedMotion)`, reading
`opts and opts.nativeStyle` inside), then pin `countOf("%.nativeStyle[^%w_]") == 0`
in the target. With the opt never in the adapter's hands there is nothing left to
substitute, and both bypasses above become unwritable rather than merely detected.

### MEDIUM-A — the RR sweep's new floor binds the reader's NAME, not the tri-state; a fifth site that asks correctly and then collapses is green

The fix makes the sweep demand `nativeStyleOpt%(` by name, and the report concludes
it *"turns the hardcoded four-site list beside it from a ceiling into a floor: it
binds every site that will ever exist."* It binds every site to **calling the right
reader**. It does not bind any site to **passing the tri-state through** — that check
(`then true else nil` → `collapses the tri-state back into a boolean`) still lives in
the four-entry hardcoded `SITES` list in the other case, and is still a ceiling.

**Measured.** A fifth adapter site that asks the *correct* reader by name and then
collapses it anyway:

```lua
local h = host.new({ nativeStyle = if FacetFlags.nativeStyleOpt() then true else nil })
```

`nativeStyleOpt()` answers `false` for an explicit rollback → falsy → `nil` → **no
opt → sheet paint**. The `UseFacetNativeStyle = false` rollback is silently deleted
for that screen, which is MEDIUM-1's defect exactly. Result: **41 passed, 0 red**
(the two touched spec files; the sweep counts the line as gated). Positive controls
above confirm the sweep sees the file and does redden it for the *old* spelling.

**Fix, one line.** The sweep already holds `line`; add the same refusal the four-site
case makes:

```lua
if string.find(line, "then true else nil", 1, true) ~= nil then
    -- not gated: the tri-state is collapsed back into a boolean
    continue
end
```

That makes the *contract* a floor rather than only the *reader*, which is what the
report claims it already did.

### LOW-B — LOW-1's fix narrowed the exemption pin to the argument list, and a comment inside the argument list still satisfies it

`string.match(source, "screen_target%.new%(%s*%b{}")` is a genuine tightening — the
original whole-file search is gone. But the balanced-brace span includes comments,
and the original defect's shape survives inside it.

**Measured.** `edit_preview.luau` rewritten as:

```lua
local adapter = screen_target.new({
    parent = opts.parent,
    style = opts.style,
    -- previously passed nativeStyle = false here; the default handles it now
})
```

→ **23 passed, 0 red**, while the preview goes back to seeding a persistent
`FacetStyle` into `ReplicatedStorage` in the Edit DataModel — the defect the round's
own report calls *"the only thing standing between the flip and permanent furniture in
a designer's place file."* The RR sweep in this same fix round learned to skip comment
lines; this check did not. Strip `^%s*%-%-` lines out of `call` before the `find`, or
match `nativeStyle%s*=%s*false` on a non-comment line within the span.

### LOW-A — the isolated-export base is labelled `462a1ca`; the commit that produces 6939 is `fa0be0c`

`git archive 462a1ca` + `lune run tests/run` → **6925**, not 6939. The true parent of
`b52d220` is `fa0be0c`, and it measures **exactly 6939**. The `+10` is right on either
base (6925 → 6935, 6939 → 6949) and the shipped commit measures 6949, so no claim is
false — but the baseline is attributed to a commit six rounds back, which is the
class of error the `SOURCE_CAP_LEDGER` re-attribution row exists to warn about. One
character-level fix in the report's table.

### LOW-C — the re-recorded ledger cell has unbalanced bold and an unclosed parenthesis

The new `screen_target.luau` cell carries **9** `**` markers (odd → one unmatched)
and **5** open parens against **4** closes. The re-record wrapped the previous entry
in `(Previously: …` without closing the group and left the previous entry's closing
`**` orphaned mid-sentence (`…not by a future one.** The round's own edit…`).
`check_doc_style` passes, so nothing catches it. Cosmetic, in the document whose whole
value is being read carefully.

### LOW-D — `nativeStyleOpt` no longer goes through `readFlag`, so the migration rule now lives in two places

The LOW-6 fix reimplements the dual-read walk inline
(`voteOf(workspace:GetAttribute(pair.new))` then `pair.old`), bypassing `readFlag`.
It is the right *semantics* — `readFlag`'s "new name wins whenever non-nil" is
precisely what swallowed the rollback — but the module header still says the
migration is *"written down"* in one place and that *"every caller asks a NAMED
question rather than reading an attribute"*, and `nativeStyleOpt` is now the one
reader that reads attributes itself. Nothing pins that the two walks agree. When the
removal trigger in `docs/migrations/facet-attribute-migration.md` fires and
`readFlag`'s fallback is deleted, `nativeStyleOpt` will silently keep honouring
`UseLuauUINativeStyle`. Cheapest fix: give `readFlag` an optional per-name predicate
(`readFlag(new, old, voteOf)`) so there stays one walk, or add a case asserting both
readers answer identically for a boolean at the old name.

### LOW-E — `native_style.available()` is now called on the opt-out path, which the round's own breakage scan does not name

Old: `if nativeOpt ~= false and native_style.available() then` — Lua short-circuits,
so an explicit `nativeStyle = false` never probed. New: `paintPlan` computes
`capable` **before** testing `resolved == false`, so every opted-out target now runs
`Instance.new("StyleSheet")` + `:Destroy()` inside a pcall. That is `edit_preview`,
`billboard_target`, and any Rascal Rally place carrying the rollback.

Harmless in substance — the probe instance is never parented, so it cannot become
Edit-DataModel furniture, and it is one transient instance per target construction —
but it is a real behavioural delta on the *exact path* the round exists to protect,
and the fix round's write-up does not mention it. One-line fix if wanted: test
`resolved == false` before computing `capable`.

### INFO-A — `check_surface_ledger` is red in the export, and it is not this round's

`nested member 'themes.paintForDisplay' is not classified in the surface ledger` —
**red at `fa0be0c` too**, so it is the paint-family round's (`c4d0591`) to close, not
this one's. The fix round's guard list does not name it, so nothing is misstated.
Recorded so the next reader of "all guards PASS" knows the export is not green under
*every* guard. (`check_flat_baseline` and `check_brand_drift` still cannot run in an
export — gitignored dump / `git ls-files` — as in the original review.)

---

## 5. New-breakage scan of the two diffs

* `native_style.paintPlan` — new function, behaviourally equivalent to the branch it
  replaces on every path (`resolved ~= false and capable` ≡ the old two-clause gate;
  transitions identical including the short-circuit that keeps `isReducedMotion`
  unasked). One delta: LOW-E. `PaintPlan` is exported as a type but `native_style` is
  not reachable from `src/init.luau`, so no public surface moved and `api.md` needs no
  row. **No defect.**
* `screen_target.new` — one call, one `plan.opt` read, one branch; `handle`/`model`
  still read off the resolved opt by identity, which is correct (they are the
  caller's objects). **No defect.**
* `edit_preview` / `billboard_target` — untouched by this commit; still pass their
  explicit `false`. **No defect.**
* Perf lab, promotion tracker, ledger — comment/JSON/prose only. **No defect.**
* RR `voteOf`/`nativeStyleOpt` — semantics verified against the fixture in all four
  directions plus garbage at both names; a real boolean at the new name still wins.
  One seam: LOW-D. **No defect.**
* RR `paintPath` now composes through `paintPlan(...).native` rather than
  `resolveOpt(...)`. Strictly better (it points at the decision the adapter obeys),
  identical answers on all three cases, and the `available = true` argument is stated
  with its reason rather than assumed. `native_style.DEFAULT_ENABLED == true` is
  still asserted directly against the live framework. **No defect.**
* RR `init.client.luau` — comment only. **No defect.**
* No locked file (`renderer`, `presenter`, `solver`, `virtual_list`, `table`) is
  touched by either diff. ✅

---

## 6. Recommended dispositions

| # | finding | disposition |
|---|---|---|
| MAJOR-A | five pins lock the shape, not the argument; one line reverts the flip green | **Fix before Step 14.** Prefer handing `paintPlan` the `opts` table and pinning `.nativeStyle` count **0** in the target; the argument-match pin is the cheap fallback. |
| MEDIUM-A | a fifth site that asks `nativeStyleOpt()` and collapses it is green | **Fix now — one line.** Move the `then true else nil` refusal into the sweep loop. |
| LOW-A | export base labelled `462a1ca`; 6939 is `fa0be0c` | Correct the report table. |
| LOW-B | exemption pin satisfied by a comment inside the argument list | Skip `^%s*%-%-` lines within the matched span. |
| LOW-C | ledger cell has unbalanced `**` and an unclosed paren | One edit. |
| LOW-D | `nativeStyleOpt` duplicates the dual-read walk | Predicate parameter on `readFlag`, or a case pinning the two agree. |
| LOW-E | `available()` now probes on the opt-out path | Test `resolved == false` first, or name the delta in the report. |
| INFO-A | `check_surface_ledger` red (pre-existing, `c4d0591`'s) | Record only; route to the paint-family round. |

---

## 7. What the fix round got conspicuously right

* **It took the extraction rather than the tighter grep.** The reviewer offered
  (a) extract and (b) tighten; the round took (a), which is the answer that also gave
  278 characters back to a file that was 8 from its trigger. The instrument and the
  cost discipline moved in the same direction, which is rare.
* **Making the engine probe and the motion fact parameters is the whole trick.**
  `available()` answers `false` under Lune, so a plan that probed for itself could
  only ever have been tested in its refusing half. Ten cases now drive branches that
  had no headless witness at all. That reasoning is stated in the module comment,
  where the next author will find it.
* **Refusing to put `handle` and `model` in the plan.** Answering MEDIUM-1 by
  shipping two plan fields no production line reads would have been committing the
  same defect one repository over. The round named that and declined.
* **Deleting `nativeStyleOn` instead of documenting it as test-only**, and pinning
  the deletion two ways (the value is `nil`; the source carries no definition) while
  deliberately keeping the prose that explains why. That is the right half to write
  down.
* **The LOW-6 catch is a real rollback-loss path** and the fix generalises correctly:
  a vote must be a boolean before it can win.
* **Disclosing the `c4d0591` sweep rather than quietly re-committing the hunk.** The
  content is correct, shipped once, and the accident is named. Re-committing it would
  have been the easy, wrong move.
* **The −4 is explained as arithmetic and the arithmetic is exactly right.** A suite
  count that goes *down* is the number most likely to be waved past; this one was
  decomposed into five, two and one, and all three components reproduce.

---

## 8. Method note

* Facet exports: `git archive {462a1ca, fa0be0c, b52d220, c4d0591}` →
  `scratchpad/rr1/facet-{A,P,C,…}`. RR: `git archive {4e271c3, 1509383}` into real
  two-tree layouts `T-{new,base,base5,mut5,mut5b,mut5c}`.
* Fourteen mutations. Facet: the original reviewer's bypass (full suite);
  `DEFAULT_ENABLED` flip-back (full suite); pin-1 bite (second `paintPlan` call);
  pin-2 bite (second opt read); pin-4 bite (`DEFAULT_ENABLED` named); the motion
  call-count pin (eager `reducedNow`); LOW-1's comment-in-arglist; and **two
  full-suite bypasses that stay green** (argument substitution; bracket-index
  re-derivation). Rascal Rally: the reviewer's fifth site at the parent (A-side,
  green) and at the fix (red); a fifth site collapsing `nativeStyleOpt` (**green**);
  a correctly written fifth site (green, no false positive).
* Single-spec runners (`tests/onerun.luau`, `tests/rronerun.luau`) were used for
  pin-level iteration and full-suite runs for every claim about a suite count.
* Neither shared tree was written to at any point except this file.
