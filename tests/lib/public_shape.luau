--!strict
--[[ THE PUBLIC SHAPE A BREAKING CHANGE MOVES, extracted once (wave
	LAYOUT-FIX fix round 1, controller ruling R15).

	Two shape facts about a public prop can turn working consumer code into broken
	consumer code without any deprecation machinery noticing:

	  * a prop FLIPPING TO REQUIRED — `blueprint_schema.deprecations()` emits a row
	    only for a prop carrying an explicit `deprecated` field, so making one
	    REQUIRED generates nothing at all, and `api_surface.spec` was checking the
	    ledger's SHAPE rather than the schema's;
	  * a DOCUMENTED DEFAULT CHANGING VALUE — the doc is the contract a consumer
	    reads, and a default that silently means something else re-lays out every
	    surface that relied on it.

	This wave shipped one of each (`AdaptiveStack.axis` required, `UI.Grid`'s
	undeclared lane default) and every gate in the repository stayed green over
	both. That blindness is what this module and `api_surface.spec`'s pins close.

	`defaultTokenOf` is the extraction, and it has ONE owner for the usual reason:
	the pin and the live read must be produced by the same function or the pin is a
	claim about a parser that no longer exists.

	WHAT IT EXTRACTS, in order, and why the last rung is a fingerprint. Eighty-eight
	of the ninety-seven documented defaults name their value in one of five shapes a
	regex can lift exactly. The remaining nine state the default in PROSE ("1 =
	opaque (the default)", "Grips are unfocusable by default"), and inventing a
	sixth pattern for each would be a parser nobody could keep true. Those pin a
	NORMALIZED WINDOW around the word instead — enough to move when the default
	statement moves, narrow enough that rewording the rest of a doc does not. ]]

local public_shape = {}

-- defaultTokenOf(doc) -> the value a doc names as its default, or nil if it
-- names none. Pure, total, and safe on a nil or non-string doc.
function public_shape.defaultTokenOf(doc: any): string?
	if type(doc) ~= "string" then
		return nil
	end
	local text = doc :: string
	-- CASE-INSENSITIVE DETECTION, and it is not a nicety: `UI.Grid`'s own
	-- lane-default doc says "the DEFAULT when neither this nor `columns` is
	-- declared", so a lowercase-only search missed the exact change this module
	-- exists to catch. Found by generating the pin and reading it.
	local lowered = string.lower(text)
	local at = string.find(lowered, "default")
	if at == nil then
		return nil
	end
	local token = string.match(text, "%(default[:%s]+([^%)]+)%)")
		or string.match(text, "`([^`]+)`%s*%(default%)")
		or string.match(text, '"([^"]+)"%s*%(default%)')
		or string.match(text, "([%w_]+)%s*%(default[,%)]")
		or string.match(text, "[Dd]efaults? to%s+`([^`]+)`")
		or string.match(text, "[Dd]efaults? to%s+([%w_%.]+)")
	if token ~= nil then
		-- one spelling for a value however the sentence spaced it
		return (string.gsub(string.gsub(token, "^%s+", ""), "%s+$", ""))
	end
	-- THE PROSE RUNG: a normalized window around the word itself
	local window = string.sub(text, math.max(1, at - 26), math.min(#text, at + 26))
	return "prose:" .. (string.gsub(string.gsub(window, "%s+", " "), '"', "'"))
end

return public_shape
