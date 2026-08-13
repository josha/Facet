--!strict
--[[
	`containerRelative` UNDER INCREMENTAL LAYOUT — RED-TEAM Milestone 1, HIGH 3.

	§2.5 widened the MEASURE MEMO's cache key so a `containerRelative` dimension
	could not be served an answer measured against a different container
	(`rebuildScopeKey`, and the last describe of `container_relative_frame.spec`).
	It did not widen the ARRANGE REUSE SKIP, which is the shipped default
	(`incrementalEnabled = opts == nil or opts.incrementalLayout ~= false`).

	THE SKIP'S ARGUMENT IS "nothing inside this subtree is dirty and it is landing
	on the rect it already had, so every descendant's geometry is the answer it
	already gave." That argument is sound for every dimension the solver had
	BEFORE this round, because each of them is a function of the parent's offer,
	which the rect carries. It is unsound for `containerRelative`, whose size is a
	function of the nearest scroll VIEWPORT — a fact the ancestor's rect does not
	mention at all.

	Measured on the fixture below (a y-scroller whose 8px bar reserve flips on as
	a sibling grows past the viewport; `Bar` is `containerRelativeFrame(horizontal,
	0.5)` inside a fixed-width wrapper whose own rect never moves):

	    incremental = false: 200 -> 196 -> 200   (correct — the full-solve oracle)
	    incremental = true : 200 -> 200 -> 200   (stale, 4px wider than the
	                                              container allows)

	THE FIX. `renderer.toLayoutNode` marks every subtree that CONTAINS a
	`containerRelative` dimension (`containerRelativeInside`, the same build-time
	shape `inertPlacement`/`placementProps` already use), `arrange` records the
	container it resolved each such subtree against, and the skip is refused when
	the enclosing container differs from the recorded one. The mark stops at a
	`scroll` node, because a scroller re-establishes the container for everything
	below it out of its own replayed rect — so a `containerRelative` node under an
	inner scroller genuinely is insulated from the enclosing one.

	EVERY CASE HERE IS A DIFFERENTIAL against the same scenario solved with
	`incrementalLayout = false`, for the reason `incremental_layout.spec` states at
	length: the only claim worth testing is that the answer is identical.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local customFactory = require("../src/core/custom")
local fake_target = require("./lib/fake_target")

local VIEWPORT = { w = 400, h = 300 }
local RESERVE = 8

local function px(n: number)
	return { type = "fixed", px = n }
end
local function crf(spec: { [string]: any }): any
	local d: any = { type = "containerRelative" }
	for k, v in spec do
		d[k] = v
	end
	return d
end

-- THE FIXTURE.
--
--   ScrollView Scroll (axis y, the container)
--     VStack  Static — no `containerRelative` anywhere inside it. The CONTROL:
--       Box   Inner    it must go on being skipped across the same change.
--     VStack  Wrap   — FIXED width 300, so its own rect is { 0, 40, 300, 40 }
--       Box   Bar      no matter what happens below it.
--                      `Bar` is containerRelativeFrame(horizontal, 0.5).
--     Box     Grow   — height bound to `big`. Flipping it takes the content past
--                      the 300px viewport, the 8px bar is reserved off the CROSS
--                      axis, and the container narrows 400 -> 392.
--
-- `Grow` is the ONLY dirty node. `Static` and `Wrap` are both clean and both land
-- on the rects they already had — so the rect check clears both, and only the
-- container check can tell them apart. `Bar` is the one node in the tree whose
-- correct answer changed.
local function world(incremental: boolean)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = VIEWPORT.w, h = VIEWPORT.h })
	local big = core:signal(false)
	local growHeight = core:memo(function(use: any)
		return px(if use(big) then 900 else 40)
	end)
	local bp = UI.ScrollView({
		id = "Scroll",
		axis = "y",
		padding = 0,
		gap = 0,
		width = { type = "fill", weight = 1 },
		height = { type = "fill", weight = 1 },
		children = {
			UI.VStack({
				id = "Static",
				padding = 0,
				gap = 0,
				width = px(300),
				height = px(40),
				children = { UI.Box({ id = "Inner", width = px(100), height = px(20) }) },
			}),
			UI.VStack({
				id = "Wrap",
				padding = 0,
				gap = 0,
				width = px(300),
				height = px(40),
				children = {
					UI.Box({ id = "Bar", width = crf({ fraction = 0.5 }), height = px(20) }),
				},
			}),
			UI.Box({ id = "Grow", width = px(100), height = growHeight }),
		},
	})
	local root = mountLib.mount(core, bp)
	local adapter = fake_target.new()
	-- the reserve is the ADAPTER's fact (renderer.luau reads
	-- `adapter.scrollBarThickness`), not an attach option
	adapter.scrollBarThickness = RESERVE
	local controller = renderer.attach(core, root, env, adapter, {
		rootPolicy = "edgeToEdge",
		incrementalLayout = incremental,
	})
	controller.initialRender()
	return { core = core, controller = controller, adapter = adapter, big = big }
