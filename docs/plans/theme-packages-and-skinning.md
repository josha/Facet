# LuauUI theme packages, metric-aware swaps, and rich skinning

**Date:** 2026-07-24  
**Status:** Proposed Step 3.5, after completed native StyleSheets and the current
authoring/control milestone.

## Decision summary

LuauUI can currently swap a dark and light **palette**, but it is not yet a complete
theme system.

The native StyleSheet stage established the right paint foundation: semantic tags,
named rules, editable color tokens, native state styling, `StyleDerive` swaps, and
no-remount runtime theme changes. The current implementation does not let each theme
own its typography, spacing, control metrics, layout-affecting insets, or rich
asset-backed chrome while keeping the solver correct.

That gap deserves a separate Step 3.5. It should not reopen Step 2, which is complete,
or be folded into the nearly complete Step 3. Step 3.5 consumes both: Step 2 supplies
native styling, and Step 3 supplies the control and layout vocabulary that every
theme must cover.

## Current capability audit

This audit reflects the repository on 2026-07-24. Recheck it after Step 3 finishes.

| Capability | Current state |
|---|---|
| Swap dark/light colors through `StyleDerive` without remounting | Implemented and Studio-verified |
| Edit named paint tokens/rules in the Style Editor | Implemented; paint edits persist under the seed-once policy |
| Give each theme a different font family, type scale, spacing, or control size | Not implemented |
| Re-solve layout when a theme changes text/control metrics | Not implemented |
| Author layout-affecting theme values visually and keep headless tests synchronized | Current sheet attributes are read-only mirrors; edits have no runtime effect |
| Build a reusable custom theme without importing internal modules | No supported public theme-package API |
| Use gradients, shadows, strokes, and basic native chrome | Partially supported, with a narrow generated rule set |
| Make a panel a nine-slice parchment, glossy plate, or sci-fi frame without changing screen code | No stable decoration slots or standardized skin recipe |
| Theme semantic icons and asset failure behavior | No theme asset/icon contract |
| Scope themes per application/root instead of one shared host sheet | Possible only through internal target options; not a public framework contract |

The concrete causes are visible in the current source:

- `sheet_model.themeTokens` emits color tokens only.
- rules use one constant Builder Sans font and radii/strokes from the first theme;
  later themes cannot change them.
- layout mirrors come from the first theme and are overwritten as reference-only
  attributes.
- `setNativeTheme` changes only the native derive; it does not update the solver.
- the renderer and composite controls still contain numeric text sizes, gaps, and
  padding. Those values cannot react to a theme.
- `LuauUI` exports token compilation but no supported theme builder, controller,
  importer, exporter, or package format.
- ordinary surfaces are Frames. A StyleSheet can style them, but cannot turn a Frame
  into an arbitrary ImageLabel subtree.

