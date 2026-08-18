--!strict
--[[ THE HEADLESS WORLD, AND THE ORDER THAT MAY NOT COME BACK
	(reuse audit REUSE-88; controller ruling R12; `tests/lib/world.luau`).

	A hundred spec files build the same six things before they can present
	anything, and that was never the finding. The finding was that the tuple came
	back in TWO orders with the SAME FIVE NAMES:

	    return core, env, system, adapter, pres   -- 12 files
	    return core, env, adapter, system, pres   -- 16 files

	Positions three and four swapped. Luau binds an action system to a variable
	called `adapter` without a word, so a line copied from a neighbouring spec —
	which is how a suite this size is written — silently tested something else,
	and failed three edits later as "the adapter has no `node` method", in a file
	nobody had touched.

	The twelve moved onto the sixteen's order, which is the order
	`Facet.newPresenter(core, env, adapter, system)` itself takes. THIS FILE IS
	WHAT KEEPS IT AT ONE. A checker would have been the other option and would
	have been worse: the rule is about the test suite's own source, the suite
	already reads its own source in a dozen places, and a rule that only runs
	under `tools/gate.sh` is a rule an author meets for the first time at the
	gate.

	SCOPE IS R12'S, AND THE TRIGGER IS RECORDED. The ~78 spec-local builders that
	never carried the collision were left alone — rewriting a hundred files to
	prove a point is how a suite acquires a regression nobody can bisect. The
	follow-up trigger lives in artifacts/release-candidate-review/reuse-ledger.md:
	the next spec file that ADDS a builder migrates its file.
]]

local fs = require("@lune/fs")
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local worldLib = require("./lib/world")

