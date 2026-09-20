--!strict
-- The application's surface verbs over a harness presenter, for a gallery
-- scenario that raises surfaces of its own. Each verb answers what `Facet.new`'s
-- does: `close, node, handle`.
local harness = require("./harness")

local scenario_app = {}

function scenario_app.over(core: any, presenter: any): any
	local function surface(method: string)
		return function(component: any, options: any?)
			local handle = presenter[method](component, options)
			return function()
				presenter.dismiss(handle)
			end, nil, handle
		end
	end
	local controls, _, library = harness.libraryOf(core)
	local app = {
		controls = controls,
		runtime = library.runtime,
		presenter = presenter,
		onFrame = presenter.onTick,
		mount = surface("present"),
		presentModal = surface("presentModal"),
	}
	function app.presentAnchored(component: any, options: any?)
		local handle = presenter.presentAnchored(component, options, function(build, presentOptions, presentSurface)
			local _, internalUI = harness.libraryOf(core)
			return presentSurface(
				harness.mount(core, function()
					return build(internalUI)
				end),
				presentOptions
			)
		end)
		return function()
			presenter.dismiss(handle)
		end, nil, handle
	end
	return app
end

-- The three fields a scenario authors against, for a ctx built over a harness world.
function scenario_app.fields(core: any, presenter: any): (any, any, any)
	local Facet = require("../../src") :: any
	return scenario_app.over(core, presenter), (harness.libraryOf(core)), Facet.Compose
end

return scenario_app
