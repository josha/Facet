# Fresh-context phase-gate review — `example-quality-pass` (roadmap Step 10)

**verdict: REJECT**

**Reviewed:** 2026-08-06, fresh context, no access to the implementer's reasoning.
**Judged source:** the working tree as of 11:35 PDT. See MINOR-9 — the tree was being
written *during* this review, so two of my three gate runs are not reproducible.

Rejection is not a claim that the work is bad. The framework fixes are real, the drift
lint is genuinely non-vacuous, and the gate honestly fails. Rejection is because
**three rows in `acceptance.md` carry `PASS_AUTOMATED` that the stored evidence does
not earn**, and the gate checks guarding them cannot see the gap. The ledger has to be
corrected (or the evidence produced) before this gate can be passed.

---

## 1. What I ran, and what it returned

| Command | Exit | Result |
|---|---|---|
| `./run-tests.sh` | **0** | **3556 passed** |
| `tools/gate.sh example-quality-pass` (11:31:56 → 11:35:02) | **1** | **`FAIL_PRODUCT`** — 14 PASS, 1 FAIL_PRODUCT, 3 PENDING |
| `lune run tools/lune/check_example_drift_cli` | **0** | clean: 8 files, 2969 lines, 83 role uses, 2 allowlisted |
| `python3 tools/check_manifest_integrity.py` | **0** | 578 suite greps, all anchored to `✓.*` |
| `stylua --check src tests tools bench examples` | **0** | clean |

Authoritative gate state:

```
PASS  acceptance-ledger            PASS  example-05-word-game
PASS  play-teaching-matrix         PASS  example-05-native-input
PASS  ownership-ledger             PASS  example-06-07-gameplay
PASS  style-authority-and-drift    PASS  lifecycle-and-rapid-input
PASS  theme-package-swap           PASS  device-matrix
FAIL_PRODUCT  large-text-overflow  PASS  places-and-docs
PASS  example-03-optimistic-sync   PASS  library-suite-green
                                   PENDING  prior-gates-unregressed
                                   PASS  rascalrally-consumer
                                   PENDING  fresh-context-reviews
                                   PENDING  physical-and-human-rows
gate: FAIL_PRODUCT -> artifacts/example-quality-pass/gate.json
```

### The four `FAIL_RECOVERABLE` checks — answered

They were a **race, not a defect**. `tools/lune/gate.luau:55-58` downgrades a `run`
check that exited 0 to `FAIL_RECOVERABLE` when its declared `evidence` path is not a
file:

```lua
if state == "PASS" and check.evidence ~= nil and not fs.isFile(check.evidence) then
    state = "FAIL_RECOVERABLE"
    detail = detail .. ` [missing evidence artifact {check.evidence}]`
end
```

The gate.json from the 11:20 run carries exactly that string for all four. At 11:20:39
`studio/ex03.json`, `studio/games.json`, `studio/lifecycle.json` and `places.json` did
not exist (`ls` confirmed); they were written at **11:31:18**. My 11:31:56 re-run shows
all four `PASS`. The greps were always fine. Nothing to fix in the manifest.

---

## 2. The six suspicions, answered

**(1) Is the drift lint property-AUTHORITY aware, and does it bite? — YES, verified.**
`tools/lune/check_example_drift.luau:57-79` reads the vocabularies live from
`themes/package.TYPE_ROLES`, `tokens/styling.TINT_ROLES`, `blueprint_schema` enums for
`Box.surface` / `Text.role`, and `themes/snapshot.isSpaceStep` / `.isMetricPath`. I
probed them directly: `caption,label,body,heading,title,control,strong,numeral` /
10 tint roles / `base,raised,control,chip,badge,accent,scrim,plain` / `secondary,content`.
I then ran **three mutations** against out-of-tree copies (no repo file was modified):

| Mutation | Control | Base | Mutant |
|---|---|---|---|
| A: `SURFACES[v]` legality → `true` | "R2: an INVENTED surface token" | `ok=false` | `ok=true` — reddens |
| B: drop the `textSize` number rule | "R1: a px text size" | `ok=false` | `ok=true` — reddens |
| C: hardcode `TYPE_ROLES` incl. `"gigantic"` | "R2: a typography role that does not exist" | `ok=false` | `ok=true` — reddens |

Mutation C is the decisive one: it proves the accept-list really is read from the
framework rather than restated. **This suspicion is cleared.** (Residual nits at
MINOR-4/5/6/8.)

