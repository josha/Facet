--!strict
local Types = require("./types")

return function(ctx: Types.Context, frame: ScrollingFrame, source: Types.Value<Vector2>?)
	if source == nil then
		return
	end
	local pending: Vector2? = ctx.read(source)
	local canvas = ctx.observe.AbsoluteCanvasSize(frame)
	local window = ctx.observe.AbsoluteWindowSize(frame)
	local function cancel(input: InputObject)
		local kind = input.UserInputType
		local E = ctx.types.Enum
		if
			kind == E.UserInputType.Touch
			or kind == E.UserInputType.MouseButton1
			or kind == E.UserInputType.MouseWheel
		then
			pending = nil
		end
	end
	ctx.runtime.connect(frame, "InputBegan", cancel)
	ctx.runtime.connect(frame, "InputChanged", cancel)
	ctx.Compose.watch(function(use)
		local extent, view = use(canvas), use(window)
		local goal = pending
		if goal == nil or view.X <= 0 or view.Y <= 0 then
			return
		end
		if (goal.X ~= 0 and extent.X <= view.X) or (goal.Y ~= 0 and extent.Y <= view.Y) then
			return
		end
		frame.CanvasPosition = goal
		if frame.CanvasPosition == goal then
			pending = nil
		end
	end)
end
