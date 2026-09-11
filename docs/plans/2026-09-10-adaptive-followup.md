# Adaptive navigation follow-up

Scope: remaining report items 1, 3, 4, 5 and 6. The implementation ladder applies
to layouts and controls: public Facet composition, supported customization,
reusable Facet extension, then only a documented minimal custom fallback.

## Decisions

- Retain the sidebar's real content reflow. A completed partial feedback layout
  covers its classified dirty suffix; the next refresh need not solve it again.
  New dirt, structural materialization and paint retain their existing paths.
  Keep the 24-card benchmark, sampling, settling and budgets unchanged.
- Extend TabView with explicit/readable `shoulderNavigation` policy. Opt-in content
  paging owns shoulders only. Nearest controls, active popups, nested tabs and
  modal/gameplay arbitration retain ownership. The game suspends global paging
  during its own editing/confirmation. No new input system.
- Reuse controller repeat for continuous/stepped value controls, pin a hold to its
  original focus owner and recheck arbitration. Repeats clamp; fresh directional
  presses retain boundary navigation. Table Back unwinds grab/edit before navigation.
- Compose search from TextInput search presentation, adaptive stacks, keyed result
  buttons and NavigationStack. Retain query outside page scopes. Suggestions,
  empty results, clear icon and Back-to-result focus are in the existing Showcase.
  No separate Search control is required for this flow; large datasets should use
  VirtualList/Grid/Table with caller-owned filtered data. Correct earlier guidance
  that named a nonexistent NavigationSplitView API.
- Add opt-in ScrollView target-arrival focus. Preserve focus by default. Cancel
  handoff on focus/modal/request/gesture/removal changes; emit removal visibility
  exits exactly once. Use existing motion, graph and native scrolling.
- Add optional theme `chrome.navigation`, native when absent. Fantasy Ornate uses
  one existing carved-strip image with declared content insets instead of its full
  panel corners/nameplate. This is a shared semantic art slot, not a per-demo fix.

## Verification

Red-first tests cover duplicate layout, four-class target requests, visibility
removal, target handoff, value hold, edit Back, search and capsule classification.
Independent verifier exercises modal/gesture/remount interruption, saturated value
controls, nested/popup shoulders, Table grab rollback and renderer feedback with
new dirt. Run the full deterministic tier, theme/Largest text containment, radial
and editable collection regressions, unchanged benchmarks, package and places.
Studio receipts must identify current source and distinguish geometry/state from
raw-input and visual evidence. Physical low-end budgets and viewing-distance feel
remain separate device work; headless profiles cannot close those claims.

Studio resize validation also exposed a shared layering gap: a geometry/hit-lift
walk can see a newly resolved subtree before its handles materialize. The z-order
cache now retains only completely materialized ranges, so the subsequent bounded
mount assigns every child its layer. Deferred native handles retain and replay
assigned z as well. Direct regressions cover both missing branches and missing
leaves; removing the completeness guard fails both. Studio recapture confirms
capsule background z7, toggle z9 and label z12 after compact-to-distant resizing.
