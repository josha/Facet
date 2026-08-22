--!strict
--[[ THE MEASURE-FACTS SEAM, MECHANISED — what keeps `layout/measure_facts.luau` one-way.

	WHY A SPEC AND NOT A COMMENT. `docs/handoff/SOURCE_CAP_LEDGER.md` records the
	rule every extraction in this repository is judged by: a block may leave a
	file only if it reads no mutable upvalue of its host, because otherwise the
	move creates a require BACK and the two files become one file with a slash in
	the middle. `table_rows_seam.spec` mechanised that for a parameter object.
	THIS SEAM HAS NO PARAMETER OBJECT: everything the module needs arrives on the
	solve's own `ctx`, which is a ~40-field record it does not own and must never
	learn. So the property is the same three set comparisons, taken one layer in:

	  READ      every `ctx.<field>` the module reads, comments stripped
	  DECLARED  every field its `MeasureCtx` type names
	  HOSTED    every field the solver's own `type Ctx` block still declares

	all three equal (READ == DECLARED, DECLARED subset of HOSTED), plus the
	shared WRITE surface pinned to exactly four names, the module's EXPORTS
	compared against the solver's binding block in both directions, the ONE
	consumer, the one-way require, and — the property no parameter object needed —
	that the module holds NO module-level mutable state, so two solves can never
	see different helpers.

	Each rule is a pure function of a string, so each carries a NEGATIVE CONTROL
	that feeds it a broken input and proves it reports. A check that cannot fail
	is decoration (`docs/lessons/a-red-check-cannot-report-the-next-defect.md`).
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")

local SOLVER_PATH = "src/layout/solver.luau"
local FACTS_PATH = "src/layout/measure_facts.luau"

--[[ COMMENTS ARE NOT CODE, and in this repository that is not a nicety: the
	solver's reasoning blocks name `ctx.compact` and `ctx.compositions` while
	discussing fields the extracted code never touches, and one of those blocks
	travelled with `memoPlan`. A scan that counted them would declare two fields
	this module must never learn. ]]
local function stripComments(source: string): string
	local out = string.gsub("\n" .. source, "%-%-%[%[.-%]%]", " ")
	out = string.gsub(out, "\n[ \t]*%-%-[^\n]*", "\n")
	return out
end

local function ctxFieldsRead(source: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for key in string.gmatch(stripComments(source), "ctx%.([%a_][%w_]*)") do
		out[key] = true
	end
	return out
end

-- every field a `type <name> = { … }` block declares. Comment lines inside the
-- block start with `--` and so never match the `<name>:` shape, which is what
-- lets a type carry its reasoning without confusing this scan.
local function typeFields(source: string, typeName: string): { [string]: boolean }
	local block = string.match(source, "type " .. typeName .. " = {\n(.-)\n}")
	assert(block ~= nil, `no 'type {typeName}' block to read`)
	local out: { [string]: boolean } = {}
	for key in string.gmatch("\n" .. (block :: string), "\n\t([%a_][%w_]*):") do
		out[key] = true
	end
	return out
end

-- the ctx fields the module WRITES: a field it assigns, or a key it stores into
-- one. Both spellings appear below (`ctx.fitCuts += 1`, `ctx.textFacts[id] = …`).
local function ctxFieldsWritten(source: string): { [string]: boolean }
	local body = stripComments(source)
	local out: { [string]: boolean } = {}
	for key in string.gmatch(body, "\n[ \t]*ctx%.([%a_][%w_]*)%s*=[^=]") do
		out[key] = true
	end
	for key in string.gmatch(body, "\n[ \t]*ctx%.([%a_][%w_]*)%s*%+=") do
		out[key] = true
	end
	for key in string.gmatch(body, "\n[ \t]*ctx%.([%a_][%w_]*)%[[^%]]+%]%s*=[^=]") do
		out[key] = true
	end
	return out
end

-- every name the module hangs off its own table
local function exportsOf(facts: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for key in string.gmatch(stripComments(facts), "\nmeasure_facts%.([%a_][%w_]*) =") do
		out[key] = true
	end
	return out
end

-- every name the solver binds off the module as a VALUE. The type re-export
-- (`export type Dim = measureFacts.Dim`) is asserted separately: a type is not a
-- runtime export and cannot be compared against the module table.
local function boundOf(solver: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for key in string.gmatch(stripComments(solver), "\nlocal [%a_][%w_]* = measureFacts%.([%a_][%w_]*)") do
		out[key] = true
	end
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

local function missingFrom(a: { [string]: boolean }, b: { [string]: boolean }): { string }
	local out: { string } = {}
	for key in a do
		if not b[key] then
			table.insert(out, key)
		end
	end
	table.sort(out)
	return out
end

describe("the measure-facts seam: READ == DECLARED == HOSTED", function()
	local solver = fs.readFile(SOLVER_PATH)
	local facts = fs.readFile(FACTS_PATH)

	it("every `ctx` field the module reads is declared in its own `MeasureCtx`", function()
		local reads = ctxFieldsRead(facts)
		expect(#missingFrom(reads, typeFields(facts, "MeasureCtx"))).toBe(0)
		-- ...and the set is not empty, which is the trap a set comparison invites:
		-- two empty sets are equal
		expect(#sorted(reads)).toBe(6)
	end)

	it("every field `MeasureCtx` declares is one the module actually reads", function()
		-- the other direction, and it is the one that catches a field left behind
		-- by a change: a declared-but-unread field is a fact the solve is still
		-- computing for nobody
		expect(#missingFrom(typeFields(facts, "MeasureCtx"), ctxFieldsRead(facts))).toBe(0)
	end)

	it("every field `MeasureCtx` declares is still declared by the solver's own `Ctx`", function()
		--[[ THE HALF A PARAMETER OBJECT WOULD HAVE GIVEN FOR FREE. Nothing hands
			these fields over one by one — the whole `ctx` crosses — so a rename on
			the solver's side is a silent `nil` here rather than a missing argument.
			This is the assertion that turns it back into a compile-time-shaped
			failure. ]]
		expect(#missingFrom(typeFields(facts, "MeasureCtx"), typeFields(solver, "Ctx"))).toBe(0)
	end)

	it("NEGATIVE CONTROL: each scan reads what it claims to, and reports the pair out of step", function()
		local declared = { alpha = true, beta = true }
		local reads = { alpha = true, gamma = true }
		expect(missingFrom(reads, declared)[1]).toBe("gamma")
		expect(missingFrom(declared, reads)[1]).toBe("beta")
		local fake = "type Deps = {\n\t-- a comment, not a field\n\talpha: any,\n\tbeta: any,\n}"
		expect(#sorted(typeFields(fake, "Deps"))).toBe(2)
		-- a `ctx.` named inside a comment is NOT a read (the trap this seam has,
		-- and `memoPlan`'s doc block is a live instance of it)
		expect(sorted(ctxFieldsRead("--[[ ctx.ghost ]]\nlocal x = ctx.real\n"))).toEqual({ "real" })
		expect(sorted(ctxFieldsRead("\t-- ctx.ghost\n\tlocal x = ctx.real\n"))).toEqual({ "real" })
	end)
end)

describe("the measure-facts seam: the shared WRITE surface", function()
	local facts = fs.readFile(FACTS_PATH)

	it("the module writes through exactly four `ctx` fields, and each is a published verdict", function()
		--[[ THE WHOLE POINT OF THE SPLIT, stated as a set. A field the module
			WRITES is state the two files share; a field it only reads is a fact the
			solve decided. Four names are allowed and each has its reason in the
			module's own header:

			  · `textStates` / `textFacts` — the per-text-node measurement verdicts,
			    published on EVERY measure so the facts a reader sees are the ones
			    the reserved box was built from (LTN-4);
			  · `fitCuts` — the `ViewThatFits` probe's clamped-cut counter, the one
			    signal that distinguishes "this fits" from "this was made to fit";
			  · `memoPlans` — the per-node `PLAN_*` verdict, memoised once per solve.

			A FIFTH NAME HERE IS THE FINDING. It means a value the solve decided has
			quietly become state with two owners, which is the shape that makes a
			later reader unable to tell which file is answerable for it. ]]
		local writes = sorted(ctxFieldsWritten(facts))
		expect(writes).toEqual({ "fitCuts", "memoPlans", "textFacts", "textStates" })
	end)

	it("NEGATIVE CONTROL: the write scan sees each spelling, and a read is not a write", function()
		local text =
			"\n\tctx.alpha = 1\n\tctx.beta[key] = 2\n\tctx.gamma += 1\n\tlocal x = ctx.delta\n\tif ctx.eps == nil then\n"
		local seen = ctxFieldsWritten(text)
		expect(seen.alpha).toBe(true)
		expect(seen.beta).toBe(true)
		expect(seen.gamma).toBe(true)
		expect(seen.delta).toBe(nil)
		expect(seen.eps).toBe(nil)
	end)
end)

describe("the measure-facts seam: EXPORTED == BOUND, one consumer, one-way require", function()
	local solver = fs.readFile(SOLVER_PATH)
	local facts = fs.readFile(FACTS_PATH)

	it("every name the module exports is bound by the solver, and every bound name is exported", function()
		local exported = exportsOf(facts)
		local bound = boundOf(solver)
		expect(#missingFrom(exported, bound)).toBe(0) -- an export nobody takes
		expect(#missingFrom(bound, exported)).toBe(0) -- a binding that would be nil
		expect(#sorted(exported)).toBe(11)
		--[[ ...and the ONE thing that crosses as a TYPE rather than a value. `Dim`
			moved with `dim` and `mainDimOf` — the two functions that read it — and
			the solver re-exports it under the name every caller and every doc uses,
			so there is one schema rather than two. A second declaration of it in
			`solver.luau` is the copy-goes-stale failure this seam exists to
			prevent, and this is what notices. ]]
		expect(string.find(solver, "export type Dim = measureFacts.Dim", 1, true) ~= nil).toBe(true)
		expect(string.find(facts, "export type Dim = {", 1, true) ~= nil).toBe(true)
		expect(string.find(solver, "export type Dim = {", 1, true)).toBe(nil)
	end)

	it("every bound name is actually USED by the solver, not just bound", function()
		--[[ A binding is free to go stale in the direction the two set comparisons
			above cannot see: the export exists, the binding exists, and the last
			call site left. That is a fact this module is still computing for
			nobody, one indirection further out than the `MeasureCtx` case. ]]
		--[[ THE BINDING LINE NAMES THE BINDING TWICE (`local X = measureFacts.X`),
			so a count that included it could never reach zero and the rule would be
			decoration. Measured, not assumed: with the line left in, inlining every
			USE of `MEMO_ARM_DEPTH` in the solver left this check green (mutation M7,
			2026-08-21). The binding block is removed before counting. ]]
		local body = string.gsub(stripComments(solver), "\nlocal [%a_][%w_]* = measureFacts%.[%a_][%w_]*", "\n")
		local unused: { string } = {}
		for _, name in sorted(boundOf(solver)) do
			local _, uses = string.gsub(body, `[^%w_]{name}[^%w_]`, "")
			if uses < 1 then
				table.insert(unused, name)
			end
		end
		expect(table.concat(unused, " ")).toBe("")
	end)

	it("there is exactly ONE consumer of the module in src/", function()
		local seen: { string } = {}
		for _, dir in
			{
				"src/layout",
				"src/render",
				"src/present",
				"src/controls",
				"src/client",
				"src/tokens",
				"src/themes",
				"src/input",
				"src/core",
			}
		do
			for _, entry in fs.readDir(dir) do
				local path = `{dir}/{entry}`
				if not fs.isFile(path) or string.sub(path, -5) ~= ".luau" then
					continue
				end
				if string.find(fs.readFile(path), 'require("./measure_facts")', 1, true) ~= nil then
					table.insert(seen, path)
				end
			end
		end
		expect(seen).toEqual({ SOLVER_PATH })
	end)

	it("the module requires the solver NOWHERE — the require is one-way", function()
		for path in string.gmatch(facts, 'require%("([^"]+)"%)') do
			expect(string.match(path, "solver$") == nil).toBe(true)
		end
		-- ...and the direction that IS allowed is present, so this pair of
		-- assertions cannot both pass by the module having no requires at all
		expect(string.find(solver, 'require("./measure_facts")', 1, true) ~= nil).toBe(true)
		expect(string.find(facts, 'require("../themes/snapshot")', 1, true) ~= nil).toBe(true)
	end)

	it("the module names no type from the solver either", function()
		-- a type import is a require by another name in Luau (`require` first, then
		-- `Module.Type`), so the structural `any` on every node/ctx parameter is
		-- what keeps the graph acyclic
		local body = stripComments(facts)
		expect(string.find(body, "solver%.")).toBe(nil)
		expect(string.find(body, ": Ctx")).toBe(nil)
		expect(string.find(body, ": Node")).toBe(nil)
	end)
end)

describe("the measure-facts seam: no module-level mutable state", function()
	local facts = fs.readFile(FACTS_PATH)

	-- every module-level `local <name>` (column 0), and every module-level
	-- reassignment of one. A local assigned twice is an upvalue two solves share.
	local function moduleLocals(source: string): { [string]: boolean }
		local out: { [string]: boolean } = {}
		for name in string.gmatch("\n" .. stripComments(source), "\nlocal ([%a_][%w_]*)") do
			out[name] = true
		end
		for name in string.gmatch("\n" .. stripComments(source), "\nlocal function ([%a_][%w_]*)") do
			out[name] = true
		end
		return out
	end

	local function moduleReassignments(source: string, names: { [string]: boolean }): { string }
		local body = stripComments(source)
		local out: { string } = {}
		for name in names do
			-- a module-level assignment is one at column 0 that is not the `local`
			if string.find(body, `\n{name}%s*=[^=]`) ~= nil then
				table.insert(out, name)
			end
		end
		table.sort(out)
		return out
	end

	it("no module-level local is ever reassigned — two solves cannot see different helpers", function()
		--[[ THE PROPERTY THE LEDGER'S TEST IS ACTUALLY ABOUT, asserted from the
			other side. `docs/lessons/later-locals-are-not-upvalues.md` records the
			shape that made `shrinkStack` un-extractable until it moved: a local
			declared near the top and assigned two thousand lines below. Nothing
			here may acquire one — a module with mutable module state is a module
			the solver shares state with, whatever its argument lists say. ]]
		expect(moduleReassignments(facts, moduleLocals(facts))).toEqual({})
		expect(#sorted(moduleLocals(facts)) > 8).toBe(true)
	end)

	it("NEGATIVE CONTROL: the reassignment scan sees a late assignment and ignores a local one", function()
		local text = "local alpha\nlocal beta = 1\nlocal function f()\n\tbeta = 2\nend\nalpha = 3\n"
		local names = moduleLocals(text)
		expect(names.alpha).toBe(true)
		expect(names.beta).toBe(true)
		-- `alpha = 3` is at column 0 and is the finding; `beta = 2` is indented
		-- inside a function and is not
		expect(moduleReassignments(text, names)).toEqual({ "alpha" })
	end)
end)
