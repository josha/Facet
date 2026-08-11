# Row Actions — RascalRally Consumer Compatibility Evidence (Task 13)

**Date:** 2026-08-11
**LuauUI branch:** `luauui/row-actions` @ `e4c4d7c` (VERSION `0.9.0`)
**RascalRally:** `games/RascalRally/code` (consumes `GameStudio/ui/LuauUI/src` directly via both Rojo projects)

**Scope.** No RR surface constructs `newRowActions` or passes `spec.rowActions` to a
Table yet — the row-actions feature ships with zero live RR callers. This document is
therefore **compatibility evidence, not a migration**: it proves the SHARED files the
row-actions branch touched (`table.luau`, `presenter.luau`, `actions.luau`,
`roblox_input.luau`, `screen_target.luau`) did not change behavior for any RR call
site that was already exercising those files before this branch.

Diff base for all "what changed" claims below: `f1de50f49dafb878694cb8ac38461ce289a41557`
(the row-actions branch point) → `HEAD` (`e4c4d7c`).

---

## 1. RR usage of every changed surface

### 1a. `newTable` / Table spec keys (`src/controls/table.luau`)

**Change:** `TABLE_KEYS` (table.luau:217-238) gained exactly one new optional key,
`"rowActions"` — no existing key removed, renamed, or reshaped. `specGuard.assertKnownKeys`
rejects unknown keys, so any RR call passing a key outside `TABLE_KEYS` would already
have been failing before this branch; the check is otherwise unaffected.

**RR call sites (grepped `newTable|Table\.new|UI\.Table|\.Table(` across all of
`games/RascalRally/code/src` — exactly one hit in the whole codebase):**

- `games/RascalRally/code/src/client/LuauUIRacerListScreen.luau:159-180` — the only
  `LuauUI.newTable(...)` call in RR. Spec keys passed, verbatim: `id`, `columns`
  (each column: `id`, `width`, `cell`), `rows`, `key`, `rowHeight`, `rowGap`, `height`,
  `header`, `selection`. **No `rowActions` key present; no key outside the pre-branch
  `TABLE_KEYS` set is used.** `selection = "single"`, no `reorderable`/`onReorder` —
  the row-actions/reorder axis-lock composition path (table.luau's
  `composeWithReorder`) is never entered for this table because `spec.rowActions` and
  `spec.reorderable` are both absent, so the wrapper is skip-constructed entirely
  (table.luau: `rowActionsCoordinator` is only built `if spec.rowActions ~= nil`).
  Compatible: an absent key can't collide with a validation change that only ever
  ADDS an allowed key.

- `games/RascalRally/code/src/client/LuauUISponsor/RacerList.luau` — NOT a Table
  consumer despite the name; it calls `newVirtualList` (`reorderable = false`,
  `selectionPaint = "none"`, `focusPolicy = "index"`). `virtual_list.luau` is a
  separate control module row-actions did not touch (its only diff in this branch,
  `selectionPaint`, is commit `ad4f399`, a pre-existing Sponsor-framework change that
  predates the row-actions task list and RR already consumes it). Not in scope for
  this evidence file.

- `LuauUISponsor/TableScreen.luau` / `TableMetrics.luau` — named "Table" but refer to
  the sponsor's in-fiction poker-table camera layer, not LuauUI's `Table` control;
  confirmed zero `newTable`/`UI.Table` references in either file.

**Verdict: compatible.** RR's single Table caller passes only pre-existing keys; the
one new key is additive and opt-in.

### 1b. `outsideDismiss.consume` / `bindMotion` / `bindPresent` (`src/present/presenter.luau`)

**Changes (presenter.luau, full diff in `/tmp/presenter.diff` during this task):**

1. **`od.consume` opt-out** (~line 2140): a contribution's `outsideDismiss` bundle can
   now set `consume = false` so a dismissing outside-tap falls through to normal
   dispatch instead of being swallowed. Default path is unchanged: `if od.consume ~= false then return end` — a bundle that never sets `consume` (every bundle before
   this task, and everything RR authors) swallows the tap exactly as before, byte-for-byte.
2. **`bindMotion`** and **`bindPresent`** (~line 981-1004): two new OPTIONAL contribution-bundle hooks, each gated `if c.bundle.X ~= nil then ... end`. A bundle
   that doesn't declare them (every bundle RR builds) triggers neither branch — pure
   no-op for any non-row-actions consumer.

