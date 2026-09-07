--!strict
--[[ ── THE CHROME-AND-ROTATION SEQUENCE, AND WHAT IT PROVED (2026-09-07) ───────

	THE REPORT (`hud.mov`, repository root, a physical phone): landscape ->
	URL bar ON -> portrait -> URL bar OFF -> landscape leaves the shipped HUD's
	score, kill feed, task panel, weapon rail and objective pill OFF THE SCREEN,
	while the fixture's own paint probe reads `14 of 14 rows wanted, 14 of 14
	painting`. What is missing is a CONTIGUOUS DOCUMENT-ORDER PREFIX that ends
	immediately before the fixture's first `Path` node — the signature
	`tests/hud_paint_probe.spec.luau` was written for (NM-H4a, 2026-08-16).

	── WHAT THIS FILE IS, AND WHAT IT IS NOT ────────────────────────────────────

	It is NOT a reproduction. It is the axis the corpus was uniform along, driven
	until it could not hide anything, and it is GREEN — a null result, recorded
	here rather than in a chat message, with the live finding beside it so the
	next reader starts where this one stopped.

	MEASURED, over the whole sequence and every variant of it below: the model
	side converges EXACTLY. Restored landscape equals a fresh landscape mount
	node for node — the same node set, the same rects, the same `Visible`, the
	same elision, the same hit rects, the same property bag, the same paint-order
	RANKING, the same focus traversal, the same context and adapter-handler
	census — across ~700 nodes and every position the URL bar can be toggled in.
	Nothing in `mount`, `layout`, `render` or `env` is holding stale state.

	── WHERE THE DEFECT ACTUALLY LIVES (Studio, compact-phone profile, 734x372) ──

	Driven live in the showcase `hud` demo, ONE portrait <-> landscape rotation is
	enough. In the broken state every fact this framework owns reads back CORRECT
	off the engine — `AbsolutePosition`, `AbsoluteSize`, `Visible`, `ZIndex`,
	`Parent`, and `GetStyled` on every paint property, for a dark node and a lit
	node alike — and no instance was recycled across the rotation (99 kept, 0
	adopted). It is the ENGINE's draw list for that `ScreenGui` that is stale:
	any write that dirties it — a `ZIndex` or `Visible` change on ANY ONE child,
	or one child added — repaints the whole prefix at once, and a `Position`
	write does not.

	THE NECESSARY INGREDIENT IS `Path2D`, measured by removal: with the adapter's
	`Path2D` creation disabled the identical drive survives TWENTY rotation
	cycles with nothing lost; with it, the first cycle loses the prefix. That is
	why the run always ends before the first `Path` node.

	So a headless target cannot see this and should not pretend to: the fake
	target has no `Path2D` and no engine draw list. What it CAN do is refuse the
	other half of the search — "the give-way decision latched", "a rect went
	stale", "a hidden row never came back" — and that is what every case below
	is for. Each one is written so that a model-side regression on this axis
	fails HERE, on the commit that introduces it, instead of in a photograph.

	── HOW THE FACTS ARE PUBLISHED, AND WHY THAT MATTERS ────────────────────────

	One per tick, in the order `src/client/roblox_env.luau` delivers them, not in
	one `env:batch` — `tests/hud_chrome_rotation.spec.luau`'s DIR-5 header owns
	that argument, and deleting `viewportRect` from that order reddens all eight
	cases below (mutation-proved).

	AND THE ENGINE ANSWERS TEXT, because the live one does: the fake queues width
	batches and answers nothing unless a spec plays the engine, so a corpus that
	never answers is solving against the ESTIMATE for ever. It is here for
	fidelity and it is recorded as a NULL RESULT rather than claimed as coverage —
	measured 2026-09-07, removing the answers reddens nothing here, because both
	sides of every comparison are driven the same way and the estimate is
	self-consistent. What it buys is that a future divergence which only appears
	once real widths land has a place to appear.

	── AND ANSWERING IS A PROCESS-GLOBAL WRITE, SO IT IS BRACKETED ──────────────

	`src/layout/text_metrics.luau`'s exact-width store is ONE table shared by
	every core and every surface in the session — its own header says so — and
	answering a batch teaches it. This file answers with a FABRICATED width
	function and its vocabulary is the shipped HUD's, so an unbracketed run left
	every later spec measuring that HUD's words against this file's arithmetic.
	Found by a pair test: `hud_chrome_sequence` immediately before
	`tests/hit_floor_region_clamp.spec.luau` moved its measured covers from
	75 | 80 to 68 | 47, standalone-green both ways.

	So every case here brackets the store, the way `tests/layout.spec.luau`
	does around its own `setMeasured` calls: reset on the way IN, so this file
	cannot inherit another's vocabulary either, and a closing case that resets and
	ASSERTS the store is clean, so the discipline is checked rather than
	remembered.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local fake_target = require("./lib/fake_target")
local text_metrics = require("../src/layout/text_metrics")
local test_world = require("./lib/world")
local hud = require("../examples/gallery/scenarios/hud") :: any

-- the showcase's own chip-strip reservation, the shape the live session lays out
-- under (see tests/hud_chrome_rotation.spec.luau)
local PLATFORM_TOP = 58
local CHIP_STRIP = 62
local SHOWCASE_TOP = PLATFORM_TOP + CHIP_STRIP

type View = { w: number, h: number }

-- the reported device, in points, as the probe plate printed them
local PORTRAIT: View = { w = 393, h = 759 }
local LANDSCAPE: View = { w = 734, h = 393 }

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

-- the order the adapter delivers them in (`roblox_env.pushViewportFacts` plus
-- `safe_insets`' per-area belt); the same list DIR-5 drives
local DEVICE_ORDER = {
	"viewportRect",
	"topbarInset",
	"coreSafeInsets",
	"deviceSafeInsets",
	"topbarSafeInsets",
	"displaySize",
}

--[[ A PLAUSIBLE ENGINE. Word widths arrive asynchronously on a device and the
	fake answers nothing on its own, so every `settle` below plays the engine
	until the queue is empty. Any monotone function of the word would do; what
	matters is that BOTH sides of every comparison get the same one. ]]
local function engineWidth(word: string, size: number, _font: string): number?
	return #word * size * 0.52 + 1
end

--[[ SIX FRAMES, EACH ONE ANSWERED. `tests/lib/world.luau`'s own `settle` is the
	right shape for a fixture whose text the engine never has to answer; this one
	interleaves the answers, because a batch delivered between two frames is what
	a phone does and because the shipped `settle` would leave the queue standing.
	The world's containment invariant is still asked, at the same point it asks it
	itself: after the loop, on the state the caller is about to assert against. ]]
--[[ THE BRACKET. Called first in every case: this file teaches the process-global
	exact-width store, so it must neither inherit a vocabulary nor leave one. ]]
local function freshMetrics()
	text_metrics.resetMeasured()
end

local function settle(w: any)
	for _ = 1, 6 do
		w.pres.refresh()
		for _ = 1, 4 do
			if w.adapter.textBatchCount() == 0 then
				break
			end
			w.adapter.deliverTextWidths(engineWidth)
			w.pres.refresh()
		end
	end
	w.overflowGuard()
end

--[[ ON THE SHARED SUBSTRATE (`tests/lib/world.luau`, ruling R12). Its follow-up
	trigger is exactly this file's case — "the next spec file that ADDS a builder
	migrates its file instead" — so this one never hand-rolls the six objects. The
	two things it does on top are the two this fixture needs and the substrate does
	not own: the target's scroll reserve, and the engine seam the fixture's own
	paint probe reads. ]]
local function world(view: View): any
	local w = test_world.new({
		viewport = platform(view).viewportRect,
		safeInsets = platform(view).coreSafeInsets,
		preferredInput = "Touch",
		capabilities = { keyboard = false, mouse = false, touch = true, gamepad = false },
		displaySize = "Medium",
		env = {
			deviceSafeInsets = platform(view).deviceSafeInsets,
			topbarSafeInsets = platform(view).topbarSafeInsets,
			topbarInset = platform(view).topbarInset,
		},
	})
	local core, env, adapter, system, presenter = w.core, w.env, w.adapter, w.system, w.pres;
	(adapter :: any).scrollBarThickness = fake_target.SCROLL_BAR_RESERVE
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
		--[[ THE ENGINE SEAM THE PROBE READS, answered off the fake exactly as
			`tests/hud_paint_probe.spec.luau` answers it: the fixture must take the
			branch it takes on a phone, not its degraded model-only one. ]]
		geometry = function(paths: { string }): any
			local out: { [string]: any } = {}
			for _, path in paths do
				local node = adapter.node(path)
				if node ~= nil and node.rect ~= nil then
					local screenId = string.match(path, "^/([^/]+)")
					out[path] = {
						x = node.rect.x,
						y = node.rect.y,
						w = node.rect.w,
						h = node.rect.h,
						visible = adapter.visibleOf(path) ~= false,
						enabled = if screenId ~= nil then adapter.rootVisibleOf(screenId) ~= false else true,
					}
				end
			end
			return out
		end,
	})
	handle = w.present(built.screen, built.present)
	built.handle = handle
	w.built = built
	settle(w)
	return w
end

local function rotate(w: any, view: View)
	local facts = platform(view)
	for _, key in DEVICE_ORDER do
		w.env:set(key, facts[key])
		settle(w)
	end
end

--[[ ── THE CENSUS: EVERY OBSERVABLE THE TARGET HOLDS ───────────────────────────

	Rects, `Visible`, elision, the hit rect, the instance host and surface root,
	and the whole property bag — because the reported defect is precisely one
	where SOME of those agree and the screen does not, so a census that reads
	only the zone rects is the census that has already missed it once
	(`hud_chrome_rotation.spec`'s `snap` reads eleven paths).

	TWO NORMALISATIONS, each for a stated reason:

	  * table-valued props are compared by IDENTITY-FREE placeholder. A font
	    descriptor or a tint is a fresh table on every rebuild, so comparing the
	    addresses would report every node as different and the case would be
	    noise. What is asserted about them is that the same KEYS are worn.
	  * the probe plate's own head carries the SOLVE COUNTER (`734x393 s90`), which
	    is by construction different between a fresh mount and a driven one. It is
	    the instrument, not the subject.

	PAINT ORDER IS COMPARED AS A RANKING, never as a number. `render/z_order.luau`
	states it: only each parent's children's relative order is observable and gaps
	are free, so a bounded structural sync legitimately leaves a driven tree's
	counter higher than a fresh mount's. A value comparison would fail on a
	surface that is painting in exactly the right order. ]]
local function census(w: any): { [string]: string }
	local paths = w.adapter.paths()
	local rank: { [string]: number } = {}
	do
		local ordered: { string } = {}
		for _, path in paths do
			local node = w.adapter.node(path)
			if node ~= nil and node.z ~= nil then
				table.insert(ordered, path)
			end
		end
		table.sort(ordered, function(a, b)
			return (w.adapter.node(a).z :: number) < (w.adapter.node(b).z :: number)
		end)
		for i, path in ordered do
			rank[path] = i
		end
	end
	local out: { [string]: string } = {}
	for _, path in paths do
		local node = w.adapter.node(path)
		local rect = node.rect
		local hit = w.adapter.hitRectOf(path)
		local keys: { string } = {}
		for k in node.props do
			table.insert(keys, k)
		end
		table.sort(keys)
		local props: { string } = {}
		for _, k in keys do
			local value = node.props[k]
			table.insert(props, `{k}={if type(value) == "table" then "<table>" else tostring(value)}`)
		end
		local propText = table.concat(props, " ")
		-- the probe's own head is the solve counter; see the header
		propText = string.gsub(propText, "label=%d+x%d+ s%d+", "label=<viewport>")
		out[path] = string.format(
			"%s rect=%s vis=%s elided=%s rank=%s root=%s host=%s hit=%s props=[%s]",
			tostring(node.class),
			if rect ~= nil then string.format("%.2fx%.2f@%.2f,%.2f", rect.w, rect.h, rect.x, rect.y) else "(none)",
			tostring(w.adapter.visibleOf(path)),
			tostring(node.elided),
			tostring(rank[path]),
			tostring(w.adapter.rootIdOf(path)),
			tostring(if node.instanceHost ~= nil then node.instanceHost.path else nil),
			if hit ~= nil then string.format("%.2fx%.2f@%.2f,%.2f", hit.w, hit.h, hit.x, hit.y) else "(none)",
			propText
		)
	end
	return out
end

-- the focus ring, as Tab would walk it
local function traversal(w: any): string
	local dump = w.built.handle.focusOrder()
	local ids: { string } = {}
	for _, entry in dump.traversal do
		table.insert(ids, `{tostring(entry.id)}:{tostring(entry.eligible)}`)
	end
	return table.concat(ids, ",")
end

--[[ WHAT IS BOUND, on both sides of the seam. `contextCount` is the input
	model's own census; `handlerCount` is what the TARGET is holding — on a phone
	each of those slots is a live `RBXScriptConnection`, so it is the honest
	headless stand-in for "the actions the player can still reach". ]]
local function bindings(w: any): string
	return `contexts={w.system.contextCount()} handlers={w.adapter.handlerCount()}`
end

--[[ ...AND THAT THE TREE REALLY IS AT THAT VIEWPORT. "The screens differ" is
	NOT enough and this file learned it the hard way: with `viewportRect` deleted
	from the publish order above, five of the six facts still move (the topbar
	inset is derived from the width), every census still differs between the two
	steps, and every case below went GREEN on a surface that never rotated at
	all. So the premise is asserted against the VIEWPORT: the HUD's own box spans
	the width it was given, minus the screen gutter it always spends. Mutation-
	proved in both directions 2026-09-07. ]]
local function assertAtViewport(w: any, view: View, where: string)
	local node = w.adapter.node("/HudScreen/Hud")
	local rect = if node ~= nil then node.rect else nil
	expect(`{where}: the HUD has a box: {rect ~= nil}`).toBe(`{where}: the HUD has a box: true`)
	--[[ THE GUTTER IS NOT PINNED HERE, only bounded: it is the theme's own space
		step and this case is about the viewport, not about the theme. What it
		refuses is the tree still being laid out for the OTHER orientation, which is
		off by hundreds of pixels either way. ]]
	local spread = math.abs((rect :: any).w - view.w)
	expect(`{where}: the HUD spans {view.w} (off by {spread <= 64}): true`).toBe(
		`{where}: the HUD spans {view.w} (off by true): true`
	)
end

local function differences(got: { [string]: string }, want: { [string]: string }): { string }
	local seen: { [string]: boolean } = {}
	for path in got do
		seen[path] = true
	end
	for path in want do
		seen[path] = true
	end
	local keys: { string } = {}
	for path in seen do
		table.insert(keys, path)
	end
	table.sort(keys)
	local out: { string } = {}
	for _, path in keys do
		if got[path] ~= want[path] then
			table.insert(out, `{path}\n    driven {tostring(got[path])}\n    fresh  {tostring(want[path])}`)
		end
	end
	return out
end

-- the oracle, built the same way every case reads it
local function freshLandscape(): any
	return world(LANDSCAPE)
end

describe("hud: the reported chrome-and-rotation sequence lands on a fresh landscape mount", function()
	it("landscape -> URL bar on -> portrait -> URL bar off -> landscape", function()
		freshMetrics()
		local fresh = freshLandscape()
		local want = census(fresh)

		local live = world(LANDSCAPE)
		local start = census(live)
		live.built.steps.openUrlBar()
		settle(live)
		rotate(live, PORTRAIT)
		assertAtViewport(live, PORTRAIT, "the middle of the sequence")
		local midway = census(live)
		live.built.steps.closeUrlBar()
		settle(live)
		rotate(live, LANDSCAPE)

		--[[ THE SEQUENCE WENT SOMEWHERE, asserted before the oracle is trusted. A
			drive that never left the landscape screen would satisfy every assertion
			below and prove nothing — the vacuity `hud_chrome_rotation.spec` has had
			to fix once already. ]]
		expect(`portrait differs from landscape: {#differences(midway, start) > 0}`).toBe(
			"portrait differs from landscape: true"
		)

		assertAtViewport(live, LANDSCAPE, "the restored end of the sequence")

		local d = differences(census(live), want)
		expect(`divergences ({#d}):\n  {table.concat(d, "\n  ")}`).toBe("divergences (0):\n  ")
	end)

	--[[ THE URL BAR IN EVERY POSITION IT CAN BE TOGGLED IN. The reported drive is
		one cell of this table; the others exist because a fix that closed only the
		reported ordering would be a fix for a photograph. Each cell ends in
		landscape with the bar CLOSED, so the fresh landscape mount is the oracle
		for all of them. ]]
	local POSITIONS = {
		{ name = "never touched", onBefore = false, onDuring = false },
		{ name = "on before the rotation, off after it", onBefore = true, onDuring = false },
		{ name = "on only while portrait", onBefore = false, onDuring = true },
		{ name = "on before AND toggled again in portrait", onBefore = true, onDuring = true },
	}

	for _, row in POSITIONS do
		it(`the URL bar {row.name}: the restored landscape is still the fresh mount`, function()
			freshMetrics()
			local fresh = freshLandscape()
			local want = census(fresh)

			local live = world(LANDSCAPE)
			if row.onBefore then
				live.built.steps.openUrlBar()
				settle(live)
			end
			rotate(live, PORTRAIT)
			assertAtViewport(live, PORTRAIT, `{row.name}: the portrait leg`)
			if row.onDuring then
				live.built.steps.openUrlBar()
				settle(live)
			end
			live.built.steps.closeUrlBar()
			settle(live)
			rotate(live, LANDSCAPE)
			assertAtViewport(live, LANDSCAPE, `{row.name}: the restored end`)

			local d = differences(census(live), want)
			expect(`{row.name} divergences ({#d}):\n  {table.concat(d, "\n  ")}`).toBe(
				`{row.name} divergences (0):\n  `
			)
		end)
	end

	--[[ REPEATED ROTATION, because the live failure is not always the FIRST cycle:
		driven in Studio it landed on cycle 1 unmodified and on cycle 13 under one
		candidate change, so a single-cycle case is a case that can be passed by
		luck. Every cycle is compared, not only the last, so a drift that
		accumulates names the cycle it started on. ]]
	it("N rotation cycles: every one of them lands on the fresh landscape mount", function()
		freshMetrics()
		local fresh = freshLandscape()
		local want = census(fresh)

		local live = world(LANDSCAPE)
		for cycle = 1, 4 do
			rotate(live, PORTRAIT)
			local portrait = census(live)
			expect(`cycle {cycle}: portrait is a different screen: {#differences(portrait, want) > 0}`).toBe(
				`cycle {cycle}: portrait is a different screen: true`
			)
			assertAtViewport(live, PORTRAIT, `cycle {cycle} portrait`)
			rotate(live, LANDSCAPE)
			assertAtViewport(live, LANDSCAPE, `cycle {cycle} landscape`)
			local d = differences(census(live), want)
			expect(`cycle {cycle} divergences ({#d}):\n  {table.concat(d, "\n  ")}`).toBe(
				`cycle {cycle} divergences (0):\n  `
			)
		end
	end)

	--[[ THE TWO THINGS A RECT CENSUS CANNOT SEE. A surface can come back painting
		the right pixels and still have lost the player's way IN to them: the Tab
		ring and what the input system is holding. Both are compared against the
		fresh mount, because "restored" has to mean restored for a thumb and a
		keyboard as well as for a camera. ]]
	it("focus ring and bindings come back equal to the fresh mount's", function()
		freshMetrics()
		local fresh = freshLandscape()
		local wantRing, wantBound = traversal(fresh), bindings(fresh)

		local live = world(LANDSCAPE)
		live.built.steps.openUrlBar()
		settle(live)
		rotate(live, PORTRAIT)
		assertAtViewport(live, PORTRAIT, "the focus case's portrait leg")
		live.built.steps.closeUrlBar()
		settle(live)
		rotate(live, LANDSCAPE)

		-- ...and the ring is not empty on either side, or this compares nothing
		expect(`the fresh ring has entries: {wantRing ~= ""}`).toBe("the fresh ring has entries: true")
		expect(`traversal {traversal(live)}`).toBe(`traversal {wantRing}`)
		expect(`bindings {bindings(live)}`).toBe(`bindings {wantBound}`)
	end)

	--[[ TEARDOWN AFTER THE SEQUENCE. A surface that survives the drive and then
		leaks on dismissal has moved the defect rather than fixed it, and the drive
		is exactly the shape that would leave a corpse behind: rows elided and
		restored, a branch opened and closed, a hit expander destroyed and rebuilt
		on every rotation. ]]
	it("dispose after the sequence leaves no live node, no handler and no root", function()
		freshMetrics()
		local live = world(LANDSCAPE)
		live.built.steps.openUrlBar()
		settle(live)
		rotate(live, PORTRAIT)
		assertAtViewport(live, PORTRAIT, "the teardown case's portrait leg")
		live.built.steps.closeUrlBar()
		settle(live)
		rotate(live, LANDSCAPE)

		-- the surface really was standing, or the teardown assertions are vacuous
		expect(`the surface was live: {live.adapter.liveCount() > 50}`).toBe("the surface was live: true")

		--[[ BOTH HALVES OF THE TEARDOWN, in the order a host performs them. The
			fixture's own `dispose` retires what the FIXTURE opened — the overflow
			sink, the probe surface and its frame clock, the animated views; the
			presenter's `dismiss` retires the SURFACE. A case that called only the
			first would be asserting that a screen nobody dismissed is empty. ]]
		live.built.dispose()
		live.pres.dismiss(live.built.handle)
		live.pres.refresh()
		expect(`live nodes after dispose: {live.adapter.liveCount()}`).toBe("live nodes after dispose: 0")
		expect(`adapter handlers after dispose: {live.adapter.handlerCount()}`).toBe(
			"adapter handlers after dispose: 0"
		)
		expect(`surface roots after dispose: {live.adapter.rootCount()}`).toBe("surface roots after dispose: 0")
	end)

	--[[ ...AND THE PROCESS-GLOBAL STORE THIS FILE TEACHES IS HANDED BACK CLEAN.

		Last, and it is the cleanup AND the check on it: a bracket nobody asserts is
		one the next edit drops, and the way this one went missing the first time was
		invisible to every spec run on its own — it surfaced as a STRANGER's measured
		geometry moving (`tests/hit_floor_region_clamp.spec.luau`'s HUD covers, 75|80
		-> 68|47, with both files green standalone).

		`measuredDump` is asked rather than a word being guessed, because which words
		at which size reach the store is the theme's business and not this case's. ]]
	it("hands the process-global width store back the way it found it", function()
		freshMetrics()
		local live = world(LANDSCAPE)
		rotate(live, PORTRAIT)
		rotate(live, LANDSCAPE)

		--[[ THE PREMISE: the drive really did teach the store, or the reset below
			has nothing to undo and this passes on a file that answered nothing. ]]
		local dump = text_metrics.measuredDump()
		expect(`the drive taught the store: {#dump > 0}`).toBe("the drive taught the store: true")
		local one = dump[1]
		expect(`and it can be read back: {text_metrics.measuredWidth(one.font, one.size, one.word) ~= nil}`).toBe(
			"and it can be read back: true"
		)

		text_metrics.resetMeasured()
		expect(`the store forgot it: {text_metrics.measuredWidth(one.font, one.size, one.word) == nil}`).toBe(
			"the store forgot it: true"
		)
		expect(`nothing is left behind: {text_metrics.measuredCount()}`).toBe("nothing is left behind: 0")
	end)
end)
