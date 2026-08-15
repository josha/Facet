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
	controls/contract (the declared hit floors), blueprint_schema.
]]

local solver = require("../layout/solver")
local themeSnapshot = require("../themes/snapshot")
local themePackage = require("../themes/package")
local chrome_slots = require("../tokens/chrome_slots")
local controlContract = require("../controls/contract")
local schema = require("../blueprint_schema")

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
-- `applyTextVerdicts` below.
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
-- (applyTextScale below) so layout and paint agree. Only sizes that ALSO reach
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
-- AN OFFSET MAY BE A FRACTION OF THE PARENT (ADR-0022 Decision 6, row SF-P5). A
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

local function isSingleWord(label: any): boolean
	if type(label) == "number" then
		return true
	end
	return type(label) == "string" and label ~= "" and string.find(label, "%s") == nil
end

-- THE EFFECTIVE TARGET FLOOR for a class, or nil when it declares none. The
-- CONTRACT (src/controls/contract.luau) is the source of truth for WHETHER a
-- class has a floor, so adding a focusable control gets it enforced; the THEME
-- owns the VALUE, and floors clamp UP only (ADR-0019 §2 step 4) — a package may
-- enlarge a touch target, never shrink one below what the control declared.
--
-- ONE reading, two readers: `toLayoutNode` carries it into the solve so the
-- result can name its interactive rects (LTN-4 diagnostics), and `pushHitRects`
-- spends the same number as real hit geometry. They were two copies of this
-- arithmetic for exactly one commit.
local function effectiveHitFloor(class: string, metrics: any): number?
	local c = controlContract.forClass(class)
	local declared = if c ~= nil then c.minHitSize else nil
	return if declared ~= nil then math.max(declared, metrics.targetSizes.minimum) else nil
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
	local function textOf(fallbackRole: string): (number, any)
		local raw = props.textSize
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
		if size == nil then
			return metrics.type[fallbackRole].size + prefOffset, role
		end
		return size * textScale + prefOffset, role
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
		-- on one line too) and publishes `textFacts.wraps`, which `applyTextVerdicts`
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
		width = themeSnapshot.resolveDim(metrics, props.width),
		height = themeSnapshot.resolveDim(metrics, props.height),
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
		-- THE EFFECTIVE TARGET FLOOR, CARRIED INTO THE SOLVE (LTN-4 diagnostics).
		-- Declared by the control contract, clamped UP by the theme — the identical
		-- pair `pushHitRects` spends below, read here so the SOLVE RESULT can say
		-- which rects belong to something the player is meant to hit. It changes no
		-- geometry: the hit expansion stays where it was, and this is the fact a
		-- pure audit needs to tell an interactive rect from a decorative one.
		hitFloor = effectiveHitFloor(class, metrics),
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
			table.insert(groups, copy)
		end
		layoutNode.composition = {
			groups = groups,
			arrangements = props.arrangements,
			laneGap = themeSnapshot.resolveNumber(metrics, props.laneGap),
			groupGap = themeSnapshot.resolveNumber(metrics, props.groupGap),
			maxMeasure = themeSnapshot.resolveNumber(metrics, props.maxMeasure),
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
		-- FULL-VALUE DISCLOSURE (LTN-4). Construction-only, so it is read straight
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
		local size, role = textOf(themeSnapshot.INTRINSIC_TEXT_ROLE.Text)
		layoutNode.textSize = size
		-- an explicit (deprecated) font prop still wins for measurement; otherwise
		-- the role's canonical font DESCRIPTOR ("family#weight#style", ADR-0019
		-- §6) and line height ride with its size, so a theme that changes weight
		-- measures as that weight instead of as the family's Regular
		layoutNode.font = props.font or (if role ~= nil then role.fontKey else nil)
		layoutNode.lineHeight = if role ~= nil then role.lineHeight else nil
	elseif class == "Button" then
		if #node.children == 0 then
			layoutNode.text = drawnButtonText(props)
			local size, role = textOf(themeSnapshot.INTRINSIC_TEXT_ROLE.Button)
			layoutNode.textSize = size
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
		-- THE CIRCLE IS A SOLVER FACT (feature round 2026-07-26). `shape =
		-- "circle"` promises a TRUE 1:1 box and promises the author never computes
		-- it, so the square is enforced HERE, through the dimension vocabulary that
		-- already expresses "this axis follows that one": `aspect` with ratio 1.
		-- Nothing new lands in the solver, and the pairing therefore inherits every
		-- fix that vocabulary already has (including `aspect` + `fill`, which used
		-- to measure 0x0 — found live 2026-07-24).
		--
		-- ONE authored axis drives the other; NEITHER authored means the control
		-- metric, resolved from the live snapshot so a metric package resizes the
		-- disc and a pixel package snaps it. BOTH authored is refused at the
		-- blueprint boundary, so this branch can never have to pick a winner.
		if props.shape == "circle" then
			if layoutNode.width == nil and layoutNode.height == nil then
				layoutNode.width = { type = "fixed", px = themeSnapshot.circleDiameter(metrics) }
			end
			if layoutNode.height == nil then
				layoutNode.height = { type = "aspect", ratio = 1 }
			elseif layoutNode.width == nil then
				layoutNode.width = { type = "aspect", ratio = 1 }
			end
		end
		layoutNode.padding = themeSnapshot.buttonPadding(metrics, props)
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
		-- FULL-VALUE DISCLOSURE for the one-line label (Step 8.5 LT-G1/LTN-5):
		-- the single-line form is measured, signed design — so where a compact
		-- width truncates it, `disclose` is the declared full-value path, riding
		-- the same textFacts channel a Text's does
		layoutNode.disclose = if props.disclose == true then true else nil
		-- explicit textSize wins and scales like every other text node
		-- (verifier F1: measure and paint must agree); the intrinsic default is
		-- the `body` role, which is ScreenTarget's toggle label size
		local size, role = textOf(themeSnapshot.INTRINSIC_TEXT_ROLE.Toggle)
		layoutNode.textSize = size
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
		local size, role = textOf(themeSnapshot.INTRINSIC_TEXT_ROLE.TextField)
		layoutNode.textSize = size
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
		-- an AUTHORED thickness may name a metric too (BP-F12): it is the same
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
				if type(dim) == "table" and dim.type == "fixed" and type(dim.px) == "number" then
					return dim.px
				end
				return math.huge
			end
			local wantX = extra.left + extra.right
			local wantY = extra.top + extra.bottom
			local spentX = chrome_slots.spendInset(extentOf(layoutNode.width), left + right, wantX)
			local spentY = chrome_slots.spendInset(extentOf(layoutNode.height), top + bottom, wantY)
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
			-- (RS-A16-D3)
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
