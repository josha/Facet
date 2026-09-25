--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local InputTypes = require("./input_types")

export type FocusControls<K> = {
	current: typeof(((nil :: unknown) :: ComposeTypes.FocusScope<K>).current)?,
	focus: typeof(((nil :: unknown) :: ComposeTypes.FocusScope<K>).focus)?,
	clear: typeof(((nil :: unknown) :: ComposeTypes.FocusScope<K>).clear)?,
	next: typeof(((nil :: unknown) :: ComposeTypes.FocusScope<K>).next)?,
	previous: typeof(((nil :: unknown) :: ComposeTypes.FocusScope<K>).previous)?,
	move: typeof(((nil :: unknown) :: ComposeTypes.FocusScope<K>).move)?,
	first: typeof(((nil :: unknown) :: ComposeTypes.FocusScope<K>).first)?,
	last: typeof(((nil :: unknown) :: ComposeTypes.FocusScope<K>).last)?,
	isFocused: typeof(((nil :: unknown) :: ComposeTypes.FocusScope<K>).isFocused)?,
}
export type Selection<K> = { [K]: boolean }
export type Sort = { column: string, direction: "ascending" | "descending" }
export type RowPredicate<V> = (item: V) -> boolean
export type Follow = "end" | "none"
export type RowRender<V, K> = (
	current: ComposeTypes.Readable<V>,
	placement: ComposeTypes.Readable<ComposeTypes.Placement>,
	key: K
) -> GuiObject
export type SelectionOptions<V, K> = {
	selection: ComposeTypes.Cell<Selection<K>>?,
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
	direction: ComposeTypes.OrderedCollectionDirection?,
}
export type Activate<V, K> = (item: V, key: K, input: InputObject?, clickCount: number?) -> ()
export type CollectionOptions<V, K> = Types.ScrollingFrameProps & ReorderOptions<V, K> & {
	from: Types.Value<{ V }>,
	render: RowRender<V, K>,
	mode: ComposeTypes.OrderedCollectionMode?,
	itemSize: Types.Value<number>?,
	gap: Types.Value<number>?,
	crossGap: Types.Value<number>?,
	columns: Types.Value<number>?,
	overscan: number?,
	measured: Types.Value<{ [K]: number }>?,
	measure: boolean?,
	status: ComposeTypes.Cell<ComposeTypes.OrderedCollectionStatus>?,
	controls: ComposeTypes.OrderedCollectionControls<K>?,
	follow: Types.Value<Follow>?,
	followThreshold: number?,
	maxRetained: number?,
	focus: FocusControls<K>?,
	initialFocus: K?,
	autoFocus: boolean?,
	wrapFocus: boolean?,
	snap: ("none" | "item")?,
	reducedMotion: Types.Value<boolean>?,
	onActivate: Activate<V, K>?,
	onReachEnd: (() -> ())?,
}
export type KeyedCollectionSpec<V, K> = CollectionOptions<V, K> & { key: ((item: V, index: number) -> K) | string }
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
	open: ComposeTypes.Cell<RowEdge?>?,
	onOpenChange: ((edge: RowEdge?) -> ())?,
	coordinator: ComposeTypes.Cell<{}?>?,
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
	sort: ComposeTypes.Cell<Sort?>?,
	onSortChange: ((sort: Sort) -> ())?,
	widths: ComposeTypes.Cell<{ [string]: number }>?,
	onWidthsChange: ((widths: { [string]: number }) -> ())?,
	onActivate: Activate<V, K>?,
	rowActions: ((current: ComposeTypes.Readable<V>, key: K) -> RowActionsOptions?)?,
	headerHeight: Types.Value<number>?,
	header: boolean?,
	status: ComposeTypes.Cell<ComposeTypes.OrderedCollectionStatus>?,
	controls: ComposeTypes.OrderedCollectionControls<K>?,
	focus: FocusControls<K>?,
	measure: boolean?,
	measured: Types.Value<{ [K]: number }>?,
	follow: Types.Value<Follow>?,
	followThreshold: number?,
	reducedMotion: Types.Value<boolean>?,
	editing: Types.Value<boolean>?,
	scrolls: boolean?,
	mode: ComposeTypes.OrderedCollectionMode?,
	snap: ("none" | "item")?,
}
export type KeyedTableSpec<V, K> = TableOptions<V, K> & { key: ((item: V, index: number) -> K) | string }
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
