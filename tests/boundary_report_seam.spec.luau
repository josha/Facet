--!strict
--[[ THE BOUNDARY-REPORT SEAM, MECHANISED — what keeps
	`layout/boundary_report.luau` one-way.

	WHY A SPEC AND NOT A COMMENT. `tools/lune/verify/data/source-cap-ledger.md` records
	the rule every extraction in this repository is judged by: a block may leave a
	file only if it reads no mutable upvalue of its host, because otherwise the move
	creates a require BACK and the two files become one file with a slash in the
	middle. This is the cheapest seam the solver has ever had — the report reads no
	`ctx`, no helper, no upvalue and not even the solver's `Node` type — so what is
	worth mechanising is exactly that emptiness, which is a claim that decays the
	moment someone reaches back across it for one convenient helper.

	  ZERO DEPS      the module requires nothing and reads no `ctx`/`deps` at all
	  ONE CONSUMER   `src/layout/solver.luau`, by a walk of the whole tree
	  ONE-WAY        it names no solver symbol and no solver type
	  EXPORTED == BOUND  its one export is the one the solver re-exports, and the
	                 solver keeps NO copy of what left
	  NO STATE       no module-level local is ever reassigned
	  BEHAVIOUR      the public name still answers, and still blames the CALLER's
	                 line for a solve that never asked for the analysis

	Each source rule is a pure function of a string, so each carries a NEGATIVE
	CONTROL that feeds it a broken input and proves it reports. A check that cannot
	fail is decoration.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")
local srcTree = require("./lib/src_tree")
local solver = require("../src/layout/solver")
local boundary_report = require("../src/layout/boundary_report")

local SOLVER_PATH = "src/layout/solver.luau"
local REPORT_PATH = "src/layout/boundary_report.luau"

--[[ COMMENTS ARE NOT CODE, and in this repository that is not a nicety: this
	module's own header names `solver.Node` and `solver.boundaryReport` while
	explaining what it must never reach for, and a scan that counted them would
	report the exact dependency the header is promising it does not have. ]]
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

describe("the boundary-report seam: ZERO deps, one consumer, one-way", function()
	local reportSrc = fs.readFile(REPORT_PATH)
	local solverSrc = fs.readFile(SOLVER_PATH)

	it("the module requires NOTHING — it is a leaf, which is what made it free to take", function()
		--[[ THE WHOLE ONE-WAY ARGUMENT IN ONE LINE. `./shrink`, `./grid` and
			`./flow` each left the solver holding a `Deps` record; this one left
			holding nothing at all, and a first `require` here is the moment that
			stops being true — including the one that would create the cycle. ]]
		local requires: { string } = {}
		for path in string.gmatch(stripComments(reportSrc), 'require%("([^"]+)"%)') do
			table.insert(requires, path)
		end
		expect(requires).toEqual({})
		-- ...and no `ctx`/`deps` surface either: the two arguments ARE the input
		expect(sorted(fieldsRead(reportSrc, "ctx"))).toEqual({})
		expect(sorted(fieldsRead(reportSrc, "deps"))).toEqual({})
	end)

	it("it reads exactly two fields of a result and two of a node", function()
		--[[ THE SCHEMA IT DEPENDS ON, AS A SET rather than as a promise. `result` is
			typed `any` here precisely so the module cannot import the solver's own
			type back, which means nothing but this check reports a third field being
			reached for — the first step of a seam growing back into its host. ]]
		expect(sorted(fieldsRead(reportSrc, "result"))).toEqual({ "work" })
		expect(sorted(fieldsRead(reportSrc, "node"))).toEqual({ "children", "id" })
	end)

	it("there is exactly ONE consumer of the module in src/", function()
		expect(srcTree.pathsMatching('require%("[^"]*boundary_report"%)')).toEqual({ SOLVER_PATH })
	end)

	it("the module names no solver symbol and no solver type", function()
		-- a type import is a require by another name in Luau (`require` first, then
		-- `Module.Type`), so the structural `any` on both parameters is what keeps
		-- the graph acyclic
		local body = stripComments(reportSrc)
		expect(string.find(body, ": Node")).toBe(nil)
		expect(string.find(body, ": Ctx")).toBe(nil)
		--[[ EXACTLY ONE `solver.` SURVIVES THE MOVE and it is a STRING: the guard's
			message names the public entry, because `solver.boundaryReport` is what the
			caller typed and `boundary_report.report` is not. Any second mention is a
			reach back across the seam, which is the whole thing this file is for. ]]
		local mentions = 0
		for _ in string.gmatch(body, "solver%.") do
			mentions += 1
		end
		expect(mentions).toBe(1)
		expect(string.find(body, 'error("solver.boundaryReport:', 1, true) ~= nil).toBe(true)
		-- ...and the direction that IS allowed is present, so this pair cannot both
		-- pass by the solver having quietly dropped the require
		expect(string.find(solverSrc, 'require("./boundary_report")', 1, true) ~= nil).toBe(true)
	end)

	it("NEGATIVE CONTROL: each scan reads what it claims to, and reports a broken input", function()
		expect(sorted(fieldsRead("local a = result.work\nlocal b = result.rects\n", "result"))).toEqual({
			"rects",
			"work",
		})
		-- a name inside a comment is NOT a read, and this module's header has live
		-- instances of that trap
		expect(sorted(fieldsRead("--[[ result.ghost ]]\nlocal x = result.work\n", "result"))).toEqual({ "work" })
		expect(sorted(fieldsRead("\t-- result.ghost\n\tlocal x = result.work\n", "result"))).toEqual({ "work" })
		local fakeRequires: { string } = {}
		for path in string.gmatch(stripComments('local s = require("./solver")\n'), 'require%("([^"]+)"%)') do
			table.insert(fakeRequires, path)
		end
		expect(fakeRequires).toEqual({ "./solver" })
	end)
end)

describe("the boundary-report seam: EXPORTED == BOUND, and nothing stayed behind", function()
	local reportSrc = fs.readFile(REPORT_PATH)
	local solverSrc = fs.readFile(SOLVER_PATH)

	it("the module exports exactly `report`, and the solver re-exports that one function", function()
		local exported: { [string]: boolean } = {}
		for name in string.gmatch(stripComments(reportSrc), "function boundary_report%.([%a_][%w_]*)") do
			exported[name] = true
		end
		expect(sorted(exported)).toEqual({ "report" })
		expect(string.find(solverSrc, "solver.boundaryReport = boundaryReportLib.report", 1, true) ~= nil).toBe(true)
		-- the public name and the module's own name are the SAME function object:
		-- a second copy is how a re-export starts answering an older version
		expect(solver.boundaryReport == boundary_report.report).toBe(true)
	end)

	it("the solver keeps no copy of what left", function()
		--[[ THE FAILURE THIS REPOSITORY HAS ALREADY PAID FOR ONCE: a block "moved"
			by copying, leaving the host's version live and the two drifting. The
			solver may name the report — it re-exports it and points at it — but it
			may not declare it again. ]]
		local body = stripComments(solverSrc)
		expect(string.find(body, "function solver%.boundaryReport%(")).toBe(nil)
		expect(string.find(body, "meanShareOfTree")).toBe(nil)
		expect(string.find(body, "absorbingNodes")).toBe(nil)
	end)

	it("NEGATIVE CONTROL: the export scan and the leftover scan both report", function()
		local fake = "function boundary_report.report(a, b)\nend\nfunction boundary_report.extra()\nend\n"
		local exported: { [string]: boolean } = {}
		for name in string.gmatch(stripComments(fake), "function boundary_report%.([%a_][%w_]*)") do
			exported[name] = true
		end
		expect(sorted(exported)).toEqual({ "extra", "report" })
		expect(
			string.find(
				stripComments("function solver.boundaryReport(root, result)\n"),
				"function solver%.boundaryReport%("
			) ~= nil
		).toBe(true)
	end)
end)

describe("the boundary-report seam: no module-level mutable state", function()
	local reportSrc = fs.readFile(REPORT_PATH)

	-- every module-level `local <name>` (column 0), and every module-level
	-- reassignment of one. A local assigned twice is an upvalue two callers share.
	local function moduleLocals(source: string): { [string]: boolean }
		local out: { [string]: boolean } = {}
		for name in string.gmatch("\n" .. stripComments(source), "\nlocal ([%a_][%w_]*)") do
			out[name] = true
		end
		return out
	end

	local function moduleReassignments(source: string, names: { [string]: boolean }): { string }
		local body = stripComments(source)
		local out: { string } = {}
		for name in names do
			if string.find(body, `\n{name}%s*=[^=]`) ~= nil then
				table.insert(out, name)
			end
		end
		table.sort(out)
		return out
	end

	it("no module-level local is ever reassigned — two calls cannot see different helpers", function()
		expect(moduleReassignments(reportSrc, moduleLocals(reportSrc))).toEqual({})
		expect(#sorted(moduleLocals(reportSrc)) > 0).toBe(true)
	end)

	it("NEGATIVE CONTROL: the reassignment scan sees a late assignment and ignores a local one", function()
		local text = "local alpha\nlocal beta = 1\nlocal function f()\n\tbeta = 2\nend\nalpha = 3\n"
		local names = moduleLocals(text)
		expect(names.alpha).toBe(true)
		expect(names.beta).toBe(true)
		expect(moduleReassignments(text, names)).toEqual({ "alpha" })
	end)
end)

describe("the boundary-report seam: the behaviour that crossed is the behaviour that arrived", function()
	--[[ A SPLIT IS A BEHAVIOUR CLAIM, so the seam is driven and not only scanned.
		One tree, solved with the analysis armed, read through the PUBLIC name. ]]
	local function tree(): any
		return {
			kind = "vstack",
			id = "/root",
			width = { type = "fixed", px = 200 },
			height = { type = "fixed", px = 200 },
			children = {
				{
					kind = "vstack",
					id = "/root/a",
					children = {
						{
							kind = "box",
							id = "/root/a/leaf",
							width = { type = "fill" },
							height = { type = "fixed", px = 10 },
						},
					},
				},
				{ kind = "box", id = "/root/b", width = { type = "fill" }, height = { type = "fixed", px = 10 } },
			},
		}
	end

	it("the report still answers, and the numbers describe the tree it was given", function()
		local root = tree()
		local result = solver.solve(root, { w = 200, h = 200 }, { analyzeBoundaries = true })
		local report = solver.boundaryReport(root, result)
		-- four nodes: root, a, a/leaf, b
		expect(report.nodes).toBe(4)
		-- the root is fixed on both axes, so it absorbs — every node's answer is
		-- bounded by the tree and the root's own answer is the whole of it
		expect(report.absorbingNodes >= 1).toBe(true)
		expect(report.todayAffected).toBe(4)
		expect(report.worstAffected <= 4).toBe(true)
		expect(report.medianAffected <= report.worstAffected).toBe(true)
		expect(report.meanShareOfTree > 0 and report.meanShareOfTree <= 1).toBe(true)
	end)

	it("a solve that never asked for the analysis still raises, and still blames the caller", function()
		local root = tree()
		local result = solver.solve(root, { w = 200, h = 200 }, {})
		local ok, err = pcall(function()
			return solver.boundaryReport(root, result)
		end)
		expect(ok).toBe(false)
		-- the message keeps the PUBLIC name (the caller never typed
		-- `boundary_report.report`), and level 2 puts the blame on this file's line
		-- rather than on the module's
		expect(string.find(tostring(err), "solver.boundaryReport", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "analyzeBoundaries", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "/src/layout/boundary_report:", 1, true) == nil).toBe(true)
		-- ...and it blames THIS file, which is the positive half: a message that
		-- merely fails to name the module could be blaming anything
		expect(string.find(tostring(err), "boundary_report_seam.spec:", 1, true) ~= nil).toBe(true)
	end)
end)
