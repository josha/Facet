--!strict
local GuiService = game:GetService("GuiService")
local storage = game:GetService("ReplicatedStorage")

local focus = {}

type Builder = {
	describe: (node: GuiObject, path: string) -> { [string]: any },
	stops: { [string]: GuiObject },
	containers: { [string]: GuiObject },
	extra: { [Instance]: string },
	taken: { [string]: boolean },
}
local builders: { [any]: Builder } = setmetatable({}, { __mode = "k" }) :: any

local function live(): any
	return (require :: any)(storage:WaitForChild("FacetLive"))
end

local function pathOf(node: Instance, root: Instance): string
	local names = {}
	local at: Instance? = node
	while at and at ~= root do
		table.insert(names, 1, at.Name)
		at = at.Parent
	end
	return table.concat(names, "/")
end

local function shown(node: GuiObject): boolean
	local at: Instance? = node
	while at and not at:IsA("LayerCollector") do
		if at:IsA("GuiObject") and (not at.Visible or not at.Interactable) then
			return false
		end
		at = at.Parent
	end
	return at ~= nil and (at :: LayerCollector).Enabled
end

function focus.stops(root: Instance): { GuiObject }
	local out = {}
	for _, node in root:GetDescendants() do
		if node:IsA("GuiObject") and node.Selectable and shown(node) and not node:IsA("ScrollingFrame") then
			local size = node.AbsoluteSize
			if size.X > 0 and size.Y > 0 then
				table.insert(out, node)
			end
		end
	end
	return out
end

function focus.lint(root: Instance): { string }
	local bad = {}
	for _, node in root:GetDescendants() do
		if
			node:HasTag("facet-adjustable")
			and node:IsA("GuiObject")
			and node.Interactable
			and node:GetAttribute("disabled") ~= true
		then
			if not node.Selectable then
				table.insert(bad, `{node:GetFullName()} is not a stop`)
			end
			for _, inner in node:GetDescendants() do
				if inner:IsA("GuiObject") and inner.Selectable then
					table.insert(bad, `{inner:GetFullName()} is a stop inside {node.Name}`)
				end
			end
		end
	end
	return bad
end

function focus.paths(root: Instance, stops: { GuiObject }): { [Instance]: string }
	local paths: { [Instance]: string } = {}
	local seen: { [string]: number } = {}
	for _, node in stops do
		local path = pathOf(node, root)
		seen[path] = (seen[path] or 0) + 1
		paths[node] = if seen[path] > 1 then `{path}#{seen[path]}` else path
	end
	return paths
end

local function named(paths: { [Instance]: string }, node: Instance, root: Instance): string
	return paths[node] or pathOf(node, root)
end

local function scrollers(root: Instance): { ScrollingFrame }
	local out = {}
	for _, node in root:GetDescendants() do
		if node:IsA("ScrollingFrame") then
			table.insert(out, node)
		end
	end
	return out
end

function focus.rest(root: Instance)
	for _, scroller in scrollers(root) do
		scroller.CanvasPosition = Vector2.zero
	end
	for _ = 1, 10 do
		task.wait()
	end
end

local function settle(root: Instance): { [string]: { number } }
	local list = scrollers(root)
	local last: { Vector2 } = {}
	for _ = 1, 40 do
		task.wait()
		local still = true
		for index, scroller in list do
			if last[index] ~= scroller.CanvasPosition then
				still = false
			end
			last[index] = scroller.CanvasPosition
		end
		if still then
			break
		end
	end
	local offsets = {}
	for _, scroller in list do
		local at = scroller.CanvasPosition
		if at.X ~= 0 or at.Y ~= 0 then
			offsets[pathOf(scroller, root)] = { at.X, at.Y }
		end
	end
	return offsets
end

