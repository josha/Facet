# Overlay continuity, table geometry and Foundation Lab

The fixes live in shared Facet controls and theme rendering. The Lab consumes
them without local layout corrections. The Lab and optional Foundation Light
and Dark themes now live in `examples/foundation-lab`; the default runtime
package still excludes them. The Lab control list uses 22-pixel text.

## Native mechanisms

Roblox `UIScale`, `AutomaticSize`, `TextBounds`, `TextFits`, `TextWrapped`,
`AnchorPoint`, `Position`, `CanvasGroup`, `UIShadow.Transparency` and scrolling
geometry were checked. Scaling an ancestor changes native glyph rounding and
can change wrapping even after the panel has been measured. Facet therefore
animates the panel dimensions while holding content at its measured layout
size. Native anchoring avoids independent pixel rounding of content offsets.
Native wrapping remains responsible for Toast text; its available width now
comes from the actual overlay parent. Native shadow transparency follows the
same fade as the panel.

Compose cells, watches, property bindings, `show`, mounting and cleanup own
the temporary content frame and restore its children. No second layout solver
or animation scheduler was added. Table measurements convert native display
pixels into the logical units used by the existing layout and drag paths.

## Studio evidence

- Overlay continuity: 108 entrance configurations across nine control families,
  three motion levels, two viewport sizes and Neutral/Sci-Fi text scenarios.
  The final run passed 586 checks with zero failures, including upward menus,
  toast width and native text fit, closing shadows, and negative controls for
  a one-pixel translation, a text-size pop and a transient scrollbar.
- Table resizing: 144 checks passed, covering large headings, repeated column
  resizing, horizontal scrolling, persistent scrollbars and display scales
  of 0.75 and 1.5.
- Local receipts: `artifacts/studio-live/appearance-final.json`, source stamp
  `531a801d-4144685`, and `table-resize-final.json`, source stamp
  `f7c97612-4140208`. These are local artifacts, not distributed package data.
- Studio's native text preference was Medium. Explicit large text and the
  Largest environment preview were exercised; this is not physical-device or
  native Largest-preference evidence.

## Repository verification

The required full verification, standalone benchmarks, package build and
package status commands were run. Benchmarks passed, type checking reported
109 targets with zero diagnostics and 174 negative probes passed. Core package,
example places and the relocated Foundation Lab built successfully.

The full gate is not green. Legacy consumer brand/API references still fail
the drift checks and package tree inspection; six old performance capture
records have obsolete metadata; host timing exceeded a recorded trend budget.
These gates and budgets were not relaxed. Three stale menu assertions from
that run were corrected to calculate the visible corner using native
`AnchorPoint`, and their complete 124-test group passed afterward.

The final full unit rerun passed 3,474 cases with one deferred and three
scenario-path failures caused by another task's untracked gallery files.
All five scenario-path tests passed against an isolated copy of the exact
staged tree. The earlier menu assertions passed in this full rerun. The
untracked gallery work was excluded from this change.

The direct Rascal Rally consumer still reads the older `app.controls` Table
API and its test harness requires a removed helper. An unmodified Studio probe
fails at the Table lookup. No production game migration was included, so this
work does not certify that consumer's integration or package publication.
