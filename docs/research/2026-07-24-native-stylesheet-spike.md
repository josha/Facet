# Studio spike results (2026-07-24): native StyleSheets Q1–Q12

Run live in Roblox Studio 0.731 (Play Solo, throwaway place) via the Studio MCP; machine
evidence in `artifacts/native-stylesheets/feasibility/*.json`. Resolves every open question
in `docs/plans/roblox-native-stylesheets.md` §10. Governing corrections doc confirmed
throughout. Studio timings are derated proxies — device measurements stay authoritative.

## The observation instrument (new engine truth — supersedes read-blindness)

- Plain property reads NEVER reflect applied styles (2026-07-19 truth still holds), but
  **`GuiObject:GetStyled(propertyName)` returns the RESOLVED styled value**, and
  `StylingService:GetAppliedStyles(instance)` lists the applied rules.
- `GetStyled` tracks the *actual* winner: on a defeated property it returns the explicit
  written value, not the rule value. **Defeat detection = `GetStyled(prop) ≠ sheet-resolved
  value`.** This is what makes the property-authority hand-off provable at runtime
  (ledger NSS-A2/NSS-M10).
- Visual ground truth (capture `NSS_M10_defeat_visual`) matched `GetStyled` pixel-for-pixel
  in all three authority cases (rule-only, write-before, write-after).

## Q-by-Q answers

| Q | Answer | Evidence |
|---|---|---|
| Q1 state selectors | `:Hover`/`:Press` restyle LuauUI's exact button shape (`TextButton`, `AutoButtonColor=false`) under REAL injected mouse; GuiState trace Idle→Hover→Press→Hover→Idle with fills following. **`:NonInteractable` keys on `GuiObject.Interactable=false` — `Active=false` does NOT trigger it.** Touch-emulator firing not drivable (lesson) → NSS-P2; touch hover-flash prevented structurally by tag-gating (Q4). | m1 |
| Q2/Q8 modifiers | `::UICorner`/`::UIStroke` rules **CREATE phantom modifiers** (render with no child instance in the tree). Precedence is **per-modifier**: a manually-created `UICorner` child SUPPRESSES the phantom corner (and is not styleable by rules) — the modifier-level analogue of the defeat truth — while a real `UIStroke` **COEXISTS** with the phantom stroke (both render; the thicker/opaquer stroke dominates visually — live probe with an exaggerated red 4px phantom + blue 2px real ring, capture `NSS_phantom_vs_focusring`). Consequence: native mode must STOP creating `UICorner`/`UIStroke` instances for handed-off chrome; the bespoke FocusRing real stroke is safe (coexists; solid 2–4px ring over a 1px 92%-transparent hairline). `::UIShadow` selector accepted; shadows stay adapter-materialized this stage. | m2, captures `NSS_M2_pseudo_visual`, `NSS_phantom_vs_focusring` |
| Q3 GA/probe | All style classes instantiable on 0.731 from plain client scripts; `hasStyleSheet = pcall(Instance.new, "StyleSheet")`. StyleQuery + enhanced pseudo-instances **fully released** (devforum 4566519, May 2026). Transitions RUN in Studio Play; publish status stays release rider NSS-P3. | m3 |
| Q4 queries | Two working forms only: **built-in global @-selectors** nested under a rule (`@ViewportDisplaySizeSmall/Medium/Large`, `@PreferredInputTouch/Gamepad/KeyboardAndMouse`, `@PreferredTextSizeMedium/…`, `@ReducedMotionEnabled`) and **element-attached container queries** (`StyleQuery` parented under the GuiBase2d, `SetCondition("MinSize"/"MaxSize"/"AspectRatioRange", …)`, referenced by `@Name` nested rule, live `IsActive`). A StyleQuery under the sheet is INERT. Custom condition names/`@Names` fail silently. LuauUI's filtered paradigm/pointer-live facts ride tags, exactly per corrections §6. | m4 |
| Q5 authorability | Rojo authors the sheet skeleton (tokens as typed attributes, rule Selectors) but NOT rule property maps. **§6.9 lands on Fallback B**: Luau token source authoritative → seed-once generator emits the DataModel sheet; editor paint edits persist because the generator refuses to overwrite an existing sheet; layout tokens mirrored as read-only reference attributes + freshness gate. | m5 + local rojo 7.7.0 probe |
| Q6 cascade | **Priority first, then insertion order (later wins). Selector specificity does NOT participate.** Generator must order rules deliberately (base → state → app-state → query variants) and may use Priority for hard overrides. | m6 |
| Q7 swap cost | 600 styled nodes: StyleLink attach 0.42 ms; `SetDerives` swap 0.05 ms (Studio-derated); repaint next frame; no residual per-frame cost. Device numbers → NSS-P2. | m7 |
| Q9 triggers | Tag flip, native GuiState change, derive swap, and runtime token mutation ALL animate declared transitions (30+ interpolated `GetStyled` samples each). A direct property write NEVER transitions (1 distinct value) and permanently defeats. | m8 |
| Q10 theme cross-fade | `SetDerives` swap cross-fades through interpolated values when the shared rule declares a transition — **animated theming is free**. NOTE: `SetDerives` takes **StyleSheets**, not StyleDerive instances; and a token attribute on the BASE sheet beats the same token from a derive — theme tokens must live only in theme sheets. | m8, m7 fixture |
| Q11 token mutation | Runtime `SetAttribute` on a theme-sheet token repaints live and transitions. Editor-view fight unobservable in Play Solo (editor edits the Edit DataModel) → folded into the NSS-P1 human workflow check. | m8 |
| Q12 reduced motion | `@ReducedMotionEnabled` is a valid built-in query (inactive while the setting is off — correct); the setting is read-only so the match-when-true direction is device-assisted (NSS-P2). **`SetPropertyTransitions({})` strips reliably → instant changes**, so LuauUI's own reducedMotion policy keeps a guaranteed adapter-side path. | m9, m4 |

## Design consequences locked by this spike

1. **Hand-off is provable:** the native-mode conformance probe asserts per handed-off
   property `GetStyled(prop) == sheet-resolved value`; any explicit-write regression is
   detected, closing the §3 policing gap at runtime rather than only by construction.
2. **Native mode must not materialize `UICorner`/`UIStroke`** for handed-off chrome — the
   sheet's phantom modifiers replace the instances; a leftover instance would silently
   defeat the sheet's corner/stroke rules (m2 precedence).
3. **Disabled = `Interactable=false`** in native mode (drives `:NonInteractable`);
   `Active=false` alone changes hit-testing but not GuiState.
4. **Rule ordering is the generator's job** (insertion order + Priority; no CSS
   specificity). Deterministic generation order: base surface rules → state rules →
   app-state tag rules → query variants; Priority reserved for accessibility overrides.
5. **Theme tokens live only in theme sheets** (base attribute would defeat every derive);
   base sheet holds rules + structural tokens; themes are whole StyleSheets passed to
   `SetDerives`.
6. **Hover gating stays LuauUI's**: state rules for hover are compound-gated on the
   pointer-live tag (`.luau-pointer-live`), so touch paradigms structurally cannot flash
   hover regardless of engine `:Hover` semantics on touch.
