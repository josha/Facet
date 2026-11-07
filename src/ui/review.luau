--!strict
local ambient = require("./ambient")
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
	for _, tag in tags do
		if type(tag) == "string" and string.sub(tag, 1, #ROLE_PREFIX) == ROLE_PREFIX then
			return string.sub(tag, #ROLE_PREFIX + 1)
		end
	end
	return nil
end

local function dataModel(): unknown
	return ambient()
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
				local tagged, marked = call(child, "HasTag", "facet-icon-glyph")
				local glyph = tagged and marked == true
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
						or (glyph and (text(read(child, "Text")) or "") ~= "" and number(
							styled(child, "TextTransparency"),
							0
						) < 0.9)
						or (
							(isA(child, "ImageLabel") or isA(child, "ImageButton"))
							and (text(read(child, "Image")) or "") ~= ""
							and number(styled(child, "ImageTransparency"), 0) < 0.9
						),
				}
				local hasUnfit, unfit = call(child, "GetAttribute", "FacetUnfit")
				if hasUnfit and unfit == true then
					local found, details = call(child, "FindFirstChild", "FacetUnfitDetails")
					local message = if found then text(read(details, "Value")) else nil
					element.unfit = message or "composition does not fit"
				end
				if not glyph and (isA(child, "TextLabel") or isA(child, "TextButton") or isA(child, "TextBox")) then
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
	local hasInput, input = call(game, "GetService", "UserInputService")
	local touch = hasInput and read(input, "TouchEnabled") == true
	return { width = width, height = height, elements = elements, touch = touch }
end

local NO_RECT: Rules.ReviewRect = { x = 0, y = 0, width = 0, height = 0 }

local function recentErrors(): { string }
	local ok, log = call(dataModel(), "GetService", "LogService")
	local found, history = call(if ok then log else nil, "GetLogHistory")
	local messages: { string } = {}
	if not found or type(history) ~= "table" then
		return messages
	end
	local seen: { [string]: boolean } = {}
	local entries = history :: { unknown }
	for index = #entries, math.max(1, #entries - 300), -1 do
		local entry = entries[index]
		local message = text(read(entry, "message"))
		if message ~= nil and string.find(tostring(read(entry, "messageType")), "Error", 1, true) ~= nil then
			local line = string.sub((string.gsub(message, "%s+", " ")), 1, 300)
			if not seen[line] then
				seen[line] = true
				table.insert(messages, line)
				if #messages == 3 then
					break
				end
			end
		end
	end
	return messages
end

local function runtimeFindings(snapshot: ReviewSnapshot): { ReviewFinding }
	local findings: { ReviewFinding } = {}
	local shown = false
	for _, element in snapshot.elements do
		if element.visible and element.text ~= nil and element.text.content ~= "" then
			shown = true
			break
		end
	end
	if not shown then
		local finding: ReviewFinding = {
			rule = "empty-screen",
			severity = "high",
			path = "PlayerGui",
			detail = "No text is visible. If a mounted screen should show content, a build error stopped it; "
				.. "read the runtime errors below and the console before adjusting layout.",
			rect = NO_RECT,
		}
		table.insert(findings, finding)
	end
	local game = dataModel()
	local ok, players = call(game, "GetService", "Players")
	local found, gui = call(if ok then read(players, "LocalPlayer") else nil, "FindFirstChildOfClass", "PlayerGui")
	local listed, descendants = call(if found then gui else nil, "GetDescendants")
	if listed and type(descendants) == "table" then
		for _, item in descendants do
			local failed, reason = call(item, "GetAttribute", "FacetError")
			if failed and type(reason) == "string" and reason ~= "" then
				local named, path = call(item, "GetFullName")
				local finding: ReviewFinding = {
					rule = "build-failed",
					severity = "high",
					path = if named and type(path) == "string" then path else "?",
					detail = "This control failed to build: " .. string.sub((string.gsub(reason, "%s+", " ")), 1, 300),
					rect = NO_RECT,
				}
				table.insert(findings, finding)
			end
			if isA(item, "ViewportFrame") and read(item, "Visible") ~= false then
				local tint = 0
				for _, key in { "Ambient", "LightColor" } do
					local value = read(item, key)
					local r, g, b =
						number(read(value, "R"), 1), number(read(value, "G"), 1), number(read(value, "B"), 1)
					local high, low = math.max(r, g, b), math.min(r, g, b)
					tint = math.max(tint, if high > 0 then (high - low) / high else 0)
				end
				if tint > 0.2 then
					local named, path = call(item, "GetFullName")
					local finding: ReviewFinding = {
						rule = "tinted-preview-light",
						severity = "medium",
						path = if named and type(path) == "string" then path else "ViewportFrame",
						detail = "A preview's Ambient or LightColor is tinted, so it shows its subject in shifted colors. "
							.. "Keep both near white where the player judges or chooses colors.",
						rect = NO_RECT,
					}
					table.insert(findings, finding)
				end
			end
		end
	end
	for _, message in recentErrors() do
		local finding: ReviewFinding = {
			rule = "runtime-error",
			severity = "high",
			path = "LogService",
			detail = "Recent client error: " .. message,
			rect = NO_RECT,
		}
		table.insert(findings, finding)
	end
	return findings
end

local function screen(options: ReviewOptions?): ReviewReport
	local snapshot = collect(options)
	local report = Rules.analyze(snapshot)
	local extra = runtimeFindings(snapshot)
	if #extra == 0 then
		return report
	end
	local lines: { string } = {}
	for index, finding in extra do
		table.insert(report.findings, index, finding)
		table.insert(lines, ("[%s] %s: %s"):format(finding.severity, finding.rule, finding.detail))
	end
	report.text = table.concat(lines, "\n") .. "\n" .. report.text
	return report
end

export type ScreenTarget = { set: (unknown, boolean) -> () } | { open: () -> (), close: (() -> ())? }
export type ScreensOptions = { root: Instance?, settle: number? }

local function mountedSheets(): { [string]: ScreenTarget }
	local found: { [string]: ScreenTarget } = {}
	local ok, players = call(dataModel(), "GetService", "Players")
	local has, gui = call(if ok then read(players, "LocalPlayer") else nil, "FindFirstChildOfClass", "PlayerGui")
	local listed, descendants = call(if has then gui else nil, "GetDescendants")
	if listed and type(descendants) == "table" then
		for _, item in descendants do
			local marked, sheet = call(item, "GetAttribute", "FacetSheet")
			if marked and sheet == true then
				local name = text(read(item, "Name")) or "Sheet"
				while found[name] ~= nil do
					name ..= "+"
				end
				local node = item :: Instance
				local target: { open: () -> (), close: (() -> ())? } = {
					open = function(): ()
						node:SetAttribute("FacetPresent", nil)
						node:SetAttribute("FacetPresent", true)
					end,
					close = function(): ()
						node:SetAttribute("FacetPresent", false)
					end,
				}
				found[name] = target
			end
		end
	end
	return found
end

local function screens(given: { [string]: ScreenTarget }?, options: ScreensOptions?): string
	local wait = assert(task and task.wait, "Facet review.screens runs in Play, where task.wait is available")
	local targets = given or mountedSheets()
	if next(targets) == nil then
		return "No screens: pass { Name = presentedCell }, or mount Sheets so review.screens can find them."
	end
	local settle = if options and options.settle then options.settle else 0.5
	local reviewOptions: ReviewOptions? = if options then { root = options.root } else nil
	local names: { string } = {}
	for name in targets do
		table.insert(names, name)
	end
	table.sort(names)
	local out: { string } = {}
	local reported: { [string]: boolean } = {}
	for _, name in names do
		local target = (targets[name] :: unknown) :: {
			set: ((unknown, boolean) -> ())?,
			open: (() -> ())?,
			close: (() -> ())?,
		}
		local function toggle(open: boolean)
			if target.set then
				target.set(target, open)
			elseif open then
				assert(target.open, "a screen target needs a writable cell or an open function")()
			elseif target.close then
				target.close()
			end
		end
		local opened, failure = pcall(toggle, true)
		wait(settle)
		local lines = { ("== %s"):format(name) }
		if not opened then
			table.insert(lines, "[high] open-failed: " .. tostring(failure))
		end
		local reviewed, report = pcall(screen, reviewOptions)
		if reviewed then
			local shown = 0
			for _, finding in report.findings do
				local lasting = finding.rule == "build-failed" or finding.rule == "runtime-error"
				local key = finding.rule .. finding.detail
				if lasting and reported[key] then
					continue
				end
				reported[key] = lasting or nil
				if finding.severity ~= "low" and shown < 5 then
					shown += 1
					local detail = string.sub((string.gsub(finding.detail, "%s+", " ")), 1, 200)
					table.insert(lines, ("[%s] %s: %s"):format(finding.severity, finding.rule, detail))
				end
			end
			if shown == 0 then
				table.insert(lines, "no high or medium findings")
			end
		else
			table.insert(lines, "[high] review-failed: " .. tostring(report))
		end
		pcall(toggle, false)
		wait(settle / 2)
		table.insert(out, table.concat(lines, "\n"))
	end
	return table.concat(out, "\n")
end

return table.freeze({
	analyze = Rules.analyze,
	collect = collect,
	screen = screen,
	screens = screens,
	fixes = Rules.fixes,
})
