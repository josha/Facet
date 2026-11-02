--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local Nav = require("./navigation_types")
local Media = require("./media_types")

export type Input<T> = Types.Input<T>

export type Diagnostics = { diagnostics: (() -> { string })? }
export type PaginationForm = "numbers" | "arrows" | "label"
export type PaginationOptions = {
	page: Types.ValueNumber,
	onChange: (number) -> (),
	pageCount: Input<number?>?,
	hasNext: Types.ValueBoolean?,
	hasPrevious: Types.ValueBoolean?,
	siblingCount: number?,
	boundaryCount: number?,
	showFirstLast: boolean?,
	form: PaginationForm?,
	direction: ("ltr" | "rtl")?,
	controlSize: Input<Types.ControlSize?>?,
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
	steps: Input<{ Step }>,
	current: Input<string?>,
	onSelect: ((string) -> ())?,
	sizing: ("fill" | "hug")?,
	listLabel: string?,
	controlSize: Input<Types.ControlSize?>?,
	enabled: Types.ValueBoolean?,
	controls: Diagnostics?,
}
export type VoteValue = "up" | "down" | "none"
export type VoteOptions = {
	value: Input<VoteValue>,
	onChange: ((VoteValue) -> ())?,
	summary: Types.ValueString?,
	readOnly: Types.ValueBoolean?,
	controlSize: Input<Types.ControlSize?>?,
	enabled: Types.ValueBoolean?,
	controls: Diagnostics?,
}
export type CardAction = {
	read label: Types.ValueString,
	read icon: Types.ValueString?,
	read onActivate: () -> (),
	read enabled: Types.ValueBoolean?,
	read busy: Types.ValueBoolean?,
}
export type CardMenu = { read items: Input<{ Nav.MenuItem<string> }>, read label: Types.ValueString? }
export type CardBadge = {
	label: Input<string?>?,
	status: Input<Media.Status>?,
	icon: Input<string?>?,
	name: string?,
}
export type CardBadges = { leading: CardBadge?, trailing: CardBadge? }
export type CardControls = {
	diagnostics: (() -> { string })?,
	enterActions: (() -> boolean)?,
	leaveActions: (() -> ())?,
	engaged: ComposeTypes.ReadOnlyValue<boolean>?,
	revealed: ComposeTypes.ReadOnlyValue<boolean>?,
	scale: ComposeTypes.ReadOnlyValue<number>?,
	lifting: ComposeTypes.ReadOnlyValue<boolean>?,
	revealExtent: ComposeTypes.ReadOnlyValue<{ body: number }>?,
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
export type BadgedOptions = { direction: ("ltr" | "rtl")?, status: Input<Media.Status>? }
export type Badged = (GuiObject, Input<BadgeValue?>, BadgedOptions?) -> Frame
return {}
