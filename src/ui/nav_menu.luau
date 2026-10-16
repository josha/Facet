--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local activation = require("./activation")
local ComposeTypes = require("../vendor/compose/core")
local ControlTypes = require("./control_types")
local InputProps = require("./input_props")
local NavigationProps = require("./navigation_props")
local MenuItems = require("./nav_menu_items")
local MenuPanel = require("./nav_menu_panel")
local registerPicker = require("./nav_picker")
local registerSplitButton = require("./nav_split_button")
local registerComboBox = require("./nav_combo_box")

return function(ctx: Types.Context, UI: ControlTypes.BuilderControls, surfaces: Nav.Surfaces): ()
	local Host, Compose, runtime, read = ctx.Host, ctx.Compose, ctx.runtime, ctx.read
	local E, D2, V2 = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2
	local itemModel = MenuItems(ctx)
	local checkWidth, menuItems, advice = itemModel.checkWidth, itemModel.menuItems, itemModel.advice
	local menuPanel = MenuPanel(ctx, UI, surfaces)
	local MENU_KEYS = {
		"items",
		"query",
		"label",
		"disclosure",
		"trigger",
		"triggers",
		"presentation",
		"backLabel",
		"onOpen",
		"onClose",
		"closeButton",
		"enabled",
		"isPresented",
		"edge",
		"align",
		"width",
		"maxHeight",
		"controls",
	}
	local function buildMenu<V>(spec: NavigationProps.MenuSpec<V>, wrap: boolean): GuiObject
		assert(
			spec.closeButton == nil or type(spec.closeButton) == "boolean",
			"Facet UI.Menu: closeButton must be a boolean"
		)
		assert(spec.items ~= nil, "Menu requires items")
		menuItems(read(spec.items))
		assert(
			spec.edge == nil or table.find({ "top", "bottom", "leading", "trailing" }, spec.edge),
			"Facet UI.Menu: edge must be top, bottom, leading or trailing"
		)
		assert(
			spec.align == nil or table.find({ "start", "center", "end" }, spec.align),
			"Facet UI.Menu: align must be start, center or end"
		)
		assert(
			spec.maxHeight == nil
				or (type(spec.maxHeight) == "number" and spec.maxHeight > 0 and spec.maxHeight < math.huge),
			"Facet UI.Menu: maxHeight must be a finite number of pixels above 0"
		)
		checkWidth(read(spec.width))
		if spec.controls then
			spec.controls.diagnostics = function(): { string }
				return advice(read(spec.items), "items", 0, {})
			end
		end
		if spec.label ~= nil and spec.trigger ~= nil then
			error("Facet UI.Menu: give label or trigger, not both", 0)
		end
		local opened: ComposeTypes.Cell<boolean> = spec.isPresented or Compose.cell(false)
		local pointer: ComposeTypes.Cell<Vector2?> = Compose.cell(nil :: Vector2?)
		local announced = false
		local function announce(state: boolean)
			if state == announced then
				return
			end
			announced = state
			if state and spec.onOpen then
				spec.onOpen()
			elseif not state and spec.onClose then
				spec.onClose()
			end
		end
		local function close()
			if opened:peek() then
				opened:set(false)
			end
			announce(false)
		end
		local function open()
			if read(spec.enabled) == false or opened:peek() then
				return
			end
			opened:set(true)
			announce(true)
		end
		Compose.watch(function(use: ComposeTypes.Use)
			local shown = use(opened)
			if not shown then
				pointer:set(nil)
			end
			announce(shown)
		end)
		Compose.cleanup(function()
			announce(false)
		end)
		local allowed: { Nav.MenuTrigger } = spec.triggers
			or { "activate", "secondary", "longPress", "keyboard", "gamepad" }
		local function allows(trigger: Nav.MenuTrigger): boolean
			return table.find(allowed, trigger) ~= nil
		end
		local authored = if type(spec.trigger) == "function" then spec.trigger() else spec.trigger
		local root: GuiObject
		local trigger: GuiObject
		local automatic = spec.AutomaticSize or (if spec.Size ~= nil then E.AutomaticSize.None else E.AutomaticSize.XY)
		if authored ~= nil and wrap then
			trigger = authored
			root = Host.Frame(ctx.props(spec, MENU_KEYS, {
				Name = "Menu",
				BackgroundTransparency = 1,
				Size = D2.fromOffset(0, 0),
				AutomaticSize = automatic,
				trigger,
			}))
			if allows("activate") then
				if activation.marked(trigger) then
					Compose.cleanup(activation.listen(trigger, open))
				else
					runtime.connect(trigger, "Activated", open)
				end
			end
		elseif authored == nil then
			local triggerProps: InputProps.ButtonProps = {
				Name = "Trigger",
				label = spec.label or "Menu",
				enabled = spec.enabled,
				onActivate = if allows("activate") then open else nil,
			}
			if spec.Size ~= nil then
				triggerProps.AutomaticSize = automatic
				triggerProps.Size = function(use: ComposeTypes.Use)
					local sizing = read(automatic, use)
					local width = sizing == E.AutomaticSize.X or sizing == E.AutomaticSize.XY
					local height = sizing == E.AutomaticSize.Y or sizing == E.AutomaticSize.XY
					return D2.new(
						if width then 0 else 1,
						0,
						if height then 0 else 1,
						if height then ctx.controlSize(nil, "height", use) else 0
					)
				end
				triggerProps.TextTruncate = E.TextTruncate.AtEnd
				triggerProps.TextWrapped = false
				triggerProps.ClipsDescendants = true
				local attributes: Types.Attributes = {
					FacetLabel = function(use: ComposeTypes.Use)
						return read(triggerProps.label, use)
					end,
				}
				triggerProps.Attributes = attributes
			end
			if spec.disclosure then
				triggerProps[#triggerProps + 1] = ctx.icon("chevron.up.chevron.down", {
					Name = "Disclosure",
					Size = D2.fromOffset(12, 12),
					AnchorPoint = V2.new(1, 0.5),
					Position = D2.new(1, 20, 0.5, 0),
					BackgroundTransparency = 1,
				}) :: Types.Child
			end
			local button = UI.Button(triggerProps)
			if spec.disclosure then
				button:AddTag("facet-disclosure")
			end
			trigger = button
			root = Host.Frame(ctx.props(spec, MENU_KEYS, {
				Name = "Menu",
				BackgroundTransparency = 1,
				Size = D2.fromOffset(0, 0),
				AutomaticSize = automatic,
				trigger,
			}))
		else
			trigger = authored
			root = authored
			local native = ctx.props(spec, MENU_KEYS, {})
			local properties: { [string]: unknown } = {}
			local children: { Types.Child } = {}
			for key, value in (native :: unknown) :: { [unknown]: unknown } do
				if type(key) == "number" then
					table.insert(children, value :: Types.Child)
				elseif type(key) == "string" then
					properties[key] = value
				end
			end
			if next(properties) ~= nil then
				runtime.decorate(trigger, properties)
			end
			if #children > 0 then
				surfaces.attach(trigger, children)
			end
			if allows("activate") then
				if activation.marked(trigger) then
					Compose.cleanup(activation.listen(trigger, open))
				else
					runtime.connect(trigger, "Activated", open)
				end
			end
		end
		local available = surfaces.available(root)
		local mounted = false
		Compose.watch(function(use: ComposeTypes.Use)
			local active = use(available)
			if active then
				mounted = true
			end
			if mounted and (not active or read(spec.enabled, use) == false) then
				close()
			end
		end)
		if allows("secondary") then
			local function secondary(input: InputObject)
				if read(spec.enabled) == false then
					return
				end
				if input.UserInputType == E.UserInputType.MouseButton2 and not activation.consumed(input) then
					local point = V2.new(input.Position.X, input.Position.Y)
					local layer = trigger:FindFirstAncestorWhichIsA("ScreenGui")
					local gui = surfaces.service("GuiService")
					if layer and (layer :: ScreenGui).IgnoreGuiInset and gui then
						point += gui:GetGuiInset()
					end
					pointer:set(point)
					open()
					if opened:peek() then
						activation.consume(input)
					end
				end
			end
			local connections: { [Instance]: RBXScriptConnection } = {}
			local function attach(node: Instance)
				if node:IsA("GuiObject") and not connections[node] then
					connections[node] = node.InputBegan:Connect(secondary)
				end
			end
			attach(trigger)
			for _, node in trigger:GetDescendants() do
				attach(node)
			end
			runtime.connect(trigger, "DescendantAdded", attach)
			runtime.connect(trigger, "DescendantRemoving", function(node: Instance)
				if connections[node] then
					connections[node]:Disconnect()
					connections[node] = nil
				end
			end)
			Compose.cleanup(function()
				for _, connection in connections do
					connection:Disconnect()
				end
			end)
		end
		if allows("longPress") then
			runtime.connect(trigger, "TouchLongPress", function(_: { Vector2 }, state: Enum.UserInputState)
				if state == E.UserInputState.Begin then
					open()
				end
			end)
		end
		local gui = surfaces.service("GuiService")
		local selected = if gui then ctx.observe.SelectedObject(gui) else Compose.cell(nil :: GuiObject?)
		local bindings: { Types.ActionBinding } = {}
		if allows("keyboard") then
			table.insert(bindings, E.KeyCode.Menu)
			bindings[#bindings + 1] = { KeyCode = E.KeyCode.F10, PrimaryModifier = E.KeyCode.LeftShift }
			bindings[#bindings + 1] = { KeyCode = E.KeyCode.F10, PrimaryModifier = E.KeyCode.RightShift }
		end
		if allows("gamepad") then
			table.insert(bindings, E.KeyCode.ButtonY)
		end
		if #bindings > 0 then
			ctx.action(root, "Menu", bindings, function(use: ComposeTypes.Use)
				return surfaces.within(use(selected), root)
			end, open, { priority = 1200 })
		end
		local motion = ctx.motionTiming("popover")
		surfaces.attach(root, {
			surfaces.overlay(root, opened, function(phase: Nav.PresencePhase?)
				local presentedPointer = Compose.cell(pointer:peek())
				Compose.watch(function(use: ComposeTypes.Use)
					if use(opened) then
						presentedPointer:set(use(pointer))
					end
				end)
				return menuPanel(
					spec,
					close,
					trigger,
					nil,
					phase,
					motion,
					presentedPointer,
					if spec.closeButton == nil then "automatic" else spec.closeButton
				)
			end, { motion = motion }),
		})
		return root
	end
	UI.Menu = ctx.construct("Menu", function<V>(spec: NavigationProps.MenuSpec<V>): GuiObject
		return buildMenu(spec, false)
	end) :: ControlTypes.MenuConstructor
	registerPicker(ctx, UI, surfaces, buildMenu)
	registerSplitButton(ctx, UI, surfaces, buildMenu)
	registerComboBox(ctx, UI, surfaces)
end
