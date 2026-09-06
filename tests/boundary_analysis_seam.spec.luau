--!strict
--[[ THE BOUNDARY-ANALYSIS SEAM, MECHANISED — what keeps
	`src/render/boundary_analysis.luau` one-way, and what its one export promises.

	`controller.analyzeBoundaries()`'s body left `render/renderer.luau` on 2026-09-06
	(ruling C-3, fix round 2) for the Source-write headroom that fix needed, in its own
	behaviour-neutral commit — the order `tools/lune/verify/data/source-cap-ledger.md`
	requires. The seam claim is the strong kind: ONE argument crosses it, the record
	the renderer already built for this call and never reads back, so there is no Deps
	table, no upvalue of the host and no state.

	Each source rule is a pure function of a string, so each carries a NEGATIVE CONTROL
	that feeds it a broken input and proves it reports. A check that cannot fail is
	decoration.

	THE BEHAVIOUR HALF IS DRIVEN, not grepped, and it is driven TWICE: once against the
	expression the renderer used to hold — term for term, on a tree this file builds —
	and once against the property that expression existed for, which is that a
	DIAGNOSTIC may not mutate the record the next real solve is going to run on. The
	live consumers (`tests/measure_reuse.spec.luau`'s "the boundary analysis is a FULL
	solve" and `tests/structural_scope.spec.luau`'s absorbing-count drive) call the
	public name through a mounted controller and are the pins that catch a regression
	in what it MEANS; these are the pins that catch a regression in where it lives. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")

local boundary_analysis = require("../src/render/boundary_analysis")
local solver = require("../src/layout/solver")

local MODULE_PATH = "src/render/boundary_analysis.luau"
local RENDERER_PATH = "src/render/renderer.luau"

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

local function requiresIn(source: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for path in string.gmatch(stripComments(source), 'require%("([^"]*)"%)') do
		out[path] = true
	end
	return out
end

--[[ the shape `render/layout_node.build` hands the solver, written out by hand for
	the reason `tests/boundary_report_seam.spec.luau` writes one out: a seam test that
	needs a renderer to produce its input is testing the renderer. ]]
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

local function describeReport(report: any): string
	return `nodes={report.nodes} absorbing={report.absorbingNodes} today={report.todayAffected} `
		.. `worst={report.worstAffected} median={report.medianAffected}`
end

describe("the boundary-analysis seam: one argument, one export, no state", function()
	it("the module requires the SOLVER and nothing else — nothing under `render/`", function()
		local source = fs.readFile(MODULE_PATH)
		--[[ a require back into `render/` is the failure this rule exists for: it would
			make the two files one file with a slash in the middle. The solver is a
			require the renderer already makes and a module that reaches nothing here. ]]
		expect(sorted(requiresIn(source))).toEqual({ "../layout/solver" })
		-- NEGATIVE CONTROL: the scan really does see a second require
		expect(sorted(requiresIn('local a = require("../layout/solver")\nlocal b = require("./renderer")'))).toEqual({
			"../layout/solver",
			"./renderer",
		})
	end)

	it("no module-level mutable state: nothing here is remembered between calls", function()
		--[[ a `local lastReport = nil` up here would be a cache shared by every surface
			on the client, and a diagnostic that answers about a tree it was not asked
			about is worse than no diagnostic. The two declarations are the require and
			the module table, and neither is ever reassigned. ]]
		local source = stripComments(fs.readFile(MODULE_PATH))
		local head = string.match(source, "^(.-)\nfunction boundary_analysis%.report")
		assert(head ~= nil, "no `function boundary_analysis.report` to split on")
		local decls: { string } = {}
		for line in string.gmatch(head :: string, "\n([^\n]*)") do
			local trimmed = string.match(line, "^%s*(.-)%s*$") :: string
			if string.match(trimmed, "^local ") ~= nil then
				table.insert(decls, trimmed)
			end
		end
		table.sort(decls)
		expect(decls).toEqual({ "local boundary_analysis = {}", 'local solver = require("../layout/solver")' })
		-- NEGATIVE CONTROL: the scan really does see a third declaration
		local fake = "local boundary_analysis = {}\nlocal cache = {}\nfunction boundary_analysis.report()"
		local fakeHead = string.match(stripComments(fake), "^(.-)\nfunction boundary_analysis%.report") :: string
		local found = 0
		for line in string.gmatch(fakeHead, "\n([^\n]*)") do
			if string.match(line, "^%s*local ") ~= nil then
				found += 1
			end
		end
		expect(`decls seen:{found}`).toBe("decls seen:2")
	end)

	it("the export set is exactly `report`, and it names no renderer symbol", function()
		local names: { string } = {}
		for name in boundary_analysis :: any do
			table.insert(names, name)
		end
		table.sort(names)
		expect(names).toEqual({ "report" })
		--[[ ONE-WAY IN THE OTHER DIRECTION TOO: the block reached five renderer locals
			before it moved, and every one of them had to become part of the one record
			the caller passes or stay behind. A name reappearing here is the seam
			decaying back into a shared scope. ]]
		local source = stripComments(fs.readFile(MODULE_PATH))
		local reached: { string } = {}
		for _, name in { "lastSolveInputs", "controller", "adapter", "handles", "stats", "root%." } do
			if string.find(source, name) ~= nil then
				table.insert(reached, (string.gsub(name, "%%", "")))
			end
		end
		expect(reached).toEqual({})
		-- NEGATIVE CONTROL: the same scan over the renderer, which of course has them
		expect(string.find(stripComments(fs.readFile(RENDERER_PATH)), "lastSolveInputs") ~= nil).toBe(true)
	end)

	it("the renderer holds the record and calls this once: one write, one read", function()
		local source = stripComments(fs.readFile(RENDERER_PATH))
		local calls = 0
		for _ in string.gmatch(source, "boundary_analysis%.report%(") do
			calls += 1
		end
		--[[ `lastSolveInputs` is written by the solve and read by this call, and by
			nothing else — which is the whole reason the argument could be ONE record
			instead of a Deps table. A third mention means the renderer started reading
			its own diagnostic input back, and the seam is no longer one-way. ]]
		local mentions = 0
		for _ in string.gmatch(source, "lastSolveInputs") do
			mentions += 1
		end
		expect(`calls={calls} lastSolveInputs mentions={mentions}`).toBe("calls=1 lastSolveInputs mentions=3")
	end)

	it("BEHAVIOUR: it answers what the renderer's own expression answered, term for term", function()
		--[[ THE NEUTRALITY CLAIM, DRIVEN. The left side is this module; the right side
			is the expression the renderer held before the move, typed out here. They are
			compared on the report the public name returns, not on the source. ]]
		local moved = boundary_analysis.report({ layoutRoot = tree(), viewport = { w = 200, h = 200 }, opts = {} })
		local root = tree()
		local opts = { analyzeBoundaries = true, reuse = nil, measures = nil }
		local asItWas = solver.boundaryReport(root, solver.solve(root, { w = 200, h = 200 }, opts))
		expect(describeReport(moved)).toBe(describeReport(asItWas))
		-- and it really did describe THIS tree: four nodes, three of them absorbing
		expect(describeReport(moved)).toBe("nodes=4 absorbing=3 today=4 worst=4 median=1")
	end)

	it("BEHAVIOUR: the CALLER's live solve options are never mutated", function()
		--[[ THE CLONE IS THE PROPERTY, not a convenience: `inputs.opts` is the record
			the NEXT real solve is going to run on, so an analysis that set the flag or
			cleared the reuse fields ON IT would make a diagnostic change what ships.
			Both fields are read back after the call, still exactly as handed in. ]]
		local reuse = {
			dirtyContains = function()
				return true
			end,
		}
		local measures = { poison = true }
		local opts: any = { reuse = reuse, measures = measures }
		boundary_analysis.report({ layoutRoot = tree(), viewport = { w = 200, h = 200 }, opts = opts })
		expect(
			`flag={tostring(opts.analyzeBoundaries)} reuse={tostring(opts.reuse == reuse)} `
				.. `measures={tostring(opts.measures == measures)}`
		).toBe("flag=nil reuse=true measures=true")
	end)

	it("BEHAVIOUR: a surface that has never solved reports nothing rather than raising", function()
		-- the `lastSolveInputs == nil` arm, which is what `controller.analyzeBoundaries`
		-- answers before the first `initialRender`
		expect(boundary_analysis.report(nil)).toBe(nil)
	end)
end)
