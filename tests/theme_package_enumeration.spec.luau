--!strict
--[[
	ONE ENUMERATOR FOR `examples/themes/` (MAINT-8c).

	Six independently hand-maintained lists of the same directory shipped in this
	repository, and nothing enumerated it or cross-validated them: a new package
	could land named by none of them, a rename could leave a list pointing at a
	file that no longer exists, and the playbook an author follows
	(`docs/extending/new-theme.md`) named exactly one of the six.

	`tools/lune/theme_packages.luau` is the enumerator. Two of the six now DERIVE
	from it (`tests/theme_reference_packages.spec.luau`'s order and
	`tools/lune/check_docs.luau`'s package list); the rest are legitimately
	different SUBSETS chosen for their case, so they are drift-checked instead —
	every theme name any of them mentions must be a module that exists, and every
	shipping reference package must be mentioned by at least one of them.

	The negative controls at the bottom are the point: a list nobody has watched
	fail is a list nobody knows works.
]]

local fs = require("@lune/fs")
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local theme_packages = require("../tools/lune/theme_packages")

-- the six consumers named in the finding, plus the playbook
local CONSUMERS = {
	"tests/theme_reference_packages.spec.luau",
	"tools/lune/check_docs.luau",
	"tools/lune/_probe_matrix.luau",
	"tests/renderer.spec.luau",
	"tests/gallery_theme_picker.spec.luau",
	"docs/extending/new-theme.md",
}

local function namesMentionedIn(path: string): { [string]: boolean }
	local source = fs.readFile(path)
	local out: { [string]: boolean } = {}
	for name in string.gmatch(source, "examples/themes/([%w_]+)") do
		out[name] = true
	end
	return out
end

describe("the theme-package directory has ONE enumerator (MAINT-8c)", function()
	it("every module on disk has a declared role, and every role names a module", function()
		local result = theme_packages.check()
		local detail = if result.ok then "" else "\n" .. table.concat(result.problems, "\n")
		expect(result.ok and true or error(`theme_packages.check FAILED:{detail}`, 2)).toBe(true)
	end)

	it("it really read the directory — the three kinds are all represented", function()
		expect(#theme_packages.files() >= 13).toBe(true)
		expect(#theme_packages.byRole("reference")).toBe(9)
		expect(#theme_packages.byRole("fixture") >= 2).toBe(true)
		expect(#theme_packages.byRole("control") >= 2).toBe(true)
		-- the declared order IS the reference corpus, in order
		expect(#theme_packages.REFERENCE_ORDER).toBe(#theme_packages.byRole("reference"))
	end)

	it("no consumer names a theme module that does not exist", function()
		local known: { [string]: boolean } = {}
		for _, name in theme_packages.files() do
			known[name] = true
		end
		for _, path in CONSUMERS do
			for name in namesMentionedIn(path) do
				expect(`{path} names {name}: {tostring(known[name] == true)}`).toBe(`{path} names {name}: true`)
			end
		end
	end)

	it("every SHIPPING reference package is named by at least one consumer", function()
		local mentioned: { [string]: boolean } = {}
		for _, path in CONSUMERS do
			for name in namesMentionedIn(path) do
				mentioned[name] = true
			end
		end
		for _, name in theme_packages.byRole("reference") do
			expect(`{name} is consumed: {tostring(mentioned[name] == true)}`).toBe(`{name} is consumed: true`)
		end
	end)

	-- NEGATIVE PROOFS
	it("catches a NEW module nobody declared a role for", function()
		local result = theme_packages.check({ "brand_new_package" })
		expect(result.ok).toBe(false)
		expect(string.find(result.problems[1], "brand_new_package", 1, true) ~= nil).toBe(true)
		expect(string.find(result.problems[1], "no declared role", 1, true) ~= nil).toBe(true)
	end)

	it("catches a role whose module was renamed away", function()
		local roles = theme_packages.ROLES
		roles.a_package_that_moved = "reference" :: any
		local result = theme_packages.check()
		roles.a_package_that_moved = nil
		expect(result.ok).toBe(false)
		local named = false
		for _, problem in result.problems do
			if string.find(problem, "a_package_that_moved", 1, true) ~= nil then
				named = true
			end
		end
		expect(named).toBe(true)
	end)

	it("catches a reference package left out of the declared order", function()
		local order = theme_packages.REFERENCE_ORDER
		local dropped = table.remove(order)
		local result = theme_packages.check()
		table.insert(order, dropped :: any)
		expect(result.ok).toBe(false)
		local named = false
		for _, problem in result.problems do
			if string.find(problem, "missing from REFERENCE_ORDER", 1, true) ~= nil then
				named = true
			end
		end
		expect(named).toBe(true)
	end)
end)
