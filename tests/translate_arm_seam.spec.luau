--!strict
--[[ THE TRANSLATE ARM SEAM, MECHANISED — what keeps `layout/translate_arm.luau`
	one-way (Plan C, T2). Built from `stack_seam.spec.luau`'s own skeleton, widened
	for the one way this seam differs from every prior one in this file:

	NO DEPS AT ALL, not a Deps record with fields. `translatable` and
	`translateDescendants` read `reuse`/`node`/`child` off their own parameters —
	nothing arrives through a closed record — which is the SAME claim
	`src/layout/placement.luau` and `src/render/recycle_key.luau` already make about
	themselves, and the strongest one-way statement a module in this repository can
	carry: there is no boundary to keep closed because nothing crosses one.

	THE WRITE SET IS WIDENED, not empty. Unlike the stack branch (which writes only
	`ctx.diagnostics`, by insert), this arm counts its own two work channels
	(`ctx.rectInserts`, `ctx.translated`) and stamps a re-based rect into three
	tables it does not own (`out`, `ctx.translatedPaths`, `ctx.translatedEntries`) —
	all by INDEX, never by field. That is the S1 brief's own widened assertion for
	this seam, spelled out here as `{ "ctx.rectInserts", "ctx.translated" }` for the
	field scan and a closed index-target set for the rest.

	Each source rule is a pure function of a string, so each carries a NEGATIVE
	CONTROL that feeds it a broken input and proves it reports. A check that cannot
	fail is decoration. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")
local srcTree = require("./lib/src_tree")

local SOLVER_PATH = "src/layout/solver.luau"
local ARM_PATH = "src/layout/translate_arm.luau"

--[[ COMMENTS ARE NOT CODE, exactly as `stack_seam`'s own copy of this helper says:
	this module's own header names every crossing name while explaining what it
	must never reach for, and a scan that counted them would report the exact
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

describe("the translate arm seam: NO Deps at all — the strongest one-way claim", function()
	it("the module carries no `Deps` field and no `export type Deps`", function()
		local mod = require("../src/layout/translate_arm")
		expect(rawget(mod :: any, "Deps")).toBe(nil)
		local src = fs.readFile(ARM_PATH)
		expect(string.find(stripComments(src), "export type Deps")).toBe(nil)
	end)

	it("NEGATIVE CONTROL: a fake module WITH a Deps type reports it", function()
		local fakeSrc = "export type Deps = {\n\tmeasure: (any) -> (),\n}\n"
		expect(string.find(stripComments(fakeSrc), "export type Deps") ~= nil).toBe(true)
		local fakeMod = { Deps = {} }
		expect(rawget(fakeMod, "Deps") ~= nil).toBe(true)
	end)
end)

describe("the translate arm seam: a CLOSED set of reuse/node/child fields", function()
	local armSrc = fs.readFile(ARM_PATH)

	it("it reads exactly `dirtyContains`/`previous` off `reuse`", function()
		expect(sorted(fieldsRead(armSrc, "reuse"))).toEqual({ "dirtyContains", "previous" })
	end)

	it("it reads exactly `children` off `node` (and `child`, the same shape, in the walk)", function()
		expect(sorted(fieldsRead(armSrc, "node"))).toEqual({ "children" })
	end)

	--[[ `hostSpace` JOINED THE SET ON 2026-09-07 (Plan D, D6a's fix round) and the
		rider is the whole point of pinning the set at all: the walk now stops at a
		coordinate-space host instead of re-basing its subtree a second time, and that
		question is asked of the CHILD. Three fields, not two — a fourth would be a
		widening nobody argued for. ]]
	it("it reads exactly `hostSpace`/`id`/`kind` off `child`", function()
		expect(sorted(fieldsRead(armSrc, "child"))).toEqual({ "hostSpace", "id", "kind" })
	end)

	it("NEGATIVE CONTROL: the field-read scan reports a changed set", function()
		expect(sorted(fieldsRead("local x = reuse.ghost\n", "reuse"))).toEqual({ "ghost" })
		expect(sorted(fieldsRead("local y = child.ghost\n", "child"))).toEqual({ "ghost" })
	end)
end)

describe("the translate arm seam: the widened write set, and nothing else", function()
	local armSrc = fs.readFile(ARM_PATH)
	local body = stripComments(armSrc)

	it("it assigns exactly `ctx.rectInserts` and `ctx.translated`, both by `+=`", function()
		local assigned: { string } = {}
		for recv, field in string.gmatch(body, "([%a_][%w_]*)%.([%a_][%w_]*)%s*[%+%-]?=[^=]") do
			if recv == "ctx" then
				table.insert(assigned, `{recv}.{field}`)
			end
		end
		expect(sorted((function()
			local set: { [string]: boolean } = {}
			for _, name in assigned do
				set[name] = true
			end
			return set
		end)())).toEqual({ "ctx.rectInserts", "ctx.translated" })
	end)

	it("its only INDEX writes are into `out[...]`, `paths[...]` and `entries[...]`", function()
		--[[ A single-level bracket scan, exactly as `child.id` and `n` (never a
			nested `[...]` expression) let it be: `out[child.id] = entry`,
			`paths[n] = child.id`, `entries[n] = entry`. Anything else assigning
			through an index is a fourth table this seam was never meant to touch. ]]
		local targets: { [string]: boolean } = {}
		for recv in string.gmatch(body, "([%a_][%w_]*)%[[^%[%]]*%]%s*=[^=]") do
			targets[recv] = true
		end
		expect(sorted(targets)).toEqual({ "entries", "out", "paths" })
	end)

	it("NEGATIVE CONTROL: the write scans both report an extra target", function()
		local fake = "\nctx.measured += 1\nrogue[n] = 1\n"
		local assigned: { [string]: boolean } = {}
		for recv, field in string.gmatch(stripComments(fake), "([%a_][%w_]*)%.([%a_][%w_]*)%s*[%+%-]?=[^=]") do
			if recv == "ctx" then
				assigned[`{recv}.{field}`] = true
			end
		end
		expect(sorted(assigned)).toEqual({ "ctx.measured" })
		local targets: { [string]: boolean } = {}
		for recv in string.gmatch(stripComments(fake), "([%a_][%w_]*)%[[^%[%]]*%]%s*=[^=]") do
			targets[recv] = true
		end
		expect(sorted(targets)).toEqual({ "rogue" })
	end)
end)

describe("the translate arm seam: the solver binds it, and keeps no copy", function()
	local solverSrc = fs.readFile(SOLVER_PATH)

	it("the solver requires the module and calls both functions, char for char", function()
		expect(string.find(solverSrc, 'local translateArm = require("./translate_arm")', 1, true) ~= nil).toBe(true)
		expect(string.find(solverSrc, "translateArm.translatable(reuse, node)", 1, true) ~= nil).toBe(true)
		expect(
			string.find(solverSrc, "translateArm.translateDescendants(ctx, node, rect, tprev.rect, out)", 1, true)
				~= nil
		).toBe(true)
	end)

	it("the solver keeps no local definition of either function", function()
		expect(string.find(solverSrc, "local function translatable", 1, true)).toBe(nil)
		expect(string.find(solverSrc, "local function translateDescendants", 1, true)).toBe(nil)
	end)

	it("NEGATIVE CONTROL: the call-line and leftover-definition scans both report", function()
		local fakeMissingCall = 'local translateArm = require("./translate_arm")\n'
		expect(string.find(fakeMissingCall, "translateArm.translatable(reuse, node)", 1, true)).toBe(nil)
		local fakeLeftover = "\tlocal function translatable(reuse: any, node: any): boolean\n\t\treturn true\n\tend\n"
		expect(string.find(fakeLeftover, "local function translatable", 1, true) ~= nil).toBe(true)
	end)

	it("there is exactly ONE consumer of the module in src/", function()
		expect(srcTree.pathsMatching('require%("[^"]*/translate_arm"%)')).toEqual({ SOLVER_PATH })
	end)

	it("the module exports exactly `translatable` and `translateDescendants`", function()
		local armSrc = fs.readFile(ARM_PATH)
		local exported: { [string]: boolean } = {}
		for name in string.gmatch(stripComments(armSrc), "function translate_arm%.([%a_][%w_]*)") do
			exported[name] = true
		end
		expect(sorted(exported)).toEqual({ "translatable", "translateDescendants" })
	end)
end)

describe("the translate arm seam: one-way and no state", function()
	local armSrc = fs.readFile(ARM_PATH)

	it("it names no solver symbol and imports no solver type", function()
		local body = stripComments(armSrc)
		expect(string.find(body, ": Node")).toBe(nil)
		expect(string.find(body, ": Ctx")).toBe(nil)
		expect(string.find(body, "solver%.")).toBe(nil)
	end)

	it("nothing declared at module level is ever reassigned", function()
		local body = stripComments(armSrc)
		local declared: { [string]: boolean } = {}
		for name in string.gmatch(body, "\nlocal ([%a_][%w_]*)") do
			declared[name] = true
		end
		local reassigned: { string } = {}
		for name in string.gmatch(body, "\n([%a_][%w_]*) =") do
			if declared[name] then
				table.insert(reassigned, name)
			end
		end
		expect(reassigned).toEqual({})
	end)

	it("NEGATIVE CONTROL: the solver-symbol and reassignment scans both report", function()
		expect(string.find(stripComments("local x: Node = node\n"), ": Node") ~= nil).toBe(true)
		local fake = "\nlocal cache = nil\ncache = 1\n"
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
