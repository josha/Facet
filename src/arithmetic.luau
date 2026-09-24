--!strict
--[[ A FOUR-FUNCTION CALCULATOR FOR A NUMERIC FIELD — the recipe, not a key.

	A numeric field takes a `parse` function, and "let me type `3 + 5` in the box"
	is the one extension of that everybody asks for. It is a RECIPE rather than a
	`calculator = true` key because it is exactly one line at the call site:

	    UI.NumberInput { …, parse = Facet.recipes.arithmetic.parse }

	and because a field that accepts arithmetic is a product decision — a price, a
	lap count and a seed are three different answers to "should `2*3` mean 6".

	TOTAL, AND BOUNDED SO IT CAN BE. `parse` answers a number or nothing for ANY
	string, which is what its callers are promised — so it caps the input length and
	the nesting depth up front rather than recursing until the stack gives out. A
	field's own commit runs it inside a `pcall`; a direct public caller has no such
	net, and "the worst a player can type is nothing" has to be true for them too.

	NEVER COMPILE THE TEXT. Text a player typed is not code, and a field that runs
	it through the language's own loader is an arbitrary-execution seam wearing a
	convenience's clothes. This is a recursive-descent parser over four operators
	and parentheses within the bounds above: it can produce a number or nothing,
	and there is no third outcome it could be talked into.

	  expr    := term (('+' | '-') term)*
	  term    := factor (('*' | '/') factor)*
	  factor  := ('+' | '-')* primary
	  primary := number | '(' expr ')'

	THE TYPOGRAPHIC OPERATORS COUNT — see the token table below.

	DIVISION BY ZERO IS REJECTED, not infinite: a field whose value became `inf`
	would fail every bound it has and format as a word. `nil` is the whole failure
	channel, which is exactly what a `parse` function's contract already says.

	Depends on nothing, so it is safe to require from anywhere and testable with no
	engine.
]]

local arithmetic = {}

--[[ ONE NUMBER GRAMMAR, shared with the plain numeric field: optional sign,
	digits, at most one `.`, no exponent and no grouping. `tonumber` is wider than
	this on purpose — it reads `0x1F`, `1e9` and surrounding blanks — and a field
	that silently accepts a hex literal is a field nobody can predict. ]]
local function readNumber(text: string, at: number): (number?, number)
	local digits, nextAt = string.match(text, "^(%d*%.?%d*)()", at)
	if digits == nil or digits == "" or digits == "." then
		return nil, at
	end
	local value = tonumber(digits)
	if value == nil or value ~= value then
		return nil, at
	end
	return value, nextAt :: number
end

--[[ THE OPERATOR TOKENS, each as the exact bytes it is. A player on a phone
	keyboard, or anyone who pasted from a document, arrives with the typographic
	multiplication, division and minus signs rather than the ASCII three, so each
	operator lists every spelling and the tokenizer advances by the length of the
	one it matched. ]]
local TIMES = { "*", "\u{00D7}", "\u{2715}" }
local OVER = { "/", "\u{00F7}" }
local MINUS = { "-", "\u{2212}" }
local PLUS = { "+" }

