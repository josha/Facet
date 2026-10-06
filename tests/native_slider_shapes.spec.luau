--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type FrameConstructor = typeof(require("@repo/tools/typecheck/aliases").FrameConstructor)

	local Compose = require("../src/vendor/compose/core")
	local Roblox = require("../src/vendor/compose/roblox")
	local context = require("../src/ui/context")
	local register = require("../src/ui/inputs")
	local engineLib = require("./lib/native_engine")
	local expect = Verify.expect

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

	local function world(spec: any, options: any?): any
		local o = options or {}
		local engine: any = o.engine or engineLib.new()
		local runtime: ComposeRuntime = Roblox.createRuntime(engine)
		local UI: any = {}
		local gui, input = engine.new("GuiService"), engine.new("UserInputService")
		local E = engine.types.Enum
		input.PreferredInput = o.preferred or E.PreferredInput.KeyboardAndMouse
		local held: { [any]: boolean } = {}
		local services: any = {
			GuiService = gui,
			UserInputService = setmetatable({
				IsKeyDown = function(_, key)
					return held[key.Name] == true
				end,
				IsGamepadButtonDown = function(_, _, key)
					return held[key.Name] == true
				end,
			}, {
				__index = function(_, key)
					local value = input[key]
					if type(value) == "function" then
						return function(_, ...)
							return value(input, ...)
						end
					end
					return value
				end,
			}),
		}
		local ctx = context(Compose, runtime, { types = engine.types, services = services, guiService = gui })
		register(ctx, UI)
		local w: any = {
			engine = engine,
			runtime = runtime,
			gui = gui,
			input = input,
			held = held,
			E = E,
			changes = {},
			commits = {},
			visible = Compose.cell(true),
		}
		local merged: { [string]: any } = table.clone(spec)
		merged.min = merged.min or 0
		merged.max = merged.max or 100
		if merged.range and merged.value == nil then
			merged.value = Compose.cell({ lower = 20, upper = 60 })
		elseif merged.value == nil then
			merged.value = Compose.cell(50)
		end
		w.value = merged.value
		if merged.onCommit == nil then
			merged.onCommit = function(value: any, info: any)
				local text = if type(value) == "table" then `{value.lower}-{value.upper}` else tostring(value)
				table.insert(w.commits, if info then `{info.thumb}:{text}` else text)
			end
		end
		local screen = engine.new("ScreenGui")
		w.screen = screen
		w.stop = runtime.mount(function()
			return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
				Name = "Host",
				Compose.show(w.visible, function()
					return UI.Slider("Vol")(merged)
				end),
			})
		end, screen)
		w.node = find(screen, "Vol")
		w.track = find(w.node, "Track")
		w.track.AbsoluteSize =
			engine.types.Vector2.new(if merged.axis == "y" then 44 else 200, if merged.axis == "y" then 200 else 44)
		w.track.AbsolutePosition = engine.types.Vector2.new(0, 0)
		return w
	end

	local function v(w: any, x: number, y: number): any
		return w.engine.types.Vector2.new(x, y)
	end

	local function action(w: any, name: string): any
		for _, child in w.screen:GetChildren() do
			if child:IsA("InputContext") and child.Enabled then
				local found = child:FindFirstChild(name)
				if found then
					return found
				end
			end
		end
		return nil
	end

	local function press(w: any, name: string): boolean
		local found = action(w, name)
		if found == nil then
			return false
		end
		found.Pressed.fire()
		found.Released.fire()
		return true
	end

	local function bindings(w: any, name: string): string
		local found = action(w, name)
		local keys = {}
		for _, binding in if found then found:GetChildren() else {} do
			table.insert(keys, binding.KeyCode.Name)
		end
		table.sort(keys)
		return table.concat(keys, " ")
	end

	local function drag(w: any, node: any, from: any, to: { any }?)
		local detector = node:FindFirstChildWhichIsA("UIDragDetector")
		detector.DragStart.fire(from)
		local points: { any } = to or {}
		for _, point in points do
			detector.DragContinue.fire(point)
		end
		detector.DragEnd.fire()
	end

	local function pair(w: any): string
		local value = w.value:peek()
		return `{value.lower}/{value.upper}`
	end

	verifyHarness:suite("native Slider axis", function()
		verifyHarness:case("a vertical track fills from the bottom edge and the thumb climbs as the value rises", {
			id = "native_slider_shapes::native Slider axis::a vertical track fills from the bottom edge and the thumb climbs as the value rises",
			run = function()
				local w = world({ axis = "y" :: "y", step = 10 })
				local fill, thumb = find(w.track, "Fill"), find(w.track, "ThumbStop")
				expect(w.track.Size.Y.Scale):toBe(1)
				expect(w.track.Size.X.Offset):toBe(44)
				expect(fill.AnchorPoint.Y):toBe(1)
				expect(fill.Position.Y.Scale):toBe(1)
				expect(fill.Size.Y.Scale):toBe(0.5)
				local before = thumb.Position.Y.Scale
				w.value:set(90)
				expect(thumb.Position.Y.Scale < before):toBe(true)
				expect(fill.Size.Y.Scale):toBeCloseTo(0.9, 1e-4)
				drag(w, w.track, v(w, 22, 29.6))
				expect((w.value:peek())):toBe(90)
				drag(w, w.track, v(w, 22, 135.2))
				expect((w.value:peek())):toBe(30)
				w.stop()
			end,
		})

		verifyHarness:case("Up and Down adjust a vertical track and Left and Right do not", {
			id = "native_slider_shapes::native Slider axis::Up and Down adjust a vertical track and Left and Right do not",
			run = function()
				local w = world({ axis = "y" :: "y", step = 10 })
				w.gui.SelectedObject = w.node
				expect((bindings(w, "IncreaseArrow"))):toBe("DPadUp Up")
				expect((bindings(w, "DecreaseArrow"))):toBe("DPadDown Down")
				press(w, "IncreaseArrow")
				expect((w.value:peek())):toBe(60)
				press(w, "DecreaseArrow")
				expect((w.value:peek())):toBe(50)
				w.stop()
				local x = world({ step = 10 })
				x.gui.SelectedObject = x.node
				expect((bindings(x, "IncreaseArrow"))):toBe("DPadRight Right")
				x.stop()
			end,
		})

		verifyHarness:case("the arrow that lands the ring is not a value step; the next arrow is", {
			id = "native_slider_shapes::native Slider axis::the arrow that lands the ring is not a value step; the next arrow is",
			run = function()
				for _, key in { "Up", "DPadUp" } do
					local w = world({ axis = "y" :: "y", step = 10 })
					w.held[key] = true
					w.gui.SelectedObject = w.node
					local increase = action(w, "IncreaseArrow")
					increase.Pressed.fire()
					expect(`{key} landed {w.value:peek()}`):toBe(`{key} landed 50`)
					w.held[key] = nil
					increase.Released.fire()
					increase.Pressed.fire()
					increase.Released.fire()
					expect(`{key} next {w.value:peek()}`):toBe(`{key} next 60`)
					w.stop()
				end
				local tabbed = world({ axis = "y" :: "y", step = 10 })
				tabbed.gui.SelectedObject = tabbed.node
				press(tabbed, "IncreaseArrow")
				expect((tabbed.value:peek())):toBe(60)
				tabbed.stop()
			end,
		})

		verifyHarness:case("the axis and the other construction words refuse a readable", {
			id = "native_slider_shapes::native Slider axis::the axis and the other construction words refuse a readable",
			run = function()
				for _, key in { "axis", "range", "minGap", "thumb" } do
					local ok, err = pcall(function()
						local spec: any = { step = 1 }
						spec[key] = Compose.cell(
							if key == "axis"
								then "y"
								elseif key == "thumb" then "auto"
								elseif key == "range" then false
								else 1
						)
						world(spec)
					end)
					expect(`{key}: {ok}`):toBe(`{key}: false`)
					expect(`{key}: {string.find(tostring(err), key, 1, true) ~= nil}`):toBe(`{key}: true`)
				end
			end,
		})
	end)

	verifyHarness:suite("native Slider rotation", function()
		verifyHarness:case("keeps the rotating track outside the list layout for every slider shape", {
			id = "native_slider_shapes::native Slider rotation::keeps the rotating track outside the list layout for every slider shape",
			run = function()
				for _, shape in { {}, { axis = "y" :: "y" }, { row = { title = "Volume" } }, { range = true } } do
					local options: any = table.clone(shape)
					options.rotation = Compose.cell(0)
					local w = world(options)
					expect(w.track.Parent.Name):toBe("TrackSlot")
					expect((w.track.Parent:FindFirstChildWhichIsA("UIListLayout"))):toBe(nil)
					expect(w.track.Parent:FindFirstChildWhichIsA("UISizeConstraint").MinSize):toBe(v(w, 44, 44))
					options.rotation:set(90)
					expect(w.track.Rotation):toBe(90)
					w.stop()
				end
			end,
		})

		local function pressAt(w: any, degrees: number, f: number, offset: any?)
			local size = w.track.AbsoluteSize
			local at = w.track.AbsolutePosition
			local cx, cy = at.X + size.X / 2, at.Y + size.Y / 2
			local ux, uy = at.X + size.X * f, cy
			local a = math.rad(degrees)
			local dx, dy = ux - cx, uy - cy
			local px = cx + dx * math.cos(a) - dy * math.sin(a)
			local py = cy + dx * math.sin(a) + dy * math.cos(a)
			drag(w, w.track, v(w, px, py))
		end

		verifyHarness:case("every eighth of a turn reads the value the upright track would", {
			id = "native_slider_shapes::native Slider rotation::every eighth of a turn reads the value the upright track would",
			run = function()
				for _, degrees in { 45, 90, 135, 180, 225, 270, 315 } do
					local w = world({ rotation = degrees, step = 25 })
					expect(w.track.Rotation):toBe(degrees)
					pressAt(w, degrees, 0.75)
					expect(`{degrees}deg -> {w.value:peek()}`):toBe(`{degrees}deg -> 75`)
					w.stop()
				end
			end,
		})

		verifyHarness:case("a press on a scrolled track reads the painted position", {
			id = "native_slider_shapes::native Slider rotation::a press on a scrolled track reads the painted position",
			run = function()
				local w = world({ rotation = 90, step = 25, value = Compose.cell(0) })
				w.track.AbsolutePosition = v(w, 40, -260)
				pressAt(w, 90, 0.25)
				expect((w.value:peek())):toBe(25)
				w.stop()
			end,
		})

		verifyHarness:case("a bound angle turns the paint live and the label and readout stay upright", {
			id = "native_slider_shapes::native Slider rotation::a bound angle turns the paint live and the label and readout stay upright",
			run = function()
				local angle = Compose.cell(0)
				local w = world({ rotation = angle, step = 25, label = "Tilt" })
				expect(w.track.Rotation):toBe(0)
				drag(w, w.track, v(w, 200, 22))
				expect((w.value:peek())):toBe(100)
				angle:set(180)
				expect(w.track.Rotation):toBe(180)
				expect(find(w.node, "Label").Rotation):toBe(0)
				expect(find(w.node, "Value").Rotation):toBe(0)
				drag(w, w.track, v(w, 150, 22))
				expect((w.value:peek())):toBe(25)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("native Slider range", function()
		verifyHarness:case("both handles are touch-floor targets and the fill spans between them", {
			id = "native_slider_shapes::native Slider range::both handles are touch-floor targets and the fill spans between them",
			run = function()
				local w = world({ range = true })
				local lower, upper, fill =
					find(w.track, "HandleLower"), find(w.track, "HandleUpper"), find(w.track, "Fill")
				expect(lower.Size.X.Offset >= 44 and lower.Size.Y.Offset >= 44):toBe(true)
				expect(upper.Size.X.Offset >= 44 and upper.Size.Y.Offset >= 44):toBe(true)
				expect(lower.Selectable or upper.Selectable):toBe(false)
				expect(w.track.Selectable):toBe(false)
				expect(w.node.Selectable):toBe(true)
				expect(fill.Position.X.Scale):toBeCloseTo(0.2, 1e-4)
				expect(fill.Size.X.Scale):toBeCloseTo(0.4, 1e-4)
				expect(lower.Position.X.Scale):toBeCloseTo(0.2, 1e-4)
				expect(upper.Position.X.Scale):toBeCloseTo(0.6, 1e-4)
				expect(find(w.node, "Value").Text):toBe("20 – 60")
				w.stop()
			end,
		})

		verifyHarness:case("a thumb stops at the other one, and minGap holds them apart", {
			id = "native_slider_shapes::native Slider range::a thumb stops at the other one, and minGap holds them apart",
			run = function()
				local w = world({ range = true, minGap = 10 })
				drag(w, find(w.track, "HandleLower"), v(w, 40, 22), { v(w, 200, 22) })
				expect((pair(w))):toBe("50/60")
				w.stop()
			end,
		})

		verifyHarness:case("an arrow a thumb cannot use against its partner keeps the ring on that thumb", {
			id = "native_slider_shapes::native Slider range::an arrow a thumb cannot use against its partner keeps the ring on that thumb",
			run = function()
				local w = world({ range = true, minGap = 10, value = Compose.cell({ lower = 50, upper = 60 }) })
				w.gui.SelectedObject = w.node
				local increase = action(w, "IncreaseArrow")
				expect(increase ~= nil):toBe(true)
				expect(increase.Parent.Sink):toBe(true)
				increase.Pressed.fire()
				expect(`{w.gui.SelectedObject == w.node} {w.node:GetAttribute("adjusting")} {w.value:peek().lower}`):toBe(
					"true lower 50"
				)
				w.stop()
			end,
		})

		verifyHarness:case(
			"a press left of a coincident pair takes the lower thumb, and a press right takes the upper",
			{
				id = "native_slider_shapes::native Slider range::a press left of a coincident pair takes the lower thumb, and a press right takes the upper",
				run = function()
					for _, case in { { at = 0.2, moves = "lower" }, { at = 0.8, moves = "upper" } } do
						local w = world({ range = true, step = 1, value = Compose.cell({ lower = 50, upper = 50 }) })
						drag(w, w.track, v(w, 200 * case.at, 22))
						local value = w.value:peek()
						local moved = if value.lower ~= 50 then "lower" else "upper"
						expect(`at {case.at} -> {moved}`):toBe(`at {case.at} -> {case.moves}`)
						w.stop()
					end
				end,
			}
		)

		verifyHarness:case("a drag keeps the thumb it started with, even dragged past the other one", {
			id = "native_slider_shapes::native Slider range::a drag keeps the thumb it started with, even dragged past the other one",
			run = function()
				local w = world({ range = true, minGap = 0 })
				drag(w, find(w.track, "HandleUpper"), v(w, 120, 22), { v(w, 0, 22) })
				expect((pair(w))):toBe("20/20")
				w.stop()
			end,
		})

		verifyHarness:case("one commit per completed gesture, and it names the thumb that moved", {
			id = "native_slider_shapes::native Slider range::one commit per completed gesture, and it names the thumb that moved",
			run = function()
				local changes = {}
				local value = Compose.cell({ lower = 20, upper = 60 })
				local w = world({
					range = true,
					step = 10,
					value = value,
					onChange = function(next: any, info: any)
						table.insert(changes, `{info.thumb}:{next.upper}`)
						value:set(next)
					end,
				})
				drag(
					w,
					find(w.track, "HandleUpper"),
					v(w, 117.6, 22),
					{ v(w, 135.2, 22), v(w, 152.8, 22), v(w, 170.4, 22) }
				)
				expect(#w.commits):toBe(1)
				expect(w.commits[1]):toBe("upper:20-90")
				expect((table.concat(changes, " "))):toBe("upper:70 upper:80 upper:90")
				w.stop()
			end,
		})

		verifyHarness:case(
			"keyboard and gamepad: the range is one stop and Return or A switches the handle the arrows move",
			{
				id = "native_slider_shapes::native Slider range::keyboard and gamepad: the range is one stop and Return or A switches the handle the arrows move",
				run = function()
					for _, preferred in { false, engineLib.new().types.Enum.PreferredInput.Gamepad } :: { any } do
						local w =
							world({ range = true, step = 5 }, if preferred then { preferred = preferred } else nil)
						w.gui.SelectedObject = w.node
						expect((press(w, "IncreaseArrow"))):toBe(true)
						expect((pair(w))):toBe("25/60")
						expect((press(w, "SwitchThumb"))):toBe(true)
						expect((press(w, "IncreaseArrow"))):toBe(true)
						expect((pair(w))):toBe("25/65")
						expect((bindings(w, "IncreaseArrow"))):toBe("DPadRight Right")
						expect((bindings(w, "SwitchThumb"))):toBe("ButtonA Return")
						w.stop()
					end
				end,
			}
		)

		verifyHarness:case("a range Slider has no pad Engage action", {
			id = "native_slider_shapes::native Slider range::a range Slider has no pad Engage action",
			run = function()
				local w = world(
					{ range = true, step = 5 },
					{ preferred = engineLib.new().types.Enum.PreferredInput.Gamepad }
				)
				w.gui.SelectedObject = w.node
				expect((action(w, "Engage"))):toBeNil()
				w.stop()
			end,
		})

		verifyHarness:case(
			"losing the input class mid-drag restores both numbers, and the later move and release commit nothing",
			{
				id = "native_slider_shapes::native Slider range::losing the input class mid-drag restores both numbers, and the later move and release commit nothing",
				run = function()
					local w = world({ range = true })
					local detector = find(w.track, "HandleLower"):FindFirstChildWhichIsA("UIDragDetector")
					detector.DragStart.fire(v(w, 40, 22))
					detector.DragContinue.fire(v(w, 0, 22))
					expect(w.value:peek().lower):toBe(0)
					w.input.PreferredInput = w.E.PreferredInput.Gamepad
					expect((pair(w))):toBe("20/60")
					detector.DragContinue.fire(v(w, 80, 22))
					detector.DragEnd.fire()
					expect(`{pair(w)} commits={#w.commits}`):toBe("20/60 commits=0")
					w.stop()
				end,
			}
		)

		verifyHarness:case("an authored pair the wrong way round is a spec error, not a silent swap", {
			id = "native_slider_shapes::native Slider range::an authored pair the wrong way round is a spec error, not a silent swap",
			run = function()
				local ok, err = pcall(world, { range = true, value = Compose.cell({ lower = 80, upper = 20 }) })
				expect(ok):toBe(false)
				expect(string.find(tostring(err), "is above", 1, true) ~= nil):toBe(true)
			end,
		})

		verifyHarness:case("an illegal pair arriving at run time keeps the last legal band and stays driveable", {
			id = "native_slider_shapes::native Slider range::an illegal pair arriving at run time keeps the last legal band and stays driveable",
			run = function()
				for _, bad in { { lower = 90, upper = 10 }, 5, false, { lower = 50, upper = 52 } } :: { any } do
					local w = world({ range = true, minGap = 10, step = 10 })
					w.value:set(bad)
					expect(find(w.track, "HandleLower").Position.X.Scale):toBeCloseTo(0.2, 1e-4)
					expect(find(w.track, "HandleUpper").Position.X.Scale):toBeCloseTo(0.6, 1e-4)
					expect(w.node:GetAttribute("diagnostics") ~= ""):toBe(true)
					expect(type(w.value:peek()) ~= "table" or w.value:peek().lower ~= 20):toBe(true)
					drag(w, find(w.track, "HandleLower"), v(w, 47.2, 22), { v(w, 64.8, 22) })
					expect((pair(w))):toBe("30/60")
					w.stop()
				end
				local ok = pcall(world, { range = true, minGap = 10, value = Compose.cell({ lower = 50, upper = 52 }) })
				expect(ok):toBe(false)
			end,
		})

		verifyHarness:case("an initial NaN, a bad type and a bad gap are build errors", {
			id = "native_slider_shapes::native Slider range::an initial NaN, a bad type and a bad gap are build errors",
			run = function()
				for _, spec in
					{
						{ range = true, value = Compose.cell({ lower = 0 / 0, upper = 10 }) },
						{ range = true, value = Compose.cell("wide") },
						{ range = true, minGap = -1 },
						{ range = true, minGap = 500 },
					} :: { any }
				do
					expect((pcall(world, spec))):toBe(false)
				end
				local w = world({ range = true })
				w.value:set({ lower = 0 / 0, upper = 10 })
				expect(find(w.track, "HandleLower").Position.X.Scale):toBeCloseTo(0.2, 1e-4)
				w.value:set({ lower = 10, upper = 30 })
				expect(find(w.track, "HandleLower").Position.X.Scale):toBeCloseTo(0.1, 1e-4)
				drag(w, find(w.track, "HandleUpper"), v(w, 60, 22), { v(w, 100, 22) })
				expect((pair(w))):toBe("10/50")
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("native Slider thumb modes and custom art", function()
		verifyHarness:case("thumb none paints no handle and leaves every route open", {
			id = "native_slider_shapes::native Slider thumb modes and custom art::thumb none paints no handle and leaves every route open",
			run = function()
				local w = world({ thumb = "none", step = 10 })
				expect(find(w.track, "Thumb").Visible):toBe(false)
				expect(find(w.node, "Value").Text):toBe("50")
				drag(w, w.track, v(w, 200, 22))
				expect((w.value:peek())):toBe(100)
				w.gui.SelectedObject = w.node
				press(w, "Decrease")
				press(w, "DecreaseArrow")
				expect((w.value:peek())):toBe(80)
				w.stop()
			end,
		})

		verifyHarness:case("thumb auto hides the handle at rest and shows it on focus, hover, drag and touch", {
			id = "native_slider_shapes::native Slider thumb modes and custom art::thumb auto hides the handle at rest and shows it on focus, hover, drag and touch",
			run = function()
				local w = world({ thumb = "auto" })
				local thumb = find(w.track, "Thumb")
				expect(thumb.Visible):toBe(false)
				w.gui.SelectedObject = w.node
				expect(thumb.Visible):toBe(true)
				w.gui.SelectedObject = nil
				expect(thumb.Visible):toBe(false)
				w.track.GuiState = w.E.GuiState.Hover
				expect(thumb.Visible):toBe(true)
				w.track.GuiState = w.E.GuiState.Idle
				expect(thumb.Visible):toBe(false)
				local detector = w.track:FindFirstChildWhichIsA("UIDragDetector")
				detector.DragStart.fire(v(w, 20, 22))
				expect(thumb.Visible):toBe(true)
				detector.DragEnd.fire()
				expect(thumb.Visible):toBe(false)
				w.stop()
				local touch = world({ thumb = "auto" }, { preferred = engineLib.new().types.Enum.PreferredInput.Touch })
				expect(find(touch.track, "Thumb").Visible):toBe(true)
				touch.stop()
			end,
		})

		verifyHarness:case("a custom knob is built once per thumb, is told its value and rides it", {
			id = "native_slider_shapes::native Slider thumb modes and custom art::a custom knob is built once per thumb, is told its value and rides it",
			run = function()
				local builds, info = 0, nil :: any
				local engine: any = engineLib.new()
				local w = world({
					step = 10,
					thumbContent = function(knob: any)
						builds += 1
						info = knob
						return engine.new("Frame")
					end,
				}, { engine = engine })
				expect(builds):toBe(1)
				expect(
					`{info.thumb}:{info.value:peek()}:{info.fraction:peek()}:{info.dragging:peek()}:{info.enabled:peek()}`
				):toBe("value:50:0.5:false:true")
				local thumb = find(w.track, "Thumb")
				local before = thumb.Position.X.Scale
				w.value:set(100)
				expect(builds):toBe(1)
				expect((info.value:peek())):toBe(100)
				expect(thumb.Position.X.Scale > before):toBe(true)
				local detector = w.track:FindFirstChildWhichIsA("UIDragDetector")
				detector.DragStart.fire(v(w, 20, 22))
				expect((info.dragging:peek())):toBe(true)
				detector.DragEnd.fire()
				expect((info.dragging:peek())):toBe(false)
				w.stop()
			end,
		})

		verifyHarness:case("a custom knob drops the theme slot and grows past the floor with its content", {
			id = "native_slider_shapes::native Slider thumb modes and custom art::a custom knob drops the theme slot and grows past the floor with its content",
			run = function()
				local engine: any = engineLib.new()
				local w = world({
					thumbContent = function()
						return engine.new("Frame")
					end,
				}, { engine = engine })
				local thumb = find(w.track, "Thumb")
				expect((thumb:HasTag("facet-slider-thumb"))):toBe(false)
				expect(thumb.AutomaticSize):toBe(w.E.AutomaticSize.XY)
				local floor = thumb:FindFirstChildWhichIsA("UISizeConstraint")
				expect(floor.MinSize.X):toBe(24)
				expect(find(thumb, "Knob") ~= nil):toBe(true)
				w.stop()
				local plain = world({})
				expect((find(plain.track, "Thumb"):HasTag("facet-slider-thumb"))):toBe(true)
				plain.stop()
			end,
		})

		verifyHarness:case("a knob is told its own thumb in a range, and each handle wears one", {
			id = "native_slider_shapes::native Slider thumb modes and custom art::a knob is told its own thumb in a range, and each handle wears one",
			run = function()
				local seen = {}
				local engine = engineLib.new()
				local w = world({
					range = true,
					thumbContent = function(info: any)
						table.insert(seen, `{info.thumb}:{info.value:peek()}`)
						return engine.new("Frame")
					end,
				}, { engine = engine })
				expect((table.concat(seen, " "))):toBe("lower:20 upper:60")
				expect(find(find(w.track, "HandleLower"), "Knob") ~= nil):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("a thumbImage beside a thumbContent names the collision, and so does a track pair", {
			id = "native_slider_shapes::native Slider thumb modes and custom art::a thumbImage beside a thumbContent names the collision, and so does a track pair",
			run = function()
				local ok, err = pcall(world, {
					thumbImage = "rbxassetid://1",
					thumbContent = function()
						return nil :: any
					end,
				})
				expect(ok):toBe(false)
				expect(string.find(tostring(err), "thumbImage", 1, true) ~= nil):toBe(true)
				local okTrack, errTrack = pcall(world, {
					trackImage = "rbxassetid://1",
					trackContent = function()
						return nil :: any
					end,
				})
				expect(okTrack):toBe(false)
				expect(string.find(tostring(errTrack), "trackContent", 1, true) ~= nil):toBe(true)
			end,
		})

		verifyHarness:case("a track content replaces the rail and the fill and fills the track", {
			id = "native_slider_shapes::native Slider thumb modes and custom art::a track content replaces the rail and the fill and fills the track",
			run = function()
				local builds = 0
				local engine: any = engineLib.new()
				local w = world({
					trackContent = function()
						builds += 1
						return engine.new("Frame")
					end,
				}, { engine = engine })
				expect(builds):toBe(1)
				expect((find(w.track, "Rail"))):toBeNil()
				expect((find(w.track, "Fill"))):toBeNil()
				local content = find(w.track, "TrackContent")
				expect(content.Size.X.Scale):toBe(1)
				expect(content.Size.Y.Scale):toBe(1)
				drag(w, w.track, v(w, 144, 22))
				expect((w.value:peek())):toBe(75)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("native Slider knob travel", function()
		local function span(node: any, extent: number): (number, number)
			local centre = node.Position.X.Scale * 200 + node.Position.X.Offset
			return centre - extent / 2, centre + extent / 2
		end

		verifyHarness:case(
			"the default knob stops flush with each end of the rail and the fill ends under its centre",
			{
				id = "native_slider_shapes::native Slider knob travel::the default knob stops flush with each end of the rail and the fill ends under its centre",
				run = function()
					local w = world({ value = Compose.cell(0) })
					local thumb, fill = find(w.track, "ThumbStop"), find(w.track, "Fill")
					local left = span(thumb, 24)
					expect(left):toBeCloseTo(0, 1e-4)
					expect(fill.Size.X.Scale * 200 + fill.Size.X.Offset):toBeCloseTo(12, 1e-4)
					w.value:set(100)
					local _, right = span(thumb, 24)
					expect(right):toBeCloseTo(200, 1e-4)
					expect(fill.Size.X.Scale * 200 + fill.Size.X.Offset):toBeCloseTo(188, 1e-4)
					drag(w, w.track, v(w, 100, 22))
					expect((w.value:peek())):toBeCloseTo(50, 1e-4)
					drag(w, w.track, v(w, 12, 22))
					expect((w.value:peek())):toBeCloseTo(0, 1e-4)
					w.stop()
				end,
			}
		)

		verifyHarness:case("each range handle travels by the size of its own art", {
			id = "native_slider_shapes::native Slider knob travel::each range handle travels by the size of its own art",
			run = function()
				local sides = { lower = 12, upper = 40 }
				local engine = engineLib.new()
				local w = world({
					range = true,
					value = Compose.cell({ lower = 0, upper = 100 }),
					thumbContent = function(info: any)
						local art = engine.new("Frame")
						local side = sides[info.thumb]
						art.Name = "Art_" .. info.thumb
						art.AbsoluteSize = engine.types.Vector2.new(side, side)
						return art
					end,
				}, { engine = engine })
				local lower, upper = find(w.track, "HandleLower"), find(w.track, "HandleUpper")
				local lowerLeft = span(lower, sides.lower)
				local _, upperRight = span(upper, sides.upper)
				expect(lowerLeft):toBeCloseTo(0, 1e-4)
				expect(upperRight):toBeCloseTo(200, 1e-4)
				local fill = find(w.track, "Fill")
				local fillLeft = fill.Position.X.Scale * 200 + fill.Position.X.Offset
				expect(fillLeft):toBeCloseTo(6, 1e-4)
				expect(fillLeft + fill.Size.X.Scale * 200 + fill.Size.X.Offset):toBeCloseTo(180, 1e-4)
				drag(w, upper, v(w, 180, 22), { v(w, 20 + 80, 22) })
				expect(w.value:peek().upper):toBeCloseTo(50, 1e-4)
				drag(w, lower, v(w, 6, 22), { v(w, 6 + 188 * 0.25, 22) })
				expect(w.value:peek().lower):toBeCloseTo(25, 1e-4)
				w.stop()
			end,
		})

		verifyHarness:case("a vertical and a rotated knob stop flush with the rail ends", {
			id = "native_slider_shapes::native Slider knob travel::a vertical and a rotated knob stop flush with the rail ends",
			run = function()
				local w = world({ axis = "y" :: "y", value = Compose.cell(0) })
				local thumb = find(w.track, "ThumbStop")
				local function centre(): number
					return thumb.Position.Y.Scale * 200 + thumb.Position.Y.Offset
				end
				expect(centre() + 12):toBeCloseTo(200, 1e-4)
				w.value:set(100)
				expect(centre() - 12):toBeCloseTo(0, 1e-4)
				drag(w, w.track, v(w, 22, 100))
				expect((w.value:peek())):toBeCloseTo(50, 1e-4)
				w.stop()
				local turned = world({ rotation = 90, value = Compose.cell(50) })
				drag(turned, turned.track, v(turned, 100, 22 + 88))
				expect((turned.value:peek())):toBeCloseTo(100, 1e-4)
				local _, right = span(find(turned.track, "ThumbStop"), 24)
				expect(right):toBeCloseTo(200, 1e-4)
				turned.stop()
			end,
		})
	end)

	verifyHarness:suite("native Slider controlSize", function()
		verifyHarness:case("a named rung paints a thinner track inside the whole target", {
			id = "native_slider_shapes::native Slider controlSize::a named rung paints a thinner track inside the whole target",
			run = function()
				local regular, compact = world({}), world({ controlSize = "compact" :: "compact" })
				local thin, normal = find(compact.track, "Rail"), find(regular.track, "Rail")
				expect(thin.Size.Y.Offset < normal.Size.Y.Offset):toBe(true)
				expect(compact.track.Size.Y.Offset):toBe(44)
				expect(find(compact.track, "Fill").Size.Y.Offset):toBe(thin.Size.Y.Offset)
				regular.stop()
				compact.stop()
			end,
		})

		verifyHarness:case("a rung thins a vertical track and the column keeps its travel", {
			id = "native_slider_shapes::native Slider controlSize::a rung thins a vertical track and the column keeps its travel",
			run = function()
				local w = world({ axis = "y" :: "y", controlSize = "compact" :: "compact" })
				local rail = find(w.track, "Rail")
				expect(rail.Size.X.Offset):toBe(4)
				expect(rail.Size.Y.Scale):toBe(1)
				expect(w.track.Size.Y.Scale):toBe(1)
				w.stop()
			end,
		})

		verifyHarness:case("building, driving and disposing a shaped slider leaves no connection behind", {
			id = "native_slider_shapes::native Slider controlSize::building, driving and disposing a shaped slider leaves no connection behind",
			run = function()
				local engine: any = engineLib.new()
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local UI: any = {}
				register(context(Compose, runtime, { types = engine.types }), UI)
				local before = engine.census()
				local value = Compose.cell({ lower = 10, upper = 90 })
				local stop = runtime.mount(function()
					return UI.Slider("Band")({
						value = value,
						min = 0,
						max = 100,
						range = true,
						minGap = 5,
						thumb = "auto",
						rotation = 45,
						thumbContent = function()
							return engine.new("Frame")
						end,
					})
				end, engine.new("ScreenGui"))
				value:set({ lower = 20, upper = 80 })
				stop()
				local after = engine.census()
				expect(after.connections):toBe(before.connections)
				runtime:dispose()
			end,
		})
	end)
end
