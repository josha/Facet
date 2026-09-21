--!strict
--[[ WHICH OWNER A PARENTLESS CONTROL GETS.

	A composite built INSIDE a component becomes a child of that component's
	owner, and nothing here is about that case. This is the other one: a control
	built with no active owner, which has to be given an owner of its own.

	That owner has to be a child of the application's root owner, and the reason
	is the whole of `src/core/README.md`. The root owner is created on
	`core.reactor` and guarded by the application's error boundary, and every
	child owner inherits that guard. So a child of it gets three things at once:
	the reactor the LAYOUT SETTLE PASS is installed on, so a write settles the
	surface inside the flush that opened it; the same batching as every other
	write on the surface; and the containment that keeps a throwing binding from
	taking the surface down.

	`Compose.createOwner()` with no reactor argument creates a PRIVATE one
	(`vendor/compose/core/ownership/owner.luau`: `local reactor = inherited or
	Reactor.create()`). A control on a private reactor has none of those three,
	and nothing says so at the call site — which is how fourteen controls came to
	be built that way and seven the other way, so a parentless `UI.Button` and a
	parentless `UI.Callout` did not even agree with each other.
]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local harness = require("./lib/harness")
local Facet = require("../src") :: any
local button = require("../src/controls/button")
local callout = require("../src/controls/callout")
local badge = require("../src/controls/badge")
local UI = Facet.UI or (require("../src/blueprint") :: any)

local function calloutSpec(id: string): any
	return {
		id = id,
		anchor = UI.Button({
			id = "Plus",
			label = "+",
			width = { type = "fixed", px = 44 },
			height = { type = "fixed", px = 44 },
		}),
		content = UI.Text({ id = "Body", text = "There" }),
		onRetire = function() end,
	}
end

local function buildParentless(core: any, control: any, spec: any): any
	local _, _, library = harness.libraryOf(core)
	-- deliberately NOT inside Compose.withOwner: this is the parentless path
	return control.build(library, core, spec)
end

describe("a parentless control belongs to the application", function()
	it("takes an owner under core.owner, so it is on the application's reactor", function()
		local core = harness.newCore()
		local before = core.owner.size()
		buildParentless(core, button, { id = "B", label = "Go" })
		expect(core.owner.size()).toBe(before + 1)
	end)

	it("...and every control agrees, whichever one it is", function()
		local core = harness.newCore()
		local before = core.owner.size()
		buildParentless(core, button, { id = "B", label = "Go" })
		buildParentless(core, button, { id = "B2", label = "Stop" })
		buildParentless(core, callout, calloutSpec("K1"))
		buildParentless(core, callout, calloutSpec("K2"))
		buildParentless(core, badge, { id = "Status", label = "Ready" })
		-- Five controls, five owners, all of them the application's children.
		-- Before the fix this read `before + 0`: `button` took a private reactor and
		-- `callout` a detached root on the core's reactor. Neither was a child.
		expect(core.owner.size()).toBe(before + 5)
	end)

	it("disposing the application disposes what it owns", function()
		local core = harness.newCore()
		buildParentless(core, button, { id = "B", label = "Go" })
		buildParentless(core, callout, calloutSpec("K"))
		core.owner.dispose()
		expect(core.owner.size()).toBe(0)
	end)
end)
