--!strict
--[[ ── EVERY PATH THROUGH `createOptsFor` DECIDES THE FIELD (RED-TEAM C-10) ──────

	`render/instance_boundary.createOptsFor` answers two callers that are not ordered
	with respect to each other — `renderer.ensureTree` when it chooses the engine
	object, and `render/layout_node` when it builds the solver's node — and the
	memoised `node.hostSpace` is what makes them agree. Its own comment says so:
	"`false` IS A MEMOISED ANSWER, not an absent one, and writing it is the point ...
	This function is the ONLY writer of the field for that reason."

	THE EARLY RETURNS WERE NOT DOING IT. `props.opacity ~= nil` returns
	`{ canvasGroup = true }` ABOVE the memo block, and `opacity` is REACTIVE —
	`mount.luau` rewrites `node.props[propName]` on every signal fire. So a container
	whose author signal yields a number and later `nil` was a non-host on its first ask
	and a coordinate-space candidate on its second, and the solver would then store its
	subtree relative to a parent the adapter never made. D6a is what made the
	fall-through population large: before it, only reactive-placement containers
	reached the memo; after it, every 2+-child `ForEach` row in a stack does, i.e.
	every list row an author fades.

	A COUNTER AND AN ORACLE, and they are NOT the same claim — stated apart because the
	fake target cannot model half of the consequence:

	  * `instance_boundary.decisions()` counts asks that found the field UNDECIDED. On
	    a settled tree it stops moving. A branch that returns without deciding makes it
	    climb, and each of those asks is a window in which the two callers can answer
	    differently. THIS IS THE PIN: mutation M1 (the `opacity` branch stops deciding)
	    reads `decided=1` against 0.
	  * the composed rect of a child under the faded row, against the same child in an
	    identical row that never carried an `opacity`. THIS IS THE ORACLE, not a second
	    pin: it says the memo's answer and the tree agree, and it holds under M1 too,
	    because `fake_target.registerFakeHost` ACCUMULATES the space flag
	    (`existing.hostSpace = existing.hostSpace or hostSpace`) and so quietly repairs
	    the divergence a live adapter would not — the engine object's class is chosen
	    once, at create. Recorded as a null rather than claimed as coverage.

	AND THE DRIVE NEEDS A WHOLE-TREE REBUILD, which is why the report could only rate
	this speculative: `opacity` is PAINT-classed, so moving it does not rebuild a layout
	node and the second asker is never called. A viewport change does.

	THE OTHER TWO EARLY RETURNS ARE BELT AND ARE RECORDED AS SUCH: mutations M2
	(`scale`/`rotation`) and M3 (`ScrollView`/`clipChildren`) redden nothing here. This
	fixture has no container of either shape at the row-host trigger, and neither prop
	is one a signal moves the way `opacity` is — they are decided for the same reason
	the memo block gives ("every path through this function answers the memo") rather
	than because a producer exists.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src")
local UI = Facet.UI
local worldLib = require("./lib/world")
local instance_boundary = require("../src/render/instance_boundary")

local ROWS = 40
-- the row that fades. Its neighbours are byte-identical apart from the prop, which is
-- what makes the rect comparison below a controlled one.
local FADE_ROW = 3

local function px(n: number): any
	return { type = "fixed", px = n }
end

local function makeWorld(): any
	local w = worldLib.new({
		viewport = { x = 0, y = 0, w = 600, h = 500 },
		overflowGuardOff = "a 40-row list of 30px rows is taller than a 500px viewport on purpose: this "
			.. "fixture measures the coordinate-space memo, not containment",
	})
	local core = w.core
	local fade = core:signal(0.5)
	local items = {}
	for i = 1, ROWS do
		items[i] = { id = `k{i}`, n = i, fade = i == FADE_ROW }
	end
	local rows = core:signal(items)
	w.present(UI.Screen({
		id = "S",
		children = {
			UI.VStack({
				id = "List",
				padding = 0,
				gap = 1,
				children = {
					UI.ForEach({
						id = "Rows",
						items = rows,
						key = function(item: any)
							return item.id
						end,
						--[[ THE ITEM ROOT CARRIES THE `opacity`, and it has to: `mount.markRow`
							stamps `inStack` on item roots only, so the row-host trigger asks about
							THIS node and no other. Two children, a stack parent — the D6a shape —
							plus the one reactive prop that returns above the memo.

							A `ZStack` BECAUSE `opacity` IS REFUSED ANYWHERE ELSE: a fade is
							`CanvasGroup.GroupTransparency` and only `UI.Box` and `UI.ZStack` can BE
							one (`blueprint_schema`'s own message says so). `ROW_HOST` carries
							`ZStack` for an unrelated reason — Facet's `Table` builds its rows as
							one — so the two triggers meet on exactly the class the framework's own
							list control already uses, which is what makes this the shipped shape
							rather than a contrived one. EVERY row is a `ZStack`, so the rect
							comparison below differs in the prop and in nothing else. ]]
						row = function(item: any)
							return UI.ZStack({
								id = "Row",
								padding = 0,
								height = px(30),
								opacity = if item.fade then fade else nil,
								children = {
									UI.Text({ id = "Name", textSize = 12, text = `row{item.n}` }),
									UI.Box({ id = "Bar", width = px(40), height = px(6) }),
								},
							})
						end,
					}),
				},
			}),
		},
	}))
	w.fade = fade
	return w
end

local FADE_ROW_PATH = `/S/List/Rows/[k{FADE_ROW}]/Row`
local PLAIN_ROW_PATH = `/S/List/Rows/[k{FADE_ROW + 1}]/Row`

describe("RED-TEAM C-10: the coordinate-space verdict is decided once, on every path", function()
	it("THE COUNTER: a settled tree stops deciding, and the faded row is not a space", function()
		--[[ THE MEMO INSTRUMENT. The first build decides every container once; every
			later ask reads the field back. A branch that returns before the write makes
			this climb on every solve that rebuilds that node — which is exactly the
			window in which the two callers can answer differently.

			The flips are the drive the defect needs: `opacity` going number -> nil -> number
			is a container that WOULD have fallen through to the row-host trigger on the
			middle one. `decided=0` across all three says it never re-asked. ]]
		local w = makeWorld()
		local before = instance_boundary.decisions()
		--[[ THE FLIP, AND THEN A WHOLE-TREE REBUILD, which is the half the drive needs.
			`opacity` is PAINT-classed, so moving it alone does not rebuild a layout node
			and `layout_node.hostSpaceOf` is never re-asked — which is why the report
			could only rate this speculative. A VIEWPORT change does rebuild every node,
			so the second asker meets the container with the prop already gone: a fresh
			`createOptsFor` on a node the adapter created as a `CanvasGroup` at mount. ]]
		w.fade:set(nil)
		w.env:set("viewportRect", { x = 0, y = 0, w = 601, h = 500 })
		w.pres.refresh()
		w.fade:set(0.25)
		w.env:set("viewportRect", { x = 0, y = 0, w = 602, h = 500 })
		w.pres.refresh()
		w.fade:set(nil)
		w.env:set("viewportRect", { x = 0, y = 0, w = 603, h = 500 })
		w.pres.refresh()
		expect(`decided={instance_boundary.decisions() - before}`).toBe("decided=0")
		--[[ ...AND THE ANSWER IS THE FIRST ONE. The row was created as a `CanvasGroup`
			and it stays a non-space for its life, whatever the signal does afterwards —
			which is what keeps the adapter and the solver describing the same tree. Its
			plain neighbour IS a space, so this is the memo refusing rather than the
			trigger being off.

			`false` RATHER THAN `nil` ON THE FADED ROW: a `CanvasGroup` is a real parent,
			so the fake registers it as a host — with the coordinate-space flag OFF, which
			is the distinction `hostSpaceAt` exists to make and the one a bare `isHost`
			could not. ]]
		expect(
			`faded={tostring(w.adapter.hostSpaceAt(FADE_ROW_PATH))} plain={tostring(
				w.adapter.hostSpaceAt(PLAIN_ROW_PATH)
			)}`
		).toBe("faded=false plain=true")
	end)

	it("THE RECT: the faded row's child reads the same absolute box as its plain neighbour's", function()
		--[[ THE ORACLE: whatever the memo decided, the public reader agrees with the
			tree. Rows are 30px tall with a 1px gap, so row N's `Bar` sits 31px below row
			N-1's, and a child stored in a space nobody registered would report its
			HOST-RELATIVE y as an absolute one — both rows reading the same number.

			IT IS AN ORACLE AND NOT A PIN (see the header): the fake target's host
			registry ACCUMULATES the space flag, so it repairs the divergence the live
			adapter could not, and this case stays green under M1. It is here because a
			memo case with no geometry beside it is a claim about bookkeeping rather than
			about the tree. ]]
		local w = makeWorld()
		w.fade:set(nil)
		w.env:set("viewportRect", { x = 0, y = 0, w = 601, h = 500 })
		w.pres.refresh()
		w.fade:set(0.5)
		w.env:set("viewportRect", { x = 0, y = 0, w = 600, h = 500 })
		w.pres.refresh()
		local faded = w.controller.rectOf(`{FADE_ROW_PATH}/Bar`)
		local plain = w.controller.rectOf(`{PLAIN_ROW_PATH}/Bar`)
		expect(`gap={plain.y - faded.y} fadedX={faded.x} plainX={plain.x}`).toBe("gap=31 fadedX=0 plainX=0")
	end)
end)
