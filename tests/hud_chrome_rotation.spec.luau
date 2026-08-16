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

--[[ ── ROUND 3: THE LADDER MAY NOT SPEND THE APP'S CHROME ──────────────────────
	The last residual of the round above, measured 2026-08-15 at 749x380 with the
	pseudo URL bar open and the showcase's chip row declared:

	  the left lane is offered 78px and needs 62 (the chrome reservation) + 36
	  (the round-button strip) = 98.

	The ladder did exactly what it is specified to do — stepped and dropped every
	other zone in that lane, descending rank — and then took the one lever it had
	left and dropped the RESERVATION, buying 62px and landing both round buttons
	inside the chip row, 36x36 each. The outcome was a HUD painting on the app's
	own chrome while every rule held.

	TWO REMEDIES WERE PROPOSED AND BOTH LOSE, measured rather than argued:

	  * "a shorter round-button form" cannot close a 20px deficit. The strip is
	    already at `controlSizes.compact.height` (36px, itself under the 44px touch
	    minimum), so the only form short enough to fit the 16px that is left is not
	    a control a thumb can hit. A content answer that produces an untappable
	    button is worse than the overlap it removes.
	  * "a chrome row that yields first" inverts ownership — the composition would
	    have to push back on the HOST's chrome — and buys the defect the director
	    already refused one round earlier: chrome that moves under pressure is a
	    player's own controls jumping around.

	THE CAUSE IS NEITHER. Rule 3's own principle is that a candidate must BUY A
	PIXEL: never degrade something that cannot help the failure it is asked to fix.
	Dropping an EXCLUSION buys pixels that are not the composition's to spend —
	they are occupied by somebody else's chrome — so it is a FALSE PURCHASE, that
	same principle one level out. The fix is that a reservation is not low-ranked
	content and leaves the drop currency (`mayDrop` is gone from the three chrome
	regions in the fixture).

	AND THE RUNG THE LADDER WAS SUSPECTED OF LACKING IS ALREADY THERE — a NULL
	RESULT, recorded so it is not re-hypothesized. `solveArrangement`'s loop takes
	ANY beneficial step-down, at any rank, before ANY drop; the case at the bottom
	of this file drives that directly. The round-button strip could not use it
	because its second form is NARROWER AND TALLER (three discs stacked, for a
	320px column), and a taller form buys a height failure nothing — which is the
	ladder refusing to degrade a zone for no pixel, correctly. ]]
