--!strict
-- Headless text measurement provider (design §7.4): non-yielding, returns
-- ready/pending/failed with conservative fallbacks. Lune metrics are screening
-- approximations calibrated later against Studio fixtures (UI-FID-001); they
-- are deliberately conservative (over-estimate) so fallback layout never
-- under-reserves. The engine premeasurement queue (TextService) lives behind
-- the same interface in the Roblox platform adapter, NOT here.
--
-- FONT KEYS (ADR-0019 §6): every store here keys on the canonical descriptor
-- "family#weight#style". The three short names the library shipped with remain
-- aliases for their Regular/Normal descriptor, so `calibrate("BuilderSans", …)`
-- and `calibrate("BuilderSans#Regular#Normal", …)` address ONE entry, and
-- `calibrationTable()` mirrors the alias back for callers that used it. A
-- different WEIGHT of a known family is a different, uncalibrated descriptor and
-- correctly takes the conservative full-em path until it is measured.
-- `measure(...)` takes an optional per-call `lineHeight` (the typography role's
-- factor); absent, the historic global 1.2 applies.

local text_metrics = {}

-- Average glyph width as a fraction of font size. Conservative upper bound
-- for typical UI sans-serif Latin text; CJK/emoji get a full em per glyph.
local AVG_GLYPH_FRACTION = 0.62
-- default line-height factor; a typography role may carry its own (ADR-0019 §6)
local LINE_HEIGHT_FACTOR = 1.2

-- ===== canonical font keys (ADR-0019 §6) ===================================
-- Every store in this module keys on the EFFECTIVE font descriptor
-- "family#weight#style", never on a short family name: two weights of one
-- family measure differently, and sharing one cache entry between them is a
-- clipped label waiting to happen. The three names the library shipped with
-- remain valid ALIASES for their regular descriptor, so existing callers (and
-- the client calibration/premeasure adapters) keep working unchanged.
local DEFAULT_WEIGHT = "Regular"
local DEFAULT_STYLE = "Normal"

-- memoized: canonicalization sits inside the per-word measure loop, and the
-- interpolation for alias names was a measurable share of a bench regression
-- (2026-07-25) before the store below went nested
local canonCache: { [string]: string } = {}

local function canonicalFont(font: string): string
	local hit = canonCache[font]
	if hit ~= nil then
		return hit
	end
	local canon = if string.find(font, "#", 1, true) ~= nil then font else `{font}#{DEFAULT_WEIGHT}#{DEFAULT_STYLE}`
	canonCache[font] = canon
	return canon
end

text_metrics.canonicalFont = canonicalFont

-- Engine calibration (UI-FID-001, native-substrate NS-A10): the Roblox
-- adapter (src/client/text_calibration.luau) measures a reference corpus with
-- the engine text-bounds API and feeds a per-font average-glyph fraction
-- back here, TIGHTENING the conservative default. Pure data: tests pin it and
-- reset it. Safety is enforced at this seam, not trusted from the caller:
-- values clamp to [0.30, AVG_GLYPH_FRACTION] — the calibration can only
-- tighten (never exceed the proven-safe default) and can never collapse below
-- a sane floor, so a garbage measurement cannot cause under-reservation
-- beyond the caller's applied safety margin.
local calibration: { [string]: number } = {}

function text_metrics.calibrate(font: string, fraction: number)
	if type(fraction) ~= "number" or fraction ~= fraction then
		return
	end
	calibration[canonicalFont(font)] = math.clamp(fraction, 0.30, AVG_GLYPH_FRACTION)
end

-- the calibration store, keyed canonically. Short-name ALIASES are mirrored into
-- the returned copy so a caller that calibrated with "BuilderSans" can read the
-- value back under the same name it used (the client calibration adapter does
-- exactly that); the live store itself only ever holds descriptors.
function text_metrics.calibrationTable(): { [string]: number }
	local out = table.clone(calibration)
	for key, value in calibration do
		local family = string.match(key, "^([^#]+)#" .. DEFAULT_WEIGHT .. "#" .. DEFAULT_STYLE .. "$")
		if family ~= nil then
			out[family] = value
		end
	end
	return out
end

function text_metrics.resetCalibration()
	table.clear(calibration)
end

