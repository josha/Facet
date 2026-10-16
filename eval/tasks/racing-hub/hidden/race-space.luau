--!strict

local Audit = require("../../../../tools/vendor/verify/src/roblox/ui-audit")
export type TouchRect = Audit.Rect & { path: string? }

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

local function textRect(element: Audit.Element): Audit.Rect
	local text = element.text
	assert(text)
	if text.xAlignment == nil or text.yAlignment == nil then
		return element.rect
	end
	local rect = element.rect
	local padding = element.padding or { left = 0, right = 0, top = 0, bottom = 0 }
	local width = rect.width - padding.left - padding.right
	local height = rect.height - padding.top - padding.bottom
	local x = if text.xAlignment == "Right"
		then width - text.bounds.width
		elseif text.xAlignment == "Center" then (width - text.bounds.width) / 2
		else 0
	local y = if text.yAlignment == "Bottom"
		then height - text.bounds.height
		elseif text.yAlignment == "Center" then (height - text.bounds.height) / 2
		else 0
	return {
		x = rect.x + padding.left + x,
		y = rect.y + padding.top + y,
		width = text.bounds.width,
		height = text.bounds.height,
	}
end

local function occluded(dump: Audit.Dump, element: Audit.Element, rect: Audit.Rect): boolean
	for _, cover in dump.elements do
		if not cover.visible or cover.background.transparency > 0.05 then
			continue
		end
		local parent = element.parent
		local ancestor = false
		while parent ~= nil do
			if parent == cover.index then
				ancestor = true
				break
			end
			parent = dump.elements[parent].parent
		end
		if ancestor then
			continue
		end
		local root, other = dump.roots[element.root], dump.roots[cover.root]
		local above = root ~= nil and other ~= nil and other.displayOrder > root.displayOrder
		if cover.root == element.root then
			above = cover.zIndex > element.zIndex
		end
		if not above then
			continue
		end
		local area = clipped(clipped(cover.rect, cover.clip), cover.scrollClip)
		if
			area.x <= rect.x
			and area.y <= rect.y
			and area.x + area.width >= rect.x + rect.width
			and area.y + area.height >= rect.y + rect.height
		then
			return true
		end
	end
	return false
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
	visibleScrimsCover = function(dump: Audit.Dump): boolean
		for _, element in dump.elements do
			local fill = element.background
			local rect = clipped(clipped(element.rect, element.clip), element.scrollClip)
			if
				element.visible
				and fill.transparency > 0
				and fill.transparency < 0.95
				and math.max(fill.color.r, fill.color.g, fill.color.b) < 0.4
				and rect.width > dump.screen.width * 0.7
				and rect.height > dump.screen.height * 0.7
			then
				if
					rect.x > 1
					or rect.y > 1
					or rect.x + rect.width < dump.screen.width - 1
					or rect.y + rect.height < dump.screen.height - 1
				then
					return false
				end
			end
		end
		return true
	end,
	touchControlsClear = function(dump: Audit.Dump, regions: { TouchRect }): boolean
		for _, element in dump.elements do
			local text = element.text
			local hud = text ~= nil and text.content ~= "" and text.transparency < 0.95
			if
				not element.visible or not (hud or ((element.interactive or element.active) and element.interactable))
			then
				continue
			end
			local rect = clipped(clipped(element.rect, element.clip), element.scrollClip)
			if occluded(dump, element, rect) then
				continue
			end
			for _, region in regions do
				local native = region.path ~= nil
					and (element.path == region.path or string.find(element.path, region.path .. ".", 1, true) == 1)
				if not native and intersects(rect, region) then
					return false
				end
			end
		end
		return true
	end,
	scrimCovers = function(dump: Audit.Dump): boolean
		local modal = false
		local covered = false
		local screen = dump.screen
		for _, element in dump.elements do
			if not element.visible then
				continue
			end
			local text = if element.text then string.lower(element.text.content) else ""
			modal = modal or (element.interactive and (text == "close" or text == "back" or text == "cancel"))
			local background = element.background
			if
				background.transparency >= 0
				and background.transparency < 0.95
				and math.max(background.color.r, background.color.g, background.color.b) < 0.4
			then
				local rect = clipped(clipped(element.rect, element.clip), element.scrollClip)
				modal = modal or (rect.width > screen.width * 0.7 and rect.height > screen.height * 0.7)
				covered = covered
					or (
						rect.x <= 1
						and rect.y <= 1
						and rect.x + rect.width >= screen.width - 1
						and rect.y + rect.height >= screen.height - 1
					)
			end
		end
		return not modal or covered
	end,
	safeContent = function(dump: Audit.Dump): boolean
		local screen = dump.screen
		local device = screen.safeArea or { x = 0, y = 0, width = screen.width, height = screen.height }
		local left = math.max(device.x, screen.guiInset.left)
		local top = math.max(device.y, screen.guiInset.top)
		local right = math.min(device.x + device.width, screen.width - screen.guiInset.right)
		local bottom = math.min(device.y + device.height, screen.height - screen.guiInset.bottom)
		for _, element in dump.elements do
			local text = element.text
			local paintsText = text ~= nil and text.content ~= "" and text.transparency < 0.95
			local input = element.interactive and element.interactable
			if not element.visible or not (paintsText or input) then
				continue
			end
			local rect = clipped(clipped(element.rect, element.clip), element.scrollClip)
			local outside = rect.x < left - 1
				or rect.y < top - 1
				or rect.x + rect.width > right + 1
				or rect.y + rect.height > bottom + 1
			local strip = screen.topbarSafeArea
			if outside and strip ~= nil then
				outside = rect.x < strip.x - 1
					or rect.y < strip.y - 1
					or rect.x + rect.width > strip.x + strip.width + 1
					or rect.y + rect.height > strip.y + strip.height + 1
			end
			if rect.width > 1 and rect.height > 1 and outside then
				return false
			end
		end
		return true
	end,
	selectionValid = function(dump: Audit.Dump): boolean
		if dump.selected == nil then
			return true
		end
		local selected = dump.elements[dump.selected]
		return selected ~= nil and selected.visible and selected.interactable and selected.selectable
	end,
	textClear = function(dump: Audit.Dump): boolean
		local texts: { Audit.Rect } = {}
		for _, element in dump.elements do
			local text = element.text
			if not element.visible or text == nil or text.content == "" or text.transparency >= 0.95 then
				continue
			end
			local rect = clipped(clipped(textRect(element), element.clip), element.scrollClip)
			rect = clipped(rect, { x = 0, y = 0, width = dump.screen.width, height = dump.screen.height })
			if occluded(dump, element, rect) then
				continue
			end
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
}
