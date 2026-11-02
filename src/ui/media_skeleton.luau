--!strict
local reducedMotion = require("./motion").reduced
local Types = require("./types")
local Engine = require("./engine_types")
local ComposeTypes = require("../vendor/compose/core")
local ControlTypes = require("./control_types")
local MediaProps = require("./media_props")

return function(ctx: Types.Context, UI: ControlTypes.Controls)
	local Host, runtime, Compose = ctx.Host, ctx.runtime, ctx.Compose
	local types, read = ctx.types, ctx.read
	local E, D2, D, V2 = types.Enum, types.UDim2, types.UDim, types.Vector2
	local metric, controlSize = ctx.metric, ctx.controlSize
	local skeletonClock = Compose.createSharedResource(function(): (Types.Playback, (() -> ())?)
		local clock = runtime.timeline({ duration = ctx.metric("motion.durations.spinnerLoop"), repeats = math.huge })
		local motionReduced = reducedMotion(ctx)
		Compose.watch(function(use: ComposeTypes.Use)
			if motionReduced(use) then
				clock:pause()
			else
				clock:play()
			end
		end)
		return clock, nil
	end)
	UI.Skeleton = ctx.construct("Skeleton", function(spec: MediaProps.SkeletonProps): Frame
		local form = spec.form or "box"
		assert(form == "box" or form == "circle" or form == "line", "Facet Skeleton invalid form")
		assert(spec.lines == nil or form == "line", "Facet Skeleton lines require line form")
		assert(spec.corners == nil or form ~= "circle", "Facet Skeleton circle owns its corners")
		local count = spec.lines or 1
		assert(count >= 1 and count % 1 == 0, "Facet Skeleton lines must be positive")
		local clock = skeletonClock()
		local motionReduced = reducedMotion(ctx)
		local rows: { ComposeTypes.Child } = {}
		for index = 1, count do
			local native: Engine.FrameProps = {
				Name = "Placeholder" .. index,
				Size = function(use: ComposeTypes.Use)
					local pixels = controlSize(spec.controlSize, if form == "line" then "iconSize" else "height", use)
					return if form == "circle"
						then D2.fromOffset(pixels, pixels)
						else D2.new(if count > 1 and index == count then 0.6 else 1, 0, 0, pixels)
				end,
				Host.UIGradient "Shimmer" {
					Enabled = function(use: ComposeTypes.Use)
						return not motionReduced(use)
					end,
					Offset = function(use: ComposeTypes.Use)
						return V2.new(use(clock.progress) * 2 - 1, 0)
					end,
					Transparency = types.NumberSequence.new({
						types.NumberSequenceKeypoint.new(0, 0.4),
						types.NumberSequenceKeypoint.new(0.5, 0),
						types.NumberSequenceKeypoint.new(1, 0.4),
					}),
				},
			}
			if form == "circle" then
				native[#native + 1] = Host.UICorner { CornerRadius = ctx.round }
			elseif spec.corners then
				native[#native + 1] = Host.UICorner {
					CornerRadius = function(use: ComposeTypes.Use)
						local value = read(spec.corners, use)
						if value == "pill" then
							return D.new(1, 0)
						end
						if value == "square" then
							return D.new(0, 0)
						end
						if value == "rounded" or value == "control" then
							return D.new(0, metric("radii.control", use))
						end
						if value == "panel" then
							return D.new(0, metric("radii.panel", use))
						end
						assert(type(value) == "number" and value >= 0, "Facet Skeleton invalid corners")
						return D.new(0, value)
					end,
				}
			end
			table.insert(rows, ctx.styled(Host.Frame(native), "skeleton"))
		end
		return ctx.column(
			rows,
			ctx.props(
				spec,
				{ "form", "lines", "controlSize", "corners" },
				{ Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y }
			)
		)
	end)
end
