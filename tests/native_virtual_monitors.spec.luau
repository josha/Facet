--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	local nativeDrag = require("./lib/native_drag")

	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type FrameConstructor = typeof(require("@repo/tools/typecheck/aliases").FrameConstructor)
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T

	local Compose = require("../src/vendor/compose/core")
	local Roblox = require("../src/vendor/compose/roblox")
	local modelModule = require("../examples/virtual_monitors/model")
	local screens = require("../examples/virtual_monitors/screens")
	local theme = require("../examples/virtual_monitors/theme")
	local engineModule = require("./lib/native_engine")

	local function withModel(body)
		local root = Compose.createRootOwner(function()
			local model = modelModule.new(Compose)
			Compose.cleanup(model.dispose)
			body(model)
		end)
		root.dispose()
	end

	local function find(node: any, name: string): any
		if node.Name == name then
			return node
		end
		for _, child in node:GetChildren() do
			local found = find(child, name)
			if found then
				return found
			end
		end
		return nil
	end

	local function ratio(first, second)
		local function luminance(value)
			local function linear(channel)
				return if channel <= 0.04045 then channel / 12.92 else ((channel + 0.055) / 1.055) ^ 2.4
			end
			return 0.2126 * linear(value.r) + 0.7152 * linear(value.g) + 0.0722 * linear(value.b)
		end
		local a, b = luminance(first), luminance(second)
		return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05)
	end

	local function rule(sheet, selector)
		for _, node in sheet:GetChildren() do
			if node.Selector == selector then
				return node:GetProperties()
			end
		end
		error("No rule: " .. selector)
	end

	local function engage(card)
		card:_fireSignal("MouseEnter")
		return card
	end

	local function saveCard(card)
		engage(card)
		find(card, "Primary").Activated:Fire()
		card:_fireSignal("MouseLeave")
	end

	local function rate(node, value: number, types)
		local control = find(node, "Stars")
		control.AbsolutePosition = types.Vector2.new(0, 0)
		control.AbsoluteSize = types.Vector2.new(220, 44)
		control.Activated:Fire({ Position = types.Vector3.new((value - 0.5) * 44, 20, 0) })
	end

	local function withScreens(body: (any) -> (), options: { [string]: any }?)
		local Facet = require("../src")
		local engine = engineModule.new()
		local runtime: ComposeRuntime = Roblox.createRuntime(engine)
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
			local config: { [string]: any } = {
				model = model,
				types = engine.types,
				services = { GuiService = gui, UserInputService = input },
				motionLevel = "none",
			}
			for key, value in (options or {}) :: { [string]: any } do
				config[key] = value
			end
			local views = screens.create(Facet, runtime, config)
			local world = {
				model = model,
				runtime = runtime,
				engine = engine,
				target = target,
				gui = gui,
				input = input,
				types = engine.types,
				views = views,
				stops = {},
			}
			for _, name in screens.APPS do
				local stop, node: any = runtime.mount(views[name], target)
				world[name] = node
				world.stops[name] = stop
			end
			body(world)
		end, runtime.reactor)
		lifetime.dispose()
		Verify.expect(#target:GetChildren()):toBe(0)
		runtime:dispose()
	end

	verifyHarness:suite("native virtual monitors", function()
		verifyHarness:case("retains overlapping flight tiles and bounds an endless scrolling world", {
			id = "native_virtual_monitors::native virtual monitors::retains overlapping flight tiles and bounds an endless scrolling world",
			run = function()
				withScreens(function(world)
					world.model.mode:set("Screen")
					world.model.selectedTab:set("Flap")
					local tiles = find(world.Flap, "TileWorld")
					Verify.expect(tiles ~= nil):toBe(true)
					local retained = find(tiles, "Tile_1_12")
					find(world.Flap, "FlapTouch").Activated:Fire()
					Verify.expect(world.model.flap.state:peek().phase):toBe("playing")
					world.model.step(0.05, true)
					Verify.expect((find(tiles, "Tile_1_12"))):toBe(retained)
					for column = 1, 1000 do
						local state = table.clone(world.model.flap.state:peek())
						state.x = column * 32
						world.model.flap.state:set(state)
						Verify.expect(#tiles:GetChildren() <= 130):toBe(true)
					end
					Verify.expect(retained.Parent == nil):toBe(true)
					world.model.selectedTab:set("Chat")
					Verify.expect(world.model.flap.state:peek().phase):toBe("paused")
					local paused = world.model.flap.state:peek()
					world.model.flapPress()
					world.model.step(0.05, false)
					Verify.expect((world.model.flap.state:peek())):toBe(paused)
					world.model.selectedTab:set("Flap")
					world.model.flapPress()
					Verify.expect(world.model.flap.state:peek().phase):toBe("playing")
				end)
			end,
		})

		verifyHarness:case("rejects nonnative Path2D paint properties in the engine fixture", {
			id = "native_virtual_monitors::native virtual monitors::rejects nonnative Path2D paint properties in the engine fixture",
			run = function()
				local engine = engineModule.new()
				local path = engine.new("Path2D")
				for _, property in { "Color", "BackgroundColor3" } do
					local ok, failure = pcall(function()
						path[property] = engine.types.Color3.new(1, 0, 0)
					end)
					Verify.expect(ok):toBe(false)
					Verify.expect(string.find(tostring(failure), property .. " is not a valid member", 1, true) ~= nil)
						:toBe(true)
				end
				path.Color3 = engine.types.Color3.new(1, 0, 0)
				path.Closed = true
				path.Thickness = 3
				Verify.expect(path.Color3):toBe(engine.types.Color3.new(1, 0, 0))
				Verify.expect(path.Closed):toBe(true)
				Verify.expect(path.Thickness):toBe(3)
				path:Destroy()
			end,
		})
		verifyHarness:case("plays the showcase press haptic only from monitor controls that change a value", {
			id = "native_virtual_monitors::native virtual monitors::plays the showcase press haptic only from monitor controls that change a value",
			run = function()
				local effect = engineModule.new().new("HapticEffect")
				withScreens(function(world)
					local buzzing, quiet = 0, 0
					for _, name in screens.APPS do
						for _, node in world[name]:GetDescendants() do
							if node:HasTag("facet-button") then
								local changesValue = node:HasTag("facet-toggle")
									or node:HasTag("facet-chip")
									or (node:HasTag("facet-segment") and not node:HasTag("facet-segment-current"))
								Verify.expect(node.PressHapticEffect):toBe(if changesValue then effect else nil)
								if changesValue then
									buzzing += 1
								else
									quiet += 1
								end
							end
						end
					end
					Verify.expect(buzzing > 0):toBe(true)
					Verify.expect(quiet > buzzing):toBe(true)
				end, { pressHaptic = effect })
			end,
		})

		verifyHarness:case("filters and sorts the full catalog with stable tie order", {
			id = "native_virtual_monitors::native virtual monitors::filters and sorts the full catalog with stable tie order",
			run = function()
				withModel(function(model)
					Verify.expect(#model.catalog.items:peek()):toBe(36)
					model.discoveryScroll:set(472)
					model.genre:set("Adventure")
					Verify.expect((model.discoveryScroll:peek())):toBe(0)
					for _, item in model.visibleGames:peek() do
						Verify.expect(item.genre):toBe("Adventure")
					end
					model.discoveryScroll:set(236)
					model.query:set("chapter 2")
					Verify.expect((model.discoveryScroll:peek())):toBe(0)
					Verify.expect(#model.visibleGames:peek()):toBe(2)
					model.query:set("")
					model.genre:set("all")
					model.sort:set("rating")
					local games = model.visibleGames:peek()
					for i = 2, #games do
						Verify.expect(games[i - 1].percent >= games[i].percent):toBe(true)
						if games[i - 1].percent == games[i].percent then
							Verify.expect(games[i - 1].index < games[i].index):toBe(true)
						end
					end
					model.catalog.seen(35)
					model.catalog.step()
					Verify.expect(#model.catalog.items:peek()):toBe(72)
				end)
			end,
		})

		verifyHarness:case("preserves saved order notes ratings and settings across mode changes", {
			id = "native_virtual_monitors::native virtual monitors::preserves saved order notes ratings and settings across mode changes",
			run = function()
				withModel(function(model)
					model.toggleSaved("1")
					model.toggleSaved("2")
					model.setNote("1", "Play with friends")
					model.rate("1", 3)
					model.reorderSaved({ "2" }, 0)
					Verify.expect(model.savedGames:peek()[1].id):toBe("2")
					model.palette:set("iris")
					model.focus("Avatar")
					model.toggleMode()
					Verify.expect((model.mode:peek())):toBe("Screen")
					Verify.expect((model.selectedTab:peek())):toBe("Avatar")
					model.toggleMode()
					Verify.expect(model.notes:peek()["1"]):toBe("Play with friends")
					Verify.expect(model.ratings:peek()["1"]):toBe(3)
					Verify.expect((model.palette:peek())):toBe("iris")
					model.toggleSaved("2")
					Verify.expect(#model.savedGames:peek()):toBe(1)
					Verify.expect(model.savedGames:peek()[1].id):toBe("1")
				end)
			end,
		})

		verifyHarness:case("has one model spin driver with reduced-motion and reset semantics", {
			id = "native_virtual_monitors::native virtual monitors::has one model spin driver with reduced-motion and reset semantics",
			run = function()
				withModel(function(model)
					model.angle:set(0)
					model.autoSpin:set(1)
					model.step(0.1, false)
					Verify.expect((model.angle:peek())):toBe(3)
					model.step(0.1, true)
					Verify.expect((model.angle:peek())):toBe(3)
					model.turnStep:set(90)
					model.turn(1)
					Verify.expect((model.angle:peek())):toBe(93)
					model.resetAvatar()
					Verify.expect((model.angle:peek())):toBe(-15)
					Verify.expect((model.autoSpin:peek())):toBe(1)
					Verify.expect((model.turnStep:peek())):toBe(90)
				end)
			end,
		})

		verifyHarness:case("streams replies and preserves the conversation through presentation changes", {
			id = "native_virtual_monitors::native virtual monitors::streams replies and preserves the conversation through presentation changes",
			run = function()
				withModel(function(model)
					model.prompt("What game should I play with friends?")
					Verify.expect((model.chat.send())):toBe(true)
					for _ = 1, 8 do
						model.step(0.1, false)
					end
					local messages = model.chat.messages:peek()
					Verify.expect(#messages):toBe(2)
					Verify.expect(#messages[2].content > 0):toBe(true)
					model.toggleMode()
					Verify.expect(#model.chat.messages:peek()):toBe(2)
					model.chat.stop()
					local content = model.chat.messages:peek()[2].content
					model.step(0.1, false)
					Verify.expect(model.chat.messages:peek()[2].content):toBe(content)
					model.chat.remove(messages[1].id)
					Verify.expect(#model.chat.messages:peek()):toBe(1)
					model.chat.clear()
					Verify.expect(#model.chat.messages:peek()):toBe(0)
				end)
			end,
		})

		verifyHarness:case("mounts the actual three screens and drives their controls through native events", {
			id = "native_virtual_monitors::native virtual monitors::mounts the actual three screens and drives their controls through native events",
			run = function()
				local Facet = require("../src")
				local engine = engineModule.new()
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local target = engine.new("ScreenGui")
				local lifetime = Compose.createRootOwner(function()
					local model = modelModule.new(Compose)
					Compose.cleanup(model.dispose)
					local views = screens.create(
						Facet,
						runtime,
						{ model = model, types = engine.types, spatial = true, motionLevel = "none" }
					)
					local _, discovery: any = runtime.mount(views.Discover, target)
					local _, avatar: any = runtime.mount(views.Avatar, target)
					local _, chat: any = runtime.mount(views.Chat, target)
					Verify.expect(discovery.ClassName):toBe("Frame")
					Verify.expect(avatar.ClassName):toBe("Frame")
					Verify.expect(chat.ClassName):toBe("Frame")
					for _, surface in { discovery, avatar, chat } do
						Verify.expect((surface:HasTag("facet-surface"))):toBe(true)
						local title = find(find(surface, "Header"), "Title")
						Verify.expect((title:HasTag("facet-text"))):toBe(true)
						Verify.expect((title:HasTag("facet-type-heading"))):toBe(true)
					end
					Verify.expect(find(find(chat, "Header"), "Title").Text):toBe("Assistant")
					find(discovery, "WakeMonitor").Activated:Fire()
					Verify.expect(find(find(discovery, "HeaderActions"), "Profile") ~= nil):toBe(true)
					Verify.expect(find(discovery, "SearchShortcut") ~= nil):toBe(true)
					local focusSearch = find(discovery, "FocusSearch")
					Verify.expect(focusSearch.ClassName):toBe("InputAction")
					local editor = find(find(discovery, "Search"), "Editor")
					local focused = false
					editor.Focused:Connect(function()
						focused = true
					end)
					focusSearch.Released:Fire()
					Verify.expect(focused or editor:IsFocused()):toBe(true)
					editor:ReleaseFocus(false)
					find(find(discovery, "Search"), "Editor"):CaptureFocus()
					find(find(discovery, "Search"), "Editor").Text = "Circuit"
					Verify.expect((model.query:peek())):toBe("Circuit")
					local grid = find(discovery, "Games")
					grid.AbsoluteWindowSize = engine.types.Vector2.new(850, 260)
					Verify.expect(find(discovery, "Game_2") ~= nil):toBe(true)
					Verify.expect((find(find(discovery, "Game_2"), "Body"):HasTag("facet-panel"))):toBe(true)
					Verify.expect((find(find(discovery, "Game_2"), "Caption"):HasTag("facet-secondary"))):toBe(true)
					saveCard(find(discovery, "Game_2"))
					Verify.expect(model.saved:peek()["2"]):toBe(true)
					find(find(discovery, "Game_2"), "Body").Activated:Fire()
					Verify.expect(model.selectedGame:peek().id):toBe("2")
					Verify.expect(find(target, "GameDetails") ~= nil):toBe(true)
					local play = find(target, "Play")
					find(play, "Primary").Activated:Fire()
					Verify.expect(model.launch:peek().id):toBe("2")
					Verify.expect(model.launch:peek().mode):toBe("Joining a public server")
					Verify.expect(find(target, "LaunchStatus").Text):toBe("Joining a public server… (simulated)")
					local steps = find(target, "LaunchSteps")
					Verify.expect((steps:GetAttribute("FacetCurrent"))):toBe("find")
					for _ = 1, 10 do
						model.step(0.1, false)
					end
					Verify.expect((steps:GetAttribute("FacetCurrent"))):toBe("load")
					for _ = 1, 20 do
						model.step(0.1, false)
					end
					Verify.expect(find(target, "LaunchStatus").Text):toBe("Joined (simulated)")
					local alternatives = find(play, "Alternatives");
					(alternatives:FindFirstChild("Trigger", true) or alternatives).Activated:Fire()
					local private
					for _, node in target:GetDescendants() do
						if node.Name == "Private" and node:IsA("GuiButton") then
							private = node
						end
					end
					private.Activated:Fire()
					Verify.expect(model.launch:peek().mode):toBe("Starting a private server")
					rate(target, 3, engine.types)
					Verify.expect(model.ratings:peek()["2"]):toBe(3)
					find(find(target, "DetailSection"), "similar").Activated:Fire()
					find(target, "Similar_8").Activated:Fire()
					Verify.expect(model.selectedGame:peek().id):toBe("8")
					find(target, "close").Activated:Fire()
					Verify.expect((model.selectedGame:peek())):toBe(nil)
					find(discovery, "Saved").Activated:Fire()
					local saved = find(discovery, "SavedGames")
					find(saved, "Body").AbsoluteWindowSize = engine.types.Vector2.new(850, 260)
					Verify.expect(find(find(saved, "Header"), "genre") ~= nil):toBe(true)
					local note = find(saved, "Note_2")
					note:CaptureFocus()
					note.Text = "Try this weekend"
					note.FocusLost:Fire(true)
					Verify.expect(model.notes:peek()["2"]):toBe("Try this weekend")
					find(avatar, "WakeMonitor").Activated:Fire()
					find(avatar, "MotionRow").Activated:Fire()
					find(avatar, "TurnRight").Activated:Fire()
					Verify.expect((model.angle:peek())):toBe(15)
					find(chat, "WakeMonitor").Activated:Fire()
					find(chat, "FindGame").Activated:Fire()
					Verify.expect((model.chat.draft:peek())):toBe("What game should I play with friends?")
					find(chat, "Send").Activated:Fire()
					Verify.expect((model.chat.streaming:peek())):toBe(true)
				end, runtime.reactor)
				lifetime.dispose()
				Verify.expect(#target:GetChildren()):toBe(0)
				runtime:dispose()
			end,
		})
		verifyHarness:case("NVM-1 wakes monitors repeatedly without activating sleeping content", {
			id = "native_virtual_monitors::native virtual monitors::NVM-1 wakes monitors repeatedly without activating sleeping content",
			run = function()
				withScreens(function(world)
					local model, discover, avatar, chat = world.model, world.Discover, world.Avatar, world.Chat
					for _, name in { "Discover", "Chat", "Discover", "Avatar" } do
						local node = world[name]
						Verify.expect(find(node, "WakeMonitor").Visible):toBe(true)
						Verify.expect(find(node, "Page"):FindFirstChild("Content").Interactable):toBe(false)
						find(node, "WakeMonitor").Activated:Fire()
						Verify.expect((model.focused:peek())):toBe(name)
						Verify.expect(find(node, "Focus").Text):toBe("All monitors")
						Verify.expect(find(node, "Page"):FindFirstChild("Content").Interactable):toBe(true)
						find(node, "Focus").Activated:Fire()
						Verify.expect((model.focused:peek())):toBe("Overview")
						Verify.expect(find(node, "Focus").Text):toBe("Focus")
					end
					find(discover, "Games").AbsoluteWindowSize = world.types.Vector2.new(820, 260)
					saveCard(find(discover, "Game_1"))
					Verify.expect((next(model.saved:peek()))):toBe(nil)
					find(discover, "WakeMonitor").Activated:Fire()
					Verify.expect((next(model.saved:peek()))):toBe(nil)
					saveCard(find(discover, "Game_1"))
					Verify.expect(model.saved:peek()["1"]):toBe(true)
					Verify.expect(model.toasts.Discover:peek().message):toBe("Saved Afterlight")
				end, { spatial = true })
			end,
		})

		verifyHarness:case("NVM-2 retains native avatar controls across narrow layouts and expands live HUD", {
			id = "native_virtual_monitors::native virtual monitors::NVM-2 retains native avatar controls across narrow layouts and expands live HUD",
			run = function()
				withScreens(function(world)
					local avatar, model, types = world.Avatar, world.model, world.types
					Verify.expect((find(avatar, "Rotation"))):toBe(nil)
					find(avatar, "MotionRow").Activated:Fire()
					Verify.expect(model.avatarPath:peek()[1].id):toBe("motion")
					Verify.expect(find(find(avatar, "motion"), "Title").Text):toBe("Motion & turning")
					local body, rotation = find(avatar, "AvatarBody"), find(avatar, "Rotation")
					local preview, settings = find(avatar, "PreviewPanel"), find(avatar, "AvatarSettings")
					for _, width in { 920, 760, 759, 393, 360, 320, 920 } do
						body.AbsoluteSize = types.Vector2.new(width, 610)
						Verify.expect((find(avatar, "Rotation"))):toBe(rotation)
						Verify.expect(find(avatar, "SettingsPage").ScrollingDirection)
							:toBe(types.Enum.ScrollingDirection.Y)
						Verify.expect(find(avatar, "MotionPage").ScrollingDirection)
							:toBe(types.Enum.ScrollingDirection.Y)
						Verify.expect(find(avatar, "LookRich") ~= nil):toBe(width >= 760)
						local flow = body:FindFirstChildWhichIsA("UIListLayout")
						Verify.expect(flow.Wraps):toBe(true)
						Verify.expect(flow.Padding.Offset):toBe(16)
						Verify.expect(flow.FillDirection):toBe(types.Enum.FillDirection.Horizontal)
						Verify.expect(preview.LayoutOrder < settings.LayoutOrder):toBe(true)
						if width >= 760 then
							local edge = preview.Size.X.Scale * width + preview.Size.X.Offset
							local span = settings.Size.X.Scale * width + settings.Size.X.Offset
							Verify.expect(math.abs(edge + 16 + span - width) < 0.001):toBe(true)
							Verify.expect(settings.Size.Y.Scale):toBe(1)
						else
							Verify.expect(preview.Size.X.Scale):toBe(1)
							Verify.expect(settings.Size.X.Scale):toBe(1)
							local stacked = preview.Size.Y.Offset
								+ 16
								+ settings.Size.Y.Scale * 610
								+ settings.Size.Y.Offset
							Verify.expect(math.abs(stacked - 610) < 0.001):toBe(true)
						end
					end
					Verify.expect(settings.SelectionGroup):toBe(true)
					for _, direction in { "Up", "Down", "Left", "Right" } :: { "Down" | "Left" | "Right" | "Up" } do
						Verify.expect(settings["SelectionBehavior" .. direction])
							:toBe(types.Enum.SelectionBehavior.Escape)
					end
					Verify.expect((settings:HasTag("facet-panel"))):toBe(true)
					Verify.expect((preview:HasTag("facet-panel"))):toBe(true)
					body.AbsoluteSize = types.Vector2.new(393, 610)
					model.palette:set("iris")
					model.hat:set(false)
					model.turnStep:set(45)
					model.autoSpin:set(2)
					model.angle:set(30)
					Verify.expect(find(avatar, "ExpandLook").Text):toBe("Iris")
					Verify.expect(find(avatar, "ExpandRotation").Text):toBe("30°")
					Verify.expect(find(avatar, "ExpandSpin").Text):toBe("Medium")
					find(avatar, "ExpandLook").Activated:Fire()
					Verify.expect((model.avatarSummary:peek())):toBe(true)
					Verify.expect(find(world.target, "SheetPanel") ~= nil):toBe(true)
					for id, expected in
						{ Palette = "Iris", Hat = "Off", Rotation = "30°", TurnStep = "45°", AutoSpin = "Medium" } :: { [string]: string }
					do
						Verify.expect(find(find(world.target, "Summary" .. id), "Value").Text):toBe(expected)
					end
					model.angle:set(45)
					Verify.expect(find(find(world.target, "SummaryRotation"), "Value").Text):toBe("45°")
					model.avatarSummaryDetent:set("large")
					find(world.target, "Done").Activated:Fire()
					Verify.expect((model.avatarSummary:peek())):toBe(false)
					find(find(avatar, "motion"), "Back").Activated:Fire()
					Verify.expect(#model.avatarPath:peek()):toBe(0)
					find(avatar, "Summary").Activated:Fire()
					Verify.expect((model.avatarSummaryDetent:peek())):toBe("large")
					find(world.target, "Done").Activated:Fire()
					find(avatar, "MotionRow").Activated:Fire()
					find(avatar, "TurnRight").Activated:Fire()
					Verify.expect((model.angle:peek())):toBe(90)
					find(find(avatar, "motion"), "Back").Activated:Fire()
					find(avatar, "Tips").Activated:Fire()
					Verify.expect((model.avatarTipsExpanded:peek())):toBe(true)
					Verify.expect(find(world.target, "PreviewTips") ~= nil):toBe(true)
					find(find(world.target, "Expanded"), "Close").Activated:Fire()
					Verify.expect((model.avatarTipsExpanded:peek())):toBe(false)
					Verify.expect((find(world.target, "PreviewTips"))):toBe(nil)
					find(find(avatar, "SettingsDisclosure"), "Header").Activated:Fire()
					Verify.expect((model.avatarSettingsExpanded:peek())):toBe(false)
					Verify.expect((find(avatar, "AppearanceSettings"))):toBe(nil)
					find(find(avatar, "SettingsDisclosure"), "Header").Activated:Fire()
					Verify.expect(find(avatar, "Hat") ~= nil):toBe(true)
					find(avatar, "Reset").Activated:Fire()
					find(world.target, "reset").Activated:Fire()
					Verify.expect((model.palette:peek())):toBe("sage")
					Verify.expect((model.hat:peek())):toBe(true)
					Verify.expect((model.angle:peek())):toBe(-15)
					Verify.expect((model.turnStep:peek())):toBe(45)
					Verify.expect(#model.avatarPath:peek()):toBe(0)
					Verify.expect(find(avatar, "MotionRow") ~= nil):toBe(true)
					Verify.expect((model.autoSpin:peek())):toBe(2)
				end)
			end,
		})

		verifyHarness:case("NVM-3 adapts chrome and featured content while keeping menu actions functional", {
			id = "native_virtual_monitors::native virtual monitors::NVM-3 adapts chrome and featured content while keeping menu actions functional",
			run = function()
				withScreens(function(world)
					local discover, model, types = world.Discover, world.model, world.types
					local body = find(discover, "DiscoverBody")
					body.AbsoluteSize = types.Vector2.new(1000, 800)
					local featured = find(discover, "Featured")
					Verify.expect(find(featured, "PagesLayout").TouchInputEnabled):toBe(true)
					Verify.expect(find(featured, "FeaturedDescription") ~= nil):toBe(true)
					Verify.expect(find(featured, "FeaturedFacts") ~= nil):toBe(true)
					find(find(featured, "Indicators"), "2").Activated:Fire()
					Verify.expect((model.featuredSelection:peek())):toBe("2")
					find(featured, "ExploreFeatured_2").Activated:Fire()
					Verify.expect(model.selectedGame:peek().id):toBe("2")
					find(world.target, "close").Activated:Fire()
					local search = find(discover, "Search")
					body.AbsoluteSize = types.Vector2.new(390, 410)
					Verify.expect((find(discover, "Featured"))):toBe(nil)
					Verify.expect((find(discover, "Search"))):toBe(search)
					Verify.expect(search.Size.Y.Offset):toBe(44)
					Verify.expect(search.Size.X.Scale):toBe(1)
					local controls = find(discover, "SearchControls")
					Verify.expect(controls:FindFirstChildWhichIsA("UIListLayout").Wraps):toBe(true)
					Verify.expect(controls.AutomaticSize):toBe(types.Enum.AutomaticSize.Y)
					Verify.expect(find(controls, "Sort").Size.X.Scale):toBe(1)
					Verify.expect(find(discover, "SearchShortcut").Visible):toBe(false)
					local genres = find(discover, "Genres")
					Verify.expect(genres.ClassName):toBe("ScrollingFrame")
					Verify.expect(genres.ScrollingDirection):toBe(types.Enum.ScrollingDirection.X)
					Verify.expect(genres.LayoutOrder > controls.LayoutOrder):toBe(true)
					Verify.expect((find(genres, "Genre_all"):GetAttribute("selected"))):toBe(true)
					find(genres, "Genre_Racing").Activated:Fire()
					Verify.expect((model.genre:peek())):toBe("Racing")
					Verify.expect((find(genres, "Genre_Racing"):GetAttribute("selected"))):toBe(true)
					Verify.expect((find(genres, "Genre_all"):GetAttribute("selected"))):toBe(false)
					find(find(discover, "Sort"), "Trigger").Activated:Fire()
					find(find(world.target, "MenuPanel"), "rating").Activated:Fire()
					Verify.expect((model.sort:peek())):toBe("rating")
					model.query:set("definitely absent")
					Verify.expect((find(discover, "NoResults"):GetAttribute("NoticeSeverity"))):toBe("info")
					Verify.expect(find(find(discover, "NoResults"), "Title").Text):toBe("No games match")
					find(discover, "ClearFilters").Activated:Fire()
					Verify.expect((find(discover, "NoResults"))):toBe(nil)
					Verify.expect((model.genre:peek())):toBe("all")
					Verify.expect((model.query:peek())):toBe("")
					local editor = find(search, "Editor")
					editor:CaptureFocus()
					editor.Text = "Circuit"
					Verify.expect(find(world.target, "MenuPanel") ~= nil):toBe(true)
					find(find(world.target, "MenuPanel"), "2").Activated:Fire()
					Verify.expect(model.selectedGame:peek().id):toBe("2")
					find(world.target, "close").Activated:Fire()
					discover.AbsoluteSize = types.Vector2.new(393, 690)
					Verify.expect(find(discover, "Chrome").Visible):toBe(false)
					local more = find(discover, "ActionsMenu")
					Verify.expect((more:GetAttribute("label"))):toBe("Menu")
					Verify.expect(find(more, "LeadingIcon") ~= nil):toBe(true)
					more.Activated:Fire()
					find(find(world.target, "MenuPanel"), "About").Activated:Fire()
					local dialog = find(world.target, "DialogModal")
					Verify.expect(dialog ~= nil):toBe(true)
					Verify.expect(find(dialog, "AboutScene") ~= nil):toBe(true)
					Verify.expect(string.find(find(dialog, "AboutVersion").Text, "Facet 0.", 1, true) ~= nil):toBe(true)
					find(dialog, "done").Activated:Fire()
					Verify.expect((find(world.target, "DialogModal"))):toBe(nil)
				end)
			end,
		})

		verifyHarness:case(
			"NVM-23 gives a short screen one toolbar row and collapses the header while the grid scrolls",
			{
				id = "native_virtual_monitors::native virtual monitors::NVM-23 gives a short screen one toolbar row and collapses the header while the grid scrolls",
				run = function()
					withScreens(function(world)
						local discover, model, types = world.Discover, world.model, world.types
						local body = find(discover, "DiscoverBody")
						local header, genres = find(discover, "Header"), find(discover, "Genres")
						local controls, shelves = find(discover, "SearchControls"), find(discover, "Shelves")
						Verify.expect(shelves.Parent):toBe(controls)
						discover.AbsoluteSize = types.Vector2.new(574, 369)
						body.AbsoluteSize = types.Vector2.new(542, 300)
						Verify.expect(find(controls, "Search").Size.X.Scale):toBe(0)
						Verify.expect(find(controls, "Sort").Size):toBe(types.UDim2.fromOffset(150, 44))
						Verify.expect(shelves.Size.X.Scale):toBe(0)
						Verify.expect(shelves.AutomaticSize):toBe(types.Enum.AutomaticSize.XY)
						Verify.expect(find(shelves, "Count").Visible):toBe(false)
						Verify.expect(header.Visible):toBe(true)
						local grid = find(discover, "Games")
						grid.AbsoluteWindowSize = types.Vector2.new(542, 180)
						grid.CanvasPosition = types.Vector2.new(0, 30)
						Verify.expect(header.Visible):toBe(true)
						grid.CanvasPosition = types.Vector2.new(0, 120)
						Verify.expect(header.Visible):toBe(false)
						Verify.expect(genres.Visible):toBe(false)
						Verify.expect(controls.Visible):toBe(true)
						grid.CanvasPosition = types.Vector2.new(0, 30)
						Verify.expect(header.Visible):toBe(false)
						grid.CanvasPosition = types.Vector2.new(0, 0)
						Verify.expect(header.Visible):toBe(true)
						Verify.expect(genres.Visible):toBe(true)
						grid.CanvasPosition = types.Vector2.new(0, 120)
						Verify.expect(header.Visible):toBe(false)
						model.shelf:set("saved")
						Verify.expect(header.Visible):toBe(true)
						model.shelf:set("browse")
						discover.AbsoluteSize = types.Vector2.new(390, 780)
						body.AbsoluteSize = types.Vector2.new(358, 640)
						Verify.expect(header.Visible):toBe(true)
						Verify.expect(find(controls, "Search").Size.X.Scale):toBe(1)
						Verify.expect(find(controls, "Sort").Size.X.Scale):toBe(1)
						Verify.expect(shelves.Size.X.Scale):toBe(1)
						Verify.expect(find(shelves, "Count").Visible):toBe(true)
						local tall = find(discover, "Games")
						tall.AbsoluteWindowSize = types.Vector2.new(358, 420)
						tall.CanvasPosition = types.Vector2.new(0, 400)
						Verify.expect(header.Visible):toBe(true)
						Verify.expect(genres.Visible):toBe(true)
					end)
				end,
			}
		)

		verifyHarness:case(
			"opens from the entire catalog card while preserving preview save drag and native identity",
			{
				id = "native_virtual_monitors::native virtual monitors::opens from the entire catalog card while preserving preview save drag and native identity",
				run = function()
					withScreens(function(world)
						local discover, model, types = world.Discover, world.model, world.types
						find(discover, "Games").AbsoluteWindowSize = types.Vector2.new(820, 260)
						for _ = 1, 4 do
							world.engine.heartbeat:Fire(1 / 60)
						end
						local item = model.catalog.items:peek()[1]
						local card = find(discover, "Game_1")
						local body, preview = find(card, "Body"), find(card, "Preview")
						local scene = preview:FindFirstChildWhichIsA("ViewportFrame")
						Verify.expect(card.ClassName):toBe("Frame")
						Verify.expect((card:GetAttribute("FacetBody"))):toBe("button")
						Verify.expect(body.ClassName):toBe("TextButton")
						Verify.expect(body.Selectable):toBe(true)
						Verify.expect(preview.Parent.Name):toBe("Artwork")
						Verify.expect(preview.Size):toBe(types.UDim2.fromScale(1, 1))
						Verify.expect(preview.ClipsDescendants):toBe(true)
						Verify.expect(scene.Active):toBe(false)
						Verify.expect((find(card, "Open"))):toBe(nil)
						Verify.expect(find(card, "Title").Text):toBe(item.title)
						Verify.expect(find(card, "Caption").Text):toBe(item.rating .. "  ·  " .. item.players)
						Verify.expect(find(preview, "LiveDot") ~= nil):toBe(true)
						Verify.expect((card:GetAttribute("FacetRevealed"))):toBe(false)
						engage(card)
						Verify.expect((card:GetAttribute("FacetRevealed"))):toBe(true)
						local save = find(card, "Primary")
						Verify.expect((save:GetAttribute("label"))):toBe("Save")
						local icon = save:FindFirstChildWhichIsA("ImageLabel", true)
						local unsavedImage = icon.Image
						save.Activated:Fire()
						Verify.expect(model.saved:peek()["1"]):toBe(true)
						Verify.expect((save:GetAttribute("label"))):toBe("Saved")
						Verify.expect(icon.Image ~= unsavedImage):toBe(true)
						Verify.expect((model.selectedGame:peek())):toBe(nil)
						body.Activated:Fire()
						Verify.expect(model.selectedGame:peek().id):toBe("1")
						Verify.expect(find(world.target, "AlertModal") ~= nil):toBe(true)
						find(world.target, "close").Activated:Fire()
						model.catalog.items:update(function(items)
							local next = table.clone(items)
							next[1] = table.clone(next[1])
							next[1].title = "Afterlight revisited"
							return next
						end)
						Verify.expect((find(discover, "Game_1"))):toBe(card)
						Verify.expect((preview:FindFirstChildWhichIsA("ViewportFrame"))):toBe(scene)
						Verify.expect(find(card, "Title").Text):toBe("Afterlight revisited")
						body.Activated:Fire()
						Verify.expect(model.selectedGame:peek().title):toBe("Afterlight revisited")
						local actions = find(find(find(discover, "Header"), "Trailing"), "HeaderActions")
						local chrome, menu, profile =
							find(actions, "Chrome"), find(actions, "ActionsMenu"), find(actions, "Profile")
						Verify.expect(chrome.LayoutOrder < menu.LayoutOrder and menu.LayoutOrder < profile.LayoutOrder)
							:toBe(true)
						Verify.expect(chrome.Visible):toBe(true)
						Verify.expect(menu.Visible):toBe(false)
					end)
				end,
			}
		)

		verifyHarness:case(
			"NVM-20 offers Share, Not interested and Report from each card and undoes a save or a hide",
			{
				id = "native_virtual_monitors::native virtual monitors::NVM-20 offers Share, Not interested and Report from each card and undoes a save or a hide",
				run = function()
					withScreens(function(world)
						local discover, model, types = world.Discover, world.model, world.types
						find(discover, "Games").AbsoluteWindowSize = types.Vector2.new(820, 260)
						local card = engage(find(discover, "Game_3"))
						find(card, "More").Activated:Fire()
						local panel = find(world.target, "MenuPanel")
						Verify.expect(find(panel, "Share") ~= nil):toBe(true)
						Verify.expect((find(panel, "Report"):GetAttribute("role"))):toBe("destructive")
						find(panel, "Hide").Activated:Fire()
						Verify.expect(model.hidden:peek()["3"]):toBe(true)
						for _, game in model.visibleGames:peek() do
							Verify.expect(game.id ~= "3"):toBe(true)
						end
						local toast = find(discover, "DiscoverToast")
						Verify.expect(toast ~= nil):toBe(true)
						local snack = find(world.target, "Snack")
						Verify.expect(find(snack, "Message").Text):toBe("Terrarium is hidden")
						find(snack, "Action").Activated:Fire()
						Verify.expect(model.hidden:peek()["3"]):toBe(nil)
						Verify.expect((model.toasts.Discover:peek())):toBe(nil)
						saveCard(find(discover, "Game_2"))
						Verify.expect(model.saved:peek()["2"]):toBe(true)
						Verify.expect(find(find(world.target, "Snack"), "Message").Text):toBe("Saved Circuit")
						find(find(world.target, "Snack"), "Action").Activated:Fire()
						Verify.expect(model.saved:peek()["2"]):toBe(nil)
						local badge = find(discover, "Saved+badge")
						Verify.expect(badge ~= nil):toBe(true)
						Verify.expect((find(badge, "CornerBadge"))):toBe(nil)
						model.toggleSaved("5")
						local seal = find(badge, "CornerBadge")
						Verify.expect(seal ~= nil):toBe(true)
						Verify.expect(seal.Text):toBe("1")
					end)
				end,
			}
		)

		verifyHarness:case(
			"NVM-21 sets presence, schedules a session, types an exact angle and counts unread replies",
			{
				id = "native_virtual_monitors::native virtual monitors::NVM-21 sets presence, schedules a session, types an exact angle and counts unread replies",
				run = function()
					withScreens(function(world)
						local model, types = world.model, world.types
						local profile = find(world.Discover, "Profile")
						profile.Activated:Fire()
						local card = find(world.target, "PresenceCard")
						Verify.expect(card ~= nil):toBe(true)
						local dot = find(card, "PresenceDot")
						Verify.expect((dot:GetAttribute("AccessibleLabel"))):toBe("Online")
						Verify.expect((profile:GetAttribute("AccessibleLabel"))):toBe("You, online")
						find(find(card, "Presence"), "away").Activated:Fire()
						Verify.expect((model.presence:peek())):toBe("away")
						Verify.expect((find(world.target, "PresenceCard"))):toBe(nil)
						Verify.expect((profile:GetAttribute("AccessibleLabel"))):toBe("You, away")
						Verify.expect((find(world.Chat, "Profile"):GetAttribute("AccessibleLabel"))):toBe("You, away")
						local first = model.catalog.items:peek()[1]
						model.selectGame(first)
						local session = find(world.target, "Session")
						Verify.expect((session:HasTag("facet-date-time-picker"))):toBe(true)
						local entry = find(session, "Entry")
						entry:CaptureFocus()
						entry.Text = "10/03/2030 7:30 PM"
						entry.FocusLost:Fire(true)
						local scheduled = model.sessions:peek()[first.id]
						Verify.expect(scheduled.year):toBe(2030)
						Verify.expect(scheduled.month):toBe(10)
						Verify.expect(scheduled.day):toBe(3)
						Verify.expect(scheduled.hour):toBe(19)
						Verify.expect(scheduled.minute):toBe(30)
						Verify.expect(
							string.find(find(find(session, "Message"), "Validation").Text, "10/03/2030", 1, true) ~= nil
						)
							:toBe(true)
						find(world.target, "close").Activated:Fire()
						find(world.Avatar, "MotionRow").Activated:Fire()
						local exact = find(world.Avatar, "ExactAngle")
						Verify.expect(find(exact, "Suffix").Text):toBe("°")
						local field = find(exact, "Field")
						field:CaptureFocus()
						field.Text = "90+45"
						field.FocusLost:Fire(true)
						Verify.expect((model.angle:peek())):toBe(135)
						model.angle:set(-30)
						Verify.expect(field.Text):toBe("-30")
						model.mode:set("Screen")
						model.selectedTab:set("Discover")
						model.chat.draft:set("What game should I play with friends?")
						model.chat.send()
						for _ = 1, 80 do
							model.step(0.1, false)
						end
						Verify.expect((model.chat.streaming:peek())):toBe(false)
						Verify.expect((model.chatUnread:peek())):toBe(1)
						model.selectedTab:set("Chat")
						Verify.expect((model.chatUnread:peek())):toBe(0)
						local _ = types
					end)
				end,
			}
		)

		verifyHarness:case("NVM-22 contains a malformed pose in Avatar and restores the app on Try again", {
			id = "native_virtual_monitors::native virtual monitors::NVM-22 contains a malformed pose in Avatar and restores the app on Try again",
			run = function()
				withScreens(function(world)
					local model = world.model
					model.angle:set("15deg" :: any)
					local boundary = find(world.Avatar, "AppBoundary")
					Verify.expect(boundary:GetAttribute("FacetError") ~= nil):toBe(true)
					Verify.expect((find(world.Avatar, "AvatarBody"))):toBe(nil)
					Verify.expect(find(find(world.Avatar, "AppFailure"), "FailureTitle").Text):toBe("Avatar stopped")
					Verify.expect(find(world.Discover, "DiscoverBody") ~= nil):toBe(true)
					Verify.expect(find(world.Chat, "ChatBody") ~= nil):toBe(true)
					Verify.expect(find(world.Avatar, "Header") ~= nil):toBe(true)
					model.angle:set(30)
					find(find(world.Avatar, "AppFailure"), "Retry").Activated:Fire()
					Verify.expect((boundary:GetAttribute("FacetError"))):toBe(nil)
					Verify.expect(find(world.Avatar, "AvatarBody") ~= nil):toBe(true)
					Verify.expect(find(world.Avatar, "LookRich") ~= nil):toBe(true)
				end, { onError = function() end })
			end,
		})

		verifyHarness:case("NVM-4 loads creator thumbnails with owned shimmer and stable native sparklines", {
			id = "native_virtual_monitors::native virtual monitors::NVM-4 loads creator thumbnails with owned shimmer and stable native sparklines",
			run = function()
				local pending, canceled = {}, {}
				withScreens(function(world)
					local model = world.model
					local first, second = model.catalog.items:peek()[1], model.catalog.items:peek()[2]
					model.dark:set(false)
					model.dark:set(true)
					find(world.Discover, "Games").AbsoluteWindowSize = world.types.Vector2.new(850, 260)
					find(find(world.Discover, "Game_" .. first.id), "Body").Activated:Fire()
					Verify.expect((find(world.Discover, "GameDetail"):GetAttribute("FacetError"))):toBe(nil)
					Verify.expect(find(world.target, "AlertModal") ~= nil):toBe(true)
					Verify.expect((model.selectedGame:peek())):toBe(first)
					local trend = find(find(world.target, "TrendLine"), "Stroke")
					Verify.expect(trend.ClassName):toBe("Path2D")
					Verify.expect((trend:HasTag("facet-path-accent"))):toBe(true)
					Verify.expect(#trend:GetControlPoints()):toBe(7)
					local arc = find(find(world.target, "RatingArc"), "Stroke")
					Verify.expect((arc:HasTag("facet-path-secondary"))):toBe(true)
					model.dark:set(false)
					Verify.expect((find(find(world.target, "TrendLine"), "Stroke"))):toBe(trend)
					local mark = find(world.Chat, "AssistantMark")
					Verify.expect(mark.Color3):toBe(world.types.Color3.fromRGB(91, 70, 140))
					Verify.expect(mark.Closed):toBe(true)
					Verify.expect(#mark:GetControlPoints()):toBe(8)
					model.dark:set(true)
					Verify.expect(mark.Color3):toBe(world.types.Color3.fromRGB(192, 172, 255))
					local image = find(world.target, "CreatorAvatar")
					Verify.expect(find(image, "CreatorShimmer") ~= nil):toBe(true)
					pending[first.creatorImage](first.creatorImage)
					Verify.expect((find(image, "CreatorShimmer"))):toBe(nil)
					Verify.expect(find(image, "Image").Image):toBe(first.creatorImage)
					Verify.expect(#find(find(world.target, "TrendLine"), "Stroke"):GetControlPoints()):toBe(7)
					local point = find(find(world.target, "TrendLine"), "Stroke"):GetControlPoints()[1].Position.Y.Scale
					model.selectGame(second)
					Verify.expect(canceled[first.creatorImage]):toBe(true)
					Verify.expect((image:isDestroyed())):toBe(true)
					Verify.expect(
						find(find(world.target, "TrendLine"), "Stroke"):GetControlPoints()[1].Position.Y.Scale ~= point
					)
						:toBe(true)
					model.selectGame(first)
					Verify.expect(
						find(find(world.target, "TrendLine"), "Stroke"):GetControlPoints()[1].Position.Y.Scale
					)
						:toBe(point)
					find(world.target, "AboutRating").Activated:Fire()
					local panel = find(world.target, "CalloutPanel")
					Verify.expect(find(panel, "RatingMeaning") ~= nil):toBe(true)
					find(panel, "Dismiss").Activated:Fire()
					Verify.expect((panel:isDestroyed())):toBe(true)
					Verify.expect((find(world.target, "RatingMeaning"))):toBe(nil)
				end, {
					creatorImageLoader = function(source, resolve)
						pending[source] = resolve
						return function()
							canceled[source] = true
						end
					end,
				})
			end,
		})

		verifyHarness:case("NVM-5 supports native card drop saving and similar-game contextual saving", {
			id = "native_virtual_monitors::native virtual monitors::NVM-5 supports native card drop saving and similar-game contextual saving",
			run = function()
				withScreens(function(world)
					local discover, model, types = world.Discover, world.model, world.types
					find(discover, "Games").AbsoluteWindowSize = types.Vector2.new(820, 260)
					local shelves = find(discover, "Shelves")
					shelves.AbsolutePosition, shelves.AbsoluteSize =
						types.Vector2.new(20, 80), types.Vector2.new(600, 40)
					nativeDrag.measure(shelves)
					local card = find(discover, "Game_1")
					local body, preview = find(card, "Body"), find(card, "Preview")
					local function dragTo(y: number)
						local mouse = world.engine.new("InputObject")
						mouse.UserInputType = types.Enum.UserInputType.MouseButton1
						mouse.Position = types.Vector3.new(60, 260, 0)
						nativeDrag.press(preview, mouse)
						nativeDrag.move(world.input, {
							UserInputType = types.Enum.UserInputType.MouseMovement,
							Position = types.Vector3.new(50, y, 0),
						})
						nativeDrag.finish(world.input, {
							UserInputType = types.Enum.UserInputType.MouseButton1,
							UserInputState = types.Enum.UserInputState.End,
							Position = types.Vector3.new(50, y, 0),
						})
					end
					dragTo(95)
					Verify.expect(model.saved:peek()["1"]):toBe(true)

					dragTo(95)
					Verify.expect(model.saved:peek()["1"]):toBe(true)
					Verify.expect(#model.savedOrder:peek()):toBe(1)
					body.Activated:Fire()
					find(find(world.target, "DetailSection"), "similar").Activated:Fire()
					local row = find(world.target, "SimilarRow_7")
					row.TouchLongPress:Fire({}, types.Enum.UserInputState.Begin)
					find(world.target, "trailing:SaveSimilar").Activated:Fire()
					Verify.expect(model.saved:peek()["7"]):toBe(true)
					find(world.target, "Similar_7").Activated:Fire()
					Verify.expect(model.selectedGame:peek().id):toBe("7")
					Verify.expect((model.detailTab:peek())):toBe("about")
				end)
			end,
		})

		verifyHarness:case("opens a card on a tap while a drag of its preview or a canceled drag never opens it", {
			id = "native_virtual_monitors::native virtual monitors::opens a card on a tap while a drag of its preview or a canceled drag never opens it",
			run = function()
				withScreens(function(world)
					local types, model, input = world.types, world.model, world.input
					find(world.Discover, "Games").AbsoluteWindowSize = types.Vector2.new(820, 260)
					local shelves = find(world.Discover, "Shelves")
					shelves.AbsolutePosition, shelves.AbsoluteSize =
						types.Vector2.new(20, 80), types.Vector2.new(600, 40)
					nativeDrag.measure(shelves)
					local card = find(world.Discover, "Game_1")
					local body, preview = find(card, "Body"), find(card, "Preview")
					local opened, selectGame = 0, model.selectGame
					model.selectGame = function(item)
						opened += 1
						selectGame(item)
					end
					local function press(): any
						local mouse = world.engine.new("InputObject")
						mouse.UserInputType = types.Enum.UserInputType.MouseButton1
						mouse.UserInputState = types.Enum.UserInputState.Begin
						mouse.Position = types.Vector3.new(60, 260, 0)
						nativeDrag.press(preview, mouse)
						return mouse
					end
					local function move(y: number)
						nativeDrag.move(input, {
							UserInputType = types.Enum.UserInputType.MouseMovement,
							Position = types.Vector3.new(50, y, 0),
						})
					end
					local function release(mouse: any, y: number, state: any?)
						mouse.UserInputState = state or types.Enum.UserInputState.End
						mouse.Position = types.Vector3.new(50, y, 0)
						nativeDrag.finish(input, mouse)
					end
					local click = press()
					release(click, 262)
					body.Activated:Fire(click)
					Verify.expect(opened):toBe(1)
					find(world.target, "close").Activated:Fire()
					local dragged = press()
					move(300)
					release(dragged, 300)
					body.Activated:Fire(dragged)
					Verify.expect(opened):toBe(1)
					Verify.expect(model.saved:peek()["1"]):toBe(nil)
					local saved = press()
					move(95)
					release(saved, 95)
					body.Activated:Fire(saved)
					Verify.expect(opened):toBe(1)
					Verify.expect(model.saved:peek()["1"]):toBe(true)
					model.toggleSaved("1")
					local canceled = press()
					move(95)
					release(canceled, 95, types.Enum.UserInputState.Cancel)
					body.Activated:Fire(canceled)
					Verify.expect(opened):toBe(1)
					Verify.expect(model.saved:peek()["1"]):toBe(nil)
					local blurred = press()
					move(95)
					input.WindowFocusReleased:Fire()
					release(blurred, 95)
					Verify.expect(model.saved:peek()["1"]):toBe(nil)
					Verify.expect((find(world.target, "DragGhost"))):toBe(nil)
					body.Activated:Fire()
					Verify.expect(opened):toBe(2)
				end)
			end,
		})

		verifyHarness:case(
			"keeps touch scrolling available until the native long press and saves only the held contact on release",
			{
				id = "native_virtual_monitors::native virtual monitors::keeps touch scrolling available until the native long press and saves only the held contact on release",
				run = function()
					withScreens(function(world)
						local types, model, input = world.types, world.model, world.input
						local states = types.Enum.UserInputState
						local games = find(world.Discover, "Games")
						games.AbsoluteWindowSize = types.Vector2.new(820, 260)
						games.ScrollingEnabled = true
						local shelves = find(world.Discover, "Shelves")
						shelves.AbsolutePosition, shelves.AbsoluteSize =
							types.Vector2.new(20, 80), types.Vector2.new(600, 40)
						nativeDrag.measure(shelves)
						local card = find(world.Discover, "Game_1")
						local body, preview = find(card, "Body"), find(card, "Preview")
						local scroller = preview:FindFirstAncestorWhichIsA("ScrollingFrame")
						local function contact(): any
							local value = world.engine.new("InputObject")
							value.UserInputType = types.Enum.UserInputType.Touch
							value.UserInputState = states.Begin
							value.Position = types.Vector3.new(60, 260, 0)
							nativeDrag.press(preview, value)
							return value
						end
						local function hold(value: any)
							preview.TouchLongPress:Fire({ types.Vector2.new(60, 260) }, states.Begin)
							Verify.expect(scroller.ScrollingEnabled):toBe(false)
						end
						local function release(value: any, state: any?)
							value.UserInputState = state or states.End
							nativeDrag.finish(input, value)
						end
						local flick = contact()
						flick.Position = types.Vector3.new(50, 95, 0)
						nativeDrag.move(input, flick)
						Verify.expect(scroller.ScrollingEnabled):toBe(true)
						release(flick)
						Verify.expect(model.saved:peek()["1"]):toBe(nil)
						local held = contact()
						hold(held)
						held.Position = types.Vector3.new(50, 95, 0)
						nativeDrag.move(input, held)
						local other = world.engine.new("InputObject")
						other.UserInputType = types.Enum.UserInputType.Touch
						other.Position = types.Vector3.new(50, 95, 0)
						release(other)
						Verify.expect(scroller.ScrollingEnabled):toBe(false)
						Verify.expect(model.saved:peek()["1"]):toBe(nil)
						release(held)
						Verify.expect(scroller.ScrollingEnabled):toBe(true)
						Verify.expect(model.saved:peek()["1"]):toBe(true)
						body.Activated:Fire(held)
						Verify.expect((model.selectedGame:peek())):toBe(nil)
						model.toggleSaved("1")
						local canceled = contact()
						hold(canceled)
						canceled.Position = types.Vector3.new(50, 95, 0)
						release(canceled, states.Cancel)
						Verify.expect(scroller.ScrollingEnabled):toBe(true)
						Verify.expect(model.saved:peek()["1"]):toBe(nil)
						local blurred = contact()
						hold(blurred)
						input.WindowFocusReleased:Fire()
						Verify.expect(scroller.ScrollingEnabled):toBe(true)
						scroller.ScrollingEnabled = false
						local locked = contact()
						preview.TouchLongPress:Fire({ types.Vector2.new(60, 260) }, states.Begin)
						release(locked, states.Cancel)
						Verify.expect(scroller.ScrollingEnabled):toBe(false)
						scroller.ScrollingEnabled = true
						local departing = contact()
						hold(departing)
						world.stops.Discover()
						Verify.expect(scroller.ScrollingEnabled):toBe(true)
					end)
				end,
			}
		)

		verifyHarness:case("NVM-6 keeps quick palette shared and adapts its button ring to a phone list", {
			id = "native_virtual_monitors::native virtual monitors::NVM-6 keeps quick palette shared and adapts its button ring to a phone list",
			run = function()
				withScreens(function(world)
					find(find(world.Avatar, "QuickPalette"), "Launcher").Activated:Fire()
					local modal = find(world.target, "Modal")
					modal.AbsoluteSize = world.types.Vector2.new(920, 640)
					local panel = find(world.target, "RadialPanel")
					Verify.expect(find(find(panel, "Sector-iris"), "Paint").Visible):toBe(false)
					Verify.expect(find(panel, "iris").ClassName):toBe("TextButton")
					modal.AbsoluteSize = world.types.Vector2.new(320, 420)
					Verify.expect(panel.ClassName):toBe("ScrollingFrame")
					find(panel, "iris").Activated:Fire()
					Verify.expect((world.model.palette:peek())):toBe("iris")
					Verify.expect(find(world.Avatar, "LookRich").Text:find("Iris", 1, true) ~= nil):toBe(true)
				end)
			end,
		})

		verifyHarness:case("NVM-Avatar restores the shared preset ladder slider increment and zeroable spin control", {
			id = "native_virtual_monitors::native virtual monitors::NVM-Avatar restores the shared preset ladder slider increment and zeroable spin control",
			run = function()
				withScreens(function(world)
					local model, avatar = world.model, world.Avatar
					local stop, other = world.runtime.mount(world.views.Avatar, world.target)
					find(find(avatar, "SettingsDisclosure"), "Header").Activated:Fire()
					Verify.expect((find(other, "AppearanceSettings"))):toBe(nil)
					find(find(other, "SettingsDisclosure"), "Header").Activated:Fire()
					Verify.expect(find(avatar, "AppearanceSettings") ~= nil):toBe(true)
					find(avatar, "MotionRow").Activated:Fire()
					Verify.expect(find(other, "TurnStep") ~= nil):toBe(true)
					local stepper = find(avatar, "TurnStep")
					find(stepper, "Increase").Activated:Fire()
					Verify.expect((model.turnStep:peek())):toBe(45)
					find(stepper, "Increase").Activated:Fire()
					Verify.expect((model.turnStep:peek())):toBe(90)
					find(stepper, "Decrease").Activated:Fire()
					Verify.expect((model.turnStep:peek())):toBe(45)
					model.angle:set(0)
					world.gui.SelectedObject = find(avatar, "Rotation")
					find(world.target, "FacetIncrease"):FindFirstChild("Increase").Pressed:Fire()
					Verify.expect((model.angle:peek())):toBe(45)
					model.turnStep:set(15)
					find(world.target, "FacetIncrease"):FindFirstChild("Increase").Pressed:Fire()
					Verify.expect((model.angle:peek())):toBe(60)
					model.autoSpin:set(3)
					local levels = find(avatar, "AutoSpin")
					Verify.expect(levels.ClassName):toBe("TextButton")
					Verify.expect(find(levels, "Level3") ~= nil):toBe(true)
					world.gui.SelectedObject = levels
					for expected = 2, 0, -1 do
						find(world.target, "FacetDecrease"):FindFirstChild("Decrease").Pressed:Fire()
						Verify.expect((model.autoSpin:peek())):toBe(expected)
					end
					stop()
				end)
			end,
		})

		verifyHarness:case("NVM-7 contains failed stage content and keeps detail controls usable", {
			id = "native_virtual_monitors::native virtual monitors::NVM-7 contains failed stage content and keeps detail controls usable",
			run = function()
				withScreens(function(world)
					world.model.selectGame(world.model.catalog.items:peek()[1])
					Verify.expect(find(world.target, "DetailSceneUnavailable").Text):toBe("Preview unavailable")
					rate(world.target, 2, world.types)
					Verify.expect(world.model.ratings:peek()["1"]):toBe(2)
					find(world.target, "close").Activated:Fire()
					Verify.expect((world.model.selectedGame:peek())):toBe(nil)
				end, {
					gameContent = function()
						return function()
							error("preview fixture")
						end
					end,
				})
			end,
		})

		verifyHarness:case("NVM-8 conversation menus stream progress and expose destructive touch actions", {
			id = "native_virtual_monitors::native virtual monitors::NVM-8 conversation menus stream progress and expose destructive touch actions",
			run = function()
				withScreens(function(world)
					local chat, model = world.Chat, world.model
					find(chat, "ConversationMenu").Activated:Fire()
					find(find(world.target, "MenuPanel"), "Suggest").Activated:Fire()
					find(find(world.target, "MenuPanel"), "FindGame").Activated:Fire()
					Verify.expect((model.chat.draft:peek())):toBe("What game should I play with friends?")
					Verify.expect((model.chatPromptUsed:peek())):toBe(true)
					local send = find(chat, "Send")
					Verify.expect((send:HasTag("facet-shape-circle"))):toBe(true)
					Verify.expect((send:GetAttribute("label"))):toBe("Send")
					send.Activated:Fire()
					Verify.expect((send:GetAttribute("label"))):toBe("Stop")
					local messages = find(chat, "Messages")
					messages.AbsoluteWindowSize = world.types.Vector2.new(850, 300)
					Verify.expect(find(find(chat, "Message_2"), "Thinking") ~= nil):toBe(true)
					Verify.expect((find(find(chat, "Message_2"), "MessageTools"))):toBe(nil)
					model.step(0.1, false)
					model.step(0.1, false)
					model.step(0.1, false)
					Verify.expect(model.chat.streamedChars:peek() > 0):toBe(true)
					Verify.expect((find(find(chat, "Message_2"), "Thinking"))):toBe(nil)
					send.Activated:Fire()
					Verify.expect((model.chat.streaming:peek())):toBe(false)
					Verify.expect((send:GetAttribute("label"))):toBe("Send")
					local messageRow = find(chat, "MessageActions_1")
					local user = find(messageRow, "Message_1")
					local assistant = find(chat, "Message_2")
					Verify.expect((user:HasTag("facet-track"))):toBe(true)
					Verify.expect((user:HasTag("facet-layout"))):toBe(true)
					Verify.expect(
						find(messageRow, "MessageRow_1"):FindFirstChildWhichIsA("UIListLayout").HorizontalAlignment
					)
						:toBe(world.types.Enum.HorizontalAlignment.Right)
					Verify.expect((assistant:HasTag("facet-layout"))):toBe(true)
					Verify.expect((find(user, "Role"))):toBe(nil)
					Verify.expect((find(assistant, "Role"))):toBe(nil)
					Verify.expect(find(find(chat, "MessageRow_2"), "AssistantMark").ClassName):toBe("Path2D")
					local tools = find(assistant, "MessageTools")
					local vote = find(tools, "Feedback")
					Verify.expect((vote:GetAttribute("FacetValue"))):toBe("none")
					find(vote, "Opt1").Activated:Fire()
					Verify.expect(model.chat.feedback:peek()[2]):toBe("up")
					Verify.expect((vote:GetAttribute("FacetValue"))):toBe("up")
					Verify.expect((find(vote, "Opt1"):HasTag("facet-segment-current"))):toBe(true)
					find(vote, "Opt2").Activated:Fire()
					Verify.expect(model.chat.feedback:peek()[2]):toBe("down")
					find(vote, "Opt2").Activated:Fire()
					Verify.expect(model.chat.feedback:peek()[2]):toBe(nil)
					Verify.expect((vote:GetAttribute("FacetValue"))):toBe("none")
					find(vote, "Opt2").Activated:Fire()
					find(tools, "Retry").Activated:Fire()
					Verify.expect((model.chat.streaming:peek())):toBe(true)
					Verify.expect(model.chat.messages:peek()[2].content):toBe("")
					Verify.expect(model.chat.feedback:peek()[2]):toBe(nil)
					Verify.expect(#model.chat.messages:peek()):toBe(2)
					send.Activated:Fire()
					messageRow.TouchLongPress:Fire({}, world.types.Enum.UserInputState.Begin)
					find(world.target, "trailing:DeleteMessage").Activated:Fire()
					Verify.expect(#model.chat.messages:peek()):toBe(1)
					local snack = find(world.target, "Snack")
					Verify.expect(find(snack, "Message").Text):toBe("Message deleted")
					find(snack, "Action").Activated:Fire()
					Verify.expect(#model.chat.messages:peek()):toBe(2)
					Verify.expect(model.chat.messages:peek()[1].content):toBe("What game should I play with friends?")
					Verify.expect((model.toasts.Chat:peek())):toBe(nil)
					find(chat, "MessageActions_1").TouchLongPress:Fire({}, world.types.Enum.UserInputState.Begin)
					find(world.target, "trailing:DeleteMessage").Activated:Fire()
					Verify.expect(#model.chat.messages:peek()):toBe(1)
					find(chat, "ConversationMenu").Activated:Fire()
					local clear = find(find(world.target, "MenuPanel"), "Clear")
					Verify.expect((clear:GetAttribute("role"))):toBe("destructive")
					clear.Activated:Fire()
					Verify.expect(#model.chat.messages:peek()):toBe(0)
					Verify.expect((find(chat, "Messages"))):toBe(messages)
					Verify.expect(find(chat, "Suggestions") ~= nil):toBe(true)
				end)
			end,
		})
		verifyHarness:case("edits a sent prompt back into the draft and removes the turns after it", {
			id = "native_virtual_monitors::native virtual monitors::edits a sent prompt back into the draft and removes the turns after it",
			run = function()
				withScreens(function(world)
					local chat, model = world.Chat, world.model
					model.chat.draft:set("First question")
					find(chat, "Send").Activated:Fire()
					find(chat, "Send").Activated:Fire()
					model.chat.draft:set("Second question")
					find(chat, "Send").Activated:Fire()
					find(chat, "Send").Activated:Fire()
					Verify.expect(#model.chat.messages:peek()):toBe(4)
					find(chat, "Messages").AbsoluteWindowSize = world.types.Vector2.new(850, 600)
					local second = find(chat, "MessageActions_3")
					second.TouchLongPress:Fire({}, world.types.Enum.UserInputState.Begin)
					find(world.target, "trailing:EditMessage").Activated:Fire()
					Verify.expect((model.chat.draft:peek())):toBe("Second question")
					Verify.expect(#model.chat.messages:peek()):toBe(2)
					Verify.expect(model.chat.messages:peek()[1].content):toBe("First question")
					Verify.expect((model.chat.streaming:peek())):toBe(false)
				end)
			end,
		})
		verifyHarness:case(
			"restores editable streaming drafts and fresh sends with persistent responsive chat prompts",
			{
				id = "native_virtual_monitors::native virtual monitors::restores editable streaming drafts and fresh sends with persistent responsive chat prompts",
				run = function()
					withScreens(function(world)
						Verify.expect((find(world.Chat, "WelcomeQuestion"):HasTag("facet-type-title"))):toBe(true)
						local chat, model, types = world.Chat, world.model, world.types
						local body, column = find(chat, "ChatBody"), find(chat, "ConversationColumn")
						local prompts, composer = find(chat, "Suggestions"), find(chat, "Composer")
						local field, send = find(chat, "Draft"), find(chat, "Send")
						local draft = find(field, "Field")
						local feed = find(chat, "Messages")
						local thread = find(chat, "Thread")
						Verify.expect(column:FindFirstChildWhichIsA("UISizeConstraint").MaxSize.X):toBe(960)
						Verify.expect(body:FindFirstChildWhichIsA("UIListLayout").HorizontalAlignment)
							:toBe(types.Enum.HorizontalAlignment.Center)
						Verify.expect(thread:FindFirstChildWhichIsA("UIFlexItem").FlexMode)
							:toBe(types.Enum.UIFlexMode.Fill)
						Verify.expect(thread.ClipsDescendants):toBe(true)
						Verify.expect(thread.LayoutOrder < composer.LayoutOrder):toBe(true)
						Verify.expect(prompts:FindFirstChildWhichIsA("UIGridLayout").FillDirectionMaxCells):toBe(2)
						Verify.expect(find(chat, "FindGame").TextWrapped):toBe(true)
						Verify.expect(find(chat, "BuildSomething").TextWrapped):toBe(true)
						Verify.expect((send:IsDescendantOf(field))):toBe(true)
						Verify.expect(find(field, "Corners") ~= nil):toBe(true)
						local disclaimer = find(chat, "Disclaimer")
						Verify.expect((disclaimer:GetAttribute("NoticeSeverity"))):toBe("info")
						Verify.expect(find(disclaimer, "Message").Text)
							:toBe("Simulated responses · No messages leave this device")
						Verify.expect(disclaimer.LayoutOrder < thread.LayoutOrder):toBe(true)
						body.AbsoluteSize = types.Vector2.new(320, 240)
						Verify.expect(prompts.Visible):toBe(false)
						Verify.expect(disclaimer.Visible):toBe(false)
						Verify.expect(prompts:FindFirstChildWhichIsA("UIGridLayout").FillDirectionMaxCells):toBe(1)
						Verify.expect((find(find(chat, "Welcome"), "AssistantIcon"))):toBe(nil)
						Verify.expect((find(find(chat, "Welcome"), "Hint"))):toBe(nil)
						Verify.expect(find(chat, "WelcomeQuestion").TextSize):toBe(20)
						body.AbsoluteSize = types.Vector2.new(1400, 700)
						Verify.expect(prompts.Visible):toBe(true)
						Verify.expect(disclaimer.Visible):toBe(true)
						find(chat, "BuildSomething").Activated:Fire()
						Verify.expect((model.chatPromptUsed:peek())):toBe(true)
						Verify.expect((find(world.target, "CalloutPanel"))):toBe(nil)
						send.Activated:Fire()
						Verify.expect((model.chat.streaming:peek())):toBe(true)
						Verify.expect((find(chat, "Messages"))):toBe(feed)
						draft:CaptureFocus()
						draft.Text = "Keep this next question"
						Verify.expect((model.chat.draft:peek())):toBe("Keep this next question")
						Verify.expect(draft.TextEditable):toBe(true)
						draft:ReleaseFocus(false)
						Verify.expect((model.chat.streaming:peek())):toBe(true)
						Verify.expect(find(chat, "NewChat").Visible):toBe(true)
						find(chat, "NewChat").Activated:Fire()
						Verify.expect(#model.chat.messages:peek()):toBe(0)
						Verify.expect((model.chat.draft:peek())):toBe("Keep this next question")
						Verify.expect(find(chat, "NewChat").Visible):toBe(false)
						send.Activated:Fire()
						Verify.expect(#model.chat.messages:peek()):toBe(2)
						Verify.expect(model.chat.messages:peek()[1].content):toBe("Keep this next question")
						Verify.expect((model.chat.draft:peek())):toBe("")
						Verify.expect((model.chat.streaming:peek())):toBe(true)
						Verify.expect(find(chat, "Suggestions").Visible):toBe(false)
						find(chat, "ConversationMenu").Activated:Fire()
						find(find(world.target, "MenuPanel"), "Suggest").Activated:Fire()
						find(find(world.target, "MenuPanel"), "BuildSomething").Activated:Fire()
						Verify.expect((model.chat.draft:peek())):toBe("Help me build a game browser")
						find(chat, "ConversationMenu").Activated:Fire()
						local follow = find(find(world.target, "MenuPanel"), "FollowReplies")
						Verify.expect((follow:GetAttribute("selected"))):toBe(true)
						follow.Activated:Fire()
						Verify.expect((model.followChat:peek())):toBe(false)
						Verify.expect((follow:GetAttribute("selected"))):toBe(false)
						follow.Activated:Fire()
						Verify.expect((model.followChat:peek())):toBe(true)
						find(find(world.target, "MenuPanel"), "Clear").Activated:Fire()
						Verify.expect((model.chat.draft:peek())):toBe("Help me build a game browser")
						Verify.expect((find(world.target, "CalloutPanel"))):toBe(nil)
						Verify.expect(find(chat, "BuildSomething") ~= nil):toBe(true)
					end)
				end,
			}
		)
		verifyHarness:case("NVM-9 pages a bounded native grid and preserves saved order and notes across shelves", {
			id = "native_virtual_monitors::native virtual monitors::NVM-9 pages a bounded native grid and preserves saved order and notes across shelves",
			run = function()
				withScreens(function(world)
					local model, discover, types = world.model, world.Discover, world.types
					local grid = find(discover, "Games")
					grid.AbsoluteWindowSize = types.Vector2.new(850, 260)
					grid.CanvasPosition = types.Vector2.new(0, 2200)
					model.step(0.1, false)
					Verify.expect(#model.catalog.items:peek()):toBe(72)
					local mounted = 0
					for _, node in grid:GetDescendants() do
						if node.Name:match("^Game_%d+$") then
							mounted += 1
						end
					end
					Verify.expect(mounted > 0 and mounted < 20):toBe(true)
					model.toggleSaved("1")
					model.toggleSaved("2")
					model.toggleSaved("3")
					find(discover, "Saved").Activated:Fire()
					local saved = find(discover, "SavedGames")
					local body, header = find(saved, "Body"), find(saved, "Header")
					body.AbsoluteWindowSize = types.Vector2.new(900, 300)
					nativeDrag.measure(body)
					for _, column in { "title", "genre", "rating" } do
						find(find(header, column), "Sort").Activated:Fire()
						Verify.expect(model.savedSort:peek().column):toBe(column)
						find(find(header, column), "Sort").Activated:Fire()
						Verify.expect(model.savedSort:peek().direction):toBe("descending")
					end
					model.savedSort:set(nil)
					local handle = find(find(body, "2"), "Move")
					local detector = handle:FindFirstChildWhichIsA("UIDragDetector")
					detector.DragStart:Fire(types.Vector2.new(10, 75))
					detector.DragContinue:Fire(types.Vector2.new(10, 0))
					detector.DragEnd:Fire()
					Verify.expect(model.savedOrder:peek()[1]):toBe("2")
					local note = find(saved, "Note_2")
					note:CaptureFocus()
					note.Text = "Play Friday"
					note:ReleaseFocus(true)
					Verify.expect(model.notes:peek()["2"]):toBe("Play Friday")
					note:CaptureFocus()
					note.Text = "Discard this"
					note.FocusLost:Fire(false, { KeyCode = types.Enum.KeyCode.Escape })
					Verify.expect(note.Text):toBe("Play Friday")
					Verify.expect(model.notes:peek()["2"]):toBe("Play Friday")
					find(discover, "Browse").Activated:Fire()
					find(discover, "Saved").Activated:Fire()
					saved = find(discover, "SavedGames")
					body = find(saved, "Body")
					body.AbsoluteWindowSize = types.Vector2.new(900, 300)
					nativeDrag.measure(body)
					Verify.expect(find(saved, "Note_2").Text):toBe("Play Friday")
					find(find(body, "2"), "RowHit").Activated:Fire()
					Verify.expect(model.savedSelection:peek()["2"]):toBe(true)
					Verify.expect(model.selectedGame:peek().id):toBe("2")
				end)
			end,
		})

		verifyHarness:case("NVM-10 follows growing conversation tails and respects a reader who scrolled away", {
			id = "native_virtual_monitors::native virtual monitors::NVM-10 follows growing conversation tails and respects a reader who scrolled away",
			run = function()
				withScreens(function(world)
					local history = {}
					for index = 1, 24 do
						table.insert(
							history,
							{ id = index, role = "assistant" :: "assistant", content = "Message " .. index }
						)
					end
					world.model.chat.messages:set(history)
					local feed = find(world.Chat, "Messages")
					feed.AbsoluteWindowSize = world.types.Vector2.new(850, 260)
					local initial = feed.CanvasPosition.Y
					Verify.expect(initial > 0):toBe(true)
					local nextHistory = table.clone(history)
					table.insert(nextHistory, { id = 25, role = "assistant" :: "assistant", content = "Latest reply" })
					world.model.chat.messages:set(nextHistory)
					Verify.expect(feed.CanvasPosition.Y > initial):toBe(true)
					local row = find(feed, "MessageRow_25")
					local previous = feed.CanvasPosition.Y
					row.AbsoluteSize = world.types.Vector2.new(800, 400)
					Verify.expect(feed.CanvasPosition.Y > previous):toBe(true)
					feed.CanvasPosition = world.types.Vector2.new(0, 120)
					local appended = table.clone(nextHistory)
					table.insert(appended, { id = 26, role = "assistant" :: "assistant", content = "Another reply" })
					world.model.chat.messages:set(appended)
					Verify.expect(feed.CanvasPosition.Y):toBe(120)
				end)
			end,
		})

		verifyHarness:case("builds genre card media and decorations before the first painted frame", {
			id = "native_virtual_monitors::native virtual monitors::builds genre card media and decorations before the first painted frame",
			run = function()
				withScreens(function(world)
					local grid = find(world.Discover, "Games")
					grid.AbsoluteSize = world.types.Vector2.new(390, 500)
					grid.AbsoluteWindowSize = world.types.Vector2.new(390, 500)
					for _, genre in { "Adventure", "all", "Racing", "all" } do
						find(world.Discover, "Genre_" .. genre).Activated:Fire()
						world.engine.heartbeat:Fire(0)
						local count = 0
						for _, node in grid:GetDescendants() do
							if string.sub(node.Name, 1, 5) == "Game_" then
								count += 1
								local stage = find(node, "Scene")
								Verify.expect(stage:GetAttribute("FacetBuilt")):toBe(true)
								Verify.expect(`{node.Name} model {find(stage, "CompleteModel") ~= nil}`)
									:toBe(`{node.Name} model true`)
								Verify.expect(`{node.Name} badge {find(node, "LiveDot") ~= nil}`)
									:toBe(`{node.Name} badge true`)
							end
						end
						Verify.expect(`genre {genre} card count {count > 0}`):toBe(`genre {genre} card count true`)
					end
				end, {
					gameContent = function()
						return function(runtime, world)
							local Host = runtime.constructors
							return runtime.mount(function()
								return Host.Model "CompleteModel" { Host.Part "Island" {} }
							end, world)
						end
					end,
				})
			end,
		})

		verifyHarness:case("keeps the Discover grid mounted through genre changes", {
			id = "native_virtual_monitors::native virtual monitors::keeps the Discover grid mounted through genre changes",
			run = function()
				withScreens(function(world)
					local grid = find(world.Discover, "Games")
					grid.AbsoluteWindowSize = world.types.Vector2.new(390, 500)
					local retained = find(grid, "Game_1")
					local artwork = find(retained, "Artwork")
					for _, genre in { "Adventure", "all", "Racing", "all" } do
						find(world.Discover, "Genre_" .. genre).Activated:Fire()
						Verify.expect(find(world.Discover, "Games") == grid):toBe(true)
						Verify.expect(grid.Parent ~= nil):toBe(true)
						Verify.expect(grid.AbsoluteWindowSize):toBe(world.types.Vector2.new(390, 500))
						if genre == "Adventure" then
							Verify.expect(find(grid, "Game_1") == retained):toBe(true)
							Verify.expect(find(retained, "Artwork") == artwork):toBe(true)
						end
					end
				end)
			end,
		})

		verifyHarness:case("starts filtered results at the top without retaining the previous collection anchor", {
			id = "native_virtual_monitors::native virtual monitors::starts filtered results at the top without retaining the previous collection anchor",
			run = function()
				withScreens(function(world)
					local grid = find(world.Discover, "Games")
					grid.AbsoluteWindowSize = world.types.Vector2.new(390, 500)
					grid.CanvasPosition = world.types.Vector2.new(0, 472)
					world.model.query:set("Circuit")
					local filtered = find(world.Discover, "Games")
					filtered.AbsoluteWindowSize = world.types.Vector2.new(390, 500)
					Verify.expect(filtered == grid):toBe(true)
					Verify.expect(grid.Parent ~= nil):toBe(true)
					Verify.expect(filtered.CanvasPosition.Y):toBe(0)
					Verify.expect((world.model.discoveryScroll:peek())):toBe(0)
				end)
			end,
		})

		verifyHarness:case("NVM-11 restores screen scroll from the shared model after presentation remount", {
			id = "native_virtual_monitors::native virtual monitors::NVM-11 restores screen scroll from the shared model after presentation remount",
			run = function()
				withScreens(function(world)
					local types = world.types
					local grid = find(world.Discover, "Games")
					grid.AbsoluteWindowSize = types.Vector2.new(850, 260)
					grid.CanvasPosition = types.Vector2.new(0, 800)
					Verify.expect((world.model.discoveryScroll:peek())):toBe(800)
					world.stops.Discover()
					world.model.toggleMode()
					local _, nextDiscover = world.runtime.mount(world.views.Discover, world.target)
					local restored = find(nextDiscover, "Games")
					restored.AbsoluteWindowSize = types.Vector2.new(600, 260)
					Verify.expect(restored.CanvasPosition.Y):toBe(800)
					local history = {}
					for index = 1, 24 do
						table.insert(
							history,
							{ id = index, role = "assistant" :: "assistant", content = "Message " .. index }
						)
					end
					world.model.chat.messages:set(history)
					local feed = find(world.Chat, "Messages")
					feed.AbsoluteWindowSize = types.Vector2.new(850, 260)
					feed.CanvasPosition = types.Vector2.new(0, 240)
					world.stops.Chat()
					world.model.toggleMode()
					local _, nextChat = world.runtime.mount(world.views.Chat, world.target)
					local restoredFeed = find(nextChat, "Messages")
					restoredFeed.AbsoluteWindowSize = types.Vector2.new(600, 260)
					Verify.expect(restoredFeed.CanvasPosition.Y):toBe(240)
				end)
			end,
		})

		verifyHarness:case("NVM-12 native modals capture selection and restore the launching control", {
			id = "native_virtual_monitors::native virtual monitors::NVM-12 native modals capture selection and restore the launching control",
			run = function()
				withScreens(function(world)
					find(world.Discover, "Games").AbsoluteWindowSize = world.types.Vector2.new(850, 260)
					find(world.Avatar, "MotionRow").Activated:Fire()
					local open = find(find(world.Discover, "Game_1"), "Body")
					world.gui.SelectedObject = open
					open.Activated:Fire()
					Verify.expect(world.gui.SelectedObject == open):toBe(false)
					Verify.expect((world.gui.SelectedObject:IsDescendantOf(find(world.target, "AlertModal"))))
						:toBe(true)
					find(world.Avatar, "TurnRight").Activated:Fire()
					Verify.expect((world.model.angle:peek())):toBe(-15)
					find(world.target, "close").Activated:Fire()
					Verify.expect(world.gui.SelectedObject):toBe(open)
				end)
			end,
		})

		verifyHarness:case("NVM-19 grows a game card into the screen and returns to its retained card and scroll", {
			id = "native_virtual_monitors::native virtual monitors::NVM-19 grows a game card into the screen and returns to its retained card and scroll",
			run = function()
				withScreens(function(world)
					local grid = find(world.Discover, "Games")
					grid.AbsoluteWindowSize = world.types.Vector2.new(850, 260)
					grid.CanvasPosition = world.types.Vector2.new(0, 236)
					local position = grid.CanvasPosition
					local card = find(world.Discover, "Game_1")
					local open = find(card, "Body")
					local sourceParent = card.Parent
					card.AbsolutePosition = world.types.Vector2.new(100, 190)
					card.AbsoluteSize = world.types.Vector2.new(270, 224)
					world.gui.SelectedObject = open
					open.Activated:Fire()
					local selected = world.model.selectedGame:peek()
					local panel = find(world.target, "AlertPanel")
					find(world.target, "AlertModal").AbsoluteSize = world.types.Vector2.new(920, 640)
					local detail = find(panel, "GameDetails")
					local snapshot = find(panel, "SourceSnapshot")
					Verify.expect(panel.Size.X.Offset):toBe(270)
					Verify.expect(panel.Size.Y.Offset):toBe(224)
					Verify.expect(panel.Position.X.Offset):toBe(100)
					Verify.expect(panel.Position.Y.Offset):toBe(190)
					world.engine.heartbeat:Fire(0.12)
					Verify.expect(panel.Size.X.Offset > 270 and panel.Size.X.Offset < 920):toBe(true)
					Verify.expect(panel.Size.Y.Offset > 224 and panel.Size.Y.Offset < 640):toBe(true)
					world.engine.heartbeat:Fire(0.2)
					Verify.expect(panel.Size.X.Offset):toBe(920)
					Verify.expect(panel.Size.Y.Offset):toBe(640)
					find(panel, "close").Activated:Fire()
					Verify.expect((world.model.selectedGame:peek())):toBe(nil)
					Verify.expect((find(panel, "GameDetails"))):toBe(detail)
					world.engine.heartbeat:Fire(0.1)
					local departingSize = panel.Size
					world.model.selectGame(selected)
					Verify.expect((find(world.target, "AlertPanel"))):toBe(panel)
					Verify.expect(panel.Size):toBe(departingSize)
					world.engine.heartbeat:Fire(0.32)
					find(panel, "close").Activated:Fire()
					world.engine.heartbeat:Fire(0.32)
					Verify.expect((find(world.target, "AlertPanel"))):toBe(nil)
					Verify.expect((snapshot:isDestroyed())):toBe(true)
					Verify.expect(card.Parent):toBe(sourceParent)
					Verify.expect((card:isDestroyed())):toBe(false)
					Verify.expect(grid.CanvasPosition):toBe(position)
					Verify.expect(world.gui.SelectedObject):toBe(open)
				end, { motionLevel = "normal" })
			end,
		})

		verifyHarness:case("NVM-13 desktop tab transitions reclaim interrupted content and release departing owners", {
			id = "native_virtual_monitors::native virtual monitors::NVM-13 desktop tab transitions reclaim interrupted content and release departing owners",
			run = function()
				local Facet, desktop = require("../src"), require("../examples/virtual_monitors/desktop")
				local engine = engineModule.new()
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local mounted, released, now = {}, {}, 0
				local target = engine.new("ScreenGui")
				local lifetime = Compose.createRootOwner(function()
					local model = modelModule.new(Compose)
					Compose.cleanup(model.dispose)
					local views = {}
					for _, name in screens.APPS do
						views[name] = function()
							mounted[name] = (mounted[name] or 0) + 1
							Compose.cleanup(function()
								released[name] = (released[name] or 0) + 1
							end)
							return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
								Name = name .. "Content",
							})
						end
					end
					local stop, root: any = runtime.mount(
						desktop.create(Facet, runtime, views, model, Compose.cell(1), { types = engine.types }),
						target
					)
					local first = find(root, "DiscoverContent")
					Verify.expect(find(root, "Flap"):GetAttribute("FacetLabel")):toBe("Flap")
					for _ = 1, 20 do
						engine.heartbeat:Fire(1 / 60)
					end
					model.selectedTab:set("Avatar")
					engine.heartbeat:Fire(0.04)
					Verify.expect(find(root, "AvatarContent") ~= nil):toBe(true)
					Verify.expect((find(root, "DiscoverContent"))):toBe(first)
					model.selectedTab:set("Discover")
					Verify.expect((find(root, "DiscoverContent"))):toBe(first)
					for _ = 1, 30 do
						engine.heartbeat:Fire(1 / 60)
					end
					Verify.expect((find(root, "AvatarContent"))):toBe(nil)
					Verify.expect(released.Avatar):toBe(1)
					Verify.expect(mounted.Discover):toBe(1)
					stop()
					Verify.expect(released.Discover):toBe(1)
				end, runtime.reactor)
				lifetime.dispose()
				runtime:dispose()
			end,
		})
		verifyHarness:case("NVM-14 keeps the selected app and shared avatar state across presentation round trips", {
			id = "native_virtual_monitors::native virtual monitors::NVM-14 keeps the selected app and shared avatar state across presentation round trips",
			run = function()
				withModel(function(model)
					model.focus("Discover")
					model.toggleMode()
					model.selectedTab:set("Avatar")
					model.avatarSettingsExpanded:set(false)
					model.avatarTipsExpanded:set(true)
					model.avatarSummaryDetent:set("large")
					model.toggleMode()
					Verify.expect((model.focused:peek())):toBe("Avatar")
					Verify.expect((model.selectedTab:peek())):toBe("Avatar")
					model.toggleMode()
					Verify.expect((model.avatarSettingsExpanded:peek())):toBe(false)
					Verify.expect((model.avatarTipsExpanded:peek())):toBe(true)
					Verify.expect((model.avatarSummaryDetent:peek())):toBe("large")
				end)
			end,
		})
		verifyHarness:case("NVM-15 keeps six recommendations and the original per-game trend values", {
			id = "native_virtual_monitors::native virtual monitors::NVM-15 keeps six recommendations and the original per-game trend values",
			run = function()
				withScreens(function(world)
					local model = world.model
					model.catalog.seen(35)
					model.catalog.step()
					model.selectGame(model.catalog.items:peek()[1])
					local points = find(find(world.target, "TrendLine"), "Stroke"):GetControlPoints()
					for day = 0, 6 do
						local expected = 1 - (0.25 + 0.5 * ((1 * (day + 1) * 37) % 23) / 23)
						Verify.expect(math.abs(points[day + 1].Position.Y.Scale - expected) < 0.0001):toBe(true)
					end
					find(find(world.target, "DetailSection"), "similar").Activated:Fire()
					local function rows()
						local ids = {}
						for _, node in find(world.target, "SimilarPage"):GetChildren() do
							local id = node.Name:match("^SimilarRow_(%d+)$")
							if id then
								table.insert(ids, id)
							end
						end
						return ids
					end
					Verify.expect(#rows()):toBe(6)
					local pages = find(world.target, "SimilarPages")
					Verify.expect((pages:GetAttribute("FacetCount"))):toBe(2)
					Verify.expect((pages:GetAttribute("FacetCurrent"))):toBe(1)
					local first = rows()
					find(pages, "Page-2").Activated:Fire()
					Verify.expect((model.similarPage:peek())):toBe(2)
					Verify.expect((pages:GetAttribute("FacetCurrent"))):toBe(2)
					local second = rows()
					Verify.expect(#second):toBe(5)
					for _, id in second do
						Verify.expect((table.find(first, id))):toBe(nil)
					end
					model.selectGame(model.catalog.items:peek()[2])
					Verify.expect((model.similarPage:peek())):toBe(1)
				end)
			end,
		})

		verifyHarness:case("NVM-16 permits only the active presentation to publish native scrolling", {
			id = "native_virtual_monitors::native virtual monitors::NVM-16 permits only the active presentation to publish native scrolling",
			run = function()
				withScreens(function(world)
					local model, types = world.model, world.types
					local spatial = find(world.Discover, "Games")
					spatial.AbsoluteWindowSize = types.Vector2.new(820, 260)
					spatial.CanvasPosition = types.Vector2.new(0, 800)
					local views = screens.create(
						require("../src"),
						world.runtime,
						{ model = model, types = types, spatial = false, motionLevel = "none" }
					)
					local stop, desktop = world.runtime.mount(views.Discover, world.target)
					local flat = find(desktop, "Games")
					flat.AbsoluteWindowSize = types.Vector2.new(600, 400)
					flat.CanvasPosition = types.Vector2.new(0, 120)
					Verify.expect((model.discoveryScroll:peek())):toBe(800)
					model.mode:set("Screen")
					spatial.CanvasPosition = types.Vector2.new(0, 160)
					Verify.expect((model.discoveryScroll:peek())):toBe(800)
					flat.CanvasPosition = types.Vector2.new(0, 400)
					Verify.expect((model.discoveryScroll:peek())):toBe(400)
					stop()
				end, { spatial = true })
			end,
		})

		verifyHarness:case("NVM-Accent derives every accent in both appearances with readable contrast", {
			id = "native_virtual_monitors::native virtual monitors::NVM-Accent derives every accent in both appearances with readable contrast",
			run = function()
				local Facet = require("../src")
				for _, app in { "Discover", "Avatar", "Chat" } do
					local package, report = theme.create(Facet, app)
					Verify.expect(report.ok):toBe(true)
					for _, result in report.contrast do
						Verify.expect(result.ok):toBe(true)
					end
					Verify.expect(#package.style.themes):toBe(#theme.ACCENTS * 2)
					for _, entry in theme.ACCENTS do
						for _, dark in { false, true } do
							local name = theme.paletteName(entry.id, dark)
							local palette
							for _, candidate in package.style.themes do
								if candidate.name == name then
									palette = candidate
								end
							end
							Verify.expect(palette ~= nil):toBe(true)
							local colors, extra = palette.colors, palette.extra
							local expected = if dark then entry.dark else entry.light
							for _, channel in { "r", "g", "b" } do
								Verify.expect(colors.accent[channel]):toBe(expected[channel])
								Verify.expect(extra.controlSelected[channel]):toBe(expected[channel])
							end
							Verify.expect(ratio(colors.onAccent, colors.accent) >= 4.5):toBe(true)
							Verify.expect(ratio(extra.onSelected, extra.controlSelected) >= 4.5):toBe(true)
							Verify.expect(ratio(colors.accent, colors.surface) >= 4.5):toBe(true)
							Verify.expect(ratio(colors.accent, colors.surfaceStrong) >= 4.5):toBe(true)
							Verify.expect(ratio(colors.accent, extra.control) >= 3):toBe(true)
						end
					end
				end
				Verify.expect((theme.paletteName("sage", true))):toBe("Dark")
				Verify.expect((theme.paletteName("sage", false))):toBe("Light")
				Verify.expect((theme.paletteName("clay", true))):toBe("Clay Dark")
				Verify.expect((theme.paletteName("iris", false))):toBe("Iris Light")
			end,
		})

		verifyHarness:case(
			"NVM-Accent swaps the native accent paint from the Accent picker and the quick accent menu",
			{
				id = "native_virtual_monitors::native virtual monitors::NVM-Accent swaps the native accent paint from the Accent picker and the quick accent menu",
				run = function()
					withScreens(function(world)
						local Facet = require("../src")
						local model, types = world.model, world.types
						local package = theme.create(Facet, "Avatar")
						local sheet
						local stop = world.runtime.mount(function()
							sheet = Facet.themes.createStyleSheet(world.runtime, package, {
								types = types,
								motionLevel = "none",
								theme = function(use: Use)
									return theme.paletteName(use(model.palette), use(model.dark))
								end,
							})
							return sheet
						end, world.target)
						local function expectAccent(id, dark)
							for _, entry in theme.ACCENTS do
								if entry.id == id then
									local value = if dark then entry.dark else entry.light
									local expected = types.Color3.new(value.r, value.g, value.b)
									Verify.expect(rule(sheet, ".facet-accent").BackgroundColor3):toBe(expected)
									Verify.expect(rule(sheet, ".facet-selected").BackgroundColor3):toBe(expected)
									Verify.expect(rule(sheet, ".facet-toggle-on").BackgroundColor3):toBe(expected)
								end
							end
						end
						local avatar = world.Avatar
						Verify.expect(find(avatar, "PaletteLabel").Text):toBe("Accent")
						for _, dark in { true, false } do
							model.dark:set(dark)
							model.palette:set("sage")
							expectAccent("sage", dark)
							find(find(avatar, "Palette"), "clay").Activated:Fire()
							Verify.expect((model.palette:peek())):toBe("clay")
							expectAccent("clay", dark)
							model.palette:set("iris")
							expectAccent("iris", dark)
						end
						model.hatTint:set({ 46, 52, 64 })
						model.palette:set("clay")
						Verify.expect(model.hatTint:peek()[1]):toBe(46)
						find(avatar, "Summary").Activated:Fire()
						local fact = find(world.target, "SummaryPalette")
						Verify.expect(find(fact, "Label").Text):toBe("Accent")
						Verify.expect(find(fact, "Value").Text):toBe("Clay")
						find(world.target, "Done").Activated:Fire()
						model.resetAvatarPresented:set(true)
						find(world.target, "reset").Activated:Fire()
						Verify.expect((model.palette:peek())):toBe("sage")
						expectAccent("sage", false)
						find(find(avatar, "QuickPalette"), "Launcher").Activated:Fire()
						find(find(world.target, "RadialPanel"), "iris").Activated:Fire()
						Verify.expect((model.palette:peek())):toBe("iris")
						expectAccent("iris", false)
						stop()
					end)
				end,
			}
		)
	end)
end