--[[ EVERY FILE WHOSE TOP-LEVEL BUILDER IS NOW `tests/lib/world.luau`.

	THE COUNTS, RE-MEASURED (R5 review §3c-1). At `d1b2d7b2^`: **12** spec files
	returned the retired order and **15** returned the kept one — the wave said
	sixteen. **24** spec files migrated (this comment said "the twelve plus the
	fourteen", which is 26 and was never true of the list below it), and the
	commit rewrote **91** destructure lines, not the 131 the report claimed.

	THREE KEPT-ORDER FILES WERE LEFT BEHIND and are named rather than papered
	over: `button_complete`, `menu` and `leaf_helpers`. `leaf_helpers` has since
	migrated — the R12 trigger it violated caught up with it — and the other two
	stay under that same trigger. THE GUARD DOES NOT CARE: its first scan is
	every top-level `*.spec.luau`, not this list, so a retired-order return in an
	un-migrated file reddens exactly as it does in a migrated one. ]]
local MIGRATED = {
	"anchored_surface",
	"auto_input",
	"auto_input_screens",
	"control_feedback",
	"display_controls",
	"feedback",
	"help",
	"keyboard_navigation",
	"late_contributions",
	"leaf_helpers",
	"level_picker",
	"modal_dismissal",
	"paradigm_carry",
	"paradigm_input_axis",
	"paradigm_table",
	"presenter",
	"responder",
	"slice_mutation",
	"table_input",
	"text_disclosure",
	"text_reveal",
	"theme_value_displays",
	"toast_presentation",
	"transitions",
	"virtual_list_input",
}

--[[ BUILT, NOT WRITTEN. Spelling the retired order as a literal would make this
	file its own first offender — which it did, on the run that introduced it. The
	file is also the ONE place the retired order is legal to name at all, because
	explaining it is what the file is for, so it excludes itself by name and the
	needle is assembled so the exclusion is not what does the work. ]]
local RETIRED_ORDER = "return " .. table.concat({ "core", "env", "system", "adapter", "pres" }, ", ")
local SELF = "world_substrate.spec.luau"

describe("the headless world substrate (REUSE-88)", function()
	it("builds the six pieces, viewport first, one presenter per adapter", function()
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 800, h = 600 } })
		expect(w.env:get("viewportRect"):get().w).toBe(800)
		expect(w.core ~= nil).toBe(true)
		expect(w.adapter ~= nil).toBe(true)
		expect(w.system ~= nil).toBe(true)
		expect(w.pres ~= nil).toBe(true)
		-- two worlds are two of everything: an adapter shared between presenters is
		-- ADR-0009's refusal, and a spec that reuses one gets cross-talk it cannot
		-- see (the instance map and the capture state are adapter-scoped)
		local other = worldLib.new()
		expect(other.adapter ~= w.adapter).toBe(true)
		expect(other.pres ~= w.pres).toBe(true)
	end)

	it("the default viewport is a phone portrait, and every named fact is optional", function()
		local w = worldLib.new()
		local vp = w.env:get("viewportRect"):get()
		expect(`{vp.w}x{vp.h}`).toBe("390x844")
	end)

	it("named facts land on the environment, and `env` takes the ones with no name", function()
		local w = worldLib.new({
			viewport = { x = 0, y = 0, w = 400, h = 600 },
			safeInsets = { top = 5, bottom = 5, left = 0, right = 0 },
			preferredInput = "Touch",
			displaySize = "Large",
			reducedMotion = true,
			env = { preferredTextOffset = 10 },
		})
		expect(w.env:get("coreSafeInsets"):get().top).toBe(5)
		expect(w.env:get("preferredInput"):get()).toBe("Touch")
		expect(w.env:get("displaySize"):get()).toBe("Large")
		expect(w.env:get("reducedMotion"):get()).toBe(true)
		expect(w.env:get("preferredTextOffset"):get()).toBe(10)
	end)

	it("settle is N frames of clock AND solve, and never zero of them", function()
		local UI = require("../src/blueprint")
		local w = worldLib.new()
		local ticks = 0
		w.present(UI.Screen({ id = "S", children = { UI.Button({ id = "B", label = "B" }) } }))
		w.pres.onTick(function()
			ticks += 1
		end)
		w.settle(3)
		expect(ticks).toBe(3)
		w.settle() -- no argument is ONE frame, never zero
		expect(ticks).toBe(4)
		w.settle(0) -- ...and neither is an explicit zero
		expect(ticks).toBe(5)
	end)

	--[[ `press` was seventeen hand-rolled copies, and the way a hand-rolled one
		goes wrong is a down with no up: the key stays held, so the SECOND press is
		not an edge at all and simply does not arrive. The case presses twice for
		exactly that reason — one press proves nothing about the release. ]]
	it("press is both edges, so the same key twice is two activations", function()
		local UI = require("../src/blueprint")
		local w = worldLib.new({ presenterOpts = { keyboardNavigation = true } })
		local fired = 0
		w.present(UI.Screen({
			id = "S",
			children = {
				UI.Button({
					id = "B",
					label = "B",
					onActivate = function()
						fired += 1
					end,
				}),
			},
		}))
		w.press("Return")
		w.pres.refresh()
		expect(fired).toBe(1)
		w.press("Return")
		w.pres.refresh()
		expect(fired).toBe(2)
	end)
end)

--[[ THE GUARD. Not "is there duplication" — that question has no automatable
	answer — but "has the retired spelling come back", which has exactly one. ]]
