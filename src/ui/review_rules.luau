--!strict
export type ReviewRect = { x: number, y: number, width: number, height: number }
export type ReviewColor = { r: number, g: number, b: number }
export type ReviewText = {
	content: string,
	size: number,
	bold: boolean,
	font: string?,
	role: string?,
	color: ReviewColor,
	transparency: number,
}
export type ReviewElement = {
	index: number,
	parent: number?,
	class: string,
	path: string,
	rect: ReviewRect,
	visible: boolean,
	interactive: boolean,
	fill: ReviewColor,
	fillTransparency: number,
	image: boolean,
	text: ReviewText?,
}
export type ReviewSnapshot = { width: number, height: number, elements: { ReviewElement }, touch: boolean? }
export type ReviewSeverity = "high" | "medium" | "low"
export type ReviewFinding = {
	rule: string,
	severity: ReviewSeverity,
	path: string,
	detail: string,
	rect: ReviewRect,
}
export type ReviewProminence = {
	path: string,
	content: string,
	size: number,
	role: string?,
	bold: boolean,
	score: number,
}
export type ReviewReport = {
	findings: { ReviewFinding },
	prominence: { ReviewProminence },
	sizes: { number },
	fixes: { [string]: string },
	text: string,
}

local SEPARATORS = { " · ", " • ", " | ", " / ", " – " }
local SEVERITY_RANK: { [ReviewSeverity]: number } = { high = 1, medium = 2, low = 3 }
local RECIPES = "See the information-display reference in the use-facet skill."

local FIXES: { [string]: string } = table.freeze({
	["joined-facts"] = "One text joins several facts with separators, so no fact leads and values cannot be compared. Give each fact its own element: the value in the numeral or strong role and its label in caption beside or under it. "
		.. RECIPES,
	["numbers-unemphasized"] = "The numbers on this screen are no larger or heavier than the text around them. Put the value that drives the decision in the numeral role, larger than body text, with its unit or label smaller. "
		.. RECIPES,
	["flat-hierarchy"] = "The largest text is close to the common text size, so nothing leads. Choose the one thing to see first and make it clearly larger (1.6 times body or more); quiet the rest.",
	["competing-peaks"] = "Two different texts share the largest size in one group, so they compete. Keep one peak per group: make one the lead and set the other as a label in caption or label.",
	["record-without-visual"] = "Repeated items have no visual, so the player reads every name to tell them apart. Give each item its image or model, or else a glyph from the theme icon set, beside its name. Rows that only compare facts belong in a Table. "
		.. RECIPES,
	["nested-surface"] = "A plate sits inside a plate of nearly the same color. Keep one plate per layer; separate groups with space or one hairline.",
	["zero-wall"] = "Most numbers on this screen are zero. Replace an all-zero record with its goal: what the player does next and how far it is.",
	["single-weight"] = "Every text uses one font and one weight. Give the lead and the values a heavier weight than labels and body text.",
	["stacked-choices"] = "Short choices are stacked in a narrow column inside a wide space, so the player scrolls past one option per row. Put color swatches, chips and filters in an HStack with wrap = true or a Grid that fills the width, and show a few peer actions in one row. AdaptiveStack turns into this column when its row does not fit.",
	["hollow-plate"] = "A plate is much larger than what it holds: the content uses a small corner and the rest is empty. Size the plate to its content, put repeated items in a Grid whose column count follows the width, or give the empty room to the subject.",
	["lopsided-page"] = 'The page content sits on one side of a wide surface and leaves the other side empty. Center a bounded column (width = "fill" with maxWidth, align = "center" on the Screen), or use the room for a second pane such as the selected item\'s detail.',
	["floating-text"] = "Several texts sit straight on the 3D world with no plate, so the scene shows through and they collide with signs and bright objects. Group HUD readouts on a panel surface, or give each a stroke.",
	["touch-control-overlap"] = "A control covers the place where Roblox draws the Jump button on touch screens. On touch, raise the bottom of the Composition above the thumb controls with bottom padding, or move the control.",
	["stranded-content"] = "The content fills a small part of a large surface and sits to one side. Bound the surface to its content or use the space for the subject.",
})

