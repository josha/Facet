--!strict

export type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
export type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
export type RobloxTypes = typeof(require("@repo/tools/typecheck/aliases").RobloxTypes)
export type CellFactory = typeof(require("@repo/tools/typecheck/aliases").CellFactory)
export type BooleanCell = typeof(require("@repo/tools/typecheck/aliases").BooleanCell)
export type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
export type FacetModule = typeof(require("@repo/tools/typecheck/aliases").FacetModule)
export type App = typeof(require("@repo/tools/typecheck/aliases").App)
export type ControlSize = typeof(require("@repo/tools/typecheck/aliases").ControlSizeValue)
export type MenuItem = typeof(require("@repo/tools/typecheck/aliases").MenuItem)
export type PickerOption = typeof(require("@repo/tools/typecheck/aliases").PickerOption)
export type OverlayAction = typeof(require("@repo/tools/typecheck/aliases").OverlayAction)
export type DialogAction = typeof(require("@repo/tools/typecheck/aliases").DialogAction)
export type TableColumn = typeof(require("@repo/tools/typecheck/aliases").TableColumn)
export type StackProps = typeof(require("@repo/tools/typecheck/aliases").StackProps)
export type SheetDetent = typeof(require("@repo/tools/typecheck/aliases").SheetDetent)
export type DropInfo = typeof(require("@repo/tools/typecheck/aliases").DropInfo)
type ExampleContext = typeof(require("@repo/examples/types").Context)
export type Use = typeof(require("@repo/tools/typecheck/aliases").Use)

export type Context = {
	UI: FacetControls,
	Compose: ComposeModule,
	Facet: FacetModule,
	Host: RobloxHost,
	types: RobloxTypes,
	app: App,
	ctx: ExampleContext?,
	logical: ReadOnlyValue<{ width: number, height: number }>,
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
	read props: Source?,
	implies: { [string]: Source }?,
}
export type State = {
	name: string,
	read props: Source,
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
	read base: Builder?,
	read axes: { Axis }?,
	read states: { State }?,
	read make: Make?,
	read valid: Valid?,
}

export type MenuCheck = typeof(require("@repo/tools/typecheck/aliases").MenuCheck)
export type MenuChoice = typeof(require("@repo/tools/typecheck/aliases").StringMenuChoice)
export type MenuSubmenu = typeof(require("@repo/tools/typecheck/aliases").StringMenuSubmenu)
export type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
export type MenuCommand = typeof(require("@repo/tools/typecheck/aliases").MenuCommand)
export type RadialMenuSpec = typeof(require("@repo/tools/typecheck/aliases").RadialMenuSpec)
export type RadialItem = typeof(require("@repo/tools/typecheck/aliases").StringRadialItem)
export type PopoverSpec = typeof(require("@repo/tools/typecheck/aliases").PopoverSpec)
export type AdaptiveStackProps = typeof(require("@repo/tools/typecheck/aliases").AdaptiveStackProps)
export type CivilDate = typeof(require("@repo/tools/typecheck/aliases").CivilDate)
export type CivilLocale = typeof(require("@repo/tools/typecheck/aliases").CivilLocale)
export type SliderProps = typeof(require("@repo/tools/typecheck/aliases").SliderProps)
export type ToggleCellProps = typeof(require("@repo/tools/typecheck/aliases").ToggleCellProps)
export type SliderCellProps = typeof(require("@repo/tools/typecheck/aliases").SliderCellProps)
export type TextInputCellProps = typeof(require("@repo/tools/typecheck/aliases").TextInputCellProps)
export type ChipCellProps = typeof(require("@repo/tools/typecheck/aliases").ChipCellProps)
export type StringSinglePickerSpec = typeof(require("@repo/tools/typecheck/aliases").StringSinglePickerSpec)

export type ReadOnlyValue<T> = typeof(require("@repo/src/vendor/compose/core").accumulator<<T, number>>(nil :: never))
export type Value<T> = typeof(require("@repo/src/vendor/compose/core").cell<<T>>(nil :: never))
return {}
