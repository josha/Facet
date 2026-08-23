--!strict
--[[ THE COMPOSITION-RESOLVE SEAM, MECHANISED — what keeps
	`layout/composition_resolve.luau` one-way.

	WHY A SPEC AND NOT A COMMENT. `docs/handoff/SOURCE_CAP_LEDGER.md` records the
	rule every extraction in this repository is judged by: a block may leave a file
	only if it reads no mutable upvalue of its host, because otherwise the move
	creates a require BACK and the two files become one file with a slash in the
	middle. That row NAMED this block as the solver's next seam and stated the one
	condition on taking it — *"unless `measure` travels as a Dep the way `FLOW_DEPS`
	now proves is cheap"* — so the properties worth mechanising are exactly the two
	the row was worried about: the `ctx` surface, and the Dep.

	  READ      every `ctx.<field>` the module reads, comments stripped
	  DECLARED  every field its own `SolveCtx` type names
	  HOSTED    every field the solver's `type Ctx` block still declares

	all three equal (READ == DECLARED, DECLARED subset of HOSTED), plus the shared
	WRITE surface pinned to exactly one name, the Deps record pinned to exactly one
	name and PASSED at every call site, the ONE consumer, the one-way require, and
	that the module holds no module-level mutable state.

	Each rule is a pure function of a string, so each carries a NEGATIVE CONTROL
	that feeds it a broken input and proves it reports. A check that cannot fail is
	decoration (`docs/lessons/a-red-check-cannot-report-the-next-defect.md`).
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")
-- every `.luau` under `src/`, ONE enumeration (see its header for the
-- nine-of-fifteen hole it replaces)
local srcTree = require("./lib/src_tree")

local SOLVER_PATH = "src/layout/solver.luau"
local RESOLVE_PATH = "src/layout/composition_resolve.luau"

--[[ COMMENTS ARE NOT CODE, and in this repository that is not a nicety: this
	module's own reasoning blocks name `ctx.fitProbe` and `ctx.fitCuts` while
	explaining what the SOLVER does around it, and a scan that counted them would
	declare two fields this module must never learn. ]]
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
-- one.
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

describe("the composition-resolve seam: READ == DECLARED == HOSTED", function()
	local solver = fs.readFile(SOLVER_PATH)
	local resolveSrc = fs.readFile(RESOLVE_PATH)

	it("every `ctx` field the module reads is declared in its own `SolveCtx`", function()
		local reads = ctxFieldsRead(resolveSrc)
		expect(#missingFrom(reads, typeFields(resolveSrc, "SolveCtx"))).toBe(0)
		-- ...and the set is not empty, which is the trap a set comparison invites:
		-- two empty sets are equal. SEVEN: the four the resolution has always read,
		-- plus the three §9/§8 added — the surface's own content rect and the two
		-- platform-band facts, which is what a WINDOW-space rect has to be measured
		-- against before a pure composition can spend it.
		expect(#sorted(reads)).toBe(7)
	end)

	it("every field `SolveCtx` declares is one the module actually reads", function()
		-- the other direction, and it is the one that catches a field left behind by
		-- a change: a declared-but-unread field is a fact the solve is still
		-- computing for nobody
		expect(#missingFrom(typeFields(resolveSrc, "SolveCtx"), ctxFieldsRead(resolveSrc))).toBe(0)
	end)

	it("every field `SolveCtx` declares is still declared by the solver's own `Ctx`", function()
		--[[ THE HALF A PARAMETER OBJECT WOULD HAVE GIVEN FOR FREE. Nothing hands
			these fields over one by one — the whole `ctx` crosses — so a rename on the
			solver's side is a silent `nil` here rather than a missing argument. ]]
		expect(#missingFrom(typeFields(resolveSrc, "SolveCtx"), typeFields(solver, "Ctx"))).toBe(0)
	end)

	it("NEGATIVE CONTROL: each scan reads what it claims to, and reports the pair out of step", function()
		local declared = { alpha = true, beta = true }
		local reads = { alpha = true, gamma = true }
		expect(missingFrom(reads, declared)[1]).toBe("gamma")
		expect(missingFrom(declared, reads)[1]).toBe("beta")
		local fake = "type Deps = {\n\t-- a comment, not a field\n\talpha: any,\n\tbeta: any,\n}"
		expect(#sorted(typeFields(fake, "Deps"))).toBe(2)
		-- a `ctx.` named inside a comment is NOT a read, and this module has live
		-- instances of that trap in its own header
		expect(sorted(ctxFieldsRead("--[[ ctx.ghost ]]\nlocal x = ctx.real\n"))).toEqual({ "real" })
		expect(sorted(ctxFieldsRead("\t-- ctx.ghost\n\tlocal x = ctx.real\n"))).toEqual({ "real" })
	end)
end)

describe("the composition-resolve seam: the shared WRITE surface is ONE name", function()
	local resolveSrc = fs.readFile(RESOLVE_PATH)

	it("the module writes through exactly one `ctx` field, and it is the per-box cache", function()
		--[[ THE WHOLE POINT OF THE SPLIT, stated as a set. A field the module WRITES
			is state the two files share; a field it only reads is a fact the solve
			decided. `compositions` is the one, and it is the cache that exists so
			measure and arrange can never get different answers about the same box.

			A SECOND NAME HERE IS THE FINDING. It means a value the solve decided has
			quietly become state with two owners, which is the shape that makes a later
			reader unable to tell which file is answerable for it. ]]
		expect(sorted(ctxFieldsWritten(resolveSrc))).toEqual({ "compositions" })
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

describe("the composition-resolve seam: the Dep, one consumer, one-way require", function()
	local solver = fs.readFile(SOLVER_PATH)
	local resolveSrc = fs.readFile(RESOLVE_PATH)

	it("`Deps` declares exactly `measure`, and that is the only host name the body calls", function()
		--[[ THE LEDGER ROW'S OWN CONDITION, mechanised. It said this block could
			leave the solver only if `measure` travelled as a Dep; a SECOND field
			appearing here means something else of the solver's has been pulled across
			and the seam is one field wider than the row that justified it. ]]
		expect(sorted(typeFields(resolveSrc, "Deps"))).toEqual({ "measure" })
		-- ...and every `deps.<name>` the body actually reaches for is that one name
		local used: { [string]: boolean } = {}
		for key in string.gmatch(stripComments(resolveSrc), "deps%.([%a_][%w_]*)") do
			used[key] = true
		end
		expect(sorted(used)).toEqual({ "measure" })
	end)

	it("the solver PASSES the record at every call site — no call reaches the module bare", function()
		--[[ A DEPS RECORD DECLARED AND NOT PASSED IS THE FAILURE MODE A TYPE ALONE
			CANNOT SEE in a codebase that types `ctx` as `any`: the call still parses,
			`deps` arrives as the ctx, and `deps.measure` is nil at the first region
			that carries an expand affordance. Every call goes through the record. ]]
		local body = stripComments(solver)
		local calls = 0
		for _ in string.gmatch(body, "compositionResolve%.resolve%(") do
			calls += 1
		end
		local withDeps = 0
		for _ in string.gmatch(body, "compositionResolve%.resolve%(COMPOSITION_DEPS,") do
			withDeps += 1
		end
		expect(calls).toBe(2) -- one in `measure`, one in `arrange`
		expect(withDeps).toBe(calls)
		expect(string.find(body, "local COMPOSITION_DEPS: compositionResolve.Deps", 1, true) ~= nil).toBe(true)
	end)

	it("there is exactly ONE consumer of the module in src/", function()
		expect(srcTree.pathsMatching('require%("[^"]*composition_resolve"%)')).toEqual({ SOLVER_PATH })
	end)

	it("the module requires the solver NOWHERE — the require is one-way", function()
		for path in string.gmatch(resolveSrc, 'require%("([^"]+)"%)') do
			expect(string.match(path, "solver$") == nil).toBe(true)
		end
		-- ...and the direction that IS allowed is present, so this pair of assertions
		-- cannot both pass by the module having no requires at all
		expect(string.find(solver, 'require("./composition_resolve")', 1, true) ~= nil).toBe(true)
		expect(string.find(resolveSrc, 'require("./composition")', 1, true) ~= nil).toBe(true)
	end)

	it("the module names no type from the solver either", function()
		-- a type import is a require by another name in Luau (`require` first, then
		-- `Module.Type`), so the structural `any` on every node parameter is what
		-- keeps the graph acyclic
		local body = stripComments(resolveSrc)
		expect(string.find(body, "solver%.")).toBe(nil)
		expect(string.find(body, ": Ctx")).toBe(nil)
		expect(string.find(body, ": Node")).toBe(nil)
	end)
end)

describe("the composition-resolve seam: no module-level mutable state", function()
	local resolveSrc = fs.readFile(RESOLVE_PATH)

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
		--[[ `docs/lessons/later-locals-are-not-upvalues.md` records the shape that
			made `shrinkStack` un-extractable until it moved: a local declared near the
			top and assigned two thousand lines below. Nothing here may acquire one —
			a module with mutable module state is a module the solver shares state
			with, whatever its argument lists say. ]]
		expect(moduleReassignments(resolveSrc, moduleLocals(resolveSrc))).toEqual({})
		expect(#sorted(moduleLocals(resolveSrc)) > 2).toBe(true)
	end)

	it("NEGATIVE CONTROL: the reassignment scan sees a late assignment and ignores a local one", function()
		local text = "local alpha\nlocal beta = 1\nlocal function f()\n\tbeta = 2\nend\nalpha = 3\n"
		local names = moduleLocals(text)
		expect(names.alpha).toBe(true)
		expect(names.beta).toBe(true)
		expect(moduleReassignments(text, names)).toEqual({ "alpha" })
	end)
end)
