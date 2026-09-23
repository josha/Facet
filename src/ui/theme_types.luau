--!strict
local Compose = require("../vendor/compose/core")
local Engine = require("./engine_types")

export type RGB = { r: number, g: number, b: number }
export type RGBPatch = { r: number?, g: number?, b: number? }
export type FontSpec = { family: string?, weight: string?, style: string? }
export type Typography = { size: number, font: Font | FontSpec, lineHeight: number? }
export type TypographyPatch = { size: number?, font: Font | FontSpec?, lineHeight: number? }
export type ControlSize = { height: number, paddingX: number, iconSize: number }
export type ControlSizePatch = { height: number?, paddingX: number?, iconSize: number? }
export type Metrics = {
	typography: { [string]: Typography },
	space: { [string]: number },
	radii: { [string]: number },
	strokes: { [string]: number },
	targetSizes: { [string]: number },
	controlSizes: { [string]: ControlSize },
	motion: { [string]: number },
	iconSizes: { [string]: number },
	controls: { [string]: { [string]: number } },
}
export type MetricsPatch = {
	typography: { [string]: TypographyPatch }?,
	space: { [string]: number }?,
	radii: { [string]: number }?,
	strokes: { [string]: number }?,
	targetSizes: { [string]: number }?,
	controlSizes: { [string]: ControlSizePatch }?,
	motion: { [string]: number }?,
	iconSizes: { [string]: number }?,
	controls: { [string]: { [string]: number } }?,
}
export type Gradient = {
	stops: { { t: number, r: number, g: number, b: number } },
	alpha: { { t: number, v: number } }?,
	rotation: number?,
}
export type ExtraValue = RGB | number | string | boolean | { [string]: Gradient }
export type PaletteExtra = {
	[string]: ExtraValue?,
	control: RGB?,
	controlHover: RGB?,
	controlPressed: RGB?,
	controlSelected: RGB?,
	onSelected: RGB?,
	contentSecondary: RGB?,
	hairline: RGB?,
	hairlineOpacity: number?,
	disabledContentOpacity: number?,
	scrimOpacity: number?,
	chromeGradient: { [string]: Gradient }?,
}
export type Palette = { name: string, colors: { [string]: RGB }, extra: PaletteExtra? }
export type PalettePatch = { name: string, colors: { [string]: RGBPatch }?, extra: PaletteExtra? }
export type Insets = { left: number?, right: number?, top: number?, bottom: number? }
export type ShadowAxis = { scale: number?, offset: number? }
export type ShadowPair = { x: ShadowAxis?, y: ShadowAxis? }
export type Shadow = {
	color: RGB?,
	transparency: number?,
	zIndex: number?,
	enabled: boolean?,
	blurRadius: ShadowAxis?,
	offset: ShadowPair?,
	spread: ShadowPair?,
}
export type Asset = {
	content: string?,
	contentId: string?,
	assetName: string?,
	tintRole: string?,
	sliceCenter: { x0: number, y0: number, x1: number, y1: number }?,
	sliceScale: number?,
	resample: "pixelated" | "default"?,
	preload: string?,
	fallback: string?,
}
export type AssetLink = string | { asset: string }
export type AssetVariants = {
	default: AssetLink?,
	hover: AssetLink?,
	pressed: AssetLink?,
	selected: AssetLink?,
	disabled: AssetLink?,
}
export type AssetSource = AssetLink | AssetVariants
export type SkinState = "default" | "hover" | "pressed" | "selected" | "disabled"
export type IconAsset = Asset & { asset: string? }
export type IconEntry = string | IconAsset | {
	default: string | IconAsset,
	hover: string | IconAsset?,
	pressed: string | IconAsset?,
	selected: string | IconAsset?,
	disabled: string | IconAsset?,
}
export type IconRegistry = { icons: { [string]: IconEntry }?, assets: { [string]: Asset }? }
export type FillDirection = "ltr" | "rtl" | "ttb" | "btt"
export type SkinLayer = {
	kind: "native"
		| "none"
		| "nineSlice"
		| "fill"
		| "frame"
		| "tile"
		| "corners"
		| "edges"
		| "plaque"
		| "layered"
		| "glow",
	asset: AssetSource?,
	text: boolean?,
	textInsets: Insets?,
	tile: number?,
	tileSize: { w: number, h: number }?,
	sliced: boolean?,
	topLeft: AssetSource?,
	topRight: AssetSource?,
	bottomLeft: AssetSource?,
	bottomRight: AssetSource?,
	sides: { "top" | "right" | "bottom" | "left" }?,
	thickness: number?,
	margin: number?,
	size: number | { w: number, h: number }?,
	edge: "top" | "right" | "bottom" | "left"?,
	overhang: number?,
	contentInsets: Insets?,
	shadow: string | Shadow?,
	layers: { SkinLayer }?,
	direction: FillDirection?,
	startAsset: AssetSource?,
	endAsset: AssetSource?,
	fallback: string?,
	color: string | RGB?,
	blurRadius: ShadowAxis?,
	transparency: number?,
	zIndex: number?,
}
export type StyleValue =
	boolean
	| number
	| string
	| EnumItem
	| Color3
	| ColorSequence
	| NumberSequence
	| UDim
	| UDim2
	| Vector2
	| Vector3
	| Rect
	| Font
	| CFrame
	| NumberRange
