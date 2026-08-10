# Roblox-platform verifier — swiftui-reference-app-validation

Verdict: **FINDINGS**
Date: 2026-08-08. Independent review; no files edited (one temporary mutation
applied to `src/client/screen_target.luau` and restored byte-identical).

## Commands run

- `./run-tests.sh` -> `3833 passed`, exit 0 (baseline, final source).
- Mutation probe: inverted the corpse guard at `src/client/screen_target.luau:4229`
  (`return false` -> `return true`, i.e. restore the shipped defect), re-ran
  `lune run tests/run` -> **`3833 passed`, still green**. File restored from backup
  and re-verified (`grep -n "handle.instance.Parent == nil" -A 2`).
- Official doc checks: `create.roblox.com/docs/reference/engine/classes/ViewportFrame`
  (property list Ambient / CurrentCamera / ImageColor3 / ImageTransparency /
  LightColor / LightDirection — all six confirmed on the frame),
  `.../classes/Instance` + devforum corroboration for `Destroy()` semantics,
  `.../datatypes/CFrame` for `lookAt`.

## Requirements checked

1. `UI.Stage` (ViewportFrame + WorldModel + Camera) engine facts, seam authority,
   teardown, headless-twin fidelity — CHECKED.
2. Park-corpse fix engine claims + live-instance false-positive analysis — CHECKED.
3. Device-matrix evidence (`artifacts/.../studio/`) — CHECKED.
4. Scenario-runner extensions (`keyboardFirst`, `setEnv`/`freezeEnv`,
   `applyStageContent`) — CHECKED (source-level; no Studio session available).
5. Roblox-service mapping in `responsibility-ledger.md` — CHECKED (desk review).
6. `review-packet.md` RA-X1..X3 physical scoping — CHECKED.

---

## BLOCKER

(none)

## MAJOR

### M1 — The park-corpse spec cannot fail; the shipped defect passes it green
**Confidence: high.** `tests/instance_park_corpse.spec.luau:51-59` asserts only that
the *string* `"handle.instance.Parent == nil"` and the comment `"A CORPSE CANNOT
TRAVEL"` appear inside `parkEligible`'s body. Inverting the guard to `return true`
— which is exactly the pre-fix behavior (a destroyed instance is parked, the pool
collects corpses, a later `adopt` throws "Parent property is locked") — leaves the
whole suite at `3833 passed`. Reproduction is the mutation command above.
Violated requirement: the repo's own PG-7 rule ("confirm a mutation BITES before
trusting it") and the gate's "reusable defects are fixed in LuauUI" clause — the
fix is asserted, not proven.
Smallest corrective test: make the source pin *directional*, e.g. capture the
guard's whole statement and assert the consequent is `return false`
(`string.find(body, "handle.instance.Parent == nil then\n\t\t\treturn false")`), or
better, give `fake_target` a nil-Parent-shaped corpse flag so an executable case
exists. Note the second case (`:61-75`) has the same weakness: it greps for
`local reparented = pcall` and `handle.parked = true` within 200 chars, so
dropping the `handle.path = PARKED_PATH` restore also stays green.

### M2 — `setCamera`'s degenerate-camera refusal lives only in the live adapter; the "one ruling, both adapters" contract is broken exactly where it was declared
**Confidence: high.** `src/render/stage_content.luau:2-15` states the whole reason
the module exists: "A normalizer each adapter wrote for itself would be two rulings
on one contract, which is how 'headless green, device wrong' ships (the SF-M9
lesson)." But `normalizeCamera` (`stage_content.luau:75-91`) contains **no**
coincident position/lookAt check. The refusal is written by hand inside the live
adapter only, at `src/client/screen_target.luau:2353-2359`. `tests/lib/fake_target.luau:830-836`
therefore *accepts and records* a camera the live adapter *throws* on.
Reproduction: a proof calling
`host.setCamera({ position = {x=0,y=0,z=0}, lookAt = {x=0,y=0,z=0} })` passes the
headless suite and raises "position and lookAt are the same point" in Studio.
Nothing in `tests/stage.spec.luau` covers it (`:244-260`, `:283-312` cover shape
refusals only).
Violated requirement: stage_content's stated single-ruling contract; the gate's
"no local workaround substitutes for framework behavior".
Smallest corrective test: move the `(at - eye).Magnitude <= 1e-4` refusal into
`stage_content.normalizeCamera` and add a `stage.spec` case that `fails()` on a
coincident camera and asserts `#host.calls == 0`.

