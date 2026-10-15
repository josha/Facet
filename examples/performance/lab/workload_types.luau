--!strict
type FacetModule = typeof(require("@repo/tools/typecheck/aliases").FacetModule)
type Runtime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
type Host = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type Controls = typeof(require("@repo/tools/typecheck/aliases").Controls)
type RobloxTypes = typeof(require("@repo/tools/typecheck/aliases").RobloxTypes)
type ThemePackage = typeof(require("@repo/tools/typecheck/aliases").ThemePackage)
type NumberCell = typeof(require("@repo/tools/typecheck/aliases").NumberCell)
type BooleanCell = typeof(require("@repo/tools/typecheck/aliases").BooleanCell)
type Readable<T> = { peek: (Readable<T>) -> T }

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
	Facet: FacetModule,
	runtime: Runtime,
	Host: Host,
	UI: Controls,
	types: RobloxTypes,
	viewport: { w: number, h: number },
	frame: ((number?) -> ())?,
	engine: unknown,
	target: Instance?,
	rowCount: number?,
	rowSize: number?,
	rowModels: { values: { [string]: NumberCell }, toggles: { [string]: BooleanCell } }?,
	onRowActivate: ((Row) -> ())?,
	rowBuilder: (Context, Readable<Row>, { full: boolean }) -> GuiObject,
	themePackages: { ThemePackage }?,
	themeNames: { string }?,
}

return (nil :: unknown) :: { Context: Context, Row: Row }
