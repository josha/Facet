--!strict
--[[ THE DEEP STACK SCENE — one thousand identical rows under ONE stack, as a
	Facet fixture.

	IT IS THE SHAPE THE MEASURE SERVE IS ABOUT, and it is deliberately the opposite
	of `tests/lib/nameplates_scene`. That fixture is one `anchor` with 250 direct
	children, so its per-sibling bill is the ANCHOR branch's re-offer — which the
	anchor arrange arm already serves from each child's previous rect. A `vstack` has
	no such arm and cannot have one: a stack child's rect is a function of every
	sibling's measured extent (`fixedMain`, `fillWeightSum`, then the cursor), so the
	only thing that can be served on a stack path is the MEASURE, one node at a time.
	That is what `measure`'s node-resident serve does, and this is the tree that shows
	it: change one row's text and the other 999 are asked exactly the question they
	answered last solve.

	`Screen > VStack > 1000 x HStack{ Text, Text }` — 3,003 layout nodes. The row is
	an HStack rather than a leaf because a stack's arrange branch measures each
	non-hug child, so a row is measured TWICE per solve (its parent's measure pass
	and its parent's arrange pass) and a leaf under it is measured twice more. The
	call count this fixture is pinned on is therefore a multiple of the row count,
	not the row count.

	THE ROW WIDTH IS A SIGNAL AND THE ROW TEXT IS A SIGNAL, and they are two
	different dirt classes on purpose:

	  `scene.text(i, s)`  — a text write. Its measure closure covers the Text, the
	    row and every ancestor, so those are the nodes a serve must refuse; the rows
	    beside it are clean and are what the serve is counted on.
	  `scene.width(i, px)` — a `width` write on the ROW itself, which is
	    measure-classed too but changes the OFFER the row makes to its two children.
	    They are not in the dirty closure and are refused by the offer test instead,
	    which is the second of the serve's two gates and needs its own drive.
	  `scene.viewport(w, h)` — an `env:set` of a geometry fact, which is a FULL solve
	    with no reuse table at all. The serve must be structurally unreachable there,
	    and a fixture with no such drive cannot tell "refused" from "never asked".

	THE FOUR GATE ARMS (`scroll`, `composition`, `unquiet`, and the plain tree) exist
	so that each row of the publish table in `tests/measure_serve.spec.luau`'s header
	has a fixture that reaches it. They are opts on ONE scene rather than four scenes
	because the drives and the snapshot must be identical across them — a gate case
	that compares two different trees is comparing the trees. ]]
local UI = require("../../src/blueprint")
local mountLib = require("../../src/mount")
local environment = require("../../src/env/environment")
local renderer = require("../../src/render/renderer")
local customFactory = require("../../src/core/custom")
local fake_target = require("./fake_target")

local deep_stack_scene = {}

deep_stack_scene.ROWS = 1000
deep_stack_scene.NODES_PER_ROW = 3 -- the HStack and its two Texts
-- the row the four gate arms hang their shape on; see `Opts.scroll`
deep_stack_scene.GATE_ROW = 3

local function px(n: number): any
	return { type = "fixed", px = n }
end
local function fill(): any
	return { type = "fill", weight = 1 }
end

export type Opts = {
	viewport: { x: number, y: number, w: number, h: number }?,
	rows: number?,
	-- arm the fake target's op log (T12, default off per ruling A-11)
	ops: boolean?,
	incremental: boolean?, -- renderer.attach `incrementalLayout` (default true)
	measureReuse: boolean?, -- default true
	commitScope: boolean?, -- default true
	--[[ a `UI.ScrollView` inside ROW `GATE_ROW`, and the position is the whole point.
		`ctx.hasScroll` is published by the SCROLL NODE ITSELF, so the serve refuses any
		node whose subtree — itself included — holds one; a scroll at the TOP would gate
		only the root chain, which the dirty closure already excludes on every drive, and
		the arm would prove nothing. In a row that is measure-CLEAN on the drive, the
		gate is the only thing standing between that row and a serve. ]]
	scroll: boolean?,
	--[[ ...and the same shape for `ctx.compositions`, which feeds the PUBLIC
		`controller.compositionAt`: a `UI.Composition` in the same row, so the same
		clean-row argument applies, and `compositionAt` is compared as a public column
		beside the counts. ]]
	composition: boolean?,
	--[[ one row declares `aspect` on BOTH axes — `measureUncached` files a
		`measured`-stamped finding for it, which makes the NEXT solve's
		`ctx.measureQuiet` false and disarms the serve wholesale. It is the same
		fourth gate the anchor arrange arm carries and for the same reason: a finding
		is filed about a node inside the subtree a serve skips, and no tuple can carry
		it back. ]]
	unquiet: boolean?,
	--[[ ROW `GATE_ROW` holds a `fill`-height VStack, and its own height becomes a
		signal (`scene.height`). That is the shape the OFFER-HEIGHT half of the serve's
		same-question test exists for, and nothing else in this fixture has it: every
		other node here answers without reading the offered height, so `memoPlan` calls
		them height-free and the serve drops `maxH` from the test — correctly, and
		untestably. A VERTICALLY WRAPPING stack is one of `memoPlan`'s
		`HEIGHT_COUPLED_KINDS`, and the only one of the six that is not already gated
		by something else: a `scroll` and a `composition` are refused by the two
		bottom-up booleans, and a `grid`/`gridrow`/`fits` would drag a second mechanism
		into the fixture. Its measured WIDTH is a function of the offered HEIGHT —
		that is what a wrap is — so a drive that moves the ROW's height moves the offer
		its clean child is measured against without putting that child in the dirty
		set. Without the height half of the offer test, the child serves the width it
		had at the old offer and the oracle sees it: four 20x10 boxes are one column at
		40px of height and four columns at 10px. ]]
	coupled: boolean?,
	--[[ the LIST HUGS instead of filling, which is what makes a node asked at TWO
		offers per solve — the measure pass hands each row the screen's 1,280 and the
		arrange pass the list's resolved 300. That is the ordinary shape of real UI and
		the one the DEFAULT arm here does not have (a `fill` list's inner width IS its
		offer), so a spec that only drove the default could not tell a one-slot cache
		from a two-slot one. It is the arm that says the second slot exists. ]]
	hug: boolean?,
	--[[ ── THE ARMS T13'S CONTAINER MEMO ADDED (Plan C, 2026-09-05) ──────────────
		Each one is a container SHAPE the memo must refuse, or a drive that must move
		its key, and each is an opt on this one scene for the reason the four gate arms
		above already are: a gate case that compares two different trees is comparing
		the trees. ]]
	--[[ ROW `GATE_ROW` gains a `fill`-width child, which PASS 2 measures against its
		weighted share of what PASS 1 left. Its index is never written in PASS 1, so the
		fill pass re-measures it on EVERY tick — owed row 5, and the one arm that proves
		the memo did not quietly swallow a pass. ]]
	fill: boolean?,
	--[[ ...and a child declaring `shrinkWeight > 0`, which takes the whole container
		out of the memo (owed row 4): PASS 1.5 rebases `mainSum` against numbers the
		memo does not hold. The row is deliberately OVERFULL so the shrink pass is live
		rather than merely declared. ]]
	shrink: boolean?,
	--[[ ...and the same weight ARRIVING LATER, on a container that has already
		memoised at this offer (review round 3, SHOULD-FIX 3). `memoable = false` does
		not clear `hit`, so PASS 1.5 DOES run over a partly memo-served `mainSum` on
		that one tick — exact, because a served number equals the number HEAD's own
		PASS 1 would have produced for that index. This arm is what drives it. ]]
	shrinkLater: boolean?,
	--[[ ...and a NESTED stack (a plain VStack of four boxes, no wrap), so the memo is
		exercised on a container whose children are themselves containers rather than
		leaves — the shape every real row list has and the one `coupled` cannot be,
		because a wrapping stack is height-coupled on purpose. ]]
	nested: boolean?,
	--[[ ...and a `containerRelative` child, which C2 refuses on the container arm of
		its cache key and which the memo refuses for the same reason (owed row 6). ]]
	crel: boolean?,
	--[[ ...and A WIDTH ON `List` ITSELF, driven by a signal (`scene.listWidth`). It is
		the only drive in this fixture that moves the OFFER a memoising container hands
		its children without moving the viewport: the container is measure-dirty and
		every child is clean, so the memo's key is what has to refuse — and refill at
		the new offer on the same tick. Without it the offer half of the key would be
		exercised only by a viewport change, which is a full solve where the memo is
		unreachable and cannot be told from a refusal. ]]
	listWidth: boolean?,
	--[[ ...and the HEIGHT half of that key, with a child whose ANSWER READS IT. A
		vertically-wrapping stack's measured WIDTH is a function of the offered HEIGHT —
		four 20x10 boxes are one column at 40px and four columns at 10px — so this arm
		replaces the gate ROW with one, as a DIRECT child of `List`. It is the only
		shape on which dropping `mOffH` from the memo's key changes a rect rather than
		merely widening it: every other child here answers without reading the offer.
		Drive it with `scene.listHeight`. ]]
	coupledRow: boolean?,
	--[[ ...and the container shape that makes that drive REACH the memo: `List` HUGS on
		width and takes a signal-driven FIXED height. Both halves are needed and the run
		is what said so — a container whose width AND height are both fixed never has its
		content size computed at all, so `contentSize` is not entered, the memo never
		runs, and the case measures nothing. The width must want content; the height must
		be the thing the drive moves. ]]
	listHeight: boolean?,
	--[[ ...and the drive that moves the offered HEIGHT of a container whose children
		are CLEAN, which is the one shape the `mOffH` half of the memo's key can be
		witnessed on (review round 1, M-5). It is `List`'s own VERTICAL PADDING, driven
		by a signal: padding is measure-classed dirt on the container alone, and
		`contentSize` derives `innerMaxH` from `maxH - pt - pb`, so a write moves what
		every child is offered on the main axis while moving nothing else. Pair it with
		`coupledRow`, whose wrapping child's measured WIDTH is a function of the offered
		height — without a child that READS the offer, serving a stale answer produces
		the same number and the term is unfalsifiable. Nothing else in this fixture
		narrows a stack's height offer without a full solve, which is why the first
		version of this task recorded `mOffH` as an unreachable null. ]]
	listPad: boolean?,
	--[[ ...and A `text` DIRECT CHILD OF `List` (owed row 2). A `text` child publishes
		three verdict channels no cached number can carry, so it is refused — PER CHILD.
		The arm exists to show the OTHER thousand children still memoise around it,
		which is the difference between a lever that serves 96.8 % of a real flat list
		and one that serves 1.4 %: a real list splices labels straight into its own
		flow, so a container-level refusal takes the whole list down. ]]
	label: boolean?,
	--[[ ...and THE SPLICE (owed row 9, the id key's whole reason). A `UI.ForEach`
		region is the FIRST child of `List`, so an insert or a remove into the region
		shifts EVERY row's index in the layout node's spliced flat list while `List`'s
		own MOUNT children table stays the same OBJECT — `mount.luau` replaces the
		REGION's children, never its parent's. An index-keyed memo would serve
		`mMain[idx]` belonging to a different node; the id key is what refuses it.
		`recreate` is the second half of the same hazard: the same PATH with different
		content, which is a structural change and is covered only by
		`renderer.luau`'s `measureContains = dirtyContains` widening. ]]
	foreach: boolean?,
}

-- `layout` is the LAYOUT-NODE count (`stats().lastLayoutNodes`); `rows` is the
-- fixture's own row count. They are named apart for the reason
-- `nameplates_scene.Census` states: a census that shares a name with a different
-- count stops being a census.
export type Census = { mounted: number, layout: number, rows: number }

function deep_stack_scene.new(opts: Opts?)
	local o: Opts = opts or {}
	local n = o.rows or deep_stack_scene.ROWS
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", o.viewport or { x = 0, y = 0, w = 1280, h = 720 })

	local texts: { any } = {}
	local widths: { any } = {}
	local heights: { any } = {}
	local rowChildren: { any } = {}
	-- the weight that ARRIVES LATER (see `Opts.shrinkLater`) and the ForEach region's
	-- item list (see `Opts.foreach`), both signals so a drive can move them
	local shrinkOn = core:signal(0)
	local listWidth = core:signal(900)
	local listHeight = core:signal(700)
	local listPad = core:signal(0)
	local items = core:signal({ { key = "i1", kind = "box" }, { key = "i2", kind = "box" } })
	for i = 1, n do
		texts[i] = core:signal(`Row {i}`)
		widths[i] = core:signal(300)
		heights[i] = core:signal(18)
		local kids: { any } = {
			UI.Text({ id = "A", textSize = 14, text = texts[i] }),
			UI.Text({ id = "B", textSize = 12, text = `#{i}` }),
		}
		if o.scroll and i == deep_stack_scene.GATE_ROW then
			table.insert(
				kids,
				UI.ScrollView({
					id = "Scroll",
					axis = "y",
					width = px(40),
					height = px(16),
					children = { UI.Box({ id = "Deep", width = px(30), height = px(60) }) },
				})
			)
		end
		if o.composition and i == deep_stack_scene.GATE_ROW then
			table.insert(
				kids,
				UI.Composition({
					id = "Comp",
					arrangements = { "column" },
					laneGap = 4,
					groupGap = 4,
					width = px(60),
					height = px(16),
					groups = { { id = "main", lane = "main", sizing = "fill", minWidth = 20 } },
					children = {
						UI.Region({
							id = "Reg",
							group = "main",
							rank = 1,
							children = { UI.Box({ id = "In", width = px(20), height = px(10) }) },
						}),
					},
				})
			)
		end
		if o.coupled and i == deep_stack_scene.GATE_ROW then
			table.insert(
				kids,
				UI.VStack({
					id = "HC",
					wrap = true,
					gap = 0,
					width = { type = "content" },
					height = fill(),
					children = {
						UI.Box({ id = "c1", width = px(20), height = px(10) }),
						UI.Box({ id = "c2", width = px(20), height = px(10) }),
						UI.Box({ id = "c3", width = px(20), height = px(10) }),
						UI.Box({ id = "c4", width = px(20), height = px(10) }),
					},
				})
			)
		end
		if o.nested and i == deep_stack_scene.GATE_ROW then
			table.insert(
				kids,
				UI.VStack({
					id = "Nest",
					gap = 1,
					padding = 0,
					width = { type = "content" },
					height = { type = "content" },
					children = {
						UI.Box({ id = "n1", width = px(14), height = px(4) }),
						UI.Box({ id = "n2", width = px(10), height = px(4) }),
						UI.Box({ id = "n3", width = px(18), height = px(4) }),
						UI.Box({ id = "n4", width = px(12), height = px(4) }),
					},
				})
			)
		end
		if o.crel and i == deep_stack_scene.GATE_ROW then
			table.insert(
				kids,
				UI.Box({ id = "Crel", width = { type = "containerRelative", fraction = 0.1 }, height = px(10) })
			)
		end
		if o.unquiet and i == 1 then
			-- `aspect` on both axes is undefined and `measureUncached` says so with a
			-- `measured` stamp; see `Opts.unquiet`
			table.insert(
				kids,
				UI.Box({ id = "Bad", width = { type = "aspect", ratio = 2 }, height = { type = "aspect", ratio = 2 } })
			)
		end
		--[[ THE GATE SHAPES RIDE THE ROW ITSELF, not a box inside it, and that
			correction came from the run. `List` is the container whose PASS 1 loop the
			memo is about; a row declares a FIXED width and height, so a row's OWN
			content size is never computed and nothing inside it ever reaches a
			memoising loop. A `shrinkWeight` or a `fill` one level down therefore
			exercised neither gate — the counters were byte-identical to the plain arm,
			which is how it was caught. `scroll`/`composition`/`crel` are different and
			stay where they are: those three are SUBTREE booleans, so a child carries
			them up to the row, and the row is `List`'s direct child. ]]
		local isGate = i == deep_stack_scene.GATE_ROW
		if o.coupledRow and isGate then
			rowChildren[i] = UI.VStack({
				id = `R{i}`,
				wrap = true,
				gap = 0,
				padding = 0,
				width = { type = "content" },
				height = { type = "content" },
				children = {
					UI.Box({ id = "c1", width = px(20), height = px(10) }),
					UI.Box({ id = "c2", width = px(20), height = px(10) }),
					UI.Box({ id = "c3", width = px(20), height = px(10) }),
					UI.Box({ id = "c4", width = px(20), height = px(10) }),
				},
			})
			continue
		end
		rowChildren[i] = UI.HStack({
			id = `R{i}`,
			padding = 0,
			gap = 4,
			width = core:memo(function(use: any)
				return px(use(widths[i]) :: number)
			end),
			height = if o.coupled and isGate
				then core:memo(function(use: any)
					return px(use(heights[i]) :: number)
				end)
				elseif o.fill and isGate then fill()
				elseif o.nested and isGate then { type = "content" }
				else px(18),
			-- ...and the weight, on the row: `List` overflows its 720px by an order of
			-- magnitude with 1,000 rows, so PASS 1.5 is LIVE rather than merely declared
			shrinkWeight = if o.shrink and isGate
				then 1
				elseif o.shrinkLater and isGate then core:memo(function(use: any)
					return use(shrinkOn) :: number
				end)
				else nil,
			children = kids,
		})
	end

	--[[ THE REGION GOES FIRST, and that is the whole design of this arm: a region
		spliced BEFORE the rows means an insert into it shifts every row's index in the
		flat list the memo indexes, while `List`'s own mount children table — the one
		the carrier gate compares by identity — is untouched. A region AFTER the rows
		would shift nothing and the fixture would be a witness to nothing. ]]
	local listChildren: { any } = {}
	if o.foreach then
		table.insert(
			listChildren,
			UI.ForEach({
				id = "F",
				items = items,
				key = function(item: any)
					return item.key
				end,
				row = function(item: any)
					if item.kind == "text" then
						return UI.Text({ id = "Item", textSize = 12, text = item.key })
					end
					return UI.Box({ id = "Item", width = px(24), height = px(8) })
				end,
			})
		)
	end
	for idx, row in rowChildren do
		table.insert(listChildren, row)
		if o.label and idx == deep_stack_scene.GATE_ROW then
			-- a LABEL between the rows: `List`'s own direct child, and a `text` node,
			-- so the memo must refuse it on every tick while its 999 siblings serve
			table.insert(listChildren, UI.Text({ id = "Label", textSize = 12, text = "section" }))
		end
	end
	local bp = UI.Screen({
		id = "S",
		children = {
			UI.VStack({
				id = "List",
				padding = if o.listPad
					then core:memo(function(use: any)
						local v = use(listPad) :: number
						return { top = v, right = 0, bottom = v, left = 0 }
					end)
					else 0,
				gap = 2,
				width = if o.listWidth
					then core:memo(function(use: any)
						return px(use(listWidth) :: number)
					end)
					elseif o.hug or o.listHeight then { type = "content" }
					else fill(),
				height = if o.listHeight
					then core:memo(function(use: any)
						return px(use(listHeight) :: number)
					end)
					else { type = "content" },
				children = listChildren,
			}),
		},
	})

	local root = mountLib.mount(core, bp)
	local adapter = fake_target.new({ ops = o.ops == true })
	local controller = renderer.attach(core, root, env, adapter, {
		rootPolicy = "edgeToEdge",
		incrementalLayout = o.incremental ~= false,
		measureReuse = o.measureReuse ~= false,
		layoutNodeReuse = true,
		commitScope = o.commitScope ~= false,
		translateHosts = true,
	})
	controller.initialRender()

	local scene: any = {
		core = core,
		env = env,
		adapter = adapter,
		controller = controller,
		rows = n,
	}

	-- the MEASURE-class drive on a LEAF: one row's first label
	function scene.text(i: number, value: string)
		texts[i]:set(value)
		controller.refresh()
	end

	-- ...and the MEASURE-class drive on the ROW ITSELF, which moves the offer its
	-- two children are measured against (see the header)
	function scene.width(i: number, value: number)
		widths[i]:set(value)
		controller.refresh()
	end

	--[[ ...and the drive that moves a CLEAN node's offered HEIGHT: the gate row's own
		height, which its `fill` child is measured against (see `Opts.coupled`). It
		dirties the ROW and never the child, so the serve's offer test is the only
		thing standing between that child and a stale size. Off the `coupled` arm the
		signal is bound to nothing and the refresh solves nothing, which is what makes
		it safe to drive on every arm of an oracle. ]]
	function scene.height(i: number, value: number)
		heights[i]:set(value)
		controller.refresh()
	end

	--[[ ...and the weight that ARRIVES on a container that has already memoised
		(`Opts.shrinkLater`). `0` is the documented "never shrinks" value and is not a
		member of the shrink pass, so the tick that writes a positive weight is the
		first tick this container is un-memoable — with a key that still MATCHES. ]]
	function scene.shrinkOn(value: number)
		shrinkOn:set(value)
		controller.refresh()
	end

	--[[ ...and the CONTAINER'S OWN WIDTH (`Opts.listWidth`), which is the offer every
		one of its thousand clean children is measured against. The container is
		measure-dirty on this drive and no child is, so the memo's `mOffW` term is the
		only thing standing between those children and an answer measured at a width
		that no longer exists. ]]
	function scene.listWidth(value: number)
		listWidth:set(value)
		controller.refresh()
	end

	-- ...and the HEIGHT the same container offers, which only a child that READS the
	-- offered height can see (`Opts.coupledRow`)
	function scene.listHeight(value: number)
		listHeight:set(value)
		controller.refresh()
	end

	--[[ ...and the container's own VERTICAL PADDING (`Opts.listPad`), which is the one
		drive here that narrows what its children are offered on the MAIN axis while
		leaving every one of them clean. See `Opts.listPad` for why the pair with
		`coupledRow` is what makes it observable. ]]
	function scene.listPad(value: number)
		listPad:set(value)
		controller.refresh()
	end

	--[[ ...and the SPLICE (`Opts.foreach`): an insert or a remove into the region that
		sits before the rows, which shifts every later index in the layout node's flat
		child list without touching `List`'s own mount children table. ]]
	function scene.insertItem(key: string)
		scene.insertItemKind(key, "box")
	end

	--[[ ...and the same insert with a CHOSEN KIND, which is how the SAME PATH ends up
		holding DIFFERENT CONTENT: remove a key and re-add it in the other form, and the
		reconciler destroys and re-creates at the identical path (`solver.Node.id` is
		`node.path`, so the memo's id key cannot tell the two apart). What refuses the
		stale number is not the key — it is that both ticks are STRUCTURAL, and a
		structural solve widens `measureContains` to the whole `dirtyContains` set. ]]
	function scene.insertItemKind(key: string, kind: string)
		local next: { any } = {}
		for _, item in items:get() :: any do
			table.insert(next, item)
		end
		table.insert(next, 1, { key = key, kind = kind })
		items:set(next)
		controller.refresh()
	end

	function scene.removeItem(key: string)
		local next: { any } = {}
		for _, item in items:get() :: any do
			if item.key ~= key then
				table.insert(next, item)
			end
		end
		items:set(next)
		controller.refresh()
	end

	--[[ ...and THE SAME PATH WITH DIFFERENT CONTENT — a keyed row whose CLASS changes,
		which the reconciler serves by destroying and re-creating at the identical path.
		`solver.Node.id` is `node.path` (`layout_node.luau`), so the memo's id key CANNOT
		see this: what refuses it is that a structural change widens
		`measureContains` to the whole `dirtyContains` set (`render/renderer.luau`), so
		the re-created child is measure-dirty and the skip arm never fires for it. ]]
	function scene.swapKind(key: string, kind: string)
		local next: { any } = {}
		for _, item in items:get() :: any do
			table.insert(next, if item.key == key then { key = item.key, kind = kind } else item)
		end
		items:set(next)
		controller.refresh()
	end

	-- ...and the geometry drive, which is a FULL solve with no reuse table
	function scene.viewport(w: number, h: number)
		env:set("viewportRect", { x = 0, y = 0, w = w, h = h })
		controller.refresh()
	end

	function scene.census(): Census
		local mounted = 0
		local function walk(node: any)
			mounted += 1
			for _, child in node.children do
				walk(child)
			end
		end
		walk(root.node)
		local st = controller.stats() :: any
		return { mounted = mounted, layout = st.lastLayoutNodes, rows = n }
	end

	function scene.stats(): any
		return controller.stats()
	end

	--[[ every live node's rect and every per-path fact the commit walks own — the
		same columns as `nameplates_scene.snapshot()`, including the `pos == sro`
		identity, because an oracle over this fixture is asking the identical
		question: did an optimisation that skips work change anything a reader can
		see? Copied rather than shared: the two fixtures' snapshots are pinned by
		different specs and a shared serializer would make one file's pin a function
		of the other file's tree. ]]
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

	function scene.snapshot(): string
		local out = {}
		local diag = controller.diagnostics()
		local diagKeys = {}
		for _, finding in diag do
			table.insert(diagKeys, `{finding.node}:{finding.issue}`)
		end
		table.sort(diagKeys)
		local diagKey = table.concat(diagKeys, ";")
		for path, node in adapter.liveNodes() do
			local props = {}
			for k, v in node.props or {} do
				table.insert(props, `{k}={ser(v, 6)}`)
			end
			table.sort(props)
			local r, hit, region = node.storedRect, node.hitRect, node.scrollRegion
			local pp, ps = node.presentedPosition, node.presentedSize
			local sro = controller.screenRectOf(path)
			local posOk = pp == nil or sro == nil or (pp.x == sro.x and pp.y == sro.y)
			table.insert(
				out,
				`{path}|{fmtRect(r)}|{table.concat(props, ",")}`
					.. `|vis={tostring(node.visible)}`
					.. `|hit={fmtRect(hit)}`
					.. `|canvas={if region then `{region.contentW},{region.contentH}` else "-"}`
					.. `|pos={if pp then `{pp.x},{pp.y}` else "-"}`
					.. `|psize={if ps then `{ps.w},{ps.h}` else "-"}`
					.. `|focus={tostring(node.focused)},{tostring(node.focusProfile)},{tostring(node.focusLift)}`
					.. `|ro={fmtRect(controller.rectOf(path))}`
					.. `|sro={fmtRect(sro)}`
					.. (if posOk then "" else "|POSMISMATCH")
			)
		end
		table.sort(out)
		table.insert(out, `diagKey={diagKey}`)
		return table.concat(out, "\n")
	end

	--[[ ...AND THE PUBLIC COMPOSITION READ, which is row 4 of the publish table and
		the one channel with a public reader. It is part of the oracle's compare on
		the composition fixture and answers `-` everywhere else, so a single column
		serves both arms. ]]
	function scene.compositionKey(path: string): string
		local ok, dump = pcall(controller.compositionAt, path)
		if not ok or dump == nil then
			return "-"
		end
		local parts = {}
		for _, region in (dump :: any).regions or {} do
			table.insert(parts, `{region.id}:{fmtRect(region.rect)}:{tostring(region.group)}`)
		end
		table.sort(parts)
		return `{(dump :: any).arrangement}|{table.concat(parts, ";")}`
	end

	function scene.dispose()
		controller.dispose()
		root.dispose()
	end

	return scene
end

return deep_stack_scene
