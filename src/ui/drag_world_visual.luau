--!strict
local Types = require("./types")
local Env = require("./environment_types")
local Drag = require("./drag_types")
local motion = require("./motion")
local travel = require("./drag_travel")
local planePoint = require("./drag_plane")

return function(
	ctx: Types.Context,
	source: BasePart | Model,
	options: Env.WorldDragOptions,
	position: Vector2?
): Drag.WorldPresentation
	local original = source:GetPivot()
	local base = original
	local offset: Vector3? = nil
	local settling = false
	local stopMotion: (() -> ())? = nil
	local function intersect(at: Vector2): Vector3?
		local workspace = ctx.config.services.Workspace
		local camera = workspace and workspace.CurrentCamera
		if not camera then
			return nil
		end
		local ray = camera:ScreenPointToRay(at.X, at.Y)
		return planePoint(ray.Origin, ray.Direction, options.plane)
	end
	if position then
		local point = intersect(position)
		if point then
			offset = original.Position - point
		end
	end
	local lift: Types.ReadOnlyValue<number>? = nil
	local reduced: ((Types.Use?) -> boolean)? = nil
	local function paint()
		if not settling and source.Parent then
			local amount = if reduced and reduced(nil) then 0 else if lift then lift:peek() else 0
			source:PivotTo(base + options.plane.UpVector * amount)
		end
	end
	local stopLift = ctx.runtime.mount(function()
		reduced = motion.reduced(ctx)
		local raised = ctx.Compose.cell(false)
		lift = ctx.runtime.tween(function(use)
			return if use(raised) then options.lift or 0 else 0
		end, {
			seconds = function(use)
				return ctx.metric("motion.durations.pressLift", use)
			end,
			ease = ctx.motionEase("present"),
			reducedMotion = reduced,
		})
		ctx.Compose.watch(function(use)
			use(assert(lift))
			assert(reduced)(use)
			paint()
		end)
		raised:set(true)
		return ctx.Host.Folder { Name = "FacetWorldDragLift" }
	end, source)
	local function stop()
		settling = true
		stopLift()
		if stopMotion then
			stopMotion()
			stopMotion = nil
		end
	end
	local function animate(goal: CFrame, complete: () -> ())
		stop()
		if reduced and reduced(nil) then
			if source.Parent then
				source:PivotTo(goal)
			end
			complete()
			return
		end
		local from = source:GetPivot()
		local finished = false
		local cancel = travel(ctx, source, function(progress)
			if source.Parent then
				source:PivotTo(from:Lerp(goal, progress))
			end
		end, function()
			finished = true
			if stopMotion then
				local dispose = stopMotion
				stopMotion = nil
				dispose()
			end
			complete()
		end)
		if finished then
			cancel()
		else
			stopMotion = cancel
		end
	end
	return {
		move = function(at, snap)
			if settling then
				return
			end
			if snap then
				base = snap
			elseif at then
				local point = intersect(at)
				if point then
					base = original.Rotation + point + (offset or ctx.types.Vector3.zero)
				end
			else
				base = original
			end
			paint()
		end,
		land = function(complete)
			animate(base, complete)
		end,
		release = function(accepted, complete)
			if accepted then
				stop()
				complete()
			else
				animate(original, complete)
			end
			return function()
				stop()
				if not accepted and source.Parent then
					source:PivotTo(original)
				end
				complete()
			end
		end,
	}
end
