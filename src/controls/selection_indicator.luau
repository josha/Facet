--!strict
-- SelectionIndicator — the sliding selection seam (navigation-and-menus brief
-- §2 D4). ONE indicator that ANIMATES FROM THE PREVIOUSLY SELECTED CHILD'S RECT
-- TO THE NEW ONE, in two skins: the `underline` (r2's tab bar, f1's sheet strip)
-- and the filled `pill` (r3's segmented control, f1's top rail and left rail).
--
-- ===== IT IS AN INTERNAL SEAM, NOT A PUBLIC CONSTRUCT =====================
--
-- Director ruling 2026-08-16: the PUBLIC authoring surface for this is a
-- PROPERTY on the controls that consume it — `indicator = "underline" | "pill" |
-- "none"` on `newPicker`, and the same property on D5's TabView. Nobody
-- instantiates the mechanism directly, so there is no `src/init.luau` export, no
-- `api.md` heading of its own, and no dump schema of its own: its state is
-- reported inside the consuming control's `dump()` (see `picker.dump().indicator`).
-- The same shape `row_actions_trays` and `virtual_window` already have — a
-- registry row that names the control it serves.
--
-- What IS deliberately reachable is the pure geometry decision below
-- (`resolveIndicatorRect`) and the pure motion decision (`resolveTransition`),
-- because both consumers must be able to test against them.
--
-- ===== WHY A SEAM AND NOT A CONTROL OR A MODIFIER =========================
--
-- It wraps a strip somebody else built and paints one decoration behind it. It
-- is not a control (it owns no value, takes no input and is never a focus stop)
-- and it is not a modifier (the constitution's positional-scalar modifier family
-- is CLOSED, §16 E-18, and this needs its own reactive state, its own motion and
-- its own geometry intake).
--
-- The shape is chosen so that NEITHER consumer owns it. D5's `TabView` is a
-- strip of tabs with content below; D6's segmented `Picker` is a pill of
-- buttons with nothing below; f1's left rail is the same pill turned VERTICAL.
-- Those three trees have nothing structural in common — so this seam is told
-- nothing about them. It is handed:
--
--     * `content`  — the strip blueprint, whatever shape it is;
--     * `segments` — {(selection value, child id)} pairs;
--     * `selected` — the owner's Readable (this module NEVER writes it).
--
-- and it resolves each child's SOLVED RECT by id at run time. A host that can
-- give an id to the thing it wants underlined can use this; nothing else about
-- the host is assumed, which is why one seam serves a horizontal tab strip, a
-- horizontal pill and a vertical pill without either consumer subclassing it.
--
-- ===== THE TRANSITION IS BETWEEN TWO RECTS, NEVER TWO INDICES ==============
--
-- Segments stop being equal-width the moment their labels differ ("For you" vs
-- "Charts" in r2), and they stop being equal-anything under a 1.4x
-- pseudo-localization. Interpolating an INDEX would put the bar under nothing
-- for the whole flight and land it at the wrong width. So four scalar springs
-- carry x, y, w and h from the old rect to the new one, and a 2-D flight is two
-- scalar springs (src/motion/chase.luau's rule, applied to a box instead of a
-- point). Nothing here knows what position a segment holds in the strip.
--
-- ===== GEOMETRY ARRIVES ON THE ARRANGE CADENCE, COMPARED BY VALUE ==========
--
-- `syncGeometry` (the input-contribution seam) is fed the surface's `rectOf` on
-- EVERY solve and every refresh, so an unguarded intake would re-run the target
-- memo, re-aim four springs and re-solve the surface forever. Both stages are
-- therefore compared BY VALUE, the `renderer.luau:2844-2860` shape from
-- `8560f2b` ("one viewport change is one solve, not five"):
--
--     fed        a FLAT numeric table (host rect + every segment rect), written
--                by syncGeometry into a signal whose equality is `sameGeometry`;
--     targetRect a scope-owned MEMO over (`fed`, `selected`) whose equality is
--                the same comparator.
--
-- `sameGeometry` refuses any table-valued field outright rather than comparing
-- it by identity — the renderer's own deliberate conservatism, kept here for the
-- same reason: a rebuilt-outer/reused-inner shape would otherwise report a false
-- "unchanged", which is a MISSED update rather than a spare one.
--
-- `rectOf`, NOT `screenRectOf`. The indicator lives in the SAME parent as the
-- strip it tracks, so it inherits every scroll offset and presentation shift the
-- strip inherits; subtracting two raw host-space rects cancels them exactly.
-- `screenRectOf` accumulates those shifts, so inside D5's overflowing horizontal
-- ScrollView it would apply the scroll twice and the bar would fly off the strip.
-- THE SAME ARGUMENT COVERS A COORDINATE-SPACE HOST (Plan C, C1): beneath one, a
-- stored rect is relative to the host, and the layer and the segments are under
-- the SAME host — so the origin is a common term in the subtraction and cancels,
-- exactly as the scroll offset does. `tests/translate_host.spec.luau` pins the
-- delta across a host move rather than leaving the cancellation asserted.
--
-- ===== REDUCED MOTION SNAPS, AND IT IS NOT RE-PLUMBED HERE =================
--
-- A `clock:spring` value is DECORATIVE by default, and the motion authority's
-- own I-4 invariant already says a decorative `setTarget` under reduced motion
-- places the value at its terminus INSTANTLY, on the same frame, with the same
-- events (src/motion/motion.luau). The clock reads `motionPolicy`, which the
-- environment derives from `reducedMotion`. So this module contains no reduced-
-- motion branch at all: it aims springs, and the authority decides whether that
-- is a flight or a placement. The spec proves it by COUNTING the rect writes the
-- adapter receives across twenty presenter ticks, not by reading a flag.
--
-- ===== FIRST PAINT PLACES; IT DOES NOT SLIDE IN FROM NOWHERE ===============
--
-- `resolveTransition` is the whole policy, pure and exported:
--   * never placed         -> PLACE (the initial selection is where the bar IS)
--   * placed, selection changed -> SLIDE
--   * placed, selection unchanged -> PLACE
-- The third rule matters as much as the first: a rotation, a theme swap or a
-- preferred-text change moves every segment rect under an UNCHANGED selection,
-- and a bar that swims across the strip on every re-solve is a bug, not motion.
--
-- ===== NEVER A FOCUS STOP =================================================
--
-- `collectFocusables` (src/present/focus_map.luau) appends any node whose class
-- is in FOCUSABLE — Button, Toggle, TextField — and that flat order IS the
-- document order Tab walks. The indicator is an `Anchor` holding a `Box`:
-- neither class is focusable, and the layer is declared FIRST inside the ZStack
-- so it paints BEHIND the strip and can never take a tap from it. Wrapping a
-- strip therefore leaves its focus order byte-identical, which the spec asserts
-- rather than assumes.
--
-- ===== IT NEVER OPENS A PRESENTER ANIMATION SCOPE ==========================
--
-- `presenter.withAnimation` is presenter-wide and hard-errors on re-entrant
-- nesting, so a decoration that wrapped its own writes in it would explode
-- inside any caller that had already opened one. This seam owns its own motion
-- values instead and drives them directly; it is safe to mount inside anything.

