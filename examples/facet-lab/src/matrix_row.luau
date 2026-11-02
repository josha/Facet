--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type Controls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type StackProps = typeof(require("@repo/tools/typecheck/aliases").StackProps)
type NumberCell = typeof(require("@repo/tools/typecheck/aliases").NumberCell)
return function(UI: Controls, Compose: ComposeModule, props: StackProps, available: NumberCell): Frame
	local row = UI.HStack(props)
	local room = UI.environment(row)
	Compose.watch(function(use)
		available:set(use(room.viewportSize).X)
	end)
	return row
end
