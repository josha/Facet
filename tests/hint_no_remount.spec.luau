--!strict
local harness = require("./lib/harness")
-- Phase 1 proof (UI-INPUT-002): a PreferredInput change updates hint
-- bindings on MOUNTED controls without any factory rerun, remount, or
-- structural change — and other bindings keep working throughout.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src")
local fake_target = require("../tests/lib/fake_target")
local Compose = require("../src/vendor/compose/core")

describe("hint changes without remount", function()
	it("preferredInput flip updates the hint text prop only; zero factory reruns", function()
		local core = harness.newCore()
		local env = Facet.newEnvironment(core)
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new({ ops = true })
		local hint = Compose.formula(function(use)
			local preferred = use(env:get("preferredInput"))
			return if preferred == "Touch" then "Tap Save" else "Press Enter"
		end)
		local screen = harness.UI.Screen({
			id = "S",
			children = {
				harness.UI.Text({ id = "Hint", text = hint, textSize = 14 }),
				harness.UI.Button({ id = "Save", label = "Save" }),
			},
		})
		local pres = harness.newPresenter(core, env, adapter, system)
		local handle = pres.present(screen)
		local runsBefore = handle.root.counters().factoryRuns
		local mountedBefore = handle.root.counters().mounted
		adapter.takeOps()

		env:set("preferredInput", "Touch")
		pres.refresh()

		expect(adapter.node("/S/Hint").props.text).toBe("Tap Save")
		expect(handle.root.counters().factoryRuns).toBe(runsBefore) -- no rerun
		expect(handle.root.counters().mounted).toBe(mountedBefore) -- no remount
		-- keyboard binding still works after the flip (inputs never removed)
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		expect(pres.focus.focused:peek()).toBe("/S/Save")
	end)
end)

--[[ ONE OWNERSHIP IDIOM FOR THE TWO REACTIVE HELPERS
	(api-architecture-consistency F-33). `adaptive.conditions(env, opts?)`
	takes `opts.scope` and owns its memos; `inputHint(core, env, action, opts?)`
	already had an `opts` table and made the caller dispose the memo by hand — two
	disposal disciplines for two calls that look identical. One memo instead of
	twelve is a fair reason to care less; it is not a reason for the SHAPE to
	differ. And `opts.style` silently defaulted on a typo, where every sibling
	string enum (`rootPolicy`, `cancelPolicy`, `responder`, `scrim`) errors and
	names its legal set. ]]
describe("inputHint: scope ownership and a validated style (F-33)", function()
	local hintLib = require("../src/input/hint")
	local customFactory = harness.coreFactory
	local environment = require("../src/env/environment")
	local actionsLib = require("../src/input/actions")

	local function world()
		local core = customFactory.new()
		local env = environment.new(core)
		local system = actionsLib.newSystem(core)
		local context = system.createContext({ name = "Nav", priority = 1 })
		local action = context.createAction("Activate", "Bool")
		action.bind({ keyCode = "Return", displayName = "Enter", inputKind = "KeyboardAndMouse" })
		return core, env, action
	end

	it("opts.scope owns the memo, so a screen cannot leak it", function()
		local core, env, action = world()
		local baseline = core.owner.size()
		local scope = core.owner.createChild()
		local label = hintLib.inputHint(core, env, action, { scope = scope })
		expect(type(label:peek())).toBe("string")
		expect(core.owner.size()).toBe(baseline + 1)
		scope:dispose()
		expect(core.owner.size()).toBe(baseline)
	end)

	it("omitting the scope leaves the memo to the caller, exactly as before", function()
		local core, env, action = world()
		local baseline = core.owner.size()
		local label = hintLib.inputHint(core, env, action)
		expect(type(label:peek())).toBe("string")
		-- nothing was registered on the application owner: the formula is the
		-- caller's, and `dispose` is the caller's to call
		expect(core.owner.size()).toBe(baseline)
		label:dispose()
		expect(core.owner.size()).toBe(baseline)
	end)

	it("an unknown style fails at the call site, naming the legal set", function()
		local core, env, action = world()
		local ok, err = pcall(function()
			return hintLib.inputHint(core, env, action, { style = "Phrase" })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "style", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "Phrase", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "phrase", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "key", 1, true) ~= nil).toBe(true)
	end)

	it("both legal styles still resolve", function()
		local core, env, action = world()
		env:set("preferredInput", "KeyboardAndMouse")
		local key = hintLib.inputHint(core, env, action, { style = "key" })
		local phrase = hintLib.inputHint(core, env, action, { style = "phrase" })
		expect(key:peek()).toBe("Enter")
		expect(phrase:peek()).toBe("Press Enter")
		key:dispose()
		phrase:dispose()
	end)
end)
