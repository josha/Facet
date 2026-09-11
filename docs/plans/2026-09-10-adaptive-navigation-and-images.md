# Adaptive navigation and image controls

Decision: extend existing controls, keeping game task semantics separate from
presentation. This builds on the distance/gamepad audit and implementation of
2026-09-09. No native Apple rendering backend or streaming-app layout is implied.

## Evidence and choices

Apple's [tab navigation guidance](https://developer.apple.com/documentation/swiftui/enhancing-your-app-content-with-tab-navigation)
and [WWDC24 tab presentation discussion](https://developer.apple.com/videos/play/wwdc2024/10207/)
distinguish tablet tabs with a sidebar toggle, persistent desktop sidebars, compact
bottom tabs, and a collapsed destination indicator on tvOS. Facet adopts these
as the opt-in `TabView.style = "sidebarAdaptable"`. Ordinary and nested game tabs
retain their existing behavior. Width, input and viewing distance are independent
facts, so a handheld controller does not acquire TV typography or a sidebar just
because it has a gamepad. Navigation chrome changes preserve mounted content;
changing the selected destination still uses the existing lazy eviction model.

The [tvOS SwiftUI sample](https://developer.apple.com/documentation/swiftui/creating-a-tvos-media-catalog-app-in-swiftui)
coordinates image-button focus effects and nearby labels. Facet extends Button
with an image form and persistent caption/subtitle. An aspect-ratio envelope
reserves the maximum 5% image lift plus semantic padding for its ring. The image
alone scales; captions stay laid out and readable. Reduced motion removes lift,
disabled/busy suppress highlight and activation, and pointer hover is observed
through local enter/leave events. No per-card global mouse listener, frame
animation, extra focus identity, or second input system is introduced.

Automatic menus now use one panel for gamepad hierarchies even with few root
items. Pointer users retain cascades on roomy screens. This reuses the menu's
existing Back history and sheet mechanism. NavigationSplitView remains the choice
for simultaneous selection/detail; NavigationStack remains drill-down. Sliders,
steppers, pickers, lists, and radials retain their shared semantic navigation and
existing adaptation rather than receiving redundant platform-specific controls.

## Verification and shipping surfaces

- `tests/adaptive_presentation.spec.luau`: real mounted input/geometry checks,
  tablet toggles, distant selection/focus transfer, mouse defaults, image activation,
  reduced motion, single-panel gamepad menus, and bounded branch lifetimes.
- Image/caption containment with +14 preferred text under Pixel Quest and Fantasy
  Ornate at 390, 1000, 1280 and 1920 pixels. Full Showcase/theme sweep remains
  authoritative for the complete demo surfaces; native paint must also be inspected.
- Existing Showcase TabView uses the adaptable style. Actions and menus now has
  image choices for racing drivers, using the same Button API as other actions.
- `bench/perf_scenes.luau` adds `adaptive-navigation-images`: 24 image buttons,
  3 destinations, separate idle/focus/navigation phases. Assertions prohibit
  idle/focus layout solves and content rebuilds during navigation chrome changes.
  Only its new trend budget is baselined; existing budgets are unchanged.
- Headless timings are development-host trend measurements, not physical console
  results. FacetBench's Vide adapter is live-only and its neutral inventory schema
  lacks adaptive navigation/semantic controls: generic inventory comparisons must
  not be represented as a comparison of these new features.
- The control chooser, API reference, guide catalog and `skills/use-facet/SKILL.md`
  teach the public forms and the game-oriented selection criteria.

Final commands, native observations and measurement results are recorded in
`artifacts/adaptive-presentation/README.md`. No publishing is part of this change.

The legacy D5 evidence rule forbade any Button or Back handler inside TabView.
The sidebar toggle now legitimately needs both. The gate still requires Picker
reuse and exactly one authored Button (ToggleSidebar), and now explicitly checks
that Back collapses only sidebar focus while leaving page Back unclaimed. The
collapsed-caption memo is owned by its own When branch so repeated distance
changes release it immediately; a counter regression check guards this lifetime.

Image hover reconnection is also checked with instance recycling disabled. A
control that receives a new mounted node releases its previous hover connection
before attaching the new one. The fake target counts this observer in its handler
census, and teardown must return that census to zero. These cases prevent default
pooling from hiding a stale callback and prevent benchmark accounting from omitting
new control wiring.
