--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local scrollLock = require("./scroll_lock")

local MEASURE = 100000

return function(
	ctx: Types.Context,
	props: Types.ScrollingFrameNativeProps,
	children: { Types.Child },
	options: { hug: boolean?, name: string?, rest: boolean? }?
): (
	ScrollingFrame,
	Frame,
	ComposeTypes.ReadOnlyValue<Vector2>,
	ComposeTypes.ReadOnlyValue<number>,
	ComposeTypes.ReadOnlyValue<boolean>
)
	local Host, Compose, E, D2 = ctx.Host, ctx.Compose, ctx.types.Enum, ctx.types.UDim2
	local hug = options ~= nil and options.hug == true
	local flowProps: Types.FrameNativeProps = {
		Name = if options and options.name then options.name else "Flow",
		BackgroundTransparency = 1,
		Size = if hug then D2.fromOffset(0, 0) else D2.new(1, 0, 0, 0),
		AutomaticSize = if hug then E.AutomaticSize.XY else E.AutomaticSize.Y,
	}
	for _, child in children do
		flowProps[#flowProps + 1] = child
	end
	local flow = Host.Frame(flowProps)
	local size = ctx.observe.AbsoluteSize(flow)
	local extent = Compose.cell(0)
	props.AutomaticCanvasSize = E.AutomaticSize.None
	props.CanvasSize = function(use: ComposeTypes.Use)
		return D2.fromOffset(0, use(extent))
	end
	props[#props + 1] = Host.Frame "Measure" {
		BackgroundTransparency = 1,
		Size = if hug then D2.fromOffset(0, MEASURE) else D2.new(1, 0, 0, MEASURE),
		AutomaticSize = if hug then E.AutomaticSize.X else E.AutomaticSize.None,
		flow,
	}
	local scroller = Host.ScrollingFrame(props)
	scrollLock.own(scroller, ctx)
	local laidOut = ctx.layoutSize(flow, ctx.layoutUnit(scroller))
	Compose.watch(function(use: ComposeTypes.Use)
		extent:set(math.ceil(use(laidOut).Y - 0.01))
	end)
	local rested = if options and options.rest
		then ctx.runtime.settled {
			sample = function(): number
				return extent:peek()
			end,
			equals = function(a: number, b: number): boolean
				return (b > 0 or size:peek().X > 0) and a == b
			end,
			timeout = ctx.metric("motion.restLimit"),
		}
		else Compose.cell(true)
	return scroller, flow, size, extent, rested
end
