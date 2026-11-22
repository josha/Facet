--!strict

type Themes = typeof(require("@repo/tools/typecheck/aliases").FacetModule.themes)

local looks = require(script.Parent.looks)
return {
	id = "look-flat",
	displayName = "Look: flat",
	build = function(themes: Themes)
		return looks.make(themes, "flat")
	end,
}
