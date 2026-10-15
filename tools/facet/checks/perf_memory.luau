--!strict

local Json = require("../lib/json")

local Memory = {}
local COUNTS = { "instances", "connections", "registrations" }

local function count(value: unknown, name: string): number?
	local found = Json.field(value, name)
	if type(found) == "number" and found >= 0 and found < math.huge and found % 1 == 0 then
		return found
	end
	return nil
end

function Memory.check(report: unknown): { string }
	local errors: { string } = {}
	local runs = Json.asArray(Json.field(report, "runs"))
	if runs == nil or #runs == 0 then
		return { "memory: no scene rows" }
	end
	local measured = 0
	for _, row in runs do
		if Json.field(row, "evidenceClass") ~= "lute" then
			continue
		end
		measured += 1
		local where = `{tostring(Json.field(row, "scene"))}@{tostring(Json.field(row, "device"))}`
		local resources = Json.field(row, "resources")
		local iterations = Json.asArray(Json.field(resources, "iterations"))
		if iterations == nil or #iterations == 0 or #iterations ~= Json.field(row, "samples") then
			table.insert(errors, `{where}: memory needs an exact census for every measured iteration`)
			continue
		end
		if type(Json.field(resources, "churn")) ~= "boolean" then
			table.insert(errors, `{where}: memory needs a churn declaration`)
		end
		for _, name in COUNTS do
			local start = count(Json.field(resources, "start"), name)
			local final = count(Json.field(resources, "teardown"), name)
			if start == nil or final == nil then
				table.insert(errors, `{where}: memory needs exact {name} counts`)
			elseif final ~= 0 then
				table.insert(errors, `{where}: teardown retains {final} {name}; expected zero`)
			end
			local previous = start
			for index, entry in iterations do
				local current = count(entry, name)
				if current == nil then
					table.insert(errors, `{where}: iteration {index} has no exact {name} count`)
					break
				elseif previous ~= nil and Json.field(resources, "churn") == true and current > previous then
					table.insert(errors, `{where}: iteration {index} grows {name} from {previous} to {current}`)
					break
				end
				previous = current
			end
		end
	end
	if measured == 0 then
		table.insert(errors, "memory: no headless resource measurements")
	end
	return errors
end

return table.freeze(Memory)
