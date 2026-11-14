--!strict
local Types = require("./review_types")
export type ReviewRect = Types.ReviewRect
export type ReviewOutset = Types.ReviewOutset
export type ReviewColor = Types.ReviewColor
export type ReviewText = Types.ReviewText
export type ReviewElement = Types.ReviewElement
export type ReviewSnapshot = Types.ReviewSnapshot
export type ReviewSeverity = Types.ReviewSeverity
export type ReviewFinding = Types.ReviewFinding
export type ReviewProminence = Types.ReviewProminence
export type ReviewMeasures = Types.ReviewMeasures
export type ReviewReport = Types.ReviewReport

local SEPARATORS = { " · ", " • ", " | ", " / ", " – " }
local SEVERITY_RANK: { [ReviewSeverity]: number } = { high = 1, medium = 2, low = 3 }
local RECIPES = "See the information-display reference in the use-facet skill."
local MEDIUM_NOTE =
	"  %d medium rule(s): each one names a generic or unfinished part. On a new interface, repair it or note why the design keeps it before you build the next screen."

local fixes: { [string]: string } = {
	["joined-facts"] = "One text joins several facts with separators, so no fact leads and values cannot be compared. Give each fact its own element: the value in the numeral or strong role and its label in caption beside or under it. In a HUD region the player reads a value at a glance during play, so a joined line that leads its region is high. "
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
	["composition-unfit"] = "A HUD Composition does not fit this screen or a phone screen: the named regions overlap there even at their last form, or their fullest form is wider than that screen, so the Popover that shows it runs past the edge. Give each of them a compact second form, such as one Menu circle for the destinations, a fullest form that hugs its content in place of a pixel width, or mayDrop = true for an optional region.",
	["unnamed-reveal"] = 'A HUD region that the screen has no room for shows as a "..." mark, and the mark does not say what is behind it. Give the Region a label, an icon or both: the mark shows them, and the popover of several regions names each one. For a readout whose shorter form loses nothing, set reveal = false.',
	["overlapping-text"] = "Two texts are drawn over each other. Siblings placed by Position or AnchorPoint collide when the room shrinks. Put them in one VStack or HStack so that each keeps its own space, and use a Spacer or UI.fill() to push a group to the far edge.",
	["covered-text"] = "A plate or an image from another part covers a text at this size. The layers of a ZStack do not make room for each other, and a child that is wider than its slot in a stack runs over its neighbor. Put the parts that must not cover each other in one VStack, HStack or AdaptiveStack, let each part fit its slot, and keep the ZStack for the parts that are meant to overlap.",
	["collapsed-text"] = 'A text has no width, so none of it is drawn. Its holder is as wide as its content, and the content waits for a width from the holder. Give the holder a width: a width in pixels or fill, a Size with a width, or align = "stretch" on the list that holds it.',
	["cut-at-edge"] = "A text or a control crosses the edge of the screen, so part of it is not drawn. A part with a width in pixels, or a row that hugs its content, is wider than the room at this size. Give the part a width that follows the room (fill, a share or a maxWidth), let the row reflow with an AdaptiveStack or wrap = true, or use a shorter form of the part at this size.",
	["covered-control"] = "A plate from another part covers a part of a control at this size. The control reads as joined to the plate, and the covered part does not take a press. A Callout, a Popover, a help plate and the layers of a ZStack float over the screen and do not make room for what is under them. Give the floating part an edge and an align where it has room, give it a shorter form at this size, or put the control and the part in one stack. A control that is wholly under another part, or under a presented modal, is taken as layered on purpose.",
	["touching-controls"] = "The edge or the shadow of a control is drawn outside its box and reaches the control beside it, so the two read as one. Set finish.edge.controls in the theme so that the edge is drawn inside the box, and give the stack that holds the two a gap that is larger than the shadow.",
	["offscreen-text"] = "A text is outside the screen while the row or the stack that holds it is on the screen. The parts are wider than the room, so a neighbor pushed the text past the edge. Let the long text wrap or truncate, give the fixed parts smaller sizes, or let the row reflow with an AdaptiveStack or wrap = true on the HStack.",
	["escaped-text"] = "A text runs past the edge of the plate or the image that it sits on, or a clip cuts it. Let the text wrap or give it a maxWidth, let the backing grow with its content, or use a smaller type role at this size. For a label on art, keep it inside the painted area of the art.",
	["native-text"] = "Some texts are native labels, so they miss the theme's type roles, the player's text size and the ten-foot scale. Build each label with UI.Text and a textRole, and arrange it with a stack, a ZStack or a Grid.",
	["stranded-content"] = "The content fills a small part of a large surface and sits to one side. Bound the surface to its content or use the space for the subject.",
	["oversized-target"] = "A control is larger than the scroll area that holds it, so the player never sees it whole at this size. Measure the room of the list with UI.environment(body) and give the record a shorter form there, such as a thumbnail beside its facts, or move the header and the filters out of the room of the list. See the compact-compositions reference in the use-facet skill.",
}
local EDGE_CUT = 4
local FIXES = table.freeze(fixes)

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
			if i ~= nil and j ~= nil and (found == nil or i < found) then
				found, finish, separator = i, j, candidate
			end
		end
		if found == nil or finish == nil then
			break
		end
		local first, last = assert(found), assert(finish)
		local before = string.sub(text, first - 1, first - 1)
		local after = string.sub(text, last + 1, last + 1)
		local range = (separator == " / " or separator == " – ")
			and string.match(before, "%d") ~= nil
			and string.match(after, "%d") ~= nil
		if not range then
			table.insert(parts, string.sub(text, start, first - 1))
			start = last + 1
		end
		position = last + 1
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

