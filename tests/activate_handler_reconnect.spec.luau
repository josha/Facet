--!strict
-- THE ACTIVATE CONNECTION LEAK, ON A RECYCLED INSTANCE (device bug fix round,
-- director 2026-08-23: "nested-tabs hit targets shift after a bottom-tab round
-- trip").
--
-- Repro (live, showcase "Tabs, nested" demo, `tab_view` scenario): the app-level
-- tabs are Pages/Inbox/Notes/Profile; Pages hosts a NESTED page-level strip of
-- eight tabs. Pages -> Notes -> Pages tears down and remounts the nested strip
-- (`UI.When` disposes/rebuilds it). Measured after that round trip: a tap on
-- "Clothing"'s own painted rect (screenshot-confirmed, no hit-expander involved
-- — every option here is 69px tall, above the touch floor) selected
-- "Backgrounds" instead. Root cause, traced to the source: instance recycling
-- is ON by default (`render/renderer.luau`'s create-or-adopt block), so a
-- RECYCLED (parked-then-adopted) instance is never destroyed between lives —
-- only reparented. `adapter.setActivateHandler` (`screen_pointer.luau`) ran
-- once per (path, fresh-or-adopted handle) and did
-- `instance.Activated:Connect(...)` WITHOUT disconnecting whatever connection
-- the instance's PRIOR life left on it. Each connection is a closure over
-- `local path = node.path` captured at a DIFFERENT commit, so a several-times-
-- recycled button accumulated multiple stale listeners bound to whichever
-- nodes it used to represent, and a single real click fired all of them —
-- `dispatchNodeTapOnce` is keyed per PATH, so a stale path's dispatch is not
-- suppressed as an echo of the fresh one.
--
-- Fixed live and confirmed in Studio (2026-08-23): Pages -> Notes -> Pages,
-- click "Clothing" -> "clothing" selected (was "backgrounds"); a second round
-- trip (-> Inbox -> Pages), click "Accessories" -> "accessories" selected.
--
-- `screen_pointer.luau` reaches engine globals (`Instance`, `RBXScriptSignal`)
-- at load time and cannot run headlessly, so — same instrument
-- `theme_layer_application.spec.luau`/`focus_ring_float_geometry.spec.luau`
-- use — this reads the live adapter as TEXT and pins the fix structurally.
-- Reverting the disconnect turns the first case below red.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")
local adapter_source = require("./lib/adapter_source")

local source = fs.readFile("src/client/screen_pointer.luau")
local FN = adapter_source.bodyOf(source, "function adapter.setActivateHandler(")

describe("screen_pointer.setActivateHandler: no leaked connection on a recycled instance", function()
	it("found the function body (the anchor still names a real member)", function()
		expect(#FN > 0).toBe(true)
	end)

	it("disconnects any PRIOR activatedConn before connecting a new one", function()
		local disconnectAt = string.find(FN, "handle.activatedConn:Disconnect()", 1, true)
		expect(disconnectAt ~= nil).toBe(true)
		local connectAt = string.find(FN, "instance.Activated:Connect(function(inputObject", 1, true)
		expect(connectAt ~= nil).toBe(true)
		-- ORDER: the old connection must go before the new one is made, or a
		-- recycled instance still ends the call holding two live listeners
		expect((disconnectAt :: number) < (connectAt :: number)).toBe(true)
	end)

	it("nils the field after disconnecting (so a later re-entry cannot double-disconnect)", function()
		local at = string.find(FN, "handle.activatedConn:Disconnect()\n\t\t\thandle.activatedConn = nil", 1, true)
		expect(at ~= nil).toBe(true)
	end)
end)
