--!strict
-- A hug ScrollView must MEASURE the bar its own arrange will RESERVE
-- (matrix row 2026-08-08, ref_wardrobe compact-phone-portrait: every category
-- chip overflowed its box by exactly the engine scrollbar's 8px). The arrange
-- pass reserves `scrollBarReserve` off the cross axis whenever the scroll axis
-- overflows — so a scroller whose own cross size HUGS content reported a size
-- at which it cannot reproduce itself: the parent granted content-height, the
-- arrange subtracted the bar, and every child was 8px too tall for the box.
-- Same fixed-point family as the Grid measure fix (grid_measure_arrange.spec).
--
-- The headless twin is deliberately opted in per-world here: the fake target
-- publishes no scrollBarThickness by default, which is WHY no headless sweep
-- ever saw this class — recorded in the stage's framework-fixes ledger.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local fake_target = require("./lib/fake_target")

local function world(withBar: boolean, build: (any) -> any)
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 360, h = 691 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	if withBar then
		(adapter :: any).scrollBarThickness = 8
	end
	local presenter = Facet.newPresenter(core, env, adapter, system)
	local handle = presenter.present(build(Facet.UI, core), {})
	presenter.refresh()
	return core, adapter, presenter, handle
end

local function chipRow(UI: any): any
	local chips: { any } = {}
	for i = 1, 9 do
		-- the REAL trigger shape from the live matrix row: a ZStack chip (button
		-- + a paint overlay). Leaf children slip past the overflow detector;
		-- container children are what the live defect clipped.
		chips[#chips + 1] = UI.ZStack({
			id = "C" .. i,
			children = {
				UI.Button({ id = "B", label = "Chip " .. i }),
				UI.Box({
					id = "U",
					height = { type = "fixed", px = 3 },
					width = { type = "fill", weight = 1 },
					alignV = "end",
					surface = "accent",
				}),
			},
		})
	end
	return UI.Screen({
		id = "S",
		children = {
			UI.VStack({
				id = "Col",
				gap = "s",
				children = {
					UI.ScrollView({
						id = "Shelf",
						axis = "x",
						gap = "s",
						width = { type = "fill", weight = 1 },
						children = chips,
					}),
					UI.Text({ id = "Below", text = "below the shelf" }),
				},
			}),
		},
	})
end

