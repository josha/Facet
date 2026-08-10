# Fresh-context phase-gate verification — swiftui-reference-app-validation

Verifier run 2026-08-08 from fresh context. Everything below was rerun or read from
disk by the verifier; no implementer conclusion was taken on faith.

## Verdict

**FINDINGS.** The gate is correctly RED right now (device-matrix + fixture-axes fail
on the owed foyer/wardrobe rows; acceptance-ledger fails on nine PENDING rows;
fresh-context-reviews is PENDING) — that part is the designed behavior and it works.
But three gate checks prove less than their notes claim (two of them prove literally
nothing), two proof artifacts overclaim evidence that is not on disk, and the
prior-gates "quiet machine" justification is contradicted by the roll-up's own load
column.

## Gate criteria rerun

| Check | Command run | Observed |
|---|---|---|
| library-suite-green | `./tools/test.sh` | `test: PASS passed=3833` exit 0; artifacts/test.json passed=3833 failed=0. Floor 3833 met exactly |
| (determinism) | `./run-tests.sh` a second time | 3833 passed, exit 0 — identical count, no flake |
| responsibility-ledger (drift clause) | `lune run tools/lune/check_example_drift_cli` | exit 0, "clean — 74 files, 24080 lines, 440 semantic role uses, 22 allowlisted" |
| docs-updated | `lune run tools/lune/check_docs_cli`, `check_registration_cli` + parity greps | both exit 0; all three greps in docs/reference/swiftui-parity.md OK |
| prior-gates battery | `python3 tools/check_manifest_integrity.py`; `stylua --check src tests tools examples`; `lune run tools/lune/check_flat_baseline` | exit 0 / exit 0 / PASS (1773 flat nodes byte-compared) |
| rascalrally-consumer | `cd games/RascalRally/code && ./run-tests.sh` | 3094 passed, exit 0 — matches the claim |
| device-matrix | the check's python verbatim | exit 1, `AssertionError: foyer: {...'RERUN_OWED'...}` |
| fixture-axes | the check's python verbatim | exit 1, `AssertionError: foyer axes owed` |
| acceptance-ledger | the check's shell loop verbatim | RA-5, RA-9, RA-P4, RA-P5, RA-M1..RA-M5 "not closed" → check fails |
| proof-{garden,dashboard,catalog,discovery-home,avatar-editor}-loop | all 26 `✓` greps against the captured suite output | all present |
| framework-fixes-tested | all 9 suite greps + all 6 file greps | all present (the FAIL_RECOVERABLE in gate.json is stale) |
| places-and-builds | digests/sizes recomputed (`shasum -a 256`, `stat`) | all five match places.json byte-for-byte and digest-for-digest |
| capability-ledger / source-inspection / physical-and-human-rows / consumer-impact greps | verbatim | all present |
| gate exit semantics | read tools/lune/gate.luau | `overallPass` requires PASS or non-releaseBlocking FAIL_ENVIRONMENT; PENDING fails; `process.exit(if overallPass then 0 else 1)` — the gate **cannot** exit 0 while foyer/wardrobe read RERUN_OWED. Item (d) confirmed |

Not run, by instruction or by risk: `tools/gate.sh`, `tools/prior_gates.sh`,
`tools/bench.sh`, `tools/build_reference_places.sh` (would overwrite the judged
`.rbxl` set — verified by digest instead).

## Findings

### BLOCKER
None.

### MAJOR

