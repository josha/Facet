--!strict
--[[ THE COLOUR VALUE POLICY UI.ColorPicker keeps beside the caller's Color3
	(phase5 P5a, D7).

	CANONICAL IS HSV FLOATS (0..1 each) + alpha. The engine's own `Color3.fromHSV`
	/ `ToHSV` convert; what the engine cannot keep is the hue of a grey — `ToHSV`
	on black or any grey answers hue 0 (measured in Studio) — so
	`hsvOf` takes the previous canonical value and keeps its hue at s = 0 or v = 0
	(and its saturation at v = 0). Text is FORMATTED from canonical and never read
	back except on an explicit commit, so switching readouts cannot walk a colour.

	HEX IS PARSED HERE, not by `Color3.fromHex`: the engine refuses the 8-digit
	form the alpha readout needs and any surrounding space, and formats lowercase
	with no `#` — so both directions would need a branch around it anyway. Channel
	bytes round like the engine (0.5 -> 128 -> "80"). ]]
local color_value = {}

--[[ THE ENGINE'S COLOUR CONSTRUCTORS, read through this table and never as bare
	globals below. Live they are the engine's own; a headless adapter
	(tests/lib/fake_target) hands in Lune's, because defining a global there takes
	`getfenv`, which de-optimises every module sharing the environment. ]]
color_value.engine = { Color3 = Color3 :: any, BrickColor = BrickColor :: any }

export type Hsv = { h: number, s: number, v: number }

local function byte(x: number): number
	return math.clamp(math.floor(x * 255 + 0.5), 0, 255)
end
color_value.byte = byte

-- the engine value's three bytes
function color_value.channels(c: any): (number, number, number)
	return byte(c.R), byte(c.G), byte(c.B)
end

-- "#RRGGBB", or "#RRGGBBAA" when an alpha is given; always uppercase
function color_value.hex(c: any, alpha: number?): string
	local r, g, b = color_value.channels(c)
	local out = string.format("#%02X%02X%02X", r, g, b)
	return if alpha ~= nil then out .. string.format("%02X", byte(alpha)) else out
end

-- the `direct` tint a leaf paints this colour with
function color_value.tintHex(c: any): string
	return string.lower(color_value.hex(c))
end

-- two colours that write the same bytes are the same colour to a player
function color_value.same(a: any, b: any): boolean
	if a == nil or b == nil then
		return a == b
	end
	local ar, ag, ab = color_value.channels(a)
	local br, bg, bb = color_value.channels(b)
	return ar == br and ag == bg and ab == bb
end

--[[ "#RGB", "#RRGGBB", and "#RRGGBBAA" when `allowAlpha`; the `#` is optional,
	case is free, nothing else is trimmed. Answers (color, alpha?) or (nil, nil,
	reason) — a refused text is never a different colour. ]]
function color_value.parseHex(text: string, allowAlpha: boolean): (any, number?, string?)
	local digits = if string.sub(text, 1, 1) == "#" then string.sub(text, 2) else text
	if string.match(digits, "^%x+$") == nil then
		return nil,
			nil,
			if allowAlpha then "Use hex digits: #RGB, #RRGGBB or #RRGGBBAA." else "Use hex digits: #RGB or #RRGGBB."
	end
	if #digits == 3 then
		digits = string.gsub(digits, "%x", "%0%0")
	end
	if #digits == 8 and not allowAlpha then
		return nil, nil, "This colour has no opacity: use #RRGGBB."
	end
	if #digits ~= 6 and #digits ~= 8 then
		return nil, nil, if allowAlpha then "Use #RGB, #RRGGBB or #RRGGBBAA." else "Use #RGB or #RRGGBB."
	end
	local function at(i: number): number
		return tonumber(string.sub(digits, i, i + 1), 16) :: number
	end
	local alpha = if #digits == 8 then at(7) / 255 else nil
	return color_value.fromBytes(at(1), at(3), at(5)), alpha, nil
end

-- the engine conversion, keeping what a grey or black cannot carry
function color_value.hsvOf(c: any, previous: Hsv?): Hsv
	local h, s, v = c:ToHSV()
	if previous ~= nil then
		if v == 0 then
			h, s = previous.h, previous.s
		elseif s == 0 then
			h = previous.h
		end
	end
	return { h = h, s = s, v = v }
end

function color_value.fromBytes(r: number, g: number, b: number): any
	return color_value.engine.Color3.fromRGB(r, g, b)
end

function color_value.toColor(hsv: Hsv): any
	return color_value.engine.Color3.fromHSV(math.clamp(hsv.h, 0, 1), math.clamp(hsv.s, 0, 1), math.clamp(hsv.v, 0, 1))
end

export type Swatch = { color: any, label: string?, key: string }

--[[ THE GENERATED STANDARD GRID the swatches tab shows when the caller gives
	none: eight hues in five value/saturation steps, then eight greys — six rows
	of the eight-column grid. ]]
function color_value.standard(): { Swatch }
	local out: { Swatch } = {}
	local steps = { { 0.35, 1 }, { 0.65, 1 }, { 1, 1 }, { 1, 0.8 }, { 1, 0.55 } } -- { s, v }
	for _, step in steps do
		for i = 0, 7 do
			local c = color_value.toColor({ h = i / 8, s = step[1], v = step[2] })
			table.insert(out, { color = c, key = color_value.hex(c) })
		end
	end
	for i = 0, 7 do
		local c = color_value.toColor({ h = 0, s = 0, v = i / 7 })
		table.insert(out, { color = c, key = color_value.hex(c) })
	end
	return out
end

--[[ THE ENGINE PALETTE (BrickColor.palette 0..127, measured), sorted by hue then
	value, greys first, each labelled with its engine name. ]]
local brickCache: { Swatch }? = nil
function color_value.brick(): { Swatch }
	if brickCache ~= nil then
		return brickCache
	end
	local out: { Swatch & { order: { number } } } = {}
	for i = 0, 127 do
		local brick = color_value.engine.BrickColor.palette(i)
		local c = brick.Color
		local h, s, v = c:ToHSV()
		table.insert(out, {
			color = c,
			label = brick.Name,
			key = brick.Name,
			order = { if s < 0.08 then 0 else 1, if s < 0.08 then 0 else h, v, i },
		})
	end
	table.sort(out, function(a, b)
		for k = 1, 4 do
			if a.order[k] ~= b.order[k] then
				return a.order[k] < b.order[k]
			end
		end
		return false
	end)
	local list: { Swatch } = {}
	for _, entry in out do
		table.insert(list, { color = entry.color, label = entry.label, key = entry.key })
	end
	brickCache = list
	return list
end

return color_value
