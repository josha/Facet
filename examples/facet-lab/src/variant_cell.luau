--!strict
type Controls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
return function(UI: Controls, props: any, available: any): Frame
	local bounded: any = table.clone(props)
	bounded.maxWidth = available
	return UI.VStack(bounded)
end
