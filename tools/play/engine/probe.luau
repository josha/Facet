--!strict

local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Collect = require("../../../tools/vendor/verify/src/roblox/ui-audit-collect")
local scrollTarget = require("./scroll_target")
local racingDrive = require("./racing_drive")
local Mount = require("./mount")
local frameStability = require("../../studio/live/frame_stability")
local invalidSelections = 0
game:GetService("LogService").MessageOut:Connect(function(message: string)
	if string.find(message, "SelectedObject", 1, true) and string.find(message, "invalid GuiObject", 1, true) then
		invalidSelections += 1
	end
end)

export type Rect = { x: number, y: number, width: number, height: number }

export type Query = {
	text: string?,
	pattern: string?,
	exact: string?,
	role: string?,
	near: string?,
	index: number?,
	clipped: boolean?,
}

export type Info = {
	path: string,
	class: string,
	label: string,
	rect: Rect,
	selectable: boolean,
	interactable: boolean,
	button: boolean,
	score: number?,
}

type Request = { command: string, [string]: unknown }

type Stash = { pieces: { string }, bytes: number, automatic: boolean? }

local FRAME_NAME = "QAProbeFrame"
local SAFE_NAME = "QAProbeSafeArea"
local EXCLUDED: { [string]: boolean } = {
	[FRAME_NAME] = true,
	[SAFE_NAME] = true,
	TouchGui = true,
	Freecam = true,
	Chat = true,
	BubbleChat = true,
}
local CHUNK = 48000
local DIRECTIONS: { [string]: Enum.KeyCode } = {
	up = Enum.KeyCode.Up,
	down = Enum.KeyCode.Down,
	left = Enum.KeyCode.Left,
	right = Enum.KeyCode.Right,
}
local ORDER = { "down", "right", "up", "left" }

local state: { input: VirtualInput?, frame: ScreenGui?, safe: ScreenGui?, stashes: { [string]: Stash }, serial: number } =
	{
		input = nil,
		frame = nil,
		safe = nil,
		stashes = {},
		serial = 0,
	}

local function frames(count: number)
	for _ = 1, count do
		RunService.Heartbeat:Wait()
	end
end

local function playerGui(): PlayerGui
	local player: Player? = Players.LocalPlayer
	assert(player, "the probe needs a local player")
	return player:WaitForChild("PlayerGui", 10) :: PlayerGui
end

local function overlay(name: string, insets: Enum.ScreenInsets): ScreenGui
	local gui = playerGui()
	local existing = gui:FindFirstChild(name)
	if existing ~= nil and existing:IsA("ScreenGui") then
		return existing
	end
	local created = Instance.new("ScreenGui")
	created.Name = name
	created.ResetOnSpawn = false
	created.ScreenInsets = insets
	created.DisplayOrder = -1000
	created.Parent = gui
	return created
end

local function frame(): ScreenGui
	local current = state.frame
	if current == nil or current.Parent == nil then
		local created = overlay(FRAME_NAME, Enum.ScreenInsets.None)
		created.IgnoreGuiInset = true
		state.frame = created
		return created
	end
	return current :: ScreenGui
end

local function safeArea(): ScreenGui
	local current = state.safe
	if current == nil or current.Parent == nil then
		current = overlay(SAFE_NAME, Enum.ScreenInsets.CoreUISafeInsets)
		state.safe = current
	end
	return current :: ScreenGui
end

local function input(): VirtualInput
	local current = state.input
	if current == nil then
		local created: Object? = UserInputService:CreateVirtualInput()
		assert(created, "virtual input is not available")
		current = created :: VirtualInput
		state.input = current
	end
	return current :: VirtualInput
end

local function origin(): Vector2
	return frame().AbsolutePosition
end

local function screenRect(): Rect
	local root = frame()
	return { x = 0, y = 0, width = root.AbsoluteSize.X, height = root.AbsoluteSize.Y }
end

local function rectOf(object: GuiBase2d): Rect
	local base = origin()
	return {
		x = object.AbsolutePosition.X - base.X,
		y = object.AbsolutePosition.Y - base.Y,
		width = object.AbsoluteSize.X,
		height = object.AbsoluteSize.Y,
	}
end

local function intersect(left: Rect, right: Rect): Rect
	local x1 = math.max(left.x, right.x)
	local y1 = math.max(left.y, right.y)
	local x2 = math.min(left.x + left.width, right.x + right.width)
	local y2 = math.min(left.y + left.height, right.y + right.height)
	return { x = x1, y = y1, width = math.max(0, x2 - x1), height = math.max(0, y2 - y1) }
end

local function roots(): { LayerCollector }
	local found: { LayerCollector } = {}
	for _, child in playerGui():GetChildren() do
		if child:IsA("LayerCollector") and not EXCLUDED[child.Name] then
			table.insert(found, child)
		end
	end
	return found
end

local function shownRect(object: GuiObject, anywhere: boolean): Rect?
	local rect = rectOf(object)
	local cursor: Instance? = object
	local rooted = false
	while cursor ~= nil do
		if cursor:IsA("GuiObject") then
			if not cursor.Visible then
				return nil
			end
			if cursor ~= object and not anywhere then
				if cursor:IsA("ScrollingFrame") then
					local window = rectOf(cursor)
					window.width = cursor.AbsoluteWindowSize.X
					window.height = cursor.AbsoluteWindowSize.Y
					rect = intersect(rect, window)
				elseif cursor.ClipsDescendants or cursor:IsA("CanvasGroup") then
					rect = intersect(rect, rectOf(cursor))
				end
			end
			if cursor:IsA("CanvasGroup") and cursor.GroupTransparency >= 0.98 then
				return nil
			end
		elseif cursor:IsA("LayerCollector") then
			if not cursor.Enabled then
				return nil
			end
			rooted = true
			break
		end
		cursor = cursor.Parent
	end
	if not rooted then
		return nil
	end
	if not anywhere then
		rect = intersect(rect, screenRect())
	end
	if rect.width < 2 or rect.height < 2 then
		return nil
	end
	return rect
end

