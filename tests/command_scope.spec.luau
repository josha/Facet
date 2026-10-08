--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local Commands = require("../src/ui/command_types")
type Scope = Commands.CommandScope<number>
type Spec = Commands.CommandSpec<number>
return function(harness: Verify.Harness)
	harness:suite("command scope", function()
		harness:case("F-024 one board command chooses one duplicate letter and text entry wins", function()
			local engine = engineLib.new()
			local runtime = Facet.Roblox.createRuntime(engine)
			local input, gui = engine.new("UserInputService"), engine.new("GuiService")
			local focused: TextBox? = nil
			input.GetFocusedTextBox = function()
				return focused
			end
			local UI = Facet.controls(runtime, { types = engine.types, userInputService = input, guiService = gui })
			local Host = (runtime.constructors :: unknown) :: typeof(require("../tools/typecheck/aliases").RobloxHost)
			local scope: Scope?
			local first: GuiObject?, second: GuiObject?, chat: TextBox?
			local letters, placed, returned = { "A", "A" }, 0, 0
			local stop = runtime.mount(function()
				local a = UI.Button "First" { label = "First cell" }
				local b = UI.Button "Second" { label = "Second cell" }
				local text = UI.TextInput "Chat" { value = Facet.Compose.cell(""), placeholder = "Chat" }
				local children: { GuiObject } = { a, b, text }
				local root = Host.Frame(children)
				first, second = a, b
				chat = if text:IsA("TextBox") then text else text:FindFirstChildWhichIsA("TextBox", true) :: TextBox?
				local targets: { Facet.CommandTarget<number> } = { { key = 1, node = a }, { key = 2, node = b } }
				local spec: Spec = {
					targets = targets,
					commands = {
						{
							id = "Letter",
							keys = { "A", "ButtonX" },
							onInvoke = function(key: number)
								Verify.expect(key):toBe(1)
								table.remove(letters, 1)
								placed += 1
							end,
						},
						{
							id = "Recall",
							keys = { "Backspace", "ButtonY" },
							onInvoke = function(key: number)
								Verify.expect(key):toBe(2)
								table.insert(letters, "A")
								returned += 1
							end,
						},
					},
				}
				scope = UI.commandScope(root, spec)
				return root
			end, engine.new("ScreenGui"))
			local commands = assert(scope)
			Verify.expect(commands.focus(1)):toBe(true)
			Verify.expect(gui.SelectedObject):toBe(first)
			local press = (commands.actions.Letter.Pressed :: unknown) :: { Fire: (unknown) -> () }
			local release = (commands.actions.Letter.Released :: unknown) :: { Fire: (unknown) -> () }
			press:Fire()
			release:Fire()
			Verify.expect(placed):toBe(1)
			Verify.expect(#letters):toBe(1)
			focused = chat
			input.TextBoxFocused:Fire(chat)
			Verify.expect(commands.actions.Letter.Enabled):toBe(false)
			press:Fire()
			release:Fire()
			Verify.expect(placed):toBe(1)
			focused = nil
			input.TextBoxFocusReleased:Fire(chat)
			gui.SelectedObject = second
			Verify.expect(commands.current:peek()):toBe(2)
			local recall = (commands.actions.Recall.Pressed :: unknown) :: { Fire: (unknown) -> () }
			recall:Fire()
			Verify.expect(returned):toBe(1)
			Verify.expect(#letters):toBe(2)
			commands.clear()
			Verify.expect(gui.SelectedObject):toBe(nil)
			press:Fire()
			Verify.expect(placed):toBe(1)
			Verify.expect(commands.focus(99)):toBe(false)
			local root = assert(first).Parent :: GuiObject
			local parent = root.Parent
			root.Parent = nil
			Verify.expect(commands.focus(1)):toBe(false)
			Verify.expect(commands.current:peek()):toBe(nil)
			root.Parent = parent
			stop()
			Verify.expect(commands.focus(1)):toBe(false)
			runtime:dispose()
		end)
		harness:case("F-024 nested scope wins, pointer focus follows targets and disposal releases commands", function()
			local engine = engineLib.new()
			local runtime = Facet.Roblox.createRuntime(engine)
			local input, gui = engine.new("UserInputService"), engine.new("GuiService")
			input.GetFocusedTextBox = function()
				return nil
			end
			local UI = Facet.controls(runtime, { types = engine.types, userInputService = input, guiService = gui })
			local Host = (runtime.constructors :: unknown) :: typeof(require("../tools/typecheck/aliases").RobloxHost)
			local parent: Facet.CommandScope<number>?
			local child: Facet.CommandScope<number>?
			local enabled = Facet.Compose.cell(true)
			local targets = Facet.Compose.cell({} :: { Facet.CommandTarget<number> })
			local target: GuiObject?
			local outerCalls, innerCalls = 0, 0
			local stop = runtime.mount(function()
				local button = UI.Button "Cell" { label = "Cell" }
				local inside = Host.Frame { button }
				local root = Host.Frame { inside }
				target = button
				targets:set({ { key = 7, node = button } })
				parent = UI.commandScope(root, {
					targets = { { key = 1, node = inside } },
					commands = {
						{
							id = "Outer",
							keys = { "A", "Escape" },
							onInvoke = function()
								outerCalls += 1
							end,
						},
					},
				})
				child = UI.commandScope(inside, {
					targets = targets,
					enabled = enabled,
					commands = {
						{
							id = "Inner",
							keys = { "A", "Escape" },
							onInvoke = function(key: number)
								Verify.expect(key):toBe(7)
								innerCalls += 1
							end,
						},
					},
				})
				return root
			end, engine.new("ScreenGui"))
			local outer, inner, cell = assert(parent), assert(child), assert(target)
			local event = (
				{
					UserInputType = engine.types.Enum.UserInputType.Touch,
					KeyCode = engine.types.Enum.KeyCode.A,
				} :: unknown
			) :: InputObject
			local began = (cell.InputBegan :: unknown) :: { Fire: (unknown, InputObject) -> () }
			began:Fire(event)
			Verify.expect(gui.SelectedObject):toBe(cell)
			Verify.expect(inner.current:peek()):toBe(7)
			Verify.expect(outer.actions.Outer.Enabled):toBe(false)
			local outerPress = (outer.actions.Outer.Pressed :: unknown) :: { Fire: (unknown) -> () }
			local innerPress = (inner.actions.Inner.Pressed :: unknown) :: { Fire: (unknown) -> () }
			outerPress:Fire()
			innerPress:Fire()
			Verify.expect(outerCalls):toBe(0)
			Verify.expect(innerCalls):toBe(1)
			local innerRelease = (inner.actions.Inner.Released :: unknown) :: { Fire: (unknown) -> () }
			innerRelease:Fire()
			input.InputBegan:Fire({ KeyCode = engine.types.Enum.KeyCode.Escape })
			input.InputEnded:Fire({ KeyCode = engine.types.Enum.KeyCode.Escape })
			Verify.expect(outerCalls):toBe(0)
			Verify.expect(innerCalls):toBe(2)
			enabled:set(false)
			Verify.expect(outer.actions.Outer.Enabled):toBe(true)
			Verify.expect(inner.focus(7)):toBe(false)
			cell.Interactable = false
			Verify.expect(outer.focus(1)):toBe(false)
			cell.Interactable = true
			enabled:set(true)
			targets:set({})
			Verify.expect(inner.current:peek()):toBe(nil)
			Verify.expect(inner.focus(7)):toBe(false)
			targets:set({ { key = 7, node = cell } })
			Verify.expect(inner.current:peek()):toBe(7)
			stop()
			Verify.expect(inner.current:peek()):toBe(nil)
			Verify.expect(engineLib.connections(input.TextBoxFocused)):toBe(0)
			Verify.expect(engineLib.connections(input.TextBoxFocusReleased)):toBe(0)
			Verify.expect(engineLib.connections(cell.InputBegan)):toBe(0)
			runtime:dispose()
		end)
		harness:case("F-024 modal Escape wins over the board command", function()
			local engine = engineLib.new()
			local runtime = Facet.Roblox.createRuntime(engine)
			local input, gui = engine.new("UserInputService"), engine.new("GuiService")
			input.GetFocusedTextBox = function()
				return nil
			end
			local UI = Facet.controls(runtime, { types = engine.types, userInputService = input, guiService = gui })
			local Host = (runtime.constructors :: unknown) :: typeof(require("../tools/typecheck/aliases").RobloxHost)
			local shown = Facet.Compose.cell(false)
			local scope: Facet.CommandScope<number>?
			local calls, dismissed = 0, 0
			local stop = runtime.mount(function()
				local cell = UI.Button { label = "Cell" }
				local dialogSpec: Facet.DialogSpec = {
					isPresented = shown,
					title = "Pause",
					onPresentedChange = function(value: boolean)
						shown:set(value)
					end,
					onDismiss = function(_reason: "close" | "outside" | "cancel" | "action")
						dismissed += 1
					end,
					content = function(): Instance
						return UI.Button { label = "Inside" }
					end,
				}
				local dialog = UI.Dialog(dialogSpec)
				local children: { GuiObject } = { cell, dialog }
				local root = Host.Frame(children)
				local targets: { Facet.CommandTarget<number> } = { { key = 1, node = cell } }
				local spec: Facet.CommandSpec<number> = {
					targets = targets,
					commands = {
						{
							id = "Cancel",
							keys = { "Escape" },
							onInvoke = function()
								calls += 1
							end,
						},
					},
				}
				scope = UI.commandScope(root, spec)
				return root
			end, engine.new("ScreenGui"))
			Verify.expect(assert(scope).focus(1)):toBe(true)
			Verify.expect(
				assert(scope).actions.Cancel.Parent and (assert(scope).actions.Cancel.Parent :: InputContext).Priority
			)
				:toBe(1500)
			shown:set(true)
			input.InputBegan:Fire({ KeyCode = engine.types.Enum.KeyCode.Escape })
			input.InputEnded:Fire({ KeyCode = engine.types.Enum.KeyCode.Escape })
			Verify.expect(calls):toBe(0)
			Verify.expect(dismissed):toBe(1)
			Verify.expect(shown:peek()):toBe(false)
			stop()
			runtime:dispose()
		end)

		harness:case("F-024 duplicate command keys are rejected", function()
			local engine = engineLib.new()
			local runtime = Facet.Roblox.createRuntime(engine)
			local UI = Facet.controls(runtime, { types = engine.types })
			local Host = (runtime.constructors :: unknown) :: typeof(require("../tools/typecheck/aliases").RobloxHost)
			local ok, message = pcall(function()
				runtime.mount(function()
					local root = Host.Frame {}
					UI.commandScope(root, {
						targets = {},
						commands = {
							{ id = "First", keys = { "A" }, onInvoke = function() end },
							{ id = "Second", keys = { "A" }, onInvoke = function() end },
						},
					})
					return root
				end, engine.new("ScreenGui"))
			end)
			Verify.expect(ok):toBe(false)
			Verify.expect(string.find(tostring(message), "keys belong to one command", 1, true) ~= nil):toBe(true)
			runtime:dispose()
		end)
	end)
end
