--!strict
-- The native TextBox press wiring, loaded from production source. Lune has no
-- TextBox, so the engine's measured order is doubled (unfinished-fields-
-- prototype.md): a mouse press places the caret, fires Focused, then the box's
-- InputBegan; its release writes the caret before UserInputService.InputEnded.
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local screen_text_press = require("../src/client/screen_text_press")

local Enum = {
	UserInputType = { MouseButton1 = "MB1", Touch = "Touch", MouseMovement = "Move", Keyboard = "Keyboard" },
	KeyCode = { Escape = "Escape", ButtonB = "ButtonB", Unknown = "Unknown" },
}

local function signal(): any
	local listeners = {}
	return {
		Connect = function(_, callback)
			local c = { connected = true }
			function c.Disconnect()
				c.connected = false
			end
			table.insert(listeners, { c = c, fn = callback })
			return c
		end,
		fire = function(...)
			for _, item in table.clone(listeners) do
				if item.c.connected then
					item.fn(...)
				end
			end
		end,
		live = function(): number
			local n = 0
			for _, item in listeners do
				n += if item.c.connected then 1 else 0
			end
			return n
		end,
	}
end

local function probe(text: string?, policy: string?, handlers: any?)
	local writes: { string } = {}
	local state: any = { Text = text or "12.5 km", CursorPosition = -1, SelectionStart = -1 }
	local focused, mouseDown = false, false
	local p: any = {}
	local instance = setmetatable({
		Focused = signal(),
		FocusLost = signal(),
		InputBegan = signal(),
		IsFocused = function()
			return focused
		end,
		ReleaseFocus = function()
			if focused then
				focused = false
				state.CursorPosition, state.SelectionStart = -1, -1
				p.instance.FocusLost.fire(false)
			end
		end,
	}, {
		__index = state,
		__newindex = function(_, key, value)
			table.insert(writes, `{key}={value}`)
			state[key] = value
		end,
	})
	local uis = {
		InputBegan = signal(),
		InputChanged = signal(),
		InputEnded = signal(),
		IsMouseButtonPressed = function(_, kind)
			return kind == "MB1" and mouseDown
		end,
	}
	local handle: any = { instance = instance, selectOnFocus = policy }
	p.instance, p.uis, p.handle, p.state, p.writes = instance, uis, handle, state, writes
	function p.wire(h: any?)
		screen_text_press.wire(handle, { uis = uis, Enum = Enum }, h or handlers or {})
	end
	-- the engine's own writes, not counted as ours
	local function engine(cursor: number, selection: number)
		state.CursorPosition, state.SelectionStart = cursor, selection
	end
	p.mouse = { UserInputType = "MB1", Position = { X = 100, Y = 30 } }
	function p.mouseDown()
		mouseDown = true
		if not focused then
			engine(5, -1)
			focused = true
			instance.Focused.fire()
		end
		instance.InputBegan.fire(p.mouse)
	end
	function p.mouseMove(dx: number, dy: number)
		uis.InputChanged.fire({ UserInputType = "Move", Position = { X = 100 + dx, Y = 30 + dy } })
	end
	function p.key(code: string)
		uis.InputBegan.fire({ UserInputType = "Keyboard", KeyCode = code })
	end
	function p.mouseUp()
		if focused then
			engine(5, -1)
		end
		mouseDown = false
		uis.InputEnded.fire(p.mouse)
	end
	function p.capture()
		focused = true
		engine(#state.Text + 1, -1)
		instance.Focused.fire()
	end
	function p.blur()
		focused = false
		instance.FocusLost.fire(false)
	end
	function p.caret(): string
		return `{state.CursorPosition} {state.SelectionStart}`
	end
	p.wire()
	return p
end

describe("TextInput selectOnFocus on the native box", function()
	it("a pointer focus selects at its own release, after the engine's release writes", function()
		for _, case in { { "all", "8 1" }, { "end", "8 -1" } } do
			local p = probe("12.5 km", case[1])
			p.mouseDown()
			expect(`{case[1]} held: {p.caret()} {#p.writes}`).toBe(`{case[1]} held: 5 -1 0`)
			p.mouseUp()
			expect(`{case[1]} released: {p.caret()}`).toBe(`{case[1]} released: {case[2]}`)
			-- once per session: a second click in the same session keeps the native caret
			p.mouseDown()
			p.mouseUp()
			expect(p.caret()).toBe("5 -1")
		end
	end)

	it("activation focus selects in Focused, and offsets are bytes", function()
		local p = probe("Café 5", "all")
		p.capture()
		expect(p.caret()).toBe("8 1")
		local e = probe("", "end")
		e.capture()
		expect(e.caret()).toBe("1 -1")
	end)

	it("none (the default) writes nothing on any focus", function()
		for _, policy in { "none", nil :: any } do
			local p = probe("12.5 km", policy)
			p.mouseDown()
			p.mouseUp()
			p.blur()
			p.capture()
			expect(#p.writes).toBe(0)
		end
	end)

	it("blur before release, recycle and disabled cancel a pending selection", function()
		local p = probe("12.5 km", "all")
		p.mouseDown()
		p.blur()
		p.mouseUp()
		expect(#p.writes).toBe(0)
		p.mouseDown()
		p.handle.selectOnFocus = nil -- recycled into a default field
		p.wire()
		p.mouseUp()
		p.capture()
		expect(#p.writes).toBe(0)
		expect(p.uis.InputEnded.live()).toBe(0)
		local d = probe("12.5 km", "all")
		d.handle.disabledState = true
		d.capture()
		expect(#d.writes).toBe(0)
	end)

	it("a policy change while focused applies at the next session", function()
		local p = probe("12.5 km", "none")
		p.capture()
		p.handle.selectOnFocus = "all"
		p.mouseDown()
		p.mouseUp()
		expect(#p.writes).toBe(0)
		p.blur()
		p.capture()
		expect(p.caret()).toBe("8 1")
	end)
end)

describe("NumberInput scrub on the native box", function()
	local function scrubProbe(refuse: string?): (any, { string })
		local log: { string } = {}
		local p = probe("10", nil, {
			onScrub = function(phase: string, arg: any?): boolean
				table.insert(log, if arg ~= nil then `{phase}:{arg}` else phase)
				return phase ~= refuse
			end,
		})
		return p, log
	end

	it("a press under the slop is a native tap: focus and caret stay, nothing is promoted", function()
		local p, log = scrubProbe()
		p.mouseDown()
		p.mouseMove(4, 3) -- 5 px, under the 6 px pointer gate
		p.mouseUp()
		expect(`{table.concat(log, " ")} | {p.caret()} {p.instance:IsFocused()} {#p.writes}`).toBe(
			"press:pointer | 5 -1 true 0"
		)
		expect(p.uis.InputChanged.live()).toBe(0)
	end)

	it("past the slop a horizontal drag releases focus and reports the total travel once to its end", function()
		local p, log = scrubProbe()
		local lost = 0
		p.instance.FocusLost:Connect(function()
			lost += 1
		end)
		p.mouseDown()
		p.mouseMove(7, 2)
		expect(`{p.instance:IsFocused()} {lost}`).toBe("false 1")
		p.mouseMove(-300, 90) -- outside the box: the global service keeps reporting
		p.mouseUp()
		p.mouseUp()
		expect(table.concat(log, " ")).toBe("press:pointer begin move:7 move:-300 end")
	end)

	it("a vertical drag or a refused promotion stays native for the rest of the press", function()
		local p, log = scrubProbe()
		p.mouseDown()
		p.mouseMove(2, 8)
		p.mouseMove(40, 8)
		p.mouseUp()
		expect(`{table.concat(log, " ")} {p.instance:IsFocused()}`).toBe("press:pointer true")
		local r, refused = scrubProbe("begin")
		r.mouseDown()
		r.mouseMove(10, 0)
		r.mouseMove(40, 0)
		expect(`{table.concat(refused, " ")} {r.instance:IsFocused()}`).toBe("press:pointer begin true")
		-- an ineligible press is not even followed
		local n, never = scrubProbe("press")
		n.mouseDown()
		expect(`{table.concat(never, " ")} {n.uis.InputChanged.live()}`).toBe("press:pointer 0")
	end)

	it("Escape cancels, a recycle cancels, and a second finger never joins the first", function()
		local p, log = scrubProbe()
		p.mouseDown()
		p.mouseMove(8, 0)
		p.key("Unknown")
		p.key("Escape")
		p.mouseMove(30, 0)
		p.mouseUp()
		expect(table.concat(log, " ")).toBe("press:pointer begin move:8 cancel")
		local r, recycled = scrubProbe()
		r.mouseDown()
		r.mouseMove(8, 0)
		r.wire({})
		r.mouseUp()
		expect(table.concat(recycled, " ")).toBe("press:pointer begin move:8 cancel")
		local t2, touches = scrubProbe()
		local finger = { UserInputType = "Touch", Position = { X = 50, Y = 20 } }
		local other = { UserInputType = "Touch", Position = { X = 90, Y = 20 } }
		t2.instance.InputBegan.fire(finger)
		t2.instance.InputBegan.fire(other)
		-- a different InputObject at the finger's place is not the finger
		t2.uis.InputChanged.fire({ UserInputType = "Touch", Position = { X = 80, Y = 20 } })
		finger.Position = { X = 63, Y = 20 }
		t2.uis.InputChanged.fire(finger) -- 13 px: under the 14 px touch gate
		t2.uis.InputChanged.fire(other)
		finger.Position = { X = 65, Y = 20 }
		t2.uis.InputChanged.fire(finger)
		t2.uis.InputEnded.fire(other)
		t2.uis.InputEnded.fire(finger)
		expect(table.concat(touches, " ")).toBe("press:touch begin move:15 end")
	end)
end)

return nil
