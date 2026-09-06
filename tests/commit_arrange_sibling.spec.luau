--!strict
--[[ ── THE COMMIT-CLASS WRITE THAT SITS BESIDE A PURE-ARRANGE ONE ───────────────

	THE AXIS THIS FILE ADDS, and why the suite had a hole exactly its shape. The
	commit prune (`render/commit_walks`' `buildDescend`) classifies a parent's
	children ONCE per commit into three descend lists — base, move-blind, and the
	arrange-blind one the four property walks read (`textScale`, `padding`,
	`textVerdicts`, `scrollRegions`). The arrange-blind list is answered against the
	COMMIT-side dirty set, so it parts company with the other two only on a child
	whose dirt is entirely in `PURE_ARRANGE_PROPS` (`anchor`, `offsetX`, `offsetY`,
	`alignH`, `alignV`, `lineAlign`, `distribute`). Every differential in this repo
	that sweeps the commit prune drove ONE prop class per fixture:
	`commit_descend_cache` drives three arms whose children carry no pure-arrange
	dirt at all, and `layout_prop_dirt` drives every pure-arrange prop but one at a
	time on a purpose-built parent, never beside a commit-class sibling. So the
	third fork of the sift was reachable in production and unreachable from the
	suite, and a list it built SHORT passed 8,663 cases green.

	THE SHAPE, and every term in it is load-bearing:

	    Anchor
	      A   static            — every shape prunes it, which is what makes the
	                              three lists alias ONE array
	      X   the channel       — dirty in the commit set: a `padding`, a
	                              `textSize`, a wrap/compact verdict or a scroll
	                              canvas, one per arm
	      C   `offsetX`         — pure-arrange dirt and a settled/moved entry, so
	                              base and move descend it and the commit shape
	                              does not: the fork

	An ANCHOR parent rather than a stack because a stack child's rect is a function
	of its siblings', so a width write there dirties the row and the case stops
	being about the sift. Under an anchor, `C`'s translate is inert to `A` and `X`.

	AND THE ORACLE IS THE C4 SWITCH, not a counter. `commitScope = false` walks the
	live tree the way HEAD did before the prune existed, so the two arms must agree
	BYTE FOR BYTE on everything a reader can see — every live node's rect, props,
	hit rect, scroll canvas, visibility and presented position, plus the adapter's
	own `engineWrites` total. A third arm mounts the same surface with the drive's
	values already in place and never refreshes it, which is the from-scratch answer
	neither pruned arm can borrow from. Nine viewports, because a verdict channel
	(wrap, compact) flips on the width the viewport hands it and 320x640 is the
	narrowest box this framework supports. ]]
local testkit = require("./lib/testkit")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local customFactory = require("../src/core/custom")
local fake_target = require("./lib/fake_target")
local device_views = require("./lib/device_views")
local describe, it, expect = testkit.describe, testkit.it, testkit.expect

local function px(n: number): any
	return { type = "fixed", px = n }
end

export type Opts = {
	channel: string,
	commitScope: boolean?,
	viewport: { w: number, h: number }?,
	-- start the surface at the values the drive would write, and never drive it:
	-- the from-scratch arm
	settled: boolean?,
}

-- the two values every channel moves between; `settled` mounts at the second
local START = { pad = 4, size = 12, width = 200, rows = 1 }
local FINAL = { pad = 17, size = 22, width = 34, rows = 4 }

local function world(o: Opts): any
	local view = o.viewport or { w = 800, h = 600 }
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = view.w, h = view.h })
	local from = if o.settled then FINAL else START
	local pad = core:signal(from.pad)
	local size = core:signal(from.size)
	local width = core:signal(from.width)
	local rows = core:signal(from.rows)
	-- the pure-arrange sibling's own signal, mounted at 0 on every arm so the
	-- from-scratch arm carries the drive's translate too
	local offset = core:signal(if o.settled then 40 else 0)

	local channelChild: any
	if o.channel == "padding" then
		channelChild = UI.Text({
			id = "X",
			text = "bbb",
			textSize = 12,
			padding = core:memo(function(use: any)
				return use(pad) :: number
			end),
		})
	elseif o.channel == "textScale" then
		channelChild = UI.Text({
			id = "X",
			text = "bbb",
			textSize = core:memo(function(use: any)
				return use(size) :: number
			end),
		})
	elseif o.channel == "wrap" then
		-- the WRAP verdict: the solver knows whether this phrase's longest word fits
		-- the box it ended up with, and the width the drive writes decides it
		channelChild = UI.Text({
			id = "X",
			text = "wrappable phrase here",
			textSize = 12,
			width = core:memo(function(use: any)
				return px(use(width) :: number)
			end),
		})
	elseif o.channel == "compact" then
		-- ...and the COMPACT verdict, the other half of the same walk
		channelChild = UI.Button({
			id = "X",
			label = "Minimize",
			compactLabel = { text = "\u{2013}" },
			width = core:memo(function(use: any)
				return px(use(width) :: number)
			end),
			height = px(30),
		})
	elseif o.channel == "scroll" then
		-- ...and the scroll canvas, which is the CONTENT extent and not the box
		channelChild = UI.ScrollView({
			id = "X",
			axis = "y",
			padding = 0,
			gap = 0,
			width = px(120),
			height = px(40),
			children = {
				UI.Box({
					id = "Fill",
					width = px(60),
					height = core:memo(function(use: any)
						return px(20 * (use(rows) :: number))
					end),
				}),
			},
		})
	else
		error(`unknown channel {o.channel}`)
	end

	local tree = UI.Screen({
		id = "S",
		children = {
			UI.Anchor({
				id = "P",
				children = {
					UI.Text({ id = "A", text = "aaa", textSize = 12, padding = 2 }),
					channelChild,
					UI.Text({
						id = "C",
						text = "ccc",
						textSize = 12,
						padding = 2,
						offsetX = core:memo(function(use: any)
							return use(offset) :: number
						end),
					}),
				},
			}),
		},
	})
	local root = mountLib.mount(core, tree)
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, {
		rootPolicy = "edgeToEdge",
		incrementalLayout = true,
		measureReuse = true,
		layoutNodeReuse = true,
		commitScope = o.commitScope ~= false,
	})
	controller.initialRender()

	local arm: any = { adapter = adapter, controller = controller }

	--[[ ONE REFRESH CARRYING BOTH WRITES, which is the whole case: the commit-class
		write on `X` and the pure-arrange write on `C` have to be classified against
		each other in ONE sift. Two refreshes would sift them separately and the fork
		this file exists for would never run. ]]
	function arm.drive()
		pad:set(FINAL.pad)
		size:set(FINAL.size)
		width:set(FINAL.width)
		rows:set(FINAL.rows)
		offset:set(40)
		controller.refresh()
	end

	local function ser(v: any, depth: number): string
		if type(v) ~= "table" then
			return tostring(v)
		end
		if depth <= 0 then
			return "…"
		end
		local inner = {}
		for k, item in v do
			table.insert(inner, `{tostring(k)}={ser(item, depth - 1)}`)
		end
		table.sort(inner)
		return `\{{table.concat(inner, ",")}\}`
	end
	local function fmtRect(r: any): string
		return if r == nil then "-" else `{r.x},{r.y},{r.w},{r.h}`
	end

	-- every live node's rect, props, hit rect, canvas, visibility and presented
	-- position — the columns `deep_stack_scene.snapshot` compares, for the same
	-- reason: an optimisation that skips work must change nothing a reader can see
	--[[ ...AND THE WRITE TOTAL IS OPTIONAL, because it is CUMULATIVE and the
		from-scratch arm has no drive history to accumulate: comparing it there would
		compare the two arms' biographies rather than their surfaces. The two pruned
		arms take the identical drive, so between THEM it is a real column. ]]
	function arm.snapshot(withWrites: boolean?): string
		local out = {}
		for path, node in adapter.liveNodes() do
			local props = {}
			for k, v in node.props or {} do
				table.insert(props, `{k}={ser(v, 6)}`)
			end
			table.sort(props)
			local pp = node.presentedPosition
			local region = node.scrollRegion
			table.insert(
				out,
				`{path}|{fmtRect(node.storedRect)}|{table.concat(props, ",")}`
					.. `|vis={tostring(node.visible)}`
					.. `|hit={fmtRect(node.hitRect)}`
					.. `|canvas={if region then `{region.contentW},{region.contentH}` else "-"}`
					.. `|pos={if pp then `{pp.x},{pp.y}` else "-"}`
					.. `|ro={fmtRect(controller.rectOf(path))}`
					.. `|sro={fmtRect(controller.screenRectOf(path))}`
			)
		end
		table.sort(out)
		if withWrites then
			table.insert(out, `engineWrites={tostring(adapter.engineWrites())}`)
		end
		return table.concat(out, "\n")
	end

	function arm.dispose()
		controller.dispose()
		root.dispose()
	end
	return arm
