--!strict
local fs = require("@std/fs")
local process = require("@std/process")
local Lute = require("../../../tools/vendor/verify/src/lute")
local roblox = require("../../../tools/vendor/verify/src/roblox").datatypes

local FACET = "../../src/ui/"
local ControlProps = require("../../../tools/facet/lib/control_props")

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
for key, value in (roblox :: unknown) :: { [string]: unknown } do
	env[key] = value
end
env.require = function(path: string): unknown
	local name = assert(string.match(path, "^%./([%w_]+)$"))
	local module = Lute.chunk.load(fs.readFileToString(`src/{name}.luau`), { name = name, environment = env })()
	return module
end
type Catalog = { PAGE_DATA: { [string]: PageData } }
local catalog =
	Lute.chunk.load(fs.readFileToString("src/catalog.luau"), { name = "catalog", environment = env })() :: Catalog

local specs: { [string]: { [string]: string } } = {}
local names: { string } = {}
local origins = ControlProps.optionOrigins("../..")
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
	if control and expr then
		local source: string = expr
		if string.match(expr, "^[%w_]+Constructor$") then
			local shapesName = string.gsub(expr, "Constructor$", "Shapes")
			source = constructors[shapesName] or expr
		end
		local fields: { [string]: string } = {}
		for propsName in string.gmatch(source, "%.([%w_]+)") do
			local declared = origins[assert(propsName)]
			if declared then
				for field, origin in declared do
					fields[field] = fields[field] or origin
				end
			end
		end
		specs[control] = fields
		table.insert(names, control)
	end
end
table.sort(names)

if process.args[2] == "fields" then
	local lines: { string } = {}
	for control, fields in specs do
		for field, origin in fields do
			table.insert(lines, `{control}\t{field}\t{origin}`)
		end
	end
	table.sort(lines)
	print(table.concat(lines, "\n"))
	return
end

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
		followTransition = "custom_transition grows a following ZoomView with a scaled split page reveal",
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
