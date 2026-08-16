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
	it("lists every tutorial example plus the twenty-five fixtures", function()
		local demos = demo_picker.list()
		expect(#demos).toBe(32)
		-- the all-controls fixture leads: it is the one that answers "what does
		-- this look like on my device"; the row-actions fixture follows it for
		-- the same feel-first reason (hosted row-actions device pass)
		expect(demos[1].id).toBe("all-controls")
		expect(demos[2].id).toBe("row-actions")
		expect(demos[2].kind).toBe("fixture")
		expect(demos[2].module).toBe("row_actions")
		expect(demos[1].kind).toBe("fixture")
		-- ...then the two SwiftUI-parity round 2 fixtures, ahead of the tutorials
		-- for the same reason the first two lead: each is the only hands-on proof
		-- of an API a still screenshot cannot show (a sideways virtualizer has to
		-- be flung; a motion policy has to be watched). They are the surfaces the
		-- Showcase rule exists for — content that is not reachable in-experience
		-- is not shipped (docs/plans/swiftui-parity-round2-brief.md).
		expect(demos[3].id).toBe("card-rail")
		expect(demos[3].kind).toBe("fixture")
		expect(demos[3].module).toBe("card_rail")
		expect(demos[4].id).toBe("with-animation")
		expect(demos[4].kind).toBe("fixture")
		expect(demos[4].module).toBe("with_animation")
		local examples = 0
		local fixtures = 0
		for _, d in demos do
			if d.kind == "example" then
				examples += 1
			else
				fixtures += 1
			end
			expect(#d.title > 0).toBe(true)
			expect(#d.blurb > 0).toBe(true)
			expect(#d.module > 0).toBe(true)
		end
		expect(examples).toBe(7)
		-- ELEVEN since 2026-08-14, and the additions are one rule being paid over
		-- and over: `lifecycle-hidden` (round 3's O-15 — the scenario shipped into
		-- ORDER and the sweep on 2026-08-13 and never entered this list, so it was
		-- reachable by workspace attribute and by nothing a player can do),
		-- `row-capabilities`, the per-row opt-out family's own surface, and
		-- `text-degrade`, the showcase rulings 1 and 5 owe (the degrade cascade is
		-- an ORDER, and an order needs a driver a player can hold).
		-- ...and THIRTEEN since ADR-0028: `surface-overlap`, whose four states
		-- paint identical pixels, so the picker entry is the only route a player
		-- has to the one thing that tells them apart.
		-- ...and FOURTEEN since the unified collection (2026-08-14):
		-- `table-virtualized`, whose whole difference from an ordinary Table is a
		-- COUNT rather than a picture, so the fixture is the only place a player can
		-- see that two thousand rows are being carried by seventeen.
		--
		-- ...and EIGHTEEN since 2026-08-15: `virtual-hgrid`, the same lazy grid on
		-- the other axis. It is listed separately rather than folded into
		-- `virtual-grid` as a step, because the two do not differ in a value a status
		-- line could report — they differ in which axis the LANES divide and which
		-- way the keyboard RING walks, and the only way to check either is to look at
		-- one and then the other. The picker is the only route to that comparison.
		-- ...and FIFTEEN since the header round (2026-08-14): `table-columns`, the
		-- other half of `newTable` — a header band with resize dividers, shipped in
		-- Phase B and never once driven on a real adapter because no showcase surface
		-- carried one. `table_virtualized` is headerless on purpose (the band is a
		-- `minMax` floor it could not afford), so this could not be a prop added to a
		-- fixture that already existed.
		-- ...and SEVENTEEN since `newVirtualGrid` (2026-08-15): `virtual-grid`, the
		-- lazy grid's own surface. A `LazyVGrid` over five thousand cells and an
		-- eager grid over five thousand cells paint the same first screen, so the
		-- count of cells the factory was ever asked for is the only place the
		-- feature is visible — and the lane chips are the only way to watch a reflow
		-- move every item to a new line without moving the one under your eye.
		-- ...and TWENTY since 2026-08-15: `branch-scope` and `sorted-entries`, the
		-- showcase halves of the two §5 BUILD NOWs. Both are here for the reason
		-- `surface-overlap` is: what they demonstrate is not in any single frame.
		-- A leak paints nothing at all — the branch-scope fixture's two panels are
		-- pixel-identical while open and differ only in the framework's own scope
		-- counter — and a dictionary's iteration order is only wrong compared with
		-- the frame BEFORE it, which is why that fixture ships a picker that
		-- rebuilds the same twelve pairs a different way.
		-- ...and TWENTY-ONE since ADR-0033 (2026-08-15): `time-curves`, the
		-- time-based-easing surface. It is here for the same reason: what it shows
		-- is a stopwatch reading, not a frame — an informational tween landing at
		-- 0.52 s beside a spring given the same number that does not settle until
		-- 1.05 s, and a reduced-motion pass where the decorative halves place
		-- instantly while that cooldown keeps stepping.
		-- ...and the UI.Foreign surface (ADR-0034), which is in the catalogue for a
		-- reason none of the others are: its three panes are not drawn by LuauUI at
		-- all, so it is the only demo where "does the framework render this" is the
		-- wrong question and "does the box hold it" is the right one.
		-- ...and TWENTY-FOUR since round 3's O-30 (2026-08-15): `async-images` and
		-- `canvas-group`. Both are the `lifecycle-hidden` defect one round later —
		-- `newAsyncImage` and `canvasGroup` were exercised by fixtures and reference
		-- proofs and reachable from this list by nothing, so in the shipped place a
		-- player could not select either capability at all. `async_images` already
		-- existed and only ever ran under a sweep; `canvas_group` is new, because the
		-- fade group had no fixture whose SUBJECT it was.
		expect(fixtures).toBe(25)
	end)

	-- A BLURB IS READ IN THE OPEN LIST ON THE NARROWEST PHONE, and the list is
	-- the one surface of this picker a device pass has actually validated. The
	-- ceiling is therefore the LONGEST BLURB THAT PASS ALREADY COVERED rather
	-- than a number somebody liked: a new catalogue entry may be as long as the
	-- longest shipped one and no longer, because past that nothing has ever been
	-- looked at on a 360px screen.
	it("no blurb is longer than the longest one a device pass has already read", function()
		-- CHARACTERS, not bytes: an em dash is three bytes and one glyph, and it is
		-- glyphs a phone lays out. `#` here would have made the ceiling depend on
		-- the punctuation an author happened to use.
		local CEILING = 82 -- "One semantic tree, every control, adapting from space and input — not device names"
		for _, d in demo_picker.list() do
			local length = utf8.len(d.blurb) or #d.blurb
			expect(`{d.id}: {length} chars, over {CEILING}? {length > CEILING}`).toBe(
				`{d.id}: {length} chars, over {CEILING}? false`
			)
		end
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

	-- THE OTHER HALF OF THE SHOWCASE RULE, and until now nothing asked it.
	--
	-- A fixture reaches a player through TWO registrations, not one: the picker
	-- offers it (`demo_picker.DEMOS`), and the scenario registry resolves the
	-- module (`examples/gallery/scenarios/init.luau`'s explicit ordered `ORDER`,
	-- which the showcase host replicates as `ReplicatedStorage.LuauUIScenarios`).
	-- The test above proves the FILE exists; a file that exists and is not in
	-- `ORDER` is not in that folder, so the picker's own `require` fails on the
	-- device, in front of whoever is holding it — the one failure mode this
	-- catalogue is supposed to be immune to.
	--
	-- READ FROM THE SOURCE TEXT, because `scenarios/init.luau` cannot be required
	-- headlessly: it resolves each entry through `script:WaitForChild`, which
	-- exists only inside the engine. The same reason (and the same technique) as
	-- the `pres.present` audit of `init.client.luau` at the bottom of this file.
	it("every fixture the picker offers is registered in the scenario registry's ORDER", function()
		local source = fs.readFile("examples/gallery/scenarios/init.luau")
		local block = string.match(source, "local ORDER = (%b{})")
		expect(block ~= nil).toBe(true)
		local registered: { [string]: boolean } = {}
		local count = 0
		for name in string.gmatch(block :: string, '"([%w_]+)"') do
			registered[name] = true
			count += 1
		end
		-- the parse itself has to be believable before anything is asserted on it
		expect(count > 20).toBe(true)
		expect(registered.probe).toBe(true)
		for _, d in demo_picker.list() do
			if d.kind ~= "fixture" then
				continue
			end
			expect(`{d.id} -> scenarios/init.luau ORDER has '{d.module}': {registered[d.module] == true}`).toBe(
				`{d.id} -> scenarios/init.luau ORDER has '{d.module}': true`
			)
		end
		-- ...and nothing in ORDER names a module that is not there, which is the
		-- registry's own failure mode (it fails loudly at mount, but only in Studio)
		for name in registered do
			expect(`ORDER '{name}' exists: {fs.isFile(`examples/gallery/scenarios/{name}.luau`)}`).toBe(
				`ORDER '{name}' exists: true`
			)
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
								-- (no `alignH`: this mirrors `init.client`'s chrome, whose `Dock` is a
								-- `UI.Anchor` — it places by corner and reads no align. Deleted there and
								-- here by the §2.1 placement audit; zero rects move, so every assertion
								-- below is unchanged)
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

-- ===== THE HOST LOOP: a fixture's declared `present` opts must reach the
-- presenter (C2, adversarial review 2026-08-12) ==============================
--
-- `examples/gallery/client/init.client.luau`'s fixture branch called
-- `pres.present(built.screen)` with NO second argument, so every `present` table
-- a fixture declared was discarded — in the SHIPPED host and nowhere else. The
-- scenario runner passed it, the overflow sweep passed it, and the tutorial
-- branch eleven lines below passed it: the test rigs were more correct than
-- production, which is the failure mode docs/lessons/the-solver-already-told-you.md
-- is named after, and it is why a one-argument omission survived.
--
-- Two halves, because either alone is how it survived: the DELIVERY is checked
-- generically over the whole catalogue (a fixture added tomorrow is covered),
-- and the CONSEQUENCE is measured on the fixture whose opts are load-bearing
-- today — `row_actions`, whose hosted VirtualList derives its window from its own
-- solved pane through `present.onGeometry`.

local LuauUI = require("../src") :: any
local fake_target = require("./lib/fake_target")

-- the picker's MINIMAL ctx (init.client.luau `mountDemo`, kind == "fixture"):
-- {LuauUI, core, env, actionSystem, presenter} — no adapter, no record, no flags
local function pickerWorld(viewport: any): any
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", viewport)
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local presenter = LuauUI.newPresenter(core, env, adapter, system)
	return { core = core, env = env, system = system, adapter = adapter, presenter = presenter }
end

describe("showcase host: the fixture branch delivers `present` opts", function()
	it("every catalogue fixture's declared opts arrive at the presenter, by identity", function()
		local fixtures = 0
		local withOpts = 0
		for _, demo in demo_picker.list() do
			if demo.kind ~= "fixture" then
				continue
			end
			fixtures += 1
			local w = pickerWorld({ x = 0, y = 0, w = 400, h = 700 })
			local scenario = require(`../examples/gallery/scenarios/{demo.module}`) :: any
			local built = scenario.build({
				LuauUI = LuauUI,
				core = w.core,
				env = w.env,
				actionSystem = w.system,
				presenter = w.presenter,
				-- the one engine seam the minimal ctx carries, because a fixture in
				-- this catalogue calls it at BUILD (`async_images`, round-3 O-30);
				-- the shipped host binds the real ContentProvider transport here
				bindResourceTransport = function()
					return function() end
				end,
			})
			-- SPY ON THE SEAM, not on a re-implementation of it: whatever the host
			-- loop below hands `present` is what the presenter receives
			local seen: { any } = {}
			local realPresent = w.presenter.present
			w.presenter.present = function(screen: any, opts: any)
				table.insert(seen, { screen = screen, opts = opts })
				return realPresent(screen, opts)
			end

			-- THE SHIPPED LOOP (init.client.luau `mountDemo`, fixture branch)
			built.handle = w.presenter.present(built.screen, built.present)

			expect(#seen).toBe(1)
			-- identity, not shape: a copy would mean the fixture's live closures
			-- (`onGeometry` binds the fixture's own signals) were rebuilt
			expect(`{demo.id}:{tostring(seen[1].opts == built.present)}`).toBe(`{demo.id}:true`)
			if built.present ~= nil then
				withOpts += 1
				expect(seen[1].opts).never().toBeNil()
			end
			expect(w.core:lastError()).toBeNil()
		end
		expect(fixtures).toBe(25)
		-- and at least one of them actually declares opts, or this proves nothing
		expect(withOpts >= 1).toBe(true)
	end)

	-- the source is the contract for the half a headless world cannot mount
	-- (init.client.luau is a client script: it reaches engine globals at load)
	it("no `present` call in the shipped host drops its opts", function()
		local source = fs.readFile("examples/gallery/client/init.client.luau")
		local calls = 0
		for args in string.gmatch(source, "pres%.present%(([^\n]*)%)") do
			calls += 1
			local hasOpts = string.find(args, ",", 1, true) ~= nil
			expect(`present({args}) has opts:{hasOpts}`).toBe(`present({args}) has opts:true`)
		end
		-- every single-line call site left in the file. It used to be four: the
		-- chrome's own `raiseChrome` was one of them, and the chrome is a required
		-- module now (`showcase_chrome.luau`), which is a strict improvement on
		-- this check — that surface is MOUNTED by tests/gallery_chrome.spec rather
		-- than pattern-matched here. The two multi-line calls (the backdrop root
		-- and the plain settings demo) pass literal tables written inline.
		expect(calls).toBe(3)
		-- and the DEMO branches are the ones this is really about: the picker's
		-- fixture branch, the picker's tutorial branch, and the single-demo mount
		-- path must all forward the built table's own opts
		local _, forwards = string.gsub(source, "pres%.present%(built%.screen, built%.present%)", "")
		expect(forwards).toBe(3)
	end)
end)

describe("showcase host: the delivered opts CHANGE the surface (row_actions)", function()
	-- the load-bearing consequence. `scenarios/row_actions.luau` replaced a
	-- `336 -- 4 rows visible` literal with a window fed from its own solved pane
	-- through `present.onGeometry` (device round 2026-08-12) — a fix the showcase
	-- host discarded, so in the showcase the window stayed at that literal and the
	-- hosted list painted past its pane on a landscape phone.
	local LITERAL = 336

	it("the hosted VirtualList's window tracks its solved pane, not the pre-geometry literal", function()
		local w = pickerWorld({ x = 0, y = 0, w = 700, h = 360 }) -- a landscape phone
		local scenario = require("../examples/gallery/scenarios/row_actions") :: any
		local built = scenario.build({
			LuauUI = LuauUI,
			core = w.core,
			env = w.env,
			actionSystem = w.system,
			presenter = w.presenter,
		})
		expect(built.present).never().toBeNil()
		expect(type(built.present.onGeometry)).toBe("function")
		built.handle = w.presenter.present(built.screen, built.present)
		w.presenter.refresh()
		-- the hosted-list surface is the one the window belongs to
		local ok = built.steps.mode(built, "vlist")
		expect(ok == nil or ok.ok ~= false).toBe(true)
		for _ = 1, 4 do
			w.presenter.refresh()
		end

		local pane = w.adapter.node("/MailActions/VListWhen/then/VListPane")
		expect(pane).never().toBeNil()
		local list = w.adapter.node("/MailActions/VListWhen/then/VListPane/VList")
			or w.adapter.node("/MailActions/VListWhen/then/VListPane/MailVList")
		-- whatever the list node is called, it must live INSIDE the pane: that is
		-- the whole point of feeding the window from the pane
		local bottom = if list ~= nil then list.rect.y + list.rect.h else nil
		expect(bottom).never().toBeNil()
		local paneBottom = pane.rect.y + pane.rect.h
		if (bottom :: number) > paneBottom + 1 then
			error(
				`the hosted list ends at {bottom} but its pane ends at {paneBottom} — `
					.. `{(bottom :: number) - paneBottom}px outside. The window is stuck at the `
					.. `pre-geometry literal ({LITERAL}), which is what dropping built.present does `
					.. "(examples/gallery/client/init.client.luau, fixture branch).",
				0
			)
		end
		-- and it is not the literal by accident: this pane is far shorter than 336
		expect(pane.rect.h < LITERAL).toBe(true)
		expect(w.core:lastError()).toBeNil()
	end)
end)

-- ===== THE HOST LOOP, PART TWO: a fixture's NATIVE-SCROLL MIRROR must be bound
-- (found live in Studio 2026-08-15) ==========================================
--
-- The same failure family as the `present`-opts defect above, one branch later.
-- A virtualized collection cannot reach the render controller at build time, so
-- the CONSUMER wires `bindNativeScroll(handle.controller)` after `present` — and
-- the loop that does it lived in the tutorial branch and the single-demo path
-- and NOT in the fixture branch. Without it `scrollTop` is written by nothing:
-- the engine moves its canvas and the control never hears, so the mounted window
-- stays pinned on its first line while the player flings a list that does not
-- move. Measured in the showcase place: an engine scroll to y=2000 left
-- `virtual_grid`'s window still showing `c1..c16`.
--
-- FIVE picker demos were dead on that path — `virtual_grid`, `virtual_hgrid`,
-- `variable_extents`, `measured_extents`, `table_virtualized`. The four that
-- worked bind themselves from `presenter.onTick`, which is why every device pass
-- so far drove a fixture that happened to be in the working half.
--
-- Three cases, because each alone is how the omission survived: the BINDING is
-- checked generically over the whole catalogue, the CONSEQUENCE is measured on
-- the two spellings of the seam (flat on a grid, under `api` on a Table), and
-- the SHIPPED SOURCE is audited for the loop in all three of its demo branches.

-- THE SHIPPED FIXTURE BRANCH, transcribed (init.client.luau `mountDemo`): build
-- with the minimal ctx, present with the fixture's own opts, then bind every
-- published control that rides the engine canvas. `foreign` is the host's other
-- post-present pass and is irrelevant here, so it is not modelled.
local function nativeScrollBinderOf(value: any): ((controller: any) -> any)?
	if type(value) ~= "table" then
		return nil
	end
	if type(value.bindNativeScroll) == "function" then
		return value.bindNativeScroll
	end
	if type(value.api) == "table" and type(value.api.bindNativeScroll) == "function" then
		return value.api.bindNativeScroll
	end
	return nil
end

local function hostMountFixture(w: any, module: string, bind: boolean): any
	local scenario = require(`../examples/gallery/scenarios/{module}`) :: any
	local built = scenario.build({
		LuauUI = LuauUI,
		core = w.core,
		env = w.env,
		actionSystem = w.system,
		presenter = w.presenter,
		-- the one runner-owned seam a catalogue fixture calls at BUILD
		-- (`async_images`); the sweep's rig hands it the same stub
		bindResourceTransport = function()
			return function() end
		end,
	})
	built.handle = w.presenter.present(built.screen, built.present)
	if bind then
		for _, value in built :: any do
			local binder = nativeScrollBinderOf(value)
			if binder ~= nil then
				binder(built.handle.controller)
			end
		end
	end
	return built
end

describe("showcase host: the fixture branch binds the native-scroll mirror", function()
	it("every catalogue fixture that rides the engine canvas gets its mirror bound", function()
		local riders: { string } = {}
		local bound = 0
		for _, demo in demo_picker.list() do
			if demo.kind ~= "fixture" then
				continue
			end
			local w = pickerWorld({ x = 0, y = 0, w = 400, h = 700 })
			-- SPY ON THE SEAM the bind uses, not on a re-implementation of it:
			-- `bindNativeScroll` registers `controller.observeScroll(path, cb)`, so a
			-- registration IS the mirror existing
			local built = hostMountFixture(w, demo.module, false)
			local controller = built.handle.controller
			local realObserve = controller.observeScroll
			local observed: { string } = {}
			controller.observeScroll = function(path: string, cb: any)
				table.insert(observed, path)
				return realObserve(path, cb)
			end

			local hasRider = false
			for _, value in built :: any do
				local binder = nativeScrollBinderOf(value)
				if binder ~= nil then
					hasRider = true
					binder(controller)
				end
			end
			if hasRider then
				table.insert(riders, demo.module)
				expect(`{demo.id}: observeScroll registrations {#observed > 0}`).toBe(
					`{demo.id}: observeScroll registrations true`
				)
				bound += 1
			end
			expect(w.core:lastError()).toBeNil()
		end
		-- a count, so that a catalogue whose controls all stopped publishing
		-- themselves cannot make this case pass by testing nothing
		expect(`{bound} riders: {table.concat(riders, ",")}`).toBe(`{bound} riders: {table.concat(riders, ",")}`)
		expect(bound >= 5).toBe(true)
	end)

	it("the lazy grid's window follows an engine scroll — the live defect, headless", function()
		local w = pickerWorld({ x = 0, y = 0, w = 400, h = 700 })
		local built = hostMountFixture(w, "virtual_grid", true)
		w.presenter.refresh()
		local first = built.grid.dump().window[1]
		expect(first).toBe("c1")
		local path = built.grid.scrollPath()
		expect(path).never().toBeNil()
		-- THE ENGINE MOVES ITS CANVAS. Without the host's bind nothing observes it
		-- and the window below stays on `c1` — which is exactly what the showcase
		-- place did at y=2000.
		w.adapter.driveScroll(path, { x = 0, y = 2000 })
		w.presenter.refresh()
		local after = built.grid.dump()
		if after.window[1] == first then
			error(
				`the engine scrolled to y=2000 and the mounted window still starts at '{first}' `
					.. "— the native-scroll mirror is not bound (examples/gallery/client/init.client.luau, "
					.. "fixture branch)",
				0
			)
		end
		expect(after.scrollTop).toBe(2000)
		expect(w.core:lastError()).toBeNil()
	end)

	it("...and the virtualized Table's, which publishes the seam under `api`", function()
		local w = pickerWorld({ x = 0, y = 0, w = 400, h = 700 })
		local built = hostMountFixture(w, "table_virtualized", true)
		w.presenter.refresh()
		local path = built.table_.api.scrollPath()
		expect(path).never().toBeNil()
		w.adapter.driveScroll(path, { x = 0, y = 1200 })
		w.presenter.refresh()
		-- `dump` is flat on a Table while `bindNativeScroll` is under `api` — the
		-- two spellings the host's binder probe exists for
		expect(built.table_.dump().scrollTop).toBe(1200)
		expect(w.core:lastError()).toBeNil()
	end)

	--[[ THE MINIMAL CTX IS A CONTRACT, and this is the half a headless world
		cannot mount: every rig here hands fixtures a STUB `bindResourceTransport`,
		so a host that stopped passing the real one would be invisible to all of
		them and would take the pcall in `show()` on the device instead —
		`async_images` calls that seam at BUILD, not in a step. Read from the source
		because `init.client.luau` reaches engine globals at load. ]]
	it("the shipped host's minimal ctx carries the seam a catalogue fixture calls at build", function()
		local source = fs.readFile("examples/gallery/client/init.client.luau")
		expect(string.find(source, "bindResourceTransport = function", 1, true) ~= nil).toBe(true)
		-- ...and it is the REAL transport, not a stub the host quietly kept
		expect(string.find(source, "client.roblox_resources", 1, true) ~= nil).toBe(true)
		-- the claim above is only true while a fixture in the catalogue reads it
		local callers = 0
		for _, demo in demo_picker.list() do
			if demo.kind == "fixture" then
				local text = fs.readFile(`examples/gallery/scenarios/{demo.module}.luau`)
				if string.find(text, "ctx.bindResourceTransport", 1, true) ~= nil then
					callers += 1
				end
			end
		end
		expect(`catalogue fixtures reading ctx.bindResourceTransport: {callers >= 1}`).toBe(
			"catalogue fixtures reading ctx.bindResourceTransport: true"
		)
	end)

	-- the source is the contract for the half a headless world cannot mount
	it("the shipped host runs the auto-bind loop in every demo branch", function()
		local source = fs.readFile("examples/gallery/client/init.client.luau")
		local _, calls = string.gsub(source, "nativeScrollBinderOf%(value%)", "")
		-- three branches mount a demo and three must bind: the picker's FIXTURE
		-- branch (this section's defect), the picker's tutorial branch, and the
		-- single-example path further down the file
		expect(calls).toBe(3)
	end)
end)

-- ===== THE FADE GROUP FIXTURE (round-3 O-30) ================================
--
-- `canvas_group` is the only surface in the catalogue whose subject is
-- `canvasGroup`/`opacity`, and its whole demonstration is a DIFFERENCE between
-- two declarations that read almost identically. So the cases below assert the
-- difference at the seam the engine actually has: how many CanvasGroups the
-- adapter was asked to create, and what transparency each carries.
--
-- The fixture also captures the framework's REFUSAL at build rather than quoting
-- it, which is a live read of `blueprint_schema`'s message — if that message
-- changes, this reddens, and that is correct: the panel would be showing the old
-- sentence to a player.

describe("showcase fixture: one fade group, or three (canvas_group)", function()
	local FIXTURE = "canvas_group"

	local function groupsOf(w: any): { [string]: number }
		local out: { [string]: number } = {}
		for _, path in w.adapter.paths() do
			local node = w.adapter.node(path)
			if node ~= nil and node.canvasGroupInstance ~= nil then
				out[path] = node.canvasGroupInstance.groupTransparency
			end
		end
		return out
	end

	it("the left panel is ONE engine CanvasGroup and the right panel is three", function()
		local w = pickerWorld({ x = 0, y = 0, w = 900, h = 800 })
		local built = hostMountFixture(w, FIXTURE, true)
		w.presenter.refresh()
		local groups = groupsOf(w)
		-- the fade is on the STACK on the left: one buffer over three plates
		expect(groups["/CanvasGroup/Page/Panels/One/OneGroup"]).never().toBeNil()
		-- ...and on each PLATE on the right: three buffers, and the stack that
		-- holds them is NOT one, which is what makes the overlaps compose twice
		expect(groups["/CanvasGroup/Page/Panels/Many/ThreeGroups"]).toBeNil()
		local perPlate = 0
		for path in groups do
			if string.find(path, "/ThreeGroups/", 1, true) ~= nil then
				perPlate += 1
			end
		end
		expect(`per-plate fade groups: {perPlate}`).toBe("per-plate fade groups: 3")
		expect(w.core:lastError()).toBeNil()
	end)

	it("...and every one of them carries the opacity the chips set", function()
		local w = pickerWorld({ x = 0, y = 0, w = 900, h = 800 })
		local built = hostMountFixture(w, FIXTURE, true)
		w.presenter.refresh()
		-- the fixture opens on the third stop (0.4), so transparency is 0.6
		expect(groupsOf(w)["/CanvasGroup/Page/Panels/One/OneGroup"]).toBe(0.6)
		built.opacity:set(1)
		w.presenter.refresh()
		local opaque = groupsOf(w)
		for path, transparency in opaque do
			expect(`{path} at opacity 1 -> {transparency}`).toBe(`{path} at opacity 1 -> 0`)
		end
		built.opacity:set(0.15)
		w.presenter.refresh()
		local faded = groupsOf(w)["/CanvasGroup/Page/Panels/Many/ThreeGroups/FrontGroup"]
		expect(math.abs((faded :: number) - 0.85) < 0.0001).toBe(true)
		expect(w.core:lastError()).toBeNil()
	end)

	it("the transition panel declares the group and writes no opacity of its own", function()
		local w = pickerWorld({ x = 0, y = 0, w = 900, h = 800 })
		local built = hostMountFixture(w, FIXTURE, true)
		w.presenter.refresh()
		built.showFading:set(true)
		w.presenter.refresh()
		local path = "/CanvasGroup/Page/Transition/FadingGate/then/FadingPanel"
		expect(w.adapter.node(path)).never().toBeNil()
		-- it IS a CanvasGroup — a fading form needs the arriving node to already be
		-- one — and the transition owns the alpha, so the fixture never writes it
		expect(groupsOf(w)[path]).never().toBeNil()
		expect(w.core:lastError()).toBeNil()
	end)

	it("the refusal on screen is the framework's own sentence, captured at build", function()
		local scenario = require(`../examples/gallery/scenarios/{FIXTURE}`) :: any
		local w = pickerWorld({ x = 0, y = 0, w = 900, h = 800 })
		local built = scenario.build({
			LuauUI = LuauUI,
			core = w.core,
			env = w.env,
			actionSystem = w.system,
			presenter = w.presenter,
		})
		-- it names the class it was reached for, says the prop is refused rather
		-- than missing, and names the one line that works (ADR-0029)
		expect(string.find(built.refusal, "'opacity' is REFUSED on UI.Text", 1, true) ~= nil).toBe(true)
		expect(string.find(built.refusal, "not missing", 1, true) ~= nil).toBe(true)
		expect(string.find(built.refusal, "UI.ZStack{ opacity = 0.4", 1, true) ~= nil).toBe(true)
		expect(built.report().refusalNamesTheClass).toBe(true)
	end)
end)
