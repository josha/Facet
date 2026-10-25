--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")

return function(ctx: Types.Context, frame: ScrollingFrame, axis: "X" | "Y", when: ComposeTypes.Readable<boolean>)
	local Compose, V2 = ctx.Compose, ctx.types.Vector2
	local frames = ctx.config.services and ctx.config.services.RunService
	if frames == nil then
		return
	end
	Compose.watch(function(use: ComposeTypes.Use)
		if not use(when) then
			return
		end
		local at = frame.CanvasPosition
		if (if axis == "X" then at.X else at.Y) ~= 0 then
			return
		end
		local nudged = if axis == "X" then V2.new(1, at.Y) else V2.new(at.X, 1)
		frame.CanvasPosition = nudged
		local connection: RBXScriptConnection? = nil
		local function settle()
			local held = connection
			connection = nil
			if held then
				held:Disconnect()
				if frame.CanvasPosition == nudged then
					frame.CanvasPosition = at
				end
			end
		end
		connection = frames.Heartbeat:Connect(settle)
		Compose.cleanup(settle)
	end)
end
