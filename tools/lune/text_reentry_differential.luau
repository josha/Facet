--!strict
--[[ THE TEXT-RE-ENTRY DIFFERENTIAL — the instrument behind T18-B's "byte-identical".

	WHAT IT IS FOR. `render/solve_queue` changes HOW a settled text correction reaches
	the tree (a queue and a drain where there was a recursion) and is supposed to
	change NOTHING a consumer can see. A claim that broad is only worth what its
	instrument is worth, so this is that instrument, committed rather than scratch:
	run the SAME file in two trees and `diff` the two outputs.

	    git worktree add /tmp/facet-before <sha-before>
	    lune run tools/lune/text_reentry_differential /tmp/before.txt      # this tree
	    cp tools/lune/text_reentry_differential.luau /tmp/facet-before/tools/lune/
	    cd /tmp/facet-before && lune run tools/lune/text_reentry_differential /tmp/after.txt
	    diff /tmp/before.txt /tmp/after.txt

	WHAT IT SWEEPS. Every `device_views.VIEWS` row x BOTH adapter shapes (the queued
	target delivered from top level, and one answering INLINE the way the settled
	engine does) x four drives — the settle, a text write that learns a word, a width
	write, a viewport change. The fixture carries a FOUR-LINK epoch-driven word chain,
	which is the shape whose notification ORDER differs if the drain is sited anywhere
	but the outermost solve, and a LIVE DRAG over a drop target, which is the shape
	whose PUBLIC callbacks differ if a post-solve hook runs before the drain.

	THE DRAG ARM IS HERE BECAUSE ITS ABSENCE IS WHAT THE FIRST ROUND MISSED. That
	sweep read rects, hit rects, screen rects, props and the per-drive counters — all
	of which were identical — while the public `UI.dropTarget` `onEnter`/`onLeave`
	and the `verdict` Readable were being fired against pre-correction geometry. A
	differential is only as wide as its channel list, so the list now carries them.

	BE HONEST ABOUT WHAT THIS ARM PROVES. It records the public sequences on every
	row, which is what makes a regression in them VISIBLE here; on the fixture as
	built it does not by itself separate the two shapes, because whether an
	intermediate geometry moves the pointer off the target depends on where the
	pointer is parked relative to the edge the correction moves. The case that
	SEPARATES them — with the estimate collapsing the slot at every viewport, and a
	mutation that restores the pre-drain hook to prove it bites — is
	`tests/text_round_reentry.spec.luau`, "a live drag's public drop-target callbacks
	see one set of rects per frame". Use this file for breadth and that case for the
	verdict.

	CHANNELS: every live node's rect, hit rect, `screenRectOf` and every adapter prop;
	`solves`, the `onSolved` count, `lastMeasured`, `lastMeasureCalls`, `lastArranged`,
	`lastLayoutNodes`, `textMeasureBatches`, `feedbackSolves`; and the drag arm's
	enter/leave/verdict SEQUENCES.
]]
local fs = require("@lune/fs")
local process = require("@lune/process")

local UI = require("../../src/blueprint")
local mountLib = require("../../src/mount")
local environment = require("../../src/env/environment")
local renderer = require("../../src/render/renderer")
local customFactory = require("../../src/core/custom")
local fake_target = require("../../tests/lib/fake_target")
local device_views = require("../../tests/lib/device_views")

local function px(n: number): any
	return { type = "fixed", px = n }
end
local function fill(): any
	return { type = "fill", weight = 1 }
end
--[[ THE GIANT WORD, and why the drag arm needs one. The slot's LEFT edge is the
	label's measured width, so what decides whether an intermediate look differs is
	whether the ESTIMATE and the EXACT width put the pointer on different sides of
	that edge — and a pointer placed by hand is only on the right side of it at one
	viewport. A 400-character word whose exact width is 20 collapses the slot on the
	estimate at EVERY viewport and restores it on the correction, so the pointer is
	over the slot before the frame and after it, and over nothing in between. ]]
local GIANT = string.rep("m", 400)

