# Native-style default flip — fix round 2, scoped re-review

**Scope.** Facet `c3eec58` (code) + `9a88feb` (report) and Rascal Rally `c3c8d49`,
against the fix-round-2 section appended to `task-native-default-report.md`,
answering `task-native-default-fix1-rereview.md` (MAJOR-A, MEDIUM-A, 5 LOW).

**Method.** Both shared trees were treated as read-only; **every number below was
produced in private `git archive` exports of the exact named commits**, under
`scratchpad/nd2/`. Every Rascal Rally run used a real `tools/mkpair.sh` pair (both
refs resolved at measurement time, never the shared working tree). The live shared
Facet tree has a renderer round mid-edit in `src/render/` (`commit_walks.luau`,
`renderer.luau`, plus touched tests and `tools/mkpair.sh` itself) — none of it was
read, exported, or touched; every export in this review came from `git archive` at
a named commit, which cannot see uncommitted working-tree state at all.

**VERDICT: NOT all-addressed.** MEDIUM-A is closed cleanly — the RR floor now binds
the value expression, not the reader's name, and a mutation search turned up no
residual. MAJOR-A is **not** closed: the report's own "count of zero" claim is true
about the *opt*, but the seam still receives the *whole `opts` table* by ordinary
variable reference, and nothing pins that the caller never reassigns it before the
call. A fresh bypass built for this review — no relation to fix round 1's — reassigns
`opts` to a fabricated substitute table using a field name spelled by string
concatenation (so the literal substring `nativeStyle` never appears in the file) and
reverts the product default with the **full 7022-test suite green, 0 red**, identical
to the honest commit. This is the same defect class for a third round in a row. One
LOW is new: the report's own screen_target.luau size decomposition mis-attributes
80% of this round's own footprint growth to "another round."

| severity | count |
|---|---|
| BLOCKER | 0 |
| MAJOR | 1 (residual of MAJOR-A, third occurrence of the class) |
| MEDIUM | 0 |
| LOW | 6 (5 confirmed fixed, 1 new) |
| INFO | 1 |

---

## 1. M7 and M3 now redden; the original bypass is still red

All three run against the unmutated export `c3eec58` first (targeted spec: 24
passed, 0 failed — matches the shipped commit) before each mutation.

**M7 — substitute the pre-flip default into the seam's argument**, exactly as
named in the task (`paintPlan` handed
`if raw == nil then { nativeStyle = false } else opts`):

```
local raw: any = opts and (opts :: any).nativeStyle
local plan = native_style.paintPlan(if raw == nil then { nativeStyle = false } else opts, isReducedMotion)
```

Targeted spec: **1 failed, 23 passed** —
`expected consumer off contract:the target names the opt 2 time(s), and may name it
none: local raw: any = opts and (opts :: any).nativeStyle; the plan is handed \`if
raw == nil then { nativeStyle = false } else opts\`, not the opts table`.
Full suite: **1 failed, 7021 passed**. ✅ Matches the report's table exactly.

**M3 — bracket-indexed re-derivation.** My spelling reassigns `opts` inline
(two lines name `nativeStyle`, not the report's one, because I did not stage a
private temp variable — a methodology difference, not a discrepancy in the
result):

```
if opts == nil or (opts :: any)["nativeStyle"] == nil then
    opts = { nativeStyle = false } :: any
end
```

Targeted spec: **1 failed, 23 passed** — `the target names the opt 2 time(s), and
may name it none: if opts == nil or (opts :: any)["nativeStyle"] == nil then`.
Full suite: **1 failed, 7021 passed**. ✅ The class reddens; the bracket index is
not a way around the pin.

**The original bypass (call into `_ignored`, re-derive underneath, restore the
three-clause transitions expression), re-applied against `c3eec58`:**

