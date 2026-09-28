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
		if node:HasTag("facet-adjustable") and node:IsA("GuiObject") and node.Interactable then
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

function focus.atlas(root: Instance, page: string): { [string]: any }
	local collector = root:FindFirstAncestorWhichIsA("LayerCollector") or root
	local view = (collector :: any).AbsoluteSize :: Vector2
	local stops = {}
	for _, node in focus.stops(root) do
		local links = {}
		for _, direction in { "Up", "Down", "Left", "Right" } do
			local link = (node :: any)["NextSelection" .. direction]
			if link then
				links[direction] = pathOf(link, root)
			end
		end
		local group: Instance? = node.Parent
		while group and group:IsA("GuiObject") and not (group :: GuiObject).SelectionGroup do
			group = group.Parent
		end
		local behavior = {}
		local groupPath = nil
		if group and group:IsA("GuiObject") then
			groupPath = pathOf(group, root)
			for _, direction in { "Up", "Down", "Left", "Right" } do
				behavior[direction] = ((group :: any)["SelectionBehavior" .. direction] :: EnumItem).Name
			end
		end
		table.insert(stops, {
			path = pathOf(node, root),
			rect = { node.AbsolutePosition.X, node.AbsolutePosition.Y, node.AbsoluteSize.X, node.AbsoluteSize.Y },
			adjustable = if node:HasTag("facet-adjustable")
				then (if node:GetAttribute("axis") == "vertical" then "vertical" else "horizontal")
				else nil,
			links = links,
			group = groupPath,
			behavior = behavior,
		})
	end
	return { page = page, viewport = { view.X, view.Y }, stops = stops, moves = {} }
end

function focus.walk(root: Instance, stops: { GuiObject }, keys: { string }): { [string]: { [string]: string? } }
	local moves = {}
	for _, node in stops do
		local row = {}
		for _, key in keys do
			GuiService.SelectedObject = node
			task.wait()
			live().press({ key })
			local now = GuiService.SelectedObject
			row[key] = if now and now ~= node then pathOf(now, root) else nil
		end
		moves[pathOf(node, root)] = row
	end
	GuiService.SelectedObject = nil
	return moves
end

return focus
