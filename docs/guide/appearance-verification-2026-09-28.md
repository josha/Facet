# Overlay continuity, table geometry and Facet Lab

Overlay continuity and table geometry use shared Facet controls and theme rendering. The Lab consumes
them without local layout corrections. The Lab and optional Foundation Light
and Dark themes are in `examples/facet-lab`; the default runtime
package still excludes them. The Lab control list uses 22-pixel text.

## Native mechanisms

Roblox `UIScale`, `AutomaticSize`, `TextBounds`, `TextFits`, `TextWrapped`,
`AnchorPoint`, `Position`, `CanvasGroup`, `UIShadow.Transparency` and scrolling
geometry supply native bounds and paint. Scaling an ancestor changes native glyph rounding and
can change wrapping even after the panel has been measured. Facet therefore
animates the panel dimensions while holding content at its measured layout
size. Native anchoring avoids independent pixel rounding of content offsets.
Native wrapping remains responsible for Toast text; its available width
comes from the actual overlay parent. Native shadow transparency follows the
same fade as the panel.

Compose cells, watches, property bindings, `show`, mounting and cleanup own
the temporary content frame and restore its children. Table measurements convert native display
pixels into the logical units used by the existing layout and drag paths.

## Verify in Studio

Run `lute run tools/lute/studio_live.luau ports_overlays --cases-from-tree --studio STUDIO_ID --device none`.
Check overlay entrance, interruption, and exit at compact and wide sizes.
Inspect text wrapping and shadows during motion. Check table resize geometry
with an ancestor UIScale. Repeat with preferred text sizes and reduced motion.
A native engine double does not prove glyph paint or physical device behavior.
