--!strict
--[[ composition_resolve — THE SOLVER'S HALF OF A `UI.Composition`.

	Public interface, one entry point and one record:

	  `compositionResolve.resolve(deps, ctx, node, innerW, innerH) -> resolution?`
	      the per-box resolution `measure` and `arrange` both read, cached on
	      `ctx.compositions` and keyed by the box.

	`compositionResolve.Deps` is what it needs from the solver: `measure`, and
	nothing else. Everything else it reads arrives on the per-solve `ctx` (the
	metrics snapshot, the diagnostics channel, the hidden depth, the cache) or
	comes from its own two requires — `./composition`, the PURE decision, and
	`./expand_plate`, the plate's own chrome.

	WHY IT IS ITS OWN FILE. `docs/handoff/SOURCE_CAP_LEDGER.md`'s solver row names
	this block by name as the next seam and states the condition on taking it:
	*"`chosenCandidate` + the composition resolution (~12 KB) read `ctx.fitProbe`,
	`ctx.fitCuts`, `ctx.compositions` and `ctx.metrics` AND call `measure` back, so
	moving either creates a require cycle rather than a seam unless `measure`
	travels as a Dep the way `FLOW_DEPS` now proves is cheap"*. That is exactly what
	this is: `measure` travels as a Dep, the four `ctx` reads travel on the `ctx`
	that was already a parameter, and the require goes one way. The block reads and
	writes NO mutable upvalue of the solver — the one-way test this library decides
	every split by — so the move takes no state with it and cannot require back.

	`ctx` AND `node` ARE TYPED `any` ON PURPOSE, the way `./shrink`, `./grid`,
	`./flow` and `./measure_facts` type them: the solver requires THIS module, so
	importing `solver.Ctx`/`solver.Node` back would be the require cycle the split
	exists to avoid, and re-declaring either schema here is the copy-goes-stale
	failure the seam is for.
]]

-- the PURE declared-content composition decision. This module supplies
-- the measurements and consumes the rects; the ranking, the step-down/drop order
-- and the arrangement choice live there, where a headless sweep can drive them
-- with no tree at all.
local compositionLib = require("./composition")
-- the expand plate's chrome, declared once beside the padding `blueprint` writes
-- on the plate; resolved into the composition's resolve context below
local expandPlate = require("./expand_plate")

local compositionResolve = {}

local function finite(v: any): number?
	return if type(v) == "number" and v == v and v > -math.huge and v < math.huge then v else nil
end

--[[ WINDOW-SPACE RECTS, IN THE COMPOSITION'S OWN BOX. A malformed entry is
	SKIPPED rather than clamped to zero: a rect with no width is not an exclusion,
	and a zero-width one at the origin would exclude the first column of every
	lane. Same refuse-don't-guess rule the env fact's own merge applies. ]]
local function localRects(
	rects: { any },
	originX: number,
	originY: number
): { { x: number, y: number, w: number, h: number } }
	local out: { { x: number, y: number, w: number, h: number } } = {}
	for _, r in rects do
		if type(r) ~= "table" then
			continue
		end
		local x, y = finite((r :: any).x), finite((r :: any).y)
		local w, h = finite((r :: any).w), finite((r :: any).h)
		if x == nil or y == nil or w == nil or h == nil or w <= 0 or h <= 0 then
			continue
		end
		table.insert(out, { x = x - originX, y = y - originY, w = w, h = h })
	end
	return out
end

-- the platform band as the composition sees it: where the free strip is across
-- this box, how tall the row that reaches its bottom edge is, and the whole
-- reservation a composition owes when it declares no `topbar` region at all
local function localBand(ctx: any, originX: number, originY: number): any
	local fullTop = finite(ctx.rootBandFullTop) or 0
	local reserve = math.max(0, fullTop - originY)
	local band = ctx.rootBand
	if type(band) ~= "table" then
		return { x = 0, w = 0, h = 0, reserve = reserve }
	end
	local bx, by = finite((band :: any).x), finite((band :: any).y)
	local bw, bh = finite((band :: any).w), finite((band :: any).h)
	if bx == nil or by == nil or bw == nil or bh == nil or bw <= 0 or bh <= 0 then
		return { x = 0, w = 0, h = 0, reserve = reserve }
	end
	return { x = bx - originX, w = bw, h = math.max(0, by + bh - originY), reserve = reserve }
