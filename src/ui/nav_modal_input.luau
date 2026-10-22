--!strict
local Types = require("./types")

type Held = {
	interactable: boolean,
	selectable: boolean,
	writing: boolean,
	connections: { RBXScriptConnection },
	owners: { [Instance]: boolean },
}
local releases = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [Instance]: () -> () }
local states = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [GuiObject]: Held }
local holders = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [Instance]: { [GuiObject]: boolean } }

local function releaseAll(node: GuiObject)
	local state = states[node]
	if state == nil then
		return
	end
	for owner in state.owners do
		local owned = holders[owner]
		if owned then
			owned[node] = nil
		end
	end
	states[node] = nil
	for _, connection in state.connections do
		connection:Disconnect()
	end
	node.Interactable = state.interactable
	node.Selectable = state.selectable
	node:SetAttribute("FacetModalInteractable", nil)
end

local function acquire(ctx: Types.Context, root: GuiObject): (() -> (), () -> ())
	local held: { [GuiObject]: boolean } = {}
	holders[root] = held
	local layer: Instance? = nil
	local connections: { RBXScriptConnection } = {}
	local excluded: { [Instance]: boolean } = { [root] = true }
	local function inside(node: Instance): boolean
		for scope in excluded do
			if node == scope or node:IsDescendantOf(scope) then
				return true
			end
		end
		return false
	end
	local function containsScope(node: Instance): boolean
		for scope in excluded do
			if scope:IsDescendantOf(node) then
				return true
			end
		end
		return false
	end
	local function restore(node: GuiObject)
		if not held[node] then
			return
		end
		held[node] = nil
		local state = states[node]
		if state == nil then
			return
		end
		state.owners[root] = nil
		if next(state.owners) ~= nil then
			return
		end
		states[node] = nil
		for _, connection in state.connections do
			connection:Disconnect()
		end
		node.Interactable = state.interactable
		node.Selectable = state.selectable
		node:SetAttribute("FacetModalInteractable", nil)
	end
	local function hold(node: Instance)
		if not node:IsA("GuiObject") then
			return
		end
		if containsScope(node) then
			return
		end
		if not (node:IsA("GuiButton") or node:IsA("TextBox") or node.Selectable) or held[node] then
			return
		end
		local node: GuiObject = node :: GuiObject
		held[node] = true
		local existing = states[node]
		if existing then
			existing.owners[root] = true
			return
		end
		local state: Held = {
			interactable = node.Interactable,
			selectable = node.Selectable,
			writing = false,
			connections = {},
			owners = { [root] = true },
		}
		states[node] = state
		local function suppress()
			state.writing = true
			node:SetAttribute("FacetModalInteractable", state.interactable)
			node.Interactable = false
			node.Selectable = false
			state.writing = false
		end
		for _, property in { "Interactable", "Selectable" } do
			table.insert(
				state.connections,
				node:GetPropertyChangedSignal(property):Connect(function()
					if state.writing then
						return
					end
					if (if property == "Interactable" then node.Interactable else node.Selectable) == false then
						return
					end
					if property == "Interactable" then
						state.interactable = node.Interactable
					else
						state.selectable = node.Selectable
					end
					suppress()
				end)
			)
		end
		suppress()
	end
	local function visit(node: Instance)
		if excluded[node] then
			return
		end
		hold(node)
		for _, child in node:GetChildren() do
			visit(child)
		end
	end
	local function added(node: Instance)
		local scopes = ctx.modalScopes:peek()
		if inside(node) then
			if node:IsA("GuiObject") and states[node :: GuiObject] then
				releaseAll(node :: GuiObject)
			end
		elseif scopes[#scopes] == root then
			hold(node)
		end
	end
	local function refresh()
		local scopes = ctx.modalScopes:peek()
		local top: Instance? = scopes[#scopes]
		table.clear(excluded)
		if top then
			excluded[top] = true
			for _, portal in ctx.modalPortals:peek() do
				if ctx.withinModal(portal.node) then
					excluded[portal.node] = true
				end
			end
		end
		for node in held do
			if top == nil or inside(node) or containsScope(node) or node.Parent == nil then
				restore(node)
			end
		end
		if top ~= root or layer == nil then
			return
		end
		local layers = { layer }
		for candidate, host in ctx.overlayHosts do
			if host == layer then
				table.insert(layers, candidate)
			end
		end
		for _, surface in layers do
			if not inside(surface) then
				visit(surface)
			end
		end
	end
	local function locate()
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		layer = root:FindFirstAncestorWhichIsA("LayerCollector")
		local scopes = ctx.modalScopes:peek()
		if layer and scopes[#scopes] == root then
			table.insert(connections, layer.DescendantAdded:Connect(added))
			for _, portal in ctx.modalPortals:peek() do
				if portal.node ~= root then
					table.insert(connections, portal.anchor.AncestryChanged:Connect(refresh))
				end
			end
		end
		refresh()
	end
	ctx.Compose.watch(function(use)
		use(ctx.modalScopes)
		use(ctx.modalPortals)
		locate()
	end)
	local function release()
		for _, connection in connections do
			connection:Disconnect()
		end
		for node in held do
			restore(node)
		end
	end
	releases[root] = release
	return function()
		releases[root] = nil
		release()
	end, locate
end

return {
	acquire = acquire,
	release = function(root: Instance)
		local release = releases[root]
		if release then
			release()
		end
	end,
}
