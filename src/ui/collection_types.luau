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
export type SlotControls<K> = { nodeOfKey: ((K) -> GuiObject?)? }
export type Selection<K> = { [K]: boolean }
export type Children<V> = ((item: V) -> { V }?) | string
export type OptionalChildren<V> = { children: Children<V>? }
export type RequiredChildren<V> = { children: Children<V> }
export type HierarchyOptions<V, K> = {
	expanded: ComposeTypes.Value<Selection<K>>?,
	onExpansionChange: ((expanded: Selection<K>) -> ())?,
	indent: Types.ValueNumber?,
}
export type Sort = { column: string, direction: "ascending" | "descending" }
export type RowPredicate<V> = (item: V) -> boolean
export type Follow = "end" | "none"
export type RowRender<V, K> = (
	current: ComposeTypes.ReadOnlyValue<V>,
	placement: ComposeTypes.ReadOnlyValue<ComposeTypes.Placement>,
	key: ComposeTypes.ReadOnlyValue<K>
) -> GuiObject
export type SelectionOptions<V, K> = {
	selection: ComposeTypes.Value<Selection<K>>?,
	selectionFrom: Types.Input<{ V }>?,
	selectionIndicator: boolean?,
	selectionMode: ("none" | "single" | "multiple")?,
	selectable: RowPredicate<V>?,
	disabled: RowPredicate<V>?,
	onSelectionChange: ((selection: Selection<K>) -> ())?,
	editing: Types.ValueBoolean?,
}
export type ReorderOptions<V, K> = {
	collectionId: unknown?,
	drag: ((items: { V }, keys: { K }) -> Env.DraggableSpec)?,
	drop: Env.DropTargetSpec?,
	rowDrop: ((ComposeTypes.ReadOnlyValue<V>, K) -> Env.DropTargetSpec?)?,
	reorderable: boolean?,
	movable: RowPredicate<V>?,
	onReorder: ((keys: { K }, slot: number, parentKey: K?) -> ())?,
	deletable: boolean?,
	rowDeletable: RowPredicate<V>?,
	onDelete: ((keys: { K }) -> ())?,
	dragLabel: ((item: V) -> string)?,
	autoscroll: boolean?,
}
export type Activate<V, K> = (item: V, key: K, input: InputObject?, clickCount: number?) -> ()
export type CollectionOptions<V, K> = {
	from: Types.Input<{ V }>,
	recycle: boolean?,
	slots: Types.Input<{ K }>?,
	slotControls: SlotControls<K>?,
	render: RowRender<V, K>?,
	mode: ComposeTypes.OrderedCollectionMode?,
	itemSize: (Types.ValueNumber | "cards")?,
	cards: { perView: number?, minWidth: number?, peek: number? }?,
	gap: Types.ValueNumber?,
	crossGap: Types.ValueNumber?,
	columns: Types.ValueNumber?,
	minColumnWidth: Types.ValueNumber?,
	minColumns: Types.ValueNumber?,
	hug: boolean?,
	rowActions: ((current: ComposeTypes.ReadOnlyValue<V>, key: K) -> RowActionsShape?)?,
	overscan: number?,
	measured: Types.Input<{ [K]: number }>?,
	measure: boolean?,
	status: (
		ComposeTypes.Value<ComposeTypes.OrderedCollectionStatus>
		| ComposeTypes.Value<ComposeTypes.OrderedCollectionStatus?>
	)?,
	controls: ComposeTypes.OrderedCollectionControls<K>?,
	follow: Types.Input<Follow>?,
	followThreshold: number?,
	scrollReset: Types.Input<string>?,
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
	contentOverflow: Types.Input<"visible" | "clip">?,
	direction: ComposeTypes.OrderedCollectionDirection?,
}
export type Keyed<V, K> = { key: ((item: V, index: number) -> K) | string }
export type Identity = { key: nil? }