local function ownText(object: Instance): string?
	if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
		if object.TextTransparency >= 0.98 then
			return nil
		end
		local content = if object:IsA("TextBox") and object.ContentText == ""
			then object.PlaceholderText
			else object.ContentText
		if not object:IsA("TextBox") and object.MaxVisibleGraphemes >= 0 then
			local limit = object.MaxVisibleGraphemes
			local count = 0
			local cut = #content
			for position in utf8.graphemes(content) do
				if count >= limit then
					cut = position - 1
					break
				end
				count += 1
			end
			content = string.sub(content, 1, cut)
		end
		if content ~= "" then
			return content
		end
	end
	return nil
end

local function label(object: GuiObject): string
	local pieces: { string } = {}
	local own = ownText(object)
	if own ~= nil then
		table.insert(pieces, own)
	end
	if object:IsA("GuiButton") or object.Selectable then
		local function visit(parent: Instance, depth: number)
			if depth > 6 then
				return
			end
			for _, child in parent:GetChildren() do
				if child:IsA("GuiObject") and child.Visible then
					local text = ownText(child)
					if text ~= nil then
						table.insert(pieces, text)
					end
					if not child:IsA("GuiButton") then
						visit(child, depth + 1)
					end
				end
			end
		end
		visit(object, 1)
	end
	return table.concat(pieces, " ")
end

local function normalize(value: string): string
	return string.lower((string.gsub(value, "%s+", " ")))
end

local function textMatches(text: string, query: Query): boolean
	local normal = normalize(text)
	if query.exact ~= nil and normal ~= normalize(query.exact :: string) then
		return false
	end
	if query.text ~= nil and string.find(normal, normalize(query.text :: string), 1, true) == nil then
		return false
	end
	if query.pattern ~= nil and string.find(normal, query.pattern :: string) == nil then
		return false
	end
	return true
end

local function roleMatches(object: GuiObject, role: string?): boolean
	if role == nil or role == "any" then
		return true
	elseif role == "button" then
		return object:IsA("GuiButton")
	elseif role == "input" then
		return object:IsA("TextBox")
	elseif role == "text" then
		return ownText(object) ~= nil
	elseif role == "selectable" then
		return object.Selectable
	end
	return false
end

local function describe(object: GuiObject, rect: Rect): Info
	return {
		path = object:GetFullName(),
		class = object.ClassName,
		label = label(object),
		rect = rect,
		selectable = object.Selectable,
		interactable = object.Interactable,
		button = object:IsA("GuiButton"),
		score = nil,
	}
end

local function depthOf(object: Instance): number
	local depth = 0
	local cursor = object.Parent
	while cursor ~= nil do
		depth += 1
		cursor = cursor.Parent
	end
	return depth
end

local function treeDistance(left: Instance, right: Instance): number
	local seen: { [Instance]: number } = {}
	local steps = 0
	local cursor: Instance? = left
	while cursor ~= nil do
		seen[cursor] = steps
		steps += 1
		cursor = cursor.Parent
	end
	steps = 0
	cursor = right
	while cursor ~= nil do
		local found = seen[cursor]
		if found ~= nil then
			return found + steps
		end
		steps += 1
		cursor = cursor.Parent
	end
	return math.huge
end

type Candidate = { object: GuiObject, rect: Rect, score: number, distance: number }

type Line = { text: string, rect: Rect }

local function each(callback: (GuiObject) -> ())
	for _, root in roots() do
		if root.Enabled then
			for _, descendant in root:GetDescendants() do
				if descendant:IsA("GuiObject") then
					callback(descendant)
				end
			end
		end
	end
end

local function anchors(text: string): { { object: GuiObject, rect: Rect } }
	local found: { { object: GuiObject, rect: Rect } } = {}
	local wanted = normalize(text)
	each(function(object)
		local own = ownText(object)
		if own ~= nil and string.find(normalize(own), wanted, 1, true) ~= nil then
			local rect = shownRect(object, true)
			if rect ~= nil then
				table.insert(found, { object = object, rect = rect })
			end
		end
	end)
	return found
end

local function center(rect: Rect): Vector2
	return Vector2.new(rect.x + rect.width / 2, rect.y + rect.height / 2)
end

local function search(query: Query): { Candidate }
	local candidates: { Candidate } = {}
	local near = if query.near ~= nil then anchors(query.near :: string) else nil
	each(function(object)
		if not roleMatches(object, query.role) then
			return
		end
		local text = label(object)
		if (query.text ~= nil or query.pattern ~= nil or query.exact ~= nil) and not textMatches(text, query) then
			return
		end
		local rect = shownRect(object, query.clipped == true)
		if rect == nil then
			return
		end
		local score = 0
		local distance = 0
		if near ~= nil then
			score = math.huge
			distance = math.huge
			for _, anchor in near do
				local tree = treeDistance(object, anchor.object)
				local gap = (center(rect) - center(anchor.rect)).Magnitude
				if tree < score or (tree == score and gap < distance) then
					score = tree
					distance = gap
				end
			end
			if score == math.huge then
				return
			end
		end
		table.insert(candidates, { object = object, rect = rect, score = score, distance = distance })
	end)
	table.sort(candidates, function(left: Candidate, right: Candidate): boolean
		if left.score ~= right.score then
			return left.score < right.score
		end
		if left.distance ~= right.distance then
			return left.distance < right.distance
		end
		if math.abs(left.rect.y - right.rect.y) > 2 then
			return left.rect.y < right.rect.y
		end
		if math.abs(left.rect.x - right.rect.x) > 2 then
			return left.rect.x < right.rect.x
		end
		return depthOf(left.object) > depthOf(right.object)
	end)
	return candidates
end

local function resolve(query: Query): Candidate?
	local found = search(query)
	return found[query.index or 1]
end

local function blocker(point: Vector2): GuiObject?
	local base = origin()
	local absolute = point + base
	for _, object in playerGui():GetGuiObjectsAtPosition(math.floor(absolute.X), math.floor(absolute.Y)) do
		local root = object:FindFirstAncestorWhichIsA("LayerCollector")
		if root ~= nil and EXCLUDED[root.Name] then
			continue
		end
		if (object:IsA("GuiButton") or object:IsA("TextBox") or object.Active) and object.Interactable then
			if shownRect(object, false) ~= nil then
				return object
			end
		end
	end
	return nil
end

