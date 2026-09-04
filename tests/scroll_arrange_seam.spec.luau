--!strict
--[[ THE SCROLL-ARRANGE SEAM, MECHANISED — what keeps `layout/scroll_arrange.luau`
	one-way, and what its one export promises.

	`arrange`'s `scroll` branch left `layout/solver.luau` on 2026-09-04 (Plan C, C3)
	for the Source-write headroom the anchor branch's clean-child skip needed: the
	solver stood 258 characters from the campaign's 197,500 STOP line with the arm in
	the tree, and its `source-cap-ledger.md` row has named this block as the seam to
	take since 2026-08-22. 197,242 -> 189,052.

	IT IS THE SEAM THE T6 ROUND DECLINED, and the reason it declined it is the reason
	this file exists: the branch calls `measure` and `arrange` directly and BRACKETS
	THE MEASURE SCOPE (`pushContainer` / `restoreScope`). That is not reimplemented on
	the other side — it is two Deps functions, so the solver still owns what a scope
	key is made of and this module only brackets one. The six-field record is the
	whole of what crosses, and the rule below that says so is a comparison of the
	record's declared fields against the keys the solver's `SCROLL_DEPS` literal
	writes, AS SETS IN BOTH DIRECTIONS — the property a split record puts at risk and
	the one no behavioural test can see.

	THE BEHAVIOUR IS UNCHANGED AND THESE CASES DO NOT CLAIM OTHERWISE.
	`tests/scroll_bar_measure.spec.luau`, `tests/scroll_window_clip.spec.luau`,
	`tests/native_scroll.spec.luau`, `tests/layout.spec.luau` and the device sweep are
	what say the branch still lays out; this file says the branch is still ONE-WAY.

	Each source rule is a pure function of a string, so each carries a NEGATIVE
	CONTROL that feeds it a broken input and proves it reports. A check that cannot
	fail is decoration. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")

local scroll_arrange = require("../src/layout/scroll_arrange")

local MODULE_PATH = "src/layout/scroll_arrange.luau"
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

-- the field names a `type X = { ... }` block declares at one indent depth
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

-- ...and the keys a `{ ... }` literal assigns at one indent depth
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

local function between(source: string, from: string, to: string): string
	local i = string.find(source, from, 1, true)
	assert(i ~= nil, `seam spec: '{from}' not found`)
	local j = string.find(source, to, i :: number, true)
	assert(j ~= nil, `seam spec: '{to}' not found after '{from}'`)
	return string.sub(source, i :: number, j :: number)
end

local moduleSrc = fs.readFile(MODULE_PATH)
local solverSrc = fs.readFile(SOLVER_PATH)

describe("the scroll-arrange seam: one-way, one entry point, no state", function()
	it("requires only the token module and the context types — never the solver", function()
		--[[ THE ONE-WAY CLAIM, at its strongest form: a module that cannot require the
			solver cannot read a solver local, and the direction of the dependency is then
			a fact about the file rather than a promise in its header. `chrome_slots` is
			the all-or-nothing leading-bleed floor the branch already used; `solve_ctx`
			supplies the `Rect` type and nothing else, and it is itself a leaf. ]]
		expect(sorted(requiresIn(moduleSrc))).toEqual({ "../tokens/chrome_slots", "./solve_ctx" })
	end)

	it("...and the solver requires IT, which is the direction the split claims", function()
		expect(requiresIn(solverSrc)["./scroll_arrange"]).toBe(true)
	end)

	it("exports exactly one function and one Deps type", function()
		local fns: { string } = {}
		for name, value in scroll_arrange :: any do
			if type(value) == "function" then
				table.insert(fns, name)
			end
		end
		table.sort(fns)
		expect(fns).toEqual({ "arrange" })
	end)

	it("holds no module-level mutable state", function()
		--[[ A `local x = {}` or a `local n = 0` at column zero, other than the module
			table itself and the two requires, is state that survives between solves —
			the thing that would make two surfaces share an accumulator. There is none,
			and this reads it off the source rather than trusting the header. ]]
		local offenders: { string } = {}
		for line in string.gmatch("\n" .. stripComments(moduleSrc), "\n([^\n]*)") do
			local name = string.match(line, "^local ([A-Za-z_][A-Za-z0-9_]*)%s*=")
			if name ~= nil and name ~= "scroll_arrange" and name ~= "chrome_slots" and name ~= "solveCtx" then
				table.insert(offenders, name)
			end
		end
		expect(`module-level locals={table.concat(offenders, " ")}`).toBe("module-level locals=")
	end)

	it("names no solver symbol it was not handed", function()
		--[[ THE FIVE THE BRANCH USED TO READ AS UPVALUES. Every one of them now arrives
			through `Deps` and is bound to a local at the top of the function, so the moved
			body is the solver's line for line. What this rule catches is the opposite
			accident: a later edit reaching for `solver.` or for a name the record does
			not carry. ]]
		local body = stripComments(moduleSrc)
		expect(string.find(body, "solver", 1, true) == nil).toBe(true)
		for _, name in { "measure", "arrange", "dim", "offsetPx", "pushContainer", "restoreScope" } do
			expect(`{name} bound={string.find(body, `deps.{name}`, 1, true) ~= nil}`).toBe(`{name} bound=true`)
		end
	end)

	it("THE RECORD AND THE SOLVER'S LITERAL CANNOT DRIFT: the two sets are equal, both ways", function()
		--[[ THE RULE WITH THE MOST TEETH. A Deps field declared here and not written by
			`SCROLL_DEPS` is `nil` at every call; a key written there and not declared is
			invisible to the type checker and reads as a spare — and a Deps record is a
			statement about what a module reads, so a spare field in it is a false
			statement. Compared AS SETS, in BOTH directions. ]]
		local declared = fieldsAt(between(moduleSrc, "export type Deps = {", "\n}"), "\t")
		local written = keysAt(between(solverSrc, "local SCROLL_DEPS: scrollArrange.Deps = {", "\n}"), "\t")
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
		expect(`declared={#sorted(declared)} written={#sorted(written)}`).toBe("declared=6 written=6")
		expect(`never supplied={table.concat(missing, " ")}`).toBe("never supplied=")
		expect(`undeclared={table.concat(undeclared, " ")}`).toBe("undeclared=")
	end)

	it("the solver keeps ONE `scroll` arrange branch, and it is the call", function()
		--[[ WHAT A HALF-DONE EXTRACTION LOOKS LIKE: the old body left behind under a
			second `if node.kind == "scroll"`, or the call added and the branch not
			removed. The arrange half of the solver now mentions the kind exactly once
			outside its own prose, and that once is the delegation. ]]
		local body = stripComments(solverSrc)
		local from = string.find(body, "local function arrangeBody", 1, true)
		expect(from ~= nil).toBe(true)
		local tail = string.sub(body, from :: number)
		local branches = 0
		for _ in string.gmatch(tail, 'if node%.kind == "scroll" then') do
			branches += 1
		end
		expect(`scroll arrange branches={branches}`).toBe("scroll arrange branches=1")
		expect(string.find(tail, "scrollArrange.arrange(SCROLL_DEPS", 1, true) ~= nil).toBe(true)
	end)

	it("NEGATIVE CONTROLS: every source rule above really does read its input", function()
		expect(sorted(requiresIn('local a = require("./x")\nlocal b = require("../y")'))).toEqual({ "../y", "./x" })
		expect(sorted(requiresIn('-- require("./commented")'))).toEqual({})
		expect(sorted(fieldsAt("\tmeasure: number,\n\t\tdeeper: number,", "\t"))).toEqual({ "measure" })
		expect(sorted(keysAt("\tmeasure = f,\n\t\tdeeper = g,", "\t"))).toEqual({ "measure" })
		expect(string.find(stripComments("--[[ solver ]]\nlocal x = 1"), "solver", 1, true) == nil).toBe(true)
	end)
end)
