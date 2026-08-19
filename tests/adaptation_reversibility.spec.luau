--!strict
--[[ ADAPTATION IS A ROUND TRIP, AND THE RECOVERY ROUTE IS THE SAME THING BACK.

	Two halves of one director finding (device review, 2026-08-16), and both are
	holes D7 left rather than defects D7 introduced.

	── 1. THE PATH BETWEEN VIEWPORTS ───────────────────────────────────────────
	D7.6 sweeps nine viewports in two URL-bar states and proves a route exists at
	each. Every one of those rows MOUNTS A FRESH SURFACE. So the corpus was uniform
	along the axis the report is about — *"it degrades but it does not recover"* —
	and a one-way ladder would have passed the whole sweep: nothing anywhere asked
	whether the SAME mounted surface, driven A -> B -> A, lands where a fresh mount
	at A lands. `tests/hud_chrome_rotation.spec.luau` asks it for ONE pair of
	viewports and only about rects; this asks it for every ordered pair of the
	swept set, in both URL-bar states, about the RESOLUTION (which arrangement,
	which form per region, what is dropped, what is elided, what is unshown and by
	which route) and about the painted tree (every rect and every visibility).

	IDENTICAL, NOT MERELY LEGAL. That distinction is the whole point: a resolution
	that is legal at A but is not the one A produces cold is exactly the shape the
	report describes — the screen came back and the information did not.

	AND IT HAS TO BITE. A reversibility check whose two sides never differ proves
	nothing, so the case first asserts that A and B really do resolve differently
	(the ladder moved), and separately that at least one transition in the sweep
	moved a form or a drop. Mutation-proved: pinning the resolution to the first
	solve (a one-line latch in `compositionResolution`'s cache key) reddens this.

	── 2. THE ROUTE MUST REACH THE SAME THING ──────────────────────────────────
	*"I'd expect when I press on 'win a round' to see the same contents I see in
	landscape when it's expanded."* — the director, on the `TasksChip` route D7.2
	turned into a Button.

	It did not. The HUD authored the disclosure as a hand-written LIST OF STRINGS
	beside the forms it was disclosing (`RECOVERED` in the fixture), so the panel
	showed `"Win a round  +50"` as one flat caption where the rich form shows a
	mark, the task's name, its PROGRESS BAR and its reward chip. A route that
	reaches a different, lesser thing is a second elision wearing a disclosure's
	clothes — and the two copies could drift apart with nothing to notice.

	This case is the anti-drift check, and it is structural rather than a string
	compare: every text the RICHEST form paints for a zone must be on the panel,
	and the panel must carry the same count of progress bars. A transcription
	cannot satisfy either half.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local fake_target = require("./lib/fake_target")
local deviceViews = require("./lib/device_views")
local hudScenario = require("../examples/gallery/scenarios/hud") :: any

local CORE_TOP = deviceViews.CORE_TOP
-- the showcase's own chip strip, the same reservation D7.6's sweep makes: every
-- one of these surfaces is reached through the demo picker
local PICKER_STRIP = 62

type View = { id: string, w: number, h: number, displaySize: string, input: string }

local function facts(view: View): { [string]: any }
	return {
		viewportRect = { x = 0, y = 0, w = view.w, h = view.h },
		coreSafeInsets = { top = CORE_TOP + PICKER_STRIP, bottom = 0, left = 0, right = 0 },
		deviceSafeInsets = { top = 0, bottom = 0, left = 0, right = 0 },
		topbarSafeInsets = { top = 0, bottom = math.max(0, view.h - CORE_TOP), left = 164, right = 0 },
		topbarInset = { x = 164, y = 0, w = math.max(0, view.w - 164), h = CORE_TOP },
		appChromeRects = { { x = 8, y = CORE_TOP, w = math.max(1, math.min(259, view.w - 16)), h = PICKER_STRIP } },
		displaySize = view.displaySize,
		preferredInput = view.input,
		capabilities = deviceViews.CAPABILITIES[view.input],
	}
end

local function drive(view: View): any
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	for key, value in facts(view) do
		env:set(key, value)
	end
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local presenter = Facet.newPresenter(core, env, adapter, system)
	local handle: any = nil
	local built = hudScenario.build({
		Facet = Facet,
		core = core,
		env = env,
		adapter = adapter,
		presenter = presenter,
		actionSystem = system,
		record = function() end,
		composition = function(path: string?): any
			return if handle == nil then nil else handle.controller.compositionAt(path)
		end,
	})
	handle = presenter.present(built.screen, built.present)
	local function refresh()
		for _ = 1, 3 do
			presenter.refresh()
		end
	end
	refresh()
	return {
		env = env,
		adapter = adapter,
		built = built,
		handle = handle,
		refresh = refresh,
		-- ONE platform event, six facts, exactly as the live adapter publishes a
		-- rotation (`src/client/roblox_env.luau` writes them in one `env:batch`)
		goTo = function(next: View)
			env:batch(function()
				for key, value in facts(next) do
					env:set(key, value)
				end
			end)
			refresh()
		end,
		dispose = function()
			built.dispose()
			presenter.dismiss(handle)
		end,
	}
end

-- WHAT THE LADDER DECIDED, as one comparable string: the arrangement, every
-- region's form with its drop/elide state, and the whole unshown list with its
-- routes. This is the RESOLUTION half of "identical, not merely legal".
local function resolutionOf(w: any): string
	local dump = w.handle.controller.compositionAt("/HudScreen/Hud")
	if dump == nil then
		error("the HUD published no composition dump — this comparison would prove nothing", 0)
	end
	local parts: { string } = { `arrangement={dump.arrangement} fallback={tostring(dump.fallback)}` }
	for _, r in dump.regions do
		table.insert(
			parts,
			string.format(
				"%s:form%d%s%s",
				string.match(r.id, "([^/]+)$") :: string,
				r.form,
				if r.dropped then "+dropped" else "",
				if r.elided then "+elided" else ""
			)
		)
	end
	for _, u in dump.unshown do
		table.insert(parts, `unshown:{string.match(u.id, "([^/]+)$")}/{u.reason}/{u.route}`)
	end
	return table.concat(parts, " ")
end

-- ...and WHAT WAS PAINTED, which is the half a resolution comparison cannot see:
-- the same resolution can still be mounted with a stale visibility or a stale
-- rect, and that is precisely the shape of the report.
local function paintedOf(w: any): { [string]: string }
	local out: { [string]: string } = {}
	for _, path in w.adapter.paths() do
		local node = w.adapter.node(path)
		local rect = if node ~= nil then node.rect else nil
		out[path] = string.format(
			"visible=%s rect=%s",
			tostring(w.adapter.visibleOf(path)),
			if rect ~= nil then string.format("%.1f,%.1f %.1fx%.1f", rect.x, rect.y, rect.w, rect.h) else "(none)"
		)
	end
	return out
end

local function paintDiff(want: { [string]: string }, got: { [string]: string }): { string }
	local out: { string } = {}
	for path, value in want do
		if got[path] ~= value then
			table.insert(out, `{path}: fresh {value} / returned {tostring(got[path])}`)
		end
	end
	for path, value in got do
		if want[path] == nil then
			table.insert(out, `{path}: fresh (absent) / returned {value}`)
		end
	end
	table.sort(out)
	return out
end

--[[ THE PAIRS. Every ordered pair of five viewports whose ROTATION is a real
	platform event — the two phone orientations the report names, the two narrow
	extremes (where the ladder actually has rungs to take), and 812x375.

	THAT LAST ONE IS NOT DECORATION AND ITS HEIGHT IS THE REASON. The URL bar
	steals 67px and this fixture drops its own caption below 360px of viewport, so
	only a height in the 360..427 band has the bar CROSS that floor: at 718 and 640
	the caption survives the steal and at 338 and 320 it was already gone, so a
	latched steal would be invisible at all four. 375 is an iPhone-class landscape
	and it is the one that can tell a stuck bar from a released one. (Mutation-
	proved: latching `urlBarPx` on first open reddens the URL-bar case only once
	this row is in the set.) ]]
local ROUND_TRIP: { View } = {
	{ id = "compact-phone-portrait", w = 359, h = 718, displaySize = "Small", input = "Touch" },
	{ id = "compact-phone-landscape", w = 705, h = 338, displaySize = "Small", input = "Touch" },
	{ id = "phone-landscape-812x375", w = 812, h = 375, displaySize = "Small", input = "Touch" },
	{ id = "narrow-portrait", w = 320, h = 640, displaySize = "Small", input = "Touch" },
	{ id = "narrow-landscape", w = 640, h = 320, displaySize = "Small", input = "Touch" },
}

describe("the path BETWEEN viewports is reversible — a ladder that steps down steps back up", function()
	it("A -> B -> A lands on the resolution a FRESH mount at A produces, for every ordered pair", function()
		local movedSomewhere = false
		local checked = 0
		for _, a in ROUND_TRIP do
			local cold = drive(a)
			local wantResolution = resolutionOf(cold)
			local wantPaint = paintedOf(cold)
			cold.dispose()

			for _, b in ROUND_TRIP do
				if b.id == a.id then
					continue
				end
				local w = drive(a)
				w.goTo(b)
				-- THE CASE WOULD BE VACUOUS WITHOUT THIS. Two viewports that resolve
				-- identically compare a thing with itself; the sweep has to have
				-- somewhere to come back FROM.
				local away = resolutionOf(w)
				movedSomewhere = movedSomewhere or away ~= wantResolution
				w.goTo(a)
				checked += 1
				expect(`{a.id} <- {b.id}: {resolutionOf(w)}`).toBe(`{a.id} <- {b.id}: {wantResolution}`)
				local diff = paintDiff(wantPaint, paintedOf(w))
				expect(`{a.id} <- {b.id} painted differences: {#diff}{if #diff > 0 then " " .. diff[1] else ""}`).toBe(
					`{a.id} <- {b.id} painted differences: 0`
				)
				w.dispose()
			end
		end
		expect(`transitions swept: {checked}`).toBe("transitions swept: 20")
		expect(`the ladder really moved somewhere: {movedSomewhere}`).toBe("the ladder really moved somewhere: true")
	end)

	--[[ THE REPORTED SEQUENCE, VERBATIM: *"rotate to portrait, toggle the URL bar
		on then off, rotate back to landscape"*. The toggle matters because it takes
		height out of the SAME box the rotation resizes, so it is the one driver that
		can leave a steal behind after it is switched off. ]]
	it("...and a URL-bar episode in the middle leaves nothing behind", function()
		local landscape = ROUND_TRIP[3]
		local cold = drive(landscape)
		local wantResolution = resolutionOf(cold)
		local wantPaint = paintedOf(cold)
		cold.dispose()

		--[[ THE BAR HAS TO HAVE DONE SOMETHING, and where it does is a fact about the
			viewport rather than an assumption: 67px off a tall portrait moves no rung at
			all, so a case that demanded a changed RESOLUTION at one chosen size would be
			asserting the wrong thing at three of the four. What is true everywhere is
			that the HUD's own BOX shrank; that a rung moves somewhere is asserted once,
			across the away-states, so neither half can go vacuous. ]]
		local movedARung = false
		for _, away in ROUND_TRIP do
			if away.id == landscape.id then
				continue
			end
			local w = drive(landscape)
			w.goTo(away)
			local before = resolutionOf(w)
			local boxBefore = paintedOf(w)["/HudScreen/Hud"]
			w.built.steps.openUrlBar()
			w.refresh()
			movedARung = movedARung or resolutionOf(w) ~= before
			expect(`{away.id}: the bar took height from the HUD: {paintedOf(w)["/HudScreen/Hud"] ~= boxBefore}`).toBe(
				`{away.id}: the bar took height from the HUD: true`
			)
			w.built.steps.closeUrlBar()
			w.refresh()
			w.goTo(landscape)
			expect(`{away.id} after the episode: {resolutionOf(w)}`).toBe(
				`{away.id} after the episode: {wantResolution}`
			)
			local diff = paintDiff(wantPaint, paintedOf(w))
			expect(`{away.id} painted differences after the episode: {#diff}{if #diff > 0 then " " .. diff[1] else ""}`).toBe(
				`{away.id} painted differences after the episode: 0`
			)
			w.dispose()
		end
		expect(`the bar moved a rung somewhere: {movedARung}`).toBe("the bar moved a rung somewhere: true")
	end)

	--[[ AND THE SINK SURVIVES THE ROUND TRIP. The paint comparison above would
		catch this too, but it would report it as one path among ninety; the sink is
		the affordance the whole recovery contract rests on and it is worth its own
		sentence when it dies. ]]
	it("the overflow sink is still reachable after every round trip", function()
		local sink = "/HudScreen/Hud/Rounds/RoundStrip/R3"
		for _, a in ROUND_TRIP do
			for _, b in ROUND_TRIP do
				if b.id == a.id then
					continue
				end
				local w = drive(a)
				w.goTo(b)
				w.goTo(a)
				expect(`{a.id} <- {b.id} sink visible: {tostring(w.adapter.visibleOf(sink))}`).toBe(
					`{a.id} <- {b.id} sink visible: true`
				)
				w.dispose()
			end
		end
	end)
end)

-- ===== the route has to reach the same thing ===============================

-- every VISIBLE text this surface paints under `root`, and the count of progress
-- bars in it. Both halves matter: the strings are what the player reads, and the
-- bars are what a transcription cannot have.
local function contentUnder(w: any, root: string): ({ [string]: boolean }, number)
	local texts: { [string]: boolean } = {}
	local bars = 0
	for _, path in w.adapter.paths() do
		if string.sub(path, 1, #root + 1) ~= root .. "/" and path ~= root then
			continue
		end
		if w.adapter.visibleOf(path) == false then
			continue
		end
		local node = w.adapter.node(path)
		if node == nil then
			continue
		end
		if node.class == "Text" and type(node.props.text) == "string" and node.props.text ~= "" then
			texts[node.props.text] = true
		end
		-- a `newProgressView`'s track is the leaf named `Bar`; its fill is `Bar/Fill`
		if string.match(path, "/Bar$") ~= nil then
			bars += 1
		end
	end
	return texts, bars
end

--[[ WAVE REVEAL SPLIT THE ROUTE IN TWO, and these two cases are the same claim
	read against the right half of it. The claim has not moved: EVERYTHING THE
	RICHEST FORM SHOWS MUST BE REACHABLE FROM WHATEVER IS ON SCREEN. What moved is
	which surface answers.

	A zone that stepped DOWN is still on screen, so it discloses its own richest
	form where it stands: the census lists it as "Simplified — open to expand" and
	the row opens THAT zone's plate, rather than pasting a second copy of the zone's
	content into the sink (two disclosures of one thing drift the first time either
	changes). A zone that was DROPPED has no form left to disclose from, so the sink
	still carries its content inline. Both cases are driven here through the real
	tap path, so "activating a row triggers the same disclosure" is proven rather
	than asserted. ]]
describe("the recovery route discloses the SAME content the richest form shows", function()
	it("the task panel's rows reach the sink whole — names, rewards and bars, not a caption", function()
		-- the RICH form, at a viewport with room for it
		local roomy = drive({ id = "tablet-landscape", w = 1079, h = 809, displaySize = "Small", input = "Touch" })
		local richTexts, richBars = contentUnder(roomy, "/HudScreen/Hud/Tasks")
		-- the fixture is only meaningful if the rich form is actually up here
		expect(`the rich task panel is showing: {richTexts[hudScenario.copy.tasksTitle] == true}`).toBe(
			"the rich task panel is showing: true"
		)
		expect(`the rich task panel has a bar per task: {richBars}`).toBe("the rich task panel has a bar per task: 3")
		roomy.dispose()

		-- ...and the ROUTE, at a viewport where the zone has stepped down or gone
		local tight = drive({ id = "narrow-landscape", w = 640, h = 320, displaySize = "Small", input = "Touch" })
		tight.built.steps.openUrlBar()
		tight.refresh()
		local opened = tight.built.steps.openOverflow()
		tight.refresh()
		expect(opened.open).toBe(true)
		--[[ THE CENSUS ROW, TAPPED. `Tasks` has stepped down rather than been
			dropped, so the sink lists it as simplified and the row is the route: one
			tap opens the zone's own plate, which is where its rich form lives. ]]
		tight.adapter.tap("/HudOverflow/Layer/Surface/OverflowPanel/OverflowBody/OverflowExpandTasks")
		tight.refresh()
		local panelTexts, panelBars = contentUnder(tight, "/Expand:Tasks")

		local missing: { string } = {}
		for text in richTexts do
			if not panelTexts[text] then
				table.insert(missing, text)
			end
		end
		table.sort(missing)
		expect(
			`strings the rich form shows and the route does not: {#missing}`
				.. `{if #missing > 0 then " (" .. table.concat(missing, ", ") .. ")" else ""}`
		).toBe("strings the rich form shows and the route does not: 0")
		expect(`progress bars on the route: {panelBars}`).toBe("progress bars on the route: 3")
		tight.refresh()
		tight.dispose()
	end)

	--[[ THE CENSUS'S EMPTY STATE IS A CLAIM, AND IT HAS TO BE TRUE (fix round 1).

		"Nothing is hidden — every zone is showing everything it has" used to print
		whenever `unshown` was empty, and `unshown` excludes a `recover = "none"`
		route BY CONSTRUCTION. So a zone standing on a REDUCED form could be on the
		screen while the sink said every zone was showing everything. The sink now
		reads both halves of the same dump — what is missing (`unshown`) and what is
		SIMPLIFIED (`activeForm > 1`) — and waits for both to be silent.

		WHAT THIS CASE CAN AND CANNOT WITNESS, stated rather than implied: this
		fixture has no multi-form `recover = "none"` region, so the state where the
		two halves DISAGREE cannot be produced here — every stepped-down zone in this
		HUD declares a route and is therefore already in `unshown`. That state is
		pinned where it IS reachable (`tests/region_expand.spec.luau`, EXPAND 2b, at
		the pure layer). What this pins is the sink's own behaviour in both
		directions, which is what catches the empty state being deleted, inverted, or
		printed unconditionally. ]]
	it("the sink says 'nothing is hidden' only when the dump agrees, in both directions", function()
		local EMPTY_LINE = "/HudOverflow/Layer/Surface/OverflowPanel/OverflowBody/OverflowEmpty"
		-- ROOMY: nothing dropped, nothing stepped down, and the line is there
		local roomy = drive({ id = "tablet-landscape", w = 1079, h = 809, displaySize = "Small", input = "Touch" })
		local dump = roomy.handle.controller.compositionAt("/HudScreen/Hud")
		local stepped = 0
		for _, r in dump.regions do
			if (r.activeForm or 0) > 1 then
				stepped += 1
			end
		end
		expect(`roomy: unshown={#dump.unshown} stepped={stepped}`).toBe("roomy: unshown=0 stepped=0")
		roomy.built.steps.openOverflow()
		roomy.refresh()
		expect(`roomy: the empty line is up={roomy.adapter.node(EMPTY_LINE) ~= nil}`).toBe(
			"roomy: the empty line is up=true"
		)
		roomy.built.steps.closeOverflow()
		roomy.refresh()
		roomy.dispose()

		-- TIGHT: zones have given way, so the claim is false and is not made
		local tight = drive({ id = "narrow-landscape", w = 640, h = 320, displaySize = "Small", input = "Touch" })
		tight.built.steps.openUrlBar()
		tight.refresh()
		tight.built.steps.openOverflow()
		tight.refresh()
		expect(`tight: the empty line is up={tight.adapter.node(EMPTY_LINE) ~= nil}`).toBe(
			"tight: the empty line is up=false"
		)
		tight.built.steps.closeOverflow()
		tight.refresh()
		tight.dispose()
	end)

	it("...and the weapon rail's ammo counts reach it the same way", function()
		local roomy = drive({ id = "compact-phone-portrait", w = 359, h = 718, displaySize = "Small", input = "Touch" })
		local richTexts = contentUnder(roomy, "/HudScreen/Hud/Rail")
		expect(`the full rail is showing: {richTexts[hudScenario.copy.ammo1] == true}`).toBe(
			"the full rail is showing: true"
		)
		roomy.dispose()

		local tight = drive({ id = "narrow-landscape", w = 640, h = 320, displaySize = "Small", input = "Touch" })
		tight.built.steps.openUrlBar()
		tight.refresh()
		tight.built.steps.openOverflow()
		tight.refresh()
		tight.adapter.tap("/HudOverflow/Layer/Surface/OverflowPanel/OverflowBody/OverflowExpandRail")
		tight.refresh()
		local panelTexts = contentUnder(tight, "/Expand:Rail")
		local missing: { string } = {}
		for text in richTexts do
			if not panelTexts[text] then
				table.insert(missing, text)
			end
		end
		table.sort(missing)
		expect(
			`rail strings the route does not reach: {#missing}`
				.. `{if #missing > 0 then " (" .. table.concat(missing, ", ") .. ")" else ""}`
		).toBe("rail strings the route does not reach: 0")
		tight.refresh()
		tight.dispose()
	end)
end)
