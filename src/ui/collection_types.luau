--!strict
local Compose = require("../vendor/compose/core")
local Types = require("./types")
local InputTypes = require("./input_types")

export type FocusControls<K> = {
	current: typeof(((nil :: unknown) :: Compose.FocusScope<K>).current)?,
	focus: typeof(((nil :: unknown) :: Compose.FocusScope<K>).focus)?,
	clear: typeof(((nil :: unknown) :: Compose.FocusScope<K>).clear)?,
	next: typeof(((nil :: unknown) :: Compose.FocusScope<K>).next)?,
	previous: typeof(((nil :: unknown) :: Compose.FocusScope<K>).previous)?,
	move: typeof(((nil :: unknown) :: Compose.FocusScope<K>).move)?,
	first: typeof(((nil :: unknown) :: Compose.FocusScope<K>).first)?,
	last: typeof(((nil :: unknown) :: Compose.FocusScope<K>).last)?,
	isFocused: typeof(((nil :: unknown) :: Compose.FocusScope<K>).isFocused)?,
}
export type Selection<K> = { [K]: boolean }
export type Sort = { column: string, direction: "ascending" | "descending" }
export type RowPredicate<V> = (item: V) -> boolean
export type RowRender<V, K> = (
	current: Compose.Readable<V>,
	placement: Compose.Readable<Compose.Placement>,
	key: K
) -> GuiObject
export type SelectionOptions<V, K> = {
	selection: Compose.Cell<Selection<K>>?,
	selectionMode: ("none" | "single" | "multi")?,
	selectable: RowPredicate<V>?,
	disabled: RowPredicate<V>?,
	onSelectionChange: ((selection: Selection<K>) -> ())?,
}
export type ReorderOptions<V, K> = SelectionOptions<V, K> & {
	reorderable: boolean?,
	movable: RowPredicate<V>?,
	onReorder: ((keys: { K }, slot: number) -> ())?,
	dragLabel: ((item: V) -> string)?,
	direction: Compose.OrderedCollectionDirection?,
}
export type CollectionOptions<V, K> = Types.ScrollingFrameProps & ReorderOptions<V, K> & {
	from: Types.Value<{ V }>,
	render: RowRender<V, K>,
	mode: Compose.OrderedCollectionMode?,
	itemSize: Types.Value<number>?,
	gap: Types.Value<number>?,
	crossGap: Types.Value<number>?,
	columns: Types.Value<number>?,
	overscan: number?,
	measured: Types.Value<{ [K]: number }>?,
	measure: boolean?,
	status: Compose.Cell<Compose.OrderedCollectionStatus>?,
	controls: Compose.OrderedCollectionControls<K>?,
	follow: ("end" | "none")?,
	followThreshold: number?,
	maxRetained: number?,
	focus: FocusControls<K>?,
	initialFocus: K?,
	autoFocus: boolean?,
	wrapFocus: boolean?,
	snap: ("none" | "item")?,
	reducedMotion: Types.Value<boolean>?,
	onActivate: ((item: V, key: K) -> ())?,
	onReachEnd: (() -> ())?,
}
export type KeyedCollectionSpec<V, K> = CollectionOptions<V, K> & { key: (item: V, index: number) -> K }
export type IdentityCollectionSpec<V> = CollectionOptions<V, V> & { key: nil? }
export type CollectionSpec<V, K> = KeyedCollectionSpec<V, K> | IdentityCollectionSpec<V>
export type CollectionConstructor =
	(<V, K>(spec: KeyedCollectionSpec<V, K>) -> ScrollingFrame)
	& (<V, _K>(spec: IdentityCollectionSpec<V>) -> ScrollingFrame)
	& ((
		name: string
	) -> (
		(<V, K>(spec: KeyedCollectionSpec<V, K>) -> ScrollingFrame)
		& (<V, _K>(spec: IdentityCollectionSpec<V>) -> ScrollingFrame)
	))

export type RowAction = {
	id: string,
	label: Types.Value<string>,
	icon: Types.Value<string>?,
	role: InputTypes.ButtonRole?,
	enabled: Types.Value<boolean>?,
	onActivate: (() -> ())?,
}
export type RowEdge = "leading" | "trailing"
export type RowActionsOptions = Types.FrameProps & {
	leading: Types.Value<{ RowAction }>?,
	trailing: Types.Value<{ RowAction }>?,
	actionWidth: Types.Value<number>?,
	fullSwipe: (boolean | { leading: boolean?, trailing: boolean? })?,
	open: Compose.Cell<RowEdge?>?,
	onOpenChange: ((edge: RowEdge?) -> ())?,
	coordinator: Compose.Cell<{}?>?,
	enabled: Types.Value<boolean>?,
	reducedMotion: Types.Value<boolean>?,
	editing: Types.Value<boolean>?,
}
export type RowActionsSpec = RowActionsOptions & { content: GuiObject | (() -> GuiObject) }
export type TableColumn<V, K> = {
	id: string,
	label: Types.Value<string>?,
	width: number?,
	minWidth: number?,
	maxWidth: number?,
	priority: (number | "always")?,
	resizable: boolean?,
	sortable: boolean?,
	value: ((item: V) -> unknown)?,
	render: RowRender<V, K>?,
}
export type TableOptions<V, K> = Types.FrameProps & ReorderOptions<V, K> & {
	from: Types.Value<{ V }>,
	columns: Types.Value<{ TableColumn<V, K> }>,
	itemSize: Types.Value<number>?,
	gap: Types.Value<number>?,
	overscan: number?,
	sort: Compose.Cell<Sort?>?,
	onSortChange: ((sort: Sort) -> ())?,
	widths: Compose.Cell<{ [string]: number }>?,
	onWidthsChange: ((widths: { [string]: number }) -> ())?,
	onActivate: ((item: V, key: K) -> ())?,
	rowActions: ((current: Compose.Readable<V>, key: K) -> RowActionsOptions?)?,
	headerHeight: Types.Value<number>?,
	header: boolean?,
	status: Compose.Cell<Compose.OrderedCollectionStatus>?,
	controls: Compose.OrderedCollectionControls<K>?,
	focus: FocusControls<K>?,
	measure: boolean?,
	measured: Types.Value<{ [K]: number }>?,
	follow: ("end" | "none")?,
	followThreshold: number?,
	reducedMotion: Types.Value<boolean>?,
	editing: Types.Value<boolean>?,
	scrolls: boolean?,
	mode: Compose.OrderedCollectionMode?,
	snap: ("none" | "item")?,
}
export type KeyedTableSpec<V, K> = TableOptions<V, K> & { key: (item: V, index: number) -> K }
export type IdentityTableSpec<V> = TableOptions<V, V> & { key: nil? }
export type TableSpec<V, K> = KeyedTableSpec<V, K> | IdentityTableSpec<V>
export type TableConstructor =
	(<V, K>(spec: KeyedTableSpec<V, K>) -> Frame)
	& (<V, _K>(spec: IdentityTableSpec<V>) -> Frame)
	& ((name: string) -> (<V, K>(spec: KeyedTableSpec<V, K>) -> Frame) & (<V, _K>(spec: IdentityTableSpec<V>) -> Frame))
export type CollectionControls = {
	VirtualList: CollectionConstructor,
	VirtualGrid: CollectionConstructor,
	Table: TableConstructor,
	RowActions: Types.Constructor<RowActionsSpec, Frame>,
}
return {}
