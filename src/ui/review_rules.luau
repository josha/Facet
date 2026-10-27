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
export type ReviewSnapshot = { width: number, height: number, elements: { ReviewElement } }
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
	["record-without-visual"] = "Repeated items have no visual, so the player reads every name to tell them apart. Give each item its image or model, or else a glyph from the theme icon set, beside its name. If the rows are only facts to compare, drop the plates and align the facts in columns. "
		.. RECIPES,
	["nested-surface"] = "A plate sits inside a plate of nearly the same color. Keep one plate per layer; separate groups with space or one hairline.",
	["zero-wall"] = "Most numbers on this screen are zero. Replace an all-zero record with its goal: what the player does next and how far it is.",
	["single-weight"] = "Every text uses one font and one weight. Give the lead and the values a heavier weight than labels and body text.",
	["stranded-content"] = "The content fills a small part of a large surface and sits to one side. Bound the surface to its content or use the space for the subject.",
})

local function clean(content: string): string
	local plain = string.gsub(content, "<[^>]+>", "")
	plain = string.gsub(plain, "%s+", " ")
	plain = string.gsub(plain, "^ ", "")
	plain = string.gsub(plain, " $", "")
	return plain
end

local function segments(content: string): { string }
	local marked = " " .. content .. " "
	for _, separator in SEPARATORS do
		marked = string.gsub(marked, separator, "\0")
	end
	local parts: { string } = {}
	for part in string.gmatch(marked .. "\0", "([^\0]*)\0") do
		local trimmed = string.gsub(string.gsub(part, "^%s+", ""), "%s+$", "")
		if trimmed ~= "" then
			table.insert(parts, trimmed)
		end
	end
	return parts
end

local function numbers(content: string): { number }
	local found: { number } = {}
	for token in string.gmatch(content, "%d[%d,]*%.?%d*") do
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
	local short = if #content > 48 then string.sub(content, 1, 45) .. "..." else content
	return '"' .. short .. '"'
end

type Prepared = {
	byIndex: { [number]: ReviewElement },
	children: { [number]: { ReviewElement } },
	texts: { ReviewElement },
	plates: { ReviewElement },
	plateOf: (ReviewElement) -> ReviewElement?,
	descendantTexts: (ReviewElement) -> { ReviewElement },
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
	for _, element in snapshot.elements do
		if not shown(element, snapshot.width, snapshot.height) then
			continue
		end
		local parent = element.parent
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
		local parent = element.parent
		while parent ~= nil do
			local ancestor = byIndex[parent]
			if ancestor == nil then
				return nil
			end
			if isPlate(ancestor) and shown(ancestor, snapshot.width, snapshot.height) then
				return ancestor
			end
			parent = ancestor.parent
		end
		return nil
	end
	local descendants: { [number]: { ReviewElement } } = {}
	for _, text in texts do
		local parent = text.parent
		while parent ~= nil do
			local list = descendants[parent]
			if list == nil then
				list = {}
				descendants[parent] = list
			end
			table.insert(list, text)
			local ancestor = byIndex[parent]
			parent = if ancestor then ancestor.parent else nil
		end
	end
	local imaged: { [number]: boolean } = {}
	for _, element in snapshot.elements do
		if not element.image or not shown(element, snapshot.width, snapshot.height) then
			continue
		end
		if element.rect.width < 16 or element.rect.height < 16 then
			continue
		end
		local parent: number? = element.index
		while parent ~= nil do
			imaged[parent] = true
			local ancestor = byIndex[parent]
			parent = if ancestor then ancestor.parent else nil
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
		hasImage = function(element: ReviewElement): boolean
			return imaged[element.index] == true
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
		if #content > 120 then
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
	for _, list in groups do
		if #list < 3 then
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
		for _, element in list do
			local content = clean(textOf(element).content)
			if textOf(element).size >= 0.92 * top and not seen[content] then
				seen[content] = true
				table.insert(peaks, element)
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
		for _, element in alike do
			if prepared.hasImage(element) then
				pictured += 1
			end
			if isPlate(element) then
				plated += 1
			end
		end
		if pictured * 2 < #alike then
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

	local screenArea = math.max(1, snapshot.width * snapshot.height)
	for _, plate in prepared.plates do
		if area(plate.rect) < 0.35 * screenArea then
			continue
		end
		local content = prepared.descendantTexts(plate)
		if #content < 2 then
			continue
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
