--!strict

local Actions = require("./actions")
local Check = require("./check")
local Play = require("./play")

local function case(name: string, screen: string?, run: Play.CaseBody): Play.Case
	local navigation: Actions.Navigation? = nil
	return {
		id = "universal/" .. name,
		tier = "universal",
		screen = screen,
		run = function(qa, context)
			if navigation == nil and name ~= "hub" then
				navigation = Actions.captureRoot(qa)
			end
			local ok, problem = pcall(function(): boolean
				run(qa, context)
				return true
			end)
			if not ok then
				if navigation ~= nil then
					context:defer(function()
						local recovered, detail = Actions.returnToRoot(qa, navigation)
						Check.that(context, recovered, "cleanup after " .. name .. ": " .. detail)
						local returned, returnDetail =
							Actions.returned(qa, { role = "button", text = "shop" }, false, navigation)
						Check.that(context, returned, "cleanup restores the hub: " .. returnDetail)
					end)
				end
				error(problem, 0)
			end
		end,
	}
end

return { case = case }