**(2) The device matrix's `ok` and its anti-vacuity clause — clause EXISTS, artifact
does not carry it.** `tools/studio/device_matrix.luau:1011-1017` is correct:

```lua
-- `judgedTrees > 0` is the anti-vacuity clause: a tree filter that matched
-- nothing would report a clean layout for an empty set
ok = observed.ok
    and (observed.judgedTrees or 0) > 0
    and #observed.offscreenNodes == 0
    and observed.solverDiagnostics == 0
    and #observed.unfitText == 0,
```

The filter (`:652`, root name must begin `LuauUI`) plus the counter at `:649-656,720-721`
are sound. **But the stored artifact drops `judgedTrees` and `skippedTrees` entirely,
and the gate check does not assert them** — see MAJOR-4. The `live`/`observed`/
`configurationChanged` fields the tool emits are also dropped, which are precisely the
fields that would prove the configurations are live getter reads — see MAJOR-5.

**(3) Evidence-class honesty — mostly honest, one undisclosed consequence.** No row
claims physical touch or gamepad. `evidenceClass: "studio-emulated"` is on every row,
`cannotProve` is populated on all five, and `honestBoundary` (device-matrix.json:49)
explicitly refuses the relabel. The `preferredInput` values are read through
`api.report()` → `src/client/roblox_env.luau:90` (`UserInputService.PreferredInput`),
i.e. genuinely live. **The problem is not relabelling, it is a hole nobody named:**
`Touch` on the desktop row means no row in the matrix ran the KeyboardAndMouse
presentation. See MAJOR-5.

**(4) The large-text instrument caveat — CORRECT. Verified against the renderer.**
`src/render/renderer.luau:2296-2313`:

```lua
-- split text-scale seams (NS-A9): MEASURE reserves the engine-scaled
-- bounds (typographyScale includes the player preference); PAINT writes
-- only authored scale — the engine applies the preference itself at
-- draw time (double-application fix, corrections §9).
```
plus `:291-295` (the preferred-text offset is added at MEASURE only, never at paint).
So overriding `preferredTextSize` through the scenario `setEnv` seam moves the
reservation and cannot move engine draw-time scaling. **The claim in
`studio/large-text.json:197` and `acceptance.md:142-151` is exactly right**, and it is
the *conservative* reading: a reserved-box overlap is what a real device fills, so
LT-F3 is correctly scoped as a genuine product defect while the physical row stays
`PENDING_PHYSICAL`. **LT-F3 is not mis-scoped in either direction.** I would not move it.

**(5) EQ-6 `FAIL_PRODUCT` and the gate not exiting 0 — HONEST.** `large-text-overflow`
is `state = "FAIL_PRODUCT"` (a literal, no `run`), gate.luau's pass rule
(`:63-68`) refuses it, and the gate exits 1. That is the correct reading. **But EQ-10
and EQ-15 do *not* survive the same scrutiny** — see BLOCKER-3.

**(6) The gate manifest — the three bare `PENDING`s are sound; one guard is
self-attesting.** `prior-gates-unregressed`, `fresh-context-reviews` and
`physical-and-human-rows` are `state = "PENDING"` with no `run`; gate.luau:60,63-68
means PENDING can never pass. Not silently satisfiable. Every `run` check uses FORM A
(`out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*…"`), and I confirmed the
grepped case names exist *and pass* in my own suite output. `check_manifest_integrity.py`
is green at 578 greps. **However** `acceptance-ledger` and `play-teaching-matrix` are
guards that cannot fail for the right reason — MAJOR-7 and BLOCKER-2.

---

## 3. Findings

### BLOCKER