**RR usage (grepped `outsideDismiss`, `PopupButton`, `presentModal`, `.present(`,
`dismiss(`, `bindMotion`, `bindPresent` across `games/RascalRally/code/src`):**

- `outsideDismiss` — **zero matches in RR.** RR never authors a composite/bundle that
  uses the transient-popup outside-tap contribution mechanism the `consume` field
  lives on.
- `PopupButton` — **zero matches in RR.**
- `bindMotion` / `bindPresent` — **zero matches in RR.** These are contribution-bundle
  hooks only a composite author would wire; RR has no custom composite. `row_actions.luau`
  is the only current consumer.
- `presentModal` (2 sites, both unaffected — see below):
  - `LuauUISettingsGui.luau:246` — `presentModal(blueprint, { rootPolicy = "edgeToEdge", onActivate = ... })`. Relies on the app-level `outsideTapCancel`/`cancelPolicy`
    mechanism (defaults), plus its own explicit scrim-path handling
    (`LuauUISettingsGui.luau:226-229`).
  - `LuauUISponsor/init.luau:2650` — `presentModal(blueprint, ROLE_MODAL_OPTS)` where
    `ROLE_MODAL_OPTS = { cancelPolicy = "none", outsideTapCancel = false, scrim = "none", rootPolicy = "edgeToEdge", ... }` — the role-pick modal is explicitly mandatory
    (neither Cancel nor an outside tap may dismiss it).

  **These two `presentModal` call sites use `outsideTapCancel`/`cancelPolicy`
  (presenter.luau:112,121-127,186,199,726,1917-1922,3409) — a completely separate
  code path from the `outsideDismiss` bundle-level `consume` field the row-actions
  diff touched.** Confirmed by grepping the diff itself
  (`grep -n "outsideTapCancel\|cancelPolicy" /tmp/presenter.diff` → zero hits): the
  row-actions branch never modified this mechanism. RR's two modals are provably
  outside the changed code path, not merely "probably fine by inspection."

**Verdict: compatible.** RR touches neither the `outsideDismiss` bundle mechanism nor
`bindMotion`/`bindPresent`; its two `presentModal` callers ride an entirely different,
untouched option surface.

### 1c. Action-system modifier support + binding-scoped key-up stamps (`src/input/actions.luau`, `src/client/roblox_input.luau`)

**Changes:**

- `actions.luau`: `action.bind(spec)` gained an optional `modifiers: { shift: boolean? }?`
  field. `modifierMatch(binding, isDown, held)` (actions.luau:~310) returns `true`
  unconditionally whenever `binding.modifiers == nil` — this is the **entire**
  candidacy path every binding used before this task, and it is untouched: `binding.keyCode == keyCode and modifierMatch(...)` reduces to the pre-existing
  `binding.keyCode == keyCode` check whenever `modifiers` is absent. The new
  binding-scoped `pressed` stamp is only ever written `if candidate.binding.modifiers ~= nil` (actions.luau:~403) — a no-op field write for any binding that never
  declares `modifiers`.
- `roblox_input.luau`: a binding with `spec.modifiers.shift == true` now creates TWO
  `InputBinding` instances (`PrimaryModifier = LeftShift`/`RightShift`) instead of the
  normal single-instance path. The normal path (`spec.modifiers == nil`) is completely
  unchanged — the new branch is gated `if spec2.modifiers ~= nil and spec2.modifiers.shift == true and spec2.keyCode ~= nil then ... return end`, so it can only be
  entered by a binding that opts in.

**RR usage (grepped `keyCode = "Return"`, `keyCode = "Delete"`, `keyCode = "Backspace"`/`BackSpace`, `keyCode = "ButtonX"`, `Enum.KeyCode.Return/Delete/Backspace`, and every `action.bind(`/`.bind({` call site in `games/RascalRally/code/src`):**

- `Return` / `Delete` / `Backspace` (either the LuauUI IAS string form or raw
  `Enum.KeyCode`) — **zero matches anywhere in RR.** RR binds none of the key codes
  the row-actions Shift+Return menu binding or the reviewed modifier fix touch.
