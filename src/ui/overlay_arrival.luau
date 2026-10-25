--!strict
local ComposeTypes = require("../vendor/compose/core")

local readiness = setmetatable({} :: { [unknown]: ComposeTypes.Readable<boolean> }, { __mode = "k" })

return {
	bind = function(phase: unknown, ready: ComposeTypes.Readable<boolean>)
		readiness[phase] = ready
	end,
	ready = function(phase: unknown): ComposeTypes.Readable<boolean>?
		return readiness[phase]
	end,
}
