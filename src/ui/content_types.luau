--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local Nav = require("./navigation_types")

type Value<T> = Types.Value<T>

export type Diagnostics = { diagnostics: (() -> { string })? }
export type PaginationForm = "numbers" | "arrows" | "label"
export type PaginationSpec = Types.FrameProps & {
	page: Value<number>,
	onChange: (number) -> (),
	pageCount: Value<number?>?,
	hasNext: Value<boolean>?,
	hasPrevious: Value<boolean>?,
	siblingCount: number?,
	boundaryCount: number?,
	showFirstLast: boolean?,
	form: PaginationForm?,
	direction: ("ltr" | "rtl")?,
	controlSize: Value<Types.ControlSize>?,
	enabled: Value<boolean>?,
	controls: Diagnostics?,
}
export type StepState = "complete" | "current" | "upcoming" | "error"
export type Step = {
	id: string,
	label: string,
	description: string?,
	state: StepState?,
	navigable: boolean?,
	enabled: boolean?,
}
export type StepIndicatorSpec = Types.FrameProps & {
	steps: Value<{ Step }>,
	current: Value<string?>,
	onSelect: ((string) -> ())?,
	sizing: ("fill" | "hug")?,
	listLabel: string?,
	controlSize: Value<Types.ControlSize>?,
	enabled: Value<boolean>?,
	controls: Diagnostics?,
}
export type VoteValue = "up" | "down" | "none"
export type VoteSpec = Types.FrameProps & {
	value: Value<VoteValue>,
	onChange: ((VoteValue) -> ())?,
	summary: Value<string>?,
	readOnly: Value<boolean>?,
	controlSize: Value<Types.ControlSize>?,
	enabled: Value<boolean>?,
	controls: Diagnostics?,
}
export type CardAction = {
	label: Value<string>,
	icon: Value<string>?,
	onActivate: () -> (),
	enabled: Value<boolean>?,
	busy: Value<boolean>?,
}
export type CardMenu = { items: Value<{ Nav.MenuItem<string> }>, label: Value<string>? }
export type CardControls = Diagnostics & {
	enterActions: (() -> boolean)?,
	leaveActions: (() -> ())?,
	engaged: ComposeTypes.Readable<boolean>?,
	revealed: ComposeTypes.Readable<boolean>?,
	scale: ComposeTypes.Readable<number>?,
	lifting: ComposeTypes.Readable<boolean>?,
	revealExtent: ComposeTypes.Readable<{ body: number }>?,
}
export type CardSpec = Types.FrameProps & {
	image: Value<string>?,
	artwork: (() -> GuiObject)?,
	title: Value<string>,
	caption: Value<string>?,
	imageAspectRatio: number?,
	imageFraming: ("fit" | "crop")?,
	onActivate: ((input: InputObject?) -> ())?,
	primaryAction: CardAction?,
	menu: CardMenu?,
	reveal: ("automatic" | "always")?,
	browseTarget: (() -> GuiObject?)?,
	enabled: Value<boolean>?,
	controls: CardControls?,
}
export type BadgeValue = string | number | boolean
export type Badged = (GuiObject, Value<BadgeValue?>, ("ltr" | "rtl")?) -> Frame
export type ContentControls = {
	badged: Badged,
	Card: Types.Constructor<CardSpec, Frame>,
	Pagination: Types.Constructor<PaginationSpec, Frame>,
	StepIndicator: Types.Constructor<StepIndicatorSpec, Frame>,
	Vote: Types.Constructor<VoteSpec, Frame>,
}
return {}
