# Image backgrounds and adaptive paradigm coverage

## Decision

Extend `UI.Image` with `imageFraming`, and forward it through the image form of
`Controls.Button`. Keep `UI.background` as the view-background mechanism. This
works with the same screen, billboard and surface adapters. No background control,
second focus system, or device-specific component hierarchy is introduced.

Existing `scaleMode` remains compatible. Explicit framing takes precedence and
adds decoded source dimensions, a crop/fit/stretch/none policy, a normalized
source focal point and a scale multiplier. Center the crop on the source point,
then clamp to source edges. Natural size means one source pixel per layout pixel
at scale 1; larger views expose centered space, smaller views crop. It does not
mean automatically guessing a downloaded texture's size. Applications know their
art metadata; asynchronous loading can bind the complete record with the image.

A pure resolver computes source crop and destination paint rectangles. Native
rendering reuses one managed ImageLabel inside the original solved leaf, using
ImageRectOffset/ImageRectSize and a destination rectangle contained by the leaf.
The foreground layout, hit region and focus identity do not change. Four local
property observers use GetStyled/GetStyledPropertyChangedSignal (with a legacy
plain-property fallback) to carry sheet-driven tint, opacity, sampling and z-order to the
picture. Clear/removal disconnects them; framing/resize reuses the picture. No
new work is installed for ordinary images. Authored gradient/corner modifiers
are copied to the picture and reused across changes. Scene art uses the background
layer; theme chrome continues to reserve its own border insets.