function focus.atlas(
	root: Instance,
	page: string,
	stops: { GuiObject },
	paths: { [Instance]: string }
): { [string]: any }
	local collector = root:FindFirstAncestorWhichIsA("LayerCollector") or root
	local view = (collector :: any).AbsoluteSize :: Vector2
	local entries, containers = {}, {}
	local containerNodes: { [string]: GuiObject } = {}
	local stopNodes: { [string]: GuiObject } = {}
	local taken: { [string]: boolean } = {}
	local chainOf: (Instance) -> { any }
	local function register(at: GuiObject): string
		local path = pathOf(at, root)
		if containers[path] == nil then
			containerNodes[path] = at
			local behavior = nil
			if at.SelectionGroup then
				behavior = {}
				for _, direction in { "Up", "Down", "Left", "Right" } :: { "Down" | "Left" | "Right" | "Up" } do
					behavior[direction] = ((at :: any)["SelectionBehavior" .. direction] :: EnumItem).Name
				end
			end
			local entry = at:GetAttribute("FacetEntry")
			containers[path] = {
				rect = { at.AbsolutePosition.X, at.AbsolutePosition.Y, at.AbsoluteSize.X, at.AbsoluteSize.Y },
				behavior = behavior,
				scroll = at:IsA("ScrollingFrame"),
				selectable = at:IsA("ScrollingFrame") and at.Selectable and shown(at),
				entry = if type(entry) == "string" then entry else nil,
				owner = at:GetAttribute("FacetSelectionOwner") == true,
				chain = {},
			}
			containers[path].chain = chainOf(at)
		end
		return path
	end
	function chainOf(node: Instance): { any }
		local chain = {}
		local at: Instance? = node.Parent
		while at and not at:IsA("LayerCollector") do
			if at:IsA("GuiObject") and ((at :: GuiObject).SelectionGroup or at:IsA("ScrollingFrame")) then
				table.insert(chain, register(at :: GuiObject))
			end
			at = at.Parent
		end
		return chain
	end
	local function describe(node: GuiObject, path: string): { [string]: any }
		local links = {}
		for _, direction in { "Up", "Down", "Left", "Right" } :: { "Down" | "Left" | "Right" | "Up" } do
			local link = (node :: any)["NextSelection" .. direction]
			if link then
				links[direction] = named(paths, link, root)
			end
		end
		return {
			path = path,
			rect = { node.AbsolutePosition.X, node.AbsolutePosition.Y, node.AbsoluteSize.X, node.AbsoluteSize.Y },
			adjustable = if node:HasTag("facet-adjustable") then node:GetAttribute("axis") else nil,
			links = links,
			chain = chainOf(node),
		}
	end
	for _, node in stops do
		table.insert(entries, describe(node, paths[node]))
		stopNodes[paths[node]] = node
		taken[paths[node]] = true
	end
	for _, scroller in scrollers(root) do
		if scroller.Selectable and shown(scroller) and scroller.AbsoluteSize.X > 0 and scroller.AbsoluteSize.Y > 0 then
			register(scroller)
		end
	end
	local atlas = {
		page = page,
		viewport = { view.X, view.Y },
		stops = entries,
		containers = containers,
		moves = {},
		offsets = {},
		scenes = {},
	}
	builders[atlas] = { describe = describe, stops = stopNodes, containers = containerNodes, extra = {}, taken = taken }
	return atlas
end

local function differs(node: GuiObject, rect: { number }, x: number, y: number): boolean
	local at, size = node.AbsolutePosition, node.AbsoluteSize
	return math.abs(at.X - x) > 0.5
		or math.abs(at.Y - y) > 0.5
		or math.abs(size.X - rect[3]) > 0.5
		or math.abs(size.Y - rect[4]) > 0.5
end

local function rested(atlas: any, entry: any, view: { [string]: { number } }): (number, number)
	local x, y = entry.rect[1], entry.rect[2]
	for _, path in entry.chain do
		local at = atlas.containers[path].scroll and view[path]
		if at then
			x -= at[1]
			y -= at[2]
		end
	end
	return x, y
end