### M3 — In native StyleSheet mode a `UI.Stage` is opaque grey, not transparent, because no class-default rule reaches `ViewportFrame`
**Confidence: medium-high (source-verified; not confirmed on device).**
`src/client/screen_target.luau:2007-2012` deliberately skips the explicit
`BackgroundTransparency = 1` write when `nativeMode` is on, on the stated grounds
that "the class-default rules own BackgroundTransparency". The sheet's class-default
selector set is `Frame / TextLabel / TextButton / ImageLabel / TextBox /
ScrollingFrame / CanvasGroup` (`src/tokens/sheet_model.luau:473-487` and the rule
list at `:740-745`). `ViewportFrame` is **not** in it, and `ViewportFrame` is not a
subclass of `Frame` (both descend from `GuiObject`), so no rule selects it. The
Stage's own schema comment says "a Stage is transparent until something paints it"
(`src/blueprint_schema.luau`, Stage class block). This is byte-for-byte the
CanvasGroup defect already recorded at `src/tokens/sheet_model.luau:480-486`
("found live at stamp 62b6cdeb-1689276, where the fresh CanvasGroup sat at
BackgroundTransparency 0 because no class rule reached it"), which was fixed by
adding a class rule + a `claimPaint` — the Stage branch
(`src/client/screen_target.luau:2068-2083`) got neither.
Grep confirms zero occurrences of `ViewportFrame` anywhere under `src/tokens/`,
`src/themes/`, `src/client/native_style.luau`, or the native/theme specs.
Reproduction: mount any proof with a Stage under native StyleSheet mode with no
`surface` declared; expect the engine's default `BackgroundColor3` (163,162,165)
plate behind/around the rendered scene.
Violated requirement: StyleSheet property authority / "accepted-and-ignored" gate.
Smallest corrective test: add `ViewportFrame = "Stage"` to `CLASS_DEFAULT_NAME` +
a `{ name = "Stage default", selector = "ViewportFrame", props = { BackgroundTransparency = num(1) } }`
rule, and a spec asserting a native-mode Stage reads transparency 1 with no
`surface`. (Alternative: mirror the CanvasGroup path — `claimPaint` + explicit
write — but the rule is the consistent choice.)

### M4 — The device-matrix row artifacts are hand-reduced summaries, not instrument output, and their shapes differ per proof; `ok: true` is asserted on rows carrying almost no evidence
**Confidence: high.** `tools/studio/device_matrix.luau:580-599` returns
`boundaryNotes`, `chosen`, `why`, `observed`, `attempts`, `candidatesConsidered`,
`live`, `scalingMode`, `factsSettledFrames`, `excluded`, `derived`, `env`. Only the
`glade/` rows carry that shape. `cartwheel/row-compact-phone-portrait.json` keys are
`['ok','row','device','derived','geometry','evidenceClass','note']` with
`device = {"id": "samsung_galaxy_s22_ultra"}`, `derived = {"sizeClass":"compact"}`,
no `env`, no `preferredInput`, no `boundaryNotes`, and a self-describing
`"trimmed record"` note. `sipworks/*` rows are a third shape. So four of the five
cartwheel rows and all sipworks rows cannot be checked against the driver's own
`rowOkRule`, and the `ok` in `device-matrix.json` is unverifiable from disk.
Violated requirement: the gate's "complete feature ledgers are honest" / evidence
pairing clause.
Smallest corrective: archive the driver's raw JSON per row (or a schema-fixed
projection produced by the driver, not by hand) and add an artifact-shape check to
`tools/check_manifest_integrity.py` / `gate_manifest.luau` that fails when a row
file is missing `env.preferredInput`, `derived.interactionClasses`,
`geometry.solverDiagnostics`, or `boundaryNotes`.

