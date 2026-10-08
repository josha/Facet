--!strict
local Shared = require("./types")
local Commands = require("./command_types")
local ComposeTypes = require("../vendor/compose/core")
local gestureOf = require("./gesture_service")
type Record = { node: GuiObject, active: (ComposeTypes.Use) -> boolean }
local registries = setmetatable({} :: { [Shared.Context]: Shared.Cell<{ Record }> }, { __mode = "k" })

return function(ctx: Shared.Context, UI: Commands.Controls)
	local C, runtime, input, gui = ctx.Compose, ctx.runtime, ctx.config.userInputService, ctx.config.guiService
	local registry = registries[ctx]
	if registry == nil then
		registry = C.cell({} :: { Record })
		registries[ctx] = registry
	end
	local scopes = registry :: Shared.Cell<{ Record }>
	UI.commandScope = function<K>(root: GuiObject, spec: Commands.CommandSpec<K>): Commands.CommandScope<K>
		local arbiter = gestureOf(ctx)
		local owner = assert(C.currentOwner(), "Facet commandScope requires a Compose owner")
		local current = C.cell(nil :: K?)
		local version, typing = C.cell(0), C.cell(input ~= nil and not not input:GetFocusedTextBox())
		local selected: Shared.Readable<GuiObject?> = if gui
			then ctx.observe.SelectedObject(gui)
			else C.cell(nil :: GuiObject?)
		local actions: { [string]: InputAction } = {}
		local function refresh()
			version:update(function(value)
				return value + 1
			end)
		end
		local function available(node: GuiObject, use: Shared.Use?): boolean
			if root.Parent == nil or not ctx.available(node, use) then
				return false
			end
			local at: Instance? = node
			while at do
				if at:IsA("GuiObject") then
					local visible = if use then use(ctx.observe.Visible(at)) else at.Visible
					local interactable = if use then use(ctx.observe.Interactable(at)) else at.Interactable
					if not visible or not interactable then
						return false
					end
				end
				if at == root then
					return true
				end
				at = at.Parent
			end
			return false
		end
		local function targetKey(use: Shared.Use): K?
			use(version)
			local node = use(selected)
			if node == nil or not available(node, use) then
				return nil
			end
			local targets = ctx.read(spec.targets, use)
			local at: Instance? = node
			while at do
				for _, target in targets do
					if target.node == at and available(target.node, use) then
						return target.key
					end
				end
				if at == root then
					break
				end
				at = at.Parent
			end
			return nil
		end
		runtime.connect(root, "AncestryChanged", refresh)
		C.watch(function(use: Shared.Use)
			current:set(targetKey(use))
		end)
		if input then
			runtime.connect(input, "TextBoxFocused", function()
				typing:set(true)
			end)
			runtime.connect(input, "TextBoxFocusReleased", function()
				typing:set(not not input:GetFocusedTextBox())
			end)
		end
		local record: Record = {
			node = root,
			active = function(use: Shared.Use): boolean
				return not owner.isDisposed()
					and use(current) ~= nil
					and not use(typing)
					and ctx.read(spec.enabled, use) ~= false
					and ctx.available(root, use)
			end,
		}
		scopes:update(function(values)
			local next = table.clone(values)
			table.insert(next, record)
			return next
		end)
		C.cleanup(function()
			scopes:update(function(values)
				local next: { Record } = {}
				for _, value in values do
					if value ~= record then
						table.insert(next, value)
					end
				end
				return next
			end)
			current:set(nil)
		end)
		local function wins(use: Shared.Use): boolean
			if not record.active(use) then
				return false
			end
			for _, candidate in use(scopes) do
				if candidate ~= record and candidate.node:IsDescendantOf(root) and candidate.active(use) then
					return false
				end
			end
			return true
		end
		local function selectable(node: Instance): GuiObject?
			if node:IsA("GuiObject") and not available(node) then
				return nil
			end
			if node:IsA("GuiObject") and node.Selectable then
				return node
			end
			for _, child in node:GetChildren() do
				local found = selectable(child)
				if found then
					return found
				end
			end
			return nil
		end
		local targetsOwner: ComposeTypes.Owner?
		C.watch(function(use: Shared.Use)
			local targets = ctx.read(spec.targets, use)
			if targetsOwner then
				targetsOwner.dispose()
			end
			local child = owner.createChild()
			targetsOwner = child
			C.withOwner(child, function()
				local keys: { [K]: boolean } = {}
				local nodes: { [GuiObject]: boolean } = {}
				for _, target in targets do
					assert(
						not keys[target.key] and not nodes[target.node],
						"Facet commandScope targets must have unique keys and nodes"
					)
					keys[target.key], nodes[target.node] = true, true
					runtime.connect(target.node, "AncestryChanged", refresh)
					runtime.connect(target.node, "SelectionGained", refresh)
					runtime.connect(target.node, "InputBegan", function(event: InputObject)
						local contact = arbiter.get(event)
						if
							contact
							and contact.owner ~= target.node
							and not contact.owner:IsDescendantOf(target.node)
						then
							return
						end
						if
							gui
							and ctx.effectiveInput()() ~= "Touch"
							and ctx.read(spec.enabled) ~= false
							and available(target.node)
							and (
								event.UserInputType == ctx.types.Enum.UserInputType.Touch
								or event.UserInputType == ctx.types.Enum.UserInputType.MouseButton1
							)
						then
							local node = selectable(target.node)
							if node then
								gui.SelectedObject = node
							end
						end
					end)
				end
			end)
			refresh()
		end)
		C.cleanup(function()
			if targetsOwner then
				targetsOwner.dispose()
			end
		end)
		local supportedKeys: { [string]: boolean } = {}
		for _, key in ctx.types.Enum.KeyCode:GetEnumItems() do
			supportedKeys[key.Name] = true
		end
		local ids, bound = {} :: { [string]: boolean }, {} :: { [string]: boolean }
		for _, command in spec.commands do
			assert(command.id ~= "" and not ids[command.id], "Facet commandScope command ids must be unique")
			assert(#command.keys > 0, "Facet commandScope commands require keys")
			ids[command.id] = true
			for _, key in command.keys do
				assert(supportedKeys[key], "Facet commandScope has an unknown KeyCode")
				assert(not bound[key], "Facet commandScope keys belong to one command")
				bound[key] = true
			end
			local enabled = function(use: Shared.Use): boolean
				return wins(use) and ctx.read(command.enabled, use) ~= false
			end
			actions[command.id] = ctx.action(root, command.id, command.keys, enabled, function()
				local key = current:peek()
				if key ~= nil and (not input or not input:GetFocusedTextBox()) then
					command.onInvoke(key)
				end
			end, { group = "Commands", priority = 1500, sink = true, capture = true })
		end

		return {
			current = current,
			actions = actions,
			focus = function(key: K): boolean
				if owner.isDisposed() or gui == nil or ctx.read(spec.enabled) == false then
					return false
				end
				for _, target in ctx.read(spec.targets) do
					if target.key == key then
						local node = selectable(target.node)
						if node then
							gui.SelectedObject = node
							return true
						end
					end
				end
				return false
			end,
			clear = function()
				if not owner.isDisposed() and gui and current:peek() ~= nil then
					gui.SelectedObject = nil
				end
			end,
		}
	end
end
