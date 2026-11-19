--!strict

export type Base = "ltr" | "rtl"

local NEUTRAL: { { number } } = {
	{ 0x0000, 0x0040 },
	{ 0x005B, 0x0060 },
	{ 0x007B, 0x00A9 },
	{ 0x00AB, 0x00B4 },
	{ 0x00B6, 0x00B9 },
	{ 0x00BB, 0x00BF },
	{ 0x00D7, 0x00D7 },
	{ 0x00F7, 0x00F7 },
	{ 0x0300, 0x036F },
	{ 0x0483, 0x0489 },
	{ 0x0591, 0x05BD },
	{ 0x05BF, 0x05BF },
	{ 0x05C1, 0x05C2 },
	{ 0x05C4, 0x05C5 },
	{ 0x05C7, 0x05C7 },
	{ 0x0600, 0x0605 },
	{ 0x060C, 0x060C },
	{ 0x0610, 0x061A },
	{ 0x064B, 0x065F },
	{ 0x0660, 0x066C },
	{ 0x0670, 0x0670 },
	{ 0x06D6, 0x06ED },
	{ 0x06F0, 0x06F9 },
	{ 0x2000, 0x215F },
	{ 0x2189, 0x27FF },
	{ 0x2900, 0x2BFF },
	{ 0x2E00, 0x2E7F },
	{ 0x3000, 0x3004 },
	{ 0x3008, 0x3020 },
	{ 0x302A, 0x3030 },
	{ 0x3036, 0x3037 },
	{ 0x303D, 0x303F },
	{ 0xFE00, 0xFE6F },
	{ 0xFEFF, 0xFEFF },
	{ 0xFF00, 0xFF20 },
	{ 0xFF3B, 0xFF40 },
	{ 0xFF5B, 0xFF65 },
	{ 0xFFF0, 0xFFFF },
	{ 0x1F000, 0x1FAFF },
	{ 0xE0000, 0xE007F },
}

local RIGHT: { { number } } = {
	{ 0x0590, 0x08FF },
	{ 0xFB1D, 0xFDFF },
	{ 0xFE70, 0xFEFE },
	{ 0x10800, 0x10FFF },
	{ 0x1E800, 0x1EFFF },
}

local LRM, RLM = 0x200E, 0x200F
local LRI, RLI, FSI, PDI = 0x2066, 0x2067, 0x2068, 0x2069

local function within(ranges: { { number } }, point: number): boolean
	for _, range in ranges do
		if point >= range[1] and point <= range[2] then
			return true
		end
	end
	return false
end

local function decoded(point: number?): string
	return if point ~= nil
			and point >= 0
			and point <= 0x10FFFF
			and (point < 0xD800 or point > 0xDFFF)
		then utf8.char(point)
		else ""
end

local function plain(text: string, rich: boolean): string
	if not rich then
		return text
	end
	local stripped = string.gsub(text, "<[^>]*>", "")
	stripped = string.gsub(stripped, "&#[xX](%x+);", function(digits: string): string
		return decoded(tonumber(digits, 16))
	end)
	stripped = string.gsub(stripped, "&#(%d+);", function(digits: string): string
		return decoded(tonumber(digits))
	end)
	return (string.gsub(stripped, "&%w+;", ""))
end

local function base(text: string, rich: boolean): Base
	local source = plain(text, rich)
	local found: Base? = nil
	pcall(function()
		local isolated = 0
		for _, point in utf8.codes(source) do
			if point == LRI or point == RLI or point == FSI then
				isolated += 1
			elseif point == PDI then
				isolated = math.max(isolated - 1, 0)
			elseif isolated == 0 then
				if point == LRM then
					found = "ltr"
				elseif point == RLM then
					found = "rtl"
				elseif not within(NEUTRAL, point) then
					found = if within(RIGHT, point) then "rtl" else "ltr"
				end
				if found ~= nil then
					return
				end
			end
		end
	end)
	return found or "ltr"
end

return table.freeze({ base = base })
