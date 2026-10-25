--!strict
export type Rect = { x: number, y: number, width: number, height: number }
export type Element = { path: string, rect: Rect, visible: boolean }
export type Violation = {
	rule: string,
	severity: "high" | "medium" | "low",
	path: string,
	detail: string,
	value: number?,
}

local CORNERS: { [string]: { string } } = {
	Top = { "TopLeft", "TopRight" },
	Bottom = { "BottomLeft", "BottomRight" },
}

local function filled(element: Element?): boolean
	return element ~= nil and element.visible and element.rect.width > 0.5 and element.rect.height > 0.5
end

local function problems(elements: { Element }): { Violation }
	local zones: { [string]: { [string]: Element } } = {}
	for _, element in elements do
		local owner, zone = string.match(element.path, "^(.*%.Zones)%.(%a+)$")
		if owner and zone then
			zones[owner] = zones[owner] or {}
			zones[owner][zone] = element
		end
	end
	local found: { Violation } = {}
	for _, frames in zones do
		for zone, corners in CORNERS do
			local middle = frames[zone]
			if not filled(middle) then
				continue
			end
			local lane = (middle :: Element).rect
			for _, name in corners do
				local corner = frames[name]
				if not filled(corner) then
					continue
				end
				local box = (corner :: Element).rect
				local under = if zone == "Top"
					then lane.y >= box.y + box.height - 1
					else lane.y + lane.height <= box.y + 1
				local across = lane.x < box.x + box.width and box.x < lane.x + lane.width
				if under and across then
					local violation: Violation = {
						rule = "hud-in-view",
						severity = "medium",
						path = (middle :: Element).path,
						detail = `the {string.lower(zone)} zone moved {if zone == "Top" then "under" else "over"} the {name} zone, into the play view`,
					}
					table.insert(found, violation)
					break
				end
			end
		end
	end
	return found
end

return { problems = problems }