describe("REUSE-88: the retired tuple order stays retired", function()
	it("no spec returns the swapped order any more", function()
		local offenders: { string } = {}
		for _, name in fs.readDir("tests") do
			if string.sub(name, -10) ~= ".spec.luau" or name == SELF then
				continue
			end
			local source = fs.readFile(`tests/{name}`)
			--[[ BOTH SPELLINGS. The hand-rolled builders returned bare names; a shim
				over the substrate returns `w.core, w.env, …`, and swapping the fields
				THERE reintroduces exactly the same collision with none of the same
				text. The second needle is a Lua pattern with a backreference, so it
				matches any local name the shim happens to use. ]]
			if
				string.find(source, RETIRED_ORDER, 1, true) ~= nil
				or string.find(source, "return ([%w_]+)%.core, %1%.env, %1%.system, %1%.adapter, %1%.pres") ~= nil
			then
				table.insert(offenders, name)
			end
		end
		table.sort(offenders)
		--[[ THE MESSAGE IS THE FIX, because the author who trips this is writing a
			builder and copying it from somewhere. `core, env, adapter, system, pres`
			is the order `Facet.newPresenter` takes; `tests/lib/world.luau` is where
			the construction lives. ]]
		expect(`files returning the retired order: {table.concat(offenders, ", ")}`).toBe(
			"files returning the retired order: "
		)
	end)

	--[[ THE R12 TRIGGER, MADE MECHANICAL (R5 review §3c-2).

		The trigger is "the next spec file that ADDS a builder migrates its file",
		and its only trace was a `grep -qF` in the gate row for the SENTENCE — the
		gate asserted the rule was written down, not that anyone honoured it. It
		was violated inside the wave that wrote it: `tests/leaf_helpers.spec.luau`
		added a hand-rolled six-piece builder hours before the substrate landed.

		A RATCHET IS THE ONLY HONEST MECHANISATION. "No spec may build a presenter
		by hand" is false today by 78 files and R12 deliberately declined to churn
		them, so what can be enforced is the DIRECTION: the count may fall, never
		rise. Adding a builder reddens this; migrating one reddens it too, and the
		fix is to lower the number — which is the point, because that edit is
		where an author reads the trigger.

		THE DETECTOR IS FILE-LEVEL AND SAYS SO: "this file declares a builder AND
		constructs a presenter somewhere". It cannot tell whether the presenter is
		built INSIDE the builder without parsing Luau, so the number is a stable
		over-approximation rather than a census — which is all a ratchet needs, so
		long as the pin is what THIS detector sees rather than a number measured
		some other way. ]]
	local HAND_ROLLED_BUILDERS = 78

	it("the count of hand-rolled presenter builders only ever falls (R12 trigger)", function()
		local live: { string } = {}
		for _, name in fs.readDir("tests") do
			if string.sub(name, -10) ~= ".spec.luau" then
				continue
			end
			local source = fs.readFile(`tests/{name}`)
			local hasBuilder = string.find(source, "local function world", 1, true) ~= nil
				or string.find(source, "local function makeWorld", 1, true) ~= nil
				or string.find(source, "local function harness", 1, true) ~= nil
			local buildsPresenter = string.find(source, "presenterLib.newPresenter(", 1, true) ~= nil
				or string.find(source, "presenterLib.new(", 1, true) ~= nil
				or string.find(source, "Facet.newPresenter(", 1, true) ~= nil
			if hasBuilder and buildsPresenter then
				table.insert(live, name)
			end
		end
		if #live > HAND_ROLLED_BUILDERS then
			error(
				`{#live} spec files build a presenter by hand, up from {HAND_ROLLED_BUILDERS}. `
					.. "R12's follow-up trigger: the next spec file that ADDS a builder migrates its "
					.. "file onto tests/lib/world.luau instead. If you migrated one, lower "
					.. "HAND_ROLLED_BUILDERS in this file to match.",
				0
			)
		end
		--[[ AND IT MUST NOT SILENTLY DRIFT DOWN EITHER: a stale high pin is a
			ratchet with slack in it, which is how a ceiling stops being one. ]]
		expect(`hand-rolled builders: {#live} (pin {HAND_ROLLED_BUILDERS})`).toBe(
			`hand-rolled builders: {HAND_ROLLED_BUILDERS} (pin {HAND_ROLLED_BUILDERS})`
		)
	end)

	it("every migrated file builds on the shared substrate rather than by hand", function()
		local missing: { string } = {}
		for _, name in MIGRATED do
			local source = fs.readFile(`tests/{name}.spec.luau`)
			if string.find(source, 'require("./lib/world")', 1, true) == nil then
				table.insert(missing, name)
			end
		end
		expect(`migrated files that stopped using the substrate: {table.concat(missing, ", ")}`).toBe(
			"migrated files that stopped using the substrate: "
		)
	end)
end)
