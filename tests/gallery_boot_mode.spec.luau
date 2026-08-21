--!strict
--[[ WHICH SURFACE THE PLACE BOOTS — and the §5 verification surface that a demo
	shell had been quietly eating (live Studio session, 2026-08-20).

	WHAT HAPPENED. `workspace.Facet_Scenario = "table_virtualized"` set in Edit,
	then Play, in the rebuilt showcase place: no `workspace.FacetScenarioAPI`, no
	error, no warning — just the ordinary `[Facet Showcase]` boot line. The
	scenario selector is `fable-execution-contract` §5 infrastructure, so the
	symptom is not "a demo did not appear"; it is that the ONE surface an external
	driver verifies this framework through reported a healthy boot while declining
	to exist.

	THE CAUSE was an ordering fact, present since the first commit and invisible
	because it is spelled as control flow rather than as a decision:
	`init.client.luau` read `Facet_Showcase` FIRST, mounted the showcase, and
	`return`ed — a hundred lines above where it would have read `Facet_Scenario`.
	In the showcase place that attribute is baked in by `tools/build_places.sh`, so
	the §5 selectors below it were unreachable in the one place a device pass
	opens. It stayed survivable only because the tribal workaround was written down
	in a plan (`docs/plans/device-bug-round-2026-08-12.md`: "set
	`Facet_Showcase = false` and `Facet_Scenario = ...`"), and because a rename
	wave briefly made the baked attribute stop matching the branch, which is why
	the flow appeared to work on 2026-08-17 and stopped when the place was rebuilt.

	THE RULE THIS FILE PINS. A verification selector OUTRANKS the demo shell, in
	every place, always — and a selector that was SET and cannot be honoured says
	so out loud instead of falling through to something that looks like a passing
	run. `boot_mode.decide` is that decision, and the shipped bootstrap has no
	second copy of it: the last case here is what keeps it that way. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")
local boot_mode = require("../examples/gallery/client/boot_mode")

-- the registered scenario names, READ FROM SOURCE because `scenarios/init.luau`
-- resolves every entry through `script:WaitForChild` and cannot be required
-- headlessly (same technique and same reason as `row_capabilities_scenario.spec`)
local function registeredScenarios(): { [string]: boolean }
	local source = fs.readFile("examples/gallery/scenarios/init.luau")
	local block = string.match(source, "local ORDER = (%b{})")
	assert(block ~= nil, "scenarios/init.luau no longer has a `local ORDER = { ... }` block to read")
	local names: { [string]: boolean } = {}
	local count = 0
	for name in string.gmatch(block :: string, '"([%w_]+)"') do
		names[name] = true
		count += 1
	end
	assert(count > 20, `the ORDER parse found only {count} entries — the block shape changed`)
	return names
end

-- the attribute set a place actually presents, spelled the way Roblox hands it
-- over: absent keys are `nil`, and every present one is whatever was typed in
-- the Edit-session property pane
local function selectors(over: any?): any
	local s: any = { showcase = nil, scenario = nil, example = nil }
	for k, v in (over or {}) :: any do
		s[k] = v
	end
	return s
end

describe("gallery boot mode: §5 verification outranks the demo shell", function()
	--[[ THE DEFECT, in one row. The showcase place bakes `Facet_Showcase = true`
		into its Workspace; a developer adds `Facet_Scenario` in Edit and presses
		Play. Before the fix this decided "showcase" and the scenario API was never
		built. ]]
	it("a scenario selector wins in the showcase place", function()
		local d = boot_mode.decide(selectors({ showcase = true, scenario = "table_virtualized" }))
		expect(d.mode).toBe("scenario")
		expect(d.scenario).toBe("table_virtualized")
		expect(#d.refusals).toBe(0)
	end)

	it("...and so does a tutorial-example selector", function()
		local d = boot_mode.decide(selectors({ showcase = true, example = 3 }))
		expect(d.mode).toBe("example")
		expect(d.example).toBe(3)
	end)

	--[[ THE TWO NAMES THE LIVE REPORT USED, checked against the shipped registry
		rather than against this file's memory of it: if either stopped being
		registered, the row above would be pinning a decision nothing can honour. ]]
	it("the reported scenario names are registered", function()
		local registered = registeredScenarios()
		expect(registered["table_virtualized"]).toBe(true)
		expect(registered["examples"]).toBe(true)
	end)

	it("the showcase still wins when no verification selector is set", function()
		expect(boot_mode.decide(selectors({ showcase = true })).mode).toBe("showcase")
	end)

	it("a place with no attributes at all boots the plain demo", function()
		local d = boot_mode.decide(selectors())
		expect(d.mode).toBe("demo")
		expect(#d.refusals).toBe(0)
	end)

	-- a scenario is the more specific instrument, and the one an external driver
	-- polls attributes for; it outranks the example selector when both are set
	it("a scenario outranks an example", function()
		expect(boot_mode.decide(selectors({ scenario = "probe", example = 2 })).mode).toBe("scenario")
	end)
end)

describe("gallery boot mode: a selector that cannot be honoured is never silent", function()
	--[[ THE FALSE-EVIDENCE-MACHINE RULE. Every branch below used to be spelled as
		`if type(x) == "string" and x ~= "" then` with no else — the exact shape that
		turns a typo into a healthy-looking boot. ]]
	it("an empty scenario name refuses, and names the attribute", function()
		local d = boot_mode.decide(selectors({ showcase = true, scenario = "" }))
		expect(d.mode).toBe("showcase")
		expect(#d.refusals).toBe(1)
		expect(string.find(d.refusals[1], "Facet_Scenario", 1, true) ~= nil).toBe(true)
	end)

	it("a scenario attribute of the wrong type refuses, and names the type", function()
		local d = boot_mode.decide(selectors({ scenario = true }))
		expect(d.mode).toBe("demo")
		expect(#d.refusals).toBe(1)
		expect(string.find(d.refusals[1], "boolean", 1, true) ~= nil).toBe(true)
	end)

	it("an example outside the shipped range refuses, and names the range", function()
		for _, bad in { 0, 8, 2.5, "3" } :: { any } do
			local d = boot_mode.decide(selectors({ example = bad }))
			expect(d.mode).toBe("demo")
			expect(#d.refusals).toBe(1)
			expect(string.find(d.refusals[1], "Facet_Example", 1, true) ~= nil).toBe(true)
			expect(string.find(d.refusals[1], tostring(#boot_mode.EXAMPLE_MODULES), 1, true) ~= nil).toBe(true)
		end
	end)

	-- both selectors mistyped: BOTH reasons are reported, because fixing one and
	-- pressing Play again to meet the other is two device sessions
	it("two bad selectors report two reasons", function()
		expect(#boot_mode.decide(selectors({ scenario = 5, example = 99 })).refusals).toBe(2)
	end)

	--[[ EVERY refusal, whatever produced it, carries the same three things: the
		attribute the author typed, why this run cannot honour it, and the fact that
		the selector is a verification surface rather than a convenience. ]]
	it("every refusal names the selector, the reason, and what the selector is for", function()
		local cases: { any } = {
			selectors({ scenario = "" }),
			selectors({ scenario = 1 }),
			selectors({ example = 0 }),
			selectors({ example = "x" }),
		}
		for _, case in cases do
			local d = boot_mode.decide(case)
			expect(#d.refusals).toBe(1)
			local message = d.refusals[1]
			expect(string.find(message, "[Facet Boot]", 1, true) ~= nil).toBe(true)
			expect(string.find(message, "§5", 1, true) ~= nil).toBe(true)
			expect(string.find(message, "could not honour it", 1, true) ~= nil).toBe(true)
		end
	end)

	--[[ THE REFUSALS `decide` CANNOT SEE are the ones that need the running place:
		the scenario folder was not replicated, the named scenario is not registered,
		the runner threw on the way up. They speak with the same voice, and they
		leave a MACHINE-READABLE state behind — an external driver polls
		`Facet_ScenarioState`, and "absent" cannot be told apart from "still
		booting". ]]
	it("a runtime refusal shares the voice, and stamps a state a driver can read", function()
		local message = boot_mode.refusal("Facet_Scenario", "FacetScenarios is not replicated into this place")
		expect(string.find(message, "[Facet Boot]", 1, true) ~= nil).toBe(true)
		expect(string.find(message, "§5", 1, true) ~= nil).toBe(true)
		expect(string.find(message, "not replicated", 1, true) ~= nil).toBe(true)
		expect(boot_mode.refusedState("no-registry")).toBe("refused:no-registry")
	end)
end)

describe("gallery boot mode: the shipped bootstrap decides here and nowhere else", function()
	--[[ THE SPEC'S OWN HONESTY, in the shape `gallery_demo_host.spec` uses: the
		decision driven above is the one the player's place runs. If
		`init.client.luau` grows its own attribute read again, this file goes back to
		pinning a copy — which is the state the defect was found in. ]]
	local source = fs.readFile("examples/gallery/client/init.client.luau")

	local function countOf(needle: string): number
		local count, from = 0, 1
		while true do
			local at = string.find(source, needle, from, true)
			if at == nil then
				return count
			end
			count += 1
			from = at + 1
		end
	end

	--[[ EACH SELECTOR IS READ ONCE, and that once is the decision's argument. A
		count is the honest form of this check: "the literal never appears" would be
		satisfied by splitting the string, and "it appears" would be satisfied by the
		second reader that is the whole defect. ]]
	it("each selector attribute is read exactly once, into the decision", function()
		local call = string.match(source, "boot_mode%.decide%((%b{})")
		assert(call ~= nil, "init.client.luau no longer calls boot_mode.decide({ ... })")
		for _, attribute in { "Facet_Showcase", "Facet_Scenario", "Facet_Example" } do
			local read = `GetAttribute("{attribute}")`
			expect(countOf(read)).toBe(1)
			expect(string.find(call :: string, read, 1, true) ~= nil).toBe(true)
		end
	end)

	it("the bootstrap branches on the decision", function()
		expect(string.find(source, "boot_mode.decide", 1, true) ~= nil).toBe(true)
		for _, mode in { "scenario", "example", "showcase" } do
			expect(string.find(source, `bootDecision.mode == "{mode}"`, 1, true) ~= nil).toBe(true)
		end
	end)

	-- a refusal that is computed and not spoken is the original defect wearing a
	-- return value: the bootstrap must warn every one of them
	it("the bootstrap warns every refusal the decision reports", function()
		expect(string.find(source, "for _, refusal in bootDecision.refusals do", 1, true) ~= nil).toBe(true)
		expect(string.find(source, "warn(refusal)", 1, true) ~= nil).toBe(true)
	end)

	--[[ THE REFUSALS `decide` CANNOT SEE, pinned where they are spoken. These are
		the ones that need the running place, and each of them used to be a `warn`
		into the void or nothing at all. ]]
	it("a scenario that cannot be mounted is stamped AND spoken", function()
		local body = string.match(source, "local function refuseScenario%b()(.-)\nend")
		assert(body ~= nil, "init.client.luau no longer has a refuseScenario(reason) helper")
		expect(string.find(body :: string, 'SetAttribute("Facet_ScenarioState"', 1, true) ~= nil).toBe(true)
		expect(string.find(body :: string, "boot_mode.refusal", 1, true) ~= nil).toBe(true)
		-- ...and the one refusal only the live place can hit uses it
		expect(string.find(source, 'refuseScenario("FacetScenarios is not replicated', 1, true) ~= nil).toBe(true)
	end)

	-- A SWALLOWED THROW IS THE ORIGINAL DEFECT WEARING A pcall: the runner may
	-- fail on the way up, and that has to leave a state, a sentence, AND a red
	-- console rather than a place that booted quietly into nothing.
	it("a runner that throws is stamped, spoken, and re-raised", function()
		expect(string.find(source, "pcall(runner.start", 1, true) ~= nil).toBe(true)
		expect(string.find(source, "error(result, 0)", 1, true) ~= nil).toBe(true)
	end)

	--[[ ONE LIST, ONE OWNER. "Which numbers are legal" and "which module a number
		names" were two copies in two files; the bootstrap now takes the name the
		decision resolved, so a new example cannot be half-added. ]]
	it("the example module names live only with the selector that validates them", function()
		for _, module in boot_mode.EXAMPLE_MODULES do
			expect(string.find(source, `"{module}"`, 1, true)).toBeNil()
		end
		expect(string.find(source, "bootDecision.exampleModule", 1, true) ~= nil).toBe(true)
	end)
end)