-- descriptors the headless provider "knows"; anything else (including another
-- WEIGHT of a known family, which measures differently) takes the pending path
-- with an even more conservative fallback (full em per glyph)
local KNOWN_FONTS: { [string]: boolean } = {
	[canonicalFont("BuilderSans")] = true,
	[canonicalFont("GothamSSm")] = true,
	[canonicalFont("SourceSans")] = true,
}

-- ENGINE PREMEASUREMENT (text-measurement milestone, 2026-07-24). The average-
-- glyph model above is a BOUND, not a measurement, and its error is variance
-- rather than font: measured live, "Brightness" runs 0.391 em/glyph and
-- "Volume" 0.469 in the same font at the same size. A single fraction that
-- bounds the wide one wastes space on the narrow one (an action button
-- reserving 68px of height for a label the engine draws in 46, because the
-- estimator predicts a wrap that never happens), and one that fits the narrow
-- one CLIPS the wide one. No average can bound a specific short string.
--
-- So exact widths are measured per WORD, never per laid-out string. Wrapping
-- is greedy over words, so exact word widths plus an exact space width give
-- exact wrapping at ANY width — measured once, stable across every resize and
-- every device profile. The cache key is (font, size, word); it deliberately
-- does NOT include maxWidth, which would turn a per-vocabulary cost into a
-- per-layout one.
--
-- This module stays pure data and non-yielding, exactly like `calibrate`. The
-- engine queue lives in the Roblox adapter (src/client/text_premeasure), which
-- measures the emitted words off the render path and feeds them back here.
-- `false` in the store means "the engine could not measure this" — the safe
-- estimate stands and the word is never requested again.
--
-- `state` is NOT the signal for this. It already means "the ESTIMATOR does not
-- know this font, so the box carries the full-em fallback", which every headless
-- solve depends on and the layout dump records; relabelling every ordinary node
-- `pending` because a word has not been measured yet would overload one field
-- with two unrelated facts. Exactness rides its own `exact` flag, and the
-- request set is drained through beginCollect/endCollect.
-- NESTED, not string-keyed (bench find 2026-07-25): the store used to key on
-- `{font}\0{size}\0{word}` strings, and once fonts became ~50-char canonical
-- DESCRIPTORS this stage, building that key per word per measure allocated its
-- way to a 2x table-mutation p95 regression. canonFont -> size -> word costs
-- three hash hops and zero allocation on the hot path.
local exactWidths: { [string]: { [number]: { [string]: number | false } } } = {}
local exactCount = 0
-- a runaway vocabulary must not become a leak. Well past any real UI's word
-- count; once full, new words simply keep the estimate.
local EXACT_CAP = 8192

local function bucketFor(canon: string, fontSize: number, create: boolean): { [string]: number | false }?
	local byFont = exactWidths[canon]
	if byFont == nil then
		if not create then
			return nil
		end
		byFont = {}
		exactWidths[canon] = byFont
	end
	local bySize = byFont[fontSize]
	if bySize == nil then
		if not create then
			return nil
		end
		bySize = {}
		byFont[fontSize] = bySize
	end
	return bySize
end

-- Requests are COLLECTED PER SOLVE by the caller that owns the solve, not
-- accumulated globally: a global queue lets one surface drain the words
-- another surface asked for, and the surface that never sees its own
-- measurement never re-solves. `nil` = nobody is collecting, which is the
-- default and the state every headless solve runs in.
local collecting: { [string]: { font: string, size: number, word: string } }? = nil
local collectCount = 0
local COLLECT_CAP = 1024

local SPACE = " "

export type Request = { font: string, size: number, word: string }

export type Metrics = {
	width: number,
	height: number,
	-- the lines actually DRAWN: the natural wrap count, clamped by `maxLines`
	-- when the caller capped it. `height` is always `ceil(lines * size * factor)`,
	-- so the reserved box and the painted box agree by construction.
	lines: number,
	-- what the text wraps to with no cap, so a caller can tell "it fits" from
	-- "it was cut" without re-measuring. Equal to `lines` when uncapped.
	naturalLines: number,
	-- naturalLines > lines: the engine will ellipsize (TextTruncate.AtEnd is on
	-- for every text node), and this is the seam that says so out loud
	truncated: boolean,
	state: "ready" | "pending" | "failed",
	-- every word (and the space, when one is drawn) came from an engine
	-- measurement: the reserved box is what the engine draws, not a bound on it
	exact: boolean,
	requestKey: string?,
	error: string?,
}

