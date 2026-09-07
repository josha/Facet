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

--[[ ── THE OTHER ORDER: A SPACE THAT LATER GAINS A PAINT PROP (RED-TEAM F1) ──────

	The block above closes `number -> nil`: a container that was a `CanvasGroup` on its
	first ask does not become a coordinate space on its second. THIS block closes
	`nil -> number`, which is the direction with the live producer and the worse
	consequence.

	WHY IT WAS OPEN. C-10 made every path through `createOptsFor` DECIDE the memo, but
	`layout_node.hostSpaceOf` still read the branch's RETURN VALUE. A row memoised
	`true` by the D6a trigger that later gains an `opacity`/`scale`/`rotation` takes an
	early return carrying `{ canvasGroup = true }` or `{ instanceHost = true }` — a
	correct answer to "which engine object", and silent about the coordinate space. So
	the LAYOUT node was rebuilt with `hostSpace = nil` while the mounted node's memo,
	`renderer.livePaths`' `spaceHosts` and the adapter's create-time host entry all
	still said `true`: the solver stored the row's whole subtree ABSOLUTELY and
	`rect_reads` composed the host origin onto it anyway.

	AND THE PRODUCER IS PUBLIC, which is why this is a fix and not a note. `opacity` is
	a documented prop on `Box` and `ZStack` whose own doc names `UI.ZStack { opacity =
	0.4, … }` as the common spelling; `scale`/`rotation` are offered on every rendered
	class ("a press dip, a motion pop"); `ZStack` is a `ROW_HOST`; and `mount.luau`
	writes `node.props[propName]` on every signal fire. A press animation on a hosted
	list row is the shipped shape.

	THE ORACLE IS THAT NONE OF THE THREE PROPS IS ALLOWED TO MOVE A BOX. All three are
	paint-only by their own schema doc — `scale` "changes nothing the solver computed" —
	so the whole census, read through the two public readers, must be BYTE-EQUAL to the
	same census before the write and to a control surface that never took the prop. At
	`4c56f1c9` the faded row's `Bar` reads y=124 through `rectOf` against the control's
	62: one 62px host origin, counted twice.

	AND THE STORED RECT IS THE LAYOUT NODE'S OWN ANSWER, read directly. `storedRect` is
	what the renderer handed the adapter — host-RELATIVE when the layout node called the
	row a space and absolute when it did not — so `stored` beside `hostSpaceAt` is
	exactly "the layout node and the mounted node agree", as two numbers rather than as
	a claim. ]]

--[[ the same 40-row shape as `makeWorld`, with the prop starting ABSENT so the first
	ask decides `true` on the D6a trigger, and arriving later. One builder for all three
	props because the divergence is a property of the EARLY RETURN, not of which prop
	took it: `opacity`/`canvasGroup` return `{ canvasGroup = true }` and
	`scale`/`rotation` return `{ instanceHost = true }`, and neither carries the key. ]]
local function makeLateWorld(prop: string): any
	local w = worldLib.new({
		viewport = { x = 0, y = 0, w = 600, h = 500 },
		overflowGuardOff = "a 40-row list of 30px rows is taller than a 500px viewport on purpose: this "
			.. "fixture measures the coordinate-space memo, not containment",
	})
	local core = w.core
	local late = core:signal(nil)
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
						row = function(item: any)
							local p: any = {
								id = "Row",
								padding = 0,
								height = px(30),
								children = {
									UI.Text({ id = "Name", textSize = 12, text = `row{item.n}` }),
									UI.Box({ id = "Bar", width = px(40), height = px(6) }),
								},
							}
							if item.fade then
								p[prop] = late
							end
							return UI.ZStack(p)
						end,
					}),
				},
			}),
		},
	}))
	w.late = late
	return w
end

