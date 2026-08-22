# Native-style default flip — implementer's report

**Status: DONE.** `native_style.DEFAULT_ENABLED` is `true`. Facet suite **6905**
(baseline 6892), Rascal Rally suite **3460** (baseline 3449), both zero red, both
measured in private rsync exports. Two Facet commits, one Rascal Rally commit.

| | Facet | Rascal Rally |
|---|---|---|
| commits | `c1120fc`, `50887a8` | `5dff3de` |
| suite | 6905 passed (was 6892) | 3460 passed (was 3449) |
| red rounds | 8 red, then 1 red | 10 red |

---

## 1. What changed, and the shape it took

The flip itself is one boolean. The thing that made it a *task* is what the red
round found: **nothing in the repository pinned the old default.**
`DEFAULT_ENABLED` appeared in exactly two source lines and no spec, because its
only reader — `screen_target.new` — needs a `LocalPlayer` and a DataModel and
cannot run headlessly at all. The library's most consequential single boolean
could have been flipped, or flipped *back*, by an edit no gate could see.

So the default-resolution rule left the closure it was buried in:

* `native_style.resolveOpt(opt)` — pure, the only reader of `DEFAULT_ENABLED`.
  `nil` → the library default; `false` → `false`, untouched; anything else →
  itself, **by identity** (the config table's `handle`/`model`/`host`/`theme`/
  `transitions` are read back off the object the caller passed, so a resolver
  that rebuilt the table would drop every key it did not know). It never answers
  `nil`, which is why the caller's whole condition is now `~= false`.
* `screen_target.new` calls it instead of re-deriving it. That is also why a
  product-behaviour change cost the near-cap `screen_target.luau` **108
  characters** (193,206 → 193,314; trigger 194,000, 686 away). Its
  `SOURCE_CAP_LEDGER` row is re-recorded with the new number and the note that
  the seam analysis was re-read and stands.

`tests/native_style_default.spec.luau` (new, 13 cases) is the witness: the
default, the escape hatch, the identity pass-through, the never-`nil` invariant,
the seam really being the one the shipped adapter asks, who the default does
**not** sweep, the ADR row, and the gallery's A/B precedence.

## 2. Every red, and its verdict

**Round 1 — Facet, 8 red.** All eight were *new pins on the new behaviour*, not
existing specs that had to be re-verdicted. **No pre-existing Facet spec went red
from the flip**, for the structural reason above: the only consumer of the
default is engine-bound, so nothing headless could have been pinning it.

| red | verdict |
|---|---|
| the default IS sheet paint | **new pin** — `DEFAULT_ENABLED` had no spec at all before today |
| NO opt resolves to the library default | **new pin** — the flip's whole meaning, red because the resolver did not exist |
| an explicit `false` STILL refuses | **new pin** — guards the escape hatch; would have gone red if the flip had taken the fallback branch with it |
| an explicit `true`/table passes through untouched | **new pin** — identity, so a config table keeps keys the resolver never heard of |
| the resolver never answers `nil` | **new pin** — a `nil` answer would make `~= false` true for "no answer", the original defect in reverse |
| `screen_target` routes through the seam, no second copy | **new pin** — a pure function agrees with itself; this is what says the shipped adapter asks it |
| the flip is RECORDED in ADR-0040 | **new pin** — the record is what makes it legal on an unreleased `0.10.0` |
| gallery: neither attribute set → the library default | **fix** — the boot hardcoded `false` there, which would have left the framework's own demo place the last consumer unable to see the framework's own default |

Four gallery-precedence cases were **green on the first run**, deliberately:
`paint_mode.luau` was first written as a faithful extraction of the shipped
`and`/`or` expression, so the three answers that must *not* move proved
themselves before the one that must moved.

**Round 2 — Facet, 1 red.** See §5 (the edit preview).

**Round 3 — Rascal Rally, 10 red**, run against the *pre-flip* Facet in a
two-tree export so the reds were real: five tri-state flag cases and five
paint-path contract cases. One further red appeared on the green run and was a
**re-verdict**: the shipped `nativeStyle`-site sweep counts *lines containing the
word*, and the four call-site comments now name the reader in prose — so the
check failed for saying what it does. It now skips comment lines and requires a
**call** to a `nativeStyle*` reader rather than the word, which is strictly
tighter than what it replaced (the word was vacuous: every swept line contains it
by construction).

