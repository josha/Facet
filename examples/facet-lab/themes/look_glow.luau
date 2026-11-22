--!strict

type Themes = typeof(require("@repo/tools/typecheck/aliases").FacetModule.themes)

local looks = require(script.Parent.looks)
return {
	id = "look-glow",
	displayName = "Look: glow",
	build = function(themes: Themes)
		return looks.make(themes, "glow")
	end,
}
