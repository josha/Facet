--!strict
export type Hsv = { h: number, s: number, v: number }
export type Swatch = { color: Color3, label: string?, key: string }
export type Engine = { Color3: typeof(Color3), BrickColor: typeof(BrickColor)? }
export type ColorValue = {
	byte: (number) -> number,
	channels: (Color3) -> (number, number, number),
	hex: (Color3, number?) -> string,
	same: (Color3?, Color3?) -> boolean,
	parseHex: (string, boolean) -> (Color3?, number?, string?),
	hsvOf: (Color3, Hsv?) -> Hsv,
	fromBytes: (number, number, number) -> Color3,
	toColor: (Hsv) -> Color3,
	standard: (number?) -> { Swatch },
	brick: () -> { Swatch },
}

local function byte(x: number): number
	return math.clamp(math.floor(x * 255 + 0.5), 0, 255)
end

return function(engine: Engine): ColorValue
	local color = {} :: ColorValue
	color.byte = byte
	function color.channels(c: Color3): (number, number, number)
		return byte(c.R), byte(c.G), byte(c.B)
	end
	function color.hex(c: Color3, alpha: number?): string
		local r, g, b = color.channels(c)
		local out = string.format("#%02X%02X%02X", r, g, b)
		return if alpha ~= nil then out .. string.format("%02X", byte(alpha)) else out
	end
	function color.same(a: Color3?, b: Color3?): boolean
		if a == nil or b == nil then
			return a == b
		end
		local ar, ag, ab = color.channels(a)
		local br, bg, bb = color.channels(b)
		return ar == br and ag == bg and ab == bb
	end
	function color.fromBytes(r: number, g: number, b: number): Color3
		return engine.Color3.fromRGB(r, g, b)
	end
	function color.parseHex(text: string, allowAlpha: boolean): (Color3?, number?, string?)
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
		return color.fromBytes(at(1), at(3), at(5)), alpha, nil
	end
	function color.hsvOf(c: Color3, previous: Hsv?): Hsv
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
	function color.toColor(hsv: Hsv): Color3
		return engine.Color3.fromHSV(math.clamp(hsv.h, 0, 1), math.clamp(hsv.s, 0, 1), math.clamp(hsv.v, 0, 1))
	end
	function color.standard(hues: number?): { Swatch }
		local n = math.max(2, hues or 8)
		local out: { Swatch } = {}
		for _, step in { { 0.35, 1 }, { 0.65, 1 }, { 1, 1 }, { 1, 0.8 }, { 1, 0.55 } } do
			for i = 0, n - 1 do
				local c = color.toColor({ h = i / n, s = step[1], v = step[2] })
				table.insert(out, { color = c, key = color.hex(c) })
			end
		end
		for i = 0, n - 1 do
			local c = color.toColor({ h = 0, s = 0, v = i / (n - 1) })
			table.insert(out, { color = c, key = color.hex(c) })
		end
		return out
	end
	local brickCache: { Swatch }? = nil
	function color.brick(): { Swatch }
		if brickCache ~= nil then
			return brickCache
		end
		local palette = assert(engine.BrickColor, "Facet ColorPicker: the brick mode requires BrickColor")
		local out: { { swatch: Swatch, order: { number } } } = {}
		for i = 0, 127 do
			local brick = palette.palette(i)
			local c = brick.Color
			local h, s, v = c:ToHSV()
			table.insert(out, {
				swatch = { color = c, label = brick.Name, key = brick.Name },
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
			table.insert(list, entry.swatch)
		end
		brickCache = list
		return list
	end
	return color
end