### M5 — The touch-shaped axis is unproven for sipworks (and unrecorded for cartwheel), yet the rows read `ok`
**Confidence: high.** `sipworks/row-compact-phone-portrait.json` records
`env.preferredInput = "KeyboardAndMouse"` and `derived.primary = "pointer"` on the
`compact-phone-portrait` row, with the honesty note "the touch-shaped env is proven
by the cartwheel/glade phone rows in the same instrument". That is a
*cross-proof* substitution: sipworks' own touch-class branches (hit-target
inflation, touch affordances, `primary == "touch"` paths in its blueprint and in
LuauUI's adaptation) were never exercised at any row. Cartwheel's phone rows record
no `env` at all (M4), so the claim rests on glade alone. Meanwhile the driver has a
declared workaround it did not use: `runner.api.freezeEnv()` +
`api.setEnv({ preferredInput = "Touch" })`
(`examples/gallery/scenarios/runner.luau:1187-1213`) exists precisely because the
emulator's touch class is a boot-time fact
(`tools/studio/device_matrix.luau:545-564`, and the recorded memory truth "the
emulator cannot produce preferredInput=Touch").
The `rowOkRule` in `device-matrix.json` gates on viewport + orientation +
`solverDiagnostics == 0` + declared truncation — it does **not** gate on the input
class the row exists to prove, so a pointer-class run at a phone viewport scores
identically to a touch-class one.
Violated requirement: plan §Evidence "relevant keyboard, pointer, touch-shaped,
gamepad-shaped ... rows".
Smallest corrective test: either (a) drive `freezeEnv()` + `setEnv{preferredInput="Touch"}`
for the phone rows and record `derived.interactionClasses.primary == "touch"`, or
(b) add `preferredInput` to `rowOkRule` so a row that could not reach the class
records `ok: false` / `PENDING` rather than `ok: true` with a prose note.

## MINOR

### N1 — `Camera.CFrame` / `Camera.FieldOfView` are seam-owned in practice but absent from the declared `SEAM_OWNED` set, so the "no bespoke write" pin does not cover them
**Confidence: high.** `src/render/authority.luau:289-292` declares exactly four
seam-owned properties (Ambient, LightColor, LightDirection, CurrentCamera), and
`tests/stage.spec.luau:388-396` proves the adapter contains no dotted assignment to
any of them. But the seam also writes `handle.stageCamera.CFrame` and
`handle.stageCamera.FieldOfView` as plain dotted assignments
(`src/client/screen_target.luau:2360-2363`) on an adapter-owned Instance. Those two
are outside the gate, so a future bespoke `camera.CFrame = …` anywhere in the
adapter is invisible to the very pin built to catch this class.
Smallest corrective test: add `CFrame` and `FieldOfView` to `SEAM_OWNED` (scoped by
a note that they apply to the stage camera), route them through `writeStageProp`,
and let the existing `stage.spec` pin cover them.

### N2 — `CFrame.lookAt` collinear-with-up is unguarded and unprobed; a top-down stage camera is the common case that hits it
**Confidence: medium.** The seam guards only the *coincident-point* case
(`src/client/screen_target.luau:2353`). A perfectly valid, very common preview
camera — `position = {0, 10, 0}`, `lookAt = {0, 0, 0}` — has magnitude 10 and passes
the guard, then calls `CFrame.lookAt(eye, at)` with the look direction parallel to
the default `Vector3.yAxis` up. The official `CFrame` page documents only the
signature (`up` defaults to `Vector3.yAxis`) and says nothing about the degenerate
case; community reports split between "up switches to the X axis" and "NaN from a
zero cross product". `docs/research/2026-08-08-viewportframe-engine-facts.md:44-46`
lists open engine limits but does not include this one, and
`examples/gallery/scenarios/runner.luau:270-272` calls `CFrame.lookAt` again for
part placement with the same exposure.
Smallest corrective: probe it once in Studio and record the answer in the research
doc; if it is NaN, refuse or fall back to a perpendicular up in
`stage_content.normalizeCamera` so both adapters agree.

### N3 — Stage park refusal keys on different facts in the two adapters, and the comment overstates the agreement
**Confidence: high.** `src/client/screen_target.luau:4233` refuses on
`handle.stageWorld ~= nil`; `tests/lib/fake_target.luau:420` refuses on
`handle.stageApi ~= nil or handle.class == "Stage"`. On an engine where the
capability probe fails (`hasStage == false`, `src/client/screen_target.luau:479-488,
1993-1997`) a degraded Stage has no `stageWorld` and **is** parkable live, while the
fake refuses it. The comment at `:4210-4212` says "Refused on both adapters", which
is only true on a full-capability engine. Harmless today (a degraded Stage is a bare
Frame and `stageHost` answers nil), but it is a stated invariant that is not one.
Smallest corrective test: refuse on `handle.class == "Stage"` in the live adapter
too, and assert the two refusal predicates match in `stage.spec`.

### N4 — `api.setEnv` silently drops facts it could not apply, and never enforces `freezeEnv()`
**Confidence: high.** `examples/gallery/scenarios/runner.luau:1200-1213` pcalls each
`env:set` and returns only the keys that succeeded; a caller that does not diff
`applied` against what it requested sees a success. It also does not check
`session.envFrozen`, so a row that forgets `freezeEnv()` has its facts silently
overwritten by the live engine binding on the next push
(`src/client/roblox_env.luau` connections) — the doc comment says "Requires
freezeEnv() first" but nothing enforces it. This is the instrument that would have
closed M5.
Smallest corrective test: return `{ applied, refused }` (with the pcall error) and
either auto-freeze or refuse with a named error when `envFrozen == false`.

### N5 — `keyboardFirst`'s `RbxCameraKeypress` unbind is one-shot, never restored, and process-global
**Confidence: medium.** `examples/gallery/scenarios/runner.luau:1105-1109` calls
`ContextActionService:UnbindAction("RbxCameraKeypress")` once inside `build()`. The
default `PlayerModule` `CameraInput` re-binds that action whenever camera input is
re-enabled (camera-type change, character re-add), so the release can be silently
undone mid-session and the arrow-key traversal the row is proving would die again
with nothing recording it. Conversely it is never re-bound at `teardown()`, so the
comment's claim that it is "Opt-in per scenario, so prior gates' scenarios keep the
environment they passed in" is false for any session that runs a `keyboardFirst`
scenario before a non-`keyboardFirst` one in the same client.
Smallest corrective test: re-assert the unbind after each `step()`/`refresh()` (or
connect `CharacterAdded`/`Camera.CameraType` and re-unbind), record in the row
whether the action was bound at the moment the keys were sent, and re-bind on
teardown.

### N6 — RA-X1 does not own the safe-area/notch row that Studio emulation demonstrably cannot prove
**Confidence: medium-high.** `review-packet.md` RA-X1 scopes touch reachability,
44px targets, the OS keyboard, orbit, and rejection copy — but never the physical
safe area. The device matrix runs `StudioDeviceSimulatorService` presets, which
produce a plain rectangular viewport: nothing in the archived rows carries
`deviceSafeInsets` or `topbarSafeInsets` values other than the desktop zeroes, and
the repo's own recorded truth is "TopbarInset != physical space on notches". The
four-edge inset derivation (`src/client/roblox_env.luau:31-71`,
`GuiService:GetInsetArea` with the `CoreUISafeInsets` / `DeviceSafeInsets` /
`TopbarSafeInsets` triple, plus the legacy `GetGuiInset` fallback where
`right` stays 0) is therefore entirely unproven on hardware for this stage.
Smallest corrective: add a numbered RA-X1 step — "on a notched phone in both
orientations, read `report().env.deviceSafeInsets` / `topbarSafeInsets` and confirm
no content or focus ring falls under the cutout, the home indicator, or the
topbar" — so the row is explicitly pending rather than silently absent.

### N7 — RA-X2 does not scope the Roblox-reserved gamepad buttons it will collide with
**Confidence: medium.** RA-X2 covers ButtonA activate / ButtonB dismiss, D-pad
traversal, and the virtual-cursor self-summon. It does not scope `ButtonStart`
(Roblox menu), `ButtonSelect`, or the CoreGui back-button arbitration that competes
with a modal's ButtonB — which is precisely the "Button A contention" family the
row is named for. Also a small internal inconsistency: RA-X2 claims
`PreferredInput == Gamepad` is what the physical row owns, but
`studio/glade/row-console-ten-foot.json` already records
`env.preferredInput = "Gamepad"` from the emulator.
Smallest corrective: name the reserved buttons in the RA-X2 checklist and re-word
the row to own *delivery and arbitration*, not the `PreferredInput` fact.

### N8 — sipworks' keyboard row records a pairing count with no raw trace, and the summary in `device-matrix.json` contradicts it
**Confidence: high.** `glade/row-keyboard-desktop.json` carries a real
`after.rawInput` array of 8 `UserInputService` events (began+ended for
Tab/Tab/Down/Return) with `gameProcessed` per event.
`sipworks/row-keyboard-desktop.json` records the same four keys but
`pairing.rawEvents = 4` and no `rawInput` array, while `device-matrix.json` states
"4 raw events paired to 1 semantic activation" for sipworks and "8 raw events" for
glade/cartwheel on the identical key list. So sipworks' number counts *keys*, not
raw events, and the "raw events AND semantic actions" pairing rule is only actually
evidenced for glade (cartwheel records the count 8 but no trace).
Smallest corrective: archive `after.rawInput` for every keyboard row, and assert
`rawEvents == 2 * #keys` in the driver.

## NOTE

### T1 — Engine facts in the research doc check out against official docs
**Confidence: high.** The `ViewportFrame` class page lists exactly
`Ambient`, `CurrentCamera`, `ImageColor3`, `ImageTransparency`, `LightColor`,
`LightDirection` — confirming research §"Facts that shape the API" item 1 (lighting
lives on the frame, so a content owner writing it would write a LuauUI-owned
Instance) and the `ImageColor3`/`ImageTransparency` tint routing at
`src/client/screen_target.luau:740-744, 770-778` (a `ViewportFrame` is not an
`ImageLabel`, so the explicit `IsA("ViewportFrame")` disjunct is required and is
present). The official page does not document parenting requirements or cost, so
those parts of the research doc rest on the local probe only — which the doc says.
Source: https://create.roblox.com/docs/reference/engine/classes/ViewportFrame

### T2 — The `Destroy()` claims the corpse fix rests on are correct
**Confidence: high.** `Instance:Destroy()` "Sets the Instance.Parent property to
nil, locks the Instance.Parent property, disconnects all connections, and calls
Destroy() on all children" — so a descendant of a destroyed host does read
`Parent == nil`, and a subsequent non-nil `Parent` write throws
"The Parent property of X is locked". `Name` and other property writes on a
destroyed instance do succeed, which is why `park`'s `Parent = nil` and `adopt`'s
`Name` write are legal and why the reparent is the only detector. The reasoning at
`src/client/screen_target.luau:4217-4231` and `:4352-4367` is sound.
Sources: https://create.roblox.com/docs/reference/engine/classes/Instance ,
https://devforum.roblox.com/t/why-does-destroy-lock-the-object-after-setting-its-parent-to-nil/1649683 ,
https://devforum.roblox.com/t/parent-property-is-locked/437847

### T3 — No live-instance false positive exists for the `Parent == nil` corpse gate
**Confidence: high.** Exhaustive grep of every `Parent` write touching a node's own
instance: creation at `src/client/screen_target.luau:2199-2205` (clip host or root
gui), `park` at `:4310` (the only nil write), `adopt` at `:4351-4362`. Presentation
transforms write `Position` only; the tree is flat
(`docs/lessons/screen-target-tree-is-flat.md`, referenced at `:1720`); clip-host
moves re-base rects, not parents; `setRootVisible` writes `ScreenGui.Enabled`
(`:2408-2409`). The focus-ring float, hit expander and chrome children are siblings
or children written elsewhere (`screen_chrome.luau:1180`, `screen_target.luau:3563`)
and are not `handle.instance`. So a live handle's instance always has a non-nil
Parent at park time and the gate cannot false-positive. The claim in the comment is
accurate.

### T4 — Stage teardown and the pool interaction are correct
**Confidence: high.** `markStageDisposed` (`:134-142`) is called on both teardown
paths (`remove` `:4519`, `destroyRoot` `:4543`) before `Destroy()`, and the cached
`stageApi`'s `live()` closure reads the nulled fields, so a consumer-held handle
refuses by name rather than writing into a corpse (`:2332-2342`). A refused `adopt`
is `discardParked`-ed rather than pushed back (`src/render/renderer.luau:1698-1701`),
so a corpse cannot be retried forever. `renderer.luau:1672-1674` pins a Stage's
decoration hint to `NO_SLOT` so no package recipe can paint over the scene.
`drainRecyclePool` (`renderer.luau:1626-1637`) discards the pool. No leak found.

### T5 — Headless twin fidelity, residual divergences beyond M2
**Confidence: medium.** `tests/lib/fake_target.luau:816-851` mirrors the three verbs
through the shared `stage_content` rulings, which is the right shape. Residual
divergences the `calls` array cannot show: (a) the live `api` is
`table.freeze`d while the fake's is a mutable table carrying an extra public
`calls` key; (b) the live gate is
`instance/stageWorld/stageCamera ~= nil and stageDisposed ~= true`
(`:2325, 2332-2337`) while the fake's is `alive`/`stageDisposed` only — the fake has
no analogue of a degraded (non-ViewportFrame) Stage, so the
`stageHost -> nil` fallback is proven only by the source-shape assertions at
`tests/stage.spec.luau:181-230`; (c) `fake_target.adopt` (`:445-463`) does not
mirror the live epoch gate (`screen_target.luau:4344-4346`), so that refusal path is
unmodelled headless (pre-existing from L-28).

### T6 — Responsibility-ledger Roblox-service mappings are accurate
**Confidence: medium-high (desk review, no API probes).** Spot-checked:
`MarketplaceService` developer products for consumables and
`PromptSubscriptionPurchase` for tiers with server-processed receipts (row P1) is
current and correctly notes the prompt chrome is a host sheet the in-experience UI
cannot own; `LocalizationService`/`Translator:FormatByKey` (row P3) is the right
pair and correctly keeps the ~1.4x expansion axis a fixture rather than claiming
platform behavior; `Player:GetJoinData` `launchData` as the App-Clip-entry analogue
(row P3) is correct; `AvatarEditorService` + `HumanoidDescription` for the preview
rig (row P5) is correct, and the ledger correctly does not claim
`AvatarEditorService:PromptSaveAvatar` for a purchase. `PolicyService` is **not**
mapped anywhere in the ledger even though several rows involve commerce and social
surfaces (`Players:GetFriendsAsync`, presence, purchase prompts) that a shipping
experience gates on `PolicyService:GetPolicyInfoForPlayerAsync`
(`ArePaidRandomItemsRestricted`, `IsSubjectToChinaPolicies`,
`AllowedExternalLinkReferences`). Not a defect of the proofs (they make no real
calls) but the ledger's stated purpose is to name "the production Roblox service a
real game would own", and that one is missing.
Smallest corrective: add a `PolicyService` row naming the commerce/social gating a
production game owes.

### T7 — Emulated interaction classes beyond `primary` are not trustworthy and the artifacts do not say so
**Confidence: medium.** `glade/row-console-ten-foot.json` records
`interactionClasses = { touch: true, keyboard: true, pointer: true, gamepad: true,
primary: "gamepad" }` on a PS4 preset, and the phone row records
`keyboard: true, pointer: true` on a Galaxy S22 Ultra. Those come from
`UserInputService.KeyboardEnabled/MouseEnabled/TouchEnabled`
(`src/client/roblox_env.luau:92-97`), which under Studio emulation report the host
workstation's real capabilities, not the emulated device's. The rows' `cannotProve`
lists do not mention it. Any framework behavior that branches on a *capability*
rather than on `primary` is therefore unproven by this matrix.

### T8 — `workspace.CurrentCamera` is captured once at bind
**Confidence: low-medium; pre-existing, out of stage scope.**
`src/client/roblox_env.luau:17` binds `camera = workspace.CurrentCamera` once and
connects `ViewportSize` on that instance (`:161`). If the engine or a script
replaces `workspace.CurrentCamera` mid-session, viewport facts freeze silently.
Not introduced by this stage; recorded because the stage adds a second Camera
concept (the adapter-owned stage camera) and a future reader could conflate them.

### T9 — The ten-foot overscan numbers are authored, not read from the engine
**Confidence: high.** `effectiveOverscanInsets = {60, 60, 90, 90}` on the ten-foot
rows comes from `src/preview/device_profiles.luau:116`, composed by
`src/env/environment.luau:182-190` — it is a developer-authored TV-safe margin
(explicitly "DISTINCT" from the platform safe insets, `environment.luau:83-87`), not
a `GuiService` reading. That is a defensible design, but the artifacts present it
under `derived`, alongside genuinely engine-read facts, with nothing marking the
difference. RA-X2/RA-X1 should own "does the authored 5% margin actually clear a
real TV's overscan".

## Checks not run, and why

- **No Studio/live-place verification.** No Roblox Studio MCP tool is exposed to
  this reviewer, so every engine-behavior claim here is either an official-doc
  reading or a source-level deduction. The four items that need a live probe are
  M3 (native-mode Stage plate), N2 (`CFrame.lookAt` collinear), N5
  (`RbxCameraKeypress` re-bind), and T7 (emulated capability facts).
- **`foyer` and `wardrobe` device-matrix rows** are recorded `RERUN_OWED` in
  `device-matrix.json` with a stated lock-screen blocker; not independently
  re-checkable here. Two of five proofs therefore have **no** archived matrix rows
  at final source (wardrobe has one portrait row at pre-fix source; foyer has an
  empty directory).
- **Replication contract / client-server boundary / Input Action System sinking
  and priority / `TextService:GetTextBoundsAsync` premeasurement** — NOT-REVIEWED.
  Out of the delegated surface for this stage and untouched by the stage diff
  (`git diff --stat` shows no change to `src/client/roblox_input.luau`,
  `src/client/text_premeasure.luau`, or any server/shared module).
- **Rascal Rally consumer lockstep** — NOT-REVIEWED (not in the delegated scope;
  flagged only because the root constitution requires it for any LuauUI change and
  `src/blueprint.luau`, `src/blueprint_schema.luau`, `src/render/renderer.luau`,
  `src/layout/solver.luau` and `src/themes/package.luau` all changed in this stage).
