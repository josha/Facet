--!strict
local ControlTypes = require("./control_types")
local Types = require("./types")
local Nav = require("./navigation_types")
local Inputs = require("./input_types")
local ComposeTypes = require("../vendor/compose/core")
local NavigationProps = require("./navigation_props")
local MenuPanel = require("./nav_menu_panel")

return function(ctx: Types.Context, UI: ControlTypes.Controls, surfaces: Nav.Surfaces)
	local Host, Compose, runtime, read = ctx.Host, ctx.Compose, ctx.runtime, ctx.read
	local readOptions = read<<{ Nav.PickerOption<string> }>>
	local readText = read<<string>>
	local E, D2 = ctx.types.Enum, ctx.types.UDim2
	local menuPanel = MenuPanel(ctx, UI, surfaces)<<string>>
	local function writable(cell: { read set: unknown }, name: string)
		assert(type(cell) == "table" and type(cell.set) == "function", name .. " requires a writable Compose cell")
	end
	UI.ComboBox = ctx.construct("ComboBox", function(spec: NavigationProps.ComboBoxSpec): Frame
		writable(spec.value, "ComboBox.value")
		writable(spec.text, "ComboBox.text")
		assert(type(spec.value:peek()) == "string", "ComboBox.value must be a string")
		assert(type(read(spec.options)) == "table", "ComboBox requires options")
		assert(type(spec.acceptCustom) == "function", "ComboBox requires acceptCustom")
		local errorText = Compose.cell("")
		local alive = true
		Compose.cleanup(function()
			alive = false
		end)
		local opened, editing = Compose.cell(false), Compose.cell(false)
		local navigating = false
		local popup: Frame?
		local gui = surfaces.service("GuiService")
		local function close()
			opened:set(false)
		end
		local function label(value: string): string
			for _, option in readOptions(spec.options) do
				if (option.value or option.id) == value then
					return readText(option.label)
				end
			end
			return value
		end
		local function update(value: string)
			close()
			errorText:set("")
			spec.text:set(label(value))
			if value ~= spec.value:peek() then
				spec.value:set(value)
				if spec.onChange then
					spec.onChange(value)
				end
			end
		end
		local function commit(text: string, reason: Inputs.CommitReason)
			if
				navigating
				or read(spec.enabled) == false
				or (reason == "focusLost" and spec.commitOnFocusLost ~= true)
			then
				return
			end
			for _, option in readOptions(spec.options) do
				if read(option.label) == text then
					if read(option.enabled) == false then
						errorText:set("This option is unavailable.")
					else
						update(option.value or option.id)
					end
					return
				end
			end
			local ok, accepted, message = pcall(spec.acceptCustom, text)
			if not alive or read(spec.enabled) == false then
				return
			end
			if ok and accepted == true then
				update(text)
			else
				errorText:set(message or "This value is not accepted.")
			end
		end
		local function cancel()
			close()
			spec.text:set(label(spec.value:peek()))
			errorText:set("")
		end
		local created = UI.TextInput "Editor" {
			value = spec.text,
			placeholder = spec.placeholder,
			enabled = spec.enabled,
			Size = D2.new(1, -60, 1, 0),
			AutomaticSize = E.AutomaticSize.None,
			onCommit = function(value, reason)
				commit(value, reason)
				if reason == "submit" then
					close()
				end
			end,
			onCancel = cancel,
			onChange = function(value)
				spec.text:set(value)
				opened:set(true)
			end,
			Focused = function()
				editing:set(true)
			end,
			FocusLost = function()
				editing:set(false)
			end,
		}
		assert(created:IsA("TextBox"), "Facet ComboBox: the editor is a TextBox")
		local editor = created

		local function open()
			if read(spec.enabled) ~= false then
				opened:set(true)
			end
		end
		local triggerAttributes: Types.Attributes = { FacetLabel = "Suggestions" }
		local suggestions = Host.Frame "Suggestions" {
			BackgroundTransparency = 1,
			Position = D2.new(1, -56, 0, 0),
			Size = D2.new(0, 56, 1, 0),
			UI.Button "Trigger" {
				label = "",
				icon = "chevron.down",
				enabled = spec.enabled,
				Size = D2.fromScale(1, 1),
				AutomaticSize = E.AutomaticSize.None,
				Attributes = triggerAttributes,
				onActivate = function()
					if opened:peek() then
						close()
					else
						open()
					end
				end,
			},
		}
		local row = Host.Frame "Row" {
			BackgroundTransparency = 1,
			Size = D2.new(1, 0, 0, 44),
			editor :: Instance,
			suggestions,
		}
		local root = ctx.column(
			{
				row,
				Compose.show(function(use: ComposeTypes.Use)
					return use(errorText) ~= ""
				end, function()
					return ctx.text({ Name = "Validation", Text = errorText, TextWrapped = true, LayoutOrder = 2 })
				end),
			},
			ctx.props(spec, {
				"value",
				"text",
				"options",
				"enabled",
				"acceptCustom",
				"onChange",
				"commitOnFocusLost",
				"placeholder",
			}, {
				Name = "ComboBox",
				Size = D2.new(1, 0, 0, 44),
				AutomaticSize = E.AutomaticSize.Y,
			})
		)
		local available = surfaces.available(root)
		Compose.watch(function(use: ComposeTypes.Use)
			if not use(available) or read(spec.enabled, use) == false then
				close()
			end
		end)
		local choices = function(use: ComposeTypes.Use): { Nav.MenuItem<string> }
			local result: { Nav.MenuItem<string> } = {}
			local query = string.lower(use(spec.text))
			for _, option in readOptions(spec.options, use) do
				if string.find(string.lower(readText(option.label, use)), query, 1, true) then
					local item: Nav.MenuCommand = {
						id = option.id or tostring(option.value),
						label = option.label,
						enabled = option.enabled,
						onSelect = function()
							update(option.value or option.id)
						end,
					}
					table.insert(result, item)
				end
			end
			return result
		end
		surfaces.attach(root, {
			surfaces.overlay(row, function(use: ComposeTypes.Use)
				return use(opened) and #choices(use) > 0
			end, function()
				local menuSpec: NavigationProps.MenuSpec<string> = { items = choices, presentation = "menu" }
				local panel = menuPanel(menuSpec, close, row, true)
				popup = panel
				Compose.cleanup(function()
					if gui and surfaces.within(gui.SelectedObject, panel) then
						gui.SelectedObject = if ctx.available(root) then editor else nil
					end
					popup = nil
				end)
				local input = surfaces.service("UserInputService")
				if input then
					runtime.connect(input, "InputBegan", function(event: InputObject)
						if
							event.UserInputType ~= E.UserInputType.MouseButton1
							and event.UserInputType ~= E.UserInputType.Touch
						then
							return
						end
						local function hit(node: GuiObject): boolean
							local at, size, point = node.AbsolutePosition, node.AbsoluteSize, event.Position
							return point.X >= at.X
								and point.Y >= at.Y
								and point.X <= at.X + size.X
								and point.Y <= at.Y + size.Y
						end
						local menu = panel:FindFirstChild("MenuPanel")
						if not hit(row) and menu and menu:IsA("GuiObject") and not hit(menu) then
							close()
						end
					end)
				end
				return panel
			end),
			Compose.show(function(use: ComposeTypes.Use)
				return use(editing) or use(opened)
			end, function()
				ctx.action(root, "ComboSuggestions", { E.KeyCode.Down, E.KeyCode.DPadDown }, editing, function()
					open()
					local panel = popup
					local target: GuiObject?
					if panel then
						for _, item in Compose.sample(choices) do
							if item.divider ~= true and read(item.enabled) ~= false then
								target = surfaces.firstSelectable(panel, item.id)
								if target then
									break
								end
							end
						end
					end
					if target and gui then
						navigating = true
						editor:ReleaseFocus(false)
						navigating = false
						gui.SelectedObject = target
					end
				end, { priority = 11000 })
				ctx.action(root, "ComboCancel", { E.KeyCode.Escape, E.KeyCode.ButtonB }, opened, function()
					cancel()
					if ctx.available(root) then
						editor:CaptureFocus()
					end
				end, { priority = 11000 })
				return Host.Folder {}
			end),
		})
		return root
	end)
end
