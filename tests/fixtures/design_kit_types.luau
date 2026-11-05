--!strict
local Facet = require("../../src")
local Editor = require("../../src/vendor/compose/design-editor")

return function(open: () -> Editor.Workspace, parent: Instance): { Facet.DesignStudioKit }
	local built: Facet.DesignStudioKit = Editor.kit("Host", open)
	local facet: Facet.DesignStudioKit = Facet.composeDesign()
	local editor: Facet.DesignStudioEditor = Facet.composeDesign().edit(parent, "Screen")
	editor.dispose()
	return { built, facet }
end
