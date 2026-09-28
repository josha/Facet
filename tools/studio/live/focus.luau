--!strict
local GuiService = game:GetService("GuiService")
local storage = game:GetService("ReplicatedStorage")

local focus = {}

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
	while at and at:IsA("GuiObject") do
		if not at.Visible or not at.Interactable then
			return false
		end
		at = at.Parent
	end
	return at ~= nil and at:IsA("LayerCollector") and at.Enabled
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
	local paths, seen = {}, {}
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
	local chainOf: (Instance) -> { any }
	local function register(at: GuiObject): string
		local path = pathOf(at, root)
		if containers[path] == nil then
			local behavior = nil
			if at.SelectionGroup then
				behavior = {}
				for _, direction in { "Up", "Down", "Left", "Right" } do
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
		while at and at:IsA("GuiObject") do
			if (at :: GuiObject).SelectionGroup or at:IsA("ScrollingFrame") then
				table.insert(chain, register(at :: GuiObject))
			end
			at = at.Parent
		end
		return chain
	end
	for _, node in stops do
		local links = {}
		for _, direction in { "Up", "Down", "Left", "Right" } do
			local link = (node :: any)["NextSelection" .. direction]
			if link then
				links[direction] = named(paths, link, root)
			end
		end
		table.insert(entries, {
			path = paths[node],
			rect = { node.AbsolutePosition.X, node.AbsolutePosition.Y, node.AbsoluteSize.X, node.AbsoluteSize.Y },
			adjustable = if node:HasTag("facet-adjustable")
				then (if node:GetAttribute("axis") == "vertical" then "vertical" else "horizontal")
				else nil,
			links = links,
			chain = chainOf(node),
		})
	end
	for _, scroller in scrollers(root) do
		if scroller.Selectable and shown(scroller) and scroller.AbsoluteSize.X > 0 and scroller.AbsoluteSize.Y > 0 then
			register(scroller)
		end
	end
	return {
		page = page,
		viewport = { view.X, view.Y },
		stops = entries,
		containers = containers,
		moves = {},
		offsets = {},
	}
end

function focus.walk(
	root: Instance,
	stops: { GuiObject },
	paths: { [Instance]: string },
	keys: { string }
): ({ [string]: { [string]: string? } }, { [string]: { [string]: any } })
	local moves, offsets = {}, {}
	for _, node in stops do
		if not node:IsDescendantOf(root) then
			continue
		end
		local row, view = {}, {}
		for _, key in keys do
			if not pcall(function()
				GuiService.SelectedObject = node
			end) then
				break
			end
			view[key] = settle(root)
			live().press({ key })
			local now = GuiService.SelectedObject
			row[key] = if now and now ~= node then named(paths, now, root) else nil
		end
		moves[paths[node]] = row
		offsets[paths[node]] = view
	end
	GuiService.SelectedObject = nil
	return moves, offsets
end

function focus.walkUp(
	root: Instance,
	stops: { GuiObject },
	paths: { [Instance]: string },
	timeout: number
): ({ [string]: string? }, { [string]: any })
	local arrivals = 0
	local connection = game:GetService("UserInputService").InputBegan:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.DPadUp then
			arrivals += 1
		end
	end)
	local moves, offsets = {}, {}
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
			elseif now and now ~= node then named(paths, now, root)
			else nil
		offsets[paths[node]] = view
	end
	connection:Disconnect()
	GuiService.SelectedObject = nil
	return moves, offsets
end

function focus.opened(
	root: Instance,
	trigger: GuiObject,
	keys: { open: string, close: string, moves: { string } }
): { [string]: any }
	local before = {}
	for _, node in focus.stops(root) do
		before[node] = true
	end
	GuiService.SelectedObject = trigger
	settle(root)
	live().press({ keys.open }, 20)
	settle(root)
	local landed = GuiService.SelectedObject
	local inside = {}
	for _, node in focus.stops(root) do
		if not before[node] then
			table.insert(inside, node)
		end
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
	}
	for _, node in inside do
		table.insert(report.items, paths[node])
	end
	local behind = {}
	for node in before do
		behind[pathOf(node, root)] = true
	end
	local moves = focus.walk(root, inside, paths, keys.moves)
	for from, row in moves do
		for key, target in row do
			if target and behind[target] then
				table.insert(report.escapes, `{from} {key} -> {target}`)
			end
		end
	end
	report.moves = moves
	local reached, queue, head = {}, {}, 1
	if report.landedInside then
		reached[report.landed], queue[1] = true, report.landed
	end
	while queue[head] do
		for _, target in moves[queue[head]] or {} do
			if members[target] and not reached[target] then
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
	if landed and landed.Parent then
		GuiService.SelectedObject = landed
		settle(root)
	end
	live().press({ keys.close }, 20)
	settle(root)
	local after = GuiService.SelectedObject
	local still = 0
	for _, node in inside do
		if node:IsDescendantOf(root) and node.Selectable and shown(node) then
			still += 1
		end
	end
	report.closed = still == 0
	report.returned = after == trigger
	report.after = if after then pathOf(after, root) else nil
	return report
end

return focus