## 3. The consumers

**`screen_target.new({})` → sheet paint; `nativeStyle = false` → still refused.**
Both pinned. The gallery's A/B driver moved out of a LocalScript argument list
into `examples/gallery/client/paint_mode.luau`, beside `boot_mode.luau`, for the
same reason and with the same spec technique (each attribute read exactly once,
into the decision, asserted by counting). Precedence, verified red-first:

1. `Facet_ForceStyleFallback` wins over everything → explicit `false`;
2. `Facet_NativeStyle` = redundant-but-harmless, still the carrier for
   `transitions`;
3. neither → **`nil`**, so the place follows the library. This is the one answer
   the flip moves.

`Facet_NativeTransitions` alone now also opts in — before the flip it did nothing
without `Facet_NativeStyle` beside it, and an attribute whose only purpose is
enhancing sheet paint asking for nothing would be a dead switch in the place that
demonstrates it.

Boots and copy corrected:

* **theme picker console line** — was *"Set `Facet_NativeStyle = true` before Play
  to see the full transaction"*, which now instructs a designer to set an
  attribute that is already the default. Now: *something opted OUT — clear
  `Facet_ForceStyleFallback`*.
* **`docs/guide/09-custom-themes.md`** — same instruction, same fix.
* **`docs/guide/05-styling.md` §5.7** — retitled from "(opt-in)" to "(the
  default)"; three-line example showing default / explicit / **opt-out**; the
  fallback paragraph now says it is a first-class path, not a legacy one.
* **`docs/reference/api.md`** — the `nativeStyle` opt row: absent **is** sheet
  paint; `false` **is** the opt-out and wins.
* **ADR-0018** — status line and Decision preamble record that the opt is
  inverted; nothing about the mechanism changed.
* **performance lab** — keeps its explicit `false` **on purpose** and now says
  why: every budget (`bench/perf_budgets.json`) and capture
  (`artifacts/performance-stress-places/`) was measured with the
  adapter as the only writer of every paint property. Taking the sheet path there
  would move instance counts and paint timings under numbers recorded against the
  other painter. Flagged as a follow-up in §7, not changed.

## 4. The record

* **ADR-0040 row B-15** added under ruling R15, immediately after B-14 with no
  blank line (a blank line severs the table). It names what moved, what a
  consumer's own code touches (no `UICorner`/`UIStroke` instances exist under a
  Facet root any more), that the adoption evidence measured the two paths
  byte-equal so the *mechanism* is what changed, the opt-out, and that Rascal
  Rally moves with it in the same task. The existing ADR-0040 instrument needed
  no change: it pins blueprint **props**, and this is a library default, so the
  new spec carries the "record exists" half itself.
* **`artifacts/native-stylesheets/promotion-readiness.json`** — the `refreshed`
  block now carries a `decision` field (made by the director, 2026-08-21,
  `DEFAULT_ENABLED = true`) and a `remaining` field (Step 14 publish). It states
  plainly that the block used to say this was "the owner's call at the Step 14
  checkpoint" and that the owner has now made it ahead of that checkpoint, so
  `stillRequired` is no longer a gate *on* the decision but the evidence the
  publish event collects about a default that is already live. The frozen
  2026-07-24 rows are untouched.

## 5. The defect the flip exposed: the Studio edit preview

The flag's own comment claimed **two** exemptions from the default — billboards
and the edit preview — and the code only had one. `billboard_target` has always
passed an explicit `nativeStyle = false`; `edit_preview.luau` passed nothing, so
the flip swept it.

