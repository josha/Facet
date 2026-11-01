--!strict
type FacetModule = typeof(require("@repo/tools/typecheck/aliases").FacetModule)
type Runtime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
type Host = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type Controls = typeof(require("@repo/tools/typecheck/aliases").Controls)
type RobloxTypes = typeof(require("@repo/tools/typecheck/aliases").RobloxTypes)
type ThemePackage = typeof(require("@repo/tools/typecheck/aliases").ThemePackage)
type NumberCell = typeof(require("@repo/tools/typecheck/aliases").NumberCell)
type BooleanCell = typeof(require("@repo/tools/typecheck/aliases").BooleanCell)
type ReadOnlyValue<T> = typeof(require("@repo/src/vendor/compose/core").accumulator<<T, number>>(nil :: never))

export type Row = {
	id: string,
	name: string,
	detail: string?,
	imageKey: string?,
	enabled: boolean?,
	rank: number?,
	team: string?,
	value: number?,
}
export type Context = {
	read Facet: FacetModule,
	read runtime: Runtime,
	read Host: Host,
	read UI: Controls,
	read types: RobloxTypes,
	read viewport: { w: number, h: number },
	read frame: ((number?) -> ())?,
	read engine: unknown,
	read target: Instance?,
	read rowCount: number?,
	read rowSize: number?,
	rowModels: { values: { [string]: NumberCell }, toggles: { [string]: BooleanCell } }?,
	onRowActivate: ((Row) -> ())?,
	read rowBuilder: (Context, ReadOnlyValue<Row>, { full: boolean }) -> GuiObject,
	read themePackages: { ThemePackage }?,
	read themeNames: { string }?,
}

return (nil :: unknown) :: { Context: Context, Row: Row }
