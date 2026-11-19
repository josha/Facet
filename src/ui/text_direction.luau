--!strict

export type Base = "ltr" | "rtl"

local NEUTRAL: { { number } } = {
	{ 0x0000, 0x0040 },
	{ 0x005B, 0x0060 },
	{ 0x007B, 0x00BF },
	{ 0x00D7, 0x00D7 },
	{ 0x00F7, 0x00F7 },
	{ 0x0300, 0x036F },
	{ 0x0660, 0x0669 },
	{ 0x06F0, 0x06F9 },
	{ 0x2000, 0x2BFF },
	{ 0x2E00, 0x2E7F },
	{ 0x3000, 0x303F },
	{ 0xFE00, 0xFE6F },
	{ 0xFEFF, 0xFEFF },
	{ 0xFF00, 0xFF20 },
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

local function plain(text: string, rich: boolean): string
	if not rich then
		return text
	end
	return (string.gsub(string.gsub(text, "<[^>]*>", ""), "&[#%w]+;", ""))
end

local function base(text: string, rich: boolean): Base
	local source = plain(text, rich)
	if utf8.len(source) == nil then
		return "ltr"
	end
	local isolated = 0
	for _, point in utf8.codes(source) do
		if point == LRI or point == RLI or point == FSI then
			isolated += 1
		elseif point == PDI then
			isolated = math.max(isolated - 1, 0)
		elseif isolated == 0 then
			if point == LRM then
				return "ltr"
			elseif point == RLM then
				return "rtl"
			elseif within(RIGHT, point) and not within(NEUTRAL, point) then
				return "rtl"
			elseif not within(NEUTRAL, point) then
				return "ltr"
			end
		end
	end
	return "ltr"
end

return table.freeze({ base = base })
