--!strict
--[[
	text_fit — "what type size makes THIS string fit THIS box?", answered against
	the library's own measurement engine instead of against a character count.

	WHY THIS EXISTS (game-side evidence, 2026-08-02). Three separate places in one
	consumer had each grown a private approximation of this question:

	  · a results surface fitting a placement/headline into a lane
	    (`cap`, `GLYPH_EM = 0.62`, `WRAP_PACKING = 0.8`);
	  · a racing HUD deciding whether a power-up's name fits its pill;
	  · the same HUD deciding whether that name fits a wider transient band.

	All three multiplied a character count by a guessed average glyph width — the
	same 0.62 this module's own measurer uses as its CONSERVATIVE FALLBACK for an
	uncalibrated font. So a caller with a calibrated font was throwing away an
	exact answer to re-derive an estimate, and three copies of the estimate could
	drift from each other and from the renderer that actually paints the string.

	`text_metrics.measure` already knows the real answer, including per-font
	calibration, per-role line height, wrapping and the CJK/emoji full-em path. It
	simply was not reachable from a presenter. This is that reach, plus the one
	derivation every caller was writing on top of it.

	THE SEARCH IS EXACT, NOT ITERATIVE-UNTIL-CLOSE. Fit is monotone in size — a
	string that fits at N fits at every size below N — so a binary search over the
	integer sizes in [floor, cap] lands on the true largest fitting size in
	~log2(cap) measures, and `measure` memoizes per (text, font, size, width).

	IT IS CONSERVATIVE BY INHERITANCE. Where the font is uncalibrated the measurer
	over-estimates, so this under-estimates the size that fits: text is smaller
	than it could be, never clipped. That is the same direction of error the
	fallback layout path takes, deliberately.
]]

local text_metrics = require("./text_metrics")
local themeSnapshot = require("../themes/snapshot")
local specGuard = require("../spec_guard")

local text_fit = {}

