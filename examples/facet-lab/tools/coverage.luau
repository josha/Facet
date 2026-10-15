--!strict
local fs = require("@std/fs")
local process = require("@std/process")
local Lute = require("../../../tools/vendor/verify/src/lute")
local roblox = require("../../../tools/vendor/verify/src/roblox").datatypes

local FACET = "../../src/ui/"

type Props = { [unknown]: unknown }
type Source = Props | (unknown) -> Props
type Axis = { key: string, values: { unknown }, props: Source?, implies: { [unknown]: Source }?, matrix: boolean? }
type State = { name: string, props: Source? }
type PageData = {
	family: string,
	alias: string?,
	base: Source?,
	axes: { Axis }?,
	states: { State }?,
	demonstrates: { string }?,
	matrix: boolean?,
	recipe: unknown,
	facet: unknown,
	scenarios: { string }?,
}

local function list<T>(items: { T }?): { T }
	return items or {}
end
local function map<K, V>(items: { [K]: V }?): { [K]: V }
	return items or {}
end

local env: { [string]: unknown } = {}
for key, value in pairs(roblox) do
	env[key] = value
end
env.require = function(path: string): unknown
	local name = assert(string.match(path, "^%./([%w_]+)$"))
	return Lute.chunk.load(fs.readFileToString(`src/{name}.luau`), { name = name, environment = env })()
end
local catalog =
	Lute.chunk.load(fs.readFileToString("src/catalog.luau"), { name = "catalog", environment = env })() :: any

local bodies: { [string]: string } = {}
for _, entry in fs.listDirectory(FACET) do
	local name = entry.name
	if string.match(name, "_types%.luau$") and name ~= "engine_types.luau" then
		local source = fs.readFileToString(FACET .. name) .. "\nexport type __END = nil\n"
		for start, typeName in string.gmatch(source, "()export type ([%w_]+)") do
			local rest = string.sub(source, assert(tonumber(start)))

			local body = string.match(rest, "^export type [%w_]+[^\n]*=(.-)\nexport type ")
				or string.match(rest, "^export type [%w_]+[^\n]*=(.-)\nreturn")
			if body then
				bodies[assert(typeName)] = body
			end
		end
	end
end

local function scan(body: string): ({ string }, { string })
	local fields, refs = {}, {}
	local depth = 0
	local i = 1
	while i <= #body do
		local ch = string.sub(body, i, i)
		if ch == "{" or ch == "(" or ch == "<" then
			depth += 1
		elseif ch == "}" or ch == ")" or ch == ">" then
			depth -= 1
		elseif ch == "-" and string.sub(body, i + 1, i + 1) == ">" then
			i += 1
		elseif depth == 1 and string.match(ch, "[%a_]") and string.match(string.sub(body, 1, i - 1), "[{,\n]%s*$") then
			local field = string.match(body, "^([%a_][%w_]*)%??%s*:", i)
			if field then
				table.insert(fields, field)
			end
		elseif
			depth == 0
			and string.match(ch, "[%a_]")
			and not string.match(string.sub(body, i - 1, i - 1), "[%w_%.]")
		then
			local ident = assert(string.match(body, "^[%a_][%w_%.]*", i))
			table.insert(refs, assert(string.match(ident, "([%w_]+)$")))
			i += #ident - 1
		end
		i += 1
	end
	return fields, refs
end

local function optionsOf(typeName: string, seen: { [string]: boolean }?): { [string]: string }
	local out: { [string]: string } = {}
	seen = seen or {}
	if assert(seen)[typeName] or bodies[typeName] == nil then
		return out
	end
	assert(seen)[typeName] = true
	local fields, refs = scan(bodies[typeName])
	for _, field in fields do
		if string.match(field, "^[a-z]") then
			out[field] = typeName
		end
	end
	for _, ref in refs do
		for field, origin in optionsOf(ref, seen) do
			out[field] = out[field] or origin
		end
	end
	return out
end

local function propsTypeOf(expr: string, depth: number?): string?
	local hit = string.match(expr, "([%w_]+Props)")
		or string.match(expr, "([%w_]+Spec)")
		or string.match(expr, "([%w_]+Options)")
	if hit then
		return hit
	end
	if (depth or 0) > 3 then
		return nil
	end
	for ident in string.gmatch(expr, "([%w_]+)") do
		if bodies[ident] then
			local found = propsTypeOf(bodies[ident], (depth or 0) + 1)
			if found then
				return found
			end
		end
	end
	return nil
