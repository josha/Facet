--!strict
--[[ The context a gallery scenario builds against, for headless specs.

	`scenario.build(ctx)` reads `{ Facet, app, UI, Compose, env, core, presenter,
	adapter, actionSystem, controlRecord, ... }` and answers a table whose `screen`
	is a component function. `of(w)` fills that context from a `tests/lib/world`
	world; `ofHarness(w)` fills it from a service-level world
	(`{ core, env, adapter, presenter | pres, system }`).

	Require this module before the world is created: it records what each
	composite control builds, so `ctx.controlRecord(id)` answers the newest
	`{ blueprint, api, dump }` record built under that id for the world's core. ]]

local Facet = require("../../src") :: any
local harness = require("./harness")

local CONTROL_MODULES = {
	"alert",
	"async_image",
	"button",
	"callout",
	"chip",
	"collapsible_view",
	"combo_box",
	"disclosure_group",
	"label",
	"shortcut_hint",
	"skeleton",
	"avatar",
	"level_picker",
	"menu",
	"navigation_stack",
	"page_view",
	"picker",
	"progress_view",
	"radial_menu",
	"rating",
	"row_actions",
	"sheet",
	"slider",
	"split_button",
	"stepper",
	"tab_view",
	"table",
	"text_input",
	"toggle",
}

local records: { [any]: { [string]: any } } = {}
-- A control record can refer back to its core, so weak keys cannot release it.
-- Inspection belongs to this case, even when a failed case skips its cleanup.
require("./testkit").afterEach(function()
	table.clear(records)
end)
for _, name in CONTROL_MODULES do
	local module = require("../../src/controls/" .. name) :: any
	local original = module.build
	module.build = function(library: any, core: any, spec: any, ...)
		local result = original(library, core, spec, ...)
		local id = if type(spec) == "table" then spec.id else nil
		if core ~= nil and type(id) == "string" and type(result) == "table" then
			local byId = records[core]
			if byId == nil then
				byId = {}
				records[core] = byId
			end
			byId[id] = result
		end
		return result
	end
end

local scenario_ctx = {}

local function base(w: any, app: any, UI: any, presenter: any, extra: { [string]: any }?): any
	local ctx: { [string]: any } = {
		Facet = Facet,
		app = app,
		UI = UI,
		Compose = Facet.Compose,
		core = w.core,
		env = w.env,
		adapter = w.adapter,
		presenter = presenter,
		actionSystem = w.system,
		record = function() end,
		flags = {},
		controlRecord = function(id: string): any
			return records[w.core] and records[w.core][id]
		end,
		geometry = function(paths: { string }): { [string]: any }
			local out: { [string]: any } = {}
			for _, path in paths do
				local node = w.adapter.node(path)
				if node ~= nil and node.rect ~= nil then
					out[path] = node.rect
				end
			end
			return out
		end,
		bindResourceTransport = function()
			return function() end
		end,
	}
	for key, value in extra or {} do
		ctx[key] = value
	end
	return ctx
end

-- A `tests/lib/world` world.
function scenario_ctx.of(w: any, extra: { [string]: any }?): any
	return base(w, w.app, w.UI, w.pres, extra)
end

-- A service-level world. `app` carries the application entry points a scenario
-- calls, over the harness presenter.
function scenario_ctx.ofHarness(w: any, extra: { [string]: any }?): any
	local presenter = w.presenter or w.pres
	local UI, _, library = harness.libraryOf(w.core)
	local function presentWith(method: string)
		return function(component: any, options: any?)
			local handle = presenter[method](component, options)
			return function()
				presenter.dismiss(handle)
			end, nil, handle
		end
	end
	local app = {
		controls = UI,
		runtime = library.runtime,
		environment = w.env,
		presenter = presenter,
		onFrame = presenter.onTick,
		mount = presentWith("present"),
		presentModal = presentWith("presentModal"),
		presentAnchored = presentWith("presentAnchored"),
	}
	return base(w, app, UI, presenter, extra)
end

-- Presents what `build` answered and records the handle on it, as the gallery
-- hosts do. `present` is `w.present` (world) or `presenter.present` (harness).
function scenario_ctx.present(built: any, present: (any, any?) -> any): any
	if type(built) == "function" then
		built = { screen = built }
	end
	if built.handle == nil and built.screen ~= nil then
		built.handle = present(built.screen, built.present)
	end
	return built
end

return scenario_ctx
