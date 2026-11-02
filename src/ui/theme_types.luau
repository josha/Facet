--!strict
local ComposeTypes = require("../vendor/compose/core")
local Engine = require("./engine_types")

export type RGB = { r: number, g: number, b: number }
export type RGBPatch = { read r: number?, read g: number?, read b: number? }
export type FontSpec = { family: string?, weight: string?, style: string? }
export type Typography = { size: number, font: Font | FontSpec, lineHeight: number? }
export type TypographyPatch = { read size: number?, read font: Font | FontSpec?, read lineHeight: number? }
export type ControlSize = { height: number, paddingX: number, iconSize: number }
export type ControlSizePatch = { read height: number?, read paddingX: number?, read iconSize: number? }
export type MotionTiming = { enter: number, exit: number }
export type MotionTimingPatch = { read enter: number?, read exit: number? }
export type SpringMetric = { period: number, damping: number }
export type SpringMetricPatch = { read period: number?, read damping: number? }
export type MotionMetrics = {
	typewriter: { grapheme: number, pause: number }?,
	fast: number,
	normal: number,
	press: number?,
	hover: number?,
	reducedFade: number?,
	revealFadeShare: number?,
	presentFadeIn: number?,
	presentFadeOut: number?,
	unfoldStart: number?,
	restLimit: number?,
	frameLimit: number?,
	popover: MotionTiming?,
	dialog: MotionTiming?,
	reveal: MotionTiming?,
	sheet: MotionTiming?,
	toast: MotionTiming?,
	radial: { enter: number, exit: number, slot: number }?,
	durations: { [string]: number }?,
	springs: { [string]: SpringMetric }?,
	materialize: { [string]: number }?,
	distances: { [string]: number }?,
	scales: { [string]: number }?,
	easing: { [string]: string }?,
	styles: { [string]: string }?,
	fling: { [string]: number }?,
}
export type MotionMetricsPatch = {
	read typewriter: { grapheme: number?, pause: number? }?,
	read fast: number?,
	read normal: number?,
	read press: number?,
	read hover: number?,
	read reducedFade: number?,
	read revealFadeShare: number?,
	read presentFadeIn: number?,
	read presentFadeOut: number?,
	read unfoldStart: number?,
	read restLimit: number?,
	read frameLimit: number?,
	read popover: MotionTimingPatch?,
	read dialog: MotionTimingPatch?,
	read reveal: MotionTimingPatch?,
	read sheet: MotionTimingPatch?,
	read toast: MotionTimingPatch?,
	read radial: { enter: number?, exit: number?, slot: number? }?,
	read durations: { read [string]: number }?,
	read springs: { read [string]: SpringMetricPatch }?,
	read materialize: { read [string]: number }?,
	read distances: { read [string]: number }?,
	read scales: { read [string]: number }?,
	read easing: { read [string]: string }?,
	read styles: { read [string]: string }?,
	read fling: { read [string]: number }?,
}
export type Metrics = {
	typography: { [string]: Typography },
	space: { [string]: number },
	radii: { [string]: number },
	strokes: { [string]: number },
	targetSizes: { [string]: number },
	controlSizes: { [string]: ControlSize },
	motion: MotionMetrics,
	iconSizes: { [string]: number },
	controls: { [string]: { [string]: number } },
}
export type MetricsPatch = {
	read typography: { read [string]: TypographyPatch }?,
	read space: { read [string]: number }?,
	read radii: { read [string]: number }?,
	read strokes: { read [string]: number }?,
	read targetSizes: { read [string]: number }?,
	read controlSizes: { read [string]: ControlSizePatch }?,
	read motion: MotionMetricsPatch?,
	read iconSizes: { read [string]: number }?,
	read controls: { read [string]: { read [string]: number } }?,
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
	selection: RGB?,
	onSelection: RGB?,
	voice: RGB?,
	scrim: RGB?,
	inverseSurface: RGB?,
	onInverse: RGB?,
	tableHeader: RGB?,
	tableRow: RGB?,
	tableRowAlternate: RGB?,
	dimDisabledPlates: boolean?,
	artTint: RGB?,
	strongHairlineOpacity: number?,
	chromeGradient: { [string]: Gradient }?,
}
export type Palette = { name: string, colors: { [string]: RGB }, extra: PaletteExtra? }
export type PalettePatch = { read name: string, read colors: { read [string]: RGBPatch }?, read extra: PaletteExtra? }
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
export type AssetLink = string | { asset: string, rotation: number?, tint: RGB? }
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
export type IconRegistry = { read icons: { [string]: IconEntry }?, read assets: { [string]: Asset }? }
export type FillDirection = "ltr" | "rtl" | "ttb" | "btt"
type SkinKind =
	"native"
	| "none"
	| "nineSlice"
	| "fill"
	| "frame"
	| "tile"
	| "corners"
	| "edges"
	| "plaque"
	| "layered"
	| "glow"
	| "ring"
	| "brackets"
