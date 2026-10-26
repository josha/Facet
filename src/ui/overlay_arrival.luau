--!strict
local ComposeTypes = require("../vendor/compose/core")

local readiness = setmetatable({} :: { [unknown]: ComposeTypes.ReadOnlyValue<boolean> }, { __mode = "k" })

return {
	bind = function(phase: unknown, ready: ComposeTypes.ReadOnlyValue<boolean>)
		readiness[phase] = ready
	end,
	ready = function(phase: unknown): ComposeTypes.ReadOnlyValue<boolean>?
		return readiness[phase]
	end,
}
