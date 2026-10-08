--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)

return function(
	Compose: ComposeModule,
	props: any,
	available: any,
	control: boolean?,
	types: any?,
	boundLabel: boolean?,
	maximum: number?
): any
	local width = props.width
	if control == false then
		return props
	end
	local bounded = table.clone(props)
	local room = if maximum
		then Compose.formula(function(use)
			return math.min(maximum, math.max(0, use(available)))
		end)
		else available
	if type(width) == "number" then
		bounded.width = Compose.formula(function(use)
			return math.min(width, math.max(0, use(room)))
		end)
	end
	if boundLabel and type(props.label) == "string" and props.Size == nil and props.width == nil then
		local native = types or { UDim2 = UDim2, Enum = Enum }
		bounded.Size = Compose.formula(function(use)
			return native.UDim2.fromOffset(math.max(0, use(room)), 0)
		end)
		bounded.AutomaticSize = native.Enum.AutomaticSize.Y
	end
	return bounded
end
