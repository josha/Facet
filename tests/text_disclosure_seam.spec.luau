--!strict
--[[ THE TEXT-DISCLOSURE SEAM, MECHANISED — what keeps `present/text_disclosure.luau`
	one-way and the owner of its own state.

	The presenter hands one record to `textDisclosureLib.new({ … })` and binds the
	returned delegates. The rules, each a pure function of the two sources:

	  HOSTED == DECLARED == READ   every key the presenter writes into the record
	                               is unpacked (`local X = ctx.X`) and used, and
	                               `ctx` is touched nowhere else
	  EXPORTED == BOUND            every returned delegate is reached by the
	                               presenter as `textDisclosure.<name>`, and back
	  WRITE MATRIX                 the module's assignment statements are exactly
	                               its own state; nothing lent is rebound, written
	                               through, `:set` or copied
	  STATE LEFT                   `disclosurePlate`/`disclosureDwell` live only
	                               inside `new`, never in the presenter or at
	                               module scope
	  ONE CONSUMER, ONE WAY        only the presenter requires it; it never
	                               requires the presenter back

	Each rule carries a NEGATIVE CONTROL feeding it a broken input. Behaviour
	(isolation between two presenters, exactly-once release) is proved mounted in
	`text_disclosure.spec`; this file proves the shape. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")
local srcTree = require("./lib/src_tree")

local PRESENTER_PATH = "src/present/presenter.luau"
local MODULE_PATH = "src/present/text_disclosure.luau"

local function stripComments(source: string): string
	local out = string.gsub("\n" .. source, "%-%-%[%[.-%]%]", " ")
	out = string.gsub(out, "\n[ \t]*%-%-[^\n]*", "\n")
	out = string.gsub(out, "[ \t]+%-%-[^\n]*", "")
	return out
end

-- `local X = ctx.X` on a line of its own: the only legal touch of `ctx`
local UNPACK = "\n\tlocal ([%a_][%w_]*) = ctx%.([%a_][%w_]*)\n"

local function declaredOf(source: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	local body = stripComments(source)
	for name, field in string.gmatch(string.gsub(body, "\n", "\n\n"), UNPACK) do
		if name == field then
			out[name] = true
		end
	end
	return out
end

local function bodyWithoutUnpack(source: string): string
	local body = string.gsub(stripComments(source), "\n", "\n\n")
	body = string.gsub(body, "\n\tlocal ([%a_][%w_]*) = ctx%.%1\n", "\n")
	return body
end

-- key -> value text of the record literal the presenter hands over
local function hostedOf(presenter: string): { [string]: string }
	local block = string.match(presenter, "textDisclosureLib%.new%({\n(.-)\n\t}%)")
	assert(block ~= nil, "no `textDisclosureLib.new({ … })` record literal to read")
	local out: { [string]: string } = {}
	for key, value in string.gmatch("\n" .. (block :: string), "\n\t\t([%a_][%w_]*) = ([^\n]*)") do
		out[key] = value
	end
	return out
end

local function keys(set: { [string]: any }): { string }
	local out: { string } = {}
	for key in set do
		table.insert(out, key)
	end
	table.sort(out)
	return out
end

local function missingFrom(a: { [string]: any }, b: { [string]: any }): { string }
	local out: { string } = {}
	for key in a do
		if b[key] == nil then
			table.insert(out, key)
		end
	end
	table.sort(out)
	return out
end

local function unusedIn(body: string, names: { [string]: boolean }): { string }
	local out: { string } = {}
	for name in names do
		if string.find(body, `[^%w_]{name}[^%w_]`) == nil then
			table.insert(out, name)
		end
	end
	table.sort(out)
	return out
end

local function exportsOf(source: string): { [string]: boolean }
	local block = string.match(source, "\n\treturn {\n(.-)\n\t}\nend\n")
	assert(block ~= nil, "no `return { … }` block to read")
	local out: { [string]: boolean } = {}
	for key in string.gmatch("\n" .. (block :: string), "\n\t\t([%a_][%w_]*) =") do
		out[key] = true
	end
	return out
end

local function boundOf(presenter: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for key in string.gmatch(stripComments(presenter), "[^%w_.]textDisclosure%.([%a_][%w_]*)") do
		out[key] = true
	end
	return out
end

--[[ THE WRITE MATRIX: every assignment STATEMENT's target, verbatim. A line
	inside an open table constructor is an entry, not a statement (the toast
	seam's recorded instrument trap), and a `local` line is a declaration. ]]
local function assignmentTargets(source: string): { string }
	local out: { string } = {}
	local depth = 0
	for line in string.gmatch(stripComments(source), "[^\n]+") do
		local trimmed = string.match(line, "^%s*(.-)%s*$") :: string
		-- one target or a comma list of them (`a, b = f()`)
		local lhs = string.match(trimmed, '^([%a_][%w_%.%[%]"%s,]*)[%+%-]?=[^=]')
		if depth == 0 and lhs ~= nil and string.sub(trimmed, 1, 6) ~= "local " then
			for target in string.gmatch(lhs, "[^,%s]+") do
				table.insert(out, target)
			end
		end
		local _, opens = string.gsub(trimmed, "{", "")
		local _, closes = string.gsub(trimmed, "}", "")
		depth += opens - closes
	end
	table.sort(out)
	return out
end

-- a lent name written through a method (`graph.focusVisible:set(…)`) or copied
local function lentMutations(source: string, names: { [string]: boolean }): { string }
	local body = bodyWithoutUnpack(source)
	local out: { string } = {}
	for name in names do
		if
			string.find(body, `[^%w_.]{name}[%w_.]*:set%(`) ~= nil
			or string.find(body, `[^%w_.]{name}[%w_.]*:update%(`) ~= nil
			or string.find(body, `table%.clone%({name}`) ~= nil
			or string.find(body, `table%.insert%({name}`) ~= nil
			or string.find(body, `table%.remove%({name}`) ~= nil
			or string.find(body, `table%.clear%({name}`) ~= nil
		then
			table.insert(out, name)
		end
	end
	table.sort(out)
	return out
end

-- column-0 locals reassigned at column 0: state two presenters would share
local function moduleReassigned(source: string): { string }
	local body = stripComments(source)
	local reassigned: { string } = {}
	for name in string.gmatch("\n" .. body, "\nlocal ([%a_][%w_]*)") do
		if string.find(body, `\n{name}%s*[%+%-]?=[^=]`) ~= nil then
			table.insert(reassigned, name)
		end
	end
	table.sort(reassigned)
	return reassigned
end

-- the targets the module may assign: its two state locals, the dwell countdown
-- on its own dwell record, and the walk/gate locals of the target lookup and the
-- focus sync. Every other target is a write into something lent.
local ALLOWED_WRITES = {
	"d.remaining",
	"disclosureDwell",
	"disclosureDwell",
	"disclosureDwell",
	"disclosureDwell",
	"disclosureDwell",
	"disclosureDwell",
	"disclosurePlate",
	"disclosurePlate",
	"foundPath",
	"foundRich",
	"foundText",
	"owner",
	"owner",
	"owner",
	"scoped",
}

describe("the text-disclosure seam: HOSTED == DECLARED == READ", function()
	local presenter = fs.readFile(PRESENTER_PATH)
	local module = fs.readFile(MODULE_PATH)

	it("the record the presenter hands over is exactly what the module unpacks", function()
		local hosted = hostedOf(presenter)
		local declared = declaredOf(module)
		expect(missingFrom(hosted, declared)).toEqual({})
		expect(missingFrom(declared, hosted)).toEqual({})
		expect(keys(hosted)).toEqual({
			"adapter",
			"core",
			"env",
			"graph",
			"handleOwning",
			"isDisposed",
			"metricsNow",
			"motionClock",
			"mountComponent",
			"safeBox",
			"stack",
		})
	end)

	it("every unpacked name is used, and `ctx` is touched nowhere but the unpack", function()
		local body = bodyWithoutUnpack(module)
		expect(unusedIn(body, declaredOf(module))).toEqual({})
		expect(string.find(body, "ctx.", 1, true)).toBe(nil)
	end)

	it("lent values arrive by reference: no copy, and `disposed` as a live getter", function()
		local hosted = hostedOf(presenter)
		for key, value in hosted do
			if key ~= "isDisposed" then
				expect(`{key} = {value}`).toBe(`{key} = {key},`)
			end
		end
		expect(hosted.isDisposed).toBe("function(): boolean")
		expect(
			string.find(presenter, "\t\tisDisposed = function(): boolean\n\t\t\treturn disposed\n\t\tend,", 1, true)
				~= nil
		).toBe(true)
		-- ...and the module holds no disposed flag of its own
		expect(string.find(stripComments(module), "[^%w_]disposed[^%w_]")).toBe(nil)
	end)

	it("NEGATIVE CONTROL: the scans report a missing, renamed, unused, stray or copied field", function()
		local literal =
			"\tlocal m = textDisclosureLib.new({\n\t\tstack = table.clone(stack),\n\t\tgraph = graph,\n\t})\n"
		expect(hostedOf(literal).stack).toBe("table.clone(stack),")
		local fake = "\n\t-- local ghost = ctx.ghost\n\tlocal real = ctx.real\n\tlocal snap = ctx.isDisposed()\n"
			.. "\tlocal alias = ctx.other\n"
		expect(keys(declaredOf(fake))).toEqual({ "real" })
		expect(string.find(bodyWithoutUnpack(fake), "ctx.", 1, true) ~= nil).toBe(true)
		expect(unusedIn("\n\treal()\n", { real = true, ghost = true })).toEqual({ "ghost" })
		expect(missingFrom({ a = true, b = true }, { a = true })).toEqual({ "b" })
	end)
end)

describe("the text-disclosure seam: the WRITE matrix", function()
	local module = fs.readFile(MODULE_PATH)

	it("the module assigns only its own state and lookup locals", function()
		expect(assignmentTargets(module)).toEqual(ALLOWED_WRITES)
	end)

	it("nothing lent is written through a method, copied, or mutated as a list", function()
		expect(lentMutations(module, declaredOf(module))).toEqual({})
	end)

	it("NEGATIVE CONTROL: each forbidden write is reported, and a read or a constructor entry is not", function()
		local text = "\n\tstack[1] = h\n\towner.hasDisclose = false\n\tgraph.x += 1\n\tdisclosurePlate = nil\n"
			.. "\tfound, stack[2] = f()\n\tlocal a = stack[1]\n\tf({\n\t\tid = DISCLOSE_ROOT,\n\t\tchildren = {\n\t\t},\n\t})\n\tif a == b then\n"
		expect(assignmentTargets(text)).toEqual({
			"disclosurePlate",
			"found",
			"graph.x",
			"owner.hasDisclose",
			"stack[1]",
			"stack[2]",
		})
		local names = { graph = true, stack = true, env = true, core = true }
		local body = "\n\tgraph.focusVisible:set(false)\n\tlocal s = table.clone(stack)\n\tenv:get('x'):peek()\n"
			.. "\ttable.insert(core, 1)\n"
		expect(lentMutations(body, names)).toEqual({ "core", "graph", "stack" })
	end)
end)

describe("the text-disclosure seam: EXPORTED == BOUND, state left, one consumer, one way", function()
	local presenter = fs.readFile(PRESENTER_PATH)
	local module = fs.readFile(MODULE_PATH)

	it("every delegate the module returns is bound by the presenter, and every binding exists", function()
		local exported = exportsOf(module)
		local bound = boundOf(presenter)
		expect(missingFrom(exported, bound)).toEqual({})
		expect(missingFrom(bound, exported)).toEqual({})
		expect(keys(exported)).toEqual({
			"clamp",
			"dismiss",
			"disposePlate",
			"dump",
			"focus",
			"hover",
			"longPress",
			"revalidate",
			"shows",
			"stepDwell",
			"targetIn",
		})
	end)

	it("the public names keep their spelling on the presenter", function()
		expect(string.find(presenter, "\n\tself.disclosure = textDisclosure.dump\n", 1, true) ~= nil).toBe(true)
		expect(string.find(presenter, "\n\tself._discloseLongPress = textDisclosure.longPress\n", 1, true) ~= nil).toBe(
			true
		)
		expect(string.find(presenter, "function self.disclosure(", 1, true)).toBe(nil)
		expect(string.find(presenter, "function self._discloseLongPress(", 1, true)).toBe(nil)
	end)

	it("the frame order is motion -> dwell -> help tick -> clamp -> anchored sync", function()
		local tick = string.match(stripComments(presenter), "\n\tfunction tickBody%(.-\n\tend\n") :: string
		local order = {}
		for _, needle in
			{
				"motionClock:step(",
				"textDisclosure.stepDwell(",
				"helpPlate.tick(",
				"textDisclosure.clamp(",
				"anchoredSurfaces.sync(",
				"stepReveal(",
			}
		do
			table.insert(order, (string.find(tick, needle, 1, true)))
		end
		for i = 2, #order do
			expect(order[i] ~= nil and order[i - 1] ~= nil and order[i] > order[i - 1]).toBe(true)
		end
	end)

	it("the plate and dwell state live only inside `new`", function()
		local stripped = stripComments(presenter)
		for _, name in { "disclosurePlate", "disclosureDwell" } do
			expect(`{name} in presenter: {string.find(stripped, `[^%w_]{name}[^%w_]`) ~= nil}`).toBe(
				`{name} in presenter: false`
			)
			expect(string.find(module, `\n\tlocal {name}: any = nil`, 1, true) ~= nil).toBe(true)
			expect(string.find(module, `\nlocal {name}`, 1, true)).toBe(nil)
		end
	end)

	it("no module-level local is ever reassigned", function()
		expect(moduleReassigned(module)).toEqual({})
	end)

	it("there is exactly ONE consumer in src/, and the require is one-way", function()
		expect(srcTree.pathsMatching('require%("[^"]*text_disclosure"%)')).toEqual({ PRESENTER_PATH })
		for path in string.gmatch(module, 'require%("([^"]+)"%)') do
			expect(string.match(path, "presenter$")).toBe(nil)
		end
		expect(string.find(presenter, 'require("./text_disclosure")', 1, true) ~= nil).toBe(true)
	end)

	it("NEGATIVE CONTROL: a module-scope plate, a stray binding and an unbound export are reported", function()
		local exported = exportsOf("\n\treturn {\n\t\tclamp = clampDisclosure,\n\t\tdump = dump,\n\t}\nend\n")
		local bound = boundOf("\n\tself.disclosure = textDisclosure.dump\n\ttextDisclosure.ghost()\n")
		expect(missingFrom(exported, bound)).toEqual({ "clamp" })
		expect(missingFrom(bound, exported)).toEqual({ "ghost" })
		local hoisted =
			"local disclosurePlate: any = nil\nfunction m.new()\n\tlocal x = 1\n\tx = 2\nend\ndisclosurePlate = {}\n"
		expect(moduleReassigned(hoisted)).toEqual({ "disclosurePlate" })
	end)
end)