That is not cosmetic, and the review found it worse than stated here. The preview
harness runs in the **Studio Edit DataModel**, where `native_style.ensure` seeds a
persistent `FacetStyle` StyleSheet that the next place save commits — the exact
furniture that module's header promises never to leave behind (verifier F5).
*(Corrected in fix round 1: this said `dispose()` "cannot take it back because the
sheet is seed-once". The simpler and stronger truth is that `dispose` **never
looks in the container the sheet lands in** — it destroys `controller`, `root` and
the `deco` ScreenGui, all of which live under `opts.parent`, while
`native_style.ensure` seeds to `ReplicatedStorage` in Edit BY DESIGN, so the sheet
is outside everything `dispose` can reach. The exemption is the only thing standing
between the flip and permanent furniture in a designer's place file.)* It costs nothing to look at: the two paint paths
were measured byte-equal on every mapped property, so a preview painted the
explicit-write way shows what the game shows.

Fixed red-first in `50887a8`, with the case pinning **both** exemptions rather
than the one that moved — "who the default does not sweep" is the half of a
default nobody writes down.

## 6. Rascal Rally lockstep

**The flip changed this game's live paint path with nothing in the package
changing**, and that is the finding rather than an inconvenience: all four
adapter sites (`GaragePilotGui`, `FacetRacerListGui`, `FacetSettingsGui`,
`FacetSponsor/init`) pass the flag's answer straight through, and with the
workspace attribute absent — what every shipped place carries — that answer is
**no opt**, which is exactly what the framework's default answers. Their comments
already predicted it ("so the game follows the framework's default flip
automatically").

**The one behaviour question, and a judgement call the controller may veto.**
`FacetFlags.nativeStyleOn()` answers `== true`, which maps **both** "absent" and
"explicitly `false`" onto the same call-site argument (`nil`). That was harmless
while both meant the bespoke painter. The moment "absent" started meaning the
sheet they became opposites, and leaving the boolean in place would have **left
`UseFacetNativeStyle = false` doing nothing at all** — a Studio-togglable flag
that silently stopped being a switch, on exactly the attribute somebody reaches
for to roll back.

`FacetFlags.nativeStyleOpt()` passes the framework's own tri-state through:
absent → `nil` (the library decides), `true` → `true`, `false` → **the rollback**,
still winning over everything, through both spellings of the attribute. A
non-boolean value reads as absent, never as `false`, so a typo cannot force the
fallback painter on a shipped place.

**This changes no behaviour beyond what the flip implies.** With the attribute
absent — the shipped state, confirmed: no RR place file or project JSON sets it —
the tri-state and the boolean produce the identical answer. With it explicitly
`false`, the tri-state *preserves* the pre-flip behaviour that the boolean would
have discarded. It is the same shape the studio already used when the Sponsor
default flipped in 2026-08-03 (`UseFacetSponsor = false` = the rollback), which
the root constitution cites by name. **The legacy Sponsor modules are shipped and
untouched, and `UseFacetSponsor = false` remains the Sponsor rollback**; nothing
in this task read or wrote that flag's behaviour.

Game-side evidence:

* `tests/facet_theme_paint_contract.spec.luau` — new block, 5 cases: the
  framework copy this package requires really carries the flip; the flag's answer
  **composed with the framework's own resolver** is sheet paint with nothing set;
  the rollback survives through both spellings; explicit `true` is
  redundant-but-harmless; and all four sites really pass the *opt* (a site that
  reverted to `if …nativeStyleOn() then true else nil` would silently delete the
  rollback and nothing else in the suite would notice).
* The tinted-plate case written as *"the compatibility floor for the day that
  flag flips"* is **re-verdicted, not re-pinned**: the day came, so it is a live
  assertion about the shipped paint path now.
* `tests/facet_flag_migration.spec.luau` — 6 tri-state cases, dual-read across
  the rename preserved. Its `luau.load` fixture moved to
  `tests/lib/facet_flags_fixture.luau` because a second spec needed it.
* `games/RascalRally/docs/migrations/facet-attribute-migration.md` updated.
  **Note: that path is not under version control** (the RR git root is
  `games/RascalRally/code`), so the edit is on disk only, not in `5dff3de`.

## 7. Guards, evidence, and concerns

**Guards, all run in the export** (`check_brand_drift` needs `git ls-files`, so it
ran in the shared tree and is read-only):

| guard | result |
|---|---|
| `check_theme_artifacts` | PASS (8 artifacts, 137 checks) |
| `check_library_purity` | PASS |
| `tools/check_types.py` | PASS |
| `check_brand_drift` | PASS |
| `check_source_size` | PASS (`screen_target` 193,314; 686 from its trigger) |
| `check_doc_style` | PASS — *failed first*: my guide edits used `B-15`/`NSS-A10` as bare shorthand in consumer-facing prose; rewritten to cite ADR-0040 by link and to say "the native-stylesheets adoption evidence" |
| `check_flat_baseline` | PASS (1461 flat nodes byte-compared) |
| `check_example_drift_cli` | PASS (74 files) |
| `check_docs_cli` | PASS |
| `stylua --check src tests tools examples` | PASS |

**The 99-token style-editor-sync evidence
(`artifacts/theme-packages-and-skinning/theme-sync/parchment-live-dump.json`) was
NOT regenerated, and the flip does not invalidate its premise.** It is a token
dump read off a live theme sheet's typed attributes, captured with native paint
active. The flip makes that state the *default* rather than an opt-in; nothing
the capture asserts depends on how the target arrived there. If anything the
capture is now more representative, since it documents the shipped path.

**Concerns for the controller:**

1. **A place saved with `UseFacetNativeStyle = false` will now paint bespoke in
   Rascal Rally.** Before this task it would have painted bespoke too, so this is
   preservation rather than a change — but the canary must **read that attribute
   before concluding anything from the screenshots**, and that is REQUIRED rather
   than advisory. *(Corrected in fix round 1, review MEDIUM-2: this originally
   said "no RR place file or project JSON sets it — confirmed". The project JSONs
   and every text source are genuinely clean, but `code/places/` holds two BINARY
   places, `DebugGraybox-v1.rbxl` and `DebugPlace-v1.rbxl`, and a `.rbxl`
   LZ4-compresses in chunks, so no byte scan can see an attribute name in one.
   The honest statement is: no TEXT place source sets it; the two `.rbxl` places
   are unverifiable from disk and must be read in Studio.)*
2. **The tri-state (§6) is my judgement, not the director's ruling.** It is one
   function and four call sites; reverting to the boolean is mechanical if the
   controller would rather the flag simply become inert.
3. **The performance lab still measures the non-default path.** Deliberate and now
   documented, but it means the perf budgets no longer describe what ships. A
   re-baseline of `bench/perf_budgets.json` + `artifacts/performance-stress-places/`
   on the sheet path is a real follow-up — out of
   scope here because it invalidates every recorded number.
4. **`screen_target.luau` is 686 characters from its extraction trigger.** The
   flip's edit went the right way (a seam left, not a line added), but the next
   change of any size to that file should take the `screen_vocabulary.luau`
   extraction its ledger row names.

**Nothing was CONTESTED.** No locked file (`renderer`, `presenter`, `solver`,
`virtual_list`, `table`) was touched, and none needed to be.


---

# Fix round 1 — review dispositions

**Review:** `task-native-default-review.md`, APPROVE with findings (0 BLOCKER, 1
MAJOR, 2 MEDIUM, 6 LOW, 2 INFO). Every finding is answered below; three are
report-only corrections, applied in place above and marked as such.

| | Facet | Rascal Rally |
|---|---|---|
| commit | `b52d220` | `1509383` |
| suite | **6949** in an isolated export of Facet **`fa0be0c`** — the true parent of `b52d220` — plus this round's files only (that parent alone: 6939, so **+10**). *(Corrected in fix round 2, LOW-A: this said `462a1ca`, a commit six rounds back that measures 6925. The `+10` holds on either base; the attribution did not.)* | **3461** (baseline at RR HEAD `4e271c3` with the same Facet: 3465, so **−4**) |
| `screen_target.luau` | **193,992 → 193,714 chars (−278)** | — |

**Why the Facet number is measured in an isolated export.** Two other rounds have
uncommitted work in the shared tree. A full working-tree run is **6973 passed, 0
red**, but `stylua --check` and `check_theme_artifacts` fail there on the DIR5
round's untracked `tests/lib/overflow_guard.luau` — `tests/lib/world.luau` requires
it and the theme probe copies only tracked files. So every number and guard result
below comes from `git archive HEAD` + this round's five files, which contains
nothing of either concurrent round and reproduces exactly.

**The Rascal Rally −4 is arithmetic, not a loss:** five generated `== true` matrix
cases that a flag which is no longer a `== true` predicate does not earn, plus two
new cases, minus the retained-boolean case that was deleted with the function it
tested.

## MAJOR-1 — the seam pin was a source grep, and a bypass reverted the flip green

**Fixed by extraction, per the reviewer's own recommendation (a).**
`native_style.paintPlan(opt, isReducedMotion, available)` is now the whole
decision: the default, the capability gate, the escape hatch, the host/theme the
sheet is seeded with, and the transitions seed with reduced motion overriding it.
It is pure — the engine probe and the motion fact are **parameters**, which is the
only reason the *accepting* half of every branch is testable at all, since
`available()` answers `false` off-engine. Ten cases now drive branches that lived
un-witnessed inside a closure nothing can require headlessly.

The motion fact is passed as a **function**, not a boolean, so a target that opted
out never calls a consumer's deprecated motion closure — pinned by a case that
counts the calls.

**What the plan deliberately does not carry: `handle` and `model`.** Those are the
caller's own objects rather than decisions, and the target reads them off
`plan.opt` where it builds the sheet, beside the style and display facts only it
has. A plan field no production line reads is a surface kept alive for a test —
which is precisely the defect this same review found on the Rascal Rally side, so
shipping one here would have been answering MEDIUM-1 by committing it.

**The consumer is pinned by SHAPE, not by substring** — five checks in one case:
exactly one `paintPlan` call; exactly one read of the opt off `opts` (matched as
`%.nativeStyle[^%w_]` so `adapter.nativeStyleInfo` cannot count); zero capability
probes in the target; zero mentions of the flag; and `if plan.native then` as the
branch. The second is the lock: a re-derivation needs the **raw** opt, there is
exactly one legal place to get it, and `plan.opt` is the **resolved** opt, from
which "was one passed" cannot be recovered — an absent opt and an explicit `true`
are the same value by the time the target sees one.

> **CORRECTION (fix round 2).** The second half of that sentence was true; the
> first half — *"exactly one legal place to get it"* — was **false**, and it was
> the load-bearing half. A count of reads says nothing about the VALUE handed
> over, and the re-review reverted the product default twice with the full suite
> green at the identical 6949: once by substituting the pre-flip answer into the
> seam's own argument (`paintPlan(if raw == nil then false else raw, …)`, all five
> pins satisfied), once through a bracket index the `%.nativeStyle` pattern could
> not see at all. The claim should have read: *five shape facts, none of which
> constrains the argument.* Fix round 2 closes it by handing the seam the whole
> `opts` table — the count is now **zero**, and there is nothing left in the
> adapter's hands to substitute.

**Mutation evidence.**

*The reviewer's exact bypass* (call `paintPlan` into `_ignored`, re-derive the
pre-flip rule underneath):

