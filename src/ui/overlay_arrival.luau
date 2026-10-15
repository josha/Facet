--!strict
local ComposeTypes = require("../vendor/compose/core")

local readiness = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [unknown]: ComposeTypes.Readable<boolean> }

return {
	bind = function(phase: unknown, ready: ComposeTypes.Readable<boolean>)
		readiness[phase] = ready
	end,
	ready = function(phase: unknown): ComposeTypes.Readable<boolean>?
		return readiness[phase]
	end,
}