describe("director 2026-08-15 round 3: the ladder may not buy the app's chrome", function()
	-- the chip row as the live session measures it, and the viewports the report
	-- named plus the two the matrix already models
	local CHIPS = { { x = 0, y = PLATFORM_TOP, w = 290, h = CHIP_STRIP } }
	local VIEWS: { View } = {
		{ w = 749, h = 380 }, -- the reported case
		{ w = 749, h = 300 },
		{ w = 749, h = 240 },
		--[[ THE ONE THAT MAKES THIS MATRIX NON-VACUOUS. Measured 2026-08-15: with
			the URL bar's own floor counting the chip row (below), every viewport
			above this one has room for the reservation AND the buttons, so a matrix
			that stopped there passed with `mayDrop = true` restored — the check
			would have proved nothing about the fix it was written for. 749x180 is
			the tallest swept viewport where the ladder genuinely runs out of levers,
			and it is where the defect lands both buttons inside the chip row, 36x36
			each. Mutation-proved in both directions. ]]
		{ w = 749, h = 180 },
		{ w = 401, h = 777 },
		{ w = 320, h = 640 },
	}
	-- the zones of the column the chip row covers: the ones the reservation exists
	-- to protect. (The centre and right columns are NOT covered — that is the whole
	-- point of the per-column rule — so they have nothing to clear here.)
	local LEFT_ZONES = { "Rounds", "Tasks", "Health", "Feed" }

	local function overlap(a: any, b: any): (number, number)
		if a == nil or b == nil then
			return 0, 0
		end
		local dx = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
		local dy = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
		if dx > 0.5 and dy > 0.5 then
			return dx, dy
		end
		return 0, 0
	end

	-- every node the adapter would actually PAINT under the left column's zones,
	-- against the rect the app declared. A hidden node paints nothing (a dropped
	-- region keeps its mount and its subtree keeps fixed boxes), which is the hole
	-- the ADR-0027 checks closed one round earlier and this reuses.
	local function assertLeftColumnClearsChips(w: any, where: string): number
		local checked = 0
		for _, path in w.adapter.paths() do
			local zone: string? = nil
			for _, id in LEFT_ZONES do
				if string.find(path, `/HudScreen/Hud/{id}`, 1, true) == 1 then
					zone = id
				end
			end
			if zone == nil then
				continue
			end
			local node = w.adapter.node(path)
			local rect = if node ~= nil then node.rect else nil
			if rect == nil or node.elided == true or rect.w <= 0 or rect.h <= 0 then
				continue
			end
			if w.adapter.visibleOf(path) == false then
				continue
			end
			checked += 1
			local dx, dy = overlap(rect, CHIPS[1])
			if dx > 0 then
				error(
					`{where}: '{path}' [{rect.w}x{rect.h} at {rect.x},{rect.y}] paints {dx}x{dy}px into the app's `
						.. `own chrome [{CHIPS[1].w}x{CHIPS[1].h} at {CHIPS[1].x},{CHIPS[1].y}]`,
					0
				)
			end
		end
		return checked
	end

	for _, view in VIEWS do
		it(`{view.w}x{view.h}: the left column never paints into the app's chrome, bar closed or open`, function()
			local w = world(view, CHIPS)
			--[[ THE CHECK HAS SOMETHING TO CATCH, asserted before it is trusted. The
				chip row has to actually lie across the left lane's band, or every
				assertion below passes on a geometry where nothing could ever overlap —
				the "check that proves nothing" class this repo keeps meeting. ]]
			local lane = w.built.report()
			expect(`report is live: {type(lane.collisions)}`).toBe("report is live: number")
			local band = rectOf(w, "/HudScreen/Hud/Rounds")
			expect(band ~= nil).toBe(true)
			local laneBox = { x = 0, y = PLATFORM_TOP, w = 244, h = 100 }
			local dx = math.min(laneBox.x + laneBox.w, CHIPS[1].x + CHIPS[1].w) - math.max(laneBox.x, CHIPS[1].x)
			expect(`the chip row crosses the left lane: {dx > 0}`).toBe("the chip row crosses the left lane: true")

			local checked = assertLeftColumnClearsChips(w, `{view.w}x{view.h} (bar closed)`)
			expect(`{view.w}x{view.h} closed: painted nodes checked {checked > 0}`).toBe(
				`{view.w}x{view.h} closed: painted nodes checked true`
			)

			w.built.steps.openUrlBar()
			settle(w)
			local checkedOpen = assertLeftColumnClearsChips(w, `{view.w}x{view.h} (bar open)`)
			expect(`{view.w}x{view.h} open: painted nodes checked {checkedOpen > 0}`).toBe(
				`{view.w}x{view.h} open: painted nodes checked true`
			)
		end)
	end

	it(
		"the reservation is never DROPPED while the chrome is declared — and the ladder was under real pressure",
		function()
			--[[ BOTH THE REPORTED VIEWPORT AND THE ONE WHERE THE LADDER RUNS OUT.
				749x380 is the case the report named; 749x180 is where the levers are
				gone and the drop is the only move left, so it is the state that can
				tell a held reservation from one that was simply never asked for. A
				case that drove 380 alone stayed GREEN with `mayDrop` restored
				(measured 2026-08-15) — the same vacuity the matrix above records. ]]
			for _, state in { { h = 380, open = true }, { h = 180, open = false } } do
				local w = world({ w = 749, h = state.h }, CHIPS)
				if state.open then
					w.built.steps.openUrlBar()
					settle(w)
				end
				local dump = w.built.handle.controller.compositionAt("/HudScreen/Hud")
				local reserve: any = nil
				for _, r in dump.regions do
					if r.id == "/HudScreen/Hud/ChromeLeft" then
						reserve = r
					end
				end
				expect(reserve ~= nil).toBe(true)
				expect(`749x{state.h} the reservation is mounted: {reserve.mounted}`).toBe(
					`749x{state.h} the reservation is mounted: true`
				)
				expect(`749x{state.h} the reservation was dropped: {reserve.dropped}`).toBe(
					`749x{state.h} the reservation was dropped: false`
				)
				expect(`749x{state.h} it is holding a real box: {reserve.rect.h > 0}`).toBe(
					`749x{state.h} it is holding a real box: true`
				)
			end
			local w = world({ w = 749, h = 380 }, CHIPS)
			w.built.steps.openUrlBar()
			settle(w)
			--[[ THE NON-VACUOUS CONTROL. A reservation that survives because the ladder
			never ran is no evidence at all: this same case passed on a HUD with room
			to spare. So the ladder has to have been WORKING — something dropped and
			something stepped down — or the assertions above prove nothing. ]]
			local report = w.built.report()
			expect(`the ladder dropped something: {#report.dropped > 0}`).toBe("the ladder dropped something: true")
			local stepped = false
			for _, form in report.forms do
				if form > 1 then
					stepped = true
				end
			end
			expect(`the ladder stepped something down: {stepped}`).toBe("the ladder stepped something down: true")
		end
	)

	--[[ THE DEFINED FLOOR: WHAT HAPPENS WHEN NOTHING FITS.
		Overlapping the app's chrome is never it, and neither is a blank screen. The
		floor is stated here and it is the composition's own rule 8 applied to an
		inviolable box: the exclusion HOLDS, every droppable zone in the lane is
		gone, the top-ranked zone that is left is placed BELOW the exclusion, and
		the resolution reports `fallback = true` so the overflow is a finding rather
		than a surprise. Measured: 749x180 is the tallest swept viewport where the
		left lane cannot be made legal at all. ]]
	it("when NOTHING fits: the exclusion holds, the tail is gone, and what is left sits BELOW it", function()
		local w = world({ w = 749, h = 180 }, CHIPS)
		local dump = w.built.handle.controller.compositionAt("/HudScreen/Hud")
		expect(`this viewport really is infeasible: {dump.fallback}`).toBe("this viewport really is infeasible: true")
		local byId: { [string]: any } = {}
		for _, r in dump.regions do
			byId[r.id] = r
		end
		local reserve = byId["/HudScreen/Hud/ChromeLeft"]
		local rounds = byId["/HudScreen/Hud/Rounds"]
		expect(`the exclusion held: {reserve.mounted and not reserve.dropped}`).toBe("the exclusion held: true")
		-- the tail of the ladder is gone: every droppable zone in the left column
		for _, id in { "Tasks", "Health", "Feed" } do
			expect(`{id} dropped: {byId[`/HudScreen/Hud/{id}`].dropped}`).toBe(`{id} dropped: true`)
		end
		-- ...and the rank-1 zone that survives is BELOW the exclusion, never in it
		expect(`the buttons start below the exclusion: {rounds.rect.y >= reserve.rect.y + reserve.rect.h - 0.01}`).toBe(
			"the buttons start below the exclusion: true"
		)
		expect(`...and clear of the chip row: {assertLeftColumnClearsChips(w, "749x180") > 0}`).toBe(
			"...and clear of the chip row: true"
		)
	end)

	--[[ THE SIMULATED BAR MAY NOT EAT THE RESERVATION. `HUD_FLOOR_PX` is a sum of
		what the screen owes before the bar may take anything, and `appChromeRects`
		added a term to it after it was written. Without this the demo stopped being
		a demo at 749x380: the bar took its full 200px, the left lane was left 78 and
		needed 98, and the fixture was showing an impossible screen rather than the
		ladder it exists to show. ]]
	it(
		"the pseudo URL bar leaves the app's chrome its room — and takes the old height where there is none",
		function()
			local declared = world({ w = 749, h = 380 }, CHIPS)
			local withChrome = declared.built.steps.openUrlBar()
			settle(declared)
			expect(`the bar yielded to the reservation: {withChrome.lostPx < 200}`).toBe(
				"the bar yielded to the reservation: true"
			)
			-- 380 (the viewport) - 160 (HUD_FLOOR_PX) - 62 (the chip row) = 158, against
			-- the 200 it took before the chrome became a term of that sum
			expect(`the bar takes {withChrome.lostPx}px`).toBe(`the bar takes {380 - 160 - CHIP_STRIP}px`)

			--[[ THE BYTE-FOR-BYTE CONTROL: a host that reserves nothing above the
			platform's own band reserves 0 in every column, and the bar takes exactly
			what it always did. Without this the case above would pass on a change
			that simply made the bar smaller everywhere. ]]
			local bare = world({ w = 749, h = 380 })
			bare.env:batch(function()
				bare.env:set("coreSafeInsets", { top = PLATFORM_TOP, bottom = 0, left = 0, right = 0 })
			end)
			settle(bare)
			local noChrome = bare.built.steps.openUrlBar()
			settle(bare)
			expect(`no chrome, the full bar: {noChrome.lostPx}`).toBe("no chrome, the full bar: 200")
		end
	)

	--[[ THE NULL RESULT, DRIVEN. The hypothesis handed to this round was that the
		ladder lacks a rung — "an item should be able to offer a compact form before
		anything is dropped". It has that rung, and this is the proof rather than a
		reading of the source: a rank-1 region with a shorter second form steps down
		while a rank-9 DROPPABLE region beside it stays on screen. Step-before-drop
		is global and it does not consult rank to choose between the two. ]]
	it("NULL RESULT: the ladder already steps a rank-1 region down before it drops a rank-9 one", function()
		local composition = require("../src/layout/composition")
		local SIZES: { [string]: { { w: number, h: number } } } = {
			Important = { { w = 100, h = 80 }, { w = 100, h = 30 } },
			Expendable = { { w = 100, h = 40 } },
		}
		local function measure(id: string, form: number, _w: number, _h: number): (number, number)
			local s = SIZES[id][math.min(form, #SIZES[id])]
			return s.w, s.h
		end
		local decl = {
			groups = { { id = "g", lane = "main", sizing = "fill" } },
			arrangements = { { name = "one", lanes = { { "main" } } } },
			regions = {
				{ id = "Important", group = "g", rank = 1, forms = 2 },
				{ id = "Expendable", group = "g", rank = 9, forms = 1, mayDrop = true },
			},
		}
		-- 120 holds both at their richest; 100 cannot, and the rank-1 region is the
		-- one that moves
		local roomy = composition.resolve(decl, { w = 200, h = 120 }, { measure = measure })
		expect(`roomy: Important form {roomy.regionById.Important.form}`).toBe("roomy: Important form 1")
		local tight = composition.resolve(decl, { w = 200, h = 100 }, { measure = measure })
		expect(`tight: Important form {tight.regionById.Important.form}`).toBe("tight: Important form 2")
		expect(`tight: Expendable dropped {tight.regionById.Expendable.dropped}`).toBe(
			"tight: Expendable dropped false"
		)
		-- ...and the round-button SHAPE, which is why the strip could not use it: a
		-- next form that is narrower but TALLER buys a height failure nothing, so the
		-- ladder correctly refuses to step and goes to the drop instead
		local TALLER: { [string]: { { w: number, h: number } } } = {
			Important = { { w = 100, h = 40 }, { w = 40, h = 120 } },
			Expendable = { { w = 100, h = 60 } },
		}
		local function measureTaller(id: string, form: number, _w: number, _h: number): (number, number)
			local s = TALLER[id][math.min(form, #TALLER[id])]
			return s.w, s.h
		end
		local squeezed = composition.resolve(decl, { w = 200, h = 80 }, { measure = measureTaller })
		expect(`taller-form: Important form {squeezed.regionById.Important.form}`).toBe("taller-form: Important form 1")
		expect(`taller-form: Expendable dropped {squeezed.regionById.Expendable.dropped}`).toBe(
			"taller-form: Expendable dropped true"
		)
	end)
end)