function focus.scene(
	root: Instance,
	atlas: any,
	paths: { [Instance]: string },
	view: { [string]: { number } }
): { [string]: any }?
	local builder = builders[atlas]
	if builder == nil then
		return nil
	end
	local rects, gone, added = {}, {}, {}
	local present: { [GuiObject]: boolean } = {}
	for _, node in focus.stops(root) do
		present[node] = true
		if paths[node] == nil then
			local path = builder.extra[node]
			if path == nil then
				path = pathOf(node, root)
				local index = 1
				while builder.taken[path] do
					index += 1
					path = `{pathOf(node, root)}+{index}`
				end
				builder.taken[path] = true
				builder.extra[node] = path
			end
			table.insert(added, builder.describe(node, path))
		end
	end
	for _, entry in atlas.stops do
		local node = builder.stops[entry.path]
		if not present[node] then
			table.insert(gone, entry.path)
		else
			local x, y = rested(atlas, entry, view)
			if differs(node, entry.rect, x, y) then
				rects[entry.path] =
					{ node.AbsolutePosition.X, node.AbsolutePosition.Y, node.AbsoluteSize.X, node.AbsoluteSize.Y }
			end
		end
	end
	for path, entry in atlas.containers do
		local node = builder.containers[path]
		if node and node:IsDescendantOf(root) then
			local x, y = rested(atlas, entry, view)
			if differs(node, entry.rect, x, y) then
				rects[path] =
					{ node.AbsolutePosition.X, node.AbsolutePosition.Y, node.AbsoluteSize.X, node.AbsoluteSize.Y }
			end
		end
	end
	if next(rects) == nil and #gone == 0 and #added == 0 then
		return nil
	end
	return {
		rects = if next(rects) then rects else nil,
		gone = if #gone > 0 then gone else nil,
		added = if #added > 0 then added else nil,
	}
end

local function arrived(atlas: any, paths: { [Instance]: string }, now: Instance, root: Instance): string
	local builder = builders[atlas]
	return if builder and builder.extra[now] then builder.extra[now] else named(paths, now, root)
end

function focus.walk(
	root: Instance,
	stops: { GuiObject },
	paths: { [Instance]: string },
	keys: { string },
	atlas: any?
): ({ [string]: { [string]: string? } }, { [string]: { [string]: any } }, {
	[string]: { [string]: any },
})
	local moves, offsets = {}, {}
	local scenes: { [string]: { [string]: any } } = {}
	for _, node in stops do
		if not node:IsDescendantOf(root) then
			continue
		end
		local row, view = {}, {}
		local seen: { [string]: any } = {}
		for _, key in keys do
			if not pcall(function()
				GuiService.SelectedObject = node
			end) then
				break
			end
			view[key] = settle(root)
			seen[key] = if atlas then focus.scene(root, atlas, paths, view[key]) else nil
			live().press({ key })
			local now = GuiService.SelectedObject
			row[key] = if now and now ~= node then arrived(atlas, paths, now, root) else nil
		end
		moves[paths[node]] = row
		offsets[paths[node]] = view
		if next(seen) then
			scenes[paths[node]] = seen
		end
	end
	GuiService.SelectedObject = nil
	return moves, offsets, scenes
end

function focus.walkUp(
	root: Instance,
	stops: { GuiObject },
	paths: { [Instance]: string },
	timeout: number,
	atlas: any?
): ({ [string]: string? }, { [string]: any }, { [string]: any })
	local arrivals = 0
	local connection = game:GetService("UserInputService").InputBegan:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.DPadUp then
			arrivals += 1
		end
	end)
	local moves, offsets, scenes = {}, {}, {}
	for _, node in stops do
		if not node:IsDescendantOf(root) then
			continue
		end
		local before, view
		for _ = 1, 5 do
			if not pcall(function()
				GuiService.SelectedObject = node
			end) then
				break
			end
			view = settle(root)
			before = arrivals
			if GuiService.SelectedObject == node then
				break
			end
		end
		if before == nil then
			continue
		end
		local scene = if atlas then focus.scene(root, atlas, paths, view) else nil
		local started = os.clock()
		while arrivals == before and os.clock() - started < timeout do
			task.wait()
		end
		for _ = 1, 8 do
			task.wait()
		end
		local now = GuiService.SelectedObject
		moves[paths[node]] = if arrivals ~= before + 1
			then `unsettled:{arrivals - before}`
			elseif now and now ~= node then arrived(atlas, paths, now, root)
			else nil
		offsets[paths[node]] = view
		scenes[paths[node]] = scene
	end
	connection:Disconnect()
	GuiService.SelectedObject = nil
	return moves, offsets, scenes
