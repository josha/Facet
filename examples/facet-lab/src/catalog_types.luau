--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type RobloxTypes = typeof(require("@repo/tools/typecheck/aliases").RobloxTypes)
type CellFactory = typeof(require("@repo/tools/typecheck/aliases").CellFactory)
type BooleanCell = typeof(require("@repo/tools/typecheck/aliases").BooleanCell)
type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type FacetModule = typeof(require("@repo/tools/typecheck/aliases").FacetModule)
type App = typeof(require("@repo/tools/typecheck/aliases").App)
type ControlSize = typeof(require("@repo/tools/typecheck/aliases").ControlSizeValue)
type MenuItem = typeof(require("@repo/tools/typecheck/aliases").MenuItem)
type PickerOption = typeof(require("@repo/tools/typecheck/aliases").PickerOption)
type OverlayAction = typeof(require("@repo/tools/typecheck/aliases").OverlayAction)
type DialogAction = typeof(require("@repo/tools/typecheck/aliases").DialogAction)
type TableColumn = typeof(require("@repo/tools/typecheck/aliases").TableColumn)
type StackProps = typeof(require("@repo/tools/typecheck/aliases").StackProps)
type SheetDetent = typeof(require("@repo/tools/typecheck/aliases").SheetDetent)
type DropInfo = typeof(require("@repo/tools/typecheck/aliases").DropInfo)
type Readable<T> = { peek: (Readable<T>) -> T }
type Cell<T> = Readable<T> & { set: (Cell<T>, T) -> (), update: (Cell<T>, (T) -> T) -> () }
type Use = <T>(Readable<T>) -> T

export type Context = {
	UI: FacetControls,
	Compose: ComposeModule,
	Facet: FacetModule,
	Host: RobloxHost,
	types: RobloxTypes,
	app: App,
	logical: Readable<{ width: number, height: number }>,
	cell: CellFactory,
	log: (string) -> (...unknown) -> (),
}
export type Properties = { [any]: any }
export type Builder = (Context) -> Properties
export type Source = Properties | Builder
export type Axis = {
	key: string,
	values: { unknown },
	matrix: boolean?,
	props: Source?,
	implies: { [string]: Source }?,
}
export type State = {
	name: string,
	props: Source,
	across: (string | boolean)?,
	matrixOnly: boolean?,
	cellWidth: number?,
	cellHeight: number?,
}
export type Make = (FacetControls, never, Context) -> Instance
export type Valid = (never) -> boolean
export type PageDefinition = {
	family: string,
	title: string?,
	alias: string?,
	purpose: string,
	note: string?,
	alternatives: string?,
	snippet: string?,
	scenarios: { string }?,
	demonstrates: { string }?,
	surface: string?,
	host: string?,
	recipe: boolean?,
	facet: boolean?,
	matrix: boolean?,
	fills: boolean?,
	stateAxis: string?,
	cellWidth: number?,
	cellHeight: number?,
	base: Builder?,
	axes: { Axis },
	states: { State },
	make: Make?,
	valid: Valid?,
}

return {}
