--!strict

local foundation = require(assert(script.Parent).foundation) :: any
return {
	id = foundation.id,
	displayName = foundation.displayName,
	build = function(themes: any): (any, any)
		return foundation.build(themes, "foundation-dark")
	end,
}
