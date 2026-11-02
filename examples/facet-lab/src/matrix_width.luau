--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type RobloxTypes = typeof(require("@repo/tools/typecheck/aliases").RobloxTypes)
type ReadOnlyValue<T> = typeof(require("@repo/src/vendor/compose/core").accumulator<<T, number>>(nil :: never))
type Bounded = { width: unknown?, label: unknown?, Size: unknown?, AutomaticSize: unknown? }

return function<P>(
	Compose: ComposeModule,
	props: P & Bounded,
	available: ReadOnlyValue<number>,
	control: boolean?,
	types: RobloxTypes?,
	boundLabel: boolean?,
	maximum: number?
): P & Bounded
	local bounded: Bounded = props
	local width = bounded.width
	if control == false then
		return props
	end
	local room: ReadOnlyValue<number> = if maximum
		then Compose.formula(function(use)
			return math.min(maximum, math.max(0, use(available)))
		end)
		else available
	if type(width) == "number" then
		bounded.width = Compose.formula(function(use)
			return math.min(width, math.max(0, use(room)))
		end)
	end
	if boundLabel and type(bounded.label) == "string" and bounded.Size == nil and width == nil then
		local native = if types then types.UDim2 else UDim2
		bounded.Size = Compose.formula(function(use)
			return native.fromOffset(math.max(0, use(room)), 0)
		end)
		bounded.AutomaticSize = if types then types.Enum.AutomaticSize.Y else Enum.AutomaticSize.Y
	end
	return props
end
