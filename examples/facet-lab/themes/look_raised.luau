--!strict

type Themes = typeof(require("@repo/tools/typecheck/aliases").FacetModule.themes)

local looks = require(script.Parent.looks)
return {
	id = "look-raised",
	displayName = "Look: raised",
	build = function(themes: Themes)
		return looks.make(themes, "raised")
	end,
}
