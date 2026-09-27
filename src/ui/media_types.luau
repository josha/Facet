--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local Engine = require("./engine_types")

export type ControlSize = "xsmall" | "compact" | "regular" | "large"
export type Status = "neutral" | "info" | "success" | "warning" | "error" | "accent" | "voice" | "contrast"
export type TextRole = "caption" | "label" | "body" | "heading" | "title" | "control" | "strong" | "numeral"
export type Corners = number | "pill" | "square" | "rounded"
export type TextFitBound = number | TextRole
export type TextFit = "fit" | { fit: { cap: TextFitBound?, floor: TextFitBound? } }
export type TextSize = number | TextRole | TextFit
export type TextAlign = "start" | "center" | "end"
export type TextProps = Engine.TextLabelNativeProps & {
	ref: ((TextLabel) -> ())?,
	text: Types.ValueString,
	textRole: Types.Value<TextRole>?,
	role: Types.Value<"secondary" | "content">?,
	truncate: ("end" | "middle")?,
	textSize: TextSize?,
	textAlign: Types.Value<TextAlign>?,
	wrap: Types.ValueBoolean?,
	rich: boolean?,
	direction: ("auto" | "ltr" | "rtl")?,
	tint: Types.Value<Color3>?,
	lines: number?,
	disclose: boolean?,
	reveal: "auto"?,
}
export type LabelPresentation = "titleAndIcon" | "titleOnly" | "iconOnly"
export type LabelProps = Engine.FrameProps & {
	ref: ((Frame) -> ())?,
	title: Types.ValueString,
	icon: string?,
	presentation: LabelPresentation?,
	iconSize: (number | string)?,
	textSize: (number | TextRole)?,
	gap: Types.Value<Types.Space>?,
	iconPosition: ("leading" | "trailing")?,
}
export type ScaleMode = "fit" | "fill" | "crop" | "stretch" | "tile" | "slice"
export type ImageProps = Engine.ImageLabelProps & {
	ref: ((ImageLabel) -> ())?,
	image: Types.ValueString?,
	tint: Types.Value<Color3>?,
	scaleMode: Types.Value<ScaleMode>?,
	tileSize: { width: number, height: number }?,
	sliceCenter: { x0: number, y0: number, x1: number, y1: number }?,
	sliceScale: number?,
	resample: Types.Value<"default" | "pixelated">?,
	shape: ("rect" | "circle")?,
}
export type BadgeProps = Types.TextLabelProps & {
	label: Types.ValueString?,
	name: string?,
	icon: Types.ValueString?,
	iconPosition: "leading" | "trailing"?,
	status: Types.Value<Status>?,
	appearance: Types.Value<"standard" | "status" | "utility">?,
	controlSize: Types.Value<ControlSize>?,
	corners: Types.Value<number | "square" | "rounded" | "capsule">?,
}
export type StatusIndicatorProps = Types.TextLabelProps & {
	status: Types.Value<Status>?,
	form: Types.Value<"dot" | "ring" | "square" | "dash">?,
	count: Types.Value<number?>?,
	max: number?,
	diameter: Types.ValueNumber?,
	controlSize: Types.Value<ControlSize>?,
	cutout: boolean?,
	name: string?,
}
export type PathPoint = { x: number, y: number, inX: number, inY: number, outX: number, outY: number }
export type PathProps = Engine.FrameProps & {
	points: Types.Value<{ PathPoint }>,
	thickness: Types.Value<number | string>?,
	closed: Types.ValueBoolean?,
	role: Types.Value<"content" | "secondary" | "accent">?,
	tint: Types.Value<Color3>?,
	width: number?,
	height: number?,
}
export type Trail = { delay: number?, duration: number? }
export type ProgressViewProps = Engine.FrameProps & {
	value: Types.ValueNumber?,
	min: Types.ValueNumber?,
	max: Types.ValueNumber?,
	presentation: "bar" | "circular" | "spinner"?,
	label: Types.ValueString?,
	endLabel: Types.ValueString?,
	showValue: boolean?,
	format: ((value: number) -> string)?,
	diameter: Types.ValueNumber?,
	thickness: Types.ValueNumber?,
	segments: number?,
	trail: Trail?,
	controlSize: Types.Value<ControlSize>?,
}
export type SkeletonProps = Engine.FrameProps & {
	form: "box" | "circle" | "line"?,
	lines: number?,
	controlSize: Types.Value<ControlSize>?,
	corners: Types.Value<Corners | "control" | "panel">?,
}
export type ImageState = "loading" | "ready" | "failed"
export type ImageResource = {
	value: Types.Value<string?>,
} & (
	{ state: Types.Value<ImageState>, status: Types.Value<ImageState>? }
	| { state: Types.Value<ImageState>?, status: Types.Value<ImageState> }
)
export type ImageLoader = (
	source: string,
	resolve: (value: string?) -> (),
	reject: (reason: unknown) -> ()
) -> (() -> ())?
export type ImageStatusCallback = (state: ImageState, reason: unknown) -> ()
export type AsyncImageProps = Engine.FrameProps & {
	source: Types.Value<string?>?,
	image: Types.Value<string?>?,
	resource: ComposeTypes.AcquireSharedResource<ImageResource>?,
	loader: ImageLoader?,
	onStatus: ImageStatusCallback?,
	failureLabel: Types.ValueString?,
	placeholder: ((state: ComposeTypes.Readable<ImageState>) -> Instance)?,
	dimmed: Types.ValueBoolean?,
	imageProperties: Types.ImageLabelProps?,
}
export type Presence = "online" | "away" | "busy" | "offline" | "inExperience"
export type AvatarProps = Types.TextButtonProps & {
	name: Types.ValueString,
	image: Types.Value<string?>?,
	userId: Types.ValueNumber?,
	resource: ComposeTypes.AcquireSharedResource<ImageResource>?,
	loader: ImageLoader?,
	onStatus: ImageStatusCallback?,
	presence: Types.Value<Presence?>?,
	presenceLabel: Types.ValueString?,
	presenceMark: boolean?,
	diameter: Types.ValueNumber?,
	controlSize: Types.Value<ControlSize>?,
	form: "standard" | "icon"?,
	backplate: boolean?,
	icon: Types.Value<string?>?,
	background: string?,
	onActivate: (() -> ())?,
}
export type AvatarMember = {
	id: string,
	name: string,
	image: string?,
	userId: number?,
	icon: string?,
	resource: ComposeTypes.AcquireSharedResource<ImageResource>?,
	presence: Presence?,
}
export type AvatarGroupProps = Engine.FrameProps & {
	items: Types.Value<{ AvatarMember }>,
	max: number?,
	diameter: Types.ValueNumber?,
	controlSize: Types.Value<ControlSize>?,
	form: "standard" | "icon"?,
	layout: "stacked" | "spread"?,
	overflow: "count" | "ellipsis"?,
	overflowLabel: Types.ValueString?,
	onOverflow: (() -> ())?,
}
export type StageProps = Types.ViewportFrameProps & {
	content: ((
		runtime: ComposeTypes.Runtime,
		world: WorldModel,
		live: ComposeTypes.Readable<boolean>
	) -> (() -> ())?)?,
	lazy: boolean?,
	camera: Camera | Types.Value<CFrame>?,
	fieldOfView: Types.ValueNumber?,
}
export type MediaControls = {
	Text: Types.Constructor<TextProps, GuiObject>,
	Label: Types.Constructor<LabelProps, GuiObject>,
	Image: Types.Constructor<ImageProps, GuiObject>,
	Badge: Types.Constructor<BadgeProps, GuiObject>,
	StatusIndicator: Types.Constructor<StatusIndicatorProps, TextLabel>,
	Path: Types.Constructor<PathProps, Frame>,
	ProgressView: Types.Constructor<ProgressViewProps, Frame>,
	Skeleton: Types.Constructor<SkeletonProps, Frame>,
	AsyncImage: Types.Constructor<AsyncImageProps, Frame>,
	Avatar: Types.Constructor<AvatarProps, TextButton>,
	AvatarGroup: Types.Constructor<AvatarGroupProps, Frame>,
	Stage: Types.Constructor<StageProps, ViewportFrame>,
}
return {}
