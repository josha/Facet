--!strict
--[[
	text_stream — "show a string as it arrives, never a half-glyph, and never a
	placeholder where a value already is."

	WHY THIS EXISTS. Every app that streams text (an assistant reply, a narrated
	tutorial, a scoreboard commentary) hand-rolls the same three decisions, and
	the same three defects:

	  · `value:sub(1, cursor)` cuts a multi-byte codepoint in half, so an emoji
	    or an accented letter paints as a replacement box for one frame — once
	    per character on the way past it;
	  · the placeholder ("Thinking…") is tested against `value == ""`, so it
	    reappears whenever the value is briefly cleared mid-stream, and it is
	    painted as if it were the value — a reader cannot tell "no answer yet"
	    from "the answer is Thinking…";
	  · reduced motion is not considered at all, so a reader who has asked for
	    no motion still watches the text crawl in.

	None of those are about the text. They are about the SHAPE, which is what
	lives here, once. Like `value_reveal`, it owns NO clock and NO signals: the
	caller passes the value, the cursor its own model advances, and the motion
	policy its surface already reads.

	THE RULES IT ENCODES

	  1. A PREFIX ENDS ON A CODEPOINT. The cursor counts CHARACTERS, not bytes,
	     and the published prefix never splits one.
	  2. A PLACEHOLDER IS NOT A VALUE. `placeholder` paints only while nothing
	     has been revealed, and `revealed` says which of the two is on screen, so
	     a caller can style or announce them differently.
	  3. NO CURSOR MEANS FULLY REVEALED. A model that streams by rewriting the
	     string itself passes no cursor and still gets rules 1, 2 and 4.
	  4. REDUCED MOTION LANDS THE WHOLE VALUE. The fact is the text; the crawl is
	     the decoration. Under `motionPolicy = "reduced"` the cursor is ignored
	     and the value paints whole.
]]

local text_stream = {}

export type Spec = {
	-- the full text so far: a string, a Readable<string>, or a binding
	value: any,
	-- how many CHARACTERS of it have been revealed. nil = all of them.
	cursor: any?,
	-- painted while nothing has been revealed yet
	placeholder: string?,
	-- the surface's `motionPolicy` readable; "reduced" reveals the value whole
	policy: any?,
}

local function reader(source: any): (use: any) -> any
	if type(source) == "function" then
		return source
	elseif type(source) == "table" and source.peek ~= nil then
		return function(use)
			return if use then use(source) else source:peek()
		end
	end
	return function()
		return source
	end
end

--[[ THE PREFIX, ON A CODEPOINT BOUNDARY. `utf8.offset(s, n + 1)` is the byte
	AFTER the nth character; nil means the string is shorter than n characters,
	which is the ordinary case while a cursor runs ahead of a value that is still
	arriving. An invalid sequence (a byte stream that is not UTF-8 at all) has no
	offsets, so the byte prefix is the honest answer there. ]]
local function prefix(value: string, characters: number): string
	if characters <= 0 then
		return ""
	end
	local ok, at = pcall(utf8.offset, value, characters + 1)
	if not ok or at == nil then
		return value
	end
	return string.sub(value, 1, at - 1)
end

function text_stream.new(spec: Spec)
	assert(type(spec) == "table", "Facet motion.newTextReveal: expected a spec table")
	assert(spec.value ~= nil, "Facet motion.newTextReveal: `value` is the full text (a string or a Readable)")
	assert(
		spec.placeholder == nil or type(spec.placeholder) == "string",
		"Facet motion.newTextReveal: `placeholder` is the string painted while nothing has been revealed"
	)
	local readValue = reader(spec.value)
	local readCursor = if spec.cursor ~= nil then reader(spec.cursor) else nil
	local readPolicy = if spec.policy ~= nil then reader(spec.policy) else nil
	local placeholder = spec.placeholder

	local function visible(use: any?): string
		local value = readValue(use)
		if type(value) ~= "string" then
			value = ""
		end
		if readCursor == nil or (readPolicy ~= nil and readPolicy(use) == "reduced") then
			return value
		end
		local cursor = readCursor(use)
		return prefix(value, if type(cursor) == "number" then cursor else 0)
	end

	local reveal = {}
	-- the string a `UI.Text` binds: the revealed prefix, or the placeholder
	function reveal.text(use: any?): string
		local shown = visible(use)
		if shown == "" and placeholder ~= nil then
			return placeholder
		end
		return shown
	end
	-- true when what is painted is the VALUE, false when it is the placeholder
	function reveal.revealed(use: any?): boolean
		return visible(use) ~= ""
	end
	-- true when the whole value so far is on screen
	function reveal.complete(use: any?): boolean
		local value = readValue(use)
		return type(value) == "string" and visible(use) == value
	end
	return reveal
end

return text_stream
