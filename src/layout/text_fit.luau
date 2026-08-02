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
}

export type Fit = {
	size: number, -- the size to paint at
	fits: boolean, -- false = even `floor` overflows; the caller must drop or resize
	lines: number, -- lines the string draws at `size`
	height: number, -- the height it needs at `size` (`ceil(lines * size * factor)`)
	exact: boolean, -- false = the font is uncalibrated, so `size` is conservative
}

local function fitsAt(spec: FitSpec, size: number): (boolean, text_metrics.Metrics)
	local m = text_metrics.measure(spec.text, spec.font, size, spec.width, spec.lineHeight, spec.lines)
	local ok = m.naturalLines <= (spec.lines or 1)
	if ok and type(spec.height) == "number" then
		ok = m.height <= (spec.height :: number)
	end
	return ok, m
end

--[[ The largest integer size in [floor, cap] at which `text` draws inside
	`width` (and `height`, when given) without exceeding `lines`. ]]
function text_fit.fit(spec: FitSpec): Fit
	local cap = math.max(1, math.floor(spec.cap))
	local floor = math.max(1, math.floor(spec.floor or 1))
	if floor > cap then
		floor = cap
	end
	if spec.text == "" or spec.width <= 0 then
		local m = text_metrics.measure(spec.text, spec.font, cap, math.max(spec.width, 0), spec.lineHeight, spec.lines)
		return { size = cap, fits = spec.text == "", lines = m.lines, height = m.height, exact = m.exact }
	end

	local capOk, capM = fitsAt(spec, cap)
	if capOk then
		return { size = cap, fits = true, lines = capM.lines, height = capM.height, exact = capM.exact }
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
	return { size = size, fits = best ~= nil, lines = m.lines, height = m.height, exact = m.exact }
end

-- The convenience every caller wanted: just the size.
function text_fit.size(spec: FitSpec): number
	return text_fit.fit(spec).size
end

return text_fit