**M-1 — `responsibility-ledger` check: the forbidden-list grep is an invalid regex
and can never fail.** (confidence: high)
`tools/lune/gate_manifest.luau:95` runs
`! grep -rqE "Instance.new|GetService(|UserInputService|os.clock|os.time|math.random" examples/reference/ --include="*.luau"`.
The `GetService(` alternative leaves an unbalanced `(` in an ERE. Rerun observed:
`ugrep: error: error at position 28 ... empty (sub)expression`, **exit 2**; `!`
turns exit 2 into success, so the clause passes unconditionally. The stage's own
`gate.json` already records this in the check's `detail` field —
`"detail": "grep: empty (sub)expression"` beside `"state": "PASS"`. The note claims
the forbidden list "is ENFORCED by grep over every proof source"; it is not enforced
at all. (Substance is fine: a corrected grep
`grep -rnE "Instance\.new|GetService\(|UserInputService|os\.clock|os\.time|math\.random" examples/reference --include="*.luau"`
hits only comment lines, so no proof actually violates the list. The defect is the
check, not the code.) Smallest corrective test: escape the paren, then mutation-prove
by adding `local x = Instance.new("Frame")` to one proof file and confirming the
check reddens.

**M-2 — `source-inspection-and-ip-boundary` check: the clean-room grep is a literal
string and can never match.** (confidence: high)
Same file, line 81: `! grep -rq "Backyard Birds|Food Truck|Fruta" examples/reference/ --include="*.luau"`
— basic grep, so the pipes are literal characters. Rerun: exit 1 (no match), clause
passes; it would pass identically if every proof file were named "Fruta". The note
claims "the clean-room grep proves no reference product name appears in any proof
source". Searching the three names individually returns zero files, so the IP
boundary does hold — again, the check is what is broken. Smallest corrective test:
`grep -rqE` (or `-e` per name) and mutation-prove by inserting `-- Fruta` into a
proof file.

**M-3 — `prior-gates-unregressed`: the allow-list is by gate NAME, not by
(gate, check) pair, contradicting its own note and analysis.** (confidence: high)
Line 149 filters `grep "^FAIL " | grep -vE "^FAIL (phase-1-minimal-screen|phase-2-settings-parity|phase-3-pilot|part-2-director|expansion-textinput|code-simplicity-cleanup|api-architecture-consistency|example-quality-pass) "`.
That excuses those eight gates for **any** failing check, forever. But
`artifacts/swiftui-reference-app-validation/prior-gates-analysis.md:80` says
"Any gate outside these **EIGHT named (gate, check) pairs** going red fails the
`prior-gates-unregressed` check", and the manifest note says the five are
allow-listed "BY NAME ... their only failing checks shell to tools/bench.sh". If, say,
`code-simplicity-cleanup` later goes red on a real check that is not
`performance-unregressed`, this check still passes. Smallest corrective test: match
the check line too (e.g. require each FAIL gate's indented failing-check line to be
in the pair list), and mutation-prove by editing prior-gates.txt to add a second
failing check under `code-simplicity-cleanup`.

**M-4 — `proofs/discovery-home.json` and `proofs/avatar-editor.json` declare E3
Studio row evidence that does not exist on disk.** (confidence: high)
Both files carry `"evidenceClass": "E1 (suite) + E3 rows in ../studio/"`. Observed:
`artifacts/swiftui-reference-app-validation/studio/foyer/` is **empty** (zero files),
and `studio/wardrobe/` holds exactly one file, `row-compact-phone-portrait.json`, whose
own body reads `"ok": false`. `studio/device-matrix.json` marks all five foyer rows and
all five wardrobe rows `RERUN_OWED`. The two proof artifacts therefore state an
evidence class the stage does not hold. This is the one place in the stage where an
owed row is described as if it were collected. Smallest corrective test: change both
to `E1 (suite); E3 rows RERUN_OWED (see studio/device-matrix.json)` and re-read.

