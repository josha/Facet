--!strict
--[[ WHICH SURFACE THIS PLACE BOOTS — one decision, taken before anything mounts.

	WHAT IT IS FOR. The gallery bootstrap is one client script serving four surfaces:
	the plain settings demo, a numbered tutorial example, a named verification
	SCENARIO, and the hands-on showcase. Which one runs was decided by the ORDER of
	three `if` blocks a hundred lines apart, each reading its own workspace
	attribute and `return`ing — and an ordering that is spelled as control flow is
	an ordering nobody can see, test, or argue with.

	WHY IT IS A MODULE AND NOT THREE `if`s. Because the order was WRONG, in the one
	place a device pass opens, for as long as the place has existed. The showcase
	branch came first, and `tools/build_places.sh` bakes `Facet_Showcase = true`
	into the showcase place's Workspace — so `Facet_Scenario`, the selector the
	`fable-execution-contract` §5 Studio surface is driven by, was unreachable
	there. Setting it produced no scenario, no `workspace.FacetScenarioAPI`, no
	error and no warning: just the ordinary `[Facet Showcase]` boot line. The
	workaround (`Facet_Showcase = false` AND `Facet_Scenario = ...`) survived as a
	line in `docs/plans/device-bug-round-2026-08-12.md` rather than as a fix.

	THE TWO RULES IT HOLDS.

	  1. A VERIFICATION SELECTOR OUTRANKS THE DEMO SHELL, in every place, always. A
	     scenario or an example is an explicit request from whoever is verifying
	     this framework; the showcase is what the place does when nobody asked.

	  2. A SELECTOR THAT WAS SET AND CANNOT BE HONOURED IS NEVER SILENT. Every
	     branch below used to be `if type(x) == "string" and x ~= "" then` with no
	     `else` — the shape that turns a typo into a healthy-looking boot. A
	     verification surface that quietly no-ops is worse than one that errors,
	     because the run it produces still LOOKS like evidence. So an unusable
	     selector becomes a `refusal`: a sentence naming the attribute, the reason,
	     and what the selector is for, which the caller warns.

	The decision is PURE — attributes in, a verdict out — so `init.client.luau`
	keeps only the mounting, and `tests/gallery_boot_mode.spec.luau` drives THIS
	module rather than a copy of it that could drift.
]]

local boot_mode = {}

--[[ The tutorial example modules, in the order the `Facet_Example` attribute
	numbers them (`docs/guide/04-tutorial-examples.md`, `tools/build_places.sh`).
	The list lives HERE, beside the validation, because "which numbers are legal"
	and "which module a number names" are one fact with one owner. ]]
boot_mode.EXAMPLE_MODULES = {
	"01_temperature_converter",
	"02_playlist_table",
	"03_settings_sync",
	"04_confirm_dialog",
	"05_word_game",
	"06_tile_game",
	"07_match3",
}

export type Selectors = {
	-- workspace attribute Facet_Showcase (baked into the showcase place)
	showcase: any,
	-- workspace attribute Facet_Scenario (a registered scenario name)
	scenario: any,
	-- workspace attribute Facet_Example (1..#EXAMPLE_MODULES)
	example: any,
}

export type Decision = {
	mode: "scenario" | "example" | "showcase" | "demo",
	scenario: string?,
	example: number?,
	exampleModule: string?,
	-- selectors that WERE SET and could not be honoured; the caller warns each
	refusals: { string },
}

--[[ The one voice every refusal speaks in, including the ones `decide` cannot
	see — the scenario folder was not replicated, the name is not registered, the
	runner threw on the way up. `init.client.luau` uses this for those too. ]]
function boot_mode.refusal(selector: string, reason: string): string
	return `[Facet Boot] {selector} was set, and this run could not honour it: {reason}. `
		.. `That selector is the Studio verification surface (fable-execution-contract §5), `
		.. `so it says so here rather than booting a demo that would look like a passing run.`
end

--[[ The machine-readable half. An external driver polls `Facet_ScenarioState`,
	and an ABSENT attribute cannot be told apart from "still booting" — so a
	refusal leaves a state behind as well as a sentence in the console. ]]
function boot_mode.refusedState(reason: string): string
	return "refused:" .. reason
end

local function describe(value: any): string
	if type(value) == "string" then
		return `the {type(value)} "{value}"`
	end
	return `the {type(value)} {tostring(value)}`
end

function boot_mode.decide(selectors: Selectors): Decision
	local refusals: { string } = {}

	-- RULE 1, and the whole of the fix: the §5 selectors are read BEFORE the demo
	-- shell, not a hundred lines below a branch that has already returned.
	local scenario = selectors.scenario
	if scenario ~= nil then
		if type(scenario) == "string" and scenario ~= "" then
			return { mode = "scenario", scenario = scenario, refusals = refusals }
		end
		table.insert(
			refusals,
			boot_mode.refusal(
				"Facet_Scenario",
				`it is {describe(scenario)}, and a scenario name is a non-empty string registered in `
					.. `examples/gallery/scenarios/init.luau`
			)
		)
	end

	local example = selectors.example
	if example ~= nil then
		local module = if type(example) == "number" then boot_mode.EXAMPLE_MODULES[example] else nil
		if module ~= nil then
			return { mode = "example", example = example, exampleModule = module, refusals = refusals }
		end
		table.insert(
			refusals,
			boot_mode.refusal(
				"Facet_Example",
				`it is {describe(example)}, and the shipped tutorial examples are the whole numbers `
					.. `1..{#boot_mode.EXAMPLE_MODULES}`
			)
		)
	end

	-- ...and the showcase is what this place does when NOBODY ASKED. Note that a
	-- refusal above still travels with it: a mistyped selector must be reported
	-- even though the place went on to boot something.
	if selectors.showcase == true then
		return { mode = "showcase", refusals = refusals }
	end

	return { mode = "demo", refusals = refusals }
end

return boot_mode
