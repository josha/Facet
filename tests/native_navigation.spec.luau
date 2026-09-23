--!strict
local t = require("./lib/testkit")
local Compose = require("../src/vendor/compose/core")
local Roblox = require("../src/vendor/compose/roblox")
local controls = require("../src/ui")
local engines = require("./lib/native_engine")
local function find(root, name)
	if root.Name == name then
		return root
	end
	for _, child in root:GetChildren() do
		local found = find(child, name)
		if found then
			return found
		end
	end
	return nil
end
local function setup(build, options)
	local engine = engines.new()
	local gui = engine.new("GuiService")
	local input = engine.new("UserInputService")
	input.GetFocusedTextBox = function()
		return nil
	end
	local runtime = Roblox.createRuntime(engine)
	local UI = controls(runtime, {
		types = engine.types,
		services = { GuiService = gui, UserInputService = input },
		theme = options and options.theme,
	})
	local target = engine.new("Folder")
	local stop, screen = runtime.mount(function()
		return runtime.constructors.ScreenGui({ build(UI, runtime.constructors, engine, gui) })
	end, target)
	return {
		engine = engine,
		gui = gui,
		input = input,
		runtime = runtime,
		screen = screen,
		stop = function()
			stop()
			runtime:dispose()
		end,
	}
end

