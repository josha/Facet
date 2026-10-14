--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local surfaceKit = require("./nav_surface_kit")
local overlayPresence = require("./nav_overlay_presence")
local popoverPlacement = require("./nav_popover_placement")
local modalStack = require("./nav_modal_stack")
local overlayPortal = require("./nav_overlay_portal")
local navHelp = require("./nav_help")

return function(ctx: Types.Context): Nav.Surfaces
	local Compose, runtime = ctx.Compose, ctx.runtime
	local function attach<N>(node: N & Instance, children: { Types.Child }): N & Instance
		local stop = runtime.mountFragment(function()
			return children
		end, node)
		Compose.cleanup(stop)
		return node
	end
	local kit = surfaceKit(ctx, attach)
	local presence = overlayPresence(ctx)
	local popover = popoverPlacement(ctx)
	local modal = modalStack(ctx, kit)
	local portal = overlayPortal(ctx, presence)
	navHelp(ctx, kit, presence, portal, popover)
	return {
		modal = modal,
		skin = kit.skin,
		inset = kit.inset,
		centered = kit.centered,
		attach = attach,
		service = kit.service,
		within = kit.within,
		keep = kit.keep,
		firstSelectable = kit.firstSelectable,
		preference = kit.preference,
		selecting = kit.selecting,
		overlay = portal.overlay,
		parent = portal.parent,
		available = portal.available,
		appearance = presence.appearance,
		atRest = presence.atRest,
		popover = popover,
		sheetModal = nil,
	}
end