**M-5 — the prior-gates roll-up contradicts the "quiet machine" claim it rests on.**
(confidence: medium)
`prior-gates.txt` header: `# settle: max=45s threshold=2 (1-min load average)`. Six of
the seven FAIL lines record `[load at start: 3.99 / 3.65 / 4.08 / 3.73 / 3.96 / 4.14]`
— i.e. the sweep waited out its 45s cap and started those gates at ~2x its own
quiet threshold, in the same load band (4–7) that `prior-gates-analysis.md` uses to
dismiss Sweep 1 as "evidence about the environment, not the source". The analysis
nevertheless calls this file "a full regenerated sweep at the judged source on the
quiet machine" and argues the five bench gates "stayed red through quiet re-runs".
The direction of the error is benign for greens (a pass under load is still a pass),
but the recorded artifact does not support the "quiet" premise of the allow-list
justification. Note also that `example-quality-pass`, the one FAIL at load 2.50, is
the one with a non-bench cause. Smallest corrective test: regenerate the roll-up with
the settle gate actually satisfied (or record why the cap was allowed to expire), and
state the observed load for PASS gates too.

### MINOR

**m-1 — `gate.json` is stale; no roll-up exists for the current manifest.**
(confidence: high) `artifacts/.../gate.json` mtime 12:24, but `tools/lune/gate_manifest.luau`
is 17:17, `prior-gates.txt` 16:07, `acceptance.md` 12:29, `prior-gates-analysis.md` 17:17.
gate.json records `acceptance-ledger` and `prior-gates-unregressed` as `PENDING` (they had
no `run` string yet) and `framework-fixes-tested` as `FAIL_RECOVERABLE` — I observe that
check's 15 clauses all pass now. Judge the gate from a fresh run, not this file.

**m-2 — acceptance.md RA-5 states the wrong suite floor.** (confidence: high)
`acceptance.md:28` — "Full library suite green at close, **floor 3556**"; the gate check
enforces `./tools/test.sh 3833`. The ledger row understates its own bar by 277 cases.

**m-3 — `framework-fixes.md` omits a shipped fix and still lists it as open.**
(confidence: high) The namespaced-icon ASCII floor shipped
(`tests/icon_ns_glyph.spec.luau`, `themePackage.iconGlyph`), and the gate check anchors
its case name — but the "Fixed this stage" table has no row for it, while finding 12
still reads "may not draw the documented ASCII-safe fallback in practice ... needs one
live check ... Reconcile api.md's claim". RA-7's artifact is out of sync with what
shipped. Relatedly the manifest note for `framework-fixes-tested` still says "The four
bounded fixes" while six are claimed.

**m-4 — the park-corpse "mutation proof" is tautological.** (confidence: high)
`tests/instance_park_corpse.spec.luau` is three `string.find` assertions over the text of
`src/client/screen_target.luau` (e.g. asserting the literal comment `A CORPSE CANNOT
TRAVEL` is inside `parkEligible`). framework-fixes.md:110 says "Mutation-proved: deleting
either guard reddens its case" — that is true by construction for a source-anchor test and
proves nothing behavioral. The spec header discloses this honestly and points at the live
A/B, so this is transparency-adequate; but two of the nine suite anchors in
`framework-fixes-tested` cannot detect a behavioral regression, only a text deletion.

