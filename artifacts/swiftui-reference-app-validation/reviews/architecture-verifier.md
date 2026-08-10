# Architecture verification — swiftui-reference-app-validation (independent)

**Verdict: FINDINGS** (2 MAJOR, 4 MINOR, 5 NOTE, 0 BLOCKER). Date 2026-08-08.
Scope: the stage's FRAMEWORK diff and the five reference proofs' architecture,
judged from source. No files were edited.

## Requirements checked

| Dim | What | Result |
|---|---|---|
| 1 | Public-API discipline in `examples/reference` + `check_example_drift` coverage | Proofs are clean by manual audit; the ENFORCEMENT has two vacuous gate greps and loose allowlist entries (F1, F2, F11, F12) |
| 2 | `UI.Stage` separation (blueprint / mounted / layout / adapter) + NO_SLOT layer | Separation holds; two containment gaps (F3, F8) and one conditional pin (F14) |
| 3 | park/adopt corpse guards, epoch/hint/corpse gate stack | Ownership boundary is defensible; no remaining "destroyed after park" hole found; one state-restore untidiness (F9) |
| 4 | ZStack diagnostic per-axis fill gate | Sound for margins/percent/aspect/minMax; one theoretical hole (F7) and one pre-existing under-measure on the same lines (F6) |
| 5 | The two recorded deferrals + proof-side accommodations | PARTIALLY REVIEWED (see "checks not run") |
| 6 | Optional-feature containment + RascalRally consumer safety | One real evidence gap (F4) |

## Evidence and commands

- `./run-tests.sh` -> exit 0, **3833 passed**.
- `lune run tools/lune/check_example_drift_cli` -> `clean - 74 files, 24080 lines, 440 semantic role uses, 22 allowlisted`, exit 0.
- Reacharound audit of `examples/reference`: zero hits for `Instance.new`, `GetService`, `UserInputService`, `ContextActionService`, `workspace.`, `IsA("`, `src/layout|src/render|src/client`, and zero device-name / `preferredInput ==` / `sizeClass ==` branches (grep over the whole tree).
- Positive-control mutation of the two gate greps in a scratch dir containing `"Backyard Birds"`, `game:GetService(...)`, `Instance.new(...)` (below).
- Source read: `src/render/stage_content.luau` (whole), `src/render/authority.luau` SEAM_OWNED block, `src/render/renderer.luau:1663-1721, 2805-2865, 3683-3701, 3796-3829, 380-451`, `src/client/screen_target.luau:2296-2400, 4206-4421, 4500-4545`, `src/layout/solver.luau:826-862, 916-990, 1530-1596, 1690-1796`, `tools/lune/check_example_drift.luau` (whole), `tools/lune/gate_manifest.luau` (RA-* entries), `examples/gallery/scenarios/runner.luau` stage materializer, `examples/reference/p5_wardrobe/init.luau:20-135, 1040-1090`.

## Findings

### BLOCKER
None.

### MAJOR

**F1 - The RA-5 "forbidden list is enforced by grep" gate check can never fail (broken ERE).**
Confidence: HIGH (mutation-proved).
Location: `tools/lune/gate_manifest.luau`, the `swiftui-reference-app-validation` RA-5 entry, run string fragment:
`! grep -rqE "Instance.new|GetService(|UserInputService|os.clock|os.time|math.random" examples/reference/ --include="*.luau"`
The `(` in `GetService(` opens an unterminated ERE group, so grep exits **2 (error)**, and `! <error>` is TRUE. The check passes on any source, including a violating one.
Reproduction:
```
$ grep -rqE "Instance.new|GetService(|UserInputService|os.clock|os.time|math.random" examples/reference/ --include="*.luau"; echo $?
grep: error at position 28 ... empty (sub)expression
2
# positive control (scratch file containing Instance.new + game:GetService):
$ grep -rqE "Instance.new|GetService(|...|math.random" ref/ --include="*.luau"; echo $?   -> 2  (check still PASSES)
$ grep -rqE 'Instance\.new|GetService\(|UserInputService|os\.clock|os\.time|math\.random' examples/reference/ --include="*.luau"; echo $?  -> 0
```
Note the corrected pattern returns 0 against the real tree - because it matches those words **inside comments** (`p3_sipworks/init.luau:16`, `p1_glade/services/supply.luau:8`, ...). So the intended check needs both an escaped pattern and comment filtering, or it will red on prose.
Violated requirement: the plan's "no local workaround substitutes for framework behavior" is claimed as ENFORCED by this check; a check that cannot fail proves nothing (repo lesson class "a check that proves nothing").
Smallest corrective test: add the positive control - inject a temp `.luau` under `examples/reference/` containing `Instance.new("Frame")` and require the check to exit non-zero.

