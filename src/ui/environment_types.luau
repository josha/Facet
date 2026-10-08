--!strict
local Types = require("./types")
local Adaptive = require("./adaptive")

export type SizeClass = Adaptive.SizeClass
export type HeightClass = Adaptive.HeightClass
export type Orientation = Adaptive.Orientation
export type InteractionClass = "pointer" | "touch" | "gamepad"
export type InteractionClasses = {
	primary: InteractionClass,
	pointer: boolean,
	touch: boolean,
	gamepad: boolean,
	keyboard: boolean,
}
export type SafeInsets = { top: number, left: number, bottom: number, right: number }
export type DisplaySize = "Small" | "Medium" | "Large"
export type Environment = {
	viewportSize: Types.Readable<Vector2>,
	viewportWidth: Types.Readable<number>,
	viewportHeight: Types.Readable<number>,
	sizeClass: Types.Readable<SizeClass>,
	heightClass: Types.Readable<HeightClass>,
	orientation: Types.Readable<Orientation>,
	isCompact: Types.Readable<boolean>,
	isRegular: Types.Readable<boolean>,
	isWide: Types.Readable<boolean>,
	isRegularOrWider: Types.Readable<boolean>,
	isShort: Types.Readable<boolean>,
	isTall: Types.Readable<boolean>,
	isLandscape: Types.Readable<boolean>,
	axis: Types.Readable<"x" | "y">,
	atLeast: (target: SizeClass) -> Types.Readable<boolean>,
	interactionClasses: Types.Readable<InteractionClasses>,
	effectiveInput: Types.Readable<"Touch" | "Gamepad" | "KeyboardAndMouse">,
	displaySize: Types.Readable<DisplaySize>,
	isTenFoot: Types.Readable<boolean>,
	viewingDistanceSource: Types.Readable<"authored" | "inferred">,
	metricScale: Types.Readable<number>,
	overscanInsets: Types.Readable<SafeInsets>,
	navPlacement: Types.Readable<Adaptive.NavPlacement>,
	safeInsets: Types.Readable<SafeInsets>,
	preferredTextSize: Types.Readable<string>,
	reducedMotion: Types.Readable<boolean>,
	motionLevel: Types.Readable<Types.MotionLevel>,
}
export type EnvironmentSource = Camera | GuiBase2d
export type WorldTarget = BasePart | Model | Player
export type WorldAnchorOptions = {
	target: Types.Value<WorldTarget?>,
	padding: number?,
	offscreen: ("hide" | "retain")?,
	occlusion: boolean?,
	camera: Types.Value<Camera?>?,
}
export type WorldAnchorPoint = {
	x: number?,
	y: number?,
	clearance: number?,
	visible: boolean,
	onscreen: boolean?,
	occluded: boolean?,
}
export type WorldAnchor = { anchor: Types.Readable<WorldAnchorPoint>, dispose: () -> () }
export type ScrollPosition = Vector2 | "top" | "bottom" | { x: number?, y: number? }
export type ScrollOptions = { animated: boolean? }
export type ScrollRect = { x: number, y: number, w: number, h: number }
export type DropOperation = "copy" | "move" | "apply"
export type DropDestination = GuiObject | BasePart | Model
export type DropInsertion = { collection: unknown, beforeKey: unknown?, afterKey: unknown?, slot: number }
export type DropInfo = {
	source: GuiObject,
	target: DropDestination,
	mode: "pointer" | "armed",
	operation: DropOperation,
	position: Vector2?,
	hit: RaycastResult?,
	insertion: DropInsertion?,
	complete: (accepted: boolean, reason: string?) -> boolean,
}
export type DraggableSpec = {
	payload: unknown,
	enabled: Types.ValueBoolean?,
	armOnTap: boolean?,
	touchPickup: ("longPress" | "immediate")?,
	touchDragAxis: ("X" | "Y" | "XY")?,
	statusLabels: boolean?,
	operations: { DropOperation }?,
	valid: (() -> boolean)?,
	onStart: ((payload: unknown, mode: "pointer" | "armed") -> ())?,
	onEnd: ((accepted: boolean, reason: string?) -> ())?,
}
export type DropTargetSpec = {
	label: Types.ValueString?,
	onDrop: ((payload: unknown, info: DropInfo) -> ()) | ((payload: unknown, info: DropInfo) -> boolean | "pending"),
	operation: Types.Value<DropOperation>?,
	passThrough: ((payload: unknown) -> boolean)?,
	focusTarget: GuiObject?,
	accepts: ((payload: unknown, info: DropInfo) -> (boolean, string?))?,
	onReject: ((payload: unknown, reason: string?) -> ())?,
	onEnter: ((payload: unknown) -> ())?,
	onLeave: ((payload: unknown) -> ())?,
	onUpdate: ((payload: unknown, info: DropInfo, accepted: boolean, reason: string?) -> ())?,
}
export type FocusSectionOptions = {
	entry: ("restore" | "first" | "nearest")?,
	preferred: string?,
	focusOnAppear: (boolean | string)?,
	returnFocus: boolean?,
}
export type ResponderOptions = Types.ResponderOptions
export type ResponderState = Types.ResponderState
export type Responder = Types.Responder
export type EnvironmentControls = {
	environment: (source: EnvironmentSource?) -> Environment,
	focusRing: (playerGui: PlayerGui) -> Frame,
	focusSection: (group: GuiObject, options: FocusSectionOptions?) -> (),
	responder: (root: Instance, options: ResponderOptions?) -> Responder,
	draggable: (source: GuiObject, spec: DraggableSpec) -> (),
	dropTarget: (target: DropDestination, spec: DropTargetSpec) -> (),
	worldAnchor: (options: WorldAnchorOptions) -> WorldAnchor,
	scrollTo: (frame: ScrollingFrame, position: ScrollPosition, options: ScrollOptions?) -> boolean,
	scrollToVisible: (node: GuiObject, rect: ScrollRect?, options: ScrollOptions?) -> boolean,
}
return {}
