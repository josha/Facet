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

	  ZERO DEPS      it takes no `deps` record, and requires only LEAVES
	  ONE CONSUMER   `src/layout/solver.luau`, from inside `arrange`
	  ONE-WAY        it names no solver symbol and imports no solver type
	  A CLOSED INPUT the exact `ctx`, `node`, `child` and `rect` fields it reads, as
	                 a SET — a third `ctx` field reached for is the first step of a
	                 seam growing back
	  A CLOSED OUTPUT `table.insert` into `ctx.diagnostics` and nothing else
	  NOTHING LEFT   the solver kept no copy of the five messages
	  NO STATE       no module-level local is ever reassigned

	THE CONTAINMENT CHECK JOINED IT ON 2026-09-04 (Plan C, T3 fix round 1), for the
	same reason the four box reports left: `layout/solver.luau` stood 55 characters
	inside the Facet-parity campaign's 197,500 STOP band with Plan C's T5 due to
	edit it next, and the solver's own ledger row had named this block as the
	candidate. It belongs here on its merits too — it is the same shape as the other
	four (gated on `ctx.hiddenDepth == 0`, output only `table.insert` into
	`ctx.diagnostics`), it simply reports about a CHILD's box rather than the node's
	own. It brought TWO requires with it (`./placement_audit`, `./measure_facts`),
	which is why the zero-deps rule below is now "no deps record, leaves only": both
	are modules the solver itself imports and neither imports anything back, so this
	file is still a leaf and no cycle can form.

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

	it("the module takes NO deps record, and requires only leaves", function()
		--[[ IT REQUIRED NOTHING AT ALL UNTIL 2026-09-04, and the two that arrived with
			the containment report are named here rather than counted. Both are modules
			`solver.luau` itself imports and neither imports anything back — each
			re-declares the node schema as `any` for exactly that reason and says so in
			its own header — so this file is still a LEAF and the require graph is still
			acyclic. A third require, or one that is not a leaf, is a seam growing back.

			The `deps` half is unchanged and is the half the ledger judges: no record
			crosses this boundary, so there is no channel for a solver forward local to
			arrive through. ]]
		local requires: { string } = {}
		for path in string.gmatch(stripComments(reportsSrc), 'require%("([^"]+)"%)') do
			table.insert(requires, path)
		end
		table.sort(requires)
		expect(requires).toEqual({ "./measure_facts", "./placement_audit" })
		expect(sorted(fieldsRead(reportsSrc, "deps"))).toEqual({})
		-- ...and neither leaf requires this module or the solver back
		for _, leaf in { "src/layout/placement_audit.luau", "src/layout/measure_facts.luau" } do
			local body = stripComments(fs.readFile(leaf))
			expect(`{leaf} -> solver={string.find(body, 'require("./solver")', 1, true) ~= nil}`).toBe(
				`{leaf} -> solver=false`
			)
			expect(`{leaf} -> reports={string.find(body, "arrange_reports", 1, true) ~= nil}`).toBe(
				`{leaf} -> reports=false`
			)
		end
	end)

	it("it reads a CLOSED set of ctx, node, child and rect fields", function()
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
		expect(sorted(fieldsRead(reportsSrc, "rect"))).toEqual({ "h", "w", "x", "y" })
		-- `child` arrived with the containment report and is READ NOWHERE: it is
		-- handed straight to `placement_audit.containment`, which is what keeps this
		-- module ignorant of the solver's node schema even for the node it reports on
		expect(sorted(fieldsRead(reportsSrc, "child"))).toEqual({})
	end)

	it("it WRITES nothing of the solver's but `ctx.diagnostics`, and only by insert", function()
		--[[ THE HALF A READ-SET SCAN CANNOT SEE, and the half that says this boundary
			is a REPORT CHANNEL rather than shared mutable state: a module that only READ
			a closed set could still assign into it. Every output of every function here
			is one `table.insert` into the list the caller already writes. ]]
		local function writesInto(source: string, receiver: string): number
			local n = 0
			for _ in string.gmatch(stripComments(source), receiver .. "%.[%a_][%w_]*%s*=[^=]") do
				n += 1
			end
			for _ in string.gmatch(stripComments(source), receiver .. "%[[^%]]*%]%s*=[^=]") do
				n += 1
			end
			return n
		end
		expect(writesInto(reportsSrc, "ctx")).toBe(0)
		expect(writesInto(reportsSrc, "node")).toBe(0)
		expect(writesInto(reportsSrc, "child")).toBe(0)
		local targets: { [string]: boolean } = {}
		for target in string.gmatch(stripComments(reportsSrc), "table%.insert%(([%a_][%w_%.]*)") do
			targets[target] = true
		end
		expect(sorted(targets)).toEqual({ "ctx.diagnostics" })
		-- NEGATIVE CONTROL: both scans report a broken input
		expect(writesInto("\n\tctx.hiddenDepth = 0\n", "ctx")).toBe(1)
		expect(writesInto("\n\tctx[node.id] = {}\n", "ctx")).toBe(1)
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

	it("the module exports exactly `box` and `containment`, and the solver calls both", function()
		local exported: { [string]: boolean } = {}
		for name in string.gmatch(stripComments(reportsSrc), "function arrange_reports%.([%a_][%w_]*)") do
			exported[name] = true
		end
		expect(sorted(exported)).toEqual({ "box", "containment" })
		expect(
			string.find(solverSrc, "arrange_reports.box(ctx, node, rect, innerW, innerH, pt, pr, pb, pl)", 1, true)
				~= nil
		).toBe(true)
		expect(string.find(solverSrc, "local noteContainment = arrange_reports.containment", 1, true) ~= nil).toBe(true)
		--[[ ...AND THE CALL SITE DID NOT MOVE, char for char. `stack.luau` takes
			`place` and `noteContainment` as CALL-SITE arguments rather than `Deps`
			fields, and `tests/stack_seam.spec.luau` pins this exact string from the
			other side — so a future edit cannot satisfy one pin by loosening the other. ]]
		expect(
			string.find(
				solverSrc,
				"stackLib.arrange(STACK_DEPS, ctx, node, innerX, innerY, innerW, innerH, gap, arrange, noteContainment, out)",
				1,
				true
			) ~= nil
		).toBe(true)
	end)

	it("the solver kept no copy of the five messages", function()
		--[[ THE FAILURE THIS REPOSITORY HAS ALREADY PAID FOR ONCE: a block "moved" by
			copying, leaving the host's version live and the two drifting. Each string
			below is a distinctive fragment of one of the four reports, and none of them
			may appear in the solver any more. ]]
		local body = stripComments(solverSrc)
		expect(string.find(body, "content box collapses to 0px", 1, true)).toBe(nil)
		expect(string.find(body, "chrome contentInsets could not be spent", 1, true)).toBe(nil)
		expect(string.find(body, "icon floor wanted", 1, true)).toBe(nil)
		expect(string.find(body, "node.inertPlacement", 1, true)).toBe(nil)
		-- ...and the fifth, which arrived on 2026-09-04: definition gone, one bind left
		expect(string.find(body, "local function noteContainment(", 1, true)).toBe(nil)
		expect(string.find(body, "placementAudit.containment(", 1, true)).toBe(nil)
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

describe("the arrange-reports seam: the moved report still is the report", function()
	it("BEHAVIOUR: containment fires on an escaping child, refuses a contained one, and is gated", function()
		--[[ EVERY CASE ABOVE IS A SOURCE RULE, so one behavioural case anchors them:
			the function this move renamed is the function that runs. The full treatment
			is `tests/containment_diagnostic.spec.luau`, which drives it through a real
			solve and did not change across the move; this drives the moved export
			DIRECTLY, which is the half a whole-solve test cannot isolate.

			The three arms are the block's own three exits: a child inside the content
			box (the common path, which never reaches `axisAbsorbs` and never
			allocates), a child outside it under a parent that cannot grow, and the
			`hiddenDepth` gate every report in this file shares — a losing ViewThatFits
			candidate does not shout. ]]
		local reports = require("../src/layout/arrange_reports") :: any
		local parent = {
			id = "/S/Row",
			kind = "hstack",
			width = { type = "fixed", px = 100 },
			height = { type = "fixed", px = 40 },
		}
		local child = { id = "/S/Row/Kid", kind = "box" }

		local contained = { hiddenDepth = 0, diagnostics = {} }
		reports.containment(contained, parent, child, { x = 0, y = 4, w = 100, h = 20 }, 0, 0, 100, 40, false)
		expect(`contained findings={#contained.diagnostics}`).toBe("contained findings=0")

		local escaping = { hiddenDepth = 0, diagnostics = {} }
		reports.containment(escaping, parent, child, { x = 0, y = 30, w = 100, h = 40 }, 0, 0, 100, 40, false)
		expect(`escaping findings>0={#escaping.diagnostics > 0}`).toBe("escaping findings>0=true")
		expect(`filed about the child={escaping.diagnostics[1].node}`).toBe("filed about the child=/S/Row/Kid")

		local hidden = { hiddenDepth = 1, diagnostics = {} }
		reports.containment(hidden, parent, child, { x = 0, y = 30, w = 100, h = 40 }, 0, 0, 100, 40, false)
		expect(`hidden findings={#hidden.diagnostics}`).toBe("hidden findings=0")
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
		--[[ FOUR MORE ARRIVED WITH THE CONTAINMENT REPORT on 2026-09-04, and every one
			of them is a CONSTANT: two module requires and the two pure readers bound off
			`measure_facts` the way `solver.luau` binds them, for the same reason (an
			extra table index per call on a path this repository has already paid a bench
			regression for). None is ever written, which the reassignment scan below is
			what actually says. ]]
		expect(sorted(declared)).toEqual({
			"arrange_reports",
			"axisAbsorbs",
			"dim",
			"measureFacts",
			"placementAudit",
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