```
✗ `screen_target` OBEYS the plan: one call, one opt read, no probe, no second rule
    expected consumer off contract:the opt is read 2 time(s) off opts, not once;
    the target still probes the capability itself — that gate belongs to the plan;
    the native branch is not `if plan.native then` — the plan is computed and ignored
1 failed, 6934 passed
```

Three of the five pins trip, in one message that names each. Previously: **6905
passed, 0 failed.**

*`DEFAULT_ENABLED` flipped back to `false`, full suite* — **4 failed** where the
review measured 2, and two of the four are now plan-level rather than
pure-function-level:

```
✗ the default IS sheet paint — the flag itself, read off the module
✗ NO opt resolves to the library default, rather than to `false`
✗ NO opt plans SHEET PAINT — the default, decided here and nowhere else
✗ the plan carries the RESOLVED opt, and it cannot say whether one was passed
```

**And it paid for itself on a near-cap file.** The concurrent paint-family round
left `screen_target.luau` **8 characters** from its 194,000 extraction trigger.
One call and one test replacing a resolve, a two-clause gate and a three-line
transitions expression gave **278 characters** back: 193,992 → 193,714, now 286
below the trigger. The `SOURCE_CAP_LEDGER` row is re-recorded, and says plainly
that the seam which answered this review is *not* the seam that row is about — the
vocabulary module is still owed.

