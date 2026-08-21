# Facet "add a new composite control" guide — verification protocol

Checkout: `.../scratchpad/exC/GameStudio/ui/Facet`
Control name used: `badge_pill` (BadgePill)
PATH: `$HOME/.rokit/bin:/opt/homebrew/bin:$PATH` (rokit 1.2.0, lune 0.10.4, rojo 7.7.0, stylua 2.5.2)
Path followed: `README.md` → "Where the documentation is" → `docs/guide/README.md` → "Extension playbooks" →
`docs/extending/new-control.md` ("a new composite control").

Baseline (before any change): `./run-tests.sh` → **6808 passed**, exit 0, ~3m33s (doc claims "about three and a
half minutes" — matches).

---

## Step 0 — Ground rules (read constitution.md first; work from library root)

**Claim:** Read `docs/reference/constitution.md` first; work from `GameStudio/ui/Facet`; use absolute paths.
**Observed:** `constitution.md` exists with all 16 numbered sections the playbook cross-references (§4 "Specs
and validation: strict at the boundary", §15 "Evidence") present exactly where cited. `ui_todo.md` §0 exists
and contains the exact quoted sentence ("...mouse is an unfinished control"). `docs/lessons/absolute-paths-in-shell-commands.md`
and `docs/plans/agent-execution-contract.md` both exist as cited.
**Verdict:** MATCH.

## Step 1 — Scaffold the skeleton

**Command:** `lune run tools/lune/scaffold_cli control badge_pill`
**Claim:** "Three files written, eleven edited" (14-row table).
**Observed:** Tool output listed exactly 3 `wrote` lines and 11 distinct `registered`/`moved` targets;
`git status --short` independently confirmed exactly 3 untracked (`??`) + 11 modified (`M`) files, matching
every row of the table (including `src/init.luau`'s two edits counted as one file, and
`tests/gallery_demo_picker.spec.luau`'s two pin-moves counted as one file). Every individual file's diff was
inspected and matches its table description verbatim (the `Controls.BadgePill` entry in `src/init.luau`, the
`api.md`/`README.md` stubs, the registry row with `inputProofs`/`affordanceProofs`, etc.).
**Verdict:** MATCH (exceptionally precise — 14/14 files, all content as described).

**Claim:** "Verify the red state: `./run-tests.sh` must now fail with the ELEVEN stamped cases and nothing else."
**Observed:** `./run-tests.sh` failed with **10** failing cases (1 TODO + 4 input-class + 4 affordance + 1
hot-switch — counted directly from the stamped `tests/badge_pill.spec.luau`, and confirmed by the transcript
tail `10 failed, 6810 passed`), not eleven. Nothing *else* went red — that half of the claim holds. This is
also an internal inconsistency in the doc itself: the table two paragraphs earlier spells out the stamped
cases as "one failing TODO case, four failing input-class cases, four failing affordance cases, one hot-switch
case" = 10, but the very next instruction calls it "the ELEVEN stamped cases."
**Verdict:** MISMATCH (doc says eleven, actual and doc's own case-by-case count are both ten).

## Step 2 — Design the control's contract

**Claim:** `tests/lib/world.luau`'s `world.new({ viewport = {...} })` hands back core, environment, adapter,
action system, presenter, in that order.
**Observed:** Read `tests/lib/world.luau` in full; its `World` type and `world.new` return exactly
`{ core, env, adapter, system, pres, ... }` in that order, matching the doc precisely, including both
documented construction invariants (viewport set before any solve; adapter created before its one presenter).
**Verdict:** MATCH.

**Claim:** house-style exemplars `tests/level_picker.spec.luau` and `tests/paradigm_table.spec.luau` are "on
the substrate" (use `world.luau`).
**Observed:** Confirmed — `level_picker.spec.luau` requires `./lib/world` and wraps it exactly as the doc
describes. (Note: `tests/chip.spec.luau`, which the *control-side* prose points to for the 44px-token pattern,
is NOT on the substrate — it hand-rolls core/env/adapter/system/pres. That's consistent with the doc's own
scoping, since it never calls chip.spec.luau a spec exemplar, only `level_picker`/`paradigm_table` for specs
and `chip.luau`/`picker.luau` for control *source*.)
**Verdict:** MATCH.

**Claim (specGuard example):** "Use `Facet.specGuard`, which is the same implementation the twenty-two
in-repo controls use," shown as a module-scope `local SPEC_KEYS = Facet.specGuard.keySet({...})` plus a
**2-argument** `function gauge.build(core, spec)`.
**Observed:** Empirically tried the snippet literally inside `src/controls/badge_pill.luau` (module-scope
`local Facet2 = require("../")` to reach `.specGuard`). `lune run tests/run_one badge_pill` **hung
indefinitely** (>120s, no output at all, had to be killed) — a circular require, since `src/init.luau`
requires every control module (including this one) near its top before it defines `specGuard`. Grepped all
24 in-repo controls: **zero** use `Facet.specGuard...`; all 24 use `local specGuard = require("../spec_guard")`
(a direct submodule require) and the documented 3-argument `build(Facet, core, spec)` seam. The snippet is
correct only for an out-of-repo consumer requiring the *published* library (its own surrounding paragraph
even says so — "it says nothing about the table a consumer hands `newGauge(core, spec)`") but is presented
without flagging that distinction, directly under a heading ("Your OWN spec is strict too") a reader adding an
in-repo control (exactly this playbook's scenario) would reasonably take as applying to their own file.
**Verdict:** MISMATCH — following the literal snippet inside an in-repo control causes an indefinite hang, not
an error with "the fix in the message" (contradicting the guide's own principle "Mistakes fail immediately,
with the fix in the message," docs/guide/README.md). The correct in-repo pattern (direct submodule require,
3-arg build) is not shown here at all; a newcomer has to reverse-engineer it from an existing control.

## Step 3 — Implement

Built a minimal real control (single `UI.Button` + `contribution.attach({ handleActivate = ... })`, modeled on
`src/controls/chip.luau`) and replaced the TODO case and the four input-class cases with real tests built on
`world.new()`. Left the four affordance-idiom cases as the scaffold's own failing stubs (the guide asks for
per-class *design judgment* there, not a literal walkthrough) and, per the guide's own literal instruction
("If the control owns NO in-flight state, DELETE this case and set `affordanceProofs.hotSwitch = false`"),
deleted the hot-switch stub case and set the registry's `hotSwitch = false`.

**Result:** `lune run tests/run_one badge_pill` → **5 passed, 4 failed** — build+render and all four
pointer/touch/keyboard/gamepad reachability cases pass; the four affordance stubs remain red exactly as
scaffolded.
**Claim:** "What mounting gives you for FREE... the presenter auto-composes navigation groups, per-node
Activate dispatch... from the input contribution you attach" — i.e. only `handleActivate` was declared (no
`focusGroups`), yet `w.pres.focus.focused:get()` auto-focused the sole control and both `w.press("Return")`
and `w.press("ButtonA")` fired it.
**Verdict:** MATCH — confirmed exactly as described.

**Claim (load-bearing fact #1 — "one activation site"):** "the presenter dispatches a tap/A/Return to the
node's own `onActivate` FIRST and then to the longest-prefix contribution, so declaring both **double-fires**
the verb."
**Observed:** Instrumented both handlers with distinguishable `print()` markers and declared both
simultaneously. Result: `NODE_ONACTIVATE_FIRED` printed on every reachability case; `CONTRIBUTION_HANDLEACTIVATE_FIRED`
**never** printed. Read `src/present/presenter.luau`'s `activateEffect` (lines ~302–328): it is an early-return
cascade — `node.props.onActivate` fires and `return`s immediately; the contribution's `handleActivate` is only
reached if no node-level `onActivate` exists. Declaring both does not double-fire the verb; it **silently
shadows the contribution's `handleActivate` entirely**, single-firing the node-level one instead.
**Verdict:** MISMATCH — the described symptom (double-fire, which is at least noticeable) is the opposite of
the actual failure mode (silent single-fire of the wrong handler, which is *harder* to notice and a more
dangerous defect class than the one the doc warns about).

**Claim (load-bearing fact #2 — the 44px token):** "`tools/lune/check_theme_drift` rejects a numeric `min`
anywhere under `src/controls/`."
**Observed:** Swapped the control's `min = "targetSizes.minimum"` for a literal `min = 44`. Running
`lune run tools/lune/check_theme_drift.luau` directly produced **no output, exit 0** — that file has no CLI
driver at all (despite its own internal comment "CLI: run this file directly"; it's a pure library returning
`checker`). However, `lune run tests/run_one theme_drift` (the way this mechanism is actually wired into the
suite, via `tests/theme_drift.spec.luau`) correctly failed with a precise message naming the file, line, and
fix. Since `docs/extending/new-control.md` never itself instructs running `check_theme_drift` as a standalone
command (that misleading "CLI: run this file directly" comment lives in the tool's own source, not in this
playbook), this is **not** counted as a new-control.md mismatch — the underlying claim (the mechanism rejects
the literal) is true when exercised the way the playbook's own gates exercise it (`./run-tests.sh`).
**Verdict:** MATCH (claim verified true via the actual suite path).

**Claim (load-bearing fact #3 — `pres.refresh()`):** binding writes need a refresh before an adapter-prop
read.
**Observed:** Not independently re-tested in isolation (would require a control with a render-visible bound
prop); accepted on the strength of consistent precedent across `chip.spec.luau` and `level_picker.spec.luau`,
both of which call `pres.refresh()`/`w.settle()` before every adapter-prop read.
**Verdict:** MATCH (by precedent, not independently re-derived).

**Claim ("A control registered the way this playbook describes moves both sides of the comparison and the row
keeps passing" — re: the `naming-adr-implemented` gate row's derived-count fix):** verified directly — the
probe's `Controls.` line count and the registry's unique `Controls.X` count both read **20** after adding
BadgePill (were presumably 19/19 before), and the deprecation-row count stayed pinned at 19.
**Verdict:** MATCH.

## Step 4 — Documentation

**Claim:** entry needs "signature, spec-table fields, return surface, invariants, and a short example."
**Observed:** Compared the scaffolded `api.md` TODO stub's anchor/shape against a filled-in exemplar
(`### \`newChip\`` in `docs/reference/api.md`) — the exemplar exhibits exactly the five described elements in
that order. Did not author a complete real BadgePill entry (out of scope — step 4 gives no literal template
to follow beyond this bullet list, and the target is the guide, not a finished doc page).
**Verdict:** MATCH (structure description is accurate against real entries).

## Step 5 — Gates and evidence

Ran all four commands, in order, against the intentionally-partial control (5/9 spec cases passing).

1. `./run-tests.sh` → exit 1, `4 failed, 6815 passed` — expected/correct given the four affordance stubs are
   deliberately left unimplemented; nothing *else* newly broke.
2. `lune run tools/lune/check_registration_cli` → `PASS (39 controls...)`. Confirms the doc's framing that
   this checker only requires each cited case *name* to exist verbatim in a registered spec — not that it
   passes — since our four affordance cases and the `hotSwitch=false` edit were accepted while still red.
   MATCH.
3. `lune run tools/lune/check_prop_parity_cli` → `PASS` (unaffected, as expected — no new primitive property
   was added). MATCH.
4. `lune run tools/lune/gate phase-4-hardening` → `FAIL_RECOVERABLE`, exit 0.

**Claim:** "The gate's pass rule counts human-signoff placeholder checks (PENDING states with no run command)
as failures by design... Your bar: every check that was PASS before your change is still PASS, and no check
moved to FAIL_RECOVERABLE."
**Observed:** Ran the same gate on a stashed clean baseline for comparison. Baseline: 12 PASS / 6
FAIL_RECOVERABLE / 1 FAIL_ENVIRONMENT (no PENDING rows at all in this gate). With the partial BadgePill work:
**7 rows that were PASS at baseline flipped to FAIL_RECOVERABLE** (`library-suite-green`, `virtualization-hardening`,
`navigation-groups`, `semver-and-deprecation`, `error-boundaries`, `maintainability-playbooks-and-checker`,
`documentation-and-examples`) — none are PENDING placeholders; they are real, run, failing checks. Their `run`
commands (inspected in `tools/lune/gate_manifest.luau`) chain through `tools/suite_transcript.sh` / a full
`./run-tests.sh`-dependent transcript grep, so *any* red suite anywhere cascades into flipping every gate row
that happens to grep for a passing-line in the full transcript — regardless of whether that row's actual
subject matter (e.g. "navigation-groups") has anything to do with the change. The doc's own §5 step order (run
`./run-tests.sh` first, "must exit 0") implies a compliant reader would stop before ever reaching the gate
command in this state, which mitigates it — but the four commands are given together in one fenced block,
inviting a reader (especially an agent) to run all four regardless, and the doc's explanation of expected gate
noise (PENDING placeholders only) does not mention or prepare the reader for this unrelated-row cascade.
**Verdict:** UNCLEAR — technically avoidable by following the doc's own ordering strictly, but the guidance
about *what kind* of noise to expect from this gate is incomplete/misleading for anyone who runs it before the
suite is fully green.

## Step 6 — Live Roblox gate

No literal shell command is given in this section (prose checklist only: grow the gallery scenario, pass the
Studio preflight, drive every native path, exercise device variations, get a fresh-context verifier, leave
true-hardware rows PENDING). Per task scope ("you do NOT need to finish a working control"), this step was
**not executed** — it requires a materially complete, polished control and a live Roblox Studio session, which
is explicitly outside this pass's target (the target is the guide's text, and step 6 gives no runnable
command to check literally). Read for clarity: the six numbered items are concrete and a Roblox developer
would understand each one (preflight, native-path pairing, orientation/text/motion sweep, fresh-context
verifier, explicit PENDING rows for what Studio can't observe) — no sentence here required outside knowledge
to parse.
**Verdict:** UNCLEAR (not executed — no command to run; prose itself reads clearly).

## Common traps section

Spot-checked one claim mechanically: `tools/test.sh` does look for a `^[0-9]+ passed` line and reports
`"no 'N passed' summary line - suite truncated"` when it's absent, and separately guards a `FACET-FAST-TIER`
transcript from being accepted as a suite verdict — both exactly as described.
**Verdict:** MATCH.

---

# Summary

**Step count:** 7 (Steps 0–6, following the doc's own numbering)

**Totals:** 5 MATCH, 3 MISMATCH, 2 UNCLEAR

**Every MISMATCH:**
- Step 1: doc says the scaffold's red state is "the ELEVEN stamped cases" (and separately, two paragraphs
  earlier, its own table enumerates exactly ten); actual stamped/failing case count is 10, confirmed both by
  the spec file's `it()` blocks and the `10 failed` transcript line.
- Step 2: the `specGuard` code example (`Facet.specGuard.keySet(...)` at module scope + 2-arg
  `build(core, spec)`), presented as "the same implementation the twenty-two in-repo controls use," is only
  valid for an out-of-repo consumer; tried literally inside an in-repo control it causes `lune run
  tests/run_one` to hang indefinitely via a circular require against `src/init.luau` — none of the 24 actual
  in-repo controls use this access pattern (all require `../spec_guard` directly with the 3-arg
  `build(Facet, core, spec)` seam, which the doc doesn't show here).
- Step 3: load-bearing fact #1 says declaring both a primitive's `onActivate` and the bundle's
  `handleActivate` "double-fires the verb"; the actual presenter code (`activateEffect` in
  `src/present/presenter.luau`) early-returns on the node's own `onActivate`, so only that one fires and the
  contribution's `handleActivate` is silently never invoked — a single wrong-handler fire, not a double-fire,
  confirmed by instrumenting both handlers distinctly.

**Every UNCLEAR:**
- Step 5: "no check moved to FAIL_RECOVERABLE" / expected-noise guidance doesn't anticipate that, mid-implementation
  (suite not yet green), 7 gate rows unrelated to the change (e.g. `navigation-groups`, `semver-and-deprecation`)
  flip from PASS to FAIL_RECOVERABLE purely because their `run` commands depend on a green full-suite
  transcript — confirmed by diffing a stashed clean-baseline gate run against the partial-implementation run.
- Step 6 (Live Roblox gate): not executed — no literal command is given, and finishing it requires a complete
  control and a live Studio session, both out of this pass's scope; the prose itself was clear where read.