**m-5 — no captures exist anywhere in this stage.** (confidence: high) The only image
under `artifacts/swiftui-reference-app-validation/` is `sources/roblox-home-narrow-observation.png`.
The plan's Evidence section requires "Pair captures with geometry, input/action, focus,
state, lifecycle, and performance evidence"; RA-M1's required evidence says "geometry/focus
asserted before captures"; RA-P1's says "E3 played slice with traces/**captures**" and the row
is closed `PASS_AUTOMATED+E3`. framework-fixes.md cites capture names that are not on disk
(`wardrobe-parchment-real`, `wardrobe-live-1..3`, `glade-parchment-postfix`,
`captures wardrobe-parchment-real vs -stage-fixed`). Either the captures are missing from the
artifact tree or the rows should say geometry-only.

**m-6 — row evidence carries a broken metrics collection but is still `ok`.**
(confidence: high) All five `glade/row-*.json` and the one `wardrobe/row-*.json` contain
`"metrics": {"error": "ReplicatedStorage.LuauUIScenarios.runner:1171: no step 'measure' in
scenario 'ref_glade'"}` (resp. `ref_wardrobe`). The performance half of the plan's evidence
pairing is absent on those rows and the `rowOkRule` does not require it.

**m-7 — the device-matrix check's per-row evidence clause is existence-only.**
(confidence: high) `ls artifacts/.../studio/$p/row-*.json >/dev/null` passes on a directory
holding one row file whose body says `"ok": false` (exactly wardrobe's current state). The
only thing that actually gates status is the hand-authored summary `device-matrix.json`.
Smallest corrective test: assert five `row-<rowname>.json` files per proof and that each
file's own `ok` is true.

**m-8 — the fixture-axes settled-0 assertion accepts any string containing "0".**
(confidence: high) `assert v == 0 or (isinstance(v, str) and '0' in v)` — the string
`"10 diagnostics"` or `"overflow x40"` satisfies it. Smallest corrective test: require
`v == 0` or a strict pattern like `re.fullmatch(r'0\b.*', v)`.

### NOTE

**n-1 — dead code in the capability-ledger check.** `for s2 in "## B." ... ; do true; done`
(gate_manifest.luau:88) evaluates nothing. Harmless, but it reads like an assertion.

**n-2 — proof case counts disagree between the acceptance ledger and the proof JSONs.**
acceptance.md says RA-P1 "73 cases", RA-P2 "62 pins", RA-P3 "63 pins"; the JSONs say
`headlessCases` 72 / 60 / 41. Possibly counting different things (spec cases vs pins); the
41 vs 63 gap is the one worth reconciling. (confidence: low)

**n-3 — the touch-shaped paradigm is not uniformly obtained.** `device-matrix.json`
`paradigms` states that the sipworks session produced `KeyboardAndMouse` rather than
`Touch` preferredInput, yet those rows read `ok`. Honestly disclosed, not hidden; recorded
so the reader does not read "phone row ok" as "touch paradigm exercised".

**n-4 — the allow-list was widened after the sweep that motivated it.**
`gate_manifest.luau` and `prior-gates-analysis.md` share mtime 17:17, both after
`prior-gates.txt` (16:07). Adding `phase-1-minimal-screen` and `part-2-director` after
seeing them go red is documented with fresh reasoning (both fail only on `tools/bench.sh`,
which passes standalone), so this is disclosed rather than concealed — but it is
check-fitted-to-result and should be read as such. `api-architecture-consistency` is in the
allow-list while passing in this roll-up.

**n-5 — confirmations (no defect).** Evidence-class labelling is honest where I could check
it: every row file says `"studio-emulated"` / `E3`, `device-matrix.json` says
`"studio-emulated (E3); physical/human rows live in review-packet.md"`, RA-X1/X2 stay
PENDING_PHYSICAL and RA-X3 PENDING_HUMAN, and `review-packet.md` explicitly says "Nothing
here is closable by Studio emulation, and none of it was relabelled as automated evidence".
`consumer-impact.md`'s "What this ledger does NOT claim" honestly declines the Studio canary.
No headless result is claimed as live anywhere I read.

## Checks not run / NOT-REVIEWED

- `tools/gate.sh`, `tools/prior_gates.sh` — excluded by instruction (long, mutate shared artifacts).
- `tools/bench.sh` — the tail clause of `prior-gates-unregressed`; not run (mutates artifacts/bench.json). The bench-instrument allow-list argument is therefore assessed from documents only.
- `tools/build_reference_places.sh` — not run; it would overwrite the judged `.rbxl` set. Substituted a digest/size recompute, which matches places.json exactly.
- The five Studio device rows themselves — not re-driven (needs a Studio session); judged from the recorded row JSONs.
- `artifacts/.../specs/`, `package-briefs.md`, `sources/features-*.md` bodies — NOT-REVIEWED beyond existence and the gate's own greps.
- `capability-ledger.md` was checked for the gate's structural greps only; its ~22k of per-feature classifications were NOT-REVIEWED row by row.
