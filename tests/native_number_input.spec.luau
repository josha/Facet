--!strict
local t = require("./lib/testkit")
local Facet = require("../src") :: any
local Compose = require("../src/vendor/compose/core")
local Roblox = require("../src/vendor/compose/roblox")
local context = require("../src/ui/context")
local register = require("../src/ui/inputs")
local arithmetic = require("../src/ui/arithmetic")
local engineLib = require("./lib/native_engine")
local expect = t.expect

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
	local runtime = Roblox.createRuntime(engine)
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
		return runtime.constructors.Frame({
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
	find(w.node, "Input/" .. name).Activated.fire()
end

t.describe("native NumberInput preset", function()
	t.it("it is the text engine with the number contract, and refuses a second presentation", function()
		local w = numberWorld()
		editAndCommit(w, "12")
		expect(`{w.commits[1].value} {typeof(w.commits[1].value)}`).toBe("12 number")
		w.stop()
		local ok, err = pcall(function()
			numberWorld({ presentation = "search" })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "IS the number presentation", 1, true) ~= nil).toBe(true)
	end)

	t.it("step must be finite and above zero, precision a whole count of places, units strings", function()
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
			expect(ok).toBe(false)
		end
		local engine: any = engineLib.new()
		local runtime = Roblox.createRuntime(engine)
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
			expect(`{key}: {ok}`).toBe(`{key}: false`)
		end
	end)
end)

t.describe("native NumberInput draft grammar", function()
	t.it("an incomplete draft reverts in silence, and says so only when the field is required", function()
		for _, draft in { "", "-", ".", "-.", "\u{2212}" } do
			local w = numberWorld({ draft = "7", number = 7 })
			editAndCommit(w, draft)
			expect(`[{draft}] {w.draft:peek()} {w.number:peek()} {#w.commits}`).toBe(`[{draft}] 7 7 0`)
			expect(w.field:GetAttribute("validationMessage")).toBe("")
			w.stop()
		end
		local required = numberWorld({ draft = "7", number = 7, requiredMark = "required", label = "Laps" })
		editAndCommit(required, "")
		expect(required.field:GetAttribute("validationMessage") ~= "").toBe(true)
		expect(find(required.node, "Message/Validation").Text).toBe("Enter a number.")
		expect(`{required.number:peek()} {#required.commits}`).toBe("7 0")
		required.stop()
	end)

	t.it("the default parser is the strict grammar, not the language's own reader", function()
		expect(arithmetic.number("42")).toBe(42)
		expect(arithmetic.number("-2.5")).toBe(-2.5)
		expect(arithmetic.number("\u{2212}2")).toBe(-2)
		for _, bad in { "1e5", "0x10", "1,000", " 7 ", "1.2.3", "inf", "nan" } do
			expect(`{bad}: {arithmetic.number(bad)}`).toBe(`{bad}: nil`)
		end
		local w = numberWorld()
		editAndCommit(w, "1e5")
		expect(w.field:GetAttribute("validationMessage") ~= "").toBe(true)
		expect(`{w.number:peek()} {w.draft:peek()} {#w.commits}`).toBe("3 1e5 0")
		w.stop()
	end)
end)

t.describe("native NumberInput commit", function()
	t.it("a commit reports the number first, and the string is only how it is written", function()
		local w = numberWorld({ draft = "", number = 0 })
		editAndCommit(w, "12")
		expect(#w.commits).toBe(1)
		expect(`{w.commits[1].value} {typeof(w.commits[1].value)} {w.commits[1].reason}`).toBe("12 number submit")
		expect(w.number:peek()).toBe(12)
		w.field:CaptureFocus()
		w.field.Text = "13"
		w.field:ReleaseFocus(false)
		expect(`{w.commits[2].value} {w.commits[2].reason}`).toBe("13 focusLost")
		w.stop()
	end)

	t.it("an out-of-range commit clamps and says clamped rather than refusing", function()
		local w = numberWorld({ draft = "", number = 1, min = 1, max = 9 })
		editAndCommit(w, "99")
		expect(`{w.commits[1].value} {w.commits[1].reason} {w.draft:peek()}`).toBe("9 clamped 9")
		expect(w.field:GetAttribute("validationMessage")).toBe("")
		w.stop()
		local low = numberWorld({ draft = "", number = 5, min = 1, max = 9 })
		editAndCommit(low, "-4")
		expect(`{low.commits[1].value} {low.commits[1].reason}`).toBe("1 clamped")
		low.stop()
	end)

	t.it("precision rounds half away from zero, at commit and never while typing", function()
		local w = numberWorld({ draft = "", number = 0, precision = 1 })
		w.field:CaptureFocus()
		w.field.Text = "0.15"
		expect(w.draft:peek()).toBe("0.15")
		w.field:ReleaseFocus(true)
		expect(`{w.number:peek()} {w.draft:peek()}`).toBe("0.2 0.2")
		w.stop()
		local negative = numberWorld({ draft = "", number = 0, precision = 1 })
		editAndCommit(negative, "-0.15")
		expect(negative.number:peek()).toBe(-0.2)
		negative.stop()
		local huge = numberWorld({ draft = "", number = 0, precision = 10 })
		editAndCommit(huge, "1" .. string.rep("0", 300))
		expect(`{huge.number:peek() == 1e300} {#huge.commits}`).toBe("true 1")
		huge.stop()
	end)

	t.it("a callback that disposes the control mid-commit leaves nothing half-written", function()
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
			expect(`{callback}: {w.number:peek()} {#w.commits}`).toBe(`{callback}: 3 0`)
			expect(field:isDestroyed()).toBe(true)
			w.stop()
		end
	end)

	t.it("a field handed the arithmetic recipe commits the answer, and never runs the text", function()
		local w = numberWorld({ draft = "", number = 0, parse = Facet.recipes.arithmetic.parse })
		editAndCommit(w, "3 + 5")
		expect(`{w.number:peek()} {w.draft:peek()}`).toBe("8 8")
		editAndCommit(w, "print('hi')")
		expect(`{w.number:peek()} {w.draft:peek()} {#w.commits}`).toBe("8 print('hi') 1")
		w.stop()
	end)
end)

t.describe("native NumberInput units and step buttons", function()
	t.it("a prefix and a suffix stand beside the editor and never enter the draft", function()
		local w = numberWorld({ draft = "", number = 0, prefix = "$", suffix = "/lap" })
		local prefix, suffix, field = find(w.node, "Input/Prefix"), find(w.node, "Input/Suffix"), w.field
		expect(prefix.Text).toBe("$")
		expect(suffix.Text).toBe("/lap")
		expect(prefix.LayoutOrder < field.LayoutOrder).toBe(true)
		expect(suffix.LayoutOrder > field.LayoutOrder).toBe(true)
		w.field:CaptureFocus()
		w.field.Text = "12"
		expect(w.draft:peek()).toBe("12")
		w.stop()
	end)

	t.it("a step button moves the value by one step and commits with submit", function()
		local w = numberWorld({ draft = "4", number = 4, stepButtons = true, step = 2, min = 0, max = 20 })
		press(w, "Increment")
		expect(`{w.number:peek()} {w.draft:peek()}`).toBe("6 6")
		local last = w.commits[#w.commits]
		expect(`{last.value} {last.reason} {w.changes[#w.changes]}`).toBe("6 submit 6")
		press(w, "Decrement")
		expect(w.number:peek()).toBe(4)
		expect(find(w.node, "Input/Increment"):HasTag("facet-stepper-button")).toBe(true)
		w.stop()
	end)

	t.it("a press goes through the typed path's rounding and clamping, bounded or not", function()
		local open = numberWorld({ draft = "0.1", number = 0.1, stepButtons = true, step = 0.2, precision = 1 })
		press(open, "Increment")
		expect(`{open.number:peek() == 0.3} {open.draft:peek()}`).toBe("true 0.3")
		editAndCommit(open, "0.25")
		expect(open.number:peek() == 0.3).toBe(true)
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
		expect(`{bounded.number:peek() == 1} {bounded.draft:peek()}`).toBe("true 1.0")
		expect(find(bounded.node, "Input/Increment").Interactable).toBe(false)
		bounded.stop()
	end)

	t.it("without a precision, presses land on the step's own places, never on float noise", function()
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
			expect(`{w.number:peek() == 0.3} {w.draft:peek()} {w.commits[3].value == 0.3}`).toBe("true 0.3 true")
			w.stop()
		end
	end)

	t.it("the step buttons are square targets at the touch floor and separate stops", function()
		local w = numberWorld({ stepButtons = true, min = 0, max = 20 })
		local dec, inc = find(w.node, "Input/Decrement"), find(w.node, "Input/Increment")
		for _, button in { dec, inc } do
			expect(button.Size.X.Offset >= 44 and button.Size.Y.Offset >= 44).toBe(true)
			expect(button.Size.X.Offset).toBe(button.Size.Y.Offset)
		end
		expect(dec.LayoutOrder < inc.LayoutOrder).toBe(true)
		w.stop()
	end)

	t.it("the step buttons are ordinary focus stops after the editor and its clear, and claim no arrows", function()
		local w =
			numberWorld({ draft = "4", number = 4, stepButtons = true, clearButtonMode = "always", min = 0, max = 20 })
		local plate = find(w.node, "Input")
		local order = {}
		for _, child in plate:GetChildren() do
			if child:IsA("GuiObject") and child.Selectable then
				table.insert(order, child)
			end
		end
		table.sort(order, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		local names = {}
		for _, child in order do
			table.insert(names, child.Name)
		end
		expect(table.concat(names, " ")).toBe("Field Clear Decrement Increment")
		for _, name in { "Decrement", "Increment" } do
			for _, context in find(plate, name):GetChildren() do
				if context:IsA("InputContext") then
					for _, action in context:GetChildren() do
						for _, binding in action:GetChildren() do
							local key = tostring(binding.KeyCode)
							expect(string.find(key, "Left") == nil and string.find(key, "Right") == nil).toBe(true)
						end
					end
				end
			end
		end
		w.stop()
	end)

	t.it("at the end of its range, read-only or disabled, the button says so and refuses", function()
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
			expect(`{case.name}: {button.Interactable}`).toBe(`{case.name}: false`)
			button.Activated.fire()
			expect(`{case.name}: {w.number:peek()} {#w.commits}`).toBe(`{case.name}: {before} 0`)
			w.stop()
		end
		local low = numberWorld({ draft = "0", number = 0, stepButtons = true, step = 5, min = 0, max = 20 })
		expect(find(low.node, "Input/Increment").Interactable).toBe(true)
		low.stop()
	end)

	t.it("closing the screen releases the numeric field and its buttons", function()
		local w = numberWorld({ stepButtons = true, prefix = "$", min = 0, max = 9, label = "Fee", hint = "Per lap" })
		w.stop()
		expect(#w.screen:GetChildren()).toBe(0)
		expect(w.field:isDestroyed()).toBe(true)
	end)
end)

t.describe("native NumberInput scrub", function()
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
		w.field.InputBegan.fire(mouse)
	end
	local function move(w: any, dx: number, dy: number?)
		w.input.InputChanged.fire({
			UserInputType = w.E.UserInputType.MouseMovement,
			Position = w.engine.types.Vector3.new(100 + dx, 10 + (dy or 0), 0),
		})
	end
	local function up(w: any)
		w.input.InputEnded.fire(w.mouse)
	end

	t.it("a press that never promotes leaves the native tap and typing alone", function()
		local w = scrubWorld()
		down(w, 100)
		move(w, 4, 3)
		up(w)
		expect(w.field:IsFocused()).toBe(true)
		w.field.Text = "105"
		w.field:ReleaseFocus(true)
		expect(`{w.number:peek()} {#w.commits} {w.commits[1].value}`).toBe("20 1 20")
		expect(w.input.InputChanged.count()).toBe(0)
		w.stop()
	end)

	t.it("travel moves whole steps of the total, clamps, reports live and commits once at release", function()
		local w = scrubWorld({ step = 0.5, precision = 1 })
		down(w, 100)
		move(w, 17, 2)
		expect(w.field:IsFocused()).toBe(false)
		expect(#w.commits).toBe(0)
		expect(`{w.number:peek()} {w.draft:peek()}`).toBe("11 11.0")
		move(w, -40)
		expect(w.number:peek()).toBe(7.5)
		move(w, 1000)
		expect(`{w.number:peek()} {table.concat(w.changes, ",")}`).toBe("20 11.0,7.5,20.0")
		up(w)
		expect(`{#w.commits} {w.commits[1].value} {w.commits[1].reason}`).toBe("1 20 submit")
		w.stop()
	end)

	t.it("a scrub lands on the step's own places, never on float noise", function()
		local w = scrubWorld({ draft = "0", number = 0, step = 0.1, max = 1 })
		down(w, 100)
		move(w, 24)
		expect(`{w.number:peek() == 0.3} {w.draft:peek()}`).toBe("true 0.3")
		w.stop()
	end)

	t.it("a scrub over a typed draft starts from the committed number and discards the draft", function()
		for _, finish in { "end", "cancel" } do
			local w = scrubWorld()
			w.field.Text = "42"
			expect(w.draft:peek()).toBe("42")
			down(w, 100)
			move(w, 8)
			expect(`{finish} begin: {w.number:peek()} {w.draft:peek()}`).toBe(`{finish} begin: 11 11`)
			move(w, 16)
			if finish == "end" then
				up(w)
			else
				w.input.InputBegan.fire({ KeyCode = w.E.KeyCode.Escape, UserInputType = w.E.UserInputType.Keyboard })
			end
			local want = if finish == "end" then "12 12 1" else "10 10 0"
			expect(`{finish}: {w.number:peek()} {w.draft:peek()} {#w.commits}`).toBe(`{finish}: {want}`)
			w.stop()
		end
	end)

	t.it("cancel, class loss, disable, readOnly and scrub off restore the snapshot without a commit", function()
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
			expect(`{how} moved {w.number:peek()}`).toBe(`{how} moved 13`)
			if how == "cancel" then
				w.input.InputBegan.fire({ KeyCode = w.E.KeyCode.ButtonB, UserInputType = w.E.UserInputType.Gamepad1 })
			elseif how == "class" then
				w.input.PreferredInput = w.E.PreferredInput.Gamepad
			elseif how == "off" then
				on:set(false)
			else
				lock:set(true)
			end
			move(w, 40)
			up(w)
			expect(`{how} {w.number:peek()} {w.draft:peek()} {#w.commits}`).toBe(`{how} 10 10 0`)
			w.stop()
		end
	end)

	t.it("a caller write mid-gesture ends it and the caller's number stands", function()
		local w = scrubWorld()
		down(w, 100)
		move(w, 16)
		expect(w.number:peek()).toBe(12)
		w.number:set(3)
		w.draft:set("3")
		move(w, 40)
		up(w)
		expect(`{w.number:peek()} {w.draft:peek()} {#w.commits}`).toBe("3 3 0")
		w.stop()
	end)

	t.it("disposal mid-gesture restores the snapshot; an unscrubbable field adds no listener", function()
		local w = scrubWorld()
		down(w, 100)
		move(w, 16)
		expect(w.number:peek()).toBe(12)
		w.visible:set(false)
		expect(`{w.number:peek()} {w.draft:peek()}`).toBe("10 10")
		expect(w.input.InputChanged.count()).toBe(0)
		w.stop()
		local plain = scrubWorld({ scrub = false })
		down(plain, 100)
		move(plain, 40)
		expect(`{plain.number:peek()} {plain.field:IsFocused()}`).toBe("10 true")
		expect(plain.input.InputChanged.count()).toBe(0)
		plain.stop()
		local none = numberWorld()
		none.field.InputBegan.fire({
			UserInputType = none.E.UserInputType.MouseButton1,
			Position = none.engine.types.Vector3.new(1, 1, 0),
		})
		expect(none.input.InputEnded.count()).toBe(0)
		none.stop()
	end)
end)
