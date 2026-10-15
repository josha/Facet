--!strict
type Controls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type StackProps = typeof(require("@repo/tools/typecheck/aliases").StackProps)
type Readable<T> = { peek: (Readable<T>) -> T }
return function(UI: Controls, props: StackProps, available: Readable<number>): Frame
	local bounded = table.clone(props)
	bounded.maxWidth = available
	return UI.VStack(bounded)
end