-- feed one engine-measured word width back into the store. Returns false for a
-- measurement that could cause a clip rather than trusting the caller: NaN,
-- infinite, negative, or a zero width for a non-empty word. Safety is enforced
-- at this seam, exactly as it is for `calibrate`.
function text_metrics.setMeasured(font: string, fontSize: number, word: string, width: number): boolean
	if type(font) ~= "string" or type(word) ~= "string" then
		return false
	end
	if type(fontSize) ~= "number" or fontSize ~= fontSize then
		return false
	end
	if type(width) ~= "number" or width ~= width or width >= math.huge or width < 0 then
		return false
	end
	if word ~= "" and width <= 0 then
		return false
	end
	local bucket = bucketFor(canonicalFont(font), fontSize, true) :: { [string]: number | false }
	if bucket[word] == nil then
		if exactCount >= EXACT_CAP then
			return false
		end
		exactCount += 1
	end
	bucket[word] = width
	return true
end

-- the engine has no bounds for this word (unmapped font, API failure): keep the
-- conservative estimate and stop emitting a request nobody can answer
function text_metrics.markUnmeasurable(font: string, fontSize: number, word: string)
	if type(font) ~= "string" or type(word) ~= "string" then
		return
	end
	if type(fontSize) ~= "number" or fontSize ~= fontSize then
		return
	end
	local bucket = bucketFor(canonicalFont(font), fontSize, true) :: { [string]: number | false }
	if bucket[word] == nil then
		if exactCount >= EXACT_CAP then
			return
		end
		exactCount += 1
	end
	bucket[word] = false
end

-- start recording the words the next measure() calls cannot size exactly.
-- Flat, not nested: a second begin discards whatever the first was collecting,
-- so an error thrown mid-solve cannot leave a stale collector accumulating.
function text_metrics.beginCollect()
	collecting = {}
	collectCount = 0
end

-- drain what was collected, in a deterministic order (font, size, word), and
-- stop collecting
function text_metrics.endCollect(): { Request }
	local pending = collecting
	collecting = nil
	collectCount = 0
	local out: { Request } = {}
	if pending == nil then
		return out
	end
	for _, request in pending do
		table.insert(out, request)
	end
	table.sort(out, function(a, b)
		if a.font ~= b.font then
			return a.font < b.font
		end
		if a.size ~= b.size then
			return a.size < b.size
		end
		return a.word < b.word
	end)
	return out
end

function text_metrics.measuredWidth(font: string, fontSize: number, word: string): (number | false)?
	local bucket = bucketFor(canonicalFont(font), fontSize, false)
	return if bucket ~= nil then bucket[word] else nil
end

function text_metrics.measuredCount(): number
	return exactCount
end

-- the whole measured vocabulary, deterministically ordered: the instrument that
-- makes an exactness claim checkable instead of inferred. `false` marks a word
-- the engine refused, which is why it appears here rather than being dropped.
function text_metrics.measuredDump(): { { font: string, size: number, word: string, width: number | false } }
	local out = {}
	for font, byFont in exactWidths do
		for size, bySize in byFont do
			for word, width in bySize do
				table.insert(out, { font = font, size = size, word = word, width = width })
			end
		end
	end
	table.sort(out, function(a, b)
		if a.font ~= b.font then
			return a.font < b.font
		end
		if a.size ~= b.size then
			return a.size < b.size
		end
		return a.word < b.word
	end)
	return out
end

function text_metrics.resetMeasured()
	table.clear(exactWidths)
	exactCount = 0
	collecting = nil
	collectCount = 0
end

local function glyphWidth(codepoint: number, fontSize: number, fraction: number): number
	-- CJK and wide ranges: full em; everything else the average fraction
	if codepoint >= 0x1100 and (codepoint <= 0x115F or codepoint >= 0x2E80) then
		return fontSize
	end
	return fontSize * fraction
end

-- exact width for one word if the engine has measured it, otherwise the
-- conservative estimate — and, while a caller is collecting, a request for it.
-- Returns (width, isExact).
-- `bucket` is the (canonFont, size) word store resolved ONCE per measure —
-- never per word (the per-word key build was the 2026-07-25 bench regression)
local function wordWidth(
	word: string,
	canon: string,
	bucket: { [string]: number | false }?,
	fontSize: number,
	fraction: number
): (number, boolean)
	local known = if bucket ~= nil then bucket[word] else nil
	if type(known) == "number" then
		return known, true
	end
	if known == nil and collecting ~= nil then
		-- the collector stays string-keyed: it only fills on the PENDING path
		-- (unmeasured words), which is off the steady-state hot loop
		local queue = collecting :: { [string]: Request }
		local key = `{canon}\0{fontSize}\0{word}`
		if queue[key] == nil and collectCount < COLLECT_CAP then
			collectCount += 1
			queue[key] = { font = canon, size = fontSize, word = word }
		end
	end
	local estimate = 0
	for _, cp in utf8.codes(word) do
		estimate += glyphWidth(cp, fontSize, fraction)
	end
	return estimate, false
