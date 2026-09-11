--!strict
-- ICON COVERAGE: a shipped theme package answers every icon name a control asks
-- for with ART, and the ASCII floor is an engine recovery path nobody ever sees.
--
-- WHY THIS SPEC EXISTS. The resolution ladder is
--
--     package art  ->  framework art (standard_icons)  ->  ASCII glyph  ->  nil
--
-- and the floor at the end of it is deliberate: a control draws a legible
-- character from the moment it is built, so nothing on screen depends on a
-- resolution succeeding. That is a recovery path. It was also, until
-- 2026-09-11, a SHIPPING STATE — and a player photographed the result in
-- Studio: `*` and `o` where a radio's mark and ring belong, `^v` where a pop-up
-- button's chevron pair belongs, a bare `v` for a tick. Three independent holes
-- produced it, and each one was invisible to every existing check:
--
--   1. no rung had art for `facet:selection.radio.on|off` or
--      `facet:selection.check.off` at all, so those three names could ONLY ever
--      reach the floor;
--   2. `menu_recipe` hand-authored `"o"`, `"[]"` and `"*"` as its own node text
--      rather than taking them from `ICON_FALLBACK_GLYPHS`, so the characters
--      were not even part of the ladder that the floor is the bottom of;
--   3. two shipped reference packages declined the framework's art rung ON
--      PURPOSE, as a controlled comparison against Fantasy Ornate's pictures —
--      which is a fine thing to demonstrate in a test and not a thing to ship.
--
-- So the rule this file enforces is a coverage rule, stated once:
--
--   **every SHIPPED package resolves every icon name any control in `src/`
--   requests to `source = "asset"`.**
--
-- It is checked three ways, because each one can be true while another is
-- false: the pinned name list is re-derived from the sources at test time (a new
-- request name cannot appear without joining it), every package is asked
-- directly, and a real screen is MOUNTED under every package so that a node
-- carrying an icon hint is caught painting a character the ladder never covered.

local t = require("./lib/testkit")
local fs = require("@lune/fs")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src")
local themePackage = require("../src/themes/package")
local themeSnapshot = require("../src/themes/snapshot")
local fake_target = require("./lib/fake_target")

-- ─────────────────────────────────────────────────────────────────────────────
-- THE NAMES A CONTROL ACTUALLY ASKS FOR
--
-- Pinned, so the list is reviewable as a list; re-derived below, so it cannot
-- rot in either direction. A name lands here when framework code names it — not
-- when a CALLER does: `trash` and `flag` are real standard icons, but only an
-- application's own row action ever requests them, and a theme package is not
-- answerable for a name no control of ours utters.
local REQUIRED_ICONS: { string } = {
	"facet:search",
	"chevron.leading",
	"chevron.trailing",
	"chevron.up",
	"chevron.down",
	"chevron.up.chevron.down",
	"checkmark",
	"close",
	"increment",
	"decrement",
	"menu",
	"more",
	"edit",
	"facet:selection.radio.off",
	"facet:selection.radio.on",
	"facet:selection.check.off",
}

-- the files a framework icon request can live in: the composite controls, the
-- presentation layer, and the blueprint library's own affordances (the expand
-- plate's close chip, the disclosure caret). `src/render` and
-- `src/blueprint_schema` are deliberately NOT here: they carry `icon = "style"`
-- (a property authority, not an icon) and `icon = "<semantic name>"` inside
-- error prose, and a scan that swept them would be measuring documentation.
local function sourceFiles(): { string }
	local out: { string } = { "src/blueprint.luau" }
	for _, dir in { "src/controls", "src/present" } do
		for _, entry in fs.readDir(dir) do
			if string.sub(entry, -5) == ".luau" then
				table.insert(out, `{dir}/{entry}`)
			end
		end
	end
	table.sort(out)
	return out
end

