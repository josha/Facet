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

local selection_indicator = {}

export type Segment = { value: any, id: string }

export type Spec = {
	id: string?,
	content: any, -- the strip blueprint this indicator tracks (required)
	segments: { Segment }, -- (selection value, child id) pairs (required)
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
	corner: any?, -- corner radius token/number ("pill" by default on the pill skin)
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

-- THEME METRICS (ADR-0019 §2; brief §3 "themed off existing tokens"). Both
-- numbers are small distances the theme's own SPACING scale already owns, so
-- neither needs a new control family — a package published before this module
-- existed answers both, and a theme that retunes its spacing retunes the
-- indicator with it. A caller may pass any other metric name (or a number) per
-- skin.
local DEFAULT_THICKNESS = "space.xs"
local DEFAULT_INSET = "space.xs"
-- the chip's rounding. `radii.pill` is the theme's own "fully rounded" role, and
-- an underline stays square by default because that is what r2 and f1 draw.
local DEFAULT_PILL_CORNER = "pill"

-- CLOSED SPEC (constitution §4). An unknown key is an authoring
-- mistake, never a silent no-op.
local INDICATOR_KEYS = specGuard.keySet({
	"axis",
	"content",
	"corner",
	"env",
	"id",
	"inset",
	"motionClass",
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
	if type(spec.segments) ~= "table" or #spec.segments == 0 then
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
	for i, segment in spec.segments do
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
		return if type(raw) == "table" and type(raw.controls) == "table" then raw else themeSnapshot.neutral()
	end))
	local skinOpts = scope:own(core:memo(function(use)
		local snap = use(metricsSig)
		return {
			skin = skin,
			axis = axisNow(use),
			thickness = themeSnapshot.resolveNumber(snap, spec.thickness or DEFAULT_THICKNESS) or 0,
			inset = themeSnapshot.resolveNumber(snap, spec.inset or DEFAULT_INSET) or 0,
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

	--[[ A CHIP IS A SURFACE; A RULE IS A STROKE OF COLOUR (found by D5's theme
		sweep, and it is a real defect the pill skin could never show). The bar was
		declared `surface = "accent"` for both skins. That is right for the PILL —
		a ~40px chip has room for a themed control chrome's borders and insets —
		and wrong for the UNDERLINE, which is `space.xs` deep: every themed package
		in the sweep filed "the 'control' chrome contentInsets could not be spent
		on y: 20px of border on a 4px height", eighty-odd times across the matrix,
		because a 4px box cannot wear a control's chrome.

		`tint` is what a thin themed rule is painted with — a continuous colour
		blended between two theme roles, no chrome, still fully themable — and it
		is the idiom `p4_foyer`'s own hand-rolled 3px active bar already used
		before this seam replaced it. `spec.surface` still overrides, on either
		skin, for a caller that wants the plate. ]]
	local UNDERLINE_TINT = table.freeze({ role = "accent", blend = 1 })
	local barSurface = if spec.surface ~= nil then spec.surface elseif skin == "pill" then "accent" else nil
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
	})
	local corner = spec.corner or (if skin == "pill" then DEFAULT_PILL_CORNER else nil)
	if corner ~= nil then
		bar = UI.corners(bar, corner)
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
	local root = UI.ZStack({
		id = id,
		width = spec.width,
		height = spec.height,
		children = { layer, spec.content },
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
	-- flat numeric table: 1..4 = the layer's rect, then 4 per segment in
	-- declaration order. FLAT on purpose — `sameGeometry` refuses nested tables,
	-- and a flat shape makes that refusal free rather than an obstacle.
	local fed = scope:own(core:signal({}, sameGeometry))

	local function indexOfValue(value: any): number?
		for i, segment in spec.segments do
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
		syncGeometry = function(rectOf: (string) -> any, rootNode: any?)
			if rootNode ~= nil and rootNode.path ~= mountedRootPath then
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
				for i, segment in spec.segments do
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
			for i in spec.segments do
				local path = segmentPaths[i]
				local rect = if path ~= nil then rectOf(path) else nil
				if rect ~= nil then
					local base = 4 * i + 1
					numbers[base], numbers[base + 1] = rect.x, rect.y
					numbers[base + 2], numbers[base + 3] = rect.w, rect.h
				end
			end
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
		for i, segment in spec.segments do
			if segmentPaths[i] == nil then
				table.insert(unresolved, segment.id)
			end
		end
		local rect = targetRect:get()
		local current = readValue(spec.selected)
		local label: string? = nil
		for _, segment in spec.segments do
			if segment.value == current then
				label = segment.id
			end
		end
		return {
			id = id,
			skin = skin,
			axis = axisNow(),
			segments = #spec.segments,
			resolved = resolvedCount,
			unresolved = unresolved,
			selectedId = label,
			placed = placed,
			transitions = transitions,
			slides = slides,
			geometryUpdates = geometryUpdates,
			animated = motionClock ~= nil,
			rect = if rect == nil then nil else { x = rect.x, y = rect.y, w = rect.w, h = rect.h },
			semanticText = `{skin} indicator on {label or "nothing"} ({resolvedCount}/{#spec.segments} segments resolved)`,
		}
	end

	function api.dispose()
		scope:dispose()
	end

	return api
end

return selection_indicator
