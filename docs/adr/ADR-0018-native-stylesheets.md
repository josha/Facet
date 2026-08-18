# ADR-0018 — Native StyleSheets as the runtime styling source of truth

**Date:** 2026-07-24 · **Status:** Accepted (opt-in target capability) ·
**Plan:** `docs/plans/roblox-native-stylesheets.md` (Rev 2) governed by
`docs/plans/roblox-native-audit-corrections.md` · **Evidence:**
`artifacts/native-stylesheets/` (ledger + feasibility m1–m10 + adoption a1–a10)
· **Spike truths:** `docs/research/2026-07-24-native-stylesheet-spike.md`.

## Decision

Adopt the plan's option (c), the **native-maximal hybrid**, behind an opt-in
target capability (`screen_target.new({ nativeStyle = … })`, gallery A/B via
`workspace` attributes `Facet_NativeStyle` / `Facet_ForceStyleFallback`):

1. **The DataModel `StyleSheet` owns every proven styleable paint property** at
   an opted-in target: surface fills + transparency, corner/hairline chrome (as
   engine-created **phantom modifiers**), text color/font/placeholder,
   scrollbar color, interaction-state paint (`:Hover`/`:Press`/
   `:NonInteractable`), app-state paint (`.facet-selected`), themes
   (`SetDerives` of whole theme sheets), and declared per-rule transitions.
2. **The adapter classifies instead of painting**: engine class + CollectionService
   tags (`facet-surface-*`, `facet-interactive`, `facet-pointer-live`,
   `facet-selected`, `facet-role-*`), computed by the pure
   `sheet_model.classifyTags`; one `StyleLink` per Facet root.
3. **One authority per property, now runtime-provable.** The 2026-07-19 defeat
   truth holds (an explicit write silently and permanently beats a rule), and
   `GuiObject:GetStyled(prop)` resolves the ACTUAL winner — so the verification
   surface proves per property that nothing defeats the sheet
   (`authority.nativeSheetOwnedSet()` is the probe list). The explicit-write
   path survives untouched as a separate fallback mode, byte-equal on every
   mapped property (a10).
4. **R1 headless boundary:** every solver input (spacing, type, layout radii,
   target sizes, measurement durations) stays plain-Luau. The sheet carries
   generator-owned read-only **mirror attributes** for editor visibility only.
5. **R3 additive layering:** the player's text preference is engine-painted
   exactly once (measure-seam reservation only, re-proven under native paint,
   a8); reduced motion strips sheet transitions live
   (`SetPropertyTransitions({})` — renderer-wired to the env fact); ten-foot /
   focus / value-driven motion stay bespoke.

## §6.9 sync resolution — Fallback B, seed-once

Rojo authors sheet skeletons but not rule property maps (m5), so: **the Luau
token styles are the source; a seed-once generator**
(`src/tokens/sheet_model.luau` → `src/client/native_style.luau`) **emits the
sheet named `FacetStyle`** and never overwrites an existing same-schema sheet.
Designer paint edits (tokens on theme sheets, properties on named rules) are
therefore durable; layout mirrors are regenerated on every apply and labeled
read-only. Theme tokens live ONLY in theme sheets — a base-sheet attribute
would defeat every derive (m5/m7).

## Engine truths this ADR rests on (m1–m10)

- Cascade = `Priority` first, then **insertion order** (later wins); selector
  specificity does not participate. BUT insertion order is NOT
  serialization-stable (director live find 2026-07-24: a migrated sheet copied
  Edit→Play returned scrambled `GetStyleRules()`), so the generator **pins the
  cascade with explicit `StyleRule.Priority`** (model index × 10) and
  re-enforces it on every apply — order is never load-bearing at runtime.
- **Defeat is order-sensitive** (director live find 2026-07-24): a write made
  BEFORE the instance first joins the styled tree is stomped by the first style
  application; only writes made while styled defeat rules. Plain reads can
  falsely "confirm" a stomped write — verify with `GetStyled` + visual only
  (`docs/lessons/stylesheet-defeat-order-sensitive.md`). The toggle knob-track
  chrome therefore rides the `.facet-toggle-chrome` tag rule for opacity, not
  explicit writes.
- `::UICorner`/`::UIStroke` rules **create phantom modifiers**; a real modifier
  child suppresses a phantom corner and is itself un-styleable; a real
  `UIStroke` **coexists** with a phantom stroke (thicker wins visually) — the
  1px/92%-transparent hairline vs the solid 2–4px focus ring resolves correctly.
