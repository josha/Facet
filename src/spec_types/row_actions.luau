--!strict
-- The `row_actions` control's types, apart from its implementation: reading a type must
-- not load the control.
local blueprint = require("../blueprint")
local themeSnapshot = require("../themes/snapshot")
local rowActionsSpec = require("../controls/row_actions_spec")
export type Edge = rowActionsSpec.Edge
export type ActionSpec = rowActionsSpec.ActionSpec
export type Spec = {
	id: string?,
	content: blueprint.Blueprint, -- Blueprint, required
	leading: { ActionSpec }?, -- nil = none; {} is a spec error
	trailing: { ActionSpec }?,
	fullSwipe: (boolean | { leading: boolean?, trailing: boolean? })?, -- default true
	coordinator: any?, -- newRowActionsCoordinator() result; Task 7 wires it
	-- OPTIONAL, table.luau's own precedent (`table.luau` Spec.env): live text/
	-- theme reactivity for each tray button's reserved width (buttonPad,
	-- buttonMinWidth) needs the environment's theme snapshot, and a composite
	-- has no other line to it (unlike font/size, which arrive fully resolved
	-- through `controller.textAt` — see the natural-width comment below).
	-- Absent degrades to `themeSnapshot.neutral()`, exactly like `table.luau`'s
	-- own `metricsOr` fallback — "the neutral package at authored size... which
	-- is what the suite has always solved" (table.luau).
	env: any?,
	--[[ MAY THIS ROW BE DELETED AT ALL? (`rowDeletable`, wired 2026-08-14.)
		A thunk, evaluated at COMMIT time inside `doCommitAction` — the one funnel
		the swipe commit, the revealed tray's Delete button, the edit-mode ⊖, the
		Delete/Backspace key and the action menu's destructive row all reach.
		Returning `false` refuses the delete; every non-destructive action is
		untouched.

		A THUNK AND NOT A BOOLEAN, because this composite has NO NOTION OF AN ITEM
		— it receives already-resolved `ActionSpec` lists. `UI.Table` /
		`UI.VirtualList` own the item and own `spec.rowDeletable`, so each closes
		over both and hands the verdict down; evaluating it late means a predicate
		reading a mutated item still decides correctly, and it keeps the fail-closed
		reading in ONE place (`row_capability.allows`) rather than two.

		`nil` (the default) means "every destructive action commits", which is what
		makes this cost nothing for every caller that never wires it. ]]
	deletable: (() -> boolean)?,
	-- Task 9 (the edit-mode leading minus). PUBLIC, not `_editing`: `table.luau`'s
	-- own `editing` spec key (Spec.editing there, "owner-held edit-mode signal")
	-- is the shipped precedent for a Readable-valued spec key living in the
	-- open, undecorated namespace — Table (Task 10) passes its OWN `editing`
	-- straight through to this exact field, and a standalone caller wiring an
	-- edit-mode toggle by hand (no Table involved) wants the identical seam, not
	-- an internal one it cannot reach. `nil` (the default) means "this row is
	-- never in edit mode" — the minus can then never appear, structurally,
	-- regardless of `hasDestructive`, at zero cost (see `hasEditAffordance`
	-- below): a caller that never wires edit mode pays nothing for this task.
	editing: blueprint.Bound<boolean>?, -- Readable<boolean>?
	-- Task 10 (Table integration). `nil` (default) leaves the root
	-- content-sized — Tasks 3-9's own shipped shape, unchanged, and correct
	-- for every existing caller whose `content` already carries its own
	-- intrinsic width (a Text/Button-shaped row). A caller whose `content`
	-- is ITSELF `width = fill` (Table's own row — see table.luau's own
	-- rowBlueprint) has nothing intrinsic for the composite's own
	-- content-sized root to measure: `Content` (fill) degrading to ITS
	-- children's natural size finds only more "fill" all the way down, so
	-- the whole composite collapses to a near-zero measured width. Table
	-- passes `{ type = "fill", weight = 1 }` here — the exact prop the
	-- unwrapped "Row" node carries on its own — to restore the row's normal
	-- list-flow width; a standalone caller never sets this and is
	-- byte-identical to before this field existed.
	width: blueprint.Bound<blueprint.Dim>?,
	-- Task 10 (Table integration). Default false: every standalone
	-- `UI.RowActions` caller (and every Table row that is NOT `reorderable`)
	-- keeps this composite's own internal Content "Hit" Grip wired to
	-- `_pointerHandlers` exactly as Tasks 3-9 shipped it — the composite is
	-- fully self-sufficient. `true` skips wiring that Grip's pointer handlers
	-- (the node itself still mounts, just inert): the caller is going to
	-- drive `_pointerHandlers` from ITS OWN hit surface instead (Table's own
	-- row "Hit" Button, composed with reorder via `composeWithReorder`
	-- below). Structural reason, not a style choice: `content` (a Table row)
	-- already carries its OWN full-fill Active pointer surface at the
	-- identical rect this composite's Grip occupies — two independent Active
	-- zones racing for the engine's one-at-a-time InputBegan capture
	-- is exactly the "row hit won the race" class table.luau's own
	-- `rowPointerHandlers` header comment already names as unsafe to leave to
	-- firing order. Table wins deterministically by construction instead:
	-- this composite simply never enters the race.
	externalGesture: boolean?,
}
export type HostedPaths = {
	content: string, -- the host's own row node: the row's live rect/screen rect
	trayLeading: string?, -- the shared overlay's leading tray container
	trayTrailing: string?,
	-- where the host mounts `api.editAffordanceView` (stage 1, 2026-08-15).
	-- Required exactly when that view exists — an unreachable minus that
	-- ANNOUNCES itself as "Delete" is refused at build time, not shipped.
	editAffordance: string?,
}
export type HostedSpec = {
	id: string?,
	leading: { ActionSpec }?,
	trailing: { ActionSpec }?,
	fullSwipe: (boolean | { leading: boolean?, trailing: boolean? })?,
	coordinator: any?,
	env: any?,
	-- `Readable<boolean>?`, same contract as `Spec.editing` — see `HOSTED_KEYS`
	editing: blueprint.Bound<boolean>?,
	paths: HostedPaths,
	onSlide: (px: number) -> (),
	onCommitHeight: ((px: number?) -> ())?,
}
export type HostedOpts = {
	paths: HostedPaths,
	onSlide: (px: number) -> (),
	onCommitHeight: ((px: number?) -> ())?,
}
export type HostedEngine = {
	blueprint: nil, -- always nil: a hosted engine mounts no node of its own
	dump: () -> any,
	dispose: () -> (),
	_open: (edge: Edge) -> (),
	_close: () -> (),
	_isOpen: () -> boolean,
	_settleTo: any,
	_closeMenu: () -> (),
	_menuHandle: () -> any,
	_pointerHandlers: {
		onPointerDown: (path: string, pos: any, rectOf: (string) -> any) -> boolean?,
		onPointerMove: (path: string, pos: any, rectOf: (string) -> any) -> (),
		onPointerUp: (path: string, pos: any, rectOf: (string) -> any) -> (),
		onPointerCancel: (path: string, reason: string?) -> boolean?,
	},
	_commitFirst: (edge: Edge) -> boolean,
	_handleActivate: (path: string, meta: any?) -> boolean,
	-- hosted-only (never present on `row_actions.build`'s own return):
	pointerHandlers: {
		onPointerDown: (path: string, pos: any, rectOf: (string) -> any) -> boolean?,
		onPointerMove: (path: string, pos: any, rectOf: (string) -> any) -> (),
		onPointerUp: (path: string, pos: any, rectOf: (string) -> any) -> (),
		onPointerCancel: (path: string, reason: string?) -> boolean?,
	},
	open: (edge: Edge) -> (),
	close: () -> (),
	-- `Readable<nil | { edge: Edge, actions: { ActionSpec }, revealPx: Readable<number> }>`
	trayState: any,
	-- the tray `UI.When` blueprints — the SAME ones standalone mode parents under
	-- its row root, for the host to parent under its shared overlay (Task 4)
	trayViews: { any },
	-- ...and the edit-mode minus, same deal (stage 1). BOTH are nil unless this
	-- row can ever show it: `spec.editing` wired AND a destructive action
	-- somewhere. `editGutterPx` is a `Readable<number>` the host declares as its
	-- own row content's left PADDING — not a callback, because the gutter stopped
	-- being an offset at the director's 2026-08-12 device round (finding 2) and a
	-- padding is a declaration, not an event.
	editAffordanceView: any,
	editGutterPx: any,
	syncGeometry: ((rectOf: ((string) -> any)?, rootNode: any?) -> ())?,
	bindMotion: (clock: any, now: (() -> number)?) -> (),
	bindController: (controller: any) -> (),
	bindPresent: (presentModal: any, dismiss: any) -> (),
	bindActionSystem: (system: any) -> (),
	bindFocusGraph: (graph: any) -> (),
	handleCancel: (focusedPath: string?) -> boolean,
	-- `{ active: Readable<boolean>, dismiss: () -> (), consume: boolean }` —
	-- fix round 1, finding 3.
	outsideDismiss: any,
}
return nil
