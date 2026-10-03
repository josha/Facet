--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local FACET = "../../src/ui/"

local env = {}
for key, value in roblox :: any do
	env[key] = value
end
local catalog = luau.load(fs.readFile("src/catalog.luau"), { debugName = "catalog", environment = env })()

local bodies: { [string]: string } = {}
for _, name in fs.readDir(FACET) do
	if string.match(name, "_types%.luau$") and name ~= "engine_types.luau" then
		local source = fs.readFile(FACET .. name) .. "\nexport type __END = nil\n"
		for start, typeName in string.gmatch(source, "()export type ([%w_]+)") do
			local rest = string.sub(source, tonumber(start) :: number)

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

local groups: { [string]: boolean } = {}
for group in string.gmatch(fs.readFile(FACET .. "control_types.luau"), ":: [%w_]+%.([%w_]+Controls)%)") do
	groups[group] = true
end
for typeName, body in bodies do
	if groups[typeName] then
		for line in string.gmatch(body, "[^\n]+") do
			local control, expr = string.match(line, "^\t([%a_][%w_]*): (.+),$")
			if control then
				local props = propsTypeOf(assert(expr))
				specs[control] = if props then optionsOf(props) else {}
				table.insert(names, control)
			end
		end
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
local function keysOf(source: any, into: { [string]: boolean })
	local ok, value = pcall(function()
		return if type(source) == "function" then source(stub) else source
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
	for _, axis in data.axes or {} do
		shown[axis.key] = true
		keysOf(axis.props, shown)
		for _, need in axis.implies or {} do
			keysOf(need, shown)
		end
	end
	for _, st in data.states or {} do
		keysOf(st.props, shown)
	end
	for _, key in data.demonstrates or {} do
		shown[key] = true
	end
	shownBy[id] = shown
end

local GLOBAL = { ref = "the root hook every constructor takes" }
local ALLOW: { [string]: { [string]: string } } = {
	environment = {},
}

if process.args[1] ~= "check" then
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
		local axes, axisText = data.axes or {}, {}
		for _, axis in axes do
			table.insert(axisText, `{axis.key}({#axis.values})`)
		end
		local states = { "rest" }
		for _, st in data.states or {} do
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