local function widthOf(word: string, size: number, _font: string): number?
	if word == GIANT then
		return 20
	end
	return math.max(1, #word * size * 0.5)
end

local ROWS = 6

local function build(view: any, inline: boolean, tag: string)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = view.w, h = view.h })
	env:set("displaySize", view.displaySize)
	env:set("preferredInput", view.input)

	local strip = {}
	for i = 1, 4 do
		strip[i] = core:signal(`{tag}S{i}`)
	end
	local solo = core:signal(`{tag}solo`)
	local pinned = core:signal(`{tag}pin`)
	local rowValue = {}
	local items = {}
	for i = 1, ROWS do
		rowValue[i] = core:signal(`{tag}row{i}`)
		table.insert(items, { id = `r{i}`, n = rowValue[i] })
	end
	local rows = core:signal(items)
	local width = core:signal(px(120))
	local dragWord = core:signal(`{tag}dragshort`)
	-- THE CHAIN: a word revealed only by the previous word's epoch bump, bounded at
	-- four links. This is the shape the notification ORDER differs on if the drain is
	-- sited anywhere but at the outermost solve.
	local chainWords = {}
	for i = 1, 4 do
		chainWords[i] = `{tag}c{string.rep("y", i)}{i}`
	end
	local chainLabel = core:memo(function(use)
		local epoch = (use(env:get("textMeasureEpoch")) :: number?) or 0
		return chainWords[math.min(4, epoch + 1)]
	end)

	local enters: { string } = {}
	local leaves: { string } = {}
	local verdicts: { string } = {}

	local bp = UI.VStack({
		id = "Root",
		padding = 0,
		gap = 0,
		width = fill(),
		height = fill(),
		children = {
			UI.HStack({
				id = "Strip",
				padding = 0,
				gap = 2,
				height = px(20),
				children = {
					UI.Text({ id = "S1", textSize = 14, text = strip[1] }),
					UI.Text({ id = "S2", textSize = 14, text = strip[2] }),
					UI.Text({ id = "S3", textSize = 14, text = strip[3] }),
					UI.Text({ id = "S4", textSize = 14, text = strip[4] }),
				},
			}),
			UI.VStack({
				id = "Deep",
				padding = 0,
				gap = 0,
				children = {
					UI.VStack({
						id = "Mid",
						padding = 0,
						gap = 0,
						children = {
							UI.HStack({
								id = "Inner",
								padding = 0,
								gap = 0,
								children = { UI.Text({ id = "Buried", textSize = 18, text = solo }) },
							}),
						},
					}),
				},
			}),
			UI.HStack({
				id = "Pins",
				padding = 0,
				gap = 2,
				height = px(24),
				children = {
					UI.Text({ id = "Pinned", textSize = 11, width = px(60), height = px(14), text = pinned }),
					UI.Text({ id = "Fitted", textSize = "fit", width = px(70), height = px(20), text = solo }),
					UI.Box({ id = "Sized", width = width, height = px(10) }),
					UI.Text({ id = "Chain", textSize = 13, text = chainLabel }),
				},
			}),
			-- THE DRAG ARM: a drop target whose left edge is a measured text width, so
			-- the correction moves it, plus the draggable that acquires the session
			UI.HStack({
				id = "DragRow",
				padding = 0,
				gap = 0,
				width = fill(),
				height = px(60),
				children = {
					UI.Text({ id = "DragLabel", textSize = 16, text = dragWord }),
					UI.dropTarget(UI.Box({ id = "Slot", width = fill(), height = px(50) }), {
						onDrop = function() end,
						onEnter = function()
							table.insert(enters, "Slot")
						end,
						onLeave = function()
							table.insert(leaves, "Slot")
						end,
					}),
				},
			}),
			UI.draggable(UI.Box({ id = "Card", width = px(40), height = px(40) }), { payload = "card" }),
			UI.VStack({
				id = "List",
				padding = 0,
				gap = 1,
				width = fill(),
				children = {
					UI.ForEach({
						id = "Rows",
						items = rows,
						key = function(item: any)
							return item.id
						end,
						row = function(item: any)
							return UI.HStack({
								id = "Row",
								padding = 0,
								gap = 2,
								width = fill(),
								height = px(16),
								children = {
									UI.Text({ id = "Name", textSize = 12, text = item.n }),
									UI.Box({ id = "Bar", width = px(10), height = px(6) }),
								},
							})
						end,
					}),
				},
			}),
		},
	})
	local root = mountLib.mount(core, bp)
	local adapter = fake_target.new()
	if inline then
		-- the SETTLED live adapter: answer inside the call, on the caller's stack
		adapter.answerTextInline(widthOf)
	end
	local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "coreSafeContent" })
	local notifies = 0
	controller.onSolved(function()
		notifies += 1
	end)
	local registry = controller.dragRegistry()
	core:observe(registry.verdict, function(v: any)
		table.insert(verdicts, if v == nil then "-" else tostring(v.targetId))
	end)
	return {
		core = core,
		env = env,
		controller = controller,
		adapter = adapter,
		registry = registry,
		strip = strip,
		solo = solo,
		dragWord = dragWord,
		pinned = pinned,
		rowValue = rowValue,
		width = width,
		enters = enters,
		leaves = leaves,
		verdicts = verdicts,
		notifyCount = function()
			return notifies
		end,
	}