end

-- WHAT THIS MODULE NEEDS FROM THE SOLVER, handed over rather than captured: the
-- mutually recursive `measure`, which a region's form is measured through. It is
-- the same forwarder shape `GRID_DEPS` / `FLOW_DEPS` already carry.
export type Deps = {
	measure: (ctx: SolveCtx, node: any, maxW: number, maxH: number) -> (number, number),
}

--[[ WHAT IT READS OFF THE SOLVE'S OWN `ctx`, DECLARED HERE.

	Nothing hands these over one by one — the whole `ctx` crosses — so a rename on
	the solver's side would be a silent `nil` rather than a missing argument. The
	four names below are the whole surface, and `tests/composition_resolve_seam.spec.luau`
	compares them three ways: READ (what the source touches) == DECLARED (this
	block) and DECLARED subset of HOSTED (the solver's own `type Ctx`). A field
	read and not declared is a runtime `nil`; a field declared and read nowhere is
	a fact the solve is still computing for nobody.

	ONE of the four is WRITTEN through — `compositions`, the per-box resolution
	cache — and that is the shared write surface the seam spec pins at exactly one
	name. A second name here would mean a value this module decided has quietly
	become state with two owners.
]]
export type SolveCtx = {
	-- node id -> `{ key, resolution }`, the per-box cache measure and arrange
	-- both read so they can never get different answers (written)
	compositions: { [string]: any },
	-- the solve's findings channel: a child of a Composition that is not a Region
	-- is reported here (written through, appended)
	diagnostics: { any },
	-- >0 while the walk is inside a subtree nothing paints, which is what silences
	-- an authoring diagnostic about a screen the player cannot see (read only)
	hiddenDepth: number,
	-- the active ThemeSnapshot: a content floor's line box and the expand plate's
	-- own chrome are resolved from it, so the NAME never crosses into the pure
	-- composition module (read only)
	metrics: any,
	--[[ THE SURFACE'S OWN BOX AND THE PLATFORM BAND ABOVE IT (§9/§8),
		all three read only. They are what turns a WINDOW-space rect — which is the
		space `platformChrome` states its band and its rects in, and the space this
		solver's own output is in — into the local box a PURE composition can reason
		about. `rootRect` is the content rect the policy resolved; `rootBand` is the
		free strip; `rootBandFullTop` is the window y the platform's whole top
		reservation ends at. All three nil-safe. ]]
	rootRect: any,
	rootBand: any,
	rootBandFullTop: number?,
}

-- THE COMPOSITION RESOLUTION, COMPUTED ONCE PER BOX.
--
-- Measure and arrange both need it, and they must never get different answers —
-- reserving a box for `threeLane` and then arranging `column` inside it is the
-- exact measure-versus-paint disagreement this solver has had to fix four times
-- (ViewThatFits' candidate, the compact ladder, the uniform Grid cell, the
-- container offer). So it is cached on the CONTEXT, keyed by the box, and the
-- cache dies with the solve.
--
-- An UNBOUNDED axis (a composition inside a scrolling region) cannot adapt on
-- that axis — there is no offer to be short of. It is resolved twice: once
-- against a large finite box to learn the natural extent, then against that
-- extent, which is what `hug` means everywhere else in this file.
local COMPOSITION_UNBOUNDED = 1e6
function compositionResolve.resolve(
	deps: Deps,
	ctx: SolveCtx,
	node: any,
	innerW: number,
	innerH: number,
	originX: number?,
	originY: number?
): any?
	local declared = node.composition
	if declared == nil then
		return nil
	end
	--[[ WHERE THIS COMPOSITION IS, AND WHAT IT DOES WITH THAT (§9/§8).

		Both window-space inputs — the platform band and the author's `exclusions` —
		have to be expressed in the composition's OWN box before a pure module can
		spend them. `arrange` knows the origin and passes it; `measure` does not
		exist at a position at all, so it falls back to the surface's content origin.

		THAT FALLBACK IS EXACT FOR THE CASE THAT MATTERS AND CONSERVATIVE OTHERWISE.
		A composition that fills its surface — which is every band-riding surface and
		every HUD — IS at the content origin, so both passes agree and the cache key
		below is the same string for both: one resolution, no extra work. A
		composition placed lower down measures against an origin ABOVE its own, which
		over-states an exclusion's reach rather than under-stating it, so a `hug`
		height reserves at least enough; `arrange` then re-resolves at the true
		origin and the rects that ship are exact.

		THE ORIGIN JOINS THE CACHE KEY, and only when something reads it. Without
		that, an arrange whose box happened to equal the measure's would hand back
		the measure-time resolution and the exclusions would silently not apply —
		the cache returning an answer computed against a different ruler, which is
		the defect family this file's own header names. ]]
	local placedX = if originX ~= nil then originX else (if type(ctx.rootRect) == "table" then ctx.rootRect.x else 0)
	local placedY = if originY ~= nil then originY else (if type(ctx.rootRect) == "table" then ctx.rootRect.y else 0)
	local exclusions = declared.exclusions
	local hasExclusions = type(exclusions) == "table" and #(exclusions :: any) > 0
	--[[ THE BAND IS THE SURFACE'S, NOT A NODE'S, so only a composition sitting at
		the surface's own content origin may ride it. A nested one is somewhere else
		on the screen and reserving the platform's row inside it would be reserving
		it twice; it is left exactly as it was. ]]
	local atRoot = type(ctx.rootRect) == "table" and placedY == ctx.rootRect.y
	local hasBand = atRoot and type(ctx.rootBandFullTop) == "number"
	local key = if hasExclusions or hasBand then `{innerW}|{innerH}|{placedX},{placedY}` else `{innerW}|{innerH}`
	local cached = ctx.compositions[node.id]
	if cached ~= nil and cached.key == key then
		return cached.resolution
	end

	local byId: { [string]: any } = {}
	-- wave REVEAL: per region, the affordance node (or nil) and the FORM count the
	-- ladder may use. Built in the same walk, read by the measure closure below.
	local expandFor: { [string]: { node: any?, forms: number } } = {}
	local regions = {}
	for _, child in node.children or {} do
		local r = child.region
		if r == nil then
			if ctx.hiddenDepth == 0 then
				table.insert(ctx.diagnostics, {
					node = child.id,
					issue = "every child of a Composition must be a UI.Region — this one is not, so it "
						.. "carries no rank, no forms and no floor, and the composition cannot place it",
				})
			end
			continue
		end
		byId[child.id] = child
		--[[ WAVE REVEAL. The region's children are its FORMS plus, when it collapses,
			ONE expand affordance appended last. The ladder must not step onto that
			button, so the count it is given excludes it — and the affordance is found
			by its own declaration (`expandTarget`) rather than by position, because a
			form declared behind a `UI.When` splices itself out of this list and an
			index would then name the wrong node. ]]
		local kids = child.children or {}
		local affordance = if #kids > 0 and kids[#kids].expandTarget ~= nil then kids[#kids] else nil
		local formCount = math.max(1, #kids - (if affordance ~= nil then 1 else 0))
		expandFor[child.id] = { node = affordance, forms = formCount }
		--[[ ...AND THE INTERACTIVITY ARRAY IS INDEXED BY THE DECLARED FORM while this
			count is of the MOUNTED ones. When they agree the declaration's own answer
			is used verbatim; when a `UI.When` has spliced a form away they cannot be
			aligned, so every form falls back to the affordance's ROLE — the
			conservative answer the construction pass already computed across the whole
			ladder ("never overload a control"). A wrong index would report a live
			control as a passive box, which is the one mistake this fact exists to
			prevent. ]]
		local record = r.expand
		local interactive: { boolean }? = nil
		if record ~= nil then
			if record.forms == formCount then
				interactive = record.interactive
			else
				interactive = {}
				for i = 1, formCount do
					(interactive :: { boolean })[i] = record.role == "chevron"
				end
			end
		end
		table.insert(regions, {
			id = child.id,
			group = r.group,
			rank = r.rank,
			forms = formCount,
			expand = if record ~= nil then record.mode else nil,
			formInteractive = interactive,
			sizing = r.sizing,
			weight = r.weight,
			floor = r.floor,
			mayScroll = r.mayScroll,
			mayDrop = r.mayDrop,
			reserved = r.reserved,
			recover = r.recover,
		})
	end

	--[[ A LIVE `eligible` is resolved HERE, once per solve, exactly as a live
		`reserved` reaches the region list above already resolved. The gate answers
		"is this candidate offered on THIS offer?", which is a per-solve question by
		construction — a size class changes when the window does. ]]
	local arrangements = declared.arrangements
	local anyLive = false
	for _, a in arrangements do
		if type(a) == "table" and type((a :: any).eligible) == "table" then
			anyLive = true
			break
		end
	end
	if anyLive then
		local resolved = {}
		for _, a in arrangements do
			local gate = if type(a) == "table" then (a :: any).eligible else nil
			if type(gate) == "table" and type((gate :: any).get) == "function" then
				local copy = table.clone(a :: any)
				copy.eligible = (gate :: any):get() == true
				table.insert(resolved, copy)
			else
				table.insert(resolved, a)
			end
		end
		arrangements = resolved
	end

	local decl = {
		id = node.id,
		groups = declared.groups,
		arrangements = arrangements,
		regions = regions,
		laneGap = declared.laneGap,
		groupGap = declared.groupGap,
		maxMeasure = declared.maxMeasure,
	}
	local resolveCtx = {
		measure = function(id: string, form: number, availW: number, availH: number): (number, number)
			local regionNode = byId[id]
			local forms = (if regionNode ~= nil then regionNode.children else nil) or {}
			local spec = expandFor[id]
			local count = if spec ~= nil then spec.forms else #forms
			local child = forms[math.min(form, count)]
			--[[ THE AFFORDANCE IS NEVER A FORM, and this identity test is what says so
				in the one state a count cannot: a region whose EVERY form is behind a
				`UI.When` that reads false has spliced them all away, leaving the
				affordance as the only child — and measuring THAT would hold open a
				region rule 9 exists to release (the composition showcase's `Callout`,
				which is exactly this shape). An empty region is absent, affordance and
				all: there is nothing to disclose. ]]
			if child == nil or (spec ~= nil and child == spec.node) then
				return 0, 0
			end
			--[[ A CHEVRON IS RESERVED, NEVER OVERLAID (wave REVEAL). When a reduced
				form carries controls of its own the affordance sits BESIDE it, so the
				region needs room for both — and the ladder has to know that before it
				chooses a rung, or a form would be picked on a width it does not have.
				A "cover" affordance reserves nothing: it is the form's own box. ]]
			local mark = if spec ~= nil then spec.node else nil
			if mark ~= nil and form > 1 and mark.expandTarget.role == "chevron" then
				local mw, mh = deps.measure(ctx, mark, availW, availH)
				local w, h = deps.measure(ctx, child, math.max(0, availW - mw), availH)
				--[[ AN EMPTY FORM RESERVES NOTHING. Rule 9 releases a region whose
					content resolves to nothing paintable, and an affordance that kept the
					box open would defeat it — the reserved slot would hold a third of a
					landscape phone for a chevron pointing at nothing. Measured on the
					composition showcase, whose regions are `UI.When` forms that genuinely
					empty. There is nothing to disclose from a form that is not there. ]]
				if w <= 0 and h <= 0 then
					return 0, 0
				end
				return w + mw, math.max(h, mh)
			end
			return deps.measure(ctx, child, availW, availH)
		end,
		floorOf = function(r: any): number?
			return compositionLib.floorPx(r.floor, ctx.metrics)
		end,
		--[[ THE GUTTER AN EXPAND PLATE LEAVES on each side of the viewport (wave
			REVEAL). The composition owns no theme, so the NUMBER is resolved here from
			the live snapshot and the NAME never crosses the boundary — the same split
			`floorOf` makes for a content floor. ]]
		expandGutter = (ctx.metrics.space :: any).m,
		--[[ ...AND THE PLATE'S OWN CHROME, which is the half the gutter could not
			say (DIR5 item 3, contested there and closed here). The gutter is what the
			plate leaves at the SCREEN edges; this is what the plate spends on ITSELF
			— two insets, one of them the close disc's reserve, plus the straddle the
			disc sits half-out on. Without it the composition measured form 1 against
			the whole allowance and handed back a plate that, once wrapped, was wider
			than the allowance it had just been chosen against.

			TWO NUMBERS, BECAUSE THEY SIT ON OPPOSITE SIDES OF THE BOX the caller
			declares: the inset is inside it (content = box - inset) and the straddle
			is outside it (panel = box + straddle). One combined number silently
			mis-sizes whichever of hug/fill it was not derived for.

			SAME SPLIT AS `expandGutter` AND `floorOf` ONE LINE UP: the composition
			owns no theme, so the NUMBERS are resolved here from the live snapshot and
			the NAMES never cross. They live in `./expand_plate` beside the padding
			`blueprint` actually writes on the plate, so the cap and the box cannot be
			two readings of one intention. ]]
		expandPlateInset = expandPlate.insetX(ctx.metrics),
		expandPlateStraddle = expandPlate.straddleX(ctx.metrics),
		--[[ ...AND THE ONE NUMBER THE DECLARATION CANNOT SPELL (plate design B).
			The metric vocabulary sums names and negates them; it cannot HALVE one,
			and half the disc is exactly the offset a disc CENTRED ON A CORNER sits
			at. It rides back out on the plate record beside `max`, so the
			declaration spends the same resolution the cap above reserved. ]]
		expandPlateDiscHalf = expandPlate.discHalf(ctx.metrics),
		--[[ THE TWO WINDOW-SPACE FACTS, CONVERTED (§9 + §8). Same split every other
			line of this record makes: the composition owns no env and no window, so
			the NUMBERS arrive already in its own box and the SPACE never crosses.

			`exclusions` — the rects a solved lane may not start inside. The author
			states them where they are (`platformChrome.rects`, an app's own declared
			chrome row); this is the one place that can subtract the composition's
			origin from them.

			`band` — the platform's free strip, plus the `reserve` the composition owes
			the platform's whole row when nothing declares a `topbar` region. `h` is
			measured to the band's own bottom and `reserve` to the reservation's, and
			they differ on a device whose device-safe top is deeper than the CoreGui
			one; both are floored at 0 so a band above the content rect never becomes
			a negative row. ]]
		exclusions = if hasExclusions then localRects(exclusions :: any, placedX, placedY) else nil,
		band = if hasBand then localBand(ctx, placedX, placedY) else nil,
	}
	local offerW = if innerW == math.huge then COMPOSITION_UNBOUNDED else innerW
	local offerH = if innerH == math.huge then COMPOSITION_UNBOUNDED else innerH
	local resolution = compositionLib.resolve(decl, { w = offerW, h = offerH }, resolveCtx)
	if innerW == math.huge or innerH == math.huge then
		resolution = compositionLib.resolve(decl, {
			w = if innerW == math.huge then resolution.used.w else offerW,
			h = if innerH == math.huge then resolution.used.h else offerH,
		}, resolveCtx)
	end
	ctx.compositions[node.id] = { key = key, resolution = resolution }
	return resolution
end

return compositionResolve
