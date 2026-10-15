--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type RobloxTypes = typeof(require("@repo/tools/typecheck/aliases").RobloxTypes)
type Readable<T> = { peek: (Readable<T>) -> T }
type Bounded = { width: unknown?, label: unknown?, Size: unknown?, AutomaticSize: unknown? }

return function<P>(
	Compose: ComposeModule,
	props: P & Bounded,
	available: Readable<number>,
	control: boolean?,
	types: RobloxTypes?,
	boundLabel: boolean?,
	maximum: number?
): P & Bounded
	local width = props.width
	if control == false then
		return props
	end
	local room: Readable<number> = if maximum
		then Compose.formula(function(use)
			return math.min(maximum, math.max(0, use(available)))
		end)
		else available
	if type(width) == "number" then
		props.width = Compose.formula(function(use)
			return math.min(width, math.max(0, use(room)))
		end)
	end
	if boundLabel and type(props.label) == "string" and props.Size == nil and width == nil then
		local native = if types then types.UDim2 else UDim2
		props.Size = Compose.formula(function(use)
			return native.fromOffset(math.max(0, use(room)), 0)
		end)
		props.AutomaticSize = if types then types.Enum.AutomaticSize.Y else Enum.AutomaticSize.Y
	end
	return props
end
