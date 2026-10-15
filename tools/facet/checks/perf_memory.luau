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

local function measured(report: unknown): { unknown }
	local rows: { unknown } = {}
	local runs: Json.Array = Json.arrayField(report, "runs") or {}
	for _, row in runs do
		if Json.field(row, "evidenceClass") == "lute" then
			table.insert(rows, row)
		end
	end
	return rows
end

local function place(row: unknown): string
	return `{tostring(Json.field(row, "scene"))}@{tostring(Json.field(row, "device"))}`
end

function Memory.check(report: unknown): { string }
	local errors: { string } = {}
	local runs = Json.asArray(Json.field(report, "runs"))
	if runs == nil or #runs == 0 then
		return { "memory: no scene rows" }
	end
	local rows = measured(report)
	for _, row in rows do
		local where = place(row)
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
			for index, entry in iterations do
				if count(entry, name) == nil then
					table.insert(errors, `{where}: iteration {index} has no exact {name} count`)
					break
				end
			end
		end
	end
	if #rows == 0 then
		table.insert(errors, "memory: no headless resource measurements")
	end
	return errors
end

function Memory.growth(report: unknown): { string }
	local trends: { string } = {}
	for _, row in measured(report) do
		local resources = Json.field(row, "resources")
		if Json.field(resources, "churn") ~= true then
			continue
		end
		for _, name in COUNTS do
			local previous = count(Json.field(resources, "start"), name)
			local iterations: Json.Array = Json.arrayField(resources, "iterations") or {}
			for index, entry in iterations do
				local current = count(entry, name)
				if current == nil then
					break
				elseif previous ~= nil and current > previous then
					table.insert(trends, `{place(row)}: iteration {index} grows {name} from {previous} to {current}`)
					break
				end
				previous = current
			end
		end
	end
	return trends
end

return table.freeze(Memory)
