--!strict
--[[ THE STACK SEAM, MECHANISED — what keeps `layout/stack.luau` one-way.

	WHY A SPEC AND NOT A COMMENT. `tools/lune/verify/data/source-cap-ledger.md`
	records the rule every extraction in this repository is judged by: a block may
	leave a file only if it reads no mutable upvalue of its host, because otherwise
	the move creates a require BACK and the two files become one file with a slash
	in the middle. This is the FIFTH solver seam and the largest — 15,821 characters,
	the whole vstack/hstack arrange branch — and it is the block that row's trigger
	has named by name since the T4 split.

	  A CLOSED DEPS      READ == DECLARED == PASSED, as three SETS compared against
	                     each other. A sixth field reached for is a seam growing back
	  READ vs WRITE      the `ctx`/`node`/`child` fields it reads, as sets, and the
	                     ONE thing it writes (`ctx.diagnostics`, and only by insert)
	  TWO CALL ARGUMENTS `place` and `noteContainment`, passed rather than captured,
	                     for the reason `grid.luau` states about its own pair
	  ONE CONSUMER       `src/layout/solver.luau`, from the tail of `arrange`
	  ONE-WAY            it names no solver symbol and imports no solver type, and
	                     its three requires are leaves the solver also requires
	  NOTHING LEFT       the solver kept no copy of the branch
	  NO STATE           no module-level local is ever reassigned

	Each source rule is a pure function of a string, so each carries a NEGATIVE
	CONTROL that feeds it a broken input and proves it reports. A check that cannot
	fail is decoration. The BEHAVIOUR half of this seam is not here and does not need
	to be: `tests/stack_distribution.spec.luau`, `tests/layout.spec.luau` and very
	nearly every fixture in this repository drive a vstack or an hstack through the
	public surface, and they were green across the split. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")
local srcTree = require("./lib/src_tree")

local SOLVER_PATH = "src/layout/solver.luau"
local STACK_PATH = "src/layout/stack.luau"

--[[ COMMENTS ARE NOT CODE, and in this repository that is not a nicety: this
	module's own header names `arrange`, `measure` and `solver.Node` while explaining
	what it must never reach for, and a scan that counted them would report the exact
	dependency the header promises it does not have. ]]
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

describe("the stack seam: a CLOSED Deps record, read == declared == passed", function()
	local stackSrc = fs.readFile(STACK_PATH)
	local solverSrc = fs.readFile(SOLVER_PATH)

	it("the fields the body READS are exactly the fields the type DECLARES", function()
		--[[ THE ONE-WAY TEST ITSELF, as a set comparison rather than a promise. A
			`Deps` record is a statement about what a module reads from its host
			(`solver.luau`'s own note beside `COMPOSITION_DEPS`: "a spare field in it is
			a false statement"), so the two directions are both defects — a field read
			and not declared would not typecheck, and a field declared and not read is
			the host handing over something this module has stopped needing. ]]
		local declared: { [string]: boolean } = {}
		local block = string.match(stripComments(stackSrc), "export type Deps = {(.-)\n}")
		assert(block ~= nil, "the Deps type block was not found")
		for name in string.gmatch(block :: string, "\n\t([%a_][%w_]*):") do
			declared[name] = true
		end
		expect(sorted(declared)).toEqual({ "dim", "mainDimOf", "measure", "shrink", "sides" })
		expect(sorted(fieldsRead(stackSrc, "deps"))).toEqual(sorted(declared))
	end)

	it("...and exactly the fields the solver PASSES, in the one record it builds", function()
		local literal = string.match(stripComments(solverSrc), "local STACK_DEPS: stackLib%.Deps = {(.-)\n}")
		assert(literal ~= nil, "the solver's STACK_DEPS literal was not found")
		local passed: { [string]: boolean } = {}
		for name in string.gmatch(literal :: string, "\n\t([%a_][%w_]*) =") do
			passed[name] = true
		end
		expect(sorted(passed)).toEqual({ "dim", "mainDimOf", "measure", "shrink", "sides" })
		--[[ AND `measure` IS BORROWED, NOT REBUILT. `GRID_DEPS.measure` is the
			forwarder that reads the forward local at call time; building a second one
			here is how the two records end up reading a different `measure` after an
			edit, which is the failure `FLOW_DEPS = GRID_DEPS` was written to prevent
			one record up. ]]
		expect(string.find(literal :: string, "measure = GRID_DEPS.measure", 1, true) ~= nil).toBe(true)
		-- ...and the shrink record TRAVELS rather than being rebuilt in the module,
		-- for the same reason
		expect(string.find(literal :: string, "shrink = SHRINK_DEPS", 1, true) ~= nil).toBe(true)
		expect(string.find(stripComments(stackSrc), "textTypography", 1, true)).toBe(nil)
	end)

	it("`place` and `noteContainment` are CALL-SITE arguments, not Deps fields", function()
		--[[ THE DISTINCTION THAT IS NOT COSMETIC, and `grid.luau`'s header already
			carries the reason: both are declared BELOW the line `STACK_DEPS` is built
			on, so a by-value record there would capture the nil global and die inside a
			protected solve boundary — and forward-declaring them to avoid that would add
			a mutable module local, which is the opposite of what a split is for. ]]
		local declaredDeps = string.match(stripComments(stackSrc), "export type Deps = {(.-)\n}") :: string
		expect(string.find(declaredDeps, "place", 1, true)).toBe(nil)
		expect(string.find(declaredDeps, "noteContainment", 1, true)).toBe(nil)
		expect(string.find(stripComments(stackSrc), "place: Place,", 1, true) ~= nil).toBe(true)
		expect(string.find(stripComments(stackSrc), "noteContainment: NoteContainment,", 1, true) ~= nil).toBe(true)
		-- and the solver really does hand both over on the one call
		expect(
			string.find(
				solverSrc,
				"stackLib.arrange(STACK_DEPS, ctx, node, innerX, innerY, innerW, innerH, gap, arrange, noteContainment, out)",
				1,
				true
			) ~= nil
		).toBe(true)
	end)

	it("NEGATIVE CONTROL: the Deps and literal scans both report a changed set", function()
		local fakeType = "export type Deps = {\n\tmeasure: (any) -> (),\n\tghost: (any) -> (),\n}\n"
		local declared: { [string]: boolean } = {}
		local block = string.match(stripComments(fakeType), "export type Deps = {(.-)\n}") :: string
		for name in string.gmatch(block, "\n\t([%a_][%w_]*):") do
			declared[name] = true
		end
		expect(sorted(declared)).toEqual({ "ghost", "measure" })
		local fakeLiteral = "local STACK_DEPS: stackLib.Deps = {\n\tmeasure = m,\n\tghost = g,\n}\n"
		local passed: { [string]: boolean } = {}
		local literal =
			string.match(stripComments(fakeLiteral), "local STACK_DEPS: stackLib%.Deps = {(.-)\n}") :: string
		for name in string.gmatch(literal, "\n\t([%a_][%w_]*) =") do
			passed[name] = true
		end
		expect(sorted(passed)).toEqual({ "ghost", "measure" })
		expect(sorted(fieldsRead("local x = deps.ghost\n", "deps"))).toEqual({ "ghost" })
	end)
end)

describe("the stack seam: what it READS of the solve, and the one thing it WRITES", function()
	local stackSrc = fs.readFile(STACK_PATH)

	it("it reads a CLOSED set of ctx, node and child fields", function()
		--[[ THE SCHEMA IT DEPENDS ON, AS A SET rather than as a promise. Every
			parameter is typed `any` precisely so the module cannot import the solver's
			own types back, which means nothing but this check reports a third `ctx`
			field being reached for. `hiddenDepth` is the gate the two diagnostics share
			and `diagnostics` is the only thing this module writes — so a third `ctx`
			field appearing here is a stack branch that has started to depend on the
			SOLVE rather than on the node and the box it was handed. ]]
		expect(sorted(fieldsRead(stackSrc, "ctx"))).toEqual({ "diagnostics", "hiddenDepth" })
		expect(sorted(fieldsRead(stackSrc, "node"))).toEqual({ "align", "children", "distribute", "id", "kind" })
		expect(sorted(fieldsRead(stackSrc, "child"))).toEqual({ "align", "lineAlign", "margin", "shrinkWeight" })
	end)

	it("it WRITES nothing of the solver's but `ctx.diagnostics`, and only by insert", function()
		--[[ THE READ-vs-WRITE HALF OF THE ONE-WAY TEST, and the half a field-read scan
			cannot see. A block that only reads its host's state can be moved; a block
			that WRITES it has to be trusted to write the same thing at the same moment,
			which is a different and much weaker claim. This branch assigns no field of
			`ctx`, `node`, `child` or `deps` at all — its two diagnostics append to the
			list its caller owns, and every rect it produces reaches `out` through
			`place`, which is the solver's own `arrange`. ]]
		local body = stripComments(stackSrc)
		local assigned: { string } = {}
		for recv, field in string.gmatch(body, "([%a_][%w_]*)%.([%a_][%w_]*)%s*[%+%-]?=[^=]") do
			if recv == "ctx" or recv == "node" or recv == "child" or recv == "deps" then
				table.insert(assigned, `{recv}.{field}`)
			end
		end
		expect(assigned).toEqual({})
		local inserts: { [string]: boolean } = {}
		for target in string.gmatch(body, "table%.insert%(%s*([%a_][%w_%.]*)") do
			if string.find(target, ".", 1, true) ~= nil then
				inserts[target] = true
			end
		end
		expect(sorted(inserts)).toEqual({ "ctx.diagnostics" })
	end)

	it("NEGATIVE CONTROL: the write scans report an assignment and a second insert target", function()
		local fake = "\nctx.measured += 1\nlocal x = ctx.diagnostics\n"
		local assigned: { string } = {}
		for recv, field in string.gmatch(stripComments(fake), "([%a_][%w_]*)%.([%a_][%w_]*)%s*[%+%-]?=[^=]") do
			if recv == "ctx" then
				table.insert(assigned, `{recv}.{field}`)
			end
		end
		expect(assigned).toEqual({ "ctx.measured" })
		local inserts: { [string]: boolean } = {}
		for target in
			string.gmatch(
				stripComments("table.insert(ctx.walked, 1)\ntable.insert(ctx.diagnostics, d)\n"),
				"table%.insert%(%s*([%a_][%w_%.]*)"
			)
		do
			if string.find(target, ".", 1, true) ~= nil then
				inserts[target] = true
			end
		end
		expect(sorted(inserts)).toEqual({ "ctx.diagnostics", "ctx.walked" })
		-- ...and a `==` comparison is not an assignment, which is the one way this
		-- scan could have been silently vacuous
		local none: { string } = {}
		for recv, field in
			string.gmatch(
				stripComments("\nif ctx.hiddenDepth == 0 then\n"),
				"([%a_][%w_]*)%.([%a_][%w_]*)%s*[%+%-]?=[^=]"
			)
		do
			table.insert(none, `{recv}.{field}`)
		end
		expect(none).toEqual({})
	end)
end)

describe("the stack seam: one-way, one consumer, and nothing stayed behind", function()
	local stackSrc = fs.readFile(STACK_PATH)
	local solverSrc = fs.readFile(SOLVER_PATH)

	it("it requires only leaves, and never the solver", function()
		--[[ THE THREE ARE LEAVES THE SOLVER ALSO REQUIRES, so the graph stays acyclic:
			`../num` is arithmetic, `./placement` is five functions on numbers, and
			`./shrink` takes the record this module is handed rather than reaching back
			for one. The `shrink` DEPS itself is NOT rebuilt here — see the Deps case. ]]
		local requires: { string } = {}
		for path in string.gmatch(stripComments(stackSrc), 'require%("([^"]+)"%)') do
			table.insert(requires, path)
		end
		table.sort(requires)
		expect(requires).toEqual({ "../num", "./placement", "./shrink" })
	end)

	it("it names no solver symbol and imports no solver type", function()
		-- a type import is a require by another name in Luau (`require` first, then
		-- `Module.Type`), so the structural `any` on every parameter is what keeps the
		-- graph acyclic
		local body = stripComments(stackSrc)
		expect(string.find(body, ": Node")).toBe(nil)
		expect(string.find(body, ": Ctx")).toBe(nil)
		expect(string.find(body, "solver%.")).toBe(nil)
		-- ...and the direction that IS allowed is present, so this cannot pass by the
		-- solver having quietly dropped the require
		expect(string.find(solverSrc, 'require("./stack")', 1, true) ~= nil).toBe(true)
	end)

	it("there is exactly ONE consumer of the module in src/", function()
		expect(srcTree.pathsMatching('require%("[^"]*/stack"%)')).toEqual({ SOLVER_PATH })
	end)

	it("the module exports exactly `arrange`, and the solver calls that one function", function()
		local exported: { [string]: boolean } = {}
		for name in string.gmatch(stripComments(stackSrc), "function stack%.([%a_][%w_]*)") do
			exported[name] = true
		end
		expect(sorted(exported)).toEqual({ "arrange" })
		local calls = 0
		for _ in string.gmatch(stripComments(solverSrc), "stackLib%.arrange%(") do
			calls += 1
		end
		expect(calls).toBe(1)
	end)

	it("the solver kept no copy of the branch", function()
		--[[ THE FAILURE THIS REPOSITORY HAS ALREADY PAID FOR ONCE: a block "moved" by
			copying, leaving the host's version live and the two drifting. Each string
			below is a distinctive line of the branch that left, and none of them may
			appear in the solver any more. `local isH = node.kind == "hstack"` is
			DELIBERATELY NOT one of them — the MEASURE-side stack pass still uses that
			exact line and stayed behind, which is what makes this list a real one. ]]
		local body = stripComments(solverSrc)
		expect(string.find(body, "local hugLater", 1, true)).toBe(nil)
		expect(string.find(body, "hasShrink", 1, true)).toBe(nil)
		expect(string.find(body, "local clipMain", 1, true)).toBe(nil)
		expect(string.find(body, "child.lineAlign or child.align or node.align", 1, true)).toBe(nil)
		--[[ THREE NEAR-MISSES ARE DELIBERATELY *NOT* ON THAT LIST, and each one is why
			this case had to be written by measurement rather than by eye:
			`local isH = node.kind == "hstack"` and `fillWeightSum` are the MEASURE-side
			stack pass, `gapExtraApplied` and `distributionOf(` are the WRAP branch, and
			`local shrunk` is the measure pass's own. All five stayed behind correctly.
			The positives below prove the file was not simply emptied. ]]
		expect(string.find(body, 'local isH = node.kind == "hstack"', 1, true) ~= nil).toBe(true)
		expect(string.find(body, "gapExtraApplied", 1, true) ~= nil).toBe(true)
		expect(string.find(body, "distributionOf(", 1, true) ~= nil).toBe(true)
	end)

	it("NEGATIVE CONTROL: the require, export and leftover scans all report", function()
		local fakeRequires: { string } = {}
		for path in string.gmatch(stripComments('local s = require("./solver")\n'), 'require%("([^"]+)"%)') do
			table.insert(fakeRequires, path)
		end
		expect(fakeRequires).toEqual({ "./solver" })
		local fake = "function stack.arrange(a)\nend\nfunction stack.extra()\nend\n"
		local exported: { [string]: boolean } = {}
		for name in string.gmatch(stripComments(fake), "function stack%.([%a_][%w_]*)") do
			exported[name] = true
		end
		expect(sorted(exported)).toEqual({ "arrange", "extra" })
		expect(string.find(stripComments("\tlocal hugLater = {}\n"), "local hugLater", 1, true) ~= nil).toBe(true)
		expect(string.find(stripComments("local x: Node = node\n"), ": Node") ~= nil).toBe(true)
	end)
end)

describe("the stack seam: no module-level mutable state", function()
	it("nothing declared at module level is ever reassigned", function()
		--[[ A MODULE-LEVEL MUTABLE IS A SECOND SOLVE'S STATE LEAKING INTO THE FIRST,
			and it is the one way a pure-looking arrange branch stops being pure. The
			scan is deliberately crude — every `local <name>` at column zero, then every
			bare `<name> =` at column zero — because a `local` that is never written is
			a constant and a `local` that is written is the thing this forbids. ]]
		local body = stripComments(fs.readFile(STACK_PATH))
		local declared: { [string]: boolean } = {}
		for name in string.gmatch(body, "\nlocal ([%a_][%w_]*)") do
			declared[name] = true
		end
		expect(sorted(declared)).toEqual({
			"alignOffset",
			"distributionOf",
			"num",
			"placementLib",
			"roundPx",
			"shrinkLib",
			"stack",
		})
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
