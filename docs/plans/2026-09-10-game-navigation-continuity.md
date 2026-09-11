# Game navigation and continuity

Implement semantic row presentations on Button, Toggle and Slider using the shared row recipe. A row retains its existing control semantics and one controller focus identity; pointer/touch retain direct adjustment. Whole-row emphasis must not change layout and must honor reduced motion and themed insets.

Add `UI.focusSection(content, {entry, preferred})` on mounted containers. Reuse the focus graph, preserve contributed grid/virtual/radial topology and explicit exits, and use resting section bounds at directional boundaries. Preferred and restored targets must remain eligible. No per-frame neighbor scan.

Extend existing ScrollView declarations with scoped named targets, visibility thresholds and programmatic target selection. Reuse native scroll reads/writes and the existing snap clock. Record lightweight scroll bookmarks by stable descendant keys under TabView destinations, restoring after mount/layout without retaining content instances. Hosts retain persistence and domain state.

Extend TabView with optional authored sections and caller-owned customization (order/hidden state), exposed through normal buttons/menus for every input. Required destinations cannot be hidden; invalid persisted IDs are ignored and newly authored destinations remain available. Selection and page identity must survive reordering and navigation relocation.

Use existing Showcase scenarios for settings/inventory rows, hero-to-shelf scrolling and personalized destination navigation. Extend the adaptive navigation benchmark and theme/text matrices. Native review covers animation interruption/settling, focus clearance, and content versus ornate borders. Optional effects serve focus and continuity; avoid continuous scene effects or a second renderer.
