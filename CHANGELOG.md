# Changelog

All notable changes to Facet are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and Facet's version
numbers follow the policy in
[`CONTRIBUTING.md` §6](CONTRIBUTING.md#6-versioning-and-deprecation): while the
library is pre-1.0, a minor bump may change public behavior, and every retiring
surface is listed in `Facet.DEPRECATIONS` with its replacement and the earliest
version that may remove it.

The version string lives in exactly one place, `src/init.luau`, and is readable at
runtime as `Facet.VERSION`.

## [Unreleased]

- Segmented picker, shape round (2026-09-12, user visual review). The strip is
  ONE strip: only its outer ends round, with the theme's `radii.control` rather
  than a hard-coded pill; the inner segments are square and touch, with a
  hairline seam between each pair (hidden beside the selection, because the
  sliding fill paints behind the strip); the fill wears the silhouette of the
  segment it is on; and the track plate takes the same outer radius. The same
  rule turned 90 degrees is the vertical rail's. `selection_indicator` gains
  `segmentCorners`, and its default corner is now `radii.control` — Pixel Quest
  draws a 4px selection and Fantasy Ornate a 6px one where both drew a capsule.
  `corner = "pill"` remains the caller's opt-in. A `TabView` strip
  (`track = false`) keeps its own spacing and gains only the theme radius.
- A ten-foot row list gives every row one silhouette, chosen or not, and lifts
  the FOCUSED row by a paint-only 1.05 on the presenter's spring (reduced motion
  places it on the frame it arrives). The solver, the hit target and the focus
  order do not move, and the rows' own gap is wider than the lift.
- `newLevelPicker`'s `bar` segment plates a track and rounds only the run's two
  ends, the same language the segmented picker speaks. `newRating` (glyph) is
  unchanged.
- Fixed: a segmented strip's segments were the same height only while their
  labels agreed about truncating — at the Largest preference under Fantasy
  Ornate one reserved its disclosure plate and the other did not, solving 108px
  beside 66px. The option stack stretches its children on the cross axis now.
- `Controls.Menu`'s anchored panel is now one card: flat `plain` rows with no
  radius of their own, one hairline between adjacent rows, and a selection fill
  that is the row's own surface, clipped to the card's radius at its two ends.
- A selected menu row's label is now painted for the fill it sits on
  (`accent`/`onAccent`). It previously kept `$Content`, which read at 2.37:1 on
  Glossy Touch and 2.46:1 on Pixel Quest. New gate:
  `tests/selection_contrast.spec.luau`.
- `Controls.SplitButton`'s touch form shows a trailing `chevron.down` hint, so
  the long-press menu is discoverable. Still one hit target, one focus stop,
  one activation.
- A control's content line is centred: an icon beside a word in a `UI.Button` no
  longer rides the top of the line under a package whose icon rung is taller
  than its control type (Pixel Quest 6px, Fantasy Ornate 4.5, Glossy Touch and
  Classic Desktop 2.5).
- A closed picker trigger paints its package's `control` plate instead of the
  row-selection wash. It declares `selected` so its open state can light up, and
  the slot classifier read that declaration as a state.
- A picker popover grows to fit its widest row's full label, measured through
  `text_metrics` and counting the card's frame, the scroller's shadow reserve
  and the row's real padding. Pixel Quest asked for 182px where 280 was needed,
  leaving 78px for a 176px word.
- `UI.ScrollView` accepts `chromeReserve` (`"auto"` default, `"none"`): the
  lane a scroller keeps for content chrome that reaches past its box. The
  picker popover's list declares `"none"` — its rows are plain and its check
  draws inside its box — so the list runs to the card's content box and the
  chosen row's fill spans the card less one `xs` a side with the theme's
  control radius (Glossy Touch had it floating 31px inside the card), and
  two rows that fit no longer show a scrollbar (the region's content grew by
  two lanes while the host grew by one). Pinned in `picker_sweep`.
- `menu_recipe.row` accepts a Readable `indicatorEdge`; the picker popover
  passes one, so the check follows the live interaction class instead of the
  class at build time.
- The chosen row in a picker popover paints its label with the theme's
  `onSelected` partner (Glossy Touch 2.37:1 → 7.03:1, Pixel Quest 2.46:1 →
  6.04:1). `onSelected` is a new tint role: the decision `$OnSelected` already
  carried, reachable by a child `UI.Text` that no `TextButton`-scoped sheet rule
  can descend into.
