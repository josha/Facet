--!strict
-- Type-only contracts for deferred controls; importing these does not load their implementations.
local core = require("./core/contract")
local bp = require("./blueprint")
local env = require("./env/environment")
local resources = require("./async/resources")
local rowActions = require("./controls/row_actions_spec")
local autoscroll = require("./input/autoscroll")
local drag = require("./input/drag_contract")
export type CellContext<T> = { scope: core.Scope, current: (core.Use) -> T }
export type GridCellContext<T> = CellContext<T> & { index: number, line: number, lane: number }
export type RowAction = rowActions.ActionSpec
export type RowActions = {
	leading: { RowAction }?,
	trailing: { RowAction }?,
	fullSwipe: (boolean | { leading: boolean?, trailing: boolean? })?,
}
export type Navigation = {
	name: string?,
	wrap: boolean?,
	containment: string?,
	entry: string?,
	exit: { [string]: string }?,
}
export type Autoscroll = autoscroll.Opts
export type DropTarget<T> = drag.TargetSpec
export type VirtualListOptions<T> = {
	id: string?,
	axis: ("x" | "y")?,
	width: bp.Bound<bp.Dim>?,
	itemExtent: (number | core.Readable<number> | "cards" | "measured" | ((T, core.Use) -> number))?,
	rowHeight: (number | core.Readable<number> | ((T, core.Use) -> number))?,
	viewportExtent: (number | core.Readable<number> | "auto")?,
	viewportHeight: (number | core.Readable<number>)?,
	estimatedItemExtent: (number | core.Readable<number>)?,
	rowGap: bp.Bound<number | string>?,
	overscan: number?,
	cards: { perView: number?, minWidth: number?, peek: number? }?,
	crossExtent: ("hug" | "measured")?,
	env: env.Env?,
	snap: ("none" | "item")?,
	selection: ("none" | "single")?,
	selectionPaint: ("native" | "none")?,
	onSelect: ((T, string) -> ())?,
	onActivate: ((T, bp.ActivationMetadata?) -> ())?,
	reorderable: boolean?,
	onReorder: ((string, number) -> ())?,
	reorderMotion: string?,
	grabOnActivate: boolean?,
	focusPolicy: string?,
	rowActions: ((T) -> RowActions?)?,
	rowFocusable: ((T) -> boolean)?,
	rowSelectable: ((T) -> boolean)?,
	rowMovable: ((T) -> boolean)?,
	rowDeletable: ((T) -> boolean)?,
	rowDropTarget: ((T) -> DropTarget<T>?)?,
	dropSurface: boolean?,
	navigation: Navigation?,
	autoscroll: (boolean | Autoscroll)?,
	motionClock: { now: () -> number }?,
}
export type VirtualListSpec<T> = VirtualListOptions<T> & {
	rows: core.Readable<{ T }>,
	key: (T) -> string,
	cell: (T, CellContext<T>) -> bp.Blueprint,
}
export type ViewVirtualListSpec<T> = VirtualListOptions<T> & {
	items: core.Readable<{ T }> | (() -> { T }),
	key: string | ((T) -> string),
	row: (() -> T) -> bp.Blueprint,
}
export type VirtualGridOptions = {
	id: string?,
	axis: ("x" | "y")?,
	width: bp.Bound<bp.Dim>?,
	columns: number | core.Readable<number>,
	itemExtent: number | core.Readable<number> | ((number, core.Use) -> number),
	viewportExtent: (number | core.Readable<number> | "auto")?,
	gap: bp.Bound<number | string>?,
	rowGap: bp.Bound<number | string>?,
	overscan: number?,
	snap: ("none" | "item")?,
	env: env.Env?,
}
export type VirtualGridSpec<T> = VirtualGridOptions & {
	items: core.Readable<{ T }>,
	key: string | ((T) -> string),
	cell: (T, GridCellContext<T>) -> bp.Blueprint,
	onActivate: ((T, bp.ActivationMetadata?) -> ())?,
}
export type ViewVirtualGridSpec<T> = VirtualGridOptions & {
	items: core.Readable<{ T }> | (() -> { T }),
	key: string | ((T) -> string),
	row: (() -> T) -> bp.Blueprint,
	onActivate: ((T, bp.ActivationMetadata?) -> ())?,
}
type BooleanSignal = core.Signal<boolean>
export type ChipSpec<V = BooleanSignal> = {
	id: string?,
	label: bp.Bound<string>?,
	selected: V,
	enabled: bp.Bound<boolean>?,
	onToggle: ((boolean) -> ())?,
}
export type ResourceHandle = {
	state: core.Readable<string>,
	value: core.Readable<any>,
	error: core.Readable<any>,
	release: () -> (),
}
export type ResourceProvider = {
	acquire: (core.Scope, string, { retry: resources.RetryOpts? }?) -> ResourceHandle,
}
export type AsyncImageOptions = {
	id: string,
	key: string,
	provider: ResourceProvider,
	retry: resources.RetryOpts?,
	dimmed: bp.Bound<boolean>?,
	failureLabel: string?,
	width: bp.Bound<bp.Dim>?,
	height: bp.Bound<bp.Dim>?,
}
export type AsyncImageSpec = AsyncImageOptions & { scope: core.Scope }
return nil
