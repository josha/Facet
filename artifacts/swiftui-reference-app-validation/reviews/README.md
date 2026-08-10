# Fresh-context reviews — swiftui-reference-app-validation (2026-08-08)

Three independent fresh-context reviews ran on the raw artifacts at the judged
source, without the implementer's conclusions: the phase-gate verifier
(`phase-gate-verifier.md`), the architecture verifier
(`architecture-verifier.md`), and the Roblox-platform verifier
(`roblox-platform-verifier.md`). Verdicts: **0 BLOCKER** across all three;
every MAJOR was fixed the same day and re-proven; every MINOR/NOTE is either
fixed or dispositioned below. The first two verifiers independently converged
on the same two vacuous gate greps — the strongest possible signal the review
pass was real.

## MAJOR findings and their closures

| Finding | Review(s) | Closure |
|---|---|---|
| Forbidden-list grep can never fail (unbalanced ERE paren; `!` masks grep's error exit) | phase-gate M-1, architecture F1 | Pattern rewritten with `[.]`/`[(]` classes + full-line-comment filter (the proofs legitimately DOCUMENT the bans in prose); mutation-proved both ways: a code-line `os.clock()` probe fails the check, the clean tree passes |
| Clean-room product-name grep can never match (basic grep, literal pipes) | phase-gate M-2, architecture F2 | `-E` added; mutation-proved with an injected `-- Fruta` probe; tree confirmed genuinely clean |
| Prior-gates allow-list was by gate NAME, not (gate, check) pair | phase-gate M-3 | Check rewritten as a python parse of the roll-up asserting every FAIL gate's indented failing-check line is in the eight named (gate, check) pairs |
| Two proof artifacts claimed E3 rows not on disk | phase-gate M-4 | `discovery-home.json` / `avatar-editor.json` evidenceClass now states the rows are OWED behind the lock blocker and flips back only when re-collected |
| "Quiet machine" premise contradicted by sweep's own load column | phase-gate M-5 | Analysis rewritten: the sweep is never quiet by construction; the quiet evidence is the load-gated isolated re-runs (measured 1.89–1.99) and `tools/bench.sh` passing standalone; the gate check now also runs bench live |
| Park-corpse spec could not fail (text-presence anchors; inverted guard stayed green) | platform M1 | Anchors made DIRECTIONAL (condition tied to consequent in one pattern); mutation-proved: inverted guard reddens, dropping any restore line reddens |
| Degenerate-camera refusal lived only in the live adapter (headless recorded what live throws on) | platform M2 | Guard moved into `stage_content.normalizeCamera` (shared); live adapter's copy removed; new headless case: coincident spec throws AND records nothing |
| Native-StyleSheet mode rendered `UI.Stage` on an opaque grey plate (no sheet selector reaches ViewportFrame) | platform M3 | Unconditional `BackgroundTransparency = 1` in the Stage creation branch with the why recorded; live confirmation rides the owed wardrobe re-run (native mode is not the reference places' mode, so no archived row was wrong) |
| Row artifacts hand-reduced with divergent shapes; touch axis unproven on two proofs; sipworks keyboard row lacks rawInput | platform M4, M5, N8 | `device-matrix.json.rerunShapeRule` now REQUIRES the full driver JSON per re-collected row and requires any non-Touch phone row to drive the declared env seam (freezeEnv+setEnv) or record input-class-unproven; executed with the owed re-runs |

## MINOR/NOTE closures and dispositions

- **Architecture F3 / platform-adjacent** (stageHost nil for three reasons; fake-only `adapter.paths()`): follow-on finding 17; the wardrobe fallback path is dev-tooling-only and its live half rides `PANE_PATH` which the live rows exercise.
- **Architecture F4** (bar-reserve invisible to headless consumer evidence): consumer-impact.md rewritten to own the blindness; a RascalRally sponsor/settings Studio canary is queued with the unlock re-runs.
- **Architecture F5** (reserve gates on offer, not resolved main size): follow-on finding 16 with the exact shape; no proof/example hits it.
- **Architecture F9** (adopt refusal left epoch cleared): fixed — refusal restores the full parked identity (epoch included); directional anchor covers it.
- **Architecture F11** (loose allowlist substrings): the two dead p5 entries (`min = 160,`/`max = 900,`) removed — they had been orphaned by the PaneZ fill change; the p2 gauge-range entries match exactly one line each.
- **Architecture F12** (drift R4 misses require-reacharound/ContextActionService/KeyCode shapes): coverage debt recorded; manual audit in the review found zero hits; follow-on for the drift tool.
- **Architecture F14** (NO_SLOT pin conditional): fixed — unconditional for the Stage class.
- **Architecture F6/F7** (pre-existing zstack margin under-measure; negative-margin hole): pre-existing, recorded in the review file; the axis gate itself verified sound for percent/minMax/aspect/margins.
- **Platform N1** (stageCamera CFrame/FieldOfView outside SEAM_OWNED): fixed — declared seam-owned AND routed through the indexed seam writer so the no-bespoke-write pin covers them.
- **Platform N2** (lookAt collinear-up): follow-on finding 18 + research-doc addendum with the safe authoring rule.
- **Platform N3** (fake park refused Stage by class, live by content): fixed — fake now keys on the content seam like the live adapter.
- **Platform N4** (setEnv silent drops, no freeze check): fixed — errors when unfrozen, returns `{applied, failed}`.
- **Platform N5** (keyboardFirst unbind one-shot): follow-on finding 19; every archived row ran in a one-scenario session where the claim holds.
- **Platform N6/N7** (safe-area/notch row unowned; ButtonStart/Select arbitration missing): review-packet RA-X1/RA-X2 extended (see review-packet.md).
- **Platform T5** (residual twin divergences incl. fake adopt missing the epoch gate): pre-existing L-28 scope, recorded; the corpse class this stage fixed is covered by the live A/B + directional anchors.
- **Platform T6** (PolicyService absent): added to responsibility-ledger.md.
- **Platform T7/T9** (host-capability interactionClasses; authored vs derived overscan): honesty notes added to device-matrix.json.
- **Phase-gate m-1** (stale gate.json): the final gate run at close regenerates it; m-2 (floor wording) fixed; m-3 (fix count) fixed in ledger + manifest note; m-4 superseded by platform M1's directional fix; m-5 (captures) honesty note added to acceptance.md; m-6 (metrics.error) note added to device-matrix.json; m-7/m-8 (weak clauses) both strengthened; n-1 (dead loop) removed; n-2 (case counts) reconciled.

## What the reviews did NOT close

Live Studio verification of M3/N2/N5/T7 shapes, the foyer/wardrobe matrix
re-runs, and the physical/human rows — all owed behind the workstation lock or
the RA-X rows, all named in device-matrix.json and review-packet.md. The gate
cannot exit zero while the re-runs are owed (verified by the phase-gate
reviewer against `gate.luau`'s exit semantics).