```
local _ignored = native_style.paintPlan(opts, isReducedMotion)
local nativeOpt: any = opts and (opts :: any).nativeStyle
if nativeOpt ~= false and native_style.available() then
    ...
    host = type(nativeOpt) == "table" and nativeOpt.host or nil,
    theme = type(nativeOpt) == "table" and nativeOpt.theme or nil,
    transitionsEnabled = type(nativeOpt) == "table" and nativeOpt.transitions == true
        and not (isReducedMotion ~= nil and isReducedMotion()),
```

Targeted spec: **1 failed, 23 passed** — three pins named in one message (opt read
count, capability probe present, branch shape not `if plan.native then`). ✅ Still
red, as claimed.

## 2. The zero-count pin is real for the *opt* — and a fresh bypass defeats it anyway

**The count is genuinely over the word, with exactly two structural exclusions.**
`grep -n "nativeStyle" src/client/screen_target.luau` on the shipped file returns
exactly two lines: the `Opts` field's own declaration (`nativeStyle: (boolean | {
...})?`) and `adapter.nativeStyleInfo`. The reads-scan in the case strips
`nativeStyleInfo` from a copy of each line before testing for the substring, and
separately excludes only a line that begins `^\tnativeStyle: ` — both mechanisms
line up with what is actually in the file, and the shipped case passes with `#reads
== 0`. `native_style.paintPlan(opts, isReducedMotion)` reads the opt exactly once,
inside `paintPlan` itself, off `opts.nativeStyle` — confirmed by reading the
function body directly.

**My fresh bypass — it must redden, and it does not.** The pin's own reasoning
("Handed the table, the adapter has nothing left to substitute") checks that the
*text* `native_style.paintPlan(opts, isReducedMotion)` is unchanged and that no line
names the opt. It does not check whether the **local variable `opts`** is
reassigned to a *different* table before that unchanged call — and a caller that
never writes the substring `nativeStyle` can still fabricate a substitute:

```lua
local nativeHandle: any = nil
do
	do
		local o: any = opts or {}
		local key = "native" .. "Style"        -- never appears as one substring
		if o[key] == nil then
			local copy: any = {}
			for k, v in pairs(o) do
				copy[k] = v
			end
			copy[key] = false
			opts = copy :: any                 -- reassigns the PARAMETER, not a local
		end
	end
	local plan = native_style.paintPlan(opts, isReducedMotion)
	...
