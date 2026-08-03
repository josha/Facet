# RascalRally consumer-impact ledger — `desktop-keyboard-navigation`

Rascal Rally mounts `GameStudio/ui/LuauUI/src` directly through both of its Rojo
projects, so this stage is incomplete until every changed contract is audited
against the game's real callers. Audited 2026-08-02 against
`games/RascalRally/code` at its current source.

**Result: one production edit was required, and it was required to PRESERVE
behavior.** Everything else is compatible for the shipped call sites, and the
lockstep rule's no-manufactured-churn clause applies to the rest.

---

## The eight changed contracts

| # | Change | Game exposure | Action |
|---|---|---|---|
| 1 | New `present()`/`presentModal()` opt `traversalWrap` | **None.** Nine present-family call sites, none passes it. `PRESENT_OPTS_KEYS` stays closed and `tests/luauui_closed_key_contract.spec.luau` re-proves every shipped opts table is still accepted. | none |
| 2 | Every surface gains a `Traverse` action; `Tab` bound while keyboard is live **and** the responder is engaged | Zero game bindings on `Tab` (`Enum.KeyCode.Tab` has no hits in `src/` or `tests/`). Passive surfaces bind nothing: the Sponsor chip band (`HudScreen.CHIP_PRESENT_OPTS`) never engages, and the main HUD binds only while maximized. | none |
| 3 | `Space` bound as a second Activate key on any engaged surface with `gameplayGuard ~= false` | **COLLISION — see below.** | `gameplayGuard = false` on both results present tables + a new test |
| 4 | A control declaring `adjustAxis` takes that axis's arrows from Navigate while focused | **None.** The game uses no `newSlider`/`newStepper`/`newRating` (zero hits). It uses `newTable` and `newVirtualList`; `newTable` deliberately declares no `adjustAxis` and keeps its select-then-resize mode, so its key set is unchanged. | none |
| 5 | New bundle fields `adjustAxis`, `handleTraverse`; `contribution.attach` throws on an illegal `adjustAxis` | **None.** Four game-side `contribution.attach` sites (`LuauUISponsor/init.luau:1860`, `ResultsScreen.luau:2873`/`:3393`, `TableScreen.luau:95`); none sets `adjustAxis`, so the new refusal cannot fire from any game call site. No game use of `handleTraverse`. | none |
| 6 | `focus_graph` scopes accept `traversalWrap`; the graph gains `traverse(delta)` | **None.** Additive; nothing existing changed. | none |
| 7 | `screen_target.setActivateHandler` reports `pointer = "keyboard"` (was `"mouse"`) for a keyboard-caused `Activated` | **None.** No game code reads `meta.pointer`/`meta.source`/`meta.shift`/`meta.toggle` (zero hits). The one meta construction, `LuauUISponsor:devDrive` (`init.luau:1100`), hardcodes `pointer = "touch"` on the dev-drive path and is unaffected. The game's own `"mouse"`/`"touch"`/`"gamepad"` literals belong to its separate `InputIdentity` device tracking, not to LuauUI activate meta. | none |
| 8 | An {IAS Activate, native Activated whose `meta.pointer` is `"keyboard"`/`"gamepad"`} pair on one path within 50 ms collapses to one activation | **None reachable.** The pair can only occur where `GuiService.SelectedObject` is set, which only `engineSelectionBridge` does, and the game's single use sets it to **`false`** (`ROLE_MODAL_OPTS`, `init.luau:352`). The guard keys on the native half's INPUT CLASS rather than on the surface, so a real mouse or touch click can never be eaten however close to a key press it lands. | none |
| — | `adjustTargets` is now handed the contribution's own node instead of the screen root (DKN-3) | **None.** No game bundle declares `adjustTargets` except the two `ResultsScreen` ones, which resolve their targets from the node they are given by walking it; both sit at the contribution root, so their own subtree is what they already meant. | none — re-proven by the game suite |

---

## The one required edit — DKN-4