export type RowAction = {
	id: string,
	label: Types.ValueString,
	icon: Types.ValueString?,
	role: InputTypes.ButtonRole?,
	enabled: Types.ValueBoolean?,
	onActivate: (() -> ())?,
}
export type RowEdge = "leading" | "trailing"
export type RowActionsFields = {
	actionPlacement: ("trailing" | "bottom")?,
	swipeEnabled: Types.ValueBoolean?,
	leading: Types.Input<{ RowAction }>?,
	trailing: Types.Input<{ RowAction }>?,
	actionWidth: Types.ValueNumber?,
	fullSwipe: (boolean | { leading: boolean?, trailing: boolean? })?,
	open: ComposeTypes.Value<RowEdge?>?,
	onOpenChange: ((edge: RowEdge?) -> ())?,
	coordinator: ComposeTypes.Value<{}?>?,
	enabled: Types.ValueBoolean?,
	reducedMotion: Types.ValueBoolean?,
	editing: Types.ValueBoolean?,
}
export type RowActionsShape = Types.FrameProps & RowActionsFields
export type RowActionsContent = { content: Types.GuiInstance | (() -> GuiObject) }
export type CellDraft = { text: string, original: unknown, error: string? }
export type CellEditorOptions = {
	editor: "text" | "number" | "toggle" | "menu",
	value: Types.Input<unknown>,
	onChange: (unknown) -> (),
	draft: ComposeTypes.Value<CellDraft?>?,
	editing: ComposeTypes.Value<boolean>?,
	editLabel: Types.ValueString?,
	validate: ((unknown) -> string?)?,
	label: Types.ValueString?,
	enabled: Types.ValueBoolean?,
	busy: Types.ValueBoolean?,
	options: { { value: unknown, label: Types.ValueString } }?,
	min: number?,
	max: number?,
	step: number?,
}
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
	wrap: boolean?,
	draft: ((key: K) -> ComposeTypes.Value<CellDraft?>)?,
	editLabel: Types.ValueString?,
	editable: ((item: V) -> boolean)?,
	validate: ((value: unknown) -> string?)?,
	render: RowRender<V, K>?,
	detailRender: RowRender<V, K>?,
	editor: ("text" | "number" | "toggle" | "menu")?,
	options: { { value: unknown, label: Types.ValueString } }?,
	min: number?,
	max: number?,
	step: number?,
}
export type TableOptions<V, K> = {
	focusPolicy: ("key" | "index")?,
	initialFocus: K?,
	autoFocus: boolean?,
	wrapFocus: boolean?,
	maxRetained: number?,
	onReachEnd: (() -> ())?,
	from: Types.Input<{ V }>,
	columns: Types.Input<{ TableColumn<V, K> }>,
	itemSize: Types.ValueNumber?,
	gap: Types.ValueNumber?,
	overscan: number?,
	sort: ComposeTypes.Value<Sort?>?,
	onSortChange: ((sort: Sort) -> ())?,
	widths: ComposeTypes.Value<{ [string]: number }>?,
	onWidthsChange: ((widths: { [string]: number }) -> ())?,
	onActivate: Activate<V, K>?,
	rowActions: ((current: ComposeTypes.ReadOnlyValue<V>, key: K) -> RowActionsShape?)?,
	headerHeight: Types.ValueNumber?,
	header: boolean?,
	status: (
		ComposeTypes.Value<ComposeTypes.OrderedCollectionStatus>
		| ComposeTypes.Value<ComposeTypes.OrderedCollectionStatus?>
	)?,
	controls: ComposeTypes.OrderedCollectionControls<K>?,
	focus: FocusControls<K>?,
	measure: boolean?,
	measured: Types.Input<{ [K]: number }>?,
	follow: Types.Input<Follow>?,
	followThreshold: number?,
	reducedMotion: Types.ValueBoolean?,
	onCellChange: ((key: K, column: string, value: unknown) -> ())?,
	alternatingRows: Types.ValueBoolean?,
	scrolls: boolean?,
	mode: ComposeTypes.OrderedCollectionMode?,
	snap: ("none" | "item")?,
	recycle: boolean?,
}
export type ReorderShape<V, K> = SelectionOptions<V, K> & ReorderOptions<V, K>
export type CollectionShape<V, K> =
	Types.ScrollingFrameProps
	& SelectionOptions<V, K>
	& ReorderOptions<V, K>
	& HierarchyOptions<V, K>
	& OptionalChildren<V>
	& CollectionOptions<V, K>
export type TableShape<V, K> =
	Types.FrameProps
	& SelectionOptions<V, K>
	& ReorderOptions<V, K>
	& HierarchyOptions<V, K>
	& OptionalChildren<V>
	& TableOptions<V, K>
return {}
