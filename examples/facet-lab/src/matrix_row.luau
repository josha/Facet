--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type Controls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type StackProps = typeof(require("@repo/tools/typecheck/aliases").StackProps)
type Cell<T> = { set: (Cell<T>, T) -> () }
return function(UI: Controls, Compose: ComposeModule, props: StackProps, available: Cell<number>): Frame
	local row = UI.HStack(props)
	local room = UI.environment(row)
	Compose.watch(function(use)
		available:set(use(room.viewportSize).X)
	end)
	return row
end