end

local function drain(arm: any)
	for _ = 1, 8 do
		if arm.adapter.textBatchCount() == 0 then
			break
		end
		arm.adapter.deliverTextWidths(widthOf)
		arm.controller.refresh()
	end
end

local function snapshot(arm: any): string
	local out = {}
	for path, node in arm.adapter.liveNodes() do
		local props = {}
		for k, v in node.props or {} do
			if type(v) == "table" then
				local inner = {}
				for k2, v2 in v do
					table.insert(inner, `{tostring(k2)}={tostring(v2)}`)
				end
				table.sort(inner)
				table.insert(props, `{k}=\{{table.concat(inner, ",")}\}`)
			else
				table.insert(props, `{k}={tostring(v)}`)
			end
		end
		table.sort(props)
		local r = node.rect
		local hit = arm.adapter.hitRectOf(path)
		local sr = arm.controller.screenRectOf(path)
		table.insert(
			out,
			`{path}|rect={if r then `{r.x},{r.y},{r.w},{r.h}` else "-"}`
				.. `|hit={if hit then `{hit.x},{hit.y},{hit.w},{hit.h}` else "-"}`
				.. `|screen={if sr then `{sr.x},{sr.y},{sr.w},{sr.h}` else "-"}`
				.. `|props={table.concat(props, ",")}`
		)
	end
	table.sort(out)
	return table.concat(out, "\n")
end

local function statLine(arm: any, label: string): string
	local st = arm.controller.stats()
	return `{label}|solves={st.solves}|notifies={arm.notifyCount()}|measured={st.lastMeasured}`
		.. `|calls={st.lastMeasureCalls}|arranged={st.lastArranged}|nodes={st.lastLayoutNodes}`
		.. `|batches={st.textMeasureBatches}|feedback={st.feedbackSolves}`
		.. `|enters={table.concat(arm.enters, ">")}`
		.. `|leaves={table.concat(arm.leaves, ">")}`
		.. `|verdicts={table.concat(arm.verdicts, ">")}`
end

local lines: { string } = {}
for _, view in device_views.VIEWS do
	for _, inline in { false, true } do
		local mode = if inline then "inline" else "queued"
		local tag = `{view.id}-{mode}-`
		local arm = build(view, inline, tag)
		arm.controller.initialRender()
		if not inline then
			drain(arm)
		end
		--[[ ...AND THE DRAG GOES LIVE BEFORE ANY DRIVE, so every correction below is a
			reflow under a session that is publishing to public listeners. The pointer sits
			near the slot's right edge, which the label's measured width moves. ]]
		local slot = arm.controller.rectOf("/Root/DragRow/Slot")
		if slot ~= nil and slot.w > 40 then
			-- the middle of the settled slot: inside it before the frame and after it,
			-- and over nothing on the estimate that collapses it (see `GIANT`)
			local x, y = slot.x + slot.w / 2, slot.y + slot.h / 2
			arm.adapter.driveDragStart("/Root/Card", { x = x - 30, y = y, pointerType = "mouse" })
			arm.adapter.driveDragContinue("/Root/Card", { x = x, y = y, pointerType = "mouse" }, { x = 0, y = 0 })
		end
		table.insert(lines, statLine(arm, `{view.id}|{mode}|settle`))
		table.insert(lines, snapshot(arm))

		-- drive 1: a text write that learns a word
		arm.strip[1]:set(`{tag}NEWWORD`)
		arm.solo:set(`{tag}NEWSOLO`)
		arm.dragWord:set(GIANT)
		arm.controller.refresh()
		if not inline then
			drain(arm)
		end
		table.insert(lines, statLine(arm, `{view.id}|{mode}|text`))
		table.insert(lines, snapshot(arm))

		-- drive 2: a width write
		arm.width:set(px(180))
		arm.controller.refresh()
		if not inline then
			drain(arm)
		end
		table.insert(lines, statLine(arm, `{view.id}|{mode}|width`))
		table.insert(lines, snapshot(arm))

		-- drive 3: a viewport change
		arm.env:set("viewportRect", { x = 0, y = 0, w = view.w // 2 + 40, h = view.h // 2 + 40 })
		arm.controller.refresh()
		if not inline then
			drain(arm)
		end
		table.insert(lines, statLine(arm, `{view.id}|{mode}|viewport`))
		table.insert(lines, snapshot(arm))

		arm.controller.dispose()
	end
end

local out = process.args[1] or "artifacts/text-reentry-differential.txt"
fs.writeFile(out, table.concat(lines, "\n") .. "\n")
print(`wrote {out} ({#lines} blocks)`)