-- every icon name the sources NAME, by the three shapes a name is written in:
-- the decoration hint / control property (`icon = "..."`), the floor lookup
-- (`iconGlyph("...")`), and a bare `facet:`-namespaced literal, which in
-- framework code is an icon name by construction (`ns:name` in an error string
-- is not, and cannot be: the namespace has to be `facet`).
local function namesInSources(): { [string]: { string } }
	local found: { [string]: { string } } = {}
	local function add(name: string, where: string)
		local seen = found[name]
		if seen == nil then
			found[name] = { where }
		elseif seen[#seen] ~= where then
			table.insert(seen, where)
		end
	end
	for _, path in sourceFiles() do
		local src = fs.readFile(path)
		for name in string.gmatch(src, 'icon = "([^"]+)"') do
			if themePackage.isIconName(name) then
				add(name, path)
			end
		end
		for name in string.gmatch(src, 'iconGlyph%("([^"]+)"%)') do
			add(name, path)
		end
		for name in string.gmatch(src, '"(facet:[%a][%w_%.]*)"') do
			add(name, path)
		end
	end
	return found
end

-- ─────────────────────────────────────────────────────────────────────────────
-- THE SHIPPED PACKAGES. The same eight the overflow sweep walks, plus the flat
-- neutral package, which is what a game gets when it installs nothing at all and
-- is therefore the most-shipped package of the lot.
local PACKAGE_MODULES = {
	"classic_desktop",
	"compact_pointer",
	"fantasy_ornate",
	"fantasy_parchment",
	"glossy_mobile",
	"glossy_touch",
	"pixel_quest",
	"scifi_hud",
}

local function shippedPackages(): { { id: string, pkg: any } }
	local out: { { id: string, pkg: any } } = { { id = "facet-neutral", pkg = themeSnapshot.neutralPackage() } }
	for _, name in PACKAGE_MODULES do
		local module = require(`../examples/themes/{name}`) :: any
		local pkg, report = module.build(Facet.themes)
		assert(
			pkg ~= nil,
			`{name} failed its own package gate: {report and report.errors[1] and report.errors[1].message}`
		)
		table.insert(out, { id = module.id, pkg = pkg })
	end
	return out
end

--[[ THE CHECK ITSELF, as a function rather than as assertions inline, so the
	mutation test below can point it at a deliberately holed package and watch it
	report. It returns the names that do NOT resolve to art, with the answer each
	one gave, because "missing" and "resolved to a character" are the same defect
	on screen and a bare name would not say which rung failed. ]]
local function uncovered(pkg: any): { string }
	local out: { string } = {}
	for _, name in REQUIRED_ICONS do
		local resolved = themePackage.resolveIcon(pkg, name)
		local source = if type(resolved) == "table" then tostring(resolved.source) else "nothing"
		if source ~= "asset" then
			local drawn = if type(resolved) == "table" and resolved.glyph ~= nil then ` ({resolved.glyph})` else ""
			table.insert(out, `{name} -> {source}{drawn}`)
		end
	end
	return out
end

describe("icon coverage: the pinned name list is the sources' own list", function()
	it("every icon name the sources request is pinned, and every pin is requested", function()
		local required: { [string]: boolean } = {}
		for _, name in REQUIRED_ICONS do
			required[name] = true
		end
		local found = namesInSources()
		-- direction 1, the one that matters: a name a control asks for that is NOT
		-- on the list is a name no package was ever checked against
		local unpinned: { string } = {}
		for name, wheres in found do
			if not required[name] then
				table.insert(unpinned, `{name} (in {table.concat(wheres, ", ")})`)
			end
		end
		table.sort(unpinned)
		expect(`unpinned: {table.concat(unpinned, "; ")}`).toBe("unpinned: ")

		-- direction 2: a pin nothing asks for any more. Not a shipping defect, but
		-- it makes every package answer for a name no screen draws, which is how a
		-- list like this quietly becomes fiction. The literal is looked for across
		-- the same files rather than in the three shapes above, because a request
		-- may be indirect (`spec.icon or "more"`, a table of pairs) and the name
		-- still has to be WRITTEN somewhere in them.
		local corpus = {}
		for _, path in sourceFiles() do
			table.insert(corpus, fs.readFile(path))
		end
		local blob = table.concat(corpus, "\n")
		local unused: { string } = {}
		for _, name in REQUIRED_ICONS do
			if string.find(blob, `"{name}"`, 1, true) == nil then
				table.insert(unused, name)
			end
		end
		table.sort(unused)
		expect(`unused: {table.concat(unused, ", ")}`).toBe("unused: ")
	end)

	it("every required name has framework art AND an ASCII floor beneath it", function()
		-- the two halves of the ladder, asserted at the framework rung so a name
		-- can never be added to one table and forgotten in the other
		local standard = require("../src/themes/standard_icons")
		local holes: { string } = {}
		for _, name in REQUIRED_ICONS do
			if standard.resolve(name) == nil then
				table.insert(holes, `{name}: no framework art`)
			end
			if themePackage.iconGlyph(name) == nil then
				table.insert(holes, `{name}: no ASCII floor`)
			end
		end
		table.sort(holes)
		expect(`holes: {table.concat(holes, "; ")}`).toBe("holes: ")
	end)
end)

describe("icon coverage: every shipped package answers with art", function()
	for _, entry in shippedPackages() do
		it(`{entry.id} resolves all {#REQUIRED_ICONS} names to art`, function()
			expect(`{entry.id} uncovered: {table.concat(uncovered(entry.pkg), "; ")}`).toBe(`{entry.id} uncovered: `)
		end)
	end

	it("the check can FAIL: one icon row removed from a package goes red", function()
		--[[ THE MUTATION, run in-process rather than by editing a file. Pixel Quest
			declines the framework rung (its 4px grid would render a 128px anti-aliased
			silhouette as mush), so its own map is the ONLY rung it has — remove one
			row and that name falls straight to the character. This is the exact shape
			of the shipped defect, reproduced on demand. ]]
		local module = require("../examples/themes/pixel_quest") :: any
		local holed = module.definition(Facet.themes)
		holed.identity.id = "pixel-quest-holed"
		holed.icons["facet:selection.radio.on"] = nil
		local pkg = Facet.themes.define(holed)
		expect(table.concat(uncovered(pkg), "; ")).toBe("facet:selection.radio.on -> glyph (*)")

		--[[ ...and the OTHER way a package loses its art: declining the framework
			rung without a complete map of its own. This is precisely what Glossy Touch
			and Compact Pointer used to ship, so the assertion doubles as the
			regression pin on that decision. ]]
		local glossy = require("../examples/themes/glossy_touch") :: any
		local declining = glossy.definition(Facet.themes)
		declining.identity.id = "glossy-touch-declining"
		declining.identity.standardIcons = false
		local blind = uncovered(Facet.themes.define(declining))
		expect(#blind).toBe(#REQUIRED_ICONS - 1) -- it declares `facet:search` itself
		expect(table.find(blind, "chevron.up.chevron.down -> glyph (^v)") ~= nil).toBe(true)
		expect(table.find(blind, "checkmark -> glyph (v)") ~= nil).toBe(true)
	end)
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- AND ON A REAL SCREEN.
--
-- The two checks above ask the resolver. This one mounts a surface and walks the
-- tree the target actually received, because the resolver answering correctly
-- and the node drawing correctly are different facts: a control authors its own
-- glyph as node text and the adapter paints theme art OVER it, so a hand-written
-- character beside an icon hint (`text = "*"`) is invisible to `resolveIcon` and
-- is exactly what shipped.
local SCENARIO = "selection_controls"

local function scenarioWorld(snapshot: any): any
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
	env:set("themeMetrics", snapshot)
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local presenter = Facet.newPresenter(core, env, adapter, system)
	return { core = core, env = env, adapter = adapter, presenter = presenter, system = system }
end

local function mountScenario(w: any): ()
	local module = require(`../examples/gallery/scenarios/{SCENARIO}`) :: any
	local built = module.build({
		Facet = Facet,
		core = w.core,
		env = w.env,
		adapter = w.adapter,
		presenter = w.presenter,
		actionSystem = w.system,
		record = function() end,
		flags = {},
		geometry = function(): { [string]: any }
			return {}
		end,
		bindResourceTransport = function()
			return function() end
		end,
	})
	if built.handle == nil and built.screen ~= nil then
		built.handle = w.presenter.present(built.screen, built.present)
	end
	assert(built.handle ~= nil, "the scenario presented no screen")
	for _ = 1, 3 do
		w.presenter.refresh()
	end
end

describe(`icon coverage: nothing on a mounted {SCENARIO} paints a fallback character`, function()
	for _, entry in shippedPackages() do
		it(`{entry.id} draws pictures over every icon node`, function()
			local w = scenarioWorld(themeSnapshot.resolve(entry.pkg, nil, {}))
			mountScenario(w)
			local hinted, problems = 0, {}
			for _, path in w.adapter.paths() do
				local node = w.adapter.node(path)
				local hint = if node ~= nil then node.decorationHint else nil
				local name = if type(hint) == "table" then hint.icon else nil
				if type(name) ~= "string" or name == "" then
					continue
				end
				hinted += 1
				local resolved = themePackage.resolveIcon(entry.pkg, name)
				local source = if type(resolved) == "table" then tostring(resolved.source) else "nothing"
				if source ~= "asset" then
					-- no art will ever cover this node, so whatever character it
					-- authored is what the player reads
					table.insert(problems, `{path}: '{name}' resolves to {source}, so its text is the picture`)
					continue
				end
				--[[ ...and the second half, which the resolver cannot see: the character
					BENEATH the art has to be the ladder's own, not one the control invented.
					A literal is un-tintable, un-suppressible and un-resolvable — the `*` and
					`o` a player photographed were literals sitting under names that had no
					art, and had the art existed they would still have been wrong the moment
					it failed to load. ]]
				local text = if type(node.props) == "table" then node.props.text else nil
				local floor = themePackage.iconGlyph(name)
				if type(text) == "string" and text ~= "" and text ~= floor then
					table.insert(
						problems,
						`{path}: '{name}' draws the literal '{text}', not the floor '{tostring(floor)}'`
					)
				end
			end
			expect(`{entry.id}: {table.concat(problems, " | ")}`).toBe(`{entry.id}: `)
			-- a walk that found no icon node proves nothing at all
			expect(hinted > 0).toBe(true)
		end)
	end
end)
