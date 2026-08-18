--!strict
-- GALLERY THEME PICKER (director review 2026-07-25: "no idea how to swap
-- themes"). The overlay itself is proved live in Studio — it is an engine
-- surface. What is proved HERE is the part that decides things: the listing a
-- player reads and the command a click turns into.
--
-- That split matters. Every bug this model can have is a reasoning bug — a row
-- in the wrong order, a swap fired at the package already installed, a theme
-- name handed to a package that never declared it — and none of them need an
-- engine to catch.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local theme_picker = require("../examples/gallery/client/theme_picker")

local themes = Facet.themes

local function packages(): { [string]: any }
	return {
		-- deliberately NOT in display order: the listing has to sort
		scifi_hud = (require("../examples/themes/scifi_hud") :: any).build(themes),
		classic_desktop = (require("../examples/themes/classic_desktop") :: any).build(themes),
		fantasy_parchment = (require("../examples/themes/fantasy_parchment") :: any).build(themes),
	}
end

describe("theme picker: the listing a player reads", function()
	it("puts Studio Neutral first, always, and sorts the rest by display name", function()
		local entries = theme_picker.listing(packages(), themes.neutralPackage())
		expect(entries[1].id).toBe(theme_picker.NEUTRAL_ID)
		expect(entries[1].displayName).toBe("Studio Neutral")
		-- "put it back the way it was" is one click and never depends on a module
		-- having replicated
		local names: { string } = {}
		for index = 2, #entries do
			table.insert(names, entries[index].displayName)
		end
		local sorted = table.clone(names)
		table.sort(sorted)
		expect(table.concat(names, "|")).toBe(table.concat(sorted, "|"))
		expect(#entries).toBe(4)
	end)

	it("carries each package's own themes as the second level", function()
		local entries = theme_picker.listing(packages(), themes.neutralPackage())
		local parchment = theme_picker.find(entries, "fantasy-parchment")
		expect(parchment ~= nil).toBe(true)
		expect(table.concat(parchment.themes, "|")).toBe("Daylight|Candlelight")
		expect(parchment.moduleName).toBe("fantasy_parchment")
		-- the built-in package is not a module at all
		expect(entries[1].moduleName).toBeNil()
	end)

	it("keeps the first module that claims an id — two rows would fight over one sheet", function()
		local pkgs = packages()
		pkgs.a_duplicate = pkgs.fantasy_parchment
		local entries = theme_picker.listing(pkgs, themes.neutralPackage())
		expect(#entries).toBe(4)
		expect(theme_picker.find(entries, "fantasy-parchment").moduleName).toBe("a_duplicate")
	end)

	it("ignores anything under the folder that is not a compiled package", function()
		local entries = theme_picker.listing({ junk = "not a package", other = {} }, themes.neutralPackage())
		expect(#entries).toBe(1)
	end)

	it("starts on what the gallery is already showing, so it never lies about state", function()
		local entries = theme_picker.listing(packages(), themes.neutralPackage())
		local start = theme_picker.initialSelection(entries)
		expect(start.packageId).toBe(theme_picker.NEUTRAL_ID)
		expect(start.theme).toBe(themes.neutralPackage().style.defaultTheme)
		expect(theme_picker.themesFor(entries, start)[1]).toBe("Dark")
	end)
end)

describe("theme picker: what a click asks the controller to do", function()
	local entries = theme_picker.listing(packages(), themes.neutralPackage())
	local start = theme_picker.initialSelection(entries)

	it("selecting a different package swaps to THAT package's own default theme", function()
		local command = theme_picker.choosePackage(entries, start, "fantasy-parchment")
		expect(command.action).toBe("swapPackage")
		expect(command.selection.packageId).toBe("fantasy-parchment")
		-- never the outgoing package's theme name: "Dark" means nothing to
		-- Fantasy Parchment, and asking for it is an error the controller raises
		expect(command.selection.theme).toBe("Daylight")
		expect(command.package.identity.id).toBe("fantasy-parchment")
	end)

	it("selecting the package already installed is a NO-OP, not a redundant swap", function()
		-- swapPackage re-materializes a sheet and re-resolves a snapshot; doing
		-- that on every click of the active row would churn the live surface
		expect(theme_picker.choosePackage(entries, start, theme_picker.NEUTRAL_ID).action).toBe("none")
	end)

	it("an unknown package id changes nothing", function()
		local command = theme_picker.choosePackage(entries, start, "no-such-package")
		expect(command.action).toBe("none")
		expect(command.selection.packageId).toBe(start.packageId)
	end)

	it("selecting a theme of the active package swaps within it", function()
		local live = { packageId = "fantasy-parchment", theme = "Daylight" }
		local command = theme_picker.chooseTheme(entries, live, "Candlelight")
		expect(command.action).toBe("swap")
		expect(command.selection.theme).toBe("Candlelight")
		expect(command.selection.packageId).toBe("fantasy-parchment")
	end)

	it("a theme the active package never declared is refused HERE, not thrown there", function()
		local live = { packageId = "fantasy-parchment", theme = "Daylight" }
		expect(theme_picker.chooseTheme(entries, live, "Candlelit").action).toBe("none")
		-- ...including a name that belongs to a DIFFERENT package
		expect(theme_picker.chooseTheme(entries, live, "Dark").action).toBe("none")
		expect(theme_picker.chooseTheme(entries, live, "Daylight").action).toBe("none")
	end)

	it("the second level follows the selection", function()
		local live = { packageId = "fantasy-parchment", theme = "Daylight" }
		expect(#theme_picker.themesFor(entries, live)).toBe(2)
		expect(#theme_picker.themesFor(entries, { packageId = "nope", theme = "x" })).toBe(0)
	end)
end)

describe("theme picker: which packages a director can actually reach", function()
	-- P5 (rich-skinning-v2): the four reference packages have to be one click
	-- away, because the readability row (RS-P1) and the phone pass (RS-P2) are
	-- HUMAN rows and a human should never need a command bar to see the skin.
	it("lists every shipping reference package, and none of the fixtures", function()
		local modules = {
			fantasy_ornate = require("../examples/themes/fantasy_ornate") :: any,
			pixel_quest = require("../examples/themes/pixel_quest") :: any,
			glossy_touch = require("../examples/themes/glossy_touch") :: any,
			compact_pointer = require("../examples/themes/compact_pointer") :: any,
			fantasy_parchment = require("../examples/themes/fantasy_parchment") :: any,
			-- the deliberately-degenerate ones the acceptance scenarios install BY
			-- NAME: a picker whose rows are broken-on-purpose packages misrepresents
			-- the framework to the one audience that judges it by looking
			layered_test = require("../examples/themes/layered_test") :: any,
			content_alias_test = require("../examples/themes/content_alias_test") :: any,
		}
		local pkgs: { [string]: any } = {}
		for name, module in modules do
			if theme_picker.isPickable(module) then
				pkgs[name] = module.build(themes)
			end
		end
		local entries = theme_picker.listing(pkgs, themes.neutralPackage())
		expect(#entries).toBe(6) -- Studio Neutral + the five shipping packages
		for _, id in { "fantasy-ornate", "pixel-quest", "glossy-touch", "compact-pointer", "fantasy-parchment" } do
			expect(theme_picker.find(entries, id) ~= nil).toBe(true)
		end
		expect(theme_picker.find(entries, "layered-test")).toBeNil()
		expect(theme_picker.find(entries, "content-alias-test")).toBeNil()
	end)

	it("isPickable reads the MODULE, because testOnly is a property of the file", function()
		expect(theme_picker.isPickable({ build = function() end })).toBe(true)
		expect(theme_picker.isPickable({ build = function() end, testOnly = true })).toBe(false)
		-- anything under the folder that is not a theme module at all
		expect(theme_picker.isPickable({ testOnly = false })).toBe(false)
		expect(theme_picker.isPickable("not a module")).toBe(false)
	end)

	it("the ornate package carries two themes into the second level", function()
		local ornate = (require("../examples/themes/fantasy_ornate") :: any).build(themes)
		local entries = theme_picker.listing({ fantasy_ornate = ornate }, themes.neutralPackage())
		local row = theme_picker.find(entries, "fantasy-ornate")
		expect(table.concat(row.themes, "|")).toBe("Grand Hall|Crypt")
		-- selecting it swaps to ITS default, never the outgoing package's theme
		local start = theme_picker.initialSelection(entries)
		expect(theme_picker.choosePackage(entries, start, "fantasy-ornate").selection.theme).toBe("Grand Hall")
	end)
end)

describe("theme picker: it stays out of the library", function()
	it("is an EXAMPLE and reaches the framework only through public surface", function()
		local fs = require("@lune/fs")
		expect(fs.isFile("examples/gallery/client/theme_picker.luau")).toBe(true)
		local source = fs.readFile("examples/gallery/client/theme_picker.luau")
		-- no internal imports: a game team copies this file as-is
		expect(string.find(source, 'require("../../../src', 1, true)).toBeNil()
		expect(string.find(source, "src/tokens", 1, true)).toBeNil()
		-- and it names the hide switch the gallery documents
		expect(theme_picker.ATTRIBUTE).toBe("Facet_ThemePicker")
		local bootstrap = fs.readFile("examples/gallery/client/init.client.luau")
		expect(string.find(bootstrap, "theme_picker.ATTRIBUTE", 1, true) ~= nil).toBe(true)
		-- the discovery site is where testOnly is read (see isPickable): a filter
		-- that lives only in this spec would filter nothing on a running screen
		expect(string.find(bootstrap, "theme_picker.isPickable", 1, true) ~= nil).toBe(true)
		-- PASSIVE, so it cannot steal focus from the fixture it sits over
		expect(string.find(source, 'responder = "passive"', 1, true) ~= nil).toBe(true)
	end)
end)

-- ===== the box and the spacing the director judged ==========================
-- PICKER-POLISH round, 2026-07-26: "clear negative space between the grid's
-- bottom row and the Day/Night toggle beneath it" and "chip heights reduced —
-- they read taller than needed, especially at desktop density".
--
-- Both are GEOMETRY, so both are asserted as geometry: the real overlay is
-- mounted through the real presenter onto a headless target under each
-- reference package's own resolved snapshot, and the solved rects are read
-- back. Only the theme CONTROLLER is stubbed — it is the one seam that needs
-- Roblox — and the metric fact it would publish (`themeMetrics`) is set
-- directly, which is exactly what its `install`/`swapPackage` do.
--
-- What this cannot see is the ENGINE's own text raster, which is why the round
-- also drove the four packages live. What it CAN see is every decision:
-- which metric the height comes from, that the width did not move, and that the
-- section gap is the one the panel authored.

local fake_target = require("./lib/fake_target")
local snapshot = require("../src/themes/snapshot")

local PICKABLE = {
	classic_desktop = require("../examples/themes/classic_desktop"),
	scifi_hud = require("../examples/themes/scifi_hud"),
	glossy_mobile = require("../examples/themes/glossy_mobile"),
	glossy_touch = require("../examples/themes/glossy_touch"),
	compact_pointer = require("../examples/themes/compact_pointer"),
	fantasy_ornate = require("../examples/themes/fantasy_ornate"),
	fantasy_parchment = require("../examples/themes/fantasy_parchment"),
	pixel_quest = require("../examples/themes/pixel_quest"),
}

local function pickablePackages(): { [string]: any }
	local out: { [string]: any } = {}
	for name, module in PICKABLE do
		if theme_picker.isPickable(module) then
			out[name] = (module :: any).build(themes)
		end
	end
	return out
end

local function stubController(): any
	return {
		inspect = function()
			return { fallback = false }
		end,
		swap = function() end,
		swapPackage = function() end,
		uninstall = function() end,
	}
end

-- ===========================================================================
-- COMPOSED PIECES CARRY THEIR OWN BEHAVIOUR
-- ===========================================================================
--
-- Three device rounds on one cause. `presenter.dispatchActivate` says it plainly:
-- "when opts.onActivate IS present it wins outright (override)" — it runs and
-- returns, so NO node on that surface reaches its own `props.onActivate`.
--
-- This picker used to route its rows by matching `P_`/`T_` out of the path in a
-- surface-level handler. That works right up until something else shares the
-- surface, and then the router answers for the neighbours too — by doing
-- nothing. Composed into the showcase chrome it killed both chips ("I click
-- Studio Neutral, nothing happens"); a re-present that dropped the override had
-- the mirror-image effect, chips alive and rows dead.
--
-- Behaviour therefore lives on the NODES. It cannot be dropped by a re-present
-- and it cannot be swallowed by a sibling's router. These cases assert the
-- structure rather than the pixels, so the guarantee is checked headlessly.
describe("theme picker: composed pieces carry their own handlers", function()
	local function composed(): any
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 800 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		env:set("themeMetrics", snapshot.resolve(themes.neutralPackage(), nil, {}))
		local adapter = fake_target.new()
		local presenter = Facet.newPresenter(core, env, adapter, Facet.newActionSystem(core))
		return theme_picker.mount({
			Facet = Facet,
			core = core,
			env = env,
			adapter = adapter,
			presenter = presenter,
			packages = pickablePackages(),
			themeController = { install = stubController },
			collapsible = true,
			composed = true,
			warn = function() end,
		})
	end

	local function findByIdPrefix(bp: any, prefix: string): any
		if type(bp) ~= "table" then
			return nil
		end
		local id = bp.id or (bp.props and bp.props.id)
		if type(id) == "string" and string.sub(id, 1, #prefix) == prefix then
			return bp
		end
		local kids = (bp.props and bp.props.children) or bp.children
		if type(kids) == "table" then
			for _, child in kids do
				local hit = findByIdPrefix(child, prefix)
				if hit ~= nil then
					return hit
				end
			end
		end
		return nil
	end

	it("hands back a chip whose activation is on the chip itself", function()
		local m = composed()
		local handler = m.chip.props.onActivate
		expect(type(handler)).toBe("function")
		-- and it really is the open/close, not a placeholder
		expect(m.open:get()).toBe(false)
		handler()
		expect(m.open:get()).toBe(true)
		handler()
		expect(m.open:get()).toBe(false)
		m.dispose()
	end)

	it("puts a handler on every package row, so no path router is needed", function()
		local m = composed()
		local row = findByIdPrefix(m.panel, "P_")
		expect(row ~= nil).toBe(true)
		expect(type(row.props.onActivate)).toBe("function")
		m.dispose()
	end)

	it("changes the selection when a package row's own handler runs", function()
		local m = composed()
		local before = m.selection:get().packageId
		local other
		for _, entry in m.entries do
			if entry.id ~= before then
				other = entry.id
				break
			end
		end
		expect(other ~= nil).toBe(true)
		local row = findByIdPrefix(m.panel, `P_{other}`)
		expect(row ~= nil).toBe(true)
		row.props.onActivate()
		expect(m.selection:get().packageId).toBe(other)
		m.dispose()
	end)
end)

-- mount the picker under `pkg`'s metrics and return the solved geometry
local function pickerUnder(pkg: any, w: number, h: number): any
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = w, h = h })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	env:set("themeMetrics", snapshot.resolve(pkg, nil, {}))
	local adapter = fake_target.new()
	local presenter = Facet.newPresenter(core, env, adapter, Facet.newActionSystem(core))
	local mounted = theme_picker.mount({
		Facet = Facet,
		core = core,
		env = env,
		adapter = adapter,
		presenter = presenter,
		packages = pickablePackages(),
		themeController = { install = stubController },
		warn = function() end,
	})
	presenter.refresh()

	local chips: { any } = {}
	for _, path in adapter.paths() do
		local node = adapter.node(path)
		if node.class == "Button" and string.find(path, "/Packages/", 1, true) ~= nil and node.rect ~= nil then
			table.insert(chips, node.rect)
		end
	end
	local choose = adapter.node("/GalleryThemePicker/Dock/Panel/Choose").rect
	local themeRow = adapter.node("/GalleryThemePicker/Dock/Panel/Themes").rect
	-- the grid's own two pitches, read off the solved chips rather than from the
	-- declaration: group the cells by row (`adapter.paths()` has no ordering
	-- promise), count the first row, and measure the vertical space BETWEEN the
	-- first two rows.
	local byRow: { [number]: number } = {}
	local ys: { number } = {}
	local heightOf: { [number]: number } = {}
	for _, rect in chips do
		if byRow[rect.y] == nil then
			byRow[rect.y] = 0
			table.insert(ys, rect.y)
			heightOf[rect.y] = rect.h
		end
		byRow[rect.y] += 1
		heightOf[rect.y] = math.max(heightOf[rect.y], rect.h)
	end
	table.sort(ys)
	local columns = if #ys > 0 then byRow[ys[1]] else 0
	local rowPitch = if #ys > 1 then ys[2] - (ys[1] + heightOf[ys[1]]) else nil
	return {
		columns = columns,
		rowPitch = rowPitch,
		adapter = adapter,
		snap = snapshot.resolve(pkg, nil, {}),
		chips = chips,
		-- the negative space the director asked for: the bottom of the package
		-- section to the top of the theme row
		gap = themeRow.y - (choose.y + choose.h),
		panel = adapter.node("/GalleryThemePicker/Dock/Panel").rect,
		dispose = function()
			mounted.dispose()
		end,
	}
end

-- the OLD box, for the A/B the director's complaint names. Restored immediately;
-- `chip()` reads the constant when it builds, so a mount inside this sees it.
local function withChipPadding(padding: any, fn: () -> ())
	local saved = theme_picker.CHIP_PADDING
	theme_picker.CHIP_PADDING = padding
	local ok, err = pcall(fn)
	theme_picker.CHIP_PADDING = saved
	if not ok then
		error(err, 0)
	end
end

describe("theme picker: the chip is its package's control metric, not a padded guess", function()
	-- the four packages the round drove live, all FLAT (no skin content insets),
	-- so the chip lands EXACTLY on the package's own compact control height
	local FLAT = {
		{ id = "studio-neutral", package = nil, height = 36 },
		{ id = "classic-desktop", package = "classic_desktop", height = 22 },
		{ id = "sci-fi-hud", package = "scifi_hud", height = 32 },
		{ id = "glossy-mobile", package = "glossy_mobile", height = 44 },
	}

	local function packageOf(name: string?): any
		return if name == nil then themes.neutralPackage() else (PICKABLE[name] :: any).build(themes)
	end

	it("solves every chip to the ACTIVE package's compact control height", function()
		for _, row in FLAT do
			local live = pickerUnder(packageOf(row.package), 1233, 1067)
			expect(#live.chips).toBe(9)
			for _, rect in live.chips do
				-- uniform cells: one size for all of them (round 9's ruling)
				expect(rect.h).toBe(row.height)
			end
			-- and that height is the METRIC, not a literal this test restates
			expect(row.height).toBe(live.snap.controlSizes.compact.height)
			live.dispose()
		end
	end)

	it("is SHORTER than the 12px-padded box it replaced, at the same width", function()
		-- the director's complaint, measured: a Button's default padding is
		-- `controls.button.padding` = 12 on all four sides and no reference package
		-- authors it, so the vertical pair was the same 12 under a 13px desktop
		-- ladder as under a 17px touch one and the compact-height floor never
		-- decided anything.
		for _, row in FLAT do
			local pkg = packageOf(row.package)
			local before: any = nil
			withChipPadding(12, function()
				local old = pickerUnder(pkg, 1233, 1067)
				before = { h = old.chips[1].h, w = old.chips[1].w }
				old.dispose()
			end)
			local live = pickerUnder(pkg, 1233, 1067)
			expect(live.chips[1].h < before.h).toBe(true)
			-- WIDTH IS UNTOUCHED: the horizontal padding is still the theme's
			-- button padding, so round 9's measured intrinsic columns — and the
			-- director's approved column count — cannot move
			expect(live.chips[1].w).toBe(before.w)
			live.dispose()
		end
	end)

	it("holds the package's own line box in every reference package, skinned ones included", function()
		-- unclipped is a HEIGHT claim here: the box has to hold one line of the
		-- Button's intrinsic type role at that role's leading, plus the vertical
		-- padding, plus whatever a nine-slice skin reserves for its carved border
		local names: { string } = { "studio-neutral" }
		for name in PICKABLE do
			table.insert(names, name)
		end
		table.sort(names)
		for _, name in names do
			local pkg = if name == "studio-neutral"
				then themes.neutralPackage()
				else (PICKABLE[name] :: any).build(themes)
			local live = pickerUnder(pkg, 1233, 1067)
			local role = live.snap.type[snapshot.INTRINSIC_TEXT_ROLE.Button]
			-- the SELECTION slot, not the control one: the chip declares `selected`
			-- (director finding 12), so a skinned package reserves the room its
			-- selection plate carves rather than its button plate's
			local inset = (live.snap.chromeInsets or {}).selection
			local needed = math.ceil(role.size * role.lineHeight)
				+ 2 * live.snap.space.xs
				+ (if inset ~= nil then inset.top + inset.bottom else 0)
			expect(live.chips[1].h >= needed).toBe(true)
			-- ...and it never falls under the package's own control metric
			expect(live.chips[1].h >= live.snap.controlSizes.compact.height).toBe(true)
			live.dispose()
		end
	end)

	it("stays a FLOOR: a chip whose label has to wrap still grows", function()
		-- round 9's defect, re-guarded. A `fixed` height clipped "Classic Desktop"
		-- to "Classic" and overflowed sci-fi's plate into its neighbours; the
		-- tighter padding must not turn the floor back into a ceiling.
		expect(theme_picker.CHIP_HEIGHT.type).toBe("minMax")
		expect(theme_picker.CHIP_HEIGHT.min).toBe("controlSizes.compact.height")
		expect(theme_picker.CHIP_HEIGHT.max).toBeNil()
		local pkg = (PICKABLE.classic_desktop :: any).build(themes)
		local wide = pickerUnder(pkg, 1233, 1067)
		local narrow = pickerUnder(pkg, 260, 900)
		expect(narrow.chips[1].h > wide.chips[1].h).toBe(true)
		expect(narrow.chips[1].h > narrow.snap.controlSizes.compact.height).toBe(true)
		wide.dispose()
		narrow.dispose()
	end)
end)

describe("theme picker: the two questions are separated, not stacked", function()
	it("puts the package section and the theme row a SECTION gap apart", function()
		local names: { string } = { "studio-neutral" }
		for name in PICKABLE do
			table.insert(names, name)
		end
		table.sort(names)
		for _, name in names do
			local pkg = if name == "studio-neutral"
				then themes.neutralPackage()
				else (PICKABLE[name] :: any).build(themes)
			local live = pickerUnder(pkg, 1233, 1067)
			local expected = snapshot.resolveNumber(live.snap, theme_picker.SECTION_GAP)
			expect(live.gap).toBe(expected)
			-- and it READS as a break: bigger than the gap between two chips, which
			-- is what made the theme row look like one more row of the grid
			expect(live.gap > theme_picker.GRID_GAP).toBe(true)
			expect(live.gap >= 2 * snapshot.resolveNumber(live.snap, theme_picker.ROW_GAP)).toBe(true)
			live.dispose()
		end
	end)

	it("keeps the caption attached to the grid it labels", function()
		-- the title is part of the FIRST question, so it keeps the tight row gap
		-- while the section gap separates the two questions
		local live = pickerUnder(themes.neutralPackage(), 1233, 1067)
		local title = live.adapter.node("/GalleryThemePicker/Dock/Panel/Choose/Title").rect
		local grid = live.adapter.node("/GalleryThemePicker/Dock/Panel/Choose/Packages").rect
		expect(grid.y - (title.y + title.h)).toBe(snapshot.resolveNumber(live.snap, theme_picker.ROW_GAP))
		-- the group is a grouping, not a size: the grid still gets the panel's
		-- full inner width (round 9 §9a-iii)
		local panel = live.panel
		local choose = live.adapter.node("/GalleryThemePicker/Dock/Panel/Choose").rect
		expect(choose.w).toBe(grid.w)
		expect(choose.x + choose.w <= panel.x + panel.w).toBe(true)
		live.dispose()
	end)

	it("spends METRIC NAMES, so a swap moves the spacing with the package", function()
		-- the picker is repainted by the package it installs; a literal gap would
		-- stay a desktop gap on a touch package
		expect(snapshot.isSpaceStep(theme_picker.SECTION_GAP)).toBe(true)
		expect(snapshot.isSpaceStep(theme_picker.ROW_GAP)).toBe(true)
		expect(snapshot.isSpaceStep(theme_picker.CHIP_PADDING.top)).toBe(true)
		expect(snapshot.isSpaceStep(theme_picker.CHIP_PADDING.bottom)).toBe(true)
		expect(snapshot.isMetricPath(theme_picker.CHIP_PADDING.left)).toBe(true)
		expect(snapshot.isMetricPath(theme_picker.CHIP_PADDING.right)).toBe(true)
		expect(snapshot.isMetricPath(theme_picker.CHIP_HEIGHT.min)).toBe(true)
		-- the horizontal pair IS the Button default, named rather than copied
		local neutral = snapshot.neutral()
		expect(snapshot.resolveNumber(neutral, theme_picker.CHIP_PADDING.left)).toBe(neutral.controls.button.padding)
		-- ...and the grid's own gap is the one deliberate literal (the column
		-- count is a director ruling; a theme-owned gap would re-column on a swap)
		expect(type(theme_picker.GRID_GAP)).toBe("number")

		local fs = require("@lune/fs")
		local source = fs.readFile("examples/gallery/client/theme_picker.luau")
		-- the constants are what the overlay actually builds with
		expect(string.find(source, "gap = theme_picker.SECTION_GAP", 1, true) ~= nil).toBe(true)
		expect(string.find(source, "height = theme_picker.CHIP_HEIGHT", 1, true) ~= nil).toBe(true)
		expect(string.find(source, "padding = theme_picker.CHIP_PADDING", 1, true) ~= nil).toBe(true)
	end)
end)

describe("RS-DIR14: the picker's grid rows breathe with the installed package", function()
	-- DIRECTOR FINDING 14 (2026-07-26): "the picker grid needs more VERTICAL
	-- space between rows, especially studio-neutral and compact-pointer".
	--
	-- Measured live at the reported stamp, studio-neutral 1233x1067: ten 196x36
	-- chips, rows **4 px** apart and columns **78 px** apart, because a grid's
	-- column pitch is `innerWidth / columns` while its row pitch IS the gap. The
	-- literal 4 was protecting the column count (a director ruling) and paying
	-- for it with the rows.
	--
	-- The row gap is now the package's own `s` step — the smallest step that is
	-- at least the old literal under every reference package and grows with a
	-- denser-target ladder: studio-neutral 8, classic-desktop 4, compact-pointer
	-- 6, sci-fi 8, glossy-mobile/touch 10, ornate/parchment 8, pixel-quest 8.
	local EXPECTED_ROW_GAP = {
		["studio-neutral"] = 8,
		classic_desktop = 4,
		scifi_hud = 8,
		glossy_mobile = 10,
		glossy_touch = 10,
		compact_pointer = 6,
		fantasy_ornate = 8,
		fantasy_parchment = 8,
		pixel_quest = 8,
	}

	local function packageOf(name: string): any
		return if name == "studio-neutral" then themes.neutralPackage() else (PICKABLE[name] :: any).build(themes)
	end

	-- the A/B: mount the same picker with the row gap the literal used to give
	local function withGridRowGap(value: any, fn: () -> any): any
		local saved = theme_picker.GRID_ROW_GAP
		theme_picker.GRID_ROW_GAP = value
		local ok, result = pcall(fn)
		theme_picker.GRID_ROW_GAP = saved
		if not ok then
			error(result, 0)
		end
		return result
	end

	it("spaces the rows by the ACTIVE package's `s` step, in every reference package", function()
		for name, expected in EXPECTED_ROW_GAP do
			local live = pickerUnder(packageOf(name), 1233, 1067)
			expect(live.rowPitch).toBe(expected)
			-- and it IS the metric, not a literal this test restates
			expect(expected).toBe(snapshot.resolveNumber(live.snap, theme_picker.GRID_ROW_GAP))
			live.dispose()
		end
	end)

	it("never narrows the vertical air the literal used to give", function()
		-- the complaint was cramped rows; a package whose `s` is SMALLER than the
		-- old literal would be a regression dressed up as a fix
		for name in EXPECTED_ROW_GAP do
			local live = pickerUnder(packageOf(name), 1233, 1067)
			expect(live.rowPitch >= theme_picker.GRID_GAP).toBe(true)
			live.dispose()
		end
	end)

	it("leaves every chip BOX and the column count exactly where the director approved them", function()
		-- the ruling being protected: the approved column count and chip boxes
		-- that are the package's own control metric (the picker-polish round).
		-- Only the rows may move.
		--
		-- The count itself is an A/B rather than a pinned number: a headless solve
		-- has no engine text widths, so its chips are the estimator's conservative
		-- boxes and its column count is not the live one (the live counts are in
		-- the round's Studio trace). What IS provable here is the property the
		-- ruling needs — that the row gap cannot reach the column arithmetic.
		local HEIGHTS = { ["studio-neutral"] = 36, classic_desktop = 22, scifi_hud = 32, glossy_mobile = 44 }
		for name, height in HEIGHTS do
			local live = pickerUnder(packageOf(name), 1233, 1067)
			for _, rect in live.chips do
				expect(rect.h).toBe(height)
			end
			local before = withGridRowGap(theme_picker.GRID_GAP, function()
				local old = pickerUnder(packageOf(name), 1233, 1067)
				local shot = { columns = old.columns, w = old.chips[1].w, h = old.chips[1].h, x = old.chips[1].x }
				old.dispose()
				return shot
			end)
			expect(live.columns).toBe(before.columns)
			expect(live.chips[1].w).toBe(before.w)
			expect(live.chips[1].h).toBe(before.h)
			expect(live.chips[1].x).toBe(before.x)
			live.dispose()
		end
	end)

	it("spends a METRIC NAME for the row gap and a LITERAL for the column gap", function()
		-- the column gap stays a literal on purpose: it feeds `minColumnWidth`'s
		-- arithmetic, and a theme-owned column gap would re-column the grid on a
		-- swap. The row gap cannot reach that arithmetic at all.
		expect(snapshot.isSpaceStep(theme_picker.GRID_ROW_GAP)).toBe(true)
		expect(type(theme_picker.GRID_GAP)).toBe("number")
		local fs = require("@lune/fs")
		local source = fs.readFile("examples/gallery/client/theme_picker.luau")
		expect(string.find(source, "rowGap = theme_picker.GRID_ROW_GAP", 1, true) ~= nil).toBe(true)
	end)

	it("keeps the grid's own solved height honest about the taller rows", function()
		-- the panel has to GROW: rows that are further apart and a grid that
		-- reports its old height would push the theme row under the last chips
		local tight = pickerUnder(packageOf("studio-neutral"), 1233, 1067)
		local grid = tight.adapter.node("/GalleryThemePicker/Dock/Panel/Choose/Packages").rect
		local last = tight.chips[#tight.chips]
		expect(last.y + last.h <= grid.y + grid.h).toBe(true)
		local themeRow = tight.adapter.node("/GalleryThemePicker/Dock/Panel/Themes").rect
		expect(themeRow.y >= grid.y + grid.h).toBe(true)
		tight.dispose()
	end)
end)

-- ===========================================================================
-- THE PANEL HUGS ITS LIST, AND SCROLLS WHEN THE LIST IS TALLER THAN THE PHONE
-- (director round 10, found live 2026-07-26 on an iPhone)
--
-- The composed panel was `fill` on both axes, which is "as big as the space"
-- rather than "as big as the list". Under Studio Neutral the ten themes ended
-- less than halfway down a raised plate that ran to the bottom of the screen,
-- and the card was the full width of the phone with the rows inset inside it.
-- Under Fantasy Ornate — taller rows, a 30px carved frame — the OTHER half
-- showed: the list ran off the bottom of the viewport and did NOT scroll,
-- because a `fill` box is by definition never smaller than its content, so the
-- overflow that turns scrolling on never registered.
-- ===========================================================================
describe("theme picker: the composed panel hugs, and scrolls when it must", function()
	local function panelUnder(viewportH: number, pkg: any?): any
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 320, h = viewportH })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		env:set("themeMetrics", snapshot.resolve(pkg or themes.neutralPackage(), nil, {}))
		local adapter = fake_target.new()
		local presenter = Facet.newPresenter(core, env, adapter, Facet.newActionSystem(core))
		local mounted = theme_picker.mount({
			Facet = Facet,
			core = core,
			env = env,
			adapter = adapter,
			presenter = presenter,
			packages = pickablePackages(),
			themeController = { install = stubController },
			collapsible = true,
			composed = true,
			warn = function() end,
		})
		presenter.present(Facet.UI.Screen({ id = "Host", children = { mounted.panel } }))
		presenter.refresh()
		return adapter.node("/Host/Panel"), mounted.panel
	end

	it("the panel declares `hug` on BOTH axes, not fill", function()
		-- the declaration is the fix; the two behaviours below are what it buys
		local _, blueprint = panelUnder(800)
		expect(blueprint.props.width.type).toBe("hug")
		expect(blueprint.props.height.type).toBe("hug")
	end)

	it("with room to spare the card stops at its last row instead of running to the floor", function()
		local node = panelUnder(1200)
		expect(node.rect.h < 1200).toBe(true)
		-- and it is not merely "a bit" short: the empty plate the director
		-- photographed was more than half the card
		expect(node.rect.h < 1200 * 0.75).toBe(true)
	end)

	it("the card is as WIDE as its chips, not as wide as the phone", function()
		local node = panelUnder(1200)
		-- the grid inside is `itemSizing = "uniform"`, so it draws every chip at
		-- the widest MEASURED chip and no wider. The card used to be the full
		-- offer with that narrow column of chips sitting inside it.
		expect(node.rect.w < 320).toBe(true)
	end)

	it("...and inside the SHOWCASE'S OWN chrome column, under the chip row", function()
		-- director round 11, 2026-07-27. The three tests above mount the panel
		-- directly under a Screen, and it hugged correctly there — which is why
		-- they passed while the phone showed a card running off the bottom. The
		-- host does not mount it directly: it sits in a `fill`-height column,
		-- BELOW a row of chips, inside an offset Anchor. A `hug` child used to be
		-- measured against that column's whole height rather than the part its
		-- siblings had left it, so it overflowed by exactly the chip row.
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 390, h = 500 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		env:set("themeMetrics", snapshot.resolve(themes.neutralPackage(), nil, {}))
		local adapter = fake_target.new()
		local presenter = Facet.newPresenter(core, env, adapter, Facet.newActionSystem(core))
		local mounted = theme_picker.mount({
			Facet = Facet,
			core = core,
			env = env,
			adapter = adapter,
			presenter = presenter,
			packages = pickablePackages(),
			themeController = { install = stubController },
			collapsible = true,
			composed = true,
			warn = function() end,
		})
		local UI = Facet.UI
		presenter.present(UI.Screen({
			id = "ShowcaseChrome",
			children = {
				UI.Anchor({
					id = "Dock",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.VStack({
							id = "Bar",
							anchor = "topLeft",
							offsetY = 20, -- the CoreGui topbar reservation the host carries
							width = { type = "fill", weight = 1 },
							height = { type = "fill", weight = 1 },
							gap = "s",
							children = {
								UI.HStack({ id = "Chips", gap = "s", children = { mounted.chip } }),
								mounted.panel,
							},
						}),
					},
				}),
			},
		}))
		presenter.refresh()
		local bar = adapter.node("/ShowcaseChrome/Dock/Bar").rect
		local panel = adapter.node("/ShowcaseChrome/Dock/Bar/Panel").rect
		-- the panel ends inside its own column...
		expect(panel.y + panel.h <= bar.y + bar.h).toBe(true)
		-- ...and inside the viewport, which is the thing the phone showed
		expect(panel.y + panel.h <= 500).toBe(true)
	end)

	it("on a short screen it stops at the viewport and SCROLLS instead of running off it", function()
		local node = panelUnder(240)
		expect(node.rect.h <= 240).toBe(true)
		-- the canvas keeps the truth, so the engine has something to scroll
		expect(node.scrollRegion ~= nil).toBe(true)
		expect(node.scrollRegion.contentH > node.rect.h).toBe(true)
	end)
end)

-- ============================================================================
-- THE STANDALONE COLLAPSED SHELL (example-quality-pass, 2026-08-06).
--
-- The tutorial-example host used to mount the picker EXPANDED, over the example.
-- Measured live on desktop: the panel occupied `x 339..899, y 8..219` while
-- example 01's text field occupied `x 16..891, y 78..122`, so the picker covered
-- most of the primary control of the example it exists to restyle; on a 360x691
-- phone it covered the example entirely.
--
-- `collapsible = true` without `composed` was previously unreachable — every
-- caller paired the two — so the shell carried the SHOWCASE's geometry: docked
-- top-left and lifted `-BAR_HEIGHT` into a strip only the showcase reserves.
-- These cases pin the standalone shape: collapsed by default, docked top-right,
-- no lift, and a chip that opens the panel with no remount.
-- ============================================================================
describe("theme picker: the standalone collapsed shell stays out of the example's way", function()
	local function collapsed(w: number, h: number): any
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = w, h = h })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		env:set("themeMetrics", snapshot.resolve(themes.neutralPackage(), nil, {}))
		local adapter = fake_target.new()
		local presenter = Facet.newPresenter(core, env, adapter, Facet.newActionSystem(core))
		local mounted = theme_picker.mount({
			Facet = Facet,
			core = core,
			env = env,
			adapter = adapter,
			presenter = presenter,
			packages = pickablePackages(),
			themeController = { install = stubController },
			collapsible = true,
			warn = function() end,
		})
		presenter.refresh()
		return { adapter = adapter, presenter = presenter, mounted = mounted, w = w, h = h }
	end

	it("starts COLLAPSED: the panel is not mounted at all", function()
		local s = collapsed(907, 986)
		expect(s.adapter.node("/GalleryThemePicker/Dock/Shell/Toggle") ~= nil).toBe(true)
		expect(s.adapter.node("/GalleryThemePicker/Dock/Shell/PanelWhen/then/Panel")).toBe(nil)
		s.mounted.dispose()
	end)

	it("docks top-RIGHT, so it cannot sit on a top-left example title", function()
		local s = collapsed(907, 986)
		local chip = s.adapter.node("/GalleryThemePicker/Dock/Shell/Toggle").rect
		-- the chip's right edge is at the dock's right edge, not its left
		expect(chip.x > s.w / 2).toBe(true)
		-- and it does NOT lift above the viewport (the showcase's -BAR_HEIGHT)
		expect(chip.y >= 0).toBe(true)
		s.mounted.dispose()
	end)

	it("collapsed, it paints nothing over the band an example lays its content into", function()
		-- the failure this replaces: the expanded panel occupied x 339..899 and
		-- covered example 01's field (x 16..891). Collapsed, every node the picker
		-- actually PAINTS must sit in the right-hand quarter. The full-bleed
		-- transparent Screen/Dock containers are structural, not paint, so the rule
		-- is stated over the nodes narrower than the viewport.
		local s = collapsed(907, 986)
		local painted = 0
		for _, path in s.adapter.paths() do
			local node = s.adapter.node(path)
			-- everything the picker draws lives under the Shell; `Dock` and the
			-- Screen are the full-bleed transparent frame the overlay is presented in
			if node.rect ~= nil and string.find(path, "/Dock/Shell", 1, true) ~= nil then
				painted += 1
				if node.rect.x <= 600 then
					error(`{path} paints at x = {node.rect.x}, inside the example's column`)
				end
			end
		end
		-- and the rule is not vacuous: the chip really is one of the nodes measured
		expect(painted >= 1).toBe(true)
		s.mounted.dispose()
	end)

	it("opening the panel is a `When`, not a rebuild of the shell", function()
		local s = collapsed(907, 986)
		expect(s.mounted.open:get()).toBe(false)
		local shellBefore = s.adapter.node("/GalleryThemePicker/Dock/Shell")
		s.mounted.open:set(true)
		s.presenter.refresh()
		expect(s.adapter.node("/GalleryThemePicker/Dock/Shell/PanelWhen/then/Panel") ~= nil).toBe(true)
		-- the shell node is the SAME node: opening the panel mounts the panel only
		expect(s.adapter.node("/GalleryThemePicker/Dock/Shell")).toBe(shellBefore)
		s.mounted.open:set(false)
		s.presenter.refresh()
		expect(s.adapter.node("/GalleryThemePicker/Dock/Shell/PanelWhen/then/Panel")).toBe(nil)
		s.mounted.dispose()
	end)

	it("exposes the same scriptable seams the composed handle has, so a capture can be driven", function()
		-- the showcase's `pickTheme` route once shipped as a nil global for exactly
		-- this reason: two returns from one function offering different powers.
		local s = collapsed(907, 986)
		expect(type(s.mounted.pickPackage)).toBe("function")
		expect(s.mounted.open ~= nil).toBe(true)
		local before = s.mounted.selection:get().packageId
		local other
		for _, entry in s.mounted.entries do
			if entry.id ~= before then
				other = entry.id
				break
			end
		end
		expect(s.mounted.pickPackage(other)).toBe(true)
		expect(s.mounted.selection:get().packageId).toBe(other)
		s.mounted.dispose()
	end)

	it("on a compact phone the collapsed chip still fits inside the viewport", function()
		local s = collapsed(360, 633)
		local chip = s.adapter.node("/GalleryThemePicker/Dock/Shell/Toggle").rect
		expect(chip.x >= 0).toBe(true)
		expect(chip.x + chip.w <= 360).toBe(true)
		expect(chip.y + chip.h <= 633).toBe(true)
		s.mounted.dispose()
	end)
end)
