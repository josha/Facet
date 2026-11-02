--!strict
local ComposeTypes = require("../vendor/compose/core")

local readiness: { [unknown]: ComposeTypes.ReadOnlyValue<boolean> } = setmetatable({}, { __mode = "k" })

return {
	bind = function(phase: unknown, ready: ComposeTypes.ReadOnlyValue<boolean>)
		readiness[phase] = ready
	end,
	ready = function(phase: unknown): ComposeTypes.ReadOnlyValue<boolean>?
		return readiness[phase]
	end,
}