This is narrower than Roblox itself. The current
[Style Editor](https://create.roblox.com/docs/ui/styling/editor) supports theme tokens
for colors, fonts, and text sizes, and runtime theme swapping. Roblox's
[styling compatibility table](https://create.roblox.com/docs/ui/styling/compatibility)
also includes ImageLabel image/nine-slice properties, UIGradient, UICorner, UIStroke,
UIShadow, text typography, and many other properties. LuauUI should expose that power
without surrendering its deterministic solver or property-authority rules.

## User-facing promise

A game author writes a screen once using semantic LuauUI roles. They can install or
create a versioned theme package and swap it at runtime without editing that screen.

A theme may change:

- palette, typography, density, spacing, radii, strokes, shadows, and motion;
- standard control heights, padding, icon sizes, focus treatment, and scroll chrome;
- semantic icons and bounded decorative assets;
- panel/control chrome, including gradients and nine-slice imagery;
- targeted variants for display/input/accessibility profiles through the existing
  environment and native-query contracts.

The solver must measure the effective font, text size, line height, spacing, content
insets, and control metrics used by the active theme. A swap may trigger a layout
pass, but must not remount controls or lose state, focus, selection, scroll position,
text entry, or resource ownership.

Themes do not change information architecture, game rules, command behavior, or input
paradigms. A fantasy button may look carved or parchment-backed; it remains the same
Button with the same actions, focus behavior, accessibility name, and hit-floor
rules.

## Required architecture

### 1. A public, versioned `ThemePackage`

Define one documented schema, available through public LuauUI APIs rather than
internal requires. The exact names are a Fable design decision, but the package must
contain these conceptual sections:

- identity: stable ID, display name, schema version, package version;
- native style: the sheet/theme derives and semantic rule/tag vocabulary;
- metrics: typography roles, spacing scale, control sizes, content insets, radii,
  target floors, icon sizes, and measurement-relevant motion;
- chrome: semantic surface/control recipes and bounded decoration slots;
- assets: semantic asset names, content IDs, nine-slice/tile metadata, preload
  policy, failure fallback, and optional tint roles;
- motion: native paint transitions plus reduced-motion behavior;
- compatibility: required LuauUI schema/capabilities and declared fallbacks.

This is a thin packaging and solver bridge around Roblox's native StyleSheets, not a
second style language. The DataModel sheet should remain the authoring source for
every value and rule the Style Editor can represent. The package adds only
versioning, validation, deterministic exported metrics, and bounded asset/chrome
metadata that the solver or native sheet cannot own directly; it must not copy the
native rule tree into a parallel hand-authored Luau table.

Use native `StyleDerive` composition so an author can begin with a supported base,
override only the visual decisions they intend to change, and inherit new core roles
through a diagnosed upgrade instead of copying the whole sheet. Keep one versioned
core role vocabulary. Custom controls may register namespaced semantic roles,
metrics, and decoration slots through LuauUI's public contribution contract; their
registration must declare types, fallbacks, authority, and required capabilities so
package validation can report uncovered controls before play.

Compilation must reject missing roles, unknown recipe fields, unsupported native
properties, contrast failures, invalid content insets, target sizes below the
accessibility floor, missing fallbacks, and incompatible schema versions with useful
authoring errors.

Do not allow arbitrary theme callbacks. A theme is declarative data, so agents can
inspect, validate, serialize, and modify it safely.

### 2. One effective metric snapshot for both solver and adapter

Theme paint can remain native, but every value that affects measurement must resolve
to one frozen plain-Luau `ThemeSnapshot`. The renderer, solver, headless suite, Studio
preview, and native materializer must consume the same effective values.

The resolver composes, exactly once:

1. theme-authored base metric;
2. LuauUI display/density policy;
3. Roblox preferred-text reservation;
4. accessibility and minimum-hit-target floors;
5. a deliberate local override, if the screen explicitly requests one.

Ordinary framework controls and examples should use semantic roles such as body,
label, heading, title, compact/regular/large control, and spacing steps. Numeric
values remain an escape hatch, but explicitly opt that property out of theme changes.
A drift/lint check should prevent reusable framework controls from silently hardcoding
theme-owned metrics.

On a theme change, switch the native derive and metric snapshot as one logical
transaction, invalidate the correct measure/arrange dependencies, and keep mount and
interaction identity. Native transitions may animate paint. They must not animate a
geometry value independently of the solver.

The public controller is scoped to a render target/application root rather than
silently mutating a process-global theme. Two independently hosted roots may select
different packages when the native `StyleLink` topology supports it. If a target
cannot provide that isolation, installation must fail with a useful capability error
instead of changing another mounted UI. Nested per-view theme overrides are not
required by this stage.

### 3. Font-aware text measurement

Typography roles include `FontFace`, size, weight/style, and line height. Extend the
existing text-measurement/calibration seam to key by the effective Font descriptor,
not a short hardcoded font name.

Use Roblox `TextService:GetTextBoundsAsync()` or the current supported measurement
surface at the adapter edge. A newly installed font uses a conservative non-clipping
fallback until calibrated, then causes one bounded relayout. Theme loading should
preflight its declared fonts where possible. Preferred text remains applied exactly
once.

### 4. Style Editor authoring with an honest synchronization workflow

The current reference-only layout mirrors are not sufficient for this feature.
Studio authors must be able to edit supported font and metric tokens and see the
running preview re-solve without changing screen source.

Probe and choose the simplest reliable source-of-truth workflow:

1. **Preferred:** the DataModel theme package owns supported paint and metric tokens;
   a public exporter writes a deterministic plain-Luau snapshot, and a freshness gate
   prevents committed headless data from drifting.
2. **Fallback:** a plain-Luau theme manifest owns metrics and generates the native
   package; the Style Editor previews paint directly, while one explicit
   “Synchronize Theme Metrics” action imports supported edits and refreshes the
   snapshot.

Either workflow must provide live Studio preview, one obvious persistence/export
action at most, deterministic rebuilds, readable names, upgrade-safe migration, and
an actionable stale-snapshot error. Never maintain two manually editable metric
sources.

The design must also declare which native properties are legal for a theme. Roblox
can style `Size`, `Position`, and other layout properties, but a LuauUI theme may not
bypass the solver. The theme linter rejects writes that conflict with layout,
binding, presentation, or host authority.

### 5. Bounded chrome recipes and stable decoration slots

Use native StyleSheet capabilities first. For appearance that requires real child
objects, add the smallest stable semantic decoration substrate at the adapter edge.
A recipe may select native fill/stroke/corner/shadow/gradient or a bounded asset
layer such as a nine-slice background. It may declare content insets that feed the
metric snapshot.

The substrate must be sufficient for:

- a compact square-edged classic desktop theme;
- a glossy early-mobile theme with different typography and control sizes;
- an original fantasy parchment theme with nine-slice panels and controls, safe
  content insets, and semantic interaction-state treatments;
- an original sci-fi HUD theme using gradients/strokes/images without game-specific
  behavior.

These are capability references, not replicas of BeOS, Mac OS, iPhone OS, Halo, or
their protected assets/trade dress.

Recipes must not insert arbitrary interactive controls or rearrange content. Asset
loading uses the existing resource provider, has deterministic failure/stale-result
handling, and falls back to readable native chrome. Instance count, memory, preload
cost, and theme-swap cost are measured; flat themes should not pay for unused ornate
layers.

### 6. Fantasy Parchment is the primary proof theme

Build **Fantasy Parchment** as though it came from a game team that only has LuauUI's
public APIs and documentation. It is not a toy palette and must not require internal
module imports or screen-specific branches.

Use original repository-owned art. Where appropriate, panels, Button variants,
TextInput, selection surfaces, and representative value-control chrome use Roblox
nine-slice images (`ScaleType = Slice`, `SliceCenter`, and `SliceScale`) through the
bounded recipe/slot contract. Prove default, hover, pressed, focused, selected,
disabled, validation/error, and asset-fallback states without replacing the control's
semantics or activation surface. Record source-art, import/publishing, content-ID,
preload, and licensing/provenance instructions so another project can reproduce the
package without hidden assets.

The package must materially change font, type scale, spacing, control heights,
corners, strokes, content insets, icons, and ornate chrome. Its metrics may adapt to
available space, viewing distance, preferred text, and accessibility floors through
the framework's declared profile/query contracts. They must not branch on platform
names or change the framework-selected interaction paradigm.

Run the full Step 3 control gallery under Studio Neutral and Fantasy Parchment on the
canonical five-view matrix. In addition to geometry and captures, drive the supported
pointer/keyboard paths and the emulatable downstream focus/navigation actions. Prove
that touch-sized geometry, ten-foot focus, scrolling/keep-visible, text entry,
Slider/Stepper adjustment, menus/dialogs, and live portrait/landscape changes remain
correct. Physical touch and gamepad delivery stay separate evidence rows. A nine-
slice screenshot alone does not pass: actual slice properties, decoration instance
counts, solver-visible insets, hit geometry, focus/state identity, and raw-to-semantic
input traces must agree.

## Public workflow

The completed API should make these operations ordinary and documented:

1. create or duplicate a theme package;
2. edit it in the Style Editor and theme authoring preview;
3. validate/export it;
4. install it in a game without modifying LuauUI internals;
5. choose an initial theme for an application root and swap through its reactive
   controller;
6. inspect the active package, schema version, effective metrics, and fallback state;
7. package/reuse a theme across places.

Provide one theme-authoring gallery scenario or place with:

- the complete control vocabulary from Step 3;
- long/localized text, preferred-text and reduced-motion switches;
- compact phone portrait/landscape, tablet, desktop, and ten-foot profiles;
- live token and metric editing;
- flat and asset-backed theme swaps;
- missing asset/font and incompatible-package failure fixtures;
- geometry, mount, focus, resource, and performance telemetry.

## Documentation and one canonical command

Ship the feature with a beginner-readable
`docs/guide/09-custom-themes.md` and index it from `docs/guide/README.md`. Starting
from Studio Neutral, it must walk through duplicating/deriving a package, editing
paint/font/metric tokens in the Style Editor, adding an original nine-slice panel and
Button treatment, declaring insets and fallbacks, previewing all controls and device
profiles, validating/exporting, installing at an application root, swapping live,
handling upgrades, and profiling ornate cost. Use Fantasy Parchment as the complete
worked example.

Also add `docs/extending/new-theme.md` for framework and agent contributors. It must
explain property authority, core and namespaced roles, schema/version migration,
decoration-slot limits, asset provenance/import, tests, Studio evidence, and the
registration/gate obligations. Update the styling and architecture guides, public API
reference, inventory, example index, and relevant extension docs so they describe the
same shipped surface; remove the current “planned limitation” language only after the
feature works.

Provide one canonical repository command:
`lune run tools/lune/check_docs_cli`. It is read-only by default and required by the
Step 3.5 gate. Prefer extending the existing registration/drift machinery over a
competing documentation system. It must verify at minimum:

- the guide index, custom-theme guide, new-theme playbook, public API, inventory, and
  examples all cover the current theme schema/controller and supported roles;
- generated schema/API tables are fresh, local links resolve, example package and
  assets exist, and every public theme export is documented;
- the Fantasy Parchment walkthrough still builds through public APIs; and
- known current-version/limitation statements are not stale.

The same tool may offer an explicit `--write` mode for deterministic generated
blocks, but it must never rewrite human explanations. On failure it prints the exact
document, missing obligation, and update command or manual action. Record the command
in the guide and final report.

## Implementation routing

This stage is Fable-led because its source-of-truth, metric-authority, font-measurement,
and chrome-slot decisions have several defensible designs and interact.

Fable owns the audit, engine probes, acceptance ledger, final interfaces, and
integration plan. Once a work package has an unambiguous contract, dispatch it to
Claude Opus 5 at `xhigh` effort. Likely packages are:

1. package schema, public API, metric resolver, and headless migration;
2. Style Editor import/export, native materialization, and atomic swapping;
3. bounded chrome recipes, asset handling, reference themes, and Studio fixtures.

Keep ownership disjoint and concurrent agents few. Fable integrates and resolves
findings; Opus does not invent an alternate theme architecture inside a package.

## Verification

Register `theme-packages-and-skinning` in the existing gate system before
implementation. Treat `agent-execution-contract.md` and
`studio-device-verification.md` as binding.

The acceptance ledger must prove:

- a third-party-style theme package can be built using only public docs/APIs;
- following the custom-theme guide from a clean consumer fixture produces Fantasy
  Parchment without internal imports or undocumented steps;
- a contributed custom control declares namespaced theme needs and receives either a
  complete package treatment or a useful pre-play validation error;
- palette-only, metric-changing, font-changing, and asset-backed themes all work;
- a theme swap causes the expected solver reflow without remount/state/focus/scroll
  loss;
- actual painted font/size and solved text bounds agree, including preferred text,
  localization, and ten-foot treatment;
- every Step 3 control responds to semantic type/spacing/control metrics;
- Style Editor paint edits apply immediately, and supported metric edits re-solve in
  preview through the documented sync path;
- Fantasy Parchment's nine-slice panels and controls retain correct slices, insets,
  state/focus treatment, hit geometry, and adaptive paradigms across the five views;
- ornate chrome fails safely when an asset/font is missing or stale;
- property authority catches illegal theme rules;
- fallback and headless paths remain deterministic;
- theme swap, instance, memory, and resource costs are recorded without claiming
  low-end-device proof from Studio.

Run the canonical five-view Studio matrix for the reference themes, but use pairwise
coverage for locale, preferred text, reduced motion, and failure axes. Physical touch,
gamepad, and low-end performance remain separate rows.

Completion requires the canonical gate artifact; public API and custom-theme guide;
the canonical documentation command green; upgrade/freshness checks; Fantasy
Parchment and other reference packages; the authoring fixture/place; full suite and
prior gates green; and fresh-context architecture, reactive-runtime, Roblox-platform,
and phase-gate reviews resolved.

## Later roadmap integration

- Step 4 measures theme-change and font/asset failure behavior as part of the quality
  system.
- Step 5 uses only the public semantic theme contract for Sponsor-shaped fixtures.
- Step 5.5 may simplify the implementation but cannot weaken the theme capability.
- Step 6 may author a RascalRally package, but does not embed game styling in LuauUI.
- Step 7 profiles both a flat theme and the most expensive reference skin.
- Step 8 proves all tutorial examples restyle through at least one materially
  different reference package without screen edits.

## Non-goals

- arbitrary theme-provided Lua callbacks or component trees;
- changing game behavior, information architecture, navigation, or platform
  paradigms through a theme;
- exact replicas or bundled assets from existing operating systems or games;
- replacing the deterministic solver with native automatic sizing;
- allowing StyleSheet rules to write solver-, binding-, or game-owned properties;
- Sponsor migration or legacy removal;
- claiming physical-device performance before Step 7's real-device work.
