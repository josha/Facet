--!strict
--[[ THE ARRANGE-REPORTS SEAM, MECHANISED — what keeps
	`layout/arrange_reports.luau` one-way.

	WHY A SPEC AND NOT A COMMENT. `tools/lune/verify/data/source-cap-ledger.md`
	records the rule every extraction in this repository is judged by: a block may
	leave a file only if it reads no mutable upvalue of its host, because otherwise
	the move creates a require BACK and the two files become one file with a slash
	in the middle. This block left `arrange` with NO `Deps` record — unlike
	`./shrink`, `./grid`, `./flow` and `./candidate`, which all left the solver
	holding one — because everything it needs is a value the caller already has on
	the line that calls it. That emptiness is the whole argument, and it is a claim
	that decays the moment someone reaches back across it for one convenient helper.

	  ZERO DEPS      the module requires nothing and takes no `deps` record
	  ONE CONSUMER   `src/layout/solver.luau`, from inside `arrange`
	  ONE-WAY        it names no solver symbol and imports no solver type
	  A CLOSED INPUT the exact `ctx` and `node` fields it reads, as a SET — a sixth
	                 `ctx` field reached for is the first step of a seam growing back
	  NOTHING LEFT   the solver kept no copy of the four messages
	  NO STATE       no module-level local is ever reassigned

	Each source rule is a pure function of a string, so each carries a NEGATIVE
	CONTROL that feeds it a broken input and proves it reports. A check that cannot
	fail is decoration. The BEHAVIOUR half of this seam is not here and does not
	need to be: `tests/layout.spec.luau`, `tests/containment_diagnostic.spec.luau`
	and `tests/chrome_inset_yield.spec.luau` already drive all four messages
	through the public surface, and they were green across the split. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")
local srcTree = require("./lib/src_tree")

local SOLVER_PATH = "src/layout/solver.luau"
local REPORTS_PATH = "src/layout/arrange_reports.luau"

--[[ COMMENTS ARE NOT CODE, and in this repository that is not a nicety: this
	module's own header names `arrange`, `ctx.diagnostics` and `measure` while
	explaining what it must never reach for, and a scan that counted them would
	report the exact dependency the header promises it does not have. ]]
local function stripComments(source: string): string
	local out = string.gsub("\n" .. source, "%-%-%[%[.-%]%]", " ")
	out = string.gsub(out, "\n[ \t]*%-%-[^\n]*", "\n")
	return out
end

local function sorted(set: { [string]: boolean }): { string }
	local out: { string } = {}
	for key in set do
		table.insert(out, key)
	end
	table.sort(out)
	return out
end

-- every `<name>.<field>` read of one receiver, comments stripped
local function fieldsRead(source: string, receiver: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for key in string.gmatch(stripComments(source), receiver .. "%.([%a_][%w_]*)") do
		out[key] = true
	end
	return out
end

describe("the arrange-reports seam: ZERO deps, one consumer, one-way", function()
	local reportsSrc = fs.readFile(REPORTS_PATH)
	local solverSrc = fs.readFile(SOLVER_PATH)

	it("the module requires NOTHING and takes no deps record", function()
		local requires: { string } = {}
		for path in string.gmatch(stripComments(reportsSrc), 'require%("([^"]+)"%)') do
			table.insert(requires, path)
		end
		expect(requires).toEqual({})
		expect(sorted(fieldsRead(reportsSrc, "deps"))).toEqual({})
	end)

	it("it reads a CLOSED set of ctx, node and rect fields", function()
		--[[ THE SCHEMA IT DEPENDS ON, AS A SET rather than as a promise. Both
			parameters are typed `any` precisely so the module cannot import the
			solver's own types back, which means nothing but this check reports a sixth
			`node` field being reached for. `hiddenDepth` is the gate every one of the
			four messages shares and `diagnostics` is the only thing it writes — so a
			third `ctx` field appearing here is a report that has started to depend on
			the SOLVE rather than on the node's own box. ]]
		expect(sorted(fieldsRead(reportsSrc, "ctx"))).toEqual({ "diagnostics", "hiddenDepth" })
		expect(sorted(fieldsRead(reportsSrc, "node"))).toEqual({
			"children",
			"chromeSlot",
			"chromeYield",
			"id",
			"inertPlacement",
			"kind",
			"sizeRefused",
			"text",
		})
		expect(sorted(fieldsRead(reportsSrc, "rect"))).toEqual({ "h", "w" })
	end)

	it("there is exactly ONE consumer of the module in src/", function()
		expect(srcTree.pathsMatching('require%("[^"]*arrange_reports"%)')).toEqual({ SOLVER_PATH })
	end)

	it("the module names no solver symbol and imports no solver type", function()
		-- a type import is a require by another name in Luau (`require` first, then
		-- `Module.Type`), so the structural `any` on both parameters is what keeps the
		-- graph acyclic
		local body = stripComments(reportsSrc)
		expect(string.find(body, ": Node")).toBe(nil)
		expect(string.find(body, ": Ctx")).toBe(nil)
		expect(string.find(body, "solver%.")).toBe(nil)
		-- ...and the direction that IS allowed is present, so this cannot pass by the
		-- solver having quietly dropped the require
		expect(string.find(solverSrc, 'require("./arrange_reports")', 1, true) ~= nil).toBe(true)
	end)

	it("NEGATIVE CONTROL: each scan reads what it claims to, and reports a broken input", function()
		expect(sorted(fieldsRead("local a = ctx.diagnostics\nlocal b = ctx.gridPlan\n", "ctx"))).toEqual({
			"diagnostics",
			"gridPlan",
		})
		-- a name inside a comment is NOT a read, and this module's header has live
		-- instances of that trap
		expect(sorted(fieldsRead("--[[ ctx.ghost ]]\nlocal x = ctx.diagnostics\n", "ctx"))).toEqual({ "diagnostics" })
		expect(sorted(fieldsRead("\t-- ctx.ghost\n\tlocal x = ctx.diagnostics\n", "ctx"))).toEqual({ "diagnostics" })
		local fakeRequires: { string } = {}
		for path in string.gmatch(stripComments('local s = require("./solver")\n'), 'require%("([^"]+)"%)') do
			table.insert(fakeRequires, path)
		end
		expect(fakeRequires).toEqual({ "./solver" })
		expect(string.find(stripComments("local x: Node = node\n"), ": Node") ~= nil).toBe(true)
	end)
end)

describe("the arrange-reports seam: EXPORTED == BOUND, and nothing stayed behind", function()
	local reportsSrc = fs.readFile(REPORTS_PATH)
	local solverSrc = fs.readFile(SOLVER_PATH)

	it("the module exports exactly `box`, and the solver calls that one function", function()
		local exported: { [string]: boolean } = {}
		for name in string.gmatch(stripComments(reportsSrc), "function arrange_reports%.([%a_][%w_]*)") do
			exported[name] = true
		end
		expect(sorted(exported)).toEqual({ "box" })
		expect(
			string.find(solverSrc, "arrange_reports.box(ctx, node, rect, innerW, innerH, pt, pr, pb, pl)", 1, true)
				~= nil
		).toBe(true)
	end)

	it("the solver kept no copy of the four messages", function()
		--[[ THE FAILURE THIS REPOSITORY HAS ALREADY PAID FOR ONCE: a block "moved" by
			copying, leaving the host's version live and the two drifting. Each string
			below is a distinctive fragment of one of the four reports, and none of them
			may appear in the solver any more. ]]
		local body = stripComments(solverSrc)
		expect(string.find(body, "content box collapses to 0px", 1, true)).toBe(nil)
		expect(string.find(body, "chrome contentInsets could not be spent", 1, true)).toBe(nil)
		expect(string.find(body, "icon floor wanted", 1, true)).toBe(nil)
		expect(string.find(body, "node.inertPlacement", 1, true)).toBe(nil)
	end)

	it("NEGATIVE CONTROL: the export scan and the leftover scan both report", function()
		local fake = "function arrange_reports.box(a)\nend\nfunction arrange_reports.extra()\nend\n"
		local exported: { [string]: boolean } = {}
		for name in string.gmatch(stripComments(fake), "function arrange_reports%.([%a_][%w_]*)") do
			exported[name] = true
		end
		expect(sorted(exported)).toEqual({ "box", "extra" })
		expect(
			string.find(
				stripComments("\tlocal x = 1 -- keep\n\tif node.inertPlacement then\n"),
				"node.inertPlacement",
				1,
				true
			) ~= nil
		).toBe(true)
	end)
end)

describe("the arrange-reports seam: no module-level mutable state", function()
	it("nothing declared at module level is ever reassigned", function()
		--[[ A MODULE-LEVEL MUTABLE IS A SECOND SOLVE'S STATE LEAKING INTO THE FIRST,
			and it is the one way a pure-looking report module stops being pure. The
			scan is deliberately crude — every `local <name>` at column zero, then every
			bare `<name> =` at column zero — because a `local` that is never written is
			a constant and a `local` that is written is the thing this forbids. ]]
		local body = stripComments(fs.readFile(REPORTS_PATH))
		local declared: { [string]: boolean } = {}
		for name in string.gmatch(body, "\nlocal ([%a_][%w_]*)") do
			declared[name] = true
		end
		expect(sorted(declared)).toEqual({ "arrange_reports" })
		local reassigned: { string } = {}
		for name in string.gmatch(body, "\n([%a_][%w_]*) =") do
			if declared[name] then
				table.insert(reassigned, name)
			end
		end
		expect(reassigned).toEqual({})
	end)

	it("NEGATIVE CONTROL: the reassignment scan reports one", function()
		local fake = "\nlocal cache = nil\nlocal m = {}\ncache = 1\n"
		local declared: { [string]: boolean } = {}
		for name in string.gmatch(fake, "\nlocal ([%a_][%w_]*)") do
			declared[name] = true
		end
		local reassigned: { string } = {}
		for name in string.gmatch(fake, "\n([%a_][%w_]*) =") do
			if declared[name] then
				table.insert(reassigned, name)
			end
		end
		expect(reassigned).toEqual({ "cache" })
	end)
end)