export type FitSpec = {
	text: string,
	font: string,
	-- the largest size this caller will ever paint at (a type role's own cap)
	cap: number,
	-- the box the string has to live in
	width: number,
	height: number?, -- absent = height is not a constraint
	lines: number?, -- the caller's own `lineLimit`; absent = one line
	lineHeight: number?, -- the typography role's factor; absent = the library's
	-- never derive below this, even if the string cannot fit. A caller that hits
	-- the floor has a box that is too small, which is a LAYOUT decision (drop it,
	-- step it down) rather than something to solve by painting unreadably.
	floor: number?,
	-- THE PAINT-TIME ADDITIVE OFFSET (Step 8.5): the engine paints every
	-- text node at `TextSize + offset(preference)`, so a size chosen to fit a
	-- box WITHOUT the offset overflows it the moment the player raises their
	-- text preference — measured live: the production role-pick CTA ellipsized
	-- at Largest exactly this way. Pass the environment's `preferredTextOffset`
	-- fact (read it inside a memo so the answer re-derives on a live change);
	-- the search then fits the PAINTED form (size + offset) while returning the
	-- authored size to paint at. Absent = 0, byte-identical to the pre-8.5
	-- behavior.
	offset: number?,
}

export type Fit = {
	size: number, -- the AUTHORED size to paint at (the engine adds `offset` itself)
	fits: boolean, -- false = even `floor` overflows; the caller must drop or resize
	-- lines/height describe the PAINTED form: with a non-zero `offset` they are
	-- measured at `size + offset` (the box must hold what the engine draws), so
	-- `height` is `ceil(lines * (size + offset) * factor)` — not the authored-size
	-- arithmetic. With offset absent/0 they are byte-identical to the old meaning.
	lines: number,
	height: number,
	exact: boolean, -- false = the font is uncalibrated, so `size` is conservative
	--[[ THE MEASURE'S OWN STATE, carried through (F-31/F-32). `exact = false`
		covers two different situations — "the font is uncalibrated and the engine
		has not answered yet" and "an engine measurement failed" — and a caller that
		must decide whether to wait or to give up cannot tell them apart from
		`exact` alone. This is the state of the measure AT THE CHOSEN SIZE, i.e. the
		measurement the returned `size`/`lines`/`height` actually came from. ]]
	state: "ready" | "pending" | "failed",
}

local function offsetOf(spec: FitSpec): number
	local raw = spec.offset
	if type(raw) ~= "number" or raw ~= raw then
		return 0
	end
	-- same legal domain the renderer clamps the env fact to
	return math.clamp(raw, 0, 32)
end

local function fitsAt(spec: FitSpec, size: number): (boolean, text_metrics.Metrics)
	-- the box has to hold the PAINTED form: the engine draws at size + offset,
	-- so that is the size the question is asked about
	local m = text_metrics.measure(spec.text, spec.font, size + offsetOf(spec), spec.width, spec.lineHeight, spec.lines)
	local ok = m.naturalLines <= (spec.lines or 1)
	if ok and type(spec.height) == "number" then
		ok = m.height <= (spec.height :: number)
	end
	return ok, m
end

--[[ The largest integer size in [floor, cap] at which `text` draws inside
	`width` (and `height`, when given) without exceeding `lines`. ]]
local FIT_SPEC_KEYS =
	specGuard.keySet({ "text", "font", "cap", "width", "height", "lines", "lineHeight", "floor", "offset" })

function text_fit.fit(spec: FitSpec): Fit
	-- strict at the boundary (§4, architecture review F-6): an unknown key or a
	-- mistyped offset must fail loudly, not silently measure at offset 0
	specGuard.assertKnownKeys("text.fit", spec, FIT_SPEC_KEYS, "spec")
	assert(
		spec.offset == nil or (type(spec.offset) == "number" and spec.offset == spec.offset),
		"text.fit: spec.offset must be a number (the environment's preferredTextOffset fact)"
	)
	local cap = math.max(1, math.floor(spec.cap))
	local floor = math.max(1, math.floor(spec.floor or 1))
	if floor > cap then
		floor = cap
	end
	if spec.text == "" or spec.width <= 0 then
		local m = text_metrics.measure(
			spec.text,
			spec.font,
			cap + offsetOf(spec),
			math.max(spec.width, 0),
			spec.lineHeight,
			spec.lines
		)
		return {
			size = cap,
			fits = spec.text == "",
			lines = m.lines,
			height = m.height,
			exact = m.exact,
			state = m.state,
		}
	end

	local capOk, capM = fitsAt(spec, cap)
	if capOk then
		return {
			size = cap,
			fits = true,
			lines = capM.lines,
			height = capM.height,
			exact = capM.exact,
			state = capM.state,
		}
	end

	-- binary search the largest fitting size; `lo` is known-not-to-fit + 1
	local lo, hi, best = floor, cap - 1, nil :: number?
	while lo <= hi do
		local mid = (lo + hi) // 2
		if fitsAt(spec, mid) then
			best = mid
			lo = mid + 1
		else
			hi = mid - 1
		end
	end

	local size = best or floor
	local _, m = fitsAt(spec, size)
	return { size = size, fits = best ~= nil, lines = m.lines, height = m.height, exact = m.exact, state = m.state }
end

-- The convenience every caller wanted: just the size.
function text_fit.size(spec: FitSpec): number
	return text_fit.fit(spec).size
end

--[[ ===== THE LINE BOX ========================================================

	"How tall is `lines` lines of this text going to be?" — the question every
	consumer that must PREDICT a text box asks, and the one nothing public
	answered.

	WHY IT EXISTS (docs/plans/variable-item-extents.md, ruled 2026-08-15). A
	survey found SEVEN near-duplicates of this arithmetic in this repo and exactly
	one correct, and that one was private to a gallery fixture; the public
	`composition.floorPx` was wrong three ways. Three independent `itemExtent`
	consumers got it wrong THE SAME WAY, each carrying a waiver in the overflow
	sweep. When three consumers make an identical mistake the API is wrong, not
	the consumers.

	The arithmetic is the solver's own, not a copy of it:

	    px = ceil(lines * (authoredSize * measureScale + preferredTextOffset)
	              * theRole'sLineHeight)

	  · `text_metrics.reservedSize` is the scale-then-add half — the same call
	    `render/layout_node.textOf` makes on every solve;
	  · `text_metrics.lineBoxPx` is the ceil half — the same call `measureAt`
	    makes to report `Metrics.height`.
	Change either seam and this moves with it, which is the whole point.

	WHEN NOT TO REACH FOR IT. If the row can measure itself, let it:
	`newVirtualList { itemExtent = "measured" }` removes the prediction instead of
	making it easier, and a cell that is wrapped text at a live size should stop
	declaring. This is for the consumer that genuinely must predict — a perf
	harness baseline, a composition floor, a list whose windowing has to be O(1) —
	and for those it is the only correct spelling. ]]

export type TextFacts = {
	-- max(typographyScale, typographyPaintScale): what a measure reserves at
	scale: number,
	-- the ADDITIVE engine offset (the player's PreferredTextSize), in px
	offset: number,
	-- the live ThemeSnapshot, so a role's size and line height come from the
	-- theme that is actually installed
	metrics: any,
}

export type FactsSpec = {
	-- the live environment (`ctx.env` / the presenter's env). Requires `use`.
	env: any?,
	--[[ THE MEMO'S OWN `use`, and it is REQUIRED with `env` — not optional.

		Reading a live fact with `:get()` is right once and registers no
		dependency, so the answer goes silently stale the moment the player raises
		their text size, swaps the theme or the screen lands on a ten-foot display.
		That silent staleness is the failure mode this whole feature exists to end,
		so the correct spelling is the only spelling the signature offers. A caller
		that genuinely wants a one-shot read writes it out —
		`use = function(r) return r:get() end` — and is thereby saying so. ]]
	use: any?,
	-- ...or a ThemeSnapshot on its own, for a caller with no env. The snapshot
	-- carries the three facts it was resolved from (`preferredText`, `density`),
	-- so the same two scales and the same offset come back out.
	metrics: any?,
}

local FACTS_SPEC_KEYS = specGuard.keySet({ "env", "use", "metrics" })

function text_fit.facts(spec: FactsSpec): TextFacts
	specGuard.assertKnownKeys("text.facts", spec, FACTS_SPEC_KEYS, "spec")
	local hasEnv = spec.env ~= nil
	local hasMetrics = spec.metrics ~= nil
	assert(
		hasEnv ~= hasMetrics,
		"text.facts: pass EITHER { env, use } (the live environment, read reactively) OR { metrics } (a ThemeSnapshot), never both and never neither"
	)
	if hasMetrics then
		local metrics = spec.metrics
		local carried = if type(metrics) == "table" then (metrics :: any).preferredText else nil
		local multiplier = if type(carried) == "table" then (carried :: any).multiplier else nil
		local rawOffset = if type(carried) == "table" then (carried :: any).offset else nil
		-- `density` is the snapshot's record of the display class it was resolved
		-- against ("ten-foot" | "near"), which is what the type-scale floor keys off
		local density = if type(metrics) == "table" then (metrics :: any).density else nil
		local displaySize = if density == "ten-foot" then "Large" else "Medium"
		return {
			scale = themeSnapshot.measureScale(displaySize, multiplier),
			offset = themeSnapshot.textOffset(rawOffset),
			metrics = metrics,
		}
	end
	local use = spec.use
	assert(
		type(use) == "function",
		"text.facts: { env } requires `use` — the enclosing memo's reader. An extent that reads a live fact with `:get()` is right once and then goes silently stale; pass `use = function(r) return r:get() end` if you really mean a one-shot read"
	)
	local env = spec.env
	-- the two DERIVED keys, not the raw facts: a fault profile or a device
	-- emulation that overrides either one must move a predicted box exactly as it
	-- moves the solver's, and `reserveScale` is the renderer measure seam's own max
	local scale = themeSnapshot.reserveScale(use(env:get("typographyScale")), use(env:get("typographyPaintScale")))
	return {
		scale = scale,
		offset = themeSnapshot.textOffset(use(env:get("preferredTextOffset"))),
		metrics = use(env:get("themeMetrics")),
	}
end

export type LineBoxSpec = {
	facts: TextFacts,
	--[[ the AUTHORED size: a number, or the name of a typography role in the live
		theme (`"body"`, `"title"`, …), whose `size` is then used. Either way it is
		scaled — an authored size reaches paint, so both seams scale it. ]]
	size: number | string,
	lines: number?, -- default 1
	--[[ the typography role whose LINE HEIGHT applies. Default: `size` when it
		names a role, else `"body"` — which is the solver's own answer, because
		`snapshot.effectiveTypeRole` resolves a literal px size on a `UI.Text` to
		the class's intrinsic role, and that role is `body`. ]]
	role: string?,
}

local LINE_BOX_SPEC_KEYS = specGuard.keySet({ "facts", "size", "lines", "role" })

local function roleEntry(metrics: any, name: string): any
	local roles = if type(metrics) == "table" then (metrics :: any).type else nil
	return if type(roles) == "table" then (roles :: any)[name] else nil
end

function text_fit.lineBox(spec: LineBoxSpec): number
	specGuard.assertKnownKeys("text.lineBox", spec, LINE_BOX_SPEC_KEYS, "spec")
	local facts = spec.facts
	assert(
		type(facts) == "table" and type((facts :: any).scale) == "number" and type((facts :: any).offset) == "number",
		"text.lineBox: spec.facts must come from text.facts({ env, use }) or text.facts({ metrics })"
	)
	local lines = if spec.lines == nil then 1 else spec.lines
	assert(
		type(lines) == "number" and lines == lines and lines >= 1 and lines ~= math.huge,
		`text.lineBox: spec.lines must be a finite count >= 1 (got {tostring(spec.lines)})`
	)

	-- 1. the AUTHORED size, and the role behind it
	local rawSize = spec.size
	local authored: number
	local sizeRole: string? = nil
	if type(rawSize) == "number" then
		assert(rawSize == rawSize and rawSize > 0, `text.lineBox: spec.size must be a positive px size (got {rawSize})`)
		authored = rawSize
	elseif type(rawSize) == "string" then
		local entry = roleEntry(facts.metrics, rawSize)
		assert(
			type(entry) == "table" and type((entry :: any).size) == "number",
			`text.lineBox: spec.size named the typography role "{rawSize}", which this theme does not carry`
		)
		authored = (entry :: any).size
		sizeRole = rawSize
	else
		error(`text.lineBox: spec.size must be a px number or a typography role name (got {type(rawSize)})`, 0)
	end

	-- 2. the LINE HEIGHT. A named `role` must exist — an accepted-and-ignored role
	-- is exactly the silent class this helper replaces. An UNNAMED one falls back
	-- to `body`, and if the theme carries no `body` either, to the measurer's own
	-- historic factor, which is what `text_metrics.measureAt` does with no role.
	local lineHeight: number? = nil
	if spec.role ~= nil then
		local entry = roleEntry(facts.metrics, spec.role)
		assert(
			type(entry) == "table" and type((entry :: any).lineHeight) == "number",
			`text.lineBox: spec.role named the typography role "{spec.role}", which this theme does not carry`
		)
		lineHeight = (entry :: any).lineHeight
	else
		local entry = roleEntry(facts.metrics, sizeRole or "body")
		lineHeight = if type(entry) == "table" and type((entry :: any).lineHeight) == "number"
			then (entry :: any).lineHeight
			else nil
	end

	-- 3. the solver's two calls, in the solver's order
	return text_metrics.lineBoxPx(text_metrics.reservedSize(authored, facts.scale, facts.offset), lines, lineHeight)
end

return text_fit