- `ButtonX` — two bind sites, both confirmed to bind **without** `modifiers`:
  1. `LuauUISponsor/init.luau:865-870` — LuauUI action-system `SkipCelebration`
     action: `for _, key in { "Space", "ButtonX" } do skipAction.bind({ keyCode = key, displayName = key }) end`. No `modifiers` field → matches via the untouched
     `binding.modifiers == nil` branch, unconditionally, on either edge — identical
     to pre-branch behavior.
  2. `SponsorResults.luau:2615-2622` — a **legacy, non-LuauUI raw** `InputContext`/`InputAction`/`InputBinding` construction (predates the LuauUI action-system port),
     unaffected by any LuauUI change by construction (it never calls `action.bind`).
  - Two other `action.bind(` sites for completeness, neither touching Return/Delete/Backspace/ButtonX and neither declaring `modifiers`: `init.luau:720` (`togglePose`,
    `keyCode = "ButtonY"`) and `init.luau:739` (`WatchPrev`/`WatchNext`,
    `ButtonL1`/`ButtonR1`).

**Verdict: compatible.** RR declares no binding with a `modifiers` field, so every RR
binding takes the exact pre-branch code path in both `actions.luau` (headless/test
model) and `roblox_input.luau` (the live client adapter). The only place `Shift+Return`
and the binding-scoped `pressed` stamp exist at all is `row_actions.luau`'s own
`RowActionsMenu` action, which RR does not construct.

### 1d. Cross-root capture scoping / destroyed-instance liveness (`src/client/screen_target.luau`)

**Change (commit `e275b69`, redteam item 14):** `onPointerDown`'s capture-acquisition
gate now runs a `pcall`-guarded `IsDescendantOf(game)` liveness check on an existing
`activeCapture` before refusing a new press; a capture whose Instance died through a
path other than `destroyRoot` (e.g. a pool eviction that destroys an Instance
directly) is now cleaned up right there instead of permanently wedging the adapter's
one capture slot. This is a pure robustness fix to the SAME single-capture-slot
mechanism every pointer interaction already went through — it does not add a public
option, does not change any call signature, and only changes behavior in the
previously-broken case (a capture stuck on a destroyed instance), which never had a
defined "correct" behavior to regress from.

**RR usage (grepped `activeCapture`, `IsDescendantOf`, `screen_target` across
`games/RascalRally/code/src`):**

- `activeCapture` — **zero matches in RR** (this is an internal adapter field, never
  exposed to or read by a consumer).
- `IsDescendantOf` — many hits, but every one is game-world logic (kart/chassis
  Instance ancestry in `KartSim.luau`, `MinKartSim.luau`, `RemoteKart.luau`,
  `KartRoster.luau`, `init.client.luau`) against `workspace`, not a LuauUI GuiObject.
  The one UI-adjacent hit, `SponsorGui.luau:299`, is in the legacy pre-LuauUI
  `SponsorGui.luau` and never touches `screen_target`'s capture machinery.
- `screen_target` — appears only as the adapter require/construction call in every RR
  file that builds a LuauUI presenter (`LuauUIRacerListGui.luau:15,45`,
  `GaragePilotGui.luau:24,42`, `LuauUISettingsGui.luau:34,85`,
  `LuauUISponsor/init.luau:226,435`) — ordinary one-time adapter setup, not a
  pointer-capture or cross-frame Instance-holding pattern of its own.

**Verdict: compatible, and strictly safer.** RR never reaches into the capture
internals; the fix only helps RR's existing pointer interactions (a table/list row
whose Instance dies out-of-band, e.g. `LuauUIRacerListScreen`'s poll-driven row
churn, can no longer wedge future presses adapter-wide).

### Completeness check

`grep -rl "LuauUI" games/RascalRally/code/src` → 44 files require LuauUI at all
(full list captured during research: every `src/client/LuauUISponsor/*.luau`,
`LuauUIRacerListGui.luau`, `LuauUIRacerListScreen.luau`, `LuauUISettingsGui.luau`,
`GaragePilotGui.luau`, `GaragePilotScreen.luau`, `ItemFx.luau`, `init.client.luau`,
three `src/shared/*.luau` model files, and `src/server/SponsorScenarioRig.luau`).
Every file that touches Table, popup/outside-dismiss, key bindings, or capture is
enumerated above; none outside this list construct a Table, bind a modifier-affected
key, or touch capture state.

---

## 2. RR full suite

```
$ cd games/RascalRally/code && ./run-tests.sh
```

Exit code: **0**. Runtime: ~29s (`28.85s user 0.37s system 99% cpu 29.283 total`).