t.describe("native navigation controls", function()
	t.it("selects enabled picker values once and honors changing veto", function()
		local selected, changes = Compose.cell("one"), 0
		local world = setup(function(UI)
			return UI.Picker({
				selected = selected,
				style = "segmented",
				options = {
					{ value = "one", label = "One" },
					{ value = "two", label = "Two" },
					{ value = "three", label = "Three", enabled = false },
				},
				onChanging = function(value)
					return value ~= "one"
				end,
				onChange = function()
					changes += 1
				end,
			})
		end)
		find(world.screen, "three").Activated.fire()
		t.expect(selected:peek()).toBe("one")
		find(world.screen, "two").Activated.fire()
		find(world.screen, "two").Activated.fire()
		find(world.screen, "one").Activated.fire()
		t.expect(selected:peek()).toBe("two")
		t.expect(changes).toBe(1)
		world.stop()
	end)

	t.it("retains model values and updates picker font bindings", function()
		local selected, textSize = Compose.cell("one"), Compose.cell(16)
		local world = setup(function(UI)
			return UI.Picker({
				selected = selected,
				textSize = textSize,
				style = "segmented",
				options = { { value = "one", label = "One" } },
			})
		end)
		textSize:set(22)
		t.expect(find(world.screen, "one").TextSize).toBe(22)
		world.stop()
	end)

	t.it("mounts menus in the native layer, traverses submenus and closes after action", function()
		local opened, count = Compose.cell(false), 0
		local world = setup(function(UI)
			return UI.Menu({
				isPresented = opened,
				items = {
					{
						id = "Nested",
						label = "Nested",
						children = {
							{
								id = "Run",
								label = "Run",
								onSelect = function()
									count += 1
								end,
							},
						},
					},
				},
			})
		end)
		opened:set(true)
		local panel = find(world.screen, "MenuPanel")
		t.expect(panel.Parent.Parent).toBe(world.screen)
		find(world.screen, "Nested").Activated.fire()
		find(world.screen, "Run").Activated.fire()
		t.expect(count).toBe(1)
		t.expect(opened:peek()).toBe(false)
		t.expect(find(world.screen, "MenuPanel")).toBe(nil)
		world.stop()
	end)

	t.it("traps all modal selection directions and restores surviving focus on Back", function()
		local presented = Compose.cell(false)
		local cancelled = 0
		local world = setup(function(UI, Host, _, gui)
			local button = UI.Button({ Name = "Original", label = "Original" })
			gui.SelectedObject = button
			return Host.Frame({
				button,
				UI.Alert({
					isPresented = presented,
					title = "Confirm",
					actions = {
						{ id = "Disabled", label = "No", enabled = false },
						{
							id = "Cancel",
							label = "Cancel",
							role = "cancel",
							onActivate = function()
								cancelled += 1
							end,
						},
						{ id = "Accept", label = "Accept" },
					},
				}),
			})
		end)
		presented:set(true)
		local panel = find(world.screen, "AlertPanel")
		for _, direction in { "Up", "Down", "Left", "Right" } do
			t.expect(panel["SelectionBehavior" .. direction]).toBe(world.engine.types.Enum.SelectionBehavior.Stop)
		end
		t.expect(world.gui.SelectedObject.Name).toBe("Cancel")
		local back = find(world.screen, "ModalBack")
		t.expect(back.Parent.Parent).toBe(world.screen)
		back.Pressed.fire()
		t.expect(presented:peek()).toBe(false)
		t.expect(cancelled).toBe(1)
		t.expect(world.gui.SelectedObject.Name).toBe("Original")
		t.expect(back.isDestroyed()).toBe(true)
		world.stop()
	end)

	t.it("captures alert payload and closes before invoking its action", function()
		local item, result = Compose.cell({ id = "payload" }), nil
		local world = setup(function(UI)
			return UI.Alert({
				item = item,
				title = function(payload)
					return payload.id
				end,
				actions = {
					{
						id = "Accept",
						label = "Accept",
						onActivate = function(payload)
							result = { payload.id, item:peek() }
						end,
					},
				},
			})
		end)
		find(world.screen, "Accept").Activated.fire()
		t.expect(item:peek()).toBe(nil)
		t.expect(result[1]).toBe("payload")
		t.expect(result[2]).toBe(nil)
		world.stop()
	end)

	t.it("owns disclosure content only while expanded", function()
		for _, appearance in { "plain", "contained", "divided" } do
			local expanded, built, disposed = Compose.cell(false), 0, 0
			local world = setup(function(UI, Host)
				return UI.DisclosureGroup({
					expanded = expanded,
					label = "Details",
					appearance = appearance,
					content = function()
						built += 1
						Compose.cleanup(function()
							disposed += 1
						end)
						return Host.Frame({ Name = "Details", LayoutOrder = -10 })
					end,
				})
			end)
			local header = find(world.screen, "Header")
			t.expect(header.LayoutOrder).toBe(1)
			t.expect(built).toBe(0)
			local function checkOrder()
				local content = find(world.screen, "Details")
				local body = if appearance == "divided" then content.Parent else content
				t.expect(body.Parent).toBe(header.Parent)
				t.expect(body.LayoutOrder).toBe(2)
				t.expect(header.LayoutOrder < body.LayoutOrder).toBe(true)
				t.expect(header.Parent:FindFirstChildWhichIsA("UIListLayout").SortOrder)
					.toBe(world.engine.types.Enum.SortOrder.LayoutOrder)
				if appearance == "divided" then
					t.expect(find(body, "Divider").LayoutOrder < content.LayoutOrder).toBe(true)
				end
				return content
			end
			local caret = find(header, "LeadingIcon")
			local closedIcon = caret.Image
			expanded:set(true)
			t.expect(caret.Image ~= closedIcon).toBe(true)
			local old = checkOrder()
			expanded:set(false)
			t.expect(caret.Image).toBe(closedIcon)
			t.expect(old.isDestroyed()).toBe(true)
			t.expect(disposed).toBe(1)
			expanded:set(true)
			t.expect(checkOrder() ~= old).toBe(true)
			t.expect(find(world.screen, "Header")).toBe(header)
			t.expect(built).toBe(2)
			world.stop()
			t.expect(disposed).toBe(2)
		end
	end)

	t.it("retains visited tab state across selection and declaration reorders", function()
		local selected, built, disposed = Compose.cell("one"), 0, 0
		local tabs
		local world = setup(function(UI, Host)
			local function content()
				built += 1
				Compose.cleanup(function()
					disposed += 1
				end)
				return Host.Frame({ Name = "ContentState" })
			end
			tabs = Compose.cell({
				{ id = "one", label = "One", content = content },
				{ id = "two", label = "Two", content = content },
			})
			return UI.TabView({ selection = selected, tabs = tabs })
		end)
		selected:set("two")
		selected:set("one")
		local old = tabs:peek()
		tabs:set({ old[2], old[1] })
		t.expect(built).toBe(2)
		t.expect(disposed).toBe(0)
		t.expect(selected:peek()).toBe("one")
		world.stop()
		t.expect(disposed).toBe(2)
	end)

	t.it("retains covered navigation destinations and disposes popped pages", function()
		local path, built, disposed = Compose.cell({}), 0, 0
		local world = setup(function(UI, Host)
			local function content(entry)
				built += 1
				Compose.cleanup(function()
					disposed += 1
				end)
				return Host.Frame({ Name = if entry then "Detail" else "Root" })
			end
			return UI.NavigationStack({
				path = path,
				root = { title = "Root", content = content },
				destinations = { detail = { title = "Detail", content = content } },
			})
		end)
		path:set({ { id = "detail" } })
		t.expect(built).toBe(2)
		t.expect(disposed).toBe(0)
		find(world.screen, "Back").Activated.fire()
		t.expect(#path:peek()).toBe(0)
		t.expect(disposed).toBe(1)
		world.stop()
		t.expect(disposed).toBe(2)
	end)

	t.it("uses native page layout for model navigation and engine swipes", function()
		local selection = Compose.cell("one")
		local world = setup(function(UI, Host)
			return UI.PageView({
				selection = selection,
				pages = {
					{ id = "one", title = "One", content = Host.Frame({}) },
					{ id = "two", title = "Two", content = Host.Frame({}) },
				},
			})
		end)
		find(world.screen, "Next").Activated.fire()
		t.expect(selection:peek()).toBe("two")
		local layout = find(world.screen, "PagesLayout")
		t.expect(layout.CurrentPage.Name).toBe("two")
		layout:JumpTo(find(find(world.screen, "Pages"), "one"))
		t.expect(selection:peek()).toBe("one")
		world.stop()
	end)

	t.it("validates combo custom commits and cancels editable text", function()
		local value, text, changes = Compose.cell("a"), Compose.cell("Alpha"), 0
		local world = setup(function(UI)
			return UI.ComboBox({
				value = value,
				text = text,
				options = { { id = "a", label = "Alpha" }, { id = "b", label = "Beta" } },
				acceptCustom = function(candidate)
					return candidate == "Custom", "Rejected"
				end,
				onChange = function()
					changes += 1
				end,
			})
		end)
		local editor = find(world.screen, "Editor")
		editor.Focused.fire()
		editor.Text = "Rejected"
		editor.FocusLost.fire(true)
		t.expect(value:peek()).toBe("a")
		t.expect(find(world.screen, "Validation").Text).toBe("Rejected")
		editor.Focused.fire()
		editor.Text = "Custom"
		editor.FocusLost.fire(true)
		t.expect(value:peek()).toBe("Custom")
		t.expect(changes).toBe(1)
		world.stop()
	end)

	t.it("keeps combo suggestions beside a single line and preserves native typing until Down", function()
		local value, text, changes, validations = Compose.cell("a"), Compose.cell("Alpha"), 0, 0
		local world = setup(function(UI, _, engine)
			return UI.ComboBox({
				Name = "SearchCombo",
				Size = engine.types.UDim2.fromOffset(320, 44),
				value = value,
				text = text,
				commitOnFocusLost = true,
				options = {
					{ value = "locked", label = "Alabama", enabled = false },
					{ value = "a", label = "Alpha" },
					{ value = "b", label = "Beta" },
				},
				acceptCustom = function()
					validations += 1
					return true
				end,
				onChange = function()
					changes += 1
				end,
			})
		end)
		local root = find(world.screen, "SearchCombo")
		local row, editor, suggestions = find(root, "Row"), find(root, "Editor"), find(root, "Suggestions")
		local trigger = find(suggestions, "Trigger")
		t.expect(editor.Parent).toBe(row)
		t.expect(suggestions.Parent).toBe(row)
		t.expect(row.Size.Y.Offset).toBe(44)
		t.expect(editor.Size.X.Scale).toBe(1)
		t.expect(editor.Size.X.Offset).toBe(-60)
		t.expect(editor.Size.Y.Scale).toBe(1)
		t.expect(suggestions.Position.X.Scale).toBe(1)
		t.expect(suggestions.Position.X.Offset).toBe(-56)
		t.expect(suggestions.Position.Y.Offset).toBe(0)
		t.expect(suggestions.Size.Y.Scale).toBe(1)
		t.expect(trigger.Size.Y.Scale).toBe(1)
		t.expect(trigger.AutomaticSize).toBe(world.engine.types.Enum.AutomaticSize.None)
		editor:CaptureFocus()
		world.gui.SelectedObject = editor
		editor.Text = "a"
		local overlay = find(world.screen, "SuggestionsOverlay")
		t.expect(overlay ~= nil).toBe(true)
		t.expect(overlay.Parent).toBe(world.screen)
		t.expect(find(overlay, "ModalBack")).toBe(nil)
		t.expect(editor:IsFocused()).toBe(true)
		t.expect(editor.TextEditable).toBe(true)
		t.expect(world.gui.SelectedObject).toBe(editor)
		editor.Text = "be"
		t.expect(find(overlay, "b") ~= nil).toBe(true)
		t.expect(find(overlay, "a")).toBe(nil)
		t.expect(find(root, "Editor")).toBe(editor)
		t.expect(editor:IsFocused()).toBe(true)
		find(world.screen, "ComboSuggestions").Pressed.fire()
		t.expect(editor:IsFocused()).toBe(false)
		t.expect(world.gui.SelectedObject).toBe(find(overlay, "b"))
		t.expect(validations).toBe(0)
		t.expect(changes).toBe(0)
		find(overlay, "b").Activated.fire()
		t.expect(value:peek()).toBe("b")
		t.expect(text:peek()).toBe("Beta")
		t.expect(changes).toBe(1)
		t.expect(find(world.screen, "SuggestionsOverlay")).toBe(nil)
		t.expect(world.gui.SelectedObject).toBe(editor)
		editor:CaptureFocus()
		editor.Text = "al"
		find(world.screen, "ComboSuggestions").Pressed.fire()
		t.expect(world.gui.SelectedObject.Name).toBe("a")
		find(world.screen, "ComboCancel").Pressed.fire()
		t.expect(text:peek()).toBe("Beta")
		t.expect(value:peek()).toBe("b")
		t.expect(editor:IsFocused()).toBe(true)
		t.expect(find(world.screen, "SuggestionsOverlay")).toBe(nil)
		t.expect(validations).toBe(0)
		t.expect(changes).toBe(1)
		world.stop()
	end)

	t.it("closes combo suggestions outside the field and honors custom focus-loss policy", function()
		local value, text, enabled = Compose.cell("a"), Compose.cell("Alpha"), Compose.cell(true)
		local world = setup(function(UI)
			return UI.ComboBox({
				value = value,
				text = text,
				enabled = enabled,
				options = { { value = "a", label = "Alpha" } },
				acceptCustom = function()
					return true
				end,
			})
		end)
		local editor = find(world.screen, "Editor")
		editor:CaptureFocus()
		editor.Text = "Custom"
		editor:ReleaseFocus(false)
		t.expect(value:peek()).toBe("a")
		t.expect(text:peek()).toBe("Custom")
		world.input.InputBegan.fire({
			UserInputType = world.engine.types.Enum.UserInputType.MouseButton1,
			Position = world.engine.types.Vector3.new(1000, 1000, 0),
		})
		t.expect(find(world.screen, "SuggestionsOverlay")).toBe(nil)
		find(find(world.screen, "Suggestions"), "Trigger").Activated.fire()
		t.expect(find(world.screen, "SuggestionsOverlay") ~= nil).toBe(true)
		enabled:set(false)
		t.expect(find(world.screen, "SuggestionsOverlay")).toBe(nil)
		world.stop()

		local enabledCommit = Compose.cell(true)
		local committing = setup(function(UI)
			return UI.ComboBox({
				value = value,
				text = text,
				enabled = enabledCommit,
				commitOnFocusLost = true,
				options = { { value = "a", label = "Alpha" } },
				acceptCustom = function(candidate)
					if candidate == "Disable" then
						enabledCommit:set(false)
					end
					return true
				end,
			})
		end)
		local committingEditor = find(committing.screen, "Editor")
		committingEditor:CaptureFocus()
		committingEditor.Text = "Custom"
		committingEditor:ReleaseFocus(false)
		t.expect(value:peek()).toBe("Custom")
		committingEditor:CaptureFocus()
		committingEditor.Text = "Disable"
		committingEditor:ReleaseFocus(true)
		t.expect(value:peek()).toBe("Custom")
		committing.stop()
	end)

	t.it("reopens combo suggestions after selected-result alerts finish their exit and the editor refocuses", function()
		local value, text, presented = Compose.cell(""), Compose.cell(""), Compose.cell(false)
		local changes = 0
		local world = setup(function(UI, Host)
			return Host.Frame({
				UI.ComboBox({
					Name = "Search",
					value = value,
					text = text,
					options = function(use)
						local query, options = string.lower(use(text)), {}
						for _, option in
							{ { value = "circuit", label = "Circuit" }, { value = "forest", label = "Forest" } }
						do
							if string.find(string.lower(option.label), query, 1, true) then
								table.insert(options, option)
							end
						end
						return options
					end,
					acceptCustom = function()
						return true
					end,
					onChange = function()
						changes += 1
						presented:set(true)
					end,
				}),
				UI.Alert({
					Name = "Result",
					isPresented = presented,
					title = "Selected game",
					transition = { seconds = 0.1 },
					actions = { { id = "CloseResult", label = "Close", role = "cancel" } },
				}),
			})
		end)
		local editor = find(world.screen, "Editor")
		world.input.GetFocusedTextBox = function()
			return if editor:IsFocused() then editor else nil
		end
		for index, choice in { "Circuit", "Forest", "Circuit" } do
			editor:CaptureFocus()
			t.expect(editor:IsFocused()).toBe(true)
			editor.Text = ""
			t.expect(text:peek()).toBe("")
			for length = 1, #choice do
				editor.Text = string.sub(choice, 1, length)
			end
			t.expect(text:peek()).toBe(choice)
			t.expect(editor:IsFocused()).toBe(true)
			local menu = find(world.screen, "MenuPanel")
			t.expect(menu ~= nil).toBe(true)
			find(menu, string.lower(choice)).Activated.fire()
			t.expect(value:peek()).toBe(string.lower(choice))
			t.expect(changes).toBe(index)
			t.expect(find(world.screen, "MenuPanel")).toBe(nil)
			t.expect(presented:peek()).toBe(true)
			t.expect(editor:IsFocused()).toBe(false)
			find(world.screen, "CloseResult").Activated.fire()
			t.expect(presented:peek()).toBe(false)
			world.engine.heartbeat.fire(0.2)
			t.expect(find(world.screen, "AlertModal")).toBe(nil)
			t.expect(find(world.screen, "Editor")).toBe(editor)
		end
		world.stop()
	end)

	t.it("snaps native sheet drags to declared detents and respects dismissal policy", function()
		local opened, detent = Compose.cell(true), Compose.cell("large")
		local world = setup(function(UI, Host)
			return UI.Sheet({
				isPresented = opened,
				detent = detent,
				title = "Sheet",
				content = function()
					return Host.Frame({ Name = "Body" })
				end,
				interactiveDismissDisabled = true,
			})
		end)
		local drag = find(world.screen, "UIDragDetector")
		drag.DragStart.fire(world.engine.types.Vector2.new(0, 0))
		drag.DragContinue.fire(world.engine.types.Vector2.new(0, 400))
		drag.DragEnd.fire()
		t.expect(detent:peek()).toBe("medium")
		find(world.screen, "ModalBack").Pressed.fire()
		t.expect(opened:peek()).toBe(true)
		world.stop()
	end)

	t.it("navigates radial branches and applies action completion", function()
		local opened, count = Compose.cell(true), 0
		local world = setup(function(UI)
			return UI.RadialMenu({
				isPresented = opened,
				items = {
					{
						id = "Branch",
						label = "Branch",
						children = {
							{
								id = "Action",
								label = "Action",
								completion = "root",
								onSelect = function()
									count += 1
								end,
							},
						},
					},
					{ id = "Unavailable", label = "Unavailable", enabled = false },
				},
			})
		end)
		find(world.screen, "Branch").Activated.fire()
		find(world.screen, "Action").Activated.fire()
		t.expect(count).toBe(1)
		t.expect(opened:peek()).toBe(true)
		t.expect(find(world.screen, "Branch") ~= nil).toBe(true)
		world.stop()
	end)
	t.it("blocks background shortcuts until the top modal leaves", function()
		local presented, count = Compose.cell(false), 0
		local world = setup(function(UI, Host)
			return Host.Frame({
				UI.Button({
					Name = "Background",
					label = "Background",
					shortcut = { keyCode = "K" },
					onActivate = function()
						count += 1
					end,
				}),
				UI.Alert({ isPresented = presented, title = "Modal" }),
			})
		end)
		local shortcut = find(world.screen, "Shortcut")
		shortcut.Pressed.fire()
		t.expect(count).toBe(1)
		presented:set(true)
		t.expect(shortcut.Parent.Enabled).toBe(false)
		shortcut.Pressed.fire()
		t.expect(count).toBe(1)
		presented:set(false)
		t.expect(shortcut.Parent.Enabled).toBe(true)
		shortcut.Pressed.fire()
		t.expect(count).toBe(2)
		world.stop()
	end)

	t.it("lets Back dismiss a disabled cancel action without invoking it", function()
		local presented, count = Compose.cell(true), 0
		local world = setup(function(UI)
			return UI.Alert({
				isPresented = presented,
				actions = {
					{
						id = "Cancel",
						label = "Cancel",
						role = "cancel",
						enabled = false,
						onActivate = function()
							count += 1
						end,
					},
					{ id = "Continue", label = "Continue", shortcut = "defaultAction" },
				},
			})
		end)
		find(world.screen, "ModalBack").Pressed.fire()
		t.expect(presented:peek()).toBe(false)
		t.expect(count).toBe(0)
		world.stop()
	end)

	t.it("returns disclosure focus before unmounting its content", function()
		local expanded = Compose.cell(true)
		local world = setup(function(UI)
			return UI.DisclosureGroup({
				expanded = expanded,
				label = "Details",
				content = function()
					return UI.Button({ Name = "Inside", label = "Inside" })
				end,
			})
		end)
		world.gui.SelectedObject = find(world.screen, "Inside")
		expanded:set(false)
		t.expect(world.gui.SelectedObject.Name).toBe("Header")
		world.stop()
	end)

	t.it("adapts an open menu to a compact sheet without losing its branch", function()
		local presented = Compose.cell(true)
		local world = setup(function(UI)
			return UI.Menu({
				isPresented = presented,
				items = {
					{
						id = "Parent",
						label = "Parent",
						children = { { id = "Leaf", label = "Leaf", onSelect = function() end } },
					},
				},
			})
		end)
		local modal = find(world.screen, "Modal")
		modal.AbsoluteSize = world.engine.types.Vector2.new(1000, 720)
		find(world.screen, "Parent").Activated.fire()
		t.expect(find(world.screen, "AncestorMenu") ~= nil).toBe(true)
		modal.AbsoluteSize = world.engine.types.Vector2.new(360, 640)
		t.expect(find(world.screen, "AncestorMenu")).toBe(nil)
		t.expect(find(world.screen, "Leaf") ~= nil).toBe(true)
		find(world.screen, "Back").Activated.fire()
		t.expect(find(world.screen, "Parent") ~= nil).toBe(true)
		world.stop()
	end)

	t.it("keeps checked menu state and required radio values while honoring dismissal", function()
		local presented, checked, selected = Compose.cell(true), Compose.cell(false), Compose.cell("a")
		local world = setup(function(UI)
			return UI.Menu({
				isPresented = presented,
				items = {
					{ id = "Check", label = "Check", checked = checked, dismiss = false },
					{ id = "Radio", label = "Radio", selected = selected, value = "b", dismiss = false },
					{ id = "Finish", label = "Finish", onSelect = function() end },
				},
			})
		end)
		find(world.screen, "Check").Activated.fire()
		find(world.screen, "Radio").Activated.fire()
		t.expect(checked:peek()).toBe(true)
		t.expect(selected:peek()).toBe("b")
		t.expect(presented:peek()).toBe(true)
		find(world.screen, "Finish").Activated.fire()
		t.expect(presented:peek()).toBe(false)
		world.stop()
	end)

	t.it("rehomes tab accessories with native measured space and owner cleanup", function()
		local selected, retired, built = Compose.cell("one"), 0, 0
		local preference, placement = Compose.cell("automatic"), Compose.cell("automatic")
		local world = setup(function(UI, Host)
			local function accessory()
				built += 1
				Compose.cleanup(function()
					retired += 1
				end)
				return Host.Frame({})
			end
			return UI.TabView({
				selection = selected,
				style = "sidebarAdaptable",
				sidebarPreference = preference,
				placement = placement,
				tabs = { {
					id = "one",
					content = function()
						return Host.Frame({})
					end,
				} },
				accessories = { head = accessory, foot = accessory, trailing = accessory, aboveBar = accessory },
			})
		end)
		local root = find(world.screen, "TabView")
		t.expect(find(root, "Tabs").ZIndex > find(root, "Content").ZIndex).toBe(true)
		root.AbsoluteSize = world.engine.types.Vector2.new(1200, 800)
		t.expect(find(world.screen, "Accessory-head") ~= nil).toBe(true)
		t.expect(find(world.screen, "Accessory-trailing")).toBe(nil)
		find(world.screen, "Accessory-head").AbsoluteSize = world.engine.types.Vector2.new(180, 52)
		t.expect(find(world.screen, "Tabs").Position.Y.Offset).toBe(52)
		preference:set("topBar")
		t.expect(find(world.screen, "Accessory-head")).toBe(nil)
		t.expect(find(world.screen, "Accessory-trailing") ~= nil).toBe(true)
		root.AbsoluteSize = world.engine.types.Vector2.new(401, 777)
		t.expect(find(world.screen, "Accessory-head")).toBe(nil)
		t.expect(find(world.screen, "Accessory-aboveBar") ~= nil).toBe(true)
		t.expect(find(world.screen, "Tabs").Position.Y.Scale).toBe(1)
		preference:set("sidebar")
		t.expect(find(world.screen, "Accessory-head")).toBe(nil)
		t.expect(find(world.screen, "Accessory-aboveBar") ~= nil).toBe(true)
		placement:set("topBar")
		t.expect(find(world.screen, "Accessory-trailing") ~= nil).toBe(true)
		t.expect(find(world.screen, "Accessory-aboveBar")).toBe(nil)
		placement:set("automatic")
		root.AbsoluteSize = world.engine.types.Vector2.new(1200, 800)
		t.expect(find(world.screen, "Accessory-head") ~= nil).toBe(true)
		world.stop()
		t.expect(retired).toBe(built)
	end)

	t.it("removes dynamically deleted tab owners and preserves the selected survivor", function()
		local selection, tabs, disposed = Compose.cell("one"), nil, 0
		local world = setup(function(UI, Host)
			local function content()
				Compose.cleanup(function()
					disposed += 1
				end)
				return Host.Frame({})
			end
			tabs = Compose.cell({ { id = "one", content = content }, { id = "two", content = content } })
			return UI.TabView({ selection = selection, tabs = tabs })
		end)
		selection:set("two")
		selection:set("one")
		tabs:set({ tabs:peek()[1] })
		t.expect(disposed).toBe(1)
		t.expect(selection:peek()).toBe("one")
		world.stop()
	end)

	t.it("queues callouts by priority and retires once without writing model facts", function()
		local seen, used, retired = Compose.cell(false), Compose.cell(false), {}
		local world = setup(function(UI, Host)
			local anchor = UI.Button({ Name = "Anchor", label = "Anchor" })
			return Host.Frame({
				anchor,
				UI.Callout({
					anchor = anchor,
					seen = seen,
					priority = 1,
					content = function()
						return Host.TextLabel({ Name = "FirstTip" })
					end,
					onRetire = function(reason)
						table.insert(retired, "low:" .. reason)
					end,
				}),
				UI.Callout({
					anchor = anchor,
					featureUsed = used,
					priority = 2,
					content = function()
						return Host.TextLabel({ Name = "PriorityTip" })
					end,
					onRetire = function(reason)
						table.insert(retired, "high:" .. reason)
					end,
				}),
			})
		end)
		t.expect(find(world.screen, "FirstTip")).toBe(nil)
		t.expect(find(world.screen, "PriorityTip") ~= nil).toBe(true)
		used:set(true)
		t.expect(find(world.screen, "PriorityTip")).toBe(nil)
		t.expect(find(world.screen, "FirstTip") ~= nil).toBe(true)
		find(world.screen, "Dismiss").Activated.fire()
		t.expect(#retired).toBe(2)
		t.expect(seen:peek()).toBe(false)
		world.stop()
		t.expect(#retired).toBe(2)
	end)

	t.it("keeps sheet content in a native flex remainder and explicit close operable", function()
		local presented = Compose.cell(true)
		local world = setup(function(UI, Host)
			return UI.Sheet({
				isPresented = presented,
				detent = Compose.cell("medium"),
				title = "Details",
				interactiveDismissDisabled = true,
				content = function()
					return Host.ScrollingFrame({ Name = "DetailBody" })
				end,
			})
		end)
		t.expect(find(world.screen, "DetailBody").Parent.Name).toBe("SheetContent")
		local body = find(world.screen, "SheetContent")
		t.expect(body.ClassName).toBe("ScrollingFrame")
		t.expect(body.AutomaticCanvasSize).toBe(world.engine.types.Enum.AutomaticSize.Y)
		t.expect(find(find(world.screen, "SheetContent"), "UIFlexItem").FlexMode)
			.toBe(world.engine.types.Enum.UIFlexMode.Fill)
		find(world.screen, "Close").Activated.fire()
		t.expect(presented:peek()).toBe(false)
		world.stop()
	end)
	t.it("contains failed alert factories and accepts a later valid presentation", function()
		local item, disposed = Compose.cell(nil), 0
		local world = setup(function(UI, Host)
			return UI.Alert({
				item = item,
				title = function(value)
					return value.id
				end,
				content = function(value)
					Compose.cleanup(function()
						disposed += 1
					end)
					if value.id == "bad" then
						error("invalid content")
					end
					return Host.Frame({ Name = "Recovered" })
				end,
			})
		end)
		item:set({ id = "bad" })
		t.expect(item:peek()).toBe(nil)
		t.expect(disposed).toBe(1)
		item:set({ id = "good" })
		t.expect(find(world.screen, "Recovered") ~= nil).toBe(true)
		world.stop()
		t.expect(disposed).toBe(2)
	end)

	t.it("wraps alert actions and bounds long message scrolling to native measurements", function()
		local world = setup(function(UI)
			return UI.Alert({
				isPresented = Compose.cell(true),
				message = string.rep("Long message ", 100),
				actions = {
					{ id = "Cancel", label = "Cancel", role = "cancel" },
					{ id = "Accept", label = "Continue" },
				},
			})
		end)
		find(world.screen, "AlertModal").AbsoluteSize = world.engine.types.Vector2.new(360, 240)
		find(world.screen, "Actions").AbsoluteSize = world.engine.types.Vector2.new(320, 96)
		find(world.screen, "AlertContent").AbsoluteSize = world.engine.types.Vector2.new(320, 1000)
		t.expect(find(find(world.screen, "Actions"), "UIListLayout").FillDirection)
			.toBe(world.engine.types.Enum.FillDirection.Vertical)
		t.expect(find(world.screen, "Cancel").LayoutOrder > find(world.screen, "Accept").LayoutOrder).toBe(true)
		t.expect(find(world.screen, "AlertMessage").Size.Y.Offset < 100).toBe(true)
		world.stop()
	end)

	t.it("keeps split primary activation separate from touch long-press alternatives", function()
		local primary, alternative = 0, 0
		local world = setup(function(UI, _, engine)
			return UI.SplitButton({
				Size = engine.types.UDim2.fromOffset(148, 44),
				AutomaticSize = engine.types.Enum.AutomaticSize.None,
				label = "Run",
				onActivate = function()
					primary += 1
				end,
				items = {
					{
						id = "Alternate",
						label = "Alternate",
						onSelect = function()
							alternative += 1
						end,
					},
				},
			})
		end)
		find(world.screen, "Primary").Activated.fire()
		t.expect(primary).toBe(1)
		world.input.PreferredInput = world.engine.types.Enum.PreferredInput.Touch
		local trigger = find(world.screen, "Primary")
		t.expect(trigger.Size).toBe(world.engine.types.UDim2.fromScale(1, 1))
		t.expect(trigger.AutomaticSize).toBe(world.engine.types.Enum.AutomaticSize.None)
		trigger.TouchLongPress.fire({}, world.engine.types.Enum.UserInputState.Begin)
		trigger.Activated.fire()
		t.expect(primary).toBe(1)
		t.expect(find(world.screen, "MenuPanel") ~= nil).toBe(true)
		find(world.screen, "Alternate").Activated.fire()
		t.expect(alternative).toBe(1)
		world.stop()
	end)

	t.it("opens searchable picker content only when presented and commits filtered results", function()
		local selection, query, opened = Compose.cell("a"), Compose.cell(""), Compose.cell(false)
		local world = setup(function(UI)
			return UI.Picker({
				selected = selection,
				query = query,
				isPresented = opened,
				style = "navigationLink",
				options = { { value = "a", label = "Alpha" }, { value = "b", label = "Beta" } },
			})
		end)
		t.expect(find(world.screen, "PickerSearch")).toBe(nil)
		opened:set(true)
		query:set("Bet")
		t.expect(find(find(world.screen, "Choices"), "a")).toBe(nil)
		find(find(world.screen, "Choices"), "b").Activated.fire()
		t.expect(selection:peek()).toBe("b")
		t.expect(opened:peek()).toBe(false)
		world.stop()
	end)
	t.it("restores surviving navigation focus and moves paging focus into the visible page", function()
		local path = Compose.cell({})
		local world = setup(function(UI)
			return UI.NavigationStack({
				path = path,
				root = {
					content = function()
						return UI.Button({ Name = "RootAction", label = "Root" })
					end,
				},
				destinations = {
					detail = {
						content = function()
							return UI.Button({ Name = "DetailAction", label = "Detail" })
						end,
					},
				},
			})
		end)
		world.gui.SelectedObject = find(world.screen, "RootAction")
		path:set({ { id = "detail" } })
		t.expect(world.gui.SelectedObject.Name).toBe("Back")
		path:set({})
		t.expect(world.gui.SelectedObject.Name).toBe("RootAction")
		world.stop()
		local selection = Compose.cell("one")
		local pager = setup(function(UI)
			return UI.PageView({
				selection = selection,
				pages = {
					{ id = "one", content = UI.Button({ Name = "PageOne", label = "One" }) },
					{ id = "two", content = UI.Button({ Name = "PageTwo", label = "Two" }) },
				},
			})
		end)
		pager.gui.SelectedObject = find(pager.screen, "PageOne")
		selection:set("two")
		t.expect(pager.gui.SelectedObject.Name).toBe("PageTwo")
		pager.stop()
	end)
	t.it("bounds menu scrolling, prunes removed branches and closes every level on tap away", function()
		local shown, items =
			Compose.cell(true), Compose.cell({ { id = "branch", label = "Branch", children = {
				{ id = "leaf", label = "Leaf", onSelect = function() end },
			} } })
		local world = setup(function(UI)
			return UI.Menu({ isPresented = shown, items = items })
		end)
		local panel = find(world.screen, "MenuPanel")
		panel.Parent.AbsoluteSize = world.engine.types.Vector2.new(700, 300)
		find(world.screen, "MenuRows").AbsoluteSize = world.engine.types.Vector2.new(280, 1000)
		t.expect(panel.ClassName).toBe("ScrollingFrame")
		t.expect(panel.Size.Y.Offset).toBe(276)
		find(world.screen, "branch").Activated.fire()
		items:set({ { id = "other", label = "Other", onSelect = function() end } })
		t.expect(find(world.screen, "leaf")).toBe(nil)
		t.expect(find(world.screen, "other") ~= nil).toBe(true)
		items:set({
			{
				id = "branch",
				label = "Branch",
				children = { { id = "leaf", label = "Leaf", onSelect = function() end } },
			},
		})
		find(world.screen, "branch").Activated.fire()
		find(world.screen, "DismissOutside").Activated.fire()
		t.expect(shown:peek()).toBe(false)
		world.stop()
	end)

	t.it("adapts automatic pickers and updates native segment axis and badges without replacing options", function()
		local value, axis, badge = Compose.cell("a"), Compose.cell("x"), Compose.cell(1)
		local position, visible, interactable = Compose.cell(24), Compose.cell(true), Compose.cell(true)
		local reference, references, enters = nil, 0, 0
		local world = setup(function(UI, Host, engine)
			return Host.Frame({
				UI.Picker({
					Name = "Auto",
					Position = function(use)
						return engine.types.UDim2.fromOffset(use(position), 70)
					end,
					AnchorPoint = engine.types.Vector2.new(0.5, 0),
					Size = engine.types.UDim2.fromOffset(240, 44),
					AutomaticSize = engine.types.Enum.AutomaticSize.None,
					LayoutOrder = 7,
					Visible = visible,
					Interactable = interactable,
					Attributes = { role = "choice" },
					ref = function(node)
						reference = node
						references += 1
					end,
					[Compose.event("MouseEnter")] = function()
						enters += 1
					end,
					Host.UICorner({ Name = "AuthoredCorner" }),
					selected = value,
					options = {
						{ value = "a", label = "Alpha" },
						{ value = "b", label = "Beta" },
					},
				}),
				UI.Picker({
					Name = "Segments",
					style = "segmented",
					axis = axis,
					selected = value,
					options = { { value = "a", label = "Alpha", badge = badge }, { value = "b", label = "Beta" } },
				}),
			})
		end)
		local automatic = find(world.screen, "Auto")
		local decoration = find(automatic, "AuthoredCorner")
		t.expect(reference).toBe(automatic)
		t.expect(automatic.Position.X.Offset).toBe(24)
		t.expect(automatic.Position.Y.Offset).toBe(70)
		t.expect(automatic.AnchorPoint.X).toBe(0.5)
		t.expect(automatic.Size.X.Offset).toBe(240)
		t.expect(automatic.Size.Y.Offset).toBe(44)
		t.expect(automatic.AutomaticSize).toBe(world.engine.types.Enum.AutomaticSize.None)
		t.expect(automatic.LayoutOrder).toBe(7)
		t.expect(automatic:GetAttribute("role")).toBe("choice")
		t.expect(decoration.Parent).toBe(automatic)
		local presentation = find(automatic, "Presentation")
		t.expect(presentation.Position.X.Offset).toBe(0)
		t.expect(presentation.Size.X.Scale).toBe(1)
		t.expect(presentation.Size.Y.Scale).toBe(1)
		t.expect(presentation:GetAttribute("role")).toBe(nil)
		automatic.MouseEnter.fire()
		presentation.MouseEnter.fire()
		t.expect(enters).toBe(1)
		position:set(52)
		visible:set(false)
		interactable:set(false)
		t.expect(automatic.Position.X.Offset).toBe(52)
		t.expect(automatic.Visible).toBe(false)
		t.expect(automatic.Interactable).toBe(false)
		visible:set(true)
		interactable:set(true)
		local segments = find(world.screen, "Segments")
		local a = find(segments, "a")
		axis:set("y")
		badge:set(3)
		t.expect(find(segments, "a")).toBe(a)
		t.expect(a.Size.X.Scale).toBe(1)
		t.expect(a.Text).toBe("Alpha (3)")
		t.expect(segments:FindFirstChildWhichIsA("UIListLayout").FillDirection)
			.toBe(world.engine.types.Enum.FillDirection.Vertical)
		world.input.PreferredInput = world.engine.types.Enum.PreferredInput.Touch
		t.expect(find(find(world.screen, "Auto"), "Trigger") ~= nil).toBe(true)
		world.input.PreferredInput = world.engine.types.Enum.PreferredInput.Gamepad
		t.expect(find(find(world.screen, "Auto"), "b") ~= nil).toBe(true)
		t.expect(find(world.screen, "Auto")).toBe(automatic)
		t.expect(find(automatic, "AuthoredCorner")).toBe(decoration)
		t.expect(automatic.Position.X.Offset).toBe(52)
		t.expect(find(automatic, "Presentation").Position.X.Offset).toBe(0)
		t.expect(references).toBe(1)
		automatic.MouseEnter.fire()
		t.expect(enters).toBe(2)
		t.expect(value:peek()).toBe("a")
		world.stop()
	end)

	t.it("bounds menu picker triggers to authored widths without losing their full label", function()
		local selected = Compose.cell("hud")
		local sizing
		local world = setup(function(UI, Host, engine)
			sizing = Compose.cell(engine.types.Enum.AutomaticSize.None)
			return Host.Frame({
				UI.Picker({
					Name = "Bounded",
					style = "menu",
					Size = engine.types.UDim2.new(1, -160, 0, 44),
					selected = selected,
					options = {
						{ value = "hud", label = "Screen-anchored HUD with a long title" },
						{ value = "other", label = "Another destination with a long title" },
					},
				}),
				UI.Menu({
					Name = "AdaptiveHeight",
					Size = engine.types.UDim2.new(1, 0, 0, 0),
					AutomaticSize = sizing,
					label = "Menu",
					items = { { id = "one", label = "One", onSelect = function() end } },
				}),
			})
		end)
		local bounded = find(world.screen, "Bounded")
		local trigger = find(bounded, "Trigger")
		t.expect(bounded.AutomaticSize).toBe(world.engine.types.Enum.AutomaticSize.None)
		t.expect(trigger.AutomaticSize).toBe(world.engine.types.Enum.AutomaticSize.None)
		t.expect(trigger.Size.X.Scale).toBe(1)
		t.expect(trigger.Size.X.Offset).toBe(0)
		t.expect(trigger.Size.Y.Scale).toBe(1)
		t.expect(trigger.TextTruncate).toBe(world.engine.types.Enum.TextTruncate.AtEnd)
		t.expect(trigger.TextWrapped).toBe(false)
		t.expect(trigger.ClipsDescendants).toBe(true)
		t.expect(trigger.Text).toBe("Screen-anchored HUD with a long title")
		t.expect(trigger:GetAttribute("FacetLabel")).toBe(trigger.Text)
		trigger.Activated.fire()
		find(find(world.screen, "MenuPanel"), "other").Activated.fire()
		t.expect(selected:peek()).toBe("other")
		t.expect(trigger.Text).toBe("Another destination with a long title")
		t.expect(trigger:GetAttribute("FacetLabel")).toBe(trigger.Text)
		local adaptive = find(find(world.screen, "AdaptiveHeight"), "Trigger")
		sizing:set(world.engine.types.Enum.AutomaticSize.Y)
		t.expect(adaptive.AutomaticSize).toBe(world.engine.types.Enum.AutomaticSize.Y)
		t.expect(adaptive.Size.X.Scale).toBe(1)
		t.expect(adaptive.Size.Y.Scale).toBe(0)
		t.expect(adaptive.Size.Y.Offset >= 44).toBe(true)
		world.stop()
	end)

	t.it("keeps plain picker segments native while retaining live description sources", function()
		local selected, description = Compose.cell("a"), Compose.cell("")
		local options = Compose.cell({ { value = "a", label = "Alpha" } })
		local world = setup(function(UI, Host)
			return Host.Frame({
				UI.Picker({
					Name = "Plain",
					style = "segmented",
					selected = selected,
					options = { { value = "a", label = "Alpha" }, { value = "b", label = "Beta" } },
				}),
				UI.Picker({
					Name = "ReadableDescription",
					style = "segmented",
					selected = selected,
					options = { { value = "a", label = "Alpha", description = description } },
				}),
				UI.Picker({ Name = "ReadableOptions", style = "segmented", selected = selected, options = options }),
			})
		end)
		local plain = find(find(world.screen, "Plain"), "a")
		t.expect(plain.ClassName).toBe("TextButton")
		t.expect(plain.Text).toBe("Alpha")
		t.expect(find(plain, "Content")).toBe(nil)
		t.expect(find(plain, "Description")).toBe(nil)
		find(find(world.screen, "Plain"), "b").Activated.fire()
		t.expect(selected:peek()).toBe("b")
		local described = find(find(world.screen, "ReadableDescription"), "a")
		description:set("Appeared")
		t.expect(find(find(world.screen, "ReadableDescription"), "a")).toBe(described)
		t.expect(find(described, "Description").Text).toBe("Appeared")
		t.expect(find(described, "Description").Visible).toBe(true)
		description:set("")
		t.expect(find(described, "Description").Visible).toBe(false)
		local replaced = find(find(world.screen, "ReadableOptions"), "a")
		options:set({ { value = "a", label = "Alpha updated", description = "Added later" } })
		t.expect(find(find(world.screen, "ReadableOptions"), "a")).toBe(replaced)
		t.expect(find(replaced, "Title").Text).toBe("Alpha updated")
		t.expect(find(replaced, "Description").Text).toBe("Added later")
		t.expect(find(find(world.screen, "Plain"), "a")).toBe(plain)
		world.stop()
	end)

	t.it("quarantines invalid paths and contains destination faults while preserving Back", function()
		local path, disposed = Compose.cell({}), 0
		local world = setup(function(UI, Host)
			return UI.NavigationStack({
				path = path,
				root = {
					content = function()
						return UI.Button({ Name = "RootAction", label = "Root" })
					end,
				},
				destinations = {
					good = {
						content = function()
							return UI.Button({ Name = "Good", label = "Good" })
						end,
					},
					bad = {
						content = function()
							Compose.cleanup(function()
								disposed += 1
							end)
							Host.Frame({})
							error("failed page")
						end,
					},
				},
			})
		end)
		local root = find(world.screen, "@root")
		t.expect(find(root, "Destination").Position.Y.Offset).toBe(0)
		path:set({ { id = "good" } })
		local good = find(world.screen, "Good")
		path:set({ { id = "unknown" } })
		t.expect(find(world.screen, "Good")).toBe(good)
		t.expect(find(world.screen, "NavigationStack"):GetAttribute("FacetError") ~= nil).toBe(true)
		path:set({ { id = "bad" } })
		t.expect(find(world.screen, "DestinationError") ~= nil).toBe(true)
		t.expect(disposed).toBe(1)
		find(world.screen, "Back").Activated.fire()
		t.expect(#path:peek()).toBe(0)
		t.expect(find(world.screen, "RootAction") ~= nil).toBe(true)
		world.stop()
	end)

	t.it("routes nested Back through the focused native context before its parent", function()
		local outer, inner = Compose.cell({ { id = "child" } }), Compose.cell({ { id = "detail" } })
		local world = setup(function(UI)
			return UI.NavigationStack({
				path = outer,
				root = {
					content = function()
						return UI.Button({ label = "Root" })
					end,
				},
				destinations = {
					child = {
						content = function()
							return UI.NavigationStack({
								Name = "ChildStack",
								path = inner,
								root = {
									content = function()
										return UI.Button({ label = "Child root" })
									end,
								},
								destinations = {
									detail = {
										content = function()
											return UI.Button({ Name = "DeepAction", label = "Deep" })
										end,
									},
								},
							})
						end,
					},
				},
			})
		end)
		world.gui.SelectedObject = find(world.screen, "DeepAction")
		local winner
		for _, node in world.screen:GetDescendants() do
			if
				node.Name == "NavigationBack"
				and node.Parent.Enabled
				and (not winner or node.Parent.Priority > winner.Parent.Priority)
			then
				winner = node
			end
		end
		t.expect(winner ~= nil).toBe(true)
		winner.Pressed.fire()
		t.expect(#inner:peek()).toBe(0)
		t.expect(#outer:peek()).toBe(1)
		world.stop()
	end)

	t.it("keeps callouts nonmodal, fits their plate and observes nonconsuming tap away", function()
		local shown, retired, presses = Compose.cell(true), nil, 0
		local world = setup(function(UI, Host, engine, gui)
			local anchor = UI.Button({
				Name = "Anchor",
				label = "Anchor",
				onActivate = function()
					presses += 1
				end,
			})
			gui.SelectedObject = anchor
			return Host.Frame({
				anchor,
				UI.Callout({
					anchor = anchor,
					isPresented = shown,
					onRetire = function(reason)
						retired = reason
					end,
					content = function()
						return UI.Button({ label = "Tip" })
					end,
				}),
			})
		end)
		local V = world.engine.types.Vector2
		world.screen.AbsoluteSize = V.new(320, 400)
		local anchor, panel = find(world.screen, "Anchor"), find(world.screen, "CalloutPanel")
		anchor.AbsolutePosition = V.new(280, 20)
		anchor.AbsoluteSize = V.new(32, 44)
		panel.AbsoluteSize = V.new(280, 100)
		t.expect(panel.Position.X.Offset).toBe(32)
		t.expect(world.gui.SelectedObject).toBe(anchor)
		anchor.Activated.fire()
		t.expect(presses).toBe(1)
		world.input.InputBegan.fire(
			{ UserInputType = world.engine.types.Enum.UserInputType.MouseButton1, Position = V.new(10, 350) },
			false
		)
		t.expect(retired).toBe("tapAway")
		t.expect(shown:peek()).toBe(true)
		t.expect(find(world.screen, "CalloutPanel")).toBe(nil)
		world.stop()
	end)

	t.it("retargets native sheet motion and honors live reduced motion without losing content", function()
		local selected, shown = Compose.cell("medium"), Compose.cell(true)
		local world = setup(function(UI)
			return UI.Sheet({
				detent = selected,
				isPresented = shown,
				content = function()
					return UI.Button({ Name = "KeptContent", label = "Content" })
				end,
			})
		end)
		local panel, content = find(world.screen, "SheetPanel"), find(world.screen, "KeptContent")
		local before = panel.Size.Y.Offset
		selected:set("large")
		t.expect(panel.Size.Y.Offset).toBe(before)
		world.engine.heartbeat.fire(0.1)
		t.expect(panel.Size.Y.Offset > before).toBe(true)
		world.gui.ReducedMotionEnabled = true
		t.expect(panel.Size.Y.Offset).toBe(684)
		t.expect(find(world.screen, "KeptContent")).toBe(content)
		world.stop()
	end)

	t.it("fades native tab layers with Compose and reveals an offscreen selected tab", function()
		local selected = Compose.cell("a")
		local world = setup(function(UI)
			return UI.TabView({
				selection = selected,
				placement = "topBar",
				transition = { seconds = 0.2 },
				tabs = {
					{
						id = "a",
						content = function()
							return UI.Button({ Name = "AContent", label = "A" })
						end,
					},
					{
						id = "b",
						content = function()
							return UI.Button({ Name = "BContent", label = "B" })
						end,
					},
				},
			})
		end)
		local bar = find(world.screen, "Tabs")
		bar.AbsoluteSize = world.engine.types.Vector2.new(100, 44)
		local b = find(bar, "b")
		b.AbsolutePosition = world.engine.types.Vector2.new(160, 0)
		b.AbsoluteSize = world.engine.types.Vector2.new(80, 44)
		selected:set("b")
		t.expect(bar.CanvasPosition.X).toBe(140)
		local panel = find(world.screen, "BContent").Parent
		t.expect(panel.ClassName).toBe("CanvasGroup")
		world.engine.heartbeat.fire(0.2)
		t.expect(panel.GroupTransparency).toBe(0)
		selected:set("a")
		t.expect(panel.Interactable).toBe(false)
		world.gui.ReducedMotionEnabled = true
		t.expect(find(world.screen, "AContent").Parent.GroupTransparency).toBe(0)
		world.stop()
	end)

	t.it("clears bound alert errors and turns native page animation off for reduced motion", function()
		local shown, errorValue, page = Compose.cell(true), Compose.cell("Oops"), Compose.cell("a")
		local world = setup(function(UI, Host)
			return Host.Frame({
				UI.Alert({ isPresented = shown, error = errorValue }),
				UI.PageView({
					selection = page,
					pages = {
						{
							id = "a",
							content = function()
								return Host.Frame({})
							end,
						},
						{
							id = "b",
							content = function()
								return Host.Frame({})
							end,
						},
					},
				}),
			})
		end)
		find(world.screen, "ModalBack").Pressed.fire()
		t.expect(errorValue:peek()).toBe(nil)
		world.gui.ReducedMotionEnabled = true
		t.expect(find(world.screen, "PagesLayout").Animated).toBe(false)
		world.stop()
	end)
	t.it("keeps measured callout arrows outside automatic content bounds", function()
		local world = setup(function(UI, Host, engine)
			local anchor = UI.Button({ Name = "Anchor", label = "Anchor" })
			return Host.Frame({
				anchor,
				UI.Callout({
					anchor = anchor,
					edge = "top",
					onRetire = function() end,
					content = function()
						return Host.TextLabel({
							Name = "TipContent",
							Text = "Start from a prompt, then edit it before you send.",
							TextWrapped = true,
							Size = engine.types.UDim2.new(1, 0, 0, 0),
							AutomaticSize = engine.types.Enum.AutomaticSize.Y,
						})
					end,
				}),
			})
		end)
		local V = world.engine.types.Vector2
		world.screen.AbsoluteSize = V.new(960, 720)
		local anchor, panel, arrow =
			find(world.screen, "Anchor"), find(world.screen, "CalloutPanel"), find(world.screen, "Arrow")
		anchor.AbsolutePosition = V.new(160, 560)
		anchor.AbsoluteSize = V.new(240, 44)
		t.expect(panel.AutomaticSize).toBe(world.engine.types.Enum.AutomaticSize.Y)
		t.expect(panel.Size.Y.Scale).toBe(0)
		t.expect(panel.Size.Y.Offset).toBe(0)
		t.expect(arrow:IsDescendantOf(panel)).toBe(false)
		t.expect(arrow.Parent).toBe(panel.Parent)
		t.expect(arrow:HasTag("facet-panel")).toBe(true)
		t.expect(arrow:HasTag("facet-callout")).toBe(true)
		t.expect(arrow.ZIndex < panel.ZIndex).toBe(true)
		for _, height in { 96, 128, 96 } do
			panel.AbsoluteSize = V.new(280, height)
			t.expect(panel.Position.Y.Offset).toBe(560 - height - 8)
			t.expect(arrow.Position.Y.Offset).toBe(547)
		end
		anchor.Visible = false
		t.expect(find(world.screen, "Arrow")).toBe(nil)
		t.expect(find(world.screen, "CalloutPanel")).toBe(nil)
		world.stop()
	end)

	t.it("suspends callout plates with hidden anchors and restores their native arrow", function()
		local retired = 0
		local world = setup(function(UI, Host)
			local anchor = UI.Button({ Name = "Anchor", label = "Anchor" })
			return Host.Frame({
				Name = "Surface",
				anchor,
				UI.Callout({
					anchor = anchor,
					onRetire = function()
						retired += 1
					end,
					content = function()
						return UI.Label({ text = "Tip" })
					end,
				}),
			})
		end)
		t.expect(find(world.screen, "Arrow") ~= nil).toBe(true)
		find(world.screen, "Surface").Visible = false
		t.expect(find(world.screen, "CalloutPanel")).toBe(nil)
		find(world.screen, "Surface").Visible = true
		t.expect(find(world.screen, "Arrow") ~= nil).toBe(true)
		t.expect(retired).toBe(0)
		world.stop()
	end)

	t.it("preserves icon-only names, indicator choices and native target floors", function()
		local value, indicator = Compose.cell("a"), Compose.cell("underline")
		local world = setup(function(UI)
			return UI.Picker({
				selected = value,
				style = "segmented",
				iconOnly = true,
				indicator = indicator,
				options = {
					{ value = "a", label = "Alpha", icon = "settings" },
					{
						value = "b",
						label = "Beta",
						icon = "settings",
					},
				},
			})
		end)
		local a = find(world.screen, "a")
		t.expect(a:GetAttribute("FacetLabel")).toBe("Alpha")
		t.expect(find(a, "LeadingIcon").Image ~= "").toBe(true)
		t.expect(a:FindFirstChildWhichIsA("UISizeConstraint").MinSize.X).toBe(44)
		t.expect(find(a, "SelectionIndicator") ~= nil).toBe(true)
		value:set("b")
		t.expect(find(a, "SelectionIndicator")).toBe(nil)
		t.expect(find(find(world.screen, "b"), "SelectionIndicator") ~= nil).toBe(true)
		indicator:set("none")
		t.expect(find(world.screen, "SelectionIndicator")).toBe(nil)
		world.stop()
	end)

	t.it("renders disclosure appearances and collapsible summaries with native assets and close policy", function()
		local expanded, image = Compose.cell(false), Compose.cell("rbxassetid://1")
		local world = setup(function(UI, Host)
			return Host.Frame({
				UI.DisclosureGroup({
					Name = "Disclosure",
					label = "Details",
					appearance = "divided",
					chevronPosition = "leading",
					expanded = Compose.cell(true),
					content = function()
						return UI.Label({ text = "Details" })
					end,
				}),
				UI.CollapsibleView({
					Name = "Summary",
					label = "Summary",
					image = image,
					expanded = expanded,
					dismissButton = false,
					content = function()
						return UI.Button({ Name = "DetailsAction", label = "Details" })
					end,
				}),
			})
		end)
		t.expect(find(find(world.screen, "Disclosure"), "LeadingIcon") ~= nil).toBe(true)
		t.expect(find(find(world.screen, "Disclosure"), "Divider") ~= nil).toBe(true)
		local summary = find(world.screen, "Summary")
		image:set("rbxassetid://2")
		t.expect(find(summary, "Image").Image).toBe("rbxassetid://2")
		summary.Activated.fire()
		t.expect(find(world.screen, "Close")).toBe(nil)
		world.input.PreferredInput = world.engine.types.Enum.PreferredInput.Gamepad
		t.expect(find(world.screen, "Close") ~= nil).toBe(true)
		find(world.screen, "Close").Activated.fire()
		t.expect(expanded:peek()).toBe(false)
		t.expect(find(world.screen, "DetailsAction")).toBe(nil)
		t.expect(find(world.screen, "Summary")).toBe(summary)
		world.stop()
	end)

	t.it("renders sidebar sections and collapsed tab destinations through the shared menu", function()
		local selected = Compose.cell("a")
		local world = setup(function(UI, Host)
			return Host.Frame({
				UI.TabView({
					Name = "Sidebar",
					selection = selected,
					placement = "sidebar",
					sections = { { id = "s", label = "Section" } },
					tabs = {
						{
							id = "a",
							section = "s",
							content = function()
								return Host.Frame({})
							end,
						},
						{
							id = "b",
							section = "s",
							content = function()
								return Host.Frame({})
							end,
						},
					},
				}),
				UI.TabView({
					Name = "Collapsed",
					selection = selected,
					style = "collapsible",
					tabs = {
						{
							id = "a",
							label = "Alpha",
							content = function()
								return Host.Frame({})
							end,
						},
						{
							id = "b",
							label = "Beta",
							content = function()
								return Host.Frame({})
							end,
						},
					},
				}),
			})
		end)
		t.expect(find(find(world.screen, "Sidebar"), "Section").Text).toBe("Section")
		local collapsed = find(world.screen, "Collapsed")
		t.expect(find(collapsed, "Tabs").Visible).toBe(false)
		find(find(collapsed, "TabsMenu"), "Trigger").Activated.fire()
		find(find(world.screen, "MenuPanel"), "b").Activated.fire()
		t.expect(selected:peek()).toBe("b")
		t.expect(find(find(collapsed, "TabsMenu"), "Trigger").Text).toBe("Beta")
		world.stop()
	end)

	t.it("closes menu and picker presentations when native ancestors become unavailable", function()
		local selected, opened = Compose.cell("a"), Compose.cell(false)
		local world = setup(function(UI, Host)
			return Host.Frame({
				Name = "Surface",
				UI.Picker({
					selected = selected,
					style = "menu",
					isPresented = opened,
					options = { { value = "a", label = "Alpha" }, { value = "b", label = "Beta" } },
				}),
			})
		end)
		opened:set(true)
		local row = find(find(world.screen, "MenuPanel"), "b")
		find(world.screen, "Surface").Interactable = false
		t.expect(opened:peek()).toBe(false)
		t.expect(find(world.screen, "MenuPanel")).toBe(nil)
		row.Activated.fire()
		t.expect(selected:peek()).toBe("a")
		find(world.screen, "Surface").Interactable = true
		find(world.screen, "Trigger").Activated.fire()
		t.expect(opened:peek()).toBe(true)
		world.stop()
	end)

	t.it("keeps panel art outside native layout and exposes alert artwork", function()
		local package = require("../src/ui/themes").neutralPackage()
		package.assets.panel = { content = "rbxassetid://42" }
		package.chrome.panel = { kind = "layered", layers = { { kind = "fill", asset = "panel" } } }
		local alert, sheet = Compose.cell(true), Compose.cell(false)
		local world = setup(function(UI, Host)
			return Host.Frame({
				UI.Alert({ isPresented = alert, severity = "critical", title = "Danger" }),
				UI.Sheet({
					isPresented = sheet,
					detent = Compose.cell("medium"),
					content = function()
						return Host.Frame({})
					end,
				}),
			})
		end, { theme = package })
		local panel = find(world.screen, "AlertPanel")
		t.expect(panel.BackgroundTransparency).toBe(0)
		t.expect(panel:HasTag("facet-panel")).toBe(true)
		t.expect(find(panel, "AlertIcon").Image ~= "").toBe(true)
		local alertArt = find(panel, "panel1")
		t.expect(alertArt.Image).toBe("rbxassetid://42")
		alert:set(false)
		sheet:set(true)
		panel = find(world.screen, "SheetPanel")
		t.expect(panel.BackgroundTransparency).toBe(0)
		t.expect(alertArt.isDestroyed()).toBe(true)
		local skin, boundary = find(panel, "Skin"), find(panel, "SkinBoundary")
		local bounds, art = skin.Parent, find(skin, "panel1")
		t.expect(art.Image).toBe("rbxassetid://42")
		t.expect(boundary.Parent:IsA("GuiObject")).toBe(false)
		t.expect(boundary.Parent.Parent).toBe(panel)
		t.expect(bounds.Parent).toBe(boundary)
		t.expect(boundary.AutomaticSize).toBe(world.engine.types.Enum.AutomaticSize.None)
		t.expect(boundary.Size.X.Offset).toBe(1)
		t.expect(boundary.Size.Y.Offset).toBe(1)
		t.expect(boundary.Position.X.Scale).toBe(1)
		t.expect(boundary.Position.Y.Scale).toBe(1)
		t.expect(bounds.AnchorPoint).toBe(world.engine.types.Vector2.new(1, 1))
		panel.AbsoluteSize = world.engine.types.Vector2.new(360, 240)
		boundary.AbsoluteSize = world.engine.types.Vector2.new(2, 2)
		t.expect(bounds.Size.X.Offset).toBe(180)
		t.expect(bounds.Size.Y.Offset).toBe(120)
		panel.AbsoluteSize = world.engine.types.Vector2.new(200, 120)
		t.expect(bounds.Size.X.Offset).toBe(100)
		t.expect(bounds.Size.Y.Offset).toBe(60)
		world.stop()
		t.expect(art.isDestroyed()).toBe(true)
		t.expect(boundary.isDestroyed()).toBe(true)
	end)

	t.it("animates alerts from native sources and reclaims interrupted Compose presence", function()
		local shown = Compose.cell(false)
		local world = setup(function(UI, Host)
			local source = UI.Button({ Name = "Source", label = "Open" })
			return Host.Frame({
				source,
				UI.Alert({ isPresented = shown, title = "Detail", transition = { source = source, seconds = 0.2 } }),
			})
		end)
		local source = find(world.screen, "Source")
		source.AbsolutePosition = world.engine.types.Vector2.new(20, 30)
		source.AbsoluteSize = world.engine.types.Vector2.new(100, 60)
		shown:set(true)
		local panel = find(world.screen, "AlertPanel")
		t.expect(panel.Position.X.Offset).toBe(70)
		t.expect(panel.Position.Y.Offset).toBe(60)
		t.expect(panel.GroupTransparency).toBe(1)
		find(world.screen, "AlertModal").AbsoluteSize = world.engine.types.Vector2.new(800, 600)
		world.engine.heartbeat.fire(0.2)
		t.expect(panel.Position.X.Offset).toBe(400)
		t.expect(find(panel, "PresentationScale").Scale).toBe(1)
		shown:set(false)
		world.engine.heartbeat.fire(0.1)
		t.expect(find(world.screen, "AlertPanel")).toBe(panel)
		shown:set(true)
		t.expect(find(world.screen, "AlertPanel")).toBe(panel)
		world.engine.heartbeat.fire(0.2)
		t.expect(panel.GroupTransparency).toBe(0)
		shown:set(false)
		world.engine.heartbeat.fire(0.2)
		t.expect(find(world.screen, "AlertPanel")).toBe(nil)
		world.stop()
	end)

	t.it("expands a source rectangle into full screen and reverses the same Compose-owned snapshot", function()
		local shown = Compose.cell(false)
		local world = setup(function(UI, Host, engine)
			local camera = Host.Camera({ Name = "PreviewCamera" })
			local externalCamera = Host.Camera({ Name = "ExternalCamera" })
			local source = Host.Frame({
				Name = "Card",
				Host.UICorner({ CornerRadius = engine.types.UDim.new(0, 12) }),
				Host.ViewportFrame({
					Name = "Scene",
					CurrentCamera = Compose.static(camera),
					Host.Camera({ Name = "PreviewCamera", Archivable = false }),
					camera,
					Host.WorldModel({ Name = "World" }),
				}),
				Host.ViewportFrame({ Name = "OtherScene", CurrentCamera = Compose.static(externalCamera) }),
				UI.Button({ Name = "Open", label = "Open" }),
				Host.UIDragDetector({ Name = "CardDrag" }),
			})
			return Host.Frame({
				source,
				externalCamera,
				UI.Alert({
					isPresented = shown,
					title = "Detail",
					surface = "fullScreen",
					transition = { source = source, seconds = 0.4 },
				}),
			})
		end)
		local V2 = world.engine.types.Vector2
		local source = find(world.screen, "Card")
		local originalParent = source.Parent
		source.AbsolutePosition = V2.new(20, 30)
		source.AbsoluteSize = V2.new(120, 80)
		shown:set(true)
		local panel = find(world.screen, "AlertPanel")
		local modal = find(world.screen, "AlertModal")
		modal.AbsolutePosition = V2.new(10, 10)
		modal.AbsoluteSize = V2.new(800, 600)
		local snapshot = find(panel, "SourceSnapshot")
		t.expect(snapshot ~= nil).toBe(true)
		t.expect(snapshot == source).toBe(false)
		t.expect(snapshot.Interactable).toBe(false)
		t.expect(find(snapshot, "Open").Selectable).toBe(false)
		t.expect(find(snapshot, "CardDrag").Enabled).toBe(false)
		t.expect(find(snapshot, "Scene").CurrentCamera).toBe(find(snapshot, "PreviewCamera"))
		t.expect(find(snapshot, "Scene").CurrentCamera == find(source, "Scene").CurrentCamera).toBe(false)
		t.expect(find(snapshot, "OtherScene").CurrentCamera).toBe(find(world.screen, "ExternalCamera"))
		t.expect(find(snapshot, "ExternalCamera")).toBe(nil)
		t.expect(panel.Size.X.Offset).toBe(120)
		t.expect(panel.Size.Y.Offset).toBe(80)
		t.expect(panel.Position.X.Offset).toBe(10)
		t.expect(panel.Position.Y.Offset).toBe(20)
		t.expect(panel.GroupTransparency).toBe(0)
		t.expect(find(panel, "AlertLayout").GroupTransparency).toBe(1)
		world.engine.heartbeat.fire(0.1)
		local width, height = panel.Size.X.Offset, panel.Size.Y.Offset
		t.expect(width > 120 and width < 800).toBe(true)
		t.expect(height > 80 and height < 600).toBe(true)
		t.expect(math.abs((width - 120) / 680 - (height - 80) / 520) < 0.0001).toBe(true)
		shown:set(false)
		t.expect(panel.Size.X.Offset).toBe(width)
		world.engine.heartbeat.fire(0.05)
		t.expect(panel.Size.X.Offset < width).toBe(true)
		local returningWidth = panel.Size.X.Offset
		shown:set(true)
		t.expect(find(world.screen, "AlertPanel")).toBe(panel)
		t.expect(panel.Size.X.Offset).toBe(returningWidth)
		world.engine.heartbeat.fire(0.4)
		t.expect(panel.Position.X.Offset).toBe(0)
		t.expect(panel.Position.Y.Offset).toBe(0)
		t.expect(panel.Size.X.Offset).toBe(800)
		t.expect(panel.Size.Y.Offset).toBe(600)
		t.expect(find(panel, "SourcePreview").Visible).toBe(false)
		t.expect(source.Parent).toBe(originalParent)
		shown:set(false)
		world.engine.heartbeat.fire(0.4)
		t.expect(snapshot.isDestroyed()).toBe(true)
		t.expect(find(world.screen, "AlertPanel")).toBe(nil)
		t.expect(source.Parent).toBe(originalParent)
		t.expect(source.isDestroyed()).toBe(false)
		t.expect(find(source, "Scene").CurrentCamera.Parent).toBe(find(source, "Scene"))
		t.expect(find(world.screen, "ExternalCamera").isDestroyed()).toBe(false)
		world.stop()
	end)

	t.it("makes full-screen source transitions immediate under native reduced motion", function()
		local shown = Compose.cell(false)
		local world = setup(function(UI, Host, engine, gui)
			gui.ReducedMotionEnabled = true
			local source = UI.Button({ Name = "Card", label = "Card" })
			return Host.Frame({
				source,
				UI.Alert({
					isPresented = shown,
					surface = "fullScreen",
					transition = { source = source, seconds = 0.4 },
				}),
			})
		end)
		shown:set(true)
		local panel = find(world.screen, "AlertPanel")
		find(world.screen, "AlertModal").AbsoluteSize = world.engine.types.Vector2.new(390, 720)
		t.expect(panel.Size.X.Offset).toBe(390)
		t.expect(panel.Size.Y.Offset).toBe(720)
		t.expect(panel.Position.X.Offset).toBe(0)
		t.expect(find(panel, "AlertLayout").GroupTransparency).toBe(0)
		t.expect(find(panel, "SourcePreview").Visible).toBe(false)
		shown:set(false)
		t.expect(find(world.screen, "AlertPanel")).toBe(nil)
		world.stop()
	end)

	t.it("resets the mounted callout showcase without replacing anchor identities", function()
		local built
		local world = setup(function(UI, Host, engine)
			built = require("../examples/gallery/scenarios/callout").build({
				UI = UI,
				Host = Host,
				Compose = Compose,
				types = engine.types,
			})
			return built.screen()
		end)
		local anchor = find(world.screen, "Plus")
		built.steps.show()
		t.expect(built.report().tip.state).toBe("showing")
		find(world.screen, "Dismiss").Activated.fire()
		t.expect(built.report().tip.state).toBe("retired")
		built.steps.reset()
		t.expect(find(world.screen, "Plus")).toBe(anchor)
		built.steps.show()
		t.expect(built.report().tip.state).toBe("showing")
		world.stop()
	end)
	t.it("keeps filtered multiple selections and reactive row descriptions through source replacement", function()
		local selected, query, opened = Compose.cell({ a = true }), Compose.cell(""), Compose.cell(true)
		local options =
			Compose.cell({ { value = "a", label = "Alpha" }, { value = "b", label = "Beta", enabled = false } })
		local world = setup(function(UI)
			return UI.Picker({
				selected = selected,
				multiple = true,
				required = true,
				style = "menu",
				options = options,
				query = query,
				isPresented = opened,
			})
		end)
		local first = find(find(world.screen, "MenuPanel"), "a")
		first.Activated.fire()
		t.expect(selected:peek().a).toBe(true)
		query:set("missing")
		t.expect(selected:peek().a).toBe(true)
		options:set({ { value = "a", label = "Alpha", description = "Added" }, { value = "b", label = "Beta" } })
		query:set("")
		local row = find(find(world.screen, "MenuPanel"), "a")
		t.expect(find(row, "Description").Text).toBe("Added")
		options:set({ { value = "a", label = "Alpha", description = "Changed" }, { value = "b", label = "Beta" } })
		t.expect(find(find(world.screen, "MenuPanel"), "a")).toBe(row)
		t.expect(find(row, "Description").Text).toBe("Changed")
		find(find(world.screen, "MenuPanel"), "b").Activated.fire()
		t.expect(selected:peek().b).toBe(true)
		t.expect(opened:peek()).toBe(true)
		options:set({ { value = "b", label = "Coast" } })
		t.expect(selected:peek().a).toBe(true)
		t.expect(find(world.screen, "Trigger").Text).toBe("Coast")
		world.stop()
	end)
	t.it("forgives near-miss backdrop taps and closes only the top native modal", function()
		local outer, inner = Compose.cell(true), Compose.cell(false)
		local world = setup(function(UI, Host)
			return Host.Frame({
				UI.Sheet({
					isPresented = outer,
					detent = Compose.cell("medium"),
					content = function()
						return UI.Button({ label = "Outer" })
					end,
				}),
				UI.Sheet({
					isPresented = inner,
					detent = Compose.cell("medium"),
					content = function()
						return UI.Button({ label = "Inner" })
					end,
				}),
			})
		end)
		local panel = find(world.screen, "SheetPanel")
		panel.AbsolutePosition = world.engine.types.Vector2.new(100, 100)
		panel.AbsoluteSize = world.engine.types.Vector2.new(200, 200)
		local backdrop = find(world.screen, "DismissOutside")
		backdrop.Activated.fire({ Position = world.engine.types.Vector2.new(90, 150) })
		t.expect(outer:peek()).toBe(true)
		inner:set(true)
		backdrop.Activated.fire({ Position = world.engine.types.Vector2.new(50, 150) })
		t.expect(outer:peek()).toBe(true)
		local top
		for _, node in world.screen:GetDescendants() do
			if node.Name == "DismissOutside" and node ~= backdrop then
				top = node
			end
		end
		t.expect(top ~= nil).toBe(true)
		top.Activated.fire({ Position = world.engine.types.Vector2.new(0, 0) })
		t.expect(inner:peek()).toBe(false)
		t.expect(outer:peek()).toBe(true)
		backdrop.Activated.fire({ Position = world.engine.types.Vector2.new(50, 150) })
		t.expect(outer:peek()).toBe(false)
		world.stop()
	end)
end)