`ResultsScreen.PRESENT_OPTS` (sponsor) and `PRESENT_OPTS_RACER` (racer) present
the results surface **engaged**, and the game binds `Space` itself on that
surface: `SkipCelebration` on the pose context
(`LuauUISponsor/init.luau:822-828`, priority 1000, non-sinking) runs
`results.skipAll()`. For the racer variant the results nav context is *also*
non-sinking (`sinkNavigation = false`, deliberately — a slow racer may still be
driving), so neither context sinks the other and **both** would have received the
same press: one Space would have skipped the celebration *and* activated
whichever results CTA the focus ring happened to be sitting on. The screen's own
comment records the assumption that broke — *"the Space/ButtonX skip … rides
non-sinking bindings already"* — which was true only while nothing else claimed
Space.

Before this stage a non-modal, non-passive `present()` screen created no
`GameplayGuard` action at all, so Space was neither guarded nor bound there.

**Fix (behavior-preserving):** both tables now declare `gameplayGuard = false`,
which is the framework's existing, documented opt-out for *"a surface that wants
Space"*. The framework then binds no Space on that surface at all, so the game's
`SkipCelebration` receives it exactly as before. No gameplay behavior changes; no
shim; no framework workaround in the game.

**Test:** `tests/luauui_closed_key_contract.spec.luau` — *"the results surfaces
keep Space for the celebration skip, not for Activate"*. It pins both directions
at the real framework boundary: the declaration is present in the shipped tables,
the framework honors it (zero `Space` bindings across the surface's actions), and
the same surface **without** the declaration does take the key — so the assertion
is testing the opt rather than the absence of the feature.

---

## Latent hazard recorded, not introduced

Three of the game's four LuauUI presenters (`GaragePilotGui`,
`LuauUIRacerListGui`, and the Sponsor results screen) can be simultaneously
mounted as non-passive, non-sinking base screens at the same priority when both
debug flags (`UseLuauUIGaragePilot`, `UseLuauUIRacerList`) are on, and neither
opt-in surface is ever destroyed. They are separate presenter instances with
separate focus graphs, so a single key steps each of them independently. That is
the hazard the presenter's own comment already warns about for the arrows, and
Tab joins the same set. **Under the default production configuration both flags
are off and the maximum is one**, so this is latent, not live, and it is not
introduced by this stage. Recorded here so the next person to enable both flags
finds it written down.

---

## Commands and results

| Command | Result |
|---|---|
| `games/RascalRally/code/run-tests.sh` (before) | 3019 passed, 0 failed |
| `games/RascalRally/code/run-tests.sh` (after, at this source) | **3020 passed, 0 failed** |
| Framework suite at the same source | 3067 passed, 0 failed |
| **Studio canary, Rascal Rally's own place** (Play session, LuauUI 0.8.0 Rojo-mounted) | **PASS** — see `studio/keyboard.json` row `DK18-consumer-canary` |

### The canary, because a suite is not a boundary

Added after the phase-gate review correctly found this row claiming a canary that
had not been run. The game's own `PRESENT_OPTS` and `PRESENT_OPTS_RACER` were read
from the live `ResultsScreen` module in a Play session and presented through the
real `client/roblox_input` + `client/screen_target` adapters, then the actual
`InputBinding` **Instances** under `PlayerScripts` were read back:

- both shipped variants: `Activate = [ButtonA, Return]` — **no Space binding
  exists**, so `SkipCelebration` keeps the key;
- with the declaration removed: `Activate` gains **Space** — the assertion tests
  the opt, not the absence of the feature;
- `Traverse = [Tab]` in **all three** — the game loses no keyboard traversal by
  keeping its skip key;
- after `dismiss`, the `Nav-*` `InputContext` Instance is gone entirely.

Driving a real racer to the results phase and pressing a physical Space remains
physical row DK-P2.

No RascalRally gameplay, content, feature flag, or Sponsor default was changed.
Nothing was published or deployed.
