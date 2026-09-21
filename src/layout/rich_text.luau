--!strict
--[[ ── MARKUP IN, DISPLAYED TEXT OUT ───────────────────────────────────────────

	`UI.Text{ rich = true }` hands the engine a string with markup in it, and the
	engine draws the markup's EFFECT rather than its characters. Everything that
	has to reserve a box for that string therefore has to ask a different question
	from "how wide is this string": it has to ask how wide the DISPLAYED text is,
	drawn with the FACES the markup asks for.

	Three pure functions answer it, and nothing here knows about a node, a solve or
	an engine.

	  · `displayText(s)` — the string the player actually sees. This is the
	    library's own reading of the engine's `ContentText`.
	  · `spansOf(s, baseFont, baseSize)` — where the displayed text changes face,
	    so the measurer can ask for each run at the face it is drawn in.
	  · `escape(s)` — the inverse door. Untrusted or composed-in text is escaped
	    ONCE, by its caller, before it is pasted into markup; otherwise a player
	    name containing `<` either paints as a tag or breaks the parse.

	EVERY WELL-FORMED TAG IS REMOVED, not a named subset. Measured live
	(2026-09-18, Studio 0.739): a `TextLabel` with `RichText = true` and
	`<blink>Lap record</blink>` reports `ContentText = "Lap record"` and bounds
	63.5 — the engine CONSUMES markup it does not implement rather than drawing it.
	A closed subset would therefore have reserved a box for tags nobody sees, which
	is the same measure-versus-paint split from the other side. So the rule is
	structural: anything shaped like a tag or a comment goes, and only the
	transforms below leave a trace.

	MALFORMED MARKUP IS MEASURED RAW. A `<` that does not open a well-formed tag
	means the parse fails, and a failed parse is drawn as the literal string it was
	given — so that is exactly what is measured. One malformed marker makes the
	WHOLE string raw, because that is what the engine does with it.

	WHAT IS EXACT AND WHAT IS NOT — and an approximate span can CLIP, so this list
	is the contract rather than a caveat:

	  · exact — paint-only markup (`<font color>`, `<stroke>`, `<mark>`), `<i>`
	    (measured live at the plain width), the two case transforms' CHARACTERS,
	    `<b>`/`<font weight>` (measured at that weight of the same family),
	    `<font size>` (measured at that size), `<font face>` (measured at that
	    family's regular face);
	  · APPROXIMATE, and named where an author reads it (`docs/reference/api.md`
	    under `Text`) — `<sc>`/`<smallcaps>` is upper-cased, which is WIDER than
	    the small capitals the engine draws, so the box over-reserves; a `<font>`
	    that changes face AND weight together takes the face's regular weight; and
	    nested spans take the innermost declaration only.

	The residuals are all in the over-reserving direction except the nesting one,
	which is why nesting is the one to fix next if a screen needs it. ]]

local rich_text = {}

--[[ THE TWO CASE TRANSFORMS, and they are the only tags whose CONTENT changes.
	The engine draws `<uc>lap</uc>` as `LAP`, so a measure that saw `lap` reserved
	a box ~16% too narrow (measured live: 401.0 against 346.0 at 24 px). Both
	spellings, because the engine accepts both. ]]
--
-- ASCII ONLY, and it is a known limit rather than an oversight: Luau's
-- `string.upper` leaves a non-ASCII letter alone, so `<uc>café</uc>` measures
-- `CAFé` where the engine draws `CAFÉ`. The error is one accented glyph's worth
-- of width and the fix is a Unicode case map, which is not worth carrying for it.
local UPPER_TAGS: { [string]: boolean } = { uc = true, uppercase = true, sc = true, smallcaps = true }

-- the five escapes, both ways. One table, so the door cannot open wider than it
-- closes: `escape(displayText(x)) == x` for any x the escaper produced.
local DECODE: { [string]: string } = {
	lt = "<",
	gt = ">",
	amp = "&",
	quot = '"',
	apos = "'",
}
local ENCODE: { { from: string, to: string } } = {
	-- `&` FIRST, or the ampersands this function introduces are escaped again
	{ from = "&", to = "&amp;" },
	{ from = "<", to = "&lt;" },
	{ from = ">", to = "&gt;" },
	{ from = '"', to = "&quot;" },
	{ from = "'", to = "&apos;" },
}

--[[ escape(s) -> markup-safe s

	Call this on anything a player or a server supplied before composing it into
	markup. It escapes the five characters the parser reads and nothing else, so
	it is safe to call on text that is already plain. It is NOT a text filter:
	deciding whether a player may say a thing at all stays the game's job. ]]
function rich_text.escape(s: string | number): string
	local text = tostring(s)
	for _, pair in ENCODE do
		text = string.gsub(text, pair.from, pair.to)
	end
	return text
end

--[[ ONE SCAN, TWO ANSWERS. The displayed string and the face changes inside it
	come from the same walk, because deriving them separately is two readings of
	one grammar that can disagree. Returns `(displayed, spans)`, where `spans` is
	nil when nothing changes face — the overwhelmingly common case, and the one
	that must allocate nothing beyond the string.

	A span is `{ at = <byte index into the displayed string>, weight = …, face = …,
	size = … }`; `at = 1` is implicit and means the base. A caller resolves the
	descriptor because only it knows the base face. ]]
type Span = { at: number, weight: string?, face: string?, size: number? }

-- `<font …>` attributes this reader understands. `color` is paint and changes no
-- advance, so it is deliberately absent: reading it would imply it mattered.
--[[ THE ENGINE'S `FontWeight` NAMES, keyed by their lower-case spelling.

	THE MEASUREMENT KEY WANTS THE CANONICAL NAME, because that is what
	`Enum.FontWeight[...]` is indexed with when the client premeasure resolves a
	descriptor into a real `Font`. Roblox's own documentation writes the attribute
	lower-case (`<font weight="heavy">`), and so does this campaign's own Studio
	measurement of the +6.6% heavy run — so a reader that only matched the
	capitalised spelling left the commonest form measuring at Regular headless AND
	resolving to the family's Regular live. Normalised here, where the numeric
	spelling is already normalised, so there is one place that knows the set. ]]
local FONT_WEIGHTS: { [string]: string } = {
	thin = "Thin",
	extralight = "ExtraLight",
	light = "Light",
	regular = "Regular",
	medium = "Medium",
	semibold = "SemiBold",
	bold = "Bold",
	extrabold = "ExtraBold",
	heavy = "Heavy",
}

--[[ ...AND THE SAME NINE BY NUMBER, which is the engine's other spelling of one
	set: `Enum.FontWeight` gives each name exactly one value, so this is a
	transcription rather than a second opinion. It replaces a hand-rolled ladder
	(`>= 800 → Heavy`, `>= 700 → Bold`, `>= 600 → SemiBold`) that disagreed with
	the engine at both ends: 800 is ExtraBold, not Heavy, and 500 is Medium rather
	than nothing at all — the second of those was the UNDER-reserving direction.

	A NUMBER OFF THE LADDER NAMES NOTHING, exactly as an unknown name does: the
	engine has no weight for `750`, so it ignores the attribute and draws the base
	face, and measuring the base face is agreeing with it. ]]
local NUMERIC_WEIGHTS: { [number]: string } = {
	[100] = "Thin",
	[200] = "ExtraLight",
	[300] = "Light",
	[400] = "Regular",
	[500] = "Medium",
	[600] = "SemiBold",
	[700] = "Bold",
	[800] = "ExtraBold",
	[900] = "Heavy",
}

local function fontAttrs(attrs: string): (string?, string?, number?)
	local weight = string.match(attrs, "weight%s*=%s*[\"']([^\"']+)[\"']")
	local face = string.match(attrs, "face%s*=%s*[\"']([^\"']+)[\"']")
	local size = tonumber(string.match(attrs, "size%s*=%s*[\"']?(%d+)"))
	--[[ A NUMERIC WEIGHT IS THE ENGINE'S OTHER SPELLING (`weight="700"`), and the
		two meet here. A name the engine has no weight for names NOTHING rather than
		naming a face that does not exist: a span with no weight, no face and no size
		is not published at all, so it measures at the node's own face. ]]
	if weight ~= nil then
		local numeric = tonumber(weight)
		weight = if numeric ~= nil then NUMERIC_WEIGHTS[numeric] else FONT_WEIGHTS[string.lower(weight)]
		-- `Regular` IS the base face, so naming it is naming nothing: a span with
		-- no weight, no face and no size is never published and the run measures
		-- at the node's own descriptor
		if weight == "Regular" then
			weight = nil
		end
	end
	return weight, face, size
end

local function scan(text: string): (string, { Span }?)
	local out: { string } = {}
	local spans: { Span }? = nil
	-- the open case transforms and face declarations, innermost last
	local upperDepth = 0
	local faceStack: { Span } = {}
	local i = 1
	local n = #text
	local length = 0
	local function push(span: Span)
		if spans == nil then
			spans = {}
		end
		table.insert(spans :: { Span }, span)
	end
	--[[ SPANS, NOT CHARACTERS. The plain run between two markers is copied with
		one `string.sub`; appending a table entry per character cost O(n) inserts and
		a concat over n pieces on every build of a rich node, which is the
		per-frame-allocation rider for a label whose text changes every frame. ]]
	local pending = 0
	local function emit(chunk: string)
		if upperDepth > 0 then
			chunk = string.upper(chunk)
		end
		table.insert(out, chunk)
		length += #chunk
	end
	local function flush(upTo: number)
		if pending > 0 and upTo > pending then
			emit(string.sub(text, pending, upTo - 1))
		end
		pending = 0
	end
	while i <= n do
		local c = string.sub(text, i, i)
		if c == "<" then
			flush(i)
			-- the comment form first: its body may contain anything at all
			local _, commentEnd = string.find(text, "^<!%-%-.-%-%->", i)
			if commentEnd ~= nil then
				i = (commentEnd :: number) + 1
				continue
			end
			local _, tagEnd, slash, name, attrs = string.find(text, "^<(/?)([%a][%w]*)([^<>]*)>", i)
			if tagEnd == nil then
				--[[ NOT A TAG, SO THE PARSE FAILS AND THE ENGINE DRAWS THE RAW STRING.
					Returning the input verbatim is the whole answer: no transforms, no
					spans, and the caller measures exactly the characters the player will
					see. ]]
				return text, nil
			end
			local tag = string.lower(name :: string)
			local closing = slash == "/"
			if tag == "br" then
				emit("\n")
			elseif UPPER_TAGS[tag] then
				upperDepth = if closing then math.max(0, upperDepth - 1) else upperDepth + 1
			elseif tag == "font" and not closing then
				local weight, face, size = fontAttrs(attrs :: string)
				local span: Span = { at = length + 1, weight = weight, face = face, size = size }
				table.insert(faceStack, span)
				if weight ~= nil or face ~= nil or size ~= nil then
					push(span)
				end
			elseif tag == "font" and closing then
				local open = table.remove(faceStack)
				if open ~= nil and (open.weight ~= nil or open.face ~= nil or open.size ~= nil) then
					-- back to the base: a closing span with no fields IS the base
					push({ at = length + 1 })
				end
			elseif tag == "b" then
				push({ at = length + 1, weight = if closing then nil else "Bold" })
			end
			i = (tagEnd :: number) + 1
			continue
		elseif c == "&" then
			local _, entityEnd, entity = string.find(text, "^&(%a+);", i)
			if entityEnd ~= nil and DECODE[entity :: string] ~= nil then
				flush(i)
				emit(DECODE[entity :: string])
				i = (entityEnd :: number) + 1
				continue
			end
		end
		if pending == 0 then
			pending = i
		end
		i += 1
	end
	flush(n + 1)
	return table.concat(out), spans
end

--[[ displayText(s) -> the glyphs the engine draws for `s` with RichText on. ]]
function rich_text.displayText(s: string | number): string
	local text = tostring(s)
	-- the common case is a string with no markup at all: two finds, no scan
	if string.find(text, "<", 1, true) == nil and string.find(text, "&", 1, true) == nil then
		return text
	end
	return (scan(text))
end

--[[ spansOf(s) -> the face changes inside `displayText(s)`, or nil.

	Separate from `displayText` so a caller that only needs the string pays only
	for the string, and returned as plain data so the measurement layer owns how a
	span becomes a font key. ]]
function rich_text.spansOf(s: string | number): { Span }?
	local text = tostring(s)
	if string.find(text, "<", 1, true) == nil then
		return nil
	end
	local _, spans = scan(text)
	return spans
end

return rich_text
