--!strict
-- Vendor smoke: proves Fusion 0.3 (vendored, require-transformed) runs
-- headless under Lune via the state-subset facade + LuneExternal provider.
-- The root init (Instances layer) is engine-only; see tests/lib/fusion_headless.
-- Deeper semantics live in the shared core conformance suite.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuneExternal = require("./lib/fusion_lune_external")
local scheduler = LuneExternal.setup()

local Fusion = require("./lib/fusion_headless")

describe("vendored Fusion 0.3", function()
	it("Value/Computed propagate and peek lazily recomputes", function()
		local scope = Fusion.scoped(Fusion)
		local source = scope:Value(2)
		local doubled = scope:Computed(function(use)
			return use(source) * 2
		end)
		expect(Fusion.peek(doubled)).toBe(4)
		source:set(5)
		expect(Fusion.peek(doubled)).toBe(10)
		Fusion.doCleanup(scope)
	end)

	it("Observer fires on change and disconnects on cleanup", function()
		local scope = Fusion.scoped(Fusion)
		local source = scope:Value(1)
		local fired = 0
		local disconnect = scope:Observer(source):onChange(function()
			fired += 1
		end)
		source:set(2)
		scheduler.step(0)
		expect(fired).toBe(1)
		disconnect()
		source:set(3)
		scheduler.step(0)
		expect(fired).toBe(1)
		Fusion.doCleanup(scope)
	end)
end)
