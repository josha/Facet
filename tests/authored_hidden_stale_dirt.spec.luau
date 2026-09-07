--!strict
--[[ ── AN AUTHORED `hidden` WRITTEN INSIDE A SOLVE IS SWALLOWED (stabilization B4-R) ──

	THE DEFECT, picker-free. A node whose `hidden` is bound flips it from inside a
	`controller.onSolved` listener — which is where every `syncGeometry` in this
	framework runs, because `present/presenter.luau` feeds solved geometry from
	inside the solve — together with a layout-class geometry write. The geometry
	write LANDS. The hide/show does not, and no number of further refreshes
	recovers it: the adapter keeps the stale verdict until unrelated dirt happens
	to force another solve.

	WHY THE TWO DIFFER, which is the whole of it. `width` reaches the commit
	through the TREE: `mount`'s bound-prop observer writes `node.props.width` and
	THEN pushes the dirty entry, so the feedback re-solve that follows the listener
	reads the new value off the node and commits the rect it produces. `hidden`
	does not. It reaches the commit through the renderer's OWN `authoredHidden`
	cache (`src/render/renderer.luau`, `local authoredHidden` —
	`commit_walks.harvest` reads it to build `hiddenRoots`, which
	`commit_walks.visible` paints from), and that cache is refreshed in exactly one
	place: while draining the dirty queue in `refresh`, on the NEXT frame.

	So the ordering is:

	  1. the listener writes `hidden` during the solve; the entry is queued;
	  2. `notifySolved` sees `dirtySeq` move and calls `resolveForFeedback`, a
	     FULL solve, which stamps `fullSolveSeq` ABOVE that entry — and commits
	     the visibility walk from the PRE-write `authoredHidden`;
	  3. the next `refresh` takes the queue, computes
	     `layoutDirtIsStale = root.dirtySeq() <= fullSolveSeq` — true — and so
	     never sets `needsSolve` for the arrange-classed `hidden` entry;
	  4. the drain refreshes `authoredHidden` correctly... and no walk runs, ever.

	`fullSolveSeq`'s claim is "a full solve read the props of everything dirtied up
	to here". That is true for every prop the SOLVER reads off the tree. It is
	false for a prop whose only route to the adapter is a cache refreshed strictly
	AFTER the solve that stamped the mark, and the fix is at the drain: a re-read
	that actually MOVES the cached value forces the solve that owes it a walk.

	THE PIN IS THE OUTLIER PAIR, not the visibility alone. The first case writes
	`width` and `hidden` in the same instant from the same listener and asserts
	both, because "the write was too late" is the obvious wrong diagnosis and the
	landed `width` is what rules it out.

	AND A STALE-DIRT FRAME MUST STILL NOT BUY A SOLVE. Forcing one on a moved
	authored hide must not force one where nothing moved — that is `fullSolveSeq`'s
	whole reason for existing (owed row O-20). The two solve-count cases are that
	guard: an idle frame, and the drain of a `hidden` entry that was written inside
	a solve and ended up back at the value the cache already holds. Both read ZERO
	before this fix and after it.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src")
local UI = Facet.UI
local worldLib = require("./lib/world")

local BAR = "/S/P/Bar"
local OTHER = "/S/P/Other"

local function px(n: number): any
	return { type = "fixed", px = n }
end

--[[ THE FIXTURE. `shown` starts false so the Bar is authored HIDDEN at mount —
	the sliding pill's own starting state, and the only one where the flip is
	observable. `w.flip()` dirties something the pair does not touch, so a solve
	runs at all; the listener registered below is what does the writing, from
	inside it. ]]
local function mountCase(): any
	local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 844 } })
	local shown = w.core:signal(false)
	local barW = w.core:signal(px(40))
	local otherW = w.core:signal(px(10))
	local hiddenMemo = w.core:memo(function(use: any)
		return not use(shown)
	end)
	w.present(UI.Screen({
		id = "S",
		children = {
			UI.VStack({
				id = "P",
				children = {
					UI.Box({ id = "Bar", hidden = hiddenMemo :: any, width = barW :: any, height = px(20) }),
					UI.Box({ id = "Other", width = otherW :: any, height = px(10) }),
				},
			}),
		},
	}))

	local fired = 0
	--[[ ONE listener, registered after the presenter's own, exactly as a control's
		`syncGeometry` is. It writes BOTH props in the same instant — the one the
		solver reads off the tree, and the one only the renderer's cache carries. ]]
	w.controller.onSolved(function()
		if fired >= 1 then
			return
		end
		fired += 1
		barW:set(px(60))
		shown:set(true)
	end)

	--[[ THE DRIVE: one refresh whose solve is the window the listener writes in.
		The entry it queues is drained by the NEXT refresh, which is the one that
		can act on it — the ordering the cases below assert rather than paper
		over. ]]
	w.drive = function()
		otherW:set(px(11))
		w.pres.refresh()
	end
	w.otherW = otherW
	w.shown = shown
	return w
end

describe("B4-R: an authored `hidden` flipped inside a solve reaches the adapter", function()
	it("the geometry lands in the same refresh, the hide in the one after — and it STAYS", function()
		local w = mountCase()
		expect(w.adapter.visibleOf(BAR)).toBe(false)
		w.drive()
		-- the layout prop written in the SAME instant: the solver read it off the
		-- tree, so it lands in the very refresh that carried it. It is the control.
		expect(`width landed: {w.adapter.node(BAR).rect.w}`).toBe("width landed: 60")
		-- ...and `hidden` cannot, by construction: its entry is still in the queue
		-- the solve that just ran deliberately does not consume.
		expect(`visible on the carrying refresh: {tostring(w.adapter.visibleOf(BAR))}`).toBe(
			"visible on the carrying refresh: false"
		)
		-- THE FIX: the refresh that drains that entry re-reads the tree, sees the
		-- value MOVED, and solves — so the visibility walk finally runs. Before
		-- B4-R this stayed false forever.
		w.pres.refresh()
		expect(`visible on the next refresh: {tostring(w.adapter.visibleOf(BAR))}`).toBe(
			"visible on the next refresh: true"
		)
	end)

	it("the reverse flip lands too — this is a cache that tracks, not a one-way unhide", function()
		local w = mountCase()
		w.drive()
		w.pres.refresh()
		expect(w.adapter.visibleOf(BAR)).toBe(true)
		-- hide it again from OUTSIDE a solve (the ordinary path: the dirt is above
		-- the mark, so the frame solves on its own and lands it immediately)
		w.shown:set(false)
		w.pres.refresh()
		expect(`hidden again: {tostring(w.adapter.visibleOf(BAR))}`).toBe("hidden again: false")
		-- ...and from INSIDE one, which is the path that used to swallow it
		local fired = 0
		w.controller.onSolved(function()
			if fired >= 1 then
				return
			end
			fired += 1
			w.shown:set(true)
		end)
		w.otherW:set(px(12))
		w.pres.refresh()
		w.pres.refresh()
		expect(`shown again from inside a solve: {tostring(w.adapter.visibleOf(BAR))}`).toBe(
			"shown again from inside a solve: true"
		)
	end)

	it("ten more refreshes neither need to run nor undo it", function()
		local w = mountCase()
		w.drive()
		for _ = 1, 10 do
			w.pres.refresh()
		end
		expect(w.adapter.visibleOf(BAR)).toBe(true)
		expect(w.adapter.visibleOf(OTHER)).toBe(true)
	end)

	--[[ THE COST GUARD, half one: `fullSolveSeq` exists so a settle-phase solve's
		dirt does not buy a second full solve every frame. An idle frame — measured
		from AFTER the repair frame, which is the fix's one and only extra solve —
		is the baseline it protects. ]]
	it("an idle refresh still solves exactly as often as it did — zero", function()
		local w = mountCase()
		w.drive()
		w.pres.refresh() -- the repair frame: one solve, and only one
		local before = w.controller.stats().solves
		for _ = 1, 5 do
			w.pres.refresh()
		end
		expect(`idle solves: {w.controller.stats().solves - before}`).toBe("idle solves: 0")
	end)

	--[[ ...AND HALF TWO, which is the half the fix could actually break: a `hidden`
		entry drained under a STALE mark whose re-read value is the one the cache
		already holds. The listener toggles `shown` and puts it straight back, so the
		prop is pushed dirty (the drive solves TWICE — the feedback re-solve is the
		proof that `dirtySeq` moved) and the value the drain re-reads has not. ]]
	it("...and a `hidden` entry whose re-read value did not move buys no solve either", function()
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 844 } })
		local shown = w.core:signal(false)
		local hiddenMemo = w.core:memo(function(use: any)
			return not use(shown)
		end)
		local otherW = w.core:signal(px(10))
		w.present(UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					id = "P",
					children = {
						UI.Box({ id = "Bar", hidden = hiddenMemo :: any, width = px(40), height = px(20) }),
						UI.Box({ id = "Other", width = otherW :: any, height = px(10) }),
					},
				}),
			},
		}))
		local fired = 0
		w.controller.onSolved(function()
			if fired >= 1 then
				return
			end
			fired += 1
			shown:set(true)
			shown:set(false)
		end)
		local before = w.controller.stats().solves
		otherW:set(px(11))
		w.pres.refresh()
		-- the drive solved twice: once for `otherW`, once for the feedback round the
		-- listener's own writes armed. That second solve is what proves the `hidden`
		-- entry really is in the queue the next refresh drains.
		expect(`drive solves: {w.controller.stats().solves - before}`).toBe("drive solves: 2")
		local mid = w.controller.stats().solves
		w.pres.refresh()
		expect(`no-op hide solves: {w.controller.stats().solves - mid}`).toBe("no-op hide solves: 0")
		expect(w.adapter.visibleOf(BAR)).toBe(false)
	end)
end)
