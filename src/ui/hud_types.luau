--!strict
local Shared = require("./types")
local Media = require("./media_types")

export type TimerControls = { completed: Shared.Readable<boolean>? }
export type TimerOptions = {
	ref: ((TextLabel) -> ())?,
	deadline: Shared.ValueNumber?,
	start: Shared.ValueNumber?,
	now: (() -> number)?,
	hours: boolean?,
	textRole: Shared.Value<Media.TextRole>?,
	onComplete: (() -> ())?,
	controls: TimerControls?,
}
export type TypewriterControls = {
	revealed: Shared.Readable<boolean>?,
	finish: (() -> ())?,
}
export type TypewriterOptions = {
	onRevealed: (() -> ())?,
	controls: TypewriterControls?,
}

return {}