- Gallery: the selection and action demos caption every control ("Picker ·
  segmented", "Split button", …) so a capture names what it shows.

- Picker menu, third visual round (2026-09-12, user review of the side-by-side
  against the reference platform). The popover is ONE card: the panel owns the
  corner and the stroke, the rows are plain with a hairline between them, the
  chosen row carries a subtle `controlSelected` fill, and the check sits at the
  row's trailing edge on a touch surface (leading on a pointer or pad). The
  touch form row is one row — title and value + chevron on one line, value and
  chevron flush trailing, no box, the whole row the tap target; a pointer or a
  pad keeps the boxed pop-up button beside the title, centred on its line. The
  chevron is centred on the value's line everywhere, and the picker sweep pins
  both centres to a pixel. `menu_recipe.row` gains `indicatorEdge`.

- `UI.Button` accepts `disclose` (construction-only), the same full-value
  path a one-line `Text` or a Toggle label carries: a squeezed label reaches its
  whole string through the large-text plate. Every segment of a sliding picker
  strip declares it, which closes the LT-G4 gap the large-text sweeps recorded
  (an option label with no route to the whole string); a TabView's tab strip
  declines it (`track = false`) because the bar's own compact ladder owns
  overflow there.

- **Icons: no shipped theme paints a character where a picture belongs.** The
  radio and checkbox indicators, the pop-up button's chevron pair and the tick
  now resolve to real art in every shipped package. Facet's own icon set gained
  the three selection marks; Pixel Quest gained the eight names it was missing,
  which is what licenses it to keep declining the framework set; Glossy Touch and
  Compact Pointer no longer decline it. `tests/icon_coverage.spec.luau` fails a
  package that leaves any control-requested name on the ASCII floor, which stays
  an engine recovery path. `tools/upload_icons.py --theme` uploads a theme
  package's own art headlessly.
- Picker visual round (2026-09-11). The segmented style is one plated track
  (the `control` surface every package skins) holding equal pill segments with
  the bar sliding beneath them; a segment carries a label only — a described
  option is refused on a declared segmented picker and steers the automatic
  ladder to a row form; the ladder also estimates the band from facts (glyph
  count x the text size the preference and the ten-foot scale make, plus the
  theme's padding) against the control's own measured offer and falls to
  inline/menu when a pill would not fit. The menu popover hugs its widest row
  between the trigger's width and the safe width, hangs from the visible
  trailing edge (a plain touch trigger's chevron) with an `xs` gap, keeps the
  screen's content inset, grows out of the corner it hangs at, and the trigger
  stays selected while it is open. `presentAnchored` gains `anchor.margin`; a
  transition gains `pivot`; Menu popovers take the same gap and margin. The
  overflow sweep now runs the largest text preference at the widest viewport
  under every shipped package as well as at the narrowest.

- Performance: a scale-only presentation transform write (every frame of a
  `materialize` transition, every animated scale) re-applies the written node
  only; the subtree is walked only when the offset half moved. Headless, the
  picker menu open/close scene halves (3.1 -> 1.4 ms) and the radial menu
  open/close drops 14%. `tests/presentation_transform_subtree.spec.luau` pins
  the rule in both adapters.
- Performance lab: a nineteenth workload, `transient-surfaces` (alert present,
  picker menu open, radial menu open), with fixtures shared by the headless
  scenes `alert-present-dismiss`, `picker-menu-open-close`,
  `picker-segmented-textsize` and `radial-menu-open-close`. Seven trend budgets
  tightened after earlier improvements; none loosened. The round's numbers and
  booked levers: `docs/plans/2026-09-11-perf-round.md`.
- Picker gains `style` — `automatic` (default), `menu`, `segmented`, `inline`,
  `radioGroup`, `navigationLink` — the reference platform's picker styles over
  one selection model. The automatic style resolves from published facts: a
  nearby touch or pointer surface gets the menu family (one integrated trigger
  carrying the value and an up/down chevron, the options anchored to it with a
  materialize transition, the current value focused and check-marked, no Cancel
  row; a titled picker is a form row that stacks at accessibility text sizes;
  a gamepad or a long list on a compact or touch surface presents a sheet); a
  ten-foot display gets a focus-navigable strip; a nearby gamepad keeps a short
  strip and folds a long list, or any list on a compact screen, into the menu.
  A searchable list (`query`) is the navigation link. `presentation` is the
  deprecated spelling of `style` (`radio` reads as `radioGroup`), declared in
  `DEPRECATIONS`; `Picker.resolveStyle(facts)` is the pure ladder.
- `Controls.PopupButton` / `newPopupButton` are deprecated (removal no earlier
  than 0.12.0): the popup engine moved to `src/controls/picker_menu.luau` and
  both names build on it. Migrate a value to a `Picker` menu style, a searchable
  list to `navigationLink` with `query`, and a `selectedValues` set to a `Menu`
  with `checked` items.
- SplitButton is one button with a long-press menu under touch and a joined
  edge-to-edge split under a pointer or gamepad; the forms follow the live
  interaction class. `dump().form` reports which is on screen.
- New framework icon `chevron.up.chevron.down` (the pop-up button's stacked
  pair), generated and uploaded with the standard set; the menu row recipe
  gains the check-only `mark` indicator.
- Showcase: Choices and filters is built on the Picker's styles (radio group,
  segmented, the automatic form-row menu, a searchable navigation link) and a
  checked `Menu` for filters; the section switch and the Actions and menus idiom
  switch declare `segmented`. The Cartwheel reference app's sort, axis and
  ingredient popups are Pickers.
- Alert actions follow the platform alert rules instead of author order: the
  cancel action leads a row and closes a stack; a stack (full-width buttons) is
  used with more than two actions, on compact widths, on ten-foot displays and at
  accessibility text sizes. The action region is one keyed `AdaptiveStack`, so a
  live width/distance/text flip moves the mounted buttons rather than remounting
  them. Alert accepts `env` like the other adaptive controls. Action paths are now
  `…/Card/Actions/Order/[<id>]/<id>`.
- Directional search inside inferred layout groups shares the section scorer
  (one beam/distance rule, not two copies).

- A node that declares a surface is no longer given a theme package's control
  decoration by its class. A `Button` or `Toggle` declaring `surface = "base"`
  or `"scrim"` fell through to the class map and was skinned as a control —
  plate, corner and, under a package with depth, the control slot's shadow,
  which reaches outside the node and painted onto whatever sat next to it. Every
  other declared surface already decided the slot; the class map now answers
  only for a node that declared none. A node carrying a `selected` prop still
  reaches the selection slot whatever surface it declared.
- A virtualized list or grid's full-bleed row hit target no longer takes a
  control surface when it paints no selection. It carried no label, no icon and
  no image, yet wore the installed theme package's control plate, corner,
  gradient and shadow — and since rows sit back to back, that shadow painted as
  far into the neighbouring rows as the package's `chromeBleed` reaches. A list
  that paints selection keeps the surface its selected row is drawn with, so
  selection treatment is unchanged.
- Add Controls.Alert for content-sized confirmations, adaptive action rows,
  presentation/data/error bindings, safe cancel focus, icons, severity and an
  optional suppression choice. Showcase confirmations and Delete Save use it.
- Adaptable tabs retain a complete TV tab strip across destination changes and
  use a shared sidebar/body gap. Distant viewing changes navigation placement
  even with mouse input; Actions and menus reflows its content sections.
- Measure capped hugging containers at their declared width limit so wrapped
  text contributes its full height before actions are placed. Hugging scroll
  containers also reserve the leading space their themed shadows require.
- Match integer fill allocation during measurement and arrangement, preventing
  aspect images from exceeding their measured columns by a pixel.
- Let pointer zones inside native scrolling containers pass touch scrolling
  through while retaining horizontal swipe gestures and their normal input capture.
- Release completed press-only scale modifiers so native themed shadows return
  after taps, including the first row after changing List and VList modes.
- Release unread-marker bindings when Row Actions List and VList rows unmount.
- Keep the virtualized table toolbar scrollable on narrow phones with large
  text; remove its resolved themed-overflow waiver.
- Remove the forced line break in the Journey details “Travel light” heading.

- Framed image geometry commits no longer reread or rewrite unchanged native
  paint. Origin-only moves preserve the crop, while source, theme and modifier
  changes retain their existing synchronization. Performance Lab now includes
  the same 24-image adaptive navigation inventory used by the headless bench.

- Keep adaptable navigation controls and their ScrollView mounted across nearby
  top/sidebar changes. ScrollView axis now accepts a readable value and updates
  directional navigation and active named travel without restoring cancelled focus.
  Scan presentation-path separators directly instead of visiting each character.

- Navigation performance: rendering and input share a live path lookup that skips
  unrelated subtrees. Buttons without a possible busy state omit progress regions
  and their reactive state; declared busy buttons retain their spinner behavior.
  The one-time input binding registry no longer strongly retains retired control
  bundles, while reusable blueprints keep their once-only binding behavior.

- Adaptive follow-up: explicit scroll-to-focus arrival and removed-target visibility exits;
  opt-in content shoulder paging, bounded value hold-repeat, and layered Table edit Back.
  Navigation flow now demonstrates adaptive search with query/focus restoration.
  Theme navigation chrome keeps ornate capsules light. Completed partial feedback
  no longer causes a redundant next-refresh layout pass. Agent guidance applies
  the Facet-first implementation order to layouts and controls.

- Narrow nonstructural geometry feedback to its changed subtree, preserving full-layout fallbacks. Cache selection-indicator geometry by structural/layout changes, pair reordered identities with their measured rectangles, and remove image-button focus polling from idle refreshes. Sidebar commands retain focus when the effective navigation placement does not change.

- Fit radial label height as well as width inside thin rings; measure compact icons against their actual padding so ten-foot action and navigation artwork remains usable.

- `UI.Image.imageFraming` adds source focal-point crop, fit, stretch, unscaled
  pixels and an explicit scale multiplier through the existing image/background
  path. Reactive framing is paint-only. Game-authoring guidance now calls for
  game-specific themes, real icon artwork and deliberate background framing.

- Add opt-in `TabView.style = "sidebarAdaptable"`: tablet toggle, pointer sidebar, distant-screen collapsed destination pill, and stable page identity when navigation moves.
- Picker/TabView badges reuse measured, wrapping row content so image-backed counts do not cover labels; `onAccent` tint keeps custom selected labels paired with the theme palette.
- Extend existing `Controls.Button` with image, aspect ratio, and subtitle content; reserve padded focus enlargement space, animate lift with the shared interruptible motion clock, and coordinate image highlight with persistent captions. Reduced motion retains the ring without lift.
- Use single-panel automatic gamepad menu hierarchies. Update the Showcase, agent/control-selection guidance, ornate-theme checks, and the 24-card adaptive-navigation performance workload.

- Navigate inferred nested layouts using resting geometry, including bound stack-axis changes; preserve declared grid, virtual collection, and radial topology.
- Add `viewingDistance` (automatic/near/ten-foot) and `distanceProfileSource`, with a Showcase setting. Explicit distance applies across typography, metrics, density, focus, and safe areas independently of controller connection.
- Restore valid tab focus paths on navigation entry without retaining tab content; `TabView.restoreFocus = false` allows a fresh task entry. Long automatic gamepad menus and popups use the existing sheet presentation.
- Keep Pixel Quest selection ornaments inside their content reservation; wrap the existing Showcase action row when theme or text needs more room.
- Bound held-navigation catch-up to three steps per frame. Expand controller and Pixel Quest theme verification to nearby handheld screens.

- Round native presentation offsets and size deltas before writing pixel geometry, removing the final pixel snap when Showcase animations settle.

- Blend focal launchers back in on the radial exit clock, including interrupted closing; hand off lists without overlapping rows. Measure navigation arcs against the themed icon square so large Close artwork stays inside its plate. Fit custom compact images against their actual rendered rectangle, including responsive image fallback. Keep explicit image content visible when a composite suppresses its theme plate, without borrowing the plate’s shadow.
- Give Pixel Quest, Compact Pointer, and Glossy Touch the actual tinted search image while preserving their other glyph choices. Expand world-anchor design guidance for proximity actions and choosing between object, corner, and single-action UI.

- Change unpublished `client.world_anchor.padding` from pixel spacing (default 12) to a relative radius fraction from 0 to 1 (default 0.15). Remove its pixel `minimumRadius` option; use RadialMenu’s theme-based `clearance` for a minimum opening. Existing pixel padding callers must migrate to a fraction.

- Preserve runtime native theme sheets across character respawns in a shared, non-rendering ScreenGui with `ResetOnSpawn = false`. This fixes lost styling after revisiting the Quick actions Item scene.

- Add public `client.world_anchor` for Part, Model, and avatar bounds projected into radial anchor/clearance data on the host frame. Radial menus follow measured radius, freeze it during selection, and support `launcher = false` and `api.isVisible` for proximity prompts without overlapping launchers. Add the real-world Item example to Quick actions.

- Preserve themed circular launcher borders outside their animation content bounds. Measure radial preview space and compact bands around fixed clearance so the Fantasy Ornate character ring fits small portrait offers.
- Keep the corner navigation disc visible through dismissal, crossfading Back/Close into the launcher icon and smoothly returning to its size; support reopening during retirement.
- Compact radial geometry before choosing a list on small landscape surfaces, preserving minimum touch targets, directions, and explicit focal clearance.
- Keep radial opening/closing centered on its launcher or focal anchor through the presentation offset channel, including all four corners and interrupted animations.

- Add `UI.Button.focusVisual` for composed controls that paint their own focus treatment; radial selection highlights the outer circle/wedge while image-only buttons retain the content outline.
- Center radial compact representations and use semantic navigation icons. Animate opening/closing rings in one coordinate space; fade list fallback fully before restoring its launcher.

- Allocate radial list rows at their themed button height so adjacent rows cannot cover the keyboard focus outline; use standard list navigation to scroll the focused row into view.
- Inset focus rings beneath any clipping ancestor, including scroll containers beyond an intermediate layout or motion host.
- Keep the native scaling pivot at an explicit settled scale of one, removing a final-frame pixel snap while preserving scale cleanup when the transform clears.
- Refine radial menus with single list navigation, closed arc borders, image-only button surfaces, concurrent parent-origin submenu motion, and a four-corner Showcase selector. Add control-choice guidance for UI-building agents.
- Correct radial-menu touch/list activation, shared surface/content retirement and replacement transitions, centered skins/icons, ring/corner navigation, uniform slim bands, and contrasting outlines. Add direction-based gesture selection for cramped layouts.

- Add `Controls.RadialMenu`: native wedges and corner buttons, configurable content-fitted arcs (both axes by default), compact icon/text labels, mixed ring/page hierarchy, captured gestures and semantic keyboard/gamepad input. Add the curated Quick actions Showcase demo.
- Add the Path tint alpha channel via a reused UIGradient; document that CanvasGroup does not fade Path2D.
- Fix scaffold runner-signature drift and remove the type checker's stale hardcoded control count.

## [0.11.0] — not yet published

- `Controls.NavigationStack` adds a caller-owned observable route path, root and
  destination builders, push/pop/back/root operations, page scope cleanup and
  legal focus restoration through the existing presenter contribution seam.
- Navigation pages share a clipped viewport. Pure horizontal slides travel the
  stack's width, reverse on Back and preserve motion when interrupted; outgoing
  pages no longer create a second vertical layout slot. Structural transition
  declarations can be readable and are sampled on enter/exit.
- Interrupted transitions release paint channels no longer used by the next
  form, so changing a fade to a slide cannot leave content partly transparent.
- The confirmation example uses an content-sized horizontal actions with compact-label fitting, centered
  labels and a primary Cancel action with explicit initial focus.
- Search clear icons and checkbox marks are centered through the existing layout
  rules, including theme changes and larger text.
- Search fields use a tintable magnifying-glass asset in the existing `facet:search`
  icon slot. Preferred compact icons reserve their theme size, including Back.
  Selected labels keep aligned with their selection pill during ten-foot focus.
- Horizontal `firstTextBaseline` / `lastTextBaseline` alignment composes with
  nested and wrapped layouts. Theme typography supplies semantic guides; no
  engine glyph-baseline measurement is claimed.
- `UI.Spacer.minLength` adds a reactive, theme-compatible main-axis floor.
- `motion` clocks can bind numeric animation values to observable state with
  `clock:animate`, including existing theme tint blends and reduced motion.
- The default theme is **Facet Neutral**, package ID `facet-neutral`. Replace
  saved or configured `studio-neutral` identifiers with `facet-neutral`.
  The theme's colors and geometry are unchanged; its identity and content stamp
  change. `themes.neutral()` and `themes.neutralPackage()` keep their names.
- The Showcase journey demonstrates navigation, text guides and flexible gaps;
  the controls guide describes current controls and their configuration.


### Added

- **`Button.role = "onIndicator"`, the label-only role.** The other three button
  roles name a fill *and* the colour that reads on it; this one names the colour
  alone, because the plate is painted by something behind the button — an accent
  surface such as Facet's own sliding selection indicator. Its rule is
  `TextColor3 = $OnAccent`, the theme contract's one gated partner for `$Accent`,
  and it brings no background, so the chip it sits on is still the only plate on
  screen. See [api.md — semantic roles](docs/reference/api.md#button).
- **`enabled` and `tint` on the layout containers, where they apply to the whole
  subtree.** `enabled = false` on a `Screen`, stack, `ScrollView`, `Grid`,
  `Anchor`, `AdaptiveStack` or `Composition` disables everything under it: every
  descendant leaves focus order — both derivations, the linear one Tab walks and
  the directional one the arrows and the pad walk — refuses Activate on every
  input class, and takes no pointer, touch, drag or secondary action. `tint` on
  the same containers is the continuous colour their subtree paints with. Both are
  reactive, and a change re-solves in place rather than rebuilding.
  See [Inherited properties](docs/reference/api.md#inherited-properties-enabled-and-tint).
- **A themed disabled state, `facet-state-disabled`**, and what it paints is
  exactly one rule. The engine's `:NonInteractable` state exists only on the
  classes it considers interactable, so Facet Neutral and every theme package
  emit `Disabled subtree text`: a `TextLabel` carrying the tag is dimmed to that
  theme's own `disabledContentOpacity`. **Text only** — image paint is legal in a
  theme rule only inside a nineSlice chrome recipe — and the tag reaches the four
  classes that consume it (`Button`, `Toggle`, `TextField`, `Text`) rather than
  every node, because writing to a container the renderer had elided materializes
  it permanently. A `tint` that declares its own `transparency` claims that
  property and outranks the dim. A presented surface (modal, toast, menu, popover,
  anchored sheet) is its own root and inherits neither channel. All four limits
  are stated in [api.md](docs/reference/api.md#inherited-properties-enabled-and-tint).
- **A Roblox Package distribution channel.** Facet is now published as one Roblox
  Package asset, which is the recommended install for creators who work in Studio
  without a file sync. The asset id does not exist yet; it is recorded in
  `package/facet-package.json` when the asset is created, and the maintainer
  interface is `tools/package.sh` with [`package/README.md`](package/README.md) as
  its reference.
  Installing, updating, and version checking are described in
  [guide 8](docs/guide/08-without-rojo.md).
- **A standalone consumer project**, `examples/consumer/`, that builds the
  five-minute screen from the public API alone and is proved headlessly by
  `tests/consumer_standalone.spec.luau`.
- **Public project files**: `LICENSE`, `THIRD_PARTY_NOTICES.md`, this changelog,
  [`CONTRIBUTING.md`](CONTRIBUTING.md), [`SECURITY.md`](SECURITY.md),
  [`AGENTS.md`](AGENTS.md), a `skills/use-facet/` skill, and continuous
  integration plus issue and pull-request templates under `.github/`.

### Fixed

- **An authored hide that moves during a solve now lands on the next drain.** A
  `hidden` flip made from inside the presenter's geometry feed was swallowed
  for the life of the surface, so a segmented `Picker`'s selection indicator
  never painted until a real slide ticked. The renderer now forces the solve
  that owes the walk when the re-read value actually moved.
- **A `UI.Path`'s stroke is born at, and follows, its node's paint order, and its
  geometry is uploaded once.** The screen target never gave a `Path2D` its
  `ZIndex` and re-sent unchanged control points on every rect write.

### Changed

- **A segmented `Picker`'s selected option is readable on its own chip.** The
  sliding pill paints `$Accent` behind the option; the option's label kept
  `$Content`, the colour chosen to read on `$Surface`, and on a package with a
  saturated accent the pair measured 1.55:1 against a 4.5 floor. The option the
  pill covers now carries `role = "onIndicator"`, so the label takes `$OnAccent`
  and travels with the selection. Nothing else about the control moves: the
  option still declares `surface = "plain"`, still carries no `selected` tag, and
  the chip is still the selection paint. The `underline` indicator is unaffected —
  it paints a tint rule on the segment's far edge, not a plate under the label.
- **`present()` refuses when `initialFocus` names a disabled control**, on every
  screen rather than only some. The flat focus derivation always refused —
  "initialFocus 'X' names no focusable on this surface", listing the ones that
  are — but a screen with horizontal structure took the grouped derivation, which
  did not exclude a disabled control at all and so presented happily with the
  ring sitting on it. The two agree now, and the error is the same one. **If you
  focus a primary action that starts disabled until a form is valid, name a
  control that is live, or use `"first"` / `"none"`.**
- **The arrows cannot cross a `Grid` row whose every cell is disabled.** A grid
  names each row group's `up`/`down` exit by index, so an emptied row is still the
  named neighbour and the move lands nowhere — everything below it is unreachable
  by the arrows and the pad. This is exactly what a fully `hidden` grid row has
  always done; what changed is that `enabled` is now inheritable, so the shape
  reaches an ordinary settings screen. **The same content as stacked `HStack` rows
  is crossed cleanly**, and `UI.When` removes the row outright. Tab is unaffected.
- **`enabled = false` now means the node AND its subtree.** On `Button`, `Toggle`
  and `TextField` the property is unchanged for a leaf; what is new is that the
  state is inherited, and that it cannot be undone from below — an ancestor never
  re-enables a node that declares `enabled = false`, and a descendant never
  re-enables itself inside a disabled container. A focusable `Grip` inside a
  disabled subtree now leaves focus order too, which it did not before: `Grip`
  carries no `enabled` of its own, so nothing had ever asked the question for it.
  A `Button` is a container, so **a disabled button's custom content is now
  disabled with it** — its own children wear the theme's disabled state instead
  of keeping full contrast beside a plate the engine had already dimmed.
- **Facet is licensed under the MIT License.** Material this repository did not
  create is listed with its own notice in
  [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
- **Verification runs in four named tiers** — affected, fast, full, and release —
  through one command, `tools/verify.sh`. An ordinary change runs affected or
  fast; a change about to merge runs full; a release runs the release tier.
  `./run-tests.sh` and `./run-tests.sh --fast` still work and still mean the same
  thing.
- **The public documentation was refreshed end to end**: the README, the guide
  index and capability catalog, installation and upgrade instructions, the
  extension playbooks, and every link that pointed at internal material.

### Removed

- **The vendored copy of another reactive library, and its adapter.** Both were
  bake-off arms kept from the comparison that chose Facet's own core; neither
  ever shipped in Facet's runtime, model, or Package. Facet's reactive core is
  and remains its own, in `src/core/`.

## [0.10.0] — not yet published

The version this tree reports as `Facet.VERSION`. It has not been published, so
the deprecation window begins at its first release. Until then the register below
is the record of every behavior change riding this version. Recording the change
is what makes a breaking change legal before a version's first publish
([`CONTRIBUTING.md` §6](CONTRIBUTING.md#6-versioning-and-deprecation)).

### Added

- `Facet.Controls`, a frozen namespace of typed control constructors called as
  `Facet.Controls.<Name>(core, spec)`. Every older `Facet.new<Name>(Facet, core,
  spec)` builder still works and is listed in `Facet.DEPRECATIONS`.
- The world-fixed surface render target, `client.surface_target`: the same flat
  two-dimensional Facet screen on a `SurfaceGui` a player walks up to. It is a
  flat world target, not a spatial one — geometry in front of it blocks input,
  and it pins `AlwaysOnTop = false` so that stays true.

### Changed

- **Adaptation answers for itself.** Controls that need device facts and cannot
  find an environment now refuse to construct instead of quietly assuming a
  large screen with a pointer. A `UI.Grid` given neither `columns` nor
  `minColumnWidth` lanes itself from the box it was given, and
  `UI.AdaptiveStack` requires its `axis`.
- **The ten-foot display class scales type, theme metrics, and paint**, so a
  screen written the ordinary way is legible on a television.
- **Roblox `StyleSheet` paint is the default render path** rather than an opt-in.
- The library is named Facet, and its call shapes moved with the name.

### Behavior changes riding this unreleased version

Each row names the surface, what it did before, what it does now, and why the
move breaks a caller. A change to what the library promises is landed by adding
its row here in the same commit.

1. `UI.AdaptiveStack.axis` was optional and defaulted to `"y"`; it is now
   **required**. A bare `UI.AdaptiveStack{…}` was a permanent vertical stack and
   now raises at construction.
2. `UI.Grid` given neither `columns` nor `minColumnWidth` laid out one lane at
   every width; it now lanes itself from the box it was given
   (`minColumnWidth = "intrinsic"`). A bare grid silently re-lays out: the same
   six cards go from one column to two, four, six, nine, five, or seven across
   the audited viewport combinations.
3. `newPicker`, `newMenu`, `newPopupButton`, `newTabView`, `newTextInput`, and
   `newVirtualList` with `itemExtent = "cards"` each **refuse to construct** when
   no environment can be found. Each previously substituted the large-screen,
   near-distance, no-cutout answer in silence. The refusal replaced wrong
   behavior rather than working behavior: zero of the seventeen shipped `Picker`
   sites had reached the adaptive default.
4. `adaptive.navPlacement` on a tablet answered `bottomBar` and now answers
   `topBar`. A documented policy answers differently for a real device class;
   six shipped assertions were re-pinned because they had asserted the defect.
5. `adaptive.columnsFor` at the ten-foot distance was uncapped and is now capped
   against the wide breakpoint, so a television gets fewer columns than a desktop
   where it used to get more.
6. Unauthored text on a `Large` display scaled only at its authored size; the
   whole type ladder now scales by 1.5. Every screen written the natural way is
   1.5 times larger on a television.
7. Every theme metric on a `Large` display was unscaled and is now scaled by the
   type floor's own factor, so control heights, spacing, icon sizes and the 44px
   hit floor all move on a television.
8. `UI.Composition`'s content lane at the ten-foot distance took an uncapped
   share and is now capped at the lane measure times the metric scale (900px). A
   shipped composition re-measures on a television and nowhere else.
9. `newTable` narrower than its columns clipped; it now **collapses** a column by
   priority and discloses it. Shipped tables re-lay out at the compact size
   class, and a `fill` column's `minWidth` is honored — one playlist column went
   from 30px to 66px.
10. `newTable` selection and edit-mode keys had no modifier semantics: an arrow
    key replaced the selection. Control or Command now moves without selecting,
    Shift extends, and on a table with no `onPrimaryAction` a device Activate
    toggles.
11. A horizontal `UI.ScrollView`'s focus ring ran vertically and now runs
    **horizontally**: Left and Right step the rail, Up and Down leave it. That is
    the opposite of what shipped.
12. `newTabView` and `newPicker` band placement parked in the band's corner and
    are now centred in it. Shipped geometry moves on three placements.
13. The library's own name and call shapes changed: the require path is `Facet`,
    and `Facet.newTable(Facet, core, spec)` became
    `Facet.Controls.Table(core, spec)`. Nineteen call shapes moved; every old
    builder still works and is in the deprecation ledger.
14. The gallery example's `showcase_chrome.TOGGLE_GAMEPAD` was `"ButtonY"` and is
    **removed**. The showcase chrome bound the gamepad toggle to `ButtonY`, which
    is `newMenu`'s own gamepad trigger, so one press opened both. `ButtonY`
    belongs to the menu verb; the pad reaches the chrome through the two shoulder
    buttons instead. This is an example's export rather than a library surface,
    and it is recorded because a consumer copying the showcase's key map is
    exactly who this register is for.
15. `native_style.DEFAULT_ENABLED`, the library's default paint path, was opt-in
    (`false`) and is now default-on (`true`): a `screen_target.new({})` carrying
    no `nativeStyle` option paints through a Roblox `StyleSheet`. Every screen
    target that never named a paint path changes painter. Sheet rules and the
    `::UICorner` and `::UIStroke` modifiers replace the adapter's per-property
    writes, so no `UICorner` or `UIStroke` instance exists under a Facet root any
    more and a consumer reading those instances back finds nothing; the Style
    Editor becomes the paint authority for anyone who opens the place. The two
    paths were measured byte-equal on every mapped property, so the pixels are
    the same and the mechanism is what moved — which is exactly the kind of
    change a consumer's own code touches and a screenshot does not. The escape
    hatch is unchanged and still wins over everything: an explicit
    `nativeStyle = false` keeps the explicit-write path, which stays a
    first-class tested path rather than a corpse.
16. `UI.Region{ expand }` on a form that carries no control of its own
    synthesized a chevron beside the form; it now synthesizes a **cover** over
    the whole form. A passive compact form draws no mark at all and the whole of
    it becomes the tap or Activate target at the standard hit floor, where it
    used to draw a caret in a column the form's own measure reserved. Shipped
    geometry moves: the form gets the mark's column back — one demo's clock zone
    went from 100px to 80px at 360x691 — so a value that was being cut may now
    fit and a screen tuned against the reserved width re-lays out. The cover
    declares `zIndex = -1`, so it and the hit expander banded below it paint
    under every form within its own region. `UI.Foreign` and the lazy regions
    still force the chevron.
17. Corner radii and hairline strokes now scale with the metric ladder at the
    ten-foot display class, derived from the same metric scale so a later scale
    change moves them in lockstep. A radius rounds to a whole pixel because a
    `UDim` offset is an integer; a stroke keeps its fraction because thickness is
    a float. At a scale of 1.5: 12 becomes 18, 8 becomes 12, and 1 becomes 1.5.
    The capsule sentinel scales from 999 to 1499 and paints identically for every
    box up to 1998px on its shorter side. A theme package's ten-foot metrics may
    name a paint path and win on both sides. Near-distance density is
    byte-identical.
18. `UI.Region{ expand }`'s plate-or-sheet selection, and the resolved
    `plate.max`, were measured against the gutter allowance and are now measured
    against **the allowance minus the plate's own chrome** (at a 390px viewport,
    358 becomes 342). A form whose natural width lands in the last few pixels of
    the allowance now falls back to the full-width sheet instead of mounting an
    anchored panel that was wider than the allowance it had just been chosen
    against — reproduced at 390px, where a 320px form gave a 358px cap and a
    380px panel. No shipped screen moves today, which is exactly why the row is
    owed: the next reader tuning a form against the allowance has no other way to
    learn the band exists.
19. The hit expander a `role = "cover"` affordance receives inflated the solved
    rect by 44px unconditionally; it now **grows one side at a time, and each
    side stops at the first rect outside it that can sink a press**. Boxed in on
    every side it retracts, and the affordance is reached through the region's own
    box. A cover is its region's whole box, so the old floor took presses from
    neighbours: measured at 390x150, 960 square pixels of one neighbouring button
    and 828 of another — 26% of each — were delivered to the plate instead of the
    button the player aimed at. Only rects the author declared stop a floor: a
    framework affordance may not take the accessibility floor off another one. Of
    381 swept routes, 38 end below the effective floor and every one is cut by an
    author node; the smallest route is 35px and 31 covers retract.
20. `newPicker`'s activation order is now **one transaction** around both the
    control's own write to `selected` and the `onChange` it then calls. It used
    to be two turns: the write flushed on its own before the callback ran. A caller
    may redirect or veto a pick from inside `onChange` by writing the signal
    back, and until now the value it was about to undo was published first: every
    observer of `selected` saw it, and a `UI.When` over the selection mounted a
    whole subtree and evicted it in the same frame. An observer that counted
    selection changes now sees fewer of them, and an `onChange` inherits a
    transaction body's obligation not to yield. A read is unaffected: a
    transaction defers the flush, never a read.
21. `newTabView` with a declared `sizing = "hug"` at `bottomBar` now gets the same
    **centred scroller** every other hugging home gets. It used to park the strip
    at the band's leading edge in a stack that could not scroll.
    The thumb-zone band is deliberately not a scroller because a
    `fill` strip divides the offer and has nothing to overflow with — a statement
    about the default that the code was applying to the home, so a caller who
    declared `hug` there got natural-width segments at the leading edge and a
    strip wider than the phone simply ran off it. The `fill` default is
    untouched.
22. `Facet.text.fit` and `Facet.text.size` decided a size "fits" when the wrapped
    form stayed inside `lines` (and `height` when given); the widest line must now
    also stay inside `width`. A single word has no legal break, so the wrapper
    reported one natural line at every size however far past the box the glyphs
    ran, and the function handed back the cap for a string that does not fit at
    all. For a multi-word phrase nothing moves, except the one case where it
    should not have: a phrase whose longest word is wider than the box, which the
    engine breaks mid-word and paints outside the column.
23. A `hug` dimension on a `UI.ViewThatFits` **candidate** was measured at the
    minimum of content and offer, like every other `hug`, so the width test was
    true at every width. It is now resolved as content, uncapped, for the
    duration of the fit probe; the author's own `min` and `max` still bind, and
    the winning candidate is capped by its offer exactly as before. A `hug`
    candidate could never report "does not fit", so the ladder pinned its first
    rung forever and the labels it exists to protect truncated anyway. Refusing
    `hug` at construction was rejected: a control that picks `hug` for itself
    would have been refused for a spelling its author never wrote.
24. A `topbar` region under `rootPolicy = "bandSafeContent"` was a row spanning
    the composition's full width, as tall as its own content. It is now laid into
    the platform's own free strip — that strip's x and width, reaching its bottom
    edge — and the lane band below it is floored at the platform's whole top
    reservation. The tenth zone is the one that is not an anchor, and its purpose
    is to sit level with the platform's own controls; until now its geometry was
    the consumer's, held open with spacers and a memo. A caller that declares a
    `topbar` region now gets a row whose x, width and height are all platform
    facts, so a hand-computed spacer beside it is a double reservation. Two
    further consequences: a span row's slack now goes to its `fill` regions, which
    is what lets a region centre in the strip rather than sit at the top of it;
    and the lane band's floor is the platform's whole reservation rather than the
    band's bottom edge, except for a composition that both rides the strip and
    declares `exclusions`, which has already said where its own chrome is per
    column and gets the platform's own row instead of the bounding box. A
    composition that declares no `topbar` region resolves exactly as
    `deviceSafeContent` would have resolved it.
25. The gallery's grid scenarios forced their cell and line gaps to `"xs"` (4px)
    at Facet Neutral, because no space step named 6. They are restored to
    `"tight"` (6px), the value both fixtures originally wanted, now that
    `space.tight` exists as a derived step naming the value halfway between `xs`
    and `s`. Both grids' rendered gutters grow from 4px to 6px in the shipped
    gallery: a deliberate value change, not a value-identical rewrite.
26. Two gallery viewports carried literal pixel heights (150 and 120, each a
    hand-guessed "roughly N rows with the next one peeking through"). They are
    now content-terms formulas — four rows of the compact control height (144px),
    and six lines (116px). Both render 6px and 4px shorter at Facet Neutral, in
    the safe direction for a viewport: the old 150 never held four full rows
    either, since the rows are 46px each. What actually changes is that both now
    grow at the ten-foot ladder and at a raised text preference, where the frozen
    literals never did: 144 becomes 216, and 116 becomes 173.
27. Under `rootPolicy = "bandSafeContent"` with both a declared `topbar` region
    and declared `exclusions`, the lane band used to start at the topbar row's own
    measured height with no platform-reservation floor under it whenever the
    platform band was absent. It now falls back to the same reservation the
    no-exclusions path already used. The platform band really is absent on a live
    device, both at boot before the first platform push and on a measured
    rotation-recovery frame, so this was a real lane-and-topbar overlap risk
    rather than a headless-only one.
28. The expand plate's close disc used a spacing step (`space.xs`) for its corner
    inset, which had no relationship to the focus ring it exists to clear. It now
    uses the larger of that step and the ring's own inset. Every package whose
    spacing already cleared the ring gets the identical inset back; the two
    packages that were short move from 3px to 4px at the ten-foot ladder, closing
    a measured 1px overrun by construction rather than by a named ratchet.
29. `surface = "badge"` had no intrinsic size at all — a bare glyph hugging its
    own pixels, or an empty zero-sized box. It now carries a theme-owned minimum
    (20px at Facet Neutral, scaling at the ten-foot ladder like every other
    control metric) on both axes when the author declared neither `width` nor
    `height`.
30. Two gallery motion fixtures sized their lane and puck with a raw 40, unscaled
    at every display class. Both now use the theme-owned decorative-chrome floor:
    identical 40 at Facet Neutral and Medium, and 60 at the ten-foot class — the
    first scaling either box has ever had. Both render 20px larger there, in the
    safe direction.
31. `UI.Composition{ exclusions }` shared a lane's slack out as the lane's budget
    without the chrome row, rather than as the lane's own already-inset height.
    An `end`-placed group landed exactly the give-way inset past the bottom of its
    own lane, a `center`-placed one half of it, a numeric placement a matching
    fraction of it, and a `fill` group took the same phantom pixels as height.
    Measured one-for-one from a 1px inset to a 300px one, and seen live at 141px
    on a console and 54px on a phone. It is a defect fix that restores the
    partition guarantee, and shipped geometry moves for every consumer that
    declares `exclusions`.
32. The themed-chrome family changed in four places. An inset was spent whenever
    any pixels remained; it is now spent only when the node's own line box still
    fits — a text-bearing leaf needs more than its text size, everything else is
    unchanged — on both the measure and the paint seam. A sibling plate's border
    is no longer spent twice. The pill selection indicator's inset is reduced by
    the plate slot's carved border. Shipped geometry moves under every package
    that carves a border: an ornate disc loses the frame it was reserving twice
    (60px becomes 52px under one package, 44px becomes 38px under another), and
    every pill indicator covers its whole segment rather than an inset chip.
    Facet Neutral and every flat package are byte-identical, because their carve
    insets are all zero.
33. `newMenu`'s automatic presentation at a **compact** size class with a
    pointer-primary interaction class resolved to its own answer, gated on live
    touch plus an item count; it is now forced to the sheet presentation whenever
    the size class is compact, unconditionally. A documented policy answered
    differently for a real, reachable environment — a compact width with no touch
    signal, which is a phone with a mouse, or Studio's own compact preset, which
    cannot inject touch at all. Every submenu now replaces the panel in place with
    a Back row instead of floating a second panel over a parent that does not have
    room for it. The regular and wide classes are unaffected, and an
    author-forced presentation is unaffected at any width.
34. `distanceProfile`, `typographyScale`, `typographyPaintScale`, `themeMetrics`,
    `sizeClass` and `effectiveOverscanInsets` resolved from the raw `displaySize`
    and now resolve from the derived `effectiveDisplaySize`, which downgrades
    `"Large"` to `"Medium"` when the session is touch-capable. On a
    `"Large"`-reporting, touch-capable session the ten-foot type and metric scale,
    the density cap and the console overscan margins now read off, 1, uncapped
    and zero, where they used to read on, 1.5, capped and 60 to 90px.
35. Under `scrollIndicatorPolicy = "auto"`, the solver's scroll-bar reserve was
    policy-blind: `"always"` and `"auto"` reserved the same thickness. It is
    policy-driven again. `"always"` is unchanged; `"auto"` now publishes zero, so
    content measures to the full cross-axis width instead of the width minus the
    bar. Content that used to stop 8px short of the scroller's own edge now runs
    to the full edge. A bare zero reserve alone would reproduce an older defect,
    because Roblox narrows a `ScrollingFrame`'s window by the bar's thickness
    whenever the scroll axis overflows regardless of paint policy — measured
    again this round, and a fully transparent bar image does not stop it — so the
    zero reserve is paired with widening the scroll host's own frame by the same
    thickness on the cross axis while it overflows. The overlap is the bar sitting
    in that borrowed space.
36. The float focus ring a focusable control draws inside a clipping or scrolling
    host read its corner radius from the target's construction-time style, which
    no theme swap ever reassigns; it now prefers the live theme snapshot's radii
    and falls back to the construction-time style only while no package is
    installed. The corner was also built only on first creation and is now
    re-synced on every focus-visual call, so a live swap's repaint reaches it. A
    focused control's ring corner moves under any installed package whose control
    or panel radius differs from the target's boot radius, on the first focus
    after a swap. With no package installed at all it is byte-identical.
37. Every badge overlay in the repository — the segmented picker's count seal and
    the gallery's hand-rolled tile badge, two independent implementations — was
    anchored flush at the raw corner under every package. Each now insets top and
    right by the theme's carved border for its slot, through one shared
    primitive rather than the same four-line loop written by hand three times.
    Shipped geometry moves under any package that carves a control or accent
    border; flat and Facet Neutral packages are byte-identical, because the
    computed inset is zero on both axes.
38. Every `UI.Path` wrote its normalized control points as pixel offsets and now
    writes them as scale. A `UDim` offset is a 32-bit integer — measured live on a
    round trip, `UDim2.new(0, 25.05, 0, 6.95)` reads back as 25 and 6, while the
    same pair survives to six decimals as scale — so every control point was
    truncated to a whole pixel. A 32px progress ring lost 0.8px at its 3 and 6
    o'clock extremes and 0.2px at 12 and 9, painting as an off-centre egg, and a
    closed ring's last point floored to 15 where its identical first point floored
    to 16, so the track closed one pixel left of where it opened. Separately, the
    showcase's glass plates now declare their own surface role and take the
    caller's gutter through one shared inset memo, instead of painting a raised
    box behind a sibling that wrote its own gutter.
39. The layout reserve every native scroll host spends under
    `scrollIndicatorPolicy = "always"` was exactly the bar instance's thickness
    (8px) and is now that thickness plus a one-pixel gutter (9px). The bar
    instance itself is untouched at 8px, and so is the engine's own window
    narrowing, which is what makes the extra pixel visible rather than painted
    over. Every overflowing `"always"` scroll host lays its content out 1px
    narrower on the cross axis, and the gutter a sibling pays — a table header
    aligning with its body — grows from 8 to 9 on the right for a vertical
    scroller and on the bottom for a horizontal one. `"auto"` is untouched: it
    reserves zero and deliberately overlaps. The earlier round had already
    measured that this boundary was not an overlap; the ruling is that
    exact-and-flush is the defect, because content on the bar's outermost pixel
    reads as a collision.

## Earlier versions

Versions 0.4.0 through 0.9.0 predate this file. Their public surfaces are
documented in [`docs/reference/api.md`](docs/reference/api.md), and the retiring
ones are listed with the version that may remove them in `Facet.DEPRECATIONS`.

### Unreleased — game navigation continuity

- Keep client input contexts in stable client-created storage; entering Table rows from a focus section works in normal and edit modes. Showcase unread markers use bounded vector paint so ornate panel decorations cannot spill across their rows.

- Add semantic row presentations to Button, Toggle and Slider, declarative focus
  sections, and named ScrollView targets with shared snap/motion and visibility/progress.
- Restore TabView scroll positions by stable descendant/item key, including virtual
  lists, grids and tables; preserve lazy page disposal.
- Add optional tab sections and caller-owned order/visibility customization, with
  animated selection indicators that follow changing keyed options.
- Extend Showcase game-art/row/navigation examples, theme containment checks and the
  adaptive navigation performance scene. Document when agents should choose each.
