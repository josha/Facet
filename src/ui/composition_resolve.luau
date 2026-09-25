--!strict
export type Zone =
	"topLeft"
	| "top"
	| "topRight"
	| "left"
	| "center"
	| "right"
	| "bottomLeft"
	| "bottom"
	| "bottomRight"
	| "topbar"
export type Declared = {
	zone: Zone,
	rank: number,
	mayDrop: boolean,
	sizes: { { x: number, y: number } },
}

local CELLS: { [string]: { number } } = {
	topLeft = { 1, 1 },
	top = { 2, 1 },
	topRight = { 3, 1 },
	left = { 1, 2 },
	center = { 2, 2 },
	right = { 3, 2 },
	bottomLeft = { 1, 3 },
	bottom = { 2, 3 },
	bottomRight = { 3, 3 },
	topbar = { 2, 1 },
}

local function cellOf(zone: string, riding: boolean): (number, number)
	if zone == "topbar" and riding then
		return 0, 0
	end
	local cell = CELLS[zone]
	return cell[1], cell[2]
end

return {
	CELLS = CELLS,
	resolve = function(
		width: number,
		height: number,
		gap: number,
		regions: { Declared },
		strip: { x: number, y: number }?
	): { number }
		local forms = table.create(#regions, 1)
		if width <= 0 or height <= 0 then
			return forms
		end
		local lane = (width - 2 * gap) / 3
		local riding = strip ~= nil
		while true do
			local zoneW: { [number]: number }, zoneH: { [number]: number }, members: { [number]: { number } } =
				{}, {}, {}
			for index, region in regions do
				local column, row = cellOf(region.zone, riding)
				local key = column * 4 + row
				members[key] = members[key] or {}
				table.insert(members[key], index)
				local form = forms[index]
				local size = if form > 0 then region.sizes[form] else nil
				if size and size.x > 0 and size.y > 0 then
					zoneW[key] = math.max(zoneW[key] or 0, size.x)
					zoneH[key] = (zoneH[key] or -gap) + gap + size.y
				end
			end
			local failing: { [number]: boolean } = {}
			local function fail(key: number, wider: number?)
				for _, index in members[key] or ({} :: { number }) do
					local form = forms[index]
					local size = if form > 0 then regions[index].sizes[form] else nil
					if wider == nil or (size and size.x > wider) then
						failing[index] = true
					end
				end
			end
			local function check(key: number, width: number, tall: number)
				if (zoneH[key] or 0) > tall then
					fail(key)
				elseif (zoneW[key] or 0) > width then
					fail(key, width)
				end
			end
			if strip then
				check(0, strip.x, strip.y)
			end
			for column = 1, 3 do
				local top, middle, bottom = column * 4 + 1, column * 4 + 2, column * 4 + 3
				for _, key in { top, middle, bottom } do
					check(key, lane, height)
				end
				local h1, h2, h3 = zoneH[top] or 0, zoneH[middle] or 0, zoneH[bottom] or 0
				if h2 > 0 then
					if h1 > 0 and h1 + gap > (height - h2) / 2 then
						fail(top)
						fail(middle)
					end
					if h3 > 0 and (height + h2) / 2 + gap > height - h3 then
						fail(bottom)
						fail(middle)
					end
				elseif h1 > 0 and h3 > 0 and h1 + gap + h3 > height then
					fail(top)
					fail(bottom)
				end
			end
			local chosen: number? = nil
			for index, region in regions do
				local form = forms[index]
				local steppable = failing[index] and form > 0 and (form < #region.sizes or region.mayDrop)
				if steppable and (chosen == nil or region.rank >= regions[chosen].rank) then
					chosen = index
				end
			end
			if chosen == nil then
				return forms
			end
			local region = regions[chosen]
			forms[chosen] = if forms[chosen] < #region.sizes then forms[chosen] + 1 else 0
		end
	end,
}
