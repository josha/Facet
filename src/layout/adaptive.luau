--!strict
-- Adaptive-layout decisions (docs/plans/parity-next.md investment 5;
-- acceptance rows A-AL2/A-AL3).
--
-- Exposing size facts was not enough to deliver write-once UI: every screen
-- still had to branch by hand, and the tempting shape for that branch is a
-- device name. The plan's rule is explicit — adaptation comes from available
-- space, viewing distance, live interaction classes and accessibility facts;
-- "phone", "Xbox" and "VR" must not appear as screen-level layout branches.
--
-- This module is the seam that makes the correct branch the easy one. It has
-- two halves:
--
--   * PURE decisions (sizeClass / axisFor / columnsFor) — plain functions over
--     numbers, so they are deterministic, headlessly testable, and usable by the
--     solver and by tooling with no DataModel and no reactive core.
--   * REACTIVE conditions (adaptive.conditions) — the same decisions as
--     Readables over the environment, so a screen BINDS them (no remount) and a
--     viewport, orientation or display-class change re-resolves in place.
--
-- Container-relative conditions: everything above `adaptive.fits` is
-- VIEWPORT-relative. A decision that must depend on the space a PARTICULAR
-- container got has two shapes here, and they are the same predicate:
--   * `UI.ViewThatFits` when the answer is a SUBTREE — the solver measures each
--     candidate against the space that container was proposed;
--   * `adaptive.fitsIn` / `adaptive.fits` when the answer is a VALUE — the same
--     comparison the ladder makes, as a plain function and as a Readable, for a
--     consumer that must reserve space in a sibling or skip a whole surface
--     before either arrangement is built.

local specGuard = require("../spec_guard")

local adaptive = {}

-- These are THE breakpoints. `src/env/environment.luau`'s `sizeClass` memo calls
-- `adaptive.sizeClass` rather than re-comparing literals, and the reactive half
-- below delegates to that memo — so there is exactly one implementation of both
-- the thresholds and the ten-foot density cap. (Verifier finding V15: the env memo
-- previously duplicated 600/1000 as literals, which made an earlier version of this
-- comment aspirational rather than true.)
adaptive.BREAKPOINTS = table.freeze({ regular = 600, wide = 1000 })

