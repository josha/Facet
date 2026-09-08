--!strict
-- Execute the native caret wiring itself with a yielding TextService. Lune has
-- no TextBox, so only engine objects/events and the async boundary are doubled;
-- the lifecycle guards and prefix measurement are loaded from production source.
local t = require("./lib/testkit")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local reconnect = require("../src/client/handle_conn").reconnect
local source = fs.readFile("src/client/screen_caret.luau")
local first = assert(string.find(source, "function screen_caret.wire(handle: any, handlers: any)", 1, true))
local last = assert(string.find(source, "\nreturn screen_caret", first, true))
local caretSource = string.sub(source, first, last - 1)
caretSource = string.gsub(caretSource, "function screen_caret.wire", "function adapter.setTextInputHandlers")

local function signal()
	local listeners = {}
	return {
		Connect = function(_, callback)
			local c = { connected = true }
			function c:Disconnect()
				self.connected = false
			end
			table.insert(listeners, { connection = c, callback = callback })
			return c
		end,
		fire = function()
			for _, item in listeners do
				if item.connection.connected then
					item.callback()
				end
			end
		end,
	}
end

local function probe(code: string?)
	local deferred, requests = {}, {}
	local events = {}
	local function event(name)
		if events[name] == nil then
			events[name] = signal()
		end
		return events[name]
	end
	local pad = {
		PaddingLeft = { Offset = 12 },
		PaddingRight = { Offset = 12 },
		PaddingTop = { Offset = 12 },
		Changed = event("Padding"),
	}
	local viewport = {
		GetPropertyChangedSignal = function(_, name)
			return event(name)
		end,
	}
	local instance = {
		Parent = {},
		MultiLine = true,
		CursorPosition = 19,
		Text = "first\nsecond\nthird",
		AbsoluteSize = { X = 200, Y = 300 },
		TextSize = 20,
		LineHeight = 1.2,
		FontFace = "old-font",
		focused = true,
		IsA = function(_, class)
			return class == "TextBox"
		end,
		IsFocused = function(self)
			return self.focused
		end,
		FindFirstChildOfClass = function()
			return pad
		end,
		FindFirstAncestorWhichIsA = function()
			return viewport
		end,
		GetStyled = function(self, name)
			return self[name]
		end,
		GetPropertyChangedSignal = function(_, name)
			return event(name)
		end,
		GetStyledPropertyChangedSignal = function(_, name)
			return event("styled:" .. name)
		end,
	}
	local destroyed = 0
	local native = {
		new = function(class)
			assert(class == "GetTextBoundsParams")
			return {
				Destroy = function()
					destroyed += 1
				end,
			}
		end,
	}
	local service = {
		GetTextBoundsAsync = function(_, params)
			local request = table.clone(params)
			table.insert(requests, request)
			coroutine.yield()
			local text = string.gsub(request.Text, "\u{200B}", "")
			local lines, widest = 0, 0
			for line in string.gmatch(text .. "\n", "(.-)\n") do
				local width = #line * 10
				widest = math.max(widest, math.min(width, request.Width))
				lines += math.max(1, math.ceil(width / request.Width))
			end
			return { X = widest, Y = lines * request.Size }
		end,
	}
	local adapter, handle = {}, { instance = instance }
	local factory =
		luau.load("return function(adapter, reconnect, task, Instance, game)\n" .. (code or caretSource) .. "\nend", {
			debugName = "native-caret-wiring",
		})()
	factory(
		adapter,
		reconnect,
		{
			defer = function(callback)
				table.insert(deferred, callback)
			end,
		},
		native,
		{
			GetService = function(_, name)
				assert(name == "TextService")
				return service
			end,
		}
	)
	local p = { instance = instance, pad = pad, requests = requests, handle = handle }
	function p.wire(callback)
		adapter.setTextInputHandlers(handle, { onCaretRect = callback })
	end
	function p.fire(name)
		event(name).fire()
	end
	function p.begin()
		assert(#deferred > 0, "the native event must schedule a caret measurement")
		local co = coroutine.create(table.remove(deferred, 1))
		assert(coroutine.resume(co))
		return co
	end
	function p.finish(co)
		while coroutine.status(co) ~= "dead" do
			assert(coroutine.resume(co))
		end
	end
	function p.drain()
		local count = 0
		while #deferred > 0 do
			count += 1
			assert(count < 20, "caret refresh must converge")
			p.finish(p.begin())
		end
	end
	function p.pendingCount()
		return #deferred
	end
	function p.destroyed()
		return destroyed
	end
	return p
end

t.describe("Native caret asynchronous ownership", function()
	t.it("rewiring rejects an old completion and lets the new owner reveal", function()
		local p = probe()
		local old, current = 0, 0
		p.wire(function()
			old += 1
		end)
		p.fire("CursorPosition")
		local pending = p.begin()
		p.wire(function()
			current += 1
		end)
		p.finish(pending)
		t.expect(old).toBe(0)
		p.fire("CursorPosition")
		p.drain()
		t.expect(current).toBe(1)
		t.expect(p.destroyed()).toBe(2)
	end)

	t.it("clearing the callback disconnects every caret event and rejects pending work", function()
		local p = probe()
		local calls = 0
		p.wire(function()
			calls += 1
		end)
		p.fire("Text")
		local pending = p.begin()
		p.wire(nil)
		p.finish(pending)
		local before = #p.requests
		for _, name in
			{
				"CursorPosition",
				"Text",
				"AbsoluteSize",
				"TextSize",
				"LineHeight",
				"styled:FontFace",
				"Padding",
				"AbsoluteWindowSize",
			}
		do
			p.fire(name)
		end
		t.expect(p.pendingCount()).toBe(0)
		p.drain()
		t.expect(#p.requests).toBe(before)
		t.expect(calls).toBe(0)
	end)

	for _, state in { "disposed", "blurred" } do
		t.it(`{state} native fields discard measurements already in flight`, function()
			local p = probe()
			local calls = 0
			p.wire(function()
				calls += 1
			end)
			p.fire("Text")
			local pending = p.begin()
			if state == "disposed" then
				p.instance.Parent = nil
			else
				p.instance.focused = false
			end
			p.finish(pending)
			t.expect(calls).toBe(0)
			t.expect(p.destroyed()).toBe(1)
		end)
	end

	for _, change in { "font", "padding", "window", "rotation" } do
		t.it(`a {change} change supersedes pending measurements and reveals the current caret`, function()
			local p = probe()
			local rects = {}
			p.wire(function(rect)
				table.insert(rects, rect)
			end)
			p.fire("CursorPosition")
			local pending = p.begin()
			if change == "font" then
				p.instance.FontFace = "new-font"
				p.fire("styled:FontFace")
			elseif change == "padding" then
				p.pad.PaddingTop.Offset = 24
				p.pad.PaddingRight.Offset = 40
				p.fire("Padding")
			elseif change == "window" then
				-- The editor's size is unchanged when only its viewport gets shorter.
				p.fire("AbsoluteWindowSize")
			else
				p.instance.AbsoluteSize.X = 140
				p.fire("AbsoluteSize")
			end
			p.finish(pending)
			t.expect(#rects).toBe(0)
			p.drain()
			t.expect(#rects).toBe(1)
			t.expect(rects[1].y).toBe(p.pad.PaddingTop.Offset + 48)
			local lastRequest = p.requests[#p.requests]
			t.expect(lastRequest.Font).toBe(p.instance.FontFace)
			t.expect(lastRequest.Width)
				.toBe(p.instance.AbsoluteSize.X - p.pad.PaddingLeft.Offset - p.pad.PaddingRight.Offset)
		end)
	end

	t.it("snapshot validation retries a font change even before its event is delivered", function()
		local p = probe()
		local calls = 0
		p.wire(function()
			calls += 1
		end)
		p.fire("Text")
		local pending = p.begin()
		p.instance.FontFace = "late-event-font"
		p.finish(pending)
		t.expect(calls).toBe(0)
		p.drain()
		t.expect(calls).toBe(1)
		t.expect(p.requests[#p.requests].Font).toBe("late-event-font")
	end)

	t.it("a caret near the start of an overlong word does not reveal the word's final line", function()
		local p = probe()
		p.instance.Text = string.rep("x", 80)
		p.instance.CursorPosition = 3
		local rect
		p.wire(function(r)
			rect = r
		end)
		p.fire("CursorPosition")
		p.drain()
		t.expect(rect.y).toBe(12)
		t.expect(p.requests[#p.requests].Text).toBe("xx\u{200B}")
	end)

	t.it("the harness detects a stale owner when identity guards are removed", function()
		local mutated = string.gsub(caretSource, "handle%.textHandlers ~= handlers", "false")
		local p = probe(mutated)
		local stale = 0
		p.wire(function()
			stale += 1
		end)
		p.fire("Text")
		local pending = p.begin()
		p.wire(function() end)
		p.finish(pending)
		t.expect(stale).toBe(1)
	end)
end)
