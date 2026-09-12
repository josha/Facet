--!strict
--[[ THE MEASURE SEAM: a mounted node becomes a `solver.Node`.

	`toLayoutNode` is the ONE translation from the mounted graph (classes, props,
	modifiers) into the pure layout tree the solver measures and arranges. It is
	engine-free and depends on nothing the renderer owns: every input arrives as an
	argument (the node, the active ThemeSnapshot, the typography scale, the
	PreferredTextSize reservation offset, the parent axis, the clipper flag) and the
	result is data. That is what let it leave `render/renderer.luau` unchanged.

	Also here, because they are the SAME decision seen from the measure side:
	`compactForm` (the authored compact-label grammar, normalized once) and
	`drawnButtonText` (what a Button's engine text node actually shows). The
	renderer re-exports both as `renderer.compactForm` / `renderer.drawnButtonText`
	— the public names did not move — and `effectiveHitFloor`, which the renderer's
	hit-rect pass spends as real geometry.

	Public interface:
	  layout_node.toLayoutNode(node, metrics, textScale, prefOffset, parentAxis?, insideClipper?, store?, insideControl?) -> solver.Node
	  layout_node.compactForm(props) -> { kind, ... }?
	  layout_node.drawnButtonText(props, compact?) -> string
	  layout_node.effectiveHitFloor(class, metrics) -> number?

	WHY IT IS ITS OWN FILE. Roblox refuses a `Script.Source` assignment at 200,000
	characters or more, and every LIVE path is a write — the Rojo plugin,
	`execute_luau`, any plugin — so a module over the cap silently stops syncing
	into an open Studio session and a live check against it then tests the code
	baked into the place rather than the edits on disk. `renderer.luau`
	was 242,943 characters; this is the first of two seams taken to get it under.

	Depends on: layout/solver (the Node type), themes/snapshot (metric and
	typography resolution), themes/package (icon glyphs), tokens/chrome_slots,
	class_contract (the declared hit floors), blueprint_schema.
]]

local solver = require("../layout/solver")
local text_metrics = require("../layout/text_metrics")
-- the ONE reading of the `textSize = "fit"` grammar, shared with the schema's
-- acceptance check and with the paint seam (`render/commit_walks.textScale`)
local textFit = require("../layout/text_fit")
local themeSnapshot = require("../themes/snapshot")
local themePackage = require("../themes/package")
local chrome_slots = require("../tokens/chrome_slots")
local controlContract = require("../class_contract")
local schema = require("../blueprint_schema")
-- the ARRANGEMENT facts (breakpoints, card widths, the content lane's measure):
-- pure numbers a package cannot move, read here so the display class and the
-- declaration meet in one place. See `adaptive.LANE_MEASURE`.
local adaptive = require("../layout/adaptive")
-- the ONE predicate that decides which nodes are real engine parents, and which of
-- those are COORDINATE SPACES (Plan C, C1) — asked here as well as in
-- `renderer.ensureTree`; see `hostSpaceOf` below for why both ask
local instance_boundary = require("./instance_boundary")

local layout_node = {}

-- drawnButtonText(props): what a Button's own engine text NODE shows.
--
-- ONE decision, TWO seams — the measure seam below (`toLayoutNode`) and the
-- paint seam (`applyProp`) — for the reason the toggle row's padding is one
-- function: a box reserved for one string and drawn with another is the defect
-- class this file has been bitten by repeatedly.
--
-- With an `icon`, the drawn mark is the FRAMEWORK'S ASCII-safe glyph for that
-- semantic name and `label` stays the semantic name only (exactly as it already
-- does for a content button). That order is the semantic-icon tofu fix applied to a
-- public prop: the legible character is in the tree from the first frame and NO
-- resolution has to succeed for it to render — a package that ships art for the
-- name simply has the adapter paint the picture over it.
-- compactForm(props): the normalized compact representation, or nil.
--   { kind = "text",  text = "Ed" }
--   { kind = "icon",  icon = "edit", glyph = "/" }
--   { kind = "image", image = "rbxassetid://…" }
-- PURE, and the ONE place the authored grammar (a bare string or a one-key
-- table) becomes a shape the rest of the pipeline reads. Every consumer — the
-- measure seam, the paint seam and the adapter — goes through this, so the
-- grammar is spelled out exactly once.
local function compactForm(props: any): any
	local raw = if type(props) == "table" then props.compactLabel else nil
	if type(raw) == "string" then
		-- the bare-string sugar has nowhere to put a modifier, so it is always a
		-- degrade. Stated rather than left `nil` so every form this function
		-- returns has the same shape.
		return { kind = "text", text = raw, prefer = false }
	end
	if type(raw) ~= "table" then
		return nil
	end
	-- the ONE modifier the grammar carries (blueprint_schema COMPACT_MODIFIERS):
	-- it names no content, so it rides ALONGSIDE whichever form was declared
	-- rather than being one of them.
	local prefer = raw.prefer == true
	if type(raw.text) == "string" then
		return { kind = "text", text = raw.text, prefer = prefer }
	end
	if type(raw.icon) == "string" then
		-- the glyph is the FLOOR, chosen the same way an `icon` button's is: a
		-- legible ASCII character is in the tree from the first frame and no
		-- resolution has to succeed for it to render. Theme art (a package's, or
		-- now the framework's own) paints OVER it.
		return { kind = "icon", icon = raw.icon, glyph = themePackage.iconGlyph(raw.icon), prefer = prefer }
	end
	if type(raw.image) == "string" then
		return { kind = "image", image = raw.image, prefer = prefer }
	end
	return nil
end

-- drawnButtonText(props, compact): what a Button's own engine text NODE shows.
-- `compact` is the SOLVER's verdict for this node on this solve — see
-- `commit_walks.textVerdicts` below.
local function drawnButtonText(props: any, compact: boolean?): any
	if compact == true then
		local form = compactForm(props)
		if form ~= nil then
			if form.kind == "text" then
				return form.text
			end
			-- an icon form draws its ASCII glyph and lets theme art cover it; a
			-- name the framework does not know has no glyph, so the full label is
			-- still the honest thing to draw.
			if form.kind == "icon" then
				return form.glyph or (props :: any).label
			end
			-- an IMAGE form has no name, so there is no glyph to fall back to and
			-- nothing legible to say: the picture IS the content. This asymmetry
			-- is why `icon` is the documented recommendation and `image` is the
			-- escape hatch — only one of them degrades.
			if form.kind == "image" then
				return ""
			end
		end
	end
	local icon = if type(props) == "table" then props.icon else nil
	if type(icon) == "string" then
		return themePackage.iconGlyph(icon) or props.label
	end
	return (props :: any).label
end

-- textScale is the env typographyScale (input-paradigms expansion, matrix D.1):
-- geometry-affecting text sizes are multiplied at the MEASURE seam here so the
-- solver reserves the scaled box; the same factor is applied at the PAINT seam
-- (`commit_walks.textScale`) so layout and paint agree. Only sizes that ALSO reach
-- paint (an explicit props.textSize) are scaled — intrinsic control defaults
-- stay as the adapter draws them, so the two seams never diverge.
-- prefOffset (platform verifier F1/F2, 2026-07-23): the engine renders the
-- player's PreferredTextSize as a FIXED PIXEL OFFSET on top of every text
-- node — including intrinsic default sizes — so the measure seam ADDS the
-- reservation offset to EVERY text node (explicit and default). Paint never
-- includes it (the engine applies its own offset at draw time).
-- parentAxis is the enclosing stack's main axis ("y" | "x" | nil). Only Divider
-- reads it, to infer its orientation (A-LV3), so the same declaration is a
-- horizontal hairline in a VStack and a vertical one in an HStack.
-- `metrics` is the active ThemeSnapshot: THE resolution point for
-- semantic metric names. A prop that names a role/step/metric path becomes a
-- number here, on every solve, which is exactly why a theme swap moves geometry
-- without touching the mounted graph. A literal number passes through untouched
-- and is thereby explicitly theme-independent.
-- a label with no whitespace: one word, and therefore nothing the engine may
-- legally break. Numbers count as words. See the Button branch below.
-- AN OFFSET MAY BE A FRACTION OF THE PARENT. A
-- number or a metric name resolves to px here, exactly as it always did; the
-- `{ scale, offset }` form CANNOT — the extent it is a fraction of is only known
-- at arrange — so it passes through as data with its px part resolved, and the
-- solver spends it against the anchor's inner box. That split is what keeps a
-- marker overlay's update an arrange-only write: a dot moving from u = 0.2 to
-- u = 0.6 re-arranges, it never re-measures and never remounts.
local function resolveOffset(metrics: any, raw: any): any
	if type(raw) == "table" then
		return { scale = raw.scale, offset = themeSnapshot.resolveNumber(metrics, raw.offset) }
	end
	return themeSnapshot.resolveNumber(metrics, raw)
end

--[[ THE FOUR FIELDS A PLACEMENT PROP DECIDES, in one place (Plan C, T5).

	`toLayoutNode`'s node literal used to carry these inline. They were lifted out
	for a reason with teeth: `render/translate_lane` re-places a coordinate-space
	host WITHOUT running a build at all, and the classifier therefore never marks
	that node dirty — so the next build serves it out of the warm store UNCHANGED.
	If the lane wrote a different set of fields from the build, the store would
	hand back a node carrying last frame's `offsetX` behind a rect that had moved,
	and the first solve that touched it for any other reason would snap the host
	back. One function called by both sides is what makes that impossible to get
	wrong by omission.

	`placementProps` is "this node carries at least one placement prop", derived
	from all NINE because every one of the values is in hand here. It is what makes
	the parent-side inert-placement audit (§2.1) affordable in the arrange path: the
	overwhelming majority of nodes carry none, and the audit's per-child cost for
	them is this ONE field test rather than nine table lookups. Measured: the
	per-lookup form cost +1.5-2.4 % on the 100-cell perf aggregate against a
	0.31-0.65 % same-arm floor.

	`layoutPriority`/`shrinkWeight` are in that set because they are placement props
	exactly like the other seven — only a stack's shrink pass reads either one — and
	were missing from it and from the solver's own table until the Milestone-1
	review (C2). THIS TEST IS THE AUDIT'S ONLY GATE: a prop absent here is unpoliced
	however complete `PLACEMENT_PROPS` is.

	WHAT THE LANE MAY AND MAY NOT SPEND THIS ON. It writes VALUES; it never writes a
	presence flip. `placementProps` and the parent's `inertPlacement` audit both
	move when a prop appears or disappears, and `inertPlacement` lives on the
	PARENT, which this function cannot reach — so the lane refuses a write whose old
	or new value is `nil` and hands it to the solve. ]]
local function applyPlacement(layoutNode: any, props: any, metrics: any)
	layoutNode.anchor = props.anchor
	layoutNode.offsetX = resolveOffset(metrics, props.offsetX)
	layoutNode.offsetY = resolveOffset(metrics, props.offsetY)
	layoutNode.placementProps = (
		props.anchor ~= nil
		or props.offsetX ~= nil
		or props.offsetY ~= nil
		or props.alignH ~= nil
		or props.alignV ~= nil
		or props.lineAlign ~= nil
		or props.gridSpan ~= nil
		or props.layoutPriority ~= nil
		or props.shrinkWeight ~= nil
	) or nil
end

--[[ stampContentTermsFacts(dim, textScale, prefOffset) -> dim — the ONE seam
	`{ type = "content", lines = n }` (framework-gaps-phase2 gap 3) needs OUTSIDE
	the solver, for the exact reason `textOf` above needs `prefOffset` outside
	it: `resolveDim` only resolves METRIC NAMES against the theme snapshot, and
	the snapshot's OWN `preferredText.offset` is the value it was resolved with
	— not necessarily the LIVE `env:get("preferredTextOffset")` this solve is
	running with. The renderer re-reads `prefOffset` fresh every solve
	(`preferredTextOffset` is a fast-changing fact kept OUT of `themeMetrics` on
	purpose, so an accessibility nudge does not re-resolve the whole snapshot);
	`toLayoutNode` already carries that live number for every text node's
	`textFit.offset` and `reservedSize` call, and a content-terms `lines` dim
	is exactly the same "predict a text box" question `text.lineBox` answers,
	so it takes the same live number rather than reading the snapshot's stale
	one. `rows`/`of` need nothing here: `of` is an ordinary metric name — no
	text-preference component — so `resolveDim`'s own resolution is already the
	whole story, which is why the solver's `contentTermsPx` (`../layout/solver`)
	reads `d.of` unchanged and `d.scale`/`d.textOffset` only for `lines`. ]]
local function stampContentTermsFacts(dim: any, textScale: number, prefOffset: number): any
	if type(dim) == "table" and dim.type == "content" and (dim :: any).lines ~= nil then
		local out = table.clone(dim)
		out.scale = textScale
		out.textOffset = prefOffset
		return out
	end
	return dim
end

local function isSingleWord(label: any): boolean
	if type(label) == "number" then
		return true
	end
	return type(label) == "string" and label ~= "" and string.find(label, "%s") == nil
end

-- THE EFFECTIVE TARGET FLOOR for a class, or nil when it declares none. The
-- CONTRACT (src/class_contract.luau) is the source of truth for WHETHER a
-- class has a floor, so adding a focusable control gets it enforced; the THEME
-- owns the VALUE, and floors clamp UP only — a package may
-- enlarge a touch target, never shrink one below what the control declared.
--
-- ONE reading, two readers: `toLayoutNode` carries it into the solve so the
-- result can name its interactive rects (large-text accessibility diagnostics), and `pushHitRects`
-- spends the same number as real hit geometry. They were two copies of this
-- arithmetic for exactly one commit.
local function effectiveHitFloor(class: string, metrics: any): number?
	local c = controlContract.forClass(class)
	local declared = if c ~= nil then c.minHitSize else nil
	return if declared ~= nil then math.max(declared, metrics.targetSizes.minimum) else nil
end

-- THE CIRCLE IS A SOLVER FACT (feature round 2026-07-26 on Button; GENERALIZED
-- to ZStack, task PAINT 2026-08-27, director items 11/12). `shape = "circle"`
-- promises a TRUE 1:1 box and promises the author never computes it, so the
-- square is enforced HERE, through the dimension vocabulary that already
-- expresses "this axis follows that one": `aspect` with ratio 1. Nothing new
-- lands in the solver, and the pairing therefore inherits every fix that
-- vocabulary already has (including `aspect` + `fill`, which used to measure
-- 0x0 — found live 2026-07-24).
--
-- ONE authored axis drives the other; NEITHER authored means the control
-- metric (`controls.button.height`), resolved from the live snapshot so a
-- metric package resizes the shape and a pixel package snaps it. BOTH
-- authored is refused at the blueprint boundary (`assertCircleSquare`), so
-- this branch can never have to pick a winner. Shared by every class that
-- reaches `shape = "circle"` rather than copied per class — the Button and
-- ZStack call sites below are identical on purpose.
local function applyCircleShape(layoutNode: any, props: any, metrics: any)
	if props.shape ~= "circle" then
		return
	end
	if layoutNode.width == nil and layoutNode.height == nil then
		layoutNode.width = { type = "fixed", px = themeSnapshot.circleDiameter(metrics) }
	end
	if layoutNode.height == nil then
		layoutNode.height = { type = "aspect", ratio = 1 }
	elseif layoutNode.width == nil then
		layoutNode.width = { type = "aspect", ratio = 1 }
	end
end

--[[ the coordinate-space decision, through the ONE predicate that owns it — AND IT
	IS THE MEMO THAT ANSWERS, NEVER THE BRANCH (RED-TEAM F1).

	`createOptsFor` is asked for two different things at once: WHICH ENGINE OBJECT to
	create (its return value, a create-time fact the adapter spends once) and WHETHER
	THIS NODE IS A COORDINATE SPACE (`node.hostSpace`, a fact fixed for the node's
	life). Reading the space off the RETURN tied the second to the first, and the two
	come apart the moment a presentation prop arrives LATE: a row memoised `true` by
	the D6a trigger that later gains an `opacity`/`canvasGroup`/`scale`/`rotation`
	takes an early return carrying `{ canvasGroup = true }` or `{ instanceHost = true }`
	— correct answers to the FIRST question, and silent on the second.

	The consequence is a live divergence and not a tidiness point, because the two
	readers read different fields: `renderer.livePaths` reads the mounted node's memo
	(`geometry.spaceHosts[node.path] = node.hostSpace`) and the adapter's host entry is
	LATCHED at create, while `layout/solver` and `layout/translate_arm` read the layout
	node this function fills in. Answer `nil` here and the solver stores the row's whole
	subtree ABSOLUTELY under a parent both the adapter and the renderer still call a
	coordinate space — so `rect_reads` composes the host origin onto an absolute rect
	and every child of that row reports, and paints, one host origin too far. That is
	the exact failure the `hostSpace` field's own comment below names.

	MEASURED, not reasoned: `tests/host_space_memo.spec.luau`'s reverse-order cases
	drive `nil -> 0.5` on all three props and read `/Row/Bar` at y=124 where its
	unfaded control reads y=62 — one 62px host origin, twice.

	So this asks the predicate (which is what MAKES the decision, first-answer-wins)
	and then reads the decision. Every path through `createOptsFor` writes the field,
	which is what makes the read total; `translateHosts = false` and a props-less node
	leave it `false`/absent and behave exactly as they did. ]]
local function hostSpaceOf(node: any, attachOpts: any): boolean?
	instance_boundary.createOptsFor(node, attachOpts)
	return if node.hostSpace == true then true else nil
end

--[[ ── THE PER-INDEX CHILD PATCH (Plan D, D2a — ruling A-9, deferred in Plan C for
	scope and not for soundness) ─────────────────────────────────────────────────

	T15's kept-children array refuses on every LEAF edit BY CONSTRUCTION: `store.dirty`
	is ancestor-closed, so every container on the dirty chain holds a dirty child and
	the scan below falsifies the arm. The container then rebuilds a fresh array and
	re-visits EVERY child — 1,126 warm store hits on `battle_hud L updateItem-hp`,
	0.146 ms of a 0.364 ms class (FacetBench §D1/§D2). These two helpers are the third
	arm: keep the array's VALUES and re-run `toLayoutNode` only at the indices whose
	child is in `store.dirty`.

	THE INDEX IS OVER THE SPLICED FLAT LIST, never over `node.children`. `appendChild`
	splices `When`/`ForEach`/`ErrorBoundary` grandchildren into the parent's flow, and
	on every arena workload the thousand-child loop IS such a splice — a container
	holding one `UI.ForEach` — so an index over the mount children would be an index
	over one region and would reach nothing.

	WHAT VALIDATES THE COPY, in three layers, none of which walks the children:
	  1. the container's own children table, compared by IDENTITY by the caller's gate
	     (`prior.kids == node.children`) — the same term the kept array rides;
	  2. each spliced REGION's children table, compared by identity AND length here.
	     That pair is exact: `mount.luau` replaces a region's array wholesale at `:450`,
	     `:218` and `:234` (identity moves) and mutates it IN PLACE only by
	     `table.remove` at `:197` and `:465` (length moves). There is no in-place
	     insertion or replacement anywhere in the mount layer, so identity+length sees
	     every writer;
	  3. on the pass that BUILDS the index a stronger check is available for free —
	     `store.byNode[child].built` must be the very layout node standing at that
	     position — so the FIRST patch of an array verifies every slot against the
	     array it is about to copy, and later patches verify the regions alone.

	WHY THE REGION'S OWN DIRT CANNOT BE THE GATE. `renderer`'s `markDirtyIn` climbs
	path prefixes, so a dirty grandchild always marks its region's path too: refusing
	on "a region under me is dirty" would refuse on exactly the shape this arm exists
	for. What distinguishes a region whose CONTENT moved is a `pushDirty(path,
	"structure")`, which makes the refresh structural, which makes `build`'s `collect`
	true, which the caller's `store.builtIds == nil` term already refuses — and layer 2
	is the belt to that braces, exact on its own and independent of the renderer's
	structural routing (so the `structuralReuse = false` arm is covered too). ]]
local function indexKids(node: any, childArray: { any }, store: any): ({ [string]: number }?, { any }?, { any }?)
	local index: { [string]: number } = {}
	local mounts: { any } = {}
	-- flat triples: the region NODE, the children table it had, and that table's
	-- length. Re-read and compared on every later patch of this array.
	local regions: { any } = {}
	local n = 0
	local ok = true
	local function visit(child: any)
		if child.class == "When" or child.class == "ForEach" or child.class == "ErrorBoundary" then
			local kids = child.children
			regions[#regions + 1] = child
			regions[#regions + 1] = kids
			regions[#regions + 1] = #kids
			for _, grandchild in kids do
				visit(grandchild)
			end
		else
			n += 1
			local entry = store.byNode[child]
			-- layer 3: the position holds the layout node THIS mounted child produced
			if entry == nil or entry.built ~= childArray[n] then
				ok = false
			end
			index[child.path] = n
			mounts[n] = child
		end
	end
	for _, child in node.children do
		visit(child)
	end
	if not ok or n ~= #childArray then
		return nil, nil, nil
	end
	return index, mounts, regions
end

--[[ THE FLOOR UNDER THE PROBE BUDGET BELOW, and under `layout/stack`'s twin (Plan D,
	D3b). The dirty set's IRREDUCIBLE size on the shape both arms exist for is the
	edited leaf's ancestor chain — the tree's depth, never its width — so the budget has
	to clear a realistic depth before it starts refusing, or every small container in a
	deep tree refuses the very tick the arm was built for. 64 is the same "small enough
	not to bother" constant `render/text_index`'s push cap already spends, an order of
	magnitude above any UI depth and an order of magnitude below the wide-push dirt sets
	this bounds (2,002 on the D3b sweep). ]]
local DIRT_PROBE_FLOOR = 64

--[[ THE INDICES TO REBUILD, or `nil` for "refuse and take the full pass". The dirty
	SET is walked, not the children: on a one-leaf edit it is the ancestor chain, so
	this is O(depth) per container where the loop it replaces is O(children). The
	output budget bounds the other direction — a dirt set wider than a quarter of the
	array rebuilds most of it anyway, and paying the scan on top of the full pass is one
	way this arm could cost more than it saves.

	── AND THE WALK IS BOUNDED BY A PROBE BUDGET, NOT BY TRUST (Plan D, D3b) ─────────
	The output budget above bounds what this returns; it does not bound what it READS.
	`store.dirty` is the whole pass's dirt, not this container's share of it, so a WIDE
	push — 1,000 settled text leaves arriving at once, ~2,000 dirty entries — made every
	one of the 1,000 rebuilt row containers walk all 2,000 to find its own one: O(dirty
	x containers), and the D3b cutoff sweep read the push route at 62.6 ms against the
	pre-D2 base's 24.2. The arena's ABBA could not see it because no arena class pushes
	a thousand leaves under the text cap.

	So the walk spends a bare COUNT first, `stack_measure`'s shape and for its reason:
	a tick that bails must not have paid for anything, and the refusal here happens
	before the index is built or the region triples are re-read. Past the budget the
	container takes the FULL PASS — the exact arm T15 refused to and D2a replaced — so
	the fallback is O(children) and the total is bounded by it either way.

	AND THE COUNT IS PAID ONCE PER PASS, NOT ONCE PER CONTAINER. `store.dirty` is one
	fixed table for the length of a `build`, so a walk that stopped at `budget + 1`
	established that the set holds MORE than that, and a walk that finished established
	its exact size: either way `store.dirtySeen` is a lower bound every later container
	can refuse against in O(1). The outermost container is built first and carries the
	largest budget, so on the wide push the whole pass pays one bounded walk and the
	thousand rows under it pay a comparison each. Both numbers are pure functions of the
	set's SIZE and of document order, never of the hash order it enumerates in. ]]
local function patchIndices(store: any, node: any, prior: any): { number }?
	local probeBudget = math.max(DIRT_PROBE_FLOOR, #prior.childArray)
	if store.dirtySeen > probeBudget then
		return nil
	end
	local probes = 0
	for _ in store.dirty do
		probes += 1
		if probes > probeBudget then
			store.patchProbes += probes
			store.dirtySeen = probes
			return nil
		end
	end
	store.patchProbes += probes
	if probes > store.dirtySeen then
		store.dirtySeen = probes
	end
	local index = prior.kidIndex
	if index == nil then
		local mounts, regions
		index, mounts, regions = indexKids(node, prior.childArray, store)
		if index == nil then
			return nil
		end
		prior.kidIndex = index
		prior.kidMounts = mounts
		prior.kidRegions = regions
	else
		local regions = prior.kidRegions
		for i = 1, #regions, 3 do
			local kids = regions[i].children
			if kids ~= regions[i + 1] or #kids ~= regions[i + 2] then
				return nil
			end
		end
	end
	local mounts = prior.kidMounts
	local out: { number } = {}
	local budget = math.max(4, #prior.childArray // 4)
	for path in store.dirty do
		local idx = index[path]
		if idx ~= nil then
			-- the subtree size to UNDO comes off the child's own entry, so an entry
			-- that is not there is a refusal rather than a guessed number
			if #out >= budget or store.byNode[mounts[idx]] == nil then
				return nil
			end
			out[#out + 1] = idx
		end
	end
	return out
end

local function toLayoutNode(
	node: any,
	metrics: any,
	textScale: number,
	prefOffset: number,
	parentAxis: string?,
	-- true once ANY ancestor is a clipping scroll container. Only the OUTERMOST
	-- clipper reserves the shadow bleed (see the block below), so this rides the
	-- recursion the same way `parentAxis` does.
	insideClipper: boolean?,
	-- THE CROSS-SOLVE NODE STORE (perf campaign P3), or nil for a one-shot build.
	-- See `layout_node.build` at the bottom of this file for what it holds and the
	-- four axes it is invalidated on; here it is two lookups and one write.
	store: Store?,
	--[[ true once ANY ancestor is a `Button` — "this node sits inside a control's
		content". It rides the recursion exactly as `parentAxis` and `insideClipper`
		do, and for the same reason: it is a fact about WHERE a node is, which a cache
		hit must not have to walk up to rediscover. Spent by ONE rule, the centred
		control line beside the `align` field below.

		LAST, BEHIND `store`, because the parameter list is a PUBLIC signature:
		`tests/build_children_reuse.spec.luau:320` calls this with seven positional
		arguments, and inserting a term in the middle would silently hand it `store`
		as this flag. ]]
	insideControl: boolean?
): solver.Node
	--[[ P3: THE SUBTREE THIS SOLVE DOES NOT HAVE TO BUILD. Every field below is a
		pure function of FIVE mounted-node fields — `class`, `path`, `props`,
		`children`, `meta` — plus `metrics`, `textScale`, `prefOffset`, `parentAxis`,
		`insideClipper` and `insideControl`; and NOTHING THE SOLVER WRITES ONTO A LAYOUT
		NODE IS ONE OF THEM, so last solve's tree is still this solve's answer wherever
		none of the eleven moved.

		**THAT LICENCE USED TO READ "the solver never writes into a layout node
		(`solver.luau` contains no `node.<field> =`)", AND SINCE C2 IT DOES WRITE**
		(2026-09-04). `solver.measure` memoises its last two answers onto the node —
		twenty-one `m*` fields plus a cached `memoPlan` verdict. **MOST of those are
		written only on a solve that was handed a reuse set** (`record` returns before
		its first write when `ctx.reuse == nil`), and TWO ARE NOT: `node.mTextW`
		(`solver.luau`'s text branch, outside `record`) and `node.mPlan`
		(`measure_facts.memoPlan`) are written on EVERY solve, a purity, analyse or
		dump solve included. That sentence read "ONLY" until 2026-09-07 and was false
		from D1 onward (RED-TEAM C-4); it does not throw, because nothing in `src/` or
		`tests/lib/` freezes a layout node, but a load-bearing sentence that is false is
		a defect on its own terms. The licence survives in the form that actually
		matters, and it is three claims rather than one: the written fields are OUTPUTS
		(the last answers this node gave), never inputs this function reads to build a
		node; a node whose props moved is a FRESH LITERAL, so a rebuilt node carries no
		stale answer; and the set is CLOSED — `tests/measure_serve.spec.luau` audits
		every `node.<field> =` in `solver.luau` AND in `measure_facts.luau` against the
		enumerated memo fields, so an unlisted write reddens rather than quietly
		widening what the store forwards. That audit read `solver.luau` alone until
		2026-09-07, which is the file D1's `node.mPlan` is NOT in: the field was on the
		list while the scan that makes the list closed could not see the file it lives
		in, so the next write added there would have widened the forwarded set in
		silence — the exact failure the audit exists to prevent.

		**THE FIFTH FIELD IS NOT REACHED THROUGH `node.`, WHICH IS WHY THE AUDIT COUNTS
		CALL SITES AND NOT ONLY FIELD READS** (P3 review, I1). `meta` is read by
		`chrome_slots.readHint(node)` below — a WHOLE-NODE helper — so a scan for
		`node.<field>` in this file cannot see it, and the first version of this audit
		reported four fields where there are five. The audit is therefore TWO
		enumerations: every `node.<field>` read, AND every call that hands the mounted
		node (or a mounted child) to somebody else. Both are pinned by
		`tests/node_reuse.spec.luau`, so the next whole-node helper fails a case instead
		of slipping a grep.

		`meta` IS IMMUTABLE PER MOUNTED NODE, which is what keeps it off the dirty axes:
		it is `bp.meta` copied by reference once at mount (`mount.luau`: "library-internal
		metadata channel: copied verbatim, never observed, never rendered, never
		dumped"), and a blueprint node is `table.freeze`d at construction along with its
		`props` and `children` (`blueprint.luau`, the `return table.freeze(node)` at the
		end of the node constructor). A `meta` change is a different blueprint, which is
		a remount, which is a different mounted node table — axis 1.

		THE FIRST SIX ARE THE STORE'S OWN AXES and are checked once per build (`build`
		below) or are constant for the node's life. The last THREE ride the recursion and
		can change WITHOUT any prop or child changing — a node re-parented from an
		hstack to a vstack, first appearing under a `scroll`, or first appearing under a
		`Button` whose content/label split flipped (`:560`) — so they are checked
		here, per node, and stored rather than derived because a cache hit must not have
		to walk up to find out where it is. ]]
	--[[ THE SUBTREE'S OWN SIZE, ACCUMULATED (perf campaign P5). `store.nodes` counts
		the layout nodes this build's tree HAS — constructed ones one at a time, served
		ones by the size their entry recorded — so the total is exact without walking a
		served subtree, which is the whole point of serving it. It is the number
		`solver.solve` derives `work.skipped` from by subtraction, and that derivation
		reads the PREVIOUS solve's totals: while every structural change forced a full
		solve the chain was re-based every time the node count moved, and P5 removed
		that reset. See the renderer's repair beside `stats.lastSkipped`. ]]
	local nodesAtEntry = if store ~= nil then store.nodes else 0
	if store ~= nil then
		--[[ `store.reuse == false` IS THE COUNT-ONLY ARM, and it exists so the
			differential oracle's control is an honest pre-fix build (P3 review, I2).
			A store that looked up and wrote on the off arm would charge that arm a
			hash probe, a record allocation and an insert per node for a table
			discarded on the next solve — an inflated denominator in every "vs off"
			ratio. Off costs one boolean test and one increment per node, which is
			the counter and nothing else. ]]
		if store.reuse then
			local hit = store.byNode[node]
			if
				hit ~= nil
				and not store.dirty[node.path]
				and hit.axis == parentAxis
				and hit.clip == (insideClipper == true)
				and hit.control == (insideControl == true)
			then
				store.nodes += hit.n
				return hit.built
			end
		end
		store.built += 1
		store.nodes += 1
		--[[ ...AND WHICH ONES (perf campaign P5), when the caller asked. A node reaches
			this line only when the lookup above refused it: a different mounted TABLE, a
			path in `dirty`, or a moved axis/clip. So this list is exactly "the nodes
			whose identity or props may have moved", and its COMPLEMENT — the nodes this
			build SERVED — is the only honest licence to skip a subtree on a structural
			solve. `render/structural_scope` spends it twice, on the reuse set and on
			`layout/measure_reuse`'s slates. Collected only when `builtIds` is non-nil,
			i.e. only on the builds that spend it. ]]
		local ids = store.builtIds
		if ids ~= nil then
			table.insert(ids, node.path)
		end
	end
	local class = node.class
	local props = node.props or {} -- structural regions carry no user props
	-- resolved text size + the typography role behind it (nil unless a role was
	-- named), so the role's font and line height reach the measurer with the size
	-- they belong to. An AUTHORED size — number, role name or metric path — is
	-- scaled, because it also reaches paint and the two seams must agree; an
	-- ABSENT one falls back to the class's intrinsic role unscaled, exactly as the
	-- adapter draws it.
	local function textOf(fallbackRole: string): (number, any, any)
		local raw = props.textSize
		--[[ `textSize = "fit"` — THE SIZE THIS NODE PAINTS AT IS THE SOLVER'S TO
			CHOOSE (audit §10, framework-gaps-phase2). Everything this seam resolves for
			a fixed size is resolved here too — the face, the line height, the scale and
			the paint offset — but the SIZE is left as a band, because the box is the one
			input this seam does not have and the solver does.

			WHAT TRAVELS: `cap` and `floor` already through `textScale`, and the additive
			paint `offset` beside them rather than folded in, because the solver has to
			measure the PAINTED form (`size + offset`) while paint writes the authored
			one. That split is `text_metrics.reservedSize`'s own ("scale, then add"), and
			keeping the two numbers apart on the record is what lets the solver hand the
			paint seam a size it can write without subtracting anything back out.

			THE CAP DEFAULTS TO THE SIZE THE NODE WOULD OTHERWISE HAVE PAINTED — the
			class's intrinsic role — so `"fit"` can only ever make text smaller, never
			bigger. THE FLOOR DEFAULTS TO THE THEME'S `caption`, which every package is
			required to carry: "never below this theme's smallest type role" is a bound
			that survives a package swap and the ten-foot ladder, where a literal would
			not, and where this module's raw `text.fit` default of 1 would let a label
			paint unreadably rather than let the layout decide.

			THE FACE STILL COMES FROM A ROLE: `cap` names one when it is a role name,
			and otherwise the class's intrinsic role answers, exactly as a literal px
			size gets the intrinsic face today. ]]
		local fitProp = textFit.fitSpecOf(raw)
		if fitProp ~= nil then
			local _, capRole = themeSnapshot.effectiveTypeRole(metrics, class, fitProp.cap)
			local capPx = if type(fitProp.cap) == "number"
				then fitProp.cap
				else (themeSnapshot.resolveSize(metrics, fitProp.cap) or metrics.type[fallbackRole].size)
			local captionRole = (metrics.type :: any).caption
			local floorPx = if type(fitProp.floor) == "number"
				then fitProp.floor
				else (themeSnapshot.resolveSize(metrics, fitProp.floor) or (if type(captionRole) == "table"
					then captionRole.size
					else nil) or capPx)
			--[[ THE BAND IS IN PAINT UNITS, and that is the one arithmetic decision in
				this branch. Everything else on this seam is scaled by `textScale`, which
				is `max(typographyScale, typographyPaintScale)` — the RESERVE scale, a
				deliberate over-estimate, because the engine applies the player's
				preference as an ADDITIVE offset at draw time and the box must hold what
				is drawn.

				A fit node has no authored size to over-reserve for: the solver picks the
				size that will actually be PAINTED, so the band it picks from has to be
				the band paint lives in, and the reserve is then exact rather than
				generous. Using the measure scale here would let a fit label grow by the
				preference AND take the engine's additive offset on top — the
				double-application defect `text_metrics.reservedSize`'s own header warns
				about, spelled the other way round. ]]
			local paintScale = themeSnapshot.typographyPaintScale(themeSnapshot.displaySizeOf(metrics))
			local fit = {
				cap = capPx * paintScale,
				-- a floor above the cap is a declaration that cannot be honoured; the
				-- cap wins, because a node may never paint LARGER than its cap
				floor = math.min(floorPx, capPx) * paintScale,
				offset = prefOffset,
			}
			-- the fallback size a reader that knows nothing of `textFit` sees: the
			-- cap as the engine will draw it, i.e. the largest box this node can need
			return fit.cap + prefOffset, capRole, fit
		end
		-- THE FACE COMES FROM THE EFFECTIVE ROLE, authored or intrinsic (F2,
		-- 2026-08-02). This used to hand back `nil` for an unauthored size, and the
		-- solver then keyed measurement on `body`'s descriptor — while the class's
		-- INTRINSIC role is `control` for a Button and a TextField. Under Studio
		-- Neutral every role wears one face so nothing showed; under a package whose
		-- control face differs from its body face the solver measured the wrong
		-- family, and the paint seam (which now writes the role's face) would have
		-- disagreed with it. One resolver for both seams, so it cannot.
		local _, role = themeSnapshot.effectiveTypeRole(metrics, class, raw)
		local size = themeSnapshot.resolveSize(metrics, raw)
		-- ONE SPELLING OF "scale, then add the engine's additive offset"
		-- (`text_metrics.reservedSize`), shared with the PUBLIC `Facet.text.lineBox`
		-- so a consumer predicting a text box spends the seam's own arithmetic
		-- instead of a hand copy.
		--
		-- BOTH BRANCHES SCALE (2026-08-18). This branch used to reserve
		-- at scale 1 and say so — "an INTRINSIC size never reaches paint scaled" —
		-- which was true, symmetric with the paint seam, and the reason the defect
		-- was invisible: nothing overflowed, so nothing complained, and a
		-- television got near-distance type for every screen written the natural
		-- way (`UI.Text{ text }`, `UI.Button{ label }`). The floor is a property of
		-- the typography ROLE, and an unauthored node wears the class's intrinsic
		-- one, so it takes the same multiplier. `commit_walks.textScale` moves in
		-- the same commit: measure/paint agreement is what must survive the fix.
		if size == nil then
			return text_metrics.reservedSize(metrics.type[fallbackRole].size, textScale, prefOffset), role
		end
		return text_metrics.reservedSize(size, textScale, prefOffset), role
	end
	local kind: string
	-- set by the Button branch below; spent once `layoutNode` exists
	local buttonSingleLine = false
	if class == "Screen" then
		kind = "vstack"
	elseif class == "VStack" then
		-- ONE PUBLIC CLASS, TWO SOLVER KINDS (round 3 item A). `wrap` is a prop
		-- because a wrapping stack is the same class in a second mode (schema
		-- `WRAP`); the KIND is distinct because `solver.auditPlacement` is keyed on
		-- it and a wrapping stack reads a genuinely different placement set — no
		-- shrink pair, because wrapping is what a main-axis deficit does here. Same
		-- prop-decides-kind seam `AdaptiveStack.axis` uses two lines down, and it
		-- carries the same guarantee: the class never changes, so a flip re-solves
		-- and never remounts.
		kind = if props.wrap == true then "vwrap" else "vstack"
	elseif class == "AdaptiveStack" then
		-- ONE class, reactive axis (A-AL2): the flip is a re-solve, never a
		-- remount, so children keep their identity and state
		kind = if props.axis == "x" then "hstack" else "vstack"
	elseif class == "ViewThatFits" then
		kind = "fits"
	elseif class == "Composition" then
		-- a screen-level container whose children are ranked regions.
		-- ONE class, no reactive prop at all: the adaptation is driven entirely by
		-- the box it receives, so an orientation change, a window resize, a
		-- preferred-text change and a theme swap are all the same re-solve.
		kind = "composition"
	elseif class == "Region" then
		kind = "region"
	elseif class == "Divider" then
		kind = "box"
	elseif class == "HStack" then
		kind = if props.wrap == true then "hwrap" else "hstack"
	elseif class == "ZStack" then
		kind = "zstack"
	elseif class == "ScrollView" then
		kind = "scroll"
	elseif class == "Grid" then
		kind = "grid"
	elseif class == "GridRow" then
		kind = "gridrow"
	elseif class == "Text" then
		kind = "text"
	elseif class == "Button" then
		-- B-BTN1: a CONTENT button sizes from its children (it draws no text of its
		-- own); a plain button keeps label-driven sizing
		kind = if #node.children > 0 then "hstack" else "text"
		-- ...and a label-driven button is measured on ONE line, because that is how
		-- the adapter draws it (director round 13, 2026-07-27). The two seams must
		-- agree about how many lines this is, or the solver reserves height for a
		-- second line nobody draws — or, as fantasy-parchment showed, the box is
		-- exactly one line wide and the engine wraps into it anyway. Same ruling
		-- the Toggle's label already carries.
		-- ONE LINE FOR A WORD, WRAPPING FOR A PHRASE (director round 13,
		-- 2026-07-27: fantasy-parchment's Edit/Done toggle drew "Don" over "e").
		--
		-- A content-sized button is measured to EXACTLY its label — under
		-- fantasy-parchment, fantasy-ornate and glossy-touch the reserved column
		-- and the text came out equal to the pixel — so there is no slack for the
		-- engine's own measurement to differ by one, and with wrapping on a
		-- one-pixel shortfall does not clip a pixel, it BREAKS THE WORD.
		--
		-- The rule is the distinction the engine does not make: a WORD has no legal
		-- break, so breaking it is always damage and an ellipsis is the honest
		-- degradation. A PHRASE has one, and wrapping it is the right answer — the
		-- theme picker's "Classic Desktop" chips grow to two lines on a narrow
		-- phone on purpose (round 9), and blanket single-line would clip them to
		-- "Classic Deskt…". So the label's own shape decides, per solve, and both
		-- seams read the same label.
		--
		-- THE STRING IS ONLY HALF THE RULE (director ruling 5, 2026-08-13). "Has
		-- this a legal break at all" is all a string can answer; whether that break
		-- can SUCCEED needs the drawable width, so the solver finishes the rule in
		-- its own wrap block (a phrase whose LONGEST WORD does not fit is measured
		-- on one line too) and publishes `textFacts.wraps`, which `commit_walks.textVerdicts`
		-- below carries to paint. This line is unchanged — a word is single-line at
		-- every width — and the width-dependent half is added on top of it.
		buttonSingleLine = kind == "text" and isSingleWord(props.label)
	elseif class == "Toggle" then
		kind = "text" -- label-driven sizing; track chrome reserved below
	elseif class == "TextField" then
		kind = "text" -- placeholder/value-driven sizing; explicit dims win
	elseif class == "Spacer" then
		kind = "spacer"
	elseif class == "Anchor" then
		kind = "anchor"
	elseif class == "When" or class == "ForEach" or class == "ErrorBoundary" then
		kind = "vstack" -- structural regions are transparent containers
	else
		kind = "box"
	end
	--[[ A CONTROL'S CONTENT LINE IS CENTRED (user review of the Pixel Quest
		capture, 2026-09-12: "the text is not vertically centred in the Advanced
		button, or in the three popup rows").

		THE CAUSE IS THE FRAMEWORK'S OWN RESERVATION, not a theme's numbers — the
		insets both packages declare for `control` are symmetric to the pixel, and
		`chrome_slots.spendInset` gives a side back only in PAIRS. A stack aligns its
		line to `start` unless its author says otherwise (api.md: "the alignment you
		asked for, which defaults to start"), and THE ICON BLOCK BELOW grows an
		icon-hinted Text node to the package's `iconSizes` square — a picture, not a
		line of type. Measured on the eight shipped packages at
		`preferredTextOffset = 0`: Pixel Quest reserves a 32px glyph beside a 20px
		`control` line, Fantasy Ornate 32 beside 23, Glossy Touch 28 beside 23,
		Classic Desktop 20 beside 15. The line is therefore as tall as the PICTURE
		and the word sits at the top of it, `(icon - line) / 2` px above the box
		centre: 6px on Pixel Quest's disclosure header and on its menu rows, 4.5 on
		Fantasy Ornate, 2.5 on Glossy Touch and Classic Desktop. Nothing the author
		wrote moved that text — this file's own reservation did.

		SO THE RULE IS BOUNDED BY THE CONTROL, and that bound is the argument for it.
		A Button's box is a control box: its content belongs in the middle of it,
		which is what every package's plate art is drawn around and what the lifted
		label (`screen_chrome.liftGeometry`) already assumes. It is also the one
		place the framework may take its own default back, because the framework is
		what inflated the line. Outside a Button nothing moves; `start` stays the
		library-wide default, and `insideControl` is what keeps the two apart.

		IT IS A DEFAULT, NOT A LAW. An authored `align` still wins outright, and the
		rule is a NO-OP wherever the line's children already share a height — which
		is every shipped row at the two largest text preferences, where the type has
		caught the picture up.

		ONE KIND ONLY, and both exclusions are load-bearing. A `vstack`'s cross axis
		is horizontal, and moving an author's left-aligned label sideways is a
		different claim from the one measured above. A WRAPPING row is excluded
		because `align` there means two things at once — where the BLOCK of lines
		sits AND where each child sits inside its line (api.md, `wrap`) — so a
		default would be guessing at two decisions from one observation.
		`examples/reference/p4_foyer`'s `MetaFits` row is the shipped instance, and
		its own `distribute` comment is about that second job. An author of a
		wrapping row still says `align` themselves. ]]
	local centredControlLine = kind == "hstack" and (class == "Button" or insideControl == true)
	local layoutNode: any = {
		kind = kind,
		singleLine = if buttonSingleLine then true else nil,
		id = node.path,
		width = stampContentTermsFacts(themeSnapshot.resolveDim(metrics, props.width), textScale, prefOffset),
		height = stampContentTermsFacts(themeSnapshot.resolveDim(metrics, props.height), textScale, prefOffset),
		padding = themeSnapshot.resolveSides(metrics, props.padding),
		gap = themeSnapshot.resolveNumber(metrics, props.gap),
		-- a grid's vertical pitch, resolved through the same space ladder as
		-- `gap`; absent, the solver falls back to `gap` (director finding 14)
		rowGap = themeSnapshot.resolveNumber(metrics, props.rowGap),
		margin = themeSnapshot.resolveSides(metrics, props.margin),
		align = props.align or (if centredControlLine then "center" else nil),
		-- the three round-2 stack-arrange inputs (parity round 2 §2.1/§2.4/§2.6).
		-- `distribute` is read off the CONTAINER, `lineAlign`/`layoutPriority`/
		-- `shrinkWeight` off each CHILD — all four are plain carried facts here and
		-- are spent in the solver's stack arrange branch
		distribute = props.distribute,
		lineAlign = props.lineAlign,
		layoutPriority = props.layoutPriority,
		shrinkWeight = props.shrinkWeight,
		-- ...and the row grid's one child-side input (§2.2), read by a `gridrow`
		-- parent and by nothing else
		gridSpan = props.gridSpan,
		alignH = props.alignH,
		alignV = props.alignV,
		-- THE FOUR PLACEMENT FIELDS ARE NOT HERE: `layout_node.applyPlacement` (below)
		-- writes them, and this literal calls it four lines after the closing brace.
		-- THE TWO KEYS `ctx.offers` IS INDEXED BY (wicked-fast A1), built once per
		-- node here instead of twice per measure AND twice per arrange — the solver
		-- was interpolating `node.id .. "|w"` on every one of those.
		--
		-- WHAT THAT COSTS IS INTERNING WORK, NOT GARBAGE, which is the opposite of
		-- what the task that added these fields set out to prove and is recorded here
		-- so nobody re-derives the wrong version. Luau interns short strings, and
		-- these keys are the same handful every solve, so re-concatenating them
		-- allocates nothing measurable — the bill is the hash and the compare that
		-- FIND the existing string, once per index. Measured on FacetBench
		-- `nameplates L`, ABBA n=4 per arm against a build that keeps the
		-- concatenations: tick p50 5.729 -> 5.624 (-1.8 %, ranges disjoint) with the
		-- tick's gcKb UNMOVED at ~3072.
		--
		-- `node.path` is the
		-- mounted path — the same expression the `id` field two dozen lines up uses,
		-- and there is no local `id` in this function — so this is a pure function of
		-- identity and the P3 node store carries it across solves for free: a reused
		-- node table keeps them, and a rebuilt one rebuilds the same two strings.
		--
		-- EVERY READ OF THEM IS GUARDED (`node.wKey or (node.id .. "|w")`), because
		-- the store's warm-hit path near the top of this function returns `hit.built`
		-- WITHOUT re-running this literal: a node table built before this commit and
		-- still in a live `store.byNode` is served without these two fields, and an
		-- unguarded `ctx.offers[node.wKey] = maxW` would raise `table index is nil`
		-- inside a protected solve boundary. A Studio module reload that leaves the
		-- controller alive is a real path to it.
		wKey = node.path .. "|w",
		hKey = node.path .. "|h",
		--[[ WHETHER THIS NODE IS A COORDINATE SPACE (Plan C, C1) — carried because
			`arrange` is what runs such a host's body at the origin. Not a prop and not
			derivable from one: the trigger reads `dynamicProps`, which does not survive
			into the layout tree.

			ASKED HERE, NOT READ OFF A STAMP. `renderer.ensureTree` stamps the same
			answer when it chooses the node's engine object, but this build can run
			FIRST — a re-solve driven from inside a settle reaches a row the structural
			sync has not created yet — and a layout node built with the flag missing
			stores its whole subtree absolutely under a parent the adapter then
			registers as a coordinate space. `createOptsFor` memoises its answer on the
			mounted node, so whichever of the two asks first fixes it for both. ]]
		hostSpace = hostSpaceOf(node, store.attachOpts),
		columns = props.columns,
		minColumnWidth = props.minColumnWidth,
		itemSizing = props.itemSizing,
		-- "row" (default) | "column": which axis the grid's lanes divide. A carried
		-- name like `itemSizing`, resolved nowhere but the solver's flow-grid plan.
		flow = props.flow,
		overflow = props.overflow,
		axis = props.axis,
		-- "this container is ONE SLOT of a fixed-pitch windowing list", carried
		-- straight through to the solver's declared-slot guard (solver `Node.
		-- virtualSlot`). A plain carried fact like `distribute`: nothing here
		-- resolves it, because every field is already a px number or a name.
		virtualSlot = props.virtualSlot,
		-- THE EFFECTIVE TARGET FLOOR, CARRIED INTO THE SOLVE (large-text accessibility diagnostics).
		-- Declared by the control contract, clamped UP by the theme — the identical
		-- pair `pushHitRects` spends below, read here so the SOLVE RESULT can say
		-- which rects belong to something the player is meant to hit. It changes no
		-- geometry: the hit expansion stays where it was, and this is the fact a
		-- pure audit needs to tell an interactive rect from a decorative one.
		hitFloor = effectiveHitFloor(class, metrics),
		-- wave REVEAL: "this button is a region's expand affordance, and this is how
		-- it is placed". Declared by `UI.Region` and by nothing else; the solver's
		-- region branch is the only reader. It is carried rather than inferred
		-- because a region's FORMS can splice themselves out from under an index
		-- (`UI.When`), so counting children could name the wrong node.
		expandTarget = props.expandTarget,
	}
	--[[ THE PLACEMENT FIELDS, WRITTEN BY THE ONE FUNCTION THAT KNOWS WHAT THEY MEAN
		(Plan C, T5). They left the literal above so that `render/translate_lane` —
		which re-places a coordinate-space host WITHOUT a build — can write them with
		the build's own code instead of an enumeration of its own. Two callers, one
		copy: a tenth placement prop is added here and both are correct. ]]
	applyPlacement(layoutNode, props, metrics)
	if class == "Composition" then
		-- Every theme-owned number is resolved HERE, on every solve, so a package
		-- with a bigger minimum field width re-arranges the screen without the
		-- author touching a line — the same contract every other metric name has.
		local groups = {}
		for _, g in props.groups or {} do
			local copy = table.clone(g)
			copy.minWidth = themeSnapshot.resolveNumber(metrics, g.minWidth)
			-- ...INCLUDING THE GROUP'S OWN GAP. The constructor accepts a spacing
			-- step or a metric path here (same rule as `minWidth`), but only
			-- `minWidth` was being resolved — so `gap = "s"` reached the solver as a
			-- STRING, where the arithmetic reads it as "no gap" and the regions in
			-- that group sat flush against each other. Accepted-and-ignored, found
			-- consuming the mechanism (RascalRally S16 v2, 2026-07-31).
			copy.gap = themeSnapshot.resolveNumber(metrics, g.gap)
			--[[ THE TEN-FOOT MEASURE, DEFAULTED (B-6e, controller ruling R14,
				2026-08-21). A `Composition` at ten-foot used to resolve the DESKTOP
				answer with more pixels — the same arrangement with the content lane
				simply wider (1316px measured, against the regular-touch tablet's
				600 that the paradigm matrix verified RIGHT). `sizeClass`,
				`heightClass` and `columnsFor` all cap at distance; the arrangement
				that decides the MEASURE did not, and its two knobs (`maxMeasure`,
				and now the group's own `maxWidth`) sat unset on every shipped site.

				THE NUMBER IS DERIVED, NOT CHOSEN: `adaptive.LANE_MEASURE` (the
				tablet measure) times `metrics.metricScale` (the
				`tenFootFloor`, the one factor behind every ten-foot number in this
				framework). 600 x 1.5 = 900, with neither number written twice, so a
				re-ruled measure is one edit in `adaptive.laneMeasureFor` and a named
				sweep goes red.

				AUTHORED WINS, per the package-authority precedent, in both
				spellings: a group that declares its own `maxWidth`, or a
				composition that declares `maxMeasure`, has made the measure
				decision and gets no default beside it. Only a `fill` group is
				asked — a hug lane's width IS its content and has no share to cap.

				THIS IS THE SEAM because it is where the display class and the
				declaration are already both in hand: the same loop that resolves
				every other theme-owned number on the group, on every solve. ]]
			if copy.maxWidth == nil and (g.sizing == "fill") and props.maxMeasure == nil then
				copy.maxWidth = adaptive.laneMeasureFor((metrics :: any).metricScale)
			else
				copy.maxWidth = themeSnapshot.resolveNumber(metrics, g.maxWidth)
			end
			table.insert(groups, copy)
		end
		layoutNode.composition = {
			groups = groups,
			arrangements = props.arrangements,
			laneGap = themeSnapshot.resolveNumber(metrics, props.laneGap),
			groupGap = themeSnapshot.resolveNumber(metrics, props.groupGap),
			maxMeasure = themeSnapshot.resolveNumber(metrics, props.maxMeasure),
			--[[ THE TEN-FOOT MEASURE, DEFAULTED (B-6e, controller ruling R14,
				2026-08-21). A `Composition` at ten-foot used to resolve the DESKTOP
				answer with more pixels — the same arrangement with the content lane
				simply wider (1316px measured, against the regular-touch tablet's
				600 that the paradigm matrix verified RIGHT). `sizeClass`,
				`heightClass` and `columnsFor` all cap at distance; the arrangement
				that decides the MEASURE did not, and `maxMeasure` sat unset on
				every shipped site.

				The ruled number is 900 and it is DERIVED rather than chosen:
				`adaptive.LANE_MEASURE` (the tablet measure) times
				`metrics.metricScale` (the `tenFootFloor`, the one factor
				behind every ten-foot number). Neither is written twice, so a
				re-ruled measure is one edit in `adaptive.laneMeasureFor`.

				AUTHORED WINS, per the package-authority precedent: a composition
				that declared `maxMeasure` has made the measure decision itself and
				gets no default beside it. This is the seam because it is where the
				display class and the declaration are both already in hand — the
				same place `maxMeasure`'s own metric name is resolved to px. ]]
			measureCap = if props.maxMeasure ~= nil then nil else adaptive.laneMeasureFor((metrics :: any).metricScale),
			-- §8: the host's own chrome, in WINDOW space. It rides through untouched —
			-- the SOLVER is the one place that knows where this composition landed, so
			-- it is the one place that can convert a window rect into the composition's
			-- own box (`layout/composition_resolve.luau`).
			exclusions = props.exclusions,
		}
	elseif class == "Region" then
		layoutNode.region = {
			group = props.group,
			rank = props.rank,
			sizing = props.sizing,
			weight = props.weight,
			floor = props.floor,
			mayScroll = props.mayScroll,
			mayDrop = props.mayDrop,
			reserved = props.reserved,
			-- D7.1: construction-only, no geometry of its own. It rides here so the
			-- solve can report WHERE an elided region's content went beside the fact
			-- that it was elided — the two are one answer and a consumer that has to
			-- join them by hand is the seam this exists to remove.
			recover = props.recover,
			-- wave REVEAL: the record `UI.Region` resolved at construction — the mode,
			-- the DECLARED form count (which `#children` no longer is, since the expand
			-- affordance rides in the same list), one interactivity boolean per form
			-- and the affordance's role. The solver reads all four.
			expand = props.expand,
		}
	end
	if class == "Spacer" then
		layoutNode.minLength = if props.minLength ~= nil
			then math.max(0, themeSnapshot.resolveNumber(metrics, props.minLength))
			else nil
		if props.minLength ~= nil then
			layoutNode.placementProps = true
		end
	end
	if class == "Text" then
		layoutNode.text = props.text
		-- THE LINE CAP (Text.lineLimit). A theme metric NAME is legal here like
		-- anywhere else a number is, so a package can express how many lines its own
		-- rows allow. The engine ellipsizes the overflow — TextTruncate.AtEnd is
		-- already set on every text node — instead of the label growing its box and
		-- painting through whatever contains it.
		layoutNode.lineLimit = themeSnapshot.resolveNumber(metrics, props.lineLimit)
		-- FULL-VALUE DISCLOSURE. Construction-only, so it is read straight
		-- off the prop bag; it changes no geometry and exists on the layout node
		-- solely so the solve result can report truncation and permission together.
		layoutNode.disclose = if props.disclose == true then true else nil
		-- THE AUTO REVEAL rides the same channel: construction-only, no geometry
		-- of its own — the solve reports truncation, permission and the natural
		-- one-line width together, and the presenter drives the travel
		layoutNode.reveal = props.reveal
		-- THE MEASURE HALF of the word/phrase rule, now that the adapter applies
		-- it to every text node and not only to Buttons (director, 2026-07-27).
		-- Both seams re-decide from the SAME string or the box is reserved for one
		-- shape and drawn as another — a single word painted on one line inside a
		-- box measured for two is the mirror of the defect this rule exists to
		-- remove. `props.text` may be a reactive binding, and it is already
		-- resolved by the time this runs, exactly as `props.label` is.
		layoutNode.singleLine = if isSingleWord(props.text) then true else nil
		local size, role, fit = textOf(themeSnapshot.INTRINSIC_TEXT_ROLE.Text)
		layoutNode.textSize = size
		-- the fit BAND, when the author asked the solver to choose the size
		layoutNode.textFit = fit
		-- an explicit (deprecated) font prop still wins for measurement; otherwise
		-- the role's canonical font DESCRIPTOR ("family#weight#style") and line
		-- height ride with its size, so a theme that changes weight
		-- measures as that weight instead of as the family's Regular
		layoutNode.font = props.font or (if role ~= nil then role.fontKey else nil)
		layoutNode.lineHeight = if role ~= nil then role.lineHeight else nil
		layoutNode.textBaseline = if role ~= nil then role.baseline else nil
	elseif class == "Button" then
		-- FULL-VALUE DISCLOSURE for a button's one-line label (picker round,
		-- 2026-09-11): `disclose` rides the same textFacts channel a Text's and a
		-- Toggle's do, so a squeezed segment label is "truncate+disclose" to the
		-- large-text audit and the plate — never a lost string
		layoutNode.disclose = if props.disclose == true then true else nil
		if #node.children == 0 then
			layoutNode.text = drawnButtonText(props)
			local size, role, fit = textOf(themeSnapshot.INTRINSIC_TEXT_ROLE.Button)
			layoutNode.textSize = size
			-- the fit BAND, when the author asked the solver to choose the size
			layoutNode.textFit = fit
			layoutNode.font = if role ~= nil then role.fontKey else nil
			layoutNode.lineHeight = if role ~= nil then role.lineHeight else nil
			layoutNode.textBaseline = if role ~= nil then role.baseline else nil
			-- THE COMPACT ALTERNATIVE, handed to the solver alongside the full
			-- label so ONE pass can measure both and pick (director, 2026-07-27).
			-- The choice cannot be made here: it depends on the width this node is
			-- about to be given, which only the solver knows. It cannot be made at
			-- paint either, or the box would be reserved for one string and drawn
			-- with another — the defect class this file keeps meeting.
			--
			-- A compact form is a single word or one mark by construction
			-- (`assertCompactLabel` rejects whitespace), so it is measured on ONE
			-- line whatever the full label's shape was. That answers "what does
			-- singleLine do when the compact form is showing" without a second
			-- rule: both seams re-derive it from the string they actually draw.
			local compact = drawnButtonText(props, true)
			if compact ~= layoutNode.text then
				layoutNode.compactText = compact
				-- ...and WHETHER IT IS A DEGRADE OR A DEFAULT (director device round
				-- 2026-08-12). `prefer = true` skips the fit test entirely, so the
				-- compact form is what this button measures AND paints — which is why
				-- the flag has to reach the solver rather than being resolved here: the
				-- box must be reserved for the string that will be drawn in it.
				local form = compactForm(props)
				if form ~= nil and form.prefer == true then
					layoutNode.compactPrefer = true
				end
			end
		end
		-- THE CIRCLE IS A SOLVER FACT (see `applyCircleShape` above, now shared
		-- with ZStack's branch below).
		applyCircleShape(layoutNode, props, metrics)
		layoutNode.padding = themeSnapshot.buttonPadding(metrics, props)
	elseif class == "ZStack" then
		-- THE CIRCLE SHAPE, generalized from the Button-only case above (task
		-- PAINT, director items 11/12). A ring/disc composite built from a
		-- ZStack (`UI.Path` track + arc + a centered mark — this round's Glade
		-- supply rings) gets the identical square guarantee: state a shape,
		-- never compute a size. No padding default here — unlike a Button's
		-- disc, a circular ZStack has no drawn label whose room this file could
		-- reserve or return, so the author's own (or absent) `padding` stands
		-- unchanged either way.
		applyCircleShape(layoutNode, props, metrics)
	elseif class == "Toggle" then
		-- measure = what the adapter DRAWS (control contract): label at the left
		-- plus the right-aligned track with its inset and the label margin. The
		-- old fixed 56x28 was track-only, so a bare labeled Toggle painted its
		-- label under the track (gallery place defect, director screenshot
		-- 2026-07-20). Explicit dims still win (the Settings-port full-width row
		-- pattern). Every number here is theme-owned: a theme with a wider track
		-- re-solves the label's wrap width without the control being rebuilt.
		layoutNode.text = props.label
		-- ONE LINE, MEASURED AND DRAWN (director finding 13, found live
		-- 2026-07-26). The adapter draws the toggle's label single-line with an
		-- end ellipsis, so the solver has to reserve a single line or the row is
		-- taller than the label it holds — the same measure-versus-paint
		-- disagreement rounds 3 and 9 landed on from the other side. Measured
		-- with wrapping on: a row whose reserved column equals the drawn bounds
		-- to the pixel (four of nine reference packages) turns any one-pixel
		-- shortfall into a MID-WORD break — "Musi" / "c" — and the press
		-- affordance (`extra.pressedScale` = 0.985) shrinks the box on every
		-- single flip.
		layoutNode.singleLine = true
		-- FULL-VALUE DISCLOSURE for the one-line label (Step 8.5 large-text accessibility):
		-- the single-line form is measured, signed design — so where a compact
		-- width truncates it, `disclose` is the declared full-value path, riding
		-- the same textFacts channel a Text's does
		layoutNode.disclose = if props.disclose == true then true else nil
		-- explicit textSize wins and scales like every other text node
		-- (verifier F1: measure and paint must agree); the intrinsic default is
		-- the `body` role, which is ScreenTarget's toggle label size
		local size, role, fit = textOf(themeSnapshot.INTRINSIC_TEXT_ROLE.Toggle)
		layoutNode.textSize = size
		-- the fit BAND, when the author asked the solver to choose the size
		layoutNode.textFit = fit
		layoutNode.font = if role ~= nil then role.fontKey else nil
		layoutNode.lineHeight = if role ~= nil then role.lineHeight else nil
		layoutNode.textBaseline = if role ~= nil then role.baseline else nil
		-- the row's box now comes from the SHARED description the adapter paints
		-- from (`themeSnapshot.toggleRowPadding`), so the reserved label column
		-- and the drawn one cannot disagree — director round 9
		layoutNode.padding = layoutNode.padding or themeSnapshot.toggleRowPadding(metrics)
		layoutNode.height = layoutNode.height or { type = "minMax", min = metrics.controls.toggle.minHeight }
	elseif class == "TextField" then
		layoutNode.singleLine = props.multiline ~= true
		-- Native editing scrolls the complete value into view; a one-line field
		-- has a full-value path even when its resting text exceeds the box.
		layoutNode.disclose = true
		-- measure from the shown text (value) or placeholder when empty, so a
		-- bare field still has an intrinsic size; the composite passes explicit
		-- fill/fixed dims which win
		local shown = props.text
		if shown == nil or shown == "" then
			shown = props.placeholder
		end
		layoutNode.text = shown or ""
		local size, role, fit = textOf(themeSnapshot.INTRINSIC_TEXT_ROLE.TextField)
		layoutNode.textSize = size
		-- the fit BAND, when the author asked the solver to choose the size
		layoutNode.textFit = fit
		layoutNode.font = if role ~= nil then role.fontKey else nil
		layoutNode.lineHeight = if role ~= nil then role.lineHeight else nil
		layoutNode.textBaseline = if role ~= nil then role.baseline else nil
		layoutNode.padding = layoutNode.padding or metrics.controls.textInput.padding
	elseif class == "Screen" then
		layoutNode.width = props.width or { type = "fill", weight = 1 }
		layoutNode.height = props.height or { type = "fill", weight = 1 }
	elseif class == "Divider" then
		-- axis names the stack axis the hairline SEPARATES ALONG: "y" (a vertical
		-- stack) draws a horizontal line spanning the cross axis; "x" draws a
		-- vertical one. Explicit axis wins; otherwise inherit the parent stack's.
		local axis = props.axis or parentAxis or "y"
		-- the default hairline is the theme's stroke weight, not a literal 1 — and
		-- an AUTHORED thickness may name a metric too: it is the same
		-- theme-owned number, so it takes the theme's own vocabulary through the
		-- same resolution `gap`/`lineLimit` use. An unresolvable name cannot reach
		-- here (the schema refuses it at construction) but still falls back.
		local resolvedThickness = themeSnapshot.resolveNumber(metrics, props.thickness)
		local thickness = if type(resolvedThickness) == "number"
			then math.max(0, resolvedThickness)
			else metrics.strokes.hairline
		if axis == "x" then
			layoutNode.width = layoutNode.width or { type = "fixed", px = thickness }
			layoutNode.height = layoutNode.height or { type = "fill", weight = 1 }
		else
			layoutNode.width = layoutNode.width or { type = "fill", weight = 1 }
			layoutNode.height = layoutNode.height or { type = "fixed", px = thickness }
		end
	end
	--[[ `surface = "badge"` INTRINSIC MINIMUM (gap 19, W3-B). A SURFACE
		concern, not a CLASS one — `Text`, `Image` and `ZStack` all wear the
		badge skin in shipped fixtures — so this reads `props.surface` rather
		than joining the class chain above, and it runs for every class.

		THE CENSUS THAT JUSTIFIES IT: every shipped `surface = "badge"` site up
		to this round independently reserved room by hand — `controls/
		picker.luau`'s own `BADGE_BOX` (`{minMax, min="l"}`),
		`p4_foyer/init.luau`'s `BADGE_MIN`/`BADGE_MAX` with the comment "a count
		bubble is a MIN-SIZED round plate, never a bare glyph hugging its own
		pixels", `adaptive_controls.luau`'s fixed 28px chip, RascalRally's
		`FacetRacerListScreen.luau` fixed 20px seal, `p2_cartwheel/screens/
		parts.luau`'s hand-padding. Only `p1_glade/ui/shop.luau`'s corner count
		left it fully undimensioned — the bare-glyph case the census exists to
		fix.

		AN EXPLICIT DIM STILL WINS, the same `or` every default above this line
		uses: this only reaches a badge whose author declared neither width nor
		height, which is every one of the census sites' own PROBLEM (they had to
		declare one BECAUSE nothing here did) and none of their shipped
		content — RR's/`adaptive_controls`'/`p4_foyer`'s explicit dims are
		unaffected byte-for-byte. ]]
	if props.surface == "badge" then
		local badgeMin = metrics.controls.badge and metrics.controls.badge.minimum
		if type(badgeMin) == "number" then
			layoutNode.width = layoutNode.width or { type = "minMax", min = badgeMin }
			layoutNode.height = layoutNode.height or { type = "minMax", min = badgeMin }
		end
	end
	-- DECORATION CONTENT INSETS. A nine-slice skin has a carved
	-- border that content must clear, so the recipe's `contentInsets` are
	-- SOLVER-VISIBLE: they are added to whatever padding the node already had,
	-- after every class default, so a Button's theme padding and its skin's
	-- border both apply. `chromeInsets` is empty for every flat package
	-- (Facet Neutral included) and this whole block is then a no-op, which is
	-- why swapping to an ornate theme moves geometry and swapping between two
	-- flat ones does not.
	--
	-- DECORATION OUTSETS (director fix round 2026-07-25) are the OTHER half, and
	-- they are the node's MARGIN rather than its padding: a bar's end-cap and
	-- centrepiece paint outside the track's own rect, so what has to move is the
	-- NEIGHBOURS — the label at one end, the readout at the other, and the rows
	-- above and below. Same classification, same one-time hint read; a flat
	-- package publishes an empty table and both blocks are then no-ops.
	-- THE OUTERMOST CLIPPER RESERVES THE SHADOW BLEED ON ITS CROSS AXIS
	-- (director report 2026-07-27, Glossy Mobile on a phone: "the way these
	-- controls are cutoff horizontally looks wrong given there's no horizontal
	-- scrolling. the view should narrow to accommodate them (and the glow
	-- underneath)").
	--
	-- `chromeBleed` is how far a package's shadow paints OUTSIDE the box it
	-- belongs to. It was spent in exactly one place — an allowance added to a
	-- ScrollView's CANVAS — so a glow past the LAST ROW becomes reachable by
	-- scrolling to it. That reasoning holds on the scroll axis and collapses on
	-- the other one: a y-axis scroller cannot be scrolled sideways, so canvas
	-- width buys nothing and the glow is simply cut by ClipsDescendants. Measured
	-- on a 390px phone, every reference package's widest child sat FLUSH with the
	-- scroller's right edge and lost its whole glow — 17px under Glossy Mobile,
	-- Glossy Touch and Fantasy Ornate, 24px under Sci-Fi HUD. The solver reported
	-- nothing, correctly: the bleed is PAINT, not layout.
	--
	-- `math.max`, NOT `+`. The requirement is that the gutter be AT LEAST the
	-- glow's reach, so a container that already insets its content by 16 owes only
	-- the missing 8 under Sci-Fi HUD and nothing at all under Glossy Mobile.
	-- Adding would have charged every scroller the full bleed twice over.
	--
	-- OUTERMOST ONLY, and that is the load-bearing part. Reserving on EVERY
	-- clipper desynchronises a composite control from its own header: a Table's
	-- rows live in an inner ScrollView while its header does not, so the rows
	-- inset and the header did not, and the columns came apart by exactly the
	-- bleed (caught by `tests/table.spec.luau` "the header tracks the rows"). An
	-- inner viewport is already inset by everything above it; the page's own
	-- clipper is the edge a control can actually sit flush against.
	--
	-- Nesting does not accumulate: reach is measured from each node's OWN box and
	-- an inner box can never lie outside its parent's, so a glowing view inside a
	-- glowing view overshoots by `bleed` and not by twice it (measured: 24px, not
	-- 72, under Sci-Fi HUD). `chromeBleed` is the package-wide MAXIMUM reach, so
	-- one reservation covers every slot at every depth — and it is 0 for any
	-- package that declares no shadow, so a flat theme is untouched and the
	-- neutral baseline cannot move.
	if kind == "scroll" and insideClipper ~= true and not chrome_slots.hasOnlyPlainLeaves(node) then
		local bleed = if type(metrics.chromeBleed) == "number" then metrics.chromeBleed else 0
		if bleed > 0 then
			local top, right, bottom, left = solver.sides(layoutNode.padding)
			if (props.axis or "y") == "x" then
				layoutNode.padding =
					{ top = math.max(top, bleed), right = right, bottom = math.max(bottom, bleed), left = left }
			else
				layoutNode.padding =
					{ top = top, right = math.max(right, bleed), bottom = bottom, left = math.max(left, bleed) }
			end
		end
		--[[ ...AND THE LEADING EDGE'S OWN RESERVE, STAMPED RATHER THAN SPENT
			HERE (task SHOWCASE3, 2026-08-29; supersedes 9eb095a, reverted).
			The cross axis above is safe unconditional: "reachable by scrolling
			to it" never applies to it either, but nothing has measured it
			collapsing a real box. The leading edge (top for y, left for x) is
			different — there is no canvas before scroll position 0 to grow
			into, so showing a first child's own glow costs real padding, and
			real padding taken from a box that cannot afford it is a blank
			scroller. 9eb095a spent it right here, unconditionally, and that is
			exactly what collapsed `overflow_sweep`'s `tab_view`/`p3_sipworks`
			to a 0px content box under Sci-Fi HUD at narrow-landscape: this
			pre-solve conversion sees only the node's own AUTHORED extent —
			`math.huge` for the common fill/hug scroll container — never the
			real offer a parent squeezing it actually has. So this only
			STAMPS the fact; `src/layout/solver.luau`'s `arrange` spends it
			floor-aware, against the rect it actually resolved. ]]
		layoutNode.leadingBleed = bleed
	end
	local chromeInsets = metrics.chromeInsets
	local chromeOutsets = metrics.chromeOutsets
	-- `hasChromeInsets`, not `next(chromeInsets)`: every slot now publishes an
	-- inset (zero when its art reserves nothing) so a control can READ one as a
	-- theme metric, which means the table's shape no longer tells you whether
	-- there is anything to spend. The snapshot answers that directly.
	local wantsInsets = chromeInsets ~= nil and metrics.hasChromeInsets == true
	local wantsOutsets = chromeOutsets ~= nil and next(chromeOutsets) ~= nil
	-- the HINT counts for the inset block below (a control that declared its own
	-- slot — a Slider's rail — would otherwise reserve the slot the generic map
	-- guessed instead of the one its art actually occupies), AND for the icon
	-- reservation after it. Read ONCE, above both, because the icon box is owed
	-- even by a package that reserves no chrome at all: Facet Neutral declares
	-- no `contentInsets` and still paints the framework's own pictures.
	local hint = chrome_slots.readHint(node)
	if wantsInsets or wantsOutsets then
		local slot = chrome_slots.classify({
			class = class,
			surface = props.surface,
			hasSelection = props.selected ~= nil,
			hint = if hint ~= nil then hint.slot else nil,
		})
		local extra = if wantsInsets and slot ~= nil then chromeInsets[slot] else nil
		if extra ~= nil then
			local top, right, bottom, left = solver.sides(layoutNode.padding)
			-- A CHROME INSET IS A REQUEST, NOT A RIGHT (director report
			-- 2026-07-28, defect 3). On a node whose size was decided FOR it, this
			-- sum can swallow the whole box: a Glossy Touch Button costs 12+12 of
			-- button padding plus 14+14 of `control` inset, and the scenario asked
			-- for a 52px button — so the content box was EXACTLY ZERO and the
			-- control rendered blank with no error anywhere.
			--
			-- The extent is only knowable here for an axis whose dimension carries
			-- a literal px; every other axis is decided later or grows to fit, and
			-- `math.huge` is the honest "no constraint" that makes the rule a
			-- no-op. Authored padding is never given back — that is an explicit
			-- instruction, and a box collapsed by it alone is still collapsed and
			-- still reported.
			local function extentOf(dim: any): number
				if type(dim) ~= "table" then
					return math.huge
				end
				if dim.type == "fixed" and type(dim.px) == "number" then
					return dim.px
				end
				--[[ ...AND A `minMax` CEILING IS AS KNOWABLE AS A `fixed` px (task THEME
					fix round, 2026-08-28, review finding I3). This is a CEILING test — "how
					much room can this axis ever have" — and `max` answers it exactly: a
					an axis whose
					`minMax` ceiling is 36 never solves wider than 36, so a frame that
					cannot fit inside 36 cannot fit inside it. Reading only the literal made
					the rule half-apply the same way the `aspect` branch below did before it
					was taught: measured under fantasy_ornate (`control` 14/10 per side), one
					`UI.Button{label = "X"}` at `fixed 36 x fixed 36` filed TWO chromeYields
					and the identical control with a `minMax` ceiling of 36 on both axes filed NONE —
					a 12px content box holding a 16px glyph, reported nowhere. `max` absent
					is an axis free to grow, which is `math.huge` and the no-op it was. ]]
				if dim.type == "minMax" and type(dim.max) == "number" then
					return dim.max
				end
				return math.huge
			end
			--[[ ...AND AN `aspect` AXIS IS AS KNOWABLE AS THE ONE IT FOLLOWS (task
				THEME, 2026-08-27). `shape = "circle"` is a fixed px on ONE axis and
				`aspect ratio = 1` on the other — the pairing a few dozen lines above
				enforces — so reading only the literal made the rule half-apply on every
				disc in the library: the HEIGHT gave its frame back and the WIDTH, seen
				as unbounded, kept charging for it. A 36px Pixel Quest round button then
				had 36px of height around a 4px-wide content box. The solver's own
				arithmetic is `w = h * ratio` / `h = w / ratio` (`measureUncached`), so
				it is followed here rather than approximated.

				IT IS THE ARITHMETIC AND NOT THE ROUNDING, and the difference is stated
				rather than left for a reader to spot (review Minor 8, 2026-08-28). The
				solver wraps both products in `num.roundPx`; this does not, because what
				it feeds is an AFFORDABILITY TEST — "is there room for a line of text
				inside this box" — and a half-pixel cannot change that answer without the
				box being within half a pixel of the floor, which is a box already
				reporting. Adding a rounding call here would import `num` into this file
				for a difference no assertion can see. At `shape = "circle"`'s ratio of
				1 — the only ratio this pairing produces today — the two are identical.

				A ZERO RATIO IS GUARDED ON BOTH BRANCHES, likewise. `h = w / 0` is why
				the second branch always had the test; `w = h * 0` yields a zero extent,
				which is not a crash but is a lie about the box, and it would refuse the
				whole inset on a node that has room. Neither is reachable from
				`shape = "circle"`; the guard costs one comparison and removes the
				asymmetry a reader would otherwise have to explain. ]]
			local wExtent, hExtent = extentOf(layoutNode.width), extentOf(layoutNode.height)
			local wDim: any, hDim: any = layoutNode.width, layoutNode.height
			if type(wDim) == "table" and wDim.type == "aspect" and type(wDim.ratio) == "number" and wDim.ratio ~= 0 then
				wExtent = if hExtent == math.huge then math.huge else hExtent * wDim.ratio
			elseif
				type(hDim) == "table"
				and hDim.type == "aspect"
				and type(hDim.ratio) == "number"
				and hDim.ratio ~= 0
			then
				hExtent = if wExtent == math.huge then math.huge else wExtent / hDim.ratio
			end
			--[[ THE FLOOR A CHROME INSET MAY NOT EAT THROUGH, and it is the node's own
				text (see `chrome_slots.spendInset`). A leaf that draws a string needs at
				least one line box of room or the string is reserved for and drawn into
				nothing; `layoutNode.text`/`textSize` are set by the class blocks above,
				so the number is already resolved and no re-measure happens here. Zero for
				every node that draws no string of its own, which is the rule that shipped
				before this line existed. ]]
			local textFloor = if type(layoutNode.text) == "string"
					and layoutNode.text ~= ""
					and type(layoutNode.textSize) == "number"
				then layoutNode.textSize
				else 0
			local wantX = extra.left + extra.right
			local wantY = extra.top + extra.bottom
			-- Native text editing uses the padded content box, unlike a full-bleed
			-- button label. Its padding must also leave room for the caret and text.
			local spentX = chrome_slots.spendInset(
				wExtent,
				left + right,
				wantX,
				textFloor + (if class == "TextField" then left + right else 0)
			)
			local spentY = chrome_slots.spendInset(
				hExtent,
				top + bottom,
				wantY,
				textFloor + (if class == "TextField" then top + bottom else 0)
			)
			-- "was it spent AS ASKED", not "is it non-zero": a slot that reserves
			-- nothing asks for nothing and gets exactly that, and reporting it as
			-- a yield would put a diagnostic on every flat scrollbar in the tree.
			local keepX = spentX == wantX
			local keepY = spentY == wantY
			layoutNode.padding = {
				top = top + (if keepY then extra.top else 0),
				right = right + (if keepX then extra.right else 0),
				bottom = bottom + (if keepY then extra.bottom else 0),
				left = left + (if keepX then extra.left else 0),
			}
			-- carry WHERE the padding came from, so the solver's collapsed
			-- content-box diagnostic can name the slot rather than only the node
			-- (rich-skinning v2)
			layoutNode.chromeSlot = slot
			-- ...and WHETHER it had to be given back, so the repair is reported
			-- rather than silent. Repaired is not the same as fine: a control too
			-- small for its own theme is exactly what an author needs told.
			if not keepX or not keepY then
				layoutNode.chromeYield = {
					slot = slot,
					x = if keepX then nil else extra.left + extra.right,
					y = if keepY then nil else extra.top + extra.bottom,
				}
			end
		end
		local outset = if wantsOutsets and slot ~= nil then chromeOutsets[slot] else nil
		if outset ~= nil then
			local top, right, bottom, left = solver.sides(layoutNode.margin)
			layoutNode.margin = {
				top = top + outset.top,
				right = right + outset.right,
				bottom = bottom + outset.bottom,
				left = left + outset.left,
			}
		end
	end
	-- THE ICON'S BOX IS A SOLVER FACT (director report 2026-07-28, defects 1+2).
	--
	-- A semantic icon request is an UPGRADE over the ASCII character the control
	-- draws itself, and that half was right. The half that was
	-- missing: the picture is a FIXED px square from `iconSizes`, centred on the
	-- node, and the node was measured as the CHARACTER. `">"` is 6px; Fantasy
	-- Ornate's `medium` rung is 32. The disclosure caret therefore painted 13px
	-- outside itself on every side — into the frame on one side and the label on
	-- the other. Measured live: SEVEN of the nine reference configurations
	-- overhang, Facet Neutral among them. It was never a theme's bug.
	--
	-- So the node reserves the picture, through the dimension vocabulary that
	-- already says "content, but never below this" — the same move `shape =
	-- "circle"` makes with `circleDiameter` a few dozen lines above.
	--
	-- ONLY WHEN THERE IS A PICTURE. `metrics.iconArt` is the snapshot's derived
	-- answer to "does this package paint this name". The two packages that looked
	-- correct before this change (glossy-touch, compact-pointer) are correct
	-- BECAUSE they draw no art, and an unconditional reservation would fix seven
	-- packages by breaking the two that were already right.
	--
	-- ONLY ON AN AXIS THE SOLVER DERIVES. An authored dimension is an instruction
	-- and still wins outright; the compact-label button in the same report is
	-- `width = 52` under a package whose frame leaves 28, and measure cannot grow
	-- it. That case is the paint seam's (screen_chrome clamps the drawn px to the
	-- box it was actually given) — the two halves cover the two directions.
	--
	-- The floor is the picture PLUS this node's padding, because padding is
	-- outside the content box the picture has to fit in, and the chrome insets
	-- above have already been folded in by the time we get here.
	local iconName = if hint ~= nil then hint.icon else nil
	if iconName == nil and type(props.icon) == "string" and props.icon ~= "" then
		-- the same fact reached through the public prop instead of the internal
		-- hint channel; an icon Button owes its picture exactly the same box
		iconName = props.icon
	end
	if iconName == nil and class == "Button" and #node.children == 0 then
		local form = compactForm(props)
		if form ~= nil and form.prefer and form.kind == "icon" then
			-- Preferred compact art is the content, just like an icon hint.
			iconName = form.icon
		end
	end
	if iconName ~= nil and type(metrics.iconArt) == "table" and metrics.iconArt[iconName] == true then
		local role = (if hint ~= nil then hint.iconSize else nil) or "medium"
		local px = if type(metrics.iconSizes) == "table" then metrics.iconSizes[role] else nil
		if type(px) == "number" and px > 0 then
			local pt, pr, pb, pl = solver.sides(layoutNode.padding)
			if layoutNode.width == nil then
				layoutNode.width = { type = "minMax", min = px + pl + pr }
			end
			if layoutNode.height == nil then
				layoutNode.height = { type = "minMax", min = px + pt + pb }
			end
			--[[ ...AND A DISC'S AUTHORED DIAMETER IS A FLOOR, NOT A CEILING
				(director report 2026-08-15, item 3: "this control seems cut off in
				each view", a crop of a round icon button whose circle reads as sliced
				at the left and right edges).

				The two branches above decline to touch an AUTHORED dimension, which is
				right for a rectangle — an authored width is an instruction, and the
				paint seam clamps the drawn picture to the box it was actually given.
				It is wrong for `shape = "circle"`, whose entire contract is a TRUE disc
				the author never computes: the diameter and the picture come from two
				INDEPENDENT theme metrics (a control metric and `iconSizes`) and nothing
				made them agree. Measured live in the showcase HUD, 2026-08-15, on a
				16 Pro landscape, across all nine shipped packages: classic-desktop is a
				22px disc holding a 20px picture (91%) and fantasy-ornate a 38px disc
				holding a 32px one (84%) — at which point the glyph runs to the rim and
				over it, and what a viewer sees is a circle cut off where the glyph
				crosses it. Facet Neutral (36/20) is why the default theme looked fine.

				So the authored axis is RAISED to hold its own picture, and the `aspect`
				pairing set a few dozen lines above carries the other axis with it — the
				disc stays a disc. Same repair as the `sponsor_drop` chevron plate: a
				floor, never a bigger constant. ]]
			if props.shape == "circle" then
				local need = px + math.max(pl + pr, pt + pb)
				--[[ ...AND A FLOOR IS A REQUEST, NOT A RIGHT (task THEME fix round,
					2026-08-28; review finding C1). Which is the same
					sentence the block a few dozen lines up is built on, at the other number
					that block decides — and this one had no such bound at all.

					The floor above grows the disc by whatever the chrome block just wrote
					into its padding, so a package that makes its `control` inset SPENDABLE
					(small enough that the line box survives it) hands the growth straight
					through: `iconSizes.medium` 32 plus 4+4 of newly-spent frame is a 40px
					disc where the host reserved 36. Measured 2026-08-28 on a Pixel Quest
					variant carving 4px per side — legal, every value a multiple of its own
					`pixelUnit`, its package gate green — the edit-mode delete disc solved
					40x40 at x=16 against a row starting at x=52. That is director item 9's
					photograph, reproduced by a legal package, because two theme facts
					decided one distance and nothing made them agree.

					`hint.footprint` is the host saying what it reserved, in the SAME
					expression it reserved it with (`chrome_slots.Hint`). Above it the floor
					is refused: the control keeps the room it was given, the paint seam's
					`chrome_slots.iconBoxPx` draws the picture at the size that fits, and
					`sizeRefused` tells the author the package wants a bigger picture than
					this control has room for. Refuse-or-catch rather than an overlap
					nothing reports. No hint = no reservation = the floor grows exactly as
					it did, which is every other disc in the library. ]]
				local reserved = if hint ~= nil and hint.footprint ~= nil
					then themeSnapshot.resolveTotal(metrics, hint.footprint)
					else nil
				if type(reserved) == "number" and reserved > 0 and need > reserved then
					layoutNode.sizeRefused = { want = need, reserved = reserved, icon = iconName }
					need = reserved
				end
				for _, axis in { "width", "height" } do
					local dim = (layoutNode :: any)[axis]
					if type(dim) == "table" and dim.type == "fixed" and type(dim.px) == "number" and dim.px < need then
						(layoutNode :: any)[axis] = { type = "fixed", px = need }
					end
				end
			end
		end
	end
	--[[ THE STORE ENTRY THIS BUILD IS REPLACING, read ONCE (ruling A-8, hoisted here
		by T15 from the `cmemo` block below — it is now read by two consumers on the
		way down and written by one at the end, and a second `store.byNode[node]` probe
		for the same answer is the cost this file exists to remove). Nothing between
		here and the entry write touches `store.byNode`, so the value is the same at
		either line. ]]
	local prior = if store ~= nil and store.reuse then store.byNode[node] else nil
	-- the axis this container imposes on its children (nil = not a stack)
	-- a wrapping stack imposes the SAME axis as the stack it is a mode of: a
	-- Divider inside a wrapping row is still a vertical rule (round 3 item A)
	local childAxis: string? = if kind == "hstack" or kind == "hwrap"
		then "x"
		elseif kind == "vstack" or kind == "vwrap" then "y"
		else nil
	--[[ ...AND THE CLIP THEY WERE BUILT UNDER, hoisted beside it and recorded on the
		entry for the reason T15's gate learned the hard way (see the kept-array block
		below): `kind` is NOT fixed for the life of a mounted node. `AdaptiveStack.axis`
		(`:529`), `VStack`/`HStack`'s `wrap` (`:523`, `:544`) and `Button`'s
		content/label split (`:560`) are all PROP-DECIDES-KIND seams whose whole
		guarantee is that a flip re-solves and never remounts. So the pair a container
		hands its children is a per-BUILD fact, not a per-node one. ]]
	local childClip = insideClipper == true or kind == "scroll"
	-- ...and whether they sit inside a control's content (the centred control line
	-- beside the `align` field above). A per-BUILD fact for the same reason the
	-- clip is: `Button`'s content/label split is one of the prop-decides-kind seams
	-- named just above, so a Button that gains its first child starts imposing this
	-- on a subtree that is not remounted.
	local childControl = insideControl == true or class == "Button"
	--[[ THE FOUR FACTS THE POST-CHILDREN FOLD USED TO RE-DERIVE BY WALKING THE ARRAY
		(Plan D, D2a). Three are the ORs `subtreeHasScroll` / `subtreeHasComposition` /
		`containerRelativeInside` are built from and the fourth is the placement audit's
		fast reject; all four are pure functions of the child layout nodes, so they are
		COUNTED as the array is built and carried on the store entry beside `n`. Counts
		rather than booleans because an OR cannot be undone: the patch arm below
		subtracts the child it replaces and adds the one it built, which a boolean fold
		could only do by walking the array again. ]]
	local kidScroll, kidComposition, kidInside, kidPlaced = 0, 0, 0, 0
	-- Baseline participation follows the existing kept/patched child summary.
	-- Re-scanning every sibling here would defeat the one-leaf layout fast path.
	local kidBaseline = 0
	-- ...and the patch's own index over this container's SPLICED children, carried
	-- with the array it describes and dropped whenever the array is rebuilt
	local kidIndex: { [string]: number }? = nil
	local kidMounts: { any }? = nil
	local kidRegions: { any }? = nil
	--[[ ...AND THE ONE FACT A DOWNSTREAM INDEX-KEYED PAYLOAD CANNOT DERIVE (Plan D,
		D2c): a token that is a FRESH table whenever this build rebuilt the children
		array from scratch, and the SAME table whenever it kept or patched one. Two
		builds that share it hold layout children with the same ids in the same order —
		the patch validates that in three layers and the kept arm is the same array —
		so a reader holding an index->id payload recorded under this token may trust its
		indices without re-scanning them. `layout/stack`'s arrange replay is the reader;
		its own header says why the scan it replaces is not optional. ]]
	local kidToken: any = nil
	if #node.children > 0 then
		--[[ THE CHILDREN ARRAY IS KEPT WHEN THE SHAPE UNDER IT DID NOT MOVE (Plan C,
			T15). A store HIT returns a whole subtree in two hash probes (`:386-395`); a
			MISS rebuilds the container AND re-visits every child — a fresh array, a
			fresh `appendChild` closure over eight upvalues, one `toLayoutNode` call and
			one `table.insert` per child. Each of those calls is itself a warm hit that
			returns immediately, so the loop is a five-figure count of cheap operations
			for a tree whose shape did not move.

			THE GATE IS TABLE IDENTITY *PLUS A `store.dirty` CHILD SCAN*, and the
			identity half alone is only a conservative superset (ruling A-14). Two things
			that look true here are not. `mount.luau:450` `node.children = newChildren`
			runs on EVERY `ForEach` reconcile, including when neither `changed` nor
			`orderChanged` is set (`:439-450`), so identity goes cold on frames where
			nothing moved — a silent loss of the arm, not a defect. And `node.children`
			IS mutated in place, at `mount.luau:197` (When exit-finish) and `:465`
			(ForEach exit-finish), each followed by `pushDirty(path, "structure")`
			(`:202`, `:470`). What identity means is therefore "the shape under me is the
			shape I built for, OR something changed that I will ALSO see in
			`store.dirty`" — and the scan below is what closes it. A LENGTH compare would
			accept a swap and hand a downstream reader a lost or duplicated node; a
			per-element compare would cost the loop it replaces.

			THE AXIS AND CLIP THE CHILDREN WERE BUILT UNDER ARE THEIR OWN TERMS, and
			the plan's reasoning for leaving them out was FALSE — the suite caught it.
			The claim was "`childAxis` is a pure function of `kind`, and `kind` is fixed
			for a mounted node, so validating the CONTAINER's `axis`/`clip` validates the
			children's". `kind` is NOT fixed: `AdaptiveStack.axis` (`:529`), `wrap` on a
			`VStack`/`HStack` (`:523`, `:544`) and a `Button` gaining children (`:560`)
			are prop-decides-kind seams whose stated guarantee is that a flip RE-SOLVES
			AND NEVER REMOUNTS. So an `AdaptiveStack` whose axis signal flips is dirty on
			its own path with clean children, which is precisely this arm's shape, and
			without `kidsAxis` it would serve a row's children a column's tree — measured
			as a Divider 280px wide where it must be 1 (`tests/adaptive.spec`, "follows an
			AdaptiveStack's axis flip with no rebuild"). `kidsAxis`/`kidsClip` are
			therefore recorded and compared, and the container's own `axis`/`clip` are
			kept beside them because this is the same entry gate the `cmemo` carrier
			rides; `parentAxis` is not an input to any child, so that half is
			conservative rather than load-bearing, and the spec says which is which.

			AND THE ARRAY IS NEVER MUTATED AFTER PUBLICATION. The moment it is reused it
			is shared between two `layoutNode`s across ticks, so an in-place edit would
			be a cross-tick aliasing bug. `tests/build_children_reuse.spec.luau` pins by
			source scan that the only writer of a layout node's `children` in this file
			is the fresh-array arm below.

			WHAT THIS ARM CAN AND CANNOT REACH, booked before it was measured.
			`store.dirty` is ancestor-closed over path prefixes, so a container holding a
			dirty descendant always fails the scan, and a container holding none never
			gets here — it is served whole at `:386-395`. The arm therefore fires for a
			container dirtied for its OWN reasons whose every child subtree is clean —
			an animating panel width, a gap that moves with a theme, a sidebar that
			resizes over a static list. Measured on the five FacetBench arena workloads,
			every step kind: the arm fires ZERO times there, because every one of their
			drives writes a signal on a LEAF. A per-index rebuild would reach the rest;
			it is DEFERRED (ruling A-9), and the reason is in the task report.

			TWO TERMS ABOVE ARE RECORDED NULLS, kept with their argument rather than
			deleted. `prior.kidsClip == childClip` cannot be falsified today because
			`kind == "scroll"` is class-fixed, so `prior.clip` already covers it — but
			that is exactly the inference `AdaptiveStack` falsified for the axis, and
			recording the value handed to the children costs one field. `prior.childArray
			~= nil` is covered by the identity term, because a node can only gain
			children by having its `children` table replaced. ]]
		local reusableKids = false
		-- the indices the PATCH arm rebuilds; nil means "no patch" (Plan D, D2a)
		local patchAt: { number }? = nil
		if store ~= nil and prior ~= nil then
			local gated = store.builtIds == nil -- a build that COLLECTS never reuses
				and prior.kids == node.children
				and prior.childArray ~= nil
				-- what the CHILDREN were built under, which is the correctness half
				and prior.kidsAxis == childAxis
				and prior.kidsClip == childClip
				and prior.kidsControl == childControl
				-- ...and where the CONTAINER sat, kept because this is the same gate
				-- the `cmemo` carrier rides and one gate is easier to reason about
				-- than two (see the block header for what each half is load-bearing for)
				and prior.axis == parentAxis
				and prior.clip == (insideClipper == true)
			reusableKids = gated
			if reusableKids then
				for _, child in node.children do
					if store.dirty[child.path] then
						reusableKids = false
						break
					end
				end
			end
			if gated and not reusableKids then
				--[[ THE SCAN REFUSED, WHICH IS THE LEAF-EDIT SHAPE (Plan D, D2a). Every
					term above still holds — same children table, same axis/clip pair,
					not a collecting build — so the array's VALUES stand at every index
					whose child is clean, and the only positions that need a
					`toLayoutNode` call are the dirty ones. `patchIndices` finds them
					from the dirty set and refuses (nil) on anything it cannot validate
					without walking. ]]
				patchAt = patchIndices(store, node, prior)
				if patchAt == nil then
					store.patchRefused += 1
				end
			end
			if reusableKids then
				--[[ NOTHING UNDER THIS CONTAINER MOVED: the array stands, and the
					subtree accounting comes off this container's own recorded `n` — the
					same arithmetic the per-child warm hit does with `hit.n`, done once.
					A build that COLLECTS is refused above because `builtIds` is spent as
					a licence to skip subtrees (`render/structural_scope.widen`) and a
					reused array constructs no child, so the list would be short by the
					whole subtree. ]]
				--[[ ...AND IT IS AN ASSIGNMENT, not a `+=`, which is sound only because
					the child loop below is the ONLY thing between this container's own
					`store.nodes += 1` and the entry write that recorded `n`. A second
					recursion site added between them would make this silently
					double-count — the count would still be plausible, and only
					`stats.lastLayoutNodes` and the skip arithmetic derived from it would
					be wrong. `prior.n` is read bare: the entry write records
					`n = store.nodes - nodesAtEntry` unconditionally, so there is no entry
					without it, and a fallback here would quietly substitute a number for
					a state that cannot occur. ]]
				layoutNode.children = prior.childArray
				store.nodes = nodesAtEntry + prior.n
				kidScroll, kidComposition, kidInside, kidPlaced =
					prior.kidScroll, prior.kidComposition, prior.kidInside, prior.kidPlaced
				kidBaseline = prior.kidBaseline
				kidIndex, kidMounts, kidRegions = prior.kidIndex, prior.kidMounts, prior.kidRegions
				kidToken = prior.kidToken
			end
		end
		if patchAt ~= nil and store ~= nil and prior ~= nil then
			--[[ THE PATCH (Plan D, D2a). A FRESH array receives the previous one's
				values in one `table.move` — the published array is never written into,
				which is owed row 11's invariant and the reason the copy is not skipped
				— and then the dirty indices alone are rebuilt.

				THE `store.nodes` ARITHMETIC IS THE FRAGILE PART, and it is the same
				identity the kept arm uses with one term per replaced child: start from
				`nodesAtEntry + prior.n`, SUBTRACT the subtree size the replaced child's
				own entry recorded (read BEFORE the rebuild overwrites that entry), and
				let each `toLayoutNode` call add the size it constructs. A clean child
				contributes exactly what the full loop's warm hit would have contributed
				— `hit.n` off the same entry — so `lastLayoutNodes` is unmoved by
				construction, and `lastNodeBuilds` is too: a clean child SERVES and
				`store.built` never sees it either way. ]]
			local kn = #prior.childArray
			local kept = table.create(kn)
			table.move(prior.childArray, 1, kn, 1, kept)
			store.nodes = nodesAtEntry + prior.n
			kidScroll, kidComposition, kidInside, kidPlaced =
				prior.kidScroll, prior.kidComposition, prior.kidInside, prior.kidPlaced
			kidBaseline = prior.kidBaseline
			kidIndex, kidMounts, kidRegions = prior.kidIndex, prior.kidMounts, prior.kidRegions
			kidToken = prior.kidToken
			local mounts = prior.kidMounts
			for _, idx in patchAt do
				local was = kept[idx]
				local baselineAlign = was.lineAlign or was.align
				if baselineAlign == "firstTextBaseline" or baselineAlign == "lastTextBaseline" then
					kidBaseline -= 1
				end
				if was.subtreeHasScroll then
					kidScroll -= 1
				end
				if was.subtreeHasComposition then
					kidComposition -= 1
				end
				if was.containerRelativeInside then
					kidInside -= 1
				end
				if was.placementProps ~= nil then
					kidPlaced -= 1
				end
				local mountChild = mounts[idx]
				store.nodes -= store.byNode[mountChild].n
				store.childVisits += 1
				local now =
					toLayoutNode(mountChild, metrics, textScale, prefOffset, childAxis, childClip, store, childControl)
				kept[idx] = now
				local baselineAlign = now.lineAlign or now.align
				if baselineAlign == "firstTextBaseline" or baselineAlign == "lastTextBaseline" then
					kidBaseline += 1
				end
				if now.subtreeHasScroll then
					kidScroll += 1
				end
				if now.subtreeHasComposition then
					kidComposition += 1
				end
				if now.containerRelativeInside then
					kidInside += 1
				end
				if now.placementProps ~= nil then
					kidPlaced += 1
				end
			end
			layoutNode.children = kept
		elseif not reusableKids then
			layoutNode.children = {}
			local function appendChild(child: any)
				-- structural regions (When/ForEach) own MOUNTING, not layout:
				-- their children splice into the parent's flow so fill dims and
				-- stack math behave as if the region wrapper did not exist
				if child.class == "When" or child.class == "ForEach" or child.class == "ErrorBoundary" then
					for _, grandchild in child.children do
						appendChild(grandchild)
					end
				else
					if store ~= nil then
						store.childVisits += 1
					end
					--[[ ...AND THE FOUR COUNTS ARE TAKEN HERE, on the one pass that
						already touches every child, rather than in a second walk after
						it (Plan D, D2a). ]]
					local built =
						toLayoutNode(child, metrics, textScale, prefOffset, childAxis, childClip, store, childControl)
					local baselineAlign = built.lineAlign or built.align
					if baselineAlign == "firstTextBaseline" or baselineAlign == "lastTextBaseline" then
						kidBaseline += 1
					end
					if built.subtreeHasScroll then
						kidScroll += 1
					end
					if built.subtreeHasComposition then
						kidComposition += 1
					end
					if built.containerRelativeInside then
						kidInside += 1
					end
					if built.placementProps ~= nil then
						kidPlaced += 1
					end
					table.insert(layoutNode.children, built)
				end
			end
			for _, child in node.children do
				appendChild(child)
			end
			-- a REBUILT array is a new sequence as far as any index-keyed reader knows
			kidToken = {}
		end
		--[[ ── THE SIBLING PLATE'S CARVED BORDER, AND WHY THE FRAMEWORK DOES NOT
			SPEND IT (task THEME, director items 7-8) ──────────

			The theme contract promises that a nine-slice skin's `contentInsets` are
			SOLVER-VISIBLE — "a carved border that content must clear". The block a few
			hundred lines up keeps that promise by adding the inset to the SURFACED
			NODE'S OWN padding, which is right whenever the plate is the content's
			parent, and cannot be kept at all for the library's other plate idiom:

			    UI.ZStack{ UI.Box{ surface = ..., width = fill, height = fill }, content }

			The HUD's `glass()` builds one, `selection_indicator`'s pill builds one, and
			a consumer reaching for a tinted panel builds one (the tint channel is a
			Box's, so the plate CANNOT be the stack itself). There the reservation lands
			on a node with no children, nothing spends it, and the content — a SIBLING —
			paints over the frame. Measured 2026-08-28 by `tools/lune/theme_containment_census`
			— the committed instrument, so this number is a RUN rather than a claim
			(review finding I1; it replaces a 494 that reproduced as nothing) — over 63
			surfaces x 9 viewports x 8 packages: **2,472 hits, 103 distinct by (surface,
			node)**, which is the dedup rule the backlog is booked against because one
			construction is one defect. The five packages that carve anything hold
			2,458 of them; the three flat ones hold 14, and those are NOT this class —
			a flat package still moves geometry through its metrics, so "0 under every
			flat one" (which this comment used to claim) was never measured and is not
			true. The neutral arm is 0. Judged against the plain RECT with the same
			packages installed — the vocabulary before the themed rules — it is 270/42,
			and the difference between 42 and 103 IS what teaching the guard bought.

			THE OBVIOUS REPAIR WAS BUILT, MEASURED AND REJECTED, and the number is why:
			handing the plate's inset to the stack's other children turns the HUD's
			objective pill from 116x41 into 92x85 under Fantasy Ornate, because a
			package's `panel` recipe is a WINDOW frame (30px per side there) and this
			idiom wears it on chips and pills too. Making every small plate grow by a
			window's border is a worse answer than the defect. Deciding that a `raised`
			chip is not a window is a THEME question — which slot a small plate should
			classify into — and belongs to a round that can re-spec the packages, not to
			a bug fix.

			SO THE FRAMEWORK REPORTS RATHER THAN REPAIRS. `tests/lib/overflow_guard`
			treats a full-bleed surfaced sibling as the boundary its stack really has, so
			every one of those 103 is now a finding a spec can fail on, and
			`tests/themed_containment.spec.luau` holds the four surfaces the director
			photographed to it. That is the half of "refuse-or-catch" this seam can
			honestly deliver. ]]
		-- THE PARENT-SIDE PLACEMENT AUDIT (parity round 2 §2.1). `anchor`,
		-- `offsetX`, `offsetY`, `alignH`, `alignV`, `lineAlign` and `gridSpan` are
		-- legal on every node but read only by particular parent arrange branches;
		-- anywhere else they are accepted and then ignored, which constitution §4
		-- forbids. A child cannot check this itself — it does not know its parent
		-- at its own construction — so the parent does, and it happens HERE for
		-- two reasons no other seam has together:
		--
		--   1. this is where `class` has already become the layout `kind`, so the
		--      audit asks what the SOLVER will read and not what the constructor
		--      was called;
		--   2. `appendChild` has already spliced `UI.When`/`UI.ForEach`/
		--      `UI.ErrorBoundary` children into this node's flow, so a row emitted
		--      by a ForEach is audited against the real parent it lands in — the
		--      case a construction-time check structurally cannot see.
		--
		-- The findings ride on the layout node and are reported by `arrange`,
		-- which is what gates them behind `hiddenDepth` and replays them through
		-- the incremental-layout reuse path.
		--[[ ...AND THE COUNT IS THE AUDIT'S OWN FAST REJECT, HOISTED OUT OF ITS LOOP
			(Plan D, D2a). `auditPlacement`'s first act per child is `if
			child.placementProps == nil then continue end`, so a container none of whose
			children carries a placement prop can only return nil — and `kidPlaced` is
			exactly that population, counted where the array was built and carried on the
			entry, so the kept and patched arms answer it without a walk. ]]
		if kidPlaced > 0 then
			layoutNode.inertPlacement = solver.auditPlacement(kind, layoutNode.id, layoutNode.children)
		end
	end
	-- "A `containerRelative` DIMENSION LIVES SOMEWHERE IN HERE" (§2.5 x incremental
	-- layout — RED-TEAM Milestone 1, HIGH 3). Computed here for the same reason
	-- `placementProps` and `inertPlacement` are: it is a fact about the built tree,
	-- the branches above have finished rewriting `width`/`height` by this line, and
	-- the alternative is asking it per solve in the hot arrange path.
	--
	-- WHY THE SOLVER NEEDS IT. `arrange`'s reuse skip replays a subtree when nothing
	-- inside it is dirty and it lands on the rect it already had. Every dimension
	-- the solver had before §2.5 is a function of the parent's offer, which that
	-- rect carries — so the argument held. A `containerRelative` dimension is a
	-- function of the nearest scroll VIEWPORT, which the ancestor's rect does not
	-- mention, so the skip could replay a size the container no longer allows. The
	-- solver refuses the skip for a marked subtree whose container has moved.
	--
	-- THE MARK STOPS AT A `scroll` NODE, and that is an argument, not a shortcut: a
	-- scroller pushes its OWN inner size as the container for everything below it,
	-- and that inner size is derived from the scroller's own rect — which the
	-- replay reproduces exactly. A `containerRelative` node under an inner scroller
	-- is therefore genuinely insulated from the enclosing container. The scroller's
	-- OWN dimensions are not: they resolve against the container outside it, so
	-- `selfRelative` is tested for every kind.
	--[[ THE LOOP BELOW VISITS EVERY CHILD, where it used to `break` on the first
		`containerRelativeInside` one (C2, 2026-09-04). The two new booleans are ORs
		over ALL children, so there is nothing to stop early for; `wantInside` keeps the
		old rule exactly — once `inside` is true nothing re-reads it, and the `scroll`
		stop still applies to it alone. The cost is the same walk either way: the early
		exit only ever fired on a tree that HAS a container-relative child, which is a
		small minority, and it saved at most the tail of one child list. ]]
	local selfRelative = (layoutNode.width ~= nil and layoutNode.width.type == "containerRelative")
		or (layoutNode.height ~= nil and layoutNode.height.type == "containerRelative")
	local inside = selfRelative
	--[[ ...AND THE TWO THE MEASURE SERVE GATES ON, computed in this same pass because
		it is the same shape and the same walk: a fact about the built subtree, asked
		once here instead of per solve in `measure`.

		SELF-INCLUSIVE, which is an argument rather than a convenience.
		`solver.measure` may answer a clean node from numbers on the node itself, and a
		tuple of numbers cannot carry `ctx.hasScroll` or `ctx.compositions[node.id]` —
		but `ctx.hasScroll` is set for the SCROLL NODE ITSELF and `ctx.compositions` is
		written for the composition node itself, so a child-only OR would leave the
		OWNER of each channel ungated and a served ScrollView would drop its own
		publish. `tests/measure_serve.spec.luau` carries the full channel table.

		AND THE SCROLL MARK DOES NOT STOP AT A SCROLLER the way `containerRelativeInside`
		does. That stop is about a scroller INSULATING its subtree from the enclosing
		container, which is a statement about what a size depends on; these two are
		about which node PUBLISHES a channel, and an outer scroller publishes its own
		regardless of what is beneath it. ]]
	--[[ ...AND THE THREE ARE NOW READ OFF THE COUNTS (Plan D, D2a), which is the same
		fold expressed as three comparisons: `scrollInside`/`compositionInside` were ORs
		over every child, and `inside` was an OR guarded by `wantInside` — `not
		selfRelative and kind ~= "scroll"` — which is preserved verbatim below because
		`inside` starts as `selfRelative` and nothing re-reads it once true. ]]
	local scrollInside = kind == "scroll" or kidScroll > 0
	local compositionInside = kind == "composition" or kidComposition > 0
	inside = inside or (kind ~= "scroll" and kidInside > 0)
	-- D2c's token rides on the layout node because the arrange replay is handed the
	-- layout node and never the store; `nil` on a store-less build, which is why every
	-- reader compares it against a NON-NIL recorded value
	layoutNode.kidToken = kidToken
	layoutNode.containerRelativeInside = inside or nil
	layoutNode.subtreeHasScroll = scrollInside or nil
	layoutNode.subtreeHasComposition = compositionInside or nil
	--[[ THE CONTAINER MEMO'S HOME IS THE STORE ENTRY, NOT THE LAYOUT NODE (Plan C,
		ruling A-8). `store.byNode` is keyed by the MOUNT node and is weak
		(`WEAK_KEYS`, this file's `newStore`), so an entry outlives every rebuild of the
		solver `Node` — and a rebuild is exactly what a container holding one dirty
		child gets: the warm-hit path above requires `not store.dirty[node.path]`, and
		`store.dirty` is the renderer's ancestor-closed set. A memo living on the layout
		node would therefore be nil on every tick the levers that read it target, and
		the lever would measure zero.

		THE POINTER IS REFRESHED, THE TABLE IS NOT REBUILT. `./layout/stack_measure`
		reads `node.cmemo` — one field — and the table it points at is the one the
		previous build produced, WHEN all three validity terms hold: the mount children
		table is the same OBJECT, and the two inputs the warm-hit lookup above cannot
		re-derive, `axis` and `clip`, are the same. Otherwise a fresh empty table —
		never a stale one.

		AND THE `kids` TERM IS A CONSERVATIVE SUPERSET, NOT A SUFFICIENT CONDITION
		(ruling A-14). It compares the MOUNT node's children table; the array the memo
		indexes is the LAYOUT node's SPLICED flat list, in which a `UI.ForEach` region's
		insert shifts every later index while this term still holds — `mount` replaces
		the REGION's children, never its parent's. Every index-keyed payload on this
		table therefore carries its own per-child id key; this gate alone is not enough
		to trust an index and no reader may treat it as if it were. ]]
	layoutNode.baselineAligned = kidBaseline > 0
		or layoutNode.align == "firstTextBaseline"
		or layoutNode.align == "lastTextBaseline"
	local cmemo = if prior ~= nil
			and prior.kids == node.children
			and prior.axis == parentAxis
			and prior.clip == (insideClipper == true)
		then prior.cmemo
		else nil
	if cmemo == nil and store ~= nil and store.reuse then
		cmemo = {}
	end
	layoutNode.cmemo = cmemo
	if cmemo ~= nil then
		--[[ ...AND WHETHER THIS BUILD WAS A STRUCTURAL ONE (T13b, owed row A2). It is
			STICKY-TRUE ON PURPOSE only until the next completed full pass: a container
			built on a structural tick keeps the flag until `contentSize` runs a whole
			pass and clears it, because every index there is either id-verified or
			freshly recorded, which is precisely the fact this flag stands in for. A
			flag cleared here instead would be cleared on ticks that never re-derived
			the index bindings. ]]
		cmemo.struct = store ~= nil and store.structural == true
	end
	if store ~= nil and store.reuse then
		-- LAST, so a node that threw builds no entry. `axis`/`clip`/`control` are
		-- recorded beside the tree because they are the three inputs the lookup above
		-- cannot re-derive from the node it is holding.
		store.byNode[node] = {
			built = layoutNode,
			axis = parentAxis,
			clip = insideClipper == true,
			control = insideControl == true,
			n = store.nodes - nodesAtEntry,
			-- ruling A-8: the memo's durable home, and the mount children table its
			-- index-keyed arrays are only valid against. Compared by IDENTITY, never
			-- iterated.
			cmemo = cmemo,
			kids = node.children,
			--[[ ...and the built array itself (T15), under the SAME `kids`/`axis`/
				`clip` gate the memo above rides, plus a `store.dirty` scan over the
				mount children. Compared by nothing — it is a VALUE the next build may
				adopt whole — and NEVER MUTATED once published, because adoption makes
				it shared between two layout nodes across ticks. ]]
			childArray = layoutNode.children,
			kidsAxis = childAxis,
			kidsClip = childClip,
			kidsControl = childControl,
			--[[ ...and D2a's four counts plus the index that describes the array beside
				them. The index is nil on the arm that BUILT a fresh array (the positions
				it described belong to the array that was replaced) and is carried
				forward by the kept and patched arms, whose positions are unchanged —
				which is what makes the lazy build in `patchIndices` a once-per-array
				cost rather than a per-tick one. ]]
			kidScroll = kidScroll,
			kidComposition = kidComposition,
			kidInside = kidInside,
			kidPlaced = kidPlaced,
			kidBaseline = kidBaseline,
			kidIndex = kidIndex,
			kidMounts = kidMounts,
			kidRegions = kidRegions,
			kidToken = kidToken,
		}
	end
	return layoutNode
end

--[[ ── THE CROSS-SOLVE NODE STORE (perf campaign P3, 2026-09-01) ───────────────

	`renderer.solveAndApply` called `toLayoutNode(root.node, …)` on EVERY solve and
	rebuilt the whole mounted-tree -> `solver.Node` translation from scratch: one
	table per node, one `textOf` closure per node, and every theme token re-resolved
	through `themeSnapshot.resolveDim`/`resolveSides`/`resolveNumber`/`resolveSize`/
	`effectiveTypeRole`. Measured headless on `battle_hud`, 2026-09-01
	(`FacetBench/tools/profile/probe`, variant D): **0.51 ms / 666 kb at S (525 nodes),
	2.66 / 2,609 at M, 6.22 / 6,507 at L** — every solve, whether one leaf moved or
	nothing did, and 1.28 kb per node of the step's allocation.

	THE STORE IS ONE SLATE PER MOUNTED NODE, and the reason it can be one at all is
	that `toLayoutNode` reads exactly FOUR fields of the node it is handed —
	`class`, `path`, `props`, `children` (grep `node%.` over this file) — plus the
	five solve-wide inputs below. `class` and `path` are fixed for the life of a
	mounted node; `props` is written in exactly ONE place in the framework
	(`mount.luau`'s dynamic-prop observer) and `children` in exactly one region
	(`mount.luau`'s `When`/`ForEach`/`ErrorBoundary` reconcilers), and **every one of
	those writes pushes a dirty entry for that node's path**. That is what makes the
	invalidation set complete rather than hopeful.

	FOUR AXES, and they are deliberately the same shape as `layout/measure_reuse`'s.

	AXIS 1 — THE NODE. Keyed by the mounted node TABLE, not by its path, so a
	`ForEach` that removes a row and later mounts a NEW one at the same key cannot be
	answered with the old row's tree. A path key would need a removal sweep to be
	safe; a table key is safe by construction.

	**A KEY THAT COMES BACK DOES NOT ALWAYS BRING A NEW TABLE, and the honest version
	is the interesting one** (P3 review, M3). `ForEach`'s RE-ENTRY MID-EXIT path
	(`mount.luau`, the `retiring[key]` branch) hands back **the same mounted row** —
	same table, same scope, same instances — when a key returns while its exit is still
	playing, and `When` does the same for a re-entered branch. Serving that row its
	cached tree is not a bug, it is the correct answer: nothing about its `props` or
	`children` changed. What DID change is where it sits in the parent's flow, and the
	region's own `pushDirty(path, "structure")` marks that — so the LIST rebuilds and
	re-splices while the row itself is served. A row that genuinely died and came back
	is a fresh `mountNode`, a fresh table, and a miss.

	AXIS 2 — WHAT CHANGED INSIDE IT. `dirty` is the renderer's dirty set closed over
	ANCESTORS — every path with a dirty entry of ANY class plus every ancestor of one.
	Any class, not just `measure`/`arrange`: `label`, `icon` and `compactLabel` are
	paint-classed and this seam sizes boxes with them, so the narrower set
	`arrange` already uses (`reuse.dirtyContains`) would be wrong here. A node in the
	set rebuilds; a node absent from it has no change on itself or below it, which is
	exactly the claim a subtree-shaped cache needs.

	AXIS 3 — WHAT CHANGED AROUND IT. `metrics` (the applied ThemeSnapshot),
	`textScale` and `prefOffset` are solve-wide: none of them dirties a node, so axis 2
	cannot catch one. All three are held on the store AS THEMSELVES and compared once
	per build; any change drops the whole store. `metrics` compares by IDENTITY — `~=`
	on the table — and that is the literal comparison rather than a stamp derived from
	it: a `tostring(metrics)` key compares ADDRESS STRINGS, and an address is reused
	once its table is collected, so a swap to a snapshot that landed where the old one
	had been would read as unchanged and serve the old tree (P3 review, M1). See AXIS 3
	IS APPLICATION, NOT EMISSION below.

	AXIS 4 — WHERE IT SITS. `parentAxis` and `insideClipper` ride the recursion and
	can move without the node moving. They are stored per entry and checked at the
	lookup, not at the stamp.

	**AXIS 3 IS APPLICATION, NOT EMISSION**, and that distinction has cost this
	project a round before. A theme package EMITS tokens; what this seam reads is what
	the surface has APPLIED — `renderer.currentMetrics()`, which reads
	`env:get("themeMetrics")` fresh at every use precisely because "the swap
	transaction sets it and re-solves in the same invocation". So the key is the
	snapshot VALUE the build actually resolved against, taken at the build. A key on a
	theme-changed signal, a package id or a generation counter would be keyed on
	emission and would answer a solve that had not yet been handed the new snapshot.
	`themeSnapshot.neutral()` is memoised (`neutralCache`), so the fallback arm is a
	stable identity too rather than a permanent miss.

	THE STORE IS WEAK IN ITS KEYS, which is what bounds it. A removed node is
	unreachable the moment its region drops it and its scope disposes, so its entry
	goes with it and a churning `ForEach` cannot grow the store forever. This is the
	one weak-table shape that works in Luau — where weak tables are NOT ephemerons, so
	a value that reaches its own key pins the pair alive. **The entry's value must
	never reference the mounted node**: a `solver.Node` carries `id = node.path` (a
	string), resolved numbers, and child `solver.Node`s — no mounted-node reference on
	any path. `tests/node_reuse.spec.luau` pins that as a reachability walk rather than
	as a promise — one that FAILS on any function or userdata value and on any
	metatable, because a closure captures its upvalues invisibly and removing a per-node
	closure is exactly what this seam did; a walk that stepped over functions would be
	blind to the one regression shape it exists to catch.

	INTERPLAY WITH P1 AND P2, because both key on node identity and this changes what
	that means. `measure_reuse`'s slate and the solve's rect map are both keyed by
	`node.id`, which IS `node.path` and is stamped at build time from the mounted
	node — so a PATCHED tree carries exactly the ids a rebuilt one would, for exactly
	the same node set. What changes is the one thing `measure_reuse`'s AXIS 1 note
	says about this file: the per-solve memo's key, the node TABLE, is no longer a
	different object each solve. That makes the per-solve memo warmer, never wrong —
	it is a fresh table per `ctx` either way.
]]

export type Store = {
	attachOpts: any,
	--[[ THE THREE AXIS 3 INPUTS THE ENTRIES WERE BUILT UNDER, held as themselves.
		`metrics` is the applied ThemeSnapshot compared with `~=`, which is what
		"identity" means and what the header says: a `tostring(metrics)` stamp would
		compare ADDRESS STRINGS, and Luau reuses an address once a table is collected,
		so a swap to a snapshot that landed where the old one had been would read as
		unchanged and serve the old tree (P3 review, M1). One reference is also
		cheaper than a formatted string per build. ]]
	metrics: any,
	textScale: number,
	prefOffset: number,
	-- mounted node -> { built, axis, clip, control }. WEAK IN ITS KEYS (see above).
	byNode: any,
	-- axis 2, the ancestor-closed dirty set for THIS build
	dirty: { [string]: boolean },
	-- nodes CONSTRUCTED by the last build. The P3 demonstrator: a clean re-solve is
	-- 0 and a one-leaf update is bounded by the touched closure, where both were N.
	built: number,
	-- ...and their PATHS, when the caller asked for them (P5). `nil` on every build
	-- that does not spend the list, which is all of them but the structural ones.
	builtIds: { string }?,
	-- every layout node the last build's TREE holds, constructed or served (P5)
	nodes: number,
	--[[ ...and the CHILD POSITIONS the last build's rebuild loop visited (Plan C,
		T15) — one per `toLayoutNode` call `appendChild` made, spliced regions counted
		at the grandchildren they contribute and never at the region itself. It is the
		denominator the kept children array moves, and it is NOT `built`: almost every
		one of these visits is a warm store hit that constructs nothing, which is
		exactly why `built` cannot see the loop. ]]
	childVisits: number,
	--[[ ...and the number of containers whose kept-array gate held but whose PATCH
		(Plan D, D2a) refused: a region whose children table moved, an array whose slots
		did not answer to their mounted children, or a dirt set wider than the budget.
		Read by `tests/build_index_patch.spec.luau` off the store itself — the renderer
		sits at its Source-write cap and this counter is not worth a seam. ]]
	patchRefused: number,
	--[[ ...and the DIRTY-SET ITERATIONS those patch attempts spent (Plan D, D3b). The
		refusal count above says how often the arm gave up; this says what it READ to
		decide, and it is the only counter that can see the O(dirty x containers) term
		the probe budget bounds — a container that patches successfully leaves
		`patchRefused` at zero however wide the set it walked. Read off the store by
		`tests/build_index_patch.spec.luau`, for the same reason `patchRefused` is. ]]
	patchProbes: number,
	--[[ ...and the widest lower bound on `store.dirty`'s SIZE this pass has
		established (Plan D, D3b). One fixed table serves the whole build, so the first
		bounded walk answers the size question for every container after it and the probe
		budget becomes a comparison rather than a walk. Reset per build, beside the
		counters, because it describes ONE dirty set. ]]
	dirtySeen: number,
	-- false makes this a COUNT-ONLY store: no lookup, no write, no entry. The
	-- oracle's honest pre-fix control (see the count-only arm in `toLayoutNode`).
	reuse: boolean,
	--[[ WAS THIS BUILD PART OF A STRUCTURAL SOLVE? (Plan C, T13b.) The renderer
		already answers that question at the call site — `structural ~= nil` is
		`build`'s `collect` argument — and T13b's aggregate needs exactly it: a pass
		that never looks at an index cannot check that index's id, so it refuses to run
		on the one class of tick where the layout children SEQUENCE can change under an
		unchanged mount children table. Reading it here costs the renderer nothing and
		spends zero of its own character budget. ]]
	structural: boolean?,
}

local WEAK_KEYS = table.freeze({ __mode = "k" })

-- `reuse == false` builds a COUNT-ONLY store: the counter still reports N, and
-- nothing is looked up, allocated or stored. That is the differential oracle's
-- control arm and it must cost what the pre-P3 build cost.
-- `attachOpts` is the renderer's own `RendererAttachOpts`, kept so `hostSpaceOf`
-- can ask the boundary predicate the same question `ensureTree` asks — the only
-- key it reads is `translateHosts`
function layout_node.newStore(reuse: boolean?, attachOpts: any?): Store
	return {
		attachOpts = attachOpts,
		metrics = nil,
		textScale = 0 / 0,
		prefOffset = 0 / 0,
		byNode = setmetatable({}, WEAK_KEYS),
		dirty = {},
		built = 0,
		builtIds = nil,
		nodes = 0,
		childVisits = 0,
		patchRefused = 0,
		patchProbes = 0,
		dirtySeen = 0,
		reuse = reuse ~= false,
		structural = false,
	}
end

-- build(store, node, metrics, textScale, prefOffset, dirty) -> solver.Node
--
-- `dirty` nil means "rebuild everything": the store starts again from an empty
-- table rather than being cleared in place, so a full build costs one allocation
-- and not one delete per stale entry. That is the arm a structural change, a first
-- solve, a feedback re-solve and the reuse-disabled build all take.
function layout_node.build(
	store: Store,
	node: any,
	metrics: any,
	textScale: number,
	prefOffset: number,
	dirty: { [string]: boolean }?,
	collect: boolean?
): solver.Node
	--[[ P5's list, armed per BUILD rather than per store, and reset here so it can
		never describe an earlier one. A COUNT-ONLY store fills it with every node, and
		that is correct rather than wasteful: the caller's set then covers the whole
		tree, nothing is skipped and every slate is dropped, which is exactly the
		pre-P5 full solve. See `render/structural_scope.widen`. ]]
	store.builtIds = if collect == true then {} else nil
	-- ...and T13b's flag, off the SAME argument and on the same line of reasoning: a
	-- structural refresh either produces a plan (`collect == true`, and the container
	-- aggregate refuses) or produces none, in which case `dirtyContains` is nil, the
	-- solve is handed no `reuse` set at all and the container memo cannot HIT. There is
	-- no third arm — `tests/container_aggregate.spec.luau` carries the enumeration.
	store.structural = collect == true
	if store.reuse then
		-- axis 3 by identity and by value; `metrics` is the APPLIED snapshot, never a
		-- string derived from it (see `Store.metrics`)
		if
			dirty == nil
			or store.metrics ~= metrics
			or store.textScale ~= textScale
			or store.prefOffset ~= prefOffset
		then
			store.metrics = metrics
			store.textScale = textScale
			store.prefOffset = prefOffset
			store.byNode = setmetatable({}, WEAK_KEYS)
			store.dirty = {}
		else
			store.dirty = dirty
		end
	end
	store.built = 0
	store.nodes = 0
	store.childVisits = 0
	store.patchRefused = 0
	store.patchProbes = 0
	store.dirtySeen = 0
	return toLayoutNode(node, metrics, textScale, prefOffset, nil, nil, store, nil)
end

layout_node.compactForm = compactForm
layout_node.drawnButtonText = drawnButtonText
layout_node.effectiveHitFloor = effectiveHitFloor
--[[ NOBODY IN `src/` CALLS THIS ANY MORE — the renderer goes through `build` — and it
	is exported anyway, on purpose: `FacetBench/tools/profile/lib_attr.luau` patches
	`layout_node.toLayoutNode` and `layout_node.build` by name to time the build stage,
	and the recursion is a module local it cannot reach. Removing the export would make
	every profiling harness in that repo report the stage as 0.000 ms. It is also the
	one-shot entry a caller with no store wants. ]]
layout_node.toLayoutNode = toLayoutNode
-- the two the translate lane needs, and it needs them for the reason
-- `applyPlacement`'s own header states: one copy of what a placement prop means
-- on a layout node, and one copy of how a theme metric becomes an offset.
layout_node.applyPlacement = applyPlacement
layout_node.resolveOffset = resolveOffset

return layout_node
