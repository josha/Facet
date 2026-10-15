--!strict

local Json = require("../lib/json")

local COUNTS = { "instances", "connections", "holdings" }

local function count(row: unknown, name: string): number?
	local value = Json.numberField(row, name)
	return if value and value >= 0 and value < math.huge and value % 1 == 0 then value else nil
end

local function check(report: unknown, limits: unknown): { string }
	local rows = Json.arrayField(report, "samples")
	local expected = Json.asObject(limits)
	if Json.field(report, "schema") ~= "facet-perf-footprint/1" or rows == nil or expected == nil then
		return { "footprint: missing control samples or resource limits" }
	end
	local errors: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, row in rows do
		local name = Json.stringField(row, "name") or "unknown"
		local limit = Json.field(expected, name)
		if limit == nil or seen[name] then
			table.insert(errors, `footprint: unknown or duplicate control {name}`)
		end
		seen[name] = true
		for _, metric in COUNTS do
			local idle = count(Json.field(row, "idle"), metric)
			local active = count(Json.field(row, "active"), metric)
			local ceiling = count(limit, metric)
			if idle == nil or active == nil or ceiling == nil or idle > ceiling then
				table.insert(errors, `footprint: {name} {metric}: idle {tostring(idle)}, ceiling {tostring(ceiling)}`)
			end
			if count(Json.field(row, "teardown"), metric) ~= 0 then
				table.insert(errors, `footprint: {name} retains {metric} after teardown`)
			end
		end
	end
	for name in expected do
		if not seen[name] then
			table.insert(errors, `footprint: missing control {tostring(name)}`)
		end
	end
	return errors
end

return { check = check }
