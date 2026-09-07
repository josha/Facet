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

	CHANNELS: every live node's rect, hit rect, `screenRectOf`, STORED rect, host
	identity and host kind, and every adapter prop; `solves`, the `onSolved` count,
	`lastMeasured`, `lastMeasureCalls`, `lastArranged`, `lastLayoutNodes`,
	`textMeasureBatches`, `feedbackSolves`, `rectWrites`, `engineWrites`, `creates`,
	`removes`, `parked`, `recycled`, `lastTranslated`, `lastLaneTranslates`,
	`lastRectInserts`, `lastTextDirtyPaths`; and the drag arm's enter/leave/verdict
	SEQUENCES. Plus a SEPARATE `plan=` line per drive carrying the counters that do not
	exist before Plan D (see below).

	── THE SECOND ROUND, AND WHY THE FIRST ONE'S md5 WAS A NULL (RED-TEAM C-2) ──────
	2026-09-07. The `3db66551b80fe677d314f2092b0a0038` baseline was carried on every
	Plan D commit as "observables byte-identical", and for six of Plan D's eight fast
	paths it could not have said otherwise:

	  1. IT COULD NOT SEE A COORDINATE-SPACE CHANGE AT ALL. `snapshot()` read
	     `node.rect`, which `tests/lib/fake_target.setRect` deliberately COMPOSES —
	     the stored, host-relative number lives beside it as `storedRect`. D6a's whole
	     mechanism is which of those two the renderer writes, so an identical md5
	     across D6a was guaranteed by construction.
	  2. THE FIXTURE CROSSED NONE OF PLAN D'S THRESHOLDS: 6 `ForEach` rows and ~40
	     nodes, so `DIRT_PROBE_FLOOR` (64), the text push cap (`max(64, nodes // 8)`)
	     and `COLLECT_CAP` (1,024 words) were all out of reach.
	  3. THE CHANNEL LIST OMITTED THE WORK CHANNELS Plan D moves — no `rectWrites`,
	     `engineWrites`, `creates`, `lastTranslated`, `lastLaneTranslates`.
	  4. NO NUMERIC TEXT (which is why the D6c numeric defect could only be found
	     live), no `compactLabel`, no host under a host.

	So the fixture set CHANGED, and with it the baseline. The old md5 remains valid
	for the OLD fixture set and says exactly what it always said about it; it is not
	evidence about anything this round added. The new sweep is the one to diff.

	THE SECOND FIXTURE (`buildWide`) crosses each of those axes on purpose: a 96-row
	`ForEach` whose two-child rows are coordinate-space hosts, a nested `ForEach`
	inside one of them (a host UNDER a host), 420 labels sharing one (font,size) so
	the over-cap text push route runs, a >1,024-word paragraph so the collector
	truncates, a numeric label, and a `Button` with a `compactLabel` in a box that
	shrinks. Drives: settle, insert, remove, reorder, a `When` branch above the list
	dropping and returning, a word correction, and the vocabulary.

	AND SOME OF IT IS EXPECTED TO DIFFER, which is the point of a differential rather
	than a checksum. Read the diff by BLOCK: `stored=`/`host=` moving under a
	`ForEach` row is D6a doing its job; a `plan=` line differing is a counter that did
	not exist at the parent; a rect a settled surface converges on differently is
	D6d's correctness fix and is named at the case. A difference in `rect=`, `hit=`,
	`screen=` or `props=` that NONE of those explain is a finding.

	── THE BASELINES ───────────────────────────────────────────────────────────────

	  * `6f14ec6b3e184809d8cef15094e6997b`, 360 blocks — THIS fixture set, Facet
	    `32ee36108` on `facet-parity-d`, taken 2026-09-07. The reason it is a new
	    number rather than a moved one is above: the FIXTURE SET CHANGED, so the old
	    baseline is not stale, it is answering a different question.
	  * `3db66551b80fe677d314f2092b0a0038`, 144 blocks — the fixture set as it stood
	    before 2026-09-07 (nine views, one ~40-node fixture, four drives, no
	    `stored`/host channel and no work counters). Still valid FOR THAT SET, and
	    that set is what every Plan D commit before this one carried it as.

	AGAINST `b315dc34` (Plan D's parent), run 2026-09-07, this file's own verdict:
	`rect=`, `hit=`, `screen=`, `props=` and the NODE SET are byte-identical on all
	120 drive blocks. Every difference is a work counter or a coordinate space:
	`hosts` (0 -> 6 small, 0 -> 99 wide) and the `stored=`/`host=`/`space=` triple on
	every descendant of a `ForEach` row (D6a); `rectWrites`/`engineWrites`/`inserts`/
	`translated` (D6a's write reduction: 731 -> 8 rect inserts on the wide insert
	drive); `measured`/`calls`/`arranged` (D1's plan cache and D2's scans: 852 -> 8
	measured on the same drive); `textPaths` 0 -> 2 (D3c/D6c's over-cap probe
	answering with a MOVED set where the parent answered `full` and pushed nothing);
	and every `plan=` line, whose counters do not exist at the parent.
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
		--[[ BOTH RECTS, AND THE HOST THAT SEPARATES THEM (RED-TEAM C-2). `node.rect` is
			the COMPOSED window rect the fake reports under that name; `node.storedRect`
			is exactly what the renderer handed the adapter, which beneath a
			coordinate-space host is HOST-RELATIVE. Reading only the composed one made
			the whole D6a mechanism invisible to this instrument. `host`/`space` say
			WHICH host a path stores against and whether this path is itself one, so a
			`stored=` that moved can be attributed rather than merely noticed. ]]
		local stored = node.storedRect
		local host = arm.adapter.hostOf(path)
		local space = arm.adapter.hostSpaceAt(path)
		table.insert(
			out,
			`{path}|rect={if r then `{r.x},{r.y},{r.w},{r.h}` else "-"}`
				.. `|stored={if stored then `{stored.x},{stored.y},{stored.w},{stored.h}` else "-"}`
				.. `|host={if host then tostring(host.path) else "-"}`
				.. `|space={tostring(space)}`
				.. `|hit={if hit then `{hit.x},{hit.y},{hit.w},{hit.h}` else "-"}`
				.. `|screen={if sr then `{sr.x},{sr.y},{sr.w},{sr.h}` else "-"}`
				.. `|props={table.concat(props, ",")}`
		)
	end
	table.sort(out)
	return table.concat(out, "\n")
end

--[[ THE WORK CHANNELS, not only the layout ones (RED-TEAM C-2). Every field here
	exists at the Plan D parent commit, so this line is diffable end to end. The
	counters Plan D INTRODUCED are on `planLine` below instead — putting them here
	would make every single line differ and drown the signal this file exists for. ]]
local function statLine(arm: any, label: string): string
	local st = arm.controller.stats()
	return `{label}|solves={st.solves}|notifies={arm.notifyCount()}|measured={st.lastMeasured}`
		.. `|calls={st.lastMeasureCalls}|arranged={st.lastArranged}|nodes={st.lastLayoutNodes}`
		.. `|batches={st.textMeasureBatches}|feedback={st.feedbackSolves}`
		.. `|rectWrites={st.rectWrites}|engineWrites={tostring(st.engineWrites)}|propWrites={st.propWrites}`
		.. `|creates={st.creates}|removes={st.removes}|parked={st.parked}|recycled={st.recycled}`
		.. `|translated={st.lastTranslated}|lane={st.lastLaneTranslates}|inserts={st.lastRectInserts}`
		.. `|textPaths={st.lastTextDirtyPaths}|hosts={arm.adapter.hostCount()}`
		.. `|enters={table.concat(arm.enters, ">")}`
		.. `|leaves={table.concat(arm.leaves, ">")}`
		.. `|verdicts={table.concat(arm.verdicts, ">")}`
end

--[[ ...AND THE COUNTERS THAT DID NOT EXIST BEFORE PLAN D, on their own line and
	labelled as such. `lastTextProbeMeasures`/`lastTextWordSkips` (D3c/D6c) and
	`textCollectTruncated` (D3a) read `nil` in a parent worktree, so EVERY one of
	these lines differs by construction — which is what they are for: they say what
	the new routes did on a fixture that actually reaches them, and they are excluded
	from the "explain every differing block" reading by name rather than by accident. ]]
local function planLine(arm: any, label: string): string
	local st = arm.controller.stats()
	return `{label}|plan=probes:{tostring(st.lastTextProbeMeasures)}`
		.. `|skips:{tostring(st.lastTextWordSkips)}`
		.. `|truncated:{tostring(st.textCollectTruncated)}`
		.. `|planVisits:{tostring(st.lastPlanVisits)}`
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
		table.insert(lines, planLine(arm, `{view.id}|{mode}|settle`))
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
		table.insert(lines, planLine(arm, `{view.id}|{mode}|text`))
		table.insert(lines, snapshot(arm))

		-- drive 2: a width write
		arm.width:set(px(180))
		arm.controller.refresh()
		if not inline then
			drain(arm)
		end
		table.insert(lines, statLine(arm, `{view.id}|{mode}|width`))
		table.insert(lines, planLine(arm, `{view.id}|{mode}|width`))
		table.insert(lines, snapshot(arm))

		-- drive 3: a viewport change
		arm.env:set("viewportRect", { x = 0, y = 0, w = view.w // 2 + 40, h = view.h // 2 + 40 })
		arm.controller.refresh()
		if not inline then
			drain(arm)
		end
		table.insert(lines, statLine(arm, `{view.id}|{mode}|viewport`))
		table.insert(lines, planLine(arm, `{view.id}|{mode}|viewport`))
		table.insert(lines, snapshot(arm))

		arm.controller.dispose()
	end
end

--[[ ── THE SECOND FIXTURE: THE THRESHOLDS THE FIRST ONE NEVER REACHED (C-2) ──────

	Every constant Plan D put a fast path behind, crossed on purpose:

	  * `WIDE_ROWS = 96` `ForEach` rows, each an `HStack` with two children spliced
	    into a stack — `mount.markRow` + `createOptsFor`'s fifth arm, i.e. exactly the
	    shape D6a turns into a COORDINATE-SPACE HOST. 96 is also past
	    `DIRT_PROBE_FLOOR`'s 64, so the container's probe budget is its child count
	    rather than the floor.
	  * a NESTED `ForEach` inside row 3, whose own item roots are hosts UNDER that
	    row's host — the case D6a's translate stop is argued for and no fixture drove.
	  * `WIDE_LABELS = 420` labels at ONE (font,size) on a ~900-node tree, so a learned
	    word names far more than `max(64, nodes // 8)` and the OVER-CAP PROBE route
	    (D3c/D6c, and RED-TEAM C-1's compact refusal) actually runs.
	  * a paragraph of `VOCAB = 1_200` distinct words, past `COLLECT_CAP`'s 1,024, set
	    on a SETTLED surface — the shape D6d's overflow queue exists for and the one
	    the parent commit drops the tail of.
	  * a NUMERIC label, which is what every HUD actually draws and what the D6c live
	    drive found the word index blind to.
	  * a `Button` with a `compactLabel` in a box that shrinks — the compact ladder,
	    whose stale `mTextW` is RED-TEAM C-1.
]]
local WIDE_ROWS = 96
local WIDE_LABELS = 420
local VOCAB = 1200

local function buildWide(view: any, inline: boolean, tag: string)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = view.w, h = view.h })
	env:set("displaySize", view.displaySize)
	env:set("preferredInput", view.input)

	local items = {}
	local rowValue = {}
	for i = 1, WIDE_ROWS do
		rowValue[i] = core:signal(`{tag}r{i}`)
		items[i] = { id = `k{i}`, n = rowValue[i], nested = i == 3 }
	end
	local rows = core:signal(items)
	local nextId = WIDE_ROWS + 1
	local banner = core:signal(true)
	local numeric = core:signal(1234)
	local paragraph = core:signal(`{tag}para`)
	local compactBox = core:signal(px(200))

	local nested = core:signal({ { id = "n1" }, { id = "n2" }, { id = "n3" } })

	local labels = {}
	for i = 1, WIDE_LABELS do
		labels[i] = UI.Text({ id = `L{i}`, textSize = 12, text = `{tag}w{i}` })
	end

	local bp = UI.VStack({
		id = "Root",
		padding = 0,
		gap = 0,
		width = fill(),
		height = fill(),
		children = {
			-- the branch ABOVE the list: dropping it moves every row below it
			UI.When({
				id = "Banner",
				condition = banner,
				thenView = function()
					return UI.HStack({
						id = "BannerRow",
						padding = 0,
						gap = 0,
						width = fill(),
						height = px(30),
						children = {
							UI.Text({ id = "BannerText", textSize = 12, text = `{tag}banner` }),
							UI.Box({ id = "BannerBox", width = px(10), height = px(6) }),
						},
					})
				end,
			}),
			UI.HStack({
				id = "Odd",
				padding = 0,
				gap = 2,
				width = fill(),
				height = px(28),
				children = {
					-- A NUMBER IS TEXT TOO (D6c): the label every HUD draws
					UI.Text({ id = "Num", textSize = 12, text = numeric }),
					-- ...and the compact ladder, in a box that shrinks under it
					UI.HStack({
						id = "CBox",
						padding = 0,
						gap = 0,
						width = compactBox,
						height = px(24),
						children = {
							UI.Button({ id = "Sub", label = "Subscribe", compactLabel = "Sub", textSize = 12 }),
						},
					}),
					UI.Text({ id = "Para", textSize = 12, text = paragraph }),
				},
			}),
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
									if item.nested
										then UI.VStack({
											id = "Nest",
											padding = 0,
											gap = 0,
											children = {
												UI.ForEach({
													id = "Sub",
													items = nested,
													key = function(inner: any)
														return inner.id
													end,
													row = function(inner: any)
														return UI.HStack({
															id = "Inner",
															padding = 0,
															gap = 1,
															height = px(8),
															children = {
																UI.Text({
																	id = "IT",
																	textSize = 12,
																	text = `{tag}{inner.id}`,
																}),
																UI.Box({ id = "IB", width = px(4), height = px(4) }),
															},
														})
													end,
												}),
											},
										})
										else UI.Box({ id = "Bar", width = px(10), height = px(6) }),
								},
							})
						end,
					}),
				},
			}),
			UI.VStack({ id = "Wide", padding = 0, gap = 0, width = fill(), children = labels }),
		},
	})
	local root = mountLib.mount(core, bp)
	local adapter = fake_target.new()
	if inline then
		adapter.answerTextInline(widthOf)
	end
	local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "coreSafeContent" })
	local notifies = 0
	controller.onSolved(function()
		notifies += 1
	end)
	return {
		core = core,
		env = env,
		controller = controller,
		adapter = adapter,
		rows = rows,
		items = items,
		rowValue = rowValue,
		banner = banner,
		numeric = numeric,
		paragraph = paragraph,
		compactBox = compactBox,
		enters = {},
		leaves = {},
		verdicts = {},
		takeId = function(): number
			nextId += 1
			return nextId
		end,
		notifyCount = function()
			return notifies
		end,
	}