local function clean(content: string): string
	local plain = string.gsub(content, "<[^>]+>", "")
	plain = string.gsub(plain, "%s+", " ")
	plain = string.gsub(plain, "^ ", "")
	plain = string.gsub(plain, " $", "")
	return plain
end

local function split(line: string): { string }
	local text = " " .. line .. " "
	local parts: { string } = {}
	local start, position = 1, 1
	while true do
		local found: number?, finish: number?, separator: string? = nil, nil, nil
		for _, candidate in SEPARATORS do
			local i, j = string.find(text, candidate, position, true)
			if i ~= nil and (found == nil or i < (found :: number)) then
				found, finish, separator = i, j, candidate
			end
		end
		if found == nil or finish == nil then
			break
		end
		local before = string.sub(text, found - 1, found - 1)
		local after = string.sub(text, finish + 1, finish + 1)
		local range = (separator == " / " or separator == " – ")
			and string.match(before, "%d") ~= nil
			and string.match(after, "%d") ~= nil
		if not range then
			table.insert(parts, string.sub(text, start, found - 1))
			start = finish + 1
		end
		position = finish + 1
	end
	table.insert(parts, string.sub(text, start))
	local kept: { string } = {}
	for _, part in parts do
		local trimmed = string.gsub(string.gsub(part, "^%s+", ""), "%s+$", "")
		if trimmed ~= "" then
			table.insert(kept, trimmed)
		end
	end
	return kept
end

local function lines(content: string): { string }
	local plain = string.gsub(content, "<[^>]+>", "")
	local found: { string } = {}
	for line in string.gmatch(plain .. "\n", "([^\n]*)\n") do
		local item = string.gsub(string.gsub(line, "%s+", " "), "^ ", "")
		item = string.gsub(item, "^[•·%-%*] ", "")
		item = string.gsub(item, " $", "")
		if item ~= "" then
			table.insert(found, item)
		end
	end
	return found
end

local function segments(content: string): { string }
	local found = lines(content)
	if #found ~= 1 then
		return if #found == 0 then {} else { content }
	end
	return split(found[1])
end

local function numbers(content: string): { number }
	local found: { number } = {}
	local rest = string.gsub(content, "%d+:%d+[:%d%.]*", function(time: string): string
		table.insert(found, if string.find(time, "[1-9]") then 1 else 0)
		return " "
	end)
	for token in string.gmatch(rest, "%d[%d,]*%.?%d*") do
		local value = tonumber((string.gsub(token, ",", "")))
		if value ~= nil then
			table.insert(found, value)
		end
	end
	return found
end

local function channel(value: number): number
	return if value <= 0.03928 then value / 12.92 else ((value + 0.055) / 1.055) ^ 2.4
end

local function luminance(color: ReviewColor): number
	return 0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b)
end

local function contrast(first: ReviewColor, second: ReviewColor): number
	local a, b = luminance(first), luminance(second)
	return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05)
end

local function distance(first: ReviewColor, second: ReviewColor): number
	return math.max(math.abs(first.r - second.r), math.abs(first.g - second.g), math.abs(first.b - second.b))
end

local function area(rect: ReviewRect): number
	return math.max(0, rect.width) * math.max(0, rect.height)
end

