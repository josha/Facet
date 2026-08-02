# native-stylesheets stage — summary (2026-07-24)

**Gate: PASS** (`gate.json`; the single `FAIL_ENVIRONMENT` check is the
irreducible NSS-P1..P3 human/device batch — see `review-packet.md`).
Suite 655→671 green · game suite 2404 green, zero game edits · 10/10 prior
gates re-pass post-fix.

## What shipped

Roblox StyleSheets + the Style Editor are now the runtime paint authority for
opted-in LuauUI targets (`screen_target.new({ nativeStyle = … })`):

- **Pure model** (`src/tokens/sheet_model.luau`): tokens/rules/mirrors/motion +
  the `classifyTags` hint→tag mapping, value-exact against the Luau styles,
  contrast-gated per theme, cascade-ordered for the measured engine semantics
  (Priority, then insertion order — specificity does not participate).
- **Seed-once materializer** (`src/client/native_style.luau`): sheet
  `LuauUIStyle` (designer ReplicatedStorage sheet preferred; runtime creation
  client-local in PlayerGui); theme token edits always survive; rules
  regenerate only on a model-stamp upgrade (with warn + token backfill);
  transitions are opt-in and pcall-guarded.
- **Native adapter mode** (`screen_target`): classifies with class + `luau-*`
  tags under one StyleLink per root; every handed-off property (fills,
  transparency, phantom corner/hairline chrome, text paint, scrollbar,
  hover/press/disabled/selected/grip-focus states, themes) is sheet-owned,
  with a central `assertBespokePaint` gate making any future bespoke write to
  a `authority.nativeSheetOwned` property a loud error. Explicit-write
  fallback unchanged and byte-equal (A/B via workspace attributes).
- **Runtime theming** (Dark + Light built-ins, contrast-gated,
  `adapter.setNativeTheme`) with no remount and focus/scroll retention;
  reduced motion strips sheet transitions live via the renderer's env wiring.

## Evidence map

- Ledger: `acceptance-ledger.md` — 10 feasibility rows (Q1–Q12), 10 adoption
  rows, 5 invariants, all `PASS_AUTOMATED` with per-row artifacts; NSS-P1..P3
  pending (E4/E5).
- The acceptance centerpiece (`a3-live-edit.json` + capture): runtime edits of
  the SAME DataModel objects the Style Editor drives repainted the running
  screen with zero Luau change, identical mount identity, unchanged focus.
- Real-input states (`a4`): injected-mouse GuiState trace
  Idle→Hover→Press→Hover→Idle with rule fills following; disabled via
  `Interactable=false` → `:NonInteractable`.
- Fresh-context verification (`verifier-architecture.json`,
  `verifier-platform.json`): 15 findings total (1 BLOCKER — feasibility
  artifacts written to the wrong root, moved; 1+4 MAJOR — all fixed:
  central authority gate, grip-focus tag rule, bridge hover suppression,
  client-local host, transitions default-off) — every finding fixed or
  dispositioned, affected slices re-driven live.

## Key engine truths pinned this stage (spike doc 2026-07-24)

`GetStyled` resolves the actual winner (defeat detection); phantom modifiers
(UICorner: real child suppresses; UIStroke: coexists); cascade =
Priority→insertion order; built-in @-queries + element-attached container
queries only (sheet-parented StyleQuery is inert; custom names silent);
`Interactable=false` drives NonInteractable; `SetDerives(StyleSheets)` +
base-attribute-beats-derive; all styling-system changes animate declared
transitions, direct writes never.

## Open (batched for human review — `review-packet.md`)

NSS-P1 Style Editor discoverability (E5) · NSS-P2 device confirmations (touch
hover-flash absence, theme-swap cost, RM-on query direction, pad-selection
hover) · NSS-P3 transitions publish status at release.