export type RuleProperties = { [string]: StyleValue? }
export type Rule = { selector: string, properties: RuleProperties?, props: RuleProperties? }
export type Identity =
	{ id: string, displayName: string?, version: string?, schemaVersion: string?, rendering: string? }
export type IdentityPatch = {
	id: string?,
	displayName: string?,
	version: string?,
	schemaVersion: string?,
	rendering: string?,
}
export type ThemePackage = {
	schema: string,
	identity: Identity,
	style: { defaultTheme: string, themes: { Palette }, shadows: { [string]: Shadow }? },
	metrics: Metrics,
	chrome: { [string]: SkinLayer }?,
	assets: { [string]: Asset }?,
	icons: { [string]: IconEntry }?,
	rules: { Rule }?,
}
export type ThemeDefinition = {
	base: ThemePackage?,
	schema: string?,
	identity: IdentityPatch?,
	style: { defaultTheme: string?, themes: { PalettePatch }?, shadows: { [string]: Shadow }? }?,
	metrics: MetricsPatch?,
	chrome: { [string]: SkinLayer }?,
	assets: { [string]: Asset }?,
	icons: { [string]: IconEntry }?,
	rules: { Rule }?,
}
export type ThemeIssue = { field: string, message: string }
export type ContrastResult = { pair: string, ratio: number, ok: boolean }
export type ThemeReport = { ok: boolean, errors: { ThemeIssue }, missing: { string }, contrast: { ContrastResult } }
export type CoverageNeed = { name: string, section: string?, kind: "color" | "number"?, fields: { string }? }
export type CoverageReport = {
	ok: boolean,
	missing: { { name: string, message: string, fix: string } },
	covered: { string },
}
export type ThemeOptions = {
	types: Engine.RobloxTypes?,
	name: string?,
	theme: Engine.Value<string>?,
	reducedMotion: Engine.Value<boolean>?,
	transition: Engine.Value<TweenInfo | false>?,
}
export type SkinOptions = {
	types: Engine.RobloxTypes?,
	target: GuiObject?,
	label: Engine.Value<string>?,
	state: Engine.Value<SkinState>?,
	direction: Engine.Value<FillDirection>?,
	Size: Engine.Value<UDim2>?,
	Position: Engine.Value<UDim2>?,
	AnchorPoint: Engine.Value<Vector2>?,
	ZIndex: number?,
}
export type Themes = {
	SCHEMA: string,
	TYPE_ROLES: { string },
	REQUIRED_TYPE_ROLES: { string },
	neutralPackage: () -> ThemePackage,
	define: (definition: ThemeDefinition) -> (ThemePackage?, ThemeReport),
	checkCoverage: (package: ThemePackage, needs: { CoverageNeed }) -> CoverageReport,
	resolveIcon: (package: IconRegistry, name: string, state: SkinState?) -> string?,
	createStyleSheet: (
		runtime: Compose.Runtime,
		packageOrReadable: Engine.Value<ThemePackage>?,
		options: ThemeOptions?
	) -> StyleSheet,
	skin: (
		runtime: Compose.Runtime,
		packageOrReadable: Engine.Value<ThemePackage>?,
		slot: string,
		options: SkinOptions?
	) -> Frame,
}
return {}
