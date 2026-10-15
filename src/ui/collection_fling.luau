--!strict
local Types = require("./types")
local State = require("./collection_state")
local FLING_MINIMUM = 200
local FLING_STOP = 20
local FLING_WINDOW = 0.1
return function<V, K>(ctx: Types.Context, view: State.View<V, K>, root: ScrollingFrame): ()
	local runtime = ctx.runtime
	local V2, E = ctx.types.Vector2, ctx.types.Enum
	local gui = ctx.config.guiService
	local spec, frames = view.spec, view.frames
	local input = ctx.config.userInputService
	if view.horizontal and input and not spec.reorderable then
		local pressAt: number? = nil
		local startOffset, dragging = 0, false
		local samples: { Vector2 } = {}
		local velocity = 0
		local stopFling: (() -> ())? = nil
		local function halt(): ()
			if stopFling then
				stopFling()
				stopFling = nil
			end
		end
		ctx.Compose.cleanup(halt)
		local function limit(): number
			return math.max(0, root.CanvasSize.X.Offset - root.AbsoluteWindowSize.X)
		end
		local function items(): Instance?
			return root:FindFirstChild("Items")
		end
		local function inside(position: Vector3): boolean
			local point = V2.new(position.X, position.Y)
			local layer = root:FindFirstAncestorWhichIsA("LayerCollector")
			if layer and layer:IsA("ScreenGui") and layer.IgnoreGuiInset and gui then
				point += gui:GetGuiInset()
			end
			local at, size = root.AbsolutePosition, root.AbsoluteSize
			return point.X >= at.X and point.Y >= at.Y and point.X <= at.X + size.X and point.Y <= at.Y + size.Y
		end
		runtime.connect(input, "InputBegan", function(value: InputObject)
			if
				value.UserInputType == E.UserInputType.MouseButton1
				and inside(value.Position)
				and ctx.available(root)
			then
				halt()
				pressAt, startOffset, dragging = value.Position.X, root.CanvasPosition.X, false
				samples = { V2.new(frames.now(), value.Position.X) }
			end
		end)
		runtime.connect(input, "InputChanged", function(value: InputObject)
			if pressAt == nil or value.UserInputType ~= E.UserInputType.MouseMovement then
				return
			end
			local travel = value.Position.X - pressAt
			if not dragging and math.abs(travel) >= 6 then
				dragging = true
				local node = items()
				if node and node:IsA("GuiObject") then
					node.Interactable = false
				end
			end
			local now = frames.now()
			table.insert(samples, V2.new(now, value.Position.X))
			while #samples > 2 and now - samples[1].X > FLING_WINDOW do
				table.remove(samples, 1)
			end
			if dragging then
				root.CanvasPosition = V2.new(math.clamp(startOffset - travel, 0, limit()), root.CanvasPosition.Y)
			end
		end)
		runtime.connect(input, "InputEnded", function(value: InputObject)
			if value.UserInputType ~= E.UserInputType.MouseButton1 or pressAt == nil then
				return
			end
			pressAt = nil
			if dragging then
				dragging = false
				local stop: (() -> ())? = nil
				stop = frames.onFrame(function()
					if stop then
						stop()
					end
					local node = items()
					if node and node:IsA("GuiObject") then
						node.Interactable = true
					end
				end)
				local first, last = samples[1], samples[#samples]
				local span = last.X - first.X
				velocity = if span > 0 then (first.Y - last.Y) / span else 0
				if frames.now() - last.X < FLING_WINDOW and math.abs(velocity) > FLING_MINIMUM then
					local friction = ctx.metric("motion.fling.friction")
					stopFling = frames.onFrame(function(step: number)
						velocity *= math.exp(-friction * step)
						local at = root.CanvasPosition.X
						local nextX = math.clamp(at + velocity * step, 0, limit())
						root.CanvasPosition = V2.new(nextX, root.CanvasPosition.Y)
						if math.abs(velocity) < FLING_STOP or nextX == at then
							halt()
						end
					end)
				end
			end
		end)
	end
end
