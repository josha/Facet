--!strict
-- Renderer (design §4.3 #4, §13): walks the mounted graph, solves layout, and
-- drives a RenderTargetAdapter. Engine-free — ScreenTarget (client-only) and
-- the FakeTarget (tests) implement the same adapter interface, which is what
-- proves the §13 seam after ADR-0003.
-- Adapter interface (all handles opaque to this module):
--   adapter.createRoot(screenId: string) -> rootHandle
--   adapter.create(rootHandle, path, class, decorationHint?) -> handle
--   adapter.setRect(handle, rect)                       [layout authority]
--   adapter.setProp(handle, prop, value, authority)     [checked upstream]
--   adapter.remove(handle)
--   adapter.destroyRoot(rootHandle)
-- Update model: refresh() drains the mounted dirty queue; paint-only changes
-- write props without re-solving; measure/arrange/structure re-solve and
-- write only rects that actually changed (minimal-write contract).
-- ARMED COMMITS: `presenter.withAnimation` arms the controller for exactly one
-- commit, in which the solved rects are diffed against the last ones and the
-- nodes that STARTED moving get a relative presentation record that flies them
-- in from where they used to be. The solve stays exact and instant either way —
-- only the PAINT travels (docs/plans/swiftui-parity-round2.md §Phase 1).

local solver = require("../layout/solver")
local profile = require("../core/profile")
local text_metrics = require("../layout/text_metrics")
local authority = require("./authority")
-- the presentation channel's arithmetic (ADR-0026): the composition rules, the
-- authored triple's domain checks, and the write memo's comparison. Pure.
local presentation = require("./presentation")
local controlContract = require("../controls/contract")
local themeSnapshot = require("../themes/snapshot")
local themePackage = require("../themes/package")
local chrome_slots = require("../tokens/chrome_slots")
-- public drag/drop (ADR-0022 D5): the declaration channel and the per-surface
-- registry that turns declarations into one acquisition→session→terminal path
local dragContract = require("../input/drag_contract")
local dragRegistryLib = require("../input/drag_registry")
local autoscrollLib = require("../input/autoscroll")
local specGuard = require("../spec_guard")
-- the CLASS SCHEMA, read here for one reason only: an enum prop's closed set has
-- to be enforced where a BOUND value lands, not just where a static one is
-- authored (see `assertEnumValue` below)
local schema = require("../blueprint_schema")

local renderer = {}

-- prop -> adapter prop authority mapping for dynamic writes
local BINDING_PROPS: { [string]: boolean } = {
	text = true,
	value = true,
	enabled = true,
	-- input-sinking containers (modal panels): the engine Active flag. It used
	-- to be written only at creation by a bespoke branch, so a REACTIVE `active`
	-- dirtied "semantics" and the refresh loop then dropped it (Milestone 0).
	active = true,
	image = true,
	label = true,
	selected = true,
	cursorHint = true,
	-- TextField (§17 Phase 5): data-driven text-entry props
	placeholder = true,
	editing = true,
	maxLength = true,
	keyboardType = true,
	-- Path (native-substrate NS-A7): reactive stroke geometry/config — a bound
	-- progress arc updates points as a paint-only prop write (never a re-solve)
	points = true,
	thickness = true,
	closed = true,
	-- THE CONTINUOUS-COLOUR CHANNEL (ADR-0022 Decision 6). Binding rather than
	-- style because the VALUE is data — a blend along a signal, an identity hue —
	-- which is exactly what a selector cannot express. It is applied LAST at
	-- creation (see ensureTree) because it composes over whatever the style props
	-- settled on.
	tint = true,
}

-- style-authority hints (§7.3): surface/text roles + the Phase 4 shadow and
-- corner modifier data. These are written at creation AND on every reactive
-- change. Milestone 0 (swiftui-parity-next investment 1) fixed the second
-- half: a bound `surface`/`role` dirtied "paint" and the refresh loop then
-- dropped it because only BINDING_PROPS were re-applied, so a reactive style
-- hint scheduled work the adapter never performed — the same silent-failure
-- class as Text.color.
local STYLE_PROPS: { [string]: boolean } = {
	surface = true,
	role = true,
	shadow = true,
	-- the per-view gradient modifier: one bespoke adapter-owned UIGradient,
	-- applied at creation and re-applied reactively like every other style prop
	gradient = true,
	corners = true,
	-- horizontal text alignment: paint-only, and it must survive a reactive
	-- change like any other style hint
	textAlign = true,
	-- the circle Button (feature round 2026-07-26): the disc's chrome. Native
	-- mode turns it into the `luau-shape-circle` tag the sheet's phantom
	-- ::UICorner/::UIStroke rules key on; fallback mode re-radiuses the real
	-- UICorner the adapter already built.
	shape = true,
	-- its semantic icon content: a NAME the adapter resolves through the R4
	-- machinery, never an asset id
	icon = true,
	-- the compact representation this button wears when its full label does not
	-- fit. The DECLARATION is style (it selects a representation, and in its icon
	-- form a theme-owned picture); the drawn string still rides the label seam.
	compactLabel = true,
	-- the authored border (ADR-0022 Decision 6): normalized UIStroke data, exactly
	-- the shape and lifecycle `gradient` has — ONE bespoke child, reused
	stroke = true,
	-- how an authored picture fills its box. Style for the same reason `shape` is:
	-- the solved rect does not move, and the single engine write is what makes the
	-- picture fit the box the solver already sized.
	scaleMode = true,
}

-- Creation-time application order. This used to be a SECOND hardcoded list
-- inline in ensureTree, so adding a style prop to STYLE_PROPS above wired it for
-- reactive updates but silently never applied it at creation — `textAlign` was
-- set on a node and simply did not paint until something else changed it
-- (director review 2026-07-24). One ordered list, asserted to cover the set, so
-- the two views cannot drift again. Order is fixed rather than table iteration
-- because paint application must be deterministic.
-- `shape` is FIRST: it is the fact every later chrome write consults (the
-- fallback path's `corner()` reads handle.shape), so a shape applied after a
-- surface would leave the surface's square radius on a disc until something
-- else touched it. `icon` is LAST because it paints OVER whatever the chrome
-- above it settled on — and `compactLabel` goes immediately BEFORE it, because
-- when the compact form is an icon it becomes an icon request, which `icon` then
-- carries to the chrome subsystem through the one reconcile entry point.
-- `stroke` sits beside `corners` (both are the node's own border chrome) and
-- `scaleMode` beside `textAlign` (both are leaf paint that no other write reads).
local STYLE_PROP_ORDER: { string } = {
	"shape",
	"surface",
	"role",
	"shadow",
	"gradient",
	"corners",
	"stroke",
	"textAlign",
	"scaleMode",
	"compactLabel",
	"icon",
}
do
	local covered: { [string]: boolean } = {}
	for _, prop in STYLE_PROP_ORDER do
		assert(STYLE_PROPS[prop], `STYLE_PROP_ORDER lists '{prop}', which is not a style prop`)
		covered[prop] = true
	end
	for prop in STYLE_PROPS do
		assert(covered[prop], `style prop '{prop}' is missing from STYLE_PROP_ORDER and would never apply at creation`)
	end
end
renderer.STYLE_PROPS = STYLE_PROPS
renderer.BINDING_PROPS = BINDING_PROPS

-- ONE NAME, TWO PROPERTIES. `thickness` is `Path`'s engine stroke width — a real
-- binding write — and `Divider`'s hairline size, which the SOLVER consumes into
-- the node's own box and no adapter ever sees (see the Divider branch of
-- `toLayoutNode`). The binding dispatch below is keyed on the prop NAME, so a
-- Divider tried to write it too and hit the authority wall: `UI.Divider{
-- thickness = … }` errored at first render for EVERY value, and always had —
-- found while giving both props the metric grammar (BP-F12). The name is
-- therefore restricted to the class that actually emits it; everything else
-- stays loud (an undeclared write is still an assertWrite error).
local BINDING_PROP_CLASSES: { [string]: { [string]: boolean } } = {
	thickness = { Path = true },
}

local function emitsBinding(class: string, prop: string): boolean
	if not BINDING_PROPS[prop] then
		return false
	end
	local only = BINDING_PROP_CLASSES[prop]
	return only == nil or only[class] == true
end

-- EVERY PROP NAME THIS MODULE CAN HAND TO `adapter.setProp`, and the seam each
-- one rides. The two channel tables above cover most of them; these are the
-- writes that go out through their own seam instead, so the set is complete.
--
-- WHY THIS EXISTS (found defect SF-M9, 2026-07-27 audit). `FakeTarget.setProp`
-- recorded any prop generically, so a headless suite proved a channel the LIVE
-- adapter had no branch for: the keyboard keep-visible transform was written,
-- recorded, asserted green — and never landed on a device for as long as the
-- feature had shipped. A declared set turns "both adapters implement the same
-- props" into a conformance test (tests/render_target_contract.spec.luau) instead
-- of a thing nobody can see. Add a new setProp write site, add it here.
local DIRECT_PROPS: { [string]: string } = {
	clipChildren = "ensureTree's clip-host declaration (layout authority)",
	textSize = "applyTextScale — the scaled-text paint seam",
	textFont = "applyTextScale — the typography role's FACE, beside its size (F2)",
	-- THE WRAP RULE'S PAINT HALF (director ruling 5, 2026-08-13). The solver is the
	-- only seam that knows the drawable width, so it decides whether wrapping can
	-- succeed and publishes the verdict; this carries it to the adapter, which
	-- otherwise sees the string and not the box.
	textWrapped = "applyTextVerdicts — the wrap-rule paint seam (layout authority)",
	padding = "applyPadding — the Button and padded-Text text-inset paint seam",
	transform = "controller.setPresentationTransform / setPresentationOffset (presentation authority)",
	transparency = "controller.setPresentationTransparency (presentation authority)",
}
do
	local emitted: { [string]: boolean } = {}
	for prop in BINDING_PROPS do
		emitted[prop] = true
	end
	for prop in STYLE_PROPS do
		emitted[prop] = true
	end
	for prop in DIRECT_PROPS do
		emitted[prop] = true
	end
	-- the registry-driven held-source state (director round five): renderer-owned,
	-- never authored — declared here so the adapter parity pin holds
	emitted.dragHeld = true
	renderer.EMITTED_PROPS = table.freeze(emitted)
	renderer.DIRECT_PROPS = table.freeze(table.clone(DIRECT_PROPS))
end

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
function renderer.compactForm(props: any): any
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
function renderer.drawnButtonText(props: any, compact: boolean?): any
	if compact == true then
		local form = renderer.compactForm(props)
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
			layoutNode.text = renderer.drawnButtonText(props)
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
			local compact = renderer.drawnButtonText(props, true)
			if compact ~= layoutNode.text then
				layoutNode.compactText = compact
				-- ...and WHETHER IT IS A DEGRADE OR A DEFAULT (director device round
				-- 2026-08-12). `prefer = true` skips the fit test entirely, so the
				-- compact form is what this button measures AND paints — which is why
				-- the flag has to reach the solver rather than being resolved here: the
				-- box must be reserved for the string that will be drawn in it.
				local form = renderer.compactForm(props)
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

local function rectsEqual(a: any, b: any): boolean
	if a == nil or b == nil then
		return a == nil and b == nil
	end
	return a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h
end

local TAPPABLE: { [string]: boolean } = { Button = true, Toggle = true, TextField = true }
-- nodes that get the pointer HOVER layer (UI-PARADIGM-001): activatable chrome
-- the renderer draws (Table rows/headers render as Button). TextField is not a
-- hover surface (its affordance is the caret/edit handshake, not a hover lift).
local HOVERABLE: { [string]: boolean } = { Button = true, Toggle = true }

export type RendererAttachOpts = {
	-- "coreSafeContent" (default) | "deviceSafeContent" | "edgeToEdge"
	rootPolicy: string?,
	-- a pointer tap on a mounted path. `meta` carries the tap's geometry
	-- (`x`/`y`) for the outside-tap policy, and `via` for a detector-driven tap.
	onNodeTap: ((path: string, meta: any?) -> ())?,
	-- OPT-IN mirror of logical focus to engine selection (NS-A12); the presenter
	-- sets it for modal/exclusive surfaces only
	engineSelectionBridge: boolean?,
	-- FULL-VALUE DISCLOSURE engagement (Step 8.5, LTN-4): pointer enter/leave
	-- and touch long-press on a `disclose` Text, delivered as (path | nil). The
	-- presenter routes these to its `_discloseHover`/`_discloseLongPress`
	-- engine-adapter seams; hand-attached surfaces may omit both (no zones are
	-- wired, focus-driven disclosure still works through the presenter).
	onDiscloseHover: ((path: string?) -> ())?,
	onDiscloseLongPress: ((path: string?) -> ())?,
	recycleInstances: boolean?,
	incrementalLayout: boolean?,
}

local ATTACH_OPTS_KEYS = specGuard.keySet({
	"engineSelectionBridge",
	"onNodeTap",
	"rootPolicy",
	"onDiscloseHover",
	"onDiscloseLongPress",
	"recycleInstances",
	"incrementalLayout",
})

-- attach(core, mountedRoot, env, adapter, opts) -> controller
function renderer.attach(
	core: any,
	root: any,
	env: any,
	adapter: any,
	--[[ THE DECLARED TYPE IS THE SHIPPED TRUTH (api-architecture-consistency F-29).
		`engineSelectionBridge` was read through an `(opts :: any)` cast and passed
		by the presenter for months while the type said this table held two keys —
		so a strict consumer wanting the bridge on a hand-attached surface got a
		type error for a supported option, and no checker would have caught the
		flag's removal. `onNodeTap` was declared one-arg and has always been called
		with `(path, meta)`; both in-tree consumers already write the two-arg form,
		and `meta` is where the outside-tap geometry (`x`/`y`) and `via` live. ]]
	opts: RendererAttachOpts?
)
	-- ...AND THE DECLARED TYPE IS ALSO CLOSED (constitution §4; ARCH-1). F-29 made
	-- the three fields honest; this makes a fourth, misspelled one loud instead of
	-- inert — the same rule `rootPolicy`'s own value check applies one level up.
	specGuard.assertKnownKeys("renderer.attach", opts, ATTACH_OPTS_KEYS, "opts")
	-- THE ACCEPTED POLICIES, ENUMERATED. `edgeToEdge` was passed by every modal
	-- scrim for months and read by nothing: it fell through to the default and
	-- the scrim was quietly inset, with a comment above the call site describing
	-- behaviour the code did not have. An unknown mode is now a failure at the
	-- call site instead of a shrug at render time
	-- (docs/lessons/decoration-paints-to-the-edges.md).
	local ROOT_POLICIES = {
		-- content, inset by the CoreGui reservation (the default)
		coreSafeContent = true,
		-- content, inset by the per-edge maximum of CoreGui and device insets
		deviceSafeContent = true,
		-- DECORATION only — a scrim or a backdrop, painting under the insets
		edgeToEdge = true,
	}
	local rootPolicy = (opts and opts.rootPolicy) or "coreSafeContent"
	if ROOT_POLICIES[rootPolicy] ~= true then
		local names = {}
		for name in ROOT_POLICIES do
			table.insert(names, name)
		end
		table.sort(names)
		error(`LuauUI renderer: unknown rootPolicy '{tostring(rootPolicy)}'. Valid: {table.concat(names, ", ")}.`, 0)
	end
	local rootHandle = adapter.createRoot(root.node.id or "Screen")
	local attachScope = core:scope("renderer-attach")
	local initialized = false
	local handles: { [string]: any } = {} -- path -> adapter handle
	local lastRects: { [string]: any } = {}
	local lastScrollRegions: { [string]: any } = {}
	-- per-ScrollView autoscroll: the authored declaration, and the live model.
	-- Declared with the regions because they are written and dropped together.
	local scrollAutoscroll: { [string]: any } = {}
	local autoscrollModels: { [string]: any } = {}
	-- drag math reads solved rects through this lookup (ADR-0008)
	local function rectOf(path: string): any
		return lastRects[path]
	end
	-- path -> its nearest ScrollView ANCESTOR's path (rebuilt every structural
	-- sync by the live-path walk). It exists for one reason: the solver arranges
	-- a scroll host's children in the HOST's own coordinate space and the engine
	-- shifts them by CanvasPosition, so a solved rect inside a scrolled list is
	-- NOT where that row is on screen. A pointer, meanwhile, always arrives in
	-- window space. Hit-testing one against the other silently targets the wrong
	-- row the moment the list is scrolled — which is precisely the case edge
	-- autoscroll spends its whole life in.
	local scrollHostOf: { [string]: string } = {}
	-- ===== STROKED PATHS ARE NOT CROPPED BY THE ENGINE (RS-PATHCLIP) ========
	--
	-- A `UI.Path` renders as an engine stroke that is NOT a box in the widget
	-- tree, so no ancestor's clip crops it: inside a scrolling list a WINDOWED
	-- row sitting outside the viewport still painted its ring — a family-hued
	-- arc floating on empty plate, unattached to any row (Sponsor review round
	-- 1, F1; `PS-T1-luauui-max-iphone16-landscape.png`, the ring of the row one
	-- pitch BELOW the last visible one). Every sibling in that row cropped
	-- correctly, which is the tell: the defect is the primitive, not the layout.
	--
	-- A stroke also cannot be crop*ped* half-way — there is no partial-clip
	-- operation for it — so the framework's rule is all-or-nothing: a path whose
	-- painted box is not FULLY inside every clip host above it does not paint at
	-- all. `clipHostOf` is the nearest such ancestor, threaded down the same
	-- live-path walk that already threads the scroll host (it is free there and
	-- a whole-tree search per path otherwise).
	local clipHostOf: { [string]: string } = {}
	local pathNodes: { [string]: boolean } = {}
	local pathNodeCount = 0
	-- what the SOLVER decided about each node's visibility, so the scroll-time
	-- re-cull never contradicts it (a path inside a losing ViewThatFits candidate
	-- stays hidden however its rect lands)
	local solverHidden: { [string]: boolean } = {}
	local pathClipObservers: { [string]: () -> () } = {}
	local function scrollShift(path: string): (number, number)
		local dx, dy = 0, 0
		local host: string? = scrollHostOf[path]
		local guard = 0
		while host ~= nil and guard < 32 do
			local handle = handles[host]
			if handle ~= nil and adapter.getScrollPosition ~= nil then
				local pos = adapter.getScrollPosition(handle)
				if type(pos) == "table" then
					dx += pos.x or 0
					dy += pos.y or 0
				end
			end
			host = scrollHostOf[host]
			guard += 1
		end
		return dx, dy
	end
	-- the presentation transform currently pushed per path (ADR-0022 Decision 2).
	-- Declared up here with `rectOf`, because `screenRectOf` reads it: a rect
	-- compared against a POINTER has to answer where the node is PAINTED, and while
	-- a presentation offset is live that is not where the solver put it. It must
	-- also be forgotten when a path is removed: a re-created node starts at rest,
	-- and a cached value would suppress the write that puts it there (the same
	-- verdict-inheritance defect the visible and hit-rect caches were bitten by —
	-- verifier finding V10). `presentationLive` counts the non-nil entries so a
	-- surface with no motion running pays one integer compare per hit-test.
	local lastTransform: { [string]: any } = {}
	local presentationLive = 0
	-- AUTHORED PRESENTATION (ADR-0026, and render/presentation.luau's header): the
	-- blueprint's `opacity`/`scale`/`rotation` are a second TERM in this channel,
	-- never a second writer. `authoredN` is the off-path gate — zero means the
	-- composition is skipped entirely.
	local authored: { [string]: any } = {}
	local authoredN = 0
	local lastTransparency: { [string]: number } = {}
	-- what was last WRITTEN, per engine property: the memo must live on the COMPOSED
	-- value, or one contributor moving alone is swallowed by the other's cache
	local lastComposedTransform: { [string]: any } = {}
	local lastComposedAlpha: { [string]: number } = {}
	-- ===== `withAnimation` RECORDS (docs/plans/swiftui-parity-round2.md §Phase 1,
	-- "Blocker 3") ===========================================================
	-- A record is the RELATIVE delta a path is currently flying, installed only at
	-- an animation ROOT. Both halves of the presentation channel already accumulate
	-- ancestor offsets (see the accumulation rule below), so a per-node ABSOLUTE
	-- delta would paint a sliding panel's children at double the distance.
	--
	-- The record belongs to the PATH; the spring is merely the driver it is
	-- attached to right now. That is what keeps two calls off one `lastTransform`
	-- slot: a later call re-bases the path and re-attaches it, and the older
	-- spring's settle clears only what it still owns.
	--
	-- They live on the CONTROLLER because they are controller-scoped state that
	-- must be cleared per path at removal, beside every other per-path cache.
	local animationSession: any = nil -- non-nil only for the duration of an ARMED commit
	local animationBaseline: { [string]: boolean }? = nil
	local animationRecords: { [string]: any } = {}
	local animationSets: { any } = {}
	local animationRecordN = 0
	-- per-path `{ o, s, r }` deltas parked by an ARMED commit and consumed by the
	-- walk below (ADR-0026 Decision 7) — the authored value is already at its
	-- destination by then, the same reason the rect half needs `lastRects`
	local animationPaintDelta: { [string]: any } = {}
	-- assigned once the controller (and its presentation writes) exist; called from
	-- the commit, which runs earlier in this file than the writes it needs
	local installAnimationRecords: (rects: any) -> ()
	local animationClear: (path: string, write: boolean) -> ()
	-- the ONE presentation write site (ADR-0026 Decision 3) and the authored-triple
	-- re-read, forward-declared: mount and the commit both reach them from above
	local pushPresentationPaint: (path: string) -> ()
	local readAuthoredPresentation: (node: any) -> boolean
	-- PLAT-4 (platform verifier, 2026-07-27): the paint half of the presentation
	-- channel was sound and the geometry half was not — `screenRectOf` composed
	-- scroll offsets only, so while the keyboard keep-visible shift sat on the root
	-- (the whole time the OS keyboard is up) or an enter/exit slide sat on a region,
	-- LuauUI's own drop verdicts disagreed with what the player was looking at by
	-- exactly the offset.
	--
	-- THE ACCUMULATION RULE, IN WINDOW SPACE. The adapter stops its own
	-- accumulation at the nearest REAL PARENT (a clip host / fade group), because
	-- that parent's instance move already carries its children
	-- (screen_target.recomputePresentationOffset). In ABSOLUTE window space that
	-- stop cancels out — the parent re-adds its own shift by moving — so the
	-- painted rect of a node is its solved rect plus its own transform plus EVERY
	-- ancestor's, with no stop. One rule, and the root case (the whole surface
	-- shifts) falls out of it, exactly as it does on the paint side.
	--
	-- OFFSETS ONLY. A transform's `scale`/`rotation` reach only the node's own
	-- instance (and whatever is really parented under it) and would turn a hit rect
	-- into a quad; hit geometry stays axis-aligned this round and a scaled node
	-- hit-tests at its solved size (documented in docs/reference/api.md).
	local function presentationShift(path: string): (number, number)
		if presentationLive == 0 then
			return 0, 0
		end
		local dx, dy = 0, 0
		local own = lastTransform[path]
		if own ~= nil then
			dx += own.x or 0
			dy += own.y or 0
		end
		local i = #path
		while i > 1 do
			if string.sub(path, i, i) == "/" then
				local t = lastTransform[string.sub(path, 1, i - 1)]
				if t ~= nil then
					dx += t.x or 0
					dy += t.y or 0
				end
			end
			i -= 1
		end
		return dx, dy
	end
	-- the solved rect in WINDOW space: nested scroll offsets accumulate up the
	-- chain, so a list inside a scrolled panel still answers where it is drawn —
	-- and presentation offsets accumulate with them, so a shifted surface answers
	-- where it is drawn too.
	local function screenRectOf(path: string): any
		local rect = lastRects[path]
		if rect == nil then
			return nil
		end
		local dx, dy = scrollShift(path)
		local px, py = presentationShift(path)
		if dx == 0 and dy == 0 and px == 0 and py == 0 then
			return rect
		end
		return { x = rect.x - dx + px, y = rect.y - dy + py, w = rect.w, h = rect.h }
	end
	-- the same window-space answer over a solve's FRESH rects: the visibility
	-- pass runs before `lastRects` is updated, and culling this frame's paths
	-- against last frame's geometry is exactly the one-frame lag that makes a
	-- re-sorted row flash its ring outside the list.
	local function paintedRectIn(rects: any, path: string): any
		local rect = if rects[path] ~= nil then rects[path].rect else nil
		if rect == nil then
			return nil
		end
		local dx, dy = scrollShift(path)
		local px, py = presentationShift(path)
		if dx == 0 and dy == 0 and px == 0 and py == 0 then
			return rect
		end
		return { x = rect.x - dx + px, y = rect.y - dy + py, w = rect.w, h = rect.h }
	end
	-- half a pixel of slack: a rect that lands exactly on its host's edge is
	-- INSIDE it, and solved rects are not guaranteed integral.
	local CLIP_EPSILON = 0.5
	local function clipContains(outer: any, inner: any): boolean
		return inner.x >= outer.x - CLIP_EPSILON
			and inner.y >= outer.y - CLIP_EPSILON
			and inner.x + inner.w <= outer.x + outer.w + CLIP_EPSILON
			and inner.y + inner.h <= outer.y + outer.h + CLIP_EPSILON
	end
	-- does this path escape ANY clip host above it? Nested hosts all count: a
	-- list inside a clipped panel must crop against both.
	local function pathEscapesClip(path: string, rectFor: (string) -> any): boolean
		local own = rectFor(path)
		if own == nil then
			return false
		end
		local host: string? = clipHostOf[path]
		local guard = 0
		while host ~= nil and guard < 32 do
			local hostRect = rectFor(host)
			if hostRect ~= nil and not clipContains(hostRect, own) then
				return true
			end
			host = clipHostOf[host]
			guard += 1
		end
		return false
	end
	-- ===== public drag/drop (ADR-0022 Decision 5) ==========================
	-- ONE registry per surface, built lazily: a screen with no `UI.draggable`
	-- and no `UI.dropTarget` pays nothing for the feature existing. It is handed
	-- the LIVE rect lookup and the paint-order walk (`lastZ`, declared below and
	-- read through a closure) so a drop verdict is always about the geometry and
	-- the stacking the player is actually looking at.
	-- RETIRING SUBTREES ARE NOT DRAG SURFACES (ARCH-F2): the mount layer keeps a
	-- retiring subtree in `children` so its exit can paint, but ADR-0022 D3 says
	-- it "turns non-interactive" — for drag that must mean RESOLUTION-time
	-- exclusion rather than registration churn, so a re-entry mid-exit is
	-- eligible again the same frame with no rewiring. Roots are collected once
	-- per structural sync; the registry consults the predicate per resolution.
	local retiringRoots: { string } = {}
	local function collectRetiringRoots()
		table.clear(retiringRoots)
		local function walk(node: any)
			if node.retiring == true then
				table.insert(retiringRoots, node.path)
				return -- descendants are covered by the prefix test
			end
			for _, child in node.children do
				walk(child)
			end
		end
		walk(root.node)
	end
	local function isPathLive(path: string): boolean
		for _, retired in retiringRoots do
			-- SEGMENT boundary, not a bare prefix (verifier P2-2): a retiring
			-- "/S/Slot" must not exclude its live sibling "/S/SlotA"
			if path == retired or string.sub(path, 1, #retired + 1) == retired .. "/" then
				return false
			end
		end
		return true
	end

	local dragRegistryInstance: any = nil
	local dragCollaborators: { [string]: any } = {}
	-- per-path live-enabled reads for drag SOURCES (P2-3); populated at wiring,
	-- cleared with the wiring's unbind
	local dragSourceEnabled: { [string]: () -> boolean } = {}
	-- ONE ACTIVATION PER PRESS (PLAT-1): a node carrying both a drag detector and
	-- a native Activated can hear the same press twice (the detector's release
	-- synthesis for classes where the engine consumes the click; the native event
	-- for classes where it does not — gamepad A is documented to deliver it).
	-- Whichever signal arrives first wins; a second signal for the same path
	-- inside the window is the same press echoing. 50 ms is far below any human
	-- double-tap, so a real second tap is never eaten. Time rides the injectable
	-- `now` collaborator so the suite drives this deterministically.
	-- ONLY detector-carrying nodes can echo (they are the only nodes with two
	-- signals per press); every other control dispatches unconditionally — a
	-- toggle mashed twice in 40 ms is two real presses and must count twice.
	local detectorTapGuard: { [string]: boolean } = {}
	local lastNodeTapAt: { [string]: number } = {}
	-- armOnTap sources by path (director round six): consulted by the shared tap
	-- dispatch so a TAP on a declaring source ARMS instead of activating — the
	-- touch paradigm's pickup. Registered with the source, cleared with it.
	local armOnTapDecl: { [string]: boolean } = {}
	local function tapArmsInstead(path: string, meta: any?): boolean
		if armOnTapDecl[path] ~= true then
			return false
		end
		-- action-source activates (gamepad A / Return) belong to the consumer's
		-- onActivate — the armed paradigm already owns them
		if type(meta) == "table" and meta.source == "action" then
			return false
		end
		-- the registry exists whenever a source is registered (registerSource
		-- built it), so a nil instance means no declaring source is mounted
		local reg = dragRegistryInstance
		if reg == nil then
			return false
		end
		if reg.isActive() then
			-- a live session: this tap means something else (put-back, a row
			-- commit) and flows to the consumer unchanged
			return false
		end
		local enabled = dragSourceEnabled[path]
		if enabled ~= nil and not enabled() then
			return false
		end
		return reg.arm(path) == true
	end
	local TAP_ECHO_WINDOW = 0.05
	local function dispatchNodeTapOnce(path: string): boolean
		if not detectorTapGuard[path] then
			return true
		end
		local clock = dragCollaborators.now or os.clock
		local at = clock()
		local last = lastNodeTapAt[path]
		if last ~= nil and (at - last) < TAP_ECHO_WINDOW then
			return false
		end
		lastNodeTapAt[path] = at
		return true
	end
	local dragUnbind: { [string]: () -> () } = {}
	local lastZ: { [string]: number } = {}
	local function dragRegistry(): any
		if dragRegistryInstance == nil then
			dragRegistryInstance = dragRegistryLib.new({
				core = core,
				rectOf = screenRectOf,
				zOf = function(path: string): number?
					return lastZ[path]
				end,
				-- ARCH-F2: a retiring subtree is not a drag surface — resolution-time
				-- exclusion, reversal-safe by construction
				isPathLive = isPathLive,
				-- P2-3: disabled sources acquire nothing, read live per acquisition
				isSourceEnabled = function(path: string): boolean
					local read = dragSourceEnabled[path]
					return read == nil or read()
				end,
				now = dragCollaborators.now,
				feedback = dragCollaborators.feedback,
				proxy = dragCollaborators.proxy,
				motionClock = dragCollaborators.motionClock,
			})
			-- THE HELD SOURCE IS A NODE STATE (director round five): the registry
			-- publishes which path a live session is carrying; the adapter's
			-- `dragHeld` state empties that node's label through the same tag+rule
			-- channel `selected` paints by. Framework guarantee — no consumer code.
			local heldPath: string? = nil
			attachScope:own(core:observe(dragRegistryInstance.heldSource, function(path: string?)
				if heldPath ~= nil and heldPath ~= path then
					local was = handles[heldPath]
					if was ~= nil then
						adapter.setProp(was, "dragHeld", false, "presentation")
					end
				end
				heldPath = path
				if path ~= nil then
					local handle = handles[path]
					if handle ~= nil then
						adapter.setProp(handle, "dragHeld", true, "presentation")
					end
				end
			end))
		end
		return dragRegistryInstance
	end
	-- native drag acquisition, shared by the mount-time wiring below and the
	-- public `controller.attachDragDetector`. Nilable by contract: an adapter or
	-- an engine without `UIDragDetector` answers nil and the caller falls back
	-- to the ADR-0008 pointer capture — the ONE thing that must never differ
	-- between the two paths is the promotion rule, which lives in the registry.
	local function attachDetector(path: string, handlers: any): (() -> ())?
		if adapter.setDragDetector == nil then
			return nil
		end
		local handle = handles[path]
		if handle == nil then
			return nil
		end
		return adapter.setDragDetector(handle, handlers)
	end
	local stats = {
		creates = 0,
		removes = 0,
		rectWrites = 0,
		propWrites = 0,
		solves = 0,
		textMeasureBatches = 0,
		-- recycling: `parked` counts nodes taken out of the tree intact rather than
		-- destroyed; `recycled` counts creates served from the pool instead of the
		-- engine. Both stay 0 unless the feature is on, which makes "is it actually
		-- doing anything" a readable number rather than an inference.
		parked = 0,
		recycled = 0,
		-- diagnostics for "why is recycling doing nothing": whether the feature is
		-- armed at all, and how many park attempts the ADAPTER refused
		recycleArmed = false,
		parkRefused = 0,
		-- nodes the MOST RECENT solve arranged / measured
		lastArranged = 0,
		lastMeasured = 0,
		-- solves served by re-solving one absorbing box instead of the whole tree
		partialSolves = 0,
		elided = 0,
		ssPasses = 0,
		ssEnsureTree = 0,
		ssRetire = 0,
		ssLivePaths = 0,
		ssSweep = 0,
		ssZOrder = 0,
		-- structuralSync phase timings, ms accumulated. MEASURED rather than assumed:
		-- the pass was believed to be O(all live nodes), and it is not — the no-op walk
		-- is ~6% of it and the rest is per-NEW-NODE setup. Kept so that stays visible.
		ssTotal = 0,
		lastSkipped = 0,
	}
	local lastDiagnostics: { any } = {}
	-- the last solve's composition resolutions, by node path (ADR-0023). A solve
	-- OUTPUT, exposed exactly where the other two live (`diagnostics`,
	-- `hiddenRoots`) — an adaptive screen whose only evidence is a screenshot is
	-- an adaptive screen nobody can debug.
	local lastCompositions: { [string]: any } = {}
	-- ...and the last solve's per-text-node measurement facts, by node path
	-- (LTN-4). Same channel, same reason: "this label was cut" is a solve output,
	-- and the presenter's disclosure affordance and the text audit both need it
	-- from the ONE authority that decided it rather than by re-measuring.
	local lastTextFacts: { [string]: any } = {}
	-- words handed to the adapter's premeasurement seam and not yet answered.
	-- Guards against asking twice while one round is in flight; a word that
	-- comes back (measured OR refused) is recorded in text_metrics and can
	-- never be requested again, so this set is the only loop guard needed.
	local textInFlight: { [string]: boolean } = {}
	local disposed = false
	-- paths whose subtree the solver hid this pass (losing ViewThatFits candidates)
	-- THE STRUCTURE EPOCH (2026-08-05). Monotonic; bumped by exactly the two things
	-- that can change what the focus map derives to for a given tree: a structural
	-- sync (nodes mounted/unmounted/reordered) and a change in which roots are HIDDEN
	-- (a ViewThatFits candidate losing at a new width does that without any structural
	-- churn at all, which is why the second half is not optional).
	--
	-- It exists because `presenter.refresh` re-derived the whole focus map from a full
	-- tree walk plus a traversal-rank sort EVERY frame, for EVERY presented surface,
	-- whether or not anything had moved. Measured on the ornate dense-scroll at
	-- 360x691: 478 derivations across 120 frames, 78.4 ms — 20% of all LuauUI work in
	-- the frame, and the great majority of it re-deriving a map identical to the one
	-- already installed.
	local structureEpoch = 0
	local hiddenRoots: { [string]: boolean } = {}
	-- AUTHORED `hidden` (round 3, item D; SwiftUI `hidden()`), kept as its own tiny
	-- set and MERGED into the solver's hidden verdict on every solve. One set means
	-- the prop inherits, with no second implementation: the paint walk, the hit-rect
	-- retraction, the `hiddenRoots` the focus map filters on, and the structure-epoch
	-- bump that makes the focus map notice. Maintained at mount, at removal, and on
	-- the prop's own dirty — never by a whole-tree scan per solve.
	local authoredHidden: { [string]: boolean } = {}
	-- VIEW LIFETIME HOOKS (round 3, item D; SwiftUI `onAppear`/`onDisappear`).
	--
	-- Both are queued rather than called where they are discovered, and the ordering
	-- is the capability rather than an implementation detail:
	--   * appear drains AFTER the frame's solve, so the callback can read its own
	--     rect. Apple's contract is that the closure "completes before the first
	--     rendered frame appears" — nothing here has reached a screen when it runs,
	--     because the whole refresh is one synchronous call.
	--   * disappear drains AFTER the removal sweep, so the handle is already gone and
	--     "the path is not mounted" is a fact rather than a comment. It is drained
	--     OUTSIDE the `mount` profiler span too — a consumer's analytics call is not
	--     Instance churn and must not be billed as it.
	local appearQueue: { { path: string, fn: (string) -> () } } = {}
	local disappearHooks: { [string]: (string) -> () } = {}
	local departedQueue: { { path: string, fn: (string) -> () } } = {}
	-- the expanded hit rect currently pushed per path (nil = none needed)
	local lastHitRects: { [string]: any } = {}
	-- path -> mounted node, memoized for the presentation channel's write sites (see
	-- nodeAt). Declared here, above structuralSync, because that is where it has to
	-- be dropped: mounted identity is stable except across a structural change.
	local presentationNodes: { [string]: any } = {}
	-- (`lastTransform`, the presentation transform pushed per path, is declared up
	-- with `rectOf` — `screenRectOf` reads it — and is dropped in structuralSync
	-- below like every other per-path cache.)
	-- THE metric authority for this surface (ADR-0019 §2). Read fresh at every
	-- use rather than captured, because `themeMetrics` is a live fact: the swap
	-- transaction sets it and re-solves in the same invocation, and a captured
	-- snapshot would paint the old theme's geometry for one frame. A garbage
	-- fact falls back to neutral rather than crashing a mounted surface.
	local function currentMetrics(): any
		local m = env:get("themeMetrics"):get()
		return if type(m) == "table" and type(m.type) == "table" then m else themeSnapshot.neutral()
	end
	-- last visibility pushed per path (hidden subtrees, A-AL1)
	local lastVisible: { [string]: boolean } = {}
	-- PRESENTATION HOLDS (auto reveal, 2026-08-04): paths whose own paint the
	-- PRESENTER is holding while its travelling strip covers them. Presentation
	-- layer only — the solve, rects and facts are untouched — and the visibility
	-- walk ORs it in so a re-solve (or a structural remount of the path) cannot
	-- un-hold a covered label. Presenter-owned: set and cleared through
	-- `controller.setPaintHeld`, never by structuralSync.
	local paintHeld: { [string]: boolean } = {}

	-- RS-PATHCLIP, the LIVE half. A native scroll host moves its canvas without
	-- moving one solved rect ("a same-window scroll delta is zero writes" —
	-- virtual_list), so a cull decided at solve time goes stale the moment the
	-- player scrolls. This re-runs it from the LIVE painted rects and is wired to
	-- every scroll host's own offset change; it touches nothing but paths, and
	-- never contradicts the solver's own hidden verdict.
	local function reculPathClips()
		if adapter.setVisible == nil or pathNodeCount == 0 then
			return
		end
		for path in pathNodes do
			local handle = handles[path]
			if handle ~= nil then
				local want = solverHidden[path] ~= true
					and paintHeld[path] ~= true
					and not pathEscapesClip(path, screenRectOf)
				if lastVisible[path] ~= want then
					adapter.setVisible(handle, want)
					lastVisible[path] = want
				end
			end
		end
	end

	-- A CLOSED SET IS ONLY CLOSED IF THE REACTIVE DOOR IS SHUT TOO
	-- (found live 2026-08-06, playing tutorial example 05).
	--
	-- `PropSpec.enum` exists because an enum prop used to accept any string and
	-- silently do nothing for an unrecognised one — `surface = "panel"` tagged the
	-- node with a selector no rule matched and painted nothing. But `schema.checkValue`
	-- runs at CONSTRUCTION, over a STATIC value. The word game bound `surface` to a
	-- memo returning "tileEmpty"/"tileCorrect"/…, never members of the surface enum,
	-- and all thirty board tiles rendered at BackgroundTransparency = 1: the exact
	-- defect the enum was added to remove, re-entering through the reactive door.
	--
	-- `tint` already had this rule (sheet_model.tintColor: "a bound tint is read long
	-- after construction, so this is the only place a reactive one is ever checked").
	--
	-- SCOPE, STATED HONESTLY (architecture review M-1). This runs inside
	-- `applyProp`/`applyStyleProp`, which are reached only for BINDING_PROPS and
	-- STYLE_PROPS — the PAINT and SEMANTICS channels. It therefore guards
	-- `surface`, `role`, `textAlign`, `scaleMode` and `shape`, and it does NOT
	-- guard an enum prop the SOLVER consumes: `anchor`, `alignH`/`alignV`,
	-- `overflow`, `align`, `reveal`, `axis`, `minColumnWidth`, `itemSizing`,
	-- `focusVisual`. A bound `itemSizing = "unifrom"` still resolves silently as
	-- `natural`. The complete seam is `mount.luau`'s binding write, which is where
	-- every bound value of every channel lands; moving it there is the recorded
	-- follow-up. Do not read this as "every enum prop" — it is not.
	local function assertEnumValue(class: string, prop: string, value: any)
		if type(value) ~= "string" then
			return
		end
		local classSpec = schema.forClass(class)
		local spec = if classSpec ~= nil then (classSpec.props :: any)[prop] else nil
		if spec == nil or spec.enum == nil then
			return
		end
		for _, allowed in spec.enum do
			if value == allowed then
				return
			end
		end
		error(
			`LuauUI {class}.{prop}: '{value}' is not one of {table.concat(spec.enum, " | ")}. `
				.. "A bound value outside the closed set is not a state — it paints nothing.",
			0
		)
	end

	local function applyProp(handle: any, node: any, prop: string)
		authority.assertWrite(node.class, if prop == "label" then "text" else prop, "binding")
		local value = node.props[prop]
		assertEnumValue(node.class, prop, value)
		-- B-BTN1: a content button's label is SEMANTICS, not paint. Writing it as
		-- text too would draw it underneath the custom content.
		if prop == "label" and node.class == "Button" and #node.children > 0 then
			value = ""
		elseif prop == "label" and node.class == "Button" then
			-- ...and an ICON button's label is semantics too: the drawn mark is the
			-- semantic glyph. Same seam the measure pass reads (renderer.drawnButtonText).
			value = renderer.drawnButtonText(node.props)
		elseif prop == "thickness" and type(value) == "string" then
			-- A PATH'S STROKE WEIGHT MAY NAME A METRIC (BP-F12), like the Divider's.
			-- The adapter writes engine pixels, so the name resolves here against
			-- the live snapshot — the same resolution point every other theme-owned
			-- number uses.
			value = themeSnapshot.resolveNumber(currentMetrics(), value)
		end
		adapter.setProp(handle, prop, value, "binding")
		stats.propWrites += 1
	end

	local function applyStyleProp(handle: any, node: any, prop: string)
		authority.assertWrite(node.class, prop, "style")
		assertEnumValue(node.class, prop, node.props[prop])
		adapter.setProp(handle, prop, node.props[prop], "style")
		stats.propWrites += 1
	end

	local function applyProps(handle: any, node: any)
		-- structural region nodes (When/ForEach) carry no user props
		for prop in node.props or {} :: any do
			-- `tint` is the ONE binding prop that is applied after the style props
			-- (ensureTree below), because it composes OVER the paint they settle: a
			-- surface written after a tint would overwrite the very property the tint
			-- claimed, and the node would wear its plain fill for as long as nothing
			-- else touched it.
			if emitsBinding(node.class, prop) and prop ~= "tint" then
				applyProp(handle, node, prop)
			end
		end
	end

	-- ---- INSTANCE RECYCLING (opt-in, default OFF) ---------------------------
	--
	-- A windowed list destroys a row at one end and builds an identical one at the
	-- other, every time the window slides, for no reason except that the PATH
	-- changed. Measured on this engine: build one 24-object row 0.252 ms, destroy
	-- it 0.045 ms, rewrite the same objects' properties 0.024 ms — **12x**. The
	-- structural pass (`LuauUI/mount`) was 0.66-0.97 ms/frame at every viewport,
	-- the largest single component of a frame.
	--
	-- Feature-detected on both sides: the adapter must offer
	-- `park`/`adopt`/`discardParked`. Since L-28 a THEMED node is eligible too —
	-- the adapter releases its chrome's path-keyed registrations on park and
	-- re-keys them on adopt — and `park` still refuses what cannot travel
	-- (clip-host role, presentation transform, motion scale, sibling-parented
	-- hit expander / float focus ring, a focused node). A refusal falls straight
	-- through to the ordinary remove, so the feature can only ever do nothing —
	-- never something different.
	-- ON BY DEFAULT; pass `recycleInstances = false` to opt out. It only ever avoids
	-- work: `park` refuses any node it cannot take intact and the refusal falls
	-- through to the ordinary remove, so the worst case is one boolean test per
	-- create and per remove.
	--
	-- WHY ON: the saving is proportional to CHURN, and churn is not what a creeping
	-- scroll does — it is what a FLING does. Measured on this workload: a steady
	-- scroll retires 2.8 objects/frame (0.035 ms/frame saved, inside the noise),
	-- while a seek that replaces the whole window retires 62.9 objects per jump
	-- (0.78 ms saved per jump, at a measured 12.4 us of engine work per object).
	-- On a low-end Android that avoided work is several times more expensive again,
	-- and it lands on exactly the frames a list feels worst on.
	local recycleEnabled = (opts == nil or opts.recycleInstances ~= false)
		and adapter.park ~= nil
		and adapter.adopt ~= nil
		and adapter.discardParked ~= nil
	-- key: the CREATION-TIME facts the adapter baked into the object. Class decides
	-- the engine class; the decoration hint decides its skin; canvasGroup decides
	-- the class outright. Two nodes agreeing on all three are interchangeable as
	-- far as construction goes — everything else is a property write the renderer
	-- is about to make anyway, because every per-path cache died with the old path.
	stats.recycleArmed = recycleEnabled
	local recyclePool: { [string]: { any } } = {}
	-- the key each live path was BUILT with. Recorded at create because the dying
	-- node's decoration hint is not available at remove time: `pathNodes` is cleared
	-- and refilled with LIVE paths before the sweep, so a dying path reads nil there
	-- and every parked handle would land in a bucket no create ever looks in.
	local recycleKeyOf: { [string]: string } = {}
	local recyclePooled = 0
	local RECYCLE_POOL_CAP = 64
	-- THE KEY INCLUDES THE DECLARED PROPERTY SET, and that is what makes carrying the
	-- property caches sound.
	--
	-- Adoption now writes only the properties that DIFFER from what the instance
	-- already holds. That is only safe if every property on the instance is one the
	-- new node also declares — otherwise a property the OLD identity set and the new
	-- one does not would survive, and nothing would ever clear it. (Proven, not
	-- assumed: the ragged case in `instance_recycling.spec` exists precisely because
	-- rows with different property sets are where that bug lives.)
	--
	-- So two nodes share a pool bucket only if they agree on class, decoration hint,
	-- canvasGroup AND the exact set of property names they declare. In a virtualized
	-- list every row comes from one blueprint, so they all agree and the pool works;
	-- anything else simply does not match and takes the ordinary create path.
	local propSigCache: { [any]: string } = {}
	local function propSignature(node: any): string
		local props = node.props
		if props == nil then
			return ""
		end
		local hit = propSigCache[props]
		if hit ~= nil then
			return hit
		end
		local names = {}
		for name in props do
			table.insert(names, name)
		end
		table.sort(names)
		local sig = table.concat(names, ",")
		propSigCache[props] = sig
		return sig
	end
	-- the hint goes in BY CONTENT (chrome_slots.hintKey), never by address: a
	-- windowed list rebuilds its cell blueprints on every slide, so a
	-- content-equal hint is a different table by construction and
	-- `tostring(hint)` made every hinted node's bucket unreachable (L-28)
	local function recycleKey(class: string, hint: any, canvasGroup: boolean, propSig: string): string
		return `{class}\0{chrome_slots.hintKey(hint)}\0{tostring(canvasGroup)}\0{propSig}`
	end
	local function drainRecyclePool()
		if recyclePooled == 0 then
			return
		end
		for _, bucket in recyclePool do
			for _, handle in bucket do
				adapter.discardParked(handle)
			end
		end
		table.clear(recyclePool)
		recyclePooled = 0
	end

	-- FORWARD. The per-path property caches are declared throughout this file, well
	-- after `ensureTree` — so the park/adopt handlers that move them are declared here
	-- and defined once every cache exists. (Assigning them inline read `lastTextSize`
	-- as nil and took out 47 cases.)
	local captureParkedProps: (path: string) -> any
	local restoreParkedProps: (path: string, carried: any) -> ()

	local function ensureTree(node: any)
		if handles[node.path] == nil then
			-- THE LIFETIME BOOKKEEPING, first, so it is impossible to reach a `return`
			-- or an adapter refusal below without it. `props.onDisappear` is captured
			-- BY VALUE here rather than read off the tree at removal time, because at
			-- removal the node is no longer in the tree — that is the whole point of
			-- the hook. `props.hidden` is registered the same way the sweep clears it.
			if node.props ~= nil then
				if node.props.onAppear ~= nil then
					table.insert(appearQueue, { path = node.path, fn = node.props.onAppear })
				end
				if node.props.onDisappear ~= nil then
					disappearHooks[node.path] = node.props.onDisappear
				end
				if node.props.hidden == true then
					authoredHidden[node.path] = true
				end
				-- read at mount so a node born faded/scaled/rotated paints that way on
				-- its FIRST frame; the write happens after the handle exists, below
				if node.props.opacity ~= nil or node.props.scale ~= nil or node.props.rotation ~= nil then
					readAuthoredPresentation(node)
				end
			end
			-- The DECORATION HINT rides the blueprint's internal `meta` channel
			-- (chrome_slots.readHint) — the same channel the input contribution
			-- uses, never the public prop bag. It is handed to `create` because
			-- skinning is the adapter's LAST construction step: a hint delivered
			-- afterwards would build one decoration and immediately churn it for
			-- another. Targets that do not skin ignore the argument.
			-- 5th argument: CREATION-TIME facts the adapter can only honour while it
			-- is choosing the engine object. `canvasGroup` decides the node's engine
			-- CLASS (ADR-0022 Decision 2), so it cannot arrive as a later prop write —
			-- the instance would already exist. Absent for every ordinary node, and
			-- targets that do not group simply ignore the argument.
			-- AN AUTHORED `opacity` IS A `canvasGroup` DECLARATION (ADR-0026
			-- Decision 4): a fade is a GroupTransparency fact, so the node carrying
			-- one has to BE the group. Creation-time exactly as the explicit prop is,
			-- and on the same recycle-key input, so a bucket cannot mix the two.
			local createOpts: any = nil
			if node.props ~= nil and (node.props.canvasGroup == true or node.props.opacity ~= nil) then
				createOpts = { canvasGroup = true }
			end
			local hint = chrome_slots.readHint(node)
			-- A STAGE IS NEVER A DECORATION SURFACE (reference-app matrix,
			-- 2026-08-08). An ornate package's whole-art recipe painted its
			-- `control` plate OVER a Stage's ViewportFrame — the 3D scene, which
			-- IS the node's content, vanished behind the skin. The engine-content
			-- leaf pins the no-slot hint at creation so no package recipe can
			-- ever cover the scene; a theme still reaches the pane through the
			-- authored stroke/corners modifiers, which decorate the box's edge
			-- rather than its face.
			if node.class == "Stage" then
				-- UNCONDITIONAL (architecture review F14): "never a decoration
				-- surface" is a fact about the CLASS, so no channel — not even a
				-- blueprint-supplied hint — may override it into a covering slot.
				hint = { slot = chrome_slots.NO_SLOT }
			end
			local adopted: any = nil
			if recycleEnabled then
				local key = recycleKey(node.class, hint, createOpts ~= nil, propSignature(node))
				local bucket = recyclePool[key]
				if bucket ~= nil and #bucket > 0 then
					local candidate = table.remove(bucket)
					recyclePooled -= 1
					-- ADOPT MAY REFUSE. It is the adapter's judgement, not ours, and a
					-- refusal must cost nothing but a fresh create — so the candidate is
					-- discarded rather than pushed back, which would let one permanently
					-- un-adoptable handle be retried on every create forever.
					-- the incoming hint rides along so the adapter can hold its own
					-- mismatch rule (the bucket key already agrees by construction,
					-- but the adapter must not depend on its caller's bookkeeping)
					if adapter.adopt(candidate, node.path, node.class, hint) then
						adopted = candidate
						-- restore the instance's own property record under its new path,
						-- so `applyProps` writes only what actually differs
						local carried = candidate.parkedProps
						if carried ~= nil then
							candidate.parkedProps = nil
							restoreParkedProps(node.path, carried)
						end
					else
						candidate.parkedProps = nil
						adapter.discardParked(candidate)
					end
				end
			end
			if adopted ~= nil then
				handles[node.path] = adopted
				stats.recycled += 1
			else
				local made = adapter.create(rootHandle, node.path, node.class, hint, createOpts)
				handles[node.path] = made
				stats.creates += 1
				-- nodes the adapter declined to give an engine object. Counted so a
				-- runtime disable is visible: the source-shape test can only see that
				-- the RULE exists, not that it is switched on.
				if made ~= nil and made.elided == true then
					stats.elided += 1
				end
			end
			if recycleEnabled then
				recycleKeyOf[node.path] = recycleKey(node.class, hint, createOpts ~= nil, propSignature(node))
			end
			-- THE PER-CONTROL SENSORY VERB, published once per handle (see
			-- target_contract's `setActivationFeedback`). Bounded to the classes
			-- that can be activated, because a verb on a Box describes an event
			-- that cannot happen there; written UNCONDITIONALLY for those classes —
			-- the nil included — because a recycled instance carries the previous
			-- control's property, and "only write when there is something to say"
			-- is exactly how a commit button's sensation leaks onto its successor.
			-- Mount-static by construction (a blueprint is frozen), so there is no
			-- update path: a changed declaration is a changed blueprint, which is a
			-- remount.
			if TAPPABLE[node.class] and adapter.setActivationFeedback ~= nil then
				adapter.setActivationFeedback(handles[node.path], node.activationFeedback)
			end
			applyProps(handles[node.path], node)
			-- ...and the authored triple, now that a handle exists. Gated, so a node
			-- declaring none of the three pays one hash lookup at mount and no more.
			if authoredN > 0 and authored[node.path] ~= nil then
				pushPresentationPaint(node.path)
			end
			-- the engine text inset must MATCH the solver's padding (the adapter
			-- used to hardcode 12px, which rendered a 22px star button's glyph
			-- into a negative text area — playlist place, 2026-07-20). The write
			-- itself is applyPadding's, per solve: writing it ONCE here meant a
			-- theme commit moved the solver's padding while the engine kept the
			-- construction inset for the rest of the session.
			-- geometry-affecting typography inputs are layout authority (§11):
			-- applied identically to measurement and render. The scaled value is
			-- written by applyTextScale (below, per solve) so a displaySize flip
			-- (handheld -> TV dock) re-scales paint to match the re-solved layout.
			-- pointer taps flow through the adapter into the same semantic
			-- activate path as focus+Activate (touch parity). Routed through the
			-- per-press dedupe (PLAT-1): when a node ALSO carries a drag detector,
			-- some input classes deliver both this native Activated AND the
			-- detector's release — one press, one activation, first signal wins.
			local onNodeTap = opts and opts.onNodeTap
			if onNodeTap ~= nil and TAPPABLE[node.class] and adapter.setActivateHandler ~= nil then
				local path = node.path
				adapter.setActivateHandler(handles[path], function(meta: any?)
					-- A HIDDEN NODE RESPONDS TO NOTHING (round 3, item D). Apple's
					-- `hidden()` is explicit that a hidden view "can't receive or
					-- respond to interactions", and this is the one gate that has to
					-- hold it: `solverHidden` is the MERGED verdict the visibility walk
					-- writes for every node, so the same line covers an authored
					-- `hidden` and a losing `ViewThatFits` candidate. The candidate case
					-- was previously carried only by its zero rect and the retracted hit
					-- expander — true, but a consequence rather than a rule, and an
					-- authored hide keeps its full-size box on purpose.
					if solverHidden[path] == true then
						return
					end
					if dispatchNodeTapOnce(path) then
						if tapArmsInstead(path, meta) then
							return
						end
						onNodeTap(path, meta)
					end
				end)
			end
			-- pointer hover layer (UI-PARADIGM-001, matrix R§7): interactive nodes
			-- get a hover state, but ONLY when the pointer class is live. A
			-- pure-touch device allocates no hover wiring (hover does not exist off
			-- pointer); nothing essential lives behind it — the visual is a free
			-- preview, the activate path above is class-agnostic. Optional adapter
			-- method: targets without it degrade cleanly (like setRootDisplayOrder).
			if
				adapter.enableHover ~= nil
				and HOVERABLE[node.class]
				and env:get("interactionClasses"):get().pointer == true
			then
				adapter.enableHover(handles[node.path])
			end
			-- FULL-VALUE DISCLOSURE engagement zones (Step 8.5, LTN-4): a Text
			-- that declares `disclose` gets pointer enter/leave and touch
			-- long-press observation on its own instance, routed to the
			-- presenter's engagement seams. Wired at mount like enableHover (the
			-- prop is construction-only), gated per input class the same way —
			-- and only OBSERVED: the label still sinks nothing. Whether a plate
			-- actually appears stays the presenter's call (it re-checks live
			-- truncation facts on every engagement).
			-- class-agnostic like the presenter's walker (LT-G1): a Toggle's
			-- one-line label declares disclose the same way a Text does
			-- ...and a `reveal` node gets the SAME zones: the static plate is the
			-- auto reveal's declared full-value alternative (director 2026-08-04)
			if
				((node.props or {}).disclose == true or (node.props or {}).reveal ~= nil)
				and adapter.enableDisclosure ~= nil
			then
				local hoverCb = opts and (opts :: any).onDiscloseHover
				local pressCb = opts and (opts :: any).onDiscloseLongPress
				if hoverCb ~= nil or pressCb ~= nil then
					local path = node.path
					local classes = env:get("interactionClasses"):get()
					adapter.enableDisclosure(handles[path], {
						hover = if hoverCb ~= nil and classes.pointer == true
							then function(over: boolean)
								hoverCb(if over then path else nil)
							end
							else nil,
						longPress = if pressCb ~= nil and classes.touch == true
							then function(held: boolean)
								pressCb(if held then path else nil)
							end
							else nil,
					})
				end
			end
			-- PUBLIC DRAG/DROP DECLARATIONS (ADR-0022 D5). Registration happens at
			-- mount and unregistration at removal (structuralSync), so a
			-- windowed row that scrolls out of the window stops being a drop
			-- target the frame it stops existing — which is the honest answer:
			-- the hit-test is over VISIBLE targets, and edge autoscroll is how a
			-- row that is not visible becomes reachable.
			local dropDecl = dragContract.readTarget(node)
			if dropDecl ~= nil then
				dragUnbind[node.path .. "\0drop"] = dragRegistry().registerTarget(node.path, dropDecl)
			end
			local dragDecl = dragContract.readSource(node)
			local dragAcquiredNatively = false
			if dragDecl ~= nil then
				-- a DISABLED source acquires nothing (verifier P2-3): the tap gate
				-- already honored enabled=false; the SESSION gate must too. The decl
				-- is frozen, so the gate lives in a renderer-side map the registry
				-- consults per acquisition (reads the LIVE resolved prop — mount
				-- writes updates into node.props)
				local declNode = node
				local declEnabled = dragDecl.enabled
				dragSourceEnabled[node.path] = function(): boolean
					if declNode.props ~= nil and declNode.props.enabled == false then
						return false
					end
					-- the DECLARATION's own gate (SF-D6): a source may refuse to be
					-- picked up while the control stays enabled and activatable, so a
					-- blocked affordance can still explain itself on a tap
					if declEnabled == nil then
						return true
					end
					if type(declEnabled) == "table" and type((declEnabled :: any).get) == "function" then
						return (declEnabled :: any):get() ~= false
					end
					return declEnabled ~= false
				end
				local registry = dragRegistry()
				local unregisterSource = registry.registerSource(node.path, dragDecl)
				armOnTapDecl[node.path] = dragDecl.armOnTap == true
				dragUnbind[node.path .. "\0drag"] = function()
					dragSourceEnabled[node.path] = nil
					armOnTapDecl[node.path] = nil
					unregisterSource()
				end
				-- ACQUISITION, IN PREFERENCE ORDER: the engine's own detector when
				-- the adapter has one (it owns cross-input drag motion), else the
				-- ADR-0008 capture below. Either way the promotion test, the
				-- session and every terminal are the registry's.
				local handlers = registry.detectorHandlers(node.path)
				local rawEnd = handlers.onEnd
				local tapPath = node.path
				local tapClass = node.class
				local tapNode = node
				handlers.onEnd = function(pos: any)
					-- SF-D3's LIVE half (found 2026-07-27 by a real injected click):
					-- the engine's UIDragDetector CONSUMES the click, so a release
					-- under the promotion token never reaches `.Activated`. The
					-- registry answers "tap" for exactly that case and the tap is
					-- dispatched through the SAME node-tap path a native tap takes —
					-- same policy checks, same semantic activate, never eaten.
					--
					-- BOUNDED AGAINST DOUBLE-FIRE (platform verifier PLAT-1): on some
					-- input classes the engine delivers `Activated` even WITH a
					-- detector (gamepad A on a selected button is documented to), so
					-- both paths route through dispatchNodeTapOnce — whichever signal
					-- arrives first wins the press, the second inside the window is
					-- the same press echoing, never a second activation. And the
					-- synthesized tap honors the same gate the native path does
					-- (PLAT-3): a disabled node taps nothing.
					local outcome = rawEnd(pos)
					local onNodeTap = opts and opts.onNodeTap
					if
						outcome == "tap"
						and onNodeTap ~= nil
						and TAPPABLE[tapClass]
						and (tapNode.props == nil or tapNode.props.enabled ~= false)
						and dispatchNodeTapOnce(tapPath)
					then
						if not tapArmsInstead(tapPath, nil) then
							onNodeTap(tapPath, { via = "dragDetectorTap" })
						end
					end
				end
				local detach = attachDetector(node.path, handlers)
				if detach ~= nil then
					dragAcquiredNatively = true
					detectorTapGuard[node.path] = true
					local rawDetach = detach
					detach = function()
						detectorTapGuard[node.path] = nil
						lastNodeTapAt[node.path] = nil
						rawDetach()
					end
					dragUnbind[node.path .. "\0det"] = detach
				end
			end
			-- pointer zones (ADR-0008): nodes carrying pointer callbacks get
			-- capture-based down/move/up through the adapter; handlers receive
			-- the node path and the renderer's rect lookup for drag math.
			--
			-- THAT LOOKUP IS `screenRectOf`, NOT `rectOf` (ESC-2, forced closed by
			-- the device report of 2026-07-28 — gallery example 02 on an iPhone 15
			-- Pro: "when I pick up a row it doesn't always appear under my finger,
			-- the picked up chip moves up as I scroll down"). The whole reason a
			-- handler is handed a rect is to compare it against `pos`, and `pos` is
			-- always WINDOW space. A solved rect inside a scroll host is CANVAS
			-- space — the engine shifts it by CanvasPosition — so a block Table
			-- inside a scrolling page did its drag arithmetic against a rect that
			-- does not move while the page does, and every verdict was wrong by the
			-- page's scroll offset.
			--
			-- ESC-2 was deferred on "no current consumer drags mid-slide", which
			-- weighed only the PRESENTATION half of the shift and missed the SCROLL
			-- half — which a shipped example lives in. Handlers that use rects as
			-- pure DIFFERENCES (Table's resize guide) or read only w/h are
			-- unaffected: the shift is common to both terms.
			local wantsDragCapture = dragDecl ~= nil and not dragAcquiredNatively
			if
				adapter.setPointerHandlers ~= nil
				and (
					wantsDragCapture
					or (node.props and (node.props.onPointerDown or node.props.onPointerMove or node.props.onPointerUp))
				)
			then
				local path = node.path
				local props = node.props or {}
				local registry = if wantsDragCapture then dragRegistry() else nil
				adapter.setPointerHandlers(handles[path], {
					down = function(pos: any)
						-- the drag declaration is offered the press FIRST: only it
						-- can decline on touch (so a native scroll host under the
						-- node keeps the pan), and a decline must reach the adapter
						-- before an authored handler claims the capture
						if registry ~= nil and registry.pointerDown(path, pos) == false then
							return false
						end
						if props.onPointerDown then
							-- propagate the CLAIM/DECLINE verdict: a handler
							-- returning false dissolves the capture so a
							-- sibling zone under the same point can take it
							return props.onPointerDown(path, pos, screenRectOf)
						end
						return nil
					end,
					move = function(pos: any)
						if registry ~= nil then
							registry.pointerMove(path, pos)
						end
						if props.onPointerMove then
							props.onPointerMove(path, pos, screenRectOf)
						end
					end,
					up = function(pos: any)
						if registry ~= nil then
							registry.pointerUp(path, pos)
						end
						if props.onPointerUp then
							props.onPointerUp(path, pos, screenRectOf)
						end
					end,
					-- the zone died mid-drag; reason "removed" may be answered
					-- with true = keep the capture alive (a drag-owned lift
					-- unmounting its own origin row — ADR-0008)
					cancel = function(reason: string?)
						local keep: boolean? = nil
						if registry ~= nil then
							keep = registry.pointerCancel(path, reason)
						end
						if props.onPointerCancel then
							local authored = props.onPointerCancel(path, reason)
							if authored ~= nil then
								return authored
							end
						end
						return keep
					end,
				})
			end
			-- text-entry seam (§17 Phase 5, TextField): the control supplies
			-- onTextChanged/onFocusGained/onFocusLost as node props (functions,
			-- not engine writes); the adapter wires them to the TextBox and
			-- reports edits/focus back through them. Optional adapter method —
			-- absent adapters degrade to a read-only field (§13 seam).
			if
				adapter.setTextInputHandlers ~= nil
				and node.class == "TextField"
				and node.props
				and (node.props.onTextChanged or node.props.onFocusGained or node.props.onFocusLost)
			then
				-- bind the node's full path into onFocusGained: on the real
				-- engine a native-tap focus never routes through handleActivate,
				-- so this is where the control learns its path for keep-visible
				-- (F1). The adapter also passes its handle path; the renderer
				-- guarantees it (path arg wins, node.path is the fallback).
				local nodePath = node.path
				local onFocusGained = node.props.onFocusGained
				adapter.setTextInputHandlers(handles[node.path], {
					onTextChanged = node.props.onTextChanged,
					onFocusGained = if onFocusGained ~= nil
						then function(path: string?)
							onFocusGained(path or nodePath)
						end
						else nil,
					onFocusLost = node.props.onFocusLost,
				})
			end
			-- real clipping (touch-scroll design): a container declaring
			-- clipChildren becomes an engine clip host — its descendants
			-- render inside it and partial overflow crops
			if node.props and node.props.clipChildren == true then
				authority.assertWrite(node.class, "clipChildren", "layout")
				adapter.setProp(handles[node.path], "clipChildren", true, "layout")
			end
			-- wheel scrolling (Phase 4 touch-scroll design): scroll containers
			-- declare onScrollWheel(path, delta, rectOf); the adapter routes
			-- hover-wheel input to it
			if adapter.setScrollHandler ~= nil and node.props and node.props.onScrollWheel then
				local path = node.path
				local props = node.props
				adapter.setScrollHandler(handles[path], function(delta: number)
					props.onScrollWheel(path, delta, rectOf)
				end)
			end
			-- style-authority hints: surface/text roles + Phase 4 shadow and
			-- corner styling (§7.3, §17; visuals resolve inside the adapter's
			-- style application — headless targets keep the data as the dump)
			for _, styleProp in STYLE_PROP_ORDER do
				local hint = node.props and node.props[styleProp]
				if hint ~= nil then
					applyStyleProp(handles[node.path], node, styleProp)
				end
			end
			-- ...and the CONTINUOUS COLOUR LAST (ADR-0022 Decision 6). It claims the
			-- same engine property the surface above just painted, so it has to be the
			-- final word — and because it is last, the adapter's blend resolves against
			-- a node whose style paint is already settled. A reactive change later rides
			-- the ordinary refresh path, by which time the same is true.
			if node.props ~= nil and node.props.tint ~= nil then
				applyProp(handles[node.path], node, "tint")
			end
		end
		for _, child in node.children do
			ensureTree(child)
		end
	end

	-- one walk, two jobs: the live-path set the removal sweep needs, and the
	-- nearest-scroll-host map `screenRectOf` needs. Threading the host down the
	-- recursion is free here and costs a whole-tree search per hit-test if it is
	-- computed on demand instead.
	local function livePaths(node: any, set: { [string]: boolean }, host: string?, clip: string?)
		set[node.path] = true
		scrollHostOf[node.path] = host
		clipHostOf[node.path] = clip
		-- ...and the stroked-path census (RS-PATHCLIP): the cull runs over this
		-- set, so a surface with no `UI.Path` never pays for the rule existing.
		if node.class == "Path" then
			pathNodes[node.path] = true
			pathNodeCount += 1
		end
		local nextHost = if node.class == "ScrollView" then node.path else host
		-- a ScrollView is a clip host by construction (the adapter mounts a real
		-- scrolling host); any container may declare itself one
		local nextClip = if node.class == "ScrollView"
				or (node.props ~= nil and node.props.clipChildren == true)
			then node.path
			else clip
		for _, child in node.children do
			livePaths(child, set, nextHost, nextClip)
		end
	end

	-- paint seam for scaled text (input-paradigms expansion, matrix D.1): write
	-- props.textSize * typographyScale, tracking the last value per path so a
	-- steady scale is a no-op (minimal-write contract) but a displaySize flip
	-- rewrites every scaled size. Runs inside solveAndApply so paint and the
	-- re-solved layout always agree.
	--
	-- ...and the INTRINSIC size paints too (director fix round 2026-07-25). It
	-- used not to: an absent `textSize` left the adapter's hardcoded TextSize 16,
	-- while the measure seam above reserved the class's typography ROLE from the
	-- snapshot. A package that moved that role — compact-pointer draws its control
	-- text at 13 — was therefore reserved for at one size and drawn at another,
	-- and a single-line button label wrapped ("Pla"/"y") inside a box the solver
	-- had sized correctly for the size it measured. Same argument as applyPadding
	-- below, same seam, same guarantee: written inside the solve, against THAT
	-- solve's metrics, so the size the engine draws with and the size the solver
	-- reserved can never disagree.
	--
	-- `textScale` multiplies AUTHORED sizes only, exactly as the measure seam does
	-- (an intrinsic default is not scaled there either), and the preferred-text
	-- offset stays out of paint because the engine applies its own at draw time.
	local lastTextSize: { [string]: number } = {}
	-- THE FACE, beside the size, from the SAME role (F2, 2026-08-02). The
	-- typography role has always carried a font descriptor and the MEASURE seam
	-- has always keyed `text_metrics` on it (`toLayoutNode` -> `layoutNode.font`);
	-- paint did not, so every text node was drawn in whatever face the adapter
	-- hardcoded at creation. That is `Text.font`'s deprecation read backwards —
	-- there, the author's face reached measurement and never paint; here, the
	-- THEME's face reached measurement and never paint — and it is why a weight
	-- channel had to be a role rather than a prop.
	--
	-- Both seams resolve through `themeSnapshot.effectiveTypeRole`, so the
	-- descriptor the solver measured with IS the descriptor the engine draws with.
	-- Written inside the solve, against THAT solve's metrics, exactly as the size
	-- and the Button padding beside it are. Minimal-write: the descriptor key is
	-- cached per path, so a steady theme costs zero writes and every screen whose
	-- roles all resolve to the family's Regular face is byte-identical.
	local lastTextFont: { [string]: string } = {}
	local function applyTextScale(scale: number, metrics: any)
		local function walk(node: any)
			-- an AUTHORED size paints; a role name is just as authored as a number
			-- (it resolves through the same snapshot the measure seam used), while
			-- an absent prop falls back to the class's own typography role
			local raw = themeSnapshot.resolveSize(metrics, node.props and node.props.textSize)
			local authored = raw ~= nil
			if raw == nil and not (node.class == "Button" and #node.children > 0) then
				raw = themeSnapshot.intrinsicTextSize(metrics, node.class)
			end
			if raw ~= nil and handles[node.path] ~= nil then
				local scaled = if authored then raw * scale else raw
				if lastTextSize[node.path] ~= scaled then
					authority.assertWrite(node.class, "textSize", "layout")
					adapter.setProp(handles[node.path], "textSize", scaled, "layout")
					lastTextSize[node.path] = scaled
					stats.propWrites += 1
				end
				-- a CONTENT Button draws no text of its own, so it has no face to
				-- write either (`raw` is already nil for one, above)
				local roleName, role =
					themeSnapshot.effectiveTypeRole(metrics, node.class, node.props and node.props.textSize)
				if role ~= nil then
					if lastTextFont[node.path] ~= role.fontKey then
						authority.assertWrite(node.class, "textFont", "layout")
						adapter.setProp(handles[node.path], "textFont", {
							role = roleName,
							fontKey = role.fontKey,
							family = role.font.family,
							weight = role.font.weight,
							style = role.font.style,
						}, "layout")
						lastTextFont[node.path] = role.fontKey
						stats.propWrites += 1
					end
				end
			end
			for _, child in node.children do
				walk(child)
			end
		end
		walk(root.node)
	end

	-- PAINT SEAM FOR PADDING, exactly the shape applyTextScale has. A Button's
	-- engine text inset is theme geometry: it resolves through the snapshot, so a
	-- theme swap or a designer's live metric edit moves it — and it is written
	-- here, inside the solve, against THAT solve's metrics, so the inset the
	-- engine draws with and the padding the solver reserved can never disagree.
	-- Minimal-write: the effective four sides are cached per path, so a steady
	-- theme costs zero writes.
	--
	-- ...AND A PADDED `Text` GOES OUT THE SAME SEAM (device report 2026-08-12,
	-- IMG_3691 — the S1..S12 stat tiles). `UI.padding` is legal on a Text because
	-- the solver's text measure ADDS it to the reserved box
	-- (`blueprint_schema` Text.padding: "it lets UI.padding apply without
	-- wrapping"), and nothing painted it: the plate came out label+12 wide and the
	-- glyphs were drawn from the box's leading edge, so every tile's label sat
	-- against — and over — its own rounded corner. Measured at a size nobody
	-- painted, which is `docs/lessons/measure-the-requirement-not-the-render.md`
	-- read backwards. A container spends its padding in `arrange` (children are
	-- placed at rect + padding) and a Button already had this write, so a text LEAF
	-- was the one shape where the two passes could disagree.
	--
	-- Guarded on an AUTHORED value: an unpadded Text — every Text on every shipped
	-- screen but these — raises no write and materializes no engine modifier.
	local lastPadding: { [string]: string } = {}
	local function applyPadding(metrics: any)
		local function walk(node: any)
			local pad: any = nil
			if node.class == "Button" then
				pad = themeSnapshot.buttonPadding(metrics, node.props)
			elseif node.class == "Text" then
				if node.props ~= nil and node.props.padding ~= nil then
					pad = themeSnapshot.resolveSides(metrics, node.props.padding)
				elseif lastPadding[node.path] ~= nil then
					-- ...AND AN ADOPTED INSTANCE MUST BE UN-PADDED EXPLICITLY. The
					-- recycler carries `padding` across an adoption
					-- (`captureParkedProps`/`restoreParkedProps` below), so a padded
					-- label recycled into an unpadded one would keep the previous row's
					-- inset on a modifier this seam had stopped visiting. Zeroing is a
					-- write; skipping is a stale glyph box.
					pad = { top = 0, right = 0, bottom = 0, left = 0 }
				end
			end
			if pad ~= nil and handles[node.path] ~= nil then
				local top, right, bottom, left = solver.sides(pad)
				local key = `{top},{right},{bottom},{left}`
				if lastPadding[node.path] ~= key then
					authority.assertWrite(node.class, "padding", "layout")
					adapter.setProp(handles[node.path], "padding", pad, "layout")
					lastPadding[node.path] = key
					stats.propWrites += 1
				end
			end
			for _, child in node.children do
				walk(child)
			end
		end
		walk(root.node)
	end

	-- PAINT SEAM FOR THE COMPACT LADDER, the same shape applyTextScale and
	-- applyPadding have (director, 2026-07-27).
	--
	-- The verdict is the SOLVER's — only it knows the width this node ended up
	-- with — and it reaches paint through the rects it produced, so the string the
	-- box was reserved for is the string the engine draws. That is the whole
	-- reason this is a post-solve seam and not a prop the author toggles.
	--
	-- The label ITSELF still goes out on the ordinary binding write, so there is
	-- exactly one writer for `Text` and `screen_target`'s TextWrapped rule
	-- re-decides from the string it is handed, exactly as it does for a reactive
	-- label. An icon form additionally raises an icon REQUEST, which is the same
	-- upgrade-not-dependency arrangement `props.icon` already uses: the ASCII
	-- glyph is already drawn, and theme art paints over it if any resolves.
	-- Minimal-write: the verdict is cached per path, so a steady layout costs zero
	-- writes and a node with no compact form is never visited twice.
	local lastCompact: { [string]: boolean } = {}

	-- ...and the WRAP verdict, on the same seam and for the same reason (director
	-- ruling 5, 2026-08-13). `screen_target`'s TextWrapped rule sees the string and
	-- not the box, so it cannot answer "does this phrase's longest word fit"; the
	-- solver can, and does (`textFacts.wraps`). Unlike `lastCompact` this IS a value
	-- the instance holds, so it rides the parked-props record across a recycle
	-- exactly as `lastTextSize` does — a recycled instance carrying `TextWrapped =
	-- false` with a cleared cache would silently keep it.
	--
	-- `nil` means "never written", which is the adapter's own default (wrap on
	-- whitespace) — so the overwhelmingly common `wraps = true` node costs ZERO
	-- writes, on the first solve and every one after it.
	local lastWrapped: { [string]: boolean } = {}

	-- The instance's own property record, moved with it across a recycle. These say
	-- what the ENGINE OBJECT holds, so they stay true when the path changes — which is
	-- what lets adoption write only the differences.
	--
	-- TWO ARE DELIBERATELY EXCLUDED, and the difference is worth stating: a cache may
	-- be carried only if it records a VALUE the instance holds. `solverHidden` is a
	-- verdict about the node. `lastCompact` looks like a value and is not — it gates
	-- `applyTextVerdicts`' compact half, whose WRITE depends on the new node's label, so a carried
	-- `true` skips re-applying a different row's glyph and the previous row's label
	-- survives. (Caught by "a REMOUNTED button gets its verdict re-applied", which is
	-- itself the pin for a defect found live on RascalRally's watch-cycle buttons.)
	captureParkedProps = function(path: string): any
		return {
			rect = lastRects[path],
			z = lastZ[path],
			textSize = lastTextSize[path],
			textFont = lastTextFont[path],
			padding = lastPadding[path],
			visible = lastVisible[path],
			hitRect = lastHitRects[path],
			textWrapped = lastWrapped[path],
		}
	end
	restoreParkedProps = function(path: string, carried: any)
		lastRects[path] = carried.rect
		lastZ[path] = carried.z
		lastTextSize[path] = carried.textSize
		lastTextFont[path] = carried.textFont
		lastPadding[path] = carried.padding
		lastVisible[path] = carried.visible
		lastHitRects[path] = carried.hitRect
		lastWrapped[path] = carried.textWrapped
	end
	-- ONE WALK, TWO VERDICTS. Both are the solver's answers about text, both reach
	-- paint through the rects that produced them, and both are cached per path — so
	-- they share the traversal rather than paying for a second one on every solve.
	local function applyTextVerdicts(rects: any)
		local function walk(node: any)
			local handle = handles[node.path]
			local labelDriven = node.class == "Text" or (node.class == "Button" and #node.children == 0)
			if labelDriven and handle ~= nil then
				local entry = rects[node.path]
				if node.class == "Button" then
					local isCompact = entry ~= nil and entry.compact == true
					local form = renderer.compactForm(node.props)
					if form ~= nil and lastCompact[node.path] ~= isCompact then
						authority.assertWrite("Button", "text", "binding")
						adapter.setProp(handle, "label", renderer.drawnButtonText(node.props, isCompact), "binding")
						stats.propWrites += 1
						if form.kind == "icon" then
							authority.assertWrite("Button", "icon", "style")
							adapter.setProp(handle, "icon", if isCompact then form.icon else nil, "style")
							stats.propWrites += 1
						elseif form.kind == "image" then
							authority.assertWrite("Button", "compactLabel", "style")
							adapter.setProp(handle, "compactLabel", if isCompact then form else nil, "style")
							stats.propWrites += 1
						end
						lastCompact[node.path] = isCompact
					end
				end
				-- THE WRAP VERDICT (ruling 5). A node the solve did not reach (hidden,
				-- not yet solved) keeps whatever it has: absent facts are not a verdict.
				local facts = if entry ~= nil then entry.textFacts else nil
				if facts ~= nil then
					local wraps = facts.wraps == true
					local previous = lastWrapped[node.path]
					if (if previous == nil then true else previous) ~= wraps then
						authority.assertWrite(node.class, "textWrapped", "layout")
						adapter.setProp(handle, "textWrapped", wraps, "layout")
						lastWrapped[node.path] = wraps
						stats.propWrites += 1
					end
				end
			end
			for _, child in node.children do
				walk(child)
			end
		end
		walk(root.node)
	end

	-- the inputs of the most recent solve, for the opt-in boundary analysis below
	local lastSolveInputs: any = nil

	-- ---- INCREMENTAL LAYOUT, STAGE 2 v2 — SKIP SUBTREES INSIDE ONE SOLVE -------
	--
	-- v1 re-solved the boundary subtree as its own ROOT and it could not be made
	-- correct: a sub-solve gets a fresh `ctx` (no `hasScroll`, `hiddenDepth` 0, zeroed
	-- insets) and a screen-root policy applied to a node that is not a screen. Ten
	-- existing cases found ten ways that mattered, starting with a `percent` box
	-- resolving its fraction against itself.
	--
	-- v2 keeps ONE solve from the root — same traversal, same ctx, same policies — and
	-- lets the solver SKIP a subtree it can prove cannot have changed: no dirty node
	-- inside it, and the same offer/rect it had last time. Nothing is re-based,
	-- re-rooted or re-parented, so there is no second context to disagree with the
	-- first. The published verdicts and diagnostics for a skipped subtree are replayed
	-- from the previous result, which is exactly the mechanism the measure memo in
	-- `solver.measure` already uses (and which a differential fuzz once caught
	-- returning geometry without them).
	local incrementalEnabled = opts == nil or (opts :: any).incrementalLayout ~= false
	local lastResult: any = nil
	local dirtyContains: { [string]: boolean }? = nil

	-- `controller.onSolved` listeners: run at the tail of every OUTERMOST solve.
	-- The presenter uses exactly one of these, to feed solved geometry to the
	-- consumers that measure this surface (see the tail of solveAndApply, L-31).
	local solvedListeners: { () -> () } = {}
	local notifyingSolved = false

	local function solveAndApply()
		stats.solves += 1
		local vp = env:get("viewportRect"):get()
		local insets = env:get("coreSafeInsets"):get()
		-- deviceSafeContent (native-substrate NS-A1): the notch/rounded-corner
		-- device insets are a SEPARATE fact from the CoreGui insets; a screen
		-- opting into deviceSafeContent clears BOTH, so the content rect insets
		-- by the per-edge maximum. coreSafeContent (default) keeps the historic
		-- CoreGui-only behavior. Exactly one authority applies insets: these
		-- facts feed the solver; the ScreenGui renders IgnoreGuiInset=true.
		-- edgeToEdge: a DECORATION layer, not content. Safe areas exist so content
		-- is readable and reachable; a scrim or a backdrop is neither — it has to
		-- paint to the edges or it draws a rectangle inside the screen with the
		-- world showing around it, which is what a device capture showed.
		--
		-- THIS NAME WAS ALREADY BEING PASSED AND NEVER READ. The presenter has
		-- asked for `rootPolicy = "edgeToEdge"` on every scrim since scrims
		-- existed, with a comment saying "covers the whole viewport (incl.
		-- insets)" — and no branch here matched it, so every scrim silently got
		-- the ordinary content insets instead. A policy string nothing consumes
		-- is indistinguishable from a policy that works until you look.
		if rootPolicy == "edgeToEdge" then
			insets = { top = 0, bottom = 0, left = 0, right = 0 }
		elseif rootPolicy == "deviceSafeContent" then
			local device = env:get("deviceSafeInsets"):get()
			if type(device) == "table" then
				insets = {
					top = math.max(insets.top, device.top or 0),
					bottom = math.max(insets.bottom, device.bottom or 0),
					left = math.max(insets.left, device.left or 0),
					right = math.max(insets.right, device.right or 0),
				}
			end
		end
		local textScale = env:get("typographyScale"):get()
		if type(textScale) ~= "number" or textScale ~= textScale then
			textScale = 1
		end
		-- split text-scale seams (NS-A9): MEASURE reserves the engine-scaled
		-- bounds (typographyScale includes the player preference); PAINT writes
		-- only authored scale — the engine applies the preference itself at
		-- draw time (double-application fix, corrections §9).
		local paintScale = env:get("typographyPaintScale"):get()
		if type(paintScale) ~= "number" or paintScale ~= paintScale then
			paintScale = 1
		end
		-- RESERVATION FLOOR (preferred-text sweep, 2026-07-24): the two seams are
		-- only safe while measure >= paint. typographyScale's legal domain starts
		-- at 0.5 (a dev/test profile may set preferredTextSize below 1) while the
		-- paint seam carries no preference factor at all — so a sub-1 preference
		-- reserved HALF the box the engine then drew into, and every explicit-size
		-- text node clipped. Proven live at preferredTextSize=0.5: 10 nodes
		-- reported TextFits == false on both the phone and desktop profiles.
		-- Over-reserving is always safe; under-reserving is never. Measure
		-- therefore takes the larger of the two scales.
		local measureScale = math.max(textScale, paintScale)
		-- ten-foot presentation (input-paradigms expansion): TVs clip edges,
		-- so overscan margins compose ON TOP of the CoreGui safe insets while
		-- the display class is Large; a near display keeps the full canvas
		if env:get("distanceProfile"):get() == "ten-foot" then
			local overscan = env:get("effectiveOverscanInsets"):get()
			if type(overscan) == "table" then
				insets = {
					top = insets.top + (overscan.top or 0),
					bottom = insets.bottom + (overscan.bottom or 0),
					left = insets.left + (overscan.left or 0),
					right = insets.right + (overscan.right or 0),
				}
			end
		end
		local prefOffset = env:get("preferredTextOffset"):get()
		if type(prefOffset) ~= "number" or prefOffset ~= prefOffset then
			prefOffset = 0
		end
		prefOffset = math.clamp(prefOffset, 0, 32)
		-- the adapter owns the scrollbar thickness (it is engine-specific); the
		-- solver reserves it off a scrolling region's cross axis so content is
		-- never laid out underneath the bar
		local barReserve = if type((adapter :: any).scrollBarThickness) == "number"
			then (adapter :: any).scrollBarThickness
			else 0
		-- EXACT TEXT MEASUREMENT (text-measurement milestone): bracket the solve
		-- so the words it could not size exactly come back attached to THIS
		-- surface's solve. Per-solve rather than a global queue on purpose — a
		-- shared queue lets one surface drain another's requests, and the
		-- surface that never sees its own measurement never re-solves.
		text_metrics.beginCollect()
		-- ONE snapshot per solve: the layout-node builder, the solver's measure
		-- path and the paint seam must all resolve the same theme, or a swap
		-- landing mid-solve would measure one theme and paint another
		local metrics = currentMetrics()
		local layoutRoot = toLayoutNode(root.node, metrics, measureScale, prefOffset)
		local solveOpts = {
			safeInsets = insets,
			rootPolicy = rootPolicy,
			scrollBarReserve = barReserve,
			metrics = metrics,
		}
		-- kept so the Stage-1 boundary analysis can re-solve the SAME tree with the
		-- SAME offers; an analysis run against a differently-built tree would be
		-- measuring something other than what shipped
		lastSolveInputs = { layoutRoot = layoutRoot, viewport = { w = vp.w, h = vp.h }, opts = solveOpts }
		if incrementalEnabled and lastResult ~= nil and dirtyContains ~= nil then
			solveOpts.reuse = { previous = lastResult, dirtyContains = dirtyContains }
		end
		local result = solver.solve(layoutRoot, { w = vp.w, h = vp.h }, solveOpts)
		if result.work ~= nil and (result.work.skipped or 0) > 0 then
			stats.partialSolves += 1
			stats.lastSkipped = result.work.skipped
		end
		lastResult = result
		-- the last solve's work, surfaced through `controller.stats()`. This is what
		-- makes "one changed value re-laid-out the whole tree" a testable claim rather
		-- than something you have to instrument the solver to see.
		if result.work ~= nil then
			stats.lastArranged = result.work.arranged
			stats.lastMeasured = result.work.measured
		end
		-- MICROPROFILER PHASE `LuauUI/commit` (roadmap Step 9): the ADAPTER COMMIT —
		-- everything between a finished solve and a frame the player can see. Visibility,
		-- hit rects, rects, scroll regions, z-order, transforms and the text-measurement
		-- follow-up all live here. It is deliberately ONE scope for the whole pass rather
		-- than one per write class: the question a capture asks is "is the framework's
		-- output cheap relative to its solve", and eight sibling bars answer it worse than
		-- one. `measure`/`arrange` are nested INSIDE the enclosing solve and remain
		-- separately named, so inclusive-minus-exclusive still separates the two halves.
		profile.span("commit", function()
			local textRequests = text_metrics.endCollect()
			lastDiagnostics = result.diagnostics
			applyTextScale(paintScale, metrics)
			applyPadding(metrics)
			applyTextVerdicts(result.rects)
			-- hidden subtrees (A-AL1): a ViewThatFits candidate that lost keeps its
			-- mount but must not be reachable. The solver marks the losing candidate
			-- roots; the presenter reads this set to exclude them from focus order,
			-- so navigation can never land on an invisible control.
			local nextHidden: { [string]: boolean } = {}
			local nextCompositions: { [string]: any } = {}
			local nextTextFacts: { [string]: any } = {}
			-- THE AUTHORED HIDES JOIN THE SOLVER'S OWN VERDICT (round 3, item D). One
			-- set from here down, so `hidden = true` inherits the paint walk, the
			-- hit-rect retraction, the `hiddenRoots` the focus map filters on, and the
			-- structure-epoch bump below — none of which a parallel paint-only channel
			-- would have reached.
			for path in authoredHidden do
				nextHidden[path] = true
			end
			for path, entry in result.rects do
				if entry.hidden == true then
					nextHidden[path] = true
				end
				if entry.composition ~= nil then
					nextCompositions[path] = entry.composition
				end
				if entry.textFacts ~= nil then
					nextTextFacts[path] = entry.textFacts
				end
			end
			lastCompositions = nextCompositions
			lastTextFacts = nextTextFacts
			-- ...AND A HIDE IS A FOCUS-MAP CHANGE, with no structural sync behind it.
			-- Compared rather than assumed-changed: the set is 0-2 entries on a normal
			-- surface, so this is cheaper than the derivation it guards, and bumping
			-- unconditionally here would defeat the epoch entirely (this runs on every
			-- solve).
			local hiddenChanged = false
			for path in nextHidden do
				if hiddenRoots[path] == nil then
					hiddenChanged = true
					break
				end
			end
			if not hiddenChanged then
				for path in hiddenRoots do
					if nextHidden[path] == nil then
						hiddenChanged = true
						break
					end
				end
			end
			if hiddenChanged then
				structureEpoch += 1
			end
			hiddenRoots = nextHidden
			-- a hidden candidate must not PAINT. A zero rect was not enough: text still
			-- wrapped and drew inside a 0px box (found live in the adaptive_controls
			-- capture, where the losing action column's labels ran down the screen edge).
			if adapter.setVisible ~= nil then
				local function rectFor(path: string): any
					return paintedRectIn(result.rects, path)
				end
				local function pushVisible(node: any, hidden: boolean)
					local isHidden = hidden or nextHidden[node.path] == true
					solverHidden[node.path] = isHidden
					-- RS-PATHCLIP: a stroked path outside its clip host is culled. It is
					-- decided per NODE and never inherited (a Path is a leaf, and the
					-- solver's own verdict is what descends), so the walk keeps carrying
					-- `isHidden` down and this only widens the write for the path itself.
					-- ...and a presenter PAINT HOLD (auto reveal) is a per-node veto the
					-- same way: never inherited, never contradicting the solver.
					local wantHidden = isHidden or paintHeld[node.path] == true
					if not wantHidden and pathNodes[node.path] == true and pathEscapesClip(node.path, rectFor) then
						wantHidden = true
					end
					local handle = handles[node.path]
					if handle ~= nil and lastVisible[node.path] ~= not wantHidden then
						adapter.setVisible(handle, not wantHidden)
						lastVisible[node.path] = not wantHidden
					end
					for _, child in node.children do
						pushVisible(child, isHidden)
					end
				end
				pushVisible(root.node, false)
			end
			-- B-BTN3: enforce the effective target floor in HIT geometry. The visual
			-- rect is deliberately untouched — flooring the painted size would silently
			-- rewrite shipped design (a 22px icon button would double) — so the
			-- framework separates what the player SEES from what the player can HIT.
			-- Feature-detected: an adapter without the seam keeps today's behaviour.
			if adapter.setHitRect ~= nil then
				-- RS-A16-D1 (found live by the rich-skinning-v2 matrix drive, under the
				-- FLAT default, with real injected clicks): this walk used to ignore the
				-- `nextHidden` set the visibility walk just built. A hidden candidate
				-- solves to zero width, so every control inside it fell under the floor
				-- and the renderer ASKED for an expanded hit rect — a live activation
				-- surface for a control the player cannot see, which in the real adapter
				-- sits at the ScreenGui root and out-ranked the VISIBLE winner's buttons.
				-- Hiddenness is carried down the walk (the solver marks the candidate
				-- ROOT only) exactly as `pushVisible` carries it, and a hidden node takes
				-- the SAME diff path with `want = nil`, so a node that BECOMES hidden has
				-- its expander retracted rather than merely left un-refreshed.
				local function pushHitRects(node: any, hidden: boolean)
					local isHidden = hidden or nextHidden[node.path] == true
					-- the same reading the solve was handed as `hitFloor` (see
					-- `effectiveHitFloor`): the contract declares the floor exists, the
					-- theme owns its value, and it clamps up only
					local floor = effectiveHitFloor(node.class, metrics)
					if floor ~= nil then
						local entry = result.rects[node.path]
						local handle = handles[node.path]
						if entry ~= nil and handle ~= nil then
							local r = entry.rect
							local want: any = nil
							if not isHidden and (r.w < floor or r.h < floor) then
								local w = math.max(r.w, floor)
								local h = math.max(r.h, floor)
								want = {
									x = r.x - math.floor((w - r.w) / 2),
									y = r.y - math.floor((h - r.h) / 2),
									w = w,
									h = h,
								}
							end
							local last = lastHitRects[node.path]
							if not rectsEqual(last, want) then
								adapter.setHitRect(handle, want)
								lastHitRects[node.path] = want
							end
						end
					end
					for _, child in node.children do
						pushHitRects(child, isHidden)
					end
				end
				pushHitRects(root.node, false)
			end
			-- `withAnimation`, and ONLY on the armed commit it forces for itself
			-- (design §"Blocker 1"). It must sit HERE: root classification is
			-- top-down, so it needs a tree walk rather than the unordered rect hash
			-- below, and it has to read `lastRects` before that loop overwrites it.
			if animationSession ~= nil then
				installAnimationRecords(result.rects)
			end
			for path, entry in result.rects do
				local handle = handles[path]
				if handle ~= nil and not rectsEqual(lastRects[path], entry.rect) then
					authority.assertWrite("common", "size", "layout")
					adapter.setRect(handle, entry.rect)
					lastRects[path] = entry.rect
					stats.rectWrites += 1
				end
			end
			-- native scroll regions (native-substrate NS-A2): a scroll node's SOLVED
			-- content extent (plus its own padding — children arrange inside the
			-- padded area, so the canvas must include it) maps to the adapter's
			-- canvas. The adapter/engine owns the live offset; the solver keeps
			-- owning every content rect. Feature-detected: a scroll-less adapter
			-- (billboard until proven, old fake) keeps the clip-only fallback.
			if adapter.setScrollRegion ~= nil then
				local function pushRegions(node: any)
					if node.class == "ScrollView" then
						local entry = result.rects[node.path]
						local handle = handles[node.path]
						if entry ~= nil and entry.contentSize ~= nil and handle ~= nil then
							-- THE PADDING THE SOLVER ACTUALLY SPENT, not the padding the
							-- author wrote (found 2026-07-27 while chasing a landscape
							-- scroll cut-off). `toLayoutNode` adds a slot's `chromeInsets`
							-- to this node's padding before the solve, and a ScrollView
							-- always classifies into the `scrollbar` slot — so recomputing
							-- from `props.padding` here would under-report the canvas by
							-- exactly the theme's reservation, and the tail of the content
							-- would be unreachable. Inert today (every shipped package
							-- declares `chrome.scrollbar = { kind = "native" }`, reserving
							-- zero) and wrong the moment one does not.
							local props = node.props or {}
							local layoutPadding = if entry.padding ~= nil
								then entry.padding
								else themeSnapshot.resolveSides(metrics, props.padding)
							local pt, pr, pb, pl = solver.sides(layoutPadding)
							-- ...PLUS THE THEME'S DECORATION BLEED (director round 11,
							-- root-caused 2026-07-27 from a landscape capture).
							--
							-- A canvas built from RECTS stops exactly at the last child's
							-- rect — I measured it doing so to the pixel in seven
							-- configurations. A `shadow` recipe paints OUTSIDE that rect,
							-- so under Sci-Fi HUD (a centred 24px glow on `panel`) the
							-- bottom of the last element was unreachable: scrollbar at the
							-- end of its track, content still cut off.
							--
							-- It is spent HERE and nowhere else, deliberately. Reserving it
							-- as layout margin would be the other way to fix it and it would
							-- be wrong — a glow is meant to overlap its neighbours, and
							-- reserving it would space every themed screen out by 24px in
							-- every direction. A canvas allowance is the iOS `contentInset`
							-- shape: the layout does not move, the paint becomes reachable.
							-- Zero for every package that declares no shadow.
							local bleed = if type(metrics.chromeBleed) == "number" then metrics.chromeBleed else 0
							local region = {
								axis = props.axis or "y",
								contentW = entry.contentSize.w + pl + pr + bleed,
								contentH = entry.contentSize.h + pt + pb + bleed,
								-- the host's ARRANGED box, so the adapter's cross-axis
								-- canvas clamp is deterministic instead of racing the
								-- engine's own window geometry mid-layout
								hostW = entry.w,
								hostH = entry.h,
								-- per-host indicator opt-out (director ruling 2026-08-09):
								-- carried on the region because the adapter learns a host
								-- overflows on exactly this walk — the same place its
								-- indicator lifecycle begins
								indicators = if props.indicators == "none" then "none" else "auto",
							}
							-- the host's own autoscroll declaration, recorded on the SAME
							-- walk that publishes its canvas: `false` opts out, a table
							-- tunes the model, absent means on-and-inert. Kept here so the
							-- per-frame stepper never needs a tree lookup.
							scrollAutoscroll[node.path] = if props.autoscroll == false
								then false
								else (if type(props.autoscroll) == "table" then props.autoscroll else true)
							local last = lastScrollRegions[node.path]
							if
								last == nil
								or last.axis ~= region.axis
								or last.contentW ~= region.contentW
								or last.contentH ~= region.contentH
								or last.indicators ~= region.indicators
								or last.hostW ~= region.hostW
								or last.hostH ~= region.hostH
							then
								authority.assertWrite("common", "canvasSize", "layout")
								adapter.setScrollRegion(handle, region)
								lastScrollRegions[node.path] = region
							end
							-- RS-PATHCLIP: the host's live offset is what a stroked path
							-- inside it has to be re-culled against. One subscription per
							-- scroll host, taken where the host is already in hand; the
							-- callback early-outs on a surface with no paths, so a list that
							-- draws none pays a comparison.
							if adapter.observeScroll ~= nil and pathClipObservers[node.path] == nil then
								pathClipObservers[node.path] = adapter.observeScroll(handle, function()
									reculPathClips()
								end)
							end
						end
					end
					for _, child in node.children do
						pushRegions(child)
					end
				end
				pushRegions(root.node)
			end

			-- ...and only now, with this frame fully painted from the conservative
			-- estimate, ask the engine for the words it could not size. Ordering is
			-- the safety property: the first frame is always the over-reserving
			-- fallback, never a guess waiting on an async answer, and the exact
			-- geometry lands one re-solve later. Batched per SOLVE over the whole
			-- tree's vocabulary — never per node.
			if adapter.measureTextWidths ~= nil and #textRequests > 0 and not disposed then
				local batch: { any } = {}
				for _, request in textRequests do
					local key = `{request.font}\0{request.size}\0{request.word}`
					if not textInFlight[key] then
						textInFlight[key] = true
						table.insert(batch, request)
					end
				end
				if #batch > 0 then
					stats.textMeasureBatches += 1
					-- `final` (default true) is the adapter saying "this batch is
					-- closed". An adapter that answers early with widths it does not
					-- yet trust — the Roblox one does, while the engine's boot window
					-- is still open — passes false, and the words stay in flight so a
					-- surface waiting for exact text keeps waiting.
					adapter.measureTextWidths(batch, function(results: { any }, final: boolean?)
						local learned = false
						for _, entry in results do
							if type(entry) ~= "table" then
								continue
							end
							if final ~= false then
								textInFlight[`{entry.font}\0{entry.size}\0{entry.word}`] = nil
							end
							if type(entry.width) == "number" then
								-- an adapter may answer the SAME batch twice (the
								-- Roblox one re-reads once the session has settled and
								-- corrects the boot answer), so a re-solve is owed only
								-- when a width actually moved
								local previous = text_metrics.measuredWidth(entry.font, entry.size, entry.word)
								if text_metrics.setMeasured(entry.font, entry.size, entry.word, entry.width) then
									if previous ~= entry.width then
										learned = true
									end
								else
									-- a measurement this seam refuses is a measurement
									-- that could clip: keep the estimate, and do not
									-- ask for it again on every solve
									text_metrics.markUnmeasurable(entry.font, entry.size, entry.word)
								end
							else
								text_metrics.markUnmeasurable(entry.font, entry.size, entry.word)
							end
						end
						--[[ exactly one re-solve per answered round, and only when the
							round actually taught the measurer something.

							PUBLISH THE GENERATION FIRST (director 2026-08-04, the
							finish-screen size pop). The re-solve fixes the SOLVER's boxes,
							but a consumer memo that called `LuauUI.text.fit/.size/.measure`
							has no dependency on the exact-width store — it is plain data —
							so it evaluated once against the ESTIMATOR and nothing here
							invalidated it. Bumping `textMeasureEpoch` is that dependency:
							any memo that reads it re-derives once, on this frame, together
							with the solve rather than at some arbitrary later tick. Written
							before `solveAndApply` so the re-solve already sees the
							re-derived values instead of needing a third pass. ]]
						if learned and not disposed then
							-- `env:get` answers the FACT's signal, so the current value is one
							-- more `:get()` in (same shape as every other read in this file)
							env:set("textMeasureEpoch", ((env:get("textMeasureEpoch"):get() :: number?) or 0) + 1)
							solveAndApply()
						end
					end)
				end
			end
			-- A REFLOW MOVES THE DROP TARGETS (ADR-0022 D5). Every rect the live
			-- session hit-tests against was just rewritten, so the hover is
			-- re-evaluated at the last pointer position on THIS frame — a verdict
			-- that trailed the layout by a frame is a verdict about geometry the
			-- player is no longer looking at.
			if dragRegistryInstance ~= nil and dragRegistryInstance.isActive() then
				dragRegistryInstance.refreshTargets()
			end
		end)
		--[[ THE SOLVE IS OVER: tell whoever measures this surface (L-31).
			The presenter's `feedGeometry` used to run only from `refresh()` on the
			host's frame connection, which put a whole FRAME between a solve and the
			consumer that measures it — so a consumer publishing a number derived
			from its own geometry (a dock reserving space, a keyboard inset, a
			sticky header) could never join the flush that caused it, and opened a
			second one. Fed from here, that write lands inside the settle phase that
			produced the rects and the cycle converges before anything is painted.

			RE-ENTRANCY IS THE ONLY HAZARD, and it is real: the text-measurement
			round above calls `solveAndApply()` again from inside this very
			function. Notifying from the inner call would feed rects the outer call
			is about to rewrite, so the guard reports once, from the outermost
			solve, with the final geometry. ]]
		if not notifyingSolved then
			notifyingSolved = true
			-- deliberately NOT pcall'd: `feedGeometry` runs unguarded from
			-- `refreshBody` today and a throwing consumer must keep behaving the
			-- same way. When this fires from the settle phase the core quarantines
			-- it into `lastError` like every other callback; when it fires from
			-- `controller.refresh()` it propagates, exactly as before.
			local ok, err = pcall(function()
				for _, fn in solvedListeners do
					fn()
				end
			end)
			notifyingSolved = false
			if not ok then
				error(err, 0)
			end
		end
	end

	-- flat sibling rendering paints in z-order; instance creation order is NOT
	-- deterministic across a structural sync, so z is assigned explicitly from
	-- the tree walk (ADR-0008; live-found defect 2026-07-19). `lastZ` itself is
	-- declared up with `rectOf`, because the drag registry reads it as the
	-- paint-order tie-break for overlapping drop targets.
	-- AUTHORED PAINT ORDER, WITHIN THE PARENT'S STACKING SCOPE (ADR-0022 Decision
	-- 6, row SF-P4). Siblings are visited in `(zIndex or 0, declaration order)`
	-- order, so a lifted node — a drag ghost, a toast — paints above the siblings it
	-- was declared before, and its whole SUBTREE travels with it because the walk
	-- is depth-first over one counter. Nothing crosses a scope: a child's counter is
	-- always higher than its parent's, whatever its zIndex, which is why lifting
	-- across surfaces stays structural (the presenter's display order).
	--
	-- The declaration index is part of the key rather than trusted to `table.sort`:
	-- Luau's sort is NOT stable, so ties between two zero-index siblings would
	-- otherwise be free to swap between solves — and z-order churn is exactly the
	-- non-determinism the explicit z walk exists to remove.
	local function orderedChildren(node: any): { any }
		local children = node.children
		if children == nil or #children < 2 then
			return children or {}
		end
		local anyLift = false
		for _, child in children do
			if child.props ~= nil and type(child.props.zIndex) == "number" and child.props.zIndex ~= 0 then
				anyLift = true
				break
			end
		end
		if not anyLift then
			return children -- the overwhelmingly common case allocates nothing
		end
		local indexed: { { node: any, index: number, z: number } } = table.create(#children)
		for index, child in children do
			local z = if child.props ~= nil and type(child.props.zIndex) == "number" then child.props.zIndex else 0
			table.insert(indexed, { node = child, index = index, z = z })
		end
		table.sort(indexed, function(a, b)
			if a.z ~= b.z then
				return a.z < b.z
			end
			return a.index < b.index
		end)
		local out: { any } = table.create(#children)
		for _, entry in indexed do
			table.insert(out, entry.node)
		end
		return out
	end
	local function syncZOrder()
		if adapter.setZOrder == nil then
			return
		end
		local z = 0
		local function walkZ(node: any)
			z += 1
			if handles[node.path] ~= nil and lastZ[node.path] ~= z then
				authority.assertWrite("common", "zIndex", "layout")
				adapter.setZOrder(handles[node.path], z)
				lastZ[node.path] = z
			end
			for _, child in orderedChildren(node) do
				walkZ(child)
			end
		end
		walkZ(root.node)
	end

	-- THE TWO DRAINS. Both take the queue by value and clear it BEFORE calling
	-- anything, so a hook that mounts or dismisses something (which is the normal
	-- reason to have one) cannot make its own entry run twice or make the drain
	-- re-enter itself. The callbacks are deliberately unprotected — that is the house
	-- rule every other handler prop follows (`onPointerDown`, `onScrollWheel`), and a
	-- swallowed error in a lifetime hook is a leak nobody ever sees.
	local function drainDeparted()
		if #departedQueue == 0 then
			return
		end
		local batch = departedQueue
		departedQueue = {}
		for _, entry in batch do
			entry.fn(entry.path)
		end
	end

	local function drainAppeared()
		if #appearQueue == 0 then
			return
		end
		local batch = appearQueue
		appearQueue = {}
		for _, entry in batch do
			entry.fn(entry.path)
		end
	end

	local function structuralSync()
		structureEpoch += 1
		local _t0 = os.clock()
		ensureTree(root.node)
		local _t1 = os.clock()
		collectRetiringRoots() -- ARCH-F2: retire begin/cancel both push structure
		-- mounted identity may have changed under any path (a When branch, a ForEach
		-- row, a re-created ViewThatFits candidate), so the presentation channel's
		-- node memo is dropped wholesale rather than patched per path
		presentationNodes = {}
		local alive: { [string]: boolean } = {}
		table.clear(scrollHostOf)
		table.clear(clipHostOf)
		table.clear(pathNodes)
		pathNodeCount = 0
		local _t2 = os.clock()
		livePaths(root.node, alive, nil, nil)
		local _t3 = os.clock()
		for path, handle in handles do
			if not alive[path] then
				-- drag/drop declarations die WITH their node (ADR-0022 D5): an
				-- unregistered target that was the live hover fires exactly one
				-- `leave` and clears the verdict on its way out (finding F5), and
				-- paths are reused across a remount, so a stale binding would make
				-- a fresh node inherit a dead declaration.
				for _, suffix in { "\0drop", "\0drag", "\0det" } do
					local unbind = dragUnbind[path .. suffix]
					if unbind ~= nil then
						dragUnbind[path .. suffix] = nil
						unbind()
					end
				end
				-- PARK BEFORE REMOVE. `park` refuses anything carrying path-keyed
				-- adapter state, and a refusal falls through to the ordinary remove —
				-- so this can only ever save a create, never change what is on screen.
				local parked = false
				local key = recycleKeyOf[path]
				recycleKeyOf[path] = nil
				if recycleEnabled and key ~= nil and recyclePooled < RECYCLE_POOL_CAP then
					if not adapter.park(handle) then
						stats.parkRefused += 1
					else
						local bucket = recyclePool[key]
						if bucket == nil then
							bucket = {}
							recyclePool[key] = bucket
						end
						table.insert(bucket, handle)
						recyclePooled += 1
						parked = true
						stats.parked += 1
					end
				end
				if parked then
					-- CARRY THE PROPERTY CACHES WITH THE INSTANCE.
					--
					-- These record what the ENGINE OBJECT currently holds, so they are a
					-- property of the instance and not of the path — carrying them across
					-- a recycle is accurate, not stale. Dropping them (which is right for
					-- a real removal, where the instance is destroyed) meant every
					-- adopted node had all ~8 properties per object rewritten from
					-- scratch, and `mount` is 67% of a fling frame.
					--
					-- `solverHidden` is deliberately NOT carried: it is a verdict about
					-- the NODE, not a value on the instance, and the new identity gets
					-- its own.
					handle.parkedProps = captureParkedProps(path)
				else
					adapter.remove(handle)
				end
				handles[path] = nil
				lastRects[path] = nil
				lastScrollRegions[path] = nil
				scrollAutoscroll[path] = nil
				if autoscrollModels[path] ~= nil then
					autoscrollModels[path]:reset()
					autoscrollModels[path] = nil
				end
				lastZ[path] = nil
				lastTextSize[path] = nil
				lastTextFont[path] = nil
				lastPadding[path] = nil
				-- ...and the wrap verdict, which is a VALUE the departed instance held:
				-- a path re-created with a different string would otherwise be told
				-- nothing and keep the old node's `TextWrapped` (ruling 5)
				lastWrapped[path] = nil
				-- paths are REUSED across a structural remount (a When/ForEach child, a
				-- re-created ViewThatFits candidate), so these caches must be forgotten
				-- too. Leaving them made a fresh instance inherit the old verdict: a node
				-- re-created while still hidden got no setVisible write and painted
				-- (reopening the defect the hidden-candidate fix closed), and a re-created
				-- sub-floor control silently lost its hit expander (verifier finding V10).
				lastVisible[path] = nil
				lastHitRects[path] = nil
				solverHidden[path] = nil
				-- ...and the authored hide, for the same reason: a path re-created with
				-- no `hidden` prop would otherwise inherit the old node's verdict and
				-- never paint
				authoredHidden[path] = nil
				-- THE LIFETIME HOOK, queued rather than called. Called here it would run
				-- inside the sweep's own iteration over `handles` and inside the `mount`
				-- profiler span; both are wrong, and the first is a live-mutation hazard
				-- while the walk is still running.
				local departed = disappearHooks[path]
				if departed ~= nil then
					disappearHooks[path] = nil
					table.insert(departedQueue, { path = path, fn = departed })
				end
				-- ...and the compact-label verdict cache (found LIVE 2026-08-04:
				-- RascalRally's watch-cycle buttons painted "Previous racer" ellipsized
				-- after a pose toggle at EVERY preference). A re-created button is
				-- born with its FULL label; a surviving `true` here said the swap was
				-- already applied, so `applyTextVerdicts` never wrote the glyph again.
				-- One mount looked right — which is why the device pass that shipped
				-- the feature saw chevrons — and every remount after it did not.
				lastCompact[path] = nil
				-- a scroll host that left takes its RS-PATHCLIP subscription with it
				if pathClipObservers[path] ~= nil then
					local detach = pathClipObservers[path]
					pathClipObservers[path] = nil
					detach()
				end
				if lastTransform[path] ~= nil then
					lastTransform[path] = nil
					presentationLive -= 1
				end
				-- ...and every other per-path presentation cache: a stale composed memo
				-- would answer for a path a recycled instance adopts, and a leaked
				-- `authored` entry would make an idle surface pay forever (ADR-0026)
				lastTransparency[path] = nil
				lastComposedTransform[path] = nil
				lastComposedAlpha[path] = nil
				animationPaintDelta[path] = nil
				if authored[path] ~= nil then
					authored[path] = nil
					authoredN -= 1
				end
				-- ...and the `withAnimation` record for this path, HERE rather than by
				-- blanket-dropping every record in structuralSync: structural syncs are
				-- frequent (virtual-list windowing, `When` branches) and a blanket drop
				-- would snap unrelated in-flight animations. The write is skipped — the
				-- handle is already gone (V10's per-path clear, one line above).
				if animationRecords[path] ~= nil then
					animationClear(path, false)
				end
				stats.removes += 1
			end
		end
		local _t4 = os.clock()
		syncZOrder()
		local _t5 = os.clock()
		stats.ssPasses += 1
		stats.ssEnsureTree += (_t1 - _t0) * 1000
		stats.ssRetire += (_t2 - _t1) * 1000
		stats.ssLivePaths += (_t3 - _t2) * 1000
		stats.ssSweep += (_t4 - _t3) * 1000
		stats.ssZOrder += (_t5 - _t4) * 1000
		stats.ssTotal += (_t5 - _t0) * 1000
	end

	--[[ ENVIRONMENT GEOMETRY DRIVES RE-ARRANGEMENT — AS ONE FACT, NOT EIGHT.
		These eight keys all mean the same thing to this surface: "the space you
		were solved for is no longer the space you are in." They were once
		observed INDEPENDENTLY, each callback running a full `solveAndApply()`,
		and the multiplication was real work on a real device: L-27 recorded "one
		viewport change costs 5 solves and 2 structural syncs, reproducibly" and
		the 2026-08-13 device capture priced a solve at 8.270 ms of arrange +
		3.057 ms of measure, 58.5% of wall.

		Two facts compound to make five. An adapter learns SEVERAL of these at
		once (`roblox_env.pushViewport()` writes six on one resize), and some are
		DERIVED from others — `typographyScale` is a memo over `displaySize` and
		`preferredTextOffset`, so even a single loose write fires twice.

		One memo over all eight fixes both. The core is glitch-free, so it
		recomputes at most ONCE per flush no matter how many of its dependencies
		moved, and the fresh table is deliberate: identity-inequality means "some
		geometry fact changed", which is exactly the question this observer asks.
		Paired with the adapter batching a platform event into one transaction
		(`env:batch`), five solves become one — measured, not assumed, in
		tests/geometry_solve_coalescing.spec.

		THE MEMO CARRIES VALUES, NOT A FRESH TABLE (RED-TEAM 2026-08-13). The first
		cut returned `{}` and relied on identity-inequality, which made "recomputed"
		mean "changed" and discarded both guarantees the core states in its own
		header — set-and-revert transactions and unchanged recomputes are fire-free.
		Measured then: a viewport set-and-reverted inside one batch cost 1 solve
		instead of 0, and a `preferredTextSize` change that left `typographyScale`
		on the same clamped value cost 1 instead of 0. Wasted solves in exactly the
		dimension this entry exists to remove. So it returns the pulled values and
		compares them element-wise; eight comparisons per flush buys both properties
		back, and it stays honest if a DERIVED key is ever added to the list.

		ADDING A KEY: put it in the list and nowhere else. REMOVING one silently
		makes the surface deaf to it, which is why that spec drives every key
		individually and asserts each still costs exactly one solve. ]]
	--[[ BY CONTENT, NOT BY TABLE IDENTITY. Every one of these facts that is not a
		scalar is a FLAT RECORD — a rect (`x,y,w,h`) or a four-edge inset — and the
		adapter builds a BRAND NEW one on every `pushViewport()`. A `TopbarInset`
		change alone re-publishes a viewportRect whose numbers are identical, and
		under identity comparison that is a full re-solve of the surface for a
		viewport that did not move. Comparing the numbers costs at most eight field
		reads and removes a whole class of solve nobody asked for.

		One level deep is deliberate and sufficient: no environment geometry fact
		nests, and a deep walk would be a general-purpose comparison bolted to a
		specific eight. A nested fact is REFUSED rather than half-compared — any
		table-valued FIELD returns false, i.e. re-solves.

		That refusal is load-bearing and the reason is worth stating, because the
		comment here used to promise conservatism it did not deliver (architecture
		gate F3, 2026-08-14). Comparing a nested field by identity is only safe
		when the inner table is rebuilt with the outer one. A future fact shaped
		`{ rect = <cached>, insets = <fresh> }` — outer rebuilt, inner reused —
		would compare the inner references as EQUAL and report "unchanged", which
		is a MISSED re-solve, not an extra one: the surface goes silently deaf to
		one platform fact. Refusing the shape costs nothing today (no fact has a
		table-valued field) and makes the conservative claim literally true. ]]
	local function sameGeometryValue(a: any, b: any): boolean
		if a == b then
			return true
		end
		if type(a) ~= "table" or type(b) ~= "table" then
			return false
		end
		for k, v in a do
			-- a nested fact is refused, never half-compared (see above)
			if type(v) == "table" then
				return false
			end
			if b[k] ~= v then
				return false
			end
		end
		for k, v in b do
			if a[k] ~= v then
				return false
			end
		end
		return true
	end

	local GEOMETRY_KEYS = {
		"viewportRect",
		"coreSafeInsets",
		"deviceSafeInsets",
		"overscanInsets",
		"displaySize",
		-- geometry-affecting (matrix D.1): a preferredTextSize or displaySize
		-- change re-scales text at measure AND paint
		"typographyScale",
		"preferredTextOffset",
		-- a theme commit is geometry (ADR-0019 §2): new type sizes, spacing,
		-- control metrics and content insets all reach the solver, so the
		-- surface RE-SOLVES — it is never rebuilt, so mount identity, focus,
		-- selection, scroll and text entry survive a swap untouched
		"themeMetrics",
	}
	--[[ AN edgeToEdge SURFACE DOES NOT CONSUME A SAFE-AREA INSET (L-31).
		`solveAndApply` opens with `if rootPolicy == "edgeToEdge" then insets =
		{0,0,0,0}` — it reads `coreSafeInsets` and throws the value away, and never
		reads `deviceSafeInsets` at all. Leaving both in the dependency list made
		every scrim, backdrop and dock re-solve for an inset it is defined to
		ignore, and the shipped case is the one that hurts: a dock that PUBLISHES
		its measured height into `coreSafeInsets` re-solved for its own
		publication, every time, forever. Measured on the general two-surface
		shape: 4 arranges per geometry change, 3 with this narrowing.

		The two remaining policies both consume both keys (`coreSafeContent` uses
		coreSafeInsets; `deviceSafeContent` takes the per-edge max of both), so
		this is the only policy that can be narrowed and it is narrowed on the
		exact branch that proves it. `rootPolicy` is fixed for the controller's
		life (read once at attach), so the key list is safe to fix with it. ]]
	if rootPolicy == "edgeToEdge" then
		local narrowed = {}
		for _, key in GEOMETRY_KEYS do
			if key ~= "coreSafeInsets" and key ~= "deviceSafeInsets" then
				table.insert(narrowed, key)
			end
		end
		GEOMETRY_KEYS = narrowed
	end
	-- scope-owned like every other memo: an unowned one is a live registry node
	-- after dispose, which the registry-neutrality suites catch as a leak
	local geometryFacts = attachScope:own(core:memo(function(use)
		local values = table.create(#GEOMETRY_KEYS)
		for i, key in GEOMETRY_KEYS do
			values[i] = use(env:get(key))
		end
		return values
	end, function(a: any, b: any): boolean
		if a == nil or b == nil then
			return a == b
		end
		for i = 1, #GEOMETRY_KEYS do
			if not sameGeometryValue(a[i], b[i]) then
				return false
			end
		end
		return true
	end))
	--[[ THE RE-SOLVE IS SETTLE WORK, NOT OBSERVER WORK (L-31, 2026-08-14).
		This observer used to call `solveAndApply()` inline, which meant a surface
		committed to a layout in the MIDDLE of propagation — before the flush had
		finished deciding what the environment was. Any write made later in the
		same flush (the shipped case: a sibling surface publishing its measured
		height back into `coreSafeInsets`) then invalidated that solve, and the
		surface solved a second time. Measured headless on the general
		two-surface shape (tools/lune/_probe_settle): 4 solves and 2 reactive
		flushes per geometry change against 2 and 1 with no round trip.

		Deferring to `core:settle` costs nothing anyone can observe — the settle
		phase runs INSIDE the flush, so a top-level `env:set` still returns with
		the surface solved — and buys the whole cycle one flush instead of two.
		The flag is the idempotence the settle contract requires: the callback
		runs once per settle pass and must be a boolean read when there is
		nothing to do. ]]
	local geometryPending = false
	attachScope:own(core:observe(geometryFacts, function()
		geometryPending = true
	end))
	attachScope:own(core:settle(function()
		if not geometryPending then
			return
		end
		-- cleared even when the surface is not initialized yet, so a geometry
		-- change made before the first render cannot solve on some later flush —
		-- the inline observer dropped it, and this must drop it identically
		geometryPending = false
		if initialized then
			solveAndApply()
		end
	end))

	local controller = {}

	-- ONE mounted-node lookup for the whole controller (Step 5.5 cleanup ledger
	-- C-02). `refresh` used to declare an identical depth-first walk as a closure
	-- INSIDE its dirty loop — one allocation per changed prop per frame — while
	-- this same walk was already written once more further down for the
	-- presentation channel. Declared here because `refresh` is the first consumer
	-- and a `local function` is not an upvalue of anything above it.
	local function findNode(path: string): any
		local function walk(node: any): any
			if node.path == path then
				return node
			end
			for _, child in node.children do
				local found = walk(child)
				if found then
					return found
				end
			end
			return nil
		end
		return walk(root.node)
	end

	function controller.refresh()
		local dirty = root.takeDirty()
		local needsSolve = false
		local needsStructure = false
		-- paths whose authored `hidden` moved this frame. Collected rather than
		-- resolved inline because the LIVE value has to be read off the tree, and the
		-- tree read is worth doing once per path even when a signal fired twice.
		local hiddenTouched: { string }? = nil
		-- ...and the same collection for the authored presentation triple (ADR-0026).
		-- One list, not three: they share one stored record and one re-read.
		local presentationTouched: { string }? = nil
		for _, entry in dirty do
			if entry.prop == "hidden" and entry.path ~= nil then
				hiddenTouched = hiddenTouched or {}
				table.insert(hiddenTouched :: { string }, entry.path)
			end
			if
				entry.path ~= nil
				and (entry.prop == "opacity" or entry.prop == "scale" or entry.prop == "rotation")
			then
				presentationTouched = presentationTouched or {}
				table.insert(presentationTouched :: { string }, entry.path)
			end
			if entry.class == "structure" then
				needsStructure = true
				needsSolve = true
			elseif entry.class == "measure" or entry.class == "arrange" then
				needsSolve = true
			elseif entry.class == "navigation" or entry.class == "semantics" then
				-- ...AND THE FOCUS MAP CAN CHANGE WITHOUT THE TREE CHANGING. Read off
				-- the SCHEMA rather than off a hand-kept prop list: `focusable` declares
				-- `dirty = { "navigation" }` and `enabled` declares `semantics`, and both
				-- decide whether a node is in the order at all. Caught by the suite —
				-- "re-enabling restores focus reachability with no remount" and
				-- "navigation skips a disabled Slider's track" both went red when the
				-- epoch only counted structure and hidden roots.
				--
				-- `semantics` also carries `selected`, which the map does not read, so
				-- this over-invalidates on a selection change. That is a click, not a
				-- frame, and the alternative is a list of prop names that a future
				-- navigation prop would silently fall off.
				structureEpoch += 1
			end
			-- paint/semantics: prop-level writes below
		end
		if needsStructure then
			-- MICROPROFILER PHASE `LuauUI/mount` (roadmap Step 9): creating,
			-- reconciling and retiring Instances. Named apart from `commit` because
			-- Instance churn and property writes have completely different fixes —
			-- one is a keying/virtualization problem, the other is a diff problem.
			profile.span("mount", structuralSync)
		end
		-- OUTSIDE the mount span, and before the solve: by here the departed nodes'
		-- handles are gone, which is the guarantee `onDisappear` publishes.
		drainDeparted()
		-- ...and the authored hides, re-read from the live tree, so the merge inside
		-- the solve below sees this frame's value
		if hiddenTouched ~= nil then
			for _, path in hiddenTouched :: { string } do
				local node = findNode(path)
				authoredHidden[path] = if node ~= nil
						and node.props ~= nil
						and node.props.hidden == true
					then true
					else nil
			end
		end
		-- THE AUTHORED TRIPLE, re-read from the live tree (ADR-0026). Here — after the
		-- structural sync, before the solve — because the read must see this frame's
		-- value, and because on an ARMED commit the OLD value has to be captured
		-- before it is overwritten: that difference is what `withAnimation` flies.
		if presentationTouched ~= nil then
			local seen: { [string]: boolean } = {}
			for _, path in presentationTouched :: { string } do
				if not seen[path] then
					seen[path] = true
					local node = findNode(path)
					if node ~= nil then
						local before = authored[path]
						if readAuthoredPresentation(node) and handles[path] ~= nil then
							if animationSession ~= nil then
								local now = authored[path]
								local function was(key: string, identity: number): number
									return (before ~= nil and before[key]) or identity
								end
								local function isNow(key: string, identity: number): number
									return (now ~= nil and now[key]) or identity
								end
								animationPaintDelta[path] = {
									o = was("opacity", 1) - isNow("opacity", 1),
									s = was("scale", 1) - isNow("scale", 1),
									r = was("rotation", 0) - isNow("rotation", 0),
								}
							end
							pushPresentationPaint(path)
						end
					end
				end
			end
		end
		-- prop writes for changed nodes (paint/semantics): write ONLY the
		-- changed prop, once, even when it dirtied several classes
		if #dirty > 0 then
			-- MICROPROFILER PHASE `LuauUI/commit`: adapter property writes. Guarded
			-- on there being any dirt at all, so an idle frame pays a comparison
			-- rather than a scope — an idle frame with a scope in it is exactly the
			-- annotation overhead the plan warns about.
			profile.span("commit", function()
				local seen: { [string]: boolean } = {}
				for _, entry in dirty do
					local key = entry.path .. "\30" .. tostring(entry.prop)
					if
						(entry.class == "paint" or entry.class == "semantics")
						and entry.prop ~= nil
						and not seen[key]
					then
						seen[key] = true
						local node = findNode(entry.path)
						if node ~= nil and handles[entry.path] ~= nil then
							if BINDING_PROPS[entry.prop] then
								applyProp(handles[entry.path], node, entry.prop :: string)
							elseif STYLE_PROPS[entry.prop] then
								applyStyleProp(handles[entry.path], node, entry.prop :: string)
							end
						end
					end
				end
			end)
		end
		-- AN ARMED COMMIT ALWAYS SOLVES (ADR-0026 Decision 7): the record walk runs
		-- inside the solve, and an authored opacity dirties `paint` alone, so a pure
		-- fade would otherwise have no walk to record itself in. One armed commit per
		-- `withAnimation` call, and incremental layout skips a solve nothing dirtied.
		if animationSession ~= nil then
			needsSolve = true
		end
		if needsSolve then
			-- A STRUCTURAL change clears the dirty set: the tree's shape moved, so the
			-- last solve's rects are not a safe base to splice onto.
			-- A STRUCTURAL change gives no reuse set at all: the tree's shape moved, so
			-- last solve's rects are not a safe base for anything.
			if needsStructure then
				dirtyContains = nil
			else
				-- THE ANCESTOR CLOSURE. A node may be skipped only if NOTHING inside it
				-- is dirty, so the set handed to the solver is every dirty node plus
				-- every ancestor of one — the solver skips exactly the nodes absent
				-- from it. Paths are `/a/b/c`, so the ancestors are the prefixes.
				local contains: { [string]: boolean } = {}
				for _, entry in dirty do
					local path = entry.path
					if (entry.class == "measure" or entry.class == "arrange") and path ~= nil then
						contains[path] = true
						local at = path
						while true do
							local cut = string.match(at, "^(.*)/[^/]*$")
							if cut == nil or cut == "" or contains[cut] then
								break
							end
							contains[cut] = true
							at = cut
						end
					end
				end
				dirtyContains = contains
			end
			solveAndApply()
			-- the set belongs to THIS refresh; a re-entrant solve (text measurement, an
			-- env observer) must not reuse it, and gets a full solve instead
			dirtyContains = nil
		end
		-- LAST, after the solve, so a hook can read its own rect (see the queue's
		-- declaration). Nothing has reached the screen yet: this whole call is
		-- synchronous, and the engine renders after it returns.
		drainAppeared()
		return stats
	end

	-- focus visuals are style output (§8.4): the presenter drives this with
	-- the logical focus path; nil clears
	local focusedPath: string? = nil
	local focusRingVisible = true
	local bridgeEngaged = (opts and opts.engineSelectionBridge) == true
	-- `visible` (optional, default true) is the RING's own answer, separate from
	-- the focus path: a pointer/touch-driven focus move tracks focus, drives the
	-- selection bridge and moves the aim, and paints nothing (focus_graph's
	-- `focusVisible`; device round 1, DB-3(b)). Absent = today's behaviour, so
	-- every existing caller is unchanged.
	function controller.setFocusPath(path: string?, visible: boolean?)
		local wantRing = visible ~= false
		if path == focusedPath and wantRing == focusRingVisible then
			return
		end
		-- engine-selection bridge (NS-A12): OPT-IN mirror of logical focus to
		-- engine selection while this surface owns UI input. Measured engine
		-- constraints (spike m9): the mirrored instance must be Selectable
		-- (non-selectable targets get warned about and REASSIGNED); expect
		-- native autoscroll inside scroll hosts; offscreen selection is NOT
		-- auto-cleared. LuauUI focus identity stays authoritative — this is a
		-- render output, cleared on dispose. Feature-detected + flag-gated:
		-- passive surfaces never reach here with the flag set (NS-A11).
		if bridgeEngaged and adapter.setEngineSelection ~= nil then
			adapter.setEngineSelection(if path ~= nil then handles[path] else nil)
		end
		-- A CONTROL THAT PAINTS ITS OWN FOCUSED STATE GETS NO SECOND ONE (director
		-- playtest 2026-08-03). `focusVisual = "none"` is declared on the NODE, so
		-- the decision is made here, where the node is known — the adapter's
		-- `setFocusVisual` handle carries no props and could not see it, and a check
		-- there would have been accepted-and-ignored, which is the one thing a
		-- declared prop may never be.
		local function paintsOwnFocus(p: string?): boolean
			if p == nil then
				return false
			end
			local node = findNode(p)
			return node ~= nil and node.props ~= nil and node.props.focusVisual == "none"
		end
		if adapter.setFocusVisual ~= nil then
			-- ten-foot focus strengthening (UI-PARADIGM-003, matrix D.4): the
			-- distance profile rides the focus write so the adapter can render an
			-- unmistakable-at-3m state (scale + glow) on a Large display while a
			-- near display keeps the hairline ring. Third arg is optional —
			-- older adapters ignore it and stay byte-identical.
			local profile = env:get("distanceProfile"):get()
			if focusedPath ~= nil and handles[focusedPath] ~= nil and not paintsOwnFocus(focusedPath) then
				adapter.setFocusVisual(handles[focusedPath], false, profile)
			end
			if wantRing and path ~= nil and handles[path] ~= nil and not paintsOwnFocus(path) then
				adapter.setFocusVisual(handles[path], true, profile)
			end
		end
		focusedPath = path
		focusRingVisible = wantRing
	end

	-- verifier F2: a displaySize dock (Medium <-> Large) must re-strengthen a
	-- RESTING focus visual — text and margins already re-adopt via the solve
	-- subscription, and the focus ring must move with them without waiting for
	-- the next focus change
	attachScope:own(core:observe(env:get("distanceProfile"), function(profile)
		if
			adapter.setFocusVisual ~= nil
			and focusRingVisible
			and focusedPath ~= nil
			and handles[focusedPath] ~= nil
		then
			adapter.setFocusVisual(handles[focusedPath], true, profile)
		end
	end))

	-- verifier F3: hover is a hot-switch CARRY idiom — a pointer ARRIVING
	-- mid-session (dock adds a mouse) enables hover on nodes that already
	-- exist, not only on nodes created after the flip. enableHover is
	-- idempotent; there is no disable path (without a mouse the events
	-- simply never fire).
	do
		local hoverLive = env:get("interactionClasses"):get().pointer == true
		attachScope:own(core:observe(env:get("interactionClasses"), function(classes)
			local live = classes.pointer == true
			if live and not hoverLive and adapter.enableHover ~= nil then
				local function enableWalk(node: any)
					if HOVERABLE[node.class] and handles[node.path] ~= nil then
						adapter.enableHover(handles[node.path])
					end
					for _, child in node.children do
						enableWalk(child)
					end
				end
				enableWalk(root.node)
			end
			hoverLive = live
		end))
	end

	-- ...and the SAME carry idiom for disclosure engagement zones (architecture
	-- review F-5): long-press is the ONLY full-value path on touch, so a touch
	-- class arriving mid-session (hybrid handheld docking, first tap on a
	-- touchscreen laptop) must retrofit zones onto already-mounted disclosed
	-- labels exactly as hover does. `enableDisclosure` merges per half, so a
	-- label wired for hover at mount gains the touch half here without
	-- disturbing the first.
	do
		local discloseHoverCb = opts and (opts :: any).onDiscloseHover
		local disclosePressCb = opts and (opts :: any).onDiscloseLongPress
		if (discloseHoverCb ~= nil or disclosePressCb ~= nil) and adapter.enableDisclosure ~= nil then
			local last = env:get("interactionClasses"):get()
			local lastPointer, lastTouch = last.pointer == true, last.touch == true
			attachScope:own(core:observe(env:get("interactionClasses"), function(classes)
				local pointer, touch = classes.pointer == true, classes.touch == true
				if (pointer and not lastPointer) or (touch and not lastTouch) then
					local function wireWalk(node: any)
						if
							((node.props or {}).disclose == true or (node.props or {}).reveal ~= nil)
							and handles[node.path] ~= nil
						then
							local path = node.path
							adapter.enableDisclosure(handles[path], {
								hover = if discloseHoverCb ~= nil and pointer
									then function(over: boolean)
										discloseHoverCb(if over then path else nil)
									end
									else nil,
								longPress = if disclosePressCb ~= nil and touch
									then function(held: boolean)
										disclosePressCb(if held then path else nil)
									end
									else nil,
							})
						end
						for _, child in node.children do
							wireWalk(child)
						end
					end
					wireWalk(root.node)
				end
				lastPointer, lastTouch = pointer, touch
			end))
		end
	end

	--[[ REDUCED MOTION IS A LIVE FACT, AND IT REACHES THE TARGET FROM HERE — both
		halves of a target's motion, through one observation of one env key.

		`setNativeTransitionsEnabled` is the SHEET half (native-stylesheets NSS-A7):
		when the target runs sheet-owned paint, the adapter strips/restores the
		sheet's declared transitions on the fly (SetPropertyTransitions({}) — the
		proven instant path, spike m9).

		`setReducedMotion` is the BESPOKE half (C1, 2026-08-12), and it exists
		because the comment that used to stand here was false. It said bespoke
		targets "consult the reducedMotion policy per-play already" — they consult
		a `screen_target.new({ isReducedMotion = ... })` CLOSURE, and no production
		caller anywhere ever passed one (not the showcase, not RascalRally's four
		GUIs), so every bespoke tween ran at full motion for a player who had asked
		for less. A construction-time opt four call sites forgot is the defect; the
		repair is that the framework pushes the fact instead of hoping a consumer
		wires it. Both calls are feature-detected, so a target with neither degrades
		by name (target_contract) rather than crashing.

		Pushed once at attach and again on every change, so a mid-session flip of
		the player's setting lands without a remount. ]]
	if adapter.setNativeTransitionsEnabled ~= nil or adapter.setReducedMotion ~= nil then
		local function pushReducedMotion(reduced: boolean)
			if adapter.setNativeTransitionsEnabled ~= nil then
				adapter.setNativeTransitionsEnabled(reduced ~= true)
			end
			if adapter.setReducedMotion ~= nil then
				adapter.setReducedMotion(reduced == true)
			end
		end
		pushReducedMotion(env:get("reducedMotion"):get() == true)
		attachScope:own(core:observe(env:get("reducedMotion"), function(reduced)
			pushReducedMotion(reduced == true)
		end))
	end

	function controller.initialRender()
		structuralSync()
		solveAndApply()
		root.takeDirty() -- initial mount noise is not an update
		initialized = true
		-- the same order `refresh` uses, for the same reason: after the solve, so an
		-- `onAppear` on a first-frame node can read the rect it was just given
		drainDeparted()
		drainAppeared()
		return stats
	end

	--[[ "THIS SURFACE JUST FINISHED SOLVING" — the seam a measurer needs (L-31).
		The presenter registers exactly one listener here and uses it to feed
		solved rects to `onGeometry` and every contribution's `syncGeometry`. It
		exists because the alternative is polling `stats().solves`, which clones a
		table on every settle pass of every flush in the session.

		It fires at the tail of the OUTERMOST solve only (a text-measurement
		re-solve nests), so a listener always sees final geometry. ]]
	function controller.onSolved(fn: () -> ()): () -> ()
		table.insert(solvedListeners, fn)
		return function()
			for i, existing in solvedListeners do
				if existing == fn then
					table.remove(solvedListeners, i)
					break
				end
			end
		end
	end

	controller.rectOf = rectOf
	-- ...and the same rect in WINDOW space (ADR-0022 D5). `rectOf` answers the
	-- SOLVED rect, which inside a scroll host is canvas-space — the engine shifts
	-- it by CanvasPosition — and which a live presentation transform has moved away
	-- from on screen. Anything comparing a rect against a POINTER (drop hit-tests,
	-- autoscroll bands) must use this one, or it targets the wrong row the moment
	-- the list is scrolled or the surface is shifted (PLAT-4).
	controller.screenRectOf = screenRectOf

	-- keep-visible presentation transform (§17 Phase 5 keyboard occlusion): the
	-- presenter drives a transient upward offset on the SCREEN ROOT so an edited
	-- field stays above the on-screen keyboard. Presentation authority (never
	-- layout): it shifts what is painted without re-solving. dy=0 restores.
	local lastOffsetY: number? = nil
	-- programmatic scroll (native-substrate NS-A2): the framework's ONLY scroll
	-- write — keep-visible and scroll-to-row compute a target and set it here;
	-- the engine owns everything between offsets. Degrades to a no-op on a
	-- scroll-less adapter (fallback path stays clip-only).
	function controller.scrollTo(path: string, pos: { x: number, y: number })
		local handle = handles[path]
		if handle ~= nil and adapter.setScrollPosition ~= nil then
			adapter.setScrollPosition(handle, pos)
		end
	end

	-- hidden-subtree roots from the last solve (A-AL1). The presenter consults
	-- this when rebuilding focus order; an empty table means nothing is hidden.
	-- see `structureEpoch` above: the value a caller can cache a tree derivation on.
	function controller.structureEpoch(): number
		return structureEpoch
	end

	function controller.hiddenRoots(): { [string]: boolean }
		-- A COPY, like `stats()` (F-30). The live set is the renderer's own state
		-- for the frame; a caller that mutated it corrupted the visibility walk,
		-- and a caller that cached it held a table the next solve replaced. One
		-- shallow clone of a small map, on a diagnostic read.
		return table.clone(hiddenRoots)
	end

	-- native drag acquisition (B-VAL2; corrections §1): attach a UIDragDetector to
	-- a MOUNTED node by path. The engine owns acquisition and cross-input motion;
	-- the framework converts positions into its own value model. Returns a detach
	-- function, or nil when the adapter or engine has no detector — callers MUST
	-- have a fallback, which is why the return value is nilable rather than an
	-- error.
	function controller.attachDragDetector(path: string, handlers: any): (() -> ())?
		return attachDetector(path, handlers)
	end

	-- THE SURFACE'S DRAG REGISTRY (ADR-0022 Decision 5). Every mounted
	-- `UI.draggable` / `UI.dropTarget` on this surface lives here, and so does
	-- the one session all four input classes drive. Consumers reach it for the
	-- non-pointer verbs (`arm`/`armTo`/`commit`/`cancel`), the predicted
	-- `verdict` Readable, and `refreshTargets()` — which an autoscrolling host
	-- calls in the SAME frame as its scroll write so the row-under-pointer
	-- verdict never trails the scroll.
	function controller.dragRegistry(): any
		return dragRegistry()
	end

	-- Non-creating read of the registry. The presenter broadcasts "a surface just
	-- presented" (finding F7) to every LIVE surface; using `dragRegistry()` for
	-- that would lazily build a registry on every surface that never declared a
	-- draggable, purely to tell it about a modal it cannot care about.
	function controller.peekDragRegistry(): any
		return dragRegistryInstance
	end

	-- INTEGRATION SEAM for the presentation layer: the semantic feedback bus,
	-- the drag-proxy layer, the motion clock and an injected `now`. Each is
	-- optional and each degrades exactly one behaviour — a registry with none of
	-- them still resolves every verdict identically, which is how the headless
	-- suite drives it. Callable at any time (before or after the first
	-- declaration mounts): the presentation layer is built around a PRESENTED
	-- surface, so a seam that could only be set before mount would force every
	-- host to guess the order.
	function controller.setDragCollaborators(collaborators: { [string]: any })
		for key, value in collaborators do
			dragCollaborators[key] = value
		end
		if dragRegistryInstance ~= nil then
			dragRegistryInstance.setCollaborators(collaborators)
		end
	end

	-- read the live offset (A-SV1: the public construct needs a READABLE as well
	-- as a settable offset). The engine co-authors this value, so it is read
	-- from the adapter rather than cached as a framework-owned property.
	function controller.scrollPosition(path: string): { x: number, y: number }?
		local handle = handles[path]
		if handle ~= nil and adapter.getScrollPosition ~= nil then
			return adapter.getScrollPosition(handle)
		end
		return nil
	end

	-- scroll-to-visible (A-SV1): THE shared keep-visible substrate. Every
	-- control that must bring a focused, selected, or newly-revealed descendant
	-- into view asks for it here instead of carrying its own scroll arithmetic,
	-- so the minimum-distance rule, the clamp, and the axis handling exist once.
	-- Returns true when it actually moved the host.

	function controller.scrollToVisible(path: string): boolean
		if adapter.setScrollPosition == nil then
			return false -- clip-only fallback adapter: nothing to scroll
		end
		-- the nearest ScrollView ANCESTOR (never `path` itself). `structuralSync`'s
		-- `livePaths` walk already threads that host down the tree and records it
		-- here — its own comment says it exists so this is not "computed on demand
		-- instead", which is exactly what a second full-tree walk here was doing
		-- (Step 5.5 cleanup ledger C-03). Absent from the map means not yet
		-- structurally synced, and such a path has no `lastRects` entry either, so
		-- both spellings refuse it.
		local hostPath: string? = scrollHostOf[path]
		if hostPath == nil then
			return false
		end
		local hostRect = lastRects[hostPath]
		local targetRect = lastRects[path]
		local region = lastScrollRegions[hostPath]
		if hostRect == nil or targetRect == nil or region == nil then
			return false
		end
		local isX = region.axis == "x"
		local current = controller.scrollPosition(hostPath) or { x = 0, y = 0 }
		local offset = if isX then current.x else current.y
		local band = if isX then hostRect.w else hostRect.h
		local extent = if isX then region.contentW else region.contentH
		-- canvas-space span of the target (the solver arranges children in the
		-- host's own coordinate space; the engine shifts them by the offset)
		local top = (if isX then targetRect.x else targetRect.y) - (if isX then hostRect.x else hostRect.y)
		local size = if isX then targetRect.w else targetRect.h
		-- ONE implementation of the minimum-distance rule (A-SV2)
		local wanted = solver.keepVisibleOffset(top, size, offset, band, extent)
		if wanted == nil then
			return false
		end
		controller.scrollTo(hostPath, {
			x = if isX then wanted else current.x,
			y = if isX then current.y else wanted,
		})
		return true
	end

	--[[ HAND A PRESS TO WHAT IS UNDERNEATH IT (ruling 6, director 2026-08-13).

		THE ENGINE FACT THIS EXISTS FOR, measured live in Studio 2026-08-13 and
		written up in `docs/lessons/a-button-eats-the-swipe-underneath-it.md`: Roblox
		delivers `InputBegan` to the TOPMOST interactive object only. A `GuiButton`
		sinks it and an Active `Frame` behind it receives NOTHING. So a hit surface
		painted BEHIND a row's content — which is how `row_actions` and `table`'s own
		`rowBlueprint` were both built, on a comment claiming the opposite — is dead
		wherever a Button covers it, and the row cannot be swiped there.

		The ruled repair (option A) puts the gesture surface ON TOP, where it always
		receives the press, and makes it FORWARD a press it decides was not its own.
		Forwarding cannot go back through the engine — the press has already been
		delivered and sunk — so it comes here instead, to the one place that holds
		the live tree, the solved rects and the tap dispatch the engine's own
		`Activated` would have reached.

		WHAT IT PICKS. The LAST node in document order (which is paint order, so the
		last match is the topmost) that (i) sits under `within` and is not under
		`skip`, (ii) is something the engine would have delivered the press to at
		all, (iii) is not hidden or disabled, (iv) contains the point in WINDOW
		space, and (v) is not scrolled out of its own clip host.

		"SOMETHING THE ENGINE WOULD HAVE DELIVERED TO" IS TWO FAMILIES, NOT ONE, and
		getting that wrong would have traded one dead control for another. A `Button`
		/`Toggle`/`TextField` is activated through `setActivateHandler`, so a
		forwarded press has to run that dispatch. But a `Rating`, a `Slider` and every
		other control built on a POINTER ZONE (`onPointerDown`/`onPointerUp` props,
		ADR-0008) is not `TAPPABLE` at all — it hears the raw press. Before this
		ruling those worked and the swipe did not, because they were painted on top;
		forwarding only the tappable family would have inverted exactly that, on the
		same surfaces. So a pointer zone gets its down/up pair replayed at the point,
		in order, with the same `screenRectOf` a native press is handed.

		The `skip` prefix exists because the forwarding surface is ITSELF a pointer
		zone and lives inside `within` — without it, the Grip would forward every
		press straight back to itself.

		The tappable path runs the SAME body `setActivateHandler` runs — the hidden
		gate, the per-press dedupe, the drag-arm check, `opts.onNodeTap` — because a
		forwarded tap must be indistinguishable from a native one. Returns the path it
		dispatched to, or nil when nothing was under the point. ]]
	local function isPointerZone(node: any): boolean
		local props = node.props
		return props ~= nil and (props.onPointerDown ~= nil or props.onPointerUp ~= nil)
	end
	function controller.tapAt(x: number, y: number, sel: any?): string?
		local within: string? = if type(sel) == "table" then sel.within else nil
		local skip: string? = if type(sel) == "table" then sel.skip else nil
		local found: any = nil
		local function walk(node: any)
			local path = node.path
			if skip ~= nil and (path == skip or string.sub(path, 1, #skip + 1) == skip .. "/") then
				return -- the forwarding surface's own subtree is never a target
			end
			local tappable = TAPPABLE[node.class]
			if
				(tappable or isPointerZone(node))
				and solverHidden[path] ~= true
				and (node.props == nil or node.props.enabled ~= false)
			then
				local rect = screenRectOf(path)
				if
					rect ~= nil
					and x >= rect.x
					and x <= rect.x + rect.w
					and y >= rect.y
					and y <= rect.y + rect.h
					and not pathEscapesClip(path, screenRectOf)
				then
					found = node -- last match wins: document order IS paint order
				end
			end
			for _, child in node.children do
				walk(child)
			end
		end
		local from = if within ~= nil then findNode(within) else root.node
		if from == nil then
			return nil
		end
		walk(from)
		if found == nil then
			return nil
		end
		local node = found :: any
		local target = node.path :: string
		if not TAPPABLE[node.class] then
			-- a POINTER ZONE: replay the press it never received, in order
			local pos = { x = x, y = y, pointerType = "touch", forwarded = true }
			if node.props.onPointerDown ~= nil then
				node.props.onPointerDown(target, pos, screenRectOf)
			end
			if node.props.onPointerUp ~= nil then
				node.props.onPointerUp(target, pos, screenRectOf)
			end
			return target
		end
		local onNodeTap = opts and opts.onNodeTap
		if onNodeTap == nil then
			return nil
		end
		if not dispatchNodeTapOnce(target) then
			return nil
		end
		if tapArmsInstead(target, { via = "forwardedTap" }) then
			return target
		end
		onNodeTap(target, { via = "forwardedTap" })
		return target
	end

	-- THE SCROLL HOST THAT CARRIES A NODE, with everything an edge autoscroll
	-- needs to steer it, in ONE answer (Table's reorder autoscroll, 2026-07-29).
	--
	-- A control cannot work this out for itself. The host may be its own scroller
	-- (a viewport Table's Body) or an ANCESTOR it does not own — a block Table
	-- inside a scrolling page is the shipped shape, and there the thing that has
	-- to move belongs to the consumer's screen, not to the control. The nearest
	-- ScrollView ancestor is already threaded down `structuralSync`'s live-path
	-- walk for `screenRectOf`, and the canvas extent is already recorded per host
	-- for the region push, so this exposes the pair rather than tempting three
	-- separate internals out through the API (the same argument `scrollToVisible`
	-- makes for the keep-visible arithmetic).
	--
	-- `rect` is in WINDOW space, because the caller compares it against a POINTER.
	-- Pass `includeSelf` for a node that may BE the host.
	function controller.scrollHostFor(path: string, includeSelf: boolean?): any
		local hostPath: string? = if includeSelf == true and lastScrollRegions[path] ~= nil
			then path
			else scrollHostOf[path]
		if hostPath == nil then
			return nil
		end
		local region = lastScrollRegions[hostPath]
		local rect = screenRectOf(hostPath)
		if region == nil or rect == nil then
			return nil
		end
		local isX = region.axis == "x"
		local offset = controller.scrollPosition(hostPath) or { x = 0, y = 0 }
		local band = if isX then rect.w else rect.h
		local extent = if isX then region.contentW else region.contentH
		return {
			path = hostPath,
			rect = rect,
			axis = if isX then "x" else "y",
			offset = if isX then offset.x else offset.y,
			-- clamped the way the engine clamps CanvasPosition: nothing to scroll
			-- reports 0, which is what makes an autoscroll model INERT rather than
			-- arming against a canvas that cannot move
			maxScroll = math.max(0, extent - band),
		}
	end

	-- ===== drag-to-edge autoscroll (device report 2026-07-29) ==============
	-- "I moved my finger to the bottom of the scroll view and held it, and it
	-- didn't auto-scroll."
	--
	-- THE POLICY LIVES ON THE SCROLLER (director ruling, same day). A drag says
	-- only WHERE the pointer is; every ScrollView decides for itself whether that
	-- point is at an edge it can still move along. That is what makes it work for
	-- a Table, an HStack of cards, or a mix, with no per-control copy — and it is
	-- the only arrangement that can answer the NESTED case, because "which
	-- scroller should move" is a question about the chain of scrollers under the
	-- point, not about the thing being dragged.
	--
	-- THE CHAIN RULE, innermost outward: take the ScrollViews whose PAINTED rect
	-- contains the drag point, nearest first. The first one that (a) has the point
	-- inside one of its own edge bands and (b) can still travel that way wins.
	-- A host already pinned at that end is transparent — the gesture falls
	-- through to its parent, which is what lets a short inner list hand a drag off
	-- to the page once its own tail is reached. Every host that is not the winner
	-- is reset, so a chain can never have two models armed at once.
	local pointerDrag: any = nil
	local autoscrollClock = 0

	-- a live pointer drag, published by whoever owns it (Table's reorder, the
	-- public drag registry). `nil` retracts it. `refresh` is called after a scroll
	-- lands so the owner can re-resolve its verdict in the SAME frame.
	function controller.setPointerDrag(info: any)
		if info == nil then
			pointerDrag = nil
			for _, model in autoscrollModels do
				model:reset()
			end
			return
		end
		pointerDrag = info
	end

	-- the ScrollView chain under a point, innermost first
	local function scrollChainAt(x: number, y: number): { string }
		local chain: { string } = {}
		for path, region in lastScrollRegions do
			if region ~= nil and handles[path] ~= nil then
				local rect = screenRectOf(path)
				if rect ~= nil and x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h then
					table.insert(chain, path)
				end
			end
		end
		-- deepest path first: a descendant's path is strictly longer than its
		-- ancestor's (paths are "/a/b/c"), so length orders the chain without a
		-- second tree walk. Ties are unrelated subtrees, which cannot both contain
		-- the point unless they overlap; `sort` is stable enough for that case
		-- because either answer is equally correct.
		table.sort(chain, function(a, b)
			return #a > #b
		end)
		return chain
	end

	-- `autoscroll` prop -> model options, or nil when this host opts out
	local function autoscrollOptsFor(path: string): any
		local declared = scrollAutoscroll[path]
		if declared == false then
			return nil
		end
		return if type(declared) == "table" then declared else {}
	end

	-- one autoscroll frame for the whole surface. Returns the host it moved (nil
	-- when nothing did) so a caller can assert on it.
	function controller.stepAutoscroll(dt: number?): any
		autoscrollClock += math.max(dt or 0, 0)
		local drag = pointerDrag
		if drag == nil or type(drag.pos) ~= "table" or adapter.setScrollPosition == nil then
			for _, model in autoscrollModels do
				model:reset()
			end
			return nil
		end
		local chain = scrollChainAt(drag.pos.x, drag.pos.y)
		local winner: string? = nil
		local winnerStep: any = nil
		for _, path in chain do
			if winner ~= nil then
				break
			end
			local opts = autoscrollOptsFor(path)
			local region = lastScrollRegions[path]
			local rect = screenRectOf(path)
			if opts ~= nil and region ~= nil and rect ~= nil then
				local isX = region.axis == "x"
				local band = if isX then rect.w else rect.h
				local extent = if isX then region.contentW else region.contentH
				local maxScroll = math.max(0, extent - band)
				local current = controller.scrollPosition(path) or { x = 0, y = 0 }
				local offset = if isX then current.x else current.y
				local model = autoscrollModels[path]
				if model == nil then
					-- the band follows the HOST's shape, not the screen's: a short
					-- wide inner list and the tall page around it do not want the
					-- same reach (autoscroll.bandForViewport owns that choice).
					local resolved = table.clone(opts)
					if resolved.bandH == nil then
						resolved.bandH = autoscrollLib.bandForViewport(rect.w, rect.h)
					end
					model = autoscrollLib.new(resolved)
					autoscrollModels[path] = model
				end
				-- the model is written for the scroll axis as a 1-D problem, so an
				-- x-axis host is fed its own axis's numbers
				local step = model:step({
					now = autoscrollClock,
					pointerPos = if isX then { x = drag.pos.y, y = drag.pos.x } else drag.pos,
					hostRect = if isX then { x = rect.y, y = rect.x, w = rect.h, h = rect.w } else rect,
					canvasPos = offset,
					maxScroll = maxScroll,
				})
				-- CAN THIS HOST STILL TRAVEL THE WAY THE POINTER IS ASKING? The model
				-- deliberately stays ARMED at the end of its canvas (its rule 5, so
				-- pulling back and pushing in again does not re-pay the dwell) — but
				-- for a CHAIN that would mean a list pinned at its tail silently
				-- swallowing the gesture forever. A host that cannot move in the
				-- direction of the band it owns is transparent: it disarms and the
				-- drag falls through to its parent, which is what lets a short inner
				-- list hand off to the page (director, 2026-07-29).
				local bandName = model:band()
				local canTravel = if bandName == "top" or bandName == "left"
					then offset > 0
					elseif bandName == "bottom" or bandName == "right" then offset < maxScroll
					else false
				if step.state ~= "idle" and canTravel then
					winner = path
					winnerStep = step
					if step.delta ~= 0 then
						controller.scrollTo(path, {
							x = if isX then offset + step.delta else current.x,
							y = if isX then current.y else offset + step.delta,
						})
						if type(drag.refresh) == "function" then
							drag.refresh()
						end
					end
				else
					model:reset()
				end
			end
		end
		-- every host that did not win is disarmed, so no second model keeps a
		-- dwell timer running behind the one the player is actually steering
		for path, model in autoscrollModels do
			if path ~= winner then
				model:reset()
			end
		end
		if winner == nil then
			return nil
		end
		return { path = winner, state = winnerStep.state, delta = winnerStep.delta }
	end

	-- engine-driven scroll observation (windowing consumes this in Phase 3):
	-- returns an unsubscribe; a scroll-less adapter returns a no-op unsubscribe
	function controller.observeScroll(path: string, fn: (pos: { x: number, y: number }) -> ()): () -> ()
		local handle = handles[path]
		if handle ~= nil and adapter.observeScroll ~= nil then
			return adapter.observeScroll(handle, fn)
		end
		return function() end
	end

	-- ===== THE PER-NODE PRESENTATION CHANNEL (ADR-0022 Decision 2) ==========
	--
	-- The authority manifest has declared `transform` and `transparency` as
	-- PRESENTATION properties since §7.3; until now the only writer was the
	-- keep-visible offset below, and it wrote them at the ROOT only. These two
	-- methods are the whole motion write surface: a transform never touches solver
	-- geometry (no Size, no re-solve, no layout-affecting animation) and never
	-- writes a native-sheet-owned property, which is what lets a 60 Hz motion run
	-- beside sheet paint without contesting it.
	--
	-- `nil` clears. Values are compared before writing, so a settled motion that
	-- keeps re-asserting its rest value costs nothing (minimal-write contract).
	local transformsEqual = presentation.transformsEqual

	-- the mounted node behind a path, memoized. A motion writes EVERY FRAME while it
	-- runs and each write needs the node's class (for the authority assertion), so
	-- walking the tree per write would put a tree walk on the frame budget. Mounted
	-- identity is stable except across a structural sync, which is where the cache is
	-- dropped (`presentationNodes = {}` in structuralSync).
	local function nodeAt(path: string): any
		local hit = presentationNodes[path]
		if hit ~= nil then
			return hit
		end
		local node = findNode(path)
		presentationNodes[path] = node
		return node
	end

	-- ===== THE ONE PRESENTATION WRITE SITE (ADR-0026 Decision 3) ==============
	-- Every contributor routes through here and NOTHING else in this file calls
	-- `adapter.setProp` for `transform` or `transparency` — which is what makes
	-- "one authority per engine property" a fact in the code rather than a claim in
	-- a comment (`tests/authored_presentation.spec.luau` counts the sites in the
	-- source). The arithmetic and its reasoning live in `render/presentation.luau`;
	-- what is here is the STATE and the write.
	--
	-- The memo is on the COMPOSED value, never on a contributor's: it was correct
	-- on the channel value while there was one contributor and would go stale the
	-- instant there were two.
	function pushPresentationPaint(path: string)
		local handle = handles[path]
		if handle == nil then
			return
		end
		local t = lastTransform[path]
		-- THE OFF-PATH GATE (Decision 9). Nothing on this surface authored one of the
		-- three, so there is nothing to compose and `composeTransform` returns the
		-- channel value by identity.
		local o, s, r = nil, nil, nil
		if authoredN > 0 then
			local rec = animationRecords[path]
			o, s, r = presentation.effective(authored[path], rec, if rec ~= nil then rec.set.spring:get() else 0)
		end
		local node: any = nil

		local composed = presentation.composeTransform(t, s, r)
		if not transformsEqual(lastComposedTransform[path], composed) then
			node = nodeAt(path)
			if node ~= nil then
				lastComposedTransform[path] = composed
				authority.assertWrite(node.class, "transform", "presentation")
				adapter.setProp(handle, "transform", composed, "presentation")
			end
		end

		local alpha = presentation.composeAlpha(lastTransparency[path], o)
		if lastComposedAlpha[path] ~= alpha then
			if node == nil then
				node = nodeAt(path)
			end
			if node ~= nil then
				lastComposedAlpha[path] = alpha
				authority.assertWrite(node.class, "transparency", "presentation")
				adapter.setProp(handle, "transparency", alpha, "presentation")
			end
		end
	end

	--[[ A FADE IS A FADE-GROUP FACT, and the node must have said so — either
		`canvasGroup = true`, or an authored `opacity`, which IS that declaration
		(ADR-0026 Decision 4). The alternative — writing BackgroundTransparency /
		TextTransparency per node — is exactly the write that permanently defeats a
		native sheet rule (spike m10), and it fades one node's own paint rather than
		the group the caller means. So the refusal is loud and names the fix instead
		of fading something nobody asked for. ]]
	local function isFadeGroup(node: any): boolean
		return node.props ~= nil and (node.props.canvasGroup == true or node.props.opacity ~= nil)
	end

	-- `w`/`h` are a PAINTED SIZE DELTA in pixels, added to the solved rect at the
	-- adapter's one Size write (withAnimation size, 2026-08-14). Unlike `x`/`y`
	-- they do NOT accumulate down the subtree: every rect is absolute, so a
	-- container's painted growth carries nothing inside it and must not.
	function controller.setPresentationTransform(
		path: string,
		t: {
			x: number,
			y: number,
			w: number?,
			h: number?,
			scale: number?,
			rotation: number?,
		}?
	)
		local handle = handles[path]
		if handle == nil then
			return
		end
		if transformsEqual(lastTransform[path], t) then
			return
		end
		local node = nodeAt(path)
		if node == nil then
			return
		end
		if (lastTransform[path] == nil) ~= (t == nil) then
			presentationLive += if t ~= nil then 1 else -1
		end
		lastTransform[path] = t
		pushPresentationPaint(path)
	end

	function controller.setPresentationTransparency(path: string, alpha: number?)
		local handle = handles[path]
		if handle == nil then
			return
		end
		local node = nodeAt(path)
		if node == nil then
			return
		end
		if not isFadeGroup(node) then
			error(
				`LuauUI presentation: {path} cannot be faded — presentation transparency needs a fade GROUP. `
					.. "Wrap the subtree in UI.Box{ canvasGroup = true } (or declare an authored `opacity`, "
					.. "which implies one) and fade that: GroupTransparency is one engine property no style "
					.. "rule owns, while per-node transparency would contest native-sheet paint and fade only "
					.. "that node's own glyphs or fill.",
				0
			)
		end
		if lastTransparency[path] == alpha then
			return
		end
		lastTransparency[path] = alpha
		pushPresentationPaint(path)
	end

	-- THE AUTHORED TRIPLE, re-read off the LIVE tree (ADR-0026). The reading and
	-- its domain checks are `presentation.readAuthored`; what is here is the
	-- bookkeeping — the map, and `authoredN`, which is the off-path gate above.
	-- Returns true when the stored triple moved, so a caller can skip a write.
	function readAuthoredPresentation(node: any): boolean
		local path = node.path
		local next = presentation.readAuthored(node.props, node.class, path)
		local prev = authored[path]
		if presentation.sameAuthored(prev, next) then
			return false
		end
		if (prev == nil) ~= (next == nil) then
			authoredN += if next ~= nil then 1 else -1
		end
		authored[path] = next
		return true
	end

	-- ===== `withAnimation`: arming, roots, and the one progress spring ========
	-- The verb is `presenter.withAnimation` (design §"Where it lives"); this is the
	-- half that has to be controller-scoped, because a record is per-path state
	-- that dies with its path.

	function animationClear(path: string, write: boolean)
		local rec = animationRecords[path]
		if rec == nil then
			return
		end
		animationRecords[path] = nil
		animationRecordN -= 1
		rec.set.paths[path] = nil
		if write then
			-- No paint-half recompose here, deliberately, and it was checked rather
			-- than assumed: the spring SNAPS to its target before `onSettle` runs
			-- (motion/motion.luau `sp:snap(sp:getTarget())`, and the clock's commit
			-- phase precedes its post phase), so `animationWrite` has already painted
			-- the record at p = 0 — which is the authored destination exactly. A push
			-- here reddened nothing when deliberately removed, and a line no check can
			-- fail is decoration.
			controller.setPresentationTransform(path, nil)
		end
	end

	-- ONE progress spring drives a whole call: 1 = at the old place, 0 = at the
	-- solved place, so every record's absolute offset is `(its delta) x p` for a
	-- single `p` — a uniform interpolation that provably cannot TEAR a subtree.
	-- `transitions.luau`'s ratified shape (its header, "one spring per transition").
	local function animationWrite(set: any)
		local p = set.spring:get()
		for path in set.paths do
			local rec = animationRecords[path]
			if rec ~= nil and rec.set == set then
				-- one `p` for position AND size, which is what makes a panel's growth
				-- and the displacement of everything below it arrive on the same frame
				-- ...and, since ADR-0026, for opacity/scale/rotation too, which is what
				-- makes a card that slides, grows and fades land on ONE frame.
				if rec.moves then
					controller.setPresentationTransform(
						path,
						{ x = rec.x * p, y = rec.y * p, w = rec.w * p, h = rec.h * p }
					)
				end
				if rec.paints then
					pushPresentationPaint(path)
				end
			end
		end
	end

	local function animationSettle(set: any)
		if set.done then
			return
		end
		set.done = true
		-- ONLY the paths it STILL owns: a later call may have re-based some of them
		-- onto its own spring, and clearing those would snap a live animation
		local owned: { string } = {}
		for path in set.paths do
			table.insert(owned, path)
		end
		for _, path in owned do
			animationClear(path, true)
		end
		if set.unobserve ~= nil then
			set.unobserve()
			set.unobserve = nil
		end
		set.spring:dispose()
		local at = table.find(animationSets, set)
		if at ~= nil then
			table.remove(animationSets, at)
		end
	end

	function installAnimationRecords(rects: any)
		local session = animationSession
		local baseline = animationBaseline
		if session == nil or baseline == nil then
			return
		end
		local set: any = nil
		-- the INTERRUPTION carry (design §Interruption). One spring serves the whole
		-- call, so the velocity that survives is the DOMINANT record's: painted speed
		-- is `rel * dp/dt`, so holding `relOld_max * vOld == relNew_max * vNew` keeps
		-- the biggest motion's speed continuous and puts a small kink on the rest.
		local carryMagOld, carryVelocity, carryMagNew = 0, 0, 0
		-- `relX`/`relY` are RELATIVE to the ancestors' composed delta (the offset half
		-- accumulates); `dw`/`dh` are the node's OWN absolute size delta, because the
		-- size half does not accumulate. See the walk below.
		-- `dOp`/`dSc`/`dRo` are the AUTHORED presentation deltas (ADR-0026 Decision 7):
		-- `old - new`, painted as `destination + delta x p` on the SAME spring as the
		-- four rect numbers. Per-node like the size half, never accumulated: a fade
		-- group's children are really inside its buffer and would fade twice.
		local function claim(
			path: string,
			relX: number,
			relY: number,
			dw: number,
			dh: number,
			dOp: number,
			dSc: number,
			dRo: number
		)
			if set == nil then
				set = { spring = session.newSpring(), paths = {}, done = false }
				-- the write rides the VALUE, not the clock step, exactly as a
				-- transition's does, so an instantly-placed value lands the same way
				set.unobserve = core:observe(set.spring, function()
					animationWrite(set)
				end)
				set.spring:onSettle(function()
					animationSettle(set)
				end)
				table.insert(animationSets, set)
			end
			local prev = animationRecords[path]
			if prev ~= nil then
				-- INTERRUPTION (design §Interruption): carry the offset this path is
				-- painted at right now into the new record, so a path claimed by two
				-- calls re-targets instead of jumping, and hand it to the new spring
				local p = prev.set.spring:get()
				-- all four components are PIXELS on the same progress spring, so the
				-- dominant magnitude is the largest of the four, not the largest offset
				local mag = math.max(math.abs(prev.x), math.abs(prev.y), math.abs(prev.w), math.abs(prev.h))
				if mag > carryMagOld then
					carryMagOld = mag
					carryVelocity = prev.set.spring:getVelocity()
				end
				relX += prev.x * p
				relY += prev.y * p
				-- the size half re-bases on exactly the same rule: carry the delta this
				-- path is PAINTED at right now, so a panel interrupted half-grown
				-- continues from the height on screen instead of snapping to its start
				dw += prev.w * p
				dh += prev.h * p
				-- ...and the paint half re-bases identically: a panel interrupted
				-- half-faded continues from the alpha on screen. The CARRY MAGNITUDE
				-- above stays on the four PIXEL numbers on purpose — a `math.max` over
				-- a ratio, a factor, an angle and pixels is a number with no meaning —
				-- so a pure-paint record re-targets from rest, which is the same small
				-- kink the dominant-record rule already accepts.
				dOp += prev.o * p
				dSc += prev.s * p
				dRo += prev.r * p
				animationClear(path, false)
			end
			carryMagNew = math.max(carryMagNew, math.abs(relX), math.abs(relY), math.abs(dw), math.abs(dh))
			local moves = relX ~= 0 or relY ~= 0 or dw ~= 0 or dh ~= 0
			local paints = dOp ~= 0 or dSc ~= 0 or dRo ~= 0
			animationRecords[path] = {
				x = relX,
				y = relY,
				w = dw,
				h = dh,
				o = dOp,
				s = dSc,
				r = dRo,
				moves = moves,
				paints = paints,
				set = set,
			}
			animationRecordN += 1
			set.paths[path] = true
			-- SEED SYNCHRONOUSLY, before the first step (transitions.luau's seed at
			-- `writeEntry(entry)` before `setTarget`): `tick` runs on PreRender and
			-- `refresh` on Heartbeat, so a record written a frame late paints one frame
			-- at the destination and then jumps back.
			--
			-- A PURE-PAINT RECORD WRITES NO TRANSFORM AT ALL: a zero transform is not
			-- free (it counts into `presentationLive` and makes the adapter recompose
			-- the subtree's offsets) and a fade has no offset to declare.
			controller.setPresentationTransform(path, if moves then { x = relX, y = relY, w = dw, h = dh } else nil)
			if paints then
				pushPresentationPaint(path)
			end
		end
		-- TOP-DOWN, because a node cannot be classified before its ancestors.
		-- `inh` is the composed ABSOLUTE delta this path inherits from the records
		-- installed above it — never an ancestor's stored RELATIVE, and never a live
		-- record from an EARLIER call (which is not this diff's business).
		local function walk(node: any, inhX: number, inhY: number)
			local path = node.path
			-- PRECEDENCE (design §Composition), SCOPED TO THE NODE — RED-TEAM
			-- Milestone 1, blocker 1 (tests/animation_precedence.spec.luau).
			--
			-- There is one `lastTransform` slot per path and no contributor stack,
			-- so a path another writer already owns — a structural transition,
			-- keep-visible — must stay out of this diff: two writers alternating on
			-- one slot is the contention this rule exists to prevent.
			--
			-- THAT IS A STATEMENT ABOUT THE SLOT, AND A SLOT BELONGS TO ONE PATH.
			-- Taking the owned path's whole SUBTREE out of the diff protects
			-- nothing (a child has its own slot, uncontended) and costs everything
			-- when the owned path is the ROOT: every `UI.TextInput` declares a
			-- `keepVisibleOffset`, and `presenter.present` wires it eagerly, so
			-- `setPresentationOffset(0)` writes a zero transform onto the root at
			-- boot on any surface holding a text field. `withAnimation` on that
			-- surface then installed zero records and snapped, with no error and no
			-- diagnostic.
			--
			-- So the owned node is EXCLUDED and the walk CONTINUES with `inh`
			-- UNCHANGED. `inh` is the composed delta of records installed in THIS
			-- diff, and a foreign writer's shift is not one of them: both halves of
			-- the presentation channel accumulate every ancestor's transform
			-- independently (`presentationShift`, the adapter's compose), so the
			-- keep-visible shift is already added on top of whatever a descendant's
			-- own record paints. Passing it through unchanged is what makes the
			-- painted sum come out right; folding it into `inh` would subtract it
			-- from the descendant twice.
			local owned = lastTransform[path] ~= nil and animationRecords[path] == nil
			if not owned then
				local dx, dy, dw, dh = 0, 0, 0, 0
				-- LIVENESS IS NOT `lastRects[path] ~= nil`: `restoreParkedProps` carries
				-- `lastRects` across paths for a recycled instance, so a brand-new row
				-- would fly in from the position of whatever dead row it adopted.
				local live = baseline[path] == true
				if live then
					local last = lastRects[path]
					local entry = rects[path]
					if last ~= nil and entry ~= nil then
						dx = last.x - entry.rect.x
						dy = last.y - entry.rect.y
						-- THE SIZE DELTA IS ABSOLUTE, not relative, and that asymmetry is
						-- the whole design (docs/plans/with-animation-size.md). A position
						-- offset accumulates down the subtree because the instance tree is
						-- FLAT — a container's move carries nothing inside it, so every
						-- descendant re-adds its ancestors' offsets. A size change carries
						-- nothing inside it EITHER, and there the same fact means the
						-- opposite: a child's rect is absolute, so the parent's painted
						-- growth must not reach it. Hence no `inh` for w/h, and no
						-- compensating record for a child that did not resize.
						dw = last.w - entry.rect.w
						dh = last.h - entry.rect.h
					end
				end
				local relX, relY = dx - inhX, dy - inhY
				-- THE AUTHORED PAINT DELTAS (ADR-0026), parked by the commit phase —
				-- exactly the role `lastRects` plays for the rect numbers, and for the
				-- same reason: `authored[path]` already holds the destination here.
				local dOp, dSc, dRo = 0, 0, 0
				local pd = if live then animationPaintDelta[path] else nil
				if pd ~= nil then
					dOp, dSc, dRo = pd.o, pd.s, pd.r
				end
				-- a path already carrying a record must be re-based even when its relative
				-- delta is zero this time, or it keeps flying to a place it no longer sits
				local claimed = relX ~= 0
					or relY ~= 0
					or dw ~= 0
					or dh ~= 0
					or dOp ~= 0
					or dSc ~= 0
					or dRo ~= 0
					or animationRecords[path] ~= nil
				if live and claimed and handles[path] ~= nil then
					claim(path, relX, relY, dw, dh, dOp, dSc, dRo)
					-- what the children inherit is this path's composed ABSOLUTE POSITION
					-- delta. Size is deliberately absent: see the comment above.
					inhX, inhY = dx, dy
				end
			end
			for _, child in node.children do
				walk(child, inhX, inhY)
			end
		end
		walk(root.node, 0, 0)
		-- the parked deltas belong to THIS armed commit only: a path the walk declined
		-- (not live, no handle) must not be flown by the next call
		animationPaintDelta = {}
		if set ~= nil then
			set.spring:setTarget(0)
			-- after the aim, so the seed is what integrates from here
			if carryMagOld > 0 and carryMagNew > 0 then
				set.spring:setVelocity(carryVelocity * (carryMagOld / carryMagNew))
			end
		end
	end

	-- Armed by `presenter.withAnimation` for exactly one commit, which it forces
	-- itself after draining the queue UNARMED — so the frame-coalesced refresh,
	-- virtual-list windowing, replication reverts and async landings never install
	-- records. `session.newSpring()` is called lazily, so a call that moves nothing
	-- builds no spring.
	function controller.armAnimation(session: any)
		animationSession = session
		-- the paths alive at the PREVIOUS (unarmed) commit — see `live` above for
		-- why this cannot be `lastRects`
		local alive: { [string]: boolean } = {}
		for path in handles do
			alive[path] = true
		end
		animationBaseline = alive
	end

	function controller.disarmAnimation()
		animationSession = nil
		animationBaseline = nil
	end

	-- DIAGNOSTIC (design §Proof), not a feature: how many paths currently carry a
	-- `withAnimation` record. The suite reads it to prove roots-only recording.
	function controller.animationRecordCount(): number
		return animationRecordN
	end

	-- keep-visible, REIMPLEMENTED OVER THE PER-NODE CHANNEL (fixes SF-M9). The
	-- root node IS the surface, so its transform is the whole-surface shift the
	-- keyboard case needs; `dy = 0` writes the zero transform rather than clearing,
	-- because "restored" is a value the presenter's own tests read back.
	function controller.setPresentationOffset(dy: number)
		if dy == lastOffsetY then
			return
		end
		lastOffsetY = dy
		controller.setPresentationTransform(root.node.path, { x = 0, y = -dy })
	end

	-- cross-surface z (modal-dismissal spec §2.2): the presenter orders whole
	-- surfaces (base < scrim < modal) via the root's display order. Optional
	-- adapter method — headless/older targets that don't order roots ignore it.
	function controller.setDisplayOrder(n: number)
		if adapter.setRootDisplayOrder ~= nil then
			adapter.setRootDisplayOrder(rootHandle, n)
		end
	end

	-- THE ENGINE-CONTENT SEAM (UI.Stage, ViewportFrame adoption 2026-08-08). A
	-- `Stage` reserves a box for content the ENGINE draws, and that content is
	-- Instances by nature — so the framework never touches it: the adapter answers
	-- a per-node handle (camera, lighting, a content root the caller parents its own
	-- models into) and this is the one door to it. Optional on BOTH sides: an
	-- adapter that never grew the seam, a node that is not a live Stage, or a path
	-- that is not mounted all answer nil, so an author gates on the nil or presents
	-- a fallback plate — never a crash and never a silent no-op.
	function controller.stageHost(path: string): any?
		if adapter.stageHost == nil then
			return nil
		end
		local handle = handles[path]
		if handle == nil then
			return nil
		end
		return adapter.stageHost(handle)
	end

	-- whole-surface visibility, used by the presenter's no-pop text gate: a
	-- surface mounts and solves normally but is not SEEN until its text is
	-- exact. Returns false when the adapter cannot hide a root, so the caller
	-- can degrade to showing it rather than gating on a write that never lands.
	function controller.setRootVisible(visible: boolean): boolean
		if adapter.setRootVisible == nil then
			return false
		end
		adapter.setRootVisible(rootHandle, visible)
		return true
	end

	-- INCREMENTAL-LAYOUT STAGE 1: DETECTION ONLY (docs/plans/incremental-layout.md).
	--
	-- Re-solves the last tree with boundary detection on and reports how much of it a
	-- boundary-aware layout would have to redo for a single change. It changes
	-- nothing and runs only when called, so an ordinary frame pays nothing for it —
	-- the whole point of Stage 1 is to size Stages 2 and 3 before touching the solver
	-- for real.
	function controller.analyzeBoundaries(): any
		if lastSolveInputs == nil then
			return nil
		end
		local opts2 = table.clone(lastSolveInputs.opts)
		opts2.analyzeBoundaries = true
		local result = solver.solve(lastSolveInputs.layoutRoot, lastSolveInputs.viewport, opts2)
		return solver.boundaryReport(lastSolveInputs.layoutRoot, result)
	end

	function controller.stats()
		return table.clone(stats)
	end

	function controller.diagnostics()
		return table.clone(lastDiagnostics) -- a copy, like `stats()` (F-30)
	end

	-- compositionAt(path) -> the last solve's `luauui-composition-dump/1` for that
	-- UI.Composition node, or nil. Omit the path for every one of them, keyed by
	-- path (ADR-0023). This is the "why" surface: which arrangement won, which
	-- form each region resolved to, and the rule every richer candidate broke.
	function controller.compositionAt(path: string?): any
		if path == nil then
			-- the SET is a copy (F-30); each dump inside it is the stored dump,
			-- exactly what the per-path read hands back
			return table.clone(lastCompositions)
		end
		return lastCompositions[path]
	end

	-- textAt(path) -> the last solve's measurement facts for that text node, or
	-- nil. Omit the path for every one of them, keyed by path (LTN-4). Same shape
	-- and same copy discipline as `compositionAt`: font, size, lines,
	-- naturalLines, truncated, lineLimit, disclose, policy, text.
	function controller.textAt(path: string?): any
		if path == nil then
			return table.clone(lastTextFacts)
		end
		return lastTextFacts[path]
	end

	-- THE PRESENTATION HOLD (auto reveal, 2026-08-04). The presenter paints its
	-- travelling strip OVER a source label and holds that label's own paint
	-- while the strip covers it. Presentation-layer only: the solve, the rects
	-- and the facts are untouched, so the reveal target stays "truncated" and
	-- the strip's travel distance stays honest. The hold survives re-solves and
	-- structural remounts of the path (the visibility walk ORs it in); it is
	-- the PRESENTER's to clear, and it dies with this controller either way.
	function controller.setPaintHeld(path: string, held: boolean)
		paintHeld[path] = if held then true else nil
		local handle = handles[path]
		if handle ~= nil and adapter.setVisible ~= nil then
			local want = solverHidden[path] ~= true and not held
			if lastVisible[path] ~= want then
				adapter.setVisible(handle, want)
				lastVisible[path] = want
			end
		end
	end

	-- is a text premeasurement round still outstanding? A surface that must not
	-- be seen until its text is exact polls this. False also means "nothing was
	-- ever asked for", which is the right answer for an adapter without the
	-- seam: there is nothing to wait for.
	function controller.textPending(): boolean
		for _ in textInFlight do
			return true
		end
		return false
	end

	function controller.dispose()
		-- a premeasurement round outlives the surface that asked for it (it is
		-- an async engine call): mark the controller dead so a late answer
		-- neither re-solves nor writes into destroyed handles
		disposed = true
		-- the selection bridge always clears on teardown (NS-A12): a dismissed
		-- modal must never leave the engine pointing at a destroyed instance
		if bridgeEngaged and adapter.setEngineSelection ~= nil then
			adapter.setEngineSelection(nil)
		end
		-- the drag registry dies with its surface: a live session holding a proxy
		-- and a motion pair must not outlive the tree it was aiming at
		if dragRegistryInstance ~= nil then
			dragRegistryInstance.dispose()
			dragRegistryInstance = nil
		end
		table.clear(dragUnbind)
		table.clear(scrollHostOf)
		-- RS-PATHCLIP: the per-scroll-host offset subscriptions are the one
		-- connection this rule holds, so they die with the surface like every
		-- other adapter subscription
		for path, detach in pathClipObservers do
			pathClipObservers[path] = nil
			detach()
		end
		table.clear(clipHostOf)
		table.clear(pathNodes)
		pathNodeCount = 0
		-- a `withAnimation` spring is built on the presenter's clock, which OUTLIVES
		-- this surface, so the springs die with the surface that started them
		for i = #animationSets, 1, -1 do
			animationSettle(animationSets[i])
		end
		attachScope:dispose()
		drainRecyclePool()
		adapter.destroyRoot(rootHandle)
		handles = {}
		lastRects = {}
		-- TEARDOWN IS A DISAPPEARANCE, and it is the most common one: a panel closes
		-- by being dismissed, not by having its rows re-keyed. Queued here, after the
		-- root is destroyed, so the hooks run with nothing left to reach and an error
		-- in one cannot strand the teardown above it. A pending APPEAR is dropped
		-- rather than fired — a node that never had a frame did not appear — while
		-- every declared cleanup still runs, because a missed cleanup is the dangerous
		-- direction and an extra one is not.
		table.clear(appearQueue)
		for path, fn in disappearHooks do
			table.insert(departedQueue, { path = path, fn = fn })
		end
		table.clear(disappearHooks)
		table.clear(authoredHidden)
		drainDeparted()
	end

	return controller
end

return renderer