local function reachable(object: GuiObject, rect: Rect): (Vector2?, string?)
	local samples = {
		Vector2.new(0.5, 0.5),
		Vector2.new(0.3, 0.5),
		Vector2.new(0.7, 0.5),
		Vector2.new(0.5, 0.3),
		Vector2.new(0.5, 0.7),
	}
	local covering: string? = nil
	for _, sample in samples do
		local point = Vector2.new(rect.x + rect.width * sample.X, rect.y + rect.height * sample.Y)
		local top = blocker(point)
		if top == nil or top == object or top:IsDescendantOf(object) or object:IsDescendantOf(top) then
			return point, nil
		end
		covering = top:GetFullName()
	end
	return nil, covering
end

local function queryOf(value: unknown): Query
	assert(type(value) == "table", "a query must be a table")
	local raw = value :: { [string]: unknown }
	local function text(key: string): string?
		local item = raw[key]
		if item == nil then
			return nil
		end
		assert(type(item) == "string", "query field " .. key .. " must be a string")
		return item
	end
	local index = raw.index
	assert(index == nil or type(index) == "number", "query index must be a number")
	return {
		text = text("text"),
		pattern = text("pattern"),
		exact = text("exact"),
		role = text("role"),
		near = text("near"),
		index = index :: number?,
		clipped = raw.clipped == true,
	}
end

local function click(point: Vector2)
	local device = input()
	device:SendMousePosition(point)
	frames(1)
	device:SendMouseButton(point, Enum.UserInputType.MouseButton1, true, 0)
	frames(2)
	device:SendMouseButton(point, Enum.UserInputType.MouseButton1, false, 0)
	frames(2)
end

local function press(object: GuiObject, point: Vector2): (boolean, number)
	if not object:IsA("GuiButton") then
		click(point)
		return true, 1
	end
	local button = object :: GuiButton
	local fired = false
	local connection = button.Activated:Connect(function()
		fired = true
	end)
	local attempts = 0
	while not fired and attempts < 2 do
		attempts += 1
		click(point)
		for _ = 1, 20 do
			if fired or button.Parent == nil then
				break
			end
			frames(1)
		end
		if button.Parent == nil then
			break
		end
	end
	connection:Disconnect()
	return fired, attempts
end

local function key(code: Enum.KeyCode)
	local device = input()
	device:SendKey(true, code, false)
	frames(2)
	device:SendKey(false, code, false)
	frames(2)
end

local function keyCode(name: string): Enum.KeyCode
	local direction = DIRECTIONS[string.lower(name)]
	if direction ~= nil then
		return direction
	end
	for _, item in Enum.KeyCode:GetEnumItems() do
		if item.Name == name then
			return item
		end
	end
	error("unknown key " .. name, 0)
end

local function selectedInfo(): Info?
	local selected = GuiService.SelectedObject
	if selected == nil then
		return nil
	end
	local rect = shownRect(selected, true) or rectOf(selected)
	return describe(selected, rect)
end

local function fullyShown(object: GuiObject): boolean
	local rect = shownRect(object, false)
	if rect == nil then
		return false
	end
	local whole = rectOf(object)
	return rect.width >= whole.width - 1 and rect.height >= whole.height - 1
end

local function nudge(scroller: ScrollingFrame, window: Rect, deltaX: number, deltaY: number, mode: string): boolean
	local before = scroller.CanvasPosition
	local middle = center(window)
	if mode == "touch" then
		local limitY = window.height * 0.4
		local limitX = window.width * 0.4
		local moveY = math.clamp(deltaY, -limitY, limitY)
		local moveX = math.clamp(deltaX, -limitX, limitX)
		local device = input()
		local start = middle + Vector2.new(moveX / 2, moveY / 2)
		local finish = middle - Vector2.new(moveX / 2, moveY / 2)
		device:SendMousePosition(start)
		device:SendMouseButton(start, Enum.UserInputType.MouseButton1, true, 0)
		for step = 1, 8 do
			frames(1)
			device:SendMousePosition(start:Lerp(finish, step / 8))
		end
		frames(1)
		device:SendMouseButton(finish, Enum.UserInputType.MouseButton1, false, 0)
		frames(10)
		for _ = 1, 180 do
			if scroller:GetScrollVelocity().Magnitude <= 1 then
				break
			end
			frames(1)
		end
	else
		local wheel = if math.abs(deltaY) >= math.abs(deltaX) then -math.sign(deltaY) else -math.sign(deltaX)
		input():SendPointerAction(middle, { Wheel = wheel })
		frames(4)
	end
	return (scroller.CanvasPosition - before).Magnitude >= 0.5
end

local function scrollers(): { ScrollingFrame }
	local found: { { scroller: ScrollingFrame, area: number } } = {}
	each(function(object)
		if not object:IsA("ScrollingFrame") or not object.ScrollingEnabled then
			return
		end
		local spare = object.AbsoluteCanvasSize - object.AbsoluteWindowSize
		if spare.X < 1 and spare.Y < 1 then
			return
		end
		local window = shownRect(object, false)
		if window ~= nil then
			table.insert(found, { scroller = object, area = window.width * window.height })
		end
	end)
	table.sort(
		found,
		function(
			left: { scroller: ScrollingFrame, area: number },
			right: { scroller: ScrollingFrame, area: number }
		): boolean
			return left.area > right.area
		end
	)
	local ordered: { ScrollingFrame } = {}
	for _, entry in found do
		table.insert(ordered, entry.scroller)
	end
	return ordered
end

local function sweep(scroller: ScrollingFrame, direction: number, mode: string, wide: Query): boolean
	local vertical = scroller.AbsoluteCanvasSize.Y - scroller.AbsoluteWindowSize.Y >= 1
	local wheelMode = mode
	for _ = 1, 80 do
		local window = shownRect(scroller, false)
		if window == nil then
			return false
		end
		local stride = direction * (if vertical then window.height else window.width) * 0.8
		local moved = nudge(scroller, window, if vertical then 0 else stride, if vertical then stride else 0, wheelMode)
		if resolve(wide) ~= nil then
			return true
		end
		if not moved then
			if wheelMode == "touch" then
				return false
			end
			wheelMode = "touch"
		end
	end
	return false
end

local function seek(query: Query, mode: string): boolean
	local wide = table.clone(query)
	wide.clipped = true
	if resolve(wide) ~= nil then
		return true
	end
	for _, scroller in scrollers() do
		if sweep(scroller, 1, mode, wide) or sweep(scroller, -1, mode, wide) then
			return true
		end
	end
	return false