end

-- THE ENGINE'S REPORTING GRID (director round 9, measured live 2026-07-26,
-- Studio 0.731). `GetTextBoundsAsync` answers on a 0.5 px grid, and it lays out
-- a WHOLE LINE in one pass while this model sums the parts. The space probe
-- (`"x x"` minus `"xx"`, src/client/text_premeasure) is a DIFFERENCE of two such
-- quantized answers, so it can land one step low: at BuilderSans@13 it returns
-- 2.50 where the engine's own inter-word advance inside "Classic Desktop" is
-- 3.00 — reproducibly, on every 2-word label, and −0.5 per gap on a 4-word one.
--
-- A per-word sum that is 0.5 px short is not a rounding curiosity: the box is
-- `ceil(width)`, so half the labels land on the wrong integer and the engine
-- wraps a line the solver reserved one line for. Measured consequence: five of
-- the theme picker's ten chips under classic-desktop — exactly the five whose
-- true width ends in .5 — clipped to their first word.
--
-- So one grid step is reserved per JOINT, and only where the widths came from
-- the engine at all: an estimated line already carries the conservative
-- full-em bound, and a headless solve (which never has engine widths) is
-- byte-unchanged, which is what keeps the flat baseline reproducible.
local BOUNDS_GRID = 0.5