-- THE HEIGHT CLASS (ADR-0023). `sizeClass` answers "how much room is there
-- ACROSS", and for a decade that was the only question a responsive UI asked,
-- because a web page scrolls forever. A game screen does not: a landscape phone
-- offers 313 px of safe height, and a composition that stacks four content bands
-- down it puts every one of them under its floor. Every screen that has met that
-- has re-derived a private threshold in its own code ("vpH < 520") and been
-- wrong on the next device.
--
-- These are THE SAME BREAKPOINTS as the width classes, deliberately. The
-- question is identical — "how much content fits along this axis" — and a second
-- set of literals would be a second thing to justify, a second thing to keep in
-- sync, and (this repo's own V15 finding) a second implementation to drift. One
-- consequence worth naming: a rotation maps a class pair onto its mirror, so
-- 733x313 is `regular` x `short` and 313x733 is `compact` x `medium`.
--
-- They are a COARSE fact for a screen that wants one. They are NOT how
-- `UI.Composition` adapts: that measures the box it actually received, which is
-- the only honest answer near a breakpoint (`viewportHeight` no more subtracts
-- safe insets than `viewportWidth` does).
adaptive.HEIGHT_BREAKPOINTS = adaptive.BREAKPOINTS

-- default axis threshold: below this a bar/row stacks vertically. Chosen to
-- match the compact/regular boundary so a screen that adapts its stack and a
-- screen that adapts its density flip at the same width.
adaptive.DEFAULT_STACK_ABOVE = 600

export type ClassOpts = {
	-- "ten-foot" caps the result at `regular`: a TV at 3 m must not resolve the
	-- densest arrangement however wide it is (input-paradigms matrix D.3)
	distanceProfile: string?,
}

local function safeWidth(w: any): number
	if type(w) ~= "number" or w ~= w then -- nil / NaN
		return 0
	end
	return math.max(0, w)
end

-- sizeClass(width, opts?) -> "compact" | "regular" | "wide"
function adaptive.sizeClass(width: number, opts: ClassOpts?): string
	local w = safeWidth(width)
	local class = if w < adaptive.BREAKPOINTS.regular
		then "compact"
		elseif w < adaptive.BREAKPOINTS.wide then "regular"
		else "wide"
	if class == "wide" and opts ~= nil and opts.distanceProfile == "ten-foot" then
		class = "regular"
	end
	return class
end

-- heightClass(height, opts?) -> "short" | "medium" | "tall"
-- The vertical sibling of `sizeClass`, with the same ten-foot cap for the same
-- reason: `tall` is the DENSEST vertical arrangement (the most bands stacked),
-- and a TV at 3 m must not resolve the densest arrangement however big it is.
function adaptive.heightClass(height: number, opts: ClassOpts?): string
	local h = safeWidth(height)
	local class = if h < adaptive.HEIGHT_BREAKPOINTS.regular
		then "short"
		elseif h < adaptive.HEIGHT_BREAKPOINTS.wide then "medium"
		else "tall"
	if class == "tall" and opts ~= nil and opts.distanceProfile == "ten-foot" then
		class = "medium"
	end
	return class
end

-- navPlacement(facts) -> "bottomBar" | "bottomBarCompact" | "topBar" | "sidebar"
-- THE app-level tab/sidebar placement policy (director ruling 2026-08-09,
-- aligned to the platform tab-bar guidance the reference apps follow):
--
--   compact width             -> "bottomBar"        a full-width tab bar in the
--                                                    thumb zone (phone portrait)
--   short height              -> "bottomBarCompact"  the SAME bottom bar in its
--                                                    reduced, inline, centered
--                                                    form (phone landscape): it
--                                                    HUGS its tabs instead of
--                                                    dividing the width. Same
--                                                    band height, same words —
--                                                    a terser name is the
--                                                    author's or the shrink
--                                                    ladder's
--   ten-foot distance         -> "topBar"            a center-aligned top tab
--                                                    bar that HUGS its content
--                                                    (never full width)
--   pointer primary           -> "sidebar"           desktop shape
--   touch + roomy SHORT SIDE  -> "topBar"            tablet shape: the same
--                                                    centered top bar. Roomy on
--                                                    BOTH axes is what separates
--                                                    a tablet from a phone, in
--                                                    either orientation
--   touch + short side < 600  -> "bottomBar"         a phone, whichever way it
--                                                    is held
--   gamepad + Small display   -> "bottomBar"         the near-distance handheld
--     (or unknown display)                           (director ruling: when we
--                                                    cannot differentiate,
--                                                    bottom tabs)
--   anything else             -> "topBar"
--
-- Deliberately a function of SHAPE, INPUT and DISPLAY facts only — the
-- reference's own rule is a device-idiom branch (`.phone`), which this
-- vocabulary bans; (size/height class, primary interaction class, engine
-- display size) reproduces the same outcomes from facts a windowed pane also
-- answers honestly. Touch alone is NOT the top-bar indicator: a touch phone and
-- a touch tablet share the class, and the SHORT SIDE is what separates them
-- (ADAPT-2 — the engine's DisplaySize cannot: it calls every tablet `Small`).
-- Pure, so the conditions memo and tests share one implementation.
export type NavPlacementFacts = {
	sizeClass: string,
	heightClass: string,
	distanceProfile: string?,
	primary: string?,
	displaySize: string?,
}
function adaptive.navPlacement(facts: NavPlacementFacts): string
	if facts.sizeClass == "compact" then
		return "bottomBar"
	end
	if facts.heightClass == "short" then
		return "bottomBarCompact"
	end
	if facts.distanceProfile == "ten-foot" then
		return "topBar"
	end
	if facts.primary == "pointer" then
		return "sidebar"
	end
	if facts.primary == "touch" then
		--[[ THE TABLET TEST IS THE SHORT SIDE (audit 2026-08-18).

			This asked the engine's DisplaySize, and the engine cannot answer it:
			Roblox documents `Enum.DisplaySize.Small` as "Most tablet/mobile/handheld
			devices", so every real tablet reported `Small` and took the PHONE bottom
			bar, while the tablet branch was reachable only by a touchscreen laptop
			whose player had last touched the glass. The tablet paradigm this policy
			documents was unreachable on tablets, and the framework's own canonical
			matrix said so all along — `tests/lib/device_views.luau`'s tablet row
			declares `displaySize = "Small"`, correctly, which is what made it
			invisible.

			The discriminator that holds in BOTH orientations is the short side
			against the SAME 600px breakpoint the size classes already use: every
			phone is under it whichever way it is held (390x844 and 844x390 alike),
			every tablet is over it (1079x809 and 810x1080 alike). The intuitive
			version — "a tablet is `sizeClass == "wide"`" — fails a PORTRAIT tablet,
			which is 768-810px wide and therefore lands in `regular` beside a
			landscape phone.

			It reads as two class comparisons rather than a `min(w, h)` because the
			classes ARE that measurement, one axis each, against that same constant:
			a compact width is a short side under 600 in portrait, a short height is
			a short side under 600 in landscape. Both of those cases have already
			returned above, which is the whole reason the rule can be stated here
			without the raw numbers — and stating it explicitly is what keeps the
			next reader from re-deriving it as "touch always tops out". ]]
		local shortSideIsRoomy = facts.sizeClass ~= "compact" and facts.heightClass ~= "short"
		return if shortSideIsRoomy then "topBar" else "bottomBar"
	end
	if facts.primary == "gamepad" then
		-- the NEAR-DISTANCE gamepad handheld keeps the display-fact rule and the
		-- director refinement behind it ("Small and joystick can vary — bottom tabs
		-- are ok there"): a pad in the hands is not a tablet in the hands, and
		-- nothing in the adaptation audit measured one. A ten-foot pad never reaches
		-- here
		-- (caught above).
		local d = facts.displaySize
		return if d == "Medium" or d == "Large" then "topBar" else "bottomBar"
	end
	return "topBar"
end

-- orientationFor(width, height) -> "landscape" | "portrait" | "square"
-- A shape fact, not a device fact: a windowed pane on a desktop is portrait and
-- must be treated as one.
function adaptive.orientationFor(width: number, height: number): string
	local w, h = safeWidth(width), safeWidth(height)
	if w > h then
		return "landscape"
	elseif h > w then
		return "portrait"
	end
	return "square"
end

export type AxisOpts = {
	stackAbove: number?, -- width at or above which the axis becomes "x"
}

-- axisFor(width, opts?) -> "y" | "x". The decision an AdaptiveStack binds.
function adaptive.axisFor(width: number, opts: AxisOpts?): string
	local threshold = (opts and opts.stackAbove) or adaptive.DEFAULT_STACK_ABOVE
	return if safeWidth(width) >= threshold then "x" else "y"
end

--[[ columnsFor(available, minColumnWidth, gap, opts?) -> integer >= 1.

	The SAME arithmetic the solver's Grid uses for `minColumnWidth` — literally,
	since `src/layout/grid.luau` calls this function rather than keeping a second
	copy — exported so a screen can ask "how many columns will I get?" before
	laying anything out.

	THE TEN-FOOT CAP, AND WHY IT BELONGS HERE (audit 2026-08-18). Both
	class functions above cap at distance for a stated reason: "a TV at 3 m must
	not resolve the densest arrangement however wide it is". This one did not, so
	the framework's own documented adaptive-grid route produced ELEVEN columns on a
	television against nine on a desktop — density capped on the two functions that
	DESCRIBE and uncapped on the one that DECIDES.

	The cap is the same one, spelled with the same constant: at ten-foot the count
	is taken against `BREAKPOINTS.wide` rather than the raw extent, exactly as
	`sizeClass` answers `regular` for any width past it. The lanes still divide the
	WHOLE extent, so a television gets fewer, larger cards — which is what the rule
	was always about. No new number, and nothing to keep in sync. ]]
function adaptive.columnsFor(available: number, minColumnWidth: number, gap: number?, opts: ClassOpts?): number
	local g = if type(gap) == "number" and gap == gap then math.max(0, gap) else 0
	local minW = safeWidth(minColumnWidth)
	local avail = safeWidth(available)
	if minW <= 0 then
		return 1
	end
	if opts ~= nil and opts.distanceProfile == "ten-foot" then
		avail = math.min(avail, adaptive.BREAKPOINTS.wide)
	end
	return math.max(1, math.floor((avail + g) / (minW + g)))
end

--[[ ── THE CARD RAIL'S ARRANGEMENT (director ruling 2026-08-18) ──────
	"How many cards belong in view here" is the same KIND of question as "how many
	columns" and "which way does this bar stack", so it lives beside them: pure,
	over numbers, exported so a caller can predict it, and with the thresholds
	named ONCE rather than in whichever control asked.

	THESE ARE ARRANGEMENT FACTS, NOT THEME METRICS, which is why they are constants
	here and not entries in the theme snapshot — the same standing this module's
	`BREAKPOINTS` have. A theme decides how a card is PAINTED; how many of them a
	surface shows is a decision about the space and the way the player is driving
	it, and a package that could change it could turn a phone carousel into a
	three-up grid nobody could read. A rail that wants a different answer says so
	with `cards.perView` / `cards.minWidth`, which is an authoring decision, in the
	place authoring decisions are made.

	CARD_MIN_WIDTH is the narrowest a card may be squeezed to before the rail drops
	a lane: a two-line plate at the shipped body size, its padding, and enough width
	left that a name is not an ellipsis on arrival.

	CARD_PEEK is the sliver of the NEXT card a one-up rail shows, and it is the
	whole affordance that there IS more — the audit's own words for the carousel
	shape ("a peeking carousel whose affordance IS the half-visible next tile",
	cell B-9). Proportional so it scales with the rail, floored so a thumb reads it
	as a card edge rather than a border, capped before it starts to look like a
	second column that got cut off. ]]
adaptive.CARD_MIN_WIDTH = 200
adaptive.CARD_PEEK = table.freeze({ fraction = 0.1, min = 24, max = 56 })

--[[ ── THE CONTENT LANE'S MEASURE (B-6e, controller ruling R14, 2026-08-21) ────
	The reading width of a `Composition`'s content lane, and the same KIND of fact
	as `CARD_MIN_WIDTH` above: an arrangement decision, not a theme metric, so it
	lives here where a caller can predict it and a package cannot move it.

	WHY IT EXISTS. `sizeClass`, `heightClass` and `columnsFor` all cap at distance;
	the arrangement that decides the MEASURE did not, so a television resolved the
	DESKTOP answer with more pixels — the same `threeLane` with the main lane
	simply wider (1316px measured, against the regular-touch tablet's 600). At
	three metres that is a line nobody can track back to its own start.

	THE BASE IS THE TABLET MEASURE, which the layout paradigm matrix verified RIGHT
	at 600px (cell B-6c, regular touch, 1024x768). The ten-foot answer is that
	measure times the DISTANCE FACTOR, which is `themes.snapshot.metricScale` —
	`tenFootFloor`, the one constant ADR-0039 put behind every ten-foot number, and
	it arrives as an argument rather than being restated here. So the ruled 900 is
	600 x 1.5 with neither number written twice, and a re-ruled measure is ONE
	EDIT: this constant, or the factor, and the sweep that names it goes red.

	NIL AT NEAR DISTANCE, deliberately: this is a distance rule, and a cap that
	also fired on a wide desktop would be a WIDTH rule wearing a distance rule's
	name. Every near combo keeps the measure it has. ]]
adaptive.LANE_MEASURE = 600

-- laneMeasureFor(metricScale) -> px cap, or nil where distance asks for none.
-- `metricScale` is `themes.snapshot.metricScale(displaySize)`: 1 near, 1.5 at
-- ten-foot. Anything that is not a number above 1 means "no cap".
function adaptive.laneMeasureFor(metricScale: number?): number?
	if type(metricScale) ~= "number" or metricScale ~= metricScale or metricScale <= 1 then
		return nil
	end
	return math.floor(adaptive.LANE_MEASURE * metricScale)
end

export type CardOpts = {
	-- is TOUCH the primary way in (never merely "touch is available")
	touchPrimary: boolean?,
	-- the gutter between card slots, which the lane arithmetic has to spend
	gap: number?,
	-- the floor a lane is dropped at; defaults to CARD_MIN_WIDTH
	minWidth: number?,
	distanceProfile: string?,
}

--[[ cardsPerView(available, opts?) -> integer >= 1

	THE ONE RUNG THAT IS NOT ARITHMETIC: a compact, touch-driven surface gets ONE
	card, even when two would fit. That is the director's example stated exactly —
	"a swipeable single-view carousel on a phone" — and it is the only place the
	answer is not simply "as many as fit". Everything else asks `columnsFor`, the
	same function `UI.Grid` uses, so a rail and a grid at the same width with the
	same floor never disagree. ]]
function adaptive.cardsPerView(available: number, opts: CardOpts?): number
	local o: CardOpts = opts or {}
	local width = safeWidth(available)
	local classOpts: ClassOpts = { distanceProfile = o.distanceProfile }
	if o.touchPrimary == true and adaptive.sizeClass(width, classOpts) == "compact" then
		return 1
	end
	local minWidth = if type(o.minWidth) == "number" and (o.minWidth :: number) > 0
		then o.minWidth :: number
		else adaptive.CARD_MIN_WIDTH
	return math.max(1, adaptive.columnsFor(width, minWidth, o.gap, classOpts))
end

--[[ cardPeek(available, perView) -> px

	ZERO ABOVE ONE CARD, always: a multi-up rail already shows the next card, and
	spending a peek there would just make every card narrower for no affordance
	that was missing. ]]
function adaptive.cardPeek(available: number, perView: number): number
	if type(perView) ~= "number" or perView > 1 then
		return 0
	end
	local peek = adaptive.CARD_PEEK
	return math.clamp(math.floor(safeWidth(available) * peek.fraction), peek.min, peek.max)
end

export type Conditions = {
	sizeClass: any, -- Readable<"compact" | "regular" | "wide">
	isCompact: any, -- Readable<boolean>
	isRegular: any,
	isWide: any,
	isTenFoot: any, -- Readable<boolean> — viewing distance, NOT input class
	viewportWidth: any, -- Readable<number> — the RAW viewport width
	contentWidth: any, -- alias of viewportWidth, kept for callers; see the note below
	axis: any, -- Readable<"y" | "x">, ready to bind to UI.AdaptiveStack
	-- the height half (ADR-0023). ADDITIVE: every key above keeps its exact
	-- meaning and its exact value, so no shipped consumer re-flows.
	heightClass: any, -- Readable<"short" | "medium" | "tall">
	isShort: any, -- Readable<boolean>
	isTall: any, -- Readable<boolean> (medium height is neither)
	viewportHeight: any, -- Readable<number> — RAW, like viewportWidth
	orientation: any, -- Readable<"landscape" | "portrait" | "square">
	isLandscape: any, -- Readable<boolean>
	-- the app-level tab/sidebar placement policy (see adaptive.navPlacement)
	navPlacement: any, -- Readable<"bottomBar" | "bottomBarCompact" | "topBar" | "sidebar">
}

--[[ THE MOST IMPORTANT ARGUMENT IS NOW IN A TYPE (F-29). `conditions` used to
	declare an inline intersection `(AxisOpts & { scope: any? })?` and read the
	scope through two `(opts :: any)` casts, so the one argument that stops a
	twelve-memo leak was undiscoverable from the exported types and a rename would
	not have been caught. ]]
export type ConditionsOpts = {
	stackAbove: number?, -- AxisOpts: width at or above which the axis becomes "x"
	scope: any?, -- owns every memo this function creates (see the note below)
}

-- conditions(core, env, opts?) -> Conditions
-- Readables the caller owns; they are memos over the environment, so they cost
-- nothing until read and re-resolve in place when a fact changes.
-- CLOSED OPTS (constitution §4). `scope` is the leak fix below, and a
-- misspelled one leaks twelve memos per mount without a word.
local CONDITIONS_OPTS_KEYS = specGuard.keySet({ "scope", "stackAbove" })

function adaptive.conditions(core: any, env: any, opts: ConditionsOpts?): Conditions
	specGuard.assertKnownKeys("adaptive.conditions", opts, CONDITIONS_OPTS_KEYS, "opts")
	local viewportRect = env:get("viewportRect")
	-- delegate to the env memo so the breakpoints have exactly one implementation
	local sizeClass = env:get("sizeClass")
	local distanceProfile = env:get("distanceProfile")
	local interactionClasses = env:get("interactionClasses")
	local displaySize = env:get("displaySize")

	-- OWNERSHIP: this function creates THIRTEEN memos (six until
	-- ADR-0023 added the height half, twelve until navPlacement), and a caller that rebuilds per mount
	-- without owning them leaks twelve per cycle — measured in the sponsor
	-- fixtures under a long-lived core. Pass `opts.scope` and the memos die with
	-- the caller; omitted, the caller owns them by hand (§6.3 — every resource
	-- has exactly one owner either way).
	local function owned<T>(resource: T): T
		if opts ~= nil and opts.scope ~= nil then
			return opts.scope:own(resource)
		end
		return resource
	end
	local contentWidth = owned(core:memo(function(use)
		local vp = use(viewportRect)
		return if type(vp) == "table" then safeWidth(vp.w) else 0
	end))
	local function is(name: string)
		return owned(core:memo(function(use)
			return use(sizeClass) == name
		end))
	end
	local contentHeight = owned(core:memo(function(use)
		local vp = use(viewportRect)
		return if type(vp) == "table" then safeWidth(vp.h) else 0
	end))
	-- the height class delegates to the same pure function the width class does,
	-- and reads the distance profile from the same env fact, so the ten-foot cap
	-- has exactly ONE implementation on each axis
	local heightClass = owned(core:memo(function(use)
		return adaptive.heightClass(use(contentHeight), { distanceProfile = use(distanceProfile) })
	end))
	local orientation = owned(core:memo(function(use)
		return adaptive.orientationFor(use(contentWidth), use(contentHeight))
	end))
	return {
		sizeClass = sizeClass,
		isCompact = is("compact"),
		isRegular = is("regular"),
		isWide = is("wide"),
		isTenFoot = owned(core:memo(function(use)
			return use(distanceProfile) == "ten-foot"
		end)),
		-- NOTE (verifier finding V16): this is the RAW viewport width — it does NOT
		-- subtract safe insets or overscan. In the console matrix row it reads 1920
		-- while overscan removes 106px per side. Near a breakpoint a screen can
		-- therefore resolve for space it does not have. `viewportWidth` is the honest
		-- name; `contentWidth` is kept as an alias so callers do not break, and a
		-- decision that must respect insets belongs in ViewThatFits, which measures.
		viewportWidth = contentWidth,
		contentWidth = contentWidth,
		axis = owned(core:memo(function(use)
			return adaptive.axisFor(use(contentWidth), opts)
		end)),
		heightClass = heightClass,
		isShort = owned(core:memo(function(use)
			return use(heightClass) == "short"
		end)),
		isTall = owned(core:memo(function(use)
			return use(heightClass) == "tall"
		end)),
		viewportHeight = contentHeight,
		orientation = orientation,
		isLandscape = owned(core:memo(function(use)
			return use(orientation) == "landscape"
		end)),
		navPlacement = owned(core:memo(function(use)
			return adaptive.navPlacement({
				sizeClass = use(sizeClass),
				heightClass = use(heightClass),
				distanceProfile = use(distanceProfile),
				primary = (function()
					local ic = use(interactionClasses)
					return if type(ic) == "table" then ic.primary else nil
				end)(),
				displaySize = use(displaySize),
			})
		end)),
	}
end

--[[ ===== THE CONTAINER-RELATIVE DECISION, AS A VALUE ========================

	"Does this content fit that container?" is the question `UI.ViewThatFits`
	answers by MOUNTING a subtree — and a consumer often needs the same answer as
	a VALUE: to reserve space in a sibling, to place or skip a minimap, to choose
	between two surfaces before either one is built. Everything above this line is
	viewport-relative and `ViewThatFits` returns a subtree, so until this pair
	there was no container-relative Readable at all (framework-gaps-phase2 §2b).

	IT IS THE LADDER'S OWN PREDICATE, deliberately, and that is the whole reason
	it lives in the framework rather than at each call site. `chosenCandidate` in
	`src/layout/solver.luau` tests `availW == math.huge or w <= availW`; so does
	`fitsIn`, and `tests/fits_ideal_size.spec.luau` drives the two side by side
	across a width sweep and requires that they never disagree. A second copy of
	the comparison is how a screen ends up reserving room for an arrangement the
	solver then refuses to use.

	WHAT IT REPLACES, and it is a measured shape rather than a hypothetical. Rascal
	Rally's `HudZoneModel.sponsorTopStrip` decided whether its Lap pill and Race
	Drama dial fit the free topbar band with `GROUP_NATURAL_W = 100 + 10 + 200` —
	a hand sum of two chip widths and a gap, mirrored from another file with a
	"keep this in sync" comment — plus `TOPBAR_SLACK = 24`, a fudge whose own
	comment admits it is guarding a guess. A hand sum is wrong in three ways this
	pair closes: a part can go stale silently, a part can arrive `nil` and be added
	as zero, and the sum does not ride the ten-foot metric ladder that moves the
	very chips it is summing.

	`needs` THEREFORE TAKES A LIST. Naming the parts is what lets them be the SAME
	metric reads the content is built from — so the sum moves when they move — and
	a part that is `nil`, NaN or negative is REFUSED rather than silently counted
	as zero, which is the hand sum's real failure mode. ]]

-- fitsIn(needs, container, clearance?) -> boolean — the PURE half, and the same
-- comparison the ViewThatFits ladder makes. An UNBOUNDED container fits
-- everything, exactly as `availW == math.huge` does in the solver: infinity has
-- room for anything, and answering "no" there is how a decision inside a
-- scroller's own axis ends up permanently pessimistic.
function adaptive.fitsIn(needs: number, container: number, clearance: number?): boolean
	if container == math.huge then
		return true
	end
	return safeWidth(needs) + safeWidth(clearance) <= safeWidth(container)
end

export type FitsSpec = {
	--[[ the extent the content needs on this axis: a px number, a
		`Readable<number>`, or a LIST of either — the parts of a row, summed with
		`gap` between them. Name the parts rather than pre-summing them: that is
		what keeps the sum honest when a theme, a display class or a preference
		moves one of them. ]]
	needs: any,
	gap: any?, -- px between the parts of a `needs` list; ignored for a single extent
	container: any, -- the container extent: a px number or a `Readable<number>`
	--[[ how much room must remain BEYOND the content for the answer to be yes. A
		real clearance ("this row may not touch the gear beside it") is a
		declaration and belongs here; a fudge covering an untrustworthy sum does
		not, and naming the parts is what removes the need for one. ]]
	clearance: any?,
	scope: any?, -- owns the memo this function creates (see `conditions`)
}

local FITS_SPEC_KEYS = specGuard.keySet({ "needs", "gap", "container", "clearance", "scope" })

--[[ fits(core, spec) -> Readable<boolean> — the REACTIVE half. Every field may be
	a live Readable, so a theme swap, a rotation, a preferred-text change and a
	display-class change all re-resolve the decision in place. ]]
function adaptive.fits(core: any, spec: FitsSpec): any
	specGuard.assertKnownKeys("adaptive.fits", spec, FITS_SPEC_KEYS, "spec")
	assert(spec.needs ~= nil, "adaptive.fits: spec.needs is required (a px number, a Readable, or a list of either)")
	assert(
		spec.container ~= nil,
		"adaptive.fits: spec.container is required (the container extent, a px number or a Readable)"
	)
	--[[ WHAT IS CHECKED WHERE, and it is forced by the reactive core rather than
		chosen: a memo's compute is pcall-quarantined, so an `assert` inside one
		records `core:lastError()` and answers `nil` instead of unwinding. A LOUD
		refusal therefore has to happen HERE, at construction, and it can — every
		STATIC part is knowable now. A part that arrives as a live Readable can only
		be judged when it resolves, and there the assert reaches the core's own
		error channel and the decision answers falsy, which is the conservative
		direction: never reserve room the container has not been shown to have. ]]
	local function isReadable(raw: any): boolean
		return type(raw) == "table" and (raw.kind == "signal" or raw.kind == "memo")
	end
	local function checkStatic(raw: any, what: string)
		if raw == nil or isReadable(raw) then
			return
		end
		assert(
			type(raw) == "number" and raw == raw and raw >= 0,
			`adaptive.fits: {what} must be a non-negative number or a Readable (got {tostring(raw)})`
		)
	end
	local rawNeeds = spec.needs
	local isList = type(rawNeeds) == "table" and not isReadable(rawNeeds)
	if isList then
		local parts = rawNeeds :: { any }
		--[[ A HOLE IS A PART THAT WENT AWAY, and Lua will not say so: `{ a, b, c }`
			with `b` nil has an undefined length, so a naive sum quietly drops the
			parts past the hole and answers "it fits". That is the hand sum's own
			failure mode reproduced one layer down, which is why the count of KEYS is
			checked against the length rather than trusted. ]]
		local keyed = 0
		for _ in parts do
			keyed += 1
		end
		assert(
			keyed == #parts and keyed > 0,
			`adaptive.fits: spec.needs is a list of {keyed} part(s) whose length reads {#parts} — a nil in the `
				.. "middle of the list, or an empty list. Name every part: a part that arrives nil is exactly the "
				.. "hand-sum failure this helper exists to end"
		)
		for i = 1, #parts do
			checkStatic(parts[i], `spec.needs[{i}]`)
		end
	else
		checkStatic(rawNeeds, "spec.needs")
	end
	checkStatic(spec.gap, "spec.gap")
	checkStatic(spec.container, "spec.container")
	checkStatic(spec.clearance, "spec.clearance")

	local function px(raw: any, use: any, what: string): number
		local value = if isReadable(raw) then use(raw) else raw
		assert(
			type(value) == "number" and value == value and value >= 0,
			`adaptive.fits: {what} resolved to {tostring(value)} rather than a non-negative number. A part that `
				.. "arrives nil is the hand-sum failure this helper exists to end, so it is refused rather than "
				.. "counted as zero"
		)
		return value
	end
	local memo = core:memo(function(use)
		local needs = 0
		if isList then
			local parts = rawNeeds :: { any }
			for i = 1, #parts do
				needs += px(parts[i], use, `spec.needs[{i}]`)
			end
			if #parts > 1 and spec.gap ~= nil then
				needs += px(spec.gap, use, "spec.gap") * (#parts - 1)
			end
		else
			needs = px(rawNeeds, use, "spec.needs")
		end
		local clearance = if spec.clearance == nil then 0 else px(spec.clearance, use, "spec.clearance")
		return adaptive.fitsIn(needs, px(spec.container, use, "spec.container"), clearance)
	end)
	if spec.scope ~= nil then
		return spec.scope:own(memo)
	end
	return memo
end

return adaptive
