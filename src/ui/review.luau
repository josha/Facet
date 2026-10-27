--!strict
local Rules = require("./review_rules")

export type ReviewReport = Rules.ReviewReport
export type ReviewSnapshot = Rules.ReviewSnapshot
export type ReviewElement = Rules.ReviewElement
export type ReviewFinding = Rules.ReviewFinding
export type ReviewOptions = { root: Instance? }

type Object = { [string]: unknown }

local ROLE_PREFIX = "facet-type-"
local ENGINE_GUIS: { [string]: boolean } = { TouchGui = true, Freecam = true, BubbleChat = true, Chat = true }

local function read(object: unknown, key: string): unknown
	if object == nil then
		return nil
	end
	local ok, value = pcall(function(): unknown
		return (object :: Object)[key]
	end)
	return if ok then value else nil
end

local function call(object: unknown, method: string, ...: unknown): (boolean, unknown)
	local callback = read(object, method)
	if type(callback) ~= "function" then
		return false, nil
	end
	local fn = callback :: (...unknown) -> unknown
	local ok, value = pcall(fn, object, ...)
	if not ok then
		return false, nil
	end
	return true, value
end

local function isA(object: unknown, class: string): boolean
	local ok, answer = call(object, "IsA", class)
	return ok and answer == true
end

local function styled(object: unknown, key: string): unknown
	local ok, value = call(object, "GetStyled", key)
	return if ok and value ~= nil then value else read(object, key)
end

local function number(value: unknown, fallback: number): number
	if type(value) == "number" and value == value and math.abs(value) ~= math.huge then
		return value
	end
	return fallback
end

local function color(value: unknown): Rules.ReviewColor
	return { r = number(read(value, "R"), 0), g = number(read(value, "G"), 0), b = number(read(value, "B"), 0) }
end

local function vector(value: unknown): (number, number)
	return number(read(value, "X"), 0), number(read(value, "Y"), 0)
end

local function children(object: unknown): { unknown }
	local ok, list = call(object, "GetChildren")
	return if ok and type(list) == "table" then list :: { unknown } else {}
end

local function text(value: unknown): string?
	return if type(value) == "string" then value else nil
end

local function role(object: unknown): string?
	local ok, tags = call(object, "GetTags")
	if not ok or type(tags) ~= "table" then
		return nil
	end
	for _, tag in tags :: { unknown } do
		if type(tag) == "string" and string.sub(tag, 1, #ROLE_PREFIX) == ROLE_PREFIX then
			return string.sub(tag, #ROLE_PREFIX + 1)
		end
	end
	return nil
end

local function dataModel(): unknown
	local environment: unknown = getfenv
	if type(environment) ~= "function" then
		return nil
	end
	return read(getfenv(0), "game")
end

local function roots(root: Instance?): { unknown }
	if root ~= nil then
		return { root }
	end
	local game = dataModel()
	local ok, players = call(game, "GetService", "Players")
	local player = if ok then read(players, "LocalPlayer") else nil
	local found, gui = call(player, "FindFirstChildOfClass", "PlayerGui")
	assert(found and gui ~= nil, "Facet review: there is no PlayerGui here. Run it on the client, or pass a root.")
	return { gui }
end

local function collect(options: ReviewOptions?): ReviewSnapshot
	local given: ReviewOptions = options or {}
	local game: unknown = nil
	if given.root ~= nil then
		local found, model = call(given.root, "FindFirstAncestorWhichIsA", "DataModel")
		game = if found then model else nil
	else
		game = dataModel()
	end
	local ok, workspace = call(game, "GetService", "Workspace")
	local width, height = vector(read(if ok then read(workspace, "CurrentCamera") else nil, "ViewportSize"))
	local elements: { ReviewElement } = {}
	local visit: (unknown, number?, boolean, number) -> ()
	local function visitChild(child: unknown, parent: number?, shown: boolean, scale: number)
		do
			local nextParent, nextShown, nextScale = parent, shown, scale
			if isA(child, "LayerCollector") then
				local name = text(read(child, "Name"))
				if not isA(child, "ScreenGui") or (name ~= nil and ENGINE_GUIS[name]) then
					return
				end
				nextShown = shown and read(child, "Enabled") ~= false
			elseif isA(child, "GuiObject") then
				local found, uiScale = call(child, "FindFirstChildOfClass", "UIScale")
				if found and uiScale ~= nil then
					nextScale = scale * number(read(uiScale, "Scale"), 1)
				end
				local x, y = vector(read(child, "AbsolutePosition"))
				local w, h = vector(read(child, "AbsoluteSize"))
				local visible = shown and read(child, "Visible") ~= false
				local element: ReviewElement = {
					index = #elements + 1,
					parent = parent,
					class = text(read(child, "ClassName")) or "GuiObject",
					path = (function(): string
						local named, path = call(child, "GetFullName")
						return if named and type(path) == "string" then path else "?"
					end)(),
					rect = { x = x, y = y, width = w, height = h },
					visible = visible,
					interactive = isA(child, "GuiButton") or isA(child, "TextBox"),
					fill = color(styled(child, "BackgroundColor3")),
					fillTransparency = math.clamp(number(styled(child, "BackgroundTransparency"), 1), 0, 1),
					image = isA(child, "ViewportFrame")
						or (
							(isA(child, "ImageLabel") or isA(child, "ImageButton"))
							and (text(read(child, "Image")) or "") ~= ""
							and number(styled(child, "ImageTransparency"), 0) < 0.9
						),
				}
				if isA(child, "TextLabel") or isA(child, "TextButton") or isA(child, "TextBox") then
					local face = styled(child, "FontFace")
					local weight = number(read(read(face, "Weight"), "Value"), 400)
					local size = number(styled(child, "TextSize"), 14)
					if styled(child, "TextScaled") == true then
						local _, boundsHeight = vector(read(child, "TextBounds"))
						size = if boundsHeight > 0 then boundsHeight / nextScale else size
					end
					element.text = {
						content = text(read(child, "Text")) or "",
						size = math.floor(size * nextScale + 0.5),
						bold = weight >= 600,
						font = text(read(face, "Family")),
						role = role(child),
						color = color(styled(child, "TextColor3")),
						transparency = math.clamp(number(styled(child, "TextTransparency"), 0), 0, 1),
					}
				end
				table.insert(elements, element)
				nextParent, nextShown = element.index, visible
			end
			visit(child, nextParent, nextShown, nextScale)
		end
	end
	visit = function(object: unknown, parent: number?, shown: boolean, scale: number)
		for _, child in children(object) do
			visitChild(child, parent, shown, scale)
		end
	end
	for _, root in roots(given.root) do
		if isA(root, "GuiObject") or isA(root, "LayerCollector") then
			visitChild(root, nil, true, 1)
		else
			visit(root, nil, true, 1)
		end
	end
	if width <= 0 or height <= 0 then
		for _, element in elements do
			width = math.max(width, element.rect.x + element.rect.width)
			height = math.max(height, element.rect.y + element.rect.height)
		end
	end
	return { width = width, height = height, elements = elements }
end

return table.freeze({
	analyze = Rules.analyze,
	collect = collect,
	screen = function(options: ReviewOptions?): ReviewReport
		return Rules.analyze(collect(options))
	end,
	fixes = Rules.fixes,
})