local function matchAny(text: string, at: number, tokens: { string }): string?
	for _, token in tokens do
		if string.sub(text, at, at + #token - 1) == token then
			return token
		end
	end
	return nil
end

-- arithmetic.number(text) -> number? — the strict grammar above over a WHOLE
-- string, which is the plain numeric field's own parser.
function arithmetic.number(text: any): number?
	if type(text) ~= "string" then
		return nil
	end
	local sign = matchAny(text, 1, MINUS) or matchAny(text, 1, PLUS)
	local rest = if sign ~= nil then string.sub(text, #sign + 1) else text
	local value, at = readNumber(rest, 1)
	if value == nil or at ~= #rest + 1 then
		return nil
	end
	return if sign ~= nil and sign ~= "+" then -value else value
end

--[[ arithmetic.incomplete(text) -> boolean — the drafts a person types ON THE WAY
	to a number: nothing yet, a lone sign, a lone decimal point, a sign and a point.
	They are not errors and they are never committed; a field reverts to its last
	committed number instead of shouting at someone mid-keystroke. ]]
function arithmetic.incomplete(text: any): boolean
	if type(text) ~= "string" then
		return true
	end
	local sign = matchAny(text, 1, MINUS) or matchAny(text, 1, PLUS)
	local rest = if sign ~= nil then string.sub(text, #sign + 1) else text
	return rest == "" or rest == "."
end

local function skipBlanks(text: string, at: number): number
	local _, stop = string.find(text, "^%s*", at)
	return (stop :: number) + 1
end

--[[ THE TWO BOUNDS. 256 characters is far past any number or expression a field
	is for and far short of anything that costs time; 32 levels of nesting is deeper
	than an expression a person writes by hand and shallow enough that the recursion
	cannot reach the stack's end. Past either, the answer is `nil` — the same answer
	every other malformed input gets, through the same channel. ]]
local MAX_LENGTH = 256
local MAX_DEPTH = 32

type State = { text: string, at: number, failed: boolean, depth: number }

local parseExpr

local function parsePrimary(s: State): number
	s.at = skipBlanks(s.text, s.at)
	if string.sub(s.text, s.at, s.at) == "(" then
		s.depth += 1
		if s.depth > MAX_DEPTH then
			s.failed = true
			return 0
		end
		s.at += 1
		local inner = parseExpr(s)
		s.depth -= 1
		s.at = skipBlanks(s.text, s.at)
		if string.sub(s.text, s.at, s.at) ~= ")" then
			s.failed = true
			return 0
		end
		s.at += 1
		return inner
	end
	local value, nextAt = readNumber(s.text, s.at)
	if value == nil then
		s.failed = true
		return 0
	end
	s.at = nextAt
	return value
end

local function parseFactor(s: State): number
	s.at = skipBlanks(s.text, s.at)
	local plus = matchAny(s.text, s.at, PLUS)
	local minus = if plus == nil then matchAny(s.text, s.at, MINUS) else nil
	local sign = plus or minus
	if sign == nil then
		return parsePrimary(s)
	end
	-- a run of signs recurses once per sign, so it counts against the same depth
	s.depth += 1
	if s.depth > MAX_DEPTH then
		s.failed = true
		return 0
	end
	s.at += #sign
	local inner = parseFactor(s)
	s.depth -= 1
	return if minus ~= nil then -inner else inner
end

local function parseTerm(s: State): number
	local value = parseFactor(s)
	while not s.failed do
		s.at = skipBlanks(s.text, s.at)
		local times = matchAny(s.text, s.at, TIMES)
		local over = if times == nil then matchAny(s.text, s.at, OVER) else nil
		local token = times or over
		if token == nil then
			break
		end
		s.at += #token
		local rhs = parseFactor(s)
		if s.failed then
			return 0
		end
		if over ~= nil then
			if rhs == 0 then
				-- a value of infinity fails every bound it has and formats as a word
				s.failed = true
				return 0
			end
			value /= rhs
		else
			value *= rhs
		end
	end
	return value
end

function parseExpr(s: State): number
	local value = parseTerm(s)
	while not s.failed do
		s.at = skipBlanks(s.text, s.at)
		local minus = matchAny(s.text, s.at, MINUS)
		local plus = if minus == nil then matchAny(s.text, s.at, PLUS) else nil
		local token = minus or plus
		if token == nil then
			break
		end
		s.at += #token
		local rhs = parseTerm(s)
		if s.failed then
			return 0
		end
		value = if minus ~= nil then value - rhs else value + rhs
	end
	return value
end

--[[ arithmetic.parse(text) -> number? — the whole recipe. Hand it to a numeric
	field's `parse`; it answers a finite number or nothing, and nothing is how a
	`parse` function says "this is not a value". ]]
function arithmetic.parse(text: any): number?
	if type(text) ~= "string" then
		return nil
	end
	if #text > MAX_LENGTH then
		return nil
	end
	local s: State = { text = text, at = 1, failed = false, depth = 0 }
	local value = parseExpr(s)
	s.at = skipBlanks(s.text, s.at)
	if s.failed or s.at ~= #s.text + 1 then
		return nil
	end
	if value ~= value or math.abs(value) == math.huge then
		return nil
	end
	return value
end

return arithmetic