end

function focus.opened(
	root: Instance,
	trigger: GuiObject,
	keys: { open: string, close: string, moves: { string }, up: number?, closeFrom: string? }
): { [string]: any }
	local before = {}
	for _, node in focus.stops(root) do
		before[node] = true
	end
	GuiService.SelectedObject = trigger
	settle(root)
	live().press({ keys.open }, 2)
	local started = os.clock()
	while GuiService.SelectedObject == trigger and os.clock() - started < 2 do
		task.wait()
	end
	local entered = os.clock() - started
	local inside, stable = {}, 0
	while stable < 3 and os.clock() - started < 4 do
		task.wait(0.15)
		local now = {}
		for _, node in focus.stops(root) do
			if not before[node] then
				table.insert(now, node)
			end
		end
		stable = if #now == #inside then stable + 1 else 0
		inside = now
	end
	settle(root)
	local landed = GuiService.SelectedObject
	if landed and not before[landed] and not table.find(inside, landed) then
		table.insert(inside, landed)
	end
	local paths = focus.paths(root, inside)
	local members = {}
	for _, node in inside do
		members[paths[node]] = true
	end
	local report: { [string]: any } = {
		trigger = pathOf(trigger, root),
		landed = if landed then named(paths, landed, root) else nil,
		landedInside = landed ~= nil and paths[landed] ~= nil,
		items = {},
		escapes = {},
		enteredAfter = entered,
	}
	for _, node in inside do
		table.insert(report.items, paths[node])
	end
	local behind = {}
	for node in before do
		behind[pathOf(node, root)] = true
	end
	local walked = table.clone(inside)
	if not report.landedInside then
		table.insert(walked, trigger)
		paths[trigger] = report.trigger
	end
	local moves = focus.walk(root, walked, paths, keys.moves)
	if keys.up then
		local up = live().signal("focus-upstream", function()
			return focus.walkUp(root, walked, paths, keys.up)
		end)
		for path, target in up do
			moves[path] = moves[path] or {}
			moves[path].DPadUp = target
		end
	end
	for from, row in moves do
		for key, target in row do
			if target and behind[target] and from ~= report.trigger then
				table.insert(report.escapes, `{from} {key} -> {target}`)
			end
		end
	end
	report.moves = moves
	local start = if report.landedInside then report.landed else report.trigger
	local reached, queue, head = { [start] = true }, { start }, 1
	while queue[head] do
		local destinations: { [string]: string? } = moves[queue[head]] or {}
		for _, target in destinations do
			if target and members[target] and not reached[target] then
				reached[target] = true
				table.insert(queue, target)
			end
		end
		head += 1
	end
	report.unreached = {}
	for _, path in report.items do
		if not reached[path] then
			table.insert(report.unreached, path)
		end
	end
	local closeFrom = if keys.closeFrom == "trigger" or not report.landedInside then trigger else landed
	if closeFrom and closeFrom.Parent then
		GuiService.SelectedObject = closeFrom
		settle(root)
	end
	local function open(): number
		local count = 0
		for _, node in inside do
			if node:IsDescendantOf(root) and node.Selectable and shown(node) then
				count += 1
			end
		end
		return count
	end
	report.closePresses = 0
	while open() > 0 and report.closePresses < 4 do
		live().press({ keys.close }, 20)
		settle(root)
		report.closePresses += 1
	end
	local after = GuiService.SelectedObject
	local still = open()
	report.closed = still == 0
	report.returned = after == trigger
	report.after = if after then pathOf(after, root) else nil
	return report
end

return focus