end

local CHANNELS = { "padding", "textScale", "wrap", "compact", "scroll" }

describe("a commit-class write on a sibling of a pure-arrange write", function()
	it("reaches the adapter with the commit prune on, exactly as it does with it off", function()
		--[[ THE END-TO-END CASE, kept readable on purpose: the `padding` channel at one
			viewport, with the per-walk visit census printed beside it. With the sift
			building a SHORT commit list the four arrange-blind walks visit 2 nodes (the
			Screen and the Anchor) where the four position-reading walks visit 4, and
			`X`'s padding never leaves the framework. ]]
		local on, off = world({ channel = "padding" }), world({ channel = "padding", commitScope = false })
		local function padOf(w: any): string
			local n = w.adapter.node("/S/P/X")
			local p = if n ~= nil then (n.props or {}).padding else nil
			return if p == nil then "-" else tostring(p)
		end
		print(`arrange-sibling mount on X={padOf(on)} off X={padOf(off)}`)
		on.drive()
		off.drive()
		local st = on.controller.stats() :: any
		local keys = {}
		for k in st.lastCommitVisitsByWalk do
			table.insert(keys, k)
		end
		table.sort(keys)
		local parts = {}
		for _, k in keys do
			table.insert(parts, `{k}={st.lastCommitVisitsByWalk[k]}`)
		end
		print(`arrange-sibling byWalk on: {table.concat(parts, " ")}`)
		print(`arrange-sibling after on X={padOf(on)} off X={padOf(off)}`)
		expect(`prune-on X padding = {padOf(on)}`).toBe(`prune-on X padding = {padOf(off)}`)
		on.dispose()
		off.dispose()
	end)

	it("...on every commit-side channel, against the from-scratch answer too", function()
		--[[ THE FOUR WALKS THE ARRANGE-BLIND LIST FEEDS, one channel each: `padding`
			and `textScale` write a prop the walk caches per path, `wrap`/`compact` write
			the solver's own verdicts, and `scroll` writes the canvas extent. The
			from-scratch arm is mounted at the drive's values and never refreshed, so it
			shares no cache, no entry map and no descend list with the other two. ]]
		for _, channel in CHANNELS do
			local on = world({ channel = channel })
			local off = world({ channel = channel, commitScope = false })
			local fresh = world({ channel = channel, settled = true })
			on.drive()
			off.drive()
			expect(`{channel} pruned\n{on.snapshot(true)}`).toBe(`{channel} pruned\n{off.snapshot(true)}`)
			expect(`{channel} fresh\n{on.snapshot()}`).toBe(`{channel} fresh\n{fresh.snapshot()}`)
			on.dispose()
			off.dispose()
			fresh.dispose()
		end
	end)

	it("...at every view in the device matrix", function()
		--[[ AND THE VIEWPORT IS AN AXIS HERE, unlike the two cases above: the wrap and
			compact verdicts are answered against the width the view leaves, so the
			channel that flips at 1232px is not the channel that flips at 320px. ]]
		for _, view in device_views.VIEWS do
			for _, channel in CHANNELS do
				local viewport = { w = view.w, h = view.h }
				local on = world({ channel = channel, viewport = viewport })
				local off = world({ channel = channel, commitScope = false, viewport = viewport })
				on.drive()
				off.drive()
				expect(`{view.id} {channel}\n{on.snapshot(true)}`).toBe(`{view.id} {channel}\n{off.snapshot(true)}`)
				on.dispose()
				off.dispose()
			end
		end
	end)
end)
