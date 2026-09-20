--!strict
--[[ The showcase's demo mount path: build a catalogue demo against the host's
	context, present it, and tie its lifetime to the presented screen.

	Every demo has one build contract. `module.build(ctx)` answers a component
	function, or a table whose `screen` is one, plus optional `present` options,
	`dispose`, and a `handle` when the demo presented itself. State is Compose
	cells and formulas; whatever a demo creates while its screen mounts belongs to
	that mount's owner and is released with it.

	It is a module, and not a local in `init.client.luau`, because it is the one
	piece of the showcase's mount path a headless spec can drive.
	`tests/gallery_demo_host.spec.luau` requires this module, so it exercises the
	path a player gets. `init.client.luau` holds the rest of mounting a demo:
	Instances, replicated folders and a live adapter. ]]

local demo_host = {}

--[[ `mount(ctx, module)` builds the demo and presents its screen through
	`ctx.app`, unless the demo presented itself. `built.dispose` then closes the
	screen. The demo's own `dispose` runs once, after the presented tree has
	unmounted, so a control that is still leaving never reads a released resource. ]]
function demo_host.mount(ctx: any, module: any): any
	local Compose = ctx.Compose
	local built = module.build(ctx)
	if type(built) == "function" then
		built = { screen = built }
	end
	local ownDispose = built.dispose
	local released = false
	local function release()
		if released then
			return
		end
		released = true
		if ownDispose then
			pcall(ownDispose)
		end
	end
	local close: (() -> ())? = nil
	if built.handle == nil and built.screen ~= nil then
		local screen = built.screen
		local mountedClose, node, handle = ctx.app.mount(function()
			-- registered first, so it runs after everything the screen built
			Compose.cleanup(release)
			return screen()
		end, built.present)
		close, built.node, built.handle = mountedClose, node, handle
	end
	built.dispose = function()
		if close ~= nil then
			close()
		else
			release()
		end
	end
	return built
end

return demo_host