--[[ EVERY NODE, THROUGH BOTH PUBLIC READERS. A per-row assertion would have named the
	row this fixture already suspects; the divergence is a whole-subtree one and the
	census is what says no OTHER node moved either. Sorted so the string is a function
	of the set and not of the adapter's hash order. ]]
local function census(w: any): string
	local paths = w.adapter.paths()
	table.sort(paths)
	local out: { string } = {}
	for _, path in paths do
		local r = w.controller.rectOf(path)
		local s = w.controller.screenRectOf(path)
		if r == nil or s == nil then
			table.insert(out, `{path} unread`)
		else
			table.insert(out, `{path} {r.x},{r.y},{r.w},{r.h} {s.x},{s.y},{s.w},{s.h}`)
		end
	end
	return table.concat(out, "\n")
end

-- the value each prop takes when it arrives. Each is the identity for its own term —
-- an invisible fade, an unscaled scale, a zero rotation — so a box that moves cannot be
-- excused as the prop doing its job.
local LATE_VALUE: { [string]: number } = { opacity = 0.5, scale = 1, rotation = 0 }

describe("RED-TEAM F1: a row that is already a coordinate space stays one", function()
	for _, prop in { "opacity", "scale", "rotation" } do
		it(`a late \`{prop}\` moves no box, and the stored rect stays host-relative`, function()
			local w = makeLateWorld(prop)
			--[[ THE PRECONDITION, stated rather than assumed: the row IS a space before
				the write. Without it the case would pass on a fixture where the trigger
				never fired and would say nothing at all. ]]
			expect(`space={tostring(w.adapter.hostSpaceAt(FADE_ROW_PATH))}`).toBe("space=true")
			local beforeCensus = census(w)
			local before = instance_boundary.decisions()

			--[[ THE WRITE, AND THEN A WHOLE-TREE REBUILD — the half the drive needs, for
				the reason the block above states: all three props are PAINT-classed, so
				moving one does not rebuild a layout node and `hostSpaceOf` is never
				re-asked. The viewport goes out and comes BACK so the closing census is
				taken at the fixture's own viewport and is comparable to the opening one
				byte for byte. ]]
			w.late:set(LATE_VALUE[prop])
			w.env:set("viewportRect", { x = 0, y = 0, w = 601, h = 500 })
			w.pres.refresh()
			w.env:set("viewportRect", { x = 0, y = 0, w = 600, h = 500 })
			w.pres.refresh()

			--[[ ...AND THE MEMO NEVER RE-OPENED. Read HERE and not at the end of the case:
				the control surface below is a second 40-row tree and decides 122 containers
				of its own, so a delta taken after it would be measuring the fixture. ]]
			expect(`decided={instance_boundary.decisions() - before}`).toBe("decided=0")

			--[[ ARM 1: THE PRE-WRITE FRAME. A paint prop that moved a box is a defect
				whatever else is true, and this arm needs no second surface to say so. ]]
			expect(`census moved={tostring(census(w) ~= beforeCensus)}`).toBe("census moved=false")

			--[[ ARM 2: A CONTROL SURFACE THAT NEVER TOOK THE PROP, driven through the
				identical viewport sequence. Arm 1 alone could be satisfied by a solve that
				answered nothing at all; this one says the tree really was rebuilt and still
				landed where an unfaded tree lands. ]]
			local control = makeLateWorld(prop)
			control.env:set("viewportRect", { x = 0, y = 0, w = 601, h = 500 })
			control.pres.refresh()
			control.env:set("viewportRect", { x = 0, y = 0, w = 600, h = 500 })
			control.pres.refresh()
			expect(`vs control={tostring(census(w) ~= census(control))}`).toBe("vs control=false")

			--[[ ...AND THE TWO ANSWERS, AS NUMBERS. `hostSpaceAt` is the mounted node's
				memo as the adapter latched it at create; `storedRect` is what the LAYOUT
				node decided, because the renderer hands over a host-relative rect exactly
				when the layout node called the row a space. Equal stored y on the faded row
				and its plain neighbour is the two callers agreeing — the `Bar` sits at the
				top of its own 30px row, so 0 is the host-relative answer and 62 is the
				absolute one. At `4c56f1c9` the faded row reads `stored=62` against its
				neighbour's 0, on all three props. ]]
			local fadedStored = w.adapter.node(`{FADE_ROW_PATH}/Bar`).storedRect
			local plainStored = w.adapter.node(`{PLAIN_ROW_PATH}/Bar`).storedRect
			expect(
				`space={tostring(w.adapter.hostSpaceAt(FADE_ROW_PATH))} stored={fadedStored.y} plain={plainStored.y}`
			).toBe("space=true stored=0 plain=0")
		end)
	end
end)
