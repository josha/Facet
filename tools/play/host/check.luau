--!strict

local task = require("@std/task")

local Core = require("../../../tools/vendor/verify/src/core")
local QA = require("./qa")

local function that(context: Core.Context, condition: boolean, detail: string)
	context:expect(condition):toBeTrueWith(detail)
end

local function tap(qa: QA.QA, context: Core.Context, query: QA.Query, what: string)
	local wide = table.clone(query)
	wide.clipped = true
	qa:waitFor(wide, 4)
	local ok, detail = qa:tap(query)
	that(context, ok, ("%s: %s"):format(what, detail))
end

local function visible(qa: QA.QA, context: Core.Context, query: QA.Query, what: string, seconds: number?): QA.Info
	local found = qa:waitFor(query, seconds)
	that(context, found ~= nil, ("%s: nothing visible matches %s"):format(what, QA.describe(query)))
	return found :: QA.Info
end

local function text(qa: QA.QA, context: Core.Context, pattern: string, what: string, seconds: number?): string
	local found = qa:waitText(pattern, seconds)
	that(context, found ~= nil, ("%s: no visible text matches the pattern %q"):format(what, pattern))
	return found :: string
end

local function absent(qa: QA.QA, context: Core.Context, pattern: string, what: string, seconds: number?)
	local deadline = os.clock() + (seconds or 3)
	local found = qa:hasText(pattern)
	while found ~= nil and os.clock() < deadline do
		task.wait(0.25)
		found = qa:hasText(pattern)
	end
	that(context, found == nil, ("%s: the text %q is still visible"):format(what, tostring(found)))
end

local function gone(qa: QA.QA, context: Core.Context, query: QA.Query, what: string, seconds: number?)
	that(context, qa:waitGone(query, seconds), ("%s: %s is still visible"):format(what, QA.describe(query)))
end

local function eventually(seconds: number, probe: () -> boolean): boolean
	local deadline = os.clock() + seconds
	repeat
		if probe() then
			return true
		end
		task.wait(0.25)
	until os.clock() >= deadline
	return false
end

local function closer(qa: QA.QA, wanted: QA.Query, other: QA.Query): boolean
	local hit = qa:first(wanted)
	if hit == nil then
		return false
	end
	local rival = qa:first(other)
	if rival == nil then
		return true
	end
	return (hit.score or math.huge) < (rival.score or math.huge)
end

local function field(value: unknown, ...: string): unknown
	local cursor = value
	for _, key in { ... } do
		if type(cursor) ~= "table" then
			return nil
		end
		cursor = (cursor :: { [string]: unknown })[key]
	end
	return cursor
end

local function number(value: unknown, ...: string): number
	return tonumber(field(value, ...)) or -1
end

local function count(pattern: string): string
	return "%f[%d]" .. pattern .. "%f[%D]"
end

return {
	that = that,
	tap = tap,
	visible = visible,
	text = text,
	absent = absent,
	gone = gone,
	eventually = eventually,
	closer = closer,
	field = field,
	number = number,
	count = count,
}
