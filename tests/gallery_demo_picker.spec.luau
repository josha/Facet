--!strict
-- The showcase demo picker's PURE half (examples/gallery/client/demo_picker).
--
-- The picker exists so one published place can be explored hands-on across
-- devices instead of one place per example with an attribute to edit and a
-- republish to see it. Its model — the catalogue, the selection, and what a
-- selection asks the host to do — is pure and asserted here; the overlay itself
-- is proved by the live device pass.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")
local demo_picker = require("../examples/gallery/client/demo_picker")

describe("showcase catalogue", function()
	it("lists every tutorial example plus the two fixtures", function()
		local demos = demo_picker.list()
		expect(#demos).toBe(9)
		-- the all-controls fixture leads: it is the one that answers "what does
		-- this look like on my device"; the row-actions fixture follows it for
		-- the same feel-first reason (hosted row-actions device pass)
		expect(demos[1].id).toBe("all-controls")
		expect(demos[2].id).toBe("row-actions")
		expect(demos[2].kind).toBe("fixture")
		expect(demos[2].module).toBe("row_actions")
		expect(demos[1].kind).toBe("fixture")
		local examples = 0
		for _, d in demos do
			if d.kind == "example" then
				examples += 1
			end
			expect(#d.title > 0).toBe(true)
			expect(#d.blurb > 0).toBe(true)
			expect(#d.module > 0).toBe(true)
		end
		expect(examples).toBe(7)
	end)

	it("names modules that actually exist", function()
		-- a catalogue entry pointing at a missing module is a demo that fails to
		-- mount on the device, in front of whoever is holding it
		for _, d in demo_picker.list() do
			local path = if d.kind == "fixture"
				then `examples/gallery/scenarios/{d.module}.luau`
				else `examples/gallery/examples/{d.module}.luau`
			expect(fs.isFile(path)).toBe(true)
		end
	end)

	it("has unique ids", function()
		local seen: { [string]: boolean } = {}
		for _, d in demo_picker.list() do
			expect(seen[d.id]).toBe(nil)
			seen[d.id] = true
		end
	end)
end)

describe("chip label", function()
	-- the chip shares a 62px strip with the theme picker's and neither surface
	-- can measure the other, so the LABEL is what gets clipped. Constraining the
	-- box instead made the label wrap to two lines and the chip left the strip.
	it("passes a title that already fits through untouched", function()
		expect(demo_picker.clip("All controls", 14)).toBe("All controls")
	end)

	it("clips a longer title to the budget, ellipsis included", function()
		local clipped = demo_picker.clip("Temperature converter", 14)
		expect(#clipped <= 14 + 2).toBe(true) -- the ellipsis is 3 bytes in UTF-8
		expect(string.sub(clipped, 1, 13)).toBe("Temperature c")
	end)

	it("never clips every title in the catalogue to the same thing", function()
		local seen: { [string]: boolean } = {}
		for _, d in demo_picker.list() do
			local label = demo_picker.clip(d.title, demo_picker.CHIP_LABEL_CHARS)
			expect(seen[label]).toBe(nil)
			seen[label] = true
		end
	end)
end)

describe("selection", function()
	it("starts on the first demo", function()
		expect(demo_picker.initialSelection()).toBe("all-controls")
	end)

	it("choosing the demo already shown is a no-op, not a remount", function()
		local command = demo_picker.choose("ex03", "ex03")
		expect(command.action).toBe("none")
		expect(command.selection).toBe("ex03")
	end)

	it("choosing another demo asks for a swap", function()
		local command = demo_picker.choose("ex03", "ex05")
		expect(command.action).toBe("swap")
		expect(command.selection).toBe("ex05")
	end)

	it("an unknown id changes nothing", function()
		local command = demo_picker.choose("ex03", "not-a-demo")
		expect(command.action).toBe("none")
		expect(command.selection).toBe("ex03")
	end)
end)

describe("stepping (the couch path)", function()
	it("advances and wraps in both directions", function()
		local demos = demo_picker.list()
		local first, last = demos[1].id, demos[#demos].id
		expect(demo_picker.next(first, 1)).toBe(demos[2].id)
		expect(demo_picker.next(last, 1)).toBe(first)
		expect(demo_picker.next(first, -1)).toBe(last)
	end)

	it("a full cycle returns to where it started", function()
		local demos = demo_picker.list()
		local id = demos[1].id
		for _ = 1, #demos do
			id = demo_picker.next(id, 1)
		end
		expect(id).toBe(demos[1].id)
	end)

	it("an unknown current id still yields a real demo", function()
		expect(demo_picker.find(demo_picker.next("not-a-demo", 1)) ~= nil).toBe(true)
	end)
end)

-- ===========================================================================
-- THE DEMO LIST SCROLLS (director report 2026-07-27, found live under Pixel
-- Quest: "the demo list overflows the screen but isn't automatically
-- scrollable--it should be").
--
-- It was a plain VStack: no cap, no scroller. Nine demos at a pixel package's
-- row height came to 720px inside the 689px this overlay actually gets on a
-- notched phone, and the last demo was simply off the bottom of the screen with
-- no way to reach it. Landscape was 700px of list in 235px of room.
--
-- The THEME picker met this in round 10 and its fix is written up beside its own
-- panel; this is the sibling that was missed. Measured, not asserted from source
-- text: the box has to CAP and the canvas has to exceed it, because a capped box
-- with a matching canvas is a clipped list, not a scrolling one.
-- ===========================================================================
describe("the showcase demo list scrolls rather than running off the screen", function()
	local LuauUI = require("../src") :: any
	local UI = require("../src/blueprint")
	local fake_target = require("./lib/fake_target")
	local themes = LuauUI.themes

	local function listGeometry(pkgName: string, w: number, h: number)
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = w, h = h })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, LuauUI.newActionSystem(core))
		local picker = demo_picker.mount({
			LuauUI = LuauUI,
			core = core,
			env = env,
			presenter = pres,
			composed = true,
			mountDemo = function()
				return nil
			end,
		} :: any)
		picker.open:set(true)
		pres.present(UI.Screen({ id = "S", padding = 0, children = { picker.list } }))
		pres.refresh()
		env:set("themeMetrics", themes.resolve((require)(`../examples/themes/{pkgName}`).build(themes), nil, {}))
		pres.refresh()
		return adapter.node("/S/Rows")
	end

	it("the list is a scroll host, not a plain stack", function()
		local rows = listGeometry("pixel_quest", 390, 844)
		expect(rows ~= nil).toBe(true)
		expect(rows.scrollRegion ~= nil).toBe(true)
	end)

	it("its box never exceeds the room it was given, in the package that showed the defect", function()
		-- `hug` = the content size CAPPED at the parent's offer. Before the fix
		-- this box was 720px tall inside an 844px phone and grew unbounded with
		-- the package's row height.
		for _, name in { "pixel_quest", "fantasy_ornate", "glossy_touch", "compact_pointer" } do
			for _, view in { { 390, 844 }, { 844, 390 } } do
				local rows = listGeometry(name, view[1], view[2])
				expect(rows.rect.h <= view[2]).toBe(true)
			end
		end
	end)

	it("...and when the list does not fit, the canvas EXCEEDS the box, so it can actually be scrolled", function()
		-- the half that matters: a capped box whose canvas equals it is a CLIPPED
		-- list with demos nobody can reach, which is the reported defect wearing a
		-- different shape.
		local rows = listGeometry("pixel_quest", 844, 390)
		expect(rows.scrollRegion.contentH > rows.rect.h).toBe(true)
	end)
end)

-- ===========================================================================
-- THE RESERVED STRIP MEASURES ITS CHIPS (device report 2026-07-27)
--
-- `BAR_HEIGHT = 62` used to BE the reservation: the strip's 8px top padding plus
-- the taller chip's 46px, measured once under Studio Neutral. A chip is a themed
-- control, so that number was only ever right for the package it was measured
-- under — and under Pixel Quest, on an iPhone, the chip grew past the strip and
-- its plate painted over the top of the demo's own page title.
--
-- These solve the REAL composed chip row (the shape init.client builds) under the
-- reference packages, and check the reservation against what the chips actually
-- measure — which is the check the literal could not make.
-- ===========================================================================
describe("the showcase strip reserves what its chips MEASURE, not a literal", function()
	local LuauUI = require("../src") :: any
	local UI = require("../src/blueprint")
	local fake_target = require("./lib/fake_target")
	local theme_picker = require("../examples/gallery/client/theme_picker")
	local themes = LuauUI.themes

	local CORE_TOP = 58 -- a notched phone's Roblox topbar inset
	local SLACK = 8 -- metrics.space.s, the step init.client passes

	-- init.client's chrome, reduced to the part this is about: both chips in one
	-- HStack, in a full-width column placed at the live topbar inset. The chip row
	-- does NOT sit inside the reservation — that is what makes measuring it safe.
	local function chipRowBottom(pkgName: string?, textOffset: number)
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 393, h = 852 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		env:set("preferredTextOffset", textOffset)
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, LuauUI.newActionSystem(core))
		if pkgName ~= nil then
			env:set("themeMetrics", themes.resolve((require)(`../examples/themes/{pkgName}`).build(themes), nil, {}))
		end
		local demos = demo_picker.mount({
			LuauUI = LuauUI,
			core = core,
			env = env,
			presenter = pres,
			composed = true,
			mountDemo = function()
				return nil
			end,
		} :: any)
		local picker = theme_picker.mount({
			LuauUI = LuauUI,
			core = core,
			env = env,
			adapter = adapter,
			presenter = pres,
			packages = { glossy_touch = (require)("../examples/themes/glossy_touch").build(themes) },
			themeController = {
				install = function()
					return {
						inspect = function()
							return { fallback = false }
						end,
						swap = function() end,
						swapPackage = function() end,
						uninstall = function() end,
					}
				end,
			},
			composed = true,
			collapsible = true,
			warn = function() end,
		} :: any)
		pres.present(
			UI.Screen({
				id = "ShowcaseChrome",
				padding = "s",
				children = {
					UI.Anchor({
						id = "Dock",
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						children = {
							UI.VStack({
								id = "Bar",
								anchor = "topLeft",
								height = { type = "fill", weight = 1 },
								width = { type = "fill", weight = 1 },
								offsetY = CORE_TOP,
								gap = "xs",
								alignH = "start",
								children = {
									UI.HStack({ id = "Chips", gap = "s", children = { demos.chip, picker.chip } }),
								},
							}),
						},
					}),
				},
			}),
			{ responder = "passive", rootPolicy = "edgeToEdge" }
		)
		pres.refresh()
		local row = adapter.node("/ShowcaseChrome/Dock/Bar/Chips")
		return row.rect.y + row.rect.h
	end

	it("the reservation clears the chip row under every reference package", function()
		for _, pkg in { nil, "glossy_touch", "pixel_quest", "fantasy_parchment" } do
			local bottom = chipRowBottom(pkg, 0)
			local reserved = demo_picker.barReservation(CORE_TOP, bottom, SLACK)
			if reserved < bottom then
				error(`{tostring(pkg)}: reserved {reserved} but the chips end at {bottom}`)
			end
		end
	end)

	it("...and a chip TALLER than the literal grows the strip, which is the defect", function()
		-- the device case: a package whose chip outgrows the 62px the literal
		-- reserved. If no reference package does that at the shipped text size, a
		-- raised accessibility text preference certainly will — and either way the
		-- measured reservation has to be the one that moves.
		local grew = false
		for _, pkg in { nil, "glossy_touch", "pixel_quest", "fantasy_parchment" } do
			for _, offset in { 0, 6, 10, 14 } do
				local bottom = chipRowBottom(pkg, offset)
				local reserved = demo_picker.barReservation(CORE_TOP, bottom, SLACK)
				expect(reserved >= bottom).toBe(true)
				if bottom > CORE_TOP + demo_picker.BAR_HEIGHT then
					-- the literal would have left this chip hanging into the demo
					grew = true
					expect(reserved > CORE_TOP + demo_picker.BAR_HEIGHT).toBe(true)
				end
			end
		end
		expect(grew).toBe(true)
	end)

	it("with no geometry yet, the literal is the floor and nothing else", function()
		expect(demo_picker.barReservation(CORE_TOP, nil, SLACK)).toBe(CORE_TOP + demo_picker.BAR_HEIGHT)
		-- a chip row that fits never SHRINKS the strip below the floor
		expect(demo_picker.barReservation(CORE_TOP, CORE_TOP + 10, SLACK)).toBe(CORE_TOP + demo_picker.BAR_HEIGHT)
	end)
end)