```

Every pin is satisfied by construction: one `paintPlan` call; zero lines contain
the substring `nativeStyle` (the field name is built by concatenating two string
literals that are never adjacent in the source); zero `native_style.available(`
calls; zero `DEFAULT_ENABLED`; `if plan.native then` untouched; and
`string.match(source, "native_style%.paintPlan%(([^,]*),")` still captures exactly
`"opts"`, because the call text itself never changed.

**Behaviourally it reverts the flip.** A bare `screen_target.new({})` (no
`nativeStyle` key) hits `o[key] == nil`, so `opts` is silently rebound to a copy
carrying `nativeStyle = false` before `paintPlan` ever sees it — the pre-flip
default, restored, for any caller that passes no opt at all. A caller that *did*
pass an opt is untouched, so the bypass is surgical rather than global.

```
$ lune run tests/run_one native_style_default    # targeted spec
24 passed                                        (0 failed)

$ lune run tests/run                             # full suite
7022 passed                                      (0 failed — identical to the honest commit)
```

**This is the same defect class MAJOR-1 and MAJOR-A both named, one level down
again.** Round 1 pinned the *shape* of the consumer and missed that the *value*
handed to the seam was unconstrained. Round 2 pinned the *value* handed to the seam
(by taking the whole table) and missed that the *variable holding that value* is
still an ordinary local the caller can freely rebind before the pinned call text
executes. "Handed the table, the adapter has nothing left to substitute" is false
whenever the adapter can substitute the table itself.

**Cheapest fix, in the same case.** Pin that the parameter identifier is never an
assignment target between the function's start and the `paintPlan` call — e.g.
`countOf("opts%s*=[^=]")` (excluding the `function screen_target.new(opts: Opts?)`
declaration line itself) must be zero. That closes this exact bypass; whether a
structurally cheaper seam exists (e.g. capturing `opts` into a `table.freeze`d
alias immediately at function entry does **not** help, since freezing the original
table doesn't stop the *local name* `opts` from being pointed at a different table)
is worth a second look rather than assumed solved.

## 3. Rascal Rally: the fifth-site floor is closed as a class

RR pair `tools/mkpair.sh` Facet `c3eec58` + RR `c3c8d49`, full suite: **3466
passed, 0 red**. ✅ Matches the report's pin exactly.

**The collapsing fifth site reddens, quoted message included.** Planted
`src/client/FacetFifthGui.luau`:

```lua
local host = { nativeStyle = if FacetFlags.nativeStyleOpt() then true else nil }
```

Two touched spec files: **1 failed, 41 passed** —
`expected sites that do not hand the opt through:src/client/FacetFifthGui.luau
hands \`if FacetFlags.nativeStyleOpt() then true else nil\` to be sites that do not
hand the opt through:`. ✅

**The correctly written fifth site stays green — with one methodology caveat worth
recording.** My first attempt at the positive control wrote
`{ nativeStyle = FacetFlags.nativeStyleOpt() }` on a single line; the sweep's
value-capture regex (`nativeStyle%s*=%s*(.-)%s*,?%s*$`, end-of-*line* anchored)
captured `FacetFlags.nativeStyleOpt() }` — trailing brace included — and the anchored
`passesTheOptThrough` pattern correctly rejected that as a non-match, producing a
**false positive against my own artifact**, not a framework defect: every real
shipped site writes `nativeStyle = FacetFlags.nativeStyleOpt(),` on its own line
inside a multi-line table literal (confirmed in `GaragePilotGui.luau`), which is
also what `stylua` produces for these constructor calls in this codebase. Rewriting
the fifth site in that same multi-line shape gave a clean run: targeted spec **42
passed, 0 failed**; full suite **3466 passed, 0 red** — identical to the shipped
count, confirming the floor admits new sites rather than freezing the four-file
list. Recorded as INFO-B below — a latent format-sensitivity, opposite in direction
to MAJOR-A (a false positive against a correct future site, not a missed bypass),
and not something this review is treating as a defect given the codebase's own
formatting convention already avoids it everywhere it currently applies.

**The four shipped adapters are still enumerated by the (now-derived) sweep.**
`the derived sweep still finds the four shipped adapters, by name` passes in both
mutation runs above and in the unmutated baseline — the sweep still finds
`GaragePilotGui.luau`, `FacetRacerListGui.luau`, `FacetSettingsGui.luau`, and
`FacetSponsor/init.luau` by path. ✅

## 4. Suite arithmetic

| claim | measured | result |
|---|---|---|
| Facet 7021 → 7022 (+1) | export `3fee51c` → export `c3eec58`, `lune run tests/run` | **7021 → 7022** ✅ |
| RR 3465 → 3466 (+1) | `mkpair.sh` Facet `a4fbd65`+RR `cae4c7a` → Facet `c3eec58`+RR `c3c8d49` | **3465 → 3466** ✅ |
| `screen_target.luau` final size 193,795 | `wc -c` at `c3eec58` | **193,795** ✅ |
| this round's own edit is **−30** | byte diff of the `local plan = native_style.paintPlan(...)` line, old vs new | **exactly −30** (90 → 60 chars before the trailing newline) ✅ |
| "the **+81** belongs to another round" | full provenance trace (below) | **not confirmed — only +7 does** ❌ |

**The +81/−30 decomposition in both the report table and the re-recorded
`SOURCE_CAP_LEDGER` row does not hold up under the diff.** True ancestry chain for
`src/client/screen_target.luau` (by `git rev-parse`/`--is-ancestor`, not log order):

| commit | round | size | Δ |
|---|---|---|---|
| `b52d220` | native-default fix round 1 (end) | 193,714 | — |
| `5a43992` | another round (ten-foot/paint-family) | 193,714 | 0 |
| `d3abdb0` | another round (citation-sweep: "seven codes become prose") | 193,721 | **+7** |
| `3fee51c` | (`a4fbd65` between, doesn't touch this file) | 193,721 | 0 |
| `c3eec58` | **this round** (fix round 2's own commit) | 193,795 | **+74** |

`git diff d3abdb0 3fee51c -- src/client/screen_target.luau` is empty, and
`git diff a4fbd65 c3eec58` (this round's own commit against its immediate parent)
touches exactly this one hunk in this file. So of the total **+81** (193,714 →
193,795): **+7 is another round's** (the citation-sweep commit's "B-16"→"B-17" and
"SEAM-3:"→"the seam rule:" relabeling), and **+74 — not −30 — is this round's own
commit.** The −30 figure is real, but it is only the functional code line
(`native_style.paintPlan(opts and (opts :: any).nativeStyle, isReducedMotion)` →
`native_style.paintPlan(opts, isReducedMotion)`, precisely 90 → 60 bytes including
the newline); the *same commit, same hunk* also adds two new comment lines
explaining the change (+104 bytes), which the report and the ledger row both
silently fold into "another round's +81" instead of naming as this round's own.
**93% of the total growth this round's report attributes elsewhere is this round's
own prose.** See LOW-F.

## 5. The two overclaims are retracted inline

Both corrections sit as a `> **CORRECTION (fix round 2).**` blockquote immediately
following the sentence that made the original claim, inside the *same* fix-round-1
section of the report rather than only in the new fix-round-2 section:

* MAJOR-1 (report lines ~326–341): the claim *"there is exactly one legal place to
  get it"* is followed in-place by the correction that this half was false, quotes
  both bypasses that broke it, and states the corrected claim ("five shape facts,
  none of which constrains the argument"). ✅
* MEDIUM-1 (report lines ~382–393): the claim that naming `nativeStyleOpt` *"turns
  the...list...from a ceiling into a floor: it binds every site that will ever
  exist"* is followed in-place by the correction that it bound the reader, not the
  value, quotes the collapsing fifth site, and states "the class is closed" was the
  wrong tense. ✅

Both are retracted in the sentence that made them, not merely acknowledged
elsewhere. ✅

## 6. New-breakage scan of the two diffs

Scoped strictly to each round's own commit against its immediate parent (`a4fbd65
c3eec58` for Facet, `c3c8d49^ c3c8d49` for RR) — not the aggregate against the
older suite-baseline pin, which pulls in unrelated rounds' commits.

* **`native_style.luau`** — `paintPlan`'s signature changed from `(opt, ...)` to
  `(opts, ...)`. Only one production caller exists (`screen_target.luau`, grepped
  across all of `src/`), and it was updated in the same commit. `PaintPlan` is not
  reachable from `src/init.luau` (grepped, zero matches), so the report's "no
  public surface moved" claim holds. The LOW-E short-circuit fix (`resolved ==
  false` tested and returned **before** `capable` is computed) is present in this
  same diff, matches the report's description exactly, and is pinned by the new
  "refuses BEFORE the engine is probed" case (which honestly discloses its own
  limit in its comment — the probe-order assertion can't observe the shipped
  2-argument call path directly). **No defect beyond §2's residual.**
* **`screen_target.luau`** — one hunk, the call-site change plus explanatory
  comment (§4). **No defect.**
* **`tests/native_style_default.spec.luau`** — the rewritten pin, the new
  "opts table itself" check, the LOW-B comment-stripping fix, the `planFor`/direct
  calls updated to the new `paintPlan(opts, ...)` signature throughout. All
  internally consistent with the shipped signature; full suite is green. **No
  defect.**
* **`SOURCE_CAP_LEDGER.md`** — re-recorded row, see LOW-F.
* **`FacetFlags.luau`** (RR) — `readFlag` gained an optional `accepts` predicate;
  `nativeStyleOpt` now routes through it with `isBoolean`. Exactly one
  `workspace:GetAttribute(oldName)` remains in the source (inside `readFlag`), and
  the four `== true` predicates (`settingsOn`, `garagePilotOn`, `racerListOn`, the
  Sponsor selector) all still call `readFlag(new, old)` with no `accepts` argument,
  preserving their original "any non-nil at the new name wins" behaviour — checked
  by reading each call site; the LOW-D case only pins the tri-state path directly,
  but the `== true` sites' own describe blocks (unchanged in this diff) still pass
  at 3466. **No defect.**
* **RR spec files** — `adapterSites()` sweep and `passesTheOptThrough` per §3; the
  hardcoded-list case correctly narrowed to a name-only membership check. **No
  defect beyond the format-sensitivity noted as INFO-B.**

---

## Findings

### MAJOR-B — the seam takes the whole `opts` table, but nothing stops the caller from substituting a whole different table before the call

See §2 in full. A fresh, independently designed bypass — reassign the `opts`
parameter to a fabricated table (built via a runtime-concatenated field name so no
line contains the literal substring `nativeStyle`) immediately before the unchanged
`native_style.paintPlan(opts, isReducedMotion)` call — satisfies every one of the
six pins (call count, opt-substring count, capability-probe count, flag-mention
count, branch shape, and the `arg == "opts"` literal match) and reverts a bare
`screen_target.new({})` to the pre-flip explicit-write default, with the full
7022-test suite green at the identical count. Third occurrence of the same defect
family across two fix rounds: a pin on the caller's *shape* or *value at the call
site* cannot see a rebinding of the variable that flows into that call site.
Cheapest fix named in §2 (pin that `opts` is never an assignment target in the
function); worth checking whether it is complete before trusting it the way "count
of zero" was trusted here.

### LOW-F — the report and the re-recorded ledger row both misattribute 74 of this round's own 81-character growth to "another round"

See §4. Only +7 of the +81 total growth in `screen_target.luau` since fix round 1
belongs to a different round (a citation-sweep commit, `d3abdb0`); the other +74 is
this round's own commit, `c3eec58` — the same commit whose functional code line
really is exactly 30 bytes shorter. The two facts are both true and do not
contradict each other (a −30 code change and a +104 comment addition in the same
hunk net to +74), but the report's phrasing ("of which +81 is another round's; this
round's own edit is −30") and the ledger's phrasing ("81 of that is somebody else's
... 30 characters SHORTER") both attribute the *entire* growth away from this round,
which the diff does not support. Given `SOURCE_CAP_LEDGER.md`'s own stated purpose —
and its own history of exactly this failure mode causing a missed trigger
(`presenter.luau`'s "RE-ATTRIBUTED" row, "the identical failure...one file over, in
the same week") — a self-report that undercounts its own contribution to a file
sitting 205 characters from a hard trigger is worth a one-line correction, in the
same spirit as this round's own two inline corrections in §5. Suggested fix: state
the true three-way split (+7 another round / −30 this round's code / +104 this
round's comment, net +74) rather than the current +81/−30 framing.

### INFO-B — the RR sweep's value capture is end-of-line anchored, so a value sharing a line with a closing brace is misread

See §3. Not a security-relevant finding (it is a false positive against a
*correctly* written site, the opposite direction from MAJOR-B), and no shipped site
is affected today — all four write the field on its own line inside a multi-line
table literal, matching the codebase's `stylua`-enforced convention. Recorded so a
future single-line `host.new({ nativeStyle = FacetFlags.nativeStyleOpt() })` isn't
mistaken for a defect in the *site* when it is a limitation of the *sweep's* regex.

---

## Own fresh bypass attempt — summary

Designed independently of fix round 1's two bypasses: reassign the `opts`
parameter to a fabricated substitute table (field name built by string
concatenation so the literal substring `nativeStyle` never appears in the source)
immediately before the unmodified, pinned `native_style.paintPlan(opts,
isReducedMotion)` call. It satisfies all six of the case's pins and reverts a bare
`screen_target.new({})` to the pre-flip default with the full suite green at 7022,
0 red — identical to the honest commit. **It did not redden.**