Roblox documents ImageRectOffset and ImageRectSize as source-pixel Vector2 values;
a zero dimension requests the full texture. Our zero-view case retains a valid
source rectangle and paints a zero-sized destination. Source:
[ImageLabel reference](https://create.roblox.com/docs/reference/engine/classes/ImageLabel),
read September 10, 2026. Actual served image resolution matters after upload
resizing. The user confirmed the computer is unlocked and authorized Studio
verification. Native results and any remaining hardware limitations are recorded
in `artifacts/image-framing/README.md`.

## Can declarative Facet code now produce the same kind of result?

**The core approach works; complete SwiftUI/tvOS parity is not claimed.** Authors
choose semantic controls and a game theme. Facet chooses size, layout, input and
navigation presentations from the shared environment. Arbitrary stacks and raw
buttons do not acquire an app shell or image-button behavior by inference.

| Sample behavior | Facet now | Remaining distinction |
|---|---|---|
| App destinations adapt between tabs/sidebar/compact distant chrome | `TabView.style = "sidebarAdaptable"`; page identity survives chrome changes | Explicit style choice. This is app navigation, not a rule for every in-game tab. No automatic tab customization/sections like Apple's full API. |
| Simultaneous selection/detail becomes a compact navigation flow | `NavigationSplitView` and `NavigationStack` | Choose the task relationship; Facet cannot infer it from two arbitrary columns. |
| Image choices coordinate image highlight and text | Image `Controls.Button`, now with source framing | Reserved lift envelope keeps captions stationary and clear; Apple may move nearby text. Native specular/gimbal/material rendering is not reproduced. |
| Shelves resize and scroll into focus | `VirtualList` cards, item snapping, container-relative sizing; shared focus/keep-visible | Generic ScrollView has no authored arbitrary fold-target/visibility policy equivalent to the sample. |
| Hero image reframes as the screen changes | `UI.background` + `UI.Image.imageFraming` | Art direction, focal point, safe areas and text contrast remain authored. A resizable picture cannot choose a good subject for the game. |
| Moving up from any shelf reaches a broad hero section | Geometry groups and explicit navigation groups | A first-class rectangular focus-section guide/entry policy would make this easier and less dependent on explicit navigation declarations. |
| Search field and suggestions integrate with navigation | Existing text-entry, filtering and searchable selection controls | No general `searchable` modifier that relocates search/suggestions automatically in all app shells. |
| Remote/gamepad adapts alongside touch and pointer | Semantic action system, focus, gamepad sheets, responsive controls, independent viewing distance | Roblox gamepad/keyboard input is not a native Siri voice/remote-touch event stack. |

The Apple sample itself authors hero folding, scroll visibility state, a custom
scroll target behavior and a gradient material mask. Those results are not the
automatic consequence of a TabView. See Apple's
[media catalog sample](https://developer.apple.com/documentation/swiftui/creating-a-tvos-media-catalog-app-in-swiftui)
and [WWDC24 session](https://developer.apple.com/videos/play/wwdc2024/10207/).
This comparison is an inference from the source/API behavior and current Facet
implementation, not a claim of native visual equivalence.

## What to add next, in order

1. **Declarative focus sections on existing containers.** Give the section a
   geometric entry region, optional preferred/restored descendant and sensible
   directional routing. Extend the current focus graph. Prove hero-to-shelf,
   inventory-to-inspector, HUD-to-pause and sparse layouts. Keep disabled/hidden
   filtering, scope lifetimes and near-gamepad behavior. No per-frame global scan.
2. **Shared scroll target and visibility hooks.** Extend ScrollView's existing
   coordinator for named snap anchors and threshold events, while preserving
   VirtualList's existing item snapping. Use one authored game landing-page
   example (track hero to events or loadout shelf) with touch, wheel and focus.
   Avoid forcing cinematic fold snapping onto settings or fast in-game menus.
3. **Adaptive search placement using existing text input and list primitives.**
   Promote the composed pattern only when a game actually needs cross-screen
   search: a full compact search page, inline/sidebar search when roomy, a
   focusable console entry with suggestions and reliable Back restoration.
4. **Native visual and hardware review before richer effects.** Verify shared
   controls and framing on the real renderer, including ornate borders and image
   masks, then profile representative hardware. Theme-authored gradients and
   quiet plates are the current material alternative. Richer image highlights
   are optional polish; add them only when the game art and measured budget
   justify the native cost.

This is the next-work plan, not a claim those four items were implemented here.

## Author guidance and showcase

`AGENTS.md`, `skills/use-facet/SKILL.md`, and the custom-theme guide now instruct
agents to derive/customize a game theme matching the art, supply real semantic
image/vector icons, reserve border insets, and use scenic backgrounds only when
appropriate. The Actions and menus showcase compares focal-crop and natural-pixel
backgrounds and forwards framing into its existing driver image buttons.

## Evidence

`tests/image_framing.spec.luau` started red for the missing framing module, then
covers crop clamping, natural pixels, scaling, containment, reactive paint-only
updates and resize. A native-API fixture executes the actual client module and
checks reuse, corner-mirror identity/removal and observer cleanup; it does not simulate the GPU. The image-button
matrix started red on the missing forwarded property, then passed across Pixel
Quest/Fantasy Ornate, enlarged text and four viewport/input profiles.

A native-style fixture initially reproduced white where the source StyleSheet
resolved red. The adapter now reads and observes resolved style values instead of
the raw properties, matching the existing paint-claim and caret contracts.

The exhaustive UICorner ownership audit classifies the mirror as a managed
grandchild: it cannot become the host chrome-radius owner.

The existing `adaptive-navigation-images` bench now frames all 24 image buttons.
Its no-idle/focus-solves, no-focus-creates and page-identity assertions remain.
It is a Lune full-stack workload, not a native render-time or Vide comparison.
The live review caught a Showcase sizing-helper typo, an instant image-focus
scale change, and a 4-pixel wide-image envelope overflow at ten-foot scale.
The existing Showcase mount test reproduces the typo; a new motion case proves
continuous interruption, exact settling, no late layout solves and reduced motion.
The image button now reuses one scoped object spring with scale-appropriate
precision. An unpainted aspect plane reserves the maximum lift before adding
padding, keeping border clearance independent of image aspect ratio.
The benchmark includes the first animated focus frame and settles flights before
the next idle sample. Native frame traces and screenshots live with the artifacts.
Final gate and package results belong in `artifacts/image-framing/README.md`.

### Labelled tab and picker badges

The native ornate sidebar exposed a count ornament over the Inbox label. Badged
options now reuse the existing menu-row recipe inside the same focusable Button.
The label and count occupy measured lanes and may wrap on a narrow offer; a
hugging tab measures their intrinsic widths. Unbadged options retain their compact
label behavior. The `onAccent` tint role exposes the existing palette partner so
custom child labels keep the selected pill's contrast without literal colors.
The border regression now tests an actually decorated segment (`indicator =
"none"`); inline counts may have extra clearance rather than sitting flush at the
corner. Separate tests verify label/badge separation and stable activation.

### Radial content in thin rings

The native ten-foot review exposed three loaded action icons reduced to one pixel.
The upright label rectangle previously retained an impossible height inside a
thin annulus. Geometry now reduces that height to a fitting square before finding
its width. Compact image/icon buttons and ring navigation reserve only the padding
they actually paint. This keeps all compass directions usable and preserves the
same semantic icon size for actions and navigation. The radial and geometry
specifications cover this case alongside narrow-screen fitting and transitions.
