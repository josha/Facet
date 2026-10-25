--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local Nav = require("./navigation_types")
local Media = require("./media_types")

export type Value<T> = Types.Value<T>

export type Diagnostics = { diagnostics: (() -> { string })? }
export type PaginationForm = "numbers" | "arrows" | "label"
export type PaginationOptions = {
	page: Types.ValueNumber,
	onChange: (number) -> (),
	pageCount: Value<number?>?,
	hasNext: Types.ValueBoolean?,
	hasPrevious: Types.ValueBoolean?,
	siblingCount: number?,
	boundaryCount: number?,
	showFirstLast: boolean?,
	form: PaginationForm?,
	direction: ("ltr" | "rtl")?,
	controlSize: Value<Types.ControlSize?>?,
	enabled: Types.ValueBoolean?,
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
export type StepIndicatorOptions = {
	steps: Value<{ Step }>,
	current: Value<string?>,
	onSelect: ((string) -> ())?,
	sizing: ("fill" | "hug")?,
	listLabel: string?,
	controlSize: Value<Types.ControlSize?>?,
	enabled: Types.ValueBoolean?,
	controls: Diagnostics?,
}
export type VoteValue = "up" | "down" | "none"
export type VoteOptions = {
	value: Value<VoteValue>,
	onChange: ((VoteValue) -> ())?,
	summary: Types.ValueString?,
	readOnly: Types.ValueBoolean?,
	controlSize: Value<Types.ControlSize?>?,
	enabled: Types.ValueBoolean?,
	controls: Diagnostics?,
}
export type CardAction = {
	label: Types.ValueString,
	icon: Types.ValueString?,
	onActivate: () -> (),
	enabled: Types.ValueBoolean?,
	busy: Types.ValueBoolean?,
}
export type CardMenu = { items: Value<{ Nav.MenuItem<string> }>, label: Types.ValueString? }
export type CardBadge = {
	label: Value<string?>?,
	status: Value<Media.Status>?,
	icon: Types.ValueString?,
	name: string?,
}
export type CardBadges = { leading: CardBadge?, trailing: CardBadge? }
export type CardControls = {
	diagnostics: (() -> { string })?,
	enterActions: (() -> boolean)?,
	leaveActions: (() -> ())?,
	engaged: ComposeTypes.Readable<boolean>?,
	revealed: ComposeTypes.Readable<boolean>?,
	scale: ComposeTypes.Readable<number>?,
	lifting: ComposeTypes.Readable<boolean>?,
	revealExtent: ComposeTypes.Readable<{ body: number }>?,
}
export type CardOptions = {
	image: Types.ValueString?,
	artwork: (() -> GuiObject)?,
	title: Types.ValueString,
	caption: Types.ValueString?,
	imageAspectRatio: number?,
	imageFraming: ("fit" | "crop")?,
	onActivate: ((input: InputObject?) -> ())?,
	primaryAction: CardAction?,
	menu: CardMenu?,
	reveal: ("automatic" | "always")?,
	browseTarget: (() -> GuiObject?)?,
	enabled: Types.ValueBoolean?,
	controls: CardControls?,
	ringTarget: ("card" | "media")?,
	badges: CardBadges?,
}
export type BadgeValue = string | number | boolean
export type BadgedOptions = { direction: ("ltr" | "rtl")?, status: Value<Media.Status>? }
export type Badged = (GuiObject, Value<BadgeValue?>, BadgedOptions?) -> Frame
return {}