local function wrap(
	text: string,
	canon: string,
	fontSize: number,
	maxWidth: number,
	fraction: number
): (number, number, boolean)
	local bucket = bucketFor(canon, fontSize, false)
	-- greedy word wrap; returns (lineCount, widestLinePx, everyWidthExact).
	-- Deterministic. With exact per-word widths this reproduces the engine's
	-- own greedy break points, so the reserved box is the drawn box.
	local widest = 0
	local lines = 1
	local lineWidth = 0
	local exact = true
	-- the space is only consulted (and only requested) when one is drawn
	local spaceW: number? = nil
	local spaceExactly = false
	-- A RUN OF SPACES IS AS WIDE AS IT IS LONG (found live 2026-08-06, tutorial
	-- example 05's legend). This loop used to be `gmatch(text, "%S+")` and add
	-- exactly ONE space width at every joint, so `"a   b"` reserved the same box as
	-- `"a b"`. Measured on the engine at BuilderSans 12: the legend
	-- `"v correct   ~ present   x absent"` draws 134.5 px and this model reserved
	-- 124.5 — the four extra spaces, at 2.5 px each, exactly — so the label
	-- truncated to "…x…" on a 907 px-wide desktop with 780 px to spare.
	--
	-- The gap's literal SPACE characters are counted. Only spaces: a gap made of a
	-- newline still counts as one, so the embedded-newline behaviour
	-- (docs/lessons/embedded-newlines-measure-as-one-line.md) is byte-identical, and
	-- so is every single-spaced string in the suite.
	--
	-- CAPTURED AS A POSITION, NOT AS A STRING (bench, 2026-08-06). The obvious
	-- spelling is `for gap, word in string.gmatch(text, "(%s*)(%S+)")`, and it costs
	-- a throwaway `gap` string on EVERY word of EVERY measured label — every
	-- keystroke re-measures the field. Against the pinned baseline
	-- `textinput-typing-storm` went from 1.28x (not flagged) to 1.57-1.84x with a
	-- heap delta of -42 MB, which is a measurement loop feeding the collector.
	-- `"()(%S+)"` captures the word's START INDEX instead: a number, not an
	-- allocation. The gap is then read out of `text` in place, so this loop
	-- allocates exactly what the pre-existing `"%S+"` loop did — one word string per
	-- word — and nothing more. Same counts, same widths; the reservation tests pin
	-- the numbers.
	local prevEnd = 0
	for wordStart: number, word: string in string.gmatch(text, "()(%S+)") do
		local wordW, wordExact = wordWidth(word, canon, bucket, fontSize, fraction)
		exact = exact and wordExact
		local extra = 0
		if lineWidth > 0 then
			if spaceW == nil then
				local w, spaceIsExact = wordWidth(SPACE, canon, bucket, fontSize, fraction)
				spaceW = w
				spaceExactly = spaceIsExact
				exact = exact and spaceIsExact
			end
			local spaces = 0
			for i = prevEnd + 1, (wordStart :: number) - 1 do
				if string.byte(text, i) == 32 then
					spaces += 1
				end
			end
			if spaces < 1 then
				spaces = 1
			end
			-- the joint's own grid step (see BOUNDS_GRID): reserved only when the
			-- space width is an ENGINE measurement, because that is the only case
			-- where the sum can fall below what the engine draws
			extra = (spaceW :: number) * spaces + (if spaceExactly then BOUNDS_GRID else 0)
		end
		if lineWidth > 0 and lineWidth + extra + wordW > maxWidth then
			widest = math.max(widest, lineWidth)
			lines += 1
			lineWidth = wordW
		else
			lineWidth += extra + wordW
		end
		prevEnd = wordStart + #word - 1
	end
	widest = math.max(widest, lineWidth)
	return lines, math.min(widest, maxWidth), exact
end

-- measure(text, font, fontSize, maxWidth, lineHeight?, maxLines?) -> Metrics.
-- Never yields.
-- `lineHeight` is the typography role's factor from the active ThemeSnapshot
-- (ADR-0019 §6); absent, the library's historic global 1.2 applies, which is
-- what every neutral role carries — so omitting it is byte-identical.
--
-- `maxLines` is the LINE CAP (solver `lineLimit`, blueprint `Text.lineLimit`).
-- Wrapping is unchanged — the greedy break points are still the engine's — but
-- the reported HEIGHT stops at that many lines, so the box a caller reserves is
-- the box the engine is allowed to fill. That is the whole mechanism behind
-- truncation actually engaging: the adapter already sets TextTruncate.AtEnd on
-- every text node (src/client/screen_target), and an uncapped box simply never
-- gave it anything to truncate against — the text grew the box instead and
-- painted straight through whatever the box sat inside (device report
-- 2026-07-27: a three-line track name crossing two table rows).
--
-- Absent (nil), NOTHING changes: `lines == naturalLines`, `truncated` is false,
-- and the height is the historic `ceil(lines * size * factor)`.
local function clampLines(natural: number, maxLines: number?): number
	if type(maxLines) ~= "number" or maxLines ~= maxLines then -- nil / NaN
		return natural
	end
	-- a cap below one line is a caller bug, not an instruction to draw nothing:
	-- one line is the floor, exactly as `lineLimit` documents
	return math.min(natural, math.max(1, math.floor(maxLines)))
end

local function measureAt(
	text: string,
	font: string,
	fontSize: number,
	maxWidth: number,
	lineHeight: number?,
	maxLines: number?
): Metrics
	if text == "" then
		return {
			width = 0,
			height = 0,
			lines = 0,
			naturalLines = 0,
			truncated = false,
			state = "ready",
			exact = true,
		} :: Metrics
	end
	local factor = if type(lineHeight) == "number"
			and lineHeight == lineHeight
			and lineHeight > 0
		then lineHeight
		else LINE_HEIGHT_FACTOR
	local key = canonicalFont(font)
	if not KNOWN_FONTS[key] then
		-- pending: conservative full-em fallback so layout over-reserves;
		-- the engine queue resolves the real metrics later (§7.4). Exact
		-- per-word widths still win here if the adapter managed to measure
		-- them — an unknown font is unknown to the ESTIMATOR, not necessarily
		-- to the engine.
		local natural, widest, exact = wrap(text, key, fontSize, maxWidth, 1.0)
		local lines = clampLines(natural, maxLines)
		return {
			width = math.ceil(widest),
			height = math.ceil(lines * fontSize * factor),
			lines = lines,
			naturalLines = natural,
			truncated = natural > lines,
			state = "pending",
			exact = exact,
			requestKey = `{font}/{fontSize}/{maxWidth}/{text}`,
		} :: Metrics
	end
	local natural, widest, exact = wrap(text, key, fontSize, maxWidth, calibration[key] or AVG_GLYPH_FRACTION)
	local lines = clampLines(natural, maxLines)
	return {
		width = math.ceil(widest),
		height = math.ceil(lines * fontSize * factor),
		lines = lines,
		naturalLines = natural,
		truncated = natural > lines,
		state = "ready",
		exact = exact,
	} :: Metrics
end

--[[ TWO FORMS, ONE ANSWER (api-architecture-consistency F-31).

	`LuauUI.text` exports three functions in one namespace: `fit` and `size` take a
	spec table, `measure` took six positional arguments. Same question, two ways to
	ask it, and a caller who learned one could not guess the other — `measure`'s
	shape was inherited from its life as a solver internal, which is a reason and
	not a justification.

	So `measure` also accepts a spec table, detected by a table-typed first
	argument, using its siblings' vocabulary (`text`, `font`, `width`) plus the one
	word `FitSpec` spells differently because it means something different there:
	`size` is the size to measure AT, where `fit`'s `cap` is the size to search
	DOWN FROM. The positional form is untouched — every existing caller, internal
	and shipped, keeps working — and the spec form is construction-strict, because
	the likeliest mistake is writing the POSITIONAL parameter's name (`fontSize`)
	as a key and silently measuring at a nil size. ]]
export type MeasureSpec = {
	text: string,
	font: string,
	size: number, -- the type size to measure AT
	width: number, -- the box the string has to live in
	lineHeight: number?, -- the typography role's factor; absent = the library's
	maxLines: number?, -- the caller's own `lineLimit`; absent = uncapped
}

local MEASURE_SPEC_KEYS: { [string]: boolean } = {
	text = true,
	font = true,
	size = true,
	width = true,
	lineHeight = true,
	maxLines = true,
}
local MEASURE_SPEC_SHAPE = "a measure spec is { text, font, size, width, lineHeight?, maxLines? }"

-- MIN-CONTENT WIDTH — the narrowest box this string can wrap into (solver shrink
-- pass, docs/plans/swiftui-parity-round2.md §2.4, the second rung of its floor
-- stack `minMax.min` -> a text node's minimum wrap width -> `0`).
--
-- WHY IT CANNOT BE ASKED WITH `measure`. `wrap` returns `math.min(widest,
-- maxWidth)`, so measuring at a tiny offer answers with the OFFER, not with what
-- the string actually needs — the one number the shrink pass has to know before it
-- decides how far a label may give way. It is the widest single word, because a
-- word has no legal break (the same rule the compact ladder and the single-line
-- ruling in the solver both rest on): squeezed below it, the engine breaks the word
-- instead of clipping a pixel.
--
-- It reuses `wordWidth`, so exact engine widths win here exactly as they do inside
-- `wrap`, and an unmeasured word falls back to the same conservative estimate. It
-- does NOT reserve the joint grid step: there is no joint on a one-word line.
function text_metrics.minWidth(text: string, font: string, fontSize: number): number
	if text == "" then
		return 0
	end
	local canon = canonicalFont(font)
	local bucket = bucketFor(canon, fontSize, false)
	local fraction = if KNOWN_FONTS[canon] then (calibration[canon] or AVG_GLYPH_FRACTION) else 1.0
	local widest = 0
	for word in string.gmatch(text, "%S+") do
		local w = wordWidth(word, canon, bucket, fontSize, fraction)
		if w > widest then
			widest = w
		end
	end
	return math.ceil(widest)
end

function text_metrics.measure(
	text: string | MeasureSpec,
	font: string?,
	fontSize: number?,
	maxWidth: number?,
	lineHeight: number?,
	maxLines: number?
): Metrics
	if type(text) == "table" then
		local spec: any = text
		for key in spec do
			if MEASURE_SPEC_KEYS[key] ~= true then
				error("LuauUI text.measure: unknown key '" .. tostring(key) .. "' — " .. MEASURE_SPEC_SHAPE .. ".", 0)
			end
		end
		if
			type(spec.text) ~= "string"
			or type(spec.font) ~= "string"
			or type(spec.size) ~= "number"
			or type(spec.width) ~= "number"
		then
			error(
				"LuauUI text.measure: "
					.. MEASURE_SPEC_SHAPE
					.. " — text and font are strings, size and width are numbers.",
				0
			)
		end
		return measureAt(spec.text, spec.font, spec.size, spec.width, spec.lineHeight, spec.maxLines)
	end
	return measureAt(text :: string, font :: string, fontSize :: number, maxWidth :: number, lineHeight, maxLines)
end

return text_metrics
