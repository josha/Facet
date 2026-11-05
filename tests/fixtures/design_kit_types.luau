--!strict
local Facet = require("../../src")
local Editor = require("../../src/vendor/compose/design-editor")

return function(open: () -> Editor.Workspace): { Facet.DesignStudioKit }
	local built: Facet.DesignStudioKit = Editor.kit("Host", open)
	local facet: Facet.DesignStudioKit = Facet.composeDesign()
	local shared: Editor.Kit = facet
	return { built, facet, shared }
end
