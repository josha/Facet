--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local Env = require("./environment_types")
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
export type Children<V> = ((item: V) -> { V }?) | string
export type HierarchyOptions<V, K> = {
	children: Children<V>?,
	expanded: ComposeTypes.Cell<Selection<K>>?,
	onExpansionChange: ((expanded: Selection<K>) -> ())?,
	indent: Types.ValueNumber?,
}
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
	selectionFrom: Types.Value<{ V }>?,
	selectionIndicator: boolean?,
	selectionMode: ("none" | "single" | "multiple")?,
	selectable: RowPredicate<V>?,
	disabled: RowPredicate<V>?,
	onSelectionChange: ((selection: Selection<K>) -> ())?,
	editing: Types.ValueBoolean?,
}
export type ReorderOptions<V, K> = SelectionOptions<V, K> & {
	collectionId: unknown?,
	drag: ((items: { V }, keys: { K }) -> Env.DraggableSpec)?,
	drop: Env.DropTargetSpec?,
	reorderable: boolean?,
	movable: RowPredicate<V>?,
	onReorder: ((keys: { K }, slot: number, parentKey: K?) -> ())?,
	deletable: boolean?,
	rowDeletable: RowPredicate<V>?,
	onDelete: ((keys: { K }) -> ())?,
	dragLabel: ((item: V) -> string)?,
	autoscroll: boolean?,
	direction: ComposeTypes.OrderedCollectionDirection?,
}
export type Activate<V, K> = (item: V, key: K, input: InputObject?, clickCount: number?) -> ()
export type CollectionOptions<V, K> = Types.ScrollingFrameProps & ReorderOptions<V, K> & HierarchyOptions<V, K> & {
	from: Types.Value<{ V }>,
	render: RowRender<V, K>,
	mode: ComposeTypes.OrderedCollectionMode?,
	itemSize: (Types.ValueNumber | "cards")?,
	cards: { perView: number?, minWidth: number?, peek: number? }?,
	gap: Types.ValueNumber?,
	crossGap: Types.ValueNumber?,
	columns: Types.ValueNumber?,
	minColumnWidth: Types.ValueNumber?,
	rowActions: ((current: ComposeTypes.Readable<V>, key: K) -> RowActionsOptions?)?,
	overscan: number?,
	measured: Types.Value<{ [K]: number }>?,
	measure: boolean?,
	status: (
		ComposeTypes.Cell<ComposeTypes.OrderedCollectionStatus>
		| ComposeTypes.Cell<ComposeTypes.OrderedCollectionStatus?>
	)?,
	controls: ComposeTypes.OrderedCollectionControls<K>?,
	follow: Types.Value<Follow>?,
	followThreshold: number?,
	maxRetained: number?,
	focus: FocusControls<K>?,
	focusPolicy: ("key" | "index")?,
	initialFocus: K?,
	autoFocus: boolean?,
	wrapFocus: boolean?,
	snap: ("none" | "item")?,
	reducedMotion: Types.ValueBoolean?,
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

export type OutlineSpec<V, K> = CollectionSpec<V, K> & { children: Children<V> }
export type OutlineConstructor =
	(<V, K>(spec: KeyedCollectionSpec<V, K> & { children: Children<V> }) -> ScrollingFrame)
	& (<V, _K>(spec: IdentityCollectionSpec<V> & { children: Children<V> }) -> ScrollingFrame)
	& ((
		name: string
	) -> (<V, K>(spec: KeyedCollectionSpec<V, K> & { children: Children<V> }) -> ScrollingFrame)
		& (<V, _K>(spec: IdentityCollectionSpec<V> & { children: Children<V> }) -> ScrollingFrame))

export type RowAction = {
	id: string,
	label: Types.ValueString,
	icon: Types.ValueString?,
	role: InputTypes.ButtonRole?,
	enabled: Types.ValueBoolean?,
	onActivate: (() -> ())?,
}
export type RowEdge = "leading" | "trailing"
export type RowActionsOptions = Types.FrameProps & {
	swipeEnabled: Types.ValueBoolean?,
	leading: Types.Value<{ RowAction }>?,
	trailing: Types.Value<{ RowAction }>?,
	actionWidth: Types.ValueNumber?,
	fullSwipe: (boolean | { leading: boolean?, trailing: boolean? })?,
	open: ComposeTypes.Cell<RowEdge?>?,
	onOpenChange: ((edge: RowEdge?) -> ())?,
	coordinator: ComposeTypes.Cell<{}?>?,
	enabled: Types.ValueBoolean?,
	reducedMotion: Types.ValueBoolean?,
	editing: Types.ValueBoolean?,
}
export type RowActionsSpec = RowActionsOptions & { content: GuiObject | (() -> GuiObject) }
export type CellDraft = { text: string, original: unknown, error: string? }
export type CellEditorOptions = {
	editor: "text" | "number" | "toggle" | "menu",
	value: Types.Value<unknown>,
	onChange: (unknown) -> (),
	draft: ComposeTypes.Cell<CellDraft?>?,
	validate: ((unknown) -> string?)?,
	label: Types.ValueString?,
	enabled: Types.ValueBoolean?,
	busy: Types.ValueBoolean?,
	options: { { value: unknown, label: Types.ValueString } }?,
	min: number?,
	max: number?,
	step: number?,
}
export type CellEditorSpec = Types.FrameProps & CellEditorOptions
export type TableColumn<V, K> = {
	id: string,
	label: Types.ValueString?,
	width: number?,
	minWidth: number?,
	maxWidth: number?,
	priority: (number | "always")?,
	resizable: boolean?,
	sortable: boolean?,
	value: ((item: V) -> unknown)?,
	align: ("start" | "center" | "end")?,
	draft: ((key: K) -> ComposeTypes.Cell<CellDraft?>)?,
	validate: ((value: unknown) -> string?)?,
	render: RowRender<V, K>?,
	editor: ("text" | "number" | "toggle" | "menu")?,
	options: { { value: unknown, label: Types.ValueString } }?,
	min: number?,
	max: number?,
	step: number?,
}
export type TableOptions<V, K> = Types.FrameProps & ReorderOptions<V, K> & HierarchyOptions<V, K> & {
	focusPolicy: ("key" | "index")?,
	initialFocus: K?,
	autoFocus: boolean?,
	wrapFocus: boolean?,
	maxRetained: number?,
	onReachEnd: (() -> ())?,
	from: Types.Value<{ V }>,
	columns: Types.Value<{ TableColumn<V, K> }>,
	itemSize: Types.ValueNumber?,
	gap: Types.ValueNumber?,
	overscan: number?,
	sort: ComposeTypes.Cell<Sort?>?,
	onSortChange: ((sort: Sort) -> ())?,
	widths: ComposeTypes.Cell<{ [string]: number }>?,
	onWidthsChange: ((widths: { [string]: number }) -> ())?,
	onActivate: Activate<V, K>?,
	rowActions: ((current: ComposeTypes.Readable<V>, key: K) -> RowActionsOptions?)?,
	headerHeight: Types.ValueNumber?,
	header: boolean?,
	status: (
		ComposeTypes.Cell<ComposeTypes.OrderedCollectionStatus>
		| ComposeTypes.Cell<ComposeTypes.OrderedCollectionStatus?>
	)?,
	controls: ComposeTypes.OrderedCollectionControls<K>?,
	focus: FocusControls<K>?,
	measure: boolean?,
	measured: Types.Value<{ [K]: number }>?,
	follow: Types.Value<Follow>?,
	followThreshold: number?,
	reducedMotion: Types.ValueBoolean?,
	onCellChange: ((key: K, column: string, value: unknown) -> ())?,
	alternatingRows: Types.ValueBoolean?,
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
	CellEditor: Types.Constructor<CellEditorSpec, Frame>,
	VirtualList: CollectionConstructor,
	VirtualGrid: CollectionConstructor,
	Outline: OutlineConstructor,
	Table: TableConstructor,
	RowActions: Types.Constructor<RowActionsSpec, Frame>,
}
return {}
