# Rich skinning v2 — fully image-driven UI

**Date:** 2026-07-25 · **Status:** Proposed (director direction from the Step 3.5 TP-P3
review). Builds on the shipped theme-package contract (ADR-0019); nothing here reopens it.

## Why (the director's brief, in plain words)

In a heavily stylized game — a fantasy RPG, a pixel-art game — a team may want
**every visible part of the UI to be artwork**: frames with corner ornaments and
title plaques, health bars whose track AND fill are images, sliders with carved
rails and jeweled thumbs, item slots, and buttons whose *selected* look is a
different picture entirely, not a tint. v1 proved the plumbing (packages, swaps,
nine-slice, insets, fallbacks); v2 makes "the art IS the interface" a supported
authoring style.

Reference targets (studied 2026-07-25; described here, not copied — original art
only, per the Step 3.5 provenance discipline):

- **Elder Scrolls Online inventory** (`cdn-eso.mmoui.com/preview/pvw6473.jpg`):
  parchment list panels inside ornate metal frames; header rails with emblems;
  full-screen decorative border; scroll lists whose rows are art strips.
- **Fantasy RPG vector kit** (`shutterstock.com/...176862326`): gold-cornered
  frames where the corner pieces are distinct ornaments; ornate horizontal
  progress/cast bars with end-caps and a crown centerpiece; round jeweled
  buttons; segmented inventory grids.
- **"Wooden GUI" Roblox kit** (`devforum-uploads...acd861...png`): wood-plank
  window chrome with a title board, inner parchment cards, grid slots, book-style
  panels — the exact class a Roblox game team will build.
- **Pixel-art RPG sheet** (`img.itch.zone/.../l1Vuae.png`): everything
  nearest-neighbor crisp; bordered plaques with corner rivets; a heart-capped HP
  bar (track + fill images); menu buttons where **selection changes the whole
  style** (different plate + side ornaments), not a highlight.
- **The platform-pair sanity check (director, 2026-07-25).** One game, one view
  tree: on phone/tablet it should be able to look like **iOS 6** (glossy
  skeuomorphic: gradient nav bar, chrome slider, sliding ON/OFF switch, glossy
  segmented control, striped progress, 44px touch rows — ref
  `koenig-media.raywenderlich.com/.../Screen-Shot-2012-09-15...png`), and when
  the player moves to desktop/console it swaps to a **macOS-like** package
  (compact ~22px pointer controls, subtle button gradients + 1px shadows,
  barber-pole progress — Mavericks-light ref — or the modern dark pill style —
  Tahoe-dark ref; both `files.mastodon.social/.../60aa4d1e...` /
  `86d7de29...`). Notably the control census in these shots is almost exactly
  our fixture gallery (field, slider, toggle, segmented picker, stepper,
  progress), which is what makes this the right acceptance scenario.

## What v1 already proves (consumed, not rebuilt)

Versioned declarative packages; per-target install/swap with mount/focus/scroll
identity; the frozen metric snapshot + solver-visible insets; nine-slice slot
chrome with tag rules, state tints, fallback, census; the chrome text lift; the
Style Editor sync loop; `::UIGradient` phantoms; measured engine truths TP-M1–M9.

## The v2 capabilities

1. **The image IS the element (default posture).** A skinned node's native
   fill/corner/stroke are suppressed by generated rules (begun in the Step 3.5
   post-review fix round); recipes may declare the decoration as the ONLY paint.
2. **Layered decoration slots.** A slot recipe may declare a small bounded STACK
   of layers: `fill` (nine-slice/tile), `frame` (nine-slice above content-back),
   `corners` (four anchored ornament images), `edges` (tiled rails), `plaque`
   (a header ornament anchored to the top edge, given a text sub-slot). Layers
   are data with fixed anchoring vocabulary — never arbitrary trees. Instance
   cost stays censused; flat themes still pay zero.
3. **Per-state asset VARIANTS, not just tints (director-confirmed 2026-07-25).**
   Every interaction state the chrome state machine already publishes —
   `default / hover / pressed / selected / disabled / error` (and `focus`, which
   rides the selection slot) — may swap the layer's IMAGE, not merely tint it
   (rules already own `Image`/`ImageContent` per state — measured). This holds
   at BOTH customization rungs:
   - *Rung 1 (theme):* every image-bearing slot recipe — panel, control, field,
     selection, sliderTrack, sliderThumb, toggleTrack/toggleKnob, badge, and
     every v2 layer kind — accepts a per-state asset map. A bare string stays
     legal and means "same art in every state" (which is also the forward-compat
     story: today's single-string hints/recipes grow a table form without
     breaking).
   - *Rung 2 (per-view override):* the modifier-style props (`thumbImage`,
     button image, …) accept the same shape — a string OR
     `{ default = "...", hover = "...", disabled = "..." }` — so one special
     button can have bespoke pressed art without a theme.
   Unstated states fall back to `default` (then tint rules still apply on top),
   so authors supply exactly as much art as they have. The pixel reference's
   "selection changes style" becomes: `selected = { asset = "...",
   plusOrnaments = ... }`. Geometry stays solver-owned; a variant may declare a
   different content inset ONLY if identical across states per axis (no reflow
   on hover) — else it is a compile error. Disabled keeps its accessibility
   floor: if a variant supplies no `disabled` art, the standard disabled
   treatment still applies over `default`.
4. **Image value-displays.** Bar-family recipes: `track` + `fill` (both sliceable,
   fill clipped by percent), end-caps, optional centerpiece; slider `rail`/`thumb`
   (begun in the fix round); stepper glyph plates. The solver keeps geometry;
   the adapter clips the fill layer.
