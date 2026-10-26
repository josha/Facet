--!strict
local Shared = require("./types")
local Media = require("./media_types")
local Env = require("./environment_types")

export type TimerControls = { completed: Shared.ReadOnlyValue<boolean>? }
export type TimerOptions = {
	ref: ((TextLabel) -> ())?,
	deadline: Shared.ValueNumber?,
	start: Shared.ValueNumber?,
	now: (() -> number)?,
	hours: boolean?,
	textRole: Shared.Input<Media.TextRole>?,
	onComplete: (() -> ())?,
	controls: TimerControls?,
}
export type TypewriterControls = {
	revealed: Shared.ReadOnlyValue<boolean>?,
	finish: (() -> ())?,
}
export type TypewriterOptions = {
	onRevealed: (() -> ())?,
	controls: TypewriterControls?,
}
export type WorldMarkerEdge = "clamp" | "hide"
export type WorldMarkerOptions = {
	anchor: Shared.ReadOnlyValue<Env.WorldAnchorPoint>,
	edge: Shared.Input<WorldMarkerEdge>?,
	margin: Shared.Input<Shared.Padding>?,
	arrow: Shared.Input<boolean>?,
}

return {}
