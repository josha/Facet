--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	local FixtureNavigationTypes = require("../src/ui/navigation_types")

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local Compose: ComposeModule = Facet.Compose

	type World = {
		engine: any,
		runtime: any,
		UI: any,
		Host: any,
		gui: any,
		input: any,
		root: any,
		node: any,
		stop: () -> (),
	}

	local function setup(build: (any, any, any, any) -> any, options: { [string]: any }?): World
		local engine: any = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui = engine.new("GuiService")
		local input = engine.new("UserInputService")
		input.GetFocusedTextBox = function()
			return nil
		end
		input.IsKeyDown = function()
			return false
		end
		local root = engine.new("ScreenGui")
		local config: { [string]: any } = {
			types = engine.types,
			guiService = gui,
			services = { GuiService = gui, UserInputService = input },
			inputParent = root,
			motionLevel = "none",
		}
		for key, value in (options or {}) :: { [string]: any } do
			config[key] = if type(value) == "function" and key ~= "onError" then value(engine) else value
		end
		local UI = Facet.controls(runtime, config :: any)
		local Host = (runtime.constructors :: unknown) :: RobloxHost
		local stop, node: any = runtime.mount(function()
			return build(UI, Host, engine, runtime)
		end, root)
		return {
			engine = engine,
			runtime = runtime,
			UI = UI,
			Host = Host,
			gui = gui,
			input = input,
			root = root,
			node = node,
			stop = function()
				stop()
				runtime:dispose()
			end,
		}
	end

	local function find(root: any, name: string): any
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

	local function action(root: any, name: string): any
		for _, child in root:GetDescendants() do
			if child:IsA("InputContext") and child.Name == "Facet" .. name and child.Enabled then
				return child:FindFirstChild(name)
			end
		end
		return nil
	end

	local function deliver(root: any, key: any): { string }
		local contexts = {}
		for _, child in root:GetDescendants() do
			if child:IsA("InputContext") and child.Enabled then
				table.insert(contexts, child)
			end
		end
		table.sort(contexts, function(a, b)
			return a.Priority > b.Priority
		end)
		local received = {}
		for _, context in contexts do
			local matched = false
			for _, inputAction in context:GetChildren() do
				if inputAction:IsA("InputAction") then
					for _, binding in inputAction:GetChildren() do
						if binding:IsA("InputBinding") and binding.KeyCode == key then
							matched = true
							table.insert(received, context.Name)
							inputAction.Pressed:Fire()
							break
						end
					end
				end
			end
			if matched and context.Sink then
				break
			end
		end
		return received
	end

	local function probe(Host: any, engine: any, onPressed: () -> ()): any
		return Host.InputContext "Probe" {
			Priority = 3000,
			Sink = false,
			Enabled = true,
			Host.InputAction "ProbeNavigate" {
				Pressed = onPressed,
				Host.InputBinding({ KeyCode = engine.types.Enum.KeyCode.DPadDown }) :: unknown,
				Host.InputBinding({ KeyCode = engine.types.Enum.KeyCode.Down }),
			},
		}
	end

	local function pointer(engine: any, kind: string): any
		local E = engine.types.Enum
		return {
			UserInputType = if kind == "gamepad"
				then E.UserInputType.Gamepad1
				elseif kind == "touch" then E.UserInputType.Touch
				else E.UserInputType.MouseButton1,
			KeyCode = if kind == "gamepad" then E.KeyCode.ButtonA else E.KeyCode:FromValue(0),
		}
	end

	local function galleryContext(): (any, any, any)
		local engine = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local viewport = Compose.cell({ width = 1280, height = 720 })
		local target = engine.new("Folder")
		local guiService = engine.new("GuiService")
		local input = engine.new("UserInputService")
		input.GetFocusedTextBox = function()
			return nil
		end
		local ctx = {
			Facet = Facet,
			Compose = Compose,
			runtime = runtime,
			Host = (runtime.constructors :: unknown) :: RobloxHost,
			types = engine.types,
			viewport = viewport,
			inputTarget = target,
			worldTarget = engine.new("Folder"),
			guiService = guiService,
			runService = { Heartbeat = engine.heartbeat },
			UI = Facet.controls(
				runtime,
				{
					types = engine.types,
					viewport = viewport,
					guiService = guiService,
					services = { GuiService = guiService, UserInputService = input },
					inputParent = target,
					motionLevel = "none",
				} :: any
			),
		}
		return ctx, engine, target
	end

	local function mountGallery(name: string, kind: string?): (any, any, () -> (), any)
		local ctx, _, target = galleryContext()
		local built
		local folder = if kind == "example" then "examples/" else "scenarios/"
		local stop, node = ctx.runtime.mount(function()
			built = (require :: any)("../examples/gallery/" .. folder .. name).build(ctx)
			if built.dispose then
				Compose.cleanup(built.dispose)
			end
			return ctx.Host.ScreenGui "DemoScreen" { built.screen() }
		end, target)
		return built, node, function()
			stop()
			ctx.runtime:dispose()
		end, ctx
	end

	verifyHarness:suite("native parity weaker actions", function()
		verifyHarness:case(
			"shows the owner value and placeholder in a native TextBox and edits without optional services",
			{
				id = "native_parity_weaker_actions::native parity weaker actions::shows the owner value and placeholder in a native TextBox and edits without optional services",
				run = function()
					local value, placeholder = Compose.cell("Ada"), "Your name"
					local world = setup(function(UI)
						return UI.TextInput "Name" { value = value, placeholder = placeholder }
					end)
					local field = find(world.node, "Name")
					Verify.expect(field.ClassName):toBe("TextBox")
					Verify.expect(field.Text):toBe("Ada")
					Verify.expect(field.PlaceholderText):toBe("Your name")
					value:set("")
					Verify.expect(field.Text):toBe("")
					Verify.expect(field.PlaceholderText):toBe("Your name")
					world.stop()
					local engine: any = engineLib.new()
					local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
					local UI = Facet.controls(runtime, { types = engine.types } :: any)
					local text, commits = Compose.cell(""), {}
					local stop, bare: any = runtime.mount(function()
						return UI.TextInput "Bare" {
							value = text,
							placeholder = "Type here",
							onCommit = function(committed: string, reason: "submit" | "focusLost")
								table.insert(commits, { committed, reason })
							end,
						}
					end, engine.new("ScreenGui"))
					Verify.expect(bare.PlaceholderText):toBe("Type here")
					bare:CaptureFocus()
					bare.Text = "abc"
					Verify.expect((text:peek())):toBe("abc")
					bare:ReleaseFocus(true)
					Verify.expect(#commits):toBe(1)
					Verify.expect(commits[1][1]):toBe("abc")
					Verify.expect(commits[1][2]):toBe("submit")
					stop()
					runtime:dispose()
				end,
			}
		)

		verifyHarness:case(
			"enters editing on native focus, flows typed text to onChange and names both commit reasons",
			{
				id = "native_parity_weaker_actions::native parity weaker actions::enters editing on native focus, flows typed text to onChange and names both commit reasons",
				run = function()
					local value, changes, commits = Compose.cell(""), {}, {}
					local world = setup(function(UI)
						return UI.TextInput "Name" {
							value = value,
							onChange = function(text)
								value:set(text)
								table.insert(changes, text)
							end,
							onCommit = function(text, reason)
								table.insert(commits, { text, reason })
							end,
						}
					end)
					local field = find(world.node, "Name")
					Verify.expect((action(world.root, "TextEditing"))):toBe(nil)
					field:CaptureFocus()
					Verify.expect(action(world.root, "TextEditing") ~= nil):toBe(true)
					for _, text in { "a", "ab", "abc" } do
						field.Text = text
					end
					Verify.expect((value:peek())):toBe("abc")
					Verify.expect(#changes):toBe(3)
					Verify.expect(changes[1]):toBe("a")
					Verify.expect(changes[3]):toBe("abc")
					Verify.expect(#commits):toBe(0)
					field:ReleaseFocus(true)
					Verify.expect(commits[1][1]):toBe("abc")
					Verify.expect(commits[1][2]):toBe("submit")
					Verify.expect((action(world.root, "TextEditing"))):toBe(nil)
					field:CaptureFocus()
					field.Text = "abcd"
					field:ReleaseFocus(false)
					Verify.expect(#commits):toBe(2)
					Verify.expect(commits[2][1]):toBe("abcd")
					Verify.expect(commits[2][2]):toBe("focusLost")
					Verify.expect((action(world.root, "TextEditing"))):toBe(nil)
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"keeps onChange and onCommit distinct, clamps a pasted append and reconciles an over-long commit",
			{
				id = "native_parity_weaker_actions::native parity weaker actions::keeps onChange and onCommit distinct, clamps a pasted append and reconciles an over-long commit",
				run = function()
					local value, changes, commits = Compose.cell("ab"), 0, {}
					local world = setup(function(UI)
						return UI.TextInput "Name" {
							value = value,
							maxLength = 5,
							onChange = function(text)
								value:set(text)
								changes += 1
							end,
							onCommit = function(text)
								table.insert(commits, text)
							end,
						}
					end)
					local field = find(world.node, "Name")
					field:CaptureFocus()
					field.Text = "abcdefgh"
					Verify.expect((value:peek())):toBe("abcde")
					Verify.expect(field.Text):toBe("abcde")
					Verify.expect(changes):toBe(1)
					Verify.expect(#commits):toBe(0)
					field.Text = "abcdeXYZ"
					Verify.expect((value:peek())):toBe("abcde")
					Verify.expect(field.Text):toBe("abcde")
					Verify.expect(changes):toBe(1)
					field:ReleaseFocus(true)
					Verify.expect(#commits):toBe(1)
					Verify.expect(commits[1]):toBe("abcde")
					world.stop()
					local upper, edits = Compose.cell(""), 0
					world = setup(function(UI)
						return UI.TextInput "Upper" {
							value = upper,
							validate = function(proposed)
								return if string.find(proposed, "%d") then nil else string.upper(proposed)
							end,
							onChange = function(text)
								upper:set(text)
								edits += 1
							end,
						}
					end)
					field = find(world.node, "Upper")
					field:CaptureFocus()
					field.Text = "ab"
					Verify.expect((upper:peek())):toBe("AB")
					Verify.expect(field.Text):toBe("AB")
					field.Text = "AB1"
					Verify.expect((upper:peek())):toBe("AB")
					Verify.expect(field.Text):toBe("AB")
					Verify.expect(edits):toBe(1)
					field.Text = "AB\xC3("
					Verify.expect((upper:peek())):toBe("AB")
					Verify.expect(edits):toBe(1)
					world.stop()
				end,
			}
		)

		verifyHarness:case("sinks navigation keys from lower contexts only while a field edits", {
			id = "native_parity_weaker_actions::native parity weaker actions::sinks navigation keys from lower contexts only while a field edits",
			run = function()
				local probed, value, commits = 0, Compose.cell("seed"), {}
				local world = setup(function(UI, Host, engine)
					return Host.Frame({
						probe(Host, engine, function()
							probed += 1
						end) :: unknown,
						UI.TextInput "Field" {
							value = value,
							onCommit = function(text, reason)
								table.insert(commits, { text, reason })
							end,
						},
					})
				end)
				local E = world.engine.types.Enum
				local field = find(world.node, "Field")
				deliver(world.root, E.KeyCode.DPadDown)
				Verify.expect(probed):toBe(1)
				field:CaptureFocus()
				local sink = find(world.root, "FacetTextEditing")
				Verify.expect(sink.Enabled):toBe(true)
				Verify.expect(sink.Sink):toBe(true)
				Verify.expect(sink.Priority > 3000):toBe(true)
				for _, key in { E.KeyCode.DPadDown, E.KeyCode.Down, E.KeyCode.Up, E.KeyCode.Left, E.KeyCode.Right } do
					local received = deliver(world.root, key)
					Verify.expect(received[1]):toBe("FacetTextEditing")
					Verify.expect((table.find(received, "Probe"))):toBe(nil)
				end
				Verify.expect(probed):toBe(1)
				Verify.expect((field:IsFocused())):toBe(true)
				field.Text = "seedX"
				Verify.expect((value:peek())):toBe("seedX")
				field:ReleaseFocus(true)
				Verify.expect(commits[1][2]):toBe("submit")
				Verify.expect(sink.Enabled):toBe(false)
				deliver(world.root, E.KeyCode.DPadDown)
				Verify.expect(probed):toBe(2)
				world.stop()
			end,
		})

		verifyHarness:case("brings the editing sink down when the engine drops the editing surface without Enter", {
			id = "native_parity_weaker_actions::native parity weaker actions::brings the editing sink down when the engine drops the editing surface without Enter",
			run = function()
				local probed, value, commits = 0, Compose.cell(""), {}
				local world = setup(function(UI, Host, engine)
					return Host.Frame({
						probe(Host, engine, function()
							probed += 1
						end) :: unknown,
						UI.TextInput "Field" {
							value = value,
							onCommit = function(text, reason)
								table.insert(commits, { text, reason })
							end,
						},
					})
				end)
				local E = world.engine.types.Enum
				local field = find(world.node, "Field")
				field:CaptureFocus()
				field.Text = "hi"
				deliver(world.root, E.KeyCode.DPadDown)
				Verify.expect(probed):toBe(0)
				field:ReleaseFocus(false)
				Verify.expect(#commits):toBe(1)
				Verify.expect(commits[1][1]):toBe("hi")
				Verify.expect(commits[1][2]):toBe("focusLost")
				Verify.expect((value:peek())):toBe("hi")
				Verify.expect(find(world.root, "FacetTextEditing").Enabled):toBe(false)
				deliver(world.root, E.KeyCode.DPadDown)
				Verify.expect(probed):toBe(1)
				field:CaptureFocus()
				deliver(world.root, E.KeyCode.DPadDown)
				Verify.expect(probed):toBe(1)
				world.node.Visible = false
				Verify.expect((field:IsFocused())):toBe(false)
				Verify.expect(find(world.root, "FacetTextEditing").Enabled):toBe(false)
				world.node.Visible = true
				deliver(world.root, E.KeyCode.DPadDown)
				Verify.expect(probed):toBe(2)
				world.stop()
			end,
		})
		verifyHarness:case(
			"converts typed Fahrenheit live, commits on Enter and focus loss, and Clear resets every readout",
			{
				id = "native_parity_weaker_actions::native parity weaker actions::converts typed Fahrenheit live, commits on Enter and focus loss, and Clear resets every readout",
				run = function()
					local built, node, stop = mountGallery("01_temperature_converter", "example")
					local field, preview, result = find(node, "Fahrenheit"), find(node, "Preview"), find(node, "Result")
					Verify.expect(field.PlaceholderText):toBe("e.g. 212")
					Verify.expect((find(node, "Convert"))):toBe(nil)
					Verify.expect((find(node, "Stepper"))):toBe(nil)
					field:CaptureFocus()
					field.Text = "212"
					Verify.expect((built.fahrenheitText())):toBe("212")
					Verify.expect(preview.Text):toBe("Preview: 100 °C  (live, as you type)")
					Verify.expect(result.Text):toBe("Result: —")
					field.Text = "212a"
					Verify.expect(field.Text):toBe("212")
					Verify.expect((built.fahrenheitText())):toBe("212")
					field:ReleaseFocus(true)
					Verify.expect(result.Text):toBe("Result: 100 °C")
					field:CaptureFocus()
					field.Text = "32"
					Verify.expect(result.Text):toBe("Result: 100 °C")
					field:ReleaseFocus(false)
					Verify.expect((built.celsius())):toBe(0)
					Verify.expect(result.Text):toBe("Result: 0 °C")
					find(node, "Clear").Activated:Fire()
					Verify.expect((built.fahrenheitText())):toBe("")
					Verify.expect(field.Text):toBe("")
					Verify.expect((built.liveCelsius())):toBe(nil)
					Verify.expect((built.celsius())):toBe(nil)
					Verify.expect(preview.Text):toBe("Preview: —")
					Verify.expect(result.Text):toBe("Result: —")
					stop()
				end,
			}
		)

		verifyHarness:case("cancels a Fahrenheit edit back to the value it started with and ends the edit", {
			id = "native_parity_weaker_actions::native parity weaker actions::cancels a Fahrenheit edit back to the value it started with and ends the edit",
			run = function()
				local built, node, stop = mountGallery("01_temperature_converter", "example")
				local field, preview = find(node, "Fahrenheit"), find(node, "Preview")
				field:CaptureFocus()
				field.Text = "5"
				Verify.expect((built.fahrenheitText())):toBe("5")
				local cancel
				local top = node
				while top.Parent do
					top = top.Parent
				end
				for _, item in top:GetDescendants() do
					if item:IsA("InputAction") and item.Name == "Cancel" then
						cancel = item
					end
				end
				Verify.expect(cancel ~= nil):toBe(true)
				local keys = {}
				for _, binding in cancel:GetChildren() do
					keys[binding.KeyCode.Name] = true
				end
				Verify.expect(keys.ButtonB):toBe(true)
				cancel.Pressed:Fire()
				Verify.expect(field.Text):toBe("")
				Verify.expect((built.fahrenheitText())):toBe("")
				Verify.expect(preview.Text):toBe("Preview: —")
				Verify.expect((field:IsFocused())):toBe(false)
				stop()
			end,
		})

		verifyHarness:case("filters the playlist from typed text, keeps row identity and never navigates the table", {
			id = "native_parity_weaker_actions::native parity weaker actions::filters the playlist from typed text, keeps row identity and never navigates the table",
			run = function()
				local built, node, stop, ctx = mountGallery("02_playlist_table", "example")
				local E = ctx.types.Enum
				find(node, "Body").AbsoluteWindowSize = ctx.types.Vector2.new(600, 400)
				local function rowFor(name: string): any
					for _, label in node:GetDescendants() do
						if label:IsA("TextLabel") and label.Text == name then
							local at = label
							while at and at.Name ~= "Row" do
								at = at.Parent
							end
							return at
						end
					end
					return nil
				end
				local filter = find(node, "Filter")
				local clear = find(filter, "Clear")
				Verify.expect(clear.Visible):toBe(false)
				local drift = rowFor("Drift City Nights")
				Verify.expect(drift ~= nil):toBe(true)
				local order = {}
				for _, track in built.baseRows:peek() do
					table.insert(order, track.id)
				end
				filter:CaptureFocus()
				local received = deliver(ctx.inputTarget, E.KeyCode.Down)
				Verify.expect(received[1]):toBe("FacetTextEditing")
				Verify.expect(#received):toBe(1)
				filter.Text = "d"
				Verify.expect((built.filterText:peek())):toBe("d")
				Verify.expect(clear.Visible):toBe(true)
				filter.Text = "DRIFT"
				Verify.expect(#built.from:peek()):toBe(1)
				Verify.expect(built.from:peek()[1].id):toBe("drift")
				Verify.expect((rowFor("Drift City Nights"))):toBe(drift)
				Verify.expect((drift:isDestroyed())):toBe(false)
				Verify.expect((rowFor("Neon Straightaway"))):toBe(nil)
				for _, row in node:GetDescendants() do
					if row.Name == "Row" then
						Verify.expect((row:GetAttribute("FacetSelected"))):toBe(false)
					end
				end
				built.reorder({ "drift" }, 0)
				for index, track in built.baseRows:peek() do
					Verify.expect(track.id):toBe(order[index])
				end
				clear.Activated:Fire()
				Verify.expect((built.filterText:peek())):toBe("")
				Verify.expect(filter.Text):toBe("")
				Verify.expect(clear.Visible):toBe(false)
				Verify.expect(#built.from:peek()):toBe(6)
				Verify.expect((rowFor("Drift City Nights"))):toBe(drift)
				filter:ReleaseFocus(false)
				Verify.expect(find(ctx.inputTarget, "FacetTextEditing").Enabled):toBe(false)
				stop()
			end,
		})
		verifyHarness:case(
			"filters the monitor feed by genre and typed search, opens the chosen game and clears back",
			{
				id = "native_parity_weaker_actions::native parity weaker actions::filters the monitor feed by genre and typed search, opens the chosen game and clears back",
				run = function()
					local screens = require("../examples/virtual_monitors/screens")
					local modelModule = require("../examples/virtual_monitors/model")
					local engine: any = engineLib.new()
					local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
					local target = engine.new("ScreenGui")
					local gui, input = engine.new("GuiService"), engine.new("UserInputService")
					input.GetFocusedTextBox = function()
						return nil
					end
					input.IsKeyDown = function()
						return false
					end
					local lifetime = Compose.createRootOwner(function()
						local model = modelModule.new(Compose)
						Compose.cleanup(model.dispose)
						local views = screens.create(Facet, runtime, {
							model = model,
							types = engine.types,
							services = { GuiService = gui, UserInputService = input },
							motionLevel = "none",
						})
						local _, discover: any = runtime.mount(views.Discover, target)
						find(discover, "DiscoverBody").AbsoluteSize = engine.types.Vector2.new(1000, 800)
						local total = #model.catalog.items:peek()
						local genres = {}
						for _, item in model.catalog.items:peek() do
							genres[item.id] = item.genre
						end
						local function shownGenres(): { string }
							local shown = {}
							local grid = find(discover, "Games")
							grid.AbsoluteWindowSize = engine.types.Vector2.new(850, 260)
							for _, card in grid:GetDescendants() do
								local id = string.match(card.Name, "^Game_(%w+)$")
								if id then
									table.insert(shown, genres[id])
								end
							end
							return shown
						end
						local picker = find(discover, "Genres")
						find(picker, "Genre_Racing").Activated:Fire()
						Verify.expect((model.genre:peek())):toBe("Racing")
						Verify.expect(#model.visibleGames:peek() > 0):toBe(true)
						for _, item in model.visibleGames:peek() do
							Verify.expect(item.genre):toBe("Racing")
						end
						Verify.expect(#shownGenres() > 0):toBe(true)
						for _, genre in shownGenres() do
							Verify.expect(genre):toBe("Racing")
						end
						find(picker, "Genre_Building").Activated:Fire()
						Verify.expect((model.genre:peek())):toBe("Building")
						Verify.expect((find(picker, "Genre_Building"):GetAttribute("selected"))):toBe(true)
						Verify.expect((find(picker, "Genre_Racing"):GetAttribute("selected"))):toBe(false)
						find(picker, "Genre_all").Activated:Fire()
						Verify.expect((model.genre:peek())):toBe("all")
						Verify.expect(#model.visibleGames:peek()):toBe(total)
						find(picker, "Genre_Adventure").Activated:Fire()
						local editor = find(find(discover, "Search"), "Editor")
						editor:CaptureFocus()
						editor.Text = "Neon Harbor"
						Verify.expect((model.query:peek())):toBe("Neon Harbor")
						Verify.expect(#model.visibleGames:peek()):toBe(0)
						find(picker, "Genre_all").Activated:Fire()
						local matches = model.visibleGames:peek()
						Verify.expect(#matches > 0):toBe(true)
						for _, item in matches do
							Verify.expect(string.find(string.lower(item.title), "neon harbor", 1, true) ~= nil)
								:toBe(true)
						end
						local panel = find(target, "MenuPanel")
						Verify.expect(panel ~= nil):toBe(true)
						find(panel, matches[1].id).Activated:Fire()
						Verify.expect(model.selectedGame:peek().title):toBe("Neon Harbor")
						find(target, "close").Activated:Fire()
						editor:CaptureFocus()
						editor.Text = ""
						editor:ReleaseFocus(false)
						Verify.expect((model.query:peek())):toBe("")
						Verify.expect(#model.visibleGames:peek()):toBe(total)
					end, runtime.reactor)
					lifetime.dispose()
					Verify.expect(#target:GetChildren()):toBe(0)
					runtime:dispose()
				end,
			}
		)
		verifyHarness:case(
			"drives the gallery setting rows and removable race tags and stops reporting after unmount",
			{
				id = "native_parity_weaker_actions::native parity weaker actions::drives the gallery setting rows and removable race tags and stops reporting after unmount",
				run = function()
					local settings, node, stop = mountGallery("adaptive_controls")
					Verify.expect((find(node, "Vsync"))):toBe(nil)
					find(find(node, "Advanced"), "Header").Activated:Fire()
					local vsync = find(node, "Vsync")
					Verify.expect(vsync ~= nil):toBe(true)
					Verify.expect(vsync.ClassName):toBe("TextButton")
					Verify.expect((vsync:HasTag("facet-toggle"))):toBe(true)
					Verify.expect((vsync:GetAttribute("selected"))):toBe(true)
					vsync.Activated:Fire()
					Verify.expect(settings.report().vsync):toBe(false)
					Verify.expect((vsync:GetAttribute("selected"))):toBe(false)
					local telemetry = find(node, "Telemetry")
					Verify.expect((telemetry:HasTag("facet-toggle"))):toBe(true)
					telemetry.Activated:Fire()
					Verify.expect(settings.report().telemetry):toBe(true)
					stop()
					local actions, actionNode, actionStop = mountGallery("action_controls")
					Verify.expect(actions.report().tokenCount):toBe(3)
					local tokens = find(actionNode, "Tokens")
					local function chips(): { any }
						local found = {}
						for _, child in tokens:GetDescendants() do
							if child.Name == "Token" then
								table.insert(found, child)
							end
						end
						return found
					end
					Verify.expect(#chips()):toBe(3)
					local removed = chips()[2]
					local remove = find(removed, "Remove")
					Verify.expect(remove.ClassName):toBe("TextLabel")
					Verify.expect(remove.Visible):toBe(false)
					Verify.expect((removed:GetAttribute("editing"))):toBe(false)
					find(actionNode, "EditTags").Activated:Fire()
					Verify.expect(remove.Visible):toBe(true)
					Verify.expect((removed:GetAttribute("editing"))):toBe(true)
					removed.Activated:Fire()
					Verify.expect(actions.report().tokenCount):toBe(2)
					Verify.expect(#chips()):toBe(2)
					Verify.expect((removed:isDestroyed())):toBe(true)
					Verify.expect(remove.Parent):toBe(nil)
					actions.steps.reset()
					Verify.expect(actions.report().tokenCount):toBe(3)
					Verify.expect(#chips()):toBe(3)
					actionStop()
					Verify.expect((actions.report())):toBe(nil)
				end,
			}
		)

		verifyHarness:case(
			"keeps recipe action order, equal column widths, appearances, focus targets, checks, chips and commands",
			{
				id = "native_parity_weaker_actions::native parity weaker actions::keeps recipe action order, equal column widths, appearances, focus targets, checks, chips and commands",
				run = function()
					local built, node, stop, ctx = mountGallery("recipes_common")
					local E = ctx.types.Enum
					local actions = find(node, "Actions")
					actions.AbsoluteSize = ctx.types.Vector2.new(700, 44)
					for name, width in { Cancel = 48, Save = 200, Delete = 80 } :: { [string]: number } do
						find(find(actions, name), "NaturalWidth").TextBounds = ctx.types.Vector2.new(width, 20)
					end
					local cancel, save, delete = find(actions, "Cancel"), find(actions, "Save"), find(actions, "Delete")
					for _, form in { "row", "column", "row" } :: { "column" | "row" } do
						local report = if form == "row" then built.steps.wideActions() else built.steps.narrowActions()
						Verify.expect(report.actionsForm):toBe(form)
						local selectable = 0
						for _, child in actions:GetDescendants() do
							if child:IsA("GuiButton") and child.Selectable then
								selectable += 1
							end
						end
						Verify.expect(selectable):toBe(3)
						Verify.expect(cancel.LayoutOrder < save.LayoutOrder and save.LayoutOrder < delete.LayoutOrder)
							:toBe(true)
						Verify.expect(find(actions, "UIListLayout").SortOrder):toBe(E.SortOrder.LayoutOrder)
						if form == "column" then
							for _, button in { cancel, save, delete } do
								Verify.expect(button.Size.X.Scale):toBe(1)
								Verify.expect(button.Size.X.Offset):toBe(0)
								Verify.expect(button.AutomaticSize):toBe(E.AutomaticSize.Y)
							end
						else
							for _, button in { cancel, save, delete } do
								Verify.expect(button.AutomaticSize):toBe(E.AutomaticSize.XY)
							end
						end
						Verify.expect((save:GetAttribute("appearance"))):toBe("emphasis")
						Verify.expect((save:HasTag("facet-accent"))):toBe(true)
						Verify.expect((delete:GetAttribute("role"))):toBe("destructive")
						Verify.expect((delete:HasTag("facet-role-destructive"))):toBe(true)
						Verify.expect((cancel:GetAttribute("role"))):toBe("cancel")
						save.Activated:Fire()
					end
					Verify.expect(built.report().activations):toBe(3)
					local group, wrap = find(node, "CheckboxGroup"), find(node, "WrapChecks")
					find(group, "fuel").Activated:Fire()
					Verify.expect(built.report().checks.tires):toBe(true)
					Verify.expect(built.report().checks.fuel):toBe(true)
					Verify.expect(built.report().requests):toBe(1)
					Verify.expect((find(wrap, "fuel"):GetAttribute("selected"))):toBe(true)
					find(wrap, "fuel").Activated:Fire()
					Verify.expect((find(group, "fuel"):GetAttribute("selected"))):toBe(false)
					Verify.expect(built.report().checks.tires):toBe(true)
					Verify.expect((find(group, "tires"):GetAttribute("selected"))):toBe(true)
					local chips = find(node, "WrapChips")
					local rain, dust = find(chips, "Rain"), find(chips, "Dust")
					rain.Activated:Fire()
					Verify.expect(built.report().wrapSelected.Rain):toBe(true)
					Verify.expect(built.report().wrapSelected.Night):toBe(false)
					built.steps.reorderTags()
					Verify.expect((find(chips, "Rain"))):toBe(rain)
					Verify.expect((dust:isDestroyed())):toBe(true)
					Verify.expect((find(chips, "Dust"))):toBe(nil)
					Verify.expect(built.report().wrapSelected.Rain):toBe(true)
					Verify.expect((rain:HasTag("facet-selected"))):toBe(true)
					Verify.expect((find(chips, "Night"):HasTag("facet-selected"))):toBe(false)
					rain.Activated:Fire()
					Verify.expect(built.report().wrapSelected.Rain):toBe(false)
					Verify.expect((rain:HasTag("facet-selected"))):toBe(false)
					for _, entry in
						{
							{ "EmptyCollection", "createCount" },
							{ "NoResults", "clearCount" },
							{ "LoadFailed", "retryCount" },
						}
					do
						for count = 1, 2 do
							find(find(node, entry[1]), "Action").Activated:Fire()
							Verify.expect(built.report()[entry[2]]):toBe(count)
						end
					end
					stop()
				end,
			}
		)

		verifyHarness:case("activates a plain Button once from pointer, touch, gamepad and keyboard with no wiring", {
			id = "native_parity_weaker_actions::native parity weaker actions::activates a plain Button once from pointer, touch, gamepad and keyboard with no wiring",
			run = function()
				local hits, count = {}, 0
				local world = setup(function(UI: FacetControls)
					return UI.Button "Go" {
						label = "Go",
						onActivate = function(input)
							count += 1
							table.insert(hits, input)
						end,
					}
				end)
				local node = find(world.node, "Go")
				Verify.expect((action(world.root, "Activate"))):toBe(nil)
				for _, kind in { "pointer", "touch", "gamepad" } :: { "gamepad" | "pointer" | "touch" } do
					local input = pointer(world.engine, kind)
					node.Activated:Fire(input, 1)
					Verify.expect(hits[#hits]):toBe(input)
				end
				Verify.expect(count):toBe(3)
				world.gui.SelectedObject = node
				local activate = action(world.root, "Activate")
				Verify.expect(activate ~= nil):toBe(true)
				local keys = {}
				for _, binding in activate:GetChildren() do
					keys[binding.KeyCode.Name] = true
				end
				Verify.expect(keys.Return):toBe(true)
				Verify.expect(keys.Space):toBe(true)
				Verify.expect(keys.ButtonA):toBe(nil)
				deliver(world.root, world.engine.types.Enum.KeyCode.Return)
				Verify.expect(count):toBe(4)
				deliver(world.root, world.engine.types.Enum.KeyCode.ButtonA)
				Verify.expect(count):toBe(4)
				world.stop()
			end,
		})

		verifyHarness:case("mounts an initially busy Button with its spinner and releases it when busy ends", {
			id = "native_parity_weaker_actions::native parity weaker actions::mounts an initially busy Button with its spinner and releases it when busy ends",
			run = function()
				local busy, actions = Compose.cell(true), 0
				local world = setup(function(UI: FacetControls)
					return UI.Button "Loading" {
						label = "Loading",
						busy = busy,
						onActivate = function()
							actions += 1
						end,
					}
				end, { motionLevel = "normal" })
				local node = find(world.node, "Loading")
				Verify.expect(find(node, "Busy") ~= nil):toBe(true)
				Verify.expect(find(node, "Dot3") ~= nil):toBe(true)
				Verify.expect((engineLib.connections(world.engine.heartbeat))):toBe(1)
				Verify.expect((node:HasTag("facet-busy"))):toBe(true)
				Verify.expect(node.Interactable):toBe(false)
				node.Activated:Fire()
				Verify.expect(actions):toBe(0)
				busy:set(false)
				Verify.expect((find(node, "Busy"))):toBe(nil)
				Verify.expect((engineLib.connections(world.engine.heartbeat))):toBe(0)
				node.Activated:Fire()
				Verify.expect(actions):toBe(1)
				busy:set(true)
				Verify.expect((engineLib.connections(world.engine.heartbeat))):toBe(1)
				world.stop()
				Verify.expect((engineLib.connections(world.engine.heartbeat))):toBe(0)
			end,
		})

		verifyHarness:case("keeps a disabled destructive Button disabled on every input and re-enables it in place", {
			id = "native_parity_weaker_actions::native parity weaker actions::keeps a disabled destructive Button disabled on every input and re-enables it in place",
			run = function()
				local enabled, fired = Compose.cell(false), 0
				local world = setup(function(UI: FacetControls)
					return UI.Button "Delete" {
						label = "Delete",
						role = "destructive" :: "destructive",
						enabled = enabled,
						onActivate = function()
							fired += 1
						end,
					}
				end)
				local node = find(world.node, "Delete")
				Verify.expect((node:HasTag("facet-role-destructive"))):toBe(true)
				Verify.expect((node:HasTag("facet-disabled"))):toBe(true)
				Verify.expect(node.Selectable):toBe(false)
				Verify.expect(node.Interactable):toBe(false)
				for _, kind in { "pointer", "touch", "gamepad" } :: { "gamepad" | "pointer" | "touch" } do
					node.Activated:Fire(pointer(world.engine, kind))
				end
				world.gui.SelectedObject = node
				Verify.expect(world.gui.SelectedObject):toBe(nil)
				Verify.expect(table.find(world.engine.rejectedSelections(), node) ~= nil):toBe(true)
				Verify.expect((action(world.root, "Activate"))):toBe(nil)
				deliver(world.root, world.engine.types.Enum.KeyCode.Return)
				Verify.expect(fired):toBe(0)
				enabled:set(true)
				Verify.expect((find(world.node, "Delete"))):toBe(node)
				Verify.expect((node:HasTag("facet-disabled"))):toBe(false)
				Verify.expect((node:HasTag("facet-role-destructive"))):toBe(true)
				Verify.expect(node.Selectable):toBe(true)
				world.gui.SelectedObject = node
				Verify.expect(world.gui.SelectedObject):toBe(node)
				deliver(world.root, world.engine.types.Enum.KeyCode.Return)
				node.Activated:Fire(pointer(world.engine, "touch"))
				Verify.expect(fired):toBe(2)
				world.stop()
			end,
		})

		verifyHarness:case("mounts an explicit rect shape as an ordinary Button and a circle with a bound label", {
			id = "native_parity_weaker_actions::native parity weaker actions::mounts an explicit rect shape as an ordinary Button and a circle with a bound label",
			run = function()
				local label = Compose.cell("1")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Button "Rect" { label = "Save changes", shape = "rect" :: "rect" } :: unknown,
						UI.Button "Plain" { label = "Save changes" },
						UI.Button "Count" { label = label, shape = "circle" :: "circle" },
					})
				end)
				local rect, plain, count =
					find(world.node, "Rect"), find(world.node, "Plain"), find(world.node, "Count")
				for _, node in { rect, plain } do
					Verify.expect((node:FindFirstChildWhichIsA("UIAspectRatioConstraint"))):toBe(nil)
					Verify.expect((node:FindFirstChildWhichIsA("UICorner"))):toBe(nil)
					Verify.expect((node:HasTag("facet-shape-circle"))):toBe(false)
					Verify.expect(node.Text):toBe("Save changes")
					Verify.expect(node.AutomaticSize):toBe(world.engine.types.Enum.AutomaticSize.XY)
				end
				Verify.expect((count:HasTag("facet-shape-circle"))):toBe(true)
				Verify.expect(count:FindFirstChildWhichIsA("UIAspectRatioConstraint").AspectRatio):toBe(1)
				Verify.expect(count.Text):toBe("1")
				Verify.expect((count:GetAttribute("label"))):toBe("1")
				label:set("99+")
				Verify.expect((find(world.node, "Count"))):toBe(count)
				Verify.expect(count.Text):toBe("99+")
				Verify.expect((count:GetAttribute("label"))):toBe("99+")
				Verify.expect(count.Size.X.Offset):toBe(count.Size.Y.Offset)
				world.stop()
			end,
		})
		verifyHarness:case(
			"shares activation and disable guards across Toggle, Button, ComboBox and SplitButton on every input",
			{
				id = "native_parity_weaker_actions::native parity weaker actions::shares activation and disable guards across Toggle, Button, ComboBox and SplitButton on every input",
				run = function()
					for _, kind in
						{ "Toggle", "Button", "ComboBox", "SplitButton" } :: { "Button" | "ComboBox" | "SplitButton" | "Toggle" }
					do
						for _, input in { "pointer", "touch", "keyboard", "gamepad" } do
							local enabled, calls = Compose.cell(true), 0
							local value, text = Compose.cell("a"), Compose.cell("A")
							local world = setup(function(UI: FacetControls)
								if kind == "Toggle" then
									return UI.Toggle "Control" {
										label = "Test checkbox",
										value = Compose.cell(false),
										mixed = Compose.cell(true),
										presentation = "checkbox" :: "checkbox",
										enabled = enabled,
										onChange = function()
											calls += 1
										end,
									}
								elseif kind == "Button" then
									return UI.Button "Control" {
										label = "Test action",
										enabled = enabled,
										onActivate = function()
											calls += 1
										end,
									}
								elseif kind == "SplitButton" then
									return UI.SplitButton "Control" {
										label = "Test action",
										enabled = enabled,
										onActivate = function()
											calls += 1
										end,
										items = {
											{ id = "option", label = "Choose this", onSelect = function() end } :: FixtureNavigationTypes.MenuItem<any>,
										},
									}
								end
								return UI.ComboBox "Control" {
									value = value,
									text = text,
									enabled = enabled,
									options = {
										{ id = "a", label = "A" } :: FixtureNavigationTypes.PickerOption<string>,
										{ id = "b", label = "B" } :: FixtureNavigationTypes.PickerOption<string>,
									},
									acceptCustom = function()
										return true
									end,
								}
							end)
							local root = world.node
							local function activate(target: any)
								if input == "keyboard" then
									world.gui.SelectedObject = target
									deliver(world.root, world.engine.types.Enum.KeyCode.Return)
									world.gui.SelectedObject = nil
								else
									target.Activated:Fire(pointer(world.engine, input), 1)
								end
							end
							if kind == "ComboBox" then
								local editor = find(root, "Editor")
								Verify.expect(editor.TextEditable):toBe(true)
								Verify.expect(editor.Selectable):toBe(true)
								editor:CaptureFocus()
								Verify.expect(find(world.root, "FacetTextEditing").Enabled):toBe(true)
								editor.Text = "B"
								editor:ReleaseFocus(true)
								Verify.expect((value:peek())):toBe("b")
								text:set("")
								activate(find(root, "Trigger"))
								Verify.expect(find(world.root, "MenuPanel") ~= nil):toBe(true)
								activate(find(find(world.root, "MenuPanel"), "a"))
								Verify.expect((value:peek())):toBe("a")
								enabled:set(false)
								Verify.expect(editor.TextEditable):toBe(false)
								Verify.expect(editor.Selectable):toBe(false)
								Verify.expect(find(root, "Trigger").Interactable):toBe(false)
								editor:CaptureFocus()
								Verify.expect(find(world.root, "FacetTextEditing").Enabled):toBe(false)
								editor.Text = "B"
								editor:ReleaseFocus(true)
								activate(find(root, "Trigger"))
								Verify.expect((value:peek())):toBe("a")
								Verify.expect((find(world.root, "MenuPanel"))):toBe(nil)
							else
								local target = if kind == "SplitButton" then find(root, "Primary") else root
								activate(target)
								Verify.expect(calls):toBe(1)
								if kind == "SplitButton" then
									activate(
										(find(find(root, "Alternatives"), "Trigger") or find(root, "Alternatives"))
									)
									Verify.expect(find(world.root, "MenuPanel") ~= nil):toBe(true)
									Verify.expect(calls):toBe(1)
									find(find(world.root, "MenuPanel"), "option").Activated:Fire()
								end
								enabled:set(false)
								Verify.expect(target.Interactable):toBe(false)
								Verify.expect(target.Selectable):toBe(false)
								activate(target)
								Verify.expect(calls):toBe(1)
								if kind == "SplitButton" then
									activate(
										(find(find(root, "Alternatives"), "Trigger") or find(root, "Alternatives"))
									)
									Verify.expect((find(world.root, "MenuPanel"))):toBe(nil)
								end
							end
							world.stop()
						end
					end
				end,
			}
		)

		verifyHarness:case(
			"hands one application press haptic to opted-in buttons, segments and toggles and leaves plain buttons, hover and fields alone",
			{
				id = "native_parity_weaker_actions::native parity weaker actions::hands one application press haptic to opted-in buttons, segments and toggles and leaves plain buttons, hover and fields alone",
				run = function()
					local effect
					local selected = Compose.cell("one")
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({
							UI.Button "Plain" { label = "Play" } :: unknown,
							UI.Button "Other" { label = "Stop", haptic = true },
							UI.Toggle "Switch" { label = "Sound", value = Compose.cell(true) },
							UI.Picker "Segments" {
								selected = selected,
								style = "segmented" :: "segmented",
								options = {
									{ value = "one", label = "One" } :: FixtureNavigationTypes.PickerOption<any>,
									{ value = "two", label = "Two" } :: FixtureNavigationTypes.PickerOption<any>,
								},
							},
							UI.TextInput "Field" { value = Compose.cell("") },
						})
					end, {
						pressHaptic = function(engine)
							effect = engine.new("HapticEffect")
							return effect
						end,
					})
					local plain, other, switch =
						find(world.node, "Plain"), find(world.node, "Other"), find(world.node, "Switch")
					local segment = find(find(world.node, "Segments"), "two")
					for _, node in { other, switch, segment } do
						Verify.expect(node.PressHapticEffect):toBe(effect)
						Verify.expect(node.HoverHapticEffect):toBe(nil)
					end
					Verify.expect(plain.PressHapticEffect):toBe(nil)
					Verify.expect(plain.HoverHapticEffect):toBe(nil)
					Verify.expect(find(world.node, "Field").PressHapticEffect):toBe(nil)
					Verify.expect(world.node.PressHapticEffect):toBe(nil)
					local effects = 0
					for _, made in world.engine.made do
						if made.ClassName == "HapticEffect" then
							effects += 1
						end
					end
					Verify.expect(effects):toBe(1)
					Verify.expect(effect.PlayCount):toBe(nil)
					plain.Activated:Fire()
					other.Activated:Fire()
					Verify.expect(effect.PlayCount):toBe(nil)
					world.stop()
					Verify.expect((effect:isDestroyed())):toBe(false)
					world = setup(function(UI: FacetControls)
						return UI.Button "Plain" { label = "Play" }
					end)
					Verify.expect(find(world.node, "Plain").PressHapticEffect):toBe(nil)
					world.stop()
				end,
			}
		)

		verifyHarness:case("returns a pressed pop to its rest under an authored scale and keeps the native shadow", {
			id = "native_parity_weaker_actions::native parity weaker actions::returns a pressed pop to its rest under an authored scale and keeps the native shadow",
			run = function()
				local package = Facet.themes.neutralPackage()
				assert(package.chrome).control = { kind = "native" :: "native", shadow = "raised" }
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame "Card" {
						Host.UIScale "Authored" { Scale = 0.8 } :: unknown,
						UI.Button "Pop" { label = "Pop", pop = true, onActivate = function() end },
					}
				end, { motionLevel = "normal", theme = package })
				local E = world.engine.types.Enum
				local node = find(world.node, "Pop")
				local authored = find(world.node, "Authored")
				local pop = node:FindFirstChildWhichIsA("UIScale")
				local shadow = find(node, "ChromeShadow")
				Verify.expect(shadow.ClassName):toBe("UIShadow")
				Verify.expect(shadow.Enabled):toBe(true)
				Verify.expect(pop.Scale):toBe(1)
				node.GuiState = E.GuiState.Press
				node.Activated:Fire()
				world.engine.heartbeat:Fire(0.1)
				Verify.expect(pop.Scale > 1):toBe(true)
				Verify.expect((find(node, "ChromeShadow"))):toBe(shadow)
				Verify.expect(shadow.Enabled):toBe(true)
				node.GuiState = E.GuiState.Idle
				world.engine.heartbeat:Fire(1)
				Verify.expect(pop.Scale):toBe(1)
				Verify.expect(authored.Scale):toBe(0.8)
				Verify.expect((find(node, "ChromeShadow"))):toBe(shadow)
				Verify.expect(shadow.Enabled):toBe(true)
				Verify.expect((shadow:isDestroyed())):toBe(false)
				world.stop()
				Verify.expect((shadow:isDestroyed())):toBe(true)
			end,
		})

		verifyHarness:case(
			"tags every disabled control for the theme and tears down cleanly under a non-interactable ancestor",
			{
				id = "native_parity_weaker_actions::native parity weaker actions::tags every disabled control for the theme and tears down cleanly under a non-interactable ancestor",
				run = function()
					local enabled = Compose.cell(false)
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame "Panel" {
							UI.Button "Go" { label = "Go", enabled = enabled, onActivate = function() end } :: unknown,
							UI.Toggle "Switch" { label = "Sound", value = Compose.cell(true), enabled = enabled },
							UI.TextInput "Field" { value = Compose.cell(""), enabled = enabled },
						}
					end)
					local go, switch, field =
						find(world.node, "Go"), find(world.node, "Switch"), find(world.node, "Field")
					for _, node in { go, switch, field } do
						Verify.expect((node:HasTag("facet-disabled"))):toBe(true)
					end
					enabled:set(true)
					for _, node in { go, switch, field } do
						Verify.expect((node:HasTag("facet-disabled"))):toBe(false)
					end
					world.gui.SelectedObject = go
					local activate = action(world.root, "Activate")
					Verify.expect(activate ~= nil):toBe(true)
					field:CaptureFocus()
					local editing = find(world.root, "FacetTextEditing")
					Verify.expect(editing.Enabled):toBe(true)
					world.node.Interactable = false
					Verify.expect(activate.Parent.Enabled):toBe(false)
					Verify.expect(editing.Enabled):toBe(false)
					Verify.expect((field:IsFocused())):toBe(false)
					enabled:set(false)
					world.stop()
					Verify.expect((activate:isDestroyed())):toBe(true)
					Verify.expect((editing:isDestroyed())):toBe(true)
					Verify.expect((engineLib.connections(world.engine.heartbeat))):toBe(0)
					Verify.expect((engineLib.connections(world.gui:GetPropertyChangedSignal("SelectedObject")))):toBe(0)
					Verify.expect((engineLib.connections(world.node:GetPropertyChangedSignal("Interactable")))):toBe(0)
					Verify.expect((engineLib.connections(go.Activated))):toBe(0)
				end,
			}
		)

		verifyHarness:case(
			"waits for a resting pointer, restarts the dwell, shows current help text and opens on a touch long-press",
			{
				id = "native_parity_weaker_actions::native parity weaker actions::waits for a resting pointer, restarts the dwell, shows current help text and opens on a touch long-press",
				run = function()
					local text = Compose.cell("Posts this avatar")
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame "Screen" {
							UI.Button "Plus" { label = "+", help = text },
						}
					end)
					local plus = find(world.node, "Plus")
					local E = world.engine.types.Enum
					world.input.PreferredInput = E.PreferredInput.KeyboardAndMouse
					plus.GuiState = E.GuiState.Hover
					world.engine.heartbeat:Fire(0.3)
					plus.GuiState = E.GuiState.Idle
					plus.GuiState = E.GuiState.Hover
					world.engine.heartbeat:Fire(0.3)
					Verify.expect((find(world.root, "HelpText"))):toBe(nil)
					text:set("Shares this avatar")
					world.engine.heartbeat:Fire(0.2)
					local help = find(world.root, "HelpText")
					Verify.expect(help.Text):toBe("Shares this avatar")
					for _, node in find(world.root, "Help"):GetDescendants() do
						if node:IsA("GuiObject") then
							Verify.expect(node.Selectable):toBe(false)
						end
					end
					Verify.expect(find(world.root, "Help").Selectable):toBe(false)
					plus.GuiState = E.GuiState.Idle
					Verify.expect((find(world.root, "HelpText"))):toBe(nil)
					world.input.PreferredInput = E.PreferredInput.Touch
					plus.GuiState = E.GuiState.Press
					world.engine.heartbeat:Fire(1)
					Verify.expect((find(world.root, "HelpText"))):toBe(nil)
					plus.TouchLongPress:Fire({}, E.UserInputState.Begin)
					world.engine.heartbeat:Fire(0.1)
					Verify.expect(find(world.root, "HelpText").Text):toBe("Shares this avatar")
					world.stop()
				end,
			}
		)

		verifyHarness:case("shows the disclosure state on a leading or trailing caret through header activation", {
			id = "native_parity_weaker_actions::native parity weaker actions::shows the disclosure state on a leading or trailing caret through header activation",
			run = function()
				for _, side in { "leading", "trailing" } :: { "leading" | "trailing" } do
					local expanded = Compose.cell(false)
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return UI.DisclosureGroup "Group" {
							label = "Advanced",
							chevronPosition = side :: "leading" | "trailing",
							expanded = expanded,
							content = function(): Instance
								return Host.Frame "Body" {}
							end,
						}
					end)
					local header = find(world.node, "Header")
					local caret = find(header, if side == "leading" then "LeadingIcon" else "TrailingIcon")
					Verify.expect((find(header, if side == "leading" then "TrailingIcon" else "LeadingIcon"))):toBe(nil)
					local closed = caret.Image
					Verify.expect((header:GetAttribute("selected"))):toBe(false)
					header.Activated:Fire()
					Verify.expect((expanded:peek())):toBe(true)
					Verify.expect(caret.Image ~= closed):toBe(true)
					Verify.expect((header:GetAttribute("selected"))):toBe(true)
					Verify.expect(find(world.node, "Body") ~= nil):toBe(true)
					header.Activated:Fire()
					Verify.expect((expanded:peek())):toBe(false)
					Verify.expect(caret.Image):toBe(closed)
					Verify.expect((header:GetAttribute("selected"))):toBe(false)
					Verify.expect((find(world.node, "Body"))):toBe(nil)
					world.stop()
				end
			end,
		})

		verifyHarness:case(
			"paints contained disclosures, places a trailing caret after the label and follows a bound description",
			{
				id = "native_parity_weaker_actions::native parity weaker actions::paints contained disclosures, places a trailing caret after the label and follows a bound description",
				run = function()
					for _, appearance in { "plain", "contained", "divided" } :: { "contained" | "divided" | "plain" } do
						local expanded, description = Compose.cell(false), Compose.cell("Configure the current race")
						local world = setup(function(UI: FacetControls, Host: RobloxHost)
							return UI.DisclosureGroup "Group" {
								label = "Details",
								description = description,
								icon = "menu",
								appearance = appearance :: "contained" | "divided" | "plain",
								chevronPosition = "trailing" :: "trailing",
								expanded = expanded,
								content = function(): Instance
									return Host.Frame "Body" {}
								end,
							}
						end)
						local group, header = world.node, find(world.node, "Header")
						Verify.expect((group:HasTag("facet-panel"))):toBe(appearance == "contained")
						Verify.expect((group:HasTag("facet-disclosure-" .. appearance))):toBe(true)
						Verify.expect((group:HasTag("facet-disclosure"))):toBe(false)
						Verify.expect((group:HasTag("facet-disclosure-group"))):toBe(true)
						if appearance == "contained" then
							Verify.expect(group.BackgroundTransparency):toBe(0)
						end
						local content = find(header, "Content")
						local captions, caret = find(content, "Captions"), find(content, "TrailingIcon")
						Verify.expect(captions.Parent):toBe(caret.Parent)
						Verify.expect(captions.LayoutOrder < caret.LayoutOrder):toBe(true)
						Verify.expect(find(content, "LeadingIcon") ~= nil):toBe(true)
						Verify.expect(find(content, "LeadingIcon").LayoutOrder < captions.LayoutOrder):toBe(true)
						Verify.expect(find(captions, "Description").Text):toBe("Configure the current race")
						Verify.expect((header:HasTag("facet-button-described"))):toBe(true)
						Verify.expect(header.AutomaticSize):toBe(world.engine.types.Enum.AutomaticSize.XY)
						description:set("Updated details")
						Verify.expect(find(captions, "Description").Text):toBe("Updated details")
						Verify.expect((find(world.node, "Header"))):toBe(header)
						Verify.expect((find(group, "Divider"))):toBe(nil)
						expanded:set(true)
						Verify.expect(find(group, "Divider") ~= nil):toBe(appearance == "divided")
						expanded:set(false)
						Verify.expect((find(group, "Divider"))):toBe(nil)
						world.stop()
					end
				end,
			}
		)

		verifyHarness:case("keeps split primary and alternatives separate in pointer form and runs a plain touch tap", {
			id = "native_parity_weaker_actions::native parity weaker actions::keeps split primary and alternatives separate in pointer form and runs a plain touch tap",
			run = function()
				local primary, alternative = 0, 0
				local world = setup(function(UI: FacetControls)
					return UI.SplitButton "Split" {
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
							} :: FixtureNavigationTypes.MenuItem<any>,
						},
					}
				end)
				local E = world.engine.types.Enum
				world.input.PreferredInput = E.PreferredInput.KeyboardAndMouse
				local first = find(world.node, "Primary")
				local menu = find(world.node, "Alternatives")
				Verify.expect(first.Parent):toBe(menu.Parent)
				Verify.expect(first.LayoutOrder < menu.LayoutOrder):toBe(true)
				Verify.expect(first.Parent:FindFirstChildWhichIsA("UIListLayout").FillDirection)
					:toBe(E.FillDirection.Horizontal)
				first.Activated:Fire(pointer(world.engine, "pointer"))
				Verify.expect(primary):toBe(1)
				Verify.expect((find(world.root, "MenuPanel"))):toBe(nil)
				local chevron = find(menu, "Trigger") or menu
				Verify.expect(first.Parent:FindFirstChildWhichIsA("UIListLayout").Padding.Offset <= 2):toBe(true)
				Verify.expect(chevron.Text):toBe("")
				chevron.Activated:Fire(pointer(world.engine, "pointer"))
				Verify.expect(primary):toBe(1)
				Verify.expect(find(world.root, "MenuPanel") ~= nil):toBe(true)
				find(find(world.root, "MenuPanel"), "Alternate").Activated:Fire()
				Verify.expect(alternative):toBe(1)
				Verify.expect(primary):toBe(1)
				Verify.expect((find(world.root, "MenuPanel"))):toBe(nil)
				world.input.PreferredInput = E.PreferredInput.Touch
				Verify.expect((find(world.node, "Alternatives"))):toBe(nil)
				local trigger = find(world.node, "Primary")
				Verify.expect(trigger ~= first):toBe(true)
				Verify.expect(trigger:FindFirstChild("TrailingIcon", true) ~= nil):toBe(true)
				trigger.Activated:Fire(pointer(world.engine, "touch"))
				Verify.expect(primary):toBe(2)
				Verify.expect((find(world.root, "MenuPanel"))):toBe(nil)
				trigger.TouchLongPress:Fire({}, E.UserInputState.Begin)
				trigger.Activated:Fire(pointer(world.engine, "touch"))
				Verify.expect(primary):toBe(2)
				find(find(world.root, "MenuPanel"), "Alternate").Activated:Fire()
				Verify.expect(alternative):toBe(2)
				trigger.Activated:Fire(pointer(world.engine, "touch"))
				Verify.expect(primary):toBe(3)
				world.input.PreferredInput = E.PreferredInput.KeyboardAndMouse
				find(world.node, "Primary").Activated:Fire(pointer(world.engine, "pointer"))
				Verify.expect(primary):toBe(4)
				world.stop()
			end,
		})

		verifyHarness:case("selects a page from pointer and touch taps on its indicators", {
			id = "native_parity_weaker_actions::native parity weaker actions::selects a page from pointer and touch taps on its indicators",
			run = function()
				local selection = Compose.cell("one")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.PageView "Pager" {
						selection = selection,
						pages = {
							{ id = "one", title = "One", content = Host.Frame({}) } :: FixtureNavigationTypes.Tab,
							{ id = "two", title = "Two", content = Host.Frame({}) } :: FixtureNavigationTypes.Tab,
							{ id = "three", title = "Three", content = Host.Frame({}) } :: FixtureNavigationTypes.Tab,
						},
					}
				end)
				local indicators = find(world.node, "Indicators")
				local layout = find(world.node, "PagesLayout")
				find(indicators, "three").Activated:Fire(pointer(world.engine, "pointer"))
				Verify.expect((selection:peek())):toBe("three")
				Verify.expect(layout.CurrentPage.Name):toBe("three")
				Verify.expect((find(indicators, "three"):HasTag("facet-selected"))):toBe(true)
				Verify.expect(find(world.node, "Summary").Text):toBe("Page 3 of 3")
				find(indicators, "two").Activated:Fire(pointer(world.engine, "touch"))
				Verify.expect((selection:peek())):toBe("two")
				Verify.expect(layout.CurrentPage.Name):toBe("two")
				Verify.expect((find(indicators, "two"):HasTag("facet-selected"))):toBe(true)
				Verify.expect((find(indicators, "three"):HasTag("facet-selected"))):toBe(false)
				world.stop()
			end,
		})

		verifyHarness:case("resolves live control-size rungs in place, retracts nil to regular and keeps selection", {
			id = "native_parity_weaker_actions::native parity weaker actions::resolves live control-size rungs in place, retracts nil to regular and keeps selection",
			run = function()
				local rung, look = Compose.cell("large" :: string?), require("./lib/cells").optionalString("standard")
				local builds = 0
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					builds += 1
					return Host.Frame({
						UI.Button "Other" { label = "Other" } :: unknown,
						UI.Button "Live" { label = "Go", controlSize = rung, appearance = look },
						UI.Toggle "Switch" { label = "Sound", value = Compose.cell(true), controlSize = rung },
					})
				end)
				local live, switch = find(world.node, "Live"), find(world.node, "Switch")
				world.gui.SelectedObject = live
				for _, entry in
					{
						{ size = "large", height = 56 },
						{ size = "compact", height = 36 },
						{ size = "regular", height = 44 },
					}
				do
					rung:set(entry.size :: "compact" | "regular" | "large")
					Verify.expect(live.Size.Y.Offset):toBe(entry.height)
					Verify.expect((live:GetAttribute("controlSize"))):toBe(entry.size)
					Verify.expect((switch:GetAttribute("controlSize"))):toBe(entry.size)
					Verify.expect(world.gui.SelectedObject):toBe(live)
				end
				rung:set("compact")
				look:set("emphasis")
				Verify.expect((live:HasTag("facet-accent"))):toBe(true)
				rung:set(nil)
				look:set(nil)
				Verify.expect(live.Size.Y.Offset):toBe(44)
				Verify.expect((live:GetAttribute("controlSize"))):toBe("regular")
				Verify.expect((live:GetAttribute("appearance"))):toBe("standard")
				Verify.expect((live:HasTag("facet-accent"))):toBe(false)
				Verify.expect((find(world.node, "Live"))):toBe(live)
				Verify.expect(world.gui.SelectedObject):toBe(live)
				Verify.expect(action(world.root, "Activate") ~= nil):toBe(true)
				Verify.expect(builds):toBe(1)
				world.stop()
			end,
		})

		verifyHarness:case("refuses a readable corners source that turns into an illegal word", {
			id = "native_parity_weaker_actions::native parity weaker actions::refuses a readable corners source that turns into an illegal word",
			run = function()
				local corners = Compose.cell("pill" :: "pill" | "square")
				local world = setup(function(UI: FacetControls)
					return UI.Button "Corners" { label = "Corners", corners = corners }
				end)
				local corner = world.node:FindFirstChildWhichIsA("UICorner")
				Verify.expect(corner.CornerRadius.Scale):toBe(1)
				local ok, message = pcall(function()
					corners:set("round" :: any)
				end)
				Verify.expect(ok):toBe(false)
				Verify.expect(string.find(tostring(message), "corners must be pill or square", 1, true) ~= nil)
					:toBe(true)
				world.stop()
				local failed, reason = pcall(function()
					setup(function(UI: FacetControls)
						return UI.Button "Bad" { label = "Bad", corners = Compose.cell("round") :: any }
					end)
				end)
				Verify.expect(failed):toBe(false)
				Verify.expect(string.find(tostring(reason), "corners must be pill or square", 1, true) ~= nil)
					:toBe(true)
			end,
		})
	end)
end
