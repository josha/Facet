--!strict
-- THE SHIPPED HUD FIXTURE, ON THE TWO AXES NOTHING ELSE SWEEPS (director report
-- 2026-08-15).
--
-- ── AXIS 1: A VIEWPORT THAT CHANGES UNDER A MOUNTED TREE ────────────────────
--
-- The report was *"i started in portrait and rotated to landscape"*, and the
-- hypothesis handed to this task was that the zone layout was being computed
-- against the PRE-ROTATION viewport. It is not — measured live in Studio on
-- 2026-08-15 (a compact phone, showcase place, demo picker), a tree rotated
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

local Facet = require("../src") :: any
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
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	for k, v in platform(view) do
		env:set(k, v)
	end
	if appChrome ~= nil then
		env:set("appChromeRects", appChrome)
	end
	env:set("preferredInput", "Touch")
	env:set("capabilities", { keyboard = false, mouse = false, touch = true, gamepad = false })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new();
	(adapter :: any).scrollBarThickness = fake_target.SCROLL_BAR_RESERVE
	local presenter = Facet.newPresenter(core, env, adapter, system)
	-- the runner's own resolution accessor, resolved lazily for the reason the
	-- showcase host resolves its `foreign` seam lazily: the handle does not exist
	-- until `present` returns, and the fixture reads this long afterwards
	local handle: any = nil
	local built = hud.build({
		Facet = Facet,
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
	through a PARALLEL real-engine mount (the demo picker is broken today), a
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

describe("director item 4: the APP's chrome is reserved per column", function()
	-- the showcase's chip row as the live session measures it: the left ~40% of
	-- the band's second row, and nothing else
	local CHIPS = { { x = 0, y = PLATFORM_TOP, w = 290, h = CHIP_STRIP } }

	--[[ ...AND THE NARROWER ROW THE "LEVEL" CASE BELOW IS NOW DRIVEN AT (DIR wave
		contract 2, 2026-08-18). `CHIPS` above is 290px wide, and this suite's
		headless text measurement — an estimate, and a wider one than the device
		reports — solves the centre column's clock at x 258..490 on this viewport. So
		at 290 the clock's own box genuinely OVERLAPS the chip row by 32px, and the
		case below used to assert that it sat there. It is not a case about a column
		the chrome does not cover; it was a case about a column the chrome covers and
		the old rule could not see (the majority rule measured 15% coverage and
		reserved nothing).

		240 is the widest row on this viewport that the centre column's content
		really does clear, so the two cases below are the two SIDES of the rule,
		measured rather than assumed: reach, and no reach. ]]
	local CHIPS_CLEAR = { { x = 0, y = PLATFORM_TOP, w = 240, h = CHIP_STRIP } }

	it("a column the chrome does not cover starts LEVEL with it, not below it", function()
		local w = world(LANDSCAPE, CHIPS_CLEAR)
		local clock = rectOf(w, "/HudScreen/Hud/Clock")
		local rounds = rectOf(w, "/HudScreen/Hud/Rounds")
		local rail = rectOf(w, "/HudScreen/Hud/Rail")
		expect(clock ~= nil).toBe(true)
		-- ...and it really does not cover it: the clock's own box clears the row
		expect(`the clock clears the chip row: {clock.x >= CHIPS_CLEAR[1].x + CHIPS_CLEAR[1].w}`).toBe(
			"the clock clears the chip row: true"
		)
		-- the centre and right columns rise to the PLATFORM's band bottom...
		expect(clock.y).toBe(PLATFORM_TOP)
		expect(rail.y).toBe(PLATFORM_TOP)
		-- ...and the left column, which the chips DO cover, stays clear of them
		expect(rounds.y >= PLATFORM_TOP + CHIP_STRIP).toBe(true)
		-- which is the director's sentence, as an inequality
		expect(clock.y < rounds.y).toBe(true)
	end)

	--[[ THE OTHER SIDE OF THE SAME RULE (contract 2). A column the chrome BARELY
		clips — 15% of the centre lane at this viewport, which the majority rule
		waved through — still gives way when the column's own content reaches into
		the clipped part. This is the shape the director photographed on the right
		column at 360x691 (the rail 28px inside the Settings chip), driven here on
		the centre one because that is where this viewport puts it. ]]
	it("...and a column the chrome barely clips still gives way when its CONTENT reaches in", function()
		local w = world(LANDSCAPE, CHIPS)
		local clock = rectOf(w, "/HudScreen/Hud/Clock")
		expect(clock ~= nil).toBe(true)
		--[[ THE PREMISE, ASSERTED: at this chip width the clock's own box really
			does run into the row. Without this the case passes on a viewport where
			nothing could ever have reached, which is the vacuity this file has had to
			fix once already. ]]
		local chip = CHIPS[1]
		expect(`the clock's box reaches the row: {clock.x < chip.x + chip.w}`).toBe(
			"the clock's box reaches the row: true"
		)
		-- so it wraps BELOW the row rather than painting on it
		expect(`the centre column gave way: {clock.y >= chip.y + chip.h}`).toBe("the centre column gave way: true")
		-- ...and the fraction the old rule measured is genuinely a MINORITY, so this
		-- is not the majority rule passing under a new name
		local band = math.max(0, LANDSCAPE.w - 16) / 3
		local x0 = 8 + band
		local covered = math.max(0, math.min(chip.x + chip.w, x0 + band) - math.max(chip.x, x0))
		expect(`the chrome covers a MINORITY of the lane: {covered / band < 0.5}`).toBe(
			"the chrome covers a MINORITY of the lane: true"
		)
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
	-- the chrome-band checks closed one round earlier and this reuses.
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
				--[[ THE RESERVATION IS THE LANE'S OWN BOX NOW (§8), not a rank-1 region
					standing at the head of the column. That is a stronger version of the
					same guarantee rather than a weaker one: the ladder's currency is
					CONTENT, and a lane's own starting edge is not something it can spend.
					The `exclusion` on the lane is what says so, and it is reported on
					every solve so a dump can still tell "the column gave way" from "the
					column happens to start there". ]]
				local dump = w.built.handle.controller.compositionAt("/HudScreen/Hud")
				local reserve = dump.lanes[1]
				expect(reserve ~= nil).toBe(true)
				expect(`749x{state.h} the reservation is held: {reserve.exclusion > 0}`).toBe(
					`749x{state.h} the reservation is held: true`
				)
				expect(`749x{state.h} the lane starts below the chrome: {reserve.rect.y >= CHIPS[1].y + CHIPS[1].h}`).toBe(
					`749x{state.h} the lane starts below the chrome: true`
				)
				expect(`749x{state.h} it is holding a real box: {reserve.rect.h > 0}`).toBe(
					`749x{state.h} it is holding a real box: true`
				)
			end
			local w = world({ w = 749, h = 180 }, CHIPS)
			settle(w)
			--[[ THE NON-VACUOUS CONTROL. A reservation that survives because the ladder
			never ran is no evidence at all: this same case passed on a HUD with room
			to spare. So the ladder has to have been WORKING — something dropped and
			something stepped down — or the assertions above prove nothing. ]]
			--[[ ...AT 749x180 RATHER THAN 380, and the viewport moved for a measured
				reason (D7.5): the URL bar's steal was re-measured against a real browser
				and fell from 200 to 67, so 380-with-the-bar-open is no longer a screen
				under pressure — nothing drops there any more, which is the repair
				working rather than the control failing. 180 is where the levers really
				do run out, and it is the same viewport the matrix above calls
				non-vacuous. ]]
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
		local reserve = dump.lanes[1]
		local rounds = byId["/HudScreen/Hud/Rounds"]
		expect(`the exclusion held: {reserve.exclusion > 0}`).toBe("the exclusion held: true")
		-- the tail of the ladder is gone: every droppable zone in the left column
		for _, id in { "Tasks", "Health", "Feed" } do
			expect(`{id} dropped: {byId[`/HudScreen/Hud/{id}`].dropped}`).toBe(`{id} dropped: true`)
		end
		-- ...and the rank-1 zone that survives is BELOW the exclusion, never in it
		expect(`the buttons start below the exclusion: {rounds.rect.y >= reserve.rect.y - 0.01}`).toBe(
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
			--[[ 749x240, AND THE VIEWPORT MOVED FOR A MEASURED REASON (D7.5). The
				steal was re-measured against a real browser and fell from 200 to 67
				(Chrome 151: a popup window's location-bar row is `outerHeight -
				innerHeight` = 486 - 419), so at 380 the floor no longer bites at all —
				`min(67, 380 - 160 - 62 = 158)` is just 67, and a case that cannot reach
				its own cap proves nothing about it. 240 is the tallest swept viewport
				where the sum still runs out: `240 - 160 - 62 = 18` against a 67px bar. ]]
			local declared = world({ w = 749, h = 240 }, CHIPS)
			local withChrome = declared.built.steps.openUrlBar()
			settle(declared)
			expect(`the bar yielded to the reservation: {withChrome.lostPx < 67}`).toBe(
				"the bar yielded to the reservation: true"
			)
			--[[ 240 (the viewport) - 8 (the content rect's own bottom gutter, which
				`bandSafeContent` floors) - 160 (HUD_FLOOR_PX) - 62 (the
				chip row) = 10. The instrument caps against the box it is IN rather than
				against the window: the band policy takes the platform's reservation off
				the SURFACE now, so a cap written against the viewport is a screen the
				demo does not have (`hud.luau`, `boxHeight`). ]]
			expect(`the bar takes {withChrome.lostPx}px`).toBe(`the bar takes {240 - 8 - 160 - CHIP_STRIP}px`)

			--[[ THE BYTE-FOR-BYTE CONTROL: a host that reserves nothing above the
			platform's own band reserves 0 in every column, and the bar takes exactly
			what it always did. Without this the case above would pass on a change
			that simply made the bar smaller everywhere. ]]
			local bare = world({ w = 749, h = 240 })
			bare.env:batch(function()
				bare.env:set("coreSafeInsets", { top = PLATFORM_TOP, bottom = 0, left = 0, right = 0 })
			end)
			settle(bare)
			local noChrome = bare.built.steps.openUrlBar()
			settle(bare)
			-- 240 - 160 - 0 = 80, so the cap does not bite and the bar takes the whole
			-- measured steal: the SAME number a roomy screen gets
			expect(`no chrome, the full bar: {noChrome.lostPx}`).toBe("no chrome, the full bar: 67")
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
				{ id = "Important", group = "g", rank = 1, forms = 2, recover = "none" },
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

--[[ ── DIR-5: THE FACTS DO NOT ARRIVE TOGETHER, AND THE DECISION MUST SETTLE ───
	(director device round 2026-08-17, `artifacts/release-candidate-review/rename/
	dir-reproductions.md` — rotating a 360x691 portrait to a 678x339 landscape left
	the Feed zone at `y=-58..-58 x=8..8`, a 0x0 corpse at the inset corner, with the
	debug plate reading *13 of 14 rows wanted · skipped: Feed*. A theme swap — a
	full repaint plus fresh metrics — did NOT bring it back.)

	WHY THE EXISTING CASES COULD NOT SEE IT. Every rotation case above publishes
	the six platform facts inside ONE `env:batch`, which is a rotation no device
	performs. `src/client/roblox_env.luau` publishes `viewportRect` the moment the
	camera's `ViewportSize` moves, and each safe-area inset only once
	`safe_insets`' belt agrees the area it read describes THAT viewport (the PLAT-3
	belt, redone 2026-08-17: an area that has not moved with the viewport is HELD).
	So on a real rotation the surface solves at least once against a new viewport
	with the previous orientation's insets still standing. A corpus that only ever
	batches is uniform along the axis the report is about — this file's own header
	states that rule, and this is the second axis it applies to.

	WHAT IS ASSERTED, and the three separate ways a decision can fail to settle:

	  1. UNBATCHED == BATCHED. The six facts published one per tick, in the order
	     the adapter delivers them, must settle on exactly the arrangement one
	     batch produces — per zone, and Feed is named because Feed is the one the
	     director lost.
	  2. THE INTERMEDIATE STATE REALLY IS DIFFERENT. Asserted before (1) is
	     trusted: with the viewport moved and the insets still stale, at least one
	     zone must sit somewhere other than where it ends up. Without this the case
	     is comparing a thing with itself, which is exactly how the batched
	     rotation case was proved vacuous once already.
	  3. A LATER REVISION OF ANY COMPOSITION INPUT RE-DECIDES. A theme swap and a
	     late `appChromeRects` are the two revisions the report names, and each is
	     compared against a tree MOUNTED in the destination state.

	THE PLATFORM MODELLED HERE IS NOTCHED, and that is load-bearing. The `platform`
	helper at the top of this file keeps every inset constant across the two
	orientations, so five of its six facts do not move and an unbatched publish of
	them is indistinguishable from a batched one. A phone with a cutout puts the
	exclusion at the TOP in portrait and on the LATERAL edges in landscape, so all
	six move — which is the only shape in which "the insets are still the previous
	orientation's" means anything at all.

	VERDICT: the shipped model already settles. This is recorded as a NULL RESULT
	on the model rather than as a fix, and it is mutation-proved rather than
	asserted: caching the app-chrome reservation against the viewport alone (so a
	later inset revision cannot re-run it) reddens case (1) at both viewports and
	leaves every batched case in this file green — which is precisely the
	discrimination a batched-only corpus cannot make. The live divergence therefore
	stays where the reproduction left it: in the real adapter's delivery, and in
	the give-way pass the DIR wave's contracts 2 and 3 rebuilt. ]]
describe("DIR-5: give-way decisions re-evaluate when the platform facts settle", function()
	--[[ A NOTCHED PHONE. Portrait puts the cutout at the top, landscape on both
		lateral edges — the asymmetry the device-emulator lesson records — so every
		one of the six facts genuinely moves between the two orientations. ]]
	local function notched(view: View): { [string]: any }
		local landscape = view.w > view.h
		local device = if landscape
			then { top = 0, bottom = 21, left = 44, right = 44 }
			else { top = 44, bottom = 21, left = 0, right = 0 }
		return {
			viewportRect = { x = 0, y = 0, w = view.w, h = view.h },
			coreSafeInsets = {
				top = SHOWCASE_TOP,
				bottom = device.bottom,
				left = device.left,
				right = device.right,
			},
			deviceSafeInsets = device,
			topbarSafeInsets = { top = 0, bottom = 0, left = device.left, right = device.right },
			topbarInset = {
				x = 164 + device.left,
				y = 0,
				w = math.max(0, view.w - 164 - device.left - device.right),
				h = PLATFORM_TOP,
			},
			displaySize = "Medium",
		}
	end

	--[[ THE ORDER THE ADAPTER DELIVERS THEM IN. `viewportRect` first, because
		`roblox_env.pushViewportFacts` publishes it from the camera signal with
		nothing to wait for; then `topbarInset`, which rides `GuiService`'s own
		signal; then the three inset areas, each released by its own belt entry as it
		catches up (`safe_insets.newBelt` — the three lag INDEPENDENTLY); then
		`displaySize`, which is derived from the viewport the adapter already
		published. Nothing here is a guess about ordering: it is the sequence
		`tests/platform_env_binding.spec.luau` drives against the fake engine. ]]
	local DEVICE_ORDER = {
		"viewportRect",
		"topbarInset",
		"coreSafeInsets",
		"deviceSafeInsets",
		"topbarSafeInsets",
		"displaySize",
	}

	local NOTCHED_PORTRAIT: View = { w = 360, h = 691 }
	local NOTCHED_LANDSCAPE: View = { w = 678, h = 339 }
	-- the showcase's chip row as the live session declares it
	local CHIPS = { { x = 8, y = PLATFORM_TOP, w = 282, h = CHIP_STRIP } }

	-- a world on the NOTCHED platform (the `world` helper at the top of this file
	-- publishes the constant-inset one)
	local function notchedWorld(view: View, chrome: { any }?): any
		local w = world(view, chrome)
		w.env:batch(function()
			for k, v in notched(view) do
				w.env:set(k, v)
			end
		end)
		settle(w)
		return w
	end

	--[[ THE DECISION, not just the geometry. `form` and `dropped` come from the
		composition dump — they ARE the give-way pass's output — and the painted rect
		rides beside them, because a zone that survives the ladder and then lands on
		a 0x0 rect is the corpse the director photographed and the ladder alone
		cannot report it. ]]
	local function decision(w: any): { [string]: string }
		local dump = w.built.handle.controller.compositionAt("/HudScreen/Hud")
		local byId: { [string]: any } = {}
		if dump ~= nil then
			for _, r in dump.regions do
				byId[r.id] = r
			end
		end
		local out: { [string]: string } = {}
		for _, path in ZONES do
			local id = string.match(path, "([^/]+)$") :: string
			local r = byId[`/HudScreen/Hud/{id}`]
			local rect = rectOf(w, path)
			out[id] = string.format(
				"form=%s dropped=%s rect=%s",
				tostring(r and r.form),
				tostring(r and r.dropped),
				if rect ~= nil then string.format("%.1fx%.1f@%.1f,%.1f", rect.w, rect.h, rect.x, rect.y) else "(none)"
			)
		end
		return out
	end

	local function differences(a: { [string]: string }, b: { [string]: string }): number
		local n = 0
		for id, value in a do
			if b[id] ~= value then
				n += 1
			end
		end
		return n
	end

	for _, pair in
		{
			{ from = NOTCHED_PORTRAIT, to = NOTCHED_LANDSCAPE, name = "portrait -> landscape" },
			{ from = NOTCHED_LANDSCAPE, to = NOTCHED_PORTRAIT, name = "landscape -> portrait" },
		}
	do
		it(`{pair.name}: the six facts UNBATCHED settle on the batched decision, zone for zone`, function()
			-- the oracle: one batch, which is what every other rotation case in this
			-- file drives
			local batched = notchedWorld(pair.from, CHIPS)
			batched.env:batch(function()
				for k, v in notched(pair.to) do
					batched.env:set(k, v)
				end
			end)
			settle(batched)
			local want = decision(batched)

			-- ...and the device's own delivery: one fact per tick, in order
			local live = notchedWorld(pair.from, CHIPS)
			local facts = notched(pair.to)
			local intermediate: { [string]: string }? = nil
			for _, key in DEVICE_ORDER do
				live.env:set(key, facts[key])
				settle(live)
				if key == "viewportRect" then
					-- the state the belt actually produces: the new viewport standing
					-- beside the PREVIOUS orientation's insets
					intermediate = decision(live)
				end
			end
			settle(live)

			--[[ (2) THE INTERMEDIATE STATE IS A DIFFERENT SCREEN. Asserted first: if
				the half-published tree already looked like the settled one, everything
				below would pass on a surface that never had to settle at all. ]]
			expect(`the half-published tree differs: {differences(intermediate :: any, want) > 0}`).toBe(
				"the half-published tree differs: true"
			)

			-- (1) ...and the settled decision is the batched one, per zone
			local got = decision(live)
			for _, path in ZONES do
				local id = string.match(path, "([^/]+)$") :: string
				expect(`{id} {got[id]}`).toBe(`{id} {want[id]}`)
			end
			--[[ FEED BY NAME. It is the zone the director lost and the last one on the
				left column's rank ladder, so it is the first thing an unsettled
				decision drops — naming it means a future edit that re-broke exactly
				this reads as "Feed" in the failure rather than as "zone 5 of 10". ]]
			expect(`Feed {got.Feed}`).toBe(`Feed {want.Feed}`)
			expect(`Feed is on screen at all: {string.find(got.Feed, "dropped=false", 1, true) ~= nil}`).toBe(
				"Feed is on screen at all: true"
			)
		end)
	end

	--[[ (3a) A THEME SWAP RE-DECIDES. The director's own instrument: a full repaint
		with fresh metrics did not bring Feed back on the device, which is what
		"the decision latched" means from the outside. Here the swapped tree is
		compared against one MOUNTED under the destination package — the only oracle
		that can tell "re-decided correctly" from "did not move". ]]
	it("a theme swap re-runs the give-way pass: swapped == mounted-there, both ways", function()
		local ornate = Facet.themes.resolve((require)("../examples/themes/fantasy_ornate").build(Facet.themes), nil, {})
		local neutral = Facet.themes.neutral()
		for _, view in { NOTCHED_PORTRAIT, NOTCHED_LANDSCAPE } do
			for _, step in { { from = neutral, to = ornate }, { from = ornate, to = neutral } } do
				local fresh = notchedWorld(view, CHIPS)
				fresh.env:set("themeMetrics", step.to)
				settle(fresh)
				local want = decision(fresh)

				local swapped = notchedWorld(view, CHIPS)
				swapped.env:set("themeMetrics", step.from)
				settle(swapped)
				local before = decision(swapped)
				swapped.env:set("themeMetrics", step.to)
				settle(swapped)
				local got = decision(swapped)

				-- the swap is a real change, or this proves nothing
				expect(`{view.w}x{view.h}: the package moves the screen: {differences(before, want) > 0}`).toBe(
					`{view.w}x{view.h}: the package moves the screen: true`
				)
				for id, value in want do
					expect(`{view.w}x{view.h} {id} {got[id]}`).toBe(`{view.w}x{view.h} {id} {value}`)
				end
			end
		end
	end)

	--[[ (3b) AND SO DOES A LATE `appChromeRects`. The showcase publishes its chip
		row's rect from `onGeometry`, i.e. AFTER the chrome surface has solved — so
		on the frame a demo mounts, and on the first frame after every rotation, the
		HUD has already decided once with no app chrome declared at all. ]]
	it("app chrome that arrives after the first solve re-runs the pass too", function()
		--[[ NON-VACUITY IS COUNTED ACROSS THE PAIR, NOT DEMANDED AT EACH VIEWPORT.
			With the showcase's own reservation already standing (`coreSafeInsets.top`
			IS the whole 120px strip), declaring the chrome can only ever let a column
			RISE — so on a viewport where every column's content reaches the row
			anyway, declaring it is correctly a no-op, and demanding movement there
			would be demanding the wrong answer. At least one of the two has to move,
			or the case is comparing a thing with itself. ]]
		local moved = 0
		for _, view in { NOTCHED_PORTRAIT, NOTCHED_LANDSCAPE } do
			local fresh = notchedWorld(view, CHIPS)
			local want = decision(fresh)

			local late = notchedWorld(view, nil)
			local before = decision(late)
			late.env:set("appChromeRects", CHIPS)
			settle(late)
			local got = decision(late)

			if differences(before, want) > 0 then
				moved += 1
			end
			for id, value in want do
				expect(`{view.w}x{view.h} {id} {got[id]}`).toBe(`{view.w}x{view.h} {id} {value}`)
			end
		end
		expect(`declaring the chrome moves at least one of the two screens: {moved > 0}`).toBe(
			"declaring the chrome moves at least one of the two screens: true"
		)
	end)
end)

--[[ ── DIR-2/DIR-3: THE BESIDE-CHROME BAND GIVES WAY INSTEAD OF OVERLAPPING ────
	(director device round 2026-08-17, fantasy-ornate, Grand Hall, topbar strip ON,
	compact-phone-portrait 360x691 — `artifacts/release-candidate-review/rename/
	dir-reproductions.md`: *"Weapon rail overlaps the showcase Settings chip: rail
	x=262..352 y=0..119 vs chip x=196..290 y=8..75 (28px x-overlap)"*.)

	THE MEASURED COLLISION SHAPE, and it is the one this case drives: the showcase's
	chip row runs x 8..290 — 282px wide — the HUD's three columns are 114.7px each
	under an 8px screen gutter, and the row therefore covers 97% of the left column,
	100% of the centre and **46%** of the right one. The majority rule reserved
	nothing for the right column; the rail is `end`-anchored and 80px wide, so it
	solved flush against the screen gutter at x 272..352 and painted 28px inside a
	chip row that ends at 290.

	WHY IT IS PINNED AS ITS OWN CASE rather than left to the swept matrix: the
	sweep derives its chip rects from the shipped chip specs, and the headless text
	measure is a wider estimate than the device's, so the sweep's own rows land at
	different widths per package. This case states the DEVICE's number, so a future
	change that happens to move the sweep's derived geometry out of the collision
	cannot quietly take this coverage with it.

	THE ORACLE IS EVERY PAINTED NODE, not the zone rects: a zone whose own box
	clears the row while a plate inside it does not is the same photograph. ]]
describe("DIR-2: the beside-chrome band gives way at the measured collision shape", function()
	local ORNATE = Facet.themes.resolve((require)("../examples/themes/fantasy_ornate").build(Facet.themes), nil, {})
	-- the device's row, to the pixel (see the header)
	local DEVICE_CHIPS = { { x = 8, y = PLATFORM_TOP, w = 282, h = CHIP_STRIP } }
	local PHONE: View = { w = 360, h = 691 }

	local function themedWorld(view: View, chrome: { any }?, snapshot: any?): any
		local w = world(view, chrome)
		if snapshot ~= nil then
			w.env:set("themeMetrics", snapshot)
		end
		settle(w)
		settle(w)
		return w
	end

	-- every node the adapter would PAINT, against the declared chrome
	local function paintedInsideChrome(w: any, chip: any): { string }
		local hits: { string } = {}
		for _, path in w.adapter.paths() do
			if string.find(path, "/HudScreen/Hud/", 1, true) ~= 1 then
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
			local dx = math.min(rect.x + rect.w, chip.x + chip.w) - math.max(rect.x, chip.x)
			local dy = math.min(rect.y + rect.h, chip.y + chip.h) - math.max(rect.y, chip.y)
			if dx > 0.5 and dy > 0.5 then
				table.insert(
					hits,
					string.format(
						"%s [%.1fx%.1f at %.1f,%.1f] by %.1fx%.1fpx",
						path,
						rect.w,
						rect.h,
						rect.x,
						rect.y,
						dx,
						dy
					)
				)
			end
		end
		table.sort(hits)
		return hits
	end

	it("360x691 under fantasy-ornate: NOTHING the HUD paints lands inside the chip row", function()
		local w = themedWorld(PHONE, DEVICE_CHIPS, ORNATE)
		--[[ THE PREMISE, ASSERTED BEFORE THE ORACLE IS TRUSTED. The chip row has to
			cross the RIGHT lane — the one the report is about — and cross it by a
			MINORITY, or this case is driving a geometry where the old rule would have
			reserved anyway and it proves nothing about the change. ]]
		local band = (PHONE.w - 16) / 3
		local x0 = 8 + 2 * band
		local chip = DEVICE_CHIPS[1]
		local covered = math.max(0, math.min(chip.x + chip.w, x0 + band) - math.max(chip.x, x0))
		expect(`the row crosses the right lane: {covered > 0}`).toBe("the row crosses the right lane: true")
		expect(`...by a MINORITY of it: {covered / band < 0.5}`).toBe("...by a MINORITY of it: true")

		local hits = paintedInsideChrome(w, chip)
		expect(`painted inside the app's chrome:\n  {table.concat(hits, "\n  ")}`).toBe(
			"painted inside the app's chrome:\n  "
		)
	end)

	it("...and the right column WRAPPED BELOW the row rather than being deleted", function()
		local w = themedWorld(PHONE, DEVICE_CHIPS, ORNATE)
		local chip = DEVICE_CHIPS[1]
		local dump = w.built.handle.controller.compositionAt("/HudScreen/Hud")
		local byId: { [string]: any } = {}
		for _, r in dump.regions do
			byId[r.id] = r
		end
		--[[ GIVING WAY IS NOT DROPPING (contract 3). The rail is the zone that had
			to move, and what "gave way" has to mean is that it is still on screen,
			below the row — a column that answered the collision by deleting its
			content would satisfy the oracle above and be a worse screen than the
			overlap. ]]
		local rail = byId["/HudScreen/Hud/Rail"]
		expect(`the rail is mounted: {rail ~= nil and rail.mounted}`).toBe("the rail is mounted: true")
		expect(`the rail was not dropped: {rail.dropped}`).toBe("the rail was not dropped: false")
		expect(`the rail is below the chip row: {rail.rect.y >= chip.y + chip.h - 0.01}`).toBe(
			"the rail is below the chip row: true"
		)
		-- ...and the reservation that put it there is the RIGHT lane's own, which is
		-- the one the majority rule left at zero (§8: the lane's starting edge, not a
		-- region standing at the head of the column)
		expect(`the right column reserved: {dump.lanes[3].exclusion > 0}`).toBe("the right column reserved: true")
	end)

	--[[ ── DIR-7: THE OBJECTIVE CHIP SWAPS INSTEAD OF SPILLING ──────────────────
		(same device round; `dir-reproductions.md` DIR-2 addendum: *"under
		fantasy-ornate the styled 'Round 3 · Capture' measures 70px and its plate
		solved 72px at landscape (1px slack; the narrower device portrait plate
		spills)"*.)

		THE STATED CAUSE IS REFUTED and the measurement is in the report: the chip's
		width swap does NOT measure with neutral metrics — `textFacts.font`, `.size`
		and `.lineHeight` come from `textTypography`, which reads the active
		snapshot on every measure. The real cause is one level out, in
		`chosenCandidate`: a candidate's measured width is CLAMPED to the offer, so a
		rung holding a single line could never report more than the offer and the
		first candidate always won. The chip drew "Round 3 · Capt…" instead of taking
		the "R3" rung it declares for exactly this.

		THIS CASE IS THE SHIPPED PIN. The framework rule is driven directly in
		tests/adaptive.spec.luau (DIR-7 + its control); this asserts the thing the
		director actually looked at, at the viewport and package he looked at it
		under, at every text preference — because a rule that is right in a fixture
		and wrong on the screen is the defect wearing the fix's clothes. ]]
	it("DIR-7: the objective chip fits its styled text or swaps to the short rung — never spills", function()
		for _, offset in { 0, 4, 10, 14 } do
			local w = world(PHONE, DEVICE_CHIPS)
			w.env:set("themeMetrics", ORNATE)
			w.env:set("preferredTextOffset", offset)
			settle(w)
			settle(w)
			-- the path moved with the §9 migration (the two cluster-width Spacers and
			-- the inner stack are the framework's job now); the claim did not
			local full = "/HudScreen/Hud/Strip/StripChip/then/StripRow/StripFit/Objective/ObjectiveRow/ObjectiveT"
			local short =
				"/HudScreen/Hud/Strip/StripChip/then/StripRow/StripFit/ObjectiveShort/ObjectiveShortRow/ObjectiveShortT"
			local shown = if w.adapter.visibleOf(full) ~= false then full else short
			expect(`+{offset}: a rung is on screen: {shown ~= nil}`).toBe(`+{offset}: a rung is on screen: true`)
			local facts = w.built.handle.controller.textAt(shown)
			expect(`+{offset}: the chip has facts: {facts ~= nil}`).toBe(`+{offset}: the chip has facts: true`)
			--[[ THE WHOLE CONTRACT IN ONE LINE: whichever rung the ladder took, the
				string it is drawing is not cut. "Fits its styled text OR swaps" is
				exactly "the chosen rung reports `truncated = false`". ]]
			expect(`+{offset}: the chip's chosen rung is uncut: {facts.truncated}`).toBe(
				`+{offset}: the chip's chosen rung is uncut: false`
			)
			--[[ ...AND IT REALLY DID HAVE TO CHOOSE at least once, or this case passes
				on a screen where the full rung always fitted and proves nothing about
				the swap. At the raised preferences under ornate the short rung is the
				one on screen. ]]
			if offset == 14 then
				expect(`+14: the SHORT rung is the one showing: {shown == short}`).toBe(
					"+14: the SHORT rung is the one showing: true"
				)
			end
		end
	end)

	--[[ THE CONTROL, and it is a control on the RULE rather than on the presence of
		chrome. Declaring NOTHING is not the comparison to make: with nothing
		declared every column falls back to the whole `coreSafeInsets.top` bounding
		box, which is the same 62px, so the rail would sit at the same y for the
		opposite reason and the case would pass on a fixture that had stopped reading
		the rects entirely.

		The honest control is the SAME chrome, narrowed until the right column's own
		content clears it: 200px ends at x=208 and the rail's lane starts at 237, so
		nothing in that column can reach. The rail must come back up. ]]
	it("CONTROL: narrow the row until the right column clears it and the rail is level again", function()
		local reaching = themedWorld(PHONE, DEVICE_CHIPS, ORNATE)
		local clear = themedWorld(PHONE, { { x = 8, y = PLATFORM_TOP, w = 200, h = CHIP_STRIP } }, ORNATE)
		local a = rectOf(reaching, "/HudScreen/Hud/Rail")
		local b = rectOf(clear, "/HudScreen/Hud/Rail")
		expect(a ~= nil and b ~= nil).toBe(true)
		expect(`the reaching row pushed the rail down: {a.y > b.y}`).toBe("the reaching row pushed the rail down: true")
		expect(`...and the cleared one leaves it level: {b.y}`).toBe(
			`...and the cleared one leaves it level: {PLATFORM_TOP}`
		)
	end)
end)

--[[ ── H1: EVERY INPUT THAT CAN MOVE A GIVE-WAY DECISION, ONE CASE PER TERM ──
	(fresh-context review of the DIR wave, 2026-08-18, finding H1; the mechanism
	underneath it replaced by framework-gaps §8, 2026-08-22.)

	WHAT THIS FAMILY WAS BUILT TO GUARD, AND WHY IT OUTLIVED IT. The DIR wave
	shipped a CROSS-FRAME FEEDBACK LOOP in this fixture: the give-way reach was
	sampled from solved rects and held monotone within an EPOCH — a hand-built
	token naming every composition input that can move a zone's width — and the
	reviewer showed the guard offered for it was no guard at all. Five of the six
	terms could be deleted from the key with both instruments still green, because
	the DIR-5 cases' oracle and their subject BOTH cross a viewport change, which
	resets the latch identically on each side.

	THE EPOCH AND THE LATCH ARE GONE. `UI.Composition{ exclusions }` decides the
	give-way inside ONE `resolve`, from the lane rects and the region widths it has
	in hand at that moment, so there is no key to keep in sync and no sample to go
	stale. The bug class this family was written to catch — an input that moves a
	zone's width and is not a dependency of the decision — cannot be spelled any
	more: the decision's dependencies are its arguments.

	SO WHY KEEP IT. Because the property it asserts is the one that matters and is
	now a claim about the FRAMEWORK rather than about a token: change ONE input on
	a live tree and the settled screen must equal a tree MOUNTED at that state.
	That is what "no latch" means, stated where a reader can see it fail, and it is
	the cheapest possible regression guard on a mechanism whose previous version
	went wrong on a real device. Every term still gets a case.

	A FRESH MOUNT TAKES ITS STEP BEFORE THE FIRST SOLVE. `urlBar` and `riding` are
	internal signals reached through the fixture's own steps, so a "fresh mount with
	the bar open" means opening it before any `refresh` — taking it afterwards is
	the A->B transition, i.e. the subject, and comparing the subject with itself is
	the vacuity this file has had to fix once already.

	── THE CELLS ARE STILL CONSTRUCTED, NOT GUESSED ─────────────────────────────

	For each term the two states' column extents were measured and a chip rect
	placed so the answer genuinely differs between them — a case whose two states
	are the same screen is six ways of comparing a tree with itself, and the
	non-vacuity assertion in each case is what says so out loud.

	`appChromeRects`' cell was RE-CONSTRUCTED for the §8 rule: the previous pair
	(x 240 w 60 against x 240 w 12) discriminated under the old sampled rule and
	does not under this one, because the framework reads the RICHEST forms' widths
	rather than the settled tree's — a 12px rect at x 240 is inside the right
	lane's own content at form 1, so both states push that lane. The rule is
	strictly more conservative there, which is the direction a reservation should
	err in; the cell now moves the rect between LANES instead of within one. ]]
describe("H1: every input that can move a give-way decision settles where a fresh mount lands", function()
	local ORNATE_PKG = Facet.themes.resolve((require)("../examples/themes/fantasy_ornate").build(Facet.themes), nil, {})
	local CLASSIC_PKG =
		Facet.themes.resolve((require)("../examples/themes/classic_desktop").build(Facet.themes), nil, {})

	--[[ A world at ONE state, with the fixture's own steps taken before the first
		solve — see the header for why that is what "a fresh mount at this state"
		has to mean for an internal signal. ]]
	local function epochWorld(view: View, state: any): any
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = view.w, h = view.h })
		env:set("coreSafeInsets", { top = SHOWCASE_TOP, bottom = 0, left = 0, right = 0 })
		env:set("deviceSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		env:set("topbarSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		env:set("topbarInset", { x = 164, y = 0, w = math.max(0, view.w - 164), h = PLATFORM_TOP })
		env:set("displaySize", "Medium")
		env:set("preferredInput", "Touch")
		env:set("capabilities", { keyboard = false, mouse = false, touch = true, gamepad = false })
		env:set("preferredTextOffset", state.offset or 0)
		env:set("themeMetrics", state.snapshot or ORNATE_PKG)
		env:set("appChromeRects", state.chips)
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new();
		(adapter :: any).scrollBarThickness = fake_target.SCROLL_BAR_RESERVE
		local presenter = Facet.newPresenter(core, env, adapter, system)
		local handle: any = nil
		local built = hud.build({
			Facet = Facet,
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
		if state.urlBar == true then
			built.steps.openUrlBar()
		end
		if state.riding == false then
			built.steps.leaveStrip()
		end
		local w = { core = core, env = env, adapter = adapter, presenter = presenter, built = built }
		for _ = 1, 12 do
			presenter.refresh()
		end
		return w
	end

	--[[ THE DECISION, and the RESERVES beside it. The three `Chrome*` regions ARE
		the give-way pass's output — a stale latch shows up there first — and the
		zone rects are what a player sees it as. ]]
	local EPOCH_IDS = {
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
	--[[ ...AND THE THREE RESERVATIONS, WHICH ARE LANES NOW AND NOT REGIONS (§8).
		This list used to end `ChromeLeft`, `ChromeTop`, `ChromeRight` — the three
		rank-1 reserve regions the fixture declared at the head of each column. The
		lane's own starting edge carries it now, so the decision is read off the lane
		and a name that no longer resolves would have compared "(none)" with
		"(none)" on both sides, which is a term with no case wearing one. ]]
	local LANE_COUNT = 3
	local function epochDecision(w: any): { [string]: string }
		local dump = w.built.handle.controller.compositionAt("/HudScreen/Hud")
		local byId: { [string]: any } = {}
		if dump ~= nil then
			for _, r in dump.regions do
				byId[r.id] = r
			end
		end
		local out: { [string]: string } = {}
		for i = 1, LANE_COUNT do
			local lane = if dump ~= nil then dump.lanes[i] else nil
			out[`lane{i}`] = string.format(
				"exclusion=%s y=%s",
				tostring(lane and lane.exclusion),
				if lane ~= nil and lane.rect ~= nil then string.format("%.0f", lane.rect.y) else "(none)"
			)
		end
		for _, id in EPOCH_IDS do
			local r = byId[`/HudScreen/Hud/{id}`]
			out[id] = string.format(
				"mounted=%s dropped=%s rect=%s",
				tostring(r and r.mounted),
				tostring(r and r.dropped),
				if r ~= nil and r.rect ~= nil
					then string.format("%.0fx%.0f@%.0f,%.0f", r.rect.w, r.rect.h, r.rect.x, r.rect.y)
					else "(none)"
			)
		end
		return out
	end
	local function unequal(a: { [string]: string }, b: { [string]: string }): number
		local n = 0
		for k, v in a do
			if b[k] ~= v then
				n += 1
			end
		end
		return n
	end

	local CHIPS_AT = function(x: number, w: number)
		return { { x = x, y = PLATFORM_TOP, w = w, h = CHIP_STRIP } }
	end

	--[[ ONE ROW PER TERM. `discriminating` records whether deleting this term from
		the key reddens this case — measured, and the two `false` rows carry the
		search that says so (see the header). ]]
	local TERMS = {
		{
			term = "viewport",
			discriminating = true,
			view = { w = 360, h = 691 } :: View,
			toView = { w = 749, h = 380 } :: View,
			chips = CHIPS_AT(40, 220),
			a = {},
			b = {},
		},
		{
			term = "preferredTextOffset",
			discriminating = true,
			view = { w = 360, h = 691 } :: View,
			chips = CHIPS_AT(120, 154),
			a = { offset = 0 },
			b = { offset = 14 },
		},
		{
			term = "themeMetrics",
			discriminating = true,
			view = { w = 360, h = 691 } :: View,
			chips = CHIPS_AT(120, 127),
			a = { snapshot = CLASSIC_PKG },
			b = { snapshot = ORNATE_PKG },
		},
		{
			term = "appChromeRects",
			discriminating = true,
			view = { w = 360, h = 691 } :: View,
			-- the rect moves between LANES: A is inside the right lane's own content,
			-- B is inside the left lane's, so the two states push different columns
			chipsA = CHIPS_AT(240, 60),
			chipsB = CHIPS_AT(10, 60),
			a = {},
			b = {},
		},
		{
			term = "riding",
			discriminating = false,
			view = { w = 360, h = 691 } :: View,
			chips = CHIPS_AT(120, 154),
			a = { riding = true },
			b = { riding = false },
		},
		{
			term = "urlBar",
			discriminating = false,
			view = { w = 393, h = 759 } :: View,
			chips = CHIPS_AT(262, 13),
			a = { urlBar = false },
			b = { urlBar = true },
		},
	}

	for _, row in TERMS do
		it(`{row.term}: changing only this input settles where a FRESH mount at that state lands`, function()
			local function stateFor(side: string): any
				local st: any = {}
				for k, v in (if side == "a" then row.a else row.b) do
					st[k] = v
				end
				st.chips = if side == "a" then (row.chipsA or row.chips) else (row.chipsB or row.chips)
				return st
			end
			local freshView = (row :: any).toView or row.view
			local fresh = epochWorld(freshView, stateFor("b"))
			local want = epochDecision(fresh)

			local live = epochWorld(row.view, stateFor("a"))
			local before = epochDecision(live)

			-- ONE input moves, and only one
			if row.term == "viewport" then
				local to = (row :: any).toView :: View
				live.env:set("viewportRect", { x = 0, y = 0, w = to.w, h = to.h })
				live.env:set("topbarInset", { x = 164, y = 0, w = math.max(0, to.w - 164), h = PLATFORM_TOP })
			elseif row.term == "preferredTextOffset" then
				live.env:set("preferredTextOffset", row.b.offset)
			elseif row.term == "themeMetrics" then
				live.env:set("themeMetrics", row.b.snapshot)
			elseif row.term == "appChromeRects" then
				live.env:set("appChromeRects", row.chipsB)
			elseif row.term == "riding" then
				live.built.steps.leaveStrip()
			elseif row.term == "urlBar" then
				live.built.steps.openUrlBar()
			end
			settle(live)
			settle(live)
			settle(live)
			local got = epochDecision(live)

			--[[ NON-VACUITY FIRST. The two states have to be different screens, or
				every assertion below passes on a term that moves nothing and the family
				becomes six ways of comparing a tree with itself. ]]
			expect(`{row.term}: the two states are different screens: {unequal(before, want) > 0}`).toBe(
				`{row.term}: the two states are different screens: true`
			)

			for _, id in EPOCH_IDS do
				expect(`{row.term} {id} {got[id]}`).toBe(`{row.term} {id} {want[id]}`)
			end
			for i = 1, LANE_COUNT do
				expect(`{row.term} lane{i} {got[`lane{i}`]}`).toBe(`{row.term} lane{i} {want[`lane{i}`]}`)
			end
		end)
	end

	--[[ THE FAMILY'S OWN COVERAGE CLAIM, made mechanical. The table above records
		which terms a deletion can be caught by; this asserts the shape of that
		record so a future edit cannot quietly add a term with no case, or mark an
		unmeasured term as covered. ]]
	it("COVERAGE: every input that can move a give-way decision has a case, and none is listed without one", function()
		local named: { [string]: boolean } = {}
		local discriminating = 0
		for _, row in TERMS do
			named[row.term] = true
			if row.discriminating then
				discriminating += 1
			end
		end
		--[[ THE SIX INPUTS THAT CAN MOVE A GIVE-WAY DECISION. They are the six the
			retired `reachEpoch` token had to name by hand; they are kept as the
			coverage claim because the SET has not changed — only who is answerable for
			it. `discriminating` records which of them this family can catch a
			regression in, which is still four: `riding` and `urlBar` move no column's
			x extent, so no cell exists where they change the answer. ]]
		for _, term in { "viewport", "riding", "urlBar", "preferredTextOffset", "themeMetrics", "appChromeRects" } do
			expect(`{term} has a case: {named[term] == true}`).toBe(`{term} has a case: true`)
		end
		expect(`terms with a case: {#TERMS}`).toBe("terms with a case: 6")
		expect(`terms whose change is CAUGHT here: {discriminating}`).toBe("terms whose change is CAUGHT here: 4")
	end)
end)