end

local specs: { [string]: { [string]: string } } = {}
local names = {}

local origins: { [string]: { [string]: string } } = {}
for _, entry in fs.listDirectory(FACET) do
	local name = entry.name
	if string.match(name, "_props%.luau$") then
		local source = fs.readFileToString(FACET .. name)
		local aliases: { [string]: string } = {}
		for alias, typeName in string.gmatch(source, "\nlocal ([%w_]+) = %(nil :: unknown%) :: [%w_]+%.([%w_]+)") do
			aliases[alias] = typeName
		end
		for _, chunk in string.split(source, "\nexport type ") do
			local typeName = string.match(chunk, "^([%w_]+)")
			if typeName then
				local fields: { [string]: string } = {}
				for line in string.gmatch(chunk, "[^\n]+") do
					local field, alias = string.match(line, "^\t([%l_][%w_]*): typeof%(([%w_]+)%.[%w_]+%),$")
					local inline = nil
					if field == nil then
						field, inline =
							string.match(line, "^\t([%l_][%w_]*): typeof%(%(%(nil :: unknown%) :: [%w_]+%.([%w_]+)")
					end
					local optionTable = if alias then aliases[alias] else inline
					if field and optionTable then
						fields[field] = optionsOf(optionTable)[field] or optionTable
					end
				end
				origins[typeName] = fields
			end
		end
	end
end
local controlTypes = fs.readFileToString(FACET .. "control_types.luau")
local constructors: { [string]: string } = {}
local collecting: string? = nil
for line in string.gmatch(controlTypes, "[^\n]+") do
	local opened = string.match(line, "^type ([%w_]+Shapes) =")
	if opened then
		collecting = opened
		constructors[opened] = ""
	elseif collecting and string.sub(line, 1, 1) == "\t" then
		constructors[collecting] ..= line
	else
		collecting = nil
	end
end
local controlsBody = assert(string.match(controlTypes, "export type Controls = {\n(.-)\n}"))
for line in string.gmatch(controlsBody, "[^\n]+") do
	local control, expr = string.match(line, "^\t([%a_][%w_]*): (.+),$")
	if control then
		local source = expr
		local shapes = string.match(expr, "^[%w_]+Constructor$")
		if shapes then
			source = constructors[string.gsub(expr, "Constructor$", "Shapes")] or expr
		end
		local fields: { [string]: string } = {}
		for propsName in string.gmatch(source, "%.([%w_]+)") do
			for field, origin in origins[propsName] or {} do
				fields[field] = fields[field] or origin
			end
		end
		specs[control] = fields
		table.insert(names, control)
	end
end
table.sort(names)

local ANY
ANY = setmetatable({}, {
	__index = function()
		return ANY
	end,
	__call = function()
		return ANY
	end,
})
local stub = setmetatable({
	cell = function(_n, v)
		return v
	end,
	log = function()
		return function() end
	end,
}, {
	__index = function()
		return ANY
	end,
})
local function keysOf(source: Source?, into: { [string]: boolean })
	local ok, value = pcall(function(): Props?
		return if typeof(source) == "function" then source(stub) else source
	end)
	if ok and type(value) == "table" then
		for key in value do
			if type(key) == "string" then
				into[key] = true
			end
		end
	end
end
local shownBy: { [string]: { [string]: boolean } } = {}
for id, data in catalog.PAGE_DATA do
	local shown: { [string]: boolean } = {}
	keysOf(data.base, shown)
	for _, axis in list(data.axes) do
		shown[axis.key] = true
		keysOf(axis.props, shown)
		for _, need in map(axis.implies) do
			keysOf(need, shown)
		end
	end
	for _, st in list(data.states) do
		keysOf(st.props, shown)
	end
	for _, key in list(data.demonstrates) do
		shown[key] = true
	end
	shownBy[id] = shown
end

