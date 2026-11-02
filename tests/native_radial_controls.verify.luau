--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Bdd = require("../tools/vendor/verify/src/bdd")
local VerifyRoblox = require("../tools/vendor/verify/src/roblox")

return function(verifyHarness: Verify.Harness)
	local test = Bdd.create(verifyHarness)
	local describe, it, expect = test.describe, test.it, test.expect
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	local Facet = require("../src")
	local Shared = require("../src/ui/types")
	local Radial = require("../src/ui/radial_types")
	local RadialProps = require("../src/ui/radial_props")

	local fadeKit = require("./lib/fade")
	local Compose = require("../src/vendor/compose/core")
	local Roblox = require("../src/vendor/compose/roblox")
	local controls = require("../src/ui")
	local engines = require("./lib/native_engine")
	type Context = typeof(require("@repo/examples/types").Context)
	type Item = Radial.RadialItem<string>
	local function action(item: Radial.RadialAction<string>): Item
		return item
	end
	local function choice(item: Radial.RadialChoice<string>): Item
		return item
	end
	type World = {
		engine: engines.Engine,
		gui: any,
		input: any,
		screen: any,
		opened: Compose.Value<boolean>,
		find: (string) -> any,
		step: (number) -> (),
		stop: () -> (),
	}
	local function setup(
		spec: RadialProps.RadialMenuSpec<string> | ((engines.Engine) -> RadialProps.RadialMenuSpec<string>),
		animated: boolean?,
		environment: Shared.EnvironmentPreview?
	): World
		local engine, now = engines.new(), 0
		local actual: RadialProps.RadialMenuSpec<string> = if type(spec) == "function" then spec(engine) else spec
		local gui: GuiService, input: UserInputService = engine.new("GuiService"), engine.new("UserInputService")
		engine.environment.fakeOn(VerifyRoblox.assertInstance(input), "GetLastInputType", function()
			return engine.types.Enum.UserInputType.Keyboard
		end)
		for _, method in { "IsKeyDown", "IsGamepadButtonDown" } do
			engine.environment.fakeOn(VerifyRoblox.assertInstance(input), method, function()
				return false
			end)
		end
		for _, method in { "GetNavigationGamepads", "GetKeysPressed", "GetGamepadState" } do
			engine.environment.fakeOn(VerifyRoblox.assertInstance(input), method, function()
				return {}
			end)
		end
		gui.GuiNavigationEnabled = true
		gui.AutoSelectGuiEnabled = true
		gui.TouchControlsEnabled = true
		engine.environment.fakeOn(VerifyRoblox.assertInstance(gui), "GetInsetArea", function()
			return engine.types.Rect.new(0, 0, 1280, 720)
		end)
		engine.clock = function()
			return now
		end
		local runtime: ComposeRuntime = Roblox.createRuntime(engine)
		local UI = controls(Compose, runtime, {
			types = engine.types,
			services = { GuiService = gui, UserInputService = input },
			motionLevel = if not animated then "none" else "normal",
			environment = environment,
		})
		local opened = actual.isPresented or Compose.cell(true)
		actual.isPresented = opened
		local stopInitialBounds = engine.environment.onCreate(function(node)
			if node:IsA("ScreenGui") then
				engine.environment.poke(VerifyRoblox.assertInstance(node), "AbsoluteSize", engine.types.Vector2.zero)
			end
		end)
		local stop, screen: any = runtime.mount(function()
			return Facet.host(runtime).ScreenGui({ (UI.RadialMenu :: any)(actual) })
		end, engine.new("Folder"))
		stopInitialBounds:Disconnect()
		return {
			engine = engine,
			gui = gui,
			input = input,
			screen = screen,
			opened = opened,
			find = function(name)
				return screen:FindFirstChild(name, true)
			end,
			step = function(seconds: number)
				for _ = 1, math.ceil(seconds * 60) do
					now += 1 / 60
					engine.heartbeat:Fire(1 / 60)
				end
			end,
			stop = function()
				stop()
				runtime:dispose()
			end,
		}
	end
	local function compass(callback: (string) -> ()): { Radial.RadialItem<string> }
		local entries: { Radial.RadialItem<string> } = {}
		local slots: { Radial.CompassSlot } = { "N", "E", "S", "W" }
		for _, slot in slots do
			table.insert(
				entries,
				action({
					id = slot,
					slot = slot,
					label = slot,
					completion = "stay",
					onSelect = function()
						callback(slot)
					end,
				})
			)
		end
		return entries
	end
	local function pointer(world: World, x: number, y: number)
		return {
			UserInputType = world.engine.types.Enum.UserInputType.Touch,
			UserInputState = world.engine.types.Enum.UserInputState.Begin,
			Position = world.engine.types.Vector3.new(x, y, 0),
		}
	end
	describe("radial label fit", function()
		it("keeps selected tool surfaces visible in the native list fallback", {
			id = "native_radial_controls::radial label fit::keeps selected tool surfaces visible in the native list fallback",
			run = function()
				local selected = Compose.cell("plant")
				local world = setup({
					items = {
						choice({ id = "plow", label = "Plow", selected = selected, value = "plow" }),
						choice({ id = "plant", label = "Plant", selected = selected, value = "plant" }),
						choice({ id = "harvest", label = "Harvest", selected = selected, value = "harvest" }),
					},
				})
				world.engine.environment.poke(
					world.find("Modal"),
					"AbsoluteSize",
					world.engine.types.Vector2.new(180, 180)
				)
				expect(world.find("RadialPanel"):GetAttribute("Presentation")):toBe("list")
				for _, name in { "plow", "plant", "harvest" } do
					expect(world.find(name).BackgroundTransparency):toBe(0)
					expect(world.find(name):HasTag("facet-radial-row")):toBe(true)
				end
				world.find("plow").Activated:Fire()
				expect(selected:peek()):toBe("plow")
				for _ = 1, 10 do
					world.step(1 / 60)
					expect(world.find("plow").BackgroundTransparency):toBe(0)
				end
				world.engine.environment.poke(
					world.find("Modal"),
					"AbsoluteSize",
					world.engine.types.Vector2.new(1280, 720)
				)
				expect(world.find("RadialPanel"):GetAttribute("Presentation")):toBe("radial")
				expect(world.find("plow").BackgroundTransparency):toBe(1)
				expect(world.find("plow"):HasTag("facet-radial-row")):toBe(false)
				world.stop()
			end,
		})
		it("captions name icon buttons below each target", {
			id = "native_radial_controls::radial label fit::captions name icon buttons below each target",
			run = function()
				for _, captions in { true, false } do
					local look: Radial.RadialAction<string> =
						{ id = "look", label = "Look", icon = "facet:search", onSelect = function() end }
					local spec: RadialProps.RadialMenuSpec<string> = {
						appearance = "buttons",
						captions = captions,
						items = { look },
					}
					local w = setup(spec)
					local caption = w.find("look"):FindFirstChild("ItemCaption")
					if captions then
						expect(caption:FindFirstChild("Text").Text):toBe("Look")
						expect(caption.Visible):toBe(true)
						expect(caption.Position.Y.Scale):toBe(1)
					else
						expect(caption):toBeNil()
					end
					w.stop()
				end
			end,
		})
		it("places captions at the top leading corner when asked", {
			id = "native_radial_controls::radial label fit::places captions at the top leading corner when asked",
			run = function()
				local look: Radial.RadialAction<string> =
					{ id = "look", label = "Look", icon = "facet:search", onSelect = function() end }
				local spec: RadialProps.RadialMenuSpec<string> = {
					appearance = "buttons",
					captions = true,
					captionPlacement = "topLeading",
					items = { look },
				}
				local w = setup(spec)
				local caption = w.find("look"):FindFirstChild("ItemCaption")
				expect(caption.AnchorPoint.X):toBe(1)
				expect(caption.AnchorPoint.Y):toBe(1)
				expect(caption.Position.X.Scale):toBe(0)
				expect(caption.Position.Y.Scale):toBe(0)
				w.stop()
			end,
		})
		it("keeps short names on one line inside round item targets", {
			id = "native_radial_controls::radial label fit::keeps short names on one line inside round item targets",
			run = function()
				local spec: RadialProps.RadialMenuSpec<string> = {
					appearance = "buttons" :: Radial.Appearance,
					items = {
						{ id = "sage", label = "Sage", onSelect = function() end } :: Radial.RadialItem<string>,
						{ id = "clay", label = "Clay", onSelect = function() end } :: Radial.RadialItem<string>,
					},
				}
				local w = setup(spec)
				for _, name in { "sage", "clay" } do
					local button = w.find(name)
					w.engine.environment.poke(
						button:FindFirstChild("CaptionMeasure"),
						"TextBounds",
						w.engine.types.Vector2.new(36, 16)
					)
					expect(button.TextWrapped):toBe(false)
					expect(button.Size.X.Offset >= 36 + 24):toBe(true)
					expect(button.TextScaled):toBe(false)
					expect(button:HasTag("facet-radial-label")):toBe(true)
				end
				w.stop()
			end,
		})
	end)

	describe("radial full caption fit", function()
		it("holds the launcher slot while Close replaces its caption", {
			id = "native_radial_controls::radial full caption fit::holds the launcher slot while Close replaces its caption",
			run = function()
				for _, label in { "Quick accent", "Tools" } do
					local world = setup({
						label = label,
						isPresented = Compose.cell(false),
						items = { action({ id = "sage", label = "Sage", onSelect = function() end }) },
					})
					local launcher = world.find("Launcher")
					local root = launcher.Parent
					world.engine.environment.poke(root, "AbsoluteSize", world.engine.types.Vector2.new(140, 44))
					local size, automatic = root.Size, root.AutomaticSize
					for _ = 1, 3 do
						launcher.Activated:Fire()
						expect(world.opened:peek()):toBe(true)
						expect(launcher.Visible):toBe(false)
						expect(root.Size):toBe(world.engine.types.UDim2.fromOffset(140, 44))
						expect(root.AutomaticSize):toBe(world.engine.types.Enum.AutomaticSize.None)
						world.find("Center").Activated:Fire()
						expect(world.opened:peek()):toBe(false)
						expect(launcher.Visible):toBe(true)
						expect(root.Size):toBe(size)
						expect(root.AutomaticSize):toBe(automatic)
					end
					world.stop()
				end
			end,
		})

		it("fits iconless tool captions and button padding inside the default wedges", {
			id = "native_radial_controls::radial full caption fit::fits iconless tool captions and button padding inside the default wedges",
			run = function()
				local world = setup({
					items = {
						action({ id = "plant", label = "Plant", onSelect = function() end }),
						action({ id = "harvest", label = "Harvest", onSelect = function() end }),
						action({ id = "plow", label = "Plow", onSelect = function() end }),
					},
				})
				for _, id in { "plant", "harvest", "plow" } do
					world.engine.environment.poke(
						world.find(id):FindFirstChild("CaptionMeasure"),
						"TextBounds",
						world.engine.types.Vector2.new(36, 16)
					)
				end
				world.step(1)
				for _, id in { "plant", "harvest", "plow" } do
					local button = world.find(id)
					expect(button.Size.X.Offset >= 36 + 24):toBe(true)
					expect(button.TextWrapped):toBe(false)
				end
				world.stop()
			end,
		})

		it("keeps complete iconless captions when a phone launcher bounds the ring", {
			id = "native_radial_controls::radial full caption fit::keeps complete iconless captions when a phone launcher bounds the ring",
			run = function()
				local world = setup({
					label = "Tools",
					items = {
						action({ id = "plant", label = "Plant", onSelect = function() end }),
						action({ id = "harvest", label = "Harvest", onSelect = function() end }),
						action({ id = "plow", label = "Plow", onSelect = function() end }),
					},
				})
				local V2 = world.engine.types.Vector2
				world.engine.environment.poke(world.screen, "AbsoluteSize", V2.new(390, 844))
				local launcher = world.find("Launcher")
				world.engine.environment.poke(launcher, "AbsolutePosition", V2.new(16, 350))
				world.engine.environment.poke(launcher, "AbsoluteSize", V2.new(50, 44))
				for _, id in { "plant", "harvest", "plow" } do
					world.engine.environment.poke(
						world.find(id):FindFirstChild("CaptionMeasure"),
						"TextBounds",
						V2.new(60, 16)
					)
				end
				world.step(1)
				for _, id in { "plant", "harvest", "plow" } do
					local button = world.find(id)
					expect(button.Size.X.Scale == 1 or button.Size.X.Offset >= 60 + 24):toBeTrueWith(id)
					expect(button.Text):toBe(
						if id == "plant" then "Plant" elseif id == "harvest" then "Harvest" else "Plow"
					)
					expect(button.TextWrapped):toBe(false)
				end
				world.stop()
			end,
		})

		it("uses the styled caption padding when choosing text over a compact icon", {
			id = "native_radial_controls::radial full caption fit::uses the styled caption padding when choosing text over a compact icon",
			run = function()
				local items: { Item } = {}
				local slots: { Radial.CompassSlot } = { "N", "E", "S", "W" }
				for _, slot in slots do
					table.insert(items, action({ id = slot, label = slot, icon = "flag", slot = slot }))
				end
				local world = setup({ distribution = "compass" :: "compass", items = items })
				for _, id in { "N", "E", "S", "W" } do
					local button = world.find(id)
					local padding = button:FindFirstChildWhichIsA("UIPadding", true) or world.engine.new("UIPadding")
					padding.Parent = button
					padding.PaddingLeft, padding.PaddingRight =
						world.engine.types.UDim.new(0, 0), world.engine.types.UDim.new(0, 0)
					world.engine.environment.poke(
						button:FindFirstChild("CaptionMeasure"),
						"TextBounds",
						world.engine.types.Vector2.new(12, 16)
					)
				end
				world.step(1)
				for _, id in { "N", "E", "S", "W" } do
					local button = world.find(id)
					expect((button:FindFirstChild("Title", true) or button).Text):toBe(id)
					expect(button:FindFirstChild("LeadingIcon", true).Visible):toBe(false)
				end
				world.stop()
			end,
		})

		it("eight short measured captions keep the ring on a wide screen", {
			id = "native_radial_controls::radial full caption fit::eight short measured captions keep the ring on a wide screen",
			run = function()
				local labels = { "GL", "Nice!", "Go!", "Thanks", "Bend!", "Drift!", "Again?", "GG" }
				local items: { Item } = {}
				for index, label in labels do
					table.insert(items, action({ id = "m" .. index, label = label, onSelect = function() end }))
				end
				local world = setup({ items = items, launcher = false })
				world.engine.environment.poke(
					world.find("Modal"),
					"AbsoluteSize",
					world.engine.types.Vector2.new(1542, 969)
				)
				for index, label in labels do
					world.engine.environment.poke(
						world.find("m" .. index):FindFirstChild("CaptionMeasure"),
						"TextBounds",
						world.engine.types.Vector2.new(9 * #label, 16)
					)
				end
				world.step(1)
				expect(world.find("RadialPanel"):GetAttribute("Presentation")):toBe("radial")
				world.stop()
			end,
		})

		it("a ring never shows a caption wider than its wedge", {
			id = "native_radial_controls::radial full caption fit::a ring never shows a caption wider than its wedge",
			run = function()
				local labels = {
					"Good luck!",
					"Nice racing!",
					"Let's go!",
					"Thanks!",
					"Watch the bend!",
					"Great drift!",
					"One more race?",
					"Well played!",
				}
				for _, perCharacter in { 9, 12 } do
					local items: { Item } = {}
					for index, label in labels do
						table.insert(items, action({ id = "m" .. index, label = label, onSelect = function() end }))
					end
					local world = setup({ items = items, launcher = false })
					local V2 = world.engine.types.Vector2
					world.engine.environment.poke(world.find("Modal"), "AbsoluteSize", V2.new(1542, 969))
					for index, label in labels do
						world.engine.environment.poke(
							world.find("m" .. index):FindFirstChild("CaptionMeasure"),
							"TextBounds",
							V2.new(perCharacter * #label, 16)
						)
					end
					world.step(1)
					if world.find("RadialPanel"):GetAttribute("Presentation") == "radial" then
						for index, label in labels do
							local button = world.find("m" .. index)
							expect(button.Size.X.Offset >= perCharacter * #label):toBeTrueWith(
								`{label}: a {button.Size.X.Offset} px box for a {perCharacter * #label} px caption`
							)
						end
					end
					world.stop()
				end
			end,
		})

		it("paints a band wider than the Path2D thickness limit with adjacent strokes", {
			id = "native_radial_controls::radial full caption fit::paints a band wider than the Path2D thickness limit with adjacent strokes",
			run = function()
				local labels = {
					"Good luck!",
					"Nice racing!",
					"Let's go!",
					"Thanks!",
					"Watch the bend!",
					"Great drift!",
					"One more race?",
					"Well played!",
				}
				local icons = { "flag", "star", "bolt", "heart", "status.warning", "trophy", "timer", "crown" }
				local items: { Item } = {}
				for index, label in labels do
					table.insert(
						items,
						action({ id = "m" .. index, label = label, icon = icons[index], onSelect = function() end })
					)
				end
				local world = setup({ items = items, launcher = false })
				local V2 = world.engine.types.Vector2
				world.engine.environment.poke(world.find("Modal"), "AbsoluteSize", V2.new(1542, 969))
				for index, label in labels do
					world.engine.environment.poke(
						world.find("m" .. index):FindFirstChild("CaptionMeasure"),
						"TextBounds",
						V2.new(9 * #label, 16)
					)
				end
				world.step(1)
				local widest, extra = 0, 0
				for _, node in world.screen:GetDescendants() do
					if node:IsA("Path2D") and string.find(node.Name, "^Sector") then
						widest = math.max(widest, node.Thickness)
						if node.Name ~= "Sector" and node.Visible then
							extra += 1
						end
					end
				end
				expect(widest <= 100):toBeTrueWith(`a {widest} px stroke`)
				expect(extra > 0):toBeTrueWith("no adjacent stroke for a band wider than 100")
				world.stop()
			end,
		})

		it("an icon that every item shares never replaces a label that does not fit", {
			id = "native_radial_controls::radial full caption fit::an icon that every item shares never replaces a label that does not fit",
			run = function()
				local labels = {
					"Good luck!",
					"Nice racing!",
					"Let's go!",
					"Thanks!",
					"Watch the bend!",
					"Great drift!",
					"One more race?",
					"Well played!",
				}
				local items: { Item } = {}
				for index, label in labels do
					table.insert(
						items,
						action({ id = "m" .. index, label = label, icon = "star", onSelect = function() end })
					)
				end
				local world = setup({ items = items })
				world.engine.environment.poke(
					world.find("Modal"),
					"AbsoluteSize",
					world.engine.types.Vector2.new(390, 760)
				)
				for index, label in labels do
					world.engine.environment.poke(
						world.find("m" .. index):FindFirstChild("CaptionMeasure"),
						"TextBounds",
						world.engine.types.Vector2.new(9 * #label, 16)
					)
				end
				world.step(1)
				local list = world.find("RadialPanel"):GetAttribute("Presentation") == "list"
				for index in labels do
					local button = world.find("m" .. index)
					local glyph = button:FindFirstChild("LeadingIcon", true)
					local iconOnly = not list and glyph ~= nil and glyph.Visible
					expect(iconOnly):toBe(false)
				end
				world.stop()
			end,
		})

		it("uses the full caption and button padding before choosing a glyph", {
			id = "native_radial_controls::radial full caption fit::uses the full caption and button padding before choosing a glyph",
			run = function()
				local items: { Item } = {}
				for _, id in { "settings", "edit", "flag", "trash", "person", "calendar" } do
					table.insert(items, action({ id = id, label = id, icon = id, onSelect = function() end }))
				end
				local world = setup({ items = items })
				world.engine.environment.poke(
					world.find("Modal"),
					"AbsoluteSize",
					world.engine.types.Vector2.new(390, 760)
				)
				local button = world.find("settings")
				local title = button:FindFirstChild("Title", true) or button
				world.engine.environment.poke(title, "TextBounds", world.engine.types.Vector2.new(32, 16))
				local measure = assert(button:FindFirstChild("CaptionMeasure"))
				local points = title.TextSize
				title.TextSize = points + 2
				expect(measure.TextSize):toBe(points + 2)
				title.TextSize = points
				world.engine.environment.poke(measure, "TextBounds", world.engine.types.Vector2.new(48, 16))
				expect(measure.Text):toBe("settings")
				expect(measure.TextTruncate.Name):toBe("None")
				expect(measure.TextTransparency):toBe(1)
				expect(measure.Interactable):toBe(false)
				expect(title.Text):toBe("settings")
				expect(button.Size.X.Offset >= 48 + 24):toBe(true)
				world.engine.environment.poke(measure, "TextBounds", world.engine.types.Vector2.new(104, 16))
				expect(title.Text):toBe("")
				expect(button:FindFirstChild("LeadingIcon", true).Visible):toBe(true)
				world.step(1)
				expect(measure.Text):toBe("settings")
				expect(title.Text):toBe("")
				local person = world.find("person")
				local personTitle = person:FindFirstChild("Title", true) or person
				world.engine.environment.poke(personTitle, "TextBounds", world.engine.types.Vector2.new(36, 16))
				world.engine.environment.poke(
					person:FindFirstChild("CaptionMeasure"),
					"TextBounds",
					world.engine.types.Vector2.new(43, 16)
				)
				expect(personTitle.Text == "" or person.Size.X.Offset >= 43):toBe(true)
				world.stop()
			end,
		})
	end)

	describe("native radial interaction policies", function()
		it("content fitting keeps the full button on its wedge", {
			id = "native_radial_controls::native radial interaction policies::content fitting keeps the full button on its wedge",
			run = function()
				local world = setup({ distribution = "compass" :: "compass", items = compass(function() end) })
				for _, id in { "N", "E", "S", "W" } do
					local button = world.find(id)
					local title = button:FindFirstChild("Title", true) or button
					world.engine.environment.poke(title, "TextBounds", world.engine.types.Vector2.new(8, 16))
				end
				world.step(1)
				for _, id in { "N", "E", "S", "W" } do
					local button = world.find(id)
					local paint = button.Parent:FindFirstChild("Paint")
					local x = button.Position.X.Offset - button.Size.X.Offset / 2
					local y = button.Position.Y.Offset - button.Size.Y.Offset / 2
					expect(x >= paint.Position.X.Offset - 1):toBe(true)
					expect(y >= paint.Position.Y.Offset - 1):toBe(true)
					expect(x + button.Size.X.Offset <= paint.Position.X.Offset + paint.Size.X.Offset + 1):toBe(true)
					expect(y + button.Size.Y.Offset <= paint.Position.Y.Offset + paint.Size.Y.Offset + 1):toBe(true)
				end
				world.stop()
			end,
		})

		it("keeps the measured overlay origin while the opening touch freezes the center", {
			id = "native_radial_controls::native radial interaction policies::keeps the measured overlay origin while the opening touch freezes the center",
			run = function()
				local world = setup({ isPresented = Compose.cell(false), items = compass(function() end) }, true)
				local V2 = world.engine.types.Vector2
				world.engine.environment.poke(world.screen, "AbsolutePosition", V2.new(0, 60))
				world.engine.environment.poke(world.screen, "AbsoluteSize", V2.new(390, 780))
				local launcher = world.find("Launcher")
				world.engine.environment.poke(launcher, "AbsolutePosition", V2.new(24, 360))
				world.engine.environment.poke(launcher, "AbsoluteSize", V2.new(120, 44))
				local touch = pointer(world, 80, 380)
				launcher.InputBegan:Fire(touch)
				local center = world.find("Center")
				local original = center.Position
				expect(original.Y.Offset):toBe(322)
				local modal = center.Parent
				world.engine.environment.poke(modal, "AbsolutePosition", world.screen.AbsolutePosition)
				world.engine.environment.poke(modal, "AbsoluteSize", world.screen.AbsoluteSize)
				world.step(0.25)
				expect(center.Position):toBe(original)
				world.input.InputEnded:Fire(touch)
				world.step(0.25)
				expect(center.Position):toBe(original)
				world.stop()
			end,
		})

		it("the ring's Back and Close are icon-only even when the level's items carry text labels", {
			id = "native_radial_controls::native radial interaction policies::the ring's Back and Close are icon-only even when the level's items carry text labels",
			run = function()
				local world = setup({
					center = "empty" :: "empty",
					items = {
						{
							id = "gear",
							label = "Gear",
							children = { { id = "wear", label = "Wear" }, { id = "tools", label = "Tools" } },
						} :: Radial.RadialItem<string>,
						{ id = "wave", label = "Wave" } :: Radial.RadialItem<string>,
					},
				})
				world.step(0.5)
				local function navigation()
					local button = world.find("$navigation")
					return button.Text, button:FindFirstChild("LeadingIcon", true).Visible
				end
				local text, glyph = navigation()
				expect(`{text}|{glyph}`):toBe("|true")
				world.find("gear").Activated:Fire()
				world.step(0.5)
				text, glyph = navigation()
				expect(`{text}|{glyph}`):toBe("|true")
				expect(world.find("$navigation"):GetAttribute("label") or "Back"):toBe("Back")
				world.stop()
			end,
		})

		it("a pointer opening leaves the ring unhighlighted though a stale keyboard selection remains", {
			id = "native_radial_controls::native radial interaction policies::a pointer opening leaves the ring unhighlighted though a stale keyboard selection remains",
			run = function()
				for _, last in { "MouseButton1", "Keyboard" } do
					local world = setup(function()
						return {
							isPresented = Compose.cell(false),
							center = "empty" :: "empty",
							items = {
								{ id = "gear", label = "Gear", icon = "menu", labelStyle = "icon" :: "icon" } :: Radial.RadialItem<string>,
								{ id = "wave", label = "Wave", icon = "flag", labelStyle = "icon" :: "icon" } :: Radial.RadialItem<string>,
							},
						}
					end)
					local E = world.engine.types.Enum
					world.engine.environment.fakeOn(world.input, "GetLastInputType", function()
						return assert(E.UserInputType:FromName(last))
					end)
					world.gui.SelectedObject = world.find("Launcher")
					world.opened:set(true)
					world.step(0.5)
					local tagged =
						world.find("Sector-gear"):FindFirstChild("Sector", true):HasTag("facet-radial-candidate")
					local inside = world.gui.SelectedObject ~= nil
						and world.gui.SelectedObject:IsDescendantOf(world.find("RadialPanel"))
					expect(`{last}:{tagged}:{inside}`):toBe(
						if last == "Keyboard" then `{last}:true:true` else `{last}:false:false`
					)
					world.stop()
				end
			end,
		})
		it("draws icon-only items at the menu icon size inside their sector", {
			id = "native_radial_controls::native radial interaction policies::draws icon-only items at the menu icon size inside their sector",
			run = function()
				local world = setup({
					center = "empty" :: "empty",
					iconSize = 40,
					ringWidth = 96,
					items = {
						{ id = "gear", label = "Gear", icon = "menu", labelStyle = "icon" :: "icon" } :: Radial.RadialItem<string>,
						{ id = "wave", label = "Wave", icon = "flag", labelStyle = "icon" :: "icon" } :: Radial.RadialItem<string>,
					},
				}, true)
				world.step(1)
				local gear = world.find("gear")
				local glyph = assert(gear:FindFirstChild("LeadingIcon", true))
				local room = math.min(gear.Size.X.Offset, gear.Size.Y.Offset)
				expect(glyph.Size.X.Offset):toBe(40)
				expect(room >= 44):toBe(true)
				world.stop()
			end,
		})

		it("a level's wedges keep their shape while they fade out for the next level", {
			id = "native_radial_controls::native radial interaction policies::a level's wedges keep their shape while they fade out for the next level",
			run = function()
				local world = setup({
					center = "empty" :: "empty",
					contentFit = "radial" :: "radial",
					items = {
						{
							id = "gear",
							label = "Gear",
							icon = "menu",
							labelStyle = "icon" :: "icon",
							children = {
								{ id = "wear", label = "Wear the lantern" },
								{ id = "tools", label = "Tools" },
							},
						} :: Radial.RadialItem<string>,
						{ id = "wave", label = "Wave", icon = "flag", labelStyle = "icon" :: "icon" } :: Radial.RadialItem<string>,
					},
				}, true)
				world.step(1)
				local wave = world.find("Sector-wave")
				local paint = wave:FindFirstChild("Paint", true)
				local before =
					`{paint.Position.X.Offset},{paint.Position.Y.Offset},{paint:FindFirstChild("Sector").Thickness}`
				world.find("gear").Activated:Fire()
				world.step(1 / 60)
				expect(wave.Parent ~= nil):toBe(true)
				local after =
					`{paint.Position.X.Offset},{paint.Position.Y.Offset},{paint:FindFirstChild("Sector").Thickness}`
				expect(after):toBe(before)
				local arriving = world.find("Sector-wear")
				local fade = fadeKit.of(arriving)
				expect(fade > 0.5):toBe(true)
				world.step(0.5)
				expect(fadeKit.of(arriving)):toBe(0)
				world.stop()
			end,
		})

		it("a corner menu can leave an empty centre for its caller's toggle", {
			id = "native_radial_controls::native radial interaction policies::a corner menu can leave an empty centre for its caller's toggle",
			run = function()
				local world = setup({
					preset = "bottom-right",
					launcher = false,
					center = "empty",
					centerPassThrough = true,
					items = compass(function() end),
				})
				expect(world.find("Center").Visible):toBe(false)
				expect(world.find("CenterHit").Visible):toBe(false)
				expect(world.find("Modal").Active):toBe(false)
				expect(world.find("DismissTarget").Visible):toBe(false)
				expect(world.find("DismissTop").Visible):toBe(true)
				world.find("DismissTop").Activated:Fire()
				expect(world.opened:peek()):toBe(false)
				world.stop()
			end,
		})
		it("an empty pass-through centre preserves only its anchor's input ownership", {
			id = "native_radial_controls::native radial interaction policies::an empty pass-through centre preserves only its anchor's input ownership",
			run = function()
				local engine = engines.new()
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local UI = controls(Compose, runtime, { types = engine.types, motionLevel = "none" })
				local opened = Compose.cell(false)
				local activations = 0
				local stop, screen = runtime.mount(function()
					local anchor = UI.Button "Toggle" {
						label = "Toggle actions",
						onActivate = function()
							activations += 1
							opened:set(not opened:peek())
						end,
					}
					local options: RadialProps.RadialMenuSpec<string> = {
						anchor = anchor,
						isPresented = opened,
						launcher = false,
						preset = "bottom-right",
						center = "empty",
						centerPassThrough = true,
						items = compass(function() end),
					}
					return Facet.host(runtime).ScreenGui {
						runtime.constructors.ScrollingFrame "AnchorContainer" {
							Selectable = true,
							anchor,
						},
						UI.Button "Unrelated" { label = "Unrelated" },
						(UI.RadialMenu :: any)(options),
					}
				end, engine.new("Folder"))
				local screenGui = (screen) :: ScreenGui
				local anchor = screenGui:FindFirstChild("Toggle", true)
				local unrelated = screenGui:FindFirstChild("Unrelated", true)
				assert(anchor and anchor:IsA("TextButton") and unrelated and unrelated:IsA("TextButton"))
				local container = anchor.Parent
				assert(container and container:IsA("ScrollingFrame"))
				local activated = (anchor.Activated) :: { Fire: (unknown) -> () }
				for _ = 1, 3 do
					activated:Fire()
					expect(opened:peek()):toBe(true)
					expect(anchor.Interactable):toBe(true)
					expect(container.Interactable):toBe(true)
					expect(unrelated.Interactable):toBe(false)
					activated:Fire()
					expect(opened:peek()):toBe(false)
					expect(unrelated.Interactable):toBe(true)
				end
				expect(activations):toBe(6)
				stop()
				runtime:dispose()
			end,
		})
		it("a corner menu keeps its launcher's room while the launcher hides under the open ring", {
			id = "native_radial_controls::native radial interaction policies::a corner menu keeps its launcher's room while the launcher hides under the open ring",
			run = function()
				local world = setup({
					isPresented = Compose.cell(false),
					preset = "bottom-left" :: "bottom-left",
					appearance = "buttons" :: "buttons",
					items = { { id = "look", label = "Look", icon = "facet:search" } :: Radial.RadialItem<string> },
				})
				local launcher = world.find("Launcher")
				local root = launcher.Parent
				world.engine.environment.poke(launcher, "AbsoluteSize", world.engine.types.Vector2.new(44, 44))
				world.engine.environment.poke(root, "AbsoluteSize", world.engine.types.Vector2.new(44, 44))
				world.opened:set(true)
				world.step(0.5)
				expect(launcher.Visible):toBe(false)
				expect(`{root.AutomaticSize.Name} {root.Size.X.Offset}x{root.Size.Y.Offset}`):toBe("None 44x44")
				world.opened:set(false)
				world.step(0.5)
				expect(launcher.Visible):toBe(true)
				expect(root.AutomaticSize.Name):toBe("XY")
				world.stop()
			end,
		})
		it("a corner menu holds its own room in layout units and hands back the caller's size", {
			id = "native_radial_controls::native radial interaction policies::a corner menu holds its own room in layout units and hands back the caller's size",
			run = function()
				local world = setup(function(engine)
					return {
						isPresented = Compose.cell(false),
						preset = "bottom-left" :: "bottom-left",
						appearance = "buttons" :: "buttons",
						Size = engine.types.UDim2.fromOffset(60, 0),
						AutomaticSize = engine.types.Enum.AutomaticSize.Y,
						items = { { id = "look", label = "Look", icon = "facet:search" } :: Radial.RadialItem<string> },
					}
				end)
				local V2 = world.engine.types.Vector2
				local launcher = world.find("Launcher")
				local root = launcher.Parent
				world.engine.environment.poke(root:FindFirstChild("LayoutUnit"), "AbsoluteSize", V2.new(62, 0.62))
				world.engine.environment.poke(launcher, "AbsoluteSize", V2.new(27.28, 27.28))
				world.engine.environment.poke(root, "AbsoluteSize", V2.new(37.2, 27.28))
				world.opened:set(true)
				world.step(0.5)
				expect(`{root.AutomaticSize.Name} {root.Size.X.Offset}x{root.Size.Y.Offset}`):toBe("None 60x44")
				world.opened:set(false)
				world.step(0.5)
				expect(`{root.AutomaticSize.Name} {root.Size}`):toBe("Y {0, 60}, {0, 0}")
				world.stop()
			end,
		})
		it("a corner menu names the hovered button right beside it", {
			id = "native_radial_controls::native radial interaction policies::a corner menu names the hovered button right beside it",
			run = function()
				local world = setup({
					preset = "bottom-left" :: "bottom-left",
					appearance = "buttons" :: "buttons",
					items = {
						{ id = "look", label = "Look", icon = "facet:search" } :: Radial.RadialItem<string>,
						{ id = "pack", label = "Pack", icon = "menu" } :: Radial.RadialItem<string>,
						{ id = "wave", label = "Wave", icon = "flag" } :: Radial.RadialItem<string>,
					},
				})
				world.step(0.5)
				world.engine.environment.fakeOn(world.input, "GetLastInputType", function()
					return world.engine.types.Enum.UserInputType.MouseMovement
				end)
				for _, id in { "look", "wave" } do
					local button = world.find(id)
					button.MouseEnter:Fire()
					local preview = world.find("SelectionPreview")
					expect(preview.Text):toBe(if id == "look" then "Look" else "Wave")
					local dx = preview.Position.X.Offset - button.Position.X.Offset
					local dy = preview.Position.Y.Offset - button.Position.Y.Offset
					local gap = math.sqrt(dx * dx + dy * dy) - button.Size.X.Offset / 2
					expect(gap >= 0 and gap <= 8):toBe(true)
					button.MouseLeave:Fire()
				end
				world.stop()
			end,
		})
		it("a slim-band ring paints its wedges only once every label on it is measured", {
			id = "native_radial_controls::native radial interaction policies::a slim-band ring paints its wedges only once every label on it is measured",
			run = function()
				local world = setup({
					contentFit = "radial" :: "radial",
					items = {
						{ id = "wear", label = "Wear" } :: Radial.RadialItem<string>,
						{ id = "tools", label = "Tools" } :: Radial.RadialItem<string>,
					},
				})
				world.step(0.5)
				local function shown(id: string)
					return world.find("Sector-" .. id):FindFirstChild("Paint").Visible
				end
				expect(`{shown("wear")} {shown("tools")}`):toBe("false false")
				world.engine.environment.poke(world.find("wear"), "TextBounds", world.engine.types.Vector2.new(34, 16))
				expect(`{shown("wear")} {shown("tools")}`):toBe("false false")
				world.engine.environment.poke(world.find("tools"), "TextBounds", world.engine.types.Vector2.new(38, 16))
				expect(`{shown("wear")} {shown("tools")}`):toBe("true true")
				world.stop()
			end,
		})
		it("NRAD-1 analog hold commits once and respects dead-zone hysteresis", {
			id = "native_radial_controls::native radial interaction policies::NRAD-1 analog hold commits once and respects dead-zone hysteresis",
			run = function()
				local engine, picked = engines.new(), {}
				local hold = engine.new("InputAction")
				local world = setup({
					isPresented = Compose.cell(false),
					holdAction = hold,
					distribution = "compass" :: "compass",
					items = compass(function(id)
						table.insert(picked, id)
					end),
				})
				hold.Pressed:Fire()
				local axis = world.find("RadialAim")
				expect(axis.Type):toBe(world.engine.types.Enum.InputActionType.Direction2D)
				axis.StateChanged:Fire(world.engine.types.Vector2.new(0, 0.3))
				hold.Released:Fire()
				expect(#picked):toBe(0)
				hold.Pressed:Fire()
				axis.StateChanged:Fire(world.engine.types.Vector2.new(0, 0.8))
				axis.StateChanged:Fire(world.engine.types.Vector2.new(0, 0.3))
				hold.Released:Fire()
				hold.Released:Fire()
				expect((table.concat(picked, ","))):toBe("N")
				world.stop()
				expect((engines.connections(hold.Pressed))):toBe(0)
				expect((engines.connections(hold.Released))):toBe(0)
			end,
		})
		it("NRAD-1b a gamepad commit works after the radial closes and opens again", {
			id = "native_radial_controls::native radial interaction policies::NRAD-1b a gamepad commit works after the radial closes and opens again",
			run = function()
				local picked = {}
				local open = Compose.cell(false)
				local world = setup({
					isPresented = open,
					distribution = "compass" :: "compass",
					items = compass(function(id)
						table.insert(picked, id)
					end),
				})
				for _ = 1, 2 do
					open:set(true)
					world.step(0.5)
					open:set(false)
					world.step(0.5)
				end
				open:set(true)
				world.step(0.5)
				world.find("RadialAim").StateChanged:Fire(world.engine.types.Vector2.new(0, 0.8))
				world.find("RadialCommit").Pressed:Fire()
				expect((table.concat(picked, ","))):toBe("N")
				world.stop()
			end,
		})
		it("NRAD-2 ignores foreign touch release and cancels captured touch", {
			id = "native_radial_controls::native radial interaction policies::NRAD-2 ignores foreign touch release and cancels captured touch",
			run = function()
				local count = 0
				local world = setup({
					distribution = "compass" :: "compass",
					items = compass(function()
						count += 1
					end),
				})
				local panel, touch = world.find("RadialPanel"), pointer(world, 320, 110)
				panel.InputBegan:Fire(touch)
				world.input.InputEnded:Fire(pointer(world, 320, 110))
				expect(count):toBe(0)
				touch.UserInputState = world.engine.types.Enum.UserInputState.Cancel
				world.input.InputEnded:Fire(touch)
				expect(count):toBe(0)
				world.stop()
			end,
		})
		it("NRAD-3 suppresses the native activation echo after gesture commit", {
			id = "native_radial_controls::native radial interaction policies::NRAD-3 suppresses the native activation echo after gesture commit",
			run = function()
				local count = 0
				local world = setup({
					distribution = "compass" :: "compass",
					items = compass(function()
						count += 1
					end),
				})
				local touch = pointer(world, 320, 110)
				world.find("N").InputBegan:Fire(touch)
				world.input.InputEnded:Fire(touch)
				world.find("N").Activated:Fire(touch)
				expect(count):toBe(1)
				world.find("N").InputBegan:Fire(touch)
				world.input.InputEnded:Fire(touch)
				expect(count):toBe(2)
				world.stop()
			end,
		})
		it("NRAD-4 direction gestures work outside paint while bounded gestures cancel", {
			id = "native_radial_controls::native radial interaction policies::NRAD-4 direction gestures work outside paint while bounded gestures cancel",
			run = function()
				for _, mode in { "direction", "bounded" } :: { "bounded" | "direction" } do
					local count = 0
					local world = setup({
						distribution = "compass" :: "compass",
						gestureSelection = mode :: "bounded" | "direction",
						items = compass(function()
							count += 1
						end),
					})
					local touch = pointer(world, 320, 110)
					world.find("RadialPanel").InputBegan:Fire(touch)
					touch.Position = world.engine.types.Vector3.new(320, -600, 0)
					world.input.InputChanged:Fire(touch)
					world.input.InputEnded:Fire(touch)
					expect(count):toBe(if mode == "direction" then 1 else 0)
					world.stop()
				end
			end,
		})
		it("NRAD-5 freezes idle-follow anchor during capture then resumes", {
			id = "native_radial_controls::native radial interaction policies::NRAD-5 freezes idle-follow anchor during capture then resumes",
			run = function()
				local start: Radial.Anchor = { x = 320, y = 240 }
				local anchor = Compose.cell(start)
				local world =
					setup({ anchor = anchor, distribution = "compass" :: "compass", items = compass(function() end) })
				local north = world.find("N").Position
				local touch = pointer(world, north.X.Offset, north.Y.Offset)
				world.find("RadialPanel").InputBegan:Fire(touch)
				anchor:set({ x = 400, y = 240 })
				expect(world.find("N").Position.X.Offset):toBe(320)
				world.input.InputEnded:Fire(touch)
				expect(world.find("N").Position.X.Offset):toBe(400)
				anchor:set({ x = 400, y = 240, visible = false })
				expect((world.opened:peek())):toBe(false)
				world.stop()
			end,
		})
		it("NRAD-6 adapts into native scrolling list without losing a branch", {
			id = "native_radial_controls::native radial interaction policies::NRAD-6 adapts into native scrolling list without losing a branch",
			run = function()
				local count = 0
				local world = setup({
					items = {
						{
							id = "Branch",
							label = "Branch",
							children = {
								{
									id = "Child",
									label = "Child",
									onSelect = function()
										count += 1
									end,
								},
							},
						} :: Radial.RadialItem<string>,
					},
				})
				world.find("Branch").Activated:Fire()
				world.engine.environment.poke(
					world.find("Modal"),
					"AbsoluteSize",
					world.engine.types.Vector2.new(180, 180)
				)
				local panel = world.find("RadialPanel")
				expect((panel:GetAttribute("Presentation"))):toBe("list")
				expect(panel.ScrollingEnabled):toBe(true)
				expect(panel:FindFirstChildWhichIsA("UIListLayout") ~= nil):toBe(true)
				expect(world.find("Child").Size.Y.Offset):toBe(44)

				expect(world.find("SelectionPreview").Text):toBe("Branch")
				world.find("Child").Activated:Fire()
				expect(count):toBe(1)
				world.stop()
			end,
		})
		it("list fallback bounds short commands and grows for measured labels within narrow room", {
			id = "native_radial_controls::native radial interaction policies::list fallback bounds short commands and grows for measured labels within narrow room",
			run = function()
				local selected = ""
				local world = setup({
					anchor = { x = 80, y = 60 },
					clearance = 160,
					label = "Crew commands: inspect the route, confirm the crossing and wait for the rest of the team before moving",
					items = compass(function(id)
						selected = id
					end),
				})
				local V2 = world.engine.types.Vector2
				world.engine.environment.poke(world.find("Modal"), "AbsoluteSize", V2.new(1600, 300))
				local panel = world.find("RadialPanel")
				expect(panel:GetAttribute("Presentation")):toBe("list")
				expect(panel.Size.X.Scale):toBe(0)
				expect(panel.Size.X.Offset < 800):toBe(true)
				expect(panel.Position.X.Offset + panel.Size.X.Offset / 2):toBe(0)
				expect(panel.ScrollingEnabled):toBe(true)
				local title = world.find("SelectionPreview")
				expect(title.AnchorPoint.Y):toBe(0)
				expect(title.Position.Y.Offset):toBe(2)
				world.engine.environment.poke(title, "AbsoluteSize", V2.new(312, 96))
				expect(panel.Position.Y.Offset):toBe(106)
				expect(panel.Size.Y.Offset):toBe(-138)
				world.engine.environment.poke(title, "AbsoluteSize", V2.new(312, 59.6))
				expect(panel.Position.Y.Offset):toBe(70)
				expect(panel.Size.Y.Offset):toBe(-102)
				world.engine.environment.poke(title, "AbsoluteSize", V2.new(312, 24))
				expect(panel.Position.Y.Offset):toBe(48)
				expect(panel.Size.Y.Offset):toBe(-80)
				local previous = panel.Size.X.Offset
				local measure = world.find("N"):FindFirstChild("CaptionMeasure", true)
				world.engine.environment.poke(measure, "TextBounds", V2.new(620, 20))
				expect(panel.Size.X.Offset > previous):toBe(true)
				expect(panel.Size.X.Offset >= 620):toBe(true)
				world.engine.environment.poke(world.find("Modal"), "AbsoluteSize", V2.new(240, 300))
				expect(panel.Size.X.Offset <= 208):toBe(true)
				expect(world.find("SelectionPreview").Size.X.Offset < panel.Size.X.Offset):toBe(true)
				world.find("N").Activated:Fire()
				expect(selected):toBe("N")
				expect(world.opened:peek()):toBe(true)
				world.find("CenterHit").Activated:Fire()
				expect(world.opened:peek()):toBe(false)
				world.stop()
			end,
		})
		it("NRAD-7 state items stay open and completion precedes callbacks", {
			id = "native_radial_controls::native radial interaction policies::NRAD-7 state items stay open and completion precedes callbacks",
			run = function()
				local checked, selected, count, during = Compose.cell(false), Compose.cell("a"), 0, nil
				local opened = Compose.cell(true)
				local world = setup({
					isPresented = opened,
					items = {
						{ id = "Check", label = "Check", checked = checked } :: Radial.RadialItem<string>,
						{
							id = "Radio",
							label = "Radio",
							selected = selected,
							value = "b",
							onChange = function()
								count += 1
							end,
						} :: Radial.RadialItem<string>,
						{
							id = "Done",
							label = "Done",
							onSelect = function()
								during = opened:peek()
							end,
						} :: Radial.RadialItem<string>,
					},
				})
				world.find("Check").Activated:Fire()
				expect((checked:peek())):toBe(true)
				expect((opened:peek())):toBe(true)
				world.find("Radio").Activated:Fire()
				world.find("Radio").Activated:Fire()
				expect(count):toBe(1)
				world.find("Done").Activated:Fire()
				expect(during):toBe(false)
				world.stop()
			end,
		})
		it("NRAD-8 nested expansion preserves parents and completion back returns", {
			id = "native_radial_controls::native radial interaction policies::NRAD-8 nested expansion preserves parents and completion back returns",
			run = function()
				local world = setup({
					navigation = "replace" :: "replace",
					gestureSelection = "direction" :: "direction",
					items = {
						{
							id = "Branch",
							label = "Branch",
							navigation = "expand" :: "expand",
							expansion = "fan" :: "fan",
							children = { { id = "Child", label = "Child", completion = "back" :: "back" } },
						} :: Radial.RadialItem<string>,
					},
				})
				world.find("Branch").Activated:Fire()
				expect(world.find("Branch") ~= nil):toBe(true)
				expect(world.find("Child") ~= nil):toBe(true)
				world.find("Child").Activated:Fire()
				expect(world.find("Branch") ~= nil):toBe(true)
				expect((world.find("Child"))):toBe(nil)
				world.stop()
			end,
		})
		it("NRAD-9 Compose exit presence releases native ownership after animation", {
			id = "native_radial_controls::native radial interaction policies::NRAD-9 Compose exit presence releases native ownership after animation",
			run = function()
				local world = setup({ items = compass(function() end) }, true)
				world.step(0.3)
				local panel = world.find("RadialPanel")
				world.opened:set(false)
				expect((world.find("RadialPanel"))):toBe(panel)
				expect(panel.Interactable):toBe(false)
				world.step(0.3)
				expect((world.find("RadialPanel"))):toBe(nil)
				expect((not world.engine.environment.isAlive(panel))):toBe(true)
				world.stop()
			end,
		})
		it("NRAD-10 reduced motion closes immediately and releases listeners", {
			id = "native_radial_controls::native radial interaction policies::NRAD-10 reduced motion closes immediately and releases listeners",
			run = function()
				local world = setup({ items = compass(function() end) })
				expect(engines.connections(world.input.InputEnded) > 0):toBe(true)
				world.opened:set(false)
				expect((world.find("RadialPanel"))):toBe(nil)
				expect((engines.connections(world.input.InputEnded))):toBe(0)
				world.stop()
			end,
		})

		it("NRAD-12 empty center keeps ring Back and full-label preview", {
			id = "native_radial_controls::native radial interaction policies::NRAD-12 empty center keeps ring Back and full-label preview",
			run = function()
				local world = setup({
					center = "empty" :: "empty",
					items = {
						{
							id = "Branch",
							label = "Branch",
							children = {
								{
									id = "Action",
									label = "Long readable action",
									compactLabel = { icon = "menu", prefer = true },
								},
							},
						} :: Radial.RadialItem<string>,
					},
				})
				world.find("Branch").Activated:Fire()
				world.engine.environment.fakeOn(world.input, "GetLastInputType", function()
					return world.engine.types.Enum.UserInputType.MouseMovement
				end)
				world.find("Action").MouseEnter:Fire()
				expect(world.find("SelectionPreview").Text):toBe("Long readable action")
				world.find("$navigation").Activated:Fire()
				expect(world.find("Branch") ~= nil):toBe(true)
				world.stop()
			end,
		})
		it("NRAD-13 gallery nearby item uses native owned scene and real actions", {
			id = "native_radial_controls::native radial interaction policies::NRAD-13 gallery nearby item uses native owned scene and real actions",
			run = function()
				local engine = engines.new()
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local gui = (engine.new("GuiService")) :: GuiService
				gui.GuiNavigationEnabled = true
				gui.AutoSelectGuiEnabled = true
				gui.TouchControlsEnabled = true
				engine.environment.fakeOn(VerifyRoblox.assertInstance(gui), "GetGuiInset", function()
					return engine.types.Vector2.zero, engine.types.Vector2.zero
				end)
				engine.environment.fakeOn(VerifyRoblox.assertInstance(gui), "GetInsetArea", function()
					return engine.types.Rect.new(0, 0, 1280, 720)
				end)
				local ctx: Context = {
					Facet = Facet,
					Compose = Compose,
					runtime = runtime,
					Host = Facet.host(runtime),
					types = engine.types,
					viewport = Compose.cell({ width = 1280, height = 720 }),
					buildStamp = nil,
					environment = nil,
					guiService = gui,
					UI = controls(Compose, runtime, {
						types = engine.types,
						services = { GuiService = gui },
						motionLevel = "none",
					}),
				}
				local radialScenario = require("../examples/gallery/scenarios/radial_menu")
				local built: typeof(radialScenario.build(ctx))? = nil
				local stop, screen: any = runtime.mount(function()
					local scenario = radialScenario.build(ctx)
					built = scenario
					return Facet.host(runtime).ScreenGui({ scenario.screen() })
				end, engine.new("Folder"))
				assert(built).steps.world()
				local stage = screen:FindFirstChild("TrailPack", true)
				expect((stage:IsA("ViewportFrame"))):toBe(true)
				screen:FindFirstChild("Launcher", true).Activated:Fire()
				screen:FindFirstChild("inspect", true).Activated:Fire()
				expect(assert(assert(built).report().world).angle):toBe(45)
				screen:FindFirstChild("resize", true).Activated:Fire()
				expect(assert(assert(built).report().world).unpacked):toBe(true)
				screen:FindFirstChild("take", true).Activated:Fire()
				expect(assert(assert(built).report().world).taken):toBe(true)
				expect(stage.Visible):toBe(false)
				stop()
				expect((not engine.environment.isAlive(stage))):toBe(true)
				runtime:dispose()
			end,
		})
		it("a launcher tap leaves the menu open when its ring places an action under the finger", {
			id = "native_radial_controls::native radial interaction policies::a launcher tap leaves the menu open when its ring places an action under the finger",
			run = function()
				local count = 0
				local world = setup({
					isPresented = Compose.cell(false),
					distribution = "compass" :: "compass",
					items = compass(function()
						count += 1
					end),
				})
				local launcher, touch = world.find("Launcher"), pointer(world, 320, 110)
				world.engine.environment.poke(
					world.input,
					"PreferredInput",
					world.engine.types.Enum.PreferredInput.Touch
				)
				launcher.InputBegan:Fire(touch)
				local function unselected()
					for _, node in world.screen:GetDescendants() do
						expect((node:HasTag("facet-radial-candidate"))):toBe(false)
					end
					expect(world.find("SelectionPlate").Visible):toBe(false)
				end
				unselected()
				touch.Position = world.engine.types.Vector3.new(321, 111, 0)
				world.input.InputChanged:Fire(touch)
				world.step(0.6)
				unselected()
				touch.Position = world.engine.types.Vector3.new(322, 112, 0)
				world.input.InputChanged:Fire(touch)
				unselected()
				touch.UserInputState = world.engine.types.Enum.UserInputState.End
				world.input.InputEnded:Fire(touch)
				launcher.Activated:Fire(touch)
				expect(count):toBe(0)
				expect((world.opened:peek())):toBe(true)
				world.find("N").MouseEnter:Fire()
				unselected()
				world.find("N").Activated:Fire(pointer(world, 320, 110))
				expect(count):toBe(1)
				world.stop()
			end,
		})
		it("NRAD-14 launcher press slide releases directly into an action", {
			id = "native_radial_controls::native radial interaction policies::NRAD-14 launcher press slide releases directly into an action",
			run = function()
				local count = 0
				local world = setup({
					isPresented = Compose.cell(false),
					distribution = "compass" :: "compass",
					items = compass(function()
						count += 1
					end),
				})
				local launcher, touch = world.find("Launcher"), pointer(world, 0, 0)
				launcher.InputBegan:Fire(touch)
				expect((world.opened:peek())):toBe(true)
				touch.Position = world.engine.types.Vector3.new(320, 110, 0)
				world.input.InputChanged:Fire(touch)
				world.input.InputEnded:Fire(touch)
				launcher.Activated:Fire(touch)
				expect(count):toBe(1)
				expect((world.opened:peek())):toBe(true)
				world.stop()
			end,
		})
		it("NRAD-15 branch replacement retains fading geometry and reclaims interrupted presence", {
			id = "native_radial_controls::native radial interaction policies::NRAD-15 branch replacement retains fading geometry and reclaims interrupted presence",
			run = function()
				for _, animated in { true, false } do
					local world = setup({
						items = {
							{
								id = "Branch",
								label = "Branch",
								children = { { id = "Leaf", label = "Leaf", onSelect = function() end } },
							} :: Radial.RadialItem<string>,
						},
					}, animated)
					world.step(0.3)
					local parent = world.find("Sector-Branch")
					local position = parent:FindFirstChild("Paint", true).Position
					world.find("Branch").Activated:Fire()
					local child = world.find("Sector-Leaf")
					expect(child ~= nil):toBe(true)
					if animated then
						expect((not world.engine.environment.isAlive(parent))):toBe(false)
						expect(parent.Parent.Interactable):toBe(false)
						world.step(0.04)
						expect(fadeKit.of(parent) > 0 and fadeKit.of(parent) < 1):toBe(true)
						expect(parent:FindFirstChild("Paint", true).Position):toBe(position)
						world.find("Center").Activated:Fire()
						expect((world.find("Sector-Branch"))):toBe(parent)
						world.find("Branch").Activated:Fire()
						world.step(0.3)
					end
					expect((not world.engine.environment.isAlive(parent))):toBe(true)
					world.stop()
					expect((not world.engine.environment.isAlive(child))):toBe(true)
				end
			end,
		})
		it("NRAD-16 keeps round button swatches circular and expands the same targets into compact rows", {
			id = "native_radial_controls::native radial interaction policies::NRAD-16 keeps round button swatches circular and expands the same targets into compact rows",
			run = function()
				local selected = Compose.cell("sage")
				local world = setup({
					appearance = "buttons" :: "buttons",
					items = {
						{ id = "sage", label = "Sage", selected = selected, value = "sage" } :: Radial.RadialItem<string>,
						{ id = "clay", label = "Clay", selected = selected, value = "clay" } :: Radial.RadialItem<string>,
						{ id = "iris", label = "Iris", selected = selected, value = "iris" } :: Radial.RadialItem<string>,
					},
				})
				local modal, panel = world.find("Modal"), world.find("RadialPanel")
				world.engine.environment.poke(modal, "AbsoluteSize", world.engine.types.Vector2.new(920, 640))
				local button = world.find("iris")
				local corner = button:FindFirstChildWhichIsA("UICorner")
				expect((panel:GetAttribute("Presentation"))):toBe("radial")
				expect(button.Size.X.Scale):toBe(0)
				expect(button.Size.Y.Scale):toBe(0)
				expect(button.Size.X.Offset):toBe(button.Size.Y.Offset)
				expect(button.Size.X.Offset >= 44):toBe(true)
				expect(corner.CornerRadius.Scale):toBe(1)
				expect(corner.CornerRadius.Offset):toBe(0)
				expect(world.find("Sector-iris"):FindFirstChild("Paint").Visible):toBe(false)
				world.engine.environment.poke(modal, "AbsoluteSize", world.engine.types.Vector2.new(180, 180))
				expect((world.find("iris"))):toBe(button)
				expect((panel:GetAttribute("Presentation"))):toBe("list")
				expect(button.Size.X.Scale):toBe(1)
				expect(button.Size.X.Offset):toBe(-8)
				expect(button.Size.Y.Offset):toBe(44)
				expect((button:FindFirstChildWhichIsA("UIAspectRatioConstraint"))):toBe(nil)
				button.Activated:Fire()
				expect((selected:peek())):toBe("iris")
				world.engine.environment.poke(modal, "AbsoluteSize", world.engine.types.Vector2.new(920, 640))
				expect((world.find("iris"))):toBe(button)
				expect(button.Size.X.Offset):toBe(button.Size.Y.Offset)
				expect((button:FindFirstChildWhichIsA("UICorner"))):toBe(corner)
				world.stop()
			end,
		})
		it("presents on the modal layer over a dimmed page and a still tap outside the ring closes it", {
			id = "native_radial_controls::native radial interaction policies::presents on the modal layer over a dimmed page and a still tap outside the ring closes it",
			run = function()
				local world = setup({
					distribution = "compass" :: "compass",
					scrim = "dark" :: "dark",
					items = compass(function() end),
				})
				local modal = world.find("Modal")
				expect(modal.Parent):toBe(world.screen)
				expect(modal.ZIndex >= 100):toBe(true)
				expect((world.find("Scrim"):HasTag("facet-scrim"))):toBe(true)
				local near = pointer(world, 330, 250)
				world.find("RadialPanel").InputBegan:Fire(near)
				world.input.InputEnded:Fire(near)
				expect((world.opened:peek())):toBe(true)
				local slide = pointer(world, 630, 10)
				world.find("RadialPanel").InputBegan:Fire(slide)
				slide.Position = world.engine.types.Vector3.new(600, 40, 0)
				world.input.InputChanged:Fire(slide)
				world.input.InputEnded:Fire(slide)
				expect((world.opened:peek())):toBe(true)
				local outside = pointer(world, 630, 10)
				world.find("RadialPanel").InputBegan:Fire(outside)
				world.input.InputEnded:Fire(outside)
				expect((world.opened:peek())):toBe(false)
				world.stop()
			end,
		})
		it("opens centred on its measured launcher and pulls the ring inside the safe area", {
			id = "native_radial_controls::native radial interaction policies::opens centred on its measured launcher and pulls the ring inside the safe area",
			run = function()
				local world = setup({
					isPresented = Compose.cell(false),
					clearance = 60,
					ringWidth = 48,
					distribution = "compass" :: "compass",
					items = compass(function() end),
				})
				local V2 = world.engine.types.Vector2
				local launcher = world.find("Launcher")
				local function centre(x, y)
					world.engine.environment.poke(launcher, "AbsolutePosition", V2.new(x, y))
					world.engine.environment.poke(launcher, "AbsoluteSize", V2.new(40, 40))
					world.opened:set(true)
					local at = world.find("Center").Position
					world.opened:set(false)
					return at.X.Offset, at.Y.Offset
				end
				local x, y = centre(140, 200)
				expect(x):toBe(160)
				expect(y):toBe(220)
				x, y = centre(600, 440)
				expect(x):toBe(640 - 120)
				expect(y):toBe(480 - 128)
				world.stop()
			end,
		})
		it("sizes the default ring band from its measured captions, never from a painted label reading", {
			id = "native_radial_controls::native radial interaction policies::sizes the default ring band from its measured captions, never from a painted label reading",
			run = function()
				local items: { Item } = {}
				for index = 1, 4 do
					table.insert(
						items,
						action({ id = "item" .. index, label = "Item " .. index, onSelect = function() end })
					)
				end
				local world = setup({ items = items })
				local V2 = world.engine.types.Vector2
				local wide = 60
				for index = 1, 4 do
					world.engine.environment.poke(
						world.find("item" .. index):FindFirstChild("CaptionMeasure"),
						"TextBounds",
						V2.new(wide, 16)
					)
				end
				local expected = 40 + (wide + 2 * 12 + 2 * 8) / 2
				local function reach()
					return 240 - world.find("item1").Position.Y.Offset
				end
				expect(math.abs(reach() - expected) <= 1):toBeTrueWith(`reach {reach()} expected {expected}`)
				for round = 1, 3 do
					for _, node in world.screen:GetDescendants() do
						if (node:IsA("TextLabel") or node:IsA("TextButton")) and node.Name ~= "CaptionMeasure" then
							world.engine.environment.poke(node, "TextBounds", V2.new(40 * round, 10 * round))
						end
					end
					expect(math.abs(reach() - expected) <= 1):toBeTrueWith(`reach {reach()} expected {expected}`)
				end
				world.stop()
			end,
		})
		it(
			"scrim sets the ring's dim: clear by default as in 0.11, dark or the theme scrim when asked, and refuses other words",
			{
				id = "native_radial_controls::native radial interaction policies::scrim sets the ring's dim: clear by default as in 0.11, dark or the theme scrim when asked, and refuses other words",
				run = function()
					for _, case in
						{
							{ scrim = nil, base = false, ring = false },
							{ scrim = "dark", base = true, ring = true },
							{ scrim = "light", base = true, ring = false },
							{ scrim = "none", base = false, ring = false },
						} :: { { scrim: ("dark" | "light" | "none")?, base: boolean, ring: boolean } }
					do
						local world = setup({
							distribution = "compass" :: "compass",
							scrim = case.scrim,
							items = compass(function() end),
						})
						local scrim = world.find("Scrim")
						expect(`{case.scrim}:{scrim:HasTag("facet-scrim")}:{scrim:HasTag("facet-radial-scrim")}`):toBe(
							`{case.scrim}:{case.base}:{case.ring}`
						)
						expect(scrim.Visible):toBe(true)
						if case.scrim == "none" or case.scrim == nil then
							expect(scrim.BackgroundTransparency):toBe(1)
						end
						world.stop()
					end
					local ok, message = pcall(setup, { scrim = "heavy", items = compass(function() end) } :: any)
					expect(ok):toBe(false)
					expect(string.find(tostring(message), "scrim", 1, true) ~= nil):toBe(true)
				end,
			}
		)

		it("puts a small plate-less close in the hole over a full dark scrim and names no labelled wedge", {
			id = "native_radial_controls::native radial interaction policies::puts a small plate-less close in the hole over a full dark scrim and names no labelled wedge",
			run = function()
				for _, label in { false, "Leave the wheel" } :: { false | string } do
					local world = setup({
						distribution = "compass" :: "compass",
						scrim = "dark" :: "dark",
						centerLabel = if type(label) == "string" then label else nil,
						items = compass(function() end),
					})
					local scrim = world.find("Scrim")
					expect(scrim:HasTag("facet-scrim") and scrim:HasTag("facet-radial-scrim") and scrim.Visible):toBe(
						true
					)
					expect(scrim.Position.X.Offset < 0 and scrim.Position.Y.Offset < 0):toBe(true)
					expect(scrim.Size.X.Scale >= 1 and scrim.Size.X.Offset >= -2 * scrim.Position.X.Offset):toBe(true)
					expect(scrim.Size.Y.Scale >= 1 and scrim.Size.Y.Offset >= -2 * scrim.Position.Y.Offset):toBe(true)
					local centre = world.find("Center")
					local w: number, h: number = centre.Size.X.Offset, centre.Size.Y.Offset
					expect(w):toBe(h)
					expect(w):toBe(32)
					expect(centre.AutomaticSize):toBe(world.engine.types.Enum.AutomaticSize.None)
					expect((centre:HasTag("facet-appearance-utility"))):toBe(true)
					local hit = world.find("CenterHit")
					expect(hit.Size.X.Offset == 44 and hit.Size.Y.Offset == 44):toBe(true)
					expect(hit.Selectable):toBe(false)
					expect(hit.AnchorPoint):toBe(world.engine.types.Vector2.new(0.5, 0.5))
					expect(hit.Position):toBe(centre.Position)
					expect(centre.Position.X.Offset):toBe(320)
					local function inside(x: number, y: number)
						return (x - 320) ^ 2 + (y - 240) ^ 2 <= 40 * 40 + 0.5
					end
					for _, dx in { -w / 2, w / 2 } do
						for _, dy in { -h / 2, h / 2 } do
							expect((inside(centre.Position.X.Offset + dx * 0.71, centre.Position.Y.Offset + dy * 0.71))):toBe(
								true
							)
						end
					end
					expect(centre.Text):toBe("")
					expect(centre:FindFirstChild("LeadingIcon", true) ~= nil):toBe(true)
					expect((centre:GetAttribute("label"))):toBe(if label then label else "Close")
					local preview = world.find("SelectionPreview")
					world.engine.environment.fakeOn(world.input, "GetLastInputType", function()
						return world.engine.types.Enum.UserInputType.MouseMovement
					end)
					world.find("N").MouseEnter:Fire()
					expect(preview.Text):toBe("")
					world.stop()
				end
			end,
		})
		it("opens with nothing highlighted until the player points, steps or aims", {
			id = "native_radial_controls::native radial interaction policies::opens with nothing highlighted until the player points, steps or aims",
			run = function()
				local world = setup({ distribution = "compass" :: "compass", items = compass(function() end) })
				for _, node in world.screen:GetDescendants() do
					expect((node:HasTag("facet-radial-candidate"))):toBe(false)
					if node:IsA("TextButton") and node.Name ~= "Center" then
						expect(node.Parent.Name .. ":" .. tostring(node.Selected == true)):toBe(
							node.Parent.Name .. ":false"
						)
					end
				end
				world.find("E").MouseEnter:Fire()
				expect((world.find("Sector-E"):FindFirstChild("Sector", true):HasTag("facet-radial-candidate"))):toBe(
					true
				)
				world.stop()
			end,
		})
		it("a corner ring keeps Close on its corner and names the item outside the ring", {
			id = "native_radial_controls::native radial interaction policies::a corner ring keeps Close on its corner and names the item outside the ring",
			run = function()
				local items: { Item } = {}
				for _, id in { "look", "pack", "wave" } do
					table.insert(items, action({ id = id, label = id, icon = "flag", onSelect = function() end }))
				end
				local world = setup({
					isPresented = Compose.cell(false),
					preset = "bottom-left" :: "bottom-left",
					center = "empty" :: "empty",
					appearance = "buttons" :: "buttons",
					items = items,
				})
				local V2 = world.engine.types.Vector2
				local launcher = world.find("Launcher")
				world.engine.environment.poke(launcher, "AbsolutePosition", V2.new(20, 420))
				world.engine.environment.poke(launcher, "AbsoluteSize", V2.new(40, 40))
				world.opened:set(true)
				expect((world.find("Sector-$navigation"))):toBeNil()
				local centre = world.find("Center")
				expect(centre.Position.X.Offset):toBe(40)
				expect(centre.Position.Y.Offset):toBe(440)
				expect(centre.Visible):toBe(true)
				world.engine.environment.fakeOn(world.input, "GetLastInputType", function()
					return world.engine.types.Enum.UserInputType.MouseMovement
				end)
				world.find("pack").MouseEnter:Fire()
				local preview = world.find("SelectionPreview")
				expect(preview.Text):toBe("pack")
				local reach = 0
				for _, id in { "look", "pack", "wave" } do
					local at = world.find(id).Position
					reach = math.max(reach, math.sqrt((at.X.Offset - 40) ^ 2 + (at.Y.Offset - 440) ^ 2))
				end
				expect(preview.Position.X.Offset > 40 + reach * 0.7):toBe(true)
				expect(preview.Position.Y.Offset < 440 - reach * 0.7):toBe(true)
				expect(preview.AnchorPoint):toBe(V2.new(0, 1))
				centre.Activated:Fire()
				expect((world.opened:peek())):toBe(false)
				world.stop()
			end,
		})
		it("blooms from its launcher on a measured screen instead of travelling in from a default one", {
			id = "native_radial_controls::native radial interaction policies::blooms from its launcher on a measured screen instead of travelling in from a default one",
			run = function()
				local world = setup({
					isPresented = Compose.cell(false),
					distribution = "compass" :: "compass",
					items = compass(function() end),
				}, true)
				local V2 = world.engine.types.Vector2
				world.engine.environment.poke(world.screen, "AbsoluteSize", V2.new(1600, 900))
				local launcher = world.find("Launcher")
				world.engine.environment.poke(launcher, "AbsolutePosition", V2.new(1380, 680))
				world.engine.environment.poke(launcher, "AbsoluteSize", V2.new(40, 40))
				world.opened:set(true)
				local function offset(name)
					local at = world.find(name).Position
					return at.X.Offset - 1400, at.Y.Offset - 700
				end
				local _, early = offset("N")
				expect((select(1, offset("Center")))):toBe(0)
				world.step(0.4)
				expect((select(1, offset("Center")))):toBe(0)
				local _, settled = offset("N")
				expect(math.abs(early) < math.abs(settled) * 0.5):toBe(true)
				world.stop()
			end,
		})
		it("takes ringWidth as a theme width or pixels and grows a ring until each label fits", {
			id = "native_radial_controls::native radial interaction policies::takes ringWidth as a theme width or pixels and grows a ring until each label fits",
			run = function()
				local function band(width: "narrow" | "regular" | "wide" | number, label: string)
					local world = setup({
						ringWidth = width,
						items = {
							{ id = "a", label = label, onSelect = function() end } :: Radial.RadialItem<string>,
							{ id = "b", label = "B", onSelect = function() end } :: Radial.RadialItem<string>,
							{ id = "c", label = "C", onSelect = function() end } :: Radial.RadialItem<string>,
						},
					})
					local reach = 240 - world.find("a").Position.Y.Offset
					world.stop()
					return reach
				end
				expect((band("wide", "A"))):toBe(band(88, "A"))
				expect((band("narrow", "A"))):toBe(band(48, "A"))
				expect(band("wide", "A") > band("narrow", "A")):toBe(true)
				expect(band(48, "Wear the lantern") > band(48, "A")):toBe(true)
				local ok, message = pcall(band, "huge" :: any, "A")
				expect(ok):toBe(false)
				expect(string.find(tostring(message), "ringWidth", 1, true) ~= nil):toBe(true)
			end,
		})
		it("shows either a glyph or a word on a ring item, never both over each other", {
			id = "native_radial_controls::native radial interaction policies::shows either a glyph or a word on a ring item, never both over each other",
			run = function()
				local world = setup({
					appearance = "buttons" :: "buttons",
					items = {
						{ id = "map", label = "Map", compactLabel = { icon = "flag" }, onSelect = function() end } :: Radial.RadialItem<string>,
						{ id = "wave", label = "Wave", icon = "flag", onSelect = function() end } :: Radial.RadialItem<string>,
					},
				})
				local function shown(button)
					local words: string = button.Text
					for _, node in button:GetDescendants() do
						if node:IsA("TextLabel") and node.Visible and node.TextTransparency < 1 then
							words ..= node.Text
						end
					end
					return words .. "|" .. tostring(button:FindFirstChild("LeadingIcon", true).Visible)
				end
				expect((shown(world.find("map")))):toBe("|true")
				expect((shown(world.find("wave")))):toBe("|true")
				world.stop()
			end,
		})
		it("puts the launcher over the object it is anchored to", {
			id = "native_radial_controls::native radial interaction policies::puts the launcher over the object it is anchored to",
			run = function()
				local made: Frame? = nil
				local world = setup(function(engine)
					local frame: Frame = engine.new("Frame")
					made = frame
					return {
						isPresented = Compose.cell(false),
						anchor = frame,
						distribution = "compass" :: "compass",
						items = compass(function() end),
					}
				end)
				local anchor = assert(made)
				local V2 = world.engine.types.Vector2
				world.engine.environment.poke(VerifyRoblox.assertInstance(anchor), "AbsolutePosition", V2.new(300, 200))
				world.engine.environment.poke(VerifyRoblox.assertInstance(anchor), "AbsoluteSize", V2.new(80, 120))
				world.engine.environment.poke(world.find("RadialMenu"), "AbsolutePosition", V2.new(20, 400))
				local launcher = world.find("Launcher")
				expect(launcher.AnchorPoint):toBe(V2.new(0.5, 0.5))
				expect(launcher.Position.X.Offset):toBe(320)
				expect(launcher.Position.Y.Offset):toBe(-140)
				world.stop()
			end,
		})
	end)
	describe("RadialMenu navigation placement (restored from 0.11)", function()
		local function nested(): { Radial.RadialItem<string> }
			return {
				action({
					id = "gear",
					label = "Gear",
					children = { action({ id = "tool", label = "Tool", onSelect = function() end }) },
				}),
				action({ id = "wave", label = "Wave", onSelect = function() end }),
			}
		end
		local function visibleCenter(world: World): any
			local centre = world.find("Center")
			return if centre and centre.Visible then centre else nil
		end

		it("a back centre uses only the centre control, which goes back and closes at the root", {
			id = "native_radial_controls::RadialMenu navigation placement (restored from 0.11)::a back centre uses only the centre control, which goes back and closes at the root",
			run = function()
				local world = setup({ items = nested() })
				expect((world.find("$navigation"))):toBeNil()
				local centre = visibleCenter(world)
				expect((centre:GetAttribute("label"))):toBe("Close")
				world.find("gear").Activated:Fire()
				expect((visibleCenter(world):GetAttribute("label"))):toBe("Back")
				visibleCenter(world).Activated:Fire()
				expect(world.find("wave") ~= nil):toBe(true)
				expect((world.opened:peek())):toBe(true)
				visibleCenter(world).Activated:Fire()
				expect((world.opened:peek())):toBe(false)
				world.stop()
			end,
		})

		it("a full compass with an empty centre uses the external control at the centre", {
			id = "native_radial_controls::RadialMenu navigation placement (restored from 0.11)::a full compass with an empty centre uses the external control at the centre",
			run = function()
				local items: { Item } = {}
				local slots: { Radial.CompassSlot } = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
				for _, slot in slots do
					table.insert(items, action({ id = slot, slot = slot, label = slot, onSelect = function() end }))
				end
				local world =
					setup({ center = "empty" :: "empty", distribution = "compass" :: "compass", items = items })
				expect((world.find("$navigation"))):toBeNil()
				local centre = visibleCenter(world)
				expect(centre ~= nil):toBe(true)
				expect(centre.Position.X.Offset):toBe(320)
				expect((centre:GetAttribute("label"))):toBe("Close")
				centre.Activated:Fire()
				expect((world.opened:peek())):toBe(false)
				world.stop()
			end,
		})

		it("a corner ring puts Back/Close on the corner whatever the centre, and never on the ring", {
			id = "native_radial_controls::RadialMenu navigation placement (restored from 0.11)::a corner ring puts Back/Close on the corner whatever the centre, and never on the ring",
			run = function()
				for _, center in { "back", "root", "close", "empty", "content" } do
					local world = setup({
						isPresented = Compose.cell(false),
						preset = "bottom-left" :: "bottom-left",
						center = center :: "empty" | "content" | "root" | "close",
						centerLabel = "Home base",
						items = nested(),
					})
					local V2 = world.engine.types.Vector2
					local launcher = world.find("Launcher")
					world.engine.environment.poke(launcher, "AbsolutePosition", V2.new(20, 420))
					world.engine.environment.poke(launcher, "AbsoluteSize", V2.new(40, 40))
					world.opened:set(true)
					expect((world.find("$navigation"))):toBeNil()
					local centre = visibleCenter(world)
					expect(`{center}: {centre.Position.X.Offset},{centre.Position.Y.Offset}`):toBe(`{center}: 40,440`)
					expect(`{center}: {centre:GetAttribute("label")}`):toBe(`{center}: Close`)
					world.find("gear").Activated:Fire()
					expect(`{center}: {visibleCenter(world):GetAttribute("label")}`):toBe(`{center}: Back`)
					visibleCenter(world).Activated:Fire()
					expect(`{center}: {world.find("wave") ~= nil and world.opened:peek()}`):toBe(`{center}: true`)
					visibleCenter(world).Activated:Fire()
					expect(`{center}: {world.opened:peek()}`):toBe(`{center}: false`)
					world.stop()
				end
			end,
		})

		it("the list fallback has one round Back/Close at the top right for every centre policy", {
			id = "native_radial_controls::RadialMenu navigation placement (restored from 0.11)::the list fallback has one round Back/Close at the top right for every centre policy",
			run = function()
				for _, center in { "empty", "back", "root", "close", "content" } do
					local world = setup({ center = center :: "empty" | "content" | "root" | "close", items = nested() })
					world.engine.environment.poke(
						world.find("Modal"),
						"AbsoluteSize",
						world.engine.types.Vector2.new(180, 180)
					)
					expect((world.find("RadialPanel"):GetAttribute("Presentation"))):toBe("list")
					expect(`{center}: {world.find("$navigation") == nil}`):toBe(`{center}: true`)
					local centre = visibleCenter(world)
					expect(`{center}: {centre ~= nil}`):toBe(`{center}: true`)
					expect(centre.Position.X.Scale):toBe(0.5)
					expect(centre.Position.X.Offset + centre.Size.X.Offset * (1 - centre.AnchorPoint.X)):toBe(
						world.find("RadialPanel").Size.X.Offset / 2
					)
					expect(centre.Position.Y.Scale):toBe(0)
					expect(centre.Size.X.Offset):toBe(centre.Size.Y.Offset)
					expect(`{center}: {centre:GetAttribute("label")}`):toBe(`{center}: Close`)
					centre.Activated:Fire()
					expect(`{center}: {world.opened:peek()}`):toBe(`{center}: false`)
					world.stop()
				end
			end,
		})
	end)

	describe("RadialMenu centre and corner controls (restored from 0.11)", function()
		local themes = require("../src/ui/themes")(Compose)
		local function nested(): { Radial.RadialItem<string> }
			return {
				action({
					id = "gear",
					label = "Gear",
					children = { action({ id = "tool", label = "Tool", onSelect = function() end }) },
				}),
				action({ id = "wave", label = "Wave", onSelect = function() end }),
			}
		end
		it("the 44 px hit area around the 32 px centre control does what the control does", {
			id = "native_radial_controls::RadialMenu centre and corner controls (restored from 0.11)::the 44 px hit area around the 32 px centre control does what the control does",
			run = function()
				local world = setup({ items = nested() })
				world.find("gear").Activated:Fire()
				world.find("CenterHit").Activated:Fire()
				expect(world.find("wave") ~= nil and world.opened:peek()):toBe(true)
				world.find("CenterHit").Activated:Fire()
				expect((world.opened:peek())):toBe(false)
				world.stop()
			end,
		})

		it("the ring's full-screen panel takes no panel padding, so a themed inset cannot shift the ring", {
			id = "native_radial_controls::RadialMenu centre and corner controls (restored from 0.11)::the ring's full-screen panel takes no panel padding, so a themed inset cannot shift the ring",
			run = function()
				local world = setup({ items = nested() })
				world.engine.environment.poke(
					world.find("Modal"),
					"AbsoluteSize",
					world.engine.types.Vector2.new(800, 600)
				)
				local panel = world.find("RadialPanel")
				expect((panel:GetAttribute("Presentation"))):toBe("radial")
				expect((panel:HasTag("facet-panel"))):toBe(false)
				world.stop()
			end,
		})
		it("the list fallback heads its opaque panel with the path, clear of the page below", {
			id = "native_radial_controls::RadialMenu centre and corner controls (restored from 0.11)::the list fallback heads its opaque panel with the path, clear of the page below",
			run = function()
				local world = setup({ items = nested() })
				world.engine.environment.poke(
					world.find("Modal"),
					"AbsoluteSize",
					world.engine.types.Vector2.new(180, 180)
				)
				local preview = world.find("SelectionPreview")
				expect(preview.AnchorPoint):toBe(world.engine.types.Vector2.zero)
				expect(preview.Position.Y.Scale):toBe(0)
				expect(preview.TextXAlignment):toBe(world.engine.types.Enum.TextXAlignment.Left)
				expect((preview:IsDescendantOf(world.find("RadialPanel")))):toBe(false)
				local panel = world.find("RadialPanel")
				expect(preview.Position.Y.Offset <= panel.Position.Y.Offset):toBe(true)
				expect(panel.BackgroundTransparency):toBe(0)
				expect((panel:HasTag("facet-panel"))):toBe(true)
				world.stop()
			end,
		})
		it("closing a corner ring hands the selection back to its launcher", {
			id = "native_radial_controls::RadialMenu centre and corner controls (restored from 0.11)::closing a corner ring hands the selection back to its launcher",
			run = function()
				local world = setup({
					isPresented = Compose.cell(false),
					preset = "bottom-left" :: "bottom-left",
					items = nested(),
				}, true)
				local launcher = world.find("Launcher")
				world.gui.SelectedObject = launcher

				launcher:GetPropertyChangedSignal("Visible"):Connect(function()
					if not launcher.Visible and world.gui.SelectedObject == launcher then
						world.gui.SelectedObject = nil
					end
				end)
				world.opened:set(true)
				expect(launcher.Visible):toBe(false)
				expect(world.gui.SelectedObject ~= launcher):toBe(true)
				world.opened:set(false)
				world.step(0.5)
				expect((world.find("Center"))):toBeNil()
				expect(world.gui.SelectedObject):toBe(launcher)
				world.stop()
			end,
		})

		it("a corner control grows out of the launcher and back into it, crossfading the glyphs", {
			id = "native_radial_controls::RadialMenu centre and corner controls (restored from 0.11)::a corner control grows out of the launcher and back into it, crossfading the glyphs",
			run = function()
				local world = setup({
					isPresented = Compose.cell(false),
					preset = "bottom-left" :: "bottom-left",
					items = nested(),
				}, true)
				local V2 = world.engine.types.Vector2
				world.engine.environment.poke(world.screen, "AbsoluteSize", V2.new(640, 480))
				local launcher = world.find("Launcher")
				world.engine.environment.poke(launcher, "AbsolutePosition", V2.new(20, 420))
				world.engine.environment.poke(launcher, "AbsoluteSize", V2.new(40, 40))
				world.opened:set(true)
				local function state(): (any, any, any, any)
					local centre = world.find("Center")
					if not centre then
						return nil, nil, nil, nil
					end
					local back = centre:FindFirstChild("LeadingIcon", true)
					local own = centre:FindFirstChild("LauncherIcon", true)
					return centre.Size.X.Offset,
						centre.Size.Y.Offset,
						1 - back.ImageTransparency,
						1 - own.ImageTransparency
				end
				local w, h, back, own = state()
				expect(w == 40 and h == 40):toBe(true)
				expect(launcher.Visible):toBe(false)
				expect(back == 0 and own == 1):toBe(true)
				local glyph = world.find("Center"):FindFirstChild("LauncherIcon", true)
				expect(glyph.Image):toBe(themes.resolveIcon({} :: any, "more"))
				world.step(0.1)
				w, h, back, own = state()
				expect(w > 32 and w < 40 and w == h):toBe(true)
				expect(math.abs(back + own - 1) < 0.001 and back > 0 and own > 0):toBe(true)
				world.step(0.3)
				w, h, back, own = state()
				expect(w == 32 and back == 1 and own == 0):toBe(true)
				world.opened:set(false)
				local frames, grew = 0, false
				for _ = 1, 30 do
					world.step(1 / 60)
					local size, _, b, o = state()
					if size == nil then
						break
					end
					frames += 1
					grew = grew or size > 32
					expect(math.abs(b + o - 1) < 0.001):toBe(true)
				end
				expect(frames > 2 and grew):toBe(true)
				expect((world.find("Center"))):toBeNil()
				expect(launcher.Visible):toBe(true)
				world.stop()
			end,
		})
		it("a gamepad replacing a level lands on the new level's first item", {
			id = "native_radial_controls::RadialMenu centre and corner controls (restored from 0.11)::a gamepad replacing a level lands on the new level's first item",
			run = function()
				local world = setup({ items = nested() })
				world.gui.SelectedObject = world.find("gear")
				world.find("gear").Activated:Fire()
				expect(world.gui.SelectedObject):toBe(world.find("tool"))
				world.stop()
			end,
		})
		it("names an icon item only while a finger holds it, never on a tap or a level change", {
			id = "native_radial_controls::RadialMenu centre and corner controls (restored from 0.11)::names an icon item only while a finger holds it, never on a tap or a level change",
			run = function()
				local function leaf(id: string, label: string): any
					return {
						id = id,
						slot = "N" :: Radial.CompassSlot,
						label = label,
						icon = "flag",
						labelStyle = "icon" :: "icon",
						onSelect = function() end,
					}
				end
				local world = setup({
					distribution = "compass" :: "compass",
					completion = "stay" :: "stay",
					items = {
						leaf("N", "Lantern"),
						{
							id = "E",
							slot = "E" :: Radial.CompassSlot,
							label = "Tools",
							icon = "menu",
							labelStyle = "icon" :: "icon",
							children = { leaf("stow", "Stow") },
						} :: Radial.RadialItem<string>,
					},
				})
				local preview, panel = world.find("SelectionPreview"), world.find("RadialPanel")
				local north = world.find("N")
				local x, y = north.Position.X.Offset, north.Position.Y.Offset
				local tap = pointer(world, x, y)
				panel.InputBegan:Fire(tap)
				world.input.InputEnded:Fire(tap)
				expect(preview.Text):toBe("")
				local hold = pointer(world, x, y)
				panel.InputBegan:Fire(hold)
				expect(preview.Text):toBe("")
				world.step(0.5)
				expect(preview.Text):toBe("Lantern")
				world.input.InputEnded:Fire(hold)
				expect(preview.Text):toBe("")
				world.find("E").Activated:Fire()
				expect(world.find("stow") ~= nil):toBe(true)
				expect(preview.Text):toBe("")
				world.find("stow").MouseEnter:Fire()
				expect(preview.Text):toBe("")
				world.stop()
			end,
		})
		it("a submenu's ring unfolds along the ring from the chosen item, not out of the centre", {
			id = "native_radial_controls::RadialMenu centre and corner controls (restored from 0.11)::a submenu's ring unfolds along the ring from the chosen item, not out of the centre",
			run = function()
				local function leaf(id: string): any
					return { id = id, label = id, onSelect = function() end }
				end
				local world = setup({
					distribution = "compass" :: "compass",
					items = {
						{
							id = "gear",
							slot = "N" :: Radial.CompassSlot,
							label = "Gear",
							children = { leaf("a"), leaf("b"), leaf("c"), leaf("d") },
						} :: Radial.RadialItem<string>,
						{ id = "E", slot = "E" :: Radial.CompassSlot, label = "E", onSelect = function() end } :: Radial.RadialItem<string>,
					},
				}, true)
				world.step(0.5)
				world.find("gear").Activated:Fire()
				world.step(1 / 60)
				local function at(id: string): any
					local node = world.find(id)
					return world.engine.types.Vector2.new(node.Position.X.Offset, node.Position.Y.Offset)
				end
				local early = at("c")
				world.step(0.5)
				local final = { a = at("a"), b = at("b"), c = at("c"), d = at("d") }
				local centre = (final.a + final.b + final.c + final.d) / 4
				local ring = (final.c - centre).Magnitude
				local offset = early - centre
				expect(offset.Magnitude > 0.9 * ring):toBe(true)
				expect(offset.Y < 0):toBe(true)
				expect((final.c - centre).Y > 0):toBe(true)
				world.stop()
			end,
		})
		it("Back folds the submenu into its item and re-opens the parent ring around it", {
			id = "native_radial_controls::RadialMenu centre and corner controls (restored from 0.11)::Back folds the submenu into its item and re-opens the parent ring around it",
			run = function()
				local function leaf(id: string): any
					return { id = id, label = id, onSelect = function() end }
				end
				local function ring(): any
					return setup({
						distribution = "compass" :: "compass",
						items = {
							{
								id = "gear",
								slot = "N" :: Radial.CompassSlot,
								label = "Gear",
								children = { leaf("a"), leaf("b"), leaf("c"), leaf("d") },
							} :: Radial.RadialItem<string>,
							{ id = "E", slot = "E" :: Radial.CompassSlot, label = "E", onSelect = function() end } :: Radial.RadialItem<string>,
						},
					}, true)
				end
				local world = ring()
				local function at(id: string, other: any?): any
					local node = (other or world).find(id)
					return world.engine.types.Vector2.new(node.Position.X.Offset, node.Position.Y.Offset)
				end
				local function reopen(target: any): any
					target.opened:set(false)
					target.step(0.5)
					target.opened:set(true)
					target.step(1 / 60)
					return at("E", target)
				end
				world.step(0.5)
				local gear, restE = at("gear"), at("E")
				world.find("gear").Activated:Fire()
				world.step(0.5)
				local restC = at("c")
				local nav = world.find("$navigation")
				local centre = world.find("Center")
				assert(nav or centre).Activated:Fire()
				world.step(1 / 60)
				world.step(1 / 60)
				local child = world.find("c")
				expect(child ~= nil):toBe(true)
				expect((at("c") - gear).Magnitude < (restC - gear).Magnitude):toBe(true)
				expect((at("E") - gear).Magnitude < (restE - gear).Magnitude):toBe(true)
				world.step(0.5)
				expect((at("E") - restE).Magnitude < 0.5):toBe(true)
				expect((world.find("c"))):toBeNil()
				local plain = ring()
				plain.step(0.5)
				expect((reopen(world) - reopen(plain)).Magnitude < 0.5):toBe(true)
				plain.stop()
				world.stop()
			end,
		})
		it("Back re-opens the parent around the item's current place after the ring re-lays out", {
			id = "native_radial_controls::RadialMenu centre and corner controls (restored from 0.11)::Back re-opens the parent around the item's current place after the ring re-lays out",
			run = function()
				local function leaf(id: string): any
					return { id = id, label = id, onSelect = function() end }
				end
				local gear = { id = "gear", label = "Gear", children = { leaf("x"), leaf("y") } }
				local items = Compose.cell({ leaf("a"), gear })
				local world = setup({ distribution = "even" :: "even", items = items }, true)
				local function at(id: string): any
					local node = world.find(id)
					return world.engine.types.Vector2.new(node.Position.X.Offset, node.Position.Y.Offset)
				end
				world.step(0.5)
				local before = at("gear")
				world.find("gear").Activated:Fire()
				world.step(0.5)
				items:set({ leaf("a"), gear, leaf("c"), leaf("d") })
				world.step(0.2)
				local nav = world.find("$navigation")
				local centre = world.find("Center")
				assert(nav or centre).Activated:Fire()
				world.step(1 / 60)
				local early = at("a")
				world.step(0.5)
				local after = at("gear")
				expect((after - before).Magnitude > 20):toBe(true)
				expect((early - after).Magnitude < (early - before).Magnitude):toBe(true)
				world.stop()
			end,
		})
		it("a long press names an item without acting; the release does nothing and a second tap acts", {
			id = "native_radial_controls::RadialMenu centre and corner controls (restored from 0.11)::a long press names an item without acting; the release does nothing and a second tap acts",
			run = function()
				local picked = 0
				local world = setup({
					distribution = "compass" :: "compass",
					completion = "stay" :: "stay",
					items = {
						{
							id = "N",
							slot = "N" :: Radial.CompassSlot,
							label = "Lantern",
							icon = "flag",
							labelStyle = "icon" :: "icon",
							onSelect = function()
								picked += 1
							end,
						} :: Radial.RadialItem<string>,
					},
				})
				local preview, panel, north = world.find("SelectionPreview"), world.find("RadialPanel"), world.find("N")
				local x, y = north.Position.X.Offset, north.Position.Y.Offset
				local hold = pointer(world, x, y)
				north.InputBegan:Fire(hold)
				world.step(0.5)
				expect(preview.Text):toBe("Lantern")
				hold.UserInputState = world.engine.types.Enum.UserInputState.End
				world.input.InputEnded:Fire(hold)
				north.Activated:Fire(hold)
				expect(picked):toBe(0)
				local tap = pointer(world, x, y)
				north.InputBegan:Fire(tap)
				tap.UserInputState = world.engine.types.Enum.UserInputState.End
				world.input.InputEnded:Fire(tap)
				north.Activated:Fire(tap)
				expect(picked):toBe(1)
				local slide = pointer(world, x, y)
				panel.InputBegan:Fire(slide)
				slide.Position = world.engine.types.Vector3.new(x + 30, y, 0)
				world.input.InputChanged:Fire(slide)
				slide.Position = world.engine.types.Vector3.new(x, y, 0)
				world.input.InputChanged:Fire(slide)
				world.step(0.5)
				slide.UserInputState = world.engine.types.Enum.UserInputState.End
				world.input.InputEnded:Fire(slide)
				expect(picked):toBe(2)
				world.stop()
			end,
		})
		it("a hold that then slides to another item picks the item under the finger on release", {
			id = "native_radial_controls::RadialMenu centre and corner controls (restored from 0.11)::a hold that then slides to another item picks the item under the finger on release",
			run = function()
				local picks = {}
				local function item(id: string): any
					return {
						id = id,
						slot = id :: Radial.CompassSlot,
						label = id,
						icon = "flag",
						labelStyle = "icon" :: "icon",
						onSelect = function()
							table.insert(picks, id)
						end,
					}
				end
				local world = setup({
					distribution = "compass" :: "compass",
					completion = "stay" :: "stay",
					items = { item("N"), item("E") },
				})
				local panel, north, east = world.find("RadialPanel"), world.find("N"), world.find("E")
				local hold = pointer(world, north.Position.X.Offset, north.Position.Y.Offset)
				panel.InputBegan:Fire(hold)
				world.step(0.5)
				hold.Position = world.engine.types.Vector3.new(east.Position.X.Offset, east.Position.Y.Offset, 0)
				world.input.InputChanged:Fire(hold)
				hold.UserInputState = world.engine.types.Enum.UserInputState.End
				world.input.InputEnded:Fire(hold)
				expect((table.concat(picks, ","))):toBe("E")
				world.stop()
			end,
		})
		it("keeps a held item's name on the screen beside a ring near the edge of a phone", {
			id = "native_radial_controls::RadialMenu centre and corner controls (restored from 0.11)::keeps a held item's name on the screen beside a ring near the edge of a phone",
			run = function()
				local world = setup({
					distribution = "compass" :: "compass",
					completion = "stay" :: "stay",
					items = {
						{
							id = "E",
							slot = "E" :: Radial.CompassSlot,
							label = "Lantern",
							icon = "flag",
							labelStyle = "icon" :: "icon",
							onSelect = function() end,
						} :: Radial.RadialItem<string>,
					},
				})
				world.engine.environment.poke(
					world.find("Modal"),
					"AbsoluteSize",
					world.engine.types.Vector2.new(390, 760)
				)
				local preview, east = world.find("SelectionPreview"), world.find("E")
				local hold = pointer(world, east.Position.X.Offset, east.Position.Y.Offset)
				world.find("RadialPanel").InputBegan:Fire(hold)
				world.step(0.5)
				expect(preview.Text):toBe("Lantern")
				local width = world.find("SelectionPlate").Size.X.Offset
				local left = preview.Position.X.Offset - preview.AnchorPoint.X * width
				expect(left >= 8 and left + width <= 382):toBe(true)
				world.input.InputEnded:Fire(hold)
				world.stop()
			end,
		})
		it("keeps a nested level on the ring by replacing its parent before it falls back to a list", {
			id = "native_radial_controls::RadialMenu centre and corner controls (restored from 0.11)::keeps a nested level on the ring by replacing its parent before it falls back to a list",
			run = function()
				local function leaf(id: string): any
					return {
						id = id,
						label = id,
						icon = "flag",
						labelStyle = "icon" :: "icon",
						onSelect = function() end,
					}
				end
				local world = setup({
					items = {
						leaf("a"),
						leaf("b"),
						leaf("c"),
						{
							id = "gear",
							label = "Gear",
							icon = "menu",
							labelStyle = "icon" :: "icon",
							children = {
								{
									id = "tools",
									label = "Tools",
									navigation = "expand" :: "expand",
									expansion = "fan" :: "fan",
									children = { leaf("x"), leaf("y"), leaf("z") },
								} :: Radial.RadialItem<string>,
								{ id = "wear", label = "Wear", children = { leaf("w") } } :: Radial.RadialItem<string>,
							},
						} :: Radial.RadialItem<string>,
					},
				})
				world.engine.environment.poke(
					world.find("Modal"),
					"AbsoluteSize",
					world.engine.types.Vector2.new(360, 240)
				)
				world.find("gear").Activated:Fire()
				world.find("tools").Activated:Fire()
				expect((world.find("RadialPanel"):GetAttribute("Presentation"))):toBe("radial")
				expect(world.find("x") ~= nil):toBe(true)
				world.stop()
			end,
		})
		it("fits an anchored ring inside the page space that holds its anchor, down to the touch floor", {
			id = "native_radial_controls::RadialMenu centre and corner controls (restored from 0.11)::fits an anchored ring inside the page space that holds its anchor, down to the touch floor",
			run = function()
				local function leaf(id: string): Item
					return action({
						id = id,
						label = id,
						icon = "flag",
						labelStyle = "icon",
						onSelect = function() end,
					})
				end
				local madeScene: Frame?, madeAnchor: Frame? = nil, nil
				local world = setup(function(engine)
					local scene: Frame, anchor: Frame = engine.new("Frame"), engine.new("Frame")
					anchor.Parent = scene
					madeScene, madeAnchor = scene, anchor
					return {
						anchor = anchor,
						clearance = 82,
						ringWidth = "narrow" :: "narrow",
						center = "empty" :: "empty",
						contentFit = "none" :: "none",
						items = {
							leaf("wave"),
							leaf("look"),
							action({
								id = "gear",
								label = "Gear",
								icon = "menu",
								labelStyle = "icon",
								navigation = "replace",
								children = {
									action({
										id = "tools",
										label = "Tools",
										icon = "edit",
										labelStyle = "icon",
										navigation = "expand",
										expansion = "fan",
										children = { leaf("x"), leaf("y"), leaf("z") },
									}),
									leaf("wear"),
								},
							}),
						},
					}
				end)
				local scene, anchor = assert(madeScene), assert(madeAnchor)
				local V2 = world.engine.types.Vector2
				world.engine.environment.poke(world.find("Modal"), "AbsoluteSize", V2.new(390, 760))
				world.engine.environment.poke(VerifyRoblox.assertInstance(scene), "AbsolutePosition", V2.new(16, 200))
				world.engine.environment.poke(VerifyRoblox.assertInstance(scene), "AbsoluteSize", V2.new(358, 260))
				world.engine.environment.poke(VerifyRoblox.assertInstance(anchor), "AbsolutePosition", V2.new(157, 275))
				world.engine.environment.poke(VerifyRoblox.assertInstance(anchor), "AbsoluteSize", V2.new(76, 110))
				world.find("gear").Activated:Fire()
				world.find("tools").Activated:Fire()
				expect((world.find("RadialPanel"):GetAttribute("Presentation"))):toBe("radial")
				local painted = 0
				for _, node in world.screen:GetDescendants() do
					if node.Name == "Paint" and node.Visible and node.Parent.Parent.Interactable then
						painted += 1
						local x, y = node.Position.X.Offset, node.Position.Y.Offset
						expect(x >= 16 and x + node.Size.X.Offset <= 374):toBe(true)
						expect(y >= 200 and y + node.Size.Y.Offset <= 460):toBe(true)
					end
				end
				expect(painted):toBe(4)
				world.stop()
			end,
		})
		it("shows an item's icon instead of a word that is wider than its fitted slot", {
			id = "native_radial_controls::RadialMenu centre and corner controls (restored from 0.11)::shows an item's icon instead of a word that is wider than its fitted slot",
			run = function()
				local world = setup({
					items = {
						{
							id = "lantern",
							label = "Lantern",
							compactLabel = { icon = "increment" },
							onSelect = function() end,
						} :: Radial.RadialItem<string>,
						{ id = "stow", label = "Stow", icon = "flag", onSelect = function() end } :: Radial.RadialItem<string>,
						{ id = "go", label = "Go", onSelect = function() end } :: Radial.RadialItem<string>,
					},
				})
				local V2 = world.engine.types.Vector2
				world.engine.environment.poke(world.find("Modal"), "AbsoluteSize", V2.new(390, 760))
				local function title(id: string): any
					local button = world.find(id)
					return button:FindFirstChild("Title", true) or button
				end
				for _, id in { "lantern", "stow", "go" } do
					world.engine.environment.poke(title(id), "TextBounds", V2.new(400, 16))
				end
				expect(title("lantern").Text):toBe("")
				expect(world.find("lantern"):FindFirstChild("LeadingIcon", true).Visible):toBe(true)
				expect(title("stow").Text):toBe("")
				expect(title("go").Text):toBe("Go")
				world.stop()
			end,
		})
	end)

	describe("touch radial label placement", function()
		it("follows a captured touch outside the wedge, wraps its name in tooltip paint and clears on cancel", {
			id = "native_radial_controls::touch radial label placement::follows a captured touch outside the wedge, wraps its name in tooltip paint and clears on cancel",
			run = function()
				local world = setup({
					gestureSelection = "direction" :: "direction",
					distribution = "compass" :: "compass",
					items = {
						{
							id = "S",
							slot = "S" :: Radial.CompassSlot,
							label = "Workshop",
							description = "Restore power",
							icon = "settings",
							labelStyle = "icon" :: "icon",
						} :: Radial.RadialItem<string>,
					},
				})
				local V2, V3, E = world.engine.types.Vector2, world.engine.types.Vector3, world.engine.types.Enum
				local modal = world.find("Modal")
				world.engine.environment.poke(modal, "AbsoluteSize", V2.new(390, 760))
				world.engine.environment.poke(modal, "AbsolutePosition", V2.new(50, 80))
				local item, preview, plate =
					world.find("S"), world.find("SelectionPreview"), world.find("SelectionPlate")
				expect(plate.Visible):toBe(false)
				local held = pointer(world, 50 + item.Position.X.Offset, 80 + item.Position.Y.Offset)
				world.find("RadialPanel").InputBegan:Fire(held)
				world.step(0.5)
				world.engine.environment.poke(preview, "AbsoluteSize", V2.new(236, 60))
				expect(preview.Text):toBe("Workshop · Restore power")
				expect(plate:HasTag("facet-tooltip") and plate.Visible):toBe(true)
				expect(preview.TextWrapped):toBe(true)
				expect(plate.Size):toBe(world.engine.types.UDim2.fromOffset(236, 60))
				expect(preview.AutomaticSize):toBe(E.AutomaticSize.XY)
				for _, y in { 680, 720 } do
					held.Position = V3.new(245, y, 0)
					world.input.InputChanged:Fire(held)
					local bottom = preview.Position.Y.Offset
					expect(bottom <= y - 80 - 44):toBe(true)
					expect(bottom >= world.find("SelectionPlate").Size.Y.Offset + 8):toBe(true)
					expect(plate.Position):toBe(preview.Position)
				end
				held.UserInputState = E.UserInputState.Cancel
				world.input.InputEnded:Fire(held)
				expect(plate.Visible):toBe(false)
				world.stop()
			end,
		})

		it("keeps held labels above lower and side items, with the pointer layout unchanged", {
			id = "native_radial_controls::touch radial label placement::keeps held labels above lower and side items, with the pointer layout unchanged",
			run = function()
				for _, slot in { "E", "SE", "S", "SW", "W" } do
					local world = setup({
						distribution = "compass" :: "compass",
						items = {
							{
								id = slot,
								slot = slot :: Radial.CompassSlot,
								label = "Workshop",
								icon = "settings",
								labelStyle = "icon" :: "icon",
								onSelect = function() end,
							} :: Radial.RadialItem<string>,
						},
					})
					local V2 = world.engine.types.Vector2
					world.engine.environment.poke(world.find("Modal"), "AbsoluteSize", V2.new(390, 760))
					world.engine.environment.poke(
						world.input,
						"PreferredInput",
						world.engine.types.Enum.PreferredInput.Touch
					)
					local item, preview = world.find(slot), world.find("SelectionPreview")
					local x, y = item.Position.X.Offset, item.Position.Y.Offset
					local held = pointer(world, x, y)
					world.find("RadialPanel").InputBegan:Fire(held)
					world.step(0.5)
					expect(preview.Text):toBe("Workshop")
					local bottom = preview.Position.Y.Offset
						+ (1 - preview.AnchorPoint.Y) * world.find("SelectionPlate").Size.Y.Offset
					expect(bottom < y - 22):toBe(true)
					local left = preview.Position.X.Offset
						- preview.AnchorPoint.X * world.find("SelectionPlate").Size.X.Offset
					expect(left >= 8 and left + world.find("SelectionPlate").Size.X.Offset <= 382):toBe(true)
					world.input.InputEnded:Fire(held)
					world.engine.environment.poke(
						world.input,
						"PreferredInput",
						world.engine.types.Enum.PreferredInput.KeyboardAndMouse
					)
					world.engine.environment.fakeOn(world.input, "GetLastInputType", function()
						return world.engine.types.Enum.UserInputType.MouseMovement
					end)
					item.MouseEnter:Fire()
					if slot == "S" then
						expect(preview.Position.Y.Offset > y):toBe(true)
					end
					world.stop()
				end
			end,
		})
	end)

	describe("touch radial label bounds", function()
		it("chooses a caption-safe form before phone-edge text measurement", {
			id = "native_radial_controls::touch radial label bounds::chooses a caption-safe form before phone-edge text measurement",
			run = function()
				local world = setup({
					anchor = { x = 96, y = 260 },
					items = {
						action({ id = "gear", label = "Gear" }),
						action({ id = "edit", label = "Edit" }),
						action({ id = "flag", label = "Flag" }),
						action({ id = "trash", label = "Trash" }),
					},
				}, false, { preferredInput = "Touch" } :: Shared.EnvironmentPreview)
				local V2 = world.engine.types.Vector2
				world.engine.environment.poke(world.screen, "AbsoluteSize", V2.new(390, 740))
				world.engine.environment.poke(world.find("Modal"), "AbsoluteSize", V2.new(390, 740))
				expect(world.find("gear").Size.X.Scale):toBe(1)
				local before = world.find("Center").Position
				for _, id in { "gear", "edit", "flag", "trash" } do
					world.engine.environment.poke(
						world.find(id):FindFirstChild("CaptionMeasure"),
						"TextBounds",
						V2.new(60, 16)
					)
					expect(world.find("gear").Size.X.Scale):toBe(1)
					expect(world.find("Center").Position):toBe(before)
				end
				world.stop()
			end,
		})
		it("falls back below a top-edge item when its label cannot fit above", {
			id = "native_radial_controls::touch radial label bounds::falls back below a top-edge item when its label cannot fit above",
			run = function()
				local world = setup({
					anchor = { x = 195, y = 8 },
					gestureSelection = "direction" :: "direction",
					distribution = "compass" :: "compass",
					items = {
						{
							id = "N",
							slot = "N" :: Radial.CompassSlot,
							label = "Beacon",
							icon = "flag",
							labelStyle = "icon" :: "icon",
							onSelect = function() end,
						} :: Radial.RadialItem<string>,
					},
				})
				world.engine.environment.poke(
					world.find("Modal"),
					"AbsoluteSize",
					world.engine.types.Vector2.new(390, 760)
				)
				world.engine.environment.poke(
					world.input,
					"PreferredInput",
					world.engine.types.Enum.PreferredInput.Touch
				)
				local item, preview = world.find("N"), world.find("SelectionPreview")
				local held = pointer(world, item.Position.X.Offset, item.Position.Y.Offset)
				world.find("RadialPanel").InputBegan:Fire(held)
				world.step(0.5)
				expect(preview.Text):toBe("Beacon")
				local top = preview.Position.Y.Offset
					- preview.AnchorPoint.Y * world.find("SelectionPlate").Size.Y.Offset
				expect(top > item.Position.Y.Offset):toBe(true)
				expect(top >= 8 and top + world.find("SelectionPlate").Size.Y.Offset <= 752):toBe(true)
				world.stop()
			end,
		})
	end)
	return nil
end
