--!strict
local Types = require("./types")

local DEPTH = 8

return function(ctx: Types.Context, frame: ScrollingFrame)
	local runtime = ctx.runtime
	local V2 = ctx.types.Vector2
	local unit = ctx.layoutUnit(frame)
	local container = frame:FindFirstChild("LayoutUnitContainer")
	local origin = assert(if container then container:FindFirstChild("LayoutUnit") else nil) :: GuiObject
	local anchor: GuiObject? = nil
	local distance = 0

	local function first(parent: Instance, line: number): GuiObject?
		local best: GuiObject? = nil
		local bestTop = math.huge
		for _, child in parent:GetChildren() do
			if child:IsA("GuiObject") and child.Visible then
				local top, height = child.AbsolutePosition.Y, child.AbsoluteSize.Y
				if height > 0 and top + height > line and top < bestTop then
					best, bestTop = child, top
				end
			end
		end
		return best
	end

	local function pick(line: number): GuiObject?
		local node = first(frame, line)
		local depth = 0
		while node and node.AbsolutePosition.Y < line and depth < DEPTH do
			local inner = first(node, line)
			if inner == nil then
				break
			end
			node = inner
			depth += 1
		end
		return node
	end

	local function record()
		local line = frame.AbsolutePosition.Y
		local current = anchor
		local top = if current then current.AbsolutePosition.Y else 0
		if
			current == nil
			or not current:IsDescendantOf(frame)
			or top > line
			or top + current.AbsoluteSize.Y <= line
		then
			current = if frame.CanvasPosition.Y > 0 then pick(line) else nil
			anchor = current
			distance = if current then current.AbsolutePosition.Y - origin.AbsolutePosition.Y else 0
		end
	end

	local function settle()
		local current = anchor
		if current ~= nil and frame.CanvasPosition.Y > 0 and current:IsDescendantOf(frame) then
			local drift = current.AbsolutePosition.Y - origin.AbsolutePosition.Y - distance
			if math.abs(drift) > 0.5 then
				local scale = unit:peek()
				local most = math.max(0, frame.AbsoluteCanvasSize.Y - frame.AbsoluteWindowSize.Y) / scale
				local position = frame.CanvasPosition
				distance += drift
				frame.CanvasPosition = V2.new(position.X, math.clamp(position.Y + drift / scale, 0, most))
			end
		end
		record()
	end

	local observation = assert(runtime.host.observation)
	ctx.Compose.cleanup(observation.observeProperty(frame, "CanvasPosition", record))
	ctx.Compose.cleanup(observation.observeProperty(frame, "AbsoluteCanvasSize", settle))
end
