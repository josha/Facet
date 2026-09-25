--!strict
local Shared = require("./types")
local Env = require("./environment_types")

type Playback = { Play: (Playback) -> (), Cancel: (Playback) -> () }
type Tweens = { Create: (Tweens, Instance, TweenInfo, { [string]: unknown }) -> Playback }

return function(ctx: Shared.Context, UI: Env.EnvironmentControls)
	local config = ctx.config
	local types = ctx.types
	local V2 = types.Vector2
	local E = types.Enum
	local running: { [Instance]: Playback } = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [Instance]: Playback }

	local function reduced(): boolean
		if ctx.read(config.reducedMotion) == true then
			return true
		end
		local gui = config.guiService
		if gui == nil then
			return false
		end
		local ok, value = pcall(function()
			return gui.ReducedMotionEnabled
		end)
		return ok and value == true
	end

	local function limit(frame: ScrollingFrame): Vector2
		local canvas, window = frame.AbsoluteCanvasSize, frame.AbsoluteWindowSize
		return V2.new(math.max(0, canvas.X - window.X), math.max(0, canvas.Y - window.Y))
	end

	local function move(frame: ScrollingFrame, target: Vector2, options: Env.ScrollOptions?): boolean
		local most = limit(frame)
		local goal = V2.new(math.clamp(target.X, 0, most.X), math.clamp(target.Y, 0, most.Y))
		local previous = running[frame]
		if previous then
			running[frame] = nil
			previous:Cancel()
		end
		if goal == frame.CanvasPosition then
			return false
		end
		local tweens = (config.services :: unknown) :: { TweenService: Tweens? }
		local service = tweens.TweenService
		if service and not (options and options.animated == false) and not reduced() then
			local playback = service:Create(
				frame,
				types.TweenInfo.new(0.25, E.EasingStyle.Quad, E.EasingDirection.Out),
				{ CanvasPosition = goal }
			)
			running[frame] = playback
			playback:Play()
		else
			frame.CanvasPosition = goal
		end
		return true
	end

	UI.scrollTo = function(frame: ScrollingFrame, position: Env.ScrollPosition, options: Env.ScrollOptions?): boolean
		assert(
			type(frame) ~= "string" and (frame :: unknown) ~= nil and frame:IsA("ScrollingFrame"),
			"Facet UI.scrollTo expects a ScrollingFrame"
		)
		local current = frame.CanvasPosition
		local target: Vector2
		if position == "top" then
			target = V2.new(current.X, 0)
		elseif position == "bottom" then
			target = V2.new(current.X, limit(frame).Y)
		elseif typeof(position) == "Vector2" then
			target = position :: Vector2
		else
			assert(type(position) == "table", "Facet UI.scrollTo expects top, bottom, a Vector2 or { x, y }")
			local point = position :: { x: number?, y: number? }
			target = V2.new(point.x or current.X, point.y or current.Y)
		end
		return move(frame, target, options)
	end

	local function keep(start: number, size: number, band: number): number
		if start < 0 or size > band then
			return start
		elseif start + size > band then
			return start + size - band
		end
		return 0
	end

	UI.scrollToVisible = function(node: GuiObject, rect: Env.ScrollRect?, options: Env.ScrollOptions?): boolean
		assert(
			type(node) ~= "string" and (node :: unknown) ~= nil and node:IsA("GuiObject"),
			"Facet UI.scrollToVisible expects a GuiObject"
		)
		local origin, extent = node.AbsolutePosition, node.AbsoluteSize
		local left, top, width, height = origin.X, origin.Y, extent.X, extent.Y
		if rect then
			left, top, width, height = left + rect.x, top + rect.y, rect.w, rect.h
		end
		local shiftX, shiftY = 0, 0
		local moved = false
		local host = node.Parent
		while host do
			if host:IsA("ScrollingFrame") then
				local frame = host :: ScrollingFrame
				local view, window, canvas = frame.AbsolutePosition, frame.AbsoluteWindowSize, frame.CanvasPosition
				local direction = frame.ScrollingDirection
				local dx = if direction == E.ScrollingDirection.Y
					then 0
					else keep(left - shiftX - view.X, width, window.X)
				local dy = if direction == E.ScrollingDirection.X
					then 0
					else keep(top - shiftY - view.Y, height, window.Y)
				if dx ~= 0 or dy ~= 0 then
					local most = limit(frame)
					local goal = V2.new(math.clamp(canvas.X + dx, 0, most.X), math.clamp(canvas.Y + dy, 0, most.Y))
					if move(frame, goal, options) then
						moved = true
						shiftX += goal.X - canvas.X
						shiftY += goal.Y - canvas.Y
					end
				end
			end
			host = host.Parent
		end
		return moved
	end
end