end

-- the paragraph, past `COLLECT_CAP` in DISTINCT words. Built per tag so no two arms
-- share a word and the process-global exact-width store cannot answer one arm's
-- vocabulary from another's settle.
local function paragraphOf(tag: string): string
	local words = table.create(VOCAB)
	for i = 1, VOCAB do
		words[i] = `{tag}v{i}`
	end
	return table.concat(words, " ")
end

local function wideDrive(arm: any, label: string)
	arm.controller.refresh()
	drain(arm)
	table.insert(lines, statLine(arm, label))
	table.insert(lines, planLine(arm, label))
	table.insert(lines, snapshot(arm))
end

-- THREE VIEWS, not nine: this fixture is ~900 nodes and the axes it crosses are
-- viewport-independent by construction (a node count, a word count, a child count).
-- The nine-view sweep above is the one that answers viewport questions.
local WIDE_VIEWS = { device_views.VIEWS[1], device_views.VIEWS[4], device_views.VIEWS[5] }

for _, view in WIDE_VIEWS do
	for _, inline in { false, true } do
		local mode = if inline then "inline" else "queued"
		local tag = `{view.id}-{mode}-W-`
		local arm = buildWide(view, inline, tag)
		arm.controller.initialRender()
		if not inline then
			drain(arm)
		end
		wideDrive(arm, `WIDE|{view.id}|{mode}|settle`)

		-- insert: one row spliced into the middle of a hosted list
		local list = table.clone(arm.items)
		local addId = arm.takeId()
		table.insert(list, 40, { id = `k{addId}`, n = `{tag}added`, nested = false })
		arm.rows:set(list)
		wideDrive(arm, `WIDE|{view.id}|{mode}|insert`)

		-- remove: a row leaves ABOVE the nested one, so the host under a host moves
		local shorter = table.clone(list)
		table.remove(shorter, 2)
		arm.rows:set(shorter)
		wideDrive(arm, `WIDE|{view.id}|{mode}|remove`)

		-- reorder: the whole list reversed, which is the class D6a was built for
		local reversed = {}
		for i = #shorter, 1, -1 do
			table.insert(reversed, shorter[i])
		end
		arm.rows:set(reversed)
		wideDrive(arm, `WIDE|{view.id}|{mode}|reorder`)

		-- the branch above the list drops, and every row below it moves
		arm.banner:set(false)
		wideDrive(arm, `WIDE|{view.id}|{mode}|branch-off`)
		arm.banner:set(true)
		wideDrive(arm, `WIDE|{view.id}|{mode}|branch-on`)

		--[[ THE TEXT DRIVE, and it carries three of the four blind spots at once: a
			relabel that teaches a word at the key 420+ labels share (the over-cap probe
			route), a NUMERIC label moving, and the compact ladder's box shrinking until
			its button swaps forms. ]]
		arm.rowValue[7]:set(`{tag}RELABELLED`)
		arm.numeric:set(98765)
		arm.compactBox:set(px(40))
		wideDrive(arm, `WIDE|{view.id}|{mode}|text`)

		-- ...and the vocabulary, on a SETTLED surface: 1,200 distinct words at one key
		arm.paragraph:set(paragraphOf(tag))
		wideDrive(arm, `WIDE|{view.id}|{mode}|vocab`)

		arm.controller.dispose()
	end
end

local out = process.args[1] or "artifacts/text-reentry-differential.txt"
fs.writeFile(out, table.concat(lines, "\n") .. "\n")
print(`wrote {out} ({#lines} blocks)`)
