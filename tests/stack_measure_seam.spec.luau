--!strict
--[[ THE STACK *MEASURE* SEAM, MECHANISED — what keeps `layout/stack_measure.luau`
	one-way.

	WHY A SPEC AND NOT A COMMENT, and why a second one beside
	`tests/stack_seam.spec.luau`. `tools/lune/verify/data/source-cap-ledger.md` records
	the rule every extraction in this repository is judged by: a block may leave a file
	only if it reads no mutable upvalue of its host, because otherwise the move creates
	a require BACK and the two files become one file with a slash in the middle. This is
	the SIXTH solver seam and the measure-side sibling of the fifth — `./stack` took the
	vstack/hstack ARRANGE branch on 2026-09-02, this took the MEASURE branch on
	2026-09-05 — and the two are pinned apart because they are two modules with two
	Deps records and two consumers' worth of ways to grow back.

	  A CLOSED DEPS      READ == DECLARED == PASSED, as three SETS compared against
	                     each other. A fifth field reached for is a seam growing back
	  FOUR, NOT FIVE     it does NOT take `mainDimOf`, which the arrange half does —
	                     a Deps record is a statement about what a module reads, so
	                     borrowing the wider record would be a false statement
	  NO CALL ARGUMENTS  unlike `./stack`, nothing this block calls is declared below
	                     the record's line, so there is no `place`/`noteContainment`
	                     pair and the call is one expression
	  READ vs WRITE      the `ctx`/`node`/`child` fields it reads, as sets, and the
	                     fact that it writes NONE of them — this branch is a pure
	                     function of the tree and the box it was handed
	  ONE CONSUMER       `src/layout/solver.luau`, from `contentSize`'s tail
	  ONE-WAY            it names no solver symbol and imports no solver type, and its
	                     one require (`./shrink`) is a leaf the solver also requires
	  NOTHING LEFT       the solver kept no copy of the branch
	  NO STATE           no module-level local is ever reassigned

	Each source rule is a pure function of a string, so each carries a NEGATIVE CONTROL
	that feeds it a broken input and proves it reports. A check that cannot fail is
	decoration. The BEHAVIOUR half of this seam is not here and does not need to be:
	`tests/layout.spec.luau`, `tests/stack_distribution.spec.luau`,
	`tests/measure_serve.spec.luau` and very nearly every fixture in this repository
	measure a vstack or an hstack through the public surface, and they were green across
	the split.

	▲ THE `ctx` READ SET IS EXPECTED TO GROW ONCE, AND ONLY ONCE. The lever this seam
	was taken for (Plan C, T13 — the per-child memo) adds the memo's key and gate
	fields; this spec is the instrument that makes that growth VISIBLE in a diff rather
	than something a reader has to notice. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")
local srcTree = require("./lib/src_tree")

local SOLVER_PATH = "src/layout/solver.luau"
local MEASURE_PATH = "src/layout/stack_measure.luau"

--[[ COMMENTS ARE NOT CODE, and in this repository that is not a nicety: this module's
	own header names `measure`, `solver.Node` and `Ctx` while explaining what it must
	never reach for, and a scan that counted them would report the exact dependency the
	header promises it does not have. ]]
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

describe("the stack-measure seam: a CLOSED Deps record, read == declared == passed", function()
	local measureSrc = fs.readFile(MEASURE_PATH)
	local solverSrc = fs.readFile(SOLVER_PATH)

	it("the fields the body READS are exactly the fields the type DECLARES", function()
		--[[ THE ONE-WAY TEST ITSELF, as a set comparison rather than a promise. Both
			directions are defects — a field read and not declared would not typecheck,
			and a field declared and not read is the host handing over something this
			module has stopped needing (`solver.luau`'s own note beside
			`COMPOSITION_DEPS`: "a spare field in it is a false statement"). ]]
		local declared: { [string]: boolean } = {}
		local block = string.match(stripComments(measureSrc), "export type Deps = {(.-)\n}")
		assert(block ~= nil, "the Deps type block was not found")
		for name in string.gmatch(block :: string, "\n\t([%a_][%w_]*):") do
			declared[name] = true
		end
		expect(sorted(declared)).toEqual({ "dim", "measure", "shrink", "sides" })
		expect(sorted(fieldsRead(measureSrc, "deps"))).toEqual(sorted(declared))
	end)

	it("...and exactly the fields the solver PASSES, in the one record it builds", function()
		local literal =
			string.match(stripComments(solverSrc), "local STACK_MEASURE_DEPS: stackMeasure%.Deps = {(.-)\n}")
		assert(literal ~= nil, "the solver's STACK_MEASURE_DEPS literal was not found")
		local passed: { [string]: boolean } = {}
		for name in string.gmatch(literal :: string, "\n\t([%a_][%w_]*) =") do
			passed[name] = true
		end
		expect(sorted(passed)).toEqual({ "dim", "measure", "shrink", "sides" })
		--[[ AND `measure` IS BORROWED, NOT REBUILT, and the shrink record TRAVELS. Two
			copies of a forwarder is how the two records end up reading a different
			`measure` after an edit — the failure `FLOW_DEPS = GRID_DEPS` was written to
			prevent, and the property `stack_seam` pins for the arrange half. ]]
		expect(string.find(literal :: string, "measure = GRID_DEPS.measure", 1, true) ~= nil).toBe(true)
		expect(string.find(literal :: string, "shrink = SHRINK_DEPS", 1, true) ~= nil).toBe(true)
	end)

	it("it takes FOUR, not the arrange half's five: `mainDimOf` is not among them", function()
		--[[ THE DISTINCTION THAT IS THE WHOLE REASON THIS RECORD EXISTS. `STACK_DEPS`
			was already in scope and already had every field this branch needs — passing
			it would have been one character of the solver instead of six lines. It is
			refused because a Deps record is a statement about what a module reads: the
			measure branch asks each child's own axis through `dim` and never asks
			`mainDimOf`, so borrowing the wider record would declare a dependency that
			does not exist, and the NEXT reader would have no way to tell which of the
			five this module actually needs. ]]
		expect(string.find(stripComments(measureSrc), "mainDimOf", 1, true)).toBe(nil)
		expect(string.find(stripComments(solverSrc), "mainDimOf = mainDimOf", 1, true) ~= nil).toBe(true)
	end)

	it("there are NO call-site arguments: the call is one expression", function()
		--[[ THE OTHER DIFFERENCE FROM `./stack`, and it is a property rather than a
			style. The arrange half takes `place` and `noteContainment` at the call
			because both are declared BELOW the line its Deps record is built on, so a
			by-value capture there would take the nil global. Nothing this branch calls
			has that problem — `measure` is a forwarder and `shrink` is a leaf module —
			so the record is the whole interface and the call site is one line. ]]
		local declaredDeps = string.match(stripComments(measureSrc), "export type Deps = {(.-)\n}") :: string
		expect(string.find(declaredDeps, "place", 1, true)).toBe(nil)
		expect(
			string.find(
				solverSrc,
				"stackMeasure.contentSize(STACK_MEASURE_DEPS, ctx, node, innerMaxW, innerMaxH, gap, pt, pr, pb, pl)",
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
		local fakeLiteral = "local STACK_MEASURE_DEPS: stackMeasure.Deps = {\n\tmeasure = m,\n\tghost = g,\n}\n"
		local passed: { [string]: boolean } = {}
		local literal = string.match(
			stripComments(fakeLiteral),
			"local STACK_MEASURE_DEPS: stackMeasure%.Deps = {(.-)\n}"
		) :: string
		for name in string.gmatch(literal, "\n\t([%a_][%w_]*) =") do
			passed[name] = true
		end
		expect(sorted(passed)).toEqual({ "ghost", "measure" })
		expect(sorted(fieldsRead("local x = deps.ghost\n", "deps"))).toEqual({ "ghost" })
	end)
end)

describe("the stack-measure seam: what it READS of the solve, and that it writes nothing", function()
	local measureSrc = fs.readFile(MEASURE_PATH)

	it("it reads a CLOSED set of ctx, node and child fields", function()
		--[[ THE SCHEMA IT DEPENDS ON, AS A SET rather than as a promise. Every parameter
			is typed `any` precisely so the module cannot import the solver's own types
			back, which means nothing but this check reports a second `ctx` field being
			reached for. `fitProbe` is the ONE solve-wide fact this branch asks for, and
			the reason is written where it is read: a `ViewThatFits` candidate is judged
			at the size it would LIKE, so the measure-side shrink does not run inside a
			fit probe. A second `ctx` field appearing here is a measure branch that has
			started to depend on the SOLVE rather than on the node and the box. ]]
		expect(sorted(fieldsRead(measureSrc, "ctx"))).toEqual({ "fitProbe" })
		expect(sorted(fieldsRead(measureSrc, "node"))).toEqual({ "children", "kind" })
		expect(sorted(fieldsRead(measureSrc, "child"))).toEqual({ "margin", "shrinkWeight" })
	end)

	it("it WRITES no field of the solver's at all", function()
		--[[ THE READ-vs-WRITE HALF OF THE ONE-WAY TEST, and the half a field-read scan
			cannot see. A block that only reads its host's state can be moved; a block
			that WRITES it has to be trusted to write the same thing at the same moment,
			which is a different and much weaker claim. This branch is stronger than the
			arrange half: it does not even insert a diagnostic — it returns two numbers
			and every table it touches is one it allocated itself. ]]
		local body = stripComments(measureSrc)
		local assigned: { string } = {}
		for recv, field in string.gmatch(body, "([%a_][%w_]*)%.([%a_][%w_]*)%s*[%+%-]?=[^=]") do
			if recv == "ctx" or recv == "node" or recv == "child" or recv == "deps" then
				table.insert(assigned, `{recv}.{field}`)
			end
		end
		expect(assigned).toEqual({})
		local inserts: { string } = {}
		for target in string.gmatch(body, "table%.insert%(%s*([%a_][%w_%.]*)") do
			table.insert(inserts, target)
		end
		expect(inserts).toEqual({})
	end)

	it("NEGATIVE CONTROL: the write scans report an assignment and an insert target", function()
		local fake = "\nctx.measured += 1\nlocal x = ctx.fitProbe\ntable.insert(ctx.diagnostics, d)\n"
		local assigned: { string } = {}
		for recv, field in string.gmatch(stripComments(fake), "([%a_][%w_]*)%.([%a_][%w_]*)%s*[%+%-]?=[^=]") do
			if recv == "ctx" then
				table.insert(assigned, `{recv}.{field}`)
			end
		end
		expect(assigned).toEqual({ "ctx.measured" })
		local inserts: { string } = {}
		for target in string.gmatch(stripComments(fake), "table%.insert%(%s*([%a_][%w_%.]*)") do
			table.insert(inserts, target)
		end
		expect(inserts).toEqual({ "ctx.diagnostics" })
		-- ...and a `==` comparison is not an assignment, which is the one way this scan
		-- could have been silently vacuous
		local none: { string } = {}
		for recv, field in
			string.gmatch(
				stripComments("\nif ctx.fitProbe == false then\n"),
				"([%a_][%w_]*)%.([%a_][%w_]*)%s*[%+%-]?=[^=]"
			)
		do
			table.insert(none, `{recv}.{field}`)
		end
		expect(none).toEqual({})
	end)
end)

describe("the stack-measure seam: one-way, one consumer, and nothing stayed behind", function()
	local measureSrc = fs.readFile(MEASURE_PATH)
	local solverSrc = fs.readFile(SOLVER_PATH)

	it("it requires exactly one leaf, and never the solver", function()
		--[[ `./shrink` IS A LEAF THE SOLVER ALSO REQUIRES, so the graph stays acyclic:
			it takes the record this module is handed rather than reaching back for one.
			The measure branch is the shorter of the two stack halves and it shows here —
			the arrange half needs three requires, this one needs a single pass. ]]
		local requires: { string } = {}
		for path in string.gmatch(stripComments(measureSrc), 'require%("([^"]+)"%)') do
			table.insert(requires, path)
		end
		table.sort(requires)
		expect(requires).toEqual({ "./shrink" })
	end)

	it("it names no solver symbol and imports no solver type", function()
		-- a type import is a require by another name in Luau (`require` first, then
		-- `Module.Type`), so the structural `any` on every parameter is what keeps the
		-- graph acyclic
		local body = stripComments(measureSrc)
		expect(string.find(body, ": Node")).toBe(nil)
		expect(string.find(body, ": Ctx")).toBe(nil)
		expect(string.find(body, "solver%.")).toBe(nil)
		-- ...and the direction that IS allowed is present, so this cannot pass by the
		-- solver having quietly dropped the require
		expect(string.find(solverSrc, 'require("./stack_measure")', 1, true) ~= nil).toBe(true)
	end)

	it("there is exactly ONE consumer of the module in src/", function()
		expect(srcTree.pathsMatching('require%("[^"]*/stack_measure"%)')).toEqual({ SOLVER_PATH })
	end)

	it("the module exports exactly `contentSize`, and the solver calls that one function", function()
		local exported: { [string]: boolean } = {}
		for name in string.gmatch(stripComments(measureSrc), "function stack_measure%.([%a_][%w_]*)") do
			exported[name] = true
		end
		expect(sorted(exported)).toEqual({ "contentSize" })
		local calls = 0
		for _ in string.gmatch(stripComments(solverSrc), "stackMeasure%.contentSize%(") do
			calls += 1
		end
		expect(calls).toBe(1)
	end)

	it("the solver kept no copy of the branch", function()
		--[[ THE FAILURE THIS REPOSITORY HAS ALREADY PAID FOR ONCE: a block "moved" by
			copying, leaving the host's version live and the two drifting. Each string
			below is a distinctive line of the branch that left. Note what this does to
			`stack_seam`'s own list: `local isH = node.kind == "hstack"` and
			`fillWeightSum` were NEAR-MISSES there — deliberately not on its
			"nothing stayed behind" list, because the MEASURE-side pass still held them.
			It does not any more, so those two moved from that spec's positives to this
			spec's negatives, and `stack_seam` was edited in this commit to say so. ]]
		local body = stripComments(solverSrc)
		expect(string.find(body, 'local isH = node.kind == "hstack"', 1, true)).toBe(nil)
		expect(string.find(body, "fillWeightSum", 1, true)).toBe(nil)
		expect(string.find(body, "local mainLimit", 1, true)).toBe(nil)
		expect(string.find(body, "crossOf", 1, true)).toBe(nil)
		expect(string.find(body, "marginMain", 1, true)).toBe(nil)
		--[[ ...AND THE POSITIVES, so this case cannot pass by the file having been
			emptied. The WRAP branch's `local isH = node.kind == "hwrap"` is one
			character different from the line above and stayed behind, which is the
			near-miss that makes this list a real one; `flowLib.plan(` is the wrap
			measure branch this extraction had to stop at. ]]
		expect(string.find(body, 'local isH = node.kind == "hwrap"', 1, true) ~= nil).toBe(true)
		expect(string.find(body, "flowLib.plan(", 1, true) ~= nil).toBe(true)
	end)

	it("NEGATIVE CONTROL: the require, export and leftover scans all report", function()
		local fakeRequires: { string } = {}
		for path in string.gmatch(stripComments('local s = require("./solver")\n'), 'require%("([^"]+)"%)') do
			table.insert(fakeRequires, path)
		end
		expect(fakeRequires).toEqual({ "./solver" })
		local fake = "function stack_measure.contentSize(a)\nend\nfunction stack_measure.extra()\nend\n"
		local exported: { [string]: boolean } = {}
		for name in string.gmatch(stripComments(fake), "function stack_measure%.([%a_][%w_]*)") do
			exported[name] = true
		end
		expect(sorted(exported)).toEqual({ "contentSize", "extra" })
		expect(string.find(stripComments("\tlocal mainLimit = 1\n"), "local mainLimit", 1, true) ~= nil).toBe(true)
		expect(string.find(stripComments("local x: Node = node\n"), ": Node") ~= nil).toBe(true)
	end)
end)

describe("the stack-measure seam: no module-level mutable state", function()
	it("nothing declared at module level is ever reassigned", function()
		--[[ A MODULE-LEVEL MUTABLE IS A SECOND SOLVE'S STATE LEAKING INTO THE FIRST, and
			it is the one way a pure-looking measure branch stops being pure — which
			matters more here than anywhere: this function's answers are about to be
			CACHED by the lever this seam was taken for, and a cache above a module that
			holds state is two caches. The scan is deliberately crude — every
			`local <name>` at column zero, then every bare `<name> =` at column zero. ]]
		local body = stripComments(fs.readFile(MEASURE_PATH))
		local declared: { [string]: boolean } = {}
		for name in string.gmatch(body, "\nlocal ([%a_][%w_]*)") do
			declared[name] = true
		end
		expect(sorted(declared)).toEqual({ "shrinkLib", "stack_measure" })
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
