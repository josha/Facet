--!strict

local Facet = require("../src")
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type RobloxTypes = typeof(require("@repo/tools/typecheck/aliases").RobloxTypes)
type SkinLayer = typeof(require("@repo/tools/typecheck/aliases").SkinLayer)
type ReadOnlyValue<T> = typeof(require("@repo/src/vendor/compose/core").accumulator<<T, number>>(nil :: never))
type Value<T> = typeof(require("@repo/src/vendor/compose/core").cell<<T>>(nil :: never))
type Use = <T>(ReadOnlyValue<T>) -> T
export type Size = { width: number, height: number }
export type Device = { width: number?, height: number?, displaySize: string, input: string, rotates: boolean? }
export type Demo = { id: string, kind: string, module: string, title: string, blurb: string? }
export type MotionLevel = "normal" | "limited" | "none"
export type ViewingDistance = "automatic" | "near" | "ten-foot"
export type Built = {
	read screen: () -> Instance,
	read report: (() -> unknown)?,
	read select: ((string) -> boolean?)?,
	read dispose: (() -> ())?,
}
export type ThemeModule = {
	testOnly: boolean?,
	build: (typeof(Facet.themes)) -> (Facet.ThemePackage?, ...unknown),
}
export type CategoryLayout = {
	placement: ReadOnlyValue<string>,
	available: ReadOnlyValue<boolean>,
	toggle: () -> (),
}
export type Scenario = { read build: (Context) -> Built }
export type DemoTab = { id: string, label: string, scenario: Scenario?, tabs: { DemoTab }? }
export type Definition = {
	read title: string?,
	read build: (Context) -> Built | () -> Instance,
}
export type Context = {
	Facet: Facet.Facet,
	Compose: Facet.ComposeModule,
	UI: Facet.Controls,
	Host: RobloxHost,
	runtime: Facet.Runtime,
	types: RobloxTypes,
	viewport: ReadOnlyValue<Size>?,
	previewViewport: ReadOnlyValue<Size>?,
	sceneViewport: ReadOnlyValue<Size>?,
	worldTarget: Instance?,
	inputTarget: Instance?,
	guiService: GuiService?,
	runService: RunService?,
	heartbeat: RBXScriptSignal?,
	selection: Value<string>?,
	demos: { Demo }?,
	buildStamp: unknown,
	theme: Value<Facet.ThemePackage>?,
	themeMode: Value<string>?,
	themeName: Value<string>?,
	packages: { [string]: Facet.ThemePackage }?,
	load: ((kind: string, name: string, ...string) -> Definition)?,
	find: ((kind: string, name: string, ...string) -> ModuleScript)?,
	overlayParent: Frame?,
	sheet: StyleSheet?,
	viewingDistance: Value<ViewingDistance?>?,
	categoryPlacement: Value<string>?,
	categoryLayout: Value<CategoryLayout?>?,
	devicePreview: Value<string>?,
	orientationPreview: Value<string>?,
	inputPreview: Value<string>?,
	textPreview: Value<string>?,
	device: ReadOnlyValue<Device?>?,
	topInset: ReadOnlyValue<number>?,
	metricScale: Value<ReadOnlyValue<number>?>?,
	previewScale: ReadOnlyValue<number>?,
	environment: typeof(require("@repo/tools/typecheck/aliases").ControlOptions.environment),
	hoverPreview: ((Use) -> boolean?)?,
	motionPreference: Value<MotionLevel?>?,
	motionLevel: ReadOnlyValue<MotionLevel>?,
	motionMode: Value<string>?,
	reducedMotion: ReadOnlyValue<boolean>?,
	sceneVisible: Value<boolean>?,
	pageVisible: ReadOnlyValue<boolean>?,
	active: Value<string?>?,
	errorMessage: Value<string?>?,
	currentReport: (() -> unknown)?,
	currentSelect: ((string) -> boolean?)?,
	requestPanel: ((string?) -> ())?,
	panelOpen: ReadOnlyValue<boolean>?,
	panelSection: ReadOnlyValue<string>?,
	copy: { [string]: string }?,
	player: Player?,
	outpostRemote: RemoteEvent?,
}

local function exports(): {
	Context: Context,
	Definition: Definition,
	Scenario: Scenario,
	DemoTab: DemoTab,
	CategoryLayout: CategoryLayout,
	ViewingDistance: ViewingDistance,
	MotionLevel: MotionLevel,
	ThemeModule: ThemeModule,
	Built: Built,
	Demo: Demo,
	Device: Device,
	Size: Size,
}
	error("examples/types.luau holds types only")
end

return exports()
