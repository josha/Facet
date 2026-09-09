--!strict
-- The existing semantic action pipeline owns analog delivery and arbitration.
-- Kept in input (not in a control or a screen) so the binding policy has one home.
local radialInput = {}
function radialInput.bind(
	core: any,
	scope: any,
	system: any,
	active: any,
	available: () -> boolean,
	direction: (number, number) -> ()
)
	local ctx = system.createContext({ name = "RadialNavigation", priority = 1200, sink = true })
	ctx.setEnabled(false)
	local action = ctx.createAction("Navigate", "Direction2D")
	action.bindAxis({ axis = "Thumbstick1" })
	scope:own(core:observe(action.state, function(value)
		if available() and type(value) == "table" then
			direction(value.x or 0, value.y or 0)
		end
	end))
	-- Availability changes with the presenter's responder and the menu signal.
	scope:own(core:effect(function(use)
		ctx.setEnabled(use(active) and available())
	end))
	scope:own(function()
		ctx.destroy()
	end)
	return function()
		if not ctx.destroyed then
			ctx.setEnabled(available())
		end
	end
end
return radialInput