**F2 - The RA-4 clean-room product-name grep can never fail (alternation without `-E`).**
Confidence: HIGH (mutation-proved).
Location: `tools/lune/gate_manifest.luau`, RA-4 run string: `! grep -rq "Backyard Birds|Food Truck|Fruta" examples/reference/ --include="*.luau"`.
Without `-E` the `|` is a literal, so the pattern searches for the single string `Backyard Birds|Food Truck|Fruta`, which nothing contains.
Reproduction (scratch dir with a file literally containing `Backyard Birds`):
```
$ grep -rq "Backyard Birds|Food Truck|Fruta" ref/ --include="*.luau"; echo $?   -> 1  (check PASSES on a violating file)
$ grep -rqE "Backyard Birds|Food Truck|Fruta" ref/ --include="*.luau"; echo $?  -> 0  (correct)
```
Violated requirement: the stage's IP boundary ("do not copy Apple product identity into the repository") is claimed as grep-enforced. The tree is in fact clean (`grep -rE` over `examples/reference` returns nothing), so this is an evidence defect, not an IP defect.
Smallest corrective test: same positive control, with `-E`.

### MINOR

**F3 - The Stage escape hatch is addressed only by a hardcoded mounted path, and the proof's fallback discovery uses an adapter method that exists ONLY on the test double.**
Confidence: HIGH on the mechanism, MEDIUM on severity.
Locations: `src/render/renderer.luau:3693` (`controller.stageHost(path)` keyed on `handles[path]`); `examples/reference/p5_wardrobe/init.luau:23` (`local PANE_PATH = "/Wardrobe/BoutiqueWhen/then/Body/Preview/PreviewCol/PaneZ/Pane"`), `:1053-1067` (fallback: iterate `deps.adapter.paths()` looking for the substring `/PaneZ/Pane`); `tests/lib/fake_target.luau:1185` (`function adapter.paths()` - the ONLY definition; it is not in `src/render/target_contract.luau` OPTIONAL and not on `screen_target`).
Consequences: (a) the escape hatch has no public "address this node" channel, so the consumer hardcodes a 7-segment mounted path that any structural edit silently invalidates; (b) `controller.stageHost` returns nil for *three* different conditions (no adapter seam / node not mounted / typo'd path) with no diagnostic, so a wrong path degrades permanently and quietly to the fallback plate; (c) the discovery fallback is live-dead - on `screen_target` `adapter.paths` is nil - so the headless and live proofs traverse different code, the exact asymmetry `src/render/stage_content.luau:5-9` says the shared normalizer exists to prevent.
Violated requirement: escape-hatch contract soundness; "no local workaround substitutes for framework behavior".
Smallest corrective test: a headless case that mounts a Stage, asks `controller.stageHost("/typo")`, and asserts a *distinguishable* answer (or a recorded diagnostic) rather than the same nil the no-seam case returns.

**F4 - The one framework change that is visible ONLY live is justified with evidence that is structurally blind to it.**
Confidence: MEDIUM-HIGH.
Locations: `src/layout/solver.luau:851-861` (cross-axis `+ reserve`); `artifacts/swiftui-reference-app-validation/consumer-impact.md` ("Game suite green at the judged source", "Studio canary: not owed").
`ctx.scrollBarReserve` is 0 for the headless twin (`grep -n scrollBarReserve tests/lib/fake_target.luau tools/lune/check_flat_baseline.luau` -> no hits), so both the RascalRally headless suite and `check_flat_baseline` run at reserve 0 and cannot observe this change at all. The affected shape - a scroll node whose CROSS axis is `hug`/`content`, or a `fill`-cross scroller inside a hugging parent (`resolveAxis` answers `fill` with `contentFn()`, which now includes the reserve) - exists in the game's vocabulary; e.g. `games/RascalRally/code/src/client/LuauUISponsor/ResultsScreen.luau:2458` is a `hug`-height y-scroller (safe: its cross axis is fixed/fill), but nothing in the ledger's evidence would have shown it if it were not.
Violated requirement: root CLAUDE.md - "add or update a Rascal Rally contract/integration test ... plus an affected game Studio canary"; and one-authority/consumer-safety honesty.
Smallest corrective test: a game-side (or framework-side, game-shaped) solver test that solves a `hug`-cross scroller with `scrollBarReserve = 8` and pins the +8, plus one line in the ledger stating the headless blindness explicitly.

**F5 - The scroll bar-reserve fix uses the OFFER as the main-axis extent, so the same defect survives for a scroll node whose main axis is `fixed`/`percent`/`minMax`.**
Confidence: MEDIUM.
Location: `src/layout/solver.luau:853-856` (`local mainOffer = if axis == "x" then innerMaxW else innerMaxH`) vs arrange's condition at `:1549-1551` (`contentH > innerH`, where `innerH` is the *granted* rect).
`contentSize` is called with the parent's OFFER, not the node's own resolved size. For `hug`/`fill` main axes the two coincide, which is why the wardrobe shape is fixed; for `height = { fixed, 200 }` (or a percent/minMax cap) inside a 900-tall offer with 400px of content, measure sees no overflow and adds no reserve, while arrange overflows and subtracts one - reproducing exactly the "reported a cross size it cannot reproduce" bug the fix names.
Violated requirement: measure/arrange fixed point (the stated rule of the fix itself).
Smallest corrective test: solve `ScrollView{ axis="y", height=fixed(200), width=hug, children = 400px of rows }` at `scrollBarReserve = 8` inside a 900-tall offer and assert the reported width includes the reserve (currently it does not).

**F8 - `SEAM_OWNED` cannot actually be enforced against the consumer that holds `contentRoot()`; the comment claims it is.**
Confidence: HIGH on the mechanism, LOW-MEDIUM on severity (Roblox offers no way to close it).
Locations: `src/render/authority.luau` SEAM_OWNED block - "so a bespoke explicit write from anywhere else is a LOUD error"; `src/client/screen_target.luau:2296-2400` (`contentRoot()` returns `handle.stageWorld`, a `WorldModel` **parented to the framework-owned ViewportFrame**).
`assertSeamWrite` only gates writes made *inside the adapter*. A consumer holding `contentRoot()` reaches the frame with one `.Parent` (or `FindFirstAncestorOfClass("ViewportFrame")`) and can write `Ambient`/`LightColor`/`LightDirection`/`CurrentCamera` silently - a second authority with no error. The claim should be scoped to "no second writer inside LuauUI", and the consumer contract should say the frame is off-limits by rule.
Smallest corrective test: none executable; a doc-anchored line in api.md's Stage section + a source-anchor test that the phrase "from anywhere else" is scoped.

### NOTE

**F6 - The ZStack diagnostic still measures the child at the pre-margin box while arrange measures it post-margin (pre-existing, same lines).**
Confidence: HIGH. `src/layout/solver.luau:1741` measures with `(innerW, innerH)`; `:1770-1772` measures with `(availW, availH) = inner - margins`. For a wrap-sensitive child with horizontal margins the diagnostic's height is measured at a WIDER offer than the child will get, so a genuine overflow is under-reported; and `overH` is compared to `innerH` rather than `availH`. Not introduced by this stage, but the axis gate makes this the trustworthy-overlap-signal claim, and this is the residual untrustworthy half.
Corrective test: hug child with `margin = 24` and wrapping text in a tight ZStack; assert the diagnostic fires.

**F7 - The fill-axis skip is sound for every child shape I could construct EXCEPT negative margins.**
Confidence: MEDIUM (I did not verify whether the schema admits a negative margin).
Verified sound: plain fill (granted exactly `availW/availH` at `:1779-1784` and positioned at `innerX+ml`, so it cannot leave the box); `percent` (not skipped); `minMax` (not skipped); `aspect` paired with fill (the aspect axis is NOT skipped, and `pairedExtent` at `:1244-1260` makes its measure honest - a `height=fill`+`width=aspect` child that overruns width is still reported). With a negative margin, `availW > innerW` and `x = innerX + ml` is outside the box, and the fill axis is now unconditionally 0 - so that displacement is invisible. Old code did not reliably catch it either (it compared sizes, not positions).
Corrective test: if negative margins are legal, a `width=fill, margin={left=-40}` child in a ZStack should still report.

**F9 - `adopt`'s refusal path restores identity only partially.**
Confidence: HIGH on the facts, LOW on impact.
Location: `src/client/screen_target.luau:4349-4367`. On a failed reparent the handle gets `parked = true` and `path = PARKED_PATH`, but `handle.instance.Name` keeps `newPath` (written at `:4350`) and `parkedChromeEpoch` stays nil (cleared at `:4348`). Today the renderer discards immediately (`src/render/renderer.luau:1699-1701`), so nothing observes it; the invariant "a parked handle's instance is named PARKED_PATH" is nonetheless broken, and a census by instance name would count a corpse as a live node.
Corrective test: pin `handle.instance.Name == PARKED_PATH` after a refused adopt in `tests/instance_park_corpse.spec.luau`.

**F10 - The corpse-guard ownership boundary is defensible, and I found no remaining "destroyed while pooled" hole.**
Confidence: MEDIUM-HIGH. Instances are FLAT under their clip host (`hostFor(newPath)` + `instance.Parent = host.instance`), and `parkEligible` refuses clip hosts, so Destroy propagation can only reach a *pre-park* descendant - which is exactly what `:4222-4232` now refuses. After a successful park the instance is unparented, so no later ancestor Destroy can reach it; and `controller.dispose` drains the pool BEFORE `adapter.destroyRoot` (`src/render/renderer.luau:3825-3826`), so the pool is never destroyed out from under itself. Ordering the removal loop children-first would be the alternative, but it would put the fix in the renderer for a fact only the adapter owns (which instances are parented where) - the two seams chosen are the right layer. The `Parent == nil` test is a heuristic for "destroyed", not a destruction test; it errs toward refusing, which is the safe direction.

**F11 - Reference-dir allowlist entries are loose substrings and suppress every rule hit on the matching line.**
Confidence: HIGH.
Location: `tools/lune/check_example_drift.luau` ALLOWLIST entries `match = "min = 0,"`, `"max = 1,"`, `"min = 160,"`, `"max = 900,"` (p2/p5). Suppression is file-scoped and whole-line (`:389-396`: any rule hit on a line containing the substring is dropped), so e.g. a future `Color3.new` (R3) or `Instance.new` (R4) on a line that also contains `max = 1,` in `p2_cartwheel/screens/workbench.luau` would be silently allowed.
Corrective test: make the allowlist entry match the FULL trimmed line, or record the rule id it exempts.

**F12 - R4's reacharound vocabulary does not cover the shapes the plan names.**
Confidence: HIGH.
Location: `tools/lune/check_example_drift.luau:146-158`. There is no rule for requiring framework internals (`require("../../src/...")`, `require(script.Parent.Parent.src...)`), for `ContextActionService`/`RunService`/`Enum.KeyCode` (a "local key listener"), or for a parallel focus graph. The proofs are clean on all of these by manual grep, so this is coverage debt, not a live violation.
Corrective test: add the patterns and re-run; expect clean.

**F13 - No proof exercises `contentRoot()` itself; the runner does.**
Confidence: HIGH.
Location: `examples/gallery/scenarios/runner.luau` `applyStageContent` (the only caller of `host.contentRoot()` outside tests) and `examples/reference/p5_wardrobe/init.luau:135` (`deps.stage.apply(PANE_PATH, { parts = parts })`). Keeping the proofs engine-free is the right call and is declared, but it means the caller-owned half of the Stage contract is proven through dev tooling only - worth stating plainly in the capability ledger rather than reading as "a proof uses the seam".

**F14 - The NO_SLOT pin is conditional on `hint == nil`.**
Confidence: MEDIUM.
Location: `src/render/renderer.luau:1672` - `if node.class == "Stage" and hint == nil then hint = { slot = chrome_slots.NO_SLOT } end`. The ruling being encoded ("a Stage is never a decoration surface") is a CLASS fact, but any node arriving with a decoration hint on the internal meta channel (`chrome_slots.withHint`, used by composite controls) keeps that hint and can still classify into a covering slot. The renderer is a defensible layer (it is where classification happens), but the rule should be unconditional for the class - or `chrome_slots` should refuse a non-NO_SLOT hint on `Stage` at the point of authorship, which is where the class fact lives.
Corrective test: build a Stage node carrying a `control` hint through `chrome_slots.withHint` and assert the created node still classifies NO_SLOT.

## What is sound (positive findings)

- **Separation holds for `UI.Stage`.** The solver never learns the class: `renderer.luau:449-450` falls it through to `kind = "box"` (measures 0x0, no new layout kind, no engine type above `src/client/`). The blueprint class is a leaf with `container = false, structural = false`. `stage_content.luau` is pure, engine-type-free, shared by both adapters, and refuses half-specs by name. `billboard_target.luau` strips the seam (documented degrade), and `screen_target` degrades to a `Frame` when the three classes are absent - so the optional feature is contained on both axes.
- **Authority.** One authored channel (`tint = "binding"`), the four engine properties declared `SEAM_OWNED` with a named writer, and `writeStageProp` indexes by name so a dotted bespoke write is greppable-at-zero. `TINT_IDENTITY.Stage = "white"` matches the ImageColor3 multiply the adapter actually uses.
- **Proof-side public-API discipline.** Zero raw Instances, zero engine services, zero device-name branches, zero `src/` reaches across all 21k lines of `examples/reference`; drift scan now covers the tree recursively (`74 files` scanned, up from the tutorials alone).
- **Suite.** 3833 passed, exit 0, at the judged source.

## Checks not run, and why

- **Dimension 5 (the two deferrals) is PARTIALLY REVIEWED.** I read the recorded findings and judged the *deferral* of the `align` channel split defensible on its face (splitting a widely-used prop's meaning is a compatibility event, not a bounded fix). I did **NOT** verify the two proof-side accommodations in source (`p5` PaneZ `fill`, `p1` rail `percent(1)` pairing) or finding 13's claim that a `fill`-width ScrollView contributes 0 to a hug parent's measure - which reads as in tension with `resolveAxis`'s `fill -> contentFn()` (`solver.luau:546-548`) and now with the reserve added to that same contribution. **NOT-REVIEWED / possibly stale finding.**
- **Live/Studio behavior:** not run (headless environment; no Studio session). All live claims (captures, place builds, the parchment A/B) are taken as recorded, not verified.
- **`tools/studio/device_matrix.luau` instrument hardening:** NOT-REVIEWED (out of the four prioritized dimensions).
- **`src/themes/package.luau` iconGlyph ASCII derivation:** NOT-REVIEWED beyond noting its test exists (`tests/icon_ns_glyph.spec.luau`) and the suite is green.
- **p1-p4 proof internals** (only p5 and p2's stage wiring were read in detail); the public-API audit above is grep-complete over all five, but the composition-level architecture of p1/p3/p4 was not read line by line.
- **Prior gates / bench:** not re-run (2h sweep; the gate's own roll-up covers it).
