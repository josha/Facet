--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local Compose = Facet.Compose

local world = require("./lib/native_motion_world")

t.describe("Native text input", function()
	t.it("edits Compose state and releases its clear button without Facet scopes", function()
		local app, adapter, advance, core = world()
		local value = Compose.cell("draft")
		local committed
		local close = app.mount(function()
			local before = core.owner.size()
			local node = app.controls.TextInput("Message")({
				value = value,
				clearButton = true,
				onCommit = function(text)
					committed = text
				end,
			})
			t.expect(core.owner.size()).toBe(before)
			return node
		end)
		advance(0.05)
		adapter.focusText("/Message/Field")
		adapter.typeText("/Message/Field", "hello")
		adapter.commitText("/Message/Field")
		advance(0.05)
		t.expect(value:peek()).toBe("drafthello")
		t.expect(committed).toBe("drafthello")
		t.expect(adapter.node("/Message/Clear") ~= nil).toBe(true)
		adapter.driveActivate("/Message/Clear")
		advance(0.05)
		t.expect(value:peek()).toBe("")
		t.expect(adapter.node("/Message/Clear")).toBeNil()
		close()
		advance(0.1)
		t.expect(adapter.rootCount()).toBe(0)
		app.dispose()
	end)
	t.it("uses interruptible Compose shake motion and cancels it for reduced motion", function()
		local app, adapter, advance = world()
		local invalid = Compose.cell(false)
		local close = app.mount(function()
			return app.controls.TextInput("Message")({ value = Compose.cell(""), invalid = invalid })
		end)
		advance(0.05)
		local function shift()
			local node = adapter.node("/Message")
			return node.presentedPosition.x - node.rect.x
		end
		local rest = adapter.node("/Message").rect.x
		t.expect(shift()).toBe(0)
		invalid:set(true)
		advance(1 / 60)
		t.expect(shift() ~= 0).toBe(true)
		t.expect(adapter.node("/Message").rect.x).toBe(rest)
		advance(0.1)
		invalid:set(false)
		invalid:set(true)
		advance(1 / 60)
		t.expect(shift() < 0).toBe(true)
		app.environment:set("reducedMotion", true)
		advance(1 / 60)
		t.expect(shift()).toBe(0)
		advance(0.3)
		t.expect(shift()).toBe(0)
		close()
		advance(0.3)
		t.expect(adapter.rootCount()).toBe(0)
		app.dispose()
	end)
end)