end

local function reveal(query: Query, mode: string): { revealed: boolean, steps: number, info: Info? }
	local wide = table.clone(query)
	wide.clipped = true
	local target = resolve(wide)
	if target == nil and seek(query, mode) then
		target = resolve(wide)
	end
	if target == nil then
		return { revealed = false, steps = 0, info = nil }
	end
	local object = target.object
	local steps = 0
	while not fullyShown(object) and steps < 40 do
		local scroller, deltaX, deltaY = scrollTarget(object, mode == "touch")
		if scroller == nil then
			break
		end
		local window = shownRect(scroller, false)
		if window == nil then
			break
		end
		if deltaX == 0 and deltaY == 0 then
			break
		end
		steps += 1
		if not nudge(scroller, window, deltaX, deltaY, mode) then
			if mode ~= "touch" then
				mode = "touch"
			else
				break
			end
		end
	end
	local shown = shownRect(object, false)
	return {
		revealed = fullyShown(object),
		steps = steps,
		info = if shown ~= nil then describe(object, shown) else nil,
	}
end

local function targetOf(query: Query): GuiObject?
	local wide = table.clone(query)
	wide.clipped = true
	local found = resolve(wide)
	return if found ~= nil then found.object else nil
end

local function same(left: GuiObject, right: GuiObject): boolean
	return left == right or left:IsDescendantOf(right) or right:IsDescendantOf(left)
end

local function gamepadPath(query: Query, limit: number): { [string]: unknown }
	local start = GuiService.SelectedObject
	if start == nil then
		return { found = false, reason = "nothing is selected", visited = 0 }
	end
	local target = targetOf(query)
	if target == nil then
		return { found = false, reason = "no element matches the target", visited = 0 }
	end
	local function selectionMatches(node: GuiObject, _query: Query): boolean
		return same(node, target :: GuiObject)
	end
	local parents: { [GuiObject]: { from: GuiObject, direction: string } } = {}
	local visited: { [GuiObject]: boolean } = { [start] = true }
	local queue: { GuiObject } = { start }
	local count = 1
	local found: GuiObject? = nil
	local labels: { string } = {}
	while #queue > 0 do
		local node = table.remove(queue, 1) :: GuiObject
		table.insert(labels, label(node))
		if selectionMatches(node, query) then
			found = node
			break
		end
		if count >= limit then
			continue
		end
		for _, direction in ORDER do
			if not node.Selectable or not node.Interactable or shownRect(node, false) == nil then
				break
			end
			GuiService.SelectedObject = node
			frames(1)
			key(DIRECTIONS[direction])
			local next = GuiService.SelectedObject
			if next ~= nil and next ~= node and not visited[next] then
				visited[next] = true
				parents[next] = { from = node, direction = direction }
				table.insert(queue, next)
				count += 1
			end
		end
	end
	if start.Selectable and start.Interactable and shownRect(start, false) ~= nil then
		GuiService.SelectedObject = start
	end
	frames(2)
	if found == nil then
		return { found = false, reason = "no selection path reaches the control", visited = count, labels = labels }
	end
	local path: { string } = {}
	local cursor: GuiObject = found
	while parents[cursor] ~= nil do
		local step = parents[cursor]
		table.insert(path, 1, step.direction)
		cursor = step.from
	end
	return { found = true, path = path, visited = count, target = label(found) }
end

local function visibleTexts(): { { text: string, rect: Rect } }
	local found: { Line } = {}
	each(function(object)
		local own = ownText(object)
		if own ~= nil then
			local rect = shownRect(object, false)
			if rect ~= nil then
				table.insert(found, { text = own, rect = rect })
			end
		end
	end)
	table.sort(found, function(left: Line, right: Line): boolean
		if math.abs(left.rect.y - right.rect.y) > 2 then
			return left.rect.y < right.rect.y
		end
		return left.rect.x < right.rect.x
	end)
	return found
end