end

local function barWidth(w: any): number
	return w.adapter.node("/Scroll/Wrap/Bar").rect.w
end
local function wrapRect(w: any): any
	return w.adapter.node("/Scroll/Wrap").rect
end

describe("containerRelative is re-resolved when the container moves under it (HIGH 3)", function()
	it("the bar narrows when the scrollbar reserve arms, and widens when it disarms", function()
		local w = world(true)
		-- the container is the scroll viewport: 400 wide, no bar yet
		expect(barWidth(w)).toBe(200)

		w.big:set(true)
		w.controller.refresh()
		-- THE PRECONDITIONS, asserted so a fixture that stops exercising the skip
		-- cannot quietly go on passing:
		--   1. the reuse path engaged at all
		expect(w.controller.stats().lastSkipped > 0).toBe(true)
		--   2. `Wrap`'s own rect really is unchanged — which is what made the skip
		--      look safe, and what the rect check alone can never catch
		expect(wrapRect(w).x).toBe(0)
		expect(wrapRect(w).y).toBe(40)
		expect(wrapRect(w).w).toBe(300)
		expect(wrapRect(w).h).toBe(40)
		-- ...and the answer. Pre-fix: 200, four pixels wider than the container
		-- allows, forever.
		expect(barWidth(w)).toBe(196)

		w.big:set(false)
		w.controller.refresh()
		expect(barWidth(w)).toBe(200)
	end)

	it("matches the full-solve oracle at every step of a long flip sequence", function()
		local inc = world(true)
		local full = world(false)
		local steps = { true, false, true, true, false, true, false, false }
		expect(barWidth(inc)).toBe(barWidth(full))
		for _, v in steps do
			for _, w in { inc, full } do
				w.big:set(v)
				w.controller.refresh()
			end
			expect(barWidth(inc)).toBe(barWidth(full))
			-- the oracle is only an oracle if it is actually moving
			expect(barWidth(full)).toBe(if v then 196 else 200)
		end
	end)

	it("the incremental solve still SKIPS — the fix refuses one subtree, not the feature", function()
		-- the cost side. A fix that simply disabled the reuse path would pass both
		-- cases above and hand back every gain incremental layout exists for, so
		-- the skip must still be doing real work on the very solve that refuses
		-- `Wrap`: `Static`/`Inner` are clean, unmarked and unmoved, and they must
		-- still be replayed.
		local w = world(true)
		w.big:set(true)
		w.controller.refresh()
		expect(barWidth(w)).toBe(196)
		expect(w.controller.stats().lastSkipped).toBe(2) -- Static + Inner
		-- ...and the refusal is not sticky. The container is now settled at 392, so
		-- the next container-preserving change puts `Wrap` back in play.
		w.big:set(true) -- same value: a re-solve with nothing dirty at all
		w.controller.refresh()
		expect(w.controller.stats().lastSkipped >= 2).toBe(true)
		expect(barWidth(w)).toBe(196)
	end)

	it("the refusal is SCOPED to the marked subtree — an unmarked twin still skips it", function()
		-- the negative control for the MARK, and the case that separates the real
		-- fix from "turn the skip off whenever a scrollbar appears". Two trees,
		-- identical node for node, differing in ONE dimension: `Bar`'s width is
		-- `containerRelative` in one and `fixed` in the other. The same container
		-- change is driven through both. The marked tree must skip exactly two
		-- nodes fewer — `Wrap` and `Bar`, the refused subtree — and no others.
		local function twin(relative: boolean)
			local core = customFactory.new()
			local env = environment.new(core)
			env:set("viewportRect", { x = 0, y = 0, w = VIEWPORT.w, h = VIEWPORT.h })
			local big = core:signal(false)
			local growHeight = core:memo(function(use: any)
				return px(if use(big) then 900 else 40)
			end)
			local root = mountLib.mount(
				core,
				UI.ScrollView({
					id = "Scroll",
					axis = "y",
					padding = 0,
					gap = 0,
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.VStack({
							id = "Static",
							padding = 0,
							gap = 0,
							width = px(300),
							height = px(40),
							children = { UI.Box({ id = "Inner", width = px(100), height = px(20) }) },
						}),
						UI.VStack({
							id = "Wrap",
							padding = 0,
							gap = 0,
							width = px(300),
							height = px(40),
							children = {
								UI.Box({
									id = "Bar",
									width = if relative then crf({ fraction = 0.5 }) else px(200),
									height = px(20),
								}),
							},
						}),
						UI.Box({ id = "Grow", width = px(100), height = growHeight }),
					},
				})
			)
			local adapter = fake_target.new()
			adapter.scrollBarThickness = RESERVE
			local controller = renderer.attach(core, root, env, adapter, {
				rootPolicy = "edgeToEdge",
				incrementalLayout = true,
			})
			controller.initialRender()
			big:set(true)
			controller.refresh()
			return controller, adapter
		end
		local marked = twin(true)
		local plain, plainAdapter = twin(false)
		-- the unmarked twin's bar is a plain fixed 200 and stays there...
		expect(plainAdapter.node("/Scroll/Wrap/Bar").rect.w).toBe(200)
		-- ...it skipped its `Static`/`Inner` control AND its `Wrap`/`Bar`...
		expect(plain.stats().lastSkipped).toBe(4)
		-- ...and the marked tree paid for exactly the two refused nodes, no more:
		-- `Static`/`Inner` are untouched by the refusal.
		expect(marked.stats().lastSkipped).toBe(2)
	end)

	it("an INNER scroller insulates what is below it — the mark stops there", function()
		-- the claim the `kind ~= \"scroll\"` clause in the mark rests on, tested as a
		-- differential and as a cost. `Bar` sits inside its OWN scroller, so its
		-- ruler is that scroller's inner size — derived from that scroller's rect,
		-- which the replay reproduces exactly. The OUTER container narrowing is
		-- therefore none of its business, `Wrap` must stay unmarked, and its whole
		-- three-node subtree must keep skipping.
		local function build(incremental: boolean)
			local core = customFactory.new()
			local env = environment.new(core)
			env:set("viewportRect", { x = 0, y = 0, w = VIEWPORT.w, h = VIEWPORT.h })
			local big = core:signal(false)
			local growHeight = core:memo(function(use: any)
				return px(if use(big) then 900 else 40)
			end)
			local root = mountLib.mount(
				core,
				UI.ScrollView({
					id = "Outer",
					axis = "y",
					padding = 0,
					gap = 0,
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.VStack({
							id = "Wrap",
							padding = 0,
							gap = 0,
							width = px(300),
							height = px(100),
							children = {
								UI.ScrollView({
									id = "In",
									axis = "y",
									padding = 0,
									gap = 0,
									width = px(200),
									height = px(100),
									children = {
										UI.Box({ id = "Bar", width = crf({ fraction = 0.5 }), height = px(20) }),
									},
								}),
							},
						}),
						UI.Box({ id = "Grow", width = px(100), height = growHeight }),
					},
				})
			)
			local adapter = fake_target.new()
			adapter.scrollBarThickness = RESERVE
			local controller = renderer.attach(core, root, env, adapter, {
				rootPolicy = "edgeToEdge",
				incrementalLayout = incremental,
			})
			controller.initialRender()
			return controller, adapter, big
		end
		local inc, incAdapter, incBig = build(true)
		local full, fullAdapter, fullBig = build(false)
		-- half of the INNER scroller's 200px viewport, and the outer reserve never
		-- reaches it
		expect(incAdapter.node("/Outer/Wrap/In/Bar").rect.w).toBe(100)
		incBig:set(true)
		inc.refresh()
		fullBig:set(true)
		full.refresh()
		expect(incAdapter.node("/Outer/Wrap/In/Bar").rect.w).toBe(fullAdapter.node("/Outer/Wrap/In/Bar").rect.w)
		expect(incAdapter.node("/Outer/Wrap/In/Bar").rect.w).toBe(100)
		-- ...and the COST: `Wrap`, `In` and `Bar` were all replayed. Propagating the
		-- mark through the inner scroller drops this to 0.
		expect(inc.stats().lastSkipped).toBe(3)
	end)
end)
