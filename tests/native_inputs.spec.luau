--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type FrameConstructor = typeof(require("@repo/tools/typecheck/aliases").FrameConstructor)
	type MotionLevel = typeof(require("@repo/tools/typecheck/aliases").MotionLevel)
	type TextButtonConstructor = typeof(require("@repo/tools/typecheck/aliases").TextButtonConstructor)
	local FixtureEngineTypes = require("../src/ui/engine_types")
	local requireDynamic = require :: (any) -> any
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T
	local SharedTypes = require("../src/ui/control_types")

	local Compose = require("../src/vendor/compose/core")
	local Roblox = require("../src/vendor/compose/roblox")
	local context = require("../src/ui/context")
	local register = require("../src/ui/inputs")
	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")

	local function world(build: (SharedTypes.Controls, any, Compose.Runtime) -> unknown, configure: ((any) -> any)?)
		local engine = engineLib.new()
		local runtime: ComposeRuntime = Roblox.createRuntime(engine)
		local UI = ({} :: unknown) :: SharedTypes.Controls
		local options: SharedTypes.Config = if configure then configure(engine) else {}
		options.types = engine.types
		local ctx = context(Compose, runtime, options)
		register(ctx, UI)
		local stop, node: any = runtime.mount(function()
			return build(UI, engine, runtime)
		end, engine.new("ScreenGui"))
		return node, stop, engine, runtime, ctx
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

	local function enabledAction(root, name)
		for _, child in root:GetChildren() do
			if child:IsA("InputContext") and child.Enabled then
				local action = child:FindFirstChild(name)
				if action then
					return action
				end
			end
		end
		return nil
	end

	verifyHarness:suite("native input controls", function()
		verifyHarness:case("keeps the checkbox image asset through activation and theme changes", {
			id = "native_inputs::native input controls::keeps the checkbox image asset through activation and theme changes",
			run = function()
				local value = Compose.cell(false)
				local theme = Compose.cell(Facet.themes.neutralPackage())
				local node, stop = world(function(UI: FacetControls)
					return UI.Toggle { label = "Club", presentation = "checkbox" :: "checkbox", value = value }
				end, function()
					return { theme = theme }
				end)
				local mark = find(node, "Check")
				Verify.expect(mark.Image):toBe(Facet.themes.resolveIcon(theme:peek(), "checkmark"))
				node.Activated:Fire()
				Verify.expect(value:peek()):toBe(true)
				Verify.expect(mark.Visible):toBe(true)
				for _, name in { "glossy_mobile", "fantasy_parchment", "scifi_hud" } do
					theme:set(requireDynamic("../examples/themes/" .. name).build(Facet.themes))
					Verify.expect(mark.Image):toBe(Facet.themes.resolveIcon(theme:peek(), "checkmark"))
					Verify.expect(mark.Image ~= ""):toBe(true)
					node.Activated:Fire()
					node.Activated:Fire()
					Verify.expect(mark.Visible):toBe(true)
				end
				stop()
			end,
		})

		verifyHarness:case("finishes an activation that removes its own Button without reading released state", {
			id = "native_inputs::native input controls::finishes an activation that removes its own Button without reading released state",
			run = function()
				local shown = Compose.cell(true)
				local presses = 0
				local node, stop = world(function(UI: FacetControls, _engine, runtime)
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
						Compose.show(shown, function()
							local allowed = Compose.formula(function(use: Use)
								return use(shown)
							end)
							return UI.Button "Dismiss" {
								label = "Dismiss",
								enabled = allowed,
								onActivate = function()
									presses += 1
									shown:set(false)
								end,
							}
						end),
					})
				end)
				local button = find(node, "Dismiss")
				button.Activated:Fire()
				Verify.expect(presses):toBe(1)
				Verify.expect((find(node, "Dismiss"))):toBe(nil)
				stop()
			end,
		})

		verifyHarness:case("uses native properties and events and releases them with its Compose owner", {
			id = "native_inputs::native input controls::uses native properties and events and releases them with its Compose owner",
			run = function()
				local value, enabled = Compose.cell("Before"), Compose.cell(true)
				local activated, nativeEvent = 0, 0
				local node, stop = world(function(UI: FacetControls)
					return UI.Button("Continue")({
						label = value,
						enabled = enabled,
						Attributes = { task = "continue" } :: FixtureEngineTypes.Attributes,
						onActivate = function()
							activated += 1
						end,
						[Compose.event("MouseEnter")] = function()
							nativeEvent += 1
						end,
					})
				end)
				Verify.expect(node.Text):toBe("Before")
				Verify.expect((node:GetAttribute("task"))):toBe("continue")
				value:set("After")
				Verify.expect(node.Text):toBe("After")
				Verify.expect((find(node, "Label"))):toBe(nil)
				node.Text = "Native text"
				Verify.expect(node.Text):toBe("Native text")
				node.Activated:Fire()
				node.MouseEnter:Fire()
				enabled:set(false)
				node.Activated:Fire()
				Verify.expect(activated):toBe(1)
				Verify.expect(nativeEvent):toBe(1)
				Verify.expect(node.Interactable):toBe(false)
				stop()
				Verify.expect((engineLib.connections(node.Activated))):toBe(0)
				Verify.expect((engineLib.connections(node.MouseEnter))):toBe(0)
			end,
		})

		verifyHarness:case("keeps Toggle requests controlled and clears a writable mixed state", {
			id = "native_inputs::native input controls::keeps Toggle requests controlled and clears a writable mixed state",
			run = function()
				local value, mixed = Compose.cell(false), Compose.cell(true)
				local node, stop = world(function(UI: FacetControls)
					return UI.Toggle({
						value = value,
						mixed = mixed,
						presentation = "checkbox" :: "checkbox",
						label = "Enabled",
					})
				end)
				node.Activated:Fire()
				Verify.expect((value:peek())):toBe(true)
				Verify.expect((mixed:peek())):toBe(false)
				stop()
				local request
				node, stop = world(function(UI: FacetControls)
					return UI.Toggle({
						value = value,
						label = "Controlled",
						onChange = function(nextValue)
							request = nextValue
						end,
					})
				end)
				node.Activated:Fire()
				Verify.expect(request):toBe(false)
				Verify.expect((value:peek())):toBe(true)
				stop()
			end,
		})

		verifyHarness:case(
			"keeps Toggle native eligibility semantics and theme tags synchronized with one ref delivery",
			{
				id = "native_inputs::native input controls::keeps Toggle native eligibility semantics and theme tags synchronized with one ref delivery",
				run = function()
					local value, enabled, busy = Compose.cell(true), Compose.cell(true), Compose.cell(false)
					local role, appearance, size, name =
						Compose.cell("default" :: "cancel" | "default" | "destructive" | "onIndicator"),
						Compose.cell("standard"),
						Compose.cell("regular" :: "compact" | "large" | "regular" | "xsmall"),
						Compose.cell("Ready")
					local references, changes = 0, 0
					local node, stop, engine = world(function(UI: FacetControls)
						return UI.Toggle({
							value = value,
							enabled = enabled,
							busy = busy,
							role = role,
							appearance = appearance,
							controlSize = size,
							name = name,
							ref = function()
								references += 1
							end,
							onChange = function(nextValue)
								changes += 1
								value:set(nextValue)
							end,
						})
					end)
					Verify.expect(references):toBe(1)
					Verify.expect((node:GetAttribute("selected"))):toBe(true)
					Verify.expect((node:HasTag("facet-selected"))):toBe(true)
					role:set("destructive")
					appearance:set("emphasis")
					size:set("large")
					name:set("Confirm")
					Verify.expect((node:HasTag("facet-role-default"))):toBe(false)
					Verify.expect((node:HasTag("facet-role-destructive"))):toBe(true)
					Verify.expect((node:HasTag("facet-accent"))):toBe(true)
					Verify.expect((node:GetAttribute("role"))):toBe("destructive")
					Verify.expect((node:GetAttribute("appearance"))):toBe("emphasis")
					Verify.expect((node:GetAttribute("controlSize"))):toBe("large")
					Verify.expect((node:GetAttribute("label"))):toBe("Confirm")
					busy:set(true)
					Verify.expect(node.Interactable):toBe(false)
					Verify.expect((node:HasTag("facet-busy"))):toBe(true)
					Verify.expect((node:HasTag("facet-disabled"))):toBe(true)
					node.Activated:Fire()
					Verify.expect(changes):toBe(0)
					busy:set(false)
					node.Activated:Fire()
					Verify.expect(changes):toBe(1)
					Verify.expect((node:GetAttribute("selected"))):toBe(false)
					Verify.expect((node:HasTag("facet-selected"))):toBe(false)
					for _ = 1, 60 do
						engine.heartbeat:Fire(1 / 60)
					end
					Verify.expect(find(node, "Mark").Position.X.Scale):toBeCloseTo(0.3, 1e-4)
					enabled:set(false)
					Verify.expect(node.Selectable):toBe(false)
					node.Activated:Fire()
					Verify.expect(changes):toBe(1)
					stop()
				end,
			}
		)

		verifyHarness:case("distinguishes edits from external model updates and disconnects observation", {
			id = "native_inputs::native input controls::distinguishes edits from external model updates and disconnects observation",
			run = function()
				local value = Compose.cell("First")
				local edits, commits = {}, {}
				local node, stop = world(function(UI: FacetControls)
					return UI.TextInput({
						value = value,
						onChange = function(text)
							value:set(text)
							table.insert(edits, text)
						end,
						onCommit = function(text: string, reason: "focusLost" | "submit")
							table.insert(commits, { text, reason })
						end,
					})
				end)
				value:set("External")
				Verify.expect(node.Text):toBe("External")
				Verify.expect(#edits):toBe(0)
				node:CaptureFocus()
				node.Text = "User"
				Verify.expect((value:peek())):toBe("User")
				Verify.expect(#edits):toBe(1)
				value:set("Model while focused")
				Verify.expect(node.Text):toBe("Model while focused")
				Verify.expect(#edits):toBe(1)
				node:ReleaseFocus(true)
				Verify.expect(commits[1][1]):toBe("Model while focused")
				Verify.expect(commits[1][2]):toBe("submit")
				stop()
				Verify.expect((engineLib.connections(node:GetPropertyChangedSignal("Text")))):toBe(0)
			end,
		})

		verifyHarness:case("limits UTF-8 characters, rejects validation and restores an edit on cancel", {
			id = "native_inputs::native input controls::limits UTF-8 characters, rejects validation and restores an edit on cancel",
			run = function()
				local value, edits, canceled = Compose.cell("old"), 0, 0
				local node, stop = world(function(UI: FacetControls)
					return UI.TextInput({
						value = value,
						maxLength = 3,
						validate = function(text)
							return if text == "bad" then nil else text
						end,
						onChange = function(text)
							value:set(text)
							edits += 1
						end,
						onCancel = function()
							canceled += 1
						end,
					})
				end)
				node:CaptureFocus()
				node.Text = "é🙂好x"
				Verify.expect((value:peek())):toBe("é🙂好")
				Verify.expect(node.Text):toBe("é🙂好")
				node.Text = "bad"
				Verify.expect((value:peek())):toBe("é🙂好")
				Verify.expect(node.Text):toBe("é🙂好")
				Verify.expect(edits):toBe(1)
				find(node.Parent, "Cancel").Pressed:Fire()
				Verify.expect((value:peek())):toBe("old")
				Verify.expect(node.Text):toBe("old")
				Verify.expect(canceled):toBe(1)
				Verify.expect((node:IsFocused())):toBe(false)
				stop()
			end,
		})

		verifyHarness:case(
			"commits and formats finite numeric input, clamps out-of-range input and refuses a non-number",
			{
				id = "native_inputs::native input controls::commits and formats finite numeric input, clamps out-of-range input and refuses a non-number",
				run = function()
					local value, number, invalid = Compose.cell("2"), Compose.cell(2), Compose.cell(false)
					local commits = 0
					local reasons = {}
					local node, stop = world(function(UI: FacetControls)
						return UI.TextInput({
							value = value,
							numericValue = number,
							invalid = invalid,
							presentation = "number" :: "number",
							min = 1,
							max = 10,
							format = function(n)
								return string.format("%.1f", n)
							end,
							onCommit = function(committed, reason)
								commits += 1
								table.insert(reasons, `{committed}:{reason}`)
							end,
						})
					end)
					node:CaptureFocus()
					node.Text = "7"
					node:ReleaseFocus(true)
					Verify.expect((number:peek())):toBe(7)
					Verify.expect((value:peek())):toBe("7.0")
					Verify.expect(node.Text):toBe("7.0")
					Verify.expect(commits):toBe(1)
					node:CaptureFocus()
					node.Text = "11"
					node:ReleaseFocus(true)
					Verify.expect((number:peek())):toBe(10)
					Verify.expect((value:peek())):toBe("10.0")
					Verify.expect((invalid:peek())):toBe(false)
					node:CaptureFocus()
					node.Text = "1e1"
					node:ReleaseFocus(true)
					Verify.expect((number:peek())):toBe(10)
					Verify.expect(commits):toBe(2)
					Verify.expect((invalid:peek())):toBe(true)
					Verify.expect((table.concat(reasons, " "))):toBe("7:submit 10:clamped")
					stop()
				end,
			}
		)

		verifyHarness:case("steps from the minimum, respects live stepping and gates all activation", {
			id = "native_inputs::native input controls::steps from the minimum, respects live stepping and gates all activation",
			run = function()
				local value, step, enabled = Compose.cell(5), Compose.cell(5), Compose.cell(true)
				local changes = 0
				local node, stop = world(function(UI: FacetControls)
					return UI.Stepper({
						value = value,
						min = 5,
						max = 25,
						step = step,
						enabled = enabled,
						onChange = function(nextValue)
							value:set(nextValue)
							changes += 1
						end,
					})
				end)
				Verify.expect(find(node, "Increase"):FindFirstChild("LeadingIcon", true) ~= nil):toBe(true)
				Verify.expect(find(node, "Increase").Text):toBe("")
				Verify.expect((find(node, "Decrease"):GetAttribute("label"))):toBe("Decrease")
				local decreaseTitle = find(node, "Decrease"):FindFirstChild("Title", true)
				Verify.expect(decreaseTitle == nil or decreaseTitle.Text == ""):toBe(true)
				find(node, "Increase").Activated:Fire()
				Verify.expect((value:peek())):toBe(10)
				step:set(2)
				find(node, "Increase").Activated:Fire()
				Verify.expect((value:peek())):toBe(13)
				enabled:set(false)
				find(node, "Increase").Activated:Fire()
				Verify.expect((value:peek())):toBe(13)
				Verify.expect(changes):toBe(2)
				stop()
			end,
		})

		verifyHarness:case("lets the native drag detector drive one bounded slider model and cancel", {
			id = "native_inputs::native input controls::lets the native drag detector drive one bounded slider model and cancel",
			run = function()
				local value, commits = Compose.cell(25), 0
				local node, stop, engine = world(function(UI: FacetControls)
					return UI.Slider({
						value = value,
						min = 0,
						max = 100,
						step = 5,
						onCommit = function()
							commits += 1
						end,
					})
				end)
				local track, drag = find(node, "Track"), find(node, "Drag")
				node.SelectionGained:Fire()
				track.AbsoluteSize = engine.types.Vector2.new(200, 44)
				track.AbsolutePosition = engine.types.Vector2.new(20, 0)
				drag.DragStart:Fire(engine.types.Vector2.new(164, 0))
				Verify.expect((value:peek())):toBe(75)
				drag.DragContinue:Fire(engine.types.Vector2.new(500, 0))
				Verify.expect((value:peek())):toBe(100)
				find(node.Parent, "Cancel").Pressed:Fire()
				Verify.expect((value:peek())):toBe(25)
				Verify.expect(commits):toBe(0)
				drag.DragStart:Fire(engine.types.Vector2.new(120, 0))
				drag.DragEnd:Fire()
				Verify.expect((value:peek())):toBe(50)
				Verify.expect(commits):toBe(1)
				stop()
			end,
		})

		verifyHarness:case("supports clearing a rating and keeps read-only levels inert", {
			id = "native_inputs::native input controls::supports clearing a rating and keeps read-only levels inert",
			run = function()
				local value = Compose.cell(3)
				local node, stop, engine = world(function(UI: FacetControls)
					return UI.Rating({ value = value })
				end)
				node.AbsoluteSize = engine.types.Vector2.new(100, 44)
				node.Activated:Fire({ Position = engine.types.Vector2.new(50, 0) })
				Verify.expect((value:peek())):toBe(0)
				node.Activated:Fire({ Position = engine.types.Vector2.new(90, 0) })
				Verify.expect((value:peek())):toBe(5)
				stop()
				node, stop = world(function(UI: FacetControls)
					return UI.LevelPicker({ value = value, readOnly = true })
				end)
				node.Activated:Fire({ Position = engine.types.Vector2.new(10, 0) })
				Verify.expect((value:peek())):toBe(5)
				stop()
			end,
		})
		verifyHarness:case("clears search fields and submits the on-screen keyboard only once", {
			id = "native_inputs::native input controls::clears search fields and submits the on-screen keyboard only once",
			run = function()
				local value, commits, changes = Compose.cell("search"), 0, 0
				local node, stop = world(function(UI: FacetControls)
					return UI.TextInput({
						value = value,
						presentation = "search" :: "search",
						onChange = function(nextValue)
							value:set(nextValue)
							changes += 1
						end,
						onCommit = function()
							commits += 1
						end,
					})
				end)
				local clear = find(node, "Clear")
				Verify.expect(clear.Visible):toBe(true)
				Verify.expect((clear:GetAttribute("label"))):toBe("Clear")
				Verify.expect(clear:FindFirstChild("LeadingIcon", true) ~= nil):toBe(true)
				Verify.expect((clear:FindFirstChild("Title", true))):toBeNil()
				Verify.expect(clear.Text):toBe("")
				Verify.expect(clear.Size.Y.Offset > 0 and clear.Size.Y.Offset < 36):toBe(true)
				Verify.expect((clear:HasTag("facet-shape-circle"))):toBe(true)
				clear.Activated:Fire()
				Verify.expect((value:peek())):toBe("")
				Verify.expect(clear.Visible):toBe(false)
				Verify.expect(changes):toBe(1)
				local field = find(node, "Field")
				field:CaptureFocus()
				field.Text = "find"
				field.ReturnPressedFromOnScreenKeyboard:Fire()
				Verify.expect(commits):toBe(1)
				Verify.expect((field:IsFocused())):toBe(false)
				stop()
			end,
		})

		verifyHarness:case("repeats while held and cancels native frame subscriptions on disposal", {
			id = "native_inputs::native input controls::repeats while held and cancels native frame subscriptions on disposal",
			run = function()
				local activated = 0
				local node, stop, engine = world(function(UI: FacetControls)
					return UI.Button({
						label = "Repeat",
						repeatDelay = 0.4,
						repeatInterval = 0.1,
						onActivate = function()
							activated += 1
						end,
					})
				end)
				local input = {
					UserInputType = engine.types.Enum.UserInputType.MouseButton1,
					KeyCode = engine.types.Enum.KeyCode:FromValue(0),
				}
				node.InputBegan:Fire(input)
				engine.heartbeat:Fire(0.4)
				engine.heartbeat:Fire(0.1)
				Verify.expect(activated):toBe(2)
				node.InputEnded:Fire(input)
				node.Activated:Fire()
				Verify.expect(activated):toBe(2)
				stop()
				engine.heartbeat:Fire(1)
				Verify.expect(activated):toBe(2)
				Verify.expect((engineLib.connections(engine.heartbeat))):toBe(0)
			end,
		})
		verifyHarness:case("reports a pointer cancel when onPointerCancel is the only pointer option", {
			id = "native_inputs::native input controls::reports a pointer cancel when onPointerCancel is the only pointer option",
			run = function()
				local cancels = 0
				local node, stop, engine = world(function(UI: FacetControls)
					return UI.Button "Hold" {
						label = "Hold",
						onPointerCancel = function()
							cancels += 1
						end,
					}
				end)
				node.InputBegan:Fire({
					UserInputType = engine.types.Enum.UserInputType.MouseButton1,
					KeyCode = engine.types.Enum.KeyCode:FromValue(0),
				})
				node.MouseLeave:Fire()
				Verify.expect(cancels):toBe(1)
				node.MouseLeave:Fire()
				Verify.expect(cancels):toBe(1)
				stop()
			end,
		})

		verifyHarness:case("follows GuiService.ReducedMotionEnabled for pop, validation pulse and busy dots", {
			id = "native_inputs::native input controls::follows GuiService.ReducedMotionEnabled for pop, validation pulse and busy dots",
			run = function()
				local gui
				local busy, value, number = Compose.cell(false), Compose.cell("2"), Compose.cell(2)
				local root, stop, engine = world(function(UI: FacetControls, engine, runtime)
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
						UI.Button "Pop" { label = "Pop", pop = true, busy = busy, onActivate = function() end } :: unknown,
						UI.TextInput "Amount" {
							value = value,
							numericValue = number,
							presentation = "number" :: "number",
							max = 10,
						},
					})
				end, function(engine)
					gui = engine.new("GuiService")
					gui.ReducedMotionEnabled = true
					return { guiService = gui, services = { GuiService = gui } }
				end)
				local button, field = find(root, "Pop"), find(root, "Amount")
				local scale = button:FindFirstChildWhichIsA("UIScale", true)
				button.Activated:Fire()
				engine.heartbeat:Fire(0.1)
				Verify.expect(scale.Scale):toBe(1)
				field:CaptureFocus()
				field.Text = "11"
				field:ReleaseFocus(true)
				engine.heartbeat:Fire(0.08)
				Verify.expect(find(field, "ValidationPulse").Scale):toBe(1)
				busy:set(true)
				engine.heartbeat:Fire(0.3)
				Verify.expect(find(button, "Dot1").BackgroundTransparency):toBe(0)
				busy:set(false)
				gui.ReducedMotionEnabled = false
				button.Activated:Fire()
				engine.heartbeat:Fire(0.1)
				Verify.expect(scale.Scale > 1):toBe(true)
				stop()
			end,
		})

		verifyHarness:case("does not commit a number TextInput that its parse callback disables", {
			id = "native_inputs::native input controls::does not commit a number TextInput that its parse callback disables",
			run = function()
				local value, number, enabled, commits = Compose.cell("2"), Compose.cell(2), Compose.cell(true), 0
				local node, stop = world(function(UI: FacetControls)
					return UI.TextInput "Amount" {
						value = value,
						numericValue = number,
						presentation = "number" :: "number",
						enabled = enabled,
						parse = function(text)
							enabled:set(false)
							return tonumber(text)
						end,
						onCommit = function()
							commits += 1
						end,
					}
				end)
				node:CaptureFocus()
				node.Text = "5"
				node:ReleaseFocus(true)
				Verify.expect(commits):toBe(0)
				Verify.expect((number:peek())):toBe(2)
				stop()
			end,
		})

		verifyHarness:case("accepts a readable Button corners value and follows it", {
			id = "native_inputs::native input controls::accepts a readable Button corners value and follows it",
			run = function()
				local corners = Compose.cell("square" :: "pill" | "square")
				local node, stop = world(function(UI: FacetControls)
					return UI.Button "Corners" { label = "Corners", corners = corners }
				end)
				local corner = node:FindFirstChildWhichIsA("UICorner")
				Verify.expect(corner.CornerRadius.Scale):toBe(0)
				corners:set("pill")
				Verify.expect(corner.CornerRadius.Scale):toBe(1)
				stop()
				Verify.expect(function()
					world(function(UI: FacetControls)
						return UI.Button "Corners"({ label = "Corners", corners = "round" } :: any)
					end)
				end):toThrow()
			end,
		})

		verifyHarness:case("edits a controlled map field without duplicating durable state", {
			id = "native_inputs::native input controls::edits a controlled map field without duplicating durable state",
			run = function()
				local notes = Compose.cell({ item = "saved" })
				local requests = 0
				local node, stop = world(function(UI: FacetControls)
					return UI.TextInput({
						value = function(use: Use)
							return use(notes).item
						end,
						onChange = function(value)
							requests += 1
							if value ~= "rejected" then
								notes:set({ item = value })
							end
						end,
					})
				end)
				node:CaptureFocus()
				node.Text = "updated"
				Verify.expect(notes:peek().item):toBe("updated")
				Verify.expect(requests):toBe(1)
				node.Text = "rejected"
				Verify.expect(node.Text):toBe("updated")
				notes:set({ item = "external" })
				Verify.expect(requests):toBe(2)
				Verify.expect(node.Text):toBe("external")
				find(node.Parent, "Cancel").Pressed:Fire()
				Verify.expect(notes:peek().item):toBe("saved")
				Verify.expect(requests):toBe(3)
				stop()
			end,
		})
		verifyHarness:case("does not mutate writable controlled models before callbacks accept requests", {
			id = "native_inputs::native input controls::does not mutate writable controlled models before callbacks accept requests",
			run = function()
				local value = Compose.cell(3)
				local requested: number | string | nil = nil
				local node, stop = world(function(UI: FacetControls)
					return UI.Stepper({
						value = value,
						min = 0,
						max = 10,
						onChange = function(nextValue)
							requested = nextValue
						end,
					})
				end)
				find(node, "Increase").Activated:Fire()
				Verify.expect(requested):toBe(4)
				Verify.expect((value:peek())):toBe(3)
				stop()
				local text = Compose.cell("accepted")
				node, stop = world(function(UI: FacetControls)
					return UI.TextInput({
						value = text,
						onChange = function(nextValue)
							requested = nextValue
						end,
					})
				end)
				node:CaptureFocus()
				node.Text = "rejected"
				Verify.expect(requested):toBe("rejected")
				Verify.expect((text:peek())):toBe("accepted")
				Verify.expect(node.Text):toBe("accepted")
				stop()
			end,
		})
		verifyHarness:case("owns busy animation only while visible and suppresses busy activation", {
			id = "native_inputs::native input controls::owns busy animation only while visible and suppresses busy activation",
			run = function()
				local busy, actions = Compose.cell(false), 0
				local node, stop, engine = world(function(UI: FacetControls)
					return UI.Button({
						label = "Loading",
						busy = busy,
						onActivate = function()
							actions += 1
						end,
					})
				end)
				Verify.expect((find(node, "Busy"))):toBe(nil)
				Verify.expect((engineLib.connections(engine.heartbeat))):toBe(0)
				for _ = 1, 3 do
					busy:set(true)
					Verify.expect(find(node, "Busy") ~= nil):toBe(true)
					Verify.expect((engineLib.connections(engine.heartbeat))):toBe(1)
					node.Activated:Fire()
					Verify.expect(node.Selectable):toBe(false)
					busy:set(false)
					Verify.expect((find(node, "Busy"))):toBe(nil)
					Verify.expect((engineLib.connections(engine.heartbeat))):toBe(0)
				end
				Verify.expect(actions):toBe(0)
				node.Activated:Fire()
				Verify.expect(actions):toBe(1)
				stop()
			end,
		})

		verifyHarness:case("keeps pop and rejection scales below stable layout slots", {
			id = "native_inputs::native input controls::keeps pop and rejection scales below stable layout slots",
			run = function()
				local invalid = Compose.cell(false)
				local node, stop, engine = world(function(UI: FacetControls, engine, runtime)
					local Host = runtime.constructors
					return Host.Frame {
						UI.Button "Pop" { label = "Pop", pop = true, onActivate = function() end } :: unknown,
						UI.TextInput "Field" { value = Compose.cell("abc"), invalid = invalid },
					}
				end)
				local button, field = find(node, "Pop"), find(node, "Field")
				button.AbsoluteSize = engine.types.Vector2.new(80, 44)
				field.AbsoluteSize = engine.types.Vector2.new(120, 44)
				local beforeButton, beforeField = button.Size, field.Size
				button.Activated:Fire()
				invalid:set(true)
				engine.heartbeat:Fire(0.08)
				Verify.expect(button:FindFirstChildWhichIsA("UIScale")):toBe(nil)
				Verify.expect(field:FindFirstChildWhichIsA("UIScale")):toBe(nil)
				Verify.expect(find(button, "FeedbackPaint"):FindFirstChild("Pop").Scale > 1):toBe(true)
				Verify.expect(find(field, "FeedbackPaint"):FindFirstChild("ValidationPulse").Scale < 1):toBe(true)
				Verify.expect(button.Size):toBe(engine.types.UDim2.fromOffset(80, 44))
				Verify.expect(field.Size):toBe(engine.types.UDim2.fromOffset(120, 44))
				engine.heartbeat:Fire(1)
				Verify.expect(button.Size):toBe(beforeButton)
				Verify.expect(field.Size):toBe(beforeField)
				stop()
				Verify.expect(engineLib.connections(engine.heartbeat)):toBe(0)
			end,
		})

		verifyHarness:case("restarts Compose pop feedback and obeys live reduced motion", {
			id = "native_inputs::native input controls::restarts Compose pop feedback and obeys live reduced motion",
			run = function()
				local reduced = Compose.cell(false)
				local node, stop, engine = world(function(UI: FacetControls)
					return UI.Button({ label = "Pop", pop = true, onActivate = function() end })
				end, function()
					return {
						motionLevel = (Compose.formula(function(use: Use): "normal" | "limited" | "none"
							return if use(reduced) then "none" else "normal"
						end) :: unknown) :: MotionLevel,
					}
				end)
				local scale = find(node, "Pop")
				Verify.expect(scale.Scale):toBe(1)
				node.Activated:Fire()
				engine.heartbeat:Fire(0.1)
				Verify.expect(scale.Scale > 1):toBe(true)
				local current = scale.Scale
				node.Activated:Fire()
				Verify.expect(scale.Scale):toBeCloseTo(current, 1e-4)
				reduced:set(true)
				Verify.expect(scale.Scale):toBe(1)
				node.Activated:Fire()
				engine.heartbeat:Fire(1)
				Verify.expect(scale.Scale):toBe(1)
				stop()
				Verify.expect((engineLib.connections(engine.heartbeat))):toBe(0)
			end,
		})

		verifyHarness:case("recovers an automatic compact caption when its parent width returns", {
			id = "native_inputs::native input controls::recovers an automatic compact caption when its parent width returns",
			run = function()
				local node, stop, engine = world(function(UI: FacetControls, engine, runtime)
					return runtime.constructors.Frame {
						Name = "Row",
						UI.Button "Sort" { label = "Sorting", compactLabel = "Srt" },
					}
				end)
				local sort = find(node, "Sort")
				local measure = find(sort, "FullLabelMeasure")
				measure.TextBounds = engine.types.Vector2.new(45, 18)
				sort.AbsoluteSize = engine.types.Vector2.new(43, 44)
				for _ = 1, 3 do
					node.AbsoluteSize = engine.types.Vector2.new(60, 44)
					Verify.expect(sort.Text):toBe("Srt")
					node.AbsoluteSize = engine.types.Vector2.new(300, 44)
					Verify.expect(sort.Text):toBe("Sorting")
					Verify.expect(sort.AbsoluteSize.X):toBe(43)
				end
				stop()
			end,
		})
		verifyHarness:case("chooses compact button text from native measurements and restores the full caption", {
			id = "native_inputs::native input controls::chooses compact button text from native measurements and restores the full caption",
			run = function()
				local node, stop, engine = world(function(UI: FacetControls)
					return UI.Button({ label = "Continue to checkout", compactLabel = "Continue" })
				end)
				local measure = find(node, "FullLabelMeasure")
				measure.TextBounds = engine.types.Vector2.new(180, 20)
				node.AbsoluteSize = engine.types.Vector2.new(110, 44)
				Verify.expect(node.Text):toBe("Continue")
				node.AbsoluteSize = engine.types.Vector2.new(240, 44)
				Verify.expect(node.Text):toBe("Continue to checkout")
				stop()
			end,
		})

		verifyHarness:case("deduplicates shortcut/default bindings and yields shortcuts during native text editing", {
			id = "native_inputs::native input controls::deduplicates shortcut/default bindings and yields shortcuts during native text editing",
			run = function()
				local editing, actions = false, 0
				local node, stop = world(function(UI: FacetControls)
					return UI.Button({
						label = "Default",
						shortcut = { keyCode = "Return" },
						dialogAction = "default" :: "default",
						onActivate = function()
							actions += 1
						end,
					})
				end, function()
					return {
						services = {
							UserInputService = {
								GetFocusedTextBox = function()
									return if editing then {} else nil
								end,
							},
						},
					}
				end)
				local action = find(node.Parent, "Shortcut")
				Verify.expect(#action:GetChildren()):toBe(1)
				action.Pressed:Fire()
				Verify.expect(actions):toBe(1)
				editing = true
				action.Pressed:Fire()
				Verify.expect(actions):toBe(1)
				stop()
				Verify.expect((engineLib.connections(action.Pressed))):toBe(0)
			end,
		})

		verifyHarness:case("binds one shortcut action to the key and the dialog button and activates once per press", {
			id = "native_inputs::native input controls::binds one shortcut action to the key and the dialog button and activates once per press",
			run = function()
				local actions = 0
				local node, stop = world(function(UI: FacetControls)
					return UI.Button({
						label = "Close",
						shortcut = { keyCode = "K" },
						dialogAction = "cancel" :: "cancel",
						onActivate = function()
							actions += 1
						end,
					})
				end)
				local action = find(node.Parent, "Shortcut")
				local keys = {}
				for _, binding in action:GetChildren() do
					table.insert(keys, binding.KeyCode.Name)
				end
				table.sort(keys)
				Verify.expect((table.concat(keys, ","))):toBe("ButtonB,K")
				action.Pressed:Fire()
				Verify.expect(actions):toBe(1)
				node.Activated:Fire()
				Verify.expect(actions):toBe(2)
				stop()
			end,
		})

		verifyHarness:case("clamps a fixed-size button's icon to its content box and never to zero", {
			id = "native_inputs::native input controls::clamps a fixed-size button's icon to its content box and never to zero",
			run = function()
				local node, stop, engine = world(function(UI: FacetControls, host, runtime)
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
						UI.Button "Tight" {
							icon = "rbxassetid://1",
							Size = host.types.UDim2.fromOffset(20, 20),
							AutomaticSize = host.types.Enum.AutomaticSize.None,
						} :: unknown,
						UI.Button "Free" { icon = "rbxassetid://1", label = "Free" },
					})
				end)
				local tight = find(node, "Tight")
				local content = find(tight, "Content")
				local glyph = find(tight, "LeadingIcon")
				local limit = glyph:FindFirstChildWhichIsA("UISizeConstraint")
				Verify.expect(limit ~= nil):toBe(true)
				content.AbsoluteSize = engine.types.Vector2.new(4, 6)
				Verify.expect(limit.MaxSize.X):toBe(4)
				Verify.expect(limit.MaxSize.Y):toBe(4)
				content.AbsoluteSize = engine.types.Vector2.new(0, 0)
				Verify.expect(limit.MaxSize.X):toBe(1)
				Verify.expect(content.AutomaticSize):toBe(engine.types.Enum.AutomaticSize.None)
				Verify.expect((find(find(node, "Free"), "LeadingIcon"):FindFirstChildWhichIsA("UISizeConstraint")))
					:toBe(nil)
				stop()
			end,
		})

		verifyHarness:case("blocks background held repeats when a Compose-owned modal becomes active", {
			id = "native_inputs::native input controls::blocks background held repeats when a Compose-owned modal becomes active",
			run = function()
				local actions = 0
				local node, stop, engine, runtime, ctx = world(function(UI: FacetControls)
					return UI.Button({
						label = "Repeat",
						repeatInterval = 0.1,
						onActivate = function()
							actions += 1
						end,
					})
				end)
				node.InputBegan:Fire({
					UserInputType = engine.types.Enum.UserInputType.MouseButton1,
					KeyCode = engine.types.Enum.KeyCode:FromValue(0),
				})
				engine.heartbeat:Fire(0.4)
				Verify.expect(actions):toBe(1)
				local modal = engine.new("Frame")
				modal.Parent = node.Parent
				ctx.modalScopes:set({ modal })
				engine.heartbeat:Fire(0.4)
				Verify.expect(actions):toBe(1)
				ctx.modalScopes:set({})
				engine.heartbeat:Fire(0.4)
				Verify.expect(actions):toBe(1)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("taps a selected level back to zero and scrubs against the visible marks", {
			id = "native_inputs::native input controls::taps a selected level back to zero and scrubs against the visible marks",
			run = function()
				local value = Compose.cell(1)
				local node, stop, engine = world(function(UI: FacetControls)
					return UI.LevelPicker({ value = value, count = 3, allowZero = true })
				end)
				local V = engine.types.Vector2
				node.AbsolutePosition, node.AbsoluteSize = V.new(709, 0), V.new(156, 44)
				local marks = find(node, "Marks")
				marks.AbsolutePosition, marks.AbsoluteSize = V.new(755, 0), V.new(64, 20)
				local detector = find(node, "Scrub")
				detector.DragStart:Fire(V.new(765, 0))
				detector.DragEnd:Fire(V.new(765, 0))
				node.Activated:Fire({ Position = engine.types.Vector3.new(765, 0, 0) })
				Verify.expect(value:peek()):toBe(0)
				for i, x in { 765, 787, 809 } do
					detector.DragStart:Fire(V.new(x, 0))
					Verify.expect(value:peek()):toBe(i)
					detector.DragContinue:Fire(V.new(810, 0))
					detector.DragEnd:Fire(V.new(809, 0))
					Verify.expect(value:peek()):toBe(3)
				end
				stop()
			end,
		})

		verifyHarness:case("keeps level marks inert with one focus target and a cancellable native scrub", {
			id = "native_inputs::native input controls::keeps level marks inert with one focus target and a cancellable native scrub",
			run = function()
				local value = Compose.cell(2)
				local node, stop, engine = world(function(UI: FacetControls)
					return UI.LevelPicker({ value = value, count = 5 })
				end)
				node.AbsoluteSize = engine.types.Vector2.new(100, 44)
				local selectable = if node.Selectable then 1 else 0
				for _, child in node:GetDescendants() do
					if child:IsA("GuiObject") and child.Selectable then
						selectable += 1
					end
				end
				Verify.expect(selectable):toBe(1)
				Verify.expect(find(node, "Level3").ClassName):toBe("Frame")
				Verify.expect((find(node.Parent, "FacetIncrease"))):toBe(nil)
				node.SelectionGained:Fire()
				Verify.expect(find(node.Parent, "FacetIncrease").Enabled):toBe(true)
				find(node, "Scrub").DragStart:Fire(engine.types.Vector2.new(90, 0))
				Verify.expect((value:peek())):toBe(5)
				find(node, "Scrub").DragContinue:Fire(engine.types.Vector2.new(10, 0))
				Verify.expect((value:peek())):toBe(1)
				find(node.Parent, "Cancel").Pressed:Fire()
				Verify.expect((value:peek())):toBe(2)
				stop()
			end,
		})

		verifyHarness:case("updates explicit shortcut alternatives without owning input bindings", {
			id = "native_inputs::native input controls::updates explicit shortcut alternatives without owning input bindings",
			run = function()
				local separator, chords = Compose.cell(" or "), Compose.cell({ { "Ctrl", "K" }, { "F1" } })
				local node, stop, engine = world(function(UI: FacetControls)
					return UI.ShortcutHint({ keys = chords, separator = separator })
				end)
				Verify.expect(node.Text):toBe("Ctrl+K or F1")
				separator:set("ou")
				Verify.expect(node.Text):toBe("Ctrl+K ou F1")
				separator:set(" / ")
				chords:set({ { "Shift", "P" } })
				Verify.expect(node.Text):toBe("Shift+P")
				for _, instance in engine.made do
					Verify.expect(instance.ClassName == "InputAction" or instance.ClassName == "InputContext")
						:toBe(false)
				end
				stop()
				Verify.expect(function()
					world(function(UI: FacetControls)
						return UI.ShortcutHint({ keys = { { "" } } })
					end)
				end):toThrow()
			end,
		})

		verifyHarness:case("borrows native preferred bindings and releases replaced hint observers", {
			id = "native_inputs::native input controls::borrows native preferred bindings and releases replaced hint observers",
			run = function()
				local action, first, second
				local node, stop, engine = world(function(UI: FacetControls, engine)
					action, first, second =
						engine.new("InputAction"), engine.new("InputBinding"), engine.new("InputBinding")
					first.KeyCode, first.DisplayName = engine.types.Enum.KeyCode.F, ""
					second.KeyCode, second.DisplayName = engine.types.Enum.KeyCode.ButtonX, "Interact"
					action.PreferredBinding = first
					return UI.ShortcutHint({ action = action })
				end)
				Verify.expect(find(node, "Key").Text):toBe("F")
				first.DisplayName = "Use"
				Verify.expect(find(node, "Key").Text):toBe("Use")
				action.PreferredBinding = second
				Verify.expect(find(node, "Key").Text):toBe("Interact")
				Verify.expect((engineLib.connections(first:GetPropertyChangedSignal("DisplayName")))):toBe(0)
				action.PreferredBinding = nil
				Verify.expect((find(node, "Key"))):toBe(nil)
				Verify.expect((engineLib.connections(second:GetPropertyChangedSignal("DisplayName")))):toBe(0)
				stop()
				Verify.expect((action:isDestroyed())):toBe(false)
				Verify.expect((engineLib.connections(action:GetPropertyChangedSignal("PreferredBinding")))):toBe(0)
			end,
		})

		verifyHarness:case("keeps an authored circle axis dominant instead of fitting inside a zero box", {
			id = "native_inputs::native input controls::keeps an authored circle axis dominant instead of fitting inside a zero box",
			run = function()
				for _, case: { x: number, y: number, axis: "Width" | "Height" } in
					{ { x = 32, y = 0, axis = "Width" :: "Width" }, { x = 0, y = 72, axis = "Height" :: "Height" } } :: { { x: number, y: number, axis: "Width" | "Height" } }
				do
					local node, stop, engine = world(function(UI: FacetControls, engine)
						return UI.Button({
							label = "Close",
							shape = "circle" :: "circle",
							controlSize = "compact" :: "compact",
							Size = engine.types.UDim2.fromOffset(case.x, case.y),
						})
					end)
					local aspect = node:FindFirstChildWhichIsA("UIAspectRatioConstraint")
					Verify.expect(aspect.AspectRatio):toBe(1)
					Verify.expect(aspect.AspectType):toBe(engine.types.Enum.AspectType.ScaleWithParentSize)
					Verify.expect(aspect.DominantAxis):toBe(assert(engine.types.Enum.DominantAxis:FromName(case.axis)))
					Verify.expect(node.Size.X.Offset):toBe(case.x)
					Verify.expect(node.Size.Y.Offset):toBe(case.y)
					stop()
				end
				local node, stop, engine = world(function(UI: FacetControls, engine)
					return UI.Button({
						label = "Close",
						shape = "circle" :: "circle",
						Size = engine.types.UDim2.fromOffset(40, 40),
					})
				end)
				Verify.expect(node:FindFirstChildWhichIsA("UIAspectRatioConstraint").AspectType)
					:toBe(engine.types.Enum.AspectType.FitWithinMaxSize)
				stop()
			end,
		})
		verifyHarness:case("shows numeric validation text with interruptible reduced-motion-aware feedback", {
			id = "native_inputs::native input controls::shows numeric validation text with interruptible reduced-motion-aware feedback",
			run = function()
				local value, number, reduced = Compose.cell("2"), Compose.cell(2), Compose.cell(false)
				local node, stop, engine = world(function(UI: FacetControls)
					return UI.TextInput({
						value = value,
						numericValue = number,
						presentation = "number" :: "number",
						min = 1,
						max = 10,
					})
				end, function()
					return {
						motionLevel = (Compose.formula(function(use: Use): "normal" | "limited" | "none"
							return if use(reduced) then "none" else "normal"
						end) :: unknown) :: MotionLevel,
					}
				end)
				node.TextBounds = engine.types.Vector2.new(20, 20)
				local label = find(node, "ValidationMessage")
				label.TextBounds = engine.types.Vector2.new(200, 18)
				node:CaptureFocus()
				node.Text = "1.2.3"
				node:ReleaseFocus(true)
				Verify.expect(label.Text):toBe("Enter a valid number.")
				Verify.expect(label.Visible):toBe(true)
				Verify.expect(node.Size.Y.Offset >= 54):toBe(true)
				engine.heartbeat:Fire(0.08)
				Verify.expect(find(node, "ValidationPulse").Scale < 1):toBe(true)
				reduced:set(true)
				Verify.expect(find(node, "ValidationPulse").Scale):toBe(1)
				node:CaptureFocus()
				node.Text = "3"
				node:ReleaseFocus(true)
				Verify.expect((number:peek())):toBe(3)
				Verify.expect(label.Visible):toBe(false)
				stop()
				Verify.expect((engineLib.connections(engine.heartbeat))):toBe(0)
			end,
		})

		verifyHarness:case("reflects external invalid state and rejects malformed invalid and numeric declarations", {
			id = "native_inputs::native input controls::reflects external invalid state and rejects malformed invalid and numeric declarations",
			run = function()
				local invalid, value = Compose.cell(false), Compose.cell("ready")
				local node, stop = world(function(UI: FacetControls)
					return UI.TextInput({ value = value, invalid = invalid })
				end)
				invalid:set(true)
				Verify.expect(find(node, "ValidationMessage").Visible):toBe(true)
				invalid:set(false)
				Verify.expect(find(node, "ValidationMessage").Visible):toBe(false)
				stop()
				Verify.expect(function()
					world(function(UI: FacetControls)
						return UI.TextInput({ value = value, invalid = true } :: any)
					end)
				end):toThrow()
				Verify.expect(function()
					world(function(UI: FacetControls)
						return UI.TextInput({ value = value, presentation = "number" } :: any)
					end)
				end):toThrow()
			end,
		})

		verifyHarness:case("honors every clear-button mode and ends disabled edits without a commit", {
			id = "native_inputs::native input controls::honors every clear-button mode and ends disabled edits without a commit",
			run = function()
				for _, mode in
					{ "never", "always", "whileEditing", "unlessEditing" } :: { "always" | "never" | "unlessEditing" | "whileEditing" }
				do
					local value, enabled, commits = Compose.cell("text"), Compose.cell(true), 0
					local node, stop = world(function(UI: FacetControls)
						return UI.TextInput({
							value = value,
							enabled = enabled,
							clearButtonMode = mode :: "always" | "never" | "unlessEditing" | "whileEditing",
							onCommit = function()
								commits += 1
							end,
						})
					end)
					local clear = find(node, "Clear")
					if mode == "never" then
						Verify.expect(clear):toBe(nil)
					else
						Verify.expect(clear.Visible):toBe(mode ~= "whileEditing")
					end
					node:CaptureFocus()
					if clear then
						Verify.expect(clear.Visible):toBe(mode ~= "unlessEditing")
					end
					Verify.expect(find(node.Parent, "FacetTextEditing").Enabled):toBe(true)
					enabled:set(false)
					Verify.expect((node:IsFocused())):toBe(false)
					Verify.expect(node.Selectable):toBe(false)
					Verify.expect(find(node.Parent, "FacetTextEditing").Enabled):toBe(false)
					Verify.expect(commits):toBe(0)
					if clear then
						Verify.expect(clear.Visible):toBe(false)
					end
					stop()
				end
			end,
		})
		verifyHarness:case("removes keyed chips toward the next then previous native target and caller fallback", {
			id = "native_inputs::native input controls::removes keyed chips toward the next then previous native target and caller fallback",
			run = function()
				local items, gui, fallback = Compose.cell({ "A", "B", "C" }), nil, nil
				local node, stop = world(function(UI: FacetControls, engine, runtime)
					fallback = ((runtime.constructors.TextButton :: unknown) :: TextButtonConstructor) "Fallback" {}
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
						fallback :: unknown,
						Compose.keyed({
							from = items,
							render = function(current, index): GuiObject
								local id = current:peek()
								return UI.Chip({
									Name = id,
									label = id,
									LayoutOrder = index,
									removeFocusFallback = fallback :: GuiObject,
									onRemove = function()
										items:update(function(before)
											local after = {}
											for _, value in before do
												if value ~= id then
													table.insert(after, value)
												end
											end
											return after
										end)
									end,
								})
							end,
						}),
					})
				end, function(engine)
					gui = engine.new("GuiService")
					return { services = { GuiService = gui } }
				end)
				local function remove(id)
					local target = find(node, id)
					gui.SelectedObject = target
					target.Activated:Fire()
				end
				remove("B")
				Verify.expect(gui.SelectedObject):toBe(find(node, "C"))
				remove("C")
				Verify.expect(gui.SelectedObject):toBe(find(node, "A"))
				remove("A")
				Verify.expect(gui.SelectedObject):toBe(fallback)
				stop()
			end,
		})

		verifyHarness:case("does not steal focus after a delayed chip removal request", {
			id = "native_inputs::native input controls::does not steal focus after a delayed chip removal request",
			run = function()
				local show, gui, fallback, other = Compose.cell(true), nil, nil, nil
				local node, stop = world(function(UI: FacetControls, engine, runtime)
					fallback = ((runtime.constructors.TextButton :: unknown) :: TextButtonConstructor) "Fallback" {}
					other = ((runtime.constructors.TextButton :: unknown) :: TextButtonConstructor) "Other" {}
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
						fallback :: unknown,
						other,
						Compose.show(show, function()
							return UI.Chip "Delayed" {
								label = "Delayed",
								removeFocusFallback = fallback :: GuiObject,
								onRemove = function() end,
							}
						end),
					})
				end, function(engine)
					gui = engine.new("GuiService")
					return { services = { GuiService = gui } }
				end)
				local remove = find(node, "Delayed")
				gui.SelectedObject = remove
				remove.Activated:Fire()
				Verify.expect(gui.SelectedObject):toBe(remove)
				gui.SelectedObject = other
				show:set(false)
				Verify.expect(gui.SelectedObject):toBe(other)
				stop()
			end,
		})

		verifyHarness:case("keeps mixed checkbox geometry live and validates presentation-specific options", {
			id = "native_inputs::native input controls::keeps mixed checkbox geometry live and validates presentation-specific options",
			run = function()
				local value, mixed = Compose.cell(false), Compose.cell(true)
				local node, stop = world(function(UI: FacetControls)
					return UI.Toggle({
						value = value,
						mixed = mixed,
						presentation = "checkbox" :: "checkbox",
						indicatorPosition = "trailing" :: "trailing",
						row = { title = "Mode", description = "Use the current setting" },
					})
				end)
				Verify.expect(find(node, "Mark").Size.Y.Offset):toBe(4)
				Verify.expect(find(node, "Mark").Visible):toBe(true)
				Verify.expect(find(node, "Check").Visible):toBe(false)
				mixed:set(false)
				Verify.expect(find(node, "Mark").Visible):toBe(false)
				Verify.expect(find(node, "Check").Visible):toBe(false)
				value:set(true)
				Verify.expect(find(node, "Mark").Visible):toBe(false)
				Verify.expect(find(node, "Check").Visible):toBe(true)
				stop()
				Verify.expect(function()
					world(function(UI: FacetControls)
						return UI.Toggle({ value = value, mixed = mixed, presentation = "switch" :: "switch" })
					end)
				end):toThrow()
			end,
		})
		verifyHarness:case(
			"a switch knob glides between its ends, reverses mid-flight without a jump, and lands at once under none",
			{
				id = "native_inputs::native input controls::a switch knob glides between its ends, reverses mid-flight without a jump, and lands at once under none",
				run = function()
					local value = Compose.cell(false)
					local node, stop, engine = world(function(UI: FacetControls)
						return UI.Toggle({ label = "Music", value = value, presentation = "switch" :: "switch" })
					end)
					local mark = find(node, "Mark")
					Verify.expect(mark.Position.X.Scale):toBeCloseTo(0.3, 1e-3)
					value:set(true)
					engine.heartbeat:Fire(1 / 60)
					local first = mark.Position.X.Scale
					Verify.expect(first > 0.3 and first < 0.7):toBe(true)
					engine.heartbeat:Fire(1 / 60)
					engine.heartbeat:Fire(1 / 60)
					local before = mark.Position.X.Scale
					value:set(false)
					engine.heartbeat:Fire(1 / 60)
					Verify.expect(math.abs(mark.Position.X.Scale - before) < 0.1):toBe(true)
					for _ = 1, 60 do
						engine.heartbeat:Fire(1 / 60)
					end
					Verify.expect(mark.Position.X.Scale):toBeCloseTo(0.3, 1e-3)
					value:set(true)
					for _ = 1, 60 do
						engine.heartbeat:Fire(1 / 60)
					end
					Verify.expect(mark.Position.X.Scale):toBeCloseTo(0.7, 1e-3)
					Verify.expect((engineLib.connections(engine.heartbeat))):toBe(0)
					stop()
					local snapped = Compose.cell(false)
					local snapNode, stopSnap = world(function(UI: FacetControls)
						return UI.Toggle({ label = "Music", value = snapped, presentation = "switch" :: "switch" })
					end, function()
						return { motionLevel = "none" }
					end)
					snapped:set(true)
					Verify.expect(find(snapNode, "Mark").Position.X.Scale):toBeCloseTo(0.7, 1e-3)
					stopSnap()
				end,
			}
		)

		verifyHarness:case("maps the named feedback kinds onto pooled engine haptic effects", {
			id = "native_inputs::native input controls::maps the named feedback kinds onto pooled engine haptic effects",
			run = function()
				local kind = Compose.cell("error" :: "error" | "impact" | "selection" | "success" | "warning" | boolean)
				local UIref
				local node, stop, engine = world(function(UI: FacetControls, _, runtime)
					UIref = UI
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
						UI.Button "Saved" { label = "Save", haptic = "success" :: "success" } :: unknown,
						UI.Button "Again" { label = "Save", haptic = "success" :: "success" },
						UI.Button "Careful" { label = "Sell", haptic = "warning" :: "warning" },
						UI.Button "Live" { label = "Try", haptic = kind },
						UI.Button "Plain" { label = "Go", haptic = true },
						UI.Toggle "Sound" { value = Compose.cell(true), label = "Sound" },
					})
				end, function()
					return { pressHaptic = "selection" }
				end)
				local E = engine.types.Enum
				local saved = find(node, "Saved").PressHapticEffect
				Verify.expect(saved.ClassName):toBe("HapticEffect")
				Verify.expect(saved.Type):toBe(E.HapticEffectType.UINotification)
				Verify.expect(find(node, "Again").PressHapticEffect):toBe(saved)
				local warning = find(node, "Careful").PressHapticEffect
				Verify.expect(warning.Type):toBe(E.HapticEffectType.Custom)
				Verify.expect(#warning.WaveformKeys >= 4):toBe(true)
				for _, key in warning.WaveformKeys do
					Verify.expect(key.Value == 0 or key.Value >= 0.3):toBe(true)
				end
				local live = find(node, "Live")
				Verify.expect(live.PressHapticEffect.Type):toBe(E.HapticEffectType.Custom)
				Verify.expect(live.PressHapticEffect == warning):toBe(false)
				kind:set("impact")
				Verify.expect(live.PressHapticEffect.Type):toBe(E.HapticEffectType.GameplayCollision)
				kind:set(false)
				Verify.expect(live.PressHapticEffect):toBe(nil)
				Verify.expect(find(node, "Plain").PressHapticEffect.Type):toBe(E.HapticEffectType.UIClick)
				Verify.expect(find(node, "Sound").PressHapticEffect):toBe(find(node, "Plain").PressHapticEffect)
				UIref.feedback("success")
				Verify.expect(saved.PlayCount):toBe(1)
				Verify.expect(function()
					UIref.feedback("boom" :: any)
				end):toThrow()
				Verify.expect(function()
					world(function(UI: FacetControls)
						return UI.Button({ label = "Bad", haptic = "boom" } :: any)
					end)
				end):toThrow()
				stop()
				node, stop = world(function(UI: FacetControls)
					return UI.Button "Bare" { label = "Go", haptic = true }
				end)
				Verify.expect(node.PressHapticEffect):toBe(nil)
				stop()
			end,
		})

		verifyHarness:case("plays the press haptic once for each slider detent and never for a continuous slider", {
			id = "native_inputs::native input controls::plays the press haptic once for each slider detent and never for a continuous slider",
			run = function()
				local stepped, continuous, plays = Compose.cell(25), Compose.cell(0.5), 0
				local effect = {
					Play = function()
						plays += 1
					end,
				}
				local node, stop, engine = world(function(UI: FacetControls, _, runtime)
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
						UI.Slider "Stepped" { value = stepped, min = 0, max = 100, step = 25 } :: unknown,
						UI.Slider "Continuous" { value = continuous },
					})
				end, function()
					return { pressHaptic = effect }
				end)
				local V = engine.types.Vector2
				local track, drag = find(find(node, "Stepped"), "Track"), find(find(node, "Stepped"), "Drag")
				track.AbsoluteSize = V.new(200, 44)
				track.AbsolutePosition = V.new(0, 0)
				drag.DragStart:Fire(V.new(50, 0))
				Verify.expect((stepped:peek())):toBe(25)
				Verify.expect(plays):toBe(0)
				for x = 51, 150 do
					drag.DragContinue:Fire(V.new(x, 0))
				end
				Verify.expect((stepped:peek())):toBe(75)
				Verify.expect(plays):toBe(2)
				drag.DragEnd:Fire()
				local free, freeDrag = find(find(node, "Continuous"), "Track"), find(find(node, "Continuous"), "Drag")
				free.AbsoluteSize = V.new(200, 44)
				free.AbsolutePosition = V.new(0, 0)
				freeDrag.DragStart:Fire(V.new(10, 0))
				for x = 11, 190 do
					freeDrag.DragContinue:Fire(V.new(x, 0))
				end
				freeDrag.DragEnd:Fire()
				Verify.expect(continuous:peek() > 0.9):toBe(true)
				Verify.expect(plays):toBe(2)
				stop()
			end,
		})

		verifyHarness:case("mirrors native caption alignment and typography without a text geometry solver", {
			id = "native_inputs::native input controls::mirrors native caption alignment and typography without a text geometry solver",
			run = function()
				local node, stop, engine = world(function(UI: FacetControls)
					return UI.Button({ label = "Centered" })
				end, function()
					return {
						theme = {
							identity = {},
							chrome = { control = { kind = "nineSlice" :: "nineSlice", asset = "control" } },
							assets = { control = { content = "rbxassetid://123" } },
						},
					}
				end)
				local caption = find(node, "Label")
				Verify.expect(caption.TextXAlignment):toBe(node.TextXAlignment)
				Verify.expect(caption.TextYAlignment):toBe(node.TextYAlignment)
				node.AbsoluteSize = engine.types.Vector2.new(67, 44)
				caption.Parent.Parent.AbsoluteSize = engine.types.Vector2.new(1, 1)
				Verify.expect(caption.Parent.Size):toBe(engine.types.UDim2.fromOffset(67, 44))
				Verify.expect(caption.Parent.Parent.Size):toBe(engine.types.UDim2.fromOffset(1, 1))
				Verify.expect(caption.Parent.Parent.AutomaticSize):toBe(engine.types.Enum.AutomaticSize.None)
				node.TextSize = 44
				node.TextXAlignment = engine.types.Enum.TextXAlignment.Right
				Verify.expect(caption.TextSize):toBe(44)
				Verify.expect(caption.TextXAlignment):toBe(engine.types.Enum.TextXAlignment.Right)
				Verify.expect(node.AutomaticSize):toBe(engine.types.Enum.AutomaticSize.XY)
				stop()
			end,
		})

		verifyHarness:case("gives native dialog contexts ordered sink priority and live eligibility", {
			id = "native_inputs::native input controls::gives native dialog contexts ordered sink priority and live eligibility",
			run = function()
				local firstEnabled = Compose.cell(false)
				local node, stop, engine = world(function(UI: FacetControls, _, runtime)
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
						UI.Button "First" { dialogAction = "default" :: "default", enabled = firstEnabled } :: unknown,
						UI.Button "Second" { dialogAction = "default" :: "default" },
					})
				end)
				local contexts = {}
				for _, instance in engine.made do
					if instance.ClassName == "InputContext" then
						table.insert(contexts, instance)
					end
				end
				Verify.expect(#contexts):toBe(2)
				Verify.expect(contexts[1].Priority > contexts[2].Priority):toBe(true)
				Verify.expect(contexts[1].Sink):toBe(true)
				Verify.expect(contexts[1].Enabled):toBe(false)
				Verify.expect(contexts[2].Enabled):toBe(true)
				firstEnabled:set(true)
				Verify.expect(contexts[1].Enabled):toBe(true)
				find(node, "First").Visible = false
				Verify.expect(contexts[1].Enabled):toBe(false)
				stop()
				Verify.expect((contexts[1]:isDestroyed())):toBe(true)
			end,
		})
		verifyHarness:case("a held arrow repeats up to the bound and releases the axis at the bound", {
			id = "native_inputs::native input controls::a held arrow repeats up to the bound and releases the axis at the bound",
			run = function()
				local value = Compose.cell(95)
				local gui
				local node, stop, engine = world(function(UI: FacetControls)
					return UI.Slider({ value = value, min = 0, max = 100, step = 1 })
				end, function(engine)
					gui = engine.new("GuiService")
					return { services = { GuiService = gui }, guiService = gui }
				end)
				gui.SelectedObject = node
				local increase = enabledAction(node.Parent, "IncreaseArrow")
				increase.Pressed:Fire()
				for _ = 1, 20 do
					engine.heartbeat:Fire(0.1)
				end
				Verify.expect((value:peek())):toBe(100)
				Verify.expect(increase.Parent.Enabled):toBe(false)
				increase.Released:Fire()
				Verify.expect(increase.Parent.Enabled):toBe(false)
				Verify.expect(enabledAction(node.Parent, "DecreaseArrow").Parent.Enabled):toBe(true)
				value:set(99)
				Verify.expect(increase.Parent.Enabled):toBe(true)
				stop()
			end,
		})

		verifyHarness:case("releases the axis at value bounds and rearms on focus return", {
			id = "native_inputs::native input controls::releases the axis at value bounds and rearms on focus return",
			run = function()
				local value = Compose.cell(4)
				local node, stop = world(function(UI: FacetControls)
					return UI.Rating({ value = value })
				end)
				Verify.expect((find(node.Parent, "IncreaseArrow"))):toBe(nil)
				node.SelectionGained:Fire()
				local increase = find(node.Parent, "IncreaseArrow")
				local decrease = find(node.Parent, "DecreaseArrow")
				local bumper = find(node.Parent, "Increase")
				Verify.expect(increase.Parent.Enabled):toBe(true)
				increase.Pressed:Fire()
				Verify.expect((value:peek())):toBe(5)
				Verify.expect(increase.Parent.Enabled):toBe(false)
				increase.Released:Fire()
				Verify.expect(increase.Parent.Enabled):toBe(false)
				Verify.expect(bumper.Parent.Enabled):toBe(true)
				Verify.expect(decrease.Parent.Enabled):toBe(true)
				decrease.Pressed:Fire()
				Verify.expect((value:peek())):toBe(4)
				Verify.expect(increase.Parent.Enabled):toBe(true)
				node.SelectionLost:Fire()
				Verify.expect((increase:isDestroyed())):toBe(true)
				Verify.expect((find(node.Parent, "IncreaseArrow"))):toBe(nil)
				node.SelectionGained:Fire()
				local rearmed = find(node.Parent, "IncreaseArrow")
				Verify.expect(rearmed ~= increase):toBe(true)
				Verify.expect(rearmed.Parent.Enabled):toBe(true)
				rearmed.Pressed:Fire()
				Verify.expect((value:peek())):toBe(5)
				stop()
			end,
		})
		verifyHarness:case("cancels slider pointer ownership on native gamepad handoff and reports bounded semantics", {
			id = "native_inputs::native input controls::cancels slider pointer ownership on native gamepad handoff and reports bounded semantics",
			run = function()
				local value, input, commits = Compose.cell(0.5), nil, 0
				local node, stop, engine = world(function(UI: FacetControls)
					return UI.Slider({
						value = value,
						min = 0,
						max = 1,
						tapToPosition = false,
						onCommit = function()
							commits += 1
						end,
					})
				end, function(engine)
					input = engine.new("UserInputService")
					return { services = { UserInputService = input } }
				end)
				local track, detector = find(node, "Track"), find(node, "Drag")
				track.AbsoluteSize = engine.types.Vector2.new(100, 44)
				detector.DragStart:Fire(engine.types.Vector2.new(80, 0))
				Verify.expect((value:peek())):toBe(0.5)
				detector.DragContinue:Fire(engine.types.Vector2.new(80.4, 0))
				Verify.expect((value:peek())):toBeCloseTo(0.9, 1e-4)
				Verify.expect((node:GetAttribute("semanticValue"))):toBe("0.9 of 0 to 1")
				input.PreferredInput = engine.types.Enum.PreferredInput.Gamepad
				Verify.expect((value:peek())):toBe(0.5)
				detector.DragEnd:Fire()
				Verify.expect(commits):toBe(0)
				value:set(4)
				Verify.expect((node:GetAttribute("value"))):toBe(1)
				Verify.expect((node:GetAttribute("semanticValue"))):toBe("1 of 0 to 1")
				stop()
			end,
		})
		verifyHarness:case("ends a multiline edit when a native ancestor disables without late mutation", {
			id = "native_inputs::native input controls::ends a multiline edit when a native ancestor disables without late mutation",
			run = function()
				local value, commits = Compose.cell("line one\nline two"), 0
				local node, stop, engine = world(function(UI: FacetControls, _, runtime)
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
						UI.TextInput "Editor" {
							value = value,
							multiline = true,
							onCommit = function()
								commits += 1
							end,
						},
					})
				end)
				local editor = find(node, "Editor")
				Verify.expect(editor.MultiLine):toBe(true)
				editor:CaptureFocus()
				editor.Text = "first\nsecond\n"
				Verify.expect((value:peek())):toBe("first\nsecond\n")
				editor.ReturnPressedFromOnScreenKeyboard:Fire()
				Verify.expect(commits):toBe(0)
				Verify.expect((editor:IsFocused())):toBe(true)
				node.Interactable = false
				Verify.expect((editor:IsFocused())):toBe(false)
				editor.Text = "late mutation"
				editor.FocusLost:Fire(true)
				Verify.expect((value:peek())):toBe("first\nsecond\n")
				Verify.expect(commits):toBe(0)
				node.Interactable = true
				editor:CaptureFocus()
				editor.Text = "accepted"
				editor:ReleaseFocus(false)
				Verify.expect(commits):toBe(1)
				stop()
			end,
		})

		verifyHarness:case("grows a multiline field from an unclamped measure of its wrapped text", {
			id = "native_inputs::native input controls::grows a multiline field from an unclamped measure of its wrapped text",
			run = function()
				local node, stop, engine = world(function(UI: FacetControls, _, runtime)
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
						UI.TextInput "Notes" {
							value = Compose.cell("a\nb\n"),
							onChange = function() end,
							multiline = true,
						},
					})
				end)
				local field = find(node, "Notes")
				local measure = find(field, "Measure")
				Verify.expect(measure ~= nil):toBe(true)
				Verify.expect((measure:IsA("TextLabel"))):toBe(true)
				Verify.expect(measure.TextTransparency):toBe(1)
				Verify.expect(measure.Text):toBe("a\nb\n ")
				Verify.expect(field.Size.Y.Offset):toBe(96)
				Verify.expect(measure.Visible):toBe(false)
				measure.TextBounds = engine.types.Vector2.new(280, 300)
				Verify.expect(field.Size.Y.Offset):toBe(316)
				stop()
			end,
		})

		verifyHarness:case("commits a touch edit when touch leaves with no keyboard and carries it otherwise", {
			id = "native_inputs::native input controls::commits a touch edit when touch leaves with no keyboard and carries it otherwise",
			run = function()
				local value, reasons, input = Compose.cell("seed"), {}, nil
				local node, stop = world(function(UI: FacetControls, _, runtime)
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
						UI.TextInput "Name" {
							value = value,
							onCommit = function(_, reason)
								table.insert(reasons, reason)
							end,
						},
					})
				end, function(engine)
					input = engine.new("UserInputService")
					input.TouchEnabled = true
					input.KeyboardEnabled = false
					return { services = { UserInputService = input } }
				end)
				local field = find(node, "Name")
				field:CaptureFocus()
				field.Text = "hi"
				input.GamepadEnabled = true
				Verify.expect((field:IsFocused())):toBe(true)
				input.KeyboardEnabled = true
				input.TouchEnabled = false
				Verify.expect((field:IsFocused())):toBe(true)
				Verify.expect(#reasons):toBe(0)
				input.TouchEnabled = true
				input.KeyboardEnabled = false
				Verify.expect((field:IsFocused())):toBe(true)
				input.TouchEnabled = false
				Verify.expect((field:IsFocused())):toBe(false)
				Verify.expect(reasons):toEqual({ "focusLost" })
				Verify.expect((value:peek())):toBe("hi")
				stop()
			end,
		})

		verifyHarness:case("retains native keyboard activation after first focus and gates it on live selection", {
			id = "native_inputs::native input controls::retains native keyboard activation after first focus and gates it on live selection",
			run = function()
				local activated = 0
				local firstEnabled = Compose.cell(true)
				local node, stop, engine = world(function(UI: FacetControls, _, runtime)
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
						UI.Button "First" {
							label = "First",
							enabled = firstEnabled,
							onActivate = function()
								activated += 1
							end,
						} :: unknown,
						UI.Button "Second" {
							label = "Second",
							onActivate = function()
								activated += 10
							end,
						},
					})
				end)
				local first, second = find(node, "First"), find(node, "Second")
				Verify.expect((find(node.Parent, "Activate"))):toBe(nil)
				first.SelectionGained:Fire()
				local action = enabledAction(node.Parent, "Activate")
				Verify.expect(action ~= nil):toBe(true)
				Verify.expect(action.Parent.Parent):toBe(node.Parent)
				action.Pressed:Fire()
				Verify.expect(activated):toBe(1)
				first.SelectionLost:Fire()
				Verify.expect((action:isDestroyed())):toBe(false)
				Verify.expect(action.Parent.Enabled):toBe(false)
				action.Pressed:Fire()
				Verify.expect(activated):toBe(1)
				first.SelectionGained:Fire()
				Verify.expect((enabledAction(node.Parent, "Activate"))):toBe(action)
				action.Pressed:Fire()
				Verify.expect(activated):toBe(2)
				first.Visible = false
				Verify.expect(action.Parent.Enabled):toBe(false)
				action.Pressed:Fire()
				Verify.expect(activated):toBe(2)
				first.Visible = true
				firstEnabled:set(false)
				Verify.expect(action.Parent.Enabled):toBe(false)
				action.Pressed:Fire()
				Verify.expect(activated):toBe(2)
				firstEnabled:set(true)
				Verify.expect((enabledAction(node.Parent, "Activate"))):toBe(action)
				first.SelectionLost:Fire()
				second.SelectionGained:Fire()
				local secondAction = enabledAction(node.Parent, "Activate")
				Verify.expect(secondAction ~= action):toBe(true)
				action.Pressed:Fire()
				Verify.expect(activated):toBe(2)
				secondAction.Pressed:Fire()
				Verify.expect(activated):toBe(12)
				stop()
				Verify.expect((action:isDestroyed())):toBe(true)
				Verify.expect((secondAction:isDestroyed())):toBe(true)
				action.Pressed:Fire()
				secondAction.Pressed:Fire()
				Verify.expect(activated):toBe(12)
				Verify.expect((engineLib.connections(first.SelectionGained))):toBe(0)
			end,
		})
		verifyHarness:case("activates programmatically selected buttons through the native GuiService property", {
			id = "native_inputs::native input controls::activates programmatically selected buttons through the native GuiService property",
			run = function()
				local gui, firstCalls, secondCalls = nil, 0, 0
				local node, stop = world(function(UI: FacetControls, _, runtime)
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
						UI.Button "First" {
							label = "First",
							onActivate = function()
								firstCalls += 1
							end,
						} :: unknown,
						UI.Button "Second" {
							label = "Second",
							onActivate = function()
								secondCalls += 1
							end,
						},
					})
				end, function(engine)
					gui = engine.new("GuiService")
					return { services = { GuiService = gui } }
				end)
				local first, second = find(node, "First"), find(node, "Second")
				Verify.expect((find(node.Parent, "Activate"))):toBe(nil)
				gui.SelectedObject = first
				local action = enabledAction(node.Parent, "Activate")
				Verify.expect(action ~= nil):toBe(true)
				Verify.expect(action.Parent.Enabled):toBe(true)
				action.Pressed:Fire()
				Verify.expect(firstCalls):toBe(1)
				gui.SelectedObject = second
				Verify.expect((action:isDestroyed())):toBe(false)
				Verify.expect(action.Parent.Enabled):toBe(false)
				local secondAction = enabledAction(node.Parent, "Activate")
				Verify.expect(secondAction ~= action):toBe(true)
				action.Pressed:Fire()
				secondAction.Pressed:Fire()
				Verify.expect(firstCalls):toBe(1)
				Verify.expect(secondCalls):toBe(1)
				gui.SelectedObject = nil
				Verify.expect((enabledAction(node.Parent, "Activate"))):toBe(nil)
				action.Pressed:Fire()
				secondAction.Pressed:Fire()
				Verify.expect(firstCalls):toBe(1)
				Verify.expect(secondCalls):toBe(1)
				gui.SelectedObject = first
				Verify.expect((enabledAction(node.Parent, "Activate"))):toBe(action)
				Verify.expect(secondAction.Parent.Enabled):toBe(false)
				action.Pressed:Fire()
				Verify.expect(firstCalls):toBe(2)
				stop()
				Verify.expect((action:isDestroyed())):toBe(true)
				Verify.expect((secondAction:isDestroyed())):toBe(true)
				Verify.expect((engineLib.connections(gui:GetPropertyChangedSignal("SelectedObject")))):toBe(0)
			end,
		})

		verifyHarness:case("allocates mirrored captions only while a reactive native theme has control artwork", {
			id = "native_inputs::native input controls::allocates mirrored captions only while a reactive native theme has control artwork",
			run = function()
				local neutral = { identity = {}, chrome = {} }
				local artwork = {
					identity = {},
					chrome = { control = { kind = "nineSlice" :: "nineSlice", asset = "control" } },
					assets = { control = { content = "rbxassetid://123" } },
				}
				local theme = Compose.cell(neutral)
				local node, stop, engine = world(function(UI: FacetControls)
					return UI.Button({ label = "Caption" })
				end, function()
					return { theme = theme }
				end)
				Verify.expect((find(node, "Label"))):toBe(nil)
				Verify.expect((engineLib.connections(node:GetPropertyChangedSignal("FontFace")))):toBe(0)
				theme:set(artwork)
				local label = find(node, "Label")
				local bounds, boundary = label.Parent, label.Parent.Parent
				Verify.expect(label.Text):toBe("Caption")
				Verify.expect((node:HasTag("facet-button-captioned"))):toBe(true)
				theme:set(neutral)
				Verify.expect((label:isDestroyed())):toBe(false)
				Verify.expect(boundary.Visible):toBe(false)
				Verify.expect((node:HasTag("facet-button-captioned"))):toBe(false)
				node.Text = "Retained caption"
				node.TextSize = 22
				node.AbsoluteSize = engine.types.Vector2.new(80, 44)
				boundary.AbsoluteSize = engine.types.Vector2.new(2, 2)
				for _ = 1, 100 do
					theme:set(artwork)
					Verify.expect((find(node, "Label"))):toBe(label)
					Verify.expect(boundary.Visible):toBe(true)
					Verify.expect((node:HasTag("facet-button-captioned"))):toBe(true)
					theme:set(neutral)
					Verify.expect(boundary.Visible):toBe(false)
					Verify.expect((node:HasTag("facet-button-captioned"))):toBe(false)
				end
				theme:set(artwork)
				Verify.expect(label.Text):toBe("Retained caption")
				Verify.expect(label.TextSize):toBe(22)
				Verify.expect(bounds.Size):toBe(engine.types.UDim2.fromOffset(40, 22))
				local created = 0
				for _, item in engine.made do
					if item.Name == "Label" or item.Name == "LabelBounds" or item.Name == "LabelBoundary" then
						created += 1
					end
				end
				Verify.expect(created):toBe(3)
				stop()
				Verify.expect((label:isDestroyed())):toBe(true)
				Verify.expect((bounds:isDestroyed())):toBe(true)
				Verify.expect((boundary:isDestroyed())):toBe(true)
				Verify.expect((engineLib.connections(node:GetPropertyChangedSignal("FontFace")))):toBe(0)
			end,
		})

		verifyHarness:case("allocates native value actions only for the selected control, never for a part inside it", {
			id = "native_inputs::native input controls::allocates native value actions only for the selected control, never for a part inside it",
			run = function()
				local gui, stepperValue, sliderValue = nil, Compose.cell(3), Compose.cell(0.5)
				local enabled = Compose.cell(true)
				local node, stop, engine = world(function(UI: FacetControls, _, runtime)
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
						UI.Stepper "Stepper" { value = stepperValue, max = 10, enabled = enabled } :: unknown,
						UI.Slider "Slider" { value = sliderValue },
					})
				end, function(engine)
					gui = engine.new("GuiService")
					return { services = { GuiService = gui } }
				end)
				local function activeContextCount()
					local count = 0
					for _, object in node.Parent:GetDescendants() do
						if object.ClassName == "InputContext" and object.Enabled then
							count += 1
						end
					end
					return count
				end
				Verify.expect((activeContextCount())):toBe(0)
				gui.SelectedObject = find(node, "Slider")
				Verify.expect((activeContextCount())):toBe(5)
				local sliderAction = find(node.Parent, "FacetIncrease"):FindFirstChild("Increase")
				sliderAction.Pressed:Fire()
				Verify.expect((sliderValue:peek())):toBe(0.51)
				local stepper = find(node, "Stepper")
				gui.SelectedObject = stepper
				Verify.expect((activeContextCount())):toBe(4)
				Verify.expect((sliderAction:isDestroyed())):toBe(true)
				Verify.expect((engineLib.connections(engine.heartbeat))):toBe(0)
				local action = find(node.Parent, "FacetIncrease"):FindFirstChild("Increase")
				action.Pressed:Fire()
				Verify.expect((stepperValue:peek())):toBe(4)
				enabled:set(false)
				Verify.expect((activeContextCount())):toBe(0)
				Verify.expect((action:isDestroyed())):toBe(true)
				Verify.expect((engineLib.connections(engine.heartbeat))):toBe(0)
				enabled:set(true)
				Verify.expect((activeContextCount())):toBe(4)
				gui.SelectedObject = nil
				Verify.expect((activeContextCount())):toBe(0)
				stop()
				local initial, initialStop = world(function(UI: FacetControls)
					return UI.Stepper({
						value = stepperValue,
						max = 10,
						ref = function(root)
							gui.SelectedObject = root
						end,
					})
				end, function(engine)
					gui = engine.new("GuiService")
					return { services = { GuiService = gui } }
				end)
				local initialAction = find(initial.Parent, "FacetIncrease"):FindFirstChild("Increase")
				Verify.expect(initialAction.Parent.Enabled):toBe(true)
				initialAction.Pressed:Fire()
				Verify.expect((stepperValue:peek())):toBe(5)
				initialStop()
				Verify.expect((initialAction:isDestroyed())):toBe(true)
			end,
		})

		verifyHarness:case("repeats a held Stepper button and a repeating Button only while held", {
			id = "native_inputs::native input controls::repeats a held Stepper button and a repeating Button only while held",
			run = function()
				local value = Compose.cell(0)
				local node, stop, engine = world(function(UI: FacetControls)
					return UI.Stepper({ value = value, max = 100 })
				end)
				local held = {
					UserInputType = engine.types.Enum.UserInputType.Touch,
					KeyCode = engine.types.Enum.KeyCode:FromValue(0),
				}
				local increase = find(node, "Increase")
				Verify.expect((engineLib.connections(engine.heartbeat))):toBe(0)
				increase.InputBegan:Fire(held)
				Verify.expect((engineLib.connections(engine.heartbeat))):toBe(1)
				engine.heartbeat:Fire(0.4)
				engine.heartbeat:Fire(0.1)
				Verify.expect((value:peek())):toBe(2)
				increase.InputEnded:Fire(held)
				Verify.expect((engineLib.connections(engine.heartbeat))):toBe(0)
				stop()
			end,
		})

		verifyHarness:case("lets a game control opt into keyboard and gamepad adjustment with UI.adjustable", {
			id = "native_inputs::native input controls::lets a game control opt into keyboard and gamepad adjustment with UI.adjustable",
			run = function()
				local steps, calls = {}, 0
				local gui
				local node, stop, engine = world(function(UI: FacetControls, engine, runtime)
					local dial = ((runtime.constructors.TextButton :: unknown) :: TextButtonConstructor)({
						Name = "Dial",
						Selectable = true,
					})
					UI.adjustable(dial, {
						onAdjust = function(direction)
							calls += 1
							table.insert(steps, direction)
						end,
						axis = "vertical" :: "vertical",
						repeats = true,
					})
					local knob = ((runtime.constructors.TextButton :: unknown) :: TextButtonConstructor)({
						Name = "Knob",
						Selectable = true,
					})
					UI.adjustable(knob, {
						onAdjust = function(direction)
							table.insert(steps, direction * 10)
						end,
						axis = "none" :: "none",
					})
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({ dial :: unknown, knob })
				end, function(engine)
					gui = engine.new("GuiService")
					return { services = { GuiService = gui }, guiService = gui }
				end)
				local dial, knob, screen = find(node, "Dial"), find(node, "Knob"), node.Parent
				Verify.expect((enabledAction(screen, "IncreaseArrow"))):toBe(nil)
				gui.SelectedObject = dial
				local up = enabledAction(screen, "IncreaseArrow")
				Verify.expect(up ~= nil):toBe(true)
				Verify.expect(up:FindFirstChildWhichIsA("InputBinding").KeyCode):toBe(engine.types.Enum.KeyCode.Up)
				up.Pressed:Fire()
				Verify.expect(steps[1]):toBe(1)
				engine.heartbeat:Fire(0.4)
				Verify.expect(steps[2]):toBe(1)
				up.Released:Fire()
				Verify.expect((engineLib.connections(engine.heartbeat))):toBe(0)
				enabledAction(screen, "Decrease").Pressed:Fire()
				Verify.expect(steps[3]):toBe(-1)
				gui.SelectedObject = knob
				Verify.expect((enabledAction(screen, "IncreaseArrow"))):toBe(nil)
				local shoulder = enabledAction(screen, "Increase")
				shoulder.Pressed:Fire()
				Verify.expect(steps[4]):toBe(10)
				engine.heartbeat:Fire(1)
				Verify.expect(#steps):toBe(4)
				Verify.expect((engineLib.connections(engine.heartbeat))):toBe(0)
				stop()
				Verify.expect(calls):toBe(3)
			end,
		})

		verifyHarness:case("makes the Slider its one selection stop and draws the engine ring on its thumb", {
			id = "native_inputs::native input controls::makes the Slider its one selection stop and draws the engine ring on its thumb",
			run = function()
				local value = Compose.cell(0.5)
				local gui
				local node, stop = world(function(UI: FacetControls, _, runtime)
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
						UI.Slider "Volume" { value = value, step = 0.1 } :: unknown,
						UI.Slider "Hidden" { value = Compose.cell(0.5), thumb = "auto" :: "auto" },
					})
				end, function(engine)
					gui = engine.new("GuiService")
					return { services = { GuiService = gui }, guiService = gui }
				end)
				local volume = find(node, "Volume")
				local thumb, track = find(volume, "ThumbStop"), find(volume, "Track")
				Verify.expect(volume.Selectable):toBe(true)
				Verify.expect(thumb.Selectable):toBe(false)
				Verify.expect(track.Selectable):toBe(false)
				Verify.expect((volume:GetAttribute("FacetFocusPart"))):toBe("Track/ThumbStop")
				Verify.expect(find(find(node, "Hidden"), "Track").Selectable):toBe(false)
				Verify.expect((find(node, "Hidden"):GetAttribute("FacetFocusPart"))):toBe("Track")
				gui.SelectedObject = volume
				enabledAction(node.Parent, "IncreaseArrow").Pressed:Fire()
				Verify.expect(math.abs(value:peek() - 0.6) < 1e-9):toBe(true)
				stop()
			end,
		})

		verifyHarness:case("repeats focused value adjustments with bounded catch-up and no idle frame subscription", {
			id = "native_inputs::native input controls::repeats focused value adjustments with bounded catch-up and no idle frame subscription",
			run = function()
				local value = Compose.cell(0)
				local node, stop, engine = world(function(UI: FacetControls)
					return UI.Stepper({ value = value, max = 100 })
				end)
				Verify.expect((engineLib.connections(engine.heartbeat))):toBe(0)
				node.SelectionGained:Fire()
				local increase = find(node.Parent, "FacetIncrease"):FindFirstChild("Increase")
				increase.Pressed:Fire()
				Verify.expect((value:peek())):toBe(1)
				Verify.expect((engineLib.connections(engine.heartbeat))):toBe(1)
				engine.heartbeat:Fire(0.35)
				Verify.expect((value:peek())):toBe(1)
				engine.heartbeat:Fire(0.25)
				Verify.expect((value:peek())):toBe(4)
				engine.heartbeat:Fire(20)
				Verify.expect((value:peek())):toBe(9)
				increase.Released:Fire()
				Verify.expect((engineLib.connections(engine.heartbeat))):toBe(0)
				increase.Pressed:Fire()
				node.SelectionLost:Fire()
				Verify.expect((engineLib.connections(engine.heartbeat))):toBe(0)
				stop()
				Verify.expect((engineLib.connections(engine.heartbeat))):toBe(0)
			end,
		})
		verifyHarness:case(
			"a Stepper's repeatDelay and repeatInterval govern its held arrows and its held buttons alike",
			{
				id = "native_inputs::native input controls::a Stepper's repeatDelay and repeatInterval govern its held arrows and its held buttons alike",
				run = function()
					local value = Compose.cell(0)
					local node, stop, engine = world(function(UI: FacetControls)
						return UI.Stepper({ value = value, max = 100, repeatDelay = 1, repeatInterval = 0.5 })
					end)
					node.SelectionGained:Fire()
					local increase = find(node.Parent, "FacetIncrease"):FindFirstChild("Increase")
					increase.Pressed:Fire()
					engine.heartbeat:Fire(0.9)
					Verify.expect((value:peek())):toBe(1)
					engine.heartbeat:Fire(0.2)
					Verify.expect((value:peek())):toBe(2)
					engine.heartbeat:Fire(0.5)
					Verify.expect((value:peek())):toBe(3)
					increase.Released:Fire()
					local button
					for _, child in node:GetDescendants() do
						if child.ClassName == "TextButton" and child.Name == "Increase" then
							button = child
						end
					end
					button.InputBegan:Fire({
						UserInputType = engine.types.Enum.UserInputType.MouseButton1,
						KeyCode = engine.types.Enum.KeyCode:FromValue(0),
					})
					engine.heartbeat:Fire(0.9)
					Verify.expect((value:peek())):toBe(3)
					engine.heartbeat:Fire(0.2)
					Verify.expect((value:peek())):toBe(4)
					stop()
				end,
			}
		)

		verifyHarness:case(
			"isolates artwork and mirrored captions from native automatic sizing while following real padding",
			{
				id = "native_inputs::native input controls::isolates artwork and mirrored captions from native automatic sizing while following real padding",
				run = function()
					local theme = Compose.cell({ identity = {}, chrome = {} })
					local node, stop, engine = world(function(UI: FacetControls)
						return UI.Button({ label = "Enter" })
					end, function()
						return { theme = theme }
					end)
					local nativeSize, automaticSize = node.Size, node.AutomaticSize
					node.AbsoluteSize = engine.types.Vector2.new(67, 44)
					theme:set({
						identity = {},
						chrome = { control = { kind = "nineSlice" :: "nineSlice", asset = "control" } },
						assets = { control = { content = "rbxassetid://123" } },
					})
					local skin, label = find(node, "SkinBounds"), find(node, "LabelBounds")
					for _, decoration in { skin, label } do
						decoration.Parent.AbsoluteSize = engine.types.Vector2.new(1, 1)
						Verify.expect(decoration.Parent.Parent):toBe(node)
						Verify.expect(decoration.Parent.Size):toBe(engine.types.UDim2.fromOffset(1, 1))
						Verify.expect(decoration.Parent.AutomaticSize):toBe(engine.types.Enum.AutomaticSize.None)
						Verify.expect(decoration.Parent.ClipsDescendants):toBe(false)
					end
					local padding = node:FindFirstChildWhichIsA("UIPadding")
					padding.PaddingLeft = engine.types.UDim.new(0.1, 2)
					padding.PaddingRight = engine.types.UDim.new(0, 5)
					padding.PaddingTop = engine.types.UDim.new(0, 3)
					padding.PaddingBottom = engine.types.UDim.new(0, 4)
					padding.Parent = node
					skin.Parent.AbsolutePosition = engine.types.Vector2.new(61, 39)
					label.Parent.AbsolutePosition = engine.types.Vector2.new(61, 39)
					Verify.expect(skin.Size):toBe(engine.types.UDim2.fromOffset(67, 44))
					Verify.expect(skin.Position):toBe(engine.types.UDim2.fromOffset(6, 5))
					Verify.expect(skin.AnchorPoint):toBe(engine.types.Vector2.new(1, 1))

					Verify.expect(label.Size):toBe(engine.types.UDim2.fromOffset(54, 37))
					Verify.expect(label.Size.Y.Offset):toBe(37)
					Verify.expect(label.Position):toBe(engine.types.UDim2.fromOffset(1, 1))
					padding.PaddingLeft = engine.types.UDim.new(0, 12)
					Verify.expect(skin.Position.X.Offset):toBe(6)
					Verify.expect(label.Size.X.Offset):toBe(50)
					node.AbsoluteSize = engine.types.Vector2.new(80, 50)
					Verify.expect(skin.Size):toBe(engine.types.UDim2.fromOffset(80, 50))
					Verify.expect(label.Size):toBe(engine.types.UDim2.fromOffset(63, 43))
					Verify.expect(node.Size):toBe(nativeSize)
					Verify.expect(node.AutomaticSize):toBe(automaticSize)
					padding.Parent = nil
					skin.Parent.AbsolutePosition = engine.types.Vector2.new(79, 49)
					Verify.expect(skin.Position):toBe(engine.types.UDim2.fromOffset(1, 1))
					Verify.expect(label.Size):toBe(engine.types.UDim2.fromOffset(80, 50))
					Verify.expect((engineLib.connections(padding:GetPropertyChangedSignal("PaddingLeft")))):toBe(0)
					stop()
					Verify.expect((engineLib.connections(node:GetPropertyChangedSignal("AbsoluteSize")))):toBe(0)
					Verify.expect((engineLib.connections(node.ChildAdded))):toBe(0)
					Verify.expect((engineLib.connections(node.ChildRemoved))):toBe(0)
				end,
			}
		)

		verifyHarness:case("converts rendered decoration bounds through the native one pixel scale reference", {
			id = "native_inputs::native input controls::converts rendered decoration bounds through the native one pixel scale reference",
			run = function()
				local node, stop, engine = world(function(UI: FacetControls)
					return UI.Button({ label = "Enter" })
				end, function()
					return {
						theme = {
							identity = {},
							chrome = { control = { kind = "nineSlice" :: "nineSlice", asset = "control" } },
							assets = { control = { content = "rbxassetid://123" } },
						},
					}
				end)
				local skin, label = find(node, "SkinBounds"), find(node, "LabelBounds")
				node.AbsoluteSize = engine.types.Vector2.new(100, 55)
				Verify.expect(skin.Size):toBe(engine.types.UDim2.fromOffset(0, 0))
				Verify.expect(label.Size):toBe(engine.types.UDim2.fromOffset(0, 0))
				for _, scale in { 1.25, 0.5, 2, 0.75, 1.25, 1 } do
					node.AbsoluteSize = engine.types.Vector2.new(80 * scale, 44 * scale)
					for _, decoration in { skin, label } do
						decoration.Parent.AbsoluteSize = engine.types.Vector2.new(scale, scale)
						Verify.expect(decoration.Size):toBe(engine.types.UDim2.fromOffset(80, 44))
						Verify.expect(decoration.Parent.Size):toBe(engine.types.UDim2.fromOffset(1, 1))
					end
				end
				local padding = node:FindFirstChildWhichIsA("UIPadding")
				padding.PaddingLeft = engine.types.UDim.new(0, 12)
				padding.PaddingRight = engine.types.UDim.new(0, 8)
				padding.Parent = node
				node.AbsoluteSize = engine.types.Vector2.new(100, 55)
				skin.Parent.AbsoluteSize = engine.types.Vector2.new(1.25, 1.25)
				label.Parent.AbsoluteSize = engine.types.Vector2.new(1.25, 1.25)
				skin.Parent.AbsolutePosition = engine.types.Vector2.new(88.75, 53.75)
				label.Parent.AbsolutePosition = engine.types.Vector2.new(88.75, 53.75)
				Verify.expect(skin.Size):toBe(engine.types.UDim2.fromOffset(80, 44))
				Verify.expect(skin.Position):toBe(engine.types.UDim2.fromOffset(9, 1))
				Verify.expect(label.Size):toBe(engine.types.UDim2.fromOffset(60, 44))
				local skinBoundary, captionBoundary = skin.Parent, label.Parent
				stop()
				Verify.expect((engineLib.connections(skinBoundary:GetPropertyChangedSignal("AbsoluteSize")))):toBe(0)
				Verify.expect((engineLib.connections(captionBoundary:GetPropertyChangedSignal("AbsoluteSize")))):toBe(0)
			end,
		})

		verifyHarness:case("keeps ten large rating marks inside a bounded phone cell and accepts the final mark", {
			id = "native_inputs::native input controls::keeps ten large rating marks inside a bounded phone cell and accepts the final mark",
			run = function()
				local value = Compose.cell(3)
				local root, stop, engine = world(function(UI: FacetControls, engine, runtime)
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
						Size = engine.types.UDim2.fromOffset(353, 44),
						UI.Rating "Stars" { value = value, count = 10, starSize = "large" :: "large" },
					})
				end)
				local V = engine.types.Vector2
				root.AbsoluteSize = V.new(353, 44)
				local node, marks = find(root, "Stars"), find(root, "Marks")
				node.AbsoluteSize = V.new(353, 44)
				local spacing = marks:FindFirstChildWhichIsA("UIListLayout").Padding.Offset
				local width = 0
				for index = 1, 10 do
					local mark = find(marks, "Level" .. index)
					Verify.expect(mark.Visible):toBe(true)
					Verify.expect(mark.Size.X.Offset > 0):toBe(true)
					Verify.expect(mark.TextSize <= mark.Size.X.Offset):toBe(true)
					width += mark.Size.X.Offset
				end
				width += 9 * spacing
				Verify.expect(width <= 353):toBe(true)
				marks.AbsolutePosition = V.new(10, 10)
				marks.AbsoluteSize = V.new(width, 36)
				local detector = find(node, "Scrub")
				detector.DragStart:Fire(V.new(10 + width - 1, 20))
				detector.DragEnd:Fire()
				Verify.expect(value:peek()):toBe(10)
				stop()
			end,
		})

		verifyHarness:case("a touch rating tightens its spacing to fit a fixed-width holder, such as a Table column", {
			id = "native_inputs::native input controls::a touch rating tightens its spacing to fit a fixed-width holder, such as a Table column",
			run = function()
				local input
				local root, stop, engine = world(function(UI: FacetControls, engine, runtime)
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
						Name = "Column",
						Size = engine.types.UDim2.fromOffset(144, 44),
						UI.Rating "Stars" { value = Compose.cell(3) },
					})
				end, function(engine)
					input = engine.new("UserInputService")
					input.TouchEnabled = true
					return { services = { UserInputService = input } }
				end)
				local V = engine.types.Vector2
				local node = find(root, "Stars")
				Verify.expect(node.Size.X.Offset):toBe(5 * 20 + 4 * 24)
				local mark = find(node, "Marks"):FindFirstChildWhichIsA("GuiObject")
				mark.AbsoluteSize = V.new(20, 20)
				root.AbsoluteSize = V.new(144, 44)
				Verify.expect(node.Size.X.Offset):toBe(5 * 20 + 4 * 11)
				mark.AbsoluteSize = V.new(40, 40)
				find(node, "LayoutUnit").AbsoluteSize = V.new(200, 2)
				Verify.expect(node.Size.X.Offset):toBe(5 * 20 + 4 * 2)
				root.AbsoluteSize = V.new(800, 88)
				Verify.expect(node.Size.X.Offset):toBe(5 * 20 + 4 * 24)
				stop()
			end,
		})

		verifyHarness:case(
			"a touch level picker shrinks beside a sibling in a row and spaces its marks to the width it is drawn at",
			{
				id = "native_inputs::native input controls::a touch level picker shrinks beside a sibling in a row and spaces its marks to the width it is drawn at",
				run = function()
					local input
					local root, stop, engine = world(function(UI: FacetControls, engine, runtime)
						return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
							Name = "Pair",
							Size = engine.types.UDim2.fromOffset(337, 44),
							UI.LevelPicker "Bars" { value = Compose.cell(2), count = 10 },
						})
					end, function(engine)
						input = engine.new("UserInputService")
						input.TouchEnabled = true
						return { services = { UserInputService = input } }
					end)
					local V = engine.types.Vector2
					local node = find(root, "Bars")
					local flex = node:FindFirstChildWhichIsA("UIFlexItem")
					Verify.expect(flex and flex.FlexMode):toBe(engine.types.Enum.UIFlexMode.Shrink)
					local mark = find(node, "Marks"):FindFirstChildWhichIsA("GuiObject")
					local spacing = find(node, "Marks"):FindFirstChildWhichIsA("UIListLayout")
					mark.AbsoluteSize = V.new(20, 20)
					root.AbsoluteSize = V.new(337, 44)
					Verify.expect(node.Size.X.Offset):toBe(10 * 20 + 9 * 15)
					node.AbsoluteSize = V.new(10 * 20 + 9 * 15, 44)
					Verify.expect(spacing.Padding.Offset):toBe(15)
					node.AbsoluteSize = V.new(10 * 20 + 9 * 6, 44)
					Verify.expect(spacing.Padding.Offset):toBe(6)
					stop()
				end,
			}
		)
	end);
	(function(verifyHarness: Verify.Harness)
		type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
		type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
		type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
		local FixtureNavigationTypes = require("../src/ui/navigation_types")

		local Facet = require("../src")
		local engineLib = require("./lib/native_engine")
		local Compose: ComposeModule = Facet.Compose
		local themes = Facet.themes

		type Harness = {
			engine: any,
			runtime: any,
			UI: any,
			Host: any,
			gui: any,
			input: any,
			dispose: () -> (),
		}

		local function harness(options: { [string]: any }?): Harness
			local engine: any = engineLib.new()
			local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
			local gui = engine.new("GuiService")
			local input = engine.new("UserInputService")
			input.GetFocusedTextBox = function()
				return nil
			end
			local config: { [string]: any } =
				{ types = engine.types, guiService = gui, services = { GuiService = gui, UserInputService = input } }
			for key, value in (options or {}) :: { [string]: any } do
				config[key] = value
			end
			local UI = Facet.controls(runtime, config :: any)
			return {
				engine = engine,
				runtime = runtime,
				UI = UI,
				Host = (runtime.constructors :: unknown) :: RobloxHost,
				gui = gui,
				input = input,
				dispose = function()
					runtime:dispose()
				end,
			}
		end

		local function mount(h: Harness, build: () -> any): (any, () -> ())
			local stop, root = h.runtime.mount(function()
				return h.Host.Frame({ build() })
			end, h.engine.new("ScreenGui"))
			return root, stop
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

		type Compound = { class: string?, name: string?, tags: { string }, state: string? }
		type Selector = { parts: { Compound }, combinators: { string }, pseudo: string? }

		local function compound(text: string): Compound
			local tags = {}
			for tag in string.gmatch(text, "%.([%w%-]+)") do
				table.insert(tags, tag)
			end
			return {
				class = string.match(text, "^(%a%w*)"),
				name = string.match(text, "#([%w_]+)"),
				tags = tags,
				state = string.match(text, ":(%a+)$"),
			}
		end

		local parsed: { [string]: Selector } = {}

		local function parse(selector: string): Selector
			local cached = parsed[selector]
			if cached then
				return cached
			end
			local pseudo = string.match(selector, "::(%a+)$")
			local rest = if pseudo then string.sub(selector, 1, -(#pseudo + 3)) else selector
			local parts, combinators = {}, {}
			while true do
				local first, last, combinator = string.find(rest, " (>>?) ")
				if not first then
					table.insert(parts, compound(rest))
					break
				end
				table.insert(parts, compound(string.sub(rest, 1, first - 1)))
				table.insert(combinators, combinator :: string)
				rest = string.sub(rest, (last :: number) + 1)
			end
			local result = { parts = parts, combinators = combinators, pseudo = pseudo }
			parsed[selector] = result
			return result
		end

		local function skinPackage(slots: { [string]: any }): any
			local package = themes.neutralPackage()
			package.assets = package.assets or {}
			for slot, asset in slots do
				assert(package.assets)[slot .. "Art"] = { content = asset }
				assert(package.chrome)[slot] = { kind = "nineSlice" :: "nineSlice", asset = slot .. "Art" }
			end
			return package
		end

		verifyHarness:suite("native paint strength: skins", function()
			verifyHarness:case("keeps full-bleed art on the plate's own box when the padding changes after mount", {
				id = "native_inputs::native paint strength: skins::keeps full-bleed art on the plate's own box when the padding changes after mount",
				run = function()
					local package = skinPackage({ control = "rbxassetid://123" })
					local h = harness({ theme = package })
					local root, stop = mount(h, function()
						return h.UI.Button({ Name = "Plate", label = "Mark read" })
					end)
					local plate = find(root, "Plate")
					local skin, label = find(plate, "SkinBounds"), find(plate, "LabelBounds")
					local UDim = h.engine.types.UDim
					local hostX, hostWidth = 10, 83
					plate.AbsoluteSize = h.engine.types.Vector2.new(hostWidth, 28)
					plate.AbsolutePosition = h.engine.types.Vector2.new(hostX, 0)
					for _, bounds in { skin, label } do
						bounds.Parent.AbsoluteSize = h.engine.types.Vector2.new(1, 1)
					end
					local padding = plate:FindFirstChildWhichIsA("UIPadding")
					local function painted(bounds: any): (number, number)
						local right = padding.PaddingRight.Offset
						local boundaryLeft = hostX + hostWidth - right - 1
						bounds.Parent.AbsolutePosition =
							h.engine.types.Vector2.new(boundaryLeft, 28 - padding.PaddingBottom.Offset - 1)
						local rightEdge = boundaryLeft + bounds.Position.X.Offset
						return rightEdge - bounds.Size.X.Offset, rightEdge
					end
					for _, inset in { 12, 8, 0, 8 } do
						padding.PaddingLeft = UDim.new(0, inset)
						padding.PaddingRight = UDim.new(0, inset)
						local left, right = painted(skin)
						Verify.expect(`{left}..{right}`):toBe("10..93")
						local textLeft, textRight = painted(label)
						Verify.expect(`{textLeft}..{textRight}`):toBe(`{10 + inset}..{93 - inset}`)
					end
					padding.PaddingLeft = UDim.new(0, 12)
					padding.PaddingRight = UDim.new(0, 8)
					local left, right = painted(skin)
					Verify.expect(`{left}..{right}`):toBe("10..93")
					local textLeft, textRight = painted(label)
					Verify.expect(`{textLeft}..{textRight}`):toBe("22..85")
					stop()
					h.dispose()
				end,
			})
		end)
	end)(verifyHarness);
	(function(verifyHarness: Verify.Harness)
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

		verifyHarness:suite("native parity weaker actions", function()
			verifyHarness:case(
				"returns a pressed pop to its rest under an authored scale and keeps the native shadow",
				{
					id = "native_inputs::native parity weaker actions::returns a pressed pop to its rest under an authored scale and keeps the native shadow",
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
						local pop = node:FindFirstChildWhichIsA("UIScale", true)
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
				}
			)
		end)
	end)(verifyHarness)
end