local contribution = require("../input/contribution")
local specGuard = require("../spec_guard")
local rectLib = require("../rect")
local themeSnapshot = require("../themes/snapshot")
local chrome_slots = require("../tokens/chrome_slots")

local selection_indicator = {}

export type Segment = { value: any, id: string }

export type Spec = {
	id: string?,
	content: any, -- the strip blueprint this indicator tracks (required)
	segments: any, -- array or internal readable keyed segment array -- (selection value, child id) pairs (required)
	selected: any, -- owner-held Readable; never written by this module
	skin: string?, -- "underline" (default) | "pill"
	-- "x" (default) | "y", or a Readable of either. REACTIVE, because the host's
	-- own axis can be: `newPicker` flips its option stack between a row and a
	-- column on a live space change and that flip is a RE-SOLVE, not a rebuild
	-- (the A-AL2 rule), so an indicator holding a build-time axis would keep
	-- underlining the wrong edge for the rest of the session.
	axis: any?,
	thickness: any?, -- underline bar extent: a metric name or a number
	inset: any?, -- pill inset from the segment box: a metric name or a number
	surface: string?, -- Box surface role painted by the bar (default "accent")
	corner: any?, -- corner radius token/number (the theme's control radius by default on the pill skin)
	--[[ PER-SEGMENT CORNER DATA, parallel to `segments` — an array of normalized
		`UI.cornersData(…)` values (or a Readable of one). The bar wears the entry
		of the segment it is currently on, so a strip whose ends are rounded and
		whose middle is square hands its fill the SAME silhouette instead of a
		permanent pill that leaves four slivers of track showing in the middle.
		Absent, `corner` is spent uniformly and nothing about this changes. ]]
	segmentCorners: any?,
	motionClass: string?, -- registered motion class name (default "object")
	env: any?, -- optional environment, for live theme metrics
	-- the WRAPPER's own dimensions. Wrapping is not free: a `fill` strip inside a
	-- content-sized wrapper has nothing to fill and solves to zero, so a host that
	-- declared a dimension on the strip must declare the same one here. Found by
	-- the Rascal Rally rider, where an indicated picker's options measured 0px.
	width: any?,
	height: any?,
}

local SKINS: { [string]: boolean } = { underline = true, pill = true }
local AXES: { [string]: boolean } = { x = true, y = true }

-- THEME METRICS. Both
-- numbers are small distances the theme's own SPACING scale already owns, so
-- neither needs a new control family — a package published before this module
-- existed answers both, and a theme that retunes its spacing retunes the
-- indicator with it. A caller may pass any other metric name (or a number) per
-- skin.
local DEFAULT_THICKNESS = "space.xs"
local DEFAULT_INSET = "space.xs"
--[[ THE CHIP'S ROUNDING, AND IT IS THE THEME'S (user visual review 2026-09-12,
	item 6). It was `"pill"` — the theme's own "fully rounded" role — which made
	the selection the ONE shape on the page a package could not restyle: Pixel
	Quest and Fantasy Ornate draw square controls and got a capsule anyway,
	because a fully-rounded role is still a role and a square theme still has to
	publish one.

	`radii.control` is the role every other control's corner already comes from,
	so a package that rounds its controls fully gets a pill here for the reason
	it gets one everywhere else, and a package that squares them gets a square.
	A caller that genuinely wants a capsule whatever the theme says still writes
	`corner = "pill"`, which is why that key stays authored.

	An underline stays square by default because that is what a tint rule on one
	edge of a segment is. ]]
--[[ THE HIGHLIGHT'S SHAPE IS A THEME TOKEN (user ruling 2026-09-12).
	`DEFAULT_CORNER` is the FAMILY name, not a finished answer: on its own
	`radii.selection` follows `radii.control` unless a package authors it (square
	art sets 0), and that is what a fill with no container to match takes. A fill
	whose caller NAMED its container takes `selection:<container>` instead — see
	`fillCornerFor` immediately below, which is the rule a reader should meet
	first, because it decides every shipped strip.

	The bar wears one uniform radius on all four corners either way — an inset
	rounded rect floating inside the plate, the reference platform's segmented
	control — while the TRACK and its end segments keep `radii.control`
	(`TRACK_CORNER`, spent by `segmentShape`). ]]
selection_indicator.DEFAULT_CORNER = "selection"
selection_indicator.TRACK_CORNER = "control"

--[[ ...AND THE LAST RESORT IS A NUMBER (final review item 1).

	`DEFAULT_CORNER` is a TOKEN, so asking a style for it is asking a question
	that style may not answer: `radii.selection` follows `radii.control`, and a
	metrics table carrying neither answers neither. That is fine where the answer
	is allowed to fail — but the fallback arm of `derivedCorners` is precisely the
	site that exists SO a corner nothing answers still paints something, and it
	spent the token too. Under a style that cannot name it, the healer raised
	inside a memo, was quarantined, and the bar painted square: the exact outcome
	the fallback was written to prevent.

	A NUMBER cannot raise (`resolveRadius` only asserts it is non-negative), and
	the neutral snapshot is the framework's own default vocabulary — the same
	value `metricsSig` degrades to when it is handed a table it cannot spend — so
	the floor under every corner resolve in this control is one literal pixel
	count, resolved once. It carries no token, deliberately: there is no name left
	to re-resolve against the paint-time style, and inventing one would put the
	unanswerable question back. ]]
local lastResortRadius: number? = nil
local function neutralSelectionRadius(): number
	if lastResortRadius == nil then
		local radii = (themeSnapshot.neutral() :: any).radii
		local authored = if type(radii) == "table" then (radii.selection or radii.control) else nil
		lastResortRadius = if type(authored) == "number" then authored else 0
	end
	return lastResortRadius :: number
end

--[[ THE CONTAINER IS THE AUTHORITY ON THE FILL'S SILHOUETTE (owner report
	2026-09-12, controller ruling).

	A selected fill sits INSIDE a strip, and the strip's plate is the shape a
	player sees it against: a pill strip holding a rounded-rect chip is two
	silhouettes in one control, and the theme was asked for neither. `radii
	.selection` cannot answer that on its own — it follows `radii.control`, which
	is what a picker's own TRACK wears and NOT what every strip wears (a
	`TabView`'s adaptable app bar is a `radii.pill` capsule).

	So a fill whose caller named its container asks for that container's OWN
	highlight token, `selection:<container>`. The three clauses — an authored
	`radii.selection` wins, a pill container gives a pill by the pill rule, and
	anything else is the container's radius less the inset — live in
	`src/tokens/styling.luau`'s `resolveRadius` and its snapshot mirror, beside
	every other radius rule.

	IT RETURNS A TOKEN NAME and never a number, which is the whole point of doing
	it here rather than computing a radius at the call site: a number authored
	near freezes the NEAR display's radius into a strip a ten-foot screen then
	paints with (`tests/ten_foot_metrics.spec.luau`). The name survives to the
	painter and re-resolves against the style that paints with it. ]]
