--!strict
local Shared = require("./types")
local Types = require("./effect_types")
local Nav = require("./navigation_types")
local reducedMotion = require("./motion").reduced
return function(ctx: Shared.Context, UI: Types.Controls, surfaces: Nav.Surfaces)
	local C, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	UI.Flash = ctx.construct("Flash", function(spec: Types.FlashProps): Frame
		local reduce = reducedMotion(ctx)
		local anchor = Host.Frame(
			ctx.props(
				spec,
				{ "target", "progress", "color", "mode" },
				{ Size = ctx.types.UDim2.fromOffset(0, 0), BackgroundTransparency = 1 }
			)
		)
		local portal = surfaces.overlay(anchor, true, function(): Instance
			local parent = assert(surfaces.parent(anchor))
			local unit = ctx.layoutUnit(parent)
			local node = ctx.styled(
				Host.Frame {
					Name = "FlashPaint",
					BorderSizePixel = 0,
					ZIndex = 1000,
					Active = false,
					Interactable = false,
					Selectable = false,
				},
				"facet-flash"
			)
			C.watch(function(use: Shared.Use)
				local target: GuiObject = ctx.read(spec.target, use)
				assert(target:IsA("GuiObject"), "Facet Flash requires a GuiObject target")
				ctx.read(ctx.observe.AbsolutePosition(target), use)
				ctx.read(ctx.observe.AbsoluteSize(target), use)
				local point, size = target.AbsolutePosition, target.AbsoluteSize
				local progress = math.clamp(ctx.read(spec.progress, use), 0, 1)
				local scale = math.max(use(unit), 0.001)
				node.Visible = not reduce(use)
					and target.Parent ~= nil
					and target.Visible
					and progress > 0
					and progress < 1
				node.Position = ctx.types.UDim2.fromOffset(
					(point.X - parent.AbsolutePosition.X) / scale,
					(point.Y - parent.AbsolutePosition.Y) / scale
				)
				node.Size = ctx.types.UDim2.fromOffset(
					size.X / scale * (if spec.mode == "sweep" then progress else 1),
					size.Y / scale
				)
				if spec.color then
					node.BackgroundColor3 = ctx.read(spec.color, use)
				end
				node.BackgroundTransparency = 1 - 4 * progress * (1 - progress)
			end)
			return node
		end)
		runtime.mountFragment(function()
			return { portal }
		end, anchor)
		return anchor
	end)
end
