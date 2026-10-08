--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)

return function(Compose: ComposeModule, props: any, available: any): any
	local width = props.width
	if type(width) ~= "number" then
		return props
	end
	local bounded = table.clone(props)
	bounded.width = Compose.formula(function(use)
		return math.min(width, math.max(0, use(available)))
	end)
	return bounded
end
