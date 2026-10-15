--!strict

type Themes = typeof(require("@repo/tools/typecheck/aliases").FacetModule.themes)

local foundation = require(script.Parent.foundation)
return {
	id = foundation.id,
	displayName = foundation.displayName,
	build = function(themes: Themes)
		return foundation.build(themes, "foundation-light")
	end,
}
