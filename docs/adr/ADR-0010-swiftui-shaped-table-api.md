# ADR-0010: SwiftUI-shaped Table API (columns own content, alignment, width sugar, owner-held sort)

- **Status:** Accepted (director round 5, 2026-07-20)
- **Amends:** ADR-0007 (Table primitive), ADR-0008 (pointer seam — no behavior change)

## Context

The Table's Phase A/B API grew NSTableView-shaped: a table-wide `cellFor(columnId, item)`
factory, raw solver `Dim` tables for widths, no per-cell alignment, and no sort
affordance. The director's round-5 ruling: *"we should make sure our table cells have
an alignment modifier for the cell (vertical and horizontal) and default to vertical
center-align … given SwiftUI has tables, we should ensure our interface is more akin to
[SwiftUI Table](https://developer.apple.com/documentation/swiftui/table)."*

SwiftUI's shape, mapped: `TableColumn` owns its content (a `value:` key path renders a
default text cell and marks the column sortable; a content closure renders custom
cells), `.width(60)` / `.width(min:ideal:max:)` are the width vocabulary,
`TableColumnAlignment` sets per-column cell alignment, and `Table(sortOrder: $order)`
is an **owner-held binding** — tapping a sortable header cycles the binding and the
*data owner* re-sorts; the table never sorts rows itself.

## Decision

`Column` gains the SwiftUI surface; everything is additive and the legacy shape keeps
working (RascalRally's racer list ships on `cellFor` today):

1. **Columns own their cells.** Priority per column: `cell(item)` (custom Blueprint,
   like `TableColumn`'s content closure) → `value(item)` (default `Text` cell id
   `Value`, coerced via `tostring` so a raw number never reaches the Text prop, like
   `TableColumn(value:)`) → legacy `spec.cellFor`. A column with none of the three is
   a hard `assert` **at build time** (validated in the normalization loop, so an
   empty rows list never masks it — verifier finding, 2026-07-20). Column ids are
   asserted path-safe (no `/`) at build for the same reason: they become
   `Cell-{id}`/`Head-{id}` path segments.
2. **Per-column alignment.** `alignment = { h = "leading"|"center"|"trailing", v =
   "top"|"center"|"bottom" }`, defaulting to **vertical center + horizontal leading**
   (the director's default ruling). Terms are SwiftUI's; they map to solver
   `start/center/end` internally.
3. **Width sugar.** A bare number is fixed px (`.width(60)`); `{ min, ideal, max }` is
   a `minMax` band with `ideal` as preferred (`.width(min:ideal:max:)`); partial bands
   are valid — `preferred` falls back explicitly to `ideal or min or max` (so
   `{ min = 50 }` alone behaves like SwiftUI's `.width(min: 50)`); full `Dim` tables
   (`fixed | fill | percent | minMax`) pass through unchanged. Columns are normalized
   into shallow clones — caller tables are never mutated.
4. **Owner-held `sortOrder`.** `spec.sortOrder` is a Signal holding `nil | { column:
   string, ascending: boolean }`. A column is sortable iff `sortOrder` is provided and
   the column has `value` (SwiftUI's rule) or opts in via `sortable = true` (for `cell`
   columns). Sortable headers render a full-header `Sort` hit (`focusable = false` — it
   never joins the keyboard focus ring; header sorting stays a pointer affordance,
   matching SwiftUI/AppKit) plus a `SortMark` text bound to the signal (`▲`/`▼`/empty).
   Tapping cycles: new column → `{ column, ascending = true }`; same column → flip
   `ascending`. **The table never reorders rows** — the owner observes the binding and
   re-sorts its rows source (see `examples/table_phaseb`).

## Consequences

- `spec.cellFor` is now optional (`Spec` type updated); the racer-list surface is
  unchanged and its suite still passes untouched.
- The header build derives from the normalized `columns` clones everywhere
  (`handleAdjust`, `setColumnWidth` included) so width sugar works in every path.
- Tests: `tests/table.spec.luau` "Table: SwiftUI-shaped columns (director round 5)" —
  alignment placement, cell/value/cellFor priority, width sugar, and the full
  sortOrder cycle (including rows-untouched and no-Sort-on-non-sortable).
- Deliberately not adopted from SwiftUI: multi-column `KeyPathComparator` arrays
  (single `{column, ascending}` covers our consumers), row-builder DSL (`rows` stays a
  Readable list + `key`), and `Table`-owned selection bindings (our selection API
  predates this and is idiomatic here).