**BLOCKER-1 — Zero captures exist anywhere in the artifact family, yet six
`PASS_AUTOMATED` rows name captures as their artifact.**
*Location:* `artifacts/example-quality-pass/` — `find` for any non-`.md`/`.json` file
returns nothing; no `.png`, `.jpg`, `.mov`.
*Reproduction:* `find artifacts/example-quality-pass -type f ! -name "*.md" ! -name "*.json"`
*Violated:* the plan §"Theme coverage and drift prevention" ("Capture all seven examples
under Studio Neutral and Fantasy Parchment for every declared layout profile… Pair each
capture with effective package/snapshot, actual and solved geometry, style-role/tag,
decoration layers/fallback, focus, and mount identity"); execution contract §3 ("Layout,
text, clipping, z-order, paint, and animation require E3 geometry/state evidence **plus a
capture**") and §7 ("captures named by fixture, device profile, orientation, input path,
and state"). Ledger rows EQ-1, EQ-3, EQ-5, EQ-11, EQ-12, EQ-13 all list "+ captures" in
their Artifact column and all read `PASS_AUTOMATED` (`acceptance.md:77,79,81,87,88,89`).
EQ-P3 ("judged against the captures") cannot even be *prepared* without them.
*What must change:* produce the capture set under both packages for the declared
profiles and store it under `artifacts/example-quality-pass/`, or demote every row whose
declared artifact includes captures.
*Smallest corrective test:* a gate check that asserts a capture file exists per
(example × package) pair and that each has a sibling geometry/state record.

**BLOCKER-2 — EQ-1 and EQ-13 are `PASS_AUTOMATED` on a PRE-implementation audit whose
own verdicts are `FAIL_PRODUCT`, and the guard cannot see it.**
*Location:* `artifacts/example-quality-pass/audit.md` — headings at `:73, :87, :99,
:111, :125` are literally `### 03 — Settings Sync — **FAIL_PRODUCT**`,
`### 04 — … **FAIL_PRODUCT**`, `### 05 — … **FAIL_PRODUCT (board invisible)**`,
`### 06 — … **FAIL_PRODUCT (silent invalid moves)**`,
`### 07 — … **FAIL_PRODUCT (all tiles identical)**`. The file has no post-fix re-audit
section (`grep "^#"` gives Preflight → instrument facts → whole-gallery defects →
per-example rows → Summary).
*The guard:* `tools/lune/gate_manifest.luau` check `play-teaching-matrix` greps only
`### 01 — Temperature Converter` … `### 07 — Match-3` (prefix match, so
`### 03 — Settings Sync — **FAIL_PRODUCT**` satisfies it), plus `"Studio preflight"` and
one lesson sentence. It passes against an all-`FAIL_PRODUCT` audit.
*Second half of the same finding:* EQ-1's required evidence is "pointer, touch,
keyboard, gamepad/ten-foot… phone portrait/landscape, tablet, desktop, and
console/ten-foot presentation" per example. `audit.md` contains **0** occurrences of
`touch`/`Touch`, **0** of `gamepad`/`Gamepad`, **0** of `tablet`/`Tablet`, **0** of
`landscape`, **0** of `ten-foot`. The per-example tables have rows for Lesson / Startup /
First action / Feedback / Completion-reset / Style / Verdict — the paradigm and
form-factor columns the row demands are simply absent.
*Reproduction:* `for w in touch gamepad tablet landscape; do grep -c "$w" artifacts/example-quality-pass/audit.md; done`
*Violated:* plan §"Audit all seven by playing them"; contract §9 stage 10 ("source
claims alone close nothing"). Note the *source* fixes are real — 01 has `UI.Button{ id =
"Clear" }` (`01_temperature_converter.luau:158`), 02 has `Restore the original playlist`
(`:323`), 04 has `Restore the save` (`:159`) — so this is an evidence defect, not a
product defect. But E0 does not close an E3 row.
*What must change:* add a post-fix play matrix to `audit.md` with one row per example
covering the four paradigms and four form factors, and tighten the gate check to require
those column headings and the absence of an unresolved `FAIL_PRODUCT` verdict.
*Smallest corrective test:* `grep -q "| Gamepad |"` and `! grep -q "FAIL_PRODUCT"` in the
post-fix section of `audit.md`.

**BLOCKER-3 — EQ-10 and EQ-15 are `PASS_AUTOMATED` for input paths that were never
driven and were never recorded `FAIL_ENVIRONMENT`.**
*Location:* `artifacts/example-quality-pass/studio/ex05.json:11` —
*"Every action below is a VirtualInput **mouse press** on the on-screen key at its live
AbsolutePosition."* Every one of the four `sequences` is `click …`. There is **no**
hardware letter/Backspace/Enter trace, **no** keyboard-focus-navigation-plus-activation
trace, and **no** live-input-class-switch trace — the three paths EQ-10 names beyond
pointer (`acceptance.md:86`).
*And the stage already knows the hardware path is blind:* `audit.md:31-37` records that
`SendKey` with a letter/digit KeyCode "delivers a raw keyboard event but does **not**
insert a character into a focused TextBox", and `KeyCode.One` is refused outright. That
is textbook `FAIL_ENVIRONMENT` under contract §2/§4. `ex05.json` does not record it;
its `cannotProve` list mentions only physical touch, gamepad and the OS keyboard.
*EQ-15 is worse:* its declared artifact is `studio/device-matrix.json`, which contains
**no VirtualInput traces at all**. The only VirtualInput content is a capability probe
(`device-matrix.json:10`, `virtualInputMethods: [...]` — a list of method *names*). EQ-15
requires "`VirtualInput` Tab/Shift+Tab, Space/Return, arrows, text and mouse over the
mounted examples… each raw event paired with the semantic action and the visible state
change" (`acceptance.md:91`). None of that is in the file.
*The guard:* the `example-05-native-input` check reduces to
`d['rawEvents']>0 and d['duplicateLetterScored'] and not d['usedGameMethods']` — three
scalars **the artifact author writes about itself**. `usedGameMethods: false` is a
self-declaration of honesty, not a measurement. `device-matrix`'s check never looks for a
trace.
*What must change:* either drive the missing paths and store the raw-event/semantic-
action/state-change triples, or record each un-driven path as `FAIL_ENVIRONMENT` with
its exact failure and demote EQ-10/EQ-15 accordingly. `usedGameMethods` must be derived
(e.g. an instrumented counter on `typeLetter`/`submit` asserted zero), not asserted.
*Smallest corrective test:* a gate assertion that `ex05.json` contains ≥1 trace object
per named input path, each with `{ rawEvent, semanticAction, stateBefore, stateAfter }`.

### MAJOR

**MAJOR-1 — Three artifacts record a blind raw-event instrument and explain it away
instead of marking `FAIL_ENVIRONMENT`.**
`studio/ex03.json`, `studio/games.json` and `studio/lifecycle.json` each carry the
identical `rawEventCaveat`: *"The InputBegan counter read 0 in these runs even though
every state below changed… An earlier run of the identical injection path against
example 05 DID capture 12 raw MouseButton1 events, so the path is the same; this
particular counter is not."* That is an **inference from a different run against a
different example**, offered in place of a measurement. Contract §4: "If the viewport is
`1,1`, capture hangs, **input produces no raw event**, or the source is stale, mark
`FAIL_ENVIRONMENT`, repair or restart the session, and rerun the preflight." Rows EQ-7,
EQ-8, EQ-11, EQ-12, EQ-16, EQ-17 are `PASS_AUTOMATED` on state readback with the raw
channel dark. *Fix:* repair the counter and re-run, or label the raw-event component of
those rows `FAIL_ENVIRONMENT` and say the rows rest on state transitions alone.

**MAJOR-2 — EQ-7 requires "pointer AND focus-based keyboard activation"; `ex03.json`
has only pointer.** Six `states` objects, each with a single `control` path reached by
mouse press. No keyboard row. `acceptance.md:83` and the manifest note both demand both.

**MAJOR-3 — EQ-5 ("all seven examples") is evidenced for one example.**
`studio/theme-swap.json` `provenChange` is `"example": 1` only, and the
`theme-package-swap` gate check asserts *only* those example-1 numbers
(`c['neutral']['font'] != c['fantasyParchment']['font']` etc.). `coverage` claims "All
seven examples swept under both packages" with no per-example record. Also
`invariants.focusPathPreserved: true` is a bare boolean — EQ-5 requires focus **and
mount identity recorded either side**; neither value is stored. *Fix:* record the seven
per-example font/metric/decoration triples and the before/after focus path + mount id.

**MAJOR-4 — The device matrix's anti-vacuity counter is not in the artifact and not
asserted by the gate.** The clause is correct in `tools/studio/device_matrix.luau:1011-1017`,
but `studio/device-matrix.json` records no `judgedTrees` and no `skippedTrees`, and the
`device-matrix` gate check asserts `rows==want`, `passed==35`, `failed==0`,
`preflight.ok`, `scalingMode`, `cannotProve`, `evidenceClass` — never `judgedTrees`. A
future run where the `LuauUI`-prefix filter matched nothing would still produce a file
this check accepts. Compounding it: only the first row enumerates its seven examples;
rows 2–5 collapse to `"allSevenOk": true`, so `result.passed: 35` is a hand-authored
scalar backed by 7 records. *Fix:* emit `judgedTrees`/`skippedTrees` per row, assert
`>0` in the gate, and keep the per-example array on all five rows.

**MAJOR-5 — No matrix row exercised the KeyboardAndMouse presentation, and the artifact
does not disclose it.** `device-matrix.json:37` records `preferredInput: "Touch"` on the
`desktop-standard` (`hd_720`, `form: "Desktop"`) row. Whatever the cause, that row ran
with touch affordances, so the desktop input paradigm is untested across the whole
matrix — and that row's `cannotProve` lists only "retail-client behavior or non-Studio
display scaling (E4)". Two related gaps in the same file: the tool's `live`, `observed`
and `configurationChanged` fields (the discriminators that prove a configuration is a
live getter read, not an echo of the request) are **dropped from the artifact** even
though `device_matrix.luau:1035-1038` emits them; and `compact-phone-portrait` records
`resolution {w:772,h:360}` (landscape-shaped) beside `orientation: "Portrait"` and
`reportedViewport {w:360,h:691}`, which is unexplained and mutually inconsistent.
*Fix:* keep `live`/`observed`/`configurationChanged` in the artifact, add the touch-on-
desktop consequence to that row's `cannotProve`, and reconcile or annotate the
resolution/viewport mismatch.

**MAJOR-6 — `rascalrally-consumer` PASSES on a ledger that declares its own requirement
unmet.** `consumer-impact.md:72-75`: *"**No Rascal Rally Studio canary was run in this
stage.** … F-2 (focus exits around a Grid) is the change most likely to be visible in
one."* The root constitution and contract §"Rascal Rally consumer lockstep" §4 require
"an affected Rascal Rally Studio canary for **visible, input, layout, adapter, or
lifecycle** behavior". F-2 changes focus traversal in two live game screens
(`GaragePilotScreen.luau`, `LuauUISponsor/ResultsScreen.luau`). The gate check greps
`"3089 passed"`, `"highlighted"`, `"What this ledger does NOT claim"` and runs the game
suite — all of which a ledger stating the canary was skipped satisfies. The ledger's
honesty is commendable; the *check* is the defect. *Fix:* run the canary, or make the
check fail while the canary is declared missing.

**MAJOR-7 — `acceptance-ledger` is a self-attesting guard.** Its `run` greps
`acceptance.md` for `^\| \*\*EQ-N\*\* \|.*\| PASS_AUTOMATED \|` for EQ-1..EQ-18. It
verifies that the ledger *says* PASS_AUTOMATED. It cannot detect BLOCKER-1, -2 or -3,
and it will keep passing for as long as the status column reads the way the author typed
it. Every other stage-10 quality claim funnels through it. *Fix:* the check should assert
the *evidence*, not the status column — at minimum that each row's declared artifact
exists and contains the row-specific discriminator.

**MAJOR-8 — EQ-18's tree assertion does not exist.** `places.json` records ten filenames
and byte counts, nothing else. EQ-18's required evidence is "`tools/build_places.sh`
then **a tree assertion over the emitted `.rbxl` files**" and its Risk is literally "a
place file that is the right size and carries last week's example"
(`acceptance.md:94`). The `places-and-docs` gate check asserts only
`ls examples/places/*.rbxl | wc -l >= 10` plus three doc greps. Seven of the example
places are byte-identical (`1357986`), so the stored evidence cannot distinguish a
correct place from a stale one. *Fix:* assert the emitted tree contains the current
example module (e.g. a source-stamp attribute or a module-name walk) per place.

**MAJOR-9 — Ledger/gate divergence, and a stale closing note.** `acceptance.md` marks
EQ-19 and EQ-21 `PENDING` while the gate checks covering them (`places-and-docs`,
`rascalrally-consumer`) report `PASS`. `acceptance.md:157-158` states *"The gate
therefore reports `PENDING` and **does not exit 0**"* — the gate now reports
`FAIL_PRODUCT`. The ledger predates the last several hours of work (mtime 10:57 vs.
artifacts at 11:31). *Fix:* re-synchronise the ledger with the closing gate run.

### MINOR

**MINOR-1** — `studio/lifecycle.json` census counts **GuiObjects only** (83 → 83). EQ-16
requires "instances, connections, reactive nodes and action contexts" return to the
pre-mount census; three of the four are covered only by headless test *names* in
`headlessCoverage`.

**MINOR-2** — `studio/large-text.json:35` excludes `LuauUIChromeText` and
`LuauUIHitExpander` from the overlap check. The reason given is sound (flat names defeat
path-prefix ancestry) and the exclusion is declared, but it is a blind spot in the one
check that found the stage's only product defect.

**MINOR-3** — `large-text.json` top-level `cellsPassed: 52 / cellsFailed: 4` is not
restated in `reRunAfterFixes` (which reports only `cells: 56, zeroWidthText: 0`), so it
is ambiguous whether 52/4 is the pre- or post-fix count.

**MINOR-4** — `tools/lune/check_example_drift.luau:119-128`: R2's `role` rule accepts
`TEXT_ROLES ∪ TINT_ROLES`. `UI.Text{ role = "danger" }` — not a legal `Text.role`
(`secondary|content`) — passes the lint. The union is justified in the comment; the
consequence is a soundness hole the schema, not the lint, would catch.

**MINOR-5** — Same file, `NUMBER_RULES:86-97`: patterns require the digits to follow the
`=` immediately, so a table form (`padding = { top = 24 }`) escapes R1. No current
example uses that spelling, so this is latent.

**MINOR-6** — Same file, `:256-262`: an allowlist entry matches a plain substring
anywhere on the line and suppresses **every** violation found on it, not just the one it
names.

**MINOR-7** — `tools/lune/gate.luau:36-43`: `severity()` has no `FAIL_PRODUCT` entry, so
it falls through to the default `4` (the `FAIL_RECOVERABLE` rank). The gate still fails
correctly; the state vocabulary is just undeclared in the runner.

**MINOR-8** — The drift lint scans `examples/gallery/examples` only
(`check_example_drift.luau:39-45`). `examples/gallery/client/theme_picker.luau`,
`init.client.luau` and `scenarios/` are unscanned, so the plan's "example **adapter
writes**" clause is covered only for the seven modules. The exclusion is documented and
defensible; recording it here so it is a decision, not an omission.

**MINOR-9 (process)** — **The repository was being written while I verified it.**
`tools/lune/gate_manifest.luau` changed at 11:19:42 and again at 11:25:12;
`studio/ex05.json` at 11:19:42; `drift.json` at 11:25; the four missing evidence
artifacts appeared at 11:31:18; `reviews/architecture.md` at 11:29. My first gate run
(11:19) saw a manifest in which **every check was a bare `PENDING`**; my second (11:20)
saw one with a broken `grep -q "\*\*$id\*\*"` that errored `repetition-operator operand
invalid` (since fixed to `grep -qF`). Only the 11:31:56 run is a judgement of the
current tree. A phase gate should be handed to acceptance control against a frozen tree;
otherwise the verifier's findings and the lead's fixes cross in flight.

---

## 4. What I did NOT check, and why

- **Any live Studio session.** I did not open Studio or re-drive the examples scenario.
  Every Studio-sourced number in this stage (`device-matrix.json`, `theme-swap.json`,
  `large-text.json`, `ex03/ex05/games/lifecycle.json`) is therefore **read, not
  reproduced**. Where a number is a self-report with no independent instrument, I have
  said so rather than assumed it.
- **`tools/prior_gates.sh`.** It is a bare `PENDING` in the manifest and was, on the
  evidence of `artifacts/phase-4/*.json` mtimes at 11:23-11:24, being run concurrently by
  the lead. Re-running it would have collided.
- **`tools/build_places.sh`.** Not re-run; `places.json` was judged as a document
  (MAJOR-8), not regenerated.
- **The Rascal Rally suite.** Run indirectly by the `rascalrally-consumer` gate check
  (which passed); I did not run it standalone or open the game tree.
- **Byte-level determinism re-run-and-diff.** `drift.json` is deterministic by
  construction (pure file scan) and I re-ran it; the Studio artifacts cannot be re-run
  from this context.
- **`reviews/architecture.md`.** Out of scope for this review and deliberately not read,
  to keep this a fresh-context judgement.

---

## 5. The shortest path to `ACCEPT`

1. Produce the capture set (BLOCKER-1) or demote the six rows that name it.
2. Add a post-fix play matrix with the paradigm/form-factor columns, and tighten
   `play-teaching-matrix` so it cannot pass an all-`FAIL_PRODUCT` audit (BLOCKER-2).
3. Drive or `FAIL_ENVIRONMENT` the non-pointer input paths for EQ-10, and put real
   VirtualInput traces in EQ-15's artifact (BLOCKER-3).
4. Repair or honestly label the dark `InputBegan` counter (MAJOR-1).
5. Re-synchronise `acceptance.md` with the closing gate run (MAJOR-9), and make
   `acceptance-ledger` assert evidence rather than the status column (MAJOR-7).

EQ-6 / LT-F3 should stay `FAIL_PRODUCT`. Its scoping and its instrument caveat are the
most rigorous work in this stage and I would not weaken either.
