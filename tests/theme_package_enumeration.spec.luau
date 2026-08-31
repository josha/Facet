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

-- the consumers named in the finding, plus the playbook (the probe script that
-- once sat here was development scratch and left with the private archive)
local CONSUMERS = {
	"tests/theme_reference_packages.spec.luau",
	"tools/lune/check_docs.luau",
	"tests/renderer.spec.luau",
	"tests/gallery_theme_picker.spec.luau",
	"docs/extending/new-theme.md",
}

--[[ THE EIGHT, WRITTEN OUT. `shippable()` derives its answer from the directory,
	so a case that re-derived it would agree with any answer the code gave — this
	list is the independent statement of which packages a player may install, and
	the two are compared. ]]
local EXPECTED_SHIPPABLE = {
	"classic_desktop",
	"glossy_mobile",
	"scifi_hud",
	"fantasy_parchment",
	"fantasy_ornate",
	"pixel_quest",
	"glossy_touch",
	"compact_pointer",
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

	--[[ THE DISTRIBUTION AXIS (wave THEME-UNBUNDLE). `tools/build_themes.sh` builds
		one artifact per SHIPPABLE package, and shippable is a different question from
		the ROLE — `fantasy_parchment_stub` is a reference package for corpus purposes
		and must never reach a player, because three of its four variants are broken on
		purpose. The partition is what the builder reads, so it is checked here rather
		than restated in the shell script. ]]
	it("the shippable set is the eight player-facing packages, derived from the directory", function()
		local shippable = theme_packages.shippable()
		expect(#shippable).toBe(8)
		local named: { [string]: boolean } = {}
		for _, name in shippable do
			named[name] = true
		end
		for _, name in EXPECTED_SHIPPABLE do
			expect(`{name} ships: {tostring(named[name] == true)}`).toBe(`{name} ships: true`)
		end
		-- ...and the exclusions are exactly the rest of the directory: the partition
		-- is TOTAL, so a new module cannot default into "shippable" by omission
		local excluded = 0
		for _ in theme_packages.NOT_SHIPPABLE do
			excluded += 1
		end
		expect(#shippable + excluded).toBe(#theme_packages.files())
	end)

	it("the artifact name is derived from the module name, PascalCase", function()
		expect(theme_packages.artifactName("fantasy_ornate")).toBe("FantasyOrnate")
		expect(theme_packages.artifactName("classic_desktop")).toBe("ClassicDesktop")
		expect(theme_packages.artifactName("scifi_hud")).toBe("ScifiHud")
		-- distinct artifacts, so no two packages can collide on one .rbxm filename
		local seen: { [string]: string } = {}
		for _, name in theme_packages.shippable() do
			local artifact = theme_packages.artifactName(name)
			expect(`{artifact} claimed by {seen[artifact] or name}`).toBe(`{artifact} claimed by {name}`)
			seen[artifact] = name
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

	it("catches an exclusion whose module was renamed away", function()
		local excluded = theme_packages.NOT_SHIPPABLE
		excluded.a_fixture_that_moved = "a reason long enough to satisfy the reason rule below it, and no more"
		local result = theme_packages.check()
		excluded.a_fixture_that_moved = nil
		expect(result.ok).toBe(false)
		local named = false
		for _, problem in result.problems do
			if string.find(problem, "excludes 'a_fixture_that_moved'", 1, true) ~= nil then
				named = true
			end
		end
		expect(named).toBe(true)
	end)

	it("catches an exclusion with no usable reason — silence is not a decision", function()
		local excluded = theme_packages.NOT_SHIPPABLE
		local was = excluded.layered_test
		excluded.layered_test = "test"
		local result = theme_packages.check()
		excluded.layered_test = was
		expect(result.ok).toBe(false)
		local named = false
		for _, problem in result.problems do
			if string.find(problem, "needs a REASON", 1, true) ~= nil then
				named = true
			end
		end
		expect(named).toBe(true)
	end)

	it("catches a would-be shippable package that is not a reference package", function()
		local roles = theme_packages.ROLES
		local was = roles.custom_control
		local excluded = theme_packages.NOT_SHIPPABLE
		local reason = excluded.custom_control
		-- drop the exclusion: `custom_control` becomes shippable by omission, which
		-- is exactly the mistake the partition exists to make loud
		excluded.custom_control = nil
		local result = theme_packages.check()
		excluded.custom_control = reason
		roles.custom_control = was
		expect(result.ok).toBe(false)
		local named = false
		for _, problem in result.problems do
			if string.find(problem, "is shippable but its role is", 1, true) ~= nil then
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