type Oversized = { first: ReviewElement, count: number, axis: string, size: number, room: number }
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

local function face(element: ReviewElement): ReviewRect
	local paint = element.paint
	return if paint ~= nil and element.image and not isPlate(element) then paint else element.rect
end

local function solid(element: ReviewElement): boolean
	return isPlate(element) or (element.image and area(face(element)) > 0)
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
			local region: ReviewElement? = nil
			local parent = prepared.parentOf(element)
			while parent ~= nil and region == nil do
				local ancestor = prepared.byIndex[parent]
				if ancestor == nil then
					break
				end
				if ancestor.region then
					region = ancestor
				end
				parent = prepared.parentOf(ancestor)
			end
			local leads = region ~= nil
			if region then
				for _, other in prepared.descendantTexts(region) do
					if textOf(other).size > textOf(element).size then
						leads = false
						break
					end
				end
			end
			if leads then
				add(
					"joined-facts",
					"high",
					element,
					("%s joins %d facts and leads a HUD region"):format(quote(content), #parts)
				)
			else
				add("joined-facts", "medium", element, ("%s joins %d facts"):format(quote(content), #parts))
			end
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

	local function overlap(first: ReviewRect, second: ReviewRect): ReviewRect?
		local left, top = math.max(first.x, second.x), math.max(first.y, second.y)
		local right = math.min(first.x + first.width, second.x + second.width)
		local bottom = math.min(first.y + first.height, second.y + second.height)
		if right <= left or bottom <= top then
			return nil
		end
		return { x = left, y = top, width = right - left, height = bottom - top }
	end
	local function lineage(element: ReviewElement): { ReviewElement }
		local chain: { ReviewElement } = {}
		local parent = prepared.parentOf(element)
		while parent ~= nil do
			local ancestor = prepared.byIndex[parent]
			if ancestor == nil then
				break
			end
			table.insert(chain, ancestor)
			parent = prepared.parentOf(ancestor)
		end
		return chain
	end
	local function inkOf(element: ReviewElement, chain: { ReviewElement }): ReviewRect?
		local ink: ReviewRect? = textOf(element).ink
		for _, ancestor in chain do
			if ink == nil then
				break
			end
			if ancestor.clips then
				ink = overlap(ink, ancestor.rect)
			end
		end
		return ink
	end
	local function backs(element: ReviewElement, shared: ReviewRect): boolean
		if not solid(element) then
			return false
		end
		local hidden = overlap(face(element), shared)
		return hidden ~= nil and area(hidden) >= area(shared) * 0.9
	end
	local function covered(chain: { ReviewElement }, other: { ReviewElement }, shared: ReviewRect): boolean
		for _, ancestor in chain do
			if table.find(other, ancestor) then
				return false
			end
			if backs(ancestor, shared) then
				return true
			end
			local group = prepared.children[ancestor.index]
			if group ~= nil then
				for _, child in group do
					if backs(child, shared) then
						return true
					end
				end
			end
		end
		return false
	end
	local inked: { { element: ReviewElement, ink: ReviewRect, chain: { ReviewElement } } } = {}
	for _, element in texts do
		if textOf(element).size < 8 then
			continue
		end
		local chain = lineage(element)
		local ink = inkOf(element, chain)
		if ink ~= nil and ink.width >= 4 and ink.height >= 4 then
			table.insert(inked, { element = element, ink = ink, chain = chain })
		end
	end
	local collisions = 0
	for first = 1, #inked do
		if collisions >= 3 then
			break
		end
		local a = inked[first]
		for second = first + 1, #inked do
			local b = inked[second]
			local shared = overlap(a.ink, b.ink)
			if shared == nil or shared.width < 4 or shared.height < 4 then
				continue
			end
			if area(shared) < 0.2 * math.min(area(a.ink), area(b.ink)) then
				continue
			end
			if table.find(a.chain, b.element) or table.find(b.chain, a.element) then
				continue
			end
			if clean(textOf(a.element).content) == clean(textOf(b.element).content) then
				continue
			end
			if covered(a.chain, b.chain, shared) or covered(b.chain, a.chain, shared) then
				continue
			end
			add(
				"overlapping-text",
				"high",
				a.element,
				("%s overlaps %s"):format(
					quote(clean(textOf(a.element).content)),
					quote(clean(textOf(b.element).content))
				)
			)
			collisions += 1
			break
		end
	end

	local limit = snapshot.width * snapshot.height * 0.35
	local buriedBy: { [number]: { ReviewElement } } = {}
	local covers: { ReviewElement } = {}
	for _, entry in inked do
		local element = entry.element
		for _, cover in snapshot.elements do
			if
				cover == element
				or cover.parent == element.parent
				or table.find(entry.chain, cover) ~= nil
				or not solid(cover)
				or area(cover.rect) >= limit
				or (cover.turn or 0) > 10
				or not shown(cover, snapshot.width, snapshot.height)
			then
				continue
			end
			local hidden = overlap(face(cover), entry.ink)
			if hidden == nil or area(hidden) < area(entry.ink) * 0.5 then
				continue
			end
			local coverChain = lineage(cover)
			local held: ReviewElement? = nil
			local mine = element
			for _, ancestor in entry.chain do
				if table.find(coverChain, ancestor) then
					held = ancestor
					break
				end
				mine = ancestor
			end
			if held == nil or held.fan then
				continue
			end
			local theirs = cover
			for _, ancestor in coverChain do
				if ancestor == held then
					break
				end
				theirs = ancestor
			end
			local low, high = mine.z or 1, theirs.z or 1
			if low > high or (low == high and mine.index > theirs.index) then
				continue
			end
			local list = buriedBy[cover.index]
			if list == nil then
				list = {}
				buriedBy[cover.index] = list
				table.insert(covers, cover)
			end
			table.insert(list, element)
			break
		end
	end
	local buried = 0
	for _, cover in covers do
		local list = buriedBy[cover.index]
		if #list > 2 or buried >= 3 then
			continue
		end
		add(
			"covered-text",
			"medium",
			list[1],
			("%s is under %s"):format(
				quote(clean(textOf(list[1]).content)),
				quote(string.match(cover.path, "[^%.]+$") or cover.class)
			)
		)
		buried += 1
	end

	local chains: { [number]: { ReviewElement } } = {}
	local function chainOf(element: ReviewElement): { ReviewElement }
		local chain = chains[element.index]
		if chain == nil then
			chain = lineage(element)
			chains[element.index] = chain
		end
		return chain
	end
	local function beneath(lower: ReviewElement, upper: ReviewElement): boolean
		local lowerChain, upperChain = chainOf(lower), chainOf(upper)
		if table.find(upperChain, lower) then
			return true
		end
		if table.find(lowerChain, upper) then
			return false
		end
		local mine = upper
		for _, ancestor in upperChain do
			if table.find(lowerChain, ancestor) then
				local theirs = lower
				for _, other in lowerChain do
					if other == ancestor then
						break
					end
					theirs = other
				end
				local low, high = theirs.z or 1, mine.z or 1
				return low < high or (low == high and theirs.index < mine.index)
			end
			mine = ancestor
		end
		return false
	end
	local function leaf(element: ReviewElement): string
		return quote(string.match(element.path, "[^%.]+$") or element.class)
	end
	local function past(ink: ReviewRect, rect: ReviewRect, size: number): boolean
		local across = math.max(rect.x - ink.x, ink.x + ink.width - rect.x - rect.width)
		local down = math.max(rect.y - ink.y, ink.y + ink.height - rect.y - rect.height)
		return across >= math.max(4, 0.3 * size) or down >= math.max(3, 0.25 * size)
	end
	local function edgeOf(backing: ReviewElement, ink: ReviewRect): ReviewRect
		local paint = face(backing)
		local on = overlap(paint, ink)
		return if on ~= nil and area(on) >= 0.5 * area(ink) then paint else backing.rect
	end
	local function near(backing: ReviewElement, chain: { ReviewElement }): boolean
		for depth, ancestor in chain do
			if ancestor == backing or (depth <= 3 and ancestor.index == backing.parent) then
				return true
			end
		end
		return false
	end
	local function grounds(backing: ReviewElement, chain: { ReviewElement }): boolean
		if backing.ground ~= true or not backing.image then
			return false
		end
		for _, ancestor in chain do
			if ancestor.index == backing.parent then
				return true
			end
		end
		return false
	end
	local escapes = 0
	for _, entry in inked do
		if escapes >= 3 then
			break
		end
		local element = entry.element
		if (element.turn or 0) > 1 then
			continue
		end
		local text = textOf(element)
		local whole = text.ink :: ReviewRect
		local cutter: ReviewElement? = nil
		local kept: ReviewRect? = whole
		for _, ancestor in entry.chain do
			if kept == nil then
				break
			end
			if ancestor.clips then
				local left = overlap(kept, ancestor.rect)
				if cutter == nil and ancestor.class ~= "ScrollingFrame" and past(kept, ancestor.rect, text.size) then
					cutter = ancestor
				end
				kept = left
			end
		end
		if cutter ~= nil then
			add("escaped-text", "medium", element, ("%s is cut by %s"):format(quote(clean(text.content)), leaf(cutter)))
			escapes += 1
			continue
		end
		local ink = entry.ink
		local nearest: ReviewElement? = if isPlate(element) then element else nil
		local held = false
		if nearest == nil then
			for _, backing in snapshot.elements do
				if backing == element or not solid(backing) or not shown(backing, snapshot.width, snapshot.height) then
					continue
				end
				local owned = grounds(backing, entry.chain)
				local shared = overlap(backing.rect, ink)
				if
					(not owned and (shared == nil or area(shared) < 0.5 * area(ink)))
					or not beneath(backing, element)
				then
					continue
				end
				local edge = if owned then face(backing) else edgeOf(backing, ink)
				if area(backing.rect) < limit and not past(ink, edge, text.size) then
					held = true
				end
				if nearest == nil or beneath(nearest, backing) then
					nearest = backing
				end
			end
		end
		if nearest == nil or (held and nearest ~= element) or (nearest.turn or 0) > 1 then
			continue
		end
		local owned = grounds(nearest, entry.chain)
		local edge = if owned then face(nearest) else edgeOf(nearest, ink)
		if area(nearest.rect) >= limit or not past(ink, edge, text.size) then
			continue
		end
		if nearest ~= element and not isPlate(nearest) and not owned then
			local shared = overlap(nearest.rect, ink)
			if shared == nil or area(shared) < 0.7 * area(ink) or not near(nearest, entry.chain) then
				continue
			end
		end
		add(
			"escaped-text",
			"medium",
			element,
			("%s runs past the edge of %s"):format(quote(clean(text.content)), leaf(nearest))
		)
		escapes += 1
	end

	local screen: ReviewRect = { x = 0, y = 0, width = snapshot.width, height = snapshot.height }
	local strays, flats = 0, 0
	for _, element in snapshot.elements do
		if strays >= 3 and flats >= 3 then
			break
		end
		local text = element.text
		if text == nil or not element.visible or text.size < 8 or clean(text.content) == "" then
			continue
		end
		local flat = element.rect.width < 1 and element.rect.height >= 4
		local ink = text.ink or element.rect
		local seen = overlap(ink, screen)
		local away = ink.width >= 4 and ink.height >= 4 and (seen == nil or area(seen) < 0.5 * area(ink))
		if not flat and not away then
			continue
		end
		local chain = lineage(element)
		local holder = if flat then nil else chain[1]
		local clipped = false
		for _, ancestor in chain do
			local empty = area(ancestor.rect) <= 0
			if not ancestor.visible or (ancestor.clips and (empty or not flat)) then
				clipped = true
				break
			end
			if holder == nil and not empty then
				holder = ancestor
			end
		end
		local held = if holder then overlap(holder.rect, screen) else nil
		if clipped or holder == nil or held == nil or area(held) < 0.5 * area(holder.rect) then
			continue
		end
		local words = quote(clean(text.content))
		if flat and flats < 3 then
			add("collapsed-text", "high", element, ("%s has no width"):format(words))
			flats += 1
		elseif away and strays < 3 then
			add("offscreen-text", "high", element, ("%s is outside the screen"):format(words))
			strays += 1
		end
	end

	local cuts = 0
	for _, element in snapshot.elements do
		if cuts >= 3 then
			break
		end
		local text = element.text
		local lettered = text ~= nil and text.size >= 8 and clean(text.content) ~= ""
		if not element.visible or not (lettered or element.interactive) then
			continue
		end
		local box = if text and lettered then text.ink or element.rect else element.rect
		local seen = overlap(box, screen)
		if
			box.width < 4
			or box.height < 4
			or box.width > snapshot.width
			or box.height > snapshot.height
			or seen == nil
			or area(seen) < 0.5 * area(box)
			or (box.width - seen.width < EDGE_CUT and box.height - seen.height < EDGE_CUT)
		then
			continue
		end
		local clipped = false
		for _, ancestor in lineage(element) do
			if not ancestor.visible or ancestor.clips then
				clipped = true
				break
			end
		end
		if clipped then
			continue
		end
		local words = if text and lettered then quote(clean(text.content)) else leaf(element)
		add(
			"cut-at-edge",
			if text and lettered then "high" else "medium",
			element,
			("%s crosses the edge of the screen"):format(words)
		)
		cuts += 1
	end

	local joined = 0
	local buttons: { ReviewElement } = {}
	for _, element in snapshot.elements do
		if element.interactive and shown(element, snapshot.width, snapshot.height) then
			table.insert(buttons, element)
		end
	end
	for _, first in buttons do
		local reach = first.outset
		if reach == nil or joined >= 3 then
			continue
		end
		local a = first.rect
		for _, second in buttons do
			if second == first or joined >= 3 then
				continue
			end
			local b = second.rect
			local other = second.outset
			local across = math.min(a.x + a.width, b.x + b.width) - math.max(a.x, b.x)
			local along = math.min(a.y + a.height, b.y + b.height) - math.max(a.y, b.y)
			local below = across >= 0.5 * math.min(a.width, b.width) and b.y >= a.y + a.height
			local beside = along >= 0.5 * math.min(a.height, b.height) and b.x >= a.x + a.width
			local clear = if below
				then b.y - (a.y + a.height) - reach.bottom - (if other then other.top else 0)
				elseif beside then b.x - (a.x + a.width) - reach.right - (if other then other.left else 0)
				else nil
			if clear == nil or clear >= 1 then
				continue
			end
			local kin = false
			for _, ancestor in lineage(second) do
				kin = kin or ancestor == first
			end
			for _, ancestor in lineage(first) do
				kin = kin or ancestor == second
			end
			if kin then
				continue
			end
			add(
				"touching-controls",
				"medium",
				first,
				("the edge or the shadow of %s reaches %s"):format(leaf(first), leaf(second))
			)
			joined += 1
		end
	end

	local function seen(element: ReviewElement): ReviewRect?
		local rect: ReviewRect? = face(element)
		for _, ancestor in chainOf(element) do
			if rect == nil then
				break
			end
			if ancestor.clips then
				rect = overlap(rect, ancestor.rect)
			end
		end
		return rect
	end
	local function over(upper: ReviewElement, lower: ReviewElement): boolean
		local lowerChain, upperChain = chainOf(lower), chainOf(upper)
		if table.find(upperChain, lower) or table.find(lowerChain, upper) then
			return false
		end
		local held: ReviewElement? = nil
		local mine = lower
		for _, ancestor in lowerChain do
			if table.find(upperChain, ancestor) then
				held = ancestor
				break
			end
			mine = ancestor
		end
		local theirs = upper
		for _, ancestor in upperChain do
			if ancestor == held then
				break
			end
			theirs = ancestor
		end
		if held == nil then
			if mine.layer ~= theirs.layer then
				return false
			end
		elseif held.fan then
			return false
		end
		local low, high = mine.z or 1, theirs.z or 1
		return low < high or (low == high and mine.index < theirs.index)
	end
	local glass = snapshot.width * snapshot.height
	local sinks: { ReviewElement } = {}
	local solids: { { element: ReviewElement, rect: ReviewRect } } = {}
	for _, element in snapshot.elements do
		if not shown(element, snapshot.width, snapshot.height) then
			continue
		end
		local on = overlap(element.rect, { x = 0, y = 0, width = snapshot.width, height = snapshot.height })
		if element.sink and on ~= nil and area(on) >= 0.9 * glass then
			table.insert(sinks, element)
		end
		if solid(element) and area(element.rect) < 0.35 * glass and (element.turn or 0) <= 10 then
			local rect = seen(element)
			if rect ~= nil then
				table.insert(solids, { element = element, rect = rect })
			end
		end
	end
	local obscured = 0
	for _, control in buttons do
		if obscured >= 3 then
			break
		end
		local whole = control.rect
		local open = true
		for _, ancestor in chainOf(control) do
			local inside = if ancestor.clips then overlap(whole, ancestor.rect) else whole
			if ancestor.class == "ScrollingFrame" or inside == nil or area(inside) < area(whole) then
				open = false
				break
			end
		end
		local faced = solid(control) or #prepared.descendantTexts(control) > 0 or prepared.hasImage(control)
		if not open or not faced or whole.width < 16 or whole.height < 16 then
			continue
		end
		for _, sink in sinks do
			if over(sink, control) then
				open = false
				break
			end
		end
		if not open then
			continue
		end
		for _, cover in solids do
			local other = cover.element
			if other == control or other.parent == control.parent or area(cover.rect) < 0.5 * area(whole) then
				continue
			end
			local under = overlap(cover.rect, whole)
			if
				under == nil
				or under.width < 4
				or under.height < 4
				or area(under) < 0.1 * area(whole)
				or area(under) > 0.9 * area(whole)
				or not over(other, control)
			then
				continue
			end
			add(
				"covered-control",
				"medium",
				control,
				("%s covers %d by %d pixels of %s"):format(
					leaf(other),
					math.floor(under.width + 0.5),
					math.floor(under.height + 0.5),
					leaf(control)
				)
			)
			obscured += 1
			break
		end
	end

	local foreign: { ReviewElement } = {}
	for _, element in texts do
		if textOf(element).native == true and textOf(element).size >= 8 then
			table.insert(foreign, element)
		end
	end
	if #foreign >= 3 then
		add(
			"native-text",
			"medium",
			foreign[1],
			("%d texts were not built with UI.Text, such as %s"):format(
				#foreign,
				quote(clean(textOf(foreign[1]).content))
			)
		)
	end

	local backdrops: { ReviewElement } = {}
	for _, element in snapshot.elements do
		if element.image and area(element.rect) >= snapshot.width * snapshot.height * 0.25 then
			table.insert(backdrops, element)
		end
	end
	local pictures: { ReviewElement } = {}
	for _, element in snapshot.elements do
		if element.image and element.text == nil and shown(element, snapshot.width, snapshot.height) then
			table.insert(pictures, element)
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
		if not backed then
			for _, art in backdrops do
				if within(art.rect, element) then
					backed = true
					break
				end
			end
		end
		if not backed then
			for _, art in pictures do
				if art ~= element and backs(art, element.rect) and beneath(art, element) then
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

	local marks = 0
	for _, element in snapshot.elements do
		if element.unfit then
			add("composition-unfit", "high", element, `does not fit {element.unfit}`)
		end
		if element.reveal and element.visible and marks < 3 and area(element.rect) > 0 then
			add("unnamed-reveal", "medium", element, `the mark does not say that it holds {element.reveal}`)
			marks += 1
		end
	end

	local oversized: { [number]: Oversized } = {}
	local oversizedOrder: { number } = {}
	for _, element in snapshot.elements do
		if not element.visible or (element.class ~= "TextButton" and element.class ~= "ImageButton") then
			continue
		end
		local scroller: ReviewElement? = nil
		local parent = prepared.parentOf(element)
		while parent ~= nil and scroller == nil do
			local ancestor = prepared.byIndex[parent]
			if ancestor == nil then
				break
			end
			if ancestor.class == "ScrollingFrame" then
				scroller = ancestor
			end
			parent = prepared.parentOf(ancestor)
		end
		if scroller == nil or not shown(scroller, snapshot.width, snapshot.height) then
			continue
		end
		local rect, window = element.rect, scroller.rect
		if window.width < 48 or window.height < 48 then
			continue
		end
		local axis: string? = nil
		local size, room = 0, 0
		if rect.height > window.height + 1 then
			axis, size, room = "tall", rect.height, window.height
		elseif rect.width > window.width + 1 then
			axis, size, room = "wide", rect.width, window.width
		end
		if axis == nil then
			continue
		end
		local group = oversized[scroller.index]
		if group == nil then
			oversized[scroller.index] = { first = element, count = 1, axis = axis, size = size, room = room }
			table.insert(oversizedOrder, scroller.index)
		else
			group.count += 1
			group.size = math.max(group.size, size)
		end
	end
	for _, index in oversizedOrder do
		local group = oversized[index]
		add(
			"oversized-target",
			"medium",
			group.first,
			("%d control(s) up to %d px %s in a scroll area %d px %s"):format(
				group.count,
				math.floor(group.size),
				group.axis,
				math.floor(group.room),
				group.axis
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

	local measures: ReviewMeasures = { width = snapshot.width, height = snapshot.height, plates = 0 }
	local weight: { [number]: number } = {}
	for _, element in texts do
		local text = textOf(element)
		if text.size < 8 or not shown(element, snapshot.width, snapshot.height) then
			continue
		end
		local content = clean(text.content)
		weight[text.size] = (weight[text.size] or 0) + #content
		local lead = measures.numeral
		if string.find(content, "%d") and (lead == nil or text.size > lead.size) then
			measures.numeral = { content = content, size = text.size, share = text.size / math.max(1, snapshot.height) }
		end
	end
	for size, count in weight do
		local body = measures.body
		if body == nil or count > weight[body] or (count == weight[body] and size < body) then
			measures.body = size
		end
	end
	for _, plate in prepared.plates do
		if not plate.interactive and area(plate.rect) < 0.35 * glass then
			measures.plates += 1
		end
	end
	local faces: { ReviewElement } = {}
	for _, control in buttons do
		if solid(control) and control.rect.width >= 16 and control.rect.height >= 16 then
			table.insert(faces, control)
		end
	end
	if #faces > 0 then
		local heights: { number } = {}
		local aspects: { number } = {}
		local areas: { number } = {}
		for _, control in faces do
			table.insert(heights, control.rect.height)
			table.insert(aspects, control.rect.width / control.rect.height)
			table.insert(areas, area(control.rect))
		end
		measures.control = { height = median(heights), aspect = median(aspects) }
		local typical = math.max(1, median(areas))
		local best: ReviewElement? = nil
		local bestScore, bestContrast = 0, 1
		for _, control in faces do
			local total, others = 0, 0
			for _, other in faces do
				if other ~= control then
					total += contrast(control.fill, other.fill)
					others += 1
				end
			end
			local apart = if others > 0 then total / others else 1
			local score = apart * apart * math.sqrt(area(control.rect) / typical)
			if score > bestScore then
				best, bestScore, bestContrast = control, score, apart
			end
		end
		if best then
			local label = ""
			for _, text in prepared.descendantTexts(best) do
				label = clean(textOf(text).content)
				if label ~= "" then
					break
				end
			end
			measures.action = {
				label = if label ~= "" then label else string.match(best.path, "[^%.]+$") or best.class,
				x = (best.rect.x + best.rect.width / 2) / math.max(1, snapshot.width),
				y = (best.rect.y + best.rect.height / 2) / math.max(1, snapshot.height),
				width = best.rect.width / math.max(1, snapshot.width),
				height = best.rect.height / math.max(1, snapshot.height),
				scale = area(best.rect) / typical,
				contrast = bestContrast,
			}
		end
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
	local medium = 0
	for _, rule in order do
		if grouped[rule][1].severity == "medium" then
			medium += 1
		end
	end
	if medium > 0 then
		table.insert(lines, MEDIUM_NOTE:format(medium))
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
	table.insert(lines, ("  measures, as shares of a screen of %d by %d:"):format(snapshot.width, snapshot.height))
	local numeral, body = measures.numeral, measures.body
	if numeral then
		table.insert(
			lines,
			("    largest numeral: %s %g px, %.1f%% of the height%s"):format(
				quote(numeral.content),
				numeral.size,
				numeral.share * 100,
				if body then ("; most text is %g px, a ratio of %.1f"):format(body, numeral.size / body) else ""
			)
		)
	elseif body then
		table.insert(lines, ("    no numeral; most text is %g px"):format(body))
	end
	local control, action = measures.control, measures.action
	table.insert(
		lines,
		("    plates: %d%s"):format(
			measures.plates,
			if control
				then ("; a typical control is %g px high and %.1f times as wide"):format(
					math.floor(control.height + 0.5),
					control.aspect
				)
				else ""
		)
	)
	if action then
		table.insert(
			lines,
			("    strongest control: %s at %d%% across and %d%% down, %d%% by %d%%; %.1f times a typical control, contrast %.1f to the others"):format(
				quote(action.label),
				math.floor(action.x * 100 + 0.5),
				math.floor(action.y * 100 + 0.5),
				math.floor(action.width * 100 + 0.5),
				math.floor(action.height * 100 + 0.5),
				action.scale,
				action.contrast
			)
		)
	end
	return {
		findings = findings,
		prominence = prominence,
		measures = measures,
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
