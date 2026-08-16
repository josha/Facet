--!strict
-- THE SHIPPED HUD FIXTURE, ON THE TWO AXES NOTHING ELSE SWEEPS (director report
-- 2026-08-15).
--
-- ── AXIS 1: A VIEWPORT THAT CHANGES UNDER A MOUNTED TREE ────────────────────
--
-- The report was *"i started in portrait and rotated to landscape"*, and the
-- hypothesis handed to this task was that the zone layout was being computed
-- against the PRE-ROTATION viewport. It is not — measured live in Studio on
-- 2026-08-15 (iPhone 16 Pro, showcase place, demo picker), a tree rotated
-- portrait -> landscape lands NODE FOR NODE where a tree mounted fresh at the
-- landscape viewport lands. The hypothesis is dead and the measurement is
-- recorded in this file rather than in a chat message.
--
-- It is recorded as a TEST because of the reason nothing caught it either way:
-- every sweep in this repo mounts a fresh surface per viewport
-- (`tests/overflow_sweep.spec.luau` walks nine viewports and builds nine trees),
-- so **a corpus uniform along an axis cannot test that axis**. No test in the
-- suite could have seen a stale-viewport bug, which is exactly why the
-- hypothesis was worth taking seriously. This case is that axis: ONE tree, one
-- platform event, compared against the fresh mount as its oracle.
--
-- ── AXIS 2: THE APP'S OWN CHROME (director item 4) ──────────────────────────
--
-- *"should we also treat the demo selector and settings menu as part of this
-- control so that the stuff in the middle (12 - 2:14, etc.) are more aligned
-- with it instead of below it?"*
--
-- What the rotation report actually measured was this: the showcase reserves its
-- demo/settings chip row by inflating `coreSafeInsets.top`, which is a BOUNDING
-- BOX for a row 300px wide, and the HUD spent the whole of it as one full-width
-- band. 58px of platform + 62px of chip strip is 120px, and 120px of a 380px
-- landscape phone is 32% of the screen — so the top-centre cluster sat a third of
-- the way down and every right-hand cluster with it. Measured live, same session:
-- clock at y=120 of 380.
--
-- `appChromeRects` is the general mechanism (the same merge point
-- `platformChrome` already uses for the PLATFORM's cluster) and these cases pin
-- both halves of it: declared, the reservation is per column; undeclared, the
-- answer is byte-for-byte what it always was.
--
-- ── AXIS 3: THE URL BAR IS A THING YOU CAN SEE (director item 5) ────────────
--
-- The switch used to spend its height as a `margin.bottom` and draw nothing in
-- it, so the only visible effect was content leaving. The bar is now a box, and
-- the box is exactly as tall as the height the HUD lost — one memo, so the
-- picture and the geometry cannot drift.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local fake_target = require("./lib/fake_target")
local hud = require("../examples/gallery/scenarios/hud") :: any

-- the showcase's own chip-strip reservation, which is what the live session
-- lays out under (see tests/overflow_sweep.spec.luau's SHOWCASE_TOP note)
local PLATFORM_TOP = 58
local CHIP_STRIP = 62
local SHOWCASE_TOP = PLATFORM_TOP + CHIP_STRIP

type View = { w: number, h: number }

local PORTRAIT: View = { w = 401, h = 777 }
local LANDSCAPE: View = { w = 749, h = 380 }

-- EVERY FACT ONE PLATFORM EVENT PUBLISHES. The live adapter writes these six in
-- ONE `env:batch` on a viewport change (src/client/roblox_env.luau), so a
-- rotation that only moved `viewportRect` would be a rotation no device performs.
local function platform(view: View): { [string]: any }
	return {
		viewportRect = { x = 0, y = 0, w = view.w, h = view.h },
		coreSafeInsets = { top = SHOWCASE_TOP, bottom = 0, left = 0, right = 0 },
		deviceSafeInsets = { top = 0, bottom = 0, left = 0, right = 0 },
		topbarSafeInsets = { top = 0, bottom = 0, left = 0, right = 0 },
		topbarInset = { x = 164, y = 0, w = math.max(0, view.w - 164), h = PLATFORM_TOP },
		displaySize = "Medium",
	}
end

local function world(view: View, appChrome: { any }?): any
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	for k, v in platform(view) do
		env:set(k, v)
	end
	if appChrome ~= nil then
		env:set("appChromeRects", appChrome)
	end
	env:set("preferredInput", "Touch")
	env:set("capabilities", { keyboard = false, mouse = false, touch = true, gamepad = false })
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new();
	(adapter :: any).scrollBarThickness = fake_target.SCROLL_BAR_THICKNESS
	local presenter = LuauUI.newPresenter(core, env, adapter, system)
	-- the runner's own resolution accessor, resolved lazily for the reason the
	-- showcase host resolves its `foreign` seam lazily: the handle does not exist
	-- until `present` returns, and the fixture reads this long afterwards
	local handle: any = nil
	local built = hud.build({
		LuauUI = LuauUI,
		core = core,
		env = env,
		adapter = adapter,
		presenter = presenter,
		actionSystem = system,
		record = function() end,
		flags = {},
		composition = function(path: string)
			return if handle ~= nil then handle.controller.compositionAt(path) else nil
		end,
		bindResourceTransport = function()
			return function() end
		end,
	})
	handle = presenter.present(built.screen, built.present)
	built.handle = handle
	for _ = 1, 4 do
		presenter.refresh()
	end
	return { core = core, env = env, adapter = adapter, presenter = presenter, built = built }
end

local function settle(w: any)
	for _ = 1, 4 do
		w.presenter.refresh()
	end
end

local ZONES = {
	"/HudScreen/Hud",
	"/HudScreen/Hud/Strip",
	"/HudScreen/Hud/Rounds",
	"/HudScreen/Hud/Tasks",
	"/HudScreen/Hud/Health",
	"/HudScreen/Hud/Feed",
	"/HudScreen/Hud/Clock",
	"/HudScreen/Hud/Rail",
	"/HudScreen/Hud/Readout",
	"/HudScreen/Hud/Actions",
	"/HudScreen/Hud/Weapon",
}

local function snap(w: any): { [string]: string }
	local out: { [string]: string } = {}
	for _, path in ZONES do
		local node = w.adapter.node(path)
		out[path] = if node ~= nil and node.rect ~= nil
			then string.format("%.1f,%.1f %.1fx%.1f", node.rect.x, node.rect.y, node.rect.w, node.rect.h)
			else "(absent)"
	end
	return out
end

local function rectOf(w: any, path: string): any
	local node = w.adapter.node(path)
	return if node ~= nil then node.rect else nil
end

describe("the HUD under a viewport that changes UNDER the mounted tree", function()
	it("a portrait -> landscape rotation lands every zone where a FRESH landscape mount does", function()
		local fresh = world(LANDSCAPE)
		local want = snap(fresh)

		local rotated = world(PORTRAIT)
		local portrait = snap(rotated)
		-- the two orientations are genuinely different layouts, or this case would
		-- be comparing a thing with itself and could never fail
		expect(portrait["/HudScreen/Hud"] ~= want["/HudScreen/Hud"]).toBe(true)

		rotated.env:batch(function()
			for k, v in platform(LANDSCAPE) do
				rotated.env:set(k, v)
			end
		end)
		settle(rotated)

		local after = snap(rotated)
		for _, path in ZONES do
			expect(`{path} {after[path]}`).toBe(`{path} {want[path]}`)
		end
	end)

	it("...and back again: the portrait layout is recovered exactly, so the change is not one-way", function()
		local w = world(PORTRAIT)
		local first = snap(w)
		for _, view in { LANDSCAPE, PORTRAIT } do
			w.env:batch(function()
				for k, v in platform(view) do
					w.env:set(k, v)
				end
			end)
			settle(w)
			-- ...AND THE TREE REALLY WENT SOMEWHERE IN BETWEEN. Without this the case
			-- passes on a surface that ignored BOTH events, which is the exact defect
			-- the case above exists to catch (mutation-proved 2026-08-15: freezing the
			-- viewport at the first solve reddens the case above and left this one
			-- green, because it was comparing a frozen tree with itself).
			if view == LANDSCAPE then
				expect(snap(w)["/HudScreen/Hud"] ~= first["/HudScreen/Hud"]).toBe(true)
			end
		end
		local back = snap(w)
		for _, path in ZONES do
			expect(`{path} {back[path]}`).toBe(`{path} {first[path]}`)
		end
	end)
end)

--[[ ── THE SECOND ROUND OF THE SAME REPORT ────────────────────────────────────
	*"the circular controls are still getting cut off in the screen-anchored hud"*
	— director, 2026-08-15, on a PORTRAIT capture where the whole right-anchored
	column reads as sliced at the screen edge.

	MEASURED, and the geometry is not what it looks like. Driven live in Studio
	through a PARALLEL real-engine mount (the demo picker is broken today), iPhone
	16 Pro portrait: EVERY right-anchored node's `AbsolutePosition.X +
	AbsoluteSize.X` is 401.0 against a 401px canvas — over by 0.0px, with zero
	composition collisions and the three lanes at x 0/134/267 w 134. Nothing
	overflows. The content is flush against the physical edge with NO GUTTER AT
	ALL, and a rounded control whose rim ends exactly on the boundary reads as one
	that was cut there.

	AND THAT IS WHY IT LOOKED LIKE OPPOSITE DEFECTS IN THE TWO ORIENTATIONS. The
	platform's own exclusion is wildly asymmetric on this device:

	  device 874x402   portrait camera 401x777   -> 1px of device beyond the camera
	                   landscape camera 749x380  -> 125px beyond it (62 per side)

	One layout rule — "anchor to the camera's edge" — therefore puts the same
	content 1px from the glass in portrait and 62px in from it in landscape. The
	earlier "pulled inward" report and this "running off the edge" one are the same
	zero gutter seen through two different letterboxes, which is why the rotation
	measurement found the tree converging node-for-node all along.

	The fix is a MINIMUM GUTTER from the theme's own space scale, so the safe-area
	inset and the gutter are a per-edge max rather than a choice. These cases are
	the check, and they are asserted on the ZONES rather than on the full-width
	containers (a Screen root, the topbar span row and the URL bar plate all span
	the box by definition and always did). ]]
describe("director 2026-08-15 round 2: anchored content never touches the physical edge", function()
	local ANCHORED = {
		"Rounds",
		"Tasks",
		"Health",
		"Feed",
		"Clock",
		"Rail",
		"Readout",
		"Actions",
		"Weapon",
	}

	for _, view in { PORTRAIT, LANDSCAPE } do
		it(`{view.w}x{view.h}: every anchored zone clears BOTH lateral edges by the theme's own step`, function()
			local w = world(view)
			local metrics = w.env:get("themeMetrics"):get()
			local gutter = ((if type(metrics) == "table" then metrics.space else nil) or {}).s
			expect(type(gutter) == "number" and gutter > 0).toBe(true)
			for _, id in ANCHORED do
				local r = rectOf(w, `/HudScreen/Hud/{id}`)
				if r == nil or r.w <= 0 then
					continue -- dropped at this viewport; it cannot touch an edge
				end
				expect(`{id} left {r.x >= gutter - 0.01}`).toBe(`{id} left true`)
				expect(`{id} right {r.x + r.w <= view.w - gutter + 0.01}`).toBe(`{id} right true`)
			end
		end)
	end

	it("a REAL safe-area inset still wins when it is bigger than the gutter", function()
		-- the negative control for the max: a platform that reports 40px of notch
		-- must not have it reduced to the theme's 8px step
		local w = world(LANDSCAPE)
		w.env:batch(function()
			w.env:set("deviceSafeInsets", { top = 0, bottom = 0, left = 40, right = 40 })
		end)
		settle(w)
		local rail = rectOf(w, "/HudScreen/Hud/Rail")
		expect(rail ~= nil).toBe(true)
		expect(rail.x + rail.w <= LANDSCAPE.w - 40 + 0.01).toBe(true)
	end)
end)

describe("ADR-0027 + director item 4: the APP's chrome is reserved per column", function()
	-- the showcase's chip row as the live session measures it: the left ~40% of
	-- the band's second row, and nothing else
	local CHIPS = { { x = 0, y = PLATFORM_TOP, w = 290, h = CHIP_STRIP } }

	it("a column the chrome does not cover starts LEVEL with it, not below it", function()
		local w = world(LANDSCAPE, CHIPS)
		local clock = rectOf(w, "/HudScreen/Hud/Clock")
		local rounds = rectOf(w, "/HudScreen/Hud/Rounds")
		local rail = rectOf(w, "/HudScreen/Hud/Rail")
		expect(clock ~= nil).toBe(true)
		-- the centre and right columns rise to the PLATFORM's band bottom...
		expect(clock.y).toBe(PLATFORM_TOP)
		expect(rail.y).toBe(PLATFORM_TOP)
		-- ...and the left column, which the chips DO cover, stays clear of them
		expect(rounds.y >= PLATFORM_TOP + CHIP_STRIP).toBe(true)
		-- which is the director's sentence, as an inequality
		expect(clock.y < rounds.y).toBe(true)
	end)

	it("NOTHING declared is byte-for-byte the bounding box this HUD always spent", function()
		local w = world(LANDSCAPE)
		for _, path in { "/HudScreen/Hud/Clock", "/HudScreen/Hud/Rounds", "/HudScreen/Hud/Rail" } do
			local r = rectOf(w, path)
			expect(r ~= nil).toBe(true)
			expect(r.y).toBe(SHOWCASE_TOP)
		end
	end)

	it("the declared chrome is REPORTED as occupied, so a collision check can see it", function()
		local w = world(LANDSCAPE, CHIPS)
		local chrome = w.env:get("platformChrome"):get()
		local found = false
		for _, r in chrome.rects do
			if r.x == 0 and r.y == PLATFORM_TOP and r.w == 290 and r.h == CHIP_STRIP then
				found = true
			end
		end
		expect(found).toBe(true)
	end)
end)

describe("director item 5: the URL bar is a box you can see, and the HUD re-flows around it", function()
	it("the drawn bar is EXACTLY the height the HUD lost", function()
		local w = world(LANDSCAPE, { { x = 0, y = PLATFORM_TOP, w = 290, h = CHIP_STRIP } })
		local before = rectOf(w, "/HudScreen/Hud")
		expect(rectOf(w, "/HudScreen/UrlBarWhen/then/UrlBarChrome") == nil).toBe(true)

		local result = w.built.steps.openUrlBar()
		settle(w)

		local bar = rectOf(w, "/HudScreen/UrlBarWhen/then/UrlBarChrome")
		expect(bar ~= nil).toBe(true)
		local after = rectOf(w, "/HudScreen/Hud")
		-- the drawn box IS the loss the step reports: one memo feeds both, so the
		-- picture and the geometry cannot drift
		expect(bar.h).toBe(result.lostPx)
		-- ...and the room came from the HUD *and* from the fixture's own caption,
		-- which yields before any zone does (measured: 315 -> 144 on the HUD, the
		-- remaining 29 from the ladder caption). Pinning "the HUD lost all 200"
		-- would pin the wrong screen — the instrument is supposed to go first.
		expect(before.h > after.h).toBe(true)
		expect(before.h - after.h <= result.lostPx).toBe(true)
	end)

	it(
		"it RE-FLOWS first: the zones the player reaches for survive, and what leaves is the tail of the rank ladder",
		function()
			local w = world(LANDSCAPE, { { x = 0, y = PLATFORM_TOP, w = 290, h = CHIP_STRIP } })
			w.built.steps.openUrlBar()
			settle(w)
			local report = w.built.report()

			-- nothing overlaps: the whole point of the partition
			expect(report.collisions).toBe(0)
			-- the top three ranks are still on screen (rounds 1, clock 2, actions 3)
			local droppedSet: { [string]: boolean } = {}
			for _, id in report.dropped do
				droppedSet[id] = true
			end
			for _, id in { "Rounds", "Clock", "Actions" } do
				expect(`{id} dropped={tostring(droppedSet[id] == true)}`).toBe(`{id} dropped=false`)
			end
			-- ...and something STEPPED DOWN rather than everything simply leaving: at
			-- least one surviving zone is showing a later form than its richest
			local stepped = false
			for id, form in report.forms do
				if form > 1 and not droppedSet[id] then
					stepped = true
				end
			end
			expect(stepped).toBe(true)
		end
	)
end)