local function median(values: { number }): number
	if #values == 0 then
		return 0
	end
	local sorted = table.clone(values)
	table.sort(sorted)
	local middle = (#sorted + 1) / 2
	return (sorted[math.floor(middle)] + sorted[math.ceil(middle)]) / 2
end

local function quote(content: string): string
	local length = utf8.len(content) or #content
	local cut = if length > 48 then (utf8.offset(content, 46) or 46) - 1 else #content
	local short = if length > 48 then string.sub(content, 1, cut) .. "..." else content
	return '"' .. short .. '"'
end

type Prepared = {
	byIndex: { [number]: ReviewElement },
	children: { [number]: { ReviewElement } },
	texts: { ReviewElement },
	plates: { ReviewElement },
	plateOf: (ReviewElement) -> ReviewElement?,
	parentOf: (ReviewElement) -> number?,
	descendantTexts: (ReviewElement) -> { ReviewElement },
	descendantImages: (ReviewElement) -> { ReviewElement },
	hasImage: (ReviewElement) -> boolean,
}

local function shown(element: ReviewElement, width: number, height: number): boolean
	local rect = element.rect
	return element.visible
		and rect.width > 0
		and rect.height > 0
		and rect.x < width
		and rect.y < height
		and rect.x + rect.width > 0
		and rect.y + rect.height > 0
end

local function isPlate(element: ReviewElement): boolean
	return element.fillTransparency < 0.4 and element.rect.width >= 24 and element.rect.height >= 24
end

local function prepare(snapshot: ReviewSnapshot): Prepared
	local byIndex: { [number]: ReviewElement } = {}
	local children: { [number]: { ReviewElement } } = {}
	local texts: { ReviewElement } = {}
	local plates: { ReviewElement } = {}
	for _, element in snapshot.elements do
		byIndex[element.index] = element
	end
	local function parentOf(element: ReviewElement): number?
		local parent = element.parent
		return if parent ~= nil and parent < element.index then parent else nil
	end
	for _, element in snapshot.elements do
		if not shown(element, snapshot.width, snapshot.height) then
			continue
		end
		local parent = parentOf(element)
		if parent ~= nil then
			local list = children[parent]
			if list == nil then
				list = {}
				children[parent] = list
			end
			table.insert(list, element)
		end
		local text = element.text
		if text ~= nil and text.transparency < 0.95 and clean(text.content) ~= "" then
			table.insert(texts, element)
		end
		if isPlate(element) then
			table.insert(plates, element)
		end
	end
	local function plateOf(element: ReviewElement): ReviewElement?
		local parent = parentOf(element)
		while parent ~= nil do
			local ancestor = byIndex[parent]
			if ancestor == nil then
				return nil
			end
			if isPlate(ancestor) and shown(ancestor, snapshot.width, snapshot.height) then
				return ancestor
			end
			parent = parentOf(ancestor)
		end
		return nil
	end
	local descendants: { [number]: { ReviewElement } } = {}
	for _, text in texts do
		local parent = parentOf(text)
		while parent ~= nil do
			local list = descendants[parent]
			if list == nil then
				list = {}
				descendants[parent] = list
			end
			table.insert(list, text)
			local ancestor = byIndex[parent]
			parent = if ancestor then parentOf(ancestor) else nil
		end
	end
	local images: { [number]: { ReviewElement } } = {}
	for _, element in snapshot.elements do
		if not element.image or not shown(element, snapshot.width, snapshot.height) then
			continue
		end
		if element.rect.width < 16 or element.rect.height < 16 then
			continue
		end
		local parent: number? = element.index
		while parent ~= nil do
			local list = images[parent]
			if list == nil then
				list = {}
				images[parent] = list
			end
			table.insert(list, element)
			local ancestor = byIndex[parent]
			parent = if ancestor then parentOf(ancestor) else nil
		end
	end
	return {
		byIndex = byIndex,
		children = children,
		texts = texts,
		plates = plates,
		plateOf = plateOf,
		descendantTexts = function(element: ReviewElement): { ReviewElement }
			local own = element.text
			local list = table.clone(descendants[element.index] or {})
			if own ~= nil and clean(own.content) ~= "" then
				table.insert(list, element)
			end
			return list
		end,
		parentOf = parentOf,
		descendantImages = function(element: ReviewElement): { ReviewElement }
			return images[element.index] or {}
		end,
		hasImage = function(element: ReviewElement): boolean
			local floor = math.max(32, element.rect.height * 0.25)
			local found: { ReviewElement } = images[element.index] or {}
			for _, image in found do
				if image.rect.height >= floor and image.rect.width >= 32 then
					return true
				end
			end
			return false
		end,
	}
end

local function textOf(element: ReviewElement): ReviewText
	return element.text :: ReviewText
end

local function analyze(snapshot: ReviewSnapshot): ReviewReport
	assert(type(snapshot) == "table" and type(snapshot.elements) == "table", "Facet review needs a snapshot")
	local prepared = prepare(snapshot)
	local findings: { ReviewFinding } = {}
	local function add(rule: string, severity: ReviewSeverity, element: ReviewElement, detail: string)
		table.insert(
			findings,
			{ rule = rule, severity = severity, path = element.path, detail = detail, rect = element.rect }
		)
	end
	local texts = prepared.texts
	local sizes: { number } = {}
	local distinct: { number } = {}
	for _, element in texts do
		local size = textOf(element).size
		table.insert(sizes, size)
		if not table.find(distinct, size) then
			table.insert(distinct, size)
		end
	end
	table.sort(distinct)
	local common = median(sizes)

	for _, element in texts do
		local content = clean(textOf(element).content)
		if #content > 120 or #lines(textOf(element).content) ~= 1 then
			continue
		end
		local parts = segments(content)
		if #parts < 2 then
			continue
		end
		local digits = false
		for _, part in parts do
			if string.find(part, "%d") then
				digits = true
			end
		end
		if digits then
			add("joined-facts", "medium", element, ("%s joins %d facts"):format(quote(content), #parts))
		elseif #parts >= 3 then
			add("joined-facts", "low", element, ("%s joins %d phrases"):format(quote(content), #parts))
		end
	end

	local numeric: { ReviewElement } = {}
	for _, element in texts do
		local content = clean(textOf(element).content)
		if #content <= 60 and string.find(content, "%d") then
			table.insert(numeric, element)
		end
	end
	if #numeric >= 3 then
		local largest, heavy = 0, false
		for _, element in numeric do
			local text = textOf(element)
			largest = math.max(largest, text.size)
			heavy = heavy or text.bold
		end
		if largest <= common and not heavy then
			add(
				"numbers-unemphasized",
				"medium",
				numeric[1],
				("%d texts carry numbers; the largest is %g px, the common size is %g px"):format(
					#numeric,
					largest,
					common
				)
			)
		end
	end

	if #texts >= 5 and common > 0 then
		local largest: ReviewElement = texts[1]
		for _, element in texts do
			if textOf(element).size > textOf(largest).size then
				largest = element
			end
		end
		local ratio = textOf(largest).size / common
		if ratio < 1.35 then
			add(
				"flat-hierarchy",
				"medium",
				largest,
				("the largest text %s is %.2f times the common size"):format(
					quote(clean(textOf(largest).content)),
					ratio
				)
			)
		end
	end

	local groups: { [number]: { ReviewElement } } = {}
	for _, element in texts do
		local plate = prepared.plateOf(element)
		local key = if plate then plate.index else 0
		local list = groups[key]
		if list == nil then
			list = {}
			groups[key] = list
		end
		table.insert(list, element)
	end
	for key, list in groups do
		if key == 0 or #list < 3 then
			continue
		end
		local top = 0
		for _, element in list do
			top = math.max(top, textOf(element).size)
		end
		local rest: { number } = {}
		for _, element in list do
			local size = textOf(element).size
			if size < 0.92 * top then
				table.insert(rest, size)
			end
		end
		if #rest == 0 or top < 1.25 * median(rest) then
			continue
		end
		local peaks: { ReviewElement } = {}
		local seen: { [string]: boolean } = {}
		local slots: { [string]: { [number]: boolean } } = {}
		for _, element in list do
			local content = clean(textOf(element).content)
			if textOf(element).size < 0.92 * top or seen[content] then
				continue
			end
			seen[content] = true
			local parent = prepared.parentOf(element) or 0
			local holder = prepared.byIndex[parent]
			local slot = element.class .. "|" .. tostring(textOf(element).size)
			if holder ~= nil then
				slot ..= ("|%d|%d|%d|%d"):format(
					math.floor((element.rect.x - holder.rect.x) / 4 + 0.5),
					math.floor((element.rect.y - holder.rect.y) / 4 + 0.5),
					math.floor(holder.rect.width / 4 + 0.5),
					math.floor(holder.rect.height / 4 + 0.5)
				)
			end
			local parents = slots[slot]
			if parents == nil then
				slots[slot] = { [parent] = true }
				table.insert(peaks, element)
			elseif parents[parent] then
				table.insert(peaks, element)
			else
				parents[parent] = true
			end
		end
		if #peaks >= 2 then
			local names: { string } = {}
			for index, element in peaks do
				if index > 3 then
					break
				end
				table.insert(names, quote(clean(textOf(element).content)))
			end
			add(
				"competing-peaks",
				"medium",
				peaks[1],
				("%s share the lead size %g px"):format(table.concat(names, " and "), top)
			)
		end
	end

	for _, siblings in prepared.children do
		local records: { ReviewElement } = {}
		for _, element in siblings do
			local inner = prepared.descendantTexts(element)
			local own = element.text
			local bare = own == nil or clean(own.content) == ""
			if bare and #inner > 0 and (#inner >= 2 or element.rect.height >= 56) then
				table.insert(records, element)
			end
		end
		if #records < 3 then
			continue
		end
		local width = records[1].rect.width
		local alike: { ReviewElement } = {}
		for _, element in records do
			if math.abs(element.rect.width - width) <= 2 then
				table.insert(alike, element)
			end
		end
		if #alike < 3 then
			continue
		end
		local pictured = 0
		local plated = 0
		local controls = 0
		for _, element in alike do
			if prepared.hasImage(element) then
				pictured += 1
			end
			if isPlate(element) then
				plated += 1
			end
			if element.interactive then
				controls += 1
			end
		end
		local items = plated == #alike or controls == #alike
		if items and pictured * 2 < #alike then
			local first = alike[1]
			add(
				"record-without-visual",
				"medium",
				first,
				("%d repeated records of %dx%d px%s; %d have a visual"):format(
					#alike,
					math.floor(first.rect.width),
					math.floor(first.rect.height),
					if plated == #alike then " on identical plates" else "",
					pictured
				)
			)
		end
	end

	for _, element in prepared.plates do
		if element.interactive then
			continue
		end
		local outer = prepared.plateOf(element)
		if outer == nil or outer.interactive then
			continue
		end
		if
			area(element.rect) >= 0.08 * area(outer.rect)
			and element.rect.width >= 0.4 * outer.rect.width
			and distance(element.fill, outer.fill) <= 0.12
			and #prepared.descendantTexts(element) > 0
		then
			add(
				"nested-surface",
				"low",
				element,
				("a plate of %dx%d px inside a plate of nearly the same color"):format(
					math.floor(element.rect.width),
					math.floor(element.rect.height)
				)
			)
		end
	end

	local zeros, total = 0, 0
	for _, element in texts do
		for _, value in numbers(clean(textOf(element).content)) do
			total += 1
			if value == 0 then
				zeros += 1
			end
		end
	end
	if zeros >= 3 and zeros * 2 >= total then
		local first: ReviewElement? = nil
		for _, element in texts do
			if first == nil and table.find(numbers(clean(textOf(element).content)), 0) then
				first = element
			end
		end
		if first ~= nil then
			add("zero-wall", "low", first, ("%d of %d numbers are zero"):format(zeros, total))
		end
	end

	if #texts >= 6 then
		local bold, font = textOf(texts[1]).bold, textOf(texts[1]).font
		local same = true
		for _, element in texts do
			local text = textOf(element)
			if text.bold ~= bold or text.font ~= font then
				same = false
				break
			end
		end
		if same then
			add("single-weight", "low", texts[1], ("%d texts in one font and one weight"):format(#texts))
		end
	end

	for parentIndex, list in prepared.children do
		local parent = prepared.byIndex[parentIndex]
		if parent == nil or parent.rect.width <= 0 then
			continue
		end
		local column: { ReviewElement } = {}
		local widest = 0
		for _, child in list do
			if not child.interactive then
				continue
			end
			local words = prepared.descendantTexts(child)
			if #words ~= 1 or (utf8.len(clean(textOf(words[1]).content)) or 0) > 24 then
				continue
			end
			table.insert(column, child)
			widest = math.max(widest, child.rect.width)
		end
		if #column < 4 or widest > 0.6 * parent.rect.width then
			continue
		end
		table.sort(column, function(left: ReviewElement, right: ReviewElement): boolean
			return left.rect.y < right.rect.y
		end)
		local run = 1
		local best = 1
		for index = 2, #column do
			local above, below = column[index - 1].rect, column[index].rect
			local sameColumn = math.abs(above.x - below.x) < 8
				or math.abs((above.x + above.width / 2) - (below.x + below.width / 2)) < 8
			if sameColumn and below.y >= above.y + above.height - 2 then
				run += 1
				best = math.max(best, run)
			else
				run = 1
			end
		end
		if best >= 4 then
			add(
				"stacked-choices",
				"medium",
				parent,
				("%d short choices stacked one per row in a %d px wide space; the widest is %d px"):format(
					best,
					math.floor(parent.rect.width),
					math.floor(widest)
				)
			)
		end
	end

	local contentElements: { ReviewElement } = {}
	for _, element in snapshot.elements do
		if not shown(element, snapshot.width, snapshot.height) then
			continue
		end
		local text = element.text
		if
			element.interactive
			or (element.image and element.rect.width >= 16 and element.rect.height >= 16)
			or (text ~= nil and text.transparency < 0.95 and clean(text.content) ~= "")
		then
			table.insert(contentElements, element)
		end
	end
	local function within(outer: ReviewRect, element: ReviewElement): boolean
		local x = element.rect.x + element.rect.width / 2
		local y = element.rect.y + element.rect.height / 2
		return x >= outer.x and x <= outer.x + outer.width and y >= outer.y and y <= outer.y + outer.height
	end
	local function ancestorOf(candidate: ReviewElement, element: ReviewElement): boolean
		local parent = prepared.parentOf(element)
		while parent ~= nil do
			if parent == candidate.index then
				return true
			end
			local ancestor = prepared.byIndex[parent]
			parent = if ancestor then prepared.parentOf(ancestor) else nil
		end
		return false
	end
	local insideCache: { [number]: { ReviewElement } } = {}
	local function inside(plate: ReviewElement): { ReviewElement }
		local cached = insideCache[plate.index]
		if cached ~= nil then
			return cached
		end
		local list: { ReviewElement } = {}
		for _, element in contentElements do
			if
				element ~= plate
				and area(element.rect) < area(plate.rect)
				and within(plate.rect, element)
				and not ancestorOf(element, plate)
			then
				table.insert(list, element)
			end
		end
		insideCache[plate.index] = list
		return list
	end
	local function bounds(list: { ReviewElement }, within: ReviewRect): ReviewRect?
		local left, top, right, bottom = math.huge, math.huge, -math.huge, -math.huge
		for _, element in list do
			local rect = element.rect
			left = math.min(left, math.max(rect.x, within.x))
			top = math.min(top, math.max(rect.y, within.y))
			right = math.max(right, math.min(rect.x + rect.width, within.x + within.width))
			bottom = math.max(bottom, math.min(rect.y + rect.height, within.y + within.height))
		end
		if right <= left or bottom <= top then
			return nil
		end
		return { x = left, y = top, width = right - left, height = bottom - top }
	end

	local fullArea = math.max(1, snapshot.width * snapshot.height)
	local hollow: { [string]: { ReviewElement } } = {}
	local hollowOrder: { string } = {}
	for _, plate in prepared.plates do
		if plate.interactive or plate.rect.width < 280 or area(plate.rect) < 40000 then
			continue
		end
		if area(plate.rect) >= 0.35 * fullArea then
			continue
		end
		local content = inside(plate)
		if #content == 0 then
			continue
		end
		local used = bounds(content, plate.rect)
		if used ~= nil and area(used) < 0.35 * area(plate.rect) then
			local key = ("%d:%d"):format(math.floor(plate.rect.width / 8), math.floor(plate.rect.height / 8))
			local group = hollow[key]
			if group == nil then
				group = {}
				hollow[key] = group
				table.insert(hollowOrder, key)
			end
			table.insert(group, plate)
		end
	end
	for _, key in hollowOrder do
		local group = hollow[key]
		local first = group[1]
		local used = bounds(inside(first), first.rect) :: ReviewRect
		add(
			"hollow-plate",
			"medium",
			first,
			("%d plate(s) of %dx%d px; the content uses %d%% of each"):format(
				#group,
				math.floor(first.rect.width),
				math.floor(first.rect.height),
				math.floor(100 * area(used) / area(first.rect))
			)
		)
	end

	if snapshot.width >= 900 then
		for _, plate in prepared.plates do
			if plate.rect.width < 0.8 * snapshot.width or area(plate.rect) < 0.6 * fullArea then
				continue
			end
			local content = inside(plate)
			if #content < 3 then
				continue
			end
			local middle = plate.rect.x + plate.rect.width / 2
			local leftWeight, rightWeight = 0, 0
			for _, element in content do
				local weight = math.min(area(element.rect), area(plate.rect))
				local center = element.rect.x + element.rect.width / 2
				if center < middle then
					leftWeight += weight
				else
					rightWeight += weight
				end
			end
			local total = leftWeight + rightWeight
			if total > 0 and math.max(leftWeight, rightWeight) >= 0.85 * total then
				add(
					"lopsided-page",
					"medium",
					plate,
					("%d%% of the content sits in one half of a %d px wide surface"):format(
						math.floor(100 * math.max(leftWeight, rightWeight) / total),
						math.floor(plate.rect.width)
					)
				)
			end
		end
	end

	local floating: { ReviewElement } = {}
	for _, element in texts do
		local text = textOf(element)
		if text.size < 12 or utf8.len(clean(text.content)) == nil or (utf8.len(clean(text.content)) or 0) < 2 then
			continue
		end
		local backed = prepared.plateOf(element) ~= nil
		if not backed then
			for _, plate in prepared.plates do
				if area(plate.rect) > area(element.rect) and within(plate.rect, element) then
					backed = true
					break
				end
			end
		end
		if backed then
			continue
		end
		local parent = prepared.parentOf(element)
		local owner = if parent ~= nil then prepared.byIndex[parent] else nil
		if element.interactive or (owner ~= nil and owner.interactive) then
			continue
		end
		table.insert(floating, element)
	end
	if #floating >= 3 then
		add(
			"floating-text",
			"medium",
			floating[1],
			("%d texts on the world with no plate, such as %s"):format(
				#floating,
				quote(clean(textOf(floating[1]).content))
			)
		)
	end

	if snapshot.touch == true then
		local small = math.min(snapshot.width, snapshot.height) <= 500
		local size = if small then 70 else 120
		local jump: ReviewRect = {
			x = snapshot.width - (if small then 95 else 170),
			y = snapshot.height - (if small then 90 else 210),
			width = size,
			height = size,
		}
		for _, element in snapshot.elements do
			if not element.interactive or not shown(element, snapshot.width, snapshot.height) then
				continue
			end
			local covered = false
			local parent = prepared.parentOf(element)
			while parent ~= nil and not covered do
				local ancestor = prepared.byIndex[parent]
				covered = ancestor ~= nil and ancestor.class == "ScrollingFrame"
				parent = if ancestor then prepared.parentOf(ancestor) else nil
			end
			for _, plate in prepared.plates do
				if plate ~= element and area(plate.rect) >= 0.35 * fullArea and within(plate.rect, element) then
					covered = true
					break
				end
			end
			if covered then
				continue
			end
			local rect = element.rect
			local overlapX = math.min(rect.x + rect.width, jump.x + jump.width) - math.max(rect.x, jump.x)
			local overlapY = math.min(rect.y + rect.height, jump.y + jump.height) - math.max(rect.y, jump.y)
			if overlapX > 0 and overlapY > 0 and overlapX * overlapY >= 0.2 * size * size then
				add(
					"touch-control-overlap",
					"medium",
					element,
					("a %dx%d px control covers %d%% of the Jump button area"):format(
						math.floor(rect.width),
						math.floor(rect.height),
						math.floor(100 * overlapX * overlapY / (size * size))
					)
				)
				break
			end
		end
	end

	local screenArea = math.max(1, snapshot.width * snapshot.height)
	for _, plate in prepared.plates do
		if area(plate.rect) < 0.35 * screenArea then
			continue
		end
		local content = prepared.descendantTexts(plate)
		if #content < 2 then
			continue
		end
		for _, image in prepared.descendantImages(plate) do
			if image ~= plate then
				table.insert(content, image)
			end
		end
		local left, top, right, bottom = math.huge, math.huge, -math.huge, -math.huge
		for _, element in content do
			left = math.min(left, element.rect.x)
			top = math.min(top, element.rect.y)
			right = math.max(right, element.rect.x + element.rect.width)
			bottom = math.max(bottom, element.rect.y + element.rect.height)
		end
		local used: ReviewRect = { x = left, y = top, width = right - left, height = bottom - top }
		local offsetX = math.abs((left + right) / 2 - (plate.rect.x + plate.rect.width / 2)) / plate.rect.width
		local offsetY = math.abs((top + bottom) / 2 - (plate.rect.y + plate.rect.height / 2)) / plate.rect.height
		if area(used) < 0.4 * area(plate.rect) and (offsetX > 0.25 or offsetY > 0.25) then
			add(
				"stranded-content",
				"low",
				plate,
				("the content uses %d%% of a %dx%d px surface"):format(
					math.floor(100 * area(used) / area(plate.rect)),
					math.floor(plate.rect.width),
					math.floor(plate.rect.height)
				)
			)
		end
	end

	table.sort(findings, function(left: ReviewFinding, right: ReviewFinding): boolean
		if left.severity ~= right.severity then
			return SEVERITY_RANK[left.severity] < SEVERITY_RANK[right.severity]
		end
		if left.rule ~= right.rule then
			return left.rule < right.rule
		end
		if left.rect.y ~= right.rect.y then
			return left.rect.y < right.rect.y
		end
		return left.rect.x < right.rect.x
	end)

	local prominence: { ReviewProminence } = {}
	for _, element in texts do
		local text = textOf(element)
		local plate = prepared.plateOf(element)
		local ratio = if plate then contrast(text.color, plate.fill) else 7
		local factor = math.clamp((ratio - 1) / 4, 0.35, 1)
		table.insert(prominence, {
			path = element.path,
			content = clean(text.content),
			size = text.size,
			role = text.role,
			bold = text.bold,
			score = math.floor(text.size * (if text.bold then 1.2 else 1) * factor * 10 + 0.5) / 10,
		})
	end
	table.sort(prominence, function(left: ReviewProminence, right: ReviewProminence): boolean
		if left.score ~= right.score then
			return left.score > right.score
		end
		return left.path < right.path
	end)
	while #prominence > 6 do
		table.remove(prominence)
	end

	local used: { [string]: string } = {}
	for _, finding in findings do
		used[finding.rule] = FIXES[finding.rule]
	end

	local lines = { ("design review: %d finding(s), %d text size(s) in use"):format(#findings, #distinct) }
	local order: { string } = {}
	local grouped: { [string]: { ReviewFinding } } = {}
	for _, finding in findings do
		local list = grouped[finding.rule]
		if list == nil then
			list = {}
			grouped[finding.rule] = list
			table.insert(order, finding.rule)
		end
		table.insert(list, finding)
	end
	for _, rule in order do
		local list = grouped[rule]
		table.insert(lines, ("  %s %s (%d): %s"):format(list[1].severity, rule, #list, FIXES[rule] or ""))
		for index, finding in list do
			if index > 3 then
				table.insert(lines, ("      ... %d more"):format(#list - 3))
				break
			end
			table.insert(lines, "      " .. finding.detail)
		end
	end
	table.insert(lines, "  most prominent text:")
	for index, item in prominence do
		table.insert(
			lines,
			("    %d. %s %g px%s%s"):format(
				index,
				quote(item.content),
				item.size,
				if item.bold then " bold" else "",
				if item.role then " " .. item.role else ""
			)
		)
	end
	return {
		findings = findings,
		prominence = prominence,
		sizes = distinct,
		fixes = used,
		text = table.concat(lines, "\n"),
	}
end

return table.freeze({
	analyze = analyze,
	segments = segments,
	fixes = FIXES,
})
