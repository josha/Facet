--!strict
--[[ THE PER-SOLVE-CONTEXT SEAM, MECHANISED — what keeps `layout/solve_ctx.luau`
	one-way, and what its one export promises.

	The `Ctx` type, its documentation and the single place a context is built left
	`layout/solver.luau` on 2026-09-04 (Plan C, T6) for the Source-write headroom the
	measure serve needed: 195,714 -> 179,355, and 13,716 of those characters were the
	type declaration alone. It is the cheapest seam this file has ever had, because
	NOTHING BEHAVIOURAL CROSSES IT — no Deps record, no reassigned upvalue, no
	function that reads a solver local. What crosses is a type and a table literal.

	THE RULE WITH THE MOST TEETH IS THE LAST ONE. A record split from its constructor
	can drift silently: a field added to the type and not to `new` is `nil` at every
	read, and a key written by `new` and not declared is invisible to the type
	checker. So the two sets are compared AS SETS, in both directions, off the source
	— which is the property the split itself put at risk and the one a behavioural
	test cannot see.

	Each source rule is a pure function of a string, so each carries a NEGATIVE
	CONTROL that feeds it a broken input and proves it reports. A check that cannot
	fail is decoration. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")
local srcTree = require("./lib/src_tree")

local solve_ctx = require("../src/layout/solve_ctx")

local MODULE_PATH = "src/layout/solve_ctx.luau"
local SOLVER_PATH = "src/layout/solver.luau"

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

-- the keys a `{ ... }` literal at ONE indent depth assigns, as a set
local function keysAt(block: string, indent: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for line in string.gmatch("\n" .. block, "\n([^\n]*)") do
		local name = string.match(line, `^{indent}([A-Za-z_][A-Za-z0-9_]*)%s*=`)
		if name ~= nil then
			out[name] = true
		end
	end
	return out
end

local function fieldsAt(block: string, indent: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for line in string.gmatch("\n" .. block, "\n([^\n]*)") do
		local name = string.match(line, `^{indent}([A-Za-z_][A-Za-z0-9_]*)%s*:`)
		if name ~= nil then
			out[name] = true
		end
	end
	return out
end

describe("the solve-context seam: one require, no state, one export", function()
	it("the module requires EXACTLY `./measure_reuse`, and that module cannot require back", function()
		expect(sorted(requiresIn(fs.readFile(MODULE_PATH)))).toEqual({ "./measure_reuse" })
		--[[ the other half of one-way, and it is the half a require list alone cannot
			state: `measure_reuse` is a LEAF. If it ever required this module or the
			solver, the extraction would have made a cycle that Luau resolves by
			returning a half-built table. ]]
		expect(sorted(requiresIn(fs.readFile("src/layout/measure_reuse.luau")))).toEqual({})
		-- NEGATIVE CONTROL: the scan really does see a require
		expect(sorted(requiresIn('local x = require("./somewhere")'))).toEqual({ "./somewhere" })
	end)

	it("it names no solver symbol — not even in a comment", function()
		local source = fs.readFile(MODULE_PATH)
		-- `solver.luau` and `solver.solve` appear in the prose (they must: the module
		-- says where it came from), so the rule is about CODE
		local code = stripComments(source)
		expect(`solver ref={string.find(code, "solver%.") ~= nil}`).toBe("solver ref=false")
		expect(`require solver={string.find(code, 'require%("%./solver"%)') ~= nil}`).toBe("require solver=false")
		-- NEGATIVE CONTROL
		expect(`control={string.find(stripComments("local x = solver.Rect"), "solver%.") ~= nil}`).toBe("control=true")
	end)

	it("no module-level mutable state: a context belongs to ONE solve", function()
		--[[ a `local shared = {}` up here would be an accumulator every solve on the
			client added into — `work.measured`, `work.arranged` and every counter in
			`controller.stats()` silently summed across surfaces and across frames. That
			is exactly what a module holding a record invites, and the reason `new`
			builds a fresh table on every call. ]]
		local source = stripComments(fs.readFile(MODULE_PATH))
		local head = string.match(source, "^(.-)\nfunction solve_ctx%.new")
		assert(head ~= nil, "no `function solve_ctx.new` to split on")
		local decls: { string } = {}
		for line in string.gmatch(head :: string, "\n([^\n]*)") do
			local trimmed = string.match(line, "^%s*(.-)%s*$") :: string
			if string.match(trimmed, "^local ") ~= nil then
				table.insert(decls, trimmed)
			end
		end
		expect(decls).toEqual({ 'local measureReuse = require("./measure_reuse")', "local solve_ctx = {}" })
		-- NEGATIVE CONTROL: the same scan over a head that DOES hold a shared record
		local fake = stripComments("local solve_ctx = {}\nlocal shared = {}\nfunction solve_ctx.new()")
		local fakeHead = string.match(fake, "^(.-)\nfunction solve_ctx%.new") :: string
		local n = 0
		for line in string.gmatch(fakeHead, "\n([^\n]*)") do
			if string.match(line, "^%s*local ") ~= nil then
				n += 1
			end
		end
		expect(`decls seen:{n}`).toBe("decls seen:2")
	end)

	it("the runtime export set is exactly `new`", function()
		local names: { string } = {}
		for name in solve_ctx :: any do
			table.insert(names, name)
		end
		table.sort(names)
		expect(names).toEqual({ "new" })
	end)

	it("NOTHING WAS LEFT BEHIND: the solver declares no `Ctx` body and builds no context literal", function()
		local solver = stripComments(fs.readFile(SOLVER_PATH))
		expect(`ctx body={string.find(solver, "type Ctx = {", 1, true) ~= nil}`).toBe("ctx body=false")
		expect(`alias={string.find(solver, "type Ctx = solveCtx.Ctx", 1, true) ~= nil}`).toBe("alias=true")
		expect(`literal={string.find(solver, "local ctx: Ctx = {", 1, true) ~= nil}`).toBe("literal=false")
		local calls = 0
		for _ in string.gmatch(solver, "solveCtx%.new%(") do
			calls += 1
		end
		expect(`call sites={calls}`).toBe("call sites=1")
	end)

	it("TWO consumers, by a tree-wide scan rather than a directory list", function()
		--[[ ONE until Plan C's C3, which moved `arrange`'s `scroll` branch to
			`src/layout/scroll_arrange.luau`; that module takes the `Rect` type from here
			(and `chrome_slots`) rather than from the solver, which is what keeps it from
			requiring the solver back. A THIRD consumer is still a change worth seeing —
			this record is a per-solve accumulator and a module that reads it is a module
			that can read another solve's state — so the list stays exact. ]]
		expect(srcTree.pathsMatching('require%("[^"]*solve_ctx"%)')).toEqual({
			"src/layout/scroll_arrange.luau",
			"src/layout/solver.luau",
		})
	end)

	it("`Rect` has ONE declaration, and the solver re-exports it rather than repeating it", function()
		local module = stripComments(fs.readFile(MODULE_PATH))
		local solver = stripComments(fs.readFile(SOLVER_PATH))
		expect(`declared={string.find(module, "export type Rect = { x: number", 1, true) ~= nil}`).toBe("declared=true")
		expect(`re-exported={string.find(solver, "export type Rect = solveCtx.Rect", 1, true) ~= nil}`).toBe(
			"re-exported=true"
		)
		expect(`repeated={string.find(solver, "type Rect = { x: number", 1, true) ~= nil}`).toBe("repeated=false")
	end)

	it("THE RECORD AND ITS CONSTRUCTOR CANNOT DRIFT: the two field sets are equal, both ways", function()
		local source = stripComments(fs.readFile(MODULE_PATH))
		local typeBody = string.match(source, "export type Ctx = {(.-)\n}\n")
		assert(typeBody ~= nil, "no `export type Ctx` body found")
		local litBody = string.match(source, "local ctx: Ctx = {(.-)\n\t}")
		assert(litBody ~= nil, "no `local ctx: Ctx = {` literal found")
		local declared = fieldsAt(typeBody :: string, "\t")
		local written = keysAt(litBody :: string, "\t\t")
		local missing: { string } = {}
		for name in declared do
			if not written[name] then
				table.insert(missing, name)
			end
		end
		local undeclared: { string } = {}
		for name in written do
			if not declared[name] then
				table.insert(undeclared, name)
			end
		end
		table.sort(missing)
		table.sort(undeclared)
		expect(`declared={#sorted(declared)} written={#sorted(written)}`).toBe("declared=52 written=52")
		expect(`never built={table.concat(missing, " ")}`).toBe("never built=")
		expect(`undeclared={table.concat(undeclared, " ")}`).toBe("undeclared=")
		-- NEGATIVE CONTROL: both scans really do read a field and a key
		expect(sorted(fieldsAt("\tarranged: number,", "\t"))).toEqual({ "arranged" })
		expect(sorted(keysAt("\t\tarranged = 0,", "\t\t"))).toEqual({ "arranged" })
	end)

	it("`new` returns a FRESH context every call — two solves never share an accumulator", function()
		local rect = { x = 0, y = 0, w = 100, h = 50 }
		local a = solve_ctx.new(rect, nil, nil)
		local b = solve_ctx.new(rect, nil, nil)
		a.measured += 7
		table.insert(a.diagnostics, { node = "x", issue = "y" })
		expect(`a={a.measured} b={b.measured} same={a == b} diags={#b.diagnostics}`).toBe("a=7 b=0 same=false diags=0")
		-- the outermost container is the content rect (§2.5), and the scope key is the
		-- unarmed one — the two facts every later measure keys off
		expect(`cw={a.containerW} ch={a.containerH} key={a.scopeKey}`).toBe("cw=100 ch=50 key=0")
	end)

	it("...and it ANSWERS `measureQuiet` off the previous solve's findings, not later", function()
		--[[ the anchor arrange arm's fourth gate, and now the measure serve's: false
			when the previous solve filed a MEASURE-time finding, because neither can
			republish a finding about a node in the subtree it skips. It is answered
			here, so there is no moment when a half-built context is worth handing out. ]]
		local rect = { x = 0, y = 0, w = 10, h = 10 }
		local clean = solve_ctx.new(rect, { reuse = { previous = { diagnostics = { { node = "a", issue = "b" } } } } })
		local noisy = solve_ctx.new(
			rect,
			{ reuse = { previous = { diagnostics = { { node = "a", issue = "b", measured = true } } } } }
		)
		local full = solve_ctx.new(rect, nil, nil)
		expect(`clean={clean.measureQuiet} noisy={noisy.measureQuiet} full={full.measureQuiet}`).toBe(
			"clean=true noisy=false full=true"
		)
	end)

	it("...and it sanitises the scrollbar reserve, which is a caller number", function()
		local rect = { x = 0, y = 0, w = 10, h = 10 }
		local nan = 0 / 0
		expect(
			`none={solve_ctx.new(rect, nil, nil).scrollBarReserve}`
				.. ` neg={solve_ctx.new(rect, { scrollBarReserve = -8 }, nil).scrollBarReserve}`
				.. ` nan={solve_ctx.new(rect, { scrollBarReserve = nan }, nil).scrollBarReserve}`
				.. ` ok={solve_ctx.new(rect, { scrollBarReserve = 8 }, nil).scrollBarReserve}`
		).toBe("none=0 neg=0 nan=0 ok=8")
	end)

	it("the measure store is bound ONLY on a solve that can read it (P1's economics, unchanged)", function()
		local rect = { x = 0, y = 0, w = 10, h = 10 }
		local store = { byId = {} }
		local full = solve_ctx.new(rect, { measures = store }, nil)
		local incremental = solve_ctx.new(rect, { measures = store, reuse = { previous = { diagnostics = {} } } }, nil)
		expect(`full={full.measures == nil} incremental={incremental.measures == store}`).toBe(
			"full=true incremental=true"
		)
	end)
end)
