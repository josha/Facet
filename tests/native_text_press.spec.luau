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
		screen_text_press.wire(handle, { uis = uis, Enum = Enum }, h or handlers)
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
	function p.mouseMove(x: number, y: number)
		uis.InputChanged.fire({ UserInputType = "Move", Position = { X = x, Y = y } })
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

return nil