Tail of output:

```
[Step 8.5 results: the wrapped caps hold at every preference (§S16.12)]
  ✓ the ledger's section heads read whole — LTN-3.1 took a section head off the list
  ✓ the SPAN recap wraps whole wherever the composition offers it (§S16.12)
  ✓ the recap's REDUCED form AUTO-SCROLLS its full value (E·3 closed, LTN-8)
  ✓ the bogey callout, the promo bait and the tease all wrap within their caps
  ✓ the celebration line reads whole: its type is fitted to the PAINTED form
  ✓ `fitType` is byte-identical at Medium, never grows, and ends on its legibility floor
[Step 8.5 results: the arrangement steps down as the preference grows]
  ✓ the 667x375 fixture re-arranges rather than clipping a lane, for both roles
  ✓ the compact-landscape row keeps its three lanes until Largest, then gives one up
  ✓ NOTHING PAINTS OVER ANYTHING at any preference — no overflow diagnostic, any row
  ✓ RECORDED FINDING: 667x375 has no legal arrangement above Large, and says so

3094 passed
```

**3094 passed, 0 failed** — matches the expected count (director charter: "suite was
~3094"). No regressions from the row-actions branch's shared-file changes.

---

## 3. Studio canary

**Instance:** "Rascal Rally" (`502314f9-ba86-43f8-8eab-ff688249a0ad`), pre-connected
but not active at task start.

### 3a. Source-currency marker (before trusting anything else)

Set active studio to Rascal Rally, confirmed `get_studio_state` → Edit mode, then
verified the synced `ReplicatedStorage.LuauUI` is the CURRENT branch source, not a
stale sync:

```lua
-- Edit datamodel
require(ReplicatedStorage.LuauUI).VERSION        --> "0.9.0"   (matches src/init.luau:90)
require(ReplicatedStorage.LuauUI).newRowActions   --> present (function)
-- table.luau ModuleScript source contains the literal `"rowActions"` key
```

Result: `{"hasNewRowActions":true,"tableModuleFound":true,"version":"0.9.0","tableSourceHasRowActionsKey":true}`.
This proves the running place's LuauUI is synced to the row-actions branch, not an
older snapshot (the version number alone would not have distinguished branch content;
the `newRowActions` existence + literal source-text check does).

### 3b. Reaching the Table surface

RR's only `newTable` consumer is `LuauUIRacerListScreen` via `LuauUIRacerListGui`,
gated behind workspace attribute `UseLuauUIRacerList` (default OFF; the production
default racer list, `LuauUISponsor/RacerList.luau`, is a `VirtualList`, not a
`Table`). Set `workspace:SetAttribute("UseLuauUIRacerList", true)` in Edit mode, then
started Play.

**Trap hit and recorded:** the attribute was confirmed `true` on the Client datamodel
once play was running, but `init.client.luau:815`'s one-time gate check
(`if workspace:GetAttribute("UseLuauUIRacerList") == true then require(...).new(player) end`) did not construct `LuauUIRacerListGui` — no `[LuauUIRacerList] failed to
construct` warning appeared (so it wasn't an error), and no `LuauUI_RL` ScreenGui was
present after play started. This reads as the documented "requires the attribute to
already be in place at LocalScript start" contract racing against attribute
replication/snapshot timing in this session, an RR-side startup-order quirk unrelated
to row-actions and out of scope to fix here (no RR code changes permitted). **Worked
around programmatically** (a legitimate "drive programmatic seams" per this task's
instructions, not a code change): required `LuauUIRacerListGui` directly from the
Client VM and called `.new(player)` by hand, bypassing only the attribute-gated
construction call site, not any LuauUI behavior.

### 3c. What was exercised

With the module constructed directly (`_G.__rrCanaryGui`), after one poll cycle
(`task.wait(1.5)`, poll interval 0.25s):

- **Table mounted and rendered 8 rows** (`AIKart_1`..`AIKart_7` + the human racer
  `Kart_1364639953`) under `PlayerGui.LuauUI_RL`, flat-named per LuauUI convention
  (e.g. `/RL/Dock/Panel/RacerList/Main/Body/Rows/[AIKart_1@0]/Row/Hit`). Each row
  carries `Rank`/`Icon`/`Name`/`State` cells plus a focusable `Hit` `TextButton`,
  exactly the `cellForRow` shape `LuauUIRacerListScreen.luau:141-157` authors.
- **Zero row-actions wrapper instances** anywhere under the mounted tree
  (`grep` for `Tray`/`RowActions` in `screenGui:GetDescendants()` → 0 of 101
  descendants) — confirms live, in-engine, that a Table with no `spec.rowActions`
  builds no tray/wrapper GuiObjects at all, matching the plan's "closed row = zero
  tray GuiObjects" / "inert passthrough adds no extra container" guarantees
  (`docs/plans/row-actions-implementation.md` Global Constraints §Performance) for a
  REAL consumer, not just the framework's own fixtures.
- **Activation/selection path exercised:** called
  `gui._screen.api.handleActivate("/RL/Dock/Panel/RacerList/Main/Body/Rows/[AIKart_1@0]/Row/Hit", nil)`
  directly (the same call `presenter.present`'s `onActivate` wiring makes on a real
  click/tap/Return/gamepad Activate) — returned cleanly (`pcall` ok, no error), and
  the row's native `selected` paint changed color
  (`Hit` `BackgroundColor3`: unselected `(0.161, 0.176, 0.227)` → selected
  `(0.176, 0.227, 0.361)` for `AIKart_1` vs. an unselected sibling row), proving
  `selection = "single"` end-to-end through the live adapter on current branch source.
- **Clean teardown:** `gui:destroy()` returned no error; the `LuauUI_RL` ScreenGui and
  its heartbeat connection were released.
- **Console output** (`get_console_output`) across the whole session showed no new
  errors or warnings attributable to `LuauUIRacerListGui`/`LuauUIRacerListScreen`/
  `table.luau`/`presenter.luau` at any point — construction, mount, activation, or
  teardown. (Two pre-existing, unrelated noise lines were present throughout:
  a CoreGui `Settings.Pages.Players` `layoutMuteAll` index-nil warning and
  `PlayerModule` "Infinite yield on InputContexts" warnings from Roblox's own
  first-party control scripts — both present before `LuauUIRacerListGui` was ever
  touched and outside RR/LuauUI code.)
- `gui._presenter.diagnostics` was not found at this call level (the app-level
  presenter object wired by `LuauUIRacerListGui` does not itself expose a
  `diagnostics()` method the way LuauUI's own test controller does) — noted rather
  than silently skipped; the structural/visual checks above stand in its place for
  this canary.

Cleaned up: destroyed the canary instance, stopped Play, cleared the
`UseLuauUIRacerList` workspace attribute back to nil in Edit mode (an in-memory Studio
session change only — never saved to the place file, so this leaves no residue either
way), and set the active Studio instance back to **Place1**
(`b77ad214-e6b1-4f7e-9299-f6ca21b6d1de`) per the task's closing instruction.

**Canary verdict: OBTAINED.** The one real RR `Table` consumer mounts, renders,
selects, and tears down cleanly on current row-actions-branch LuauUI source, with a
zero-instance footprint for the (unused) row-actions wrapper.

---

## 4. Summary

| Changed shared surface | RR touches it? | Verdict |
|---|---|---|
| `table.luau` `TABLE_KEYS` / `rowActions` integration | Yes (1 call site, no `rowActions` key) | Compatible — additive key, unused |
| `presenter.luau` `outsideDismiss.consume` | No | Compatible — mechanism unused by RR |
| `presenter.luau` `bindMotion`/`bindPresent` | No | Compatible — composite-only hooks, RR has no composite |
| `presenter.luau` `presentModal` `outsideTapCancel`/`cancelPolicy` | Yes (2 sites) | Compatible — provably untouched by this diff |
| `actions.luau` modifier support + `pressed` stamp | No (`modifiers` never declared by RR) | Compatible — old code path preserved verbatim |
| `roblox_input.luau` modifier-gated `InputBinding` pair | No | Compatible — new branch never entered |
| `screen_target.luau` capture liveness fix | No (internal only) | Compatible, and strictly safer |
| RR full test suite | — | **3094 passed, exit 0** |
| Studio canary (`LuauUIRacerListScreen` Table) | — | **OBTAINED** — mount/select/teardown clean, zero console errors, zero row-actions wrapper instances |

**No RR code or config changes were made.** All findings above are read-only
grep/inspection plus a live, non-persistent Studio Play-mode exercise (attribute set
in Edit mode was not saved; canary instance was destroyed; Play was stopped).
