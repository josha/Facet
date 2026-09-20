--!strict
-- The `table` control's types, apart from its implementation: reading a type must
-- not load the control.
local publicCore = require("../core/contract")
local publicBlueprint = require("../blueprint")
local publicEnv = require("../env/environment")
local row_actions = require("./row_actions")
local table_columns = require("../controls/table_columns")
export type Column = {
	id: string,
	title: string?,
	-- width sugar: a NUMBER is fixed px (SwiftUI .width(60)); {min, ideal,
	-- max} is a minMax band (SwiftUI .width(min:ideal:max:)); full Dim tables
	-- (fixed | fill | percent | minMax) pass through unchanged
	width: any,
	minWidth: number?,
	resizable: boolean?,
	-- per-column cell alignment (SwiftUI TableColumnAlignment); vertical
	-- CENTER and horizontal LEADING are the defaults
	alignment: { h: ("leading" | "center" | "trailing")?, v: ("top" | "center" | "bottom")? }?,
	-- cell content, in priority order: `cell(item)` (custom Blueprint, like
	-- TableColumn's content closure), `value(item)` (default Text cell, like
	-- TableColumn(value:) — also marks the column sortable), spec.cellFor
	cell: ((item: any) -> any)?,
	value: ((item: any) -> string)?,
	sortable: boolean?, -- opt a `cell` column into sorting explicitly
	-- FULL-VALUE DISCLOSURE for table-authored text (Step 8.5 LT-G2): the
	-- default `value` cell and the header title are Texts the TABLE authors, so
	-- a consumer had no way to declare their identity strings disclosable. A
	-- column carrying `disclose = true` passes the declaration to both; a
	-- custom `cell` blueprint declares it on its own Text instead.
	disclose: boolean?,
	--[[ WHICH COLUMN GOES FIRST WHEN THE TABLE IS TOO NARROW FOR ALL OF THEM
		(ADAPT-18). `1` is the most important. Absent, a column's priority IS its
		declaration order, so an author who never sets this gets the ordering they
		already wrote; `"always"` is the opt-out for a column that must stand at
		any width. The FIRST declared column never collapses either way — it is the
		row's identity, and it is what the disclosure names each hidden value
		against.

		Collapse triggers only where a floor was declared (`minWidth`, a `fixed`
		width, a `percent`), so a table whose columns declare none never collapses
		anything. The whole rule, and why it is a hide rather than an unmount, is
		`controls/table_columns.luau`'s COLUMN PRIORITY-COLLAPSE note. ]]
	priority: (number | "always")?,
}
export type Spec = {
	id: string?,
	columns: { Column },
	rows: publicCore.Readable<{ any }>, -- Readable<{T}>
	key: (any) -> string,
	-- legacy table-wide cell factory; optional when every column carries
	-- its own `cell`/`value` (the SwiftUI shape)
	cellFor: ((columnId: string, item: any) -> any)?,
	-- OPTIONAL, and leaving it out is the recommended shape (director, 2026-07-27).
	-- Absent, the table derives the row height from the theme's own per-paradigm row
	-- description and the live text scale — taller under touch so a row clears the
	-- target floor, taller again when the player raises their text preference. Set,
	-- a number or a per-item function still wins; the cell line cap is re-derived
	-- from whatever height won, so an authored row cannot overflow either.
	rowHeight: (number | (any) -> number)?,
	header: boolean?,
	selection: ("none" | "single" | "multi")?,
	selectedKeys: any?, -- caller-owned Compose cell of { [rowKey]: boolean }
	gap: number?,
	-- OWNER-HELD sort binding (SwiftUI Table(sortOrder:)): a Signal holding
	-- nil | { column: string, ascending: boolean }. Tapping a sortable
	-- column's header cycles it (new column -> ascending, same -> flips);
	-- the table NEVER sorts the data — the owner observes and re-sorts rows.
	sortOrder: any?,
	height: publicBlueprint.Bound<publicBlueprint.Dim>?, -- root height dim (default fill); pass a Readable fixed dim
	-- to make the table hug its content (content-hugging docked panels)
	-- WHO OWNS THE SCROLLING (director report 2026-07-27, playlist in landscape:
	-- "just the table scrolls. really the whole view should scroll, as it's
	-- unusable having just the table scroll").
	--
	-- Default TRUE: the table owns a viewport, its rows scroll inside it, and the
	-- page around it does not move. That is right when the table IS the screen.
	--
	-- FALSE makes the table a BLOCK: every row lays out, the body clips nothing,
	-- and the height defaults to content — so a host that wraps it in its own
	-- ScrollView scrolls the whole page, header and filter included. On a short
	-- landscape viewport the title, filter and hint ate 45-55% of the screen and
	-- the rows were left a 144px window that was the only thing that could move.
	--
	-- It is a CHOICE and not an inference because both are legitimate: a mail
	-- app's list owns its viewport, a settings page's small table does not.
	scrolls: boolean?,
	rowGap: (number | string)?, -- vertical space between row cards; a number or a
	-- theme metric name ("xs".."xl" or a dotted path such as "controls.table.rowGap"),
	-- exactly like `cellPadding` below. Default 0 (the drop indicator centers in the
	-- gap) — cards with hairline strokes need >= 2.
	--
	-- IT TAKES A METRIC NAME BECAUSE IT IS USED IN ARITHMETIC (example-quality-pass,
	-- 2026-08-06). `cellPadding` has accepted one since it shipped, because it is
	-- only ever handed to a blueprint prop and the solver resolves it. `rowGap` is
	-- also read in Luau — cumulative row tops, the content extent, and the drop
	-- slot — so a metric name here used to reach `cum += height + rowGap` and throw
	-- "attempt to perform arithmetic on number and string". It resolves against the
	-- live snapshot now, so the two spellings behave identically and a themed table
	-- gap is expressible at all.
	cellPadding: (number | string)?, -- horizontal cell inset; number or theme metric name (default "s")
	-- Phase B: row drag-and-drop — rows stay in place while dragging; a ghost
	-- chip and drop line carry the affordance (director round 2). Dragging a
	-- SELECTED row moves the whole selection as a contiguous block (director:
	-- rows 1,3,5 selected, drag 3, drop after 2 -> 2,1,3,5,4); an unselected
	-- row drags alone. onReorder(keys, toIndex): keys in DOCUMENT order;
	-- toIndex = 0-based insertion slot among the rows NOT being dragged —
	-- consumers remove all keys then insert the block at toIndex + 1.
	-- Drops that reproduce the current order are suppressed.
	reorderable: boolean?,
	onReorder: ((keys: { string }, toIndex: number) -> ())?,
	dragLabel: ((item: any) -> string)?, -- ghost chip text (default: the key)
	-- THE PRIMARY ACTION (parity round 2 §3.4). THE NAME IS OURS: SwiftUI has no
	-- `onPrimaryAction` symbol — it delivers this verb as the `primaryAction:`
	-- argument of `contextMenu(forSelectionType:menu:primaryAction:)`, whose
	-- documented gesture model is what the dispatch below implements.
	-- "Open this row" — the verb that is NOT selection. Reachable on all four
	-- inputs with no invented gesture (see the primary-action block below for the
	-- gesture table, Apple's own words, and the cost of the touch rule). Absent =
	-- the table has no primary action and every gesture below behaves exactly as
	-- it does today.
	onPrimaryAction: ((item: any, key: string) -> ())?,
	-- touch-scroll design (2026-07-20): owner-held edit-mode signal. When it is
	-- nil the table manages its own (api.editing), and auto-shows an Edit/Done
	-- toggle whenever edit mode is the ONLY route to a capability this table
	-- declares — `reorderable`, or a selectable table that declares
	-- `onPrimaryAction` (gated to non-mouse input when `env` is provided). The
	-- full predicate, the principle behind it, and what Apple does and does not
	-- document about `EditButton` are at THE AUTO EDIT/DONE TOGGLE below.
	editing: publicBlueprint.Bound<boolean>?,
	env: publicEnv.Env?, -- optional environment for input-aware affordances
	-- Task 10 (row-actions Table integration). Per-item callback: return
	-- `{ leading?, trailing?, fullSwipe? }` (the same shape `UI.RowActions`
	-- itself takes, minus `content`/`coordinator`/`env`/`editing` — Table
	-- supplies all four) to wrap that row in a swipeable action tray; `nil`
	-- (the common case) leaves the row completely unwrapped — no extra
	-- Instance, no extra subscription (see row_actions.luau's own "TRUE
	-- INERT PASSTHROUGH" — this is that same guarantee, one level up). Every
	-- wrapped row shares ONE coordinator (at most one open tray at a time
	-- across the whole table) and Table's own `editing` signal (the edit-mode
	-- leading minus and the reorder ≡ handle can both show at once — see
	-- row_actions.luau Task 9).
	rowActions: ((
		item: any
	) -> {
		leading: { any }?, -- { newRowActions.ActionSpec }
		trailing: { any }?,
		fullSwipe: (boolean | { leading: boolean?, trailing: boolean? })?,
	}?)?,
	--[[ VIRTUALIZATION (2026-08-14, `docs/plans/unified-collection.md`). When true
		the body mounts only the rows the viewport touches (plus `OVERSCAN` on each
		side) as absolutely-positioned children of one full-extent Canvas, instead of
		flowing every row. Everything else about the table is unchanged: the same
		columns, the same header, the same single/multi selection, the same reorder,
		the same per-row capability opt-outs.

		IT IS OPT-IN, AND THE REASON IS STATE. A row that leaves the window is
		UNMOUNTED and its item scope dies with it — which is right for a plate of
		text and wrong for a cell holding a live `UI.TextInput` mid-edit. Selection,
		focus, the sort and the order are model state and survive (the specs below
		pin each); anything a CELL holds is the consumer's to hoist. A flowing table
		keeps every byte of its old behaviour, so nothing that ships today moves.

		WHAT IT COSTS TO SAY YES: `scrolls = false` and `rowActions` are refused
		with it — see the two construction refusals in `build`, each of which says
		why in the message. ]]
	virtualized: boolean?,
}
return nil
