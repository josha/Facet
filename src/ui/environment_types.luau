--!strict
local Types = require("./types")
local Adaptive = require("./adaptive")
local Gesture = require("./gesture_arbitration")

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
	viewportSize: Types.ReadOnlyValue<Vector2>,
	viewportWidth: Types.ReadOnlyValue<number>,
	viewportHeight: Types.ReadOnlyValue<number>,
	sizeClass: Types.ReadOnlyValue<SizeClass>,
	heightClass: Types.ReadOnlyValue<HeightClass>,
	orientation: Types.ReadOnlyValue<Orientation>,
	isCompact: Types.ReadOnlyValue<boolean>,
	isRegular: Types.ReadOnlyValue<boolean>,
	isWide: Types.ReadOnlyValue<boolean>,
	isRegularOrWider: Types.ReadOnlyValue<boolean>,
	isShort: Types.ReadOnlyValue<boolean>,
	isTall: Types.ReadOnlyValue<boolean>,
	thumbTarget: Types.ReadOnlyValue<number>,
	isLandscape: Types.ReadOnlyValue<boolean>,
	axis: Types.ReadOnlyValue<"x" | "y">,
	atLeast: (target: SizeClass) -> Types.ReadOnlyValue<boolean>,
	interactionClasses: Types.ReadOnlyValue<InteractionClasses>,
	effectiveInput: Types.ReadOnlyValue<"Touch" | "Gamepad" | "KeyboardAndMouse">,
	displaySize: Types.ReadOnlyValue<DisplaySize>,
	isTenFoot: Types.ReadOnlyValue<boolean>,
	viewingDistanceSource: Types.ReadOnlyValue<"authored" | "inferred">,
	metricScale: Types.ReadOnlyValue<number>,
	scaled: (value: number | string, relativeTo: string?) -> Types.ReadOnlyValue<number>,
	layoutSize: (node: GuiBase2d) -> Types.ReadOnlyValue<Vector2>,
	overscanInsets: Types.ReadOnlyValue<SafeInsets>,
	navPlacement: Types.ReadOnlyValue<Adaptive.NavPlacement>,
	safeInsets: Types.ReadOnlyValue<SafeInsets>,
	topbarInset: Types.ReadOnlyValue<Rect>,
	topbarControlDiameter: Types.ReadOnlyValue<number>,
	gameplaySuspended: Types.ReadOnlyValue<boolean>,
	preferredTextSize: Types.ReadOnlyValue<string>,
	reducedMotion: Types.ReadOnlyValue<boolean>,
	motionLevel: Types.ReadOnlyValue<Types.MotionLevel>,
}
export type EnvironmentSource = Camera | GuiBase2d
export type WorldTarget = BasePart | Model | Player
export type WorldAnchorOptions = {
	target: Types.Input<WorldTarget?>,
	padding: number?,
	offscreen: ("hide" | "retain")?,
	occlusion: boolean?,
	camera: Types.Input<Camera?>?,
}
export type WorldAnchorPoint = {
	x: number?,
	y: number?,
	clearance: number?,
	visible: boolean,
	onscreen: boolean?,
	occluded: boolean?,
}
export type WorldAnchor = { anchor: Types.ReadOnlyValue<WorldAnchorPoint>, dispose: () -> () }
export type ScrollPosition = Vector2 | "top" | "bottom" | { x: number?, y: number? }
export type ScrollOptions = { animated: boolean? }
export type ScrollRect = { x: number, y: number, w: number, h: number }
export type DropOperation = "copy" | "move" | "apply"
export type DropDestination = GuiObject | BasePart | Model
export type WorldDragOptions = {
	plane: CFrame,
	lift: number?,
	focusTarget: GuiObject,
	hitArea: GuiObject?,
	maxActivationDistance: number?,
}
export type DropInsertion = { collection: unknown, beforeKey: unknown?, afterKey: unknown?, slot: number }
export type DropPlacement = { column: number, row: number, width: number, height: number }
export type DropInfo = {
	source: DropDestination,
	target: DropDestination,
	mode: "pointer" | "armed",
	operation: DropOperation,
	position: Vector2?,
	hit: RaycastResult?,
	insertion: DropInsertion?,
	placement: DropPlacement?,
	worldPlacement: CFrame?,
	complete: (accepted: boolean, reason: string?) -> boolean,
}
export type DraggableSpec = {
	payload: unknown,
	world: WorldDragOptions?,
	enabled: Types.ValueBoolean?,
	armOnTap: boolean?,
	touchPickup: ("longPress" | "immediate")?,
	touchDragAxis: ("X" | "Y" | "XY")?,
	statusLabels: boolean?,
	previewScale: number?,
	preview: GuiObject?,
	hitArea: GuiObject?,
	returnTravel: boolean?,
	mark: boolean?,
	operations: { DropOperation }?,
	valid: (() -> boolean)?,
	onStart: ((payload: unknown, mode: "pointer" | "armed") -> ())?,
	onEnd: ((accepted: boolean, reason: string?) -> ())?,
}
export type DropTargetSpec = {
	placement: Types.Input<DropPlacement>?,
	worldPlacement: Types.Input<CFrame>?,
	travel: boolean?,
	landing: ((info: DropInfo) -> ScrollRect)?,
	label: Types.ValueString?,
	onDrop: ((payload: unknown, info: DropInfo) -> ()) | ((payload: unknown, info: DropInfo) -> boolean | "pending"),
	operation: Types.Input<DropOperation>?,
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
	gestureArbiter: (surface: Instance) -> Gesture.Binding,
	draggable: (source: DropDestination, spec: DraggableSpec) -> (),
	dropTarget: (target: DropDestination, spec: DropTargetSpec) -> (),
	worldAnchor: (options: WorldAnchorOptions) -> WorldAnchor,
	scrollTo: (frame: ScrollingFrame, position: ScrollPosition, options: ScrollOptions?) -> boolean,
	scrollToVisible: (node: GuiObject, rect: ScrollRect?, options: ScrollOptions?) -> boolean,
}
return {}