local function stash(
	text: string,
	first: boolean?
): { token: string, count: number, bytes: number, first: string?, automatic: boolean? }
	state.serial += 1
	local token = "s" .. tostring(state.serial)
	local pieces: { string } = {}
	local cursor = 1
	while cursor <= #text do
		local last = math.min(cursor + CHUNK - 1, #text)
		while last < #text and last > cursor do
			local following = string.byte(text, last + 1)
			if following >= 128 and following < 192 then
				last -= 1
			else
				break
			end
		end
		table.insert(pieces, string.sub(text, cursor, last))
		cursor = last + 1
	end
	if #pieces == 0 then
		table.insert(pieces, "")
	end
	state.stashes[token] = { pieces = pieces, bytes = #text, automatic = first }
	return { token = token, count = #pieces, bytes = #text, first = if first then pieces[1] else nil, automatic = first }
end

local function inputs(): { [string]: boolean }
	return {
		touch = UserInputService.TouchEnabled,
		mouse = UserInputService.MouseEnabled,
		keyboard = UserInputService.KeyboardEnabled,
		gamepad = UserInputService.GamepadEnabled,
		tenFoot = GuiService:IsTenFootInterface(),
	}
end

local function viewport(): { width: number, height: number, screenWidth: number, screenHeight: number }
	local camera: Camera? = workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else Vector2.zero
	local screen = screenRect()
	return { width = size.X, height = size.Y, screenWidth = screen.width, screenHeight = screen.height }
end

local function stringField(request: Request, key: string): string
	local value = request[key]
	assert(type(value) == "string", key .. " must be a string")
	return value
end

local function numberField(request: Request, key: string, default: number): number
	local value = request[key]
	if value == nil then
		return default
	end
	assert(type(value) == "number", key .. " must be a number")
	return value
end

local handlers: { [string]: (Request) -> unknown } = {}

local stabilityConnection: RBXScriptConnection? = nil
local stabilityTracker = frameStability.new()
handlers.frameStability = function(request): unknown
	if stabilityConnection then
		stabilityConnection:Disconnect()
		stabilityConnection = nil
	end
	if stringField(request, "action") == "begin" then
		stabilityTracker = frameStability.new()
		local identities: { [Instance]: number } = {}
		local serial = 0
		stabilityConnection = RunService.RenderStepped:Connect(function()
			local samples: { frameStability.Sample } = {}
			each(function(object)
				if shownRect(object, false) == nil then
					return
				end
				if identities[object] == nil then
					serial += 1
					identities[object] = serial
				end
				local position, size = object.AbsolutePosition, object.AbsoluteSize
				table.insert(samples, {
					path = object:GetFullName() .. "#" .. tostring(identities[object]),
					rect = { position.X, position.Y, size.X, size.Y },
				})
			end)
			frameStability.push(stabilityTracker, samples)
		end)
	end
	return { frames = stabilityTracker.frame, seen = stabilityTracker.seen, faults = stabilityTracker.faults }
end

handlers.touchControls = function(): unknown
	local gui = playerGui()
	local touch = gui:FindFirstChild("TouchGui")
	local controlFrame = if touch then touch:FindFirstChild("TouchControlFrame") else nil
	local rectangles: { { name: string, path: string, rect: Rect } } = {}
	local function add(node: Instance?, name: string)
		if node == nil or not node:IsA("GuiObject") or node.AbsoluteSize.X <= 0 or node.AbsoluteSize.Y <= 0 then
			return
		end
		local parent: Instance? = node
		while parent ~= nil and parent ~= gui do
			if parent:IsA("GuiObject") and not parent.Visible then
				return
			elseif parent:IsA("ScreenGui") and not parent.Enabled then
				return
			end
			parent = parent.Parent
		end
		local base = origin()
		table.insert(rectangles, {
			name = name,
			path = node:GetFullName(),
			rect = {
				x = node.AbsolutePosition.X - base.X,
				y = node.AbsolutePosition.Y - base.Y,
				width = node.AbsoluteSize.X,
				height = node.AbsoluteSize.Y,
			},
		})
	end
	if controlFrame ~= nil then
		for _, name in { "ThumbstickFrame", "DynamicThumbstickFrame", "JumpButton" } do
			add(controlFrame:FindFirstChild(name, true), name)
		end
	end
	local actions = game:GetService("ContextActionService")
	for name in actions:GetAllBoundActionInfo() do
		add(actions:GetButton(name), "CAS:" .. name)
	end
	return { available = controlFrame ~= nil, rectangles = rectangles }
end

handlers.ping = function()
	local gui = playerGui()
	frame()
	safeArea()
	return {
		ready = true,
		roots = #roots(),
		viewport = viewport(),
		inputs = inputs(),
		loaded = game:IsLoaded(),
		gui = gui:GetFullName(),
	}
end

handlers.find = function(request)
	local query = queryOf(request.query)
	local found: { Info } = {}
	for index, candidate in search(query) do
		if index > numberField(request, "limit", 8) then
			break
		end
		local info = describe(candidate.object, candidate.rect)
		info.score = candidate.score
		table.insert(found, info)
	end
	return found
end

handlers.texts = function()
	return visibleTexts()
end

handlers.tap = function(request: Request): unknown
	local query = queryOf(request.query)
	local found = search(query)
	if #found == 0 then
		return { tapped = false, reason = "no visible element matches" }
	end
	local covered: { string } = {}
	for index = query.index or 1, #found do
		local target = found[index]
		local point, covering = reachable(target.object, target.rect)
		if point ~= nil then
			local activated, attempts = press(target.object, point)
			return {
				tapped = true,
				activated = activated,
				attempts = attempts,
				info = describe(target.object, target.rect),
				point = { x = point.X, y = point.Y },
			}
		end
		table.insert(covered, ("%s is covered by %s"):format(label(target.object), tostring(covering)))
		if query.index ~= nil or index >= 4 then
			break
		end
	end
	return { tapped = false, reason = table.concat(covered, "; ") }
end

handlers.point = function(request)
	local x = numberField(request, "x", 0)
	local y = numberField(request, "y", 0)
	click(Vector2.new(x, y))
	return { tapped = true }
end

handlers.drag = function(request: Request): unknown
	local query = queryOf(request.query)
	local target = resolve(query)
	if target == nil then
		return { dragged = false, reason = "no visible element matches" }
	end
	local rect = target.rect
	local fromX = numberField(request, "fromX", 0.5)
	local toX = numberField(request, "toX", 0.5)
	local fromY = numberField(request, "fromY", 0.5)
	local toY = numberField(request, "toY", 0.5)
	local start = Vector2.new(rect.x + rect.width * fromX, rect.y + rect.height * fromY)
	local finish = Vector2.new(rect.x + rect.width * toX, rect.y + rect.height * toY)
	local device = input()
	device:SendMousePosition(start)
	frames(1)
	device:SendMouseButton(start, Enum.UserInputType.MouseButton1, true, 0)
	frames(2)
	local steps = math.floor(numberField(request, "steps", 12))
	for step = 1, steps do
		device:SendMousePosition(start:Lerp(finish, step / steps))
		frames(1)
	end
	frames(2)
	device:SendMouseButton(finish, Enum.UserInputType.MouseButton1, false, 0)
	frames(3)
	return { dragged = true, info = describe(target.object, rect) }
end

local function draggable(object: GuiObject): boolean
	return object:IsA("GuiButton") or object.Active or object:FindFirstChildWhichIsA("UIDragDetector") ~= nil
end

local function sliderParts(near: string): (GuiObject?, GuiObject?, number)
	local anchorList = anchors(near)
	local bestTrack: GuiObject? = nil
	local bestScore = math.huge
	local bestWidth = 0
	for _, anchor in anchorList do
		each(function(object)
			if not draggable(object) then
				return
			end
			local rect = shownRect(object, false)
			if rect == nil or rect.width < rect.height * 2 or rect.width < 40 then
				return
			end
			local distance = treeDistance(object, anchor.object)
			if distance > 6 then
				return
			end
			if distance < bestScore or (distance == bestScore and rect.width > bestWidth) then
				bestScore = distance
				bestWidth = rect.width
				bestTrack = object
			end
		end)
	end
	if bestTrack == nil then
		for _, anchor in anchorList do
			each(function(object)
				local rect = shownRect(object, false)
				if rect == nil or rect.width < rect.height * 2 or rect.width < 40 then
					return
				end
				if object:FindFirstChildWhichIsA("UIDragDetector", true) == nil then
					return
				end
				local distance = treeDistance(object, anchor.object)
				if distance <= 6 and (distance < bestScore or (distance == bestScore and rect.width > bestWidth)) then
					bestScore = distance
					bestWidth = rect.width
					bestTrack = object
				end
			end)
		end
	end
	if bestTrack == nil then
		return nil, nil, 0
	end
	local track = bestTrack :: GuiObject
	local thumb: GuiObject? = nil
	local thumbArea = math.huge
	for _, descendant in track:GetDescendants() do
		if descendant:IsA("GuiObject") and draggable(descendant) then
			local rect = shownRect(descendant, false)
			if rect ~= nil and rect.width * rect.height < thumbArea then
				thumbArea = rect.width * rect.height
				thumb = descendant
			end
		end
	end
	return track, thumb, bestScore
end

handlers.slide = function(request: Request): unknown
	local near = stringField(request, "near")
	local fraction = math.clamp(numberField(request, "to", 0.5), 0, 1)
	local track, thumb = sliderParts(near)
	if track == nil then
		return { slid = false, reason = "no slider control is near " .. near }
	end
	local trackRect = shownRect(track, false) :: Rect
	local target = Vector2.new(trackRect.x + trackRect.width * fraction, trackRect.y + trackRect.height / 2)
	local start = target
	if thumb ~= nil then
		local thumbRect = shownRect(thumb, false)
		if thumbRect ~= nil then
			start = center(thumbRect)
		end
	end
	local device = input()
	device:SendMousePosition(start)
	frames(1)
	device:SendMouseButton(start, Enum.UserInputType.MouseButton1, true, 0)
	frames(2)
	for step = 1, 12 do
		device:SendMousePosition(start:Lerp(target, step / 12))
		frames(1)
	end
	frames(2)
	device:SendMouseButton(target, Enum.UserInputType.MouseButton1, false, 0)
	frames(4)
	return {
		slid = true,
		track = describe(track, trackRect),
		thumb = if thumb ~= nil then thumb:GetFullName() else nil,
	}
end

handlers.wheel = function(request)
	local query = queryOf(request.query)
	local target = resolve(query)
	if target == nil then
		return { scrolled = false }
	end
	input():SendPointerAction(center(target.rect), { Wheel = numberField(request, "delta", -1) })
	frames(4)
	return { scrolled = true }
end

handlers.reveal = function(request)
	return reveal(queryOf(request.query), if request.mode == "touch" then "touch" else "wheel")
end

handlers.key = function(request: Request): unknown
	local ok, problem = pcall(function(): boolean
		key(keyCode(stringField(request, "key")))
		return true
	end)
	if not ok then
		return { pressed = false, reason = tostring(problem) }
	end
	return { pressed = true, reason = "" }
end

handlers.type = function(request: Request): unknown
	local query = queryOf(request.query)
	local target = resolve(query)
	if target == nil then
		return { typed = false, reason = "no visible element matches" }
	end
	local object = target.object
	if not object:IsA("TextBox") then
		return { typed = false, reason = object:GetFullName() .. " is not a text field" }
	end
	local box = object :: TextBox
	if request.mode == "gamepad" then
		if GuiService.SelectedObject ~= box then
			return { typed = false, reason = "the text field is not selected" }
		end
		key(Enum.KeyCode.Return)
	else
		for _ = 1, 2 do
			local current = shownRect(box, false)
			if current == nil then
				return { typed = false, reason = "the text field is not on the screen" }
			end
			local point = reachable(box, current :: Rect)
			if point == nil then
				return { typed = false, reason = "the text field is covered" }
			end
			click(point :: Vector2)
			for _ = 1, 15 do
				if box:IsFocused() then
					break
				end
				frames(1)
			end
			if box:IsFocused() then
				break
			end
		end
	end
	for _ = 1, 15 do
		if box:IsFocused() then
			break
		end
		frames(1)
	end
	if not box:IsFocused() then
		return { typed = false, reason = "the text field did not take focus" }
	end
	local wanted = stringField(request, "text")
	local attempts = 0
	while request.replace ~= false and box.Text ~= "" and attempts < 3 do
		attempts += 1
		box.CursorPosition = #box.Text + 1
		for _ = 1, utf8.len(box.Text) or #box.Text do
			input():SendKey(true, Enum.KeyCode.Backspace, false)
			frames(1)
			input():SendKey(false, Enum.KeyCode.Backspace, false)
		end
		frames(2)
	end
	if request.replace ~= false and box.Text ~= "" then
		return { typed = false, reason = ("the text field still holds %q after it was cleared"):format(box.Text) }
	end
	if wanted ~= "" then
		input():SendTextInput(wanted)
	end
	local function loose(value: string): string
		return string.lower((string.gsub(value, "%s", "")))
	end
	for _ = 1, 10 do
		if string.find(loose(box.Text), loose(wanted), 1, true) ~= nil then
			break
		end
		frames(1)
	end
	local entered = box.Text
	if request.submit == true then
		key(Enum.KeyCode.Return)
	elseif box:IsFocused() then
		box:ReleaseFocus(false)
		frames(2)
	end
	if string.find(loose(entered), loose(wanted), 1, true) == nil then
		return { typed = false, reason = ("the text field shows %q instead of %q"):format(entered, wanted) }
	end
	return { typed = true, text = entered, info = describe(box, target.rect) }
end

handlers.selected = function()
	return { selected = selectedInfo() }
end

handlers.autoselect = function()
	if GuiService.SelectedObject == nil then
		GuiService:Select(playerGui())
		frames(2)
	end
	return { selected = selectedInfo() }
end

handlers.deselect = function()
	GuiService.SelectedObject = nil
	frames(2)
	return { selected = selectedInfo() }
end

handlers.navigate = function(request)
	key(DIRECTIONS[stringField(request, "direction")])
	return { selected = selectedInfo() }
end

handlers.activate = function()
	local before = selectedInfo()
	key(Enum.KeyCode.Return)
	return { activated = before }
end

handlers.path = function(request)
	return gamepadPath(queryOf(request.query), numberField(request, "limit", 80))
end

handlers.matches = function(request)
	local selected = GuiService.SelectedObject
	local target = targetOf(queryOf(request.query))
	return { matches = selected ~= nil and target ~= nil and same(selected, target), selected = selectedInfo() }
end

handlers.racingDrive = function()
	return racingDrive()
end

handlers.racingState = function()
	local player = Players.LocalPlayer
	assert(player)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return {
		racing = player:GetAttribute("Racing") == true,
		x = if root and root:IsA("BasePart") then root.Position.X else 0,
		z = if root and root:IsA("BasePart") then root.Position.Z else 0,
		invalidSelections = invalidSelections,
	}
end

handlers.dump = function(request)
	local inputList: { string } = {}
	local raw = request.input
	if type(raw) == "table" then
		for _, item in raw :: { unknown } do
			if type(item) == "string" then
				table.insert(inputList, item)
			end
		end
	end
	local rootList: { unknown } = {}
	for _, root in roots() do
		table.insert(rootList, root)
	end
	local dump = Collect.collect({
		roots = rootList,
		device = if type(request.device) == "string" then request.device :: string else nil,
		scale = 1,
		input = inputList,
		safeAreaRoot = safeArea(),
	})
	local viewport = frame()
	local offset = viewport.AbsolutePosition + Vector2.new(dump.screen.guiInset.left, dump.screen.guiInset.top)
	local shifted: { [unknown]: boolean } = {}
	local function translate(rect: Rect?)
		if rect ~= nil and not shifted[rect] then
			shifted[rect] = true
			rect.x -= offset.X
			rect.y -= offset.Y
		end
	end
	for _, root in dump.roots do
		if not root.world then
			translate(root.rect)
		end
	end
	for _, element in dump.elements do
		local root = dump.roots[element.root]
		if root ~= nil and not root.world then
			translate(element.rect)
			translate(element.clip)
			translate(element.scrollClip)
		end
	end
	translate(dump.screen.safeArea)
	dump.screen.width = viewport.AbsoluteSize.X
	dump.screen.height = viewport.AbsoluteSize.Y
	local safe = dump.screen.safeArea
	if safe ~= nil then
		dump.screen.guiInset = {
			left = safe.x,
			top = safe.y,
			right = dump.screen.width - safe.x - safe.width,
			bottom = dump.screen.height - safe.y - safe.height,
		}
	end
	local text = HttpService:JSONEncode(dump)
	return if request.inline == true and #text <= CHUNK then text else stash(text, request.inline == true)
end

local Stats = game:GetService("Stats")
local frameTimes: { number } = {}
local sampling: RBXScriptConnection? = nil
local perfMark = 0

local function sample()
	if sampling == nil then
		frameTimes = {}
		sampling = RunService.RenderStepped:Connect(function(delta: number)
			table.insert(frameTimes, delta)
		end)
	end
end

local function stopSampling()
	if sampling ~= nil then
		sampling:Disconnect()
		sampling = nil
	end
end

local function frameStats(from: number): { [string]: number }
	local window: { number } = {}
	for index = from + 1, #frameTimes do
		table.insert(window, frameTimes[index] * 1000)
	end
	table.sort(window)
	local count = #window
	if count == 0 then
		return { frames = 0 }
	end
	local sum = 0
	for _, value in window do
		sum += value
	end
	local function at(fraction: number): number
		return window[math.clamp(math.ceil(count * fraction), 1, count)]
	end
	return { frames = count, mean = sum / count, p50 = at(0.5), p95 = at(0.95), max = window[count] }
end

local function census(): { [string]: number }
	local gui, components, other = 0, 0, 0
	local layerCollectors = roots()
	for _, root in layerCollectors do
		for _, node in root:GetDescendants() do
			if node:IsA("GuiObject") then
				gui += 1
			elseif node:IsA("UIComponent") then
				components += 1
			else
				other += 1
			end
		end
	end
	return {
		roots = #layerCollectors,
		gui = gui,
		components = components,
		other = other,
		instances = #layerCollectors + gui + components + other,
	}
end

local function signature(): number
	local value = 0
	for _, root in roots() do
		for _, node in root:GetDescendants() do
			value += 1
			if node:IsA("GuiObject") then
				local at, size = node.AbsolutePosition, node.AbsoluteSize
				value += math.floor(at.X + at.Y * 3 + size.X * 7 + size.Y * 11 + 0.5) % 100003
			end
		end
	end
	return value
end

local function memory(): { [string]: number }
	local result: { [string]: number } = { luaHeapKb = gcinfo() }
	local counted, instances = pcall(function(): number
		return Stats.InstanceCount
	end)
	if counted then
		result.instances = instances
	end
	local tagged, guiMb = pcall(function(): number
		assert(Stats.MemoryTrackingEnabled, "memory tracking is disabled")
		return Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.Gui)
	end)
	if tagged then
		result.guiMb = guiMb
	end
	return result
end

local function mountSnapshot(identities: { [Instance]: number }, nextIdentity: { number }): Mount.Snapshot
	local snapshot: Mount.Snapshot = {}
	local function add(node: Instance)
		if identities[node] == nil then
			nextIdentity[1] += 1
			identities[node] = nextIdentity[1]
		end
		local entry: Mount.Node = { parent = node.Parent, path = node:GetFullName(), identity = identities[node] }
		if node:IsA("GuiBase2d") then
			entry.x, entry.y = node.AbsolutePosition.X, node.AbsolutePosition.Y
			entry.width, entry.height = node.AbsoluteSize.X, node.AbsoluteSize.Y
			if node:IsA("TextLabel") or node:IsA("TextButton") then
				entry.text = node.Text
			end
		end
		snapshot[node] = entry
	end
	for _, root in roots() do
		add(root)
		for _, node in root:GetDescendants() do
			add(node)
		end
	end
	return snapshot
end

type LiveContent = {
	path: string,
	identity: number,
	reason: string,
	frames: number,
	firstSeconds: number,
	lastSeconds: number,
	firstBefore: string,
	firstAfter: string,
	lastBefore: string,
	lastAfter: string,
}

local function settle(quiet: number, limit: number, compareLegacy: boolean): { [string]: unknown }
	local started = os.clock()
	local identities: { [Instance]: number } = {}
	local nextIdentity = { 0 }
	local run = Mount.start(mountSnapshot(identities, nextIdentity), started)
	local legacyPrevious = signature()
	local legacyChange = started
	local legacySeconds = nil :: number?
	local live: {
		[string]: {
			path: string,
			identity: number,
			reason: string,
			frames: number,
			firstSeconds: number,
			lastSeconds: number,
			firstBefore: string,
			firstAfter: string,
			lastBefore: string,
			lastAfter: string,
		},
	} =
		{}
	local frames = 0
	while os.clock() - started < limit do
		RunService.RenderStepped:Wait()
		frames += 1
		local now = os.clock()
		local measuring = run.seconds == nil
		local exclusions = Mount.step(run, mountSnapshot(identities, nextIdentity), now, quiet)
		if measuring then
			for _, exclusion in exclusions do
				local key = tostring(exclusion.identity) .. ":" .. exclusion.reason
				local entry: LiveContent = live[key]
					or {
						path = exclusion.path,
						identity = exclusion.identity,
						reason = exclusion.reason,
						frames = 0,
						firstSeconds = now - started,
						lastSeconds = now - started,
						firstBefore = exclusion.before,
						firstAfter = exclusion.after,
						lastBefore = exclusion.before,
						lastAfter = exclusion.after,
					}
				entry.frames += 1
				entry.lastSeconds = now - started
				entry.lastBefore, entry.lastAfter = exclusion.before, exclusion.after
				live[key] = entry
			end
		end
		if compareLegacy and legacySeconds == nil then
			local value = signature()
			if value ~= legacyPrevious then
				legacyChange = now
			end
			legacyPrevious = value
			if now - legacyChange >= quiet then
				legacySeconds = legacyChange - started
			end
		end
		if run.seconds ~= nil and (not compareLegacy or legacySeconds ~= nil) then
			break
		end
	end
	return {
		seconds = run.seconds or limit,
		timedOut = run.seconds == nil,
		frames = frames,
		quiet = quiet,
		limit = limit,
		liveContent = live,
		legacySeconds = if compareLegacy then legacySeconds or (legacyChange - started) else nil,
		legacyTimedOut = if compareLegacy then legacySeconds == nil else nil,
	}
end

handlers.perf = function(request: Request): unknown
	local action = stringField(request, "action")
	if action == "geometry" then
		local previous: { [Instance]: string } = {}
		local changed: { [string]: { changes: number, first: string, last: string } } = {}
		local untilTime = os.clock() + numberField(request, "seconds", 2)
		repeat
			for _, root in roots() do
				for _, node in root:GetDescendants() do
					if node:IsA("GuiObject") then
						local value = `{node.AbsolutePosition}:{node.AbsoluteSize}:{node.Visible}`
						local before = previous[node]
						if before and before ~= value then
							local path = node:GetFullName()
							local record: { changes: number, first: string, last: string } = changed[path]
								or { changes = 0, first = before, last = value }
							record.changes += 1
							record.last = value
							changed[path] = record
						end
						previous[node] = value
					end
				end
			end
			RunService.RenderStepped:Wait()
		until os.clock() >= untilTime
		return changed
	elseif action == "settle" then
		local result =
			settle(numberField(request, "quiet", 1), numberField(request, "limit", 20), request.compareLegacy == true)
		result.census = census()
		return result
	elseif action == "idle" then
		sample()
		local mark = #frameTimes
		task.wait(numberField(request, "seconds", 2))
		stopSampling()
		return { frames = frameStats(mark), census = census(), memory = memory() }
	elseif action == "begin" then
		sample()
		perfMark = #frameTimes
		return { census = census() }
	elseif action == "end" then
		stopSampling()
		return { frames = frameStats(perfMark), census = census(), memory = memory() }
	elseif action == "memory" then
		return { census = census(), memory = memory() }
	end
	error("unknown perf action " .. action, 0)
end

handlers.chunk = function(request)
	local token = stringField(request, "token")
	local entry = state.stashes[token]
	assert(entry ~= nil, "unknown stash")
	local index = numberField(request, "index", 1)
	local piece = entry.pieces[index]
	if entry.automatic and index == #entry.pieces then
		state.stashes[token] = nil
	end
	return piece
end

handlers.release = function(request)
	state.stashes[stringField(request, "token")] = nil
	return true
end

handlers.preview = function(request: Request): unknown
	local query = queryOf(request.query)
	local wide = table.clone(query)
	wide.clipped = true
	local deadline = os.clock() + 4
	while resolve(wide) == nil and os.clock() < deadline do
		RunService.RenderStepped:Wait()
	end
	local tapped: { [string]: unknown } = { tapped = false, reason = "no visible control matches" }
	if request.mode == "gamepad" then
		for _ = 1, 4 do
			if GuiService.SelectedObject == nil then
				GuiService:Select(playerGui())
				frames(2)
			end
			local selected, target = GuiService.SelectedObject, targetOf(query)
			if selected == nil or selectedInfo() == nil then
				tapped.reason = "nothing on the screen can be selected with a gamepad"
				break
			end
			if target == nil or not same(selected, target) then
				local route = gamepadPath(query, 80)
				if route.found ~= true or type(route.path) ~= "table" then
					tapped.reason = route.reason
					break
				end
				for _, direction in route.path :: { string } do
					key(DIRECTIONS[direction])
				end
			end
			local now, destination = GuiService.SelectedObject, targetOf(query)
			if now ~= nil and destination ~= nil and same(now, destination) then
				tapped = { tapped = true, activated = true, info = selectedInfo() }
				key(Enum.KeyCode.Return)
				break
			end
			tapped.reason = "gamepad navigation did not settle on the target"
		end
	else
		reveal(query, if request.mode == "touch" then "touch" else "wheel")
		tapped = handlers.tap(request) :: { [string]: unknown }
	end
	local wait = request.wait
	local settled = true
	if type(wait) == "number" then
		task.wait(wait)
	else
		settled = settle(0.1, 20, false).timedOut == false
	end
	request.inline = true
	return { tap = tapped, settled = settled, dump = handlers.dump(request) }
end

local function call(encoded: string): string
	local ok, result = pcall(function(): unknown
		local decoded = HttpService:JSONDecode(encoded)
		assert(type(decoded) == "table", "a request must be an object")
		local request = decoded :: Request
		local handler = handlers[request.command]
		assert(handler ~= nil, "unknown command " .. tostring(request.command))
		return handler(request)
	end)
	if not ok then
		return HttpService:JSONEncode({ ok = false, error = tostring(result) })
	end
	if type(result) == "string" then
		return HttpService:JSONEncode({ ok = true, raw = result })
	end
	return HttpService:JSONEncode({ ok = true, value = result })
end

return { call = call }
