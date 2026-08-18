# /goal prompt — native Roblox styling for Facet

This prompt is the standalone copy of Step 2 in
[`facet-consolidated-roadmap.md`](facet-consolidated-roadmap.md). The consolidated
roadmap is the preferred entry point because it includes dependencies and ordering.

```text
/goal Implement the corrected native-stylesheet plan for Facet. Read and follow:

- GameStudio/ui/Facet/docs/plans/roblox-native-audit-corrections.md
- GameStudio/ui/Facet/docs/plans/roblox-native-stylesheets.md

Outcome: Roblox StyleSheets and the Style Editor become the runtime source of truth
for every proven styleable paint property, semantic role, native interaction state,
app-state tag, theme, and transition. A designer can edit a named rule or paint token
in Studio and see it on a running Facet screen without changing Luau.

Boundaries:
- GuiState is read-only and engine-owned. Use native state selectors for native
  hover/press/non-interactable state and tags for Facet-owned state.
- Use only documented built-in StyleQuery conditions. Tags carry Facet's filtered
  input-paradigm and pointer-live decisions.
- One authority owns each engine property. Once a property is native-styled, remove
  Facet's direct write for that property; preserve an explicit-write fallback only
  as a separate target mode.
- Keep solver inputs available in pure Luau. Do not promise editor round-trip for
  spacing or type metrics without a tested export/freshness workflow.
- Run the preferred-text matrix and ensure Roblox preference is painted exactly once
  while headless measurement reserves matching bounds.
- Styling Transitions are progressive enhancement until publishable. Prefer the
  ReducedMotionEnabled query and keep instant-change behavior.

Start with the plan's Studio evidence matrix, then implement behind an opt-in target
capability. Prove editor round-trip, authority handoff, theme swap, native/app state,
reduced motion, preferred text, fallback parity, and no remount/focus loss. Verify the
full suites and fresh-context platform/architecture review. Update the styling guide
so a human can tell which Style Editor edits are immediate and which require export.
```
