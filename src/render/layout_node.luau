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
	  layout_node.toLayoutNode(node, metrics, textScale, prefOffset, parentAxis?, insideClipper?) -> solver.Node
	  layout_node.compactForm(props) -> { kind, ... }?
	  layout_node.drawnButtonText(props, compact?) -> string
	  layout_node.effectiveHitFloor(class, metrics) -> number?

	WHY IT IS ITS OWN FILE. Roblox refuses a `Script.Source` assignment at 200,000
	characters or more, and every LIVE path is a write — the Rojo plugin,
	`execute_luau`, any plugin — so a module over the cap silently stops syncing
	into an open Studio session and a live check against it then tests the code
	baked into the place rather than the edits on disk
	(docs/lessons/the-200k-source-cap-is-on-writing-not-loading.md). `renderer.luau`
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
-- does for a content button). That order is ADR-0020 R4's tofu fix applied to a
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
-- `metrics` is the active ThemeSnapshot (ADR-0019 §2): THE resolution point for
-- semantic metric names. A prop that names a role/step/metric path becomes a
-- number here, on every solve, which is exactly why a theme swap moves geometry
-- without touching the mounted graph. A literal number passes through untouched
-- and is thereby explicitly theme-independent.
-- a label with no whitespace: one word, and therefore nothing the engine may
-- legally break. Numbers count as words. See the Button branch below.
-- AN OFFSET MAY BE A FRACTION OF THE PARENT (ADR-0022 Decision 6). A
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
-- owns the VALUE, and floors clamp UP only (ADR-0019 §2 step 4) — a package may
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