describe("ScrollView measure includes the bar its arrange reserves", function()
	it("an overflowing hug x-shelf reports zero diagnostics with a live bar", function()
		local core, _, _, handle = world(true, chipRow)
		local diags = handle.controller.diagnostics()
		expect(#diags).toBe(0)
		expect(core:lastError()).toBeNil()
	end)

	it("the shelf's box is tall enough for a full control PLUS the bar", function()
		local _, _, _, handle = world(true, chipRow)
		local shelf = handle.controller.rectOf("/S/Col/Shelf")
		local chip = handle.controller.rectOf("/S/Col/Shelf/C1")
		expect(shelf ~= nil and chip ~= nil).toBe(true)
		expect(shelf.h >= chip.h + 8).toBe(true)
	end)

	it("without a bar (fallback adapters) nothing changes", function()
		local _, _, _, handle = world(false, chipRow)
		local diags = handle.controller.diagnostics()
		expect(#diags).toBe(0)
		local shelf = handle.controller.rectOf("/S/Col/Shelf")
		local chip = handle.controller.rectOf("/S/Col/Shelf/C1")
		expect(shelf.h).toBe(chip.h)
	end)

	it("a shelf whose content FITS reserves nothing", function()
		local _, _, _, handle = world(true, function(UI: any, _core: any)
			return UI.Screen({
				id = "S",
				children = {
					UI.VStack({
						id = "Col",
						gap = "s",
						children = {
							UI.ScrollView({
								id = "Shelf",
								axis = "x",
								gap = "s",
								width = { type = "fill", weight = 1 },
								children = { UI.Button({ id = "C1", label = "One" }) },
							}),
						},
					}),
				},
			})
		end)
		local shelf = handle.controller.rectOf("/S/Col/Shelf")
		local chip = handle.controller.rectOf("/S/Col/Shelf/C1")
		expect(shelf.h).toBe(chip.h)
	end)

	it("the vertical mirror: an overflowing hug-width y-scroller widens by the bar", function()
		local _, _, _, handle = world(true, function(UI: any, _core: any)
			local rows: { any } = {}
			for i = 1, 30 do
				rows[#rows + 1] = UI.Button({ id = "R" .. i, label = "Row " .. i })
			end
			return UI.Screen({
				id = "S",
				children = {
					UI.HStack({
						id = "Row",
						gap = "s",
						height = { type = "fill", weight = 1 },
						children = {
							UI.ScrollView({
								id = "List",
								height = { type = "fill", weight = 1 },
								gap = "s",
								children = rows,
							}),
							UI.Text({ id = "Beside", text = "beside" }),
						},
					}),
				},
			})
		end)
		local diags = handle.controller.diagnostics()
		expect(#diags).toBe(0)
		local list = handle.controller.rectOf("/S/Row/List")
		local row = handle.controller.rectOf("/S/Row/List/R1")
		expect(list.w >= row.w + 8).toBe(true)
	end)
end)

--[[ ── THE GUTTER IS PUBLISHED, ON THE SIDE IT WAS TAKEN FROM ──────────────────

	A host's own descendants never need this number — the reservation already
	narrowed the box they were measured in. The node that needs it is the one
	OUTSIDE the subtree that must still line up across the boundary: a Table's
	header is a sibling of its scrolling body and drifted by exactly the reserve
	until it started paying it too (director report 2026-08-14, and the follow-up
	correction "the scroll bar issue should apply to both horizontal and vertical
	ones" — which is why the side is published rather than assumed).

	`newTable` is the only consumer today and its body always scrolls Y, so the X
	half would ship untested on the strength of a `then/else`. This is the case
	that measures it: the SAME reserve, the SAME overflow, reported on `bottom`
	because the shelf scrolls sideways.

	MUTATION-PROVEN 2026-08-14: swapping the solver's two branches (publishing
	`right` for an X host) fails the shelf case; dropping the `spentReserve > 0`
	guard fails the "reserves nothing" case. ]]
describe("the bar gutter a host spent is published for its SIBLINGS to pay", function()
	it("an X shelf reports it on `bottom` — the side an X scroller reserves from", function()
		local _, _, _, handle = world(true, chipRow)
		local inset = handle.controller.scrollBarInsetOf("/S/Col/Shelf")
		expect(`x:{inset ~= nil and `{inset.right}/{inset.bottom}` or "nil"}`).toBe("x:0/8")
	end)

	it("a Y list reports it on `right`", function()
		local _, _, _, handle = world(true, function(UI: any, _core: any)
			local rows: { any } = {}
			for i = 1, 30 do
				rows[#rows + 1] = UI.Button({ id = "R" .. i, label = "Row " .. i })
			end
			return UI.Screen({
				id = "S",
				children = {
					UI.ScrollView({
						id = "List",
						height = { type = "fill", weight = 1 },
						gap = "s",
						children = rows,
					}),
				},
			})
		end)
		local inset = handle.controller.scrollBarInsetOf("/S/List")
		expect(`y:{inset ~= nil and `{inset.right}/{inset.bottom}` or "nil"}`).toBe("y:8/0")
	end)

	it("a host whose content FITS reserves nothing, and publishes nothing", function()
		-- the conditionality is the whole reason this is published rather than
		-- re-derived from `adapter.scrollBarThickness`: a sibling cannot know
		-- whether THIS host's content overflowed
		local _, _, _, handle = world(true, function(UI: any, _core: any)
			return UI.Screen({
				id = "S",
				children = {
					UI.ScrollView({
						id = "Shelf",
						axis = "x",
						width = { type = "fill", weight = 1 },
						children = { UI.Button({ id = "C1", label = "One" }) },
					}),
				},
			})
		end)
		expect(handle.controller.scrollBarInsetOf("/S/Shelf")).toBeNil()
	end)

	it("...and a fallback adapter with no bar publishes nothing either", function()
		local _, _, _, handle = world(false, chipRow)
		expect(handle.controller.scrollBarInsetOf("/S/Col/Shelf")).toBeNil()
	end)

	it("an unmounted host stops answering", function()
		-- `lastBarInsets` is renderer state keyed by path; a path that leaves the
		-- tree and comes back as something else must not inherit the old gutter
		local _, _, presenter, handle = world(true, chipRow)
		expect(handle.controller.scrollBarInsetOf("/S/Col/Shelf")).never().toBeNil()
		presenter.dismiss(handle)
		presenter.refresh()
		expect(handle.controller.scrollBarInsetOf("/S/Col/Shelf")).toBeNil()
	end)
end)

--[[ ── ITEM 3 (framework-gaps-phase2-followups, task MISC): "desktop scrollbar
	reserves no pixels, overlaps content" ────────────────────────────────────

	desktopScroll.png is a plain vertical list of individually-rounded,
	FULL-WIDTH cards — the shape every card-list/settings-list screen in this
	repo and its consumer reach for, and one this file did not already cover:
	every case above is either a HUG scroller measuring its own bar (the
	shelf/list-beside-text cases) or a synthetic Button row, never a `fill`
	scroll host whose direct children are themselves `fill`-width leaves.

	ROOT-CAUSE FINDING: there is no framework defect here. The mechanism this
	whole file exists for — `ctx.scrollBarReserve` narrowing the cross axis
	whenever the scroll axis overflows (`layout/solver.luau`'s `arrange`
	branch for `kind == "scroll"`) — already applies unconditionally to a
	`fill`-width child of ANY scroll host, HUG or FILL-sized, under EITHER
	indicator policy (the 2026-08-12 reversal made the reserve policy-blind on
	purpose: "the engine charges the window for the bar instance however the
	bar is painted"). This file's own header already names why no headless
	sweep saw the class before `scroll_bar_measure.spec` existed — the fake
	target's `scrollBarThickness` is deliberately opt-in per world, not a
	silent default — so the fix this item owes is the same shape as the file
	around it: cover the SHAPE the director's screenshot is, opted in exactly
	like every other case here, so a future regression in this exact card-list
	shape cannot ship unseen. RR lockstep: no Facet API/default/behavior
	changed, so there is nothing for the consumer to migrate (clean-negative —
	`games/RascalRally/code` mounts its own lists through the same public
	`ScrollView`/`Table` surfaces this file already exercises). ]]
describe("item 3: a persistent scrollbar never overlaps a full-width card list", function()
	local CARD_COUNT = 20
	local CARD_H = 60

	local function cardList(UI: any): any
		local cards: { any } = {}
		for i = 1, CARD_COUNT do
			cards[#cards + 1] = UI.corners(
				UI.Box({
					id = "Card" .. i,
					width = UI.fill(),
					height = { type = "fixed", px = CARD_H },
					surface = "raised",
				}),
				"panel"
			)
		end
		return UI.Screen({
			id = "S",
			children = {
				UI.ScrollView({
					id = "List",
					gap = "s",
					width = UI.fill(),
					height = UI.fill(),
					children = cards,
				}),
			},
		})
	end

	-- the REAL reactive path, not a manual short-circuit: presenter
	-- construction runs the scroll-indicator-policy effect once at boot
	-- (src/present/presenter.luau), which is what a live desktop session
	-- actually goes through before its first paint
	local function policyWorld(viewport: { w: number, h: number }, preferredInput: string?): any
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = viewport.w, h = viewport.h })
		if preferredInput ~= nil then
			env:set("preferredInput", preferredInput)
		end
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		adapter.scrollBarThickness = fake_target.SCROLL_BAR_THICKNESS
		local presenter = Facet.newPresenter(core, env, adapter, system)
		local handle = presenter.present(cardList(Facet.UI), {})
		presenter.refresh()
		return { core = core, adapter = adapter, presenter = presenter, handle = handle }
	end

	local function assertNoOverlap(w: any)
		local list = w.handle.controller.rectOf("/S/List")
		expect(list ~= nil).toBe(true)
		-- the reserve a sibling would have to pay (§ "THE GUTTER IS PUBLISHED"
		-- above) — nil when nothing overflowed, which is the honest "at rest"
		-- case: a list with no bar to paint has nothing to leave room for
		local inset = w.handle.controller.scrollBarInsetOf("/S/List")
		local reserve = if type(inset) == "table" and type(inset.right) == "number" then inset.right else 0
		for i = 1, CARD_COUNT do
			local card = w.handle.controller.rectOf(`/S/List/Card{i}`)
			if card ~= nil then
				-- the card's right edge must never reach the reserved gutter —
				-- the exact overlap desktopScroll.png shows
				if card.x + card.w > (list :: any).x + (list :: any).w - reserve + 0.01 then
					error(
						`Card{i}: right edge {card.x + card.w} runs into the {reserve}px scrollbar gutter `
							.. `reserved off list right edge {(list :: any).x + (list :: any).w}`,
						2
					)
				end
			end
		end
		expect(#w.handle.controller.diagnostics()).toBe(0)
	end

	it("desktop/pointer (the default profile — a persistent bar): no card overlaps it, overflowing", function()
		local w = policyWorld({ w = 360, h = 400 }) -- 400/60 < 20 rows: overflows
		assertNoOverlap(w)
		local inset = w.handle.controller.scrollBarInsetOf("/S/List")
		expect(inset ~= nil and inset.right).toBe(fake_target.SCROLL_BAR_THICKNESS)
	end)

	it("desktop/pointer at rest (content fits — nothing to reserve, nothing to overlap)", function()
		local w = policyWorld({ w = 360, h = 4000 })
		assertNoOverlap(w)
		expect(w.handle.controller.scrollBarInsetOf("/S/List")).toBeNil()
	end)

	it(
		"touch/auto profile: ZERO reserve (director ruling 2026-08-28 — persistent holds space, auto overlaps)",
		function()
			local w = policyWorld({ w = 360, h = 400 }, "Touch")
			assertNoOverlap(w)
			-- the reserve publishes NOTHING under auto: a sibling that asked
			-- "how much room did this host take" gets the honest "none" answer,
			-- not the always-policy's 8
			expect(w.handle.controller.scrollBarInsetOf("/S/List")).toBeNil()
			-- and the content itself proves it, not just the published fact: an
			-- auto card is measured `fake_target.SCROLL_BAR_THICKNESS` px WIDER
			-- than the SAME list under "always", because nothing narrowed it
			local alwaysW = policyWorld({ w = 360, h = 400 })
			local autoCard = w.handle.controller.rectOf("/S/List/Card1")
			local alwaysCard = alwaysW.handle.controller.rectOf("/S/List/Card1")
			expect(autoCard ~= nil and alwaysCard ~= nil).toBe(true)
			expect((autoCard :: any).w - (alwaysCard :: any).w).toBe(fake_target.SCROLL_BAR_THICKNESS)
		end
	)
end)

--[[ ── DIRECTOR RULING 2026-08-28, PINNED ACROSS EVERY CONSTRUCTION CLASS ──────

	"we should make sure that if the scrollbar is set to persistently visible, we
	hold space for it, but if it's auto visible, we let it overlap. that should be
	a framework thing that just works with our layouts." Implemented ONCE, at the
	seam that already knows the policy (`screen_scroll_indicators.
	setScrollIndicatorPolicy` feeds `adapter.scrollBarThickness`, which
	`renderer.luau` feeds the solver as `scrollBarReserve` — no parallel
	per-construction copy of the decision) — so this describe proves the SAME
	seam reaches every scroller shape a caller can build from the public API,
	not just the hand-rolled `ScrollView` the block above already covers.

	The "let it overlap" half is NOT "zero reserve, full stop" (that reproduces
	2026-08-09's clip — see `screen_scroll_indicators.luau`'s file header): the
	live adapter widens the FRAME by the bar's thickness under "auto" whenever
	the scroll axis overflows (`applyBarOverlayWiden`), which the fake mirrors as
	its NET OUTCOME (`_deriveWindowRect`: `lost = 0` under "auto"). What a
	headless world can prove is exactly that net outcome — nothing is clipped,
	nothing is reserved — which is what every case below asserts. ]]
describe("director ruling 2026-08-28: persistent holds space, auto lets it overlap — every construction", function()
	local function tableWorld(viewport: { w: number, h: number }, preferredInput: string?): any
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = viewport.w, h = viewport.h })
		if preferredInput ~= nil then
			env:set("preferredInput", preferredInput)
		end
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		adapter.scrollBarThickness = fake_target.SCROLL_BAR_THICKNESS
		local presenter = Facet.newPresenter(core, env, adapter, system)
		-- RascalRally's FacetRacerListScreen shape exactly (task-misc-report.md):
		-- headerless, single `fill` column, overflowing a fixed-height panel
		local ROW_COUNT = 40
		local rows: { any } = {}
		for i = 1, ROW_COUNT do
			rows[i] = { id = "r" .. i, label = "Row " .. i }
		end
		local tbl = Facet.Controls.Table(core, {
			id = "Tbl",
			rows = core:signal(rows),
			key = function(item: any)
				return item.id
			end,
			header = false,
			rowHeight = 28,
			height = { type = "fixed", px = 300 }, -- a fixed panel, overflowing 40 rows
			columns = { { id = "label", width = { type = "fill", weight = 1 } } },
			cellFor = function(_columnId: string, item: any)
				return Facet.UI.Text({ id = "Value", text = item.label })
			end,
		})
		local screen = Facet.UI.Screen({
			id = "S",
			padding = 0,
			gap = 0,
			children = { tbl.blueprint },
		})
		local handle = presenter.present(screen, {})
		presenter.refresh()
		presenter.refresh() -- the body window is taken against a measured height, settled one solve later
		return { core = core, adapter = adapter, presenter = presenter, handle = handle, tbl = tbl }
	end

	it("Table (headerless, RascalRally's racer-list shape): always holds space, auto does not", function()
		local always = tableWorld({ w = 360, h = 400 })
		local auto = tableWorld({ w = 360, h = 400 }, "Touch")
		local bodyPath = "/S/Tbl/Main/Body"
		local alwaysInset = always.handle.controller.scrollBarInsetOf(bodyPath)
		local autoInset = auto.handle.controller.scrollBarInsetOf(bodyPath)
		expect(alwaysInset ~= nil and alwaysInset.right).toBe(fake_target.SCROLL_BAR_THICKNESS)
		expect(autoInset).toBeNil()
		-- a ROW's own solved box proves it too (measured live: `Body` and its
		-- `Rows` grouping node are never themselves narrowed — `Body` reports
		-- the full 360px panel under EITHER policy, exactly like `BodyScroll` in
		-- the All-controls case below; the reserve lands on each ROW's own
		-- `fill`, matching task-misc-report.md's own finding for this exact
		-- headerless shape): under "always" a row is narrowed by exactly the
		-- bar's thickness; under "auto" it gets the FULL panel width.
		local rowPath = bodyPath .. "/Rows/[r1@0]/Row"
		local alwaysRow = always.handle.controller.rectOf(rowPath)
		local autoRow = auto.handle.controller.rectOf(rowPath)
		expect(alwaysRow ~= nil and autoRow ~= nil).toBe(true)
		expect((autoRow :: any).w - (alwaysRow :: any).w).toBe(fake_target.SCROLL_BAR_THICKNESS)
	end)

	--[[ THE ALL-CONTROLS CONSTRUCTION ITSELF — item 3's reopened repro
		(director, 2026-08-28: "the missing repro supplied... showcase 'ALL
		CONTROLS' boot view, DESKTOP with Roblox IN A WINDOW"). Mounted exactly
		as `examples/gallery/client/init.client.luau`'s `mountDemo` does for a
		`kind == "fixture"` scenario (the same minimal ctx `tests/
		examples_gallery.spec.luau`'s `mountFixture` already uses), at a
		WINDOWED-not-fullscreen desktop viewport — the differentiator the prior
		two rounds' fullscreen-only tests never exercised. This is the proof
		case the director named: persistent (the desktop/pointer default) STILL
		reserves on this exact construction; auto does not. ]]
	local adaptive_controls = require("../examples/gallery/scenarios/adaptive_controls") :: any
	local WINDOWED_DESKTOP = { w = 1200, h = 800 } -- windowed, not fullscreen (measured live at 1366x768 too)

	local function allControlsWorld(viewport: { w: number, h: number }, preferredInput: string?): any
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = viewport.w, h = viewport.h })
		if preferredInput ~= nil then
			env:set("preferredInput", preferredInput)
		end
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		adapter.scrollBarThickness = fake_target.SCROLL_BAR_THICKNESS
		local presenter = Facet.newPresenter(core, env, adapter, system)
		local built = adaptive_controls.build({ Facet = Facet, core = core, env = env })
		local handle = presenter.present(built.screen, {})
		presenter.refresh()
		presenter.refresh()
		presenter.refresh()
		return { core = core, adapter = adapter, presenter = presenter, handle = handle, built = built }
	end

	it("the All-controls scenario, windowed desktop: persistent (pointer default) holds space", function()
		local w = allControlsWorld(WINDOWED_DESKTOP)
		local inset = w.handle.controller.scrollBarInsetOf("/AdaptiveScreen/BodyScroll")
		expect(inset ~= nil and inset.right).toBe(fake_target.SCROLL_BAR_THICKNESS)
		expect(#w.handle.controller.diagnostics()).toBe(0)
		w.built.dispose()
	end)

	it("the All-controls scenario, windowed desktop: auto lets it overlap (zero reserve)", function()
		local w = allControlsWorld(WINDOWED_DESKTOP, "Touch")
		expect(w.handle.controller.scrollBarInsetOf("/AdaptiveScreen/BodyScroll")).toBeNil()
		expect(#w.handle.controller.diagnostics()).toBe(0)
		local always = allControlsWorld(WINDOWED_DESKTOP)
		local autoBody = w.handle.controller.rectOf("/AdaptiveScreen/BodyScroll/Body")
		local alwaysBody = always.handle.controller.rectOf("/AdaptiveScreen/BodyScroll/Body")
		expect(autoBody ~= nil and alwaysBody ~= nil).toBe(true)
		expect((autoBody :: any).w - (alwaysBody :: any).w).toBe(fake_target.SCROLL_BAR_THICKNESS)
		w.built.dispose()
		always.built.dispose()
	end)
end)

--[[ ── RED-TEAM finding 1 (fix round 1): THE WIDEN MUST LAND ON THE SAME PAINT
	IT WAS COMPUTED FOR ────────────────────────────────────────────────────────

	Every case above measures the SETTLED geometry, after `presenter.refresh()`
	has run once or more — which is exactly what the RED-TEAM review found could
	mask a one-commit-late write: `render/renderer.luau`'s `solveAndApply` used to
	call `rectPass.apply` (paints Size, reading `handle.barOverlayWidenW/H`)
	BEFORE `commitWalks.scrollRegions` (computes and writes that same field for
	THIS solve). A host newly overflowing under "auto" therefore painted with the
	PREVIOUS solve's widen — nil on a fresh mount — and the field is a bare,
	non-reactive handle write with no settle-phase feedback to correct it later
	(unlike `table.luau`'s `bodyBarInset`, which rides a `core:signal` through the
	renderer's settle phase for exactly this "derived from this solve's own
	rects, must land before paint" hazard). A host nothing else ever re-solves
	stays clipped indefinitely — the 2026-08-09 defect this whole file exists to
	keep fixed.

	`tests/lib/fake_target.luau`'s `_deriveWindowRect` could not see this: it
	recomputes `windowRect` FRESH every call from whatever is current, which is
	structurally incapable of representing a stale read. The mirror added
	alongside this spec (`handle.appliedRectW/H`, snapshotted inside `setRect`
	exactly where the live `applyRect` reads the field; `handle.barOverlayWidenW/H`,
	written inside `setScrollRegion` exactly where the live `applyBarOverlayWiden`
	writes it) makes the ORDER observable without needing the live, engine-coupled
	adapter — this is real `render/renderer.luau`/`rect_pass.luau`/`commit_walks.luau`
	code driving a mirrored adapter, the same relationship every other case in this
	file already has to the live `screen_target.luau`.

	A SINGLE `presenter.present()` call, nothing else: no `presenter.refresh()`,
	and plain `Box` rows with no text at all, so the text-measurement round
	(`renderer.luau`'s `adapter.measureTextWidths` branch) never fires and cannot
	sneak in a confounding second solve that would re-touch this node's rect and
	paper over the hazard by chance — the exact confound the review named in the
	report's own multi-refresh helpers above. `ops()` below proves it stayed one. ]]
describe("fix round 1 (RED-TEAM finding 1): the widen lands on the SAME paint that computes it", function()
	local ROW_H = 40
	local ROW_COUNT = 6 -- 240px of content in a 100px box: overflows on the FIRST solve

	local function firstPaintWorld(preferredInput: string?): any
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 360, h = 691 })
		if preferredInput ~= nil then
			env:set("preferredInput", preferredInput)
		end
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		adapter.scrollBarThickness = fake_target.SCROLL_BAR_THICKNESS
		local presenter = Facet.newPresenter(core, env, adapter, system)
		local UI = Facet.UI
		local rows: { any } = {}
		for i = 1, ROW_COUNT do
			rows[i] = UI.Box({
				id = "R" .. i,
				width = UI.fill(),
				height = { type = "fixed", px = ROW_H },
				surface = "raised",
			})
		end
		local handle = presenter.present(
			UI.Screen({
				id = "S",
				padding = 0,
				children = {
					UI.ScrollView({
						id = "List",
						width = UI.fill(),
						height = { type = "fixed", px = 100 },
						children = rows,
					}),
				},
			}),
			{}
		)
		return { core = core, adapter = adapter, presenter = presenter, handle = handle }
	end

	it("an already-overflowing 'auto' host gets the widen on its FIRST setRect call, not a later one", function()
		local w = firstPaintWorld("Touch")
		local node = (w.adapter :: any).node("/S/List")
		expect(node ~= nil).toBe(true)
		local rectCalls, regionCalls = 0, 0
		for _, op in (w.adapter :: any).ops() do
			if string.match(op, "^rect /S/List ") ~= nil then
				rectCalls += 1
			elseif string.match(op, "^scrollregion /S/List ") ~= nil then
				regionCalls += 1
			end
		end
		-- exactly one paint: the ordering hazard cannot survive a second
		-- `setRect`/`setScrollRegion` round papering over it
		expect(rectCalls).toBe(1)
		expect(regionCalls).toBe(1)
		-- THE ASSERTION: the Size actually applied on that ONE `setRect` call
		-- already includes the widen. Before the `renderer.luau` reorder fix
		-- (task SCROLL2 fix round 1), this read a stale nil widen — RED.
		expect((node :: any).appliedRectW).toBe((node :: any).rect.w + fake_target.SCROLL_BAR_THICKNESS)
		expect(#w.handle.controller.diagnostics()).toBe(0)
		expect(w.core:lastError()).toBeNil()
	end)

	it("...and under 'always' policy the same first solve applies no widen at all (sanity control)", function()
		local w = firstPaintWorld(nil)
		local node = (w.adapter :: any).node("/S/List")
		expect(node ~= nil).toBe(true)
		expect((node :: any).appliedRectW).toBe((node :: any).rect.w)
		expect(w.core:lastError()).toBeNil()
	end)
end)
