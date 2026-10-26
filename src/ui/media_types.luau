--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local Engine = require("./engine_types")

export type ControlSize = "xsmall" | "compact" | "regular" | "large"
export type Status = "neutral" | "info" | "success" | "warning" | "error" | "accent" | "voice" | "contrast"
export type TextRole = Types.TextRole
export type Corners = number | "pill" | "square" | "rounded"
export type TextFitBound = number | TextRole
export type TextFit = "fit" | { fit: { cap: TextFitBound?, floor: TextFitBound? } }
export type TextSize = number | TextRole | TextFit
export type TextAlign = "start" | "center" | "end"
export type TextOptions = {
	ref: ((TextLabel) -> ())?,
	text: Types.ValueString,
	textRole: Types.Input<TextRole>?,
	role: Types.Input<"secondary" | "content">?,
	truncate: ("end" | "middle")?,
	textSize: TextSize?,
	textAlign: Types.Input<TextAlign>?,
	wrap: Types.ValueBoolean?,
	rich: boolean?,
	direction: ("auto" | "ltr" | "rtl")?,
	tint: Types.Input<Color3>?,
	lines: number?,
	disclose: boolean?,
	reveal: "auto"?,
}
export type LabelPresentation = "titleAndIcon" | "titleOnly" | "iconOnly"
export type LabelOptions = {
	ref: ((Frame) -> ())?,
	title: Types.ValueString,
	icon: string?,
	presentation: LabelPresentation?,
	iconSize: (number | string)?,
	textSize: (number | TextRole)?,
	gap: Types.Input<Types.Space>?,
	iconPosition: ("leading" | "trailing")?,
}
export type ScaleMode = "fit" | "fill" | "crop" | "stretch" | "tile" | "slice"
export type ImageOptions = {
	ref: ((ImageLabel) -> ())?,
	image: Types.ValueString?,
	tint: Types.Input<Color3>?,
	scaleMode: Types.Input<ScaleMode>?,
	tileSize: { width: number, height: number }?,
	sliceCenter: { x0: number, y0: number, x1: number, y1: number }?,
	sliceScale: number?,
	resample: Types.Input<"default" | "pixelated">?,
	shape: ("rect" | "circle")?,
}
export type BadgeOptions = {
	label: Types.Input<string?>?,
	name: string?,
	icon: Types.ValueString?,
	iconPosition: "leading" | "trailing"?,
	status: Types.Input<Status>?,
	appearance: Types.Input<"standard" | "status" | "utility">?,
	controlSize: Types.Input<ControlSize?>?,
	corners: Types.Input<number | "square" | "rounded" | "capsule">?,
}
export type StatusIndicatorOptions = {
	status: Types.Input<Status>?,
	form: Types.Input<"dot" | "ring" | "square" | "dash">?,
	count: Types.Input<number?>?,
	max: number?,
	diameter: Types.ValueNumber?,
	controlSize: Types.Input<ControlSize?>?,
	cutout: boolean?,
	name: Types.ValueString?,
}
export type PathPoint = { x: number, y: number, inX: number, inY: number, outX: number, outY: number }
export type PathOptions = {
	points: Types.Input<{ PathPoint }>,
	thickness: Types.Input<number | string>?,
	closed: Types.ValueBoolean?,
	role: Types.Input<"content" | "secondary" | "accent">?,
	tint: Types.Input<Color3>?,
	width: number?,
	height: number?,
}
export type Trail = { delay: number?, duration: number? }
export type ProgressViewOptions = {
	value: Types.ValueNumber?,
	min: Types.ValueNumber?,
	max: Types.ValueNumber?,
	presentation: "bar" | "circular" | "gauge" | "spinner"?,
	sweep: number?,
	needle: boolean?,
	label: Types.ValueString?,
	endLabel: Types.ValueString?,
	showValue: boolean?,
	format: ((value: number) -> string)?,
	diameter: Types.ValueNumber?,
	thickness: Types.ValueNumber?,
	segments: number?,
	trail: Trail?,
	controlSize: Types.Input<ControlSize?>?,
}
export type SkeletonOptions = {
	form: "box" | "circle" | "line"?,
	lines: number?,
	controlSize: Types.Input<ControlSize?>?,
	corners: Types.Input<Corners | "control" | "panel">?,
}
export type ImageState = "loading" | "ready" | "failed"
export type ImageResource =
	{ value: Types.Input<string?>, state: Types.Input<ImageState>, status: Types.Input<ImageState>? }
	| { value: Types.Input<string?>, state: Types.Input<ImageState>?, status: Types.Input<ImageState> }
export type ImageLoader = (
	source: string,
	resolve: (value: string?) -> (),
	reject: (reason: unknown) -> ()
) -> (() -> ())?
export type ImageStatusCallback = (state: ImageState, reason: unknown) -> ()
export type AsyncImageOptions = {
	source: Types.Input<string?>?,
	image: Types.Input<string?>?,
	resource: (() -> ImageResource)?,
	loader: ImageLoader?,
	onStatus: ImageStatusCallback?,
	failureLabel: Types.ValueString?,
	placeholder: ((state: ComposeTypes.ReadOnlyValue<ImageState>) -> Instance)?,
	dimmed: Types.ValueBoolean?,
	imageProperties: Types.ImageLabelProps?,
}
export type Presence = "online" | "away" | "busy" | "offline" | "inExperience"
export type AvatarOptions = {
	name: Types.ValueString,
	image: Types.Input<string?>?,
	userId: Types.ValueNumber?,
	resource: (() -> ImageResource)?,
	loader: ImageLoader?,
	onStatus: ImageStatusCallback?,
	presence: Types.Input<Presence?>?,
	presenceLabel: Types.ValueString?,
	presenceMark: boolean?,
	diameter: Types.ValueNumber?,
	controlSize: Types.Input<ControlSize?>?,
	form: "standard" | "icon"?,
	backplate: boolean?,
	icon: Types.Input<string?>?,
	background: string?,
	onActivate: (() -> ())?,
}
export type AvatarMember = {
	id: string,
	name: string,
	image: string?,
	userId: number?,
	icon: string?,
	resource: (() -> ImageResource)?,
	presence: Presence?,
}
export type AvatarGroupOptions = {
	items: Types.Input<{ AvatarMember }>,
	max: number?,
	diameter: Types.ValueNumber?,
	controlSize: Types.Input<ControlSize?>?,
	form: "standard" | "icon"?,
	layout: "stacked" | "spread"?,
	overflow: "count" | "ellipsis"?,
	overflowLabel: Types.ValueString?,
	onOverflow: (() -> ())?,
}
export type StageOptions = {
	content: ((
		runtime: ComposeTypes.Runtime,
		world: WorldModel,
		live: ComposeTypes.ReadOnlyValue<boolean>
	) -> (() -> ())?)?,
	lazy: boolean?,
	camera: Camera | Types.Input<CFrame>?,
	fieldOfView: Types.ValueNumber?,
}
return {}
