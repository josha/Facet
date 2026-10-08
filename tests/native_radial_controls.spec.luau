--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type ScreenGuiConstructor = typeof(require("@repo/tools/typecheck/aliases").ScreenGuiConstructor)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	local Shared = require("../src/ui/types")
	local Radial = require("../src/ui/radial_types")

	local fadeKit = require("./lib/fade")
	local Compose = require("../src/vendor/compose/core")
	local Roblox = require("../src/vendor/compose/roblox")
	local controls = require("../src/ui")
	local engines = require("./lib/native_engine")
	type World = {
		engine: engines.Engine,
		gui: any,
		input: any,
		screen: any,
		opened: Compose.Cell<boolean>,
		find: (string) -> any,
		step: (number) -> (),
		stop: () -> (),
	}
	local function setup(
		spec: Radial.RadialMenuSpec<any> | ((engines.Engine) -> Radial.RadialMenuSpec<any>),
		animated: boolean?,
		environment: Shared.EnvironmentPreview?
	): World
		local engine, now = engines.new(), 0
		local actual: Radial.RadialMenuSpec<any> = if type(spec) == "function" then spec(engine) else spec
		local gui, input = engine.new("GuiService"), engine.new("UserInputService")
		input.GetFocusedTextBox = function()
			return nil
		end
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
		local stop, screen: any = runtime.mount(function()
			return ((runtime.constructors.ScreenGui :: unknown) :: ScreenGuiConstructor)({ UI.RadialMenu(actual) })
		end, engine.new("Folder"))
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
		for _, id in { "N", "E", "S", "W" } do
			table.insert(entries, {
				id = id,
				slot = id :: Radial.CompassSlot,
				label = id,
				completion = "stay" :: "stay",
				onSelect = function()
					callback(id)
				end,
			})
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
	verifyHarness:suite("radial label fit", function()
		verifyHarness:case("keeps short names on one line inside round item targets", {
			id = "native_radial_controls::radial label fit::keeps short names on one line inside round item targets",
			run = function()
				local spec: Radial.RadialMenuSpec<any> = {
					appearance = "buttons" :: Radial.Appearance,
					items = {
						{ id = "sage", label = "Sage", onSelect = function() end } :: Radial.RadialItem<any>,
						{ id = "clay", label = "Clay", onSelect = function() end } :: Radial.RadialItem<any>,
					},
				}
				local w = setup(spec)
				for _, name in { "sage", "clay" } do
					local button = w.find(name)
					button:FindFirstChild("CaptionMeasure").TextBounds = w.engine.types.Vector2.new(36, 16)
					Verify.expect(button.TextWrapped):toBe(false)
					Verify.expect(button.Size.X.Offset >= 36 + 24):toBe(true)
					Verify.expect(button.TextScaled):toBe(false)
					Verify.expect(button:HasTag("facet-radial-label")):toBe(true)
				end
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("radial full caption fit", function()
		verifyHarness:case("holds the launcher slot while Close replaces its caption", {
			id = "native_radial_controls::radial full caption fit::holds the launcher slot while Close replaces its caption",
			run = function()
				for _, label in { "Quick accent", "Tools" } do
					local world = setup({
						label = label,
						isPresented = Compose.cell(false),
						items = { { id = "sage", label = "Sage", onSelect = function() end } },
					})
					local launcher = world.find("Launcher")
					local root = launcher.Parent
					root.AbsoluteSize = world.engine.types.Vector2.new(140, 44)
					local size, automatic = root.Size, root.AutomaticSize
					for _ = 1, 3 do
						launcher.Activated:Fire()
						Verify.expect(world.opened:peek()):toBe(true)
						Verify.expect(launcher.Visible):toBe(false)
						Verify.expect(root.Size):toBe(world.engine.types.UDim2.fromOffset(140, 44))
						Verify.expect(root.AutomaticSize):toBe(world.engine.types.Enum.AutomaticSize.None)
						world.find("Center").Activated:Fire()
						Verify.expect(world.opened:peek()):toBe(false)
						Verify.expect(launcher.Visible):toBe(true)
						Verify.expect(root.Size):toBe(size)
						Verify.expect(root.AutomaticSize):toBe(automatic)
					end
					world.stop()
				end
			end,
		})

		verifyHarness:case("fits iconless tool captions and button padding inside the default wedges", {
			id = "native_radial_controls::radial full caption fit::fits iconless tool captions and button padding inside the default wedges",
			run = function()
				local world = setup({
					items = {
						{ id = "plant", label = "Plant", onSelect = function() end },
						{ id = "harvest", label = "Harvest", onSelect = function() end },
						{ id = "plow", label = "Plow", onSelect = function() end },
					},
				})
				for _, id in { "plant", "harvest", "plow" } do
					world.find(id):FindFirstChild("CaptionMeasure").TextBounds = world.engine.types.Vector2.new(36, 16)
				end
				world.step(1)
				for _, id in { "plant", "harvest", "plow" } do
					local button = world.find(id)
					Verify.expect(button.Size.X.Offset >= 36 + 24):toBe(true)
					Verify.expect(button.TextWrapped):toBe(false)
				end
				world.stop()
			end,
		})

		verifyHarness:case("keeps complete iconless captions when a phone launcher bounds the ring", {
			id = "native_radial_controls::radial full caption fit::keeps complete iconless captions when a phone launcher bounds the ring",
			run = function()
				local world = setup({
					label = "Tools",
					items = {
						{ id = "plant", label = "Plant", onSelect = function() end },
						{ id = "harvest", label = "Harvest", onSelect = function() end },
						{ id = "plow", label = "Plow", onSelect = function() end },
					},
				})
				local V2 = world.engine.types.Vector2
				world.screen.AbsoluteSize = V2.new(390, 844)
				local launcher = world.find("Launcher")
				launcher.AbsolutePosition, launcher.AbsoluteSize = V2.new(16, 350), V2.new(50, 44)
				for _, id in { "plant", "harvest", "plow" } do
					world.find(id):FindFirstChild("CaptionMeasure").TextBounds = V2.new(60, 16)
				end
				world.step(1)
				for _, id in { "plant", "harvest", "plow" } do
					local button = world.find(id)
					Verify.expect(button.Size.X.Scale == 1 or button.Size.X.Offset >= 60 + 24):toBeTrueWith(id)
					Verify.expect(button.Text)
						:toBe(if id == "plant" then "Plant" elseif id == "harvest" then "Harvest" else "Plow")
					Verify.expect(button.TextWrapped):toBe(false)
				end
				world.stop()
			end,
		})

		verifyHarness:case("uses the styled caption padding when choosing text over a compact icon", {
			id = "native_radial_controls::radial full caption fit::uses the styled caption padding when choosing text over a compact icon",
			run = function()
				local items = {}
				for _, id in { "N", "E", "S", "W" } do
					table.insert(items, { id = id, label = id, icon = "flag", slot = id :: Radial.CompassSlot })
				end
				local world = setup({ distribution = "compass" :: "compass", items = items })
				for _, id in { "N", "E", "S", "W" } do
					local button = world.find(id)
					local padding = button:FindFirstChildWhichIsA("UIPadding", true) or world.engine.new("UIPadding")
					padding.Parent = button
					padding.PaddingLeft, padding.PaddingRight =
						world.engine.types.UDim.new(0, 0), world.engine.types.UDim.new(0, 0)
					button:FindFirstChild("CaptionMeasure").TextBounds = world.engine.types.Vector2.new(12, 16)
				end
				world.step(1)
				for _, id in { "N", "E", "S", "W" } do
					local button = world.find(id)
					Verify.expect((button:FindFirstChild("Title", true) or button).Text):toBe(id)
					Verify.expect(button:FindFirstChild("LeadingIcon", true).Visible):toBe(false)
				end
				world.stop()
			end,
		})

		verifyHarness:case("uses the full caption and button padding before choosing a glyph", {
			id = "native_radial_controls::radial full caption fit::uses the full caption and button padding before choosing a glyph",
			run = function()
				local items = {}
				for _, id in { "settings", "edit", "flag", "trash", "person", "calendar" } do
					table.insert(items, { id = id, label = id, icon = id, onSelect = function() end })
				end
				local world = setup({ items = items })
				world.find("Modal").AbsoluteSize = world.engine.types.Vector2.new(390, 760)
				local button = world.find("settings")
				local title = button:FindFirstChild("Title", true) or button
				title.TextBounds = world.engine.types.Vector2.new(32, 16)
				local measure = assert(button:FindFirstChild("CaptionMeasure"))
				measure.TextBounds = world.engine.types.Vector2.new(48, 16)
				Verify.expect(measure.Text):toBe("settings")
				Verify.expect(measure.TextTruncate.Name):toBe("None")
				Verify.expect(measure.TextTransparency):toBe(1)
				Verify.expect(measure.Interactable):toBe(false)
				Verify.expect(title.Text):toBe("settings")
				Verify.expect(button.Size.X.Offset >= 48 + 24):toBe(true)
				measure.TextBounds = world.engine.types.Vector2.new(104, 16)
				Verify.expect(title.Text):toBe("")
				Verify.expect(button:FindFirstChild("LeadingIcon", true).Visible):toBe(true)
				world.step(1)
				Verify.expect(measure.Text):toBe("settings")
				Verify.expect(title.Text):toBe("")
				local person = world.find("person")
				local personTitle = person:FindFirstChild("Title", true) or person
				personTitle.TextBounds = world.engine.types.Vector2.new(36, 16)
				person:FindFirstChild("CaptionMeasure").TextBounds = world.engine.types.Vector2.new(43, 16)
				Verify.expect(personTitle.Text == "" or person.Size.X.Offset >= 43):toBe(true)
				world.stop()
			end,
		})
	end)

	verifyHarness:suite("native radial interaction policies", function()
		verifyHarness:case("content fitting keeps the full button on its wedge", {
			id = "native_radial_controls::native radial interaction policies::content fitting keeps the full button on its wedge",
			run = function()
				local world = setup({ distribution = "compass" :: "compass", items = compass(function() end) })
				for _, id in { "N", "E", "S", "W" } do
					local button = world.find(id)
					local title = button:FindFirstChild("Title", true) or button
					title.TextBounds = world.engine.types.Vector2.new(8, 16)
				end
				world.step(1)
				for _, id in { "N", "E", "S", "W" } do
					local button = world.find(id)
					local paint = button.Parent:FindFirstChild("Paint")
					local x = button.Position.X.Offset - button.Size.X.Offset / 2
					local y = button.Position.Y.Offset - button.Size.Y.Offset / 2
					Verify.expect(x >= paint.Position.X.Offset - 1):toBe(true)
					Verify.expect(y >= paint.Position.Y.Offset - 1):toBe(true)
					Verify.expect(x + button.Size.X.Offset <= paint.Position.X.Offset + paint.Size.X.Offset + 1)
						:toBe(true)
					Verify.expect(y + button.Size.Y.Offset <= paint.Position.Y.Offset + paint.Size.Y.Offset + 1)
						:toBe(true)
				end
				world.stop()
			end,
		})

		verifyHarness:case("keeps the measured overlay origin while the opening touch freezes the center", {
			id = "native_radial_controls::native radial interaction policies::keeps the measured overlay origin while the opening touch freezes the center",
			run = function()
				local world = setup({ isPresented = Compose.cell(false), items = compass(function() end) }, true)
				local V2 = world.engine.types.Vector2
				world.screen.AbsolutePosition = V2.new(0, 60)
				world.screen.AbsoluteSize = V2.new(390, 780)
				local launcher = world.find("Launcher")
				launcher.AbsolutePosition = V2.new(24, 360)
				launcher.AbsoluteSize = V2.new(120, 44)
				local touch = pointer(world, 80, 380)
				launcher.InputBegan:Fire(touch)
				local center = world.find("Center")
				local original = center.Position
				Verify.expect(original.Y.Offset):toBe(322)
				local modal = center.Parent
				modal.AbsolutePosition = world.screen.AbsolutePosition
				modal.AbsoluteSize = world.screen.AbsoluteSize
				world.step(0.25)
				Verify.expect(center.Position):toBe(original)
				world.input.InputEnded:Fire(touch)
				world.step(0.25)
				Verify.expect(center.Position):toBe(original)
				world.stop()
			end,
		})

		verifyHarness:case("the ring's Back and Close are icon-only even when the level's items carry text labels", {
			id = "native_radial_controls::native radial interaction policies::the ring's Back and Close are icon-only even when the level's items carry text labels",
			run = function()
				local world = setup({
					center = "empty" :: "empty",
					items = {
						{
							id = "gear",
							label = "Gear",
							children = { { id = "wear", label = "Wear" }, { id = "tools", label = "Tools" } },
						} :: Radial.RadialItem<any>,
						{ id = "wave", label = "Wave" } :: Radial.RadialItem<any>,
					},
				})
				world.step(0.5)
				local function navigation()
					local button = world.find("$navigation")
					return button.Text, button:FindFirstChild("LeadingIcon", true).Visible
				end
				local text, glyph = navigation()
				Verify.expect(`{text}|{glyph}`):toBe("|true")
				world.find("gear").Activated:Fire()
				world.step(0.5)
				text, glyph = navigation()
				Verify.expect(`{text}|{glyph}`):toBe("|true")
				Verify.expect(world.find("$navigation"):GetAttribute("label") or "Back"):toBe("Back")
				world.stop()
			end,
		})

		verifyHarness:case(
			"a pointer opening leaves the ring unhighlighted though a stale keyboard selection remains",
			{
				id = "native_radial_controls::native radial interaction policies::a pointer opening leaves the ring unhighlighted though a stale keyboard selection remains",
				run = function()
					for _, last in { "MouseButton1", "Keyboard" } do
						local world = setup(function()
							return {
								isPresented = Compose.cell(false),
								center = "empty" :: "empty",
								items = {
									{ id = "gear", label = "Gear", icon = "menu", labelStyle = "icon" :: "icon" } :: Radial.RadialItem<any>,
									{ id = "wave", label = "Wave", icon = "flag", labelStyle = "icon" :: "icon" } :: Radial.RadialItem<any>,
								},
							}
						end)
						local E = world.engine.types.Enum
						world.input.GetLastInputType = function()
							return assert(E.UserInputType:FromName(last))
						end
						world.gui.SelectedObject = world.find("Launcher")
						world.opened:set(true)
						world.step(0.5)
						local tagged =
							world.find("Sector-gear"):FindFirstChild("Sector", true):HasTag("facet-radial-candidate")
						local inside = world.gui.SelectedObject ~= nil
							and world.gui.SelectedObject:IsDescendantOf(world.find("RadialPanel"))
						Verify.expect(`{last}:{tagged}:{inside}`)
							:toBe(if last == "Keyboard" then `{last}:true:true` else `{last}:false:false`)
						world.stop()
					end
				end,
			}
		)
		verifyHarness:case("a level's wedges keep their shape while they fade out for the next level", {
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
						} :: Radial.RadialItem<any>,
						{ id = "wave", label = "Wave", icon = "flag", labelStyle = "icon" :: "icon" } :: Radial.RadialItem<any>,
					},
				}, true)
				world.step(1)
				local wave = world.find("Sector-wave")
				local paint = wave:FindFirstChild("Paint", true)
				local before =
					`{paint.Position.X.Offset},{paint.Position.Y.Offset},{paint:FindFirstChild("Sector").Thickness}`
				world.find("gear").Activated:Fire()
				world.step(1 / 60)
				Verify.expect(wave.Parent ~= nil):toBe(true)
				local after =
					`{paint.Position.X.Offset},{paint.Position.Y.Offset},{paint:FindFirstChild("Sector").Thickness}`
				Verify.expect(after):toBe(before)
				local arriving = world.find("Sector-wear")
				local fade = arriving:FindFirstChild("FadePaint").Transparency.Keypoints[1].Value
				Verify.expect(fade > 0.5):toBe(true)
				world.step(0.5)
				Verify.expect(arriving:FindFirstChild("FadePaint").Transparency.Keypoints[1].Value):toBe(0)
				world.stop()
			end,
		})

		verifyHarness:case("a corner menu keeps its launcher's room while the launcher hides under the open ring", {
			id = "native_radial_controls::native radial interaction policies::a corner menu keeps its launcher's room while the launcher hides under the open ring",
			run = function()
				local world = setup({
					isPresented = Compose.cell(false),
					preset = "bottom-left" :: "bottom-left",
					appearance = "buttons" :: "buttons",
					items = { { id = "look", label = "Look", icon = "facet:search" } :: Radial.RadialItem<any> },
				})
				local launcher = world.find("Launcher")
				local root = launcher.Parent
				launcher.AbsoluteSize = world.engine.types.Vector2.new(44, 44)
				root.AbsoluteSize = world.engine.types.Vector2.new(44, 44)
				world.opened:set(true)
				world.step(0.5)
				Verify.expect(launcher.Visible):toBe(false)
				Verify.expect(`{root.AutomaticSize.Name} {root.Size.X.Offset}x{root.Size.Y.Offset}`):toBe("None 44x44")
				world.opened:set(false)
				world.step(0.5)
				Verify.expect(launcher.Visible):toBe(true)
				Verify.expect(root.AutomaticSize.Name):toBe("XY")
				world.stop()
			end,
		})
		verifyHarness:case("a corner menu holds its own room in layout units and hands back the caller's size", {
			id = "native_radial_controls::native radial interaction policies::a corner menu holds its own room in layout units and hands back the caller's size",
			run = function()
				local world = setup(function(engine)
					return {
						isPresented = Compose.cell(false),
						preset = "bottom-left" :: "bottom-left",
						appearance = "buttons" :: "buttons",
						Size = engine.types.UDim2.fromOffset(60, 0),
						AutomaticSize = engine.types.Enum.AutomaticSize.Y,
						items = { { id = "look", label = "Look", icon = "facet:search" } :: Radial.RadialItem<any> },
					}
				end)
				local V2 = world.engine.types.Vector2
				local launcher = world.find("Launcher")
				local root = launcher.Parent
				root:FindFirstChild("LayoutUnit").AbsoluteSize = V2.new(62, 0.62)
				launcher.AbsoluteSize = V2.new(27.28, 27.28)
				root.AbsoluteSize = V2.new(37.2, 27.28)
				world.opened:set(true)
				world.step(0.5)
				Verify.expect(`{root.AutomaticSize.Name} {root.Size.X.Offset}x{root.Size.Y.Offset}`):toBe("None 60x44")
				world.opened:set(false)
				world.step(0.5)
				Verify.expect(`{root.AutomaticSize.Name} {root.Size}`):toBe("Y 0, 60, 0, 0")
				world.stop()
			end,
		})
		verifyHarness:case("a corner menu names the hovered button right beside it", {
			id = "native_radial_controls::native radial interaction policies::a corner menu names the hovered button right beside it",
			run = function()
				local world = setup({
					preset = "bottom-left" :: "bottom-left",
					appearance = "buttons" :: "buttons",
					items = {
						{ id = "look", label = "Look", icon = "facet:search" } :: Radial.RadialItem<any>,
						{ id = "pack", label = "Pack", icon = "menu" } :: Radial.RadialItem<any>,
						{ id = "wave", label = "Wave", icon = "flag" } :: Radial.RadialItem<any>,
					},
				})
				world.step(0.5)
				world.input.GetLastInputType = function()
					return world.engine.types.Enum.UserInputType.MouseMovement
				end
				for _, id in { "look", "wave" } do
					local button = world.find(id)
					button.MouseEnter:Fire()
					local preview = world.find("SelectionPreview")
					Verify.expect(preview.Text):toBe(if id == "look" then "Look" else "Wave")
					local dx = preview.Position.X.Offset - button.Position.X.Offset
					local dy = preview.Position.Y.Offset - button.Position.Y.Offset
					local gap = math.sqrt(dx * dx + dy * dy) - button.Size.X.Offset / 2
					Verify.expect(gap >= 0 and gap <= 8):toBe(true)
					button.MouseLeave:Fire()
				end
				world.stop()
			end,
		})
		verifyHarness:case("a slim-band ring paints its wedges only once every label on it is measured", {
			id = "native_radial_controls::native radial interaction policies::a slim-band ring paints its wedges only once every label on it is measured",
			run = function()
				local world = setup({
					contentFit = "radial" :: "radial",
					items = {
						{ id = "wear", label = "Wear" } :: Radial.RadialItem<any>,
						{ id = "tools", label = "Tools" } :: Radial.RadialItem<any>,
					},
				})
				world.step(0.5)
				local function shown(id)
					return world.find("Sector-" .. id):FindFirstChild("Paint").Visible
				end
				Verify.expect(`{shown("wear")} {shown("tools")}`):toBe("false false")
				world.find("wear").TextBounds = world.engine.types.Vector2.new(34, 16)
				Verify.expect(`{shown("wear")} {shown("tools")}`):toBe("false false")
				world.find("tools").TextBounds = world.engine.types.Vector2.new(38, 16)
				Verify.expect(`{shown("wear")} {shown("tools")}`):toBe("true true")
				world.stop()
			end,
		})
		verifyHarness:case("NRAD-1 analog hold commits once and respects dead-zone hysteresis", {
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
				Verify.expect(axis.Type):toBe(world.engine.types.Enum.InputActionType.Direction2D)
				axis.StateChanged:Fire(world.engine.types.Vector2.new(0, 0.3))
				hold.Released:Fire()
				Verify.expect(#picked):toBe(0)
				hold.Pressed:Fire()
				axis.StateChanged:Fire(world.engine.types.Vector2.new(0, 0.8))
				axis.StateChanged:Fire(world.engine.types.Vector2.new(0, 0.3))
				hold.Released:Fire()
				hold.Released:Fire()
				Verify.expect((table.concat(picked, ","))):toBe("N")
				world.stop()
				Verify.expect((engines.connections(hold.Pressed))):toBe(0)
				Verify.expect((engines.connections(hold.Released))):toBe(0)
			end,
		})
		verifyHarness:case("NRAD-2 ignores foreign touch release and cancels captured touch", {
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
				Verify.expect(count):toBe(0)
				touch.UserInputState = world.engine.types.Enum.UserInputState.Cancel
				world.input.InputEnded:Fire(touch)
				Verify.expect(count):toBe(0)
				world.stop()
			end,
		})
		verifyHarness:case("NRAD-3 suppresses the native activation echo after gesture commit", {
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
				Verify.expect(count):toBe(1)
				world.find("N").InputBegan:Fire(touch)
				world.input.InputEnded:Fire(touch)
				Verify.expect(count):toBe(2)
				world.stop()
			end,
		})
		verifyHarness:case("NRAD-4 direction gestures work outside paint while bounded gestures cancel", {
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
					Verify.expect(count):toBe(if mode == "direction" then 1 else 0)
					world.stop()
				end
			end,
		})
		verifyHarness:case("NRAD-5 freezes idle-follow anchor during capture then resumes", {
			id = "native_radial_controls::native radial interaction policies::NRAD-5 freezes idle-follow anchor during capture then resumes",
			run = function()
				local anchor = Compose.cell({ x = 320, y = 240 })
				local world =
					setup({ anchor = anchor, distribution = "compass" :: "compass", items = compass(function() end) })
				local north = world.find("N").Position
				local touch = pointer(world, north.X.Offset, north.Y.Offset)
				world.find("RadialPanel").InputBegan:Fire(touch)
				anchor:set({ x = 400, y = 240 })
				Verify.expect(world.find("N").Position.X.Offset):toBe(320)
				world.input.InputEnded:Fire(touch)
				Verify.expect(world.find("N").Position.X.Offset):toBe(400)
				anchor:set({ x = 400, y = 240, visible = false })
				Verify.expect((world.opened:peek())):toBe(false)
				world.stop()
			end,
		})
		verifyHarness:case("NRAD-6 adapts into native scrolling list without losing a branch", {
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
						} :: Radial.RadialItem<any>,
					},
				})
				world.find("Branch").Activated:Fire()
				world.find("Modal").AbsoluteSize = world.engine.types.Vector2.new(180, 180)
				local panel = world.find("RadialPanel")
				Verify.expect((panel:GetAttribute("Presentation"))):toBe("list")
				Verify.expect(panel.ScrollingEnabled):toBe(true)
				Verify.expect(panel:FindFirstChildWhichIsA("UIListLayout") ~= nil):toBe(true)
				Verify.expect(world.find("Child").Size.Y.Offset):toBe(44)

				Verify.expect(world.find("SelectionPreview").Text):toBe("Branch")
				world.find("Child").Activated:Fire()
				Verify.expect(count):toBe(1)
				world.stop()
			end,
		})
		verifyHarness:case("NRAD-7 state items stay open and completion precedes callbacks", {
			id = "native_radial_controls::native radial interaction policies::NRAD-7 state items stay open and completion precedes callbacks",
			run = function()
				local checked, selected, count, during = Compose.cell(false), Compose.cell("a"), 0, nil
				local opened = Compose.cell(true)
				local world = setup({
					isPresented = opened,
					items = {
						{ id = "Check", label = "Check", checked = checked } :: Radial.RadialItem<any>,
						{
							id = "Radio",
							label = "Radio",
							selected = selected,
							value = "b",
							onChange = function()
								count += 1
							end,
						} :: Radial.RadialItem<any>,
						{
							id = "Done",
							label = "Done",
							onSelect = function()
								during = opened:peek()
							end,
						} :: Radial.RadialItem<any>,
					},
				})
				world.find("Check").Activated:Fire()
				Verify.expect((checked:peek())):toBe(true)
				Verify.expect((opened:peek())):toBe(true)
				world.find("Radio").Activated:Fire()
				world.find("Radio").Activated:Fire()
				Verify.expect(count):toBe(1)
				world.find("Done").Activated:Fire()
				Verify.expect(during):toBe(false)
				world.stop()
			end,
		})
		verifyHarness:case("NRAD-8 nested expansion preserves parents and completion back returns", {
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
						} :: Radial.RadialItem<any>,
					},
				})
				world.find("Branch").Activated:Fire()
				Verify.expect(world.find("Branch") ~= nil):toBe(true)
				Verify.expect(world.find("Child") ~= nil):toBe(true)
				world.find("Child").Activated:Fire()
				Verify.expect(world.find("Branch") ~= nil):toBe(true)
				Verify.expect((world.find("Child"))):toBe(nil)
				world.stop()
			end,
		})
		verifyHarness:case("NRAD-9 Compose exit presence releases native ownership after animation", {
			id = "native_radial_controls::native radial interaction policies::NRAD-9 Compose exit presence releases native ownership after animation",
			run = function()
				local world = setup({ items = compass(function() end) }, true)
				world.step(0.3)
				local panel = world.find("RadialPanel")
				world.opened:set(false)
				Verify.expect((world.find("RadialPanel"))):toBe(panel)
				Verify.expect(panel.Interactable):toBe(false)
				world.step(0.3)
				Verify.expect((world.find("RadialPanel"))):toBe(nil)
				Verify.expect((panel:isDestroyed())):toBe(true)
				world.stop()
			end,
		})
		verifyHarness:case("NRAD-10 reduced motion closes immediately and releases listeners", {
			id = "native_radial_controls::native radial interaction policies::NRAD-10 reduced motion closes immediately and releases listeners",
			run = function()
				local world = setup({ items = compass(function() end) })
				Verify.expect(engines.connections(world.input.InputEnded) > 0):toBe(true)
				world.opened:set(false)
				Verify.expect((world.find("RadialPanel"))):toBe(nil)
				Verify.expect((engines.connections(world.input.InputEnded))):toBe(0)
				world.stop()
			end,
		})

		verifyHarness:case("NRAD-12 empty center keeps ring Back and full-label preview", {
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
						} :: Radial.RadialItem<any>,
					},
				})
				world.find("Branch").Activated:Fire()
				world.input.GetLastInputType = function()
					return world.engine.types.Enum.UserInputType.MouseMovement
				end
				world.find("Action").MouseEnter:Fire()
				Verify.expect(world.find("SelectionPreview").Text):toBe("Long readable action")
				world.find("$navigation").Activated:Fire()
				Verify.expect(world.find("Branch") ~= nil):toBe(true)
				world.stop()
			end,
		})
		verifyHarness:case("NRAD-13 gallery nearby item uses native owned scene and real actions", {
			id = "native_radial_controls::native radial interaction policies::NRAD-13 gallery nearby item uses native owned scene and real actions",
			run = function()
				local engine = engines.new()
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local ctx = {
					Compose = Compose,
					runtime = runtime,
					Host = (runtime.constructors :: unknown) :: RobloxHost,
					types = engine.types,
					viewport = Compose.cell({ width = 1280, height = 720 }),
					UI = controls(Compose, runtime, {
						types = engine.types,
						services = { GuiService = engine.new("GuiService") },
						motionLevel = "none",
					}),
				}
				local built
				local stop, screen: any = runtime.mount(function()
					built = require("../examples/gallery/scenarios/radial_menu").build(ctx)
					return ((runtime.constructors.ScreenGui :: unknown) :: ScreenGuiConstructor)({ built.screen() })
				end, engine.new("Folder"))
				built.steps.world()
				local stage = screen:FindFirstChild("TrailPack", true)
				Verify.expect((stage:IsA("ViewportFrame"))):toBe(true)
				screen:FindFirstChild("Launcher", true).Activated:Fire()
				screen:FindFirstChild("inspect", true).Activated:Fire()
				Verify.expect(assert(assert(built).report().world).angle):toBe(45)
				screen:FindFirstChild("resize", true).Activated:Fire()
				Verify.expect(assert(assert(built).report().world).unpacked):toBe(true)
				screen:FindFirstChild("take", true).Activated:Fire()
				Verify.expect(assert(assert(built).report().world).taken):toBe(true)
				Verify.expect(stage.Visible):toBe(false)
				stop()
				Verify.expect((stage:isDestroyed())):toBe(true)
				runtime:dispose()
			end,
		})
		verifyHarness:case("a launcher tap leaves the menu open when its ring places an action under the finger", {
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
				world.input.PreferredInput = world.engine.types.Enum.PreferredInput.Touch
				launcher.InputBegan:Fire(touch)
				local function unselected()
					for _, node in world.screen:GetDescendants() do
						Verify.expect((node:HasTag("facet-radial-candidate"))):toBe(false)
					end
					Verify.expect(world.find("SelectionPlate").Visible):toBe(false)
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
				Verify.expect(count):toBe(0)
				Verify.expect((world.opened:peek())):toBe(true)
				world.find("N").MouseEnter:Fire()
				unselected()
				world.find("N").Activated:Fire(pointer(world, 320, 110))
				Verify.expect(count):toBe(1)
				world.stop()
			end,
		})
		verifyHarness:case("NRAD-14 launcher press slide releases directly into an action", {
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
				Verify.expect((world.opened:peek())):toBe(true)
				touch.Position = world.engine.types.Vector3.new(320, 110, 0)
				world.input.InputChanged:Fire(touch)
				world.input.InputEnded:Fire(touch)
				launcher.Activated:Fire(touch)
				Verify.expect(count):toBe(1)
				Verify.expect((world.opened:peek())):toBe(true)
				world.stop()
			end,
		})
		verifyHarness:case("NRAD-15 branch replacement retains fading geometry and reclaims interrupted presence", {
			id = "native_radial_controls::native radial interaction policies::NRAD-15 branch replacement retains fading geometry and reclaims interrupted presence",
			run = function()
				for _, animated in { true, false } do
					local world = setup({
						items = {
							{
								id = "Branch",
								label = "Branch",
								children = { { id = "Leaf", label = "Leaf", onSelect = function() end } },
							} :: Radial.RadialItem<any>,
						},
					}, animated)
					world.step(0.3)
					local parent = world.find("Sector-Branch")
					local position = parent:FindFirstChild("Paint", true).Position
					world.find("Branch").Activated:Fire()
					local child = world.find("Sector-Leaf")
					Verify.expect(child ~= nil):toBe(true)
					if animated then
						Verify.expect((parent:isDestroyed())):toBe(false)
						Verify.expect(parent.Parent.Interactable):toBe(false)
						world.step(0.04)
						Verify.expect(fadeKit.of(parent) > 0 and fadeKit.of(parent) < 1):toBe(true)
						Verify.expect(parent:FindFirstChild("Paint", true).Position):toBe(position)
						world.find("Center").Activated:Fire()
						Verify.expect((world.find("Sector-Branch"))):toBe(parent)
						world.find("Branch").Activated:Fire()
						world.step(0.3)
					end
					Verify.expect((parent:isDestroyed())):toBe(true)
					world.stop()
					Verify.expect((child:isDestroyed())):toBe(true)
				end
			end,
		})
		verifyHarness:case(
			"NRAD-16 keeps round button swatches circular and expands the same targets into compact rows",
			{
				id = "native_radial_controls::native radial interaction policies::NRAD-16 keeps round button swatches circular and expands the same targets into compact rows",
				run = function()
					local selected = Compose.cell("sage")
					local world = setup({
						appearance = "buttons" :: "buttons",
						items = {
							{ id = "sage", label = "Sage", selected = selected, value = "sage" } :: Radial.RadialItem<any>,
							{ id = "clay", label = "Clay", selected = selected, value = "clay" } :: Radial.RadialItem<any>,
							{ id = "iris", label = "Iris", selected = selected, value = "iris" } :: Radial.RadialItem<any>,
						},
					})
					local modal, panel = world.find("Modal"), world.find("RadialPanel")
					modal.AbsoluteSize = world.engine.types.Vector2.new(920, 640)
					local button = world.find("iris")
					local corner = button:FindFirstChildWhichIsA("UICorner")
					Verify.expect((panel:GetAttribute("Presentation"))):toBe("radial")
					Verify.expect(button.Size.X.Scale):toBe(0)
					Verify.expect(button.Size.Y.Scale):toBe(0)
					Verify.expect(button.Size.X.Offset):toBe(button.Size.Y.Offset)
					Verify.expect(button.Size.X.Offset >= 44):toBe(true)
					Verify.expect(corner.CornerRadius.Scale):toBe(1)
					Verify.expect(corner.CornerRadius.Offset):toBe(0)
					Verify.expect(world.find("Sector-iris"):FindFirstChild("Paint").Visible):toBe(false)
					modal.AbsoluteSize = world.engine.types.Vector2.new(180, 180)
					Verify.expect((world.find("iris"))):toBe(button)
					Verify.expect((panel:GetAttribute("Presentation"))):toBe("list")
					Verify.expect(button.Size.X.Scale):toBe(1)
					Verify.expect(button.Size.X.Offset):toBe(-8)
					Verify.expect(button.Size.Y.Offset):toBe(44)
					Verify.expect((button:FindFirstChildWhichIsA("UIAspectRatioConstraint"))):toBe(nil)
					button.Activated:Fire()
					Verify.expect((selected:peek())):toBe("iris")
					modal.AbsoluteSize = world.engine.types.Vector2.new(920, 640)
					Verify.expect((world.find("iris"))):toBe(button)
					Verify.expect(button.Size.X.Offset):toBe(button.Size.Y.Offset)
					Verify.expect((button:FindFirstChildWhichIsA("UICorner"))):toBe(corner)
					world.stop()
				end,
			}
		)
		verifyHarness:case(
			"presents on the modal layer over a dimmed page and a still tap outside the ring closes it",
			{
				id = "native_radial_controls::native radial interaction policies::presents on the modal layer over a dimmed page and a still tap outside the ring closes it",
				run = function()
					local world = setup({
						distribution = "compass" :: "compass",
						scrim = "dark" :: "dark",
						items = compass(function() end),
					})
					local modal = world.find("Modal")
					Verify.expect(modal.Parent):toBe(world.screen)
					Verify.expect(modal.ZIndex >= 100):toBe(true)
					Verify.expect((world.find("DismissOutside"):HasTag("facet-scrim"))):toBe(true)
					local near = pointer(world, 330, 250)
					world.find("RadialPanel").InputBegan:Fire(near)
					world.input.InputEnded:Fire(near)
					Verify.expect((world.opened:peek())):toBe(true)
					local slide = pointer(world, 630, 10)
					world.find("RadialPanel").InputBegan:Fire(slide)
					slide.Position = world.engine.types.Vector3.new(600, 40, 0)
					world.input.InputChanged:Fire(slide)
					world.input.InputEnded:Fire(slide)
					Verify.expect((world.opened:peek())):toBe(true)
					local outside = pointer(world, 630, 10)
					world.find("RadialPanel").InputBegan:Fire(outside)
					world.input.InputEnded:Fire(outside)
					Verify.expect((world.opened:peek())):toBe(false)
					world.stop()
				end,
			}
		)
		verifyHarness:case("opens centred on its measured launcher and pulls the ring inside the safe area", {
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
					launcher.AbsolutePosition, launcher.AbsoluteSize = V2.new(x, y), V2.new(40, 40)
					world.opened:set(true)
					local at = world.find("Center").Position
					world.opened:set(false)
					return at.X.Offset, at.Y.Offset
				end
				local x, y = centre(140, 200)
				Verify.expect(x):toBe(160)
				Verify.expect(y):toBe(220)
				x, y = centre(600, 440)
				Verify.expect(x):toBe(640 - 120)
				Verify.expect(y):toBe(480 - 128)
				world.stop()
			end,
		})
		verifyHarness:case(
			"sizes the default ring band from its labels and the theme metrics, never from an engine reading",
			{
				id = "native_radial_controls::native radial interaction policies::sizes the default ring band from its labels and the theme metrics, never from an engine reading",
				run = function()
					local items = {}
					for index = 1, 4 do
						table.insert(
							items,
							{ id = "item" .. index, label = "Item " .. index, onSelect = function() end }
						)
					end
					local world = setup({ items = items })
					local wide = #"Item 1" * 18 * 0.6
					local expected = 40 + (wide + 2 * 12 + 2 * 8) / 2
					local function reach()
						return 240 - world.find("item1").Position.Y.Offset
					end
					Verify.expect(math.abs(reach() - expected) <= 1):toBeTrueWith(`reach {reach()} expected {expected}`)
					local V2 = world.engine.types.Vector2
					for round = 1, 3 do
						for _, node in world.screen:GetDescendants() do
							if node:IsA("TextLabel") or node:IsA("TextButton") then
								node.TextBounds = V2.new(40 * round, 10 * round)
							end
						end
						Verify.expect(math.abs(reach() - expected) <= 1)
							:toBeTrueWith(`reach {reach()} expected {expected}`)
					end
					world.stop()
				end,
			}
		)
		verifyHarness:case(
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
						local scrim = world.find("DismissOutside")
						Verify.expect(`{case.scrim}:{scrim:HasTag("facet-scrim")}:{scrim:HasTag("facet-radial-scrim")}`)
							:toBe(`{case.scrim}:{case.base}:{case.ring}`)
						Verify.expect(scrim.Visible):toBe(true)
						if case.scrim == "none" or case.scrim == nil then
							Verify.expect(scrim.BackgroundTransparency):toBe(1)
						end
						world.stop()
					end
					local ok, message = pcall(setup, { scrim = "heavy", items = compass(function() end) } :: any)
					Verify.expect(ok):toBe(false)
					Verify.expect(string.find(tostring(message), "scrim", 1, true) ~= nil):toBe(true)
				end,
			}
		)

		verifyHarness:case(
			"puts a small plate-less close in the hole over a full dark scrim and names no labelled wedge",
			{
				id = "native_radial_controls::native radial interaction policies::puts a small plate-less close in the hole over a full dark scrim and names no labelled wedge",
				run = function()
					for _, label in { false, "Leave the wheel" } :: { false | string } do
						local world = setup({
							distribution = "compass" :: "compass",
							scrim = "dark" :: "dark",
							centerLabel = if type(label) == "string" then label else nil,
							items = compass(function() end),
						})
						local scrim = world.find("DismissOutside")
						Verify.expect(
							scrim:HasTag("facet-scrim") and scrim:HasTag("facet-radial-scrim") and scrim.Visible
						)
							:toBe(true)
						Verify.expect(scrim.Position.X.Offset < 0 and scrim.Position.Y.Offset < 0):toBe(true)
						Verify.expect(scrim.Size.X.Scale >= 1 and scrim.Size.X.Offset >= -2 * scrim.Position.X.Offset)
							:toBe(true)
						Verify.expect(scrim.Size.Y.Scale >= 1 and scrim.Size.Y.Offset >= -2 * scrim.Position.Y.Offset)
							:toBe(true)
						local centre = world.find("Center")
						local w, h = centre.Size.X.Offset, centre.Size.Y.Offset
						Verify.expect(w):toBe(h)
						Verify.expect(w):toBe(32)
						Verify.expect(centre.AutomaticSize):toBe(world.engine.types.Enum.AutomaticSize.None)
						Verify.expect((centre:HasTag("facet-appearance-utility"))):toBe(true)
						local hit = world.find("CenterHit")
						Verify.expect(hit.Size.X.Offset == 44 and hit.Size.Y.Offset == 44):toBe(true)
						Verify.expect(hit.Selectable):toBe(false)
						Verify.expect(hit.AnchorPoint):toBe(world.engine.types.Vector2.new(0.5, 0.5))
						Verify.expect(hit.Position):toBe(centre.Position)
						Verify.expect(centre.Position.X.Offset):toBe(320)
						local function inside(x: number, y: number)
							return (x - 320) ^ 2 + (y - 240) ^ 2 <= 40 * 40 + 0.5
						end
						for _, dx in { -w / 2, w / 2 } do
							for _, dy in { -h / 2, h / 2 } do
								Verify.expect(
									(inside(centre.Position.X.Offset + dx * 0.71, centre.Position.Y.Offset + dy * 0.71))
								)
									:toBe(true)
							end
						end
						Verify.expect(centre.Text):toBe("")
						Verify.expect(centre:FindFirstChild("LeadingIcon", true) ~= nil):toBe(true)
						Verify.expect((centre:GetAttribute("label"))):toBe(if label then label else "Close")
						local preview = world.find("SelectionPreview")
						world.input.GetLastInputType = function()
							return world.engine.types.Enum.UserInputType.MouseMovement
						end
						world.find("N").MouseEnter:Fire()
						Verify.expect(preview.Text):toBe("")
						world.stop()
					end
				end,
			}
		)
		verifyHarness:case("opens with nothing highlighted until the player points, steps or aims", {
			id = "native_radial_controls::native radial interaction policies::opens with nothing highlighted until the player points, steps or aims",
			run = function()
				local world = setup({ distribution = "compass" :: "compass", items = compass(function() end) })
				for _, node in world.screen:GetDescendants() do
					Verify.expect((node:HasTag("facet-radial-candidate"))):toBe(false)
					if node:IsA("TextButton") and node.Name ~= "Center" then
						Verify.expect(node.Parent.Name .. ":" .. tostring(node.Selected == true))
							:toBe(node.Parent.Name .. ":false")
					end
				end
				world.find("E").MouseEnter:Fire()
				Verify.expect((world.find("Sector-E"):FindFirstChild("Sector", true):HasTag("facet-radial-candidate")))
					:toBe(true)
				world.stop()
			end,
		})
		verifyHarness:case("a corner ring keeps Close on its corner and names the item outside the ring", {
			id = "native_radial_controls::native radial interaction policies::a corner ring keeps Close on its corner and names the item outside the ring",
			run = function()
				local items = {}
				for _, id in { "look", "pack", "wave" } do
					table.insert(items, { id = id, label = id, icon = "flag", onSelect = function() end })
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
				launcher.AbsolutePosition, launcher.AbsoluteSize = V2.new(20, 420), V2.new(40, 40)
				world.opened:set(true)
				Verify.expect((world.find("Sector-$navigation"))):toBeNil()
				local centre = world.find("Center")
				Verify.expect(centre.Position.X.Offset):toBe(40)
				Verify.expect(centre.Position.Y.Offset):toBe(440)
				Verify.expect(centre.Visible):toBe(true)
				world.input.GetLastInputType = function()
					return world.engine.types.Enum.UserInputType.MouseMovement
				end
				world.find("pack").MouseEnter:Fire()
				local preview = world.find("SelectionPreview")
				Verify.expect(preview.Text):toBe("pack")
				local reach = 0
				for _, id in { "look", "pack", "wave" } do
					local at = world.find(id).Position
					reach = math.max(reach, math.sqrt((at.X.Offset - 40) ^ 2 + (at.Y.Offset - 440) ^ 2))
				end
				Verify.expect(preview.Position.X.Offset > 40 + reach * 0.7):toBe(true)
				Verify.expect(preview.Position.Y.Offset < 440 - reach * 0.7):toBe(true)
				Verify.expect(preview.AnchorPoint):toBe(V2.new(0, 1))
				centre.Activated:Fire()
				Verify.expect((world.opened:peek())):toBe(false)
				world.stop()
			end,
		})
		verifyHarness:case(
			"blooms from its launcher on a measured screen instead of travelling in from a default one",
			{
				id = "native_radial_controls::native radial interaction policies::blooms from its launcher on a measured screen instead of travelling in from a default one",
				run = function()
					local world = setup({
						isPresented = Compose.cell(false),
						distribution = "compass" :: "compass",
						items = compass(function() end),
					}, true)
					local V2 = world.engine.types.Vector2
					world.screen.AbsoluteSize = V2.new(1600, 900)
					local launcher = world.find("Launcher")
					launcher.AbsolutePosition, launcher.AbsoluteSize = V2.new(1380, 680), V2.new(40, 40)
					world.opened:set(true)
					local function offset(name)
						local at = world.find(name).Position
						return at.X.Offset - 1400, at.Y.Offset - 700
					end
					local _, early = offset("N")
					Verify.expect((select(1, offset("Center")))):toBe(0)
					world.step(0.4)
					Verify.expect((select(1, offset("Center")))):toBe(0)
					local _, settled = offset("N")
					Verify.expect(math.abs(early) < math.abs(settled) * 0.5):toBe(true)
					world.stop()
				end,
			}
		)
		verifyHarness:case("takes ringWidth as a theme width or pixels and grows a ring until each label fits", {
			id = "native_radial_controls::native radial interaction policies::takes ringWidth as a theme width or pixels and grows a ring until each label fits",
			run = function()
				local function band(width: "narrow" | "regular" | "wide" | number, label: string)
					local world = setup({
						ringWidth = width,
						items = {
							{ id = "a", label = label, onSelect = function() end } :: Radial.RadialItem<any>,
							{ id = "b", label = "B", onSelect = function() end } :: Radial.RadialItem<any>,
							{ id = "c", label = "C", onSelect = function() end } :: Radial.RadialItem<any>,
						},
					})
					local reach = 240 - world.find("a").Position.Y.Offset
					world.stop()
					return reach
				end
				Verify.expect((band("wide", "A"))):toBe(band(88, "A"))
				Verify.expect((band("narrow", "A"))):toBe(band(48, "A"))
				Verify.expect(band("wide", "A") > band("narrow", "A")):toBe(true)
				Verify.expect(band(48, "Wear the lantern") > band(48, "A")):toBe(true)
				local ok, message = pcall(band, "huge" :: any, "A")
				Verify.expect(ok):toBe(false)
				Verify.expect(string.find(tostring(message), "ringWidth", 1, true) ~= nil):toBe(true)
			end,
		})
		verifyHarness:case("shows either a glyph or a word on a ring item, never both over each other", {
			id = "native_radial_controls::native radial interaction policies::shows either a glyph or a word on a ring item, never both over each other",
			run = function()
				local world = setup({
					appearance = "buttons" :: "buttons",
					items = {
						{ id = "map", label = "Map", compactLabel = { icon = "flag" }, onSelect = function() end } :: Radial.RadialItem<any>,
						{ id = "wave", label = "Wave", icon = "flag", onSelect = function() end } :: Radial.RadialItem<any>,
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
				Verify.expect((shown(world.find("map")))):toBe("|true")
				Verify.expect((shown(world.find("wave")))):toBe("|true")
				world.stop()
			end,
		})
		verifyHarness:case("puts the launcher over the object it is anchored to", {
			id = "native_radial_controls::native radial interaction policies::puts the launcher over the object it is anchored to",
			run = function()
				local anchor
				local world = setup(function(engine)
					anchor = engine.new("Frame")
					return {
						isPresented = Compose.cell(false),
						anchor = anchor,
						distribution = "compass" :: "compass",
						items = compass(function() end),
					}
				end)
				local V2 = world.engine.types.Vector2
				anchor.AbsolutePosition, anchor.AbsoluteSize = V2.new(300, 200), V2.new(80, 120)
				world.find("RadialMenu").AbsolutePosition = V2.new(20, 400)
				local launcher = world.find("Launcher")
				Verify.expect(launcher.AnchorPoint):toBe(V2.new(0.5, 0.5))
				Verify.expect(launcher.Position.X.Offset):toBe(320)
				Verify.expect(launcher.Position.Y.Offset):toBe(-140)
				world.stop()
			end,
		})
	end)
	verifyHarness:suite("RadialMenu navigation placement (restored from 0.11)", function()
		local function nested(): { Radial.RadialItem<any> }
			return {
				{
					id = "gear",
					label = "Gear",
					children = { { id = "tool", label = "Tool", onSelect = function() end } },
				},
				{ id = "wave", label = "Wave", onSelect = function() end },
			}
		end
		local function visibleCenter(world: World): any
			local centre = world.find("Center")
			return if centre and centre.Visible then centre else nil
		end

		verifyHarness:case("a back centre uses only the centre control, which goes back and closes at the root", {
			id = "native_radial_controls::RadialMenu navigation placement (restored from 0.11)::a back centre uses only the centre control, which goes back and closes at the root",
			run = function()
				local world = setup({ items = nested() })
				Verify.expect((world.find("$navigation"))):toBeNil()
				local centre = visibleCenter(world)
				Verify.expect((centre:GetAttribute("label"))):toBe("Close")
				world.find("gear").Activated:Fire()
				Verify.expect((visibleCenter(world):GetAttribute("label"))):toBe("Back")
				visibleCenter(world).Activated:Fire()
				Verify.expect(world.find("wave") ~= nil):toBe(true)
				Verify.expect((world.opened:peek())):toBe(true)
				visibleCenter(world).Activated:Fire()
				Verify.expect((world.opened:peek())):toBe(false)
				world.stop()
			end,
		})

		verifyHarness:case("a full compass with an empty centre uses the external control at the centre", {
			id = "native_radial_controls::RadialMenu navigation placement (restored from 0.11)::a full compass with an empty centre uses the external control at the centre",
			run = function()
				local items = {}
				for _, slot in { "N", "NE", "E", "SE", "S", "SW", "W", "NW" } do
					table.insert(
						items,
						{ id = slot, slot = slot :: Radial.CompassSlot, label = slot, onSelect = function() end }
					)
				end
				local world =
					setup({ center = "empty" :: "empty", distribution = "compass" :: "compass", items = items })
				Verify.expect((world.find("$navigation"))):toBeNil()
				local centre = visibleCenter(world)
				Verify.expect(centre ~= nil):toBe(true)
				Verify.expect(centre.Position.X.Offset):toBe(320)
				Verify.expect((centre:GetAttribute("label"))):toBe("Close")
				centre.Activated:Fire()
				Verify.expect((world.opened:peek())):toBe(false)
				world.stop()
			end,
		})

		verifyHarness:case("a corner ring puts Back/Close on the corner whatever the centre, and never on the ring", {
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
					launcher.AbsolutePosition, launcher.AbsoluteSize = V2.new(20, 420), V2.new(40, 40)
					world.opened:set(true)
					Verify.expect((world.find("$navigation"))):toBeNil()
					local centre = visibleCenter(world)
					Verify.expect(`{center}: {centre.Position.X.Offset},{centre.Position.Y.Offset}`)
						:toBe(`{center}: 40,440`)
					Verify.expect(`{center}: {centre:GetAttribute("label")}`):toBe(`{center}: Close`)
					world.find("gear").Activated:Fire()
					Verify.expect(`{center}: {visibleCenter(world):GetAttribute("label")}`):toBe(`{center}: Back`)
					visibleCenter(world).Activated:Fire()
					Verify.expect(`{center}: {world.find("wave") ~= nil and world.opened:peek()}`)
						:toBe(`{center}: true`)
					visibleCenter(world).Activated:Fire()
					Verify.expect(`{center}: {world.opened:peek()}`):toBe(`{center}: false`)
					world.stop()
				end
			end,
		})

		verifyHarness:case("the list fallback has one round Back/Close at the top right for every centre policy", {
			id = "native_radial_controls::RadialMenu navigation placement (restored from 0.11)::the list fallback has one round Back/Close at the top right for every centre policy",
			run = function()
				for _, center in { "empty", "back", "root", "close", "content" } do
					local world = setup({ center = center :: "empty" | "content" | "root" | "close", items = nested() })
					world.find("Modal").AbsoluteSize = world.engine.types.Vector2.new(180, 180)
					Verify.expect((world.find("RadialPanel"):GetAttribute("Presentation"))):toBe("list")
					Verify.expect(`{center}: {world.find("$navigation") == nil}`):toBe(`{center}: true`)
					local centre = visibleCenter(world)
					Verify.expect(`{center}: {centre ~= nil}`):toBe(`{center}: true`)
					Verify.expect(centre.Position.X.Scale):toBe(1)
					Verify.expect(centre.Position.X.Offset + centre.Size.X.Offset * (1 - centre.AnchorPoint.X))
						:toBe(-16)
					Verify.expect(centre.Position.Y.Scale):toBe(0)
					Verify.expect(centre.Size.X.Offset):toBe(centre.Size.Y.Offset)
					Verify.expect(`{center}: {centre:GetAttribute("label")}`):toBe(`{center}: Close`)
					centre.Activated:Fire()
					Verify.expect(`{center}: {world.opened:peek()}`):toBe(`{center}: false`)
					world.stop()
				end
			end,
		})
	end)

	verifyHarness:suite("RadialMenu centre and corner controls (restored from 0.11)", function()
		local themes = require("../src/ui/themes")(Compose)
		local function nested(): { Radial.RadialItem<any> }
			return {
				{
					id = "gear",
					label = "Gear",
					children = { { id = "tool", label = "Tool", onSelect = function() end } },
				},
				{ id = "wave", label = "Wave", onSelect = function() end },
			}
		end
		verifyHarness:case("the 44 px hit area around the 32 px centre control does what the control does", {
			id = "native_radial_controls::RadialMenu centre and corner controls (restored from 0.11)::the 44 px hit area around the 32 px centre control does what the control does",
			run = function()
				local world = setup({ items = nested() })
				world.find("gear").Activated:Fire()
				world.find("CenterHit").Activated:Fire()
				Verify.expect(world.find("wave") ~= nil and world.opened:peek()):toBe(true)
				world.find("CenterHit").Activated:Fire()
				Verify.expect((world.opened:peek())):toBe(false)
				world.stop()
			end,
		})

		verifyHarness:case(
			"the ring's full-screen panel takes no panel padding, so a themed inset cannot shift the ring",
			{
				id = "native_radial_controls::RadialMenu centre and corner controls (restored from 0.11)::the ring's full-screen panel takes no panel padding, so a themed inset cannot shift the ring",
				run = function()
					local world = setup({ items = nested() })
					world.find("Modal").AbsoluteSize = world.engine.types.Vector2.new(800, 600)
					local panel = world.find("RadialPanel")
					Verify.expect((panel:GetAttribute("Presentation"))):toBe("radial")
					Verify.expect((panel:HasTag("facet-panel"))):toBe(false)
					world.stop()
				end,
			}
		)
		verifyHarness:case("the list fallback heads its opaque panel with the path, clear of the page below", {
			id = "native_radial_controls::RadialMenu centre and corner controls (restored from 0.11)::the list fallback heads its opaque panel with the path, clear of the page below",
			run = function()
				local world = setup({ items = nested() })
				world.find("Modal").AbsoluteSize = world.engine.types.Vector2.new(180, 180)
				local preview = world.find("SelectionPreview")
				Verify.expect(preview.AnchorPoint):toBe(world.engine.types.Vector2.new(0, 1))
				Verify.expect(preview.Position.Y.Scale):toBe(0)
				Verify.expect(preview.TextXAlignment):toBe(world.engine.types.Enum.TextXAlignment.Left)
				Verify.expect((preview:IsDescendantOf(world.find("RadialPanel")))):toBe(false)
				local panel = world.find("RadialPanel")
				Verify.expect(preview.Position.Y.Offset <= panel.Position.Y.Offset):toBe(true)
				Verify.expect(panel.BackgroundTransparency):toBe(0)
				Verify.expect((panel:HasTag("facet-panel"))):toBe(true)
				world.stop()
			end,
		})
		verifyHarness:case("closing a corner ring hands the selection back to its launcher", {
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
				Verify.expect(launcher.Visible):toBe(false)
				Verify.expect(world.gui.SelectedObject ~= launcher):toBe(true)
				world.opened:set(false)
				world.step(0.5)
				Verify.expect((world.find("Center"))):toBeNil()
				Verify.expect(world.gui.SelectedObject):toBe(launcher)
				world.stop()
			end,
		})

		verifyHarness:case("a corner control grows out of the launcher and back into it, crossfading the glyphs", {
			id = "native_radial_controls::RadialMenu centre and corner controls (restored from 0.11)::a corner control grows out of the launcher and back into it, crossfading the glyphs",
			run = function()
				local world = setup({
					isPresented = Compose.cell(false),
					preset = "bottom-left" :: "bottom-left",
					items = nested(),
				}, true)
				local V2 = world.engine.types.Vector2
				world.screen.AbsoluteSize = V2.new(640, 480)
				local launcher = world.find("Launcher")
				launcher.AbsolutePosition, launcher.AbsoluteSize = V2.new(20, 420), V2.new(40, 40)
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
				Verify.expect(w == 40 and h == 40):toBe(true)
				Verify.expect(launcher.Visible):toBe(false)
				Verify.expect(back == 0 and own == 1):toBe(true)
				local glyph = world.find("Center"):FindFirstChild("LauncherIcon", true)
				Verify.expect(glyph.Image):toBe(themes.resolveIcon({} :: any, "more"))
				world.step(0.1)
				w, h, back, own = state()
				Verify.expect(w > 32 and w < 40 and w == h):toBe(true)
				Verify.expect(math.abs(back + own - 1) < 0.001 and back > 0 and own > 0):toBe(true)
				world.step(0.3)
				w, h, back, own = state()
				Verify.expect(w == 32 and back == 1 and own == 0):toBe(true)
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
					Verify.expect(math.abs(b + o - 1) < 0.001):toBe(true)
				end
				Verify.expect(frames > 2 and grew):toBe(true)
				Verify.expect((world.find("Center"))):toBeNil()
				Verify.expect(launcher.Visible):toBe(true)
				world.stop()
			end,
		})
		verifyHarness:case("a gamepad replacing a level lands on the new level's first item", {
			id = "native_radial_controls::RadialMenu centre and corner controls (restored from 0.11)::a gamepad replacing a level lands on the new level's first item",
			run = function()
				local world = setup({ items = nested() })
				world.gui.SelectedObject = world.find("gear")
				world.find("gear").Activated:Fire()
				Verify.expect(world.gui.SelectedObject):toBe(world.find("tool"))
				world.stop()
			end,
		})
		verifyHarness:case("names an icon item only while a finger holds it, never on a tap or a level change", {
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
						} :: Radial.RadialItem<any>,
					},
				})
				local preview, panel = world.find("SelectionPreview"), world.find("RadialPanel")
				local north = world.find("N")
				local x, y = north.Position.X.Offset, north.Position.Y.Offset
				local tap = pointer(world, x, y)
				panel.InputBegan:Fire(tap)
				world.input.InputEnded:Fire(tap)
				Verify.expect(preview.Text):toBe("")
				local hold = pointer(world, x, y)
				panel.InputBegan:Fire(hold)
				Verify.expect(preview.Text):toBe("")
				world.step(0.5)
				Verify.expect(preview.Text):toBe("Lantern")
				world.input.InputEnded:Fire(hold)
				Verify.expect(preview.Text):toBe("")
				world.find("E").Activated:Fire()
				Verify.expect(world.find("stow") ~= nil):toBe(true)
				Verify.expect(preview.Text):toBe("")
				world.find("stow").MouseEnter:Fire()
				Verify.expect(preview.Text):toBe("")
				world.stop()
			end,
		})
		verifyHarness:case("a submenu's ring unfolds along the ring from the chosen item, not out of the centre", {
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
						} :: Radial.RadialItem<any>,
						{ id = "E", slot = "E" :: Radial.CompassSlot, label = "E", onSelect = function() end } :: Radial.RadialItem<any>,
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
				Verify.expect(offset.Magnitude > 0.9 * ring):toBe(true)
				Verify.expect(offset.Y < 0):toBe(true)
				Verify.expect((final.c - centre).Y > 0):toBe(true)
				world.stop()
			end,
		})
		verifyHarness:case("Back folds the submenu into its item and re-opens the parent ring around it", {
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
							} :: Radial.RadialItem<any>,
							{ id = "E", slot = "E" :: Radial.CompassSlot, label = "E", onSelect = function() end } :: Radial.RadialItem<any>,
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
				Verify.expect(child ~= nil):toBe(true)
				Verify.expect((at("c") - gear).Magnitude < (restC - gear).Magnitude):toBe(true)
				Verify.expect((at("E") - gear).Magnitude < (restE - gear).Magnitude):toBe(true)
				world.step(0.5)
				Verify.expect((at("E") - restE).Magnitude < 0.5):toBe(true)
				Verify.expect((world.find("c"))):toBeNil()
				local plain = ring()
				plain.step(0.5)
				Verify.expect((reopen(world) - reopen(plain)).Magnitude < 0.5):toBe(true)
				plain.stop()
				world.stop()
			end,
		})
		verifyHarness:case("Back re-opens the parent around the item's current place after the ring re-lays out", {
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
				Verify.expect((after - before).Magnitude > 20):toBe(true)
				Verify.expect((early - after).Magnitude < (early - before).Magnitude):toBe(true)
				world.stop()
			end,
		})
		verifyHarness:case(
			"a long press names an item without acting; the release does nothing and a second tap acts",
			{
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
							} :: Radial.RadialItem<any>,
						},
					})
					local preview, panel, north =
						world.find("SelectionPreview"), world.find("RadialPanel"), world.find("N")
					local x, y = north.Position.X.Offset, north.Position.Y.Offset
					local hold = pointer(world, x, y)
					north.InputBegan:Fire(hold)
					world.step(0.5)
					Verify.expect(preview.Text):toBe("Lantern")
					hold.UserInputState = world.engine.types.Enum.UserInputState.End
					world.input.InputEnded:Fire(hold)
					north.Activated:Fire(hold)
					Verify.expect(picked):toBe(0)
					local tap = pointer(world, x, y)
					north.InputBegan:Fire(tap)
					tap.UserInputState = world.engine.types.Enum.UserInputState.End
					world.input.InputEnded:Fire(tap)
					north.Activated:Fire(tap)
					Verify.expect(picked):toBe(1)
					local slide = pointer(world, x, y)
					panel.InputBegan:Fire(slide)
					slide.Position = world.engine.types.Vector3.new(x + 30, y, 0)
					world.input.InputChanged:Fire(slide)
					slide.Position = world.engine.types.Vector3.new(x, y, 0)
					world.input.InputChanged:Fire(slide)
					world.step(0.5)
					slide.UserInputState = world.engine.types.Enum.UserInputState.End
					world.input.InputEnded:Fire(slide)
					Verify.expect(picked):toBe(2)
					world.stop()
				end,
			}
		)
		verifyHarness:case("a hold that then slides to another item picks the item under the finger on release", {
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
				Verify.expect((table.concat(picks, ","))):toBe("E")
				world.stop()
			end,
		})
		verifyHarness:case("keeps a held item's name on the screen beside a ring near the edge of a phone", {
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
						} :: Radial.RadialItem<any>,
					},
				})
				world.find("Modal").AbsoluteSize = world.engine.types.Vector2.new(390, 760)
				local preview, east = world.find("SelectionPreview"), world.find("E")
				local hold = pointer(world, east.Position.X.Offset, east.Position.Y.Offset)
				world.find("RadialPanel").InputBegan:Fire(hold)
				world.step(0.5)
				Verify.expect(preview.Text):toBe("Lantern")
				local width = world.find("SelectionPlate").Size.X.Offset
				local left = preview.Position.X.Offset - preview.AnchorPoint.X * width
				Verify.expect(left >= 8 and left + width <= 382):toBe(true)
				world.input.InputEnded:Fire(hold)
				world.stop()
			end,
		})
		verifyHarness:case("keeps a nested level on the ring by replacing its parent before it falls back to a list", {
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
								} :: Radial.RadialItem<any>,
								{ id = "wear", label = "Wear", children = { leaf("w") } } :: Radial.RadialItem<any>,
							},
						} :: Radial.RadialItem<any>,
					},
				})
				world.find("Modal").AbsoluteSize = world.engine.types.Vector2.new(360, 240)
				world.find("gear").Activated:Fire()
				world.find("tools").Activated:Fire()
				Verify.expect((world.find("RadialPanel"):GetAttribute("Presentation"))):toBe("radial")
				Verify.expect(world.find("x") ~= nil):toBe(true)
				world.stop()
			end,
		})
		verifyHarness:case(
			"fits an anchored ring inside the page space that holds its anchor, down to the touch floor",
			{
				id = "native_radial_controls::RadialMenu centre and corner controls (restored from 0.11)::fits an anchored ring inside the page space that holds its anchor, down to the touch floor",
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
					local scene, anchor
					local world = setup(function(engine)
						scene, anchor = engine.new("Frame"), engine.new("Frame")
						anchor.Parent = scene
						return {
							anchor = anchor,
							clearance = 82,
							ringWidth = "narrow" :: "narrow",
							center = "empty" :: "empty",
							contentFit = "none" :: "none",
							items = {
								leaf("wave"),
								leaf("look"),
								{
									id = "gear",
									label = "Gear",
									icon = "menu",
									labelStyle = "icon" :: "icon",
									navigation = "replace" :: "replace",
									children = {
										{
											id = "tools",
											label = "Tools",
											icon = "edit",
											labelStyle = "icon" :: "icon",
											navigation = "expand" :: "expand",
											expansion = "fan" :: "fan",
											children = { leaf("x"), leaf("y"), leaf("z") },
										},
										leaf("wear"),
									},
								} :: Radial.RadialItem<any>,
							},
						}
					end)
					local V2 = world.engine.types.Vector2
					world.find("Modal").AbsoluteSize = V2.new(390, 760)
					scene.AbsolutePosition, scene.AbsoluteSize = V2.new(16, 200), V2.new(358, 260)
					anchor.AbsolutePosition, anchor.AbsoluteSize = V2.new(157, 275), V2.new(76, 110)
					world.find("gear").Activated:Fire()
					world.find("tools").Activated:Fire()
					Verify.expect((world.find("RadialPanel"):GetAttribute("Presentation"))):toBe("radial")
					local painted = 0
					for _, node in world.screen:GetDescendants() do
						if node.Name == "Paint" and node.Visible and node.Parent.Parent.Interactable then
							painted += 1
							local x, y = node.Position.X.Offset, node.Position.Y.Offset
							Verify.expect(x >= 16 and x + node.Size.X.Offset <= 374):toBe(true)
							Verify.expect(y >= 200 and y + node.Size.Y.Offset <= 460):toBe(true)
						end
					end
					Verify.expect(painted):toBe(4)
					world.stop()
				end,
			}
		)
		verifyHarness:case("shows an item's icon instead of a word that is wider than its fitted slot", {
			id = "native_radial_controls::RadialMenu centre and corner controls (restored from 0.11)::shows an item's icon instead of a word that is wider than its fitted slot",
			run = function()
				local world = setup({
					items = {
						{
							id = "lantern",
							label = "Lantern",
							compactLabel = { icon = "increment" },
							onSelect = function() end,
						} :: Radial.RadialItem<any>,
						{ id = "stow", label = "Stow", icon = "flag", onSelect = function() end } :: Radial.RadialItem<any>,
						{ id = "go", label = "Go", onSelect = function() end } :: Radial.RadialItem<any>,
					},
				})
				local V2 = world.engine.types.Vector2
				world.find("Modal").AbsoluteSize = V2.new(390, 760)
				local function title(id: string): any
					local button = world.find(id)
					return button:FindFirstChild("Title", true) or button
				end
				for _, id in { "lantern", "stow", "go" } do
					title(id).TextBounds = V2.new(400, 16)
				end
				Verify.expect(title("lantern").Text):toBe("")
				Verify.expect(world.find("lantern"):FindFirstChild("LeadingIcon", true).Visible):toBe(true)
				Verify.expect(title("stow").Text):toBe("")
				Verify.expect(title("go").Text):toBe("Go")
				world.stop()
			end,
		})
	end)

	verifyHarness:suite("touch radial label placement", function()
		verifyHarness:case(
			"follows a captured touch outside the wedge, wraps its name in tooltip paint and clears on cancel",
			{
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
							} :: Radial.RadialItem<any>,
						},
					})
					local V2, V3, E = world.engine.types.Vector2, world.engine.types.Vector3, world.engine.types.Enum
					local modal = world.find("Modal")
					modal.AbsoluteSize = V2.new(390, 760)
					modal.AbsolutePosition = V2.new(50, 80)
					local item, preview, plate =
						world.find("S"), world.find("SelectionPreview"), world.find("SelectionPlate")
					Verify.expect(plate.Visible):toBe(false)
					local held = pointer(world, 50 + item.Position.X.Offset, 80 + item.Position.Y.Offset)
					world.find("RadialPanel").InputBegan:Fire(held)
					world.step(0.5)
					preview.AbsoluteSize = V2.new(236, 60)
					Verify.expect(preview.Text):toBe("Workshop · Restore power")
					Verify.expect(plate:HasTag("facet-tooltip") and plate.Visible):toBe(true)
					Verify.expect(preview.TextWrapped):toBe(true)
					Verify.expect(plate.Size):toBe(world.engine.types.UDim2.fromOffset(236, 60))
					Verify.expect(preview.AutomaticSize):toBe(E.AutomaticSize.XY)
					for _, y in { 680, 720 } do
						held.Position = V3.new(245, y, 0)
						world.input.InputChanged:Fire(held)
						local bottom = preview.Position.Y.Offset
						Verify.expect(bottom <= y - 80 - 44):toBe(true)
						Verify.expect(bottom >= world.find("SelectionPlate").Size.Y.Offset + 8):toBe(true)
						Verify.expect(plate.Position):toBe(preview.Position)
					end
					held.UserInputState = E.UserInputState.Cancel
					world.input.InputEnded:Fire(held)
					Verify.expect(plate.Visible):toBe(false)
					world.stop()
				end,
			}
		)

		verifyHarness:case("keeps held labels above lower and side items, with the pointer layout unchanged", {
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
							} :: Radial.RadialItem<any>,
						},
					})
					local V2 = world.engine.types.Vector2
					world.find("Modal").AbsoluteSize = V2.new(390, 760)
					world.input.PreferredInput = world.engine.types.Enum.PreferredInput.Touch
					local item, preview = world.find(slot), world.find("SelectionPreview")
					local x, y = item.Position.X.Offset, item.Position.Y.Offset
					local held = pointer(world, x, y)
					world.find("RadialPanel").InputBegan:Fire(held)
					world.step(0.5)
					Verify.expect(preview.Text):toBe("Workshop")
					local bottom = preview.Position.Y.Offset
						+ (1 - preview.AnchorPoint.Y) * world.find("SelectionPlate").Size.Y.Offset
					Verify.expect(bottom < y - 22):toBe(true)
					local left = preview.Position.X.Offset
						- preview.AnchorPoint.X * world.find("SelectionPlate").Size.X.Offset
					Verify.expect(left >= 8 and left + world.find("SelectionPlate").Size.X.Offset <= 382):toBe(true)
					world.input.InputEnded:Fire(held)
					world.input.PreferredInput = world.engine.types.Enum.PreferredInput.KeyboardAndMouse
					world.input.GetLastInputType = function()
						return world.engine.types.Enum.UserInputType.MouseMovement
					end
					item.MouseEnter:Fire()
					if slot == "S" then
						Verify.expect(preview.Position.Y.Offset > y):toBe(true)
					end
					world.stop()
				end
			end,
		})
	end)

	verifyHarness:suite("touch radial label bounds", function()
		verifyHarness:case("chooses a caption-safe form before phone-edge text measurement", {
			id = "native_radial_controls::touch radial label bounds::chooses a caption-safe form before phone-edge text measurement",
			run = function()
				local world = setup({
					anchor = { x = 96, y = 260 },
					items = {
						{ id = "gear", label = "Gear" },
						{ id = "edit", label = "Edit" },
						{ id = "flag", label = "Flag" },
						{ id = "trash", label = "Trash" },
					},
				}, false, { preferredInput = "Touch" } :: Shared.EnvironmentPreview)
				local V2 = world.engine.types.Vector2
				world.screen.AbsoluteSize = V2.new(390, 740)
				world.find("Modal").AbsoluteSize = V2.new(390, 740)
				Verify.expect(world.find("gear").Size.X.Scale):toBe(1)
				local before = world.find("Center").Position
				for _, id in { "gear", "edit", "flag", "trash" } do
					world.find(id):FindFirstChild("CaptionMeasure").TextBounds = V2.new(60, 16)
					Verify.expect(world.find("gear").Size.X.Scale):toBe(1)
					Verify.expect(world.find("Center").Position):toBe(before)
				end
				world.stop()
			end,
		})
		verifyHarness:case("falls back below a top-edge item when its label cannot fit above", {
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
						} :: Radial.RadialItem<any>,
					},
				})
				world.find("Modal").AbsoluteSize = world.engine.types.Vector2.new(390, 760)
				world.input.PreferredInput = world.engine.types.Enum.PreferredInput.Touch
				local item, preview = world.find("N"), world.find("SelectionPreview")
				local held = pointer(world, item.Position.X.Offset, item.Position.Y.Offset)
				world.find("RadialPanel").InputBegan:Fire(held)
				world.step(0.5)
				Verify.expect(preview.Text):toBe("Beacon")
				local top = preview.Position.Y.Offset
					- preview.AnchorPoint.Y * world.find("SelectionPlate").Size.Y.Offset
				Verify.expect(top > item.Position.Y.Offset):toBe(true)
				Verify.expect(top >= 8 and top + world.find("SelectionPlate").Size.Y.Offset <= 752):toBe(true)
				world.stop()
			end,
		})
	end)
	return nil
end
