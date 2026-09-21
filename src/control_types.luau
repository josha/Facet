--!strict
-- Type-only contracts. Every control keeps its types in `src/spec_types/<control>.luau`, so
-- reading a `Spec` here loads no control: `require(Facet)` stays as light as it was.
local core = require("./core/contract")
local bp = require("./blueprint")
local env = require("./env/environment")
local resources = require("./async/resources")
local rowActions = require("./controls/row_actions_spec")
local autoscroll = require("./input/autoscroll")
local drag = require("./input/drag_contract")
local menu = require("./spec_types/menu")
local navigation_stackControl = require("./spec_types/navigation_stack")
local tableControl = require("./spec_types/table")
local sliderControl = require("./spec_types/slider")
local stepperControl = require("./spec_types/stepper")
local pickerControl = require("./spec_types/picker")
local picker_menuControl = require("./spec_types/picker_menu")
local tab_viewControl = require("./spec_types/tab_view")
local labelControl = require("./spec_types/label")
local ratingControl = require("./spec_types/rating")
local text_inputControl = require("./spec_types/text_input")
local progress_viewControl = require("./spec_types/progress_view")
local level_pickerControl = require("./spec_types/level_picker")
local disclosure_groupControl = require("./spec_types/disclosure_group")
local row_actionsControl = require("./spec_types/row_actions")
local calloutControl = require("./spec_types/callout")
local radial_menuControl = require("./spec_types/radial_menu")
local alertControl = require("./spec_types/alert")
local sheetControl = require("./spec_types/sheet")
local page_viewControl = require("./spec_types/page_view")
local collapsible_viewControl = require("./spec_types/collapsible_view")
export type CellContext<T> = { scope: core.Owner, current: (core.Use) -> T }
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
	follow: bp.Bound<"end" | "none">?,
	followThreshold: number?,
	scrollNavigation: { position: core.Cell<number>, active: bp.Bound<boolean>? }?,
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
-- One flat table, not `Options & {…}`: Luau checks a literal against an
-- intersection invariantly and would refuse a `Cell` where a `Readable` is asked for.
export type VirtualListSpec<T> = {
	id: string?,
	axis: ("x" | "y")?,
	width: bp.Bound<bp.Dim>?,
	itemExtent: (number | core.Readable<number> | "cards" | "measured" | ((T, core.Use) -> number))?,
	rowHeight: (number | core.Readable<number> | ((T, core.Use) -> number))?,
	viewportExtent: (number | core.Readable<number> | "auto")?,
	viewportHeight: (number | core.Readable<number>)?,
	estimatedItemExtent: (number | core.Readable<number>)?,
	rowGap: bp.Bound<number | string>?,
	follow: bp.Bound<"end" | "none">?,
	followThreshold: number?,
	scrollNavigation: { position: core.Cell<number>, active: bp.Bound<boolean>? }?,
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
	rows: core.Readable<{ T }> | ((core.Use) -> { T }),
	key: ((T) -> string) | string,
	cell: (T, CellContext<T>) -> any,
	ref: ((record: any) -> ())?,
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
export type VirtualGridSpec<T> = {
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
	items: core.Readable<{ T }> | ((core.Use) -> { T }),
	key: string | ((T) -> string),
	cell: (T, GridCellContext<T>) -> any,
	onActivate: ((T, bp.ActivationMetadata?) -> ())?,
	ref: ((record: any) -> ())?,
}
export type ViewVirtualGridSpec<T> = VirtualGridOptions & {
	items: core.Readable<{ T }> | (() -> { T }),
	key: string | ((T) -> string),
	row: (() -> T) -> bp.Blueprint,
	onActivate: ((T, bp.ActivationMetadata?) -> ())?,
}
type BooleanCell = core.Cell<boolean>
export type ChipSpec<V = BooleanCell> = {
	controlSize: bp.Bound<("compact" | "regular" | "large")?>?,
	appearance: bp.Bound<("standard" | "utility")?>?,
	corners: ("pill" | "square")?,
	leading: bp.Blueprint?,
	trailing: bp.Blueprint?,
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
	acquire: (core.Owner, string, { retry: resources.RetryOpts? }?) -> ResourceHandle,
}
export type AsyncImageOptions = {
	id: string?,
	key: string,
	provider: ResourceProvider,
	retry: resources.RetryOpts?,
	dimmed: bp.Bound<boolean>?,
	failureLabel: string?,
	width: bp.Bound<bp.Dim>?,
	height: bp.Bound<bp.Dim>?,
	scaleMode: bp.Bound<"fit" | "fill" | "crop" | "stretch" | "tile" | "slice">?,
	tileSize: { width: number, height: number }?,
	sliceCenter: bp.ImageSliceCenter?,
	sliceScale: number?,
	resample: bp.Bound<"default" | "pixelated">?,
}
export type AsyncImageSpec = {
	id: string?,
	key: string,
	provider: ResourceProvider,
	retry: resources.RetryOpts?,
	dimmed: bp.Bound<boolean>?,
	failureLabel: string?,
	width: bp.Bound<bp.Dim>?,
	height: bp.Bound<bp.Dim>?,
	ref: ((record: any) -> ())?,
	scaleMode: bp.Bound<"fit" | "fill" | "crop" | "stretch" | "tile" | "slice">?,
	tileSize: { width: number, height: number }?,
	sliceCenter: bp.ImageSliceCenter?,
	sliceScale: number?,
	resample: bp.Bound<"default" | "pixelated">?,
}

type StringCell = core.Cell<string>

export type ConfirmationSpec = {
	title: bp.Bound<string>,
	message: bp.Bound<string>?,
	acceptLabel: string?,
	cancelLabel: string?,
	destructive: boolean?,
}
export type SemanticRow = {
	description: bp.Bound<string>?,
	icon: bp.Bound<string>?,
	value: bp.Bound<string>?,
}
export type ButtonShortcut = { keyCode: string, modifiers: { shift: boolean? }? }
export type ButtonSpec = {
	controlSize: bp.Bound<("compact" | "regular" | "large")?>?,
	appearance: bp.Bound<("standard" | "emphasis" | "soft" | "utility" | "link")?>?,
	corners: ("pill" | "square")?,
	over: "media"?,
	name: string?,
	trailingIcon: string?,
	image: bp.Bound<string>?,
	imageAspectRatio: number?,
	imageFraming: bp.ImageFraming?,
	subtitle: bp.Bound<string>?,
	row: SemanticRow?,
	pop: boolean?,
	id: string?,
	label: bp.Bound<string>?,
	children: { bp.Blueprint }?,
	enabled: bp.Bound<boolean>?,
	busy: bp.Bound<boolean>?,
	onActivate: ((bp.ActivationMetadata?) -> ())?,
	repeatDelay: number?,
	repeatInterval: number?,
	shortcut: ButtonShortcut?,
	dialogAction: ("default" | "cancel")?,
	role: bp.Bound<string>?,
	width: bp.Bound<bp.Dim>?,
	height: bp.Bound<bp.Dim>?,
	-- layout, paint and lifecycle keys shared with every box
	compactLabel: any?,
	surface: any?,
	selected: any?,
	gap: any?,
	align: any?,
	shrinkWeight: any?,
	focusable: any?,
	help: any?,
	icon: string?,
	shape: any?,
	textSize: any?,
	padding: any?,
	hidden: any?,
	anchor: any?,
	alignH: any?,
	alignV: any?,
	margin: any?,
	offsetX: any?,
	offsetY: any?,
	zIndex: any?,
	layoutPriority: any?,
	traversalPriority: any?,
	gridSpan: any?,
	disclose: any?,
	onAppear: any?,
	onDisappear: any?,
	onPointerDown: any?,
	onPointerUp: any?,
	onPointerCancel: any?,
	onPointerMove: any?,
	ref: ((record: any) -> ())?,
	[number]: any,
}
type BooleanSource = core.Readable<boolean> | ((core.Use) -> boolean)
export type ToggleSpec<V = BooleanSource> = {
	ref: ((record: any) -> ())?,
	row: SemanticRow?,
	id: string?,
	label: bp.Bound<string>?,
	value: V,
	mixed: BooleanSource?, -- construction restricts this to checkbox
	presentation: ("switch" | "checkbox" | "button")?,
	children: { bp.Blueprint }?, -- construction restricts this to button
	enabled: bp.Bound<boolean>?,
	onChange: ((boolean) -> ())?,
}
export type ComboBoxOption =
	{
		id: string,
		label: bp.Bound<string>,
		description: bp.Bound<string>?,
		icon: bp.Bound<string>?,
		enabled: bp.Bound<boolean>?,
		divider: false?,
	}
	| { divider: true }
export type ComboBoxSpec<V = StringCell, S = StringCell> = {
	ref: ((record: any) -> ())?,
	id: string?,
	value: V,
	text: S,
	options: bp.Bound<{ ComboBoxOption }>,
	enabled: bp.Bound<boolean>?,
	acceptCustom: (string) -> (boolean, string?),
	onChange: ((string) -> ())?,
	commitOnFocusLost: boolean?,
	placeholder: string?,
	env: env.Env?,
}
export type SplitButtonSpec = {
	ref: ((record: any) -> ())?,
	id: string?,
	label: bp.Bound<string>?,
	menuLabel: bp.Bound<string>?,
	onActivate: (bp.ActivationMetadata?) -> (),
	items: { menu.Item },
	enabled: bp.Bound<boolean>?,
	busy: bp.Bound<boolean>?,
	shortcut: ButtonShortcut?,
	env: env.Env?,
}

-- WHAT `app.controls` IS TO THE TYPE CHECKER. A constructor takes its spec, or
-- a name and then its spec. Naming every composite here is what lets the
-- analyzer check a spec's fields at the call site; primitives and modifiers
-- ride the open indexer.
export type Node = any
export type Record<Api> = { api: Api, dump: (() -> any)? }
-- BOTH FORMS CHECK THEIR SPEC: `UI.Button({ … })` and `UI.Button("Go")({ … })`.
-- Luau checks an overloaded call without an expected type, so a spec field has
-- to name what authors pass it; that is why `Readable<T>` and `Bound<T>` spell
-- out `Cell<T>`, `Formula<T>` and `(use) -> T`.
export type Constructor<S> = ((spec: S) -> Node) & ((id: string) -> (spec: S) -> Node)
export type Controls = {
	Button: Constructor<ButtonSpec>,
	Toggle: Constructor<ToggleSpec>,
	ComboBox: Constructor<ComboBoxSpec>,
	SplitButton: Constructor<SplitButtonSpec>,
	Chip: Constructor<ChipSpec>,
	AsyncImage: Constructor<AsyncImageSpec>,
	VirtualList: Constructor<VirtualListSpec<any>>,
	VirtualGrid: Constructor<VirtualGridSpec<any>>,
	NavigationStack: Constructor<navigation_stackControl.Spec>,
	Table: Constructor<tableControl.Spec>,
	Slider: Constructor<sliderControl.Spec>,
	Stepper: Constructor<stepperControl.Spec>,
	Picker: Constructor<pickerControl.Spec>,
	PopupButton: Constructor<picker_menuControl.Spec>,
	Menu: Constructor<menu.Spec>,
	TabView: Constructor<tab_viewControl.Spec>,
	Label: Constructor<labelControl.Spec>,
	Rating: Constructor<ratingControl.Spec>,
	TextInput: Constructor<text_inputControl.Spec>,
	ProgressView: Constructor<progress_viewControl.Spec>,
	LevelPicker: Constructor<level_pickerControl.Spec>,
	DisclosureGroup: Constructor<disclosure_groupControl.Spec>,
	RowActions: Constructor<row_actionsControl.Spec>,
	Callout: Constructor<calloutControl.Spec>,
	RadialMenu: Constructor<radial_menuControl.Spec>,
	Alert: Constructor<alertControl.Spec>,
	Sheet: Constructor<sheetControl.Spec>,
	PageView: Constructor<page_viewControl.Spec>,
	CollapsibleView: Constructor<collapsible_viewControl.Spec>,
	-- primitives (`VStack`, `Text`, …), regions and modifiers
	[string]: any,
}
-- What `Facet.new` answers: the constructor table is typed, and the rest of the
-- application handle is documented in docs/reference/api.md.
export type App = {
	controls: Controls,
	[string]: any,
}
return nil
