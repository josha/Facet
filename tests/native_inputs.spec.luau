--!strict
local t = require("./lib/testkit")
local Compose = require("../src/vendor/compose/core")
local Roblox = require("../src/vendor/compose/roblox")
local context = require("../src/ui/context")
local register = require("../src/ui/inputs")
local engineLib = require("./lib/native_engine")

local function world(build, configure)
	local engine = engineLib.new()
	local runtime = Roblox.createRuntime(engine)
	local UI = {}
	local options = if configure then configure(engine) else {}
	options.types = engine.types
	local ctx = context(runtime, options)
	register(ctx, UI)
	local stop, node = runtime.mount(function()
		return build(UI, engine, runtime)
	end, engine.new("ScreenGui"))
	return node, stop, engine, runtime, ctx
end

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

t.describe("native input controls", function()
	t.it("delivers only the final native Chip and ShortcutHint roots to refs", function()
		local chipRefs, hintRefs = {}, {}
		local node, stop = world(function(UI, engine, runtime)
			return runtime.constructors.Frame({
				UI.Chip({
					selected = Compose.cell(false),
					onRemove = function() end,
					ref = function(root)
						table.insert(chipRefs, root)
					end,
				}),
				UI.ShortcutHint({
					action = engine.new("InputAction"),
					ref = function(root)
						table.insert(hintRefs, root)
					end,
				}),
			})
		end)
		t.expect(#chipRefs).toBe(1)
		t.expect(#hintRefs).toBe(1)
		t.expect(chipRefs[1].ClassName).toBe("Frame")
		t.expect(hintRefs[1].ClassName).toBe("Frame")
		t.expect(chipRefs[1].Parent).toBe(node)
		t.expect(hintRefs[1].Parent).toBe(node)
		stop()
	end)

	t.it("uses native properties and events and releases them with its Compose owner", function()
		local value, enabled = Compose.cell("Before"), Compose.cell(true)
		local activated, nativeEvent = 0, 0
		local node, stop = world(function(UI)
			return UI.Button("Continue")({
				label = value,
				enabled = enabled,
				Attributes = { task = "continue" },
				onActivate = function()
					activated += 1
				end,
				[Compose.event("MouseEnter")] = function()
					nativeEvent += 1
				end,
			})
		end)
		t.expect(node.Text).toBe("Before")
		t.expect(node:GetAttribute("task")).toBe("continue")
		value:set("After")
		t.expect(node.Text).toBe("After")
		t.expect(find(node, "Label")).toBe(nil)
		node.Text = "Native text"
		t.expect(node.Text).toBe("Native text")
		node.Activated.fire()
		node.MouseEnter.fire()
		enabled:set(false)
		node.Activated.fire()
		t.expect(activated).toBe(1)
		t.expect(nativeEvent).toBe(1)
		t.expect(node.Interactable).toBe(false)
		stop()
		t.expect(node.Activated.count()).toBe(0)
		t.expect(node.MouseEnter.count()).toBe(0)
	end)

	t.it("keeps Toggle requests controlled and clears a writable mixed state", function()
		local value, mixed = Compose.cell(false), Compose.cell(true)
		local node, stop = world(function(UI)
			return UI.Toggle({ value = value, mixed = mixed, presentation = "checkbox", label = "Enabled" })
		end)
		node.Activated.fire()
		t.expect(value:peek()).toBe(true)
		t.expect(mixed:peek()).toBe(false)
		stop()
		local request
		node, stop = world(function(UI)
			return UI.Toggle({
				value = value,
				label = "Controlled",
				onChange = function(nextValue)
					request = nextValue
				end,
			})
		end)
		node.Activated.fire()
		t.expect(request).toBe(false)
		t.expect(value:peek()).toBe(true)
		stop()
	end)

	t.it("keeps Toggle native eligibility semantics and theme tags synchronized with one ref delivery", function()
		local value, enabled, busy = Compose.cell(true), Compose.cell(true), Compose.cell(false)
		local role, appearance, size, name =
			Compose.cell("default"), Compose.cell("standard"), Compose.cell("regular"), Compose.cell("Ready")
		local references, changes = 0, 0
		local node, stop = world(function(UI)
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
		t.expect(references).toBe(1)
		t.expect(node:GetAttribute("selected")).toBe(true)
		t.expect(node:HasTag("facet-selected")).toBe(true)
		role:set("destructive")
		appearance:set("emphasis")
		size:set("large")
		name:set("Confirm")
		t.expect(node:HasTag("facet-role-default")).toBe(false)
		t.expect(node:HasTag("facet-role-destructive")).toBe(true)
		t.expect(node:HasTag("facet-accent")).toBe(true)
		t.expect(node:GetAttribute("role")).toBe("destructive")
		t.expect(node:GetAttribute("appearance")).toBe("emphasis")
		t.expect(node:GetAttribute("controlSize")).toBe("large")
		t.expect(node:GetAttribute("label")).toBe("Confirm")
		busy:set(true)
		t.expect(node.Interactable).toBe(false)
		t.expect(node:HasTag("facet-busy")).toBe(true)
		t.expect(node:HasTag("facet-disabled")).toBe(true)
		node.Activated.fire()
		t.expect(changes).toBe(0)
		busy:set(false)
		node.Activated.fire()
		t.expect(changes).toBe(1)
		t.expect(node:GetAttribute("selected")).toBe(false)
		t.expect(node:HasTag("facet-selected")).toBe(false)
		t.expect(find(node, "Mark").Position.X.Scale).toBeCloseTo(0.3)
		enabled:set(false)
		t.expect(node.Selectable).toBe(false)
		node.Activated.fire()
		t.expect(changes).toBe(1)
		stop()
	end)

	t.it("distinguishes edits from external model updates and disconnects observation", function()
		local value = Compose.cell("First")
		local edits, commits = {}, {}
		local node, stop = world(function(UI)
			return UI.TextInput({
				value = value,
				onChange = function(text)
					value:set(text)
					table.insert(edits, text)
				end,
				onCommit = function(text, reason)
					table.insert(commits, { text, reason })
				end,
			})
		end)
		value:set("External")
		t.expect(node.Text).toBe("External")
		t.expect(#edits).toBe(0)
		node:CaptureFocus()
		node.Text = "User"
		t.expect(value:peek()).toBe("User")
		t.expect(#edits).toBe(1)
		value:set("Model while focused")
		t.expect(node.Text).toBe("Model while focused")
		t.expect(#edits).toBe(1)
		node:ReleaseFocus(true)
		t.expect(commits[1][1]).toBe("Model while focused")
		t.expect(commits[1][2]).toBe("submit")
		stop()
		t.expect(node:GetPropertyChangedSignal("Text").count()).toBe(0)
	end)

	t.it("limits UTF-8 characters, rejects validation and restores an edit on cancel", function()
		local value, edits, canceled = Compose.cell("old"), 0, 0
		local node, stop = world(function(UI)
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
		t.expect(value:peek()).toBe("é🙂好")
		t.expect(node.Text).toBe("é🙂好")
		node.Text = "bad"
		t.expect(value:peek()).toBe("é🙂好")
		t.expect(node.Text).toBe("é🙂好")
		t.expect(edits).toBe(1)
		find(node.Parent, "Cancel").Pressed.fire()
		t.expect(value:peek()).toBe("old")
		t.expect(node.Text).toBe("old")
		t.expect(canceled).toBe(1)
		t.expect(node:IsFocused()).toBe(false)
		stop()
	end)

	t.it("commits and formats finite numeric input without committing out-of-range input", function()
		local value, number, invalid = Compose.cell("2"), Compose.cell(2), Compose.cell(false)
		local commits = 0
		local node, stop = world(function(UI)
			return UI.TextInput({
				value = value,
				numericValue = number,
				invalid = invalid,
				presentation = "number",
				min = 1,
				max = 10,
				format = function(n)
					return string.format("%.1f", n)
				end,
				onCommit = function()
					commits += 1
				end,
			})
		end)
		node:CaptureFocus()
		node.Text = "7"
		node:ReleaseFocus(true)
		t.expect(number:peek()).toBe(7)
		t.expect(value:peek()).toBe("7.0")
		t.expect(node.Text).toBe("7.0")
		t.expect(commits).toBe(1)
		node:CaptureFocus()
		node.Text = "11"
		node:ReleaseFocus(true)
		t.expect(number:peek()).toBe(7)
		t.expect(commits).toBe(1)
		t.expect(invalid:peek()).toBe(true)
		stop()
	end)

	t.it("steps from the minimum, respects live stepping and gates all activation", function()
		local value, step, enabled = Compose.cell(5), Compose.cell(5), Compose.cell(true)
		local changes = 0
		local node, stop = world(function(UI)
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
		find(node, "Increase").Activated.fire()
		t.expect(value:peek()).toBe(10)
		step:set(2)
		find(node, "Increase").Activated.fire()
		t.expect(value:peek()).toBe(13)
		enabled:set(false)
		find(node, "Increase").Activated.fire()
		t.expect(value:peek()).toBe(13)
		t.expect(changes).toBe(2)
		stop()
	end)

	t.it("lets the native drag detector drive one bounded slider model and cancel", function()
		local value, commits = Compose.cell(25), 0
		local node, stop, engine = world(function(UI)
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
		track.SelectionGained.fire()
		track.AbsoluteSize = engine.types.Vector2.new(200, 44)
		track.AbsolutePosition = engine.types.Vector2.new(20, 0)
		drag.DragStart.fire(engine.types.Vector2.new(170, 0))
		t.expect(value:peek()).toBe(75)
		drag.DragContinue.fire(engine.types.Vector2.new(500, 0))
		t.expect(value:peek()).toBe(100)
		find(node.Parent, "Cancel").Pressed.fire()
		t.expect(value:peek()).toBe(25)
		t.expect(commits).toBe(0)
		drag.DragStart.fire(engine.types.Vector2.new(120, 0))
		drag.DragEnd.fire()
		t.expect(value:peek()).toBe(50)
		t.expect(commits).toBe(1)
		stop()
	end)

	t.it("keeps authored slider widths with an inline readout and a vertically sized row presentation", function()
		local value = Compose.cell(0.5)
		local node, stop, engine = world(function(UI, engine, runtime)
			return runtime.constructors.Frame({
				UI.Slider({ Name = "Inline", value = value, Size = engine.types.UDim2.fromOffset(80, 36) }),
				UI.Slider({ Name = "Row", value = value, row = { title = "Volume", description = "Playback level" } }),
				UI.Slider({ Name = "Fixed", value = value, AutomaticSize = engine.types.Enum.AutomaticSize.None }),
			})
		end)
		local inline, row, fixed = find(node, "Inline"), find(node, "Row"), find(node, "Fixed")
		t.expect(inline.Size.X.Offset).toBe(80)
		t.expect(inline.AutomaticSize).toBe(engine.types.Enum.AutomaticSize.Y)
		t.expect(inline:FindFirstChildWhichIsA("UIListLayout").FillDirection)
			.toBe(engine.types.Enum.FillDirection.Horizontal)
		t.expect(inline:FindFirstChildWhichIsA("UIListLayout").VerticalAlignment)
			.toBe(engine.types.Enum.VerticalAlignment.Center)
		t.expect(find(inline, "Track"):FindFirstChildWhichIsA("UIFlexItem").FlexMode)
			.toBe(engine.types.Enum.UIFlexMode.Fill)
		t.expect(find(inline, "Track").Size.Y.Offset).toBe(44)
		t.expect(find(inline, "Value").Text).toBe("0.5")
		value:set(0.75)
		t.expect(find(inline, "Value").Text).toBe("0.75")
		t.expect(row.AutomaticSize).toBe(engine.types.Enum.AutomaticSize.Y)
		t.expect(row:FindFirstChildWhichIsA("UIListLayout").FillDirection)
			.toBe(engine.types.Enum.FillDirection.Vertical)
		t.expect(find(row, "Value").Parent).toBe(find(row, "Header"))
		t.expect(find(row, "Description").Text).toBe("Playback level")
		t.expect(fixed.AutomaticSize).toBe(engine.types.Enum.AutomaticSize.None)
		stop()
	end)

	t.it("supports clearing a rating and keeps read-only levels inert", function()
		local value = Compose.cell(3)
		local node, stop, engine = world(function(UI)
			return UI.Rating({ value = value })
		end)
		node.AbsoluteSize = engine.types.Vector2.new(100, 44)
		node.Activated.fire({ Position = engine.types.Vector2.new(50, 0) })
		t.expect(value:peek()).toBe(0)
		node.Activated.fire({ Position = engine.types.Vector2.new(90, 0) })
		t.expect(value:peek()).toBe(5)
		stop()
		node, stop = world(function(UI)
			return UI.LevelPicker({ value = value, readOnly = true })
		end)
		node.Activated.fire({ Position = engine.types.Vector2.new(10, 0) })
		t.expect(value:peek()).toBe(5)
		stop()
	end)
	t.it("clears search fields and submits the on-screen keyboard only once", function()
		local value, commits, changes = Compose.cell("search"), 0, 0
		local node, stop = world(function(UI)
			return UI.TextInput({
				value = value,
				presentation = "search",
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
		t.expect(clear.Visible).toBe(true)
		clear.Activated.fire()
		t.expect(value:peek()).toBe("")
		t.expect(clear.Visible).toBe(false)
		t.expect(changes).toBe(1)
		node:CaptureFocus()
		node.Text = "find"
		node.ReturnPressedFromOnScreenKeyboard.fire()
		t.expect(commits).toBe(1)
		t.expect(node:IsFocused()).toBe(false)
		stop()
	end)

	t.it("repeats while held and cancels native frame subscriptions on disposal", function()
		local activated = 0
		local node, stop, engine = world(function(UI)
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
			KeyCode = engine.types.Enum.KeyCode.Unknown,
		}
		node.InputBegan.fire(input)
		engine.heartbeat.fire(0.4)
		engine.heartbeat.fire(0.1)
		t.expect(activated).toBe(2)
		node.InputEnded.fire(input)
		node.Activated.fire()
		t.expect(activated).toBe(2)
		stop()
		engine.heartbeat.fire(1)
		t.expect(activated).toBe(2)
		t.expect(engine.heartbeat.count()).toBe(0)
	end)
	t.it("edits a controlled map field without duplicating durable state", function()
		local notes = Compose.cell({ item = "saved" })
		local requests = 0
		local node, stop = world(function(UI)
			return UI.TextInput({
				value = function(use)
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
		t.expect(notes:peek().item).toBe("updated")
		t.expect(requests).toBe(1)
		node.Text = "rejected"
		t.expect(node.Text).toBe("updated")
		notes:set({ item = "external" })
		t.expect(requests).toBe(2)
		t.expect(node.Text).toBe("external")
		find(node.Parent, "Cancel").Pressed.fire()
		t.expect(notes:peek().item).toBe("saved")
		t.expect(requests).toBe(3)
		stop()
	end)
	t.it("does not mutate writable controlled models before callbacks accept requests", function()
		local value, requested = Compose.cell(3), nil
		local node, stop = world(function(UI)
			return UI.Stepper({
				value = value,
				min = 0,
				max = 10,
				onChange = function(nextValue)
					requested = nextValue
				end,
			})
		end)
		find(node, "Increase").Activated.fire()
		t.expect(requested).toBe(4)
		t.expect(value:peek()).toBe(3)
		stop()
		local text = Compose.cell("accepted")
		node, stop = world(function(UI)
			return UI.TextInput({
				value = text,
				onChange = function(nextValue)
					requested = nextValue
				end,
			})
		end)
		node:CaptureFocus()
		node.Text = "rejected"
		t.expect(requested).toBe("rejected")
		t.expect(text:peek()).toBe("accepted")
		t.expect(node.Text).toBe("accepted")
		stop()
	end)
	t.it("owns busy animation only while visible and suppresses busy activation", function()
		local busy, actions = Compose.cell(false), 0
		local node, stop, engine = world(function(UI)
			return UI.Button({
				label = "Loading",
				busy = busy,
				onActivate = function()
					actions += 1
				end,
			})
		end)
		t.expect(find(node, "Busy")).toBe(nil)
		t.expect(engine.heartbeat.count()).toBe(0)
		for _ = 1, 3 do
			busy:set(true)
			t.expect(find(node, "Busy") ~= nil).toBe(true)
			t.expect(engine.heartbeat.count()).toBe(1)
			node.Activated.fire()
			t.expect(node.Selectable).toBe(false)
			busy:set(false)
			t.expect(find(node, "Busy")).toBe(nil)
			t.expect(engine.heartbeat.count()).toBe(0)
		end
		t.expect(actions).toBe(0)
		node.Activated.fire()
		t.expect(actions).toBe(1)
		stop()
	end)

	t.it("restarts Compose pop feedback and obeys live reduced motion", function()
		local reduced = Compose.cell(false)
		local node, stop, engine = world(function(UI)
			return UI.Button({ label = "Pop", pop = true, onActivate = function() end })
		end, function()
			return { reducedMotion = reduced }
		end)
		local scale = find(node, "Pop")
		t.expect(scale.Scale).toBe(1)
		node.Activated.fire()
		engine.heartbeat.fire(0.1)
		t.expect(scale.Scale > 1).toBe(true)
		local current = scale.Scale
		node.Activated.fire()
		t.expect(scale.Scale).toBeCloseTo(current)
		reduced:set(true)
		t.expect(scale.Scale).toBe(1)
		node.Activated.fire()
		engine.heartbeat.fire(1)
		t.expect(scale.Scale).toBe(1)
		stop()
		t.expect(engine.heartbeat.count()).toBe(0)
	end)

	t.it("uses native circle constraints and updates semantic roles without paint writes", function()
		local role = Compose.cell("default")
		local node, stop = world(function(UI)
			return UI.Button({
				label = "A meaningful long name",
				icon = "rbxassetid://1",
				shape = "circle",
				role = role,
			})
		end)
		t.expect(find(node, "UIAspectRatioConstraint").AspectRatio).toBe(1)
		t.expect(find(node, "UICorner").CornerRadius.Scale).toBe(1)
		t.expect(find(node, "LeadingIcon").Image).toBe("rbxassetid://1")
		t.expect(node:GetAttribute("label")).toBe("A meaningful long name")
		t.expect(node:HasTag("facet-role-default")).toBe(true)
		role:set("destructive")
		t.expect(node:HasTag("facet-role-default")).toBe(false)
		t.expect(node:HasTag("facet-role-destructive")).toBe(true)
		stop()
	end)

	t.it("chooses compact button text from native measurements and restores the full caption", function()
		local node, stop, engine = world(function(UI)
			return UI.Button({ label = "Continue to checkout", compactLabel = "Continue" })
		end)
		local measure = find(node, "FullLabelMeasure")
		measure.TextBounds = engine.types.Vector2.new(180, 20)
		node.AbsoluteSize = engine.types.Vector2.new(110, 44)
		t.expect(node.Text).toBe("Continue")
		node.AbsoluteSize = engine.types.Vector2.new(240, 44)
		t.expect(node.Text).toBe("Continue to checkout")
		stop()
	end)

	t.it("deduplicates shortcut/default bindings and yields shortcuts during native text editing", function()
		local editing, actions = false, 0
		local node, stop = world(function(UI)
			return UI.Button({
				label = "Default",
				shortcut = { keyCode = "Return" },
				dialogAction = "default",
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
		t.expect(#action:GetChildren()).toBe(1)
		action.Pressed.fire()
		t.expect(actions).toBe(1)
		editing = true
		action.Pressed.fire()
		t.expect(actions).toBe(1)
		stop()
		t.expect(action.Pressed.count()).toBe(0)
	end)

	t.it("blocks background held repeats when a Compose-owned modal becomes active", function()
		local actions = 0
		local node, stop, engine, runtime, ctx = world(function(UI)
			return UI.Button({
				label = "Repeat",
				repeatInterval = 0.1,
				onActivate = function()
					actions += 1
				end,
			})
		end)
		node.InputBegan.fire({
			UserInputType = engine.types.Enum.UserInputType.MouseButton1,
			KeyCode = engine.types.Enum.KeyCode.Unknown,
		})
		engine.heartbeat.fire(0.4)
		t.expect(actions).toBe(1)
		local modal = engine.new("Frame")
		modal.Parent = node.Parent
		ctx.modalScopes:set({ modal })
		engine.heartbeat.fire(0.4)
		t.expect(actions).toBe(1)
		ctx.modalScopes:set({})
		engine.heartbeat.fire(0.4)
		t.expect(actions).toBe(1)
		stop()
		runtime:dispose()
	end)

	t.it("keeps level marks inert with one focus target and a cancellable native scrub", function()
		local value = Compose.cell(2)
		local node, stop, engine = world(function(UI)
			return UI.LevelPicker({ value = value, count = 5 })
		end)
		node.AbsoluteSize = engine.types.Vector2.new(100, 44)
		local selectable = if node.Selectable then 1 else 0
		for _, child in node:GetDescendants() do
			if child:IsA("GuiObject") and child.Selectable then
				selectable += 1
			end
		end
		t.expect(selectable).toBe(1)
		t.expect(find(node, "Level3").ClassName).toBe("Frame")
		t.expect(find(node.Parent, "FacetIncrease")).toBe(nil)
		node.SelectionGained.fire()
		t.expect(find(node.Parent, "FacetIncrease").Enabled).toBe(true)
		find(node, "Scrub").DragStart.fire(engine.types.Vector2.new(90, 0))
		t.expect(value:peek()).toBe(5)
		find(node, "Scrub").DragContinue.fire(engine.types.Vector2.new(10, 0))
		t.expect(value:peek()).toBe(1)
		find(node.Parent, "Cancel").Pressed.fire()
		t.expect(value:peek()).toBe(2)
		stop()
	end)

	t.it("paints live level assets and tint while allowing an omitted tint to return to native styles", function()
		local value = Compose.cell(1)
		local node, stop, engine = world(function(UI, engine)
			return UI.LevelPicker({
				value = value,
				segment = "image",
				images = { filled = "rbxassetid://1", empty = "rbxassetid://2" },
				tint = { filled = engine.types.Color3.new(1, 0, 0) },
			})
		end)
		local first = find(node, "Level1")
		t.expect(first.Image).toBe("rbxassetid://1")
		t.expect(first.ImageColor3).toBe(engine.types.Color3.new(1, 0, 0))
		value:set(0)
		t.expect(first.Image).toBe("rbxassetid://2")
		t.expect(first.ImageColor3 == engine.types.Color3.new(1, 0, 0)).toBe(false)
		stop()
	end)

	t.it("shares finite bound arithmetic, live steps and formatter fallback across value controls", function()
		local make = require("../src/ui/input_value")
		local step = Compose.cell(0.25)
		local function read(value)
			return if Compose.isReadable(value) then value:peek() else value
		end
		local model = make({
			min = 0,
			max = 1,
			step = step,
			format = function(value)
				if value == 0.5 then
					error("no format")
				end
				return tostring(value) .. "x"
			end,
		}, read)
		t.expect(model.quantize(0.3)).toBe(0.25)
		t.expect(model.fromFraction(2)).toBe(1)
		t.expect(model.fraction(0 / 0)).toBe(0)
		t.expect(model.quantize(math.huge)).toBe(0)
		t.expect(model.format(0.5)).toBe("0.5")
		t.expect(model.format(0.75)).toBe("0.75x")
		step:set(0.5)
		t.expect(model.stepped(0, 1)).toBe(0.5)
		step:set(0)
		t.expect(function()
			model.stepped(0, 1)
		end).toThrow()
		t.expect(function()
			make({ min = 1, max = 1 }, read)
		end).toThrow()
	end)
	t.it("updates explicit shortcut alternatives without owning input bindings", function()
		local separator, chords = Compose.cell(" or "), Compose.cell({ { "Ctrl", "K" }, { "F1" } })
		local node, stop, engine = world(function(UI)
			return UI.ShortcutHint({ keys = chords, separator = separator })
		end)
		t.expect(node.Text).toBe("Ctrl+K or F1")
		separator:set(" / ")
		chords:set({ { "Shift", "P" } })
		t.expect(node.Text).toBe("Shift+P")
		for _, instance in engine.made do
			t.expect(instance.ClassName == "InputAction" or instance.ClassName == "InputContext").toBe(false)
		end
		stop()
		t.expect(function()
			world(function(UI)
				return UI.ShortcutHint({ keys = { { "" } } })
			end)
		end).toThrow()
	end)

	t.it("borrows native preferred bindings and releases replaced hint observers", function()
		local action, first, second
		local node, stop, engine = world(function(UI, engine)
			action, first, second = engine.new("InputAction"), engine.new("InputBinding"), engine.new("InputBinding")
			first.KeyCode, first.DisplayName = engine.types.Enum.KeyCode.F, ""
			second.KeyCode, second.DisplayName = engine.types.Enum.KeyCode.ButtonX, "Interact"
			action.PreferredBinding = first
			return UI.ShortcutHint({ action = action })
		end)
		t.expect(find(node, "Key").Text).toBe("F")
		first.DisplayName = "Use"
		t.expect(find(node, "Key").Text).toBe("Use")
		action.PreferredBinding = second
		t.expect(find(node, "Key").Text).toBe("Interact")
		t.expect(first:GetPropertyChangedSignal("DisplayName").count()).toBe(0)
		action.PreferredBinding = nil
		t.expect(find(node, "Key")).toBe(nil)
		t.expect(second:GetPropertyChangedSignal("DisplayName").count()).toBe(0)
		stop()
		t.expect(action.isDestroyed()).toBe(false)
		t.expect(action:GetPropertyChangedSignal("PreferredBinding").count()).toBe(0)
	end)

	t.it("reflows Button and circle sizes from live theme metrics and control rungs", function()
		local theme =
			Compose.cell({ metrics = { controlSizes = { regular = { height = 52 }, large = { height = 70 } } } })
		local size = Compose.cell("regular")
		local node, stop = world(function(UI)
			return UI.Button({ label = "Go", controlSize = size, shape = "circle" })
		end, function()
			return { theme = theme }
		end)
		t.expect(node.Size.X.Offset).toBe(52)
		t.expect(node.Size.Y.Offset).toBe(52)
		size:set("large")
		t.expect(node.Size.X.Offset).toBe(70)
		t.expect(node.Size.Y.Offset).toBe(70)
		theme:set({ metrics = { controlSizes = { large = { height = 64 } } } })
		t.expect(node.Size.Y.Offset).toBe(64)
		stop()
	end)
	t.it("shows numeric validation text with interruptible reduced-motion-aware feedback", function()
		local value, number, reduced = Compose.cell("2"), Compose.cell(2), Compose.cell(false)
		local node, stop, engine = world(function(UI)
			return UI.TextInput({ value = value, numericValue = number, presentation = "number", min = 1, max = 10 })
		end, function()
			return { reducedMotion = reduced }
		end)
		node.TextBounds = engine.types.Vector2.new(20, 20)
		local label = find(node, "ValidationMessage")
		label.TextBounds = engine.types.Vector2.new(200, 18)
		node:CaptureFocus()
		node.Text = "11"
		node:ReleaseFocus(true)
		t.expect(label.Text).toBe("Enter a value of at most 10.")
		t.expect(label.Visible).toBe(true)
		t.expect(node.Size.Y.Offset >= 54).toBe(true)
		engine.heartbeat.fire(0.08)
		t.expect(find(node, "ValidationPulse").Scale < 1).toBe(true)
		reduced:set(true)
		t.expect(find(node, "ValidationPulse").Scale).toBe(1)
		node:CaptureFocus()
		node.Text = "3"
		node:ReleaseFocus(true)
		t.expect(number:peek()).toBe(3)
		t.expect(label.Visible).toBe(false)
		stop()
		t.expect(engine.heartbeat.count()).toBe(0)
	end)

	t.it("reflects external invalid state and rejects malformed invalid and numeric declarations", function()
		local invalid, value = Compose.cell(false), Compose.cell("ready")
		local node, stop = world(function(UI)
			return UI.TextInput({ value = value, invalid = invalid })
		end)
		invalid:set(true)
		t.expect(find(node, "ValidationMessage").Visible).toBe(true)
		invalid:set(false)
		t.expect(find(node, "ValidationMessage").Visible).toBe(false)
		stop()
		t.expect(function()
			world(function(UI)
				return UI.TextInput({ value = value, invalid = true })
			end)
		end).toThrow()
		t.expect(function()
			world(function(UI)
				return UI.TextInput({ value = value, presentation = "number" })
			end)
		end).toThrow()
	end)

	t.it("honors every clear-button mode and ends disabled edits without a commit", function()
		for _, mode in { "never", "always", "whileEditing", "unlessEditing" } do
			local value, enabled, commits = Compose.cell("text"), Compose.cell(true), 0
			local node, stop = world(function(UI)
				return UI.TextInput({
					value = value,
					enabled = enabled,
					clearButtonMode = mode,
					onCommit = function()
						commits += 1
					end,
				})
			end)
			local clear = find(node, "Clear")
			if mode == "never" then
				t.expect(clear).toBe(nil)
			else
				t.expect(clear.Visible).toBe(mode ~= "whileEditing")
			end
			node:CaptureFocus()
			if clear then
				t.expect(clear.Visible).toBe(mode ~= "unlessEditing")
			end
			t.expect(find(node.Parent, "FacetTextEditing").Enabled).toBe(true)
			enabled:set(false)
			t.expect(node:IsFocused()).toBe(false)
			t.expect(node.Selectable).toBe(false)
			t.expect(find(node.Parent, "FacetTextEditing").Enabled).toBe(false)
			t.expect(commits).toBe(0)
			if clear then
				t.expect(clear.Visible).toBe(false)
			end
			stop()
		end
	end)
	t.it("removes keyed chips toward the next then previous native target and caller fallback", function()
		local items, gui, fallback = Compose.cell({ "A", "B", "C" }), nil, nil
		local node, stop = world(function(UI, engine, runtime)
			fallback = runtime.constructors.TextButton({ Name = "Fallback" })
			return runtime.constructors.Frame({
				fallback,
				Compose.keyed({
					from = items,
					render = function(current, index)
						local id = current:peek()
						return UI.Chip({
							Name = id,
							label = id,
							LayoutOrder = index,
							removeFocusFallback = fallback,
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
			local target = find(find(node, id), "Remove")
			gui.SelectedObject = target
			target.Activated.fire()
		end
		remove("B")
		t.expect(gui.SelectedObject).toBe(find(find(node, "C"), "Remove"))
		remove("C")
		t.expect(gui.SelectedObject).toBe(find(find(node, "A"), "Remove"))
		remove("A")
		t.expect(gui.SelectedObject).toBe(fallback)
		stop()
	end)

	t.it("does not steal focus after a delayed chip removal request", function()
		local show, gui, fallback, other = Compose.cell(true), nil, nil, nil
		local node, stop = world(function(UI, engine, runtime)
			fallback = runtime.constructors.TextButton({ Name = "Fallback" })
			other = runtime.constructors.TextButton({ Name = "Other" })
			return runtime.constructors.Frame({
				fallback,
				other,
				Compose.show(show, function()
					return UI.Chip({
						Name = "Delayed",
						label = "Delayed",
						removeFocusFallback = fallback,
						onRemove = function() end,
					})
				end),
			})
		end, function(engine)
			gui = engine.new("GuiService")
			return { services = { GuiService = gui } }
		end)
		local remove = find(node, "Remove")
		gui.SelectedObject = remove
		remove.Activated.fire()
		t.expect(gui.SelectedObject).toBe(remove)
		gui.SelectedObject = other
		show:set(false)
		t.expect(gui.SelectedObject).toBe(other)
		stop()
	end)

	t.it("keeps mixed checkbox geometry live and validates presentation-specific options", function()
		local value, mixed = Compose.cell(false), Compose.cell(true)
		local node, stop = world(function(UI)
			return UI.Toggle({
				value = value,
				mixed = mixed,
				presentation = "checkbox",
				indicatorPosition = "trailing",
				row = { title = "Mode", description = "Use the current setting" },
			})
		end)
		t.expect(find(node, "Mark").Size.Y.Offset).toBe(4)
		mixed:set(false)
		t.expect(find(node, "Mark").Size.Y.Offset).toBe(12)
		t.expect(find(node, "Mark").Visible).toBe(false)
		value:set(true)
		t.expect(find(node, "Mark").Visible).toBe(true)
		stop()
		t.expect(function()
			world(function(UI)
				return UI.Toggle({ value = value, mixed = mixed, presentation = "switch" })
			end)
		end).toThrow()
	end)
	t.it("mirrors native caption alignment and typography without a text geometry solver", function()
		local node, stop, engine = world(function(UI)
			return UI.Button({ label = "Centered" })
		end, function()
			return {
				theme = {
					identity = {},
					chrome = { control = { kind = "nineSlice", asset = "control" } },
					assets = { control = { content = "rbxassetid://123" } },
				},
			}
		end)
		local caption = find(node, "Label")
		t.expect(caption.TextXAlignment).toBe(node.TextXAlignment)
		t.expect(caption.TextYAlignment).toBe(node.TextYAlignment)
		node.AbsoluteSize = engine.types.Vector2.new(67, 44)
		caption.Parent.Parent.AbsoluteSize = engine.types.Vector2.new(1, 1)
		t.expect(caption.Parent.Size).toBe(engine.types.UDim2.fromOffset(67, 44))
		t.expect(caption.Parent.Parent.Size).toBe(engine.types.UDim2.fromOffset(1, 1))
		t.expect(caption.Parent.Parent.AutomaticSize).toBe(engine.types.Enum.AutomaticSize.None)
		node.TextSize = 44
		node.TextXAlignment = engine.types.Enum.TextXAlignment.Right
		t.expect(caption.TextSize).toBe(44)
		t.expect(caption.TextXAlignment).toBe(engine.types.Enum.TextXAlignment.Right)
		t.expect(node.AutomaticSize).toBe(engine.types.Enum.AutomaticSize.XY)
		stop()
	end)
	t.it("replaces native hint art when the preferred asset changes representation", function()
		local binding
		local node, stop = world(function(UI, engine)
			local action = engine.new("InputAction")
			binding = engine.new("InputBinding")
			binding.KeyCode = engine.types.Enum.KeyCode.ButtonX
			action.PreferredBinding = binding
			return UI.ShortcutHint({ action = action })
		end, function()
			return {
				services = {
					UserInputService = {
						GetImageForKeyCode = function()
							return "rbxassetid://123"
						end,
					},
				},
			}
		end)
		local platform = find(node, "Glyph")
		t.expect(platform.Image).toBe("rbxassetid://123")
		local content = { SourceType = { Name = "Uri" }, Uri = "rbxassetid://456" }
		binding.DisplayImage = content
		local custom = find(node, "Glyph")
		t.expect(platform.isDestroyed()).toBe(true)
		t.expect(custom.ImageContent).toBe(content)
		binding.DisplayImage = nil
		t.expect(custom.isDestroyed()).toBe(true)
		t.expect(find(node, "Glyph").Image).toBe("rbxassetid://123")
		stop()
	end)

	t.it("gives native dialog contexts ordered sink priority and live eligibility", function()
		local firstEnabled = Compose.cell(false)
		local node, stop, engine = world(function(UI, _, runtime)
			return runtime.constructors.Frame({
				UI.Button({ Name = "First", dialogAction = "default", enabled = firstEnabled }),
				UI.Button({ Name = "Second", dialogAction = "default" }),
			})
		end)
		local contexts = {}
		for _, instance in engine.made do
			if instance.ClassName == "InputContext" then
				table.insert(contexts, instance)
			end
		end
		t.expect(#contexts).toBe(2)
		t.expect(contexts[1].Priority > contexts[2].Priority).toBe(true)
		t.expect(contexts[1].Sink).toBe(true)
		t.expect(contexts[1].Enabled).toBe(false)
		t.expect(contexts[2].Enabled).toBe(true)
		firstEnabled:set(true)
		t.expect(contexts[1].Enabled).toBe(true)
		find(node, "First").Visible = false
		t.expect(contexts[1].Enabled).toBe(false)
		stop()
		t.expect(contexts[1].isDestroyed()).toBe(true)
	end)
	t.it("yields native directional navigation at value bounds and rearms on focus return", function()
		local value = Compose.cell(4)
		local node, stop = world(function(UI)
			return UI.Rating({ value = value })
		end)
		t.expect(find(node.Parent, "IncreaseArrow")).toBe(nil)
		node.SelectionGained.fire()
		local increase = find(node.Parent, "IncreaseArrow")
		local decrease = find(node.Parent, "DecreaseArrow")
		local bumper = find(node.Parent, "Increase")
		t.expect(increase.Parent.Enabled).toBe(true)
		increase.Pressed.fire()
		t.expect(value:peek()).toBe(5)
		t.expect(increase.Parent.Enabled).toBe(false)
		t.expect(bumper.Parent.Enabled).toBe(true)
		t.expect(decrease.Parent.Enabled).toBe(true)
		decrease.Pressed.fire()
		t.expect(value:peek()).toBe(4)
		t.expect(increase.Parent.Enabled).toBe(true)
		node.SelectionLost.fire()
		t.expect(increase.isDestroyed()).toBe(true)
		t.expect(find(node.Parent, "IncreaseArrow")).toBe(nil)
		node.SelectionGained.fire()
		local rearmed = find(node.Parent, "IncreaseArrow")
		t.expect(rearmed ~= increase).toBe(true)
		t.expect(rearmed.Parent.Enabled).toBe(true)
		rearmed.Pressed.fire()
		t.expect(value:peek()).toBe(5)
		stop()
	end)
	t.it("cancels slider pointer ownership on native gamepad handoff and reports bounded semantics", function()
		local value, input, commits = Compose.cell(0.5), nil, 0
		local node, stop, engine = world(function(UI)
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
		detector.DragStart.fire(engine.types.Vector2.new(80, 0))
		t.expect(value:peek()).toBe(0.5)
		detector.DragContinue.fire(engine.types.Vector2.new(90, 0))
		t.expect(value:peek()).toBe(0.9)
		t.expect(node:GetAttribute("semanticValue")).toBe("0.9 of 0 to 1")
		input.PreferredInput = engine.types.Enum.PreferredInput.Gamepad
		t.expect(value:peek()).toBe(0.5)
		detector.DragEnd.fire()
		t.expect(commits).toBe(0)
		value:set(4)
		t.expect(node:GetAttribute("value")).toBe(1)
		t.expect(node:GetAttribute("semanticValue")).toBe("1 of 0 to 1")
		stop()
	end)
	t.it("ends a multiline edit when a native ancestor disables without late mutation", function()
		local value, commits = Compose.cell("line one\nline two"), 0
		local node, stop, engine = world(function(UI, _, runtime)
			return runtime.constructors.Frame({
				UI.TextInput({
					Name = "Editor",
					value = value,
					multiline = true,
					onCommit = function()
						commits += 1
					end,
				}),
			})
		end)
		local editor = find(node, "Editor")
		t.expect(editor.MultiLine).toBe(true)
		editor:CaptureFocus()
		editor.Text = "first\nsecond\n"
		t.expect(value:peek()).toBe("first\nsecond\n")
		editor.ReturnPressedFromOnScreenKeyboard.fire()
		t.expect(commits).toBe(0)
		t.expect(editor:IsFocused()).toBe(true)
		node.Interactable = false
		t.expect(editor:IsFocused()).toBe(false)
		editor.Text = "late mutation"
		editor.FocusLost.fire(true)
		t.expect(value:peek()).toBe("first\nsecond\n")
		t.expect(commits).toBe(0)
		node.Interactable = true
		editor:CaptureFocus()
		editor.Text = "accepted"
		editor:ReleaseFocus(false)
		t.expect(commits).toBe(1)
		stop()
	end)

	t.it("keeps composite control roots transparent instead of exposing native stock plates", function()
		local node, stop = world(function(UI, _, runtime)
			return runtime.constructors.Frame({
				UI.Stepper({ Name = "Stepper", value = Compose.cell(0) }),
				UI.Slider({ Name = "Slider", value = Compose.cell(0) }),
				UI.Rating({ Name = "Rating", value = Compose.cell(0) }),
				UI.LevelPicker({ Name = "Level", value = Compose.cell(0) }),
			})
		end)
		for _, name in { "Stepper", "Slider", "Rating", "Level" } do
			t.expect(find(node, name).BackgroundTransparency).toBe(1)
		end
		t.expect(find(node, "Stepper").BorderSizePixel).toBe(0)
		stop()
	end)
	t.it("retains native keyboard activation after first focus and gates it on live selection", function()
		local activated = 0
		local firstEnabled = Compose.cell(true)
		local node, stop, engine = world(function(UI, _, runtime)
			return runtime.constructors.Frame({
				UI.Button({
					Name = "First",
					label = "First",
					enabled = firstEnabled,
					onActivate = function()
						activated += 1
					end,
				}),
				UI.Button({
					Name = "Second",
					label = "Second",
					onActivate = function()
						activated += 10
					end,
				}),
			})
		end)
		local first, second = find(node, "First"), find(node, "Second")
		t.expect(find(node.Parent, "Activate")).toBe(nil)
		first.SelectionGained.fire()
		local action = enabledAction(node.Parent, "Activate")
		t.expect(action ~= nil).toBe(true)
		t.expect(action.Parent.Parent).toBe(node.Parent)
		action.Pressed.fire()
		t.expect(activated).toBe(1)
		first.SelectionLost.fire()
		t.expect(action.isDestroyed()).toBe(false)
		t.expect(action.Parent.Enabled).toBe(false)
		action.Pressed.fire()
		t.expect(activated).toBe(1)
		first.SelectionGained.fire()
		t.expect(enabledAction(node.Parent, "Activate")).toBe(action)
		action.Pressed.fire()
		t.expect(activated).toBe(2)
		first.Visible = false
		t.expect(action.Parent.Enabled).toBe(false)
		action.Pressed.fire()
		t.expect(activated).toBe(2)
		first.Visible = true
		firstEnabled:set(false)
		t.expect(action.Parent.Enabled).toBe(false)
		action.Pressed.fire()
		t.expect(activated).toBe(2)
		firstEnabled:set(true)
		t.expect(enabledAction(node.Parent, "Activate")).toBe(action)
		first.SelectionLost.fire()
		second.SelectionGained.fire()
		local secondAction = enabledAction(node.Parent, "Activate")
		t.expect(secondAction ~= action).toBe(true)
		action.Pressed.fire()
		t.expect(activated).toBe(2)
		secondAction.Pressed.fire()
		t.expect(activated).toBe(12)
		stop()
		t.expect(action.isDestroyed()).toBe(true)
		t.expect(secondAction.isDestroyed()).toBe(true)
		action.Pressed.fire()
		secondAction.Pressed.fire()
		t.expect(activated).toBe(12)
		t.expect(first.SelectionGained.count()).toBe(0)
	end)
	t.it("activates programmatically selected buttons through the native GuiService property", function()
		local gui, firstCalls, secondCalls = nil, 0, 0
		local node, stop = world(function(UI, _, runtime)
			return runtime.constructors.Frame({
				UI.Button({
					Name = "First",
					label = "First",
					onActivate = function()
						firstCalls += 1
					end,
				}),
				UI.Button({
					Name = "Second",
					label = "Second",
					onActivate = function()
						secondCalls += 1
					end,
				}),
			})
		end, function(engine)
			gui = engine.new("GuiService")
			return { services = { GuiService = gui } }
		end)
		local first, second = find(node, "First"), find(node, "Second")
		t.expect(find(node.Parent, "Activate")).toBe(nil)
		gui.SelectedObject = first
		local action = enabledAction(node.Parent, "Activate")
		t.expect(action ~= nil).toBe(true)
		t.expect(action.Parent.Enabled).toBe(true)
		action.Pressed.fire()
		t.expect(firstCalls).toBe(1)
		gui.SelectedObject = second
		t.expect(action.isDestroyed()).toBe(false)
		t.expect(action.Parent.Enabled).toBe(false)
		local secondAction = enabledAction(node.Parent, "Activate")
		t.expect(secondAction ~= action).toBe(true)
		action.Pressed.fire()
		secondAction.Pressed.fire()
		t.expect(firstCalls).toBe(1)
		t.expect(secondCalls).toBe(1)
		gui.SelectedObject = nil
		t.expect(enabledAction(node.Parent, "Activate")).toBe(nil)
		action.Pressed.fire()
		secondAction.Pressed.fire()
		t.expect(firstCalls).toBe(1)
		t.expect(secondCalls).toBe(1)
		gui.SelectedObject = first
		t.expect(enabledAction(node.Parent, "Activate")).toBe(action)
		t.expect(secondAction.Parent.Enabled).toBe(false)
		action.Pressed.fire()
		t.expect(firstCalls).toBe(2)
		stop()
		t.expect(action.isDestroyed()).toBe(true)
		t.expect(secondAction.isDestroyed()).toBe(true)
		t.expect(gui:GetPropertyChangedSignal("SelectedObject").count()).toBe(0)
	end)

	t.it("allocates mirrored captions only while a reactive native theme has control artwork", function()
		local neutral = { identity = {}, chrome = {} }
		local artwork = {
			identity = {},
			chrome = { control = { kind = "nineSlice", asset = "control" } },
			assets = { control = { content = "rbxassetid://123" } },
		}
		local theme = Compose.cell(neutral)
		local node, stop, engine = world(function(UI)
			return UI.Button({ label = "Caption" })
		end, function()
			return { theme = theme }
		end)
		t.expect(find(node, "Label")).toBe(nil)
		t.expect(node:GetPropertyChangedSignal("FontFace").count()).toBe(0)
		theme:set(artwork)
		local label = find(node, "Label")
		local bounds, boundary = label.Parent, label.Parent.Parent
		t.expect(label.Text).toBe("Caption")
		t.expect(node:HasTag("facet-button-captioned")).toBe(true)
		theme:set(neutral)
		t.expect(label.isDestroyed()).toBe(false)
		t.expect(boundary.Visible).toBe(false)
		t.expect(node:HasTag("facet-button-captioned")).toBe(false)
		node.Text = "Retained caption"
		node.TextSize = 22
		node.AbsoluteSize = engine.types.Vector2.new(80, 44)
		boundary.AbsoluteSize = engine.types.Vector2.new(2, 2)
		for _ = 1, 100 do
			theme:set(artwork)
			t.expect(find(node, "Label")).toBe(label)
			t.expect(boundary.Visible).toBe(true)
			t.expect(node:HasTag("facet-button-captioned")).toBe(true)
			theme:set(neutral)
			t.expect(boundary.Visible).toBe(false)
			t.expect(node:HasTag("facet-button-captioned")).toBe(false)
		end
		theme:set(artwork)
		t.expect(label.Text).toBe("Retained caption")
		t.expect(label.TextSize).toBe(22)
		t.expect(bounds.Size).toBe(engine.types.UDim2.fromOffset(40, 22))
		local created = 0
		for _, item in engine.made do
			if item.Name == "Label" or item.Name == "LabelBounds" or item.Name == "LabelBoundary" then
				created += 1
			end
		end
		t.expect(created).toBe(3)
		stop()
		t.expect(label.isDestroyed()).toBe(true)
		t.expect(bounds.isDestroyed()).toBe(true)
		t.expect(boundary.isDestroyed()).toBe(true)
		t.expect(node:GetPropertyChangedSignal("FontFace").count()).toBe(0)
	end)

	t.it("lays out image buttons vertically inside their authored card bounds", function()
		local node, stop, engine = world(function(UI, engine)
			return UI.Button({
				label = "A driver with a descriptive title",
				subtitle = "A longer description that must wrap inside the card.",
				image = "rbxassetid://123",
				imageAspectRatio = 2,
				Size = engine.types.UDim2.fromOffset(240, 260),
			})
		end)
		t.expect(node.AutomaticSize).toBe(engine.types.Enum.AutomaticSize.None)
		t.expect(find(node, "Content"):FindFirstChildWhichIsA("UIListLayout").FillDirection)
			.toBe(engine.types.Enum.FillDirection.Vertical)
		t.expect(find(node, "Title").TextWrapped).toBe(true)
		t.expect(find(node, "Title").Size.X.Scale).toBe(1)
		t.expect(find(node, "Description").TextWrapped).toBe(true)
		t.expect(find(node, "Image"):FindFirstChildWhichIsA("UIAspectRatioConstraint").AspectRatio).toBe(2)
		stop()
	end)
	t.it("allocates native value actions only for the selected control and preserves descendant focus", function()
		local gui, stepperValue, sliderValue = nil, Compose.cell(3), Compose.cell(0.5)
		local enabled = Compose.cell(true)
		local node, stop, engine = world(function(UI, _, runtime)
			return runtime.constructors.Frame({
				UI.Stepper({ Name = "Stepper", value = stepperValue, max = 10, enabled = enabled }),
				UI.Slider({ Name = "Slider", value = sliderValue }),
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
		t.expect(activeContextCount()).toBe(0)
		gui.SelectedObject = find(node, "Track")
		t.expect(activeContextCount()).toBe(5)
		local sliderAction = find(node.Parent, "FacetIncrease"):FindFirstChild("Increase")
		sliderAction.Pressed.fire()
		t.expect(sliderValue:peek()).toBe(0.51)
		local stepper = find(node, "Stepper")
		gui.SelectedObject = find(stepper, "Decrease")
		t.expect(activeContextCount()).toBe(5)
		t.expect(sliderAction.isDestroyed()).toBe(true)
		t.expect(engine.heartbeat.count()).toBe(0)
		local action = find(node.Parent, "FacetIncrease"):FindFirstChild("Increase")
		action.Pressed.fire()
		t.expect(stepperValue:peek()).toBe(4)
		gui.SelectedObject = find(stepper, "Increase")
		t.expect(find(node.Parent, "FacetIncrease"):FindFirstChild("Increase")).toBe(action)
		enabled:set(false)
		t.expect(activeContextCount()).toBe(0)
		t.expect(action.isDestroyed()).toBe(true)
		t.expect(engine.heartbeat.count()).toBe(0)
		enabled:set(true)
		t.expect(activeContextCount()).toBe(5)
		gui.SelectedObject = nil
		t.expect(activeContextCount()).toBe(0)
		stop()
		local initial, initialStop = world(function(UI)
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
		t.expect(initialAction.Parent.Enabled).toBe(true)
		initialAction.Pressed.fire()
		t.expect(stepperValue:peek()).toBe(5)
		initialStop()
		t.expect(initialAction.isDestroyed()).toBe(true)
	end)

	t.it("repeats focused value adjustments with bounded catch-up and no idle frame subscription", function()
		local value = Compose.cell(0)
		local node, stop, engine = world(function(UI)
			return UI.Stepper({ value = value, max = 100 })
		end)
		t.expect(engine.heartbeat.count()).toBe(0)
		node.SelectionGained.fire()
		local increase = find(node.Parent, "FacetIncrease"):FindFirstChild("Increase")
		increase.Pressed.fire()
		t.expect(value:peek()).toBe(1)
		t.expect(engine.heartbeat.count()).toBe(1)
		engine.heartbeat.fire(0.35)
		t.expect(value:peek()).toBe(1)
		engine.heartbeat.fire(0.25)
		t.expect(value:peek()).toBe(4)
		engine.heartbeat.fire(20)
		t.expect(value:peek()).toBe(9)
		increase.Released.fire()
		t.expect(engine.heartbeat.count()).toBe(0)
		increase.Pressed.fire()
		node.SelectionLost.fire()
		t.expect(engine.heartbeat.count()).toBe(0)
		stop()
		t.expect(engine.heartbeat.count()).toBe(0)
	end)
	t.it("uses native Toggle text and reserved padding while retaining rich hints and live theme insets", function()
		local label, rung = Compose.cell("Music"), Compose.cell("compact")
		local node, stop, engine = world(function(UI)
			return UI.Toggle({ value = Compose.cell(false), label = label, controlSize = rung })
		end)
		t.expect(node.Text).toBe("Music")
		t.expect(node:FindFirstChildWhichIsA("TextLabel", true)).toBe(nil)
		t.expect(node:FindFirstChildWhichIsA("UIListLayout", true)).toBe(nil)
		t.expect(#node:GetDescendants()).toBe(5)
		local padding = node:FindFirstChildWhichIsA("UIPadding")
		t.expect(padding.PaddingLeft.Offset).toBe(54)
		t.expect(padding.PaddingRight.Offset).toBe(8)
		t.expect(find(node, "Indicator").Position.X.Offset).toBe(-46)
		label:set("Music and effects")
		rung:set("large")
		t.expect(node.Text).toBe("Music and effects")
		t.expect(padding.PaddingLeft.Offset).toBe(62)
		stop()
		local themes = require("../src/ui/themes")
		local package = themes.neutralPackage()
		package.chrome.control = { kind = "native", contentInsets = { left = 24, right = 28 } }
		local selected = Compose.cell(package)
		node, stop = world(function(UI)
			return UI.Toggle({
				value = Compose.cell(false),
				label = "Sound",
				presentation = "checkbox",
				indicatorPosition = "trailing",
			})
		end, function()
			return { theme = selected }
		end)
		padding = node:FindFirstChildWhichIsA("UIPadding")
		t.expect(padding.PaddingLeft.Offset).toBe(24)
		t.expect(padding.PaddingRight.Offset).toBe(60)
		t.expect(find(node, "Indicator").Position.X.Scale).toBe(1)
		local nextPackage = themes.neutralPackage()
		nextPackage.chrome.control = { kind = "native", contentInsets = { left = 30, right = 36 } }
		selected:set(nextPackage)
		t.expect(padding.PaddingLeft.Offset).toBe(30)
		t.expect(padding.PaddingRight.Offset).toBe(68)
		stop()
		local hint = Compose.cell("Initial hint")
		node, stop = world(function(UI)
			return UI.Toggle({ value = Compose.cell(false), label = "Assistance", hint = hint })
		end)
		local caption
		for _, child in node:GetDescendants() do
			if child:IsA("TextLabel") and child.Text == "Initial hint" then
				caption = child
			end
		end
		t.expect(caption ~= nil).toBe(true)
		hint:set("Updated hint")
		t.expect(caption.Text).toBe("Updated hint")
		t.expect(node:FindFirstChildWhichIsA("UIListLayout", true) ~= nil).toBe(true)
		stop()
	end)

	t.it("isolates artwork and mirrored captions from native automatic sizing while following real padding", function()
		local theme = Compose.cell({ identity = {}, chrome = {} })
		local node, stop, engine = world(function(UI)
			return UI.Button({ label = "Enter" })
		end, function()
			return { theme = theme }
		end)
		local nativeSize, automaticSize = node.Size, node.AutomaticSize
		node.AbsoluteSize = engine.types.Vector2.new(67, 44)
		theme:set({
			identity = {},
			chrome = { control = { kind = "nineSlice", asset = "control" } },
			assets = { control = { content = "rbxassetid://123" } },
		})
		local skin, label = find(node, "SkinBounds"), find(node, "LabelBounds")
		for _, decoration in { skin, label } do
			decoration.Parent.AbsoluteSize = engine.types.Vector2.new(1, 1)
			t.expect(decoration.Parent.Parent).toBe(node)
			t.expect(decoration.Parent.Size).toBe(engine.types.UDim2.fromOffset(1, 1))
			t.expect(decoration.Parent.AutomaticSize).toBe(engine.types.Enum.AutomaticSize.None)
			t.expect(decoration.Parent.ClipsDescendants).toBe(false)
		end
		local padding = node:FindFirstChildWhichIsA("UIPadding")
		padding.PaddingLeft = engine.types.UDim.new(0.1, 2)
		padding.PaddingRight = engine.types.UDim.new(0, 5)
		padding.PaddingTop = engine.types.UDim.new(0, 3)
		padding.PaddingBottom = engine.types.UDim.new(0, 4)
		padding.Parent = node
		t.expect(skin.Size).toBe(engine.types.UDim2.fromOffset(67, 44))
		t.expect(skin.Position).toBe(engine.types.UDim2.fromOffset(6, 5))
		t.expect(skin.AnchorPoint).toBe(engine.types.Vector2.new(1, 1))
		t.expect(label.Size).toBe(engine.types.UDim2.fromOffset(53.3, 37))
		t.expect(label.Size.Y.Offset).toBe(37)
		t.expect(label.Position).toBe(engine.types.UDim2.fromOffset(1, 1))
		padding.PaddingLeft = engine.types.UDim.new(0, 12)
		t.expect(skin.Position.X.Offset).toBe(6)
		t.expect(label.Size.X.Offset).toBe(50)
		node.AbsoluteSize = engine.types.Vector2.new(80, 50)
		t.expect(skin.Size).toBe(engine.types.UDim2.fromOffset(80, 50))
		t.expect(label.Size).toBe(engine.types.UDim2.fromOffset(63, 43))
		t.expect(node.Size).toBe(nativeSize)
		t.expect(node.AutomaticSize).toBe(automaticSize)
		padding.Parent = nil
		t.expect(skin.Position).toBe(engine.types.UDim2.fromOffset(1, 1))
		t.expect(label.Size).toBe(engine.types.UDim2.fromOffset(80, 50))
		t.expect(padding:GetPropertyChangedSignal("PaddingLeft").count()).toBe(0)
		stop()
		t.expect(node:GetPropertyChangedSignal("AbsoluteSize").count()).toBe(0)
		t.expect(node.ChildAdded.count()).toBe(0)
		t.expect(node.ChildRemoved.count()).toBe(0)
	end)

	t.it("converts rendered decoration bounds through the native one pixel scale reference", function()
		local node, stop, engine = world(function(UI)
			return UI.Button({ label = "Enter" })
		end, function()
			return {
				theme = {
					identity = {},
					chrome = { control = { kind = "nineSlice", asset = "control" } },
					assets = { control = { content = "rbxassetid://123" } },
				},
			}
		end)
		local skin, label = find(node, "SkinBounds"), find(node, "LabelBounds")
		node.AbsoluteSize = engine.types.Vector2.new(100, 55)
		t.expect(skin.Size).toBe(engine.types.UDim2.fromOffset(0, 0))
		t.expect(label.Size).toBe(engine.types.UDim2.fromOffset(0, 0))
		for _, scale in { 1.25, 0.5, 2, 0.75, 1.25, 1 } do
			node.AbsoluteSize = engine.types.Vector2.new(80 * scale, 44 * scale)
			for _, decoration in { skin, label } do
				decoration.Parent.AbsoluteSize = engine.types.Vector2.new(scale, scale)
				t.expect(decoration.Size).toBe(engine.types.UDim2.fromOffset(80, 44))
				t.expect(decoration.Parent.Size).toBe(engine.types.UDim2.fromOffset(1, 1))
			end
		end
		local padding = node:FindFirstChildWhichIsA("UIPadding")
		padding.PaddingLeft = engine.types.UDim.new(0, 12)
		padding.PaddingRight = engine.types.UDim.new(0, 8)
		padding.Parent = node
		node.AbsoluteSize = engine.types.Vector2.new(100, 55)
		skin.Parent.AbsoluteSize = engine.types.Vector2.new(1.25, 1.25)
		label.Parent.AbsoluteSize = engine.types.Vector2.new(1.25, 1.25)
		t.expect(skin.Size).toBe(engine.types.UDim2.fromOffset(80, 44))
		t.expect(skin.Position).toBe(engine.types.UDim2.fromOffset(9, 1))
		t.expect(label.Size).toBe(engine.types.UDim2.fromOffset(60, 44))
		local skinBoundary, captionBoundary = skin.Parent, label.Parent
		stop()
		t.expect(skinBoundary:GetPropertyChangedSignal("AbsoluteSize").count()).toBe(0)
		t.expect(captionBoundary:GetPropertyChangedSignal("AbsoluteSize").count()).toBe(0)
	end)
end)