- `:NonInteractable` keys on `GuiObject.Interactable=false` (`Active` does not).
- Working query forms: built-in global `@Name` selectors
  (`@ViewportDisplaySize*`, `@PreferredInput{Touch,Gamepad,KeyboardAndMouse}`,
  `@PreferredTextSize*`, `@ReducedMotionEnabled`) nested under a rule, and
  element-attached container `StyleQuery` (`MinSize`/`MaxSize`/
  `AspectRatioRange`, live `IsActive`). A `StyleQuery` under the sheet is
  inert; custom names fail silently → Facet facts ride tags, per corrections §6.
- Tag flips, GuiState changes, derive swaps, and token mutation all trigger
  declared transitions; direct writes never do.
- Plain property reads are blind to styles; **`GetStyled` is the instrument**.

## What stays bespoke (with reasons)

Layout + text geometry (solver-owned), data bindings, the logical focus ring +
ten-foot lift (four-paradigm graph + bounds-fit — not expressible natively),
choreographed/value-driven motion (Toggle knob-track assembly — opacity via
the `.facet-toggle-chrome` tag rule, value-driven colors as post-styling
writes), pointer
capture/cursor seams, `UIShadow` materialization (kept behind the existing
capability probe this stage), `Path2D` stroke color (value-adjacent; candidate
for a later tag rule), and capability fallbacks.

## Verifier-driven refinements (2026-07-24, same session)

The fresh-context architecture + platform reviews (NSS-I5) drove these
corrections, all landed and re-verified:

- **Central authority gate:** every bespoke paint path calls
  `assertBespokePaint(prop)` (screen_target), which errors on any write to a
  `authority.nativeSheetOwned` property in native mode — a missed guard is now
  loud, never a silent dual authority. The toggle knob-track assembly's chrome
  opacity is sheet-owned via `.facet-toggle-chrome` (its earlier "declared
  override" writes were pre-parent and got stomped — order-sensitivity truth
  above); its value-driven colors are post-styling writes with no competing rule.
- **Grip focus fill** moved from an explicit write (which permanently defeated
  the "Frame default" rule) to the `.facet-grip-focus` tag rule — theme-aware.
- **Host policy:** lookup prefers the designer-seeded ReplicatedStorage sheet;
  runtime creation is CLIENT-LOCAL (PlayerGui) — a LocalScript must not
  populate ReplicatedStorage (client-local anyway under FilteringEnabled, and
  it invites name collisions). Edit-mode seeding still targets
  ReplicatedStorage so the sheet persists with the place. Per-client
  `SetDerives`/attribute writes on a replicated sheet are client-local — each
  client can hold its own theme.
- **Transitions default OFF** (`nativeStyle = { transitions = true }` to opt
  in; gallery attribute `Facet_NativeTransitions`) and every
  `SetPropertyTransitions` call is pcall-guarded — publish status is the open
  NSS-P3 rider and the instant path must never depend on the method existing.
  The renderer's reduced-motion wiring composes with the opt (RM strips; RM
  off restores only where opted in).
- **Gamepad-selection hover suppression:** engine selection reports
  `GuiState=Hover` (native-substrate m9), so the engine-selection bridge
  suppresses the node's pointer-live tag while it owns it — a pad-selected
  control never paints the pointer hover fill. Outside the bridge Facet keeps
  `SelectedObject=nil`, so no other selection path exists.
- **Stroke precedence precision:** real `UIStroke` COEXISTS with a phantom
  stroke (probe `NSS_phantom_vs_focusring`); only `UICorner` has real-child
  suppression. Recorded per-modifier in m2/the spike doc.

## Known limits (documented, not defects)

- **One shared sheet per host:** all native-mode targets of one client share
  `FacetStyle` — theme and transition state are global across those roots
  (last writer wins). Per-target theming would need per-target sheets via
  `nativeStyle.host`/`model`; deliberately out of scope this stage.
- **Disabled affordance parity:** only text dims (`TextTransparency 0.4`), and
  a disabled Toggle's child label does not dim — byte-parity with the bespoke
  path (pre-existing thinness, not a regression).

## Consequences

- Runtime theming exists for the first time (`adapter.setNativeTheme`; Dark +
  Light built-ins, both contrast-gated).
- Designers edit named rules/tokens in the Style Editor and the running screen
  repaints with no Luau change (a3 automated; editor-UI discoverability is the
  NSS-P1 human row).
- Transitions remain progressive enhancement: strip path proven, publish
  status re-checked at release (NSS-P3).
- The sheet must never share a name with the library tree (`FacetStyle`;
  class-checked lookup — a live-found hazard, a9).