export type SkinLayer = {
	kind: SkinKind,
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
	corner: ("pill" | "square")?,
	outset: number?,
	sliceScale: number?,
	pulse: boolean?,
	halo: boolean | RGB?,
	span: ("track" | "fill")?,
}
export type SkinLayerPatch = {
	kind: SkinKind?,
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
	corner: ("pill" | "square")?,
	outset: number?,
	sliceScale: number?,
	pulse: boolean?,
	halo: boolean | RGB?,
	span: ("track" | "fill")?,
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
export type AuthoredRuleProperties = { [string]: (StyleValue | { role: string } | { metric: string })? }
export type Rule = { selector: string, properties: AuthoredRuleProperties?, props: AuthoredRuleProperties? }
export type Identity =
	{ id: string, displayName: string?, version: string?, schemaVersion: string?, rendering: string? }
export type IdentityPatch = {
	id: string?,
	displayName: string?,
	version: string?,
	schemaVersion: string?,
	rendering: string?,
}
export type ThemeStyle = { defaultTheme: string, themes: { Palette }, shadows: { [string]: Shadow }? }
export type ThemePackage = {
	schema: string,
	identity: Identity,
	style: ThemeStyle,
	metrics: Metrics,
	chrome: { [string]: SkinLayer }?,
	assets: { [string]: Asset }?,
	icons: { [string]: IconEntry }?,
	rules: { Rule }?,
}
export type ReadOnlyThemePackage = {
	schema: string,
	identity: Identity,
	read style: ThemeStyle,
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
	chrome: { [string]: SkinLayerPatch }?,
	assets: { [string]: Asset }?,
	icons: { [string]: IconEntry }?,
	rules: { Rule }?,
}
export type ThemeIssue = { field: string, message: string }
export type ContrastResult = { pair: string, ratio: number, ok: boolean }
export type ThemeReport = {
	ok: boolean,
	errors: { ThemeIssue },
	missing: { string },
	contrast: { ContrastResult },
	advice: { ThemeIssue },
}
export type CoverageNeed = { name: string, section: string?, kind: "color" | "number"?, fields: { string }? }
export type CoverageReport = {
	ok: boolean,
	missing: { { name: string, message: string, fix: string } },
	covered: { string },
}
export type ThemeOptions = {
	types: Engine.RobloxTypes?,
	name: string?,
	theme: Engine.ValueString?,
	motionLevel: (Engine.Input<"normal" | "limited" | "none"> | Engine.Input<("normal" | "limited" | "none")?>)?,
	preferredTransparency: Engine.ValueNumber?,
	hover: (Engine.ValueBoolean | Engine.Input<boolean?>)?,
	tenFoot: Engine.ValueBoolean?,
	transition: Engine.Input<(TweenInfo | false)?>?,
	contentProvider: ContentProvider?,
	collectionService: CollectionService?,
}
export type SkinOptions = {
	types: Engine.RobloxTypes?,
	shadowTransparency: Engine.ValueNumber?,
	target: GuiObject?,
	label: Engine.ValueString?,
	onCaption: ((boolean) -> ())?,
	state: Engine.Input<SkinState>?,
	selected: Engine.ValueBoolean?,
	direction: Engine.Input<FillDirection>?,
	fit: Engine.ValueNumber?,
	Size: Engine.Input<UDim2>?,
	Position: Engine.Input<UDim2>?,
	AnchorPoint: Engine.Input<Vector2>?,
	ZIndex: number?,
}
export type Themes = {
	SCHEMA: string,
	TYPE_ROLES: { string },
	REQUIRED_TYPE_ROLES: { string },
	neutralPackage: () -> ThemePackage,
	forDistance: (package: ReadOnlyThemePackage, distance: "near" | "ten-foot") -> ReadOnlyThemePackage,
	define: (definition: ThemeDefinition | ThemePackage) -> (ThemePackage?, ThemeReport),
	checkCoverage: (package: ThemePackage, needs: { CoverageNeed }) -> CoverageReport,
	resolveIcon: (package: IconRegistry, name: string, state: SkinState?) -> string?,
	createStyleSheet: (
		runtime: ComposeTypes.Runtime,
		packageOrReadable: Engine.Input<ReadOnlyThemePackage>?,
		options: ThemeOptions?
	) -> StyleSheet,
	skin: (
		runtime: ComposeTypes.Runtime,
		packageOrReadable: Engine.Input<ReadOnlyThemePackage>?,
		slot: string,
		options: SkinOptions?
	) -> Frame,
}
return {}
