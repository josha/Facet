--!strict
local arithmetic = {}

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

function arithmetic.number(text: unknown): number?
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

function arithmetic.incomplete(text: unknown): boolean
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

function arithmetic.parse(text: unknown): number?
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