function selection_indicator.fillCornerFor(trackCorner: any): any
	if type(trackCorner) ~= "string" or trackCorner == "" then
		return selection_indicator.DEFAULT_CORNER
	end
	return `{selection_indicator.DEFAULT_CORNER}:{trackCorner}`
end

-- CLOSED SPEC (constitution §4). An unknown key is an authoring
-- mistake, never a silent no-op.
local INDICATOR_KEYS = specGuard.keySet({
	"axis",
	"content",
	"corner",
	"env",
	"id",
	"inset",
	"plate",
	"motionClass",
	"segmentCorners",
	-- the corner the STRIP THAT HOLDS THE FILL actually wears (see
	-- `fillCornerFor`). The container is the authority on the fill's silhouette;
	-- absent, the fill keeps the `radii.selection` token it always took.
	"trackCorner",
	"segments",
	"selected",
	"height",
	"skin",
	"surface",
	"thickness",
	"width",
})

-- ===== the two pure decisions (plain numbers in, plain values out) =========

export type Rect = { x: number, y: number, w: number, h: number }

export type SkinOpts = {
	skin: string,
	axis: string,
	thickness: number,
	inset: number,
}

--[[ THE ONE GEOMETRY DECISION. Both skins are the same arithmetic over the
	SELECTED CHILD'S rect, expressed in the host layer's own coordinate space
	(the anchor offsets the renderer will spend). `child` and `host` arrive in
	the same raw host space, so the subtraction cancels every shift both share.

	pill       the whole segment box, inset on all four sides — r3's chip and
	           f1's top rail; identical arithmetic on x and y, which is why the
	           VERTICAL pill (f1's left rail) needs no second code path.
	underline  a bar `thickness` deep on the far edge of the axis the strip runs
	           along: the BOTTOM of a horizontal segment (r2, f1's sheet strip),
	           the LEADING edge of a vertical one. It spans the segment's full
	           cross extent, so a 1.4x-expanded label widens the bar with it and
	           it can never be painted at a size nobody measured.

	Returns nil when there is nothing to point at; the caller hides the bar. ]]
function selection_indicator.resolveIndicatorRect(child: Rect?, host: Rect?, opts: SkinOpts): Rect?
	if child == nil or host == nil then
		return nil
	end
	local x = child.x - host.x
	local y = child.y - host.y
	if opts.skin == "pill" then
		local inset = math.max(opts.inset, 0)
		return {
			x = x + inset,
			y = y + inset,
			w = math.max(child.w - 2 * inset, 0),
			h = math.max(child.h - 2 * inset, 0),
		}
	end
	-- underline: never thicker than the box it decorates
	local thickness = math.max(opts.thickness, 0)
	if opts.axis == "y" then
		return { x = x, y = y, w = math.min(thickness, child.w), h = child.h }
	end
	return {
		x = x,
		y = y + child.h - math.min(thickness, child.h),
		w = child.w,
		h = math.min(thickness, child.h),
	}
end

--[[ THE STRIP'S CORNER LANGUAGE, as one pure function (user visual review
	2026-09-12, item 2). A run of segments that reads as ONE control rounds only
	its two OUTER ends and leaves everything between them square:

	    index 1        the leading end rounds       (left on x, top on y)
	    index count    the trailing end rounds      (right on x, bottom on y)
	    everything else                             square on all four
	    count <= 1     one segment IS both ends, so it takes the plain shape

	`radii.control` is spent as a TOKEN, never a resolved number: normalizeCorners
	keeps the name beside the authored pixel and the painter re-resolves it
	against the style it paints with, so a ten-foot display's derived radius
	reaches the strip instead of a build-time near-distance number.

	It lives here rather than in either consumer because BOTH speak it — the
	segmented picker's strip and the level picker's run of marks — and a second
	copy is how the two would drift apart the day the rule changes. `UI` is passed
	in for the same reason every recipe in this framework takes it: this module
	stays free of the init cycle. ]]
function selection_indicator.segmentShape(UI: any, index: number, count: number, axis: string): any
	if count <= 1 then
		return UI.cornersData(selection_indicator.TRACK_CORNER)
	end
	local first = if index == 1 then selection_indicator.TRACK_CORNER else 0
	local last = if index == count then selection_indicator.TRACK_CORNER else 0
	if axis == "y" then
		return UI.cornersData({ topLeft = first, topRight = first, bottomLeft = last, bottomRight = last })
	end
	return UI.cornersData({ topLeft = first, bottomLeft = first, topRight = last, bottomRight = last })
end

--[[ THE ONE MOTION DECISION. Pure, so the rule is a test over booleans rather
	than a claim about a mounted tree. See the header: the first placement and
	every re-solve under an UNCHANGED selection are PLACEMENTS; only a selection
	change is a flight. ]]
function selection_indicator.resolveTransition(placed: boolean, selectionChanged: boolean): string
	if not placed then
		return "place"
	end
	return if selectionChanged then "slide" else "place"
end

--[[ THE ONE PAINT DECISION: WHICH SURFACE THE BAR PLATES WITH, or nil for a bar
	that plates nothing (stabilization B'1, 2026-09-07).

	It was an inline expression at `barSurface`'s declaration, spent by this
	module alone. It is a function now — pure, exported, tested as arithmetic —
	because the CONSUMER has to be able to ask the same question: a bar that
	paints a plate is a plate UNDER SOMEBODY'S LABEL, and the label needs the
	colour that reads on it (`sheet_model.ON_INDICATOR_ROLE`). The consumer
	builds its strip BEFORE this seam exists, so it cannot read the answer off
	`build`; a second copy of the expression over there is how the two skins
	would drift apart the day a third one lands.

	`underline` returns nil deliberately and that is the whole distinction: it
	paints a `space.xs` tint RULE on the far edge of the segment, not a plate
	under the label, so the label keeps sitting on the ordinary surface and keeps
	$Content. Confirmed against the geometry above — `resolveIndicatorRect`'s
	underline branch is a bar `thickness` deep on one edge, never the segment
	box. ]]
function selection_indicator.barSurfaceFor(skin: string, surface: string?): string?
	if surface ~= nil then
		return surface
	end
	return if skin == "pill" then "accent" else nil
end

-- BY-VALUE COMPARISON, and the renderer's own. This comment used to
-- say "renderer.luau's `sameGeometryValue`, kept field-for-field" above a
-- verbatim copy of it, across a layer boundary; `src/rect.luau` is the leaf both
-- may require, and it states the reason the refusal of nested fields is
-- load-bearing rather than defensive.
local sameGeometry = rectLib.sameFlatValue

selection_indicator.sameGeometry = sameGeometry

-- read a Readable-or-plain value, subscribing when a `use` is in hand. BOTH
-- reactive kinds: `selected` is normally a Signal and `axis` is normally a MEMO
-- (picker's option-stack axis is derived from its presentation), and reading only
-- one of them would hand the caller back the node itself.
local function readValue(source: any, use: any?): any
	if type(source) == "table" and ((source :: any).kind == "signal" or (source :: any).kind == "memo") then
		return if use ~= nil then use(source) else (source :: any):get()
	end
	return source
end

-- does this static blueprint subtree mount more than it declares? A `When` or a
-- `ForEach` can, so a segment id absent from the static tree is not provably an
-- authoring error there (see the build-time check).
local function findIds(bp: any, ids: { [string]: boolean }, structural: { boolean })
	if type(bp) ~= "table" then
		return
	end
	if bp.class == "When" or bp.class == "ForEach" then
		structural[1] = true
	end
	if type(bp.id) == "string" then
		ids[bp.id] = true
	end
	for _, child in bp.children or {} do
		findIds(child, ids, structural)
	end
end

function selection_indicator.build(Facet: any, core: any, spec: Spec)
	specGuard.assertKnownKeys("selectionIndicator", spec, INDICATOR_KEYS, "spec")
	local UI = Facet.UI
	local id = spec.id or "SelectionIndicator"
	local scope = core:scope("selection-indicator-" .. tostring(id))

	if type(spec.content) ~= "table" or spec.content.class == nil then
		error(`Facet selectionIndicator('{id}'): \`content\` must be the strip blueprint this indicator tracks`, 0)
	end
	local liveSegments = type(spec.segments) == "table" and spec.segments.kind ~= nil
	local function segmentsNow(use)
		return readValue(spec.segments, use)
	end
	if type(segmentsNow()) ~= "table" or (not liveSegments and #segmentsNow() == 0) then
		error(
			`Facet selectionIndicator('{id}'): \`segments\` must be a non-empty array of `
				.. "{ value = <selection value>, id = <the child's id> } pairs",
			0
		)
	end
	local skin = spec.skin or "underline"
	if not SKINS[skin] then
		error(`Facet selectionIndicator('{id}'): unknown skin '{tostring(skin)}'. One of underline | pill.`, 0)
	end
	-- `axis` may be a plain string or a Readable (see the Spec comment). A plain
	-- one is validated here; a Readable's CURRENT value is validated here too, so
	-- a typo is still an authoring error rather than a wrong edge — but a later
	-- unknown value is tolerated as "x" rather than thrown from inside a memo,
	-- which is `picker.readSizeClass`'s own tolerance for a reactive enum.
	local axisSource = if spec.axis == nil then "x" else spec.axis
	local function axisNow(use: any?): string
		local value = readValue(axisSource, use)
		return if AXES[value] then value else "x"
	end
	local declaredAxis = readValue(axisSource)
	if not AXES[declaredAxis] then
		error(
			`Facet selectionIndicator('{id}'): unknown axis '{tostring(declaredAxis)}'. One of x | y — a vertical `
				.. 'segmented pill is `axis = "y"`, and it is the same mechanism, not a second one.',
			0
		)
	end

	-- AUTHORING CHECK: a segment id that names no child is a typo the strip's
	-- author can fix now instead of finding an invisible indicator later. It is
	-- skipped when the strip contains a `When`/`ForEach`, because those mount
	-- children this static walk cannot see; an id that never resolves at run time
	-- is reported by `state().unresolved` instead.
	local declaredIds: { [string]: boolean } = {}
	local structural = { false }
	findIds(spec.content, declaredIds, structural)
	for i, segment in segmentsNow() do
		if type(segment) ~= "table" or type(segment.id) ~= "string" or segment.id == "" then
			error(
				`Facet selectionIndicator('{id}'): segments[{i}] needs an \`id\` naming the child this `
					.. "indicator points at",
				0
			)
		end
		if not structural[1] and not declaredIds[segment.id] then
			error(
				`Facet selectionIndicator('{id}'): segments[{i}].id '{segment.id}' names no child of `
					.. "`content`. The indicator resolves each segment's SOLVED RECT by id, so the id must be the "
					.. "one the strip gave that child.",
				0
			)
		end
	end

	-- THEME METRICS resolved to pixels, because the arithmetic above is Luau's:
	-- `child.h - thickness` cannot be handed to the solver as a metric NAME. Same
	-- shape as `table.luau`/`row_actions_metrics.luau` — `spec.env` is optional
	-- and absent degrades to the neutral snapshot, while a live theme swap
	-- re-resolves through `env:get("themeMetrics")`, which is itself reactive.
	local env = spec.env
	local metricsSig = scope:own(core:memo(function(use)
		if env == nil then
			return themeSnapshot.neutral()
		end
		local raw = use(env:get("themeMetrics"))
		-- `radii` is checked as well as `controls` because the corner resolve
		-- below spends it: a hand-built metrics table carrying `controls` and no
		-- `radii` would otherwise reach `UI.cornersData` inside a memo and raise
		-- there, where it is quarantined. The guard's whole job is that this memo
		-- yields a snapshot every consumer of it can spend.
		return if type(raw) == "table"
				and type(raw.controls) == "table"
				and type(raw.radii) == "table"
			then raw
			else themeSnapshot.neutral()
	end))
	--[[ WHICH PLATE THE BAR IS, hoisted above `skinOpts` because the inset rule
		below has to know what the bar's surface CARVES. The declaration and the
		reasoning for it live at `barSurface`'s use site further down; only the two
		values move here. ]]
	local barSurface = selection_indicator.barSurfaceFor(skin, spec.surface)
	-- The default pill must paint Accent beneath OnAccent. Arbitrary control
	-- artwork can replace that fill with dark pixels, breaking the paired label.
	local barHint = if skin == "pill" and spec.surface == nil then chrome_slots.NO_SLOT else nil
	local barSurfaceSlot = chrome_slots.classify({ class = "Box", surface = barSurface })

	-- Keep the theme's segment coverage even when the pill uses palette paint.
	-- NO_SLOT changes artwork, not the established control-border clearance:
	-- subtracting that clearance prevents a second inset inside themed segments.
	local skinOpts = scope:own(core:memo(function(use)
		local snap = use(metricsSig)
		local carved = 0
		local insets = if type(snap) == "table" then (snap :: any).chromeInsets else nil
		local plate = if type(insets) == "table" and barSurfaceSlot ~= nil then (insets :: any)[barSurfaceSlot] else nil
		if type(plate) == "table" then
			for _, side in { "top", "right", "bottom", "left" } do
				local px = (plate :: any)[side]
				carved = math.max(carved, if type(px) == "number" then px else 0)
			end
		end
		local declared = themeSnapshot.resolveNumber(snap, spec.inset or DEFAULT_INSET) or 0
		return {
			skin = skin,
			axis = axisNow(use),
			thickness = themeSnapshot.resolveNumber(snap, spec.thickness or DEFAULT_THICKNESS) or 0,
			inset = math.max(0, declared - carved),
		}
	end, sameGeometry))

	-- ===== the painted bar =================================================
	-- Four owned signals ARE the bound props; the springs (built lazily, only
	-- once a presenter has handed over its clock) write into them. Exactly
	-- row_actions' shipped shape: with no clock — a bare `mountLib.mount` in a
	-- unit test, which never runs a presenter's bindContribution walk — every
	-- retarget falls back to an instant placement, which is a supported
	-- degradation and not a second code path.
	local offX = scope:own(core:signal(0))
	local offY = scope:own(core:signal(0))
	local boxW = scope:own(core:signal(0))
	local boxH = scope:own(core:signal(0))
	local shown = scope:own(core:signal(false))

	local function dimEq(a: any, b: any): boolean
		return type(a) == "table" and type(b) == "table" and a.px == b.px
	end
	-- A FRESH DIM TABLE EVERY WRITE WOULD RE-MEASURE EVERY FRAME. `width`/`height`
	-- carry `dirty = { "measure" }`, so the memo's by-value equality is what makes
	-- an equal-width strip (r3's icon-only segments) an ARRANGE-ONLY slide: the
	-- size memos never re-emit and only the two anchor offsets move.
	local widthDim = scope:own(core:memo(function(use)
		return { type = "fixed", px = use(boxW) }
	end, dimEq))
	local heightDim = scope:own(core:memo(function(use)
		return { type = "fixed", px = use(boxH) }
	end, dimEq))
	local hiddenMemo = scope:own(core:memo(function(use)
		return not use(shown)
	end))

	-- A pill fills its themed surface; an underline is a tint rule. The default
	-- pill keeps the palette fill paired with its label, while an explicit surface
	-- opts into that surface's ordinary chrome.
	local UNDERLINE_TINT = table.freeze({ role = "accent", blend = 1 })
	--[[ THE CORNER, AND WHICH SEGMENT DECIDES IT. `corner` is the uniform answer
		and has always been; `segmentCorners` is the per-index one, and it is a
		BOUND prop rather than a `UI.corners` wrap because the answer changes with
		the selection: a strip that rounds only its two ends has three silhouettes
		and the fill has to be wearing the right one on the frame it arrives. The
		`corners` prop is reactive and `paint`-dirty, so following the selection
		costs a paint write and never a re-solve.

		The uniform data is the FALLBACK inside the memo too, so a selection the
		array has no entry for (a live reorder mid-flight) draws the plain shape
		rather than dropping the prop and painting a square corner nobody asked
		for. ]]
	local corner = spec.corner or (if skin == "pill" then selection_indicator.DEFAULT_CORNER else nil)
	--[[ ...AND THE CONTAINER IS WHAT DECIDES IT when the caller named no corner
		(owner report 2026-09-12; `fillCornerFor` above carries the rule and the
		reasons). It is a MEMO rather than a constant because two of the three
		clauses read the live snapshot — whether the package authored
		`radii.selection` at all, and the container's radius less the inset the fill
		floats by — so a theme swap and a ten-foot display's scaled radii both
		re-resolve it, exactly as the geometry memo beside it does. A caller that
		named a corner, or a strip that declared no container corner, takes the same
		static answer it always took. ]]
	--[[ ...AND THE TOKEN IS NORMALIZED AGAINST THE LIVE SNAPSHOT, not the base
		style (review N6). `UI.cornersData` with no style resolves through
		`default_style`, whose `radii` is the BASE vocabulary — so
		`selection:<container>` for a container only a PACKAGE publishes
		(`radii.chip`) was refused here even though `paintCorners` would have
		answered it perfectly well one layer on. Handing it `metricsSig` asks the
		refusal of the style that will actually paint, which is the whole point of
		a refusal, and leaves the check as strict as it ever was for a container
		nothing publishes (a `selection:panle` typo still errors). The reactive
		branch reads it through `use`, so a theme swap re-resolves the token the
		same way the memo beside it re-resolves the geometry.

		...AND A MEMO MUST NOT RAISE (review D6). Asking the live style makes the
		answer depend on the live style, so a SWAP AWAY from the package that
		published the container — Pixel Quest's `radii.chip` uninstalled while a
		strip is mounted — turns a token that resolved a frame ago into one this
		style cannot answer. Inside a memo that is quarantined: the bar loses its
		corner data entirely and paints SQUARE, which is a worse answer than the
		one the token was reaching for. So the derived token is resolved
		DEFENSIVELY here and falls back to the plain `selection` radius, the same
		family, which every style can answer. The authoring refusal is unaffected
		— `newPicker` still refuses a container its live radii cannot name, where
		the author wrote it, which is the check that catches a typo. ]]
	local derives = spec.corner == nil and skin == "pill" and spec.trackCorner ~= nil
	--[[ the derived token, or the plain `selection` fallback when this style
		cannot answer it. `UI.cornersData` keeps the TOKEN beside the number, so
		the painter re-resolves whichever one survives against the style it paints
		with — a swap BACK re-derives the container answer on the next read.

		AND IT SAYS SO. A `pcall` that heals and tells nobody is the silent
		quarantine this codebase's own `fail()` header refuses ("a silent
		quarantine heals the STATE and tells nobody"). The fallback exists for a
		LEGITIMATE case — a theme swapped away from the package that published the
		container — but it catches an illegitimate one just as quietly: a REACTIVE
		`stripCorner` whose value becomes a typo. `newPicker`'s authoring check
		refuses a typo it can see at build, and by construction cannot see a value
		set later. So the healed case is noted, naming both the token and what was
		painted instead.

		ONCE PER TOKEN WHILE IT IS FALLING BACK, and the "while" is the whole
		point: the moment this site resolves ANY token the set is cleared, so
		`cornerFallbacks` reads as "is the fill painting a fallback RIGHT NOW"
		rather than "did it ever". That is what makes the count answer the
		question a reader has — a legitimate swap away from the package clears
		when the package comes back, a typo never does — and it means a second
		departure warns again, which is correct for a fact stated in the present
		tense. The set is REPLACED rather than added to, because only one token is
		in use at a time: the two ways a fallback ends are the style coming back
		(same token) and the caller changing the value (different token), and
		"what is failing here now" covers both. So it is at most 1 — a fill has
		one corner — and it is a count rather than a boolean so a second derived
		corner, if this control ever grows one, needs no new vocabulary.

		ONCE PER TOKEN PER CONTROL, not per session: three strips naming the same
		container warn three times on one theme swap. A per-CORE set would silence
		the other two, and it would have to be REFCOUNTED to stay honest under the
		"currently" rule above — one strip resolving again must not clear a note
		another strip is still earning — which is more machinery than the noise it
		saves, and it would leave this control's own count disagreeing with the
		dedup. Stated rather than solved, here and in `docs/reference/api.md`. ]]
	local notedCornerTokens: { [string]: boolean } = {}
	local cornerFallbacks = 0
	local function derivedCorners(token: any, style: any): any
		local ok, data = pcall(UI.cornersData, token, style)
		if ok then
			-- this site resolves again, so nothing here is falling back — whether
			-- the style came back or the caller corrected the token
			if cornerFallbacks > 0 then
				table.clear(notedCornerTokens)
				cornerFallbacks = 0
			end
			return data
		end
		local key = tostring(token)
		if not notedCornerTokens[key] then
			-- a DIFFERENT token is failing now; the previous one is not in use
			table.clear(notedCornerTokens)
			notedCornerTokens[key] = true
			cornerFallbacks = 1
			if type(warn) == "function" then
				--[[ THE FALLBACK NAMES ITSELF, AND THE FALLBACK IS NOT ALWAYS THE
					SAME ONE (R3). Below this the resolve tries `DEFAULT_CORNER` and
					then, if THAT fails too, the neutral theme's own number. When the
					token that just failed IS `DEFAULT_CORNER`, the first branch is
					already spent: the message promised "paints plain 'selection'
					instead" while naming 'selection' as the thing that failed, which
					reads as a contradiction to the one person who ever sees it. ]]
				local fallback = if key == selection_indicator.DEFAULT_CORNER
					then `the neutral theme's own selection radius ({neutralSelectionRadius()}px)`
					else `plain '{selection_indicator.DEFAULT_CORNER}'`
				warn(
					`Facet selection indicator: no live style answers the corner token '{key}', so the fill `
						.. `paints {fallback} instead. A theme swapped away from `
						.. `the package that publishes that container is expected; a container name that never `
						.. `resolves is an authoring mistake (\`stripCorner\` refuses one it can see at build, `
						.. `and cannot see a value set later).`
				)
			end
		end
		local plain, plainData = pcall(UI.cornersData, selection_indicator.DEFAULT_CORNER, style)
		if plain then
			return plainData
		end
		return UI.cornersData(neutralSelectionRadius())
	end
	--[[ ...INCLUDING THE STATIC ONE (final review item 1). This site resolved the
		authored/default corner RAW, so the same unanswerable style raised out of
		`Picker(...)` itself — an author's call erroring on a token the theme in
		hand happens not to publish. It is the same question `derivedCorners` asks
		and heals, asked one line earlier, so it goes through the same door. ]]
	--[[ ...AND NOT WHEN THE STRIP DERIVES (R3). `derives` means the caller named
		no corner, so `corner` is `DEFAULT_CORNER` by the line above and this
		resolve's answer is overwritten two lines down by the derived one. It was
		never dead in the harmless sense: a style that cannot answer 'selection'
		fires the warn and sets `cornerFallbacks = 1` for a corner that is then
		thrown away and never painted, so the diagnostic reported a fallback that
		did not happen. ]]
	local uniformCorners: any = if corner ~= nil and not derives then derivedCorners(corner, metricsSig:get()) else nil
	if derives then
		local reactive = type(spec.trackCorner) == "table"
		if reactive then
			uniformCorners = scope:own(core:memo(function(use)
				return derivedCorners(
					selection_indicator.fillCornerFor(readValue(spec.trackCorner, use)),
					use(metricsSig)
				)
			end))
		else
			uniformCorners = derivedCorners(selection_indicator.fillCornerFor(spec.trackCorner), metricsSig:get())
		end
	end
	local barCorners: any = uniformCorners
	if spec.segmentCorners ~= nil then
		barCorners = scope:own(core:memo(function(use)
			local fallback = readValue(uniformCorners, use)
			local list = readValue(spec.segmentCorners, use)
			if type(list) ~= "table" then
				return fallback
			end
			local value = readValue(spec.selected, use)
			for i, segment in segmentsNow(use) do
				if segment.value == value then
					return (list :: any)[i] or fallback
				end
			end
			return fallback
		end))
	end
	-- `barSurface` is declared above `skinOpts` (the carved-border rule reads its
	-- slot); the decision it records is this paragraph's.
	local bar = UI.Box({
		id = "Bar",
		surface = barSurface,
		tint = if barSurface == nil then UNDERLINE_TINT else nil,
		anchor = "topLeft",
		offsetX = offX,
		offsetY = offY,
		width = widthDim,
		height = heightDim,
		hidden = hiddenMemo,
		corners = barCorners,
	})
	if barHint ~= nil then
		bar = chrome_slots.attachHint(bar, { slot = barHint })
	end
	-- the layer fills the wrapper so its own solved rect IS the space the offsets
	-- are spent in; the bar is anchored `topLeft` inside it
	local layer = UI.Anchor({
		id = "Layer",
		width = { type = "fill", weight = 1 },
		height = { type = "fill", weight = 1 },
		children = { bar },
	})
	-- LAYER FIRST: ZIndexBehavior is Sibling, so a later sibling paints on top.
	-- The decoration therefore sits BEHIND the strip and can never intercept a
	-- gesture meant for a segment (a GuiButton sinks input; the layer must never
	-- be the thing above it).
	--[[ `plate` is a blueprint drawn BENEATH the bar — the segmented control's
		track (picker, 2026-09-11). It is the caller's node, so it lands at
		`<id>/<plate id>` and no segment path moves; the bar's Layer keeps its own
		host, so the geometry it is fed is unchanged. ]]
	local root = UI.ZStack({
		id = id,
		width = spec.width,
		height = spec.height,
		children = if spec.plate ~= nil then { spec.plate, layer, spec.content } else { layer, spec.content },
	})

	-- ===== geometry intake ==================================================
	local segmentPaths: { [number]: string } = {}
	local layerPath: string? = nil
	local resolvedCount = 0
	-- WHERE THE WRAPPER WAS MOUNTED LAST TIME (found by D5). The paths below are
	-- learned by walking the mounted tree, and a consumer may RE-HOME the wrapper:
	-- D5's TabView moves its strip between four `When`-gated homes as
	-- `adaptive.navPlacement` changes, and every reference shell does the same by
	-- hand. Learning them exactly once left `rectOf` answering nil for a path that
	-- no longer exists, `syncGeometry` returning early, and the bar frozen at the
	-- rect it held before the rotation — a chip painted where nobody measured.
	-- Comparing the ROOT's path is the cheap, exact test for "this is a different
	-- mount", and it costs one string compare per solve on the unchanged path.
	local mountedRootPath: string? = nil
	local controller, learnedRoot, learnedSegments, learnedStructure, fedEpoch, fedReader
	-- flat numeric table: 1..4 = the layer's rect, then 4 per segment in
	-- declaration order. FLAT on purpose — `sameGeometry` refuses nested tables,
	-- and a flat shape makes that refusal free rather than an obstacle.
	local fed = scope:own(core:signal({}, sameGeometry))

	-- Identity and geometry must describe the SAME solve. A live reorder cannot
	-- interpret the previous rectangles using the new option indices.
	local fedSegments = segmentsNow()
	local orderVersion = 0
	local function indexOfValue(value: any): number?
		for i, segment in fedSegments do
			if segment.value == value then
				return i
			end
		end
		return nil
	end

	-- HOW OFTEN THE FED GEOMETRY ACTUALLY MOVED. An observer, so it counts
	-- NOTIFICATIONS rather than feeds: it is the instrument that makes the
	-- by-value guard on `fed` observable, and the number a bug report about a
	-- swimming bar or a per-frame re-solve wants first. Ten idle refreshes must
	-- leave it where it was.
	local geometryUpdates = 0
	scope:own(core:observe(fed, function()
		geometryUpdates += 1
	end))

	local targetRect = scope:own(core:memo(function(use)
		local numbers = use(fed)
		local index = indexOfValue(readValue(spec.selected, use))
		if index == nil or numbers[1] == nil then
			return nil
		end
		local base = 4 * index + 1
		if numbers[base] == nil then
			return nil
		end
		return selection_indicator.resolveIndicatorRect(
			{ x = numbers[base], y = numbers[base + 1], w = numbers[base + 2], h = numbers[base + 3] },
			{ x = numbers[1], y = numbers[2], w = numbers[3], h = numbers[4] },
			use(skinOpts)
		)
	end, sameGeometry))

	-- ===== motion ===========================================================
	local motionClock: any = nil
	local motionClassName = spec.motionClass or "object"
	local springs: any = nil

	local function ensureSprings()
		if springs ~= nil or motionClock == nil then
			return
		end
		local made = {
			x = scope:own(motionClock:spring(offX:get(), motionClassName)),
			y = scope:own(motionClock:spring(offY:get(), motionClassName)),
			w = scope:own(motionClock:spring(boxW:get(), motionClassName)),
			h = scope:own(motionClock:spring(boxH:get(), motionClassName)),
		}
		springs = made
		scope:own(core:observe(made.x, function()
			offX:set(made.x:get())
		end))
		scope:own(core:observe(made.y, function()
			offY:set(made.y:get())
		end))
		scope:own(core:observe(made.w, function()
			boxW:set(made.w:get())
		end))
		scope:own(core:observe(made.h, function()
			boxH:set(made.h:get())
		end))
	end

	local function placeAt(rect: Rect)
		offX:set(rect.x)
		offY:set(rect.y)
		boxW:set(rect.w)
		boxH:set(rect.h)
		if springs ~= nil then
			springs.x:snap(rect.x)
			springs.y:snap(rect.y)
			springs.w:snap(rect.w)
			springs.h:snap(rect.h)
		end
	end

	local function slideTo(rect: Rect)
		if motionClock == nil then
			placeAt(rect) -- no presenter, no clock: an instant placement (supported)
			return
		end
		ensureSprings()
		-- Under reduced motion each of these places the value at its terminus on
		-- this very frame and fires the same settle event (motion I-4). There is
		-- no branch here on purpose: the authority owns that decision.
		springs.x:setTarget(rect.x)
		springs.y:setTarget(rect.y)
		springs.w:setTarget(rect.w)
		springs.h:setTarget(rect.h)
	end

	local placed = false
	local lastValue: any = nil
	local haveLastValue = false
	local transitions = 0
	local slides = 0

	local function applyTarget()
		local rect = targetRect:get()
		if rect == nil then
			shown:set(false)
			return
		end
		local value = readValue(spec.selected)
		local changed = haveLastValue and value ~= lastValue
		local mode = selection_indicator.resolveTransition(placed, changed)
		lastValue = value
		haveLastValue = true
		transitions += 1
		if mode == "slide" then
			slides += 1
			slideTo(rect)
		else
			placeAt(rect)
		end
		placed = true
		shown:set(true)
	end

	scope:own(core:observe(targetRect, applyTarget))

	local built = contribution.attach(root, {
		-- SOLVED RECTS, ON THE ARRANGE CADENCE. Idempotent and equality-guarded
		-- (the presenter feeds every contribution on every solve AND every
		-- refresh, and states that every syncGeometry in the framework must be
		-- both) — the `fed` signal's by-value equality is what makes it so.
		bindController = function(c)
			controller = c
			fedEpoch = nil
		end,
		syncGeometry = function(rectOf: (string) -> any, rootNode: any?)
			local segments = segmentsNow()
			local structure = if controller then controller.structureEpoch() else nil
			local geometry = if controller then controller.geometryEpoch() else nil
			local relearn = rootNode ~= learnedRoot
				or segments ~= learnedSegments
				or structure ~= learnedStructure
				or (liveSegments and not controller)
			if not relearn and geometry ~= nil and fedEpoch == geometry and fedReader == rectOf then
				return
			end
			if rootNode ~= nil and (relearn or rootNode.path ~= mountedRootPath) then
				learnedRoot, learnedSegments, learnedStructure = rootNode, segments, structure
				-- a DIFFERENT mount: forget everything learned about the old one
				-- rather than keeping half of it, which is how a re-home would
				-- otherwise leave the layer resolved and the segments dangling
				mountedRootPath = rootNode.path
				layerPath = nil
				segmentPaths = {}
				resolvedCount = 0
			end
			if rootNode ~= nil and layerPath == nil then
				-- resolve by IDENTITY, walking the mounted tree, never by string
				-- arithmetic: the mounted path depends on where the consumer placed
				-- this wrapper, so guessing it is the assumption that breaks silently
				local wanted: { [string]: number } = {}
				for i, segment in segmentsNow() do
					wanted[segment.id] = i
				end
				local function walk(node: any)
					if node.id == "Layer" and node.class == "Anchor" and layerPath == nil then
						layerPath = node.path
					end
					local index = wanted[node.id]
					if index ~= nil and segmentPaths[index] == nil then
						segmentPaths[index] = node.path
						resolvedCount += 1
					end
					for _, child in node.children or {} do
						walk(child)
					end
				end
				walk(rootNode)
			end
			if layerPath == nil then
				return
			end
			local host = rectOf(layerPath)
			if host == nil then
				return
			end
			local numbers: { number } = { host.x, host.y, host.w, host.h }
			for i in segmentsNow() do
				local path = segmentPaths[i]
				local rect = if path ~= nil then rectOf(path) else nil
				if rect ~= nil then
					local base = 4 * i + 1
					numbers[base], numbers[base + 1] = rect.x, rect.y
					numbers[base + 2], numbers[base + 3] = rect.w, rect.h
				end
			end
			if fedSegments ~= segments then
				fedSegments = segments
				orderVersion += 1
			end
			numbers[0] = orderVersion
			fedEpoch, fedReader = geometry, rectOf
			fed:set(numbers)
		end,
		-- the presenter's OWN motion clock, the one every surface transition and
		-- drag flight already rides (constitution §13: a control is handed it,
		-- never asked for it). Absent is a supported degradation — see slideTo.
		bindMotion = function(clock: any)
			motionClock = clock
		end,
	})

	local api = {}
	api.blueprint = built
	-- the live indicator rect, in the layer's own space. Published because D5's
	-- autoscroll and D6's vertical rail both need to know where the bar IS, and
	-- re-deriving it from the strip by hand is how two consumers drift apart.
	api.rect = targetRect

	--[[ NOT a `dump()`. This seam is internal (see the header), so its state is
		reported INSIDE the consuming control's dump — `picker.dump().indicator` is
		exactly this table — rather than carrying a second schema string a bug
		report would have to be taught to look for. ]]
	function api.state()
		local unresolved: { string } = {}
		for i, segment in segmentsNow() do
			if segmentPaths[i] == nil then
				table.insert(unresolved, segment.id)
			end
		end
		local rect = targetRect:get()
		local current = readValue(spec.selected)
		local label: string? = nil
		for _, segment in segmentsNow() do
			if segment.value == current then
				label = segment.id
			end
		end
		return {
			id = id,
			skin = skin,
			axis = axisNow(),
			segments = #segmentsNow(),
			resolved = resolvedCount,
			unresolved = unresolved,
			selectedId = label,
			placed = placed,
			transitions = transitions,
			slides = slides,
			geometryUpdates = geometryUpdates,
			animated = motionClock ~= nil,
			-- is the fill painting a fallback corner RIGHT NOW, because no live
			-- style answers the token it derived (`derivedCorners`)? Present
			-- tense, and at most 1 (a fill has one corner). A theme swapped away
			-- from the package that publishes the container reads 1 while it is
			-- away and 0 when the package returns; a typo on a REACTIVE
			-- `stripCorner` — the one `newPicker` cannot see at build — stays at
			-- 1 until the value is corrected. Zero is the ordinary reading.
			cornerFallbacks = cornerFallbacks,
			rect = if rect == nil then nil else { x = rect.x, y = rect.y, w = rect.w, h = rect.h },
			semanticText = `{skin} indicator on {label or "nothing"} ({resolvedCount}/{#segmentsNow()} segments resolved)`,
		}
	end

	function api.dispose()
		scope:dispose()
	end

	return api
end

return selection_indicator
