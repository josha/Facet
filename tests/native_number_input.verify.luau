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

	local function find(root: any, path: string): any
		local at = root
		for name in string.gmatch(path, "[^/]+") do
			if at == nil then
				return nil
			end
			local found = nil
			for _, child in at:GetChildren() do
				if child.Name == name then
					found = child
					break
				end
			end
			at = found
		end
		return at
	end

	local function numberWorld(spec: any?): any
		local o = spec or {}
		local engine: any = engineLib.new()
		local runtime: ComposeRuntime = Roblox.createRuntime(engine)
		local UI: any = {}
		local gui, input = engine.new("GuiService"), engine.new("UserInputService")
		input.PreferredInput = engine.types.Enum.PreferredInput.KeyboardAndMouse
		local ctx = context(Compose, runtime, {
			types = engine.types,
			services = { GuiService = gui, UserInputService = input },
			guiService = gui,
		})
		register(ctx, UI)
		local w: any = {
			engine = engine,
			runtime = runtime,
			input = input,
			E = engine.types.Enum,
			draft = Compose.cell(o.draft or "3"),
			number = Compose.cell(o.number or 3),
			commits = {},
			changes = {},
			visible = Compose.cell(true),
		}
		local merged: any = {
			value = w.draft,
			numericValue = w.number,
			onCommit = function(value: any, reason: string)
				table.insert(w.commits, { value = value, reason = reason })
			end,
			onChange = function(text: string)
				table.insert(w.changes, text)
				w.draft:set(text)
			end,
		}
		for key, entry in o do
			if key ~= "draft" and key ~= "number" then
				merged[key] = entry
			end
		end
		local screen = engine.new("ScreenGui")
		w.screen = screen
		w.stop = runtime.mount(function()
			return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
				Name = "Host",
				Compose.show(w.visible, function()
					return UI.NumberInput("Laps")(merged)
				end),
			})
		end, screen)
		w.node = find(screen, "Host/Laps")
		w.field = if w.node.ClassName == "TextBox" then w.node else find(w.node, "Input/Field")
		return w
	end

	local function editAndCommit(w: any, text: string)
		w.field:CaptureFocus()
		w.field.Text = text
		w.field:ReleaseFocus(true)
	end

	local function press(w: any, name: string)
		find(w.node, "Input/" .. name).Activated:Fire()
	end

	verifyHarness:suite("native NumberInput preset", function()
		verifyHarness:case("step must be finite and above zero, precision a whole count of places, units strings", {
			id = "native_number_input::native NumberInput preset::step must be finite and above zero, precision a whole count of places, units strings",
			run = function()
				for _, bad in
					{
						{ step = 0 },
						{ step = -1 },
						{ step = math.huge },
						{ precision = 1.5 },
						{ precision = 11 },
						{ prefix = 4 },
						{ scrub = "yes" },
					} :: { any }
				do
					local ok = pcall(numberWorld, bad)
					expect(ok):toBe(false)
				end
				local engine: any = engineLib.new()
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local UI: any = {}
				register(context(Compose, runtime, { types = engine.types }), UI)
				for _, key in { "stepButtons", "step", "precision", "prefix", "suffix", "scrub" } do
					local ok = pcall(function()
						local stop = runtime.mount(function()
							local spec: any = { value = Compose.cell("") }
							spec[key] = if key == "stepButtons" or key == "scrub"
								then true
								elseif key == "prefix" or key == "suffix" then "$"
								else 1
							return UI.TextInput("T")(spec)
						end, engine.new("ScreenGui"))
						stop()
					end)
					expect(`{key}: {ok}`):toBe(`{key}: false`)
				end
			end,
		})
	end)

	verifyHarness:suite("native NumberInput commit", function()
		verifyHarness:case("a commit reports the number first, and the string is only how it is written", {
			id = "native_number_input::native NumberInput commit::a commit reports the number first, and the string is only how it is written",
			run = function()
				local w = numberWorld({ draft = "", number = 0 })
				editAndCommit(w, "12")
				expect(#w.commits):toBe(1)
				expect(`{w.commits[1].value} {typeof(w.commits[1].value)} {w.commits[1].reason}`):toBe(
					"12 number submit"
				)
				expect((w.number:peek())):toBe(12)
				w.field:CaptureFocus()
				w.field.Text = "13"
				w.field:ReleaseFocus(false)
				expect(`{w.commits[2].value} {w.commits[2].reason}`):toBe("13 focusLost")
				w.stop()
			end,
		})

		verifyHarness:case("precision rounds half away from zero, at commit and never while typing", {
			id = "native_number_input::native NumberInput commit::precision rounds half away from zero, at commit and never while typing",
			run = function()
				local w = numberWorld({ draft = "", number = 0, precision = 1 })
				w.field:CaptureFocus()
				w.field.Text = "0.15"
				expect((w.draft:peek())):toBe("0.15")
				w.field:ReleaseFocus(true)
				expect(`{w.number:peek()} {w.draft:peek()}`):toBe("0.2 0.2")
				w.stop()
				local negative = numberWorld({ draft = "", number = 0, precision = 1 })
				editAndCommit(negative, "-0.15")
				expect((negative.number:peek())):toBe(-0.2)
				negative.stop()
				local huge = numberWorld({ draft = "", number = 0, precision = 10 })
				editAndCommit(huge, "1" .. string.rep("0", 300))
				expect(`{huge.number:peek() == 1e300} {#huge.commits}`):toBe("true 1")
				huge.stop()
			end,
		})

		verifyHarness:case("a callback that disposes the control mid-commit leaves nothing half-written", {
			id = "native_number_input::native NumberInput commit::a callback that disposes the control mid-commit leaves nothing half-written",
			run = function()
				for _, callback in { "parse", "format" } do
					local holder: any = {}
					local spec: any = {}
					spec[callback] = function(input: any)
						holder.w.visible:set(false)
						return if callback == "parse" then tonumber(input) else tostring(input)
					end
					local w = numberWorld(spec)
					holder.w = w
					local field = w.field
					field:CaptureFocus()
					field.Text = "2"
					field:ReleaseFocus(true)
					expect(`{callback}: {w.number:peek()} {#w.commits}`):toBe(`{callback}: 3 0`)
					expect((field:isDestroyed())):toBe(true)
					w.stop()
				end
			end,
		})
	end)

	verifyHarness:suite("native NumberInput units and step buttons", function()
		verifyHarness:case("a prefix and a suffix stand beside the editor and never enter the draft", {
			id = "native_number_input::native NumberInput units and step buttons::a prefix and a suffix stand beside the editor and never enter the draft",
			run = function()
				local w = numberWorld({ draft = "", number = 0, prefix = "$", suffix = "/lap" })
				local prefix, suffix, field = find(w.node, "Input/Prefix"), find(w.node, "Input/Suffix"), w.field
				expect(prefix.Text):toBe("$")
				expect(suffix.Text):toBe("/lap")
				expect(prefix.LayoutOrder < field.LayoutOrder):toBe(true)
				expect(suffix.LayoutOrder > field.LayoutOrder):toBe(true)
				w.field:CaptureFocus()
				w.field.Text = "12"
				expect((w.draft:peek())):toBe("12")
				w.stop()
			end,
		})

		verifyHarness:case("a step button moves the value by one step and commits with submit", {
			id = "native_number_input::native NumberInput units and step buttons::a step button moves the value by one step and commits with submit",
			run = function()
				local w = numberWorld({ draft = "4", number = 4, stepButtons = true, step = 2, min = 0, max = 20 })
				press(w, "Increment")
				expect(`{w.number:peek()} {w.draft:peek()}`):toBe("6 6")
				local last = w.commits[#w.commits]
				expect(`{last.value} {last.reason} {w.changes[#w.changes]}`):toBe("6 submit 6")
				press(w, "Decrement")
				expect((w.number:peek())):toBe(4)
				expect((find(w.node, "Input/Increment"):HasTag("facet-stepper-button"))):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case(
			"a held step button repeats after 0.4 seconds, then every 0.1 seconds, with no idle frame work",
			{
				id = "native_number_input::native NumberInput units and step buttons::a held step button repeats after 0.4 seconds, then every 0.1 seconds, with no idle frame work",
				run = function()
					local w = numberWorld({ draft = "0", number = 0, stepButtons = true, step = 1, min = 0, max = 20 })
					local button = find(w.node, "Input/Increment")
					local held = { UserInputType = w.E.UserInputType.MouseButton1, KeyCode = w.E.KeyCode:FromValue(0) }
					expect((engineLib.connections(w.engine.heartbeat))):toBe(0)
					button.InputBegan:Fire(held)
					w.engine.heartbeat:Fire(0.4)
					w.engine.heartbeat:Fire(0.1)
					expect((w.number:peek())):toBe(2)
					button.InputEnded:Fire(held)
					expect((engineLib.connections(w.engine.heartbeat))):toBe(0)
					w.stop()
				end,
			}
		)

		verifyHarness:case("a press goes through the typed path's rounding and clamping, bounded or not", {
			id = "native_number_input::native NumberInput units and step buttons::a press goes through the typed path's rounding and clamping, bounded or not",
			run = function()
				local open = numberWorld({ draft = "0.1", number = 0.1, stepButtons = true, step = 0.2, precision = 1 })
				press(open, "Increment")
				expect(`{open.number:peek() == 0.3} {open.draft:peek()}`):toBe("true 0.3")
				editAndCommit(open, "0.25")
				expect(open.number:peek() == 0.3):toBe(true)
				open.stop()
				local bounded = numberWorld({
					draft = "0.8",
					number = 0.8,
					stepButtons = true,
					step = 0.2,
					min = 0,
					max = 1,
					precision = 1,
				})
				press(bounded, "Increment")
				expect(`{bounded.number:peek() == 1} {bounded.draft:peek()}`):toBe("true 1.0")
				expect(find(bounded.node, "Input/Increment").Interactable):toBe(false)
				bounded.stop()
			end,
		})

		verifyHarness:case("without a precision, presses land on the step's own places, never on float noise", {
			id = "native_number_input::native NumberInput units and step buttons::without a precision, presses land on the step's own places, never on float noise",
			run = function()
				for _, bounds in { { min = 0, max = 1 }, {} :: any } do
					local w = numberWorld({
						draft = "0",
						number = 0,
						stepButtons = true,
						step = 0.1,
						min = bounds.min,
						max = bounds.max,
					})
					for _ = 1, 3 do
						press(w, "Increment")
					end
					expect(`{w.number:peek() == 0.3} {w.draft:peek()} {w.commits[3].value == 0.3}`):toBe(
						"true 0.3 true"
					)
					w.stop()
				end
			end,
		})

		verifyHarness:case("at the end of its range, read-only or disabled, the button says so and refuses", {
			id = "native_number_input::native NumberInput units and step buttons::at the end of its range, read-only or disabled, the button says so and refuses",
			run = function()
				local cases = {
					{ name = "at max", spec = { draft = "20", number = 20 }, path = "Increment" },
					{ name = "at min", spec = { draft = "0", number = 0 }, path = "Decrement" },
					{ name = "read-only", spec = { draft = "8", number = 8, readOnly = true }, path = "Increment" },
					{ name = "disabled", spec = { draft = "8", number = 8, enabled = false }, path = "Increment" },
				}
				for _, case in cases do
					local spec: any = { stepButtons = true, step = 5, min = 0, max = 20 }
					for key, entry in case.spec do
						spec[key] = entry
					end
					local w = numberWorld(spec)
					local before = w.number:peek()
					local button = find(w.node, "Input/" .. case.path)
					expect(`{case.name}: {button.Interactable}`):toBe(`{case.name}: false`)
					button.Activated:Fire()
					expect(`{case.name}: {w.number:peek()} {#w.commits}`):toBe(`{case.name}: {before} 0`)
					w.stop()
				end
				local low = numberWorld({ draft = "0", number = 0, stepButtons = true, step = 5, min = 0, max = 20 })
				expect(find(low.node, "Input/Increment").Interactable):toBe(true)
				low.stop()
			end,
		})

		verifyHarness:case("closing the screen releases the numeric field and its buttons", {
			id = "native_number_input::native NumberInput units and step buttons::closing the screen releases the numeric field and its buttons",
			run = function()
				local w =
					numberWorld({ stepButtons = true, prefix = "$", min = 0, max = 9, label = "Fee", hint = "Per lap" })
				w.stop()
				expect(#w.screen:GetChildren()):toBe(0)
				expect((w.field:isDestroyed())):toBe(true)
			end,
		})
	end)

	verifyHarness:suite("native NumberInput scrub", function()
		local function scrubWorld(extra: any?): any
			local spec: any = { draft = "10", number = 10, scrub = true, min = 0, max = 20 }
			for key, entry in extra or {} do
				spec[key] = entry
			end
			local w = numberWorld(spec)
			w.field:CaptureFocus()
			return w
		end
		local function down(w: any, x: number)
			local mouse =
				{ UserInputType = w.E.UserInputType.MouseButton1, Position = w.engine.types.Vector3.new(x, 10, 0) }
			w.mouse = mouse
			w.field.InputBegan:Fire(mouse)
		end
		local function move(w: any, dx: number, dy: number?)
			w.input.InputChanged:Fire({
				UserInputType = w.E.UserInputType.MouseMovement,
				Position = w.engine.types.Vector3.new(100 + dx, 10 + (dy or 0), 0),
			})
		end
		local function up(w: any)
			w.input.InputEnded:Fire(w.mouse)
		end

		verifyHarness:case("a press that never promotes leaves the native tap and typing alone", {
			id = "native_number_input::native NumberInput scrub::a press that never promotes leaves the native tap and typing alone",
			run = function()
				local w = scrubWorld()
				down(w, 100)
				move(w, 4, 3)
				up(w)
				expect((w.field:IsFocused())):toBe(true)
				w.field.Text = "105"
				w.field:ReleaseFocus(true)
				expect(`{w.number:peek()} {#w.commits} {w.commits[1].value}`):toBe("20 1 20")
				expect((engineLib.connections(w.input.InputChanged))):toBe(0)
				w.stop()
			end,
		})

		verifyHarness:case("travel moves whole steps of the total, clamps, reports live and commits once at release", {
			id = "native_number_input::native NumberInput scrub::travel moves whole steps of the total, clamps, reports live and commits once at release",
			run = function()
				local w = scrubWorld({ step = 0.5, precision = 1 })
				down(w, 100)
				move(w, 17, 2)
				expect((w.field:IsFocused())):toBe(false)
				expect(#w.commits):toBe(0)
				expect(`{w.number:peek()} {w.draft:peek()}`):toBe("11 11.0")
				move(w, -40)
				expect((w.number:peek())):toBe(7.5)
				move(w, 1000)
				expect(`{w.number:peek()} {table.concat(w.changes, ",")}`):toBe("20 11.0,7.5,20.0")
				up(w)
				expect(`{#w.commits} {w.commits[1].value} {w.commits[1].reason}`):toBe("1 20 submit")
				w.stop()
			end,
		})

		verifyHarness:case("a scrub over a typed draft starts from the committed number and discards the draft", {
			id = "native_number_input::native NumberInput scrub::a scrub over a typed draft starts from the committed number and discards the draft",
			run = function()
				for _, finish in { "end", "cancel" } do
					local w = scrubWorld()
					w.field.Text = "42"
					expect((w.draft:peek())):toBe("42")
					down(w, 100)
					move(w, 8)
					expect(`{finish} begin: {w.number:peek()} {w.draft:peek()}`):toBe(`{finish} begin: 11 11`)
					move(w, 16)
					if finish == "end" then
						up(w)
					else
						w.input.InputBegan:Fire({
							KeyCode = w.E.KeyCode.Escape,
							UserInputType = w.E.UserInputType.Keyboard,
						})
					end
					local want = if finish == "end" then "12 12 1" else "10 10 0"
					expect(`{finish}: {w.number:peek()} {w.draft:peek()} {#w.commits}`):toBe(`{finish}: {want}`)
					w.stop()
				end
			end,
		})

		verifyHarness:case(
			"cancel, class loss, disable, readOnly and scrub off restore the snapshot without a commit",
			{
				id = "native_number_input::native NumberInput scrub::cancel, class loss, disable, readOnly and scrub off restore the snapshot without a commit",
				run = function()
					for _, how in { "cancel", "class", "disabled", "readOnly", "off" } do
						local lock = Compose.cell(false)
						local on = Compose.cell(true)
						local w = scrubWorld({
							disabled = if how == "disabled" then lock else nil,
							readOnly = if how == "readOnly" then lock else nil,
							scrub = on,
						})
						down(w, 100)
						move(w, 24)
						expect(`{how} moved {w.number:peek()}`):toBe(`{how} moved 13`)
						if how == "cancel" then
							w.input.InputBegan:Fire({
								KeyCode = w.E.KeyCode.ButtonB,
								UserInputType = w.E.UserInputType.Gamepad1,
							})
						elseif how == "class" then
							w.input.PreferredInput = w.E.PreferredInput.Gamepad
						elseif how == "off" then
							on:set(false)
						else
							lock:set(true)
						end
						move(w, 40)
						up(w)
						expect(`{how} {w.number:peek()} {w.draft:peek()} {#w.commits}`):toBe(`{how} 10 10 0`)
						w.stop()
					end
				end,
			}
		)

		verifyHarness:case("disposal mid-gesture restores the snapshot; an unscrubbable field adds no listener", {
			id = "native_number_input::native NumberInput scrub::disposal mid-gesture restores the snapshot; an unscrubbable field adds no listener",
			run = function()
				local w = scrubWorld()
				down(w, 100)
				move(w, 16)
				expect((w.number:peek())):toBe(12)
				w.visible:set(false)
				expect(`{w.number:peek()} {w.draft:peek()}`):toBe("10 10")
				expect((engineLib.connections(w.input.InputChanged))):toBe(0)
				w.stop()
				local plain = scrubWorld({ scrub = false })
				down(plain, 100)
				move(plain, 40)
				expect(`{plain.number:peek()} {plain.field:IsFocused()}`):toBe("10 true")
				expect((engineLib.connections(plain.input.InputChanged))):toBe(0)
				plain.stop()
				local none = numberWorld()
				none.field.InputBegan:Fire({
					UserInputType = none.E.UserInputType.MouseButton1,
					Position = none.engine.types.Vector3.new(1, 1, 0),
				})
				expect((engineLib.connections(none.input.InputEnded))):toBe(0)
				none.stop()
			end,
		})
	end)
end
