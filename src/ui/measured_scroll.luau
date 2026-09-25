--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")

local MEASURE = 100000

return function(
	ctx: Types.Context,
	props: Types.ScrollingFrameNativeProps,
	children: { Types.Child },
	options: { hug: boolean?, name: string? }?
): (ScrollingFrame, Frame, ComposeTypes.Readable<Vector2>)
	local Host, E, D2 = ctx.Host, ctx.types.Enum, ctx.types.UDim2
	local hug = options ~= nil and options.hug == true
	local flowProps: Types.FrameNativeProps = {
		Name = if options and options.name then options.name else "Flow",
		BackgroundTransparency = 1,
		Size = if hug then D2.fromOffset(0, 0) else D2.new(1, 0, 0, 0),
		AutomaticSize = if hug then E.AutomaticSize.XY else E.AutomaticSize.Y,
	}
	for _, child in children do
		table.insert(flowProps, child)
	end
	local flow = Host.Frame(flowProps)
	local size = ctx.observe(flow, "AbsoluteSize")
	props.AutomaticCanvasSize = E.AutomaticSize.None
	props.CanvasSize = function(use: ComposeTypes.Use)
		return D2.fromOffset(0, use(size).Y)
	end
	table.insert(
		props,
		Host.Frame({
			Name = "Measure",
			BackgroundTransparency = 1,
			Size = if hug then D2.fromOffset(0, MEASURE) else D2.new(1, 0, 0, MEASURE),
			AutomaticSize = if hug then E.AutomaticSize.X else E.AutomaticSize.None,
			flow,
		})
	)
	return Host.ScrollingFrame(props), flow, size
end