5. **Semantic icon assets (un-deferred).** A theme-scoped icon map
   (`icons.<name> -> asset`) with sizes from `iconSizes`, tint roles, fallback
   glyphs; controls request icons by semantic name.
6. **Pixel-art mode.** Package-level `rendering = "pixel"`: ResampleMode=Pixelated
   rides the rules (measured, m9), snapshot metrics snap to integer multiples of
   a declared unit, and SliceScale locks to integers.
7. **Content adoption (m9 stance).** Authored data stays plain string URIs
   (Content is NOT an attribute type; packages must stay serializable). Schema
   accepts `content` as the canonical field name (`contentId` alias kept). The
   adapter/rules may materialize `ImageContent`/`Content.fromUri`, and
   `Content.fromObject` opens EditableImage-generated skins as a stretch item.

8. **Profile-conditional package selection (the platform-pair check).** The
   MECHANISM already exists and is proven: two independent packages with
   different METRIC snapshots (44px touch rows vs ~22px pointer controls —
   metrics move geometry on swap, identity preserved) and
   `theme_controller.swapPackage` is atomic mid-session. What v1 lacks is the
   DECLARATION: today a game writes its own observer over the env facts
   (`preferredInput` / display size) and calls swap. v2 adds a one-shot rule on
   the controller — `selectBy = { touch = <pkgA>, pointer = <pkgB>, gamepad =
   <pkgB> }` (vocabulary = the input-paradigm facts we already publish, nothing
   new to detect) — so "iOS-6-like on the phone, macOS-like when docked to a
   monitor" is one line of authoring, swaps live on dock/undock, and the view
   tree never knows. Focus/selection affordances stay orthogonal: the input
   paradigm system already handles gamepad focus regardless of which package is
   painted.
9. **Tiled textures (probe first).** `TileSize` appears nowhere in src and was
   never probed; `ScaleType = Tile` without it is useless. The barber-pole
   progress stripe, iOS pinstripe backgrounds, and the fantasy kits' repeating
   edge rails all need it. Probe: is `TileSize` rule-settable per state, and
   does it compose with `ImageContent` + `ResampleMode`? If yes, `tile` becomes
   a layer kind in capability 2; if no, pre-tiled strips at fixed sizes are the
   fallback and the plan says so honestly.
10. **Toggle knob/track slots.** The fix round gave Slider its rail and thumb;
   the iOS 6 ON/OFF switch (a sliding knob over a two-tone track, per-state art
   on BOTH) needs the same treatment for Toggle: `toggleTrack` / `toggleKnob`
   slots plus per-state variants from capability 3. Same recipe shape, no new
   machinery.

11. **The SwiftUI customization ladder (director, 2026-07-25).** Three rungs, each
   easy and documented:
   - *Rung 1 — the theme owns it.* Semantic roles + package recipes (v1, default).
   - *Rung 2 — the view overrides it.* Per-view modifier-style props that beat the
     theme for THAT node only, SwiftUI-style: a custom `thumbImage` on one Slider,
     an image on one Button, `UI.shadow`/corner modifiers (already shipped), and a
     per-view `gradient` modifier akin to SwiftUI's gradient fills. Per-view
     overrides follow the existing opt-out rule: an explicit local value opts that
     property out of theme changes, visibly and deliberately.
   - *Rung 3 — a custom control.* When the look is truly bespoke, the answer is a
     new control — and making one must be EASY and correct-by-construction: the
     scaffold + `docs/extending/new-control.md` playbook + the contribution
     contract (`themes.checkCoverage`) already exist; v2 adds a worked
     "custom-skinned control" example that registers namespaced roles, ships its
     own art, passes conformance, and re-themes with packages.
   Shadows and gradients become first-class at BOTH rungs: theme recipes may
   declare shadow presets per slot (begun in the fix round), and views may apply
   shadow/gradient modifiers locally, with the two composing predictably
   (view modifier wins on that node).

## Non-goals

Arbitrary theme-provided instance trees or callbacks; themes changing layout
structure, information architecture, or input paradigms; per-state geometry
changes that reflow on hover; bundling third-party art.

## Verification shape

Same discipline as Step 3.5: probes first (layer z-order under the text lift,
anchored ornament positioning, fill-clip approaches, pixel snapping), acceptance
ledger + gate, the theme_authoring scenario grows layer/census/state steps, an
original **Fantasy Ornate** reference package (frames + plaques + bars + icon
set) exercises everything through public APIs, five-view matrix + captures, the
capture readability pass stays a human row.

Plus the **platform-pair test** as a standing acceptance row: two original
packages over the SAME fixture — a glossy touch-metric package (gradients,
sliding switch art, striped progress; iOS-6-class, original art) and a compact
pointer-metric package (subtle gradients + hairline shadows; macOS-class) —
with `selectBy` proving the live dock/undock swap: mount identity held, geometry
re-solved to the new metric snapshot, zero view-tree changes. Captures of both
on both form factors go in the evidence pack.

## Immediate post-review fix round (Step 3.5 closure — already in flight)

The image-is-the-button suppression, image-tinted roles, slider rail/thumb slots
(parchment art uploaded: track `rbxassetid://133629068271978`, thumb
`rbxassetid://102024273231445`, badge seal `rbxassetid://103212793200116`),
readable badge seals, recipe shadow presets, the gallery theme picker, and the
guide's ELI5+technical language pass. Those are v1 defect fixes; everything
above this section is the v2 mission.
