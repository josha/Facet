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
	hangs: { number }?,
	leading: boolean?,
	trailing: boolean?,
}
export type Strip = { x: number, y: number, lanes: number? }
export type Shift = { top: number, bottom: number, hang: number, leanTop: number, leanBottom: number }
export type Rows = { top: number, bottom: number }
type Stacked = { top: boolean, bottom: boolean }

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

type Extent = { x: number, y: number }

local FLOWS: { [number]: number } = { [9] = 1, [11] = 3 }
local BOTTOM: { number } = { 7, 11, 15 }

local function cellOf(zone: string, riding: boolean, trailing: boolean?): (number, number)
	if zone == "topbar" and riding then
		return 0, 0
	end
	local cell = if zone == "topbar" and trailing then CELLS.topRight else CELLS[zone]
	return cell[1], cell[2]
end

local function resolve(
	width: number,
	height: number,
	gap: number,
	regions: { Declared },
	strip: Strip?,
	stacked: Stacked?,
	leaning: { [string]: number }?
): ({ number }, { boolean }, Shift, { number }, Rows)
	local forms = table.create(#regions, 1)
	local landed = table.create(#regions, false)
	local shift: Shift = { top = 0, bottom = 0, hang = 0, leanTop = 0, leanBottom = 0 }
	if width <= 0 or height <= 0 then
		return forms, landed, shift, {}, { top = 0, bottom = 0 }
	end
	local stack: Stacked = stacked or { top = false, bottom = false }
	local lane = (width - 2 * gap) / 3
	local lean: { [string]: number } = leaning or { top = 0, bottom = 0 }
	while true do
		local zoneW: { [number]: number }, zoneH: { [number]: number }, members: { [number]: { number } } = {}, {}, {}
		local flowItems: { [number]: { Extent } }, landedBlock: { [number]: Extent } = {}, {}
		local hang = 0
		local function between(row: number, edge: string?): (number, number, number, number)
			local left, right = zoneW[4 + row] or 0, zoneW[12 + row] or 0
			local side = math.max(left, right)
			if side <= 0 then
				return width, 0, 0, 0
			end
			local lone = if left > 0 and right <= 0 then 1 elseif right > 0 and left <= 0 then -1 else 0
			if edge and lone ~= 0 and lean[edge] == lone then
				return width - side - gap, lone, side, lone
			end
			return math.max(lane, width - 2 * (side + gap)), 0, side, lone
		end
		for index, region in regions do
			local column, row = cellOf(region.zone, strip ~= nil and not landed[index], region.trailing)
			local key = column * 4 + row
			members[key] = members[key] or {}
			table.insert(members[key], index)
			local form = forms[index]
			local size = if form > 0 then region.sizes[form] else nil
			if size and size.x > 0 and size.y > 0 then
				if row == 3 and region.hangs then
					hang = math.max(hang, region.hangs[form] or 0)
				end
				if key == 0 then
					zoneW[key] = (zoneW[key] or -gap) + gap + size.x
					zoneH[key] = math.max(zoneH[key] or 0, size.y)
				elseif FLOWS[key] then
					local items = flowItems[key] or {}
					flowItems[key] = items
					if region.zone == "topbar" then
						local block = landedBlock[key]
						if block == nil then
							block = { x = 0, y = -gap }
							landedBlock[key] = block
							table.insert(items, 1, block)
						end
						block.x = math.max(block.x, size.x)
						block.y += gap + size.y
					else
						table.insert(items, { x = size.x, y = size.y })
					end
				else
					zoneW[key] = math.max(zoneW[key] or 0, size.x)
					zoneH[key] = (zoneH[key] or -gap) + gap + size.y
				end
			end
		end
		for key, row in FLOWS do
			local items = flowItems[key]
			if items then
				local edge = if row == 1 then "top" else "bottom"
				local room = if stack[edge] then width else (between(row, edge))
				local widest, total, lineW, lineH = 0, -gap, -1, 0
				for _, item in items do
					if lineW >= 0 and lineW + gap + item.x <= room then
						lineW += gap + item.x
						lineH = math.max(lineH, item.y)
					else
						if lineW >= 0 then
							widest = math.max(widest, lineW)
							total += gap + lineH
						end
						lineW, lineH = item.x, item.y
					end
				end
				widest = math.max(widest, lineW)
				total += gap + lineH
				zoneW[key], zoneH[key] = widest, total
			end
		end
		for _, key in BOTTOM do
			if (zoneH[key] or 0) > 0 then
				zoneH[key] += hang
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
		local function check(key: number, room: number, tall: number)
			if (zoneH[key] or 0) > tall then
				fail(key)
			elseif (zoneW[key] or 0) > room then
				fail(key, room)
			end
		end
		if strip then
			local filled: { [string]: boolean } = {}
			local lanes = 0
			for _, index in members[0] or ({} :: { number }) do
				local form = forms[index]
				local size = if form > 0 then regions[index].sizes[form] else nil
				if size and size.x > 0 and size.y > 0 then
					local lane = if regions[index].leading
						then "leading"
						elseif regions[index].trailing then "trailing"
						else "middle"
					if not filled[lane] then
						filled[lane] = true
						lanes += 1
					end
				end
			end
			local empty = if lanes > 0 then math.max(0, (strip.lanes or 1) - lanes) else 0
			if (zoneW[0] or 0) + empty * gap > strip.x then
				fail(0)
			elseif (zoneH[0] or 0) > strip.y then
				for _, index in members[0] or ({} :: { number }) do
					local form = forms[index]
					local size = if form > 0 then regions[index].sizes[form] else nil
					if size and size.y > strip.y then
						failing[index] = true
					end
				end
			end
		end
		local corner = {
			top = math.max(zoneH[5] or 0, zoneH[13] or 0),
			bottom = math.max(zoneH[7] or 0, zoneH[15] or 0),
		}
		local squeezed = { top = false, bottom = false }
		for column = 1, 3 do
			local top, middle, bottom = column * 4 + 1, column * 4 + 2, column * 4 + 3
			for row, key in { top, middle, bottom } do
				local room = lane
				if column ~= 2 and row ~= 2 and (zoneW[8 + row] or 0) == 0 then
					local opposite = zoneW[(if column == 1 then 12 else 4) + row] or 0
					room = math.max(lane, if opposite > 0 then width - opposite - gap else width)
				end
				if column == 2 then
					local edge = if row == 1 then "top" elseif row == 3 then "bottom" else nil
					room = between(row, edge)
					local wide = zoneW[key] or 0
					if edge and stack[edge] then
						room = width
					elseif wide > room then
						if edge then
							squeezed[edge] = true
						end
						if wide <= width and (zoneH[key] or 0) <= height then
							local spare = (width - wide) / 2 - gap
							fail(4 + row, spare)
							fail(12 + row, spare)
						end
					end
				end
				check(key, room, height)
			end
			local h1, h2, h3 = zoneH[top] or 0, zoneH[middle] or 0, zoneH[bottom] or 0
			if column == 2 then
				h1 = if stack.top and h1 > 0 then corner.top + gap + h1 else h1
				h3 = if stack.bottom and h3 > 0 then corner.bottom + gap + h3 else h3
			end
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
		local function clearSides(stacked: boolean, key: number, reach: number)
			local wide = zoneW[key] or 0
			if not stacked or wide <= 0 then
				return
			end
			for _, side in { 6, 14 } do
				local sideW, sideH = zoneW[side] or 0, zoneH[side] or 0
				if sideH > 0 and sideW + gap > (width - wide) / 2 and reach + gap > (height - sideH) / 2 then
					fail(side)
					fail(key)
				end
			end
		end
		clearSides(stack.top, 9, corner.top + gap + (zoneH[9] or 0))
		clearSides(stack.bottom, 11, corner.bottom + gap + (zoneH[11] or 0))
		local chosen: number? = nil
		for index, region in regions do
			local form = forms[index]
			local lands = strip ~= nil and region.zone == "topbar" and not landed[index]
			local steppable = failing[index] and form > 0 and (form < #region.sizes or region.mayDrop or lands)
			if steppable and (chosen == nil or region.rank >= regions[chosen].rank) then
				chosen = index
			end
		end
		if chosen == nil then
			for edge in squeezed do
				local _, _, _, lone = between(if edge == "top" then 1 else 3, edge)
				if squeezed[edge] and not stack[edge] and lean[edge] == 0 and lone ~= 0 then
					local next = { top = lean.top, bottom = lean.bottom }
					next[edge] = lone
					return resolve(width, height, gap, regions, strip, stack, next)
				end
			end
			for edge in squeezed do
				if squeezed[edge] and not stack[edge] and corner[edge] > 0 then
					local next: Stacked = { top = stack.top, bottom = stack.bottom }
					next[edge] = true
					return resolve(width, height, gap, regions, strip, next, lean)
				end
			end
			shift.top = if stack.top and (zoneW[9] or 0) > 0 then corner.top + gap else 0
			shift.bottom = if stack.bottom and (zoneW[11] or 0) > 0 then corner.bottom + gap else 0
			shift.hang = hang
			for row, edge in { [1] = "top", [3] = "bottom" } do
				local _, direction, side = between(row, edge)
				local offset = if stack[edge] or direction == 0 then 0 else direction * (side + gap) / 2
				if edge == "top" then
					shift.leanTop = offset
				else
					shift.leanBottom = offset
				end
			end
			local overflow: { number } = {}
			for index in failing do
				table.insert(overflow, index)
			end
			table.sort(overflow)
			return forms, landed, shift, overflow, { top = zoneW[9] or 0, bottom = zoneW[11] or 0 }
		end
		local region = regions[chosen]
		if forms[chosen] < #region.sizes then
			forms[chosen] += 1
		elseif strip ~= nil and region.zone == "topbar" and not landed[chosen] then
			landed[chosen] = true
			forms[chosen] = 1
		else
			forms[chosen] = 0
		end
	end
end

local function occupied(
	regions: { Declared },
	forms: { number },
	landed: { boolean },
	riding: boolean
): { [string]: boolean }
	local zones: { [string]: boolean } = {}
	for index, region in regions do
		local form = forms[index] or 0
		local size = if form > 0 then region.sizes[form] else nil
		local inStrip = region.zone == "topbar" and riding and not landed[index]
		if size and size.x > 0 and size.y > 0 and not inStrip then
			local home: string = if region.zone == "topbar"
				then (if region.trailing then "topRight" else "top")
				else region.zone
			zones[home] = true
		end
	end
	return zones
end

return {
	CELLS = CELLS,
	occupied = occupied,
	resolve = resolve,
}
