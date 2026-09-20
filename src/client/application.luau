--!strict
-- Client bootstrap for Compose-authored Facet surfaces. The runtime is Compose's
-- actual runtime; this module connects its domain nodes to Facet's UI services.
local host = require("./host")
local scene = require("../render/compose_scene")
local controls = require("../render/compose_controls")
local application = {}

function application.new(opts: host.Opts?)
	-- The presenter exists before the UI runtime does, so the seam it mounts its
	-- own surfaces through is bound once the runtime is up.
	local mountComponent
	local hostOpts = table.clone(opts or {}) :: any
	hostOpts.mountComponent = function(component)
		return mountComponent(component)
	end
	local surface = host.new(hostOpts)
	local domain =
		scene.new({ onFrame = surface.presenter.onTick, now = if opts and opts.now then opts.now else os.clock })
	local runtime = surface.core.adopt(domain.runtime)
	local mounted = {}
	local disposed = false
	local installedTheme
	local surfaces = {}
	local providers = {}
	local constructors, domainUI = controls.new(runtime, surface.core, surface.presenter, surfaces)
	local app = {
		controls = constructors,
		runtime = runtime,
		environment = surface.env,
		presenter = surface.presenter,
		onFrame = surface.presenter.onTick,
	}
	function mountComponent(component)
		assert(not disposed, "Facet: cannot mount into a disposed application")
		local target = domain.target()
		local stop = runtime.mount(function()
			return component(domainUI)
		end, target)
		return domain.root(target, stop)
	end
	local function present(component, options, presentSurface)
		assert(not disposed, "Facet: cannot mount into a disposed application")
		local target = domain.target()
		local stop, node = runtime.mount(component, target)
		local closed, handle = false, nil
		local close
		local function release()
			if closed then
				return
			end
			closed = true
			mounted[close] = nil
			stop()
		end
		close = function()
			if closed then
				return
			end
			if handle then
				surface.presenter.dismiss(handle)
			else
				release()
			end
		end
		local ok, result = pcall(function()
			return presentSurface(domain.root(target, release), options)
		end)
		if not ok then
			release()
			error(result, 0)
		end
		handle = result
		if not closed then
			mounted[close] = true
		end
		return close, node, handle
	end
	function app.mount(component, options)
		return present(component, options, surface.presenter.present)
	end
	function app.presentModal(component, options)
		return present(component, options, surface.presenter.presentModal)
	end
	local function presentAnchored(component, options)
		local close, node, anchoredHandle
		-- The presenter builds the surface with the internal vocabulary and calls
		-- the panel builder with the same one. An app-facing builder sees
		-- `app.controls` instead — the spelling `app.mount` closes over.
		local panel = if type(component) == "function"
			then function()
				return component(constructors)
			end
			else component
		anchoredHandle = surface.presenter.presentAnchored(
			panel,
			options,
			function(build, presentOptions, presentSurface)
				local handle
				close, node, handle = present(function()
					return build(domainUI)
				end, presentOptions, presentSurface)
				return handle
			end
		)
		return close, node, anchoredHandle
	end
	function app.presentAnchored(component, options)
		local close, node = presentAnchored(component, options)
		return close, node
	end
	-- A toast owns its body: the component runs inside the toast's own row.
	function app.presentToast(component, options)
		return surface.presenter.presentToast(component, options)
	end
	function surfaces.modal(component, options)
		local _, _, handle = present(component, options, surface.presenter.presentModal)
		return handle
	end
	function surfaces.anchored(component, options)
		local _, _, handle = presentAnchored(component, options)
		return handle
	end
	function surfaces.callout(spec)
		return surface.presenter.presentCallout(spec, surfaces.anchored)
	end
	-- A provider for `AsyncImage` and other leased content. `options.bind` replaces
	-- the Roblox transport (a headless caller completes requests itself).
	function app.newResourceProvider(options)
		assert(not disposed, "Facet: cannot create a provider for a disposed application")
		local config = table.clone(options or {})
		local bind = config.bind
		config.bind = nil
		local provider = require("../async/resources").newProvider(surface.core, config)
		local unbind = if bind == nil
			then require("./roblox_resources").bind(provider)
			elseif bind then bind(provider)
			else nil
		local released = false
		local function release()
			if released then
				return
			end
			released = true
			providers[release] = nil
			if unbind then
				unbind()
			end
			provider.dispose()
		end
		providers[release] = true
		return provider, release
	end
	function app.installTheme(package, options)
		assert(not disposed, "Facet: cannot install a theme into a disposed application")
		assert(installedTheme == nil, "Facet: use the installed theme controller to swap themes or packages")
		local config = table.clone(options or {})
		assert(config.env == nil and config.core == nil, "Facet: the application owns the theme environment")
		config.env, config.core = surface.env, surface.core
		installedTheme = require("./theme_controller").install(surface.adapter, package, config)
		return installedTheme
	end
	function app.dispose()
		if disposed then
			return
		end
		disposed = true
		for close in mounted do
			close()
		end
		for release in table.clone(providers) do
			release()
		end
		if installedTheme then
			installedTheme.uninstall()
		end
		runtime:dispose()
		surface.dispose()
	end
	return app
end
return application
