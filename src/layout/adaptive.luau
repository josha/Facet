--!strict
-- Adaptive-layout decisions (docs/plans/swiftui-parity-next.md investment 5;
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
-- Container-relative conditions: these are viewport-relative. A decision that
-- must depend on the space a PARTICULAR container actually got needs the real
-- measurement contract, which is `UI.ViewThatFits` — the solver measures each
-- candidate against the space that container was proposed. Use the conditions
-- here for screen-level arrangement and ViewThatFits inside a container whose
-- width is not the screen's.

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
--                                                    form (phone landscape)
--   ten-foot distance         -> "topBar"            a center-aligned top tab
--                                                    bar that HUGS its content
--                                                    (never full width)
--   pointer primary           -> "sidebar"           desktop shape
--   touch + Medium/Large disp -> "topBar"            tablet shape: the same
--                                                    centered top bar
--   touch/gamepad + Small     -> "bottomBar"         a roomy canvas the DISPLAY
--     (or unknown display)                           fact cannot tell from a
--                                                    phone/handheld stays one
--                                                    (director ruling: when we
--                                                    cannot differentiate,
--                                                    bottom tabs)
--   anything else             -> "topBar"
--
-- Deliberately a function of SHAPE, INPUT and DISPLAY facts only — the
-- reference's own rule is a device-idiom branch (`.phone`), which this
-- vocabulary bans; (size/height class, primary interaction class, engine
-- display size) reproduces the same outcomes from facts a windowed pane also
-- answers honestly. Touch alone is NOT the top-bar indicator: a touch phone
-- and a touch tablet share the class, and the engine's DisplaySize is what
-- separates them. Pure, so the conditions memo and tests share one
-- implementation.
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
	if facts.primary == "touch" or facts.primary == "gamepad" then
		-- touch phones/tablets AND near-distance gamepad handhelds share this
		-- rule (director refinement: "Small and joystick can vary — bottom
		-- tabs are ok there"): the engine's DisplaySize separates the roomy
		-- device from the handheld, and when it cannot, the bottom bar is the
		-- safe home. A ten-foot gamepad never reaches here (caught above).
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

-- columnsFor(available, minColumnWidth, gap) -> integer >= 1.
-- The SAME arithmetic the solver's Grid uses for `minColumnWidth`, exported so a
-- screen can ask "how many columns will I get?" before laying anything out.
function adaptive.columnsFor(available: number, minColumnWidth: number, gap: number?): number
	local g = if type(gap) == "number" and gap == gap then math.max(0, gap) else 0
	local minW = safeWidth(minColumnWidth)
	local avail = safeWidth(available)
	if minW <= 0 then
		return 1
	end
	return math.max(1, math.floor((avail + g) / (minW + g)))
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
-- CLOSED OPTS (constitution §4; ARCH-1). `scope` is the leak fix below, and a
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

	-- OWNERSHIP (verifier RR-8): this function creates THIRTEEN memos (six until
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

return adaptive