## MEDIUM-1 — a fifth adapter site collapsing the tri-state passed green

**Both mechanisms closed.**

1. The sweep's gate was `nativeStyle%a*%(`, which accepts `nativeStyleOn(`. It now
   names **`nativeStyleOpt`**, which turns the hardcoded four-site list beside it
   from a ceiling into a floor: it binds every site that will ever exist.

   > **CORRECTION (fix round 2).** Premature. It bound every site to *calling the
   > right reader*; it bound none of them to *passing its answer through*. The
   > re-review wrote the difference in one line —
   > `nativeStyle = if FacetFlags.nativeStyleOpt() then true else nil` — which asks
   > correctly, maps the `false` rollback onto `nil`, and deletes the rollback for
   > that screen with the suite green at 3465. "The class is closed" was the wrong
   > tense: one *spelling* was closed. Fix round 2 puts the contract on the value
   > expression and derives the site list from the sweep.
2. **`nativeStyleOn()` is deleted**, not documented as test-only. It had no
   production caller at all and survived to satisfy one row of the rename matrix;
   the reviewer used it exactly as a future author would. The matrix row now names
   `nativeStyleOpt` and the `== true` loop skips it the way it already skips the
   Sponsor's `~= false` — the flag is not a predicate any more. A case asserts the
   **definition** is gone (not the name: the module header still tells the story of
   why, and that prose is the point rather than a leak).

