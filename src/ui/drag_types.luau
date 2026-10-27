--!strict
local Shared = require("./types")
local Env = require("./environment_types")

export type SourceSpec = Env.DraggableSpec & {
	mark: boolean?,
	navigationHint: string?,
	returnPosition: (() -> Vector2)?,
	liftValue: Shared.ReadOnlyValue<number>?,
	liftVisual: GuiObject?,
}
export type Proposal = Env.DropInfo & { invalid: string? }
export type TargetOptions = {
	placement: Shared.Input<Env.DropPlacement>?,
	worldPlacement: Shared.Input<CFrame>?,
	travel: boolean?,
	landing: ((Env.DropInfo) -> Env.ScrollRect)?,
	label: Shared.ValueString?,
	onDrop: ((unknown, Proposal) -> ())
		| ((unknown, Proposal) -> boolean | "pending")
		| ((unknown, Proposal) -> (boolean | "pending")?),
	operation: Shared.Input<Env.DropOperation>?,
	passThrough: ((unknown) -> boolean)?,
	focusTarget: GuiObject?,
	accepts: ((unknown, Proposal) -> (boolean, string?))?,
	onReject: ((unknown, string?) -> ())?,
	onEnter: ((unknown) -> ())?,
	onLeave: ((unknown) -> ())?,
	onUpdate: ((unknown, Proposal, boolean, string?) -> ())?,
	propose: ((unknown, Proposal) -> ())?,
	collectionAxis: ("X" | "Y")?,
	autoscroll: boolean?,
	scroll: ((Vector2, number) -> boolean)?,
}
export type TargetSpec = TargetOptions & { feedback: boolean? }
export type RegisteredTarget = TargetOptions & { feedback: (UIStroke | Highlight)? }
export type Session = {
	source: Env.DropDestination,
	world: WorldPresentation?,
	spec: SourceSpec,
	mode: "pointer" | "armed",
	payload: unknown,
	press: InputObject?,
	origin: Vector2,
	pickupSize: Vector2,
	pickupAnchor: Vector2,
	position: Vector2?,
	target: Instance?,
	hit: RaycastResult?,
	accepted: boolean?,
	reason: string?,
	operation: Env.DropOperation?,
	pending: boolean?,
	pendingTarget: Instance?,
	executing: boolean?,
	ghost: GuiObject?,
	highlight: Highlight?,
	status: TextLabel?,
	previewSize: Vector2?,
	liftScale: number?,
	armedPreview: GuiObject?,
	effectiveInput: ((Shared.Use?) -> "Touch" | "Gamepad" | "KeyboardAndMouse")?,
	stop: (() -> ())?,
	stopPreview: (() -> ())?,
	stopLift: (() -> ())?,
	stopStatus: (() -> ())?,
	stopTravel: (() -> ())?,
	travelled: boolean?,
}
export type WorldPresentation = {
	move: (Vector2?, CFrame?) -> (),
	land: (() -> ()) -> (),
	release: (boolean, () -> ()) -> () -> (),
}
export type Service = {
	state: Shared.Value<Session?>,
	own: (Env.DropDestination) -> (),
	finish: (boolean?, string?) -> (),
	hover: (Instance?, RaycastResult?) -> (),
	update: (Vector2) -> (),
	commit: (Instance?, Vector2?) -> boolean,
	begin: (
		Env.DropDestination,
		SourceSpec,
		"pointer" | "armed",
		InputObject?,
		(GuiObject | false)?,
		{ position: Vector2, source: GuiObject }?
	) -> (),
	preview: (GuiObject, ScrollingFrame, UDim2?) -> (),
	register: (Instance, TargetSpec) -> (),
	targetOf: (Instance?) -> Instance?,
}
return {}
