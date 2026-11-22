--!strict

type Themes = typeof(require("@repo/tools/typecheck/aliases").FacetModule.themes)

local looks = require(script.Parent.looks)
return {
	id = "look-hard",
	displayName = "Look: hard",
	build = function(themes: Themes)
		return looks.make(themes, "hard")
	end,
}