**Mutation evidence.** The reviewer's fifth site, re-applied verbatim:

* before: **3465 passed, 0 red** (the hole, reproduced first as an A-side);
* after: **1 failed** — `✗ a tinted plate with no surface still has a FILL under
  native stylesheets`, `4 of 5 nativeStyle sites gated`.

## MEDIUM-2 — the `.rbxl` precondition was not confirmed

**Report corrected in place** (concern #1 above), and the mitigation upgraded from
advisory to **required**: no text place source sets the attribute; the two binary
places cannot be scanned from disk and must be read in Studio as the first step of
the owed canary.

## The six LOWs

| # | disposition |
|---|---|
| LOW-1 | **Fixed.** The exemption pin was a whole-file substring search that a comment satisfied (the reviewer deleted the argument, left `-- previously passed nativeStyle = false here`, and the preview went back to seeding a persistent sheet with the case green). The match is now anchored to `screen_target%.new%(%s*%b{}` — the constructor's own argument list. |
| LOW-2 | **Fixed.** `artifacts/perf/` does not exist; the source comment and both mentions in this report now name `bench/perf_budgets.json` and `artifacts/performance-stress-places/`. |
| LOW-3 | **Fixed.** `RascalRally/src/client/init.client.luau` — the boot file that constructs all four adapters — still said "absent = the library default (currently bespoke paint)". It states the new polarity and the tri-state. |
| LOW-4 | **Fixed.** The `stillRequired` device row said the flag was "staged"; it is restated to say the device pass now exercises the shipped default, and to read `UseFacetNativeStyle` first. |
| LOW-5 | **Fixed — and it landed in someone else's commit.** The `host.Opts.nativeStyle` doc now states the default and the opt-out. Worth recording: the edit was swept into the paint-family round's `c4d0591` before I committed. The content is correct and shipped, but it is the exact accident `commit_isolated` exists to prevent, running in the other direction. The typing note (`host.Opts` types the field `boolean?`, so the table form cannot reach `screen_target` through `host`) is pre-existing and **not fixed** — it is a public-surface change that wants its own decision. |
| LOW-6 | **Fixed.** `readFlag` answers with the Facet-era name whenever it is non-nil, so `UseFacetNativeStyle = "yes"` beside a real `UseLuauUINativeStyle = false` resolved to "no opt" → **sheet paint**, discarding a deliberate rollback. A vote must be a **boolean** before it can win: `voteOf` reads each name and a non-boolean at the new name now falls through to the old one. A real boolean at the new name still wins. Four assertions, including garbage at both names. |

## Not fixed, with reasons

* **INFO-1 (`examples/table_phaseb` is a bare `host.new()`)** — record only, per the
  reviewer's own disposition. It is the correct outcome for an example; it is now
  named here so the consumer enumeration is complete.
* **INFO-2 (the showcase place hardcodes `Facet_NativeStyle: true`)** — record only.
  Dropping the attribute from `showcase.project.json` and `tools/build_places.sh`
  would make the published place demonstrate the default, and I think it should
  before any device row is claimed from a showcase build — but what the published
  showcase carries is device-evidence policy and the controller's call, not an
  implementer's.
* **The stale transitions comment in `screen_target.new`.** Eight lines above the
  `ensure` call still explain reasoning that now lives in `paintPlan`. Left in
  place deliberately: it sits inside the concurrent paint-family round's diff
  context, and rewriting it would have merged my hunk with theirs in a shared tree.
  Worth a two-line trim once that round lands.

## Guards (isolated export)

`check_theme_artifacts`, `check_library_purity`, `check_types`,
`check_source_size`, `check_doc_style`, `check_example_drift_cli`,
`check_docs_cli`, `stylua --check src tests tools examples` — **all PASS**.
`check_brand_drift` and `check_flat_baseline` need a git index / a gitignored dump
and were run in the shared tree at the previous round; neither is touched by any
change here.

## Concurrent-round hygiene

Two other rounds were live in Facet and one in Rascal Rally. Nothing of theirs was
committed here: every `screen_target.luau` edit was placed to keep ≥7 unchanged
lines from the paint-family round's hunks so git could not merge them, verified
with `--dry-run` before committing, and `tests/run.luau`, `src/layout/solver.luau`,
`src/themes/snapshot.luau`, `tests/facet_composition_collision_contract.spec.luau`
and the rest were left untouched.


---

# Fix round 2 — re-review dispositions

**Re-review:** `task-native-default-fix1-rereview.md`, APPROVE with findings
(0 BLOCKER, 1 MAJOR residual, 1 MEDIUM residual, 5 LOW, 1 INFO). Both headline
findings were **narrowed but not closed** in fix round 1, and this report's own
wording claimed closure twice. The two corrections are inline above, in the
sentences that overclaimed, rather than only here.

**Pins, taken AT MEASUREMENT TIME** (the standing lesson of 2026-08-21, after the
same failure bit three times in one day — a pair pinned at *dispatch* time
fabricates reds that survive an A/B, because the mis-pin is common-mode):

| measurement | Facet | Rascal Rally |
|---|---|---|
| Facet suite | `3fee51c` | — |
| Rascal Rally pair (`tools/mkpair.sh`) | `a4fbd65` | `cae4c7a` |

| | Facet | Rascal Rally |
|---|---|---|
| commit | `c3eec58` | `c3c8d49` |
| suite | **7022** (parent `3fee51c` alone: 7021, so **+1**) | **3466** (same pair, baseline 3465, so **+1**) |
| `screen_target.luau` | 193,714 → **193,795**, of which **+81 is another round's**; this round's own edit is **−30** | — |

## MAJOR-A — the five pins locked the SHAPE, not the ARGUMENT

**Closed by the reviewer's prescribed endgame, not the cheap fallback.**
`native_style.paintPlan` now takes the target's **whole `opts` table** and reads
the paint opt itself. The consumer pin became a **count of ZERO**: the adapter
never holds the opt, in any spelling, so there is nothing left to substitute.

The count is over the **word**, line by line, with exactly two structural
exclusions — the `Opts` field's own declaration, and the unrelated
`adapter.nativeStyleInfo` surface. That is what catches the bracket-index
re-derivation a `%.nativeStyle` pattern was blind to. **The named cost:** the
adapter may no longer write the opt's name in a comment. Stated in the case.

The argument itself is also pinned (`arg == "opts"`), because a seam handed a
*value* can always be handed a different one — belt and braces, and the message
names whichever half broke.

**Mutation evidence — all three now redden, where two were green at 6949:**

| mutation | before | after |
|---|---|---|
| **M7**, substitute the pre-flip default into the seam's argument | 6949 passed, **0 red** | **1 failed** — `the target names the opt 2 time(s), and may name it none: local raw: any = opts and (opts :: any).nativeStyle; the plan is handed \`if raw == nil then { nativeStyle = false } else opts\`, not the opts table` |
| **M3**, bracket-indexed re-derivation | 6949 passed, **0 red** | **1 failed** — `the target names the opt 1 time(s)…: if opts == nil or (opts :: any)["nativeStyle"] == nil then` |
| the original bypass (call, discard, re-derive) | already red | **still red**, three pins in one message |

## MEDIUM-A — the RR floor bound the reader's NAME, not the tri-state

**Closed as a class, both halves.**

1. **The contract is now the VALUE EXPRESSION**, not the reader's name: the opt
   must arrive at the adapter exactly as the owner answered it, **unmapped**. The
   two legal spellings are the reader called on the owner and the Sponsor's getter
   form. A variable holding the answer is deliberately *not* accepted — a
   line-based reader cannot follow a local, so a site that wants one is asked to
   inline the call. Strictness costs nothing here and is the difference between a
   rule and a suggestion; it is stated in the helper rather than left implicit.
2. **The hardcoded four-entry `SITES` list is gone.** One `adapterSites()` sweep
   feeds both cases. The floor case enforces the contract on whatever it finds; the
   second case now asserts only what a sweep cannot say about itself — that it
   still finds the four screens this game ships, so a sweep that silently found
   nothing cannot pass the floor with flying colours.

**Mutation evidence:**

| mutation | before | after |
|---|---|---|
| the re-review's collapsing fifth site (`if FacetFlags.nativeStyleOpt() then true else nil`) | **3465 passed, 0 red** | **1 failed** — `sites that do not hand the opt through: src/client/FacetFifthGui.luau hands \`if FacetFlags.nativeStyleOpt() then true else nil })\`` |
| positive control: a correctly written fifth site | green | **green** (3466) — the floor admits new sites, it does not freeze the file list |

## The five LOWs

| # | disposition |
|---|---|
| LOW-A | **Fixed** — the fix-round-1 table now names `fa0be0c`, the true parent, and marks the correction. `462a1ca` measures 6925; the `+10` held on either base, the attribution did not. |
| LOW-B | **Fixed** — comment lines are stripped from the matched argument span before the search, so an exemption has to be **code**. The re-review's `-- previously passed nativeStyle = false here` inside the braces no longer satisfies it. |
| LOW-C | **Fixed** — the ledger cell is rewritten as a chronological chain, newest first, with balanced `**` (22) and balanced parens (8/8). The nested `(Previously: …` groups that never closed are gone; every entry keeps its content. |
| LOW-D | **Fixed** — `readFlag` takes an optional `accepts` predicate, so there is **one** dual-read walk with two policies instead of a second copy inside `nativeStyleOpt`. A case pins both halves: exactly one `GetAttribute(oldName)` in the source, no `GetAttribute(pair.old` anywhere, and the two readers still agree on a boolean at the old name. When the removal trigger fires, the fallback is deleted once and every reader loses it together. |
| LOW-E | **Fixed, not merely named** — `resolved == false` is now tested **before** the capability is computed, restoring the short-circuit the two-clause gate had for free. Fix round 1 quietly spent it: every opted-out target ran `Instance.new("StyleSheet")` — the edit preview, every billboard, every place carrying the rollback. Pinned by a case, on the exact path this round exists to protect. |
| INFO-A | **Skipped, correctly routed.** `check_surface_ledger` is red at the parent too (`themes.paintForDisplay` unclassified) — the paint-family round's to close. |

## Guards, and one honest FAIL

In the isolated export at `3fee51c` + this round's files: `check_library_purity`,
`check_types`, `check_source_size`, `check_doc_style`, `check_example_drift_cli`,
`check_docs_cli`, `stylua --check src tests tools examples` — **PASS**.

**`check_theme_artifacts` FAILS, and it is not this round's**: the theme probe
copies tracked files only, and the DIR5/overflow round's `tests/lib/world.luau`
requires an untracked `tests/lib/overflow_guard.luau`. **It fails identically at
`3fee51c` with none of this round's files present**, which is how I know. Recorded
rather than omitted, because "all guards PASS" is exactly the claim the re-review
caught this report making loosely once already.

## What this round changed about how it writes

Both corrections above are the same defect in prose: a mechanism was described by
what it *constrains* and reported as though it constrained the *class*. The pins
were real, the counts were real, and the sentences around them were one step
stronger than the evidence. Fix round 2's own claims are therefore stated as what
was measured — a count of zero, a value expression, two mutations that were green
and are now red — with the cost of each named beside it.
