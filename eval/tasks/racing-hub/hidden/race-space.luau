--!strict

local Audit = require("../../../../tools/vendor/verify/src/roblox/ui-audit")

local function intersects(a: Audit.Rect, b: Audit.Rect): boolean
	return a.width > 0
		and a.height > 0
		and a.x < b.x + b.width
		and a.x + a.width > b.x
		and a.y < b.y + b.height
		and a.y + a.height > b.y
end

local function clipped(rect: Audit.Rect, clip: Audit.Rect?): Audit.Rect
	if clip == nil then
		return rect
	end
	local x, y = math.max(rect.x, clip.x), math.max(rect.y, clip.y)
	return {
		x = x,
		y = y,
		width = math.max(0, math.min(rect.x + rect.width, clip.x + clip.width) - x),
		height = math.max(0, math.min(rect.y + rect.height, clip.y + clip.height) - y),
	}
end

local function clear(dump: Audit.Dump, region: Audit.Rect, interactiveOnly: boolean): boolean
	for _, element in dump.elements do
		if not element.visible then
			continue
		end
		local paints = element.background.transparency < 0.95
			or (element.text ~= nil and element.text.content ~= "" and element.text.transparency < 0.95)
			or (element.image ~= nil and element.image.transparency < 0.95)
		if if interactiveOnly then (element.interactive or element.active) and element.interactable else paints then
			local rect = clipped(clipped(element.rect, element.clip), element.scrollClip)
			if intersects(rect, region) then
				return false
			end
		end
	end
	return true
end

return {
	textClear = function(dump: Audit.Dump): boolean
		local texts: { Audit.Rect } = {}
		for _, element in dump.elements do
			local text = element.text
			if not element.visible or text == nil or text.content == "" or text.transparency >= 0.95 then
				continue
			end
			local rect = clipped(clipped(element.rect, element.clip), element.scrollClip)
			rect = clipped(rect, { x = 0, y = 0, width = dump.screen.width, height = dump.screen.height })
			for _, previous in texts do
				local shared = clipped(rect, previous)
				if shared.width > 1 and shared.height > 1 then
					return false
				end
			end
			table.insert(texts, rect)
		end
		return true
	end,
	centerClear = function(dump: Audit.Dump): boolean
		local screen = dump.screen
		return clear(
			dump,
			{ x = screen.width / 3, y = screen.height * 0.35, width = screen.width / 3, height = screen.height * 0.3 },
			false
		)
	end,
	thumbstickClear = function(dump: Audit.Dump): boolean
		local screen = dump.screen
		return clear(
			dump,
			{ x = 0, y = screen.height * 0.6, width = screen.width * 0.35, height = screen.height * 0.4 },
			true
		)
	end,
}