local function toLayoutNode(
	node: any,
	metrics: any,
	textScale: number,
	prefOffset: number,
	parentAxis: string?,
	-- true once ANY ancestor is a clipping scroll container. Only the OUTERMOST
	-- clipper reserves the shadow bleed (see the block below), so this rides the
	-- recursion the same way `parentAxis` does.
	insideClipper: boolean?
): solver.Node
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
		-- ADR-0023: a screen-level container whose children are ranked regions.
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
		align = props.align,
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
		anchor = props.anchor,
		offsetX = resolveOffset(metrics, props.offsetX),
		offsetY = resolveOffset(metrics, props.offsetY),
		-- "this node carries at least one placement prop", set here because every
		-- one of the NINE values is already in hand on this line. It is what makes
		-- the parent-side inert-placement audit (§2.1, below) affordable in the
		-- arrange path: the overwhelming majority of nodes carry none, and the
		-- audit's per-child cost for them is this ONE field test rather than nine
		-- table lookups. Measured: the per-lookup form cost +1.5-2.4% on the
		-- 100-cell perf aggregate against a 0.31-0.65% same-arm floor.
		--
		-- `layoutPriority`/`shrinkWeight` are here because they are placement props
		-- exactly like the other seven — only a stack's shrink pass reads either one —
		-- and were missing from this set and from the solver's own table until the
		-- Milestone-1 review (C2). THIS TEST IS THE AUDIT'S ONLY GATE: a prop absent
		-- here is unpoliced however complete `PLACEMENT_PROPS` is.
		placementProps = (
			props.anchor ~= nil
			or props.offsetX ~= nil
			or props.offsetY ~= nil
			or props.alignH ~= nil
			or props.alignV ~= nil
			or props.lineAlign ~= nil
			or props.gridSpan ~= nil
			or props.layoutPriority ~= nil
			or props.shrinkWeight ~= nil
		) or nil,
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
				tablet measure) times `metrics.metricScale` (ADR-0039's
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
				`metrics.metricScale` (ADR-0039's `tenFootFloor`, the one factor
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
		-- the role's canonical font DESCRIPTOR ("family#weight#style", ADR-0019
		-- §6) and line height ride with its size, so a theme that changes weight
		-- measures as that weight instead of as the family's Regular
		layoutNode.font = props.font or (if role ~= nil then role.fontKey else nil)
		layoutNode.lineHeight = if role ~= nil then role.lineHeight else nil
	elseif class == "Button" then
		if #node.children == 0 then
			layoutNode.text = drawnButtonText(props)
			local size, role, fit = textOf(themeSnapshot.INTRINSIC_TEXT_ROLE.Button)
			layoutNode.textSize = size
			-- the fit BAND, when the author asked the solver to choose the size
			layoutNode.textFit = fit
			layoutNode.font = if role ~= nil then role.fontKey else nil
			layoutNode.lineHeight = if role ~= nil then role.lineHeight else nil
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
		-- the row's box now comes from the SHARED description the adapter paints
		-- from (`themeSnapshot.toggleRowPadding`), so the reserved label column
		-- and the drawn one cannot disagree — director round 9
		layoutNode.padding = layoutNode.padding or themeSnapshot.toggleRowPadding(metrics)
		layoutNode.height = layoutNode.height or { type = "minMax", min = metrics.controls.toggle.minHeight }
	elseif class == "TextField" then
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
	-- DECORATION CONTENT INSETS (ADR-0019 §5). A nine-slice skin has a carved
	-- border that content must clear, so the recipe's `contentInsets` are
	-- SOLVER-VISIBLE: they are added to whatever padding the node already had,
	-- after every class default, so a Button's theme padding and its skin's
	-- border both apply. `chromeInsets` is empty for every flat package
	-- (Studio Neutral included) and this whole block is then a no-op, which is
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
	if kind == "scroll" and insideClipper ~= true then
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
	-- even by a package that reserves no chrome at all: Studio Neutral declares
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
					`minMax{max = 36}` axis never solves wider than 36, so a frame that
					cannot fit inside 36 cannot fit inside it. Reading only the literal made
					the rule half-apply the same way the `aspect` branch below did before it
					was taught: measured under fantasy_ornate (`control` 14/10 per side), one
					`UI.Button{label = "X"}` at `fixed 36 x fixed 36` filed TWO chromeYields
					and the identical control at `minMax{max = 36}` on both axes filed NONE —
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
				it is copied here rather than approximated. ]]
			local wExtent, hExtent = extentOf(layoutNode.width), extentOf(layoutNode.height)
			local wDim: any, hDim: any = layoutNode.width, layoutNode.height
			if type(wDim) == "table" and wDim.type == "aspect" and type(wDim.ratio) == "number" then
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
			local spentX = chrome_slots.spendInset(wExtent, left + right, wantX, textFloor)
			local spentY = chrome_slots.spendInset(hExtent, top + bottom, wantY, textFloor)
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
	-- draws itself (ADR-0020 R4), and that half was right. The half that was
	-- missing: the picture is a FIXED px square from `iconSizes`, centred on the
	-- node, and the node was measured as the CHARACTER. `">"` is 6px; Fantasy
	-- Ornate's `medium` rung is 32. The disclosure caret therefore painted 13px
	-- outside itself on every side — into the frame on one side and the label on
	-- the other. Measured live: SEVEN of the nine reference configurations
	-- overhang, Studio Neutral among them. It was never a theme's bug.
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
				crosses it. Studio Neutral (36/20) is why the default theme looked fine.

				So the authored axis is RAISED to hold its own picture, and the `aspect`
				pairing set a few dozen lines above carries the other axis with it — the
				disc stays a disc. Same repair as the `sponsor_drop` chevron plate: a
				floor, never a bigger constant. ]]
			if props.shape == "circle" then
				local need = px + math.max(pl + pr, pt + pb)
				--[[ ...AND A FLOOR IS A REQUEST, NOT A RIGHT (task THEME fix round,
					2026-08-28; ADR-0059 Decision 6; review finding C1). Which is the same
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
	if #node.children > 0 then
		layoutNode.children = {}
		-- the axis this container imposes on its children (nil = not a stack)
		-- a wrapping stack imposes the SAME axis as the stack it is a mode of: a
		-- Divider inside a wrapping row is still a vertical rule (round 3 item A)
		local childAxis: string? = if kind == "hstack" or kind == "hwrap"
			then "x"
			elseif kind == "vstack" or kind == "vwrap" then "y"
			else nil
		local function appendChild(child: any)
			-- structural regions (When/ForEach) own MOUNTING, not layout:
			-- their children splice into the parent's flow so fill dims and
			-- stack math behave as if the region wrapper did not exist
			if child.class == "When" or child.class == "ForEach" or child.class == "ErrorBoundary" then
				for _, grandchild in child.children do
					appendChild(grandchild)
				end
			else
				table.insert(
					layoutNode.children,
					toLayoutNode(
						child,
						metrics,
						textScale,
						prefOffset,
						childAxis,
						insideClipper == true or kind == "scroll"
					)
				)
			end
		end
		for _, child in node.children do
			appendChild(child)
		end
		--[[ ── THE SIBLING PLATE'S CARVED BORDER, AND WHY THE FRAMEWORK DOES NOT
			SPEND IT (task THEME, director items 7-8; ADR-0059 Decision 2) ──────────

			ADR-0019 §5 promises that a nine-slice skin's `contentInsets` are
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
			every one of those 494 is now a finding a spec can fail on, and
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
		layoutNode.inertPlacement = solver.auditPlacement(kind, layoutNode.id, layoutNode.children)
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
	local selfRelative = (layoutNode.width ~= nil and layoutNode.width.type == "containerRelative")
		or (layoutNode.height ~= nil and layoutNode.height.type == "containerRelative")
	local inside = selfRelative
	if not inside and kind ~= "scroll" and layoutNode.children ~= nil then
		for _, child in layoutNode.children do
			if child.containerRelativeInside then
				inside = true
				break
			end
		end
	end
	layoutNode.containerRelativeInside = inside or nil
	return layoutNode
end

layout_node.compactForm = compactForm
layout_node.drawnButtonText = drawnButtonText
layout_node.effectiveHitFloor = effectiveHitFloor
layout_node.toLayoutNode = toLayoutNode

return layout_node