local GLOBAL = { ref = "the root hook every constructor takes" }
local ALLOW: { [string]: { [string]: string } } = {
	environment = {},
	Flash = {
		color = "the reward sequence page drives Flash through UI.sequence",
		mode = "the reward sequence page drives Flash through UI.sequence",
		progress = "the reward sequence page drives Flash through UI.sequence",
		target = "the reward sequence page drives Flash through UI.sequence",
	},
	NavigationSplitView = {
		compactHeight = "the split view page shows its default columns",
		compactWidth = "the split view page shows its default columns",
		detailVisible = "the split view page shows its default columns",
		maxSidebarHeight = "the split view page shows its default columns",
		maxSidebarWidth = "the split view page shows its default columns",
		minDetailHeight = "the split view page shows its default columns",
		minDetailWidth = "the split view page shows its default columns",
		minSidebarHeight = "the split view page shows its default columns",
		minSidebarWidth = "the split view page shows its default columns",
	},
	Travel = {
		content = "the Travel page drives these options from its custom demos",
		destination = "the Travel page drives these options from its custom demos",
		lift = "the Travel page drives these options from its custom demos",
		motion = "the Travel page drives these options from its custom demos",
		onLanded = "the Travel page drives these options from its custom demos",
		onStarted = "the Travel page drives these options from its custom demos",
		stagger = "the Travel page drives these options from its custom demos",
		transparency = "the Travel page drives these options from its custom demos",
	},
	ZoomView = {
		content = "the ZoomView page drives these options from its custom demo",
		contentSize = "the ZoomView page drives these options from its custom demo",
		controls = "the ZoomView page drives these options from its custom demo",
		doubleTapZoom = "the ZoomView page drives these options from its custom demo",
		focus = "the ZoomView page drives these options from its custom demo",
		minZoom = "the ZoomView page drives these options from its custom demo",
		zoom = "the ZoomView page drives these options from its custom demo",
	},
}

if process.args[2] ~= "check" then
	local lines = {
		"| Family | Page | Kind | Foundation alias | Variant axes | States (+rest) | Matrix cells | Scenarios |",
		"|---|---|---|---|---|---|---|---|",
	}
	local total = 0
	local ids = {}
	for id in catalog.PAGE_DATA do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		local fa, fb = catalog.PAGE_DATA[a].family, catalog.PAGE_DATA[b].family
		return if fa == fb then string.lower(a) < string.lower(b) else fa < fb
	end)
	for _, id in ids do
		local data = catalog.PAGE_DATA[id]
		local axes, axisText = list(data.axes), {}
		for _, axis in axes do
			table.insert(axisText, `{axis.key}({#axis.values})`)
		end
		local states = { "rest" }
		for _, st in list(data.states) do
			table.insert(states, st.name)
		end
		local cells = if data.matrix == false then 0 else #states * (if axes[1] then #axes[1].values else 1)
		for a = 2, #axes do
			cells += if axes[a].matrix == false then 0 else #axes[a].values
		end
		total += cells
		local kind = if data.recipe then "recipe" elseif data.facet then "facet" else "UI"
		table.insert(
			lines,
			`| {data.family} | {id} | {kind} | {data.alias or "—"} | {if #axisText > 0
				then table.concat(axisText, ", ")
				else "—"} | {table.concat(states, ", ")} | {cells} | {table.concat(data.scenarios or {}, ", ")} |`
		)
	end
	print(table.concat(lines, "\n"))
	print(`\nTotals: {#ids} pages ({#names} public app.UI entries); {total} example cells per theme.`)
	return
end

local shownAnywhere: { [string]: boolean } = {}
for _, control in names do
	for field, origin in specs[control] do
		if shownBy[control] and shownBy[control][field] then
			shownAnywhere[field .. "@" .. origin] = true
		end
	end
end
local gaps = {}
for _, control in names do
	local shown = shownBy[control]
	if shown == nil then
		table.insert(gaps, `{control}: no lab page`)
		continue
	end
	local missing = {}
	for field, origin in specs[control] do
		local covered = shown[field] or shownAnywhere[field .. "@" .. origin]
		if not covered and GLOBAL[field] == nil and (ALLOW[control] or {})[field] == nil then
			table.insert(missing, field)
		end
	end
	table.sort(missing)
	if #missing > 0 then
		table.insert(gaps, `{control}: {table.concat(missing, ", ")}`)
	end
end
if #gaps > 0 then
	print(`OPTION COVERAGE: {#gaps} public entries are not fully demonstrated:\n  ` .. table.concat(gaps, "\n  "))
	process.exit(1)
end
print(
	`OPTION COVERAGE: every option of {#names} public app.UI entries is demonstrated (or allow-listed with a reason).`
)
