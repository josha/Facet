# ADR-0014 — First responder: a Facet surface engages over avatar input via focus, never by disabling player control

Date: 2026-07-21 · Status: **ACCEPTED** · Spec: ui_todo.md §0/§3, design §9.1/§12.1 · Research: [`docs/research/2026-07-21-first-responder-platform-research.md`](../research/2026-07-21-first-responder-platform-research.md)

## Context

The director's standing principle (ui_todo §0) is that every Facet surface must
coexist with a real avatar game: a menu, a HUD, or a modal on screen must NOT
swallow the player's movement/jump input wholesale. The UI-only-place hammer —
`gamepad_contention.disableLegacyControls()` / `PlayerModule:GetControls():Disable()`
— turns avatar input OFF, which is correct only for a place that is nothing but UI
(the gallery). A real game keeps the avatar controls and must instead let a
surface become **first responder** through *arbitration*, so it handles events
before the avatar only while it is actually engaged, and yields otherwise. FIRST
RESPONDER is Facet's name for exactly that: the one surface that gets an input
event first, held only while the surface is engaged and given back the moment it
is not.

The bounded platform research (commissioned by the director, persisted verbatim
under `docs/research/`) established the load-bearing facts this ADR must follow.
Its conclusions in brief:

1. Roblox exposes **no unified responder chain**; "first responder" is assembled
   from two parallel systems — `GuiService` gamepad **focus** and an input-layer
   **sink** (IAS `Sink` or CAS priority) — coordinated manually.
2. The doc-sanctioned layering idiom is `PlayContext` vs `NavContext` toggled by
   `Enabled`, with a **gameplay sink recommended at `Priority = 2000`**; the
   default PlayerScripts contexts sit below that. No reserved-band table is
   published.

   **Corrected 2026-08-03.** This clause used to say the PlayerScripts contexts
   sit at a "historical default 1000", and the guide repeated it. Measured on the
   shipped `PlayerModule`, they are far lower and are not one number:
   **Camera 100, Character 150, Vehicle 200, Transformer 300**. The 2000 figure is
   a *recommendation for a game's own sink*, never where the avatar actually sits.
   No behavior depends on the difference — Facet's bands (1500 plain, 3000
   engaged) clear all of these either way — but the false number invites somebody
   to size a context against it, which is why it is written down correctly here
   rather than left as folklore.
3. To be focus-aware and never swallow jump wholesale, Facet must **sink jump
   inputs only in the engaged context, above the gameplay band** — mirror
   `ContextActionPriority.High = 3000` rather than tying the game's 2000.
4. **This only works in IAS player-script mode** (`PlayerScriptsUseInputActionSystem
   = true`). In legacy mode the character binds jump via CAS at 2000 and eats
   `ButtonA` before IAS fires; the requirement is unattainable there.

## Decision

Introduce a **responder mode per presented surface** in the presenter
(`src/present/presenter.luau`), engine-free, resolved entirely through the
headless action system's context priority + `Sink`.

### 1. Responder modes

- **`present()` default — engaged-open.** Unchanged from before this ADR: the nav
  `InputContext` is enabled at priority **1500**, **non-sinking**. Navigation
  works immediately AND gameplay also receives (documented UI-only-place
  semantics). Every prior test/example stays byte-identical. This is the correct
  mode for a UI-only place.
- **`present({ responder = "passive" })` — passive HUD.** The nav context is
  created **DISABLED** (at the engaged-band priority, but inert while disabled).
  A passive HUD binds nothing gameplay-contended: `deviceKey` navigation reaches
  the lower gameplay contexts and the HUD's focus never moves.
- **`presentModal()` — engaged-exclusive.** Always sinking, from the moment it
  opens, in the engaged band. Unaffected by `responder`.

### 2. Engagement transitions (the responder-chain analogue)

`handle.engage()` / `handle.resign()` are public. Auto transitions on a passive
surface:

- **Engage** — a pointer/touch tap on a focusable *inside* the passive surface
  engages it (routed at the presenter's `onNodeTap`, before Activate dispatch),
  or an explicit `handle.engage()`. Engaging enables the context and sets
  `Sink = true` — the surface is now first responder; its events stop before
  gameplay.
- **Resign** — **Cancel** (gamepad B) while an engaged-from-passive surface holds
  navigation resigns it (back to passive, context disabled) instead of doing
  nothing; an **outside tap** resigns it (reusing the modal outside-tap machinery,
  never clicking through to a lower screen); or an explicit `handle.resign()`.
  Resigning un-sinks and disables the context, restoring avatar delivery exactly.
- **`handle.responder`** is a readable `"passive" | "engaged"` for consumers /
  adapters. **`presenter.exclusiveSurfaceActive`** is a presenter-level readable
  `boolean`, true while any surface is exclusive (a modal, or an engaged-passive
  surface).

### 3. Priority bands (research conclusion 3)

- Base screens stay at **1500** (above the ~1000 avatar default, below the
  gameplay sink at 2000 — a passive/plain screen never suppresses movement).
- The **engaged-exclusive band starts at 3000** (moved up from the previous 2000
  base). 3000 mirrors `ContextActionPriority.High` and sits **strictly above** the
  doc-sanctioned gameplay sink at 2000. Tying 2000 would collide with a game's own
  `PlayContext` at an **undocumented** tie-break — beaten deliberately.
- An **engaged-from-passive** surface takes the band base (3000). **Modals** stack
  `topModalPriority() + 500`, i.e. from 3500 and +500 per stacked depth, always
  above the passive-engaged base.
- Fallout: no test asserted the literal old 2000 modal priority; the band change
  was proven by `tests/responder.spec.luau` asserting a modal's context priority
  is `> 2000` and `>= 3000`, citing this ADR / the research doc.

### 4. Gameplay guard while exclusive

An engaged-exclusive context (a modal, or a passive surface once engaged)
additionally sinks the avatar-contended keys our other bindings do not already
cover. `ButtonA` is sunk via **Activate**; arrows/D-pad via **Navigate**. The one
gap is **`Space` (keyboard jump)**, so an exclusive context binds `Space` to a
no-op **`GameplayGuard`** Bool action — sunk while engaged, so jump never fires.

- Overridable: `opts.gameplayGuard = false` opts out (a word-game-style modal that
  wants `Space`).
- **WASD is deliberately NOT sunk in v1** — recorded here as an **open decision**
  pending the live probe of the IAS jump/move binding set (research Open risk 3:
  the exact set of inputs the IAS jump/move `InputAction`s bind is undocumented;
  confirm `ButtonA` + `Space` + touch jump, and whether movement should be guarded,
  in a Studio session with a character and the flag set).

### 5. Client adapter effect seam

`src/client/responder_effects.luau` (client-local, require-safe, `pcall`-guarded
like `gamepad_contention`) observes `presenter.exclusiveSurfaceActive` and sets
`GuiService.TouchControlsEnabled = false` while an exclusive surface is up,
restoring the prior value on release. `bind(core, presenter) -> disconnect`. It is
NOT exported on the `Facet` table (client-only; require directly from
`src/client`). The gallery bootstrap wires it once with a comment — the gallery is
a UI-only place whose default screen presents no modal, so the effect is inert
there but proves the one-line wiring shape a real game uses.

### 6. The IAS-player-scripts precondition (research conclusion 4)

This model **only works in IAS player-script mode**. A real game must set
`Workspace.PlayerScriptsUseInputActionSystem = true` so the avatar controls
join the same arbitration Facet participates in. The flag is **Properties-panel
only** — not script- or rojo-reflectable (ui_todo §3; ENGINE TRUTH 2). The
framework therefore **DETECTS, never sets**:

- `gamepad_contention.legacyStackActive()` is a *behavioral* probe (a `jumpAction`
  binding in `ContextActionService:GetAllBoundActionInfo()`) — a **warn**, not a
  gate. A game (or doctor tooling) uses it to surface "gamepad ButtonA may be
  contended" instead of failing silently.
- **Legacy fallback is explicitly coarser.** With the flag off, the character
  binds jump via legacy CAS at 2000 and consumes `ButtonA` before IAS — a Facet
  IAS context can never see or sink it. The only levers are CAS-level
  (`BindAction` sink above 2000) or `Controls:Disable()`, neither per-action nor
  focus-granular. The director's requirement is attainable ONLY with the flag on;
  this ADR states that as a precondition and offers only the coarser fallback.

### 7. UI-only-place exemption

A place that is nothing but UI (the gallery, a menu shell, a lobby) has no avatar
to protect and MAY disable the legacy control stack
(`gamepad_contention.disableLegacyControls()`). That remedy is **UI-only-place
scoped** and out of scope for a real game — recorded so the two paths never blur.

## Deferred / open riders

- **WASD guard** — not sunk in v1; pending the live IAS move/jump binding-set probe
  (Open risk 3).
- **`GuiService.SelectedObject`** — v1 does **not** drive engine gamepad focus.
  `SelectedObject` and IAS are parallel systems with undocumented linkage (Open
  risk 4); driving it alongside Facet's own focus graph risks a double-drive.
  Deferred pending a probe of whether setting `SelectedObject` alters IAS
  arbitration (expected: no).
- **`TouchControlsEnabled` verification** — that `false` hides *both* thumbstick and
  jump and cleanly restores is inferred from the property's documented effect;
  confirm on a physical touch device (Open risk 6; the standing
  `physical-device-confirmation` gate rider).
- **Default PlayerScripts priorities/names, priority tie behavior, and Escape /
  CoreGui reservations** — undocumented / no sanctioned mechanism (research Open
  risks 1, 2, 5). Facet relies only on the doc-guaranteed "2000 sinks the
  defaults" and beats it at 3000.

## Consequences

- `present()` gains `responder` and `gameplayGuard` options (additive; default
  behavior byte-identical). Handle gains `.responder`, `.engage()`, `.resign()`.
  Presenter gains `.exclusiveSurfaceActive`.
- The director's exact scenario is proven headless in `tests/responder.spec.luau`
  (a fake gameplay stack — CharacterContext at 1000 with Jump←Space+ButtonA /
  Move←Up/Down, PlayContext at 2000 sink — driven through the real `deviceKey` /
  `adapter.tap` paths): passive yields, tap engages, resign restores, modal
  suppresses + restores, `gameplayGuard=false` lets `Space` through, `present()`
  default stays byte-compatible, and engage/resign churn is registry-neutral.
- The engaged-modal band moved 2000→3000; `docs/guide/07-input.md` and
  `docs/reference/api.md` document the shipped recipe.

## Alternatives considered

- **Tying the gameplay band at 2000** — rejected: undocumented tie-break with a
  game's own `PlayContext` (research conclusion 3). 3000 (CAS High) is above it.
- **Disabling player controls for engaged surfaces** — rejected: the director's
  core constraint. That is the UI-only-place hammer, not a focus mechanism, and
  hides the mobile GUI as a side effect (research conclusion 7).
- **Driving `GuiService.SelectedObject` in v1** — deferred (parallel-systems
  double-drive risk; needs a live probe).

## Verifier findings disposition (2026-07-21, the lead)

Two fresh-context verifiers (roblox-platform, architecture, both xhigh) reviewed this
delivery. Full reports: `artifacts/input-adaptation-audit/platform-verification.json` /
`architecture-verification.json`.

**Resolved (requirement-affecting):**
- **P1** — `engage()`/`resign()` changed Sink by bare field write, which the Roblox adapter
  never mirrored onto the real `InputContext.Sink` (dead write; engaged passive HUD would
  not have suppressed jump on hardware). Fixed: `setSink(on)` seam on BOTH action systems
  (`actions.luau`, `roblox_input.luau` → `contextInstance.Sink`), presenter routes through
  it; red-first spy test `engage() calls setSink(true) and resign() calls setSink(false)`;
  live Sink flip verified in the Studio drive.
- **P2** — the IAS flag is `Workspace.PlayerScriptsUseInputActionSystem`, not StarterPlayer.
  Renamed across guide/ADR/`gamepad_contention`/research/ui_todo (correction annotated).

**Acknowledged advisories (recorded, not gate-blocking):**
- **P3** — two headless behaviors (equal-priority sink tie; Released-on-disable) are
  [INFERRED], not doc-backed; `actions.luau` comments now carry the rider. Not load-bearing:
  Facet never shares a priority band.
- **P4** — adapter-parity had no test; the P1 spy test now guards the Sink seam contract.
- **F1** — reserved-prop collision: `contribution.read` now type-guards (non-table → nil).
- **F2** — auto navigation-mode is latched at present time; a screen that mounts its first
  HStack/Grid later never upgrades to 2D nav. Known limitation, documented here; revisit if
  a real consumer hits it.
- **F3** — two passive surfaces both `engage()`d share the 3000 band (double-delivery). The
  tap path already resigns the prior surface; the explicit-API hazard is documented: only
  one passive surface should be engaged at a time; enforcement is a follow-up.
- **F4** — a modal stack of depth ≥14 would tie/exceed the text-entry sink (10000).
  Unrealistic depth; recorded so the constant is derived, not rediscovered, if bounds change.
- **F5** — the four-input conformance check verifies cited case names exist verbatim but not
  that a case exercises the claimed class (mis-citation is possible; omission is not).
  Registry is honest today; scoping caseExists per-row-spec is a follow-up hardening.

**Studio-drive findings (2026-07-21 live pass; `artifacts/input-adaptation-audit/studio-drive.json`):**
- **Drive-F1 (design call owed):** modal outside-tap dismiss fires only when the tap lands on
  a RENDERED node outside the modal — there is no full-screen scrim catcher, so a tap on
  truly empty screen space does not dismiss. Whether the presenter should synthesize an
  invisible scrim catcher under every modal is a director design call; recorded, not assumed.
- **Drive-F2 (fixed):** `cannot own into a disposed scope` when a late Activate raced a
  TextInput dispose (stale handle during rapid example switching). Fixed same session:
  `disposed` guard in `beginEditing` with a red-first regression test.

### Drive-F1 RESOLUTION (2026-07-21, director-commissioned; the two-zone model)

The director commissioned a best-practice survey and presenter spec
([`docs/research/2026-07-21-modal-dismissal-spec.md`](../research/2026-07-21-modal-dismissal-spec.md),
UI-Designer authored) which **validated** the director's two-region model and closed
Drive-F1. Built test-first (`tests/modal_dismissal.spec.luau`).

- **Zone A (no dismiss)** is the modal's **painted** panel rect ⊕ a **24 px** forgiveness
  ring (`space.l` token) ∪ every focusable's **44 px** hit rect — a *geometric* region read
  from the modal's solved rects (`controller.rectOf`), **not** its blueprint-path envelope.
  An invisible/transparent container contributes nothing (defusing the "fill root swallows
  every tap" footgun); a visible fullscreen panel correctly has no outside.
- **Zone B (dismiss)** is a **presenter-synthesized full-viewport scrim/catcher** mounted
  beneath the top exclusive surface (path `/__scrim__/...`, outside every blueprint root,
  non-focusable, absent from navigation, `DisplayOrder` below its owner). Every tap now hits
  something, so the empty-space gap is closed. It also serves as the modal barrier and the
  dim affordance (`surface = "scrim"` at `scrimOpacity` 0.45; `scrim = "none"` = transparent
  but still catching, the default for an engaged HUD, §3.6).
- **Safety invariant:** outside-tap, `ButtonB`/Cancel, and the Close button resolve to the
  **same** non-destructive outcome (dismiss for modals, resign for engaged-passive surfaces).
- **BEHAVIOR CHANGE:** `outsideTapCancel = false` now **swallows** the outside tap (a true
  barrier — no dismiss, **no clickthrough**), where the pre-spec code let it fall through to
  the lower surface. The `auto_input_screens` WP-2 case that asserted the old clickthrough was
  updated to assert the swallow, citing the spec. Gamepad/keyboard paths are untouched.
- **Public surface (additive):** `present`/`presentModal` gain an optional `scrim` opt
  (`"scrim"` | `"none"`); handles gain `displayOrder`; the presenter gains `topScrimPath()`.
  The render-target contract gains an OPTIONAL `setRootDisplayOrder`, and the pointer activate
  meta now carries the window-space tap `x`/`y` (both degrade cleanly on targets that omit
  them). Guide §7.2 and `docs/reference/api.md` document the shipped surface.
