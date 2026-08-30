--!strict
-- Phase 4 agentic-maintainability enforcement (design §17 Phase 4;
-- UI-AGENT-001): the registration checker fails the gate when any composite
-- control lacks registry coverage (conformance, spec, docs, dump surface),
-- when the API reference drifts from the actual public exports (either
-- direction), when a spec file exists but is not registered in the runner (a
-- green suite with an unregistered spec is a silent zero), or when an
-- extension playbook is missing. The scaffold plans a complete new-control /
-- new-adapter skeleton (source, spec, registry entry, docs stub) so
-- registration cannot be forgotten.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local checker = require("../tools/lune/check_registration")
local scaffold = require("../tools/lune/scaffold")

local function problemsMentioning(result: any, needle: string): number
	local n = 0
	for _, problem in result.problems :: { string } do
		if string.find(problem, needle, 1, true) ~= nil then
			n += 1
		end
	end
	return n
end

-- ENF-1 raised the api.md coverage bar twice in one pass: a public export now
-- needs its own `###` heading (a mention no longer counts), and every member of
-- every namespace export needs a QUALIFIED entry. Both rules immediately found
-- real, pre-existing documentation gaps, and this suite held the checker to "no
-- problem OTHER than those fourteen enumerated gaps"
-- (artifacts/api-architecture-consistency/enforcement-gap-list.txt) — a list
-- written to shrink and never grow.
--
-- It shrank to nothing: the 0.8.0 documentation package closed all fourteen, so
-- the tolerance is GONE. The live repository must now produce no registration
-- problem at all, of any shape.
local function unexpectedProblems(result: any): { string }
	return table.clone(result.problems :: { string })
end

describe("registration checker (agentic maintainability)", function()
	it("the live repository passes every registration rule", function()
		local result = checker.check()
		local unexpected = unexpectedProblems(result)
		if #unexpected > 0 then
			error("checker problems:\n  " .. table.concat(unexpected, "\n  "))
		end
		expect(#unexpected).toBe(0)
		expect(result.ok).toBe(true)
		expect(result.counts.controls).toBeGreaterThanOrEqual(2) -- table, virtual_list
		expect(result.counts.exportsDocumented).toBeGreaterThanOrEqual(10)
		-- every nested namespace member has a qualified reference entry (ENF-1b)
		expect(result.counts.nestedDocumented).toBe(result.counts.nestedMembers)
	end)

	it("reports a control file missing from the registry", function()
		local result = checker.check({ extraControlFiles = { "ghost_control" } })
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "ghost_control")).toBeGreaterThanOrEqual(1)
	end)

	it("reports an export missing from the API reference AND a documented ghost", function()
		local result = checker.check({ extraExports = { "newGhostThing" } })
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "newGhostThing")).toBeGreaterThanOrEqual(1)
		local ghostDoc = checker.check({ extraDocumented = { "newImaginaryApi" } })
		expect(ghostDoc.ok).toBe(false)
		expect(problemsMentioning(ghostDoc, "newImaginaryApi")).toBeGreaterThanOrEqual(1)
	end)

	-- ---- ENF-1: what the checker could NOT see before ----------------------
	-- Three holes, each of which let real drift pass: an export "documented" by
	-- a passing mention, a namespace whose members were never looked at, and a
	-- dump surface "proved" by any substring at all.

	it("reports a nested namespace member that api.md does not document QUALIFIED", function()
		local result = checker.check({
			extraNestedMembers = { { namespace = "motion", member = "ghostNestedMember" } },
		})
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "motion.ghostNestedMember")).toBeGreaterThanOrEqual(1)
	end)

	it("an allowlist entry needs a REASON — an empty one is itself a problem", function()
		local silenced = checker.check({
			extraNestedMembers = { { namespace = "motion", member = "ghostNestedMember" } },
			extraNestedAllow = { ["motion.ghostNestedMember"] = "documented in prose under the clock section" },
		})
		expect(problemsMentioning(silenced, "motion.ghostNestedMember")).toBe(0)

		local reasonless = checker.check({
			extraNestedMembers = { { namespace = "motion", member = "ghostNestedMember" } },
			extraNestedAllow = { ["motion.ghostNestedMember"] = "" },
		})
		expect(reasonless.ok).toBe(false)
		expect(problemsMentioning(reasonless, "EMPTY reason")).toBeGreaterThanOrEqual(1)
	end)

	it("the live repository's namespace members are actually WALKED (not an empty set)", function()
		local result = checker.check()
		-- motion/text/themes/tokens/adaptive/composition/replication/spatial/
		-- touchGestures/interactionTokens/valueModel — a rule that walked nothing
		-- would report nothing and look identical from the outside
		expect(result.counts.nestedMembers).toBeGreaterThanOrEqual(40)
	end)

	it("reports a dumpFunction that is not defined in the module", function()
		local result = checker.check({
			extraDumpRows = {
				{ name = "GhostBadDump", module = "src/controls/table.luau", dumpFunction = "function ghost.dump" },
			},
		})
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "GhostBadDump")).toBeGreaterThanOrEqual(1)
	end)

	it("reports a dumpFunction that is not a dump DEFINITION at all (the old substring hole)", function()
		-- 'async_image' used to pass as this row's dump surface: it is the module's
		-- own name, present in every line of it
		local result = checker.check({
			extraDumpRows = {
				{ name = "GhostSubstringDump", module = "src/controls/async_image.luau", dumpFunction = "async_image" },
			},
		})
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "GhostSubstringDump")).toBeGreaterThanOrEqual(1)
		expect(problemsMentioning(result, "not a dump definition")).toBeGreaterThanOrEqual(1)
	end)

	it("reports a row that declares neither a dumpFunction nor dump = false", function()
		local result = checker.check({
			extraDumpRows = { { name = "GhostNoDumpDecl", module = "src/controls/table.luau" } },
		})
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "GhostNoDumpDecl")).toBeGreaterThanOrEqual(1)
	end)

	it("reports dump = false with no reason, and accepts one with a reason", function()
		local reasonless = checker.check({
			extraDumpRows = { { name = "GhostMuteDump", module = "src/controls/table.luau", dump = false } },
		})
		expect(reasonless.ok).toBe(false)
		expect(problemsMentioning(reasonless, "GhostMuteDump")).toBeGreaterThanOrEqual(1)

		local declared = checker.check({
			extraDumpRows = {
				{
					name = "GhostMuteDump",
					module = "src/controls/table.luau",
					dump = false,
					reason = "stateless module",
				},
			},
		})
		expect(problemsMentioning(declared, "GhostMuteDump")).toBe(0)
	end)

	it("reports a spec file that is not registered in the runner (silent zero)", function()
		local result = checker.check({ extraSpecFiles = { "unregistered_thing.spec" } })
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "unregistered_thing")).toBeGreaterThanOrEqual(1)
	end)

	it("reports a missing extension playbook", function()
		local result = checker.check({ requiredPlaybooks = { "docs/extending/imaginary-playbook.md" } })
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "imaginary-playbook")).toBeGreaterThanOrEqual(1)
	end)

	-- ---- four-input conformance (ui_todo §0) --------------------------------
	local REAL_CASE = "keyboard Return activates the focused Button" -- exists in auto_input.spec

	it("reports a row that declares no inputProofs at all (silent omission = failure)", function()
		local result = checker.check({ extraProofRows = { { name = "GhostNoProofs", interactive = false } } })
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "GhostNoProofs")).toBeGreaterThanOrEqual(1)
	end)

	it("reports an interactive control that is mouse-only (missing an input class)", function()
		local result = checker.check({
			extraProofRows = {
				{
					name = "GhostMouseOnly",
					interactive = true,
					inputProofs = {
						pointer = { REAL_CASE },
						touch = { REAL_CASE },
						keyboard = { REAL_CASE },
						gamepad = {}, -- the mouse-only tell: no gamepad proof
					},
				},
			},
		})
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "GhostMouseOnly")).toBeGreaterThanOrEqual(1)
		expect(problemsMentioning(result, "gamepad")).toBeGreaterThanOrEqual(1)
	end)

	it("reports an interactive control that declared inputProofs = false", function()
		local result = checker.check({
			extraProofRows = { { name = "GhostFalseButInteractive", interactive = true, inputProofs = false } },
		})
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "GhostFalseButInteractive")).toBeGreaterThanOrEqual(1)
	end)

	it("reports a declared proof case that no registered spec contains (rule b)", function()
		-- built by concatenation so this literal never appears verbatim in a spec
		-- source (this file is itself a registered, searched spec)
		local absentCase = "zz-" .. "no-registered-" .. "spec-has-this-" .. "proof-case-42"
		local result = checker.check({
			extraProofRows = {
				{
					name = "GhostBadProof",
					interactive = true,
					inputProofs = {
						pointer = { REAL_CASE },
						touch = { REAL_CASE },
						keyboard = { REAL_CASE, absentCase },
						gamepad = { REAL_CASE },
					},
				},
			},
		})
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "GhostBadProof")).toBeGreaterThanOrEqual(1)
	end)

	it("the live repository proves the four-input story for every interactive control", function()
		local result = checker.check()
		expect(#unexpectedProblems(result)).toBe(0)
		expect(result.counts.interactiveControls).toBeGreaterThanOrEqual(7) -- Button, Toggle, TextField, Table, VirtualList, PopupButton, TextInput
	end)

	-- ---- PARADIGM axis: affordanceProofs (UI-PARADIGM-001/002) --------------
	-- inputProofs proves REACHABILITY; affordanceProofs proves the STRUCTURAL
	-- IDIOM per live class plus the in-flight hot-switch semantic. The checker
	-- fails a silent omission, an uncited case, a missing class, or a missing
	-- hotSwitch decision — mirroring the inputProofs enforcement pattern.
	local FULL_INPUTS = {
		pointer = { REAL_CASE },
		touch = { REAL_CASE },
		keyboard = { REAL_CASE },
		gamepad = { REAL_CASE },
	}
	local FULL_AFFORDANCE = {
		pointer = { REAL_CASE },
		touch = { REAL_CASE },
		keyboard = { REAL_CASE },
		gamepad = { REAL_CASE },
		hotSwitch = false,
	}

	it("reports an interactive control that proves inputs but is MISSING an affordance class", function()
		local aff = table.clone(FULL_AFFORDANCE)
		aff.gamepad = {} -- the paradigm tell: reachable on gamepad, but no structural idiom cited
		local result = checker.check({
			extraProofRows = {
				{ name = "GhostNoGamepadIdiom", interactive = true, inputProofs = FULL_INPUTS, affordanceProofs = aff },
			},
		})
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "GhostNoGamepadIdiom")).toBeGreaterThanOrEqual(1)
		expect(problemsMentioning(result, "gamepad")).toBeGreaterThanOrEqual(1)
	end)

	it("reports an interactive control that declares no affordanceProofs at all (silent omission)", function()
		local result = checker.check({
			extraProofRows = {
				{ name = "GhostNoAffordance", interactive = true, inputProofs = FULL_INPUTS }, -- affordanceProofs nil
			},
		})
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "GhostNoAffordance")).toBeGreaterThanOrEqual(1)
		expect(problemsMentioning(result, "affordanceProofs")).toBeGreaterThanOrEqual(1)
	end)

	it("reports an interactive control that declared affordanceProofs = false", function()
		local result = checker.check({
			extraProofRows = {
				{
					name = "GhostAffordanceFalse",
					interactive = true,
					inputProofs = FULL_INPUTS,
					affordanceProofs = false,
				},
			},
		})
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "GhostAffordanceFalse")).toBeGreaterThanOrEqual(1)
	end)

	it("reports an affordance proof case that no registered spec contains (rule b, paradigm)", function()
		local absentCase = "zz-" .. "no-registered-" .. "spec-affordance-" .. "case-99"
		local aff = table.clone(FULL_AFFORDANCE)
		aff.keyboard = { REAL_CASE, absentCase }
		local result = checker.check({
			extraProofRows = {
				{ name = "GhostBadAffordance", interactive = true, inputProofs = FULL_INPUTS, affordanceProofs = aff },
			},
		})
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "GhostBadAffordance")).toBeGreaterThanOrEqual(1)
	end)

	it("reports an interactive control whose affordanceProofs omits the hotSwitch decision", function()
		local aff = {
			pointer = { REAL_CASE },
			touch = { REAL_CASE },
			keyboard = { REAL_CASE },
			gamepad = { REAL_CASE },
			-- hotSwitch omitted: neither a list of §C cases nor an explicit false
		}
		local result = checker.check({
			extraProofRows = {
				{ name = "GhostNoHotSwitch", interactive = true, inputProofs = FULL_INPUTS, affordanceProofs = aff },
			},
		})
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "GhostNoHotSwitch")).toBeGreaterThanOrEqual(1)
		expect(problemsMentioning(result, "hotSwitch")).toBeGreaterThanOrEqual(1)
	end)

	it("the live repository proves the PARADIGM axis for every interactive control", function()
		local result = checker.check()
		expect(#unexpectedProblems(result)).toBe(0)
		expect(result.counts.affordanceControls).toBeGreaterThanOrEqual(7) -- Button, Toggle, TextField, Table, VirtualList, PopupButton, TextInput
	end)
end)

describe("extension scaffold", function()
	it("plans a complete control skeleton: source, spec, runner registration, registry entry, docs stub", function()
		local plan = scaffold.plan("control", "popup_button")
		local paths = {}
		for _, file in plan.files do
			paths[file.path] = file
		end
		expect(paths["src/controls/popup_button.luau"] ~= nil).toBeTruthy()
		expect(paths["tests/popup_button.spec.luau"] ~= nil).toBeTruthy()
		expect(plan.edits ~= nil).toBeTruthy() -- runner registration + registry append + api.md stub
		local editTargets = {}
		for _, edit in plan.edits do
			editTargets[edit.path] = true
		end
		expect(editTargets["tests/run.luau"]).toBeTruthy()
		expect(editTargets["tests/conformance/controls_registry.luau"]).toBeTruthy()
		expect(editTargets["docs/reference/api.md"]).toBeTruthy()
		-- the stamped source implements the composite-control seam
		local source = paths["src/controls/popup_button.luau"].content
		expect(string.find(source, "function popup_button.build") ~= nil).toBeTruthy()
		expect(string.find(source, "dump") ~= nil).toBeTruthy() -- dump surface stamped in
		-- the stamped source carries the four-input contribution.attach stub
		-- (ui_todo §0): the checker reads "contribution.attach" as the interactive
		-- tell, so a scaffolded control must ship its multi-input skeleton
		expect(string.find(source, "contribution.attach") ~= nil).toBeTruthy()

		-- the stamped SPEC carries a failing TODO case per input class, whose
		-- names match the inputProofs stamped into the registry row
		local spec = paths["tests/popup_button.spec.luau"].content
		local classes = { "pointer", "touch", "keyboard", "gamepad" }
		local registryRow = nil
		for _, edit in plan.edits do
			if edit.path == "tests/conformance/controls_registry.luau" then
				registryRow = edit.insert
			end
		end
		expect(registryRow ~= nil).toBeTruthy()
		expect(string.find(registryRow, "inputProofs", 1, true) ~= nil).toBeTruthy()
		for _, class in classes do
			-- each class appears as an inputProofs key in the stamped row
			expect(string.find(registryRow, class .. " = {", 1, true) ~= nil).toBeTruthy()
			-- and the stamped spec case name for that class is REFERENCED verbatim
			-- in the registry row (spec case === registry proof, by construction)
			local caseStart = string.find(spec, "PopupButton " .. class .. ":", 1, true)
			expect(caseStart ~= nil).toBeTruthy()
			local caseName = string.match(string.sub(spec, caseStart :: number), '^([^"]+)')
			expect(caseName ~= nil).toBeTruthy()
			expect(string.find(registryRow, caseName :: string, 1, true) ~= nil).toBeTruthy()
		end
	end)

	it(
		"stamps the PARADIGM axis: an affordance-declaration block, four affordance cases, a hot-switch stub, and affordanceProofs citing them",
		function()
			local plan = scaffold.plan("control", "popup_button")
			local paths = {}
			for _, file in plan.files do
				paths[file.path] = file
			end
			local spec = paths["tests/popup_button.spec.luau"].content
			local source = paths["src/controls/popup_button.luau"].content
			local registryRow = nil
			for _, edit in plan.edits do
				if edit.path == "tests/conformance/controls_registry.luau" then
					registryRow = edit.insert
				end
			end
			expect(registryRow ~= nil).toBeTruthy()

			-- (a) an affordance-declaration comment block naming the three axes is stamped
			--     into the control source (so the author chooses idioms deliberately)
			expect(string.find(source, "THREE AXES", 1, true) ~= nil).toBeTruthy()

			-- (c) the registry row carries affordanceProofs, distinct from inputProofs
			expect(string.find(registryRow, "affordanceProofs", 1, true) ~= nil).toBeTruthy()

			-- (b) a failing per-class AFFORDANCE case (distinct from the reachability
			--     cases), each cited verbatim by the affordanceProofs
			local classes = { "pointer", "touch", "keyboard", "gamepad" }
			for _, class in classes do
				local marker = "PopupButton " .. class .. " affordance:"
				local caseStart = string.find(spec, marker, 1, true)
				expect(caseStart ~= nil).toBeTruthy()
				local caseName = string.match(string.sub(spec, caseStart :: number), '^([^"]+)')
				expect(caseName ~= nil).toBeTruthy()
				expect(string.find(registryRow, caseName :: string, 1, true) ~= nil).toBeTruthy()
			end

			-- (d) a hot-switch stub case + the hotSwitch key in the row (CARRY/CANCEL)
			local hsStart = string.find(spec, "PopupButton hot-switch:", 1, true)
			expect(hsStart ~= nil).toBeTruthy()
			local hsName = string.match(string.sub(spec, hsStart :: number), '^([^"]+)')
			expect(string.find(registryRow, "hotSwitch", 1, true) ~= nil).toBeTruthy()
			expect(string.find(registryRow, hsName :: string, 1, true) ~= nil).toBeTruthy()
		end
	)

	it("plans a render-target adapter skeleton against the target contract", function()
		local plan = scaffold.plan("adapter", "surface_target")
		local paths = {}
		for _, file in plan.files do
			paths[file.path] = file
		end
		expect(paths["src/client/surface_target.luau"] ~= nil).toBeTruthy()
		local source = paths["src/client/surface_target.luau"].content
		local target_contract = require("../src/render/target_contract")
		for _, method in target_contract.REQUIRED do
			expect(`{method} stamped: {string.find(source, method) ~= nil}`).toBe(`{method} stamped: true`)
		end

		-- SEAM-25: the stamped `create` used to take THREE arguments while the
		-- contract takes five, so a scaffolded adapter could never skin a
		-- decoration slot or make a CanvasGroup and nothing said so. The
		-- creation-time pair is part of the signature.
		expect(string.find(source, "decorationHint: any?", 1, true) ~= nil).toBeTruthy()
		expect(string.find(source, "createOpts: { canvasGroup: boolean? }?", 1, true) ~= nil).toBeTruthy()
		-- and the author is pointed at the two lists `check` reports beyond REQUIRED
		expect(string.find(source, "OPTIONAL", 1, true) ~= nil).toBeTruthy()
		expect(string.find(source, "THEME", 1, true) ~= nil).toBeTruthy()
	end)

	it("stamps the adapter's conformance spec AND registers it in the runner (SEAM-25)", function()
		-- the adapter branch used to plan zero edits: no spec, nothing registered,
		-- and an unregistered spec is a silent zero (checker rule 3)
		local plan = scaffold.plan("adapter", "surface_target")
		local paths = {}
		for _, file in plan.files do
			paths[file.path] = file
		end
		expect(paths["tests/surface_target.spec.luau"] ~= nil).toBeTruthy()
		local spec = paths["tests/surface_target.spec.luau"].content
		-- it checks itself against the contract and fails on a REQUIRED gap
		expect(string.find(spec, "target_contract.check", 1, true) ~= nil).toBeTruthy()
		expect(string.find(spec, "result.missing", 1, true) ~= nil).toBeTruthy()

		local runnerEdit = nil
		for _, edit in plan.edits do
			if edit.path == "tests/run.luau" then
				runnerEdit = edit
			end
		end
		expect(runnerEdit ~= nil).toBeTruthy()
		expect((runnerEdit :: any).insert).toBe('require("./surface_target.spec")')
		-- the runner anchor is real, and the apply is idempotent against it
		local fs = require("@lune/fs")
		local runner = fs.readFile("tests/run.luau")
		local applied = scaffold.applyEdit(runner, runnerEdit :: any)
		expect(string.find(applied, 'require("./surface_target.spec")', 1, true) ~= nil).toBeTruthy()
		expect(scaffold.applyEdit(applied, runnerEdit :: any)).toBe(applied)
	end)

	it("applying the registry edit lands the row INSIDE the registry array (dry-run defect 1)", function()
		-- the popup-button dry run proved the old '^}$' anchor inserted into
		-- the export type block and broke the file; the apply must be pure and
		-- provably correct against the REAL registry source
		local fs = require("@lune/fs")
		local source = fs.readFile("tests/conformance/controls_registry.luau")
		local plan = scaffold.plan("control", "probe_widget")
		local registryEdit = nil
		for _, edit in plan.edits do
			if edit.path == "tests/conformance/controls_registry.luau" then
				registryEdit = edit
			end
		end
		expect(registryEdit ~= nil).toBeTruthy()
		local applied = scaffold.applyEdit(source, registryEdit)
		-- the row must land AFTER the registry table opens, never in the type
		local typeClose = string.find(applied, "^}$", string.find(applied, "export type Entry") :: number, false)
		local tableOpen = string.find(applied, "local registry", 1, true) :: number
		local rowAt = string.find(applied, 'name = "ProbeWidget"', 1, true) :: number
		expect(rowAt ~= nil).toBeTruthy()
		expect(rowAt > tableOpen).toBeTruthy()
		-- and before the return
		local returnAt = string.find(applied, "return registry", 1, true) :: number
		expect(rowAt < returnAt).toBeTruthy()
		-- applying twice is idempotent
		expect(scaffold.applyEdit(applied, registryEdit)).toBe(applied)
		local _ = typeClose
	end)

	--[[ THE SIX REGISTRATIONS THAT WERE NOBODY'S TO REMEMBER (2026-08-21).

		Measured, not imagined: a fresh-context agent contributed a real control
		through this scaffold with no other help, and found EVERY one of the six
		registrations below by meeting a red test — never by reading. One of them
		(the guide's capability-catalog row) reddened four documentation-gate cases
		at once, and `docs/extending/new-control.md` asked for four of the others in
		nine words ("Add it to an instrumented gallery fixture").

		These cases hold the plan to the whole list, and the case after them holds
		the ANCHORS to the live files — because a plan that names a file it cannot
		actually edit is a scaffold that fails in the author's working tree rather
		than here. ]]
	it("stamps EVERY registration a twentieth control needs, from the one declared name", function()
		local plan = scaffold.plan("control", "probe_widget")
		local files: { [string]: boolean } = {}
		for _, file in plan.files do
			files[file.path] = true
		end
		local edits: { [string]: boolean } = {}
		for _, edit in plan.edits do
			edits[edit.path] = true
		end

		-- the gallery scenario is a FILE, because standing rule 4 wants a surface a
		-- person can open, not a name in a list
		expect(`scenario stamped: {files["examples/gallery/scenarios/probe_widget.luau"] == true}`).toBe(
			"scenario stamped: true"
		)
		for _, path in
			{
				-- the six that were discovered one red test at a time
				"docs/guide/README.md",
				"tests/controls_namespace.spec.luau",
				"examples/gallery/scenarios/init.luau",
				"tests/overflow_sweep.spec.luau",
				"examples/gallery/client/demo_picker.luau",
				"tests/gallery_demo_picker.spec.luau",
				-- ...beside the ones that were already stamped
				"tests/run.luau",
				"tests/conformance/controls_registry.luau",
				"src/init.luau",
				"tests/lib/large_text_fixtures.luau",
				"docs/reference/api.md",
			}
		do
			expect(`{path} registered: {edits[path] == true}`).toBe(`{path} registered: true`)
		end

		-- and the two catalogue count pins move with it
		expect(#plan.bumps).toBe(2)
		for _, bump in plan.bumps do
			expect(bump.path).toBe("tests/gallery_demo_picker.spec.luau")
			expect(`guard names the control: {string.find(bump.guard, "probe-widget", 1, true) ~= nil}`).toBe(
				"guard names the control: true"
			)
		end
	end)

	it("every late-registration anchor is REAL: each edit applies to the shipped file, twice safely", function()
		local fs = require("@lune/fs")
		local plan = scaffold.plan("control", "probe_widget")
		local LATE = {
			["docs/guide/README.md"] = "`Controls.ProbeWidget`",
			["tests/controls_namespace.spec.luau"] = '"ProbeWidget",',
			["examples/gallery/scenarios/init.luau"] = '"probe_widget",',
			["tests/overflow_sweep.spec.luau"] = '"probe_widget",',
			["examples/gallery/client/demo_picker.luau"] = 'id = "probe-widget"',
			["tests/gallery_demo_picker.spec.luau"] = '["probe-widget"] = "ProbeWidget"',
		}
		local checked = 0
		for _, edit in plan.edits do
			local needle = LATE[edit.path]
			if needle == nil then
				continue
			end
			checked += 1
			local source = fs.readFile(edit.path)
			-- the anchor exists in the SHIPPED file (applyEdit asserts when it does not)
			local applied = scaffold.applyEdit(source, edit)
			expect(`{edit.path} landed: {string.find(applied, needle, 1, true) ~= nil}`).toBe(
				`{edit.path} landed: true`
			)
			expect(`{edit.path} idempotent: {scaffold.applyEdit(applied, edit) == applied}`).toBe(
				`{edit.path} idempotent: true`
			)
		end
		expect(checked).toBe(6)
	end)

	it("the scenario, the demo, and the pinned root all name the SAME surface", function()
		-- three files, one name. A demo whose module does not exist fails to mount
		-- on the device in front of whoever is holding it; a demo with no pinned
		-- root is advanced through and never actually looked at.
		local plan = scaffold.plan("control", "probe_widget")
		local scenario = nil
		for _, file in plan.files do
			if file.path == "examples/gallery/scenarios/probe_widget.luau" then
				scenario = file.content
			end
		end
		expect(scenario ~= nil).toBeTruthy()
		-- the scenario's ROOT SCREEN is the control's display name...
		expect(`root screen: {string.find(scenario :: string, 'id = "ProbeWidget"', 1, true) ~= nil}`).toBe(
			"root screen: true"
		)
		-- ...and it mounts the control through its ONE public spelling
		expect(`public spelling: {string.find(scenario :: string, "ctx.Facet.Controls.ProbeWidget(", 1, true) ~= nil}`).toBe(
			"public spelling: true"
		)

		local demoRow, rootRow, catalogRow = nil, nil, nil
		for _, edit in plan.edits do
			if edit.path == "examples/gallery/client/demo_picker.luau" then
				demoRow = edit.insert
			elseif edit.path == "tests/gallery_demo_picker.spec.luau" then
				rootRow = edit.insert
			elseif edit.path == "docs/guide/README.md" then
				catalogRow = edit.insert
			end
		end
		expect(`demo module: {string.find(demoRow :: string, 'module = "probe_widget"', 1, true) ~= nil}`).toBe(
			"demo module: true"
		)
		expect(`root pinned: {string.find(rootRow :: string, '["probe-widget"] = "ProbeWidget"', 1, true) ~= nil}`).toBe(
			"root pinned: true"
		)

		-- THE BLURB CEILING IS A DEVICE FACT, not a style preference: 82 characters
		-- is the longest blurb a device pass has ever read on a 360px phone
		-- (tests/gallery_demo_picker.spec). A scaffold that stamps a longer one
		-- hands its author a red test it wrote itself.
		local blurb = string.match(demoRow :: string, 'blurb = "([^"]+)"')
		expect(blurb ~= nil).toBeTruthy()
		expect(`blurb {utf8.len(blurb :: string)} chars, over 82? {(utf8.len(blurb :: string) :: number) > 82}`).toBe(
			`blurb {utf8.len(blurb :: string)} chars, over 82? false`
		)

		-- the catalog row's api.md link must land on the heading the api.md stub
		-- writes, or `check_docs` reports a guide link to nothing
		expect(
			`catalog anchor: {string.find(catalogRow :: string, "(../reference/api.md#controlsprobewidget)", 1, true) ~= nil}`
		).toBe("catalog anchor: true")
	end)

	--[[ THE ONE EDIT SHAPE A PLAIN INSERT CANNOT EXPRESS. Two spec files pin
		catalogue SIZES as literals, deliberately — a ratchet is how this repository
		makes a catalogue change a decision rather than an accident. A scaffold run
		IS that decision, so the tool moves the number; the ratchet keeps biting for
		every hand edit that is not a scaffold run. ]]
	it("applyBump moves every occurrence of a count pin, exactly once", function()
		local source = table.concat({
			"expect(#demos).toBe(36)",
			"-- prose that says toBe( without a number",
			"expect(fixtures).toBe(29)",
			"expect(fixtures).toBe(29)",
			'["nested-tree"] = "NestedCompositing",',
		}, "\n")
		local bump = {
			path = "x",
			prefix = "expect(fixtures).toBe(",
			suffix = ")",
			guard = '["probe-widget"] = "ProbeWidget",',
		}
		local once = scaffold.applyBump(source, bump)
		expect(`both moved: {select(2, string.gsub(once, "expect%(fixtures%)%.toBe%(30%)", ""))}`).toBe("both moved: 2")
		-- the OTHER pin is untouched: a bump is about one pin, not about numbers
		expect(`other pin held: {string.find(once, "expect(#demos).toBe(36)", 1, true) ~= nil}`).toBe(
			"other pin held: true"
		)

		-- GUARDED, because a bump has no idempotence of its own. The guard is a row
		-- the same scaffold run inserts into the same file, which is why the CLI
		-- applies every bump BEFORE any edit.
		local guarded = once .. '\n["probe-widget"] = "ProbeWidget",'
		expect(scaffold.applyBump(guarded, bump)).toBe(guarded)

		-- and a pin that moved or was renamed is an ERROR, not a silent no-op: a
		-- count pin that quietly moved nowhere leaves a red test behind a scaffold
		-- that reported success
		expect(function()
			scaffold.applyBump("nothing to see here", bump)
		end).toThrow()
	end)

	--[[ THE TOOL MUST NOT HAND ITS AUTHOR A FAILURE IT WROTE ITSELF.

		Two of these arrived on the first end-to-end run of the extended scaffold
		(2026-08-21) and both were pre-existing: a stray blank line and a stamped
		`it(` line 102 characters wide, so a freshly scaffolded control failed
		`stylua --check` before its author had typed anything — the same shape as
		MAINT-3's `textSize`, which used to fail this scaffold's own theme-drift
		pass condition, and as the LT8-CTL truncation the stamped `disclose = true`
		now prevents.

		The formatter itself is not runnable from here, so the guard is the RULE
		the formatter enforces: the default 120-column budget, measured with a tab
		counted as the default indent width of four. A LONG control name is used on
		purpose, because the overflow is a function of the name and a short one
		proves nothing. ]]
	it("the stamped output is formatter-clean: no line over 120 columns, no double blank line", function()
		local plan = scaffold.plan("control", "extremely_long_probe_name")
		local INDENT_WIDTH = 4
		local COLUMN_WIDTH = 120
		local problems: { string } = {}
		local checked = 0
		for _, file in plan.files do
			checked += 1
			local blanks = 0
			for index, line in string.split(file.content, "\n") do
				local width = #line + (select(2, string.gsub(line, "\t", "")) * (INDENT_WIDTH - 1))
				if width > COLUMN_WIDTH then
					table.insert(
						problems,
						`{file.path}:{index} is {width} columns wide (stylua wraps past {COLUMN_WIDTH})`
					)
				end
				blanks = if line == "" then blanks + 1 else 0
				if blanks == 2 then
					table.insert(
						problems,
						`{file.path}:{index} is the second blank line in a row (stylua collapses it)`
					)
				end
			end
		end
		expect(checked).toBe(3)
		expect(table.concat(problems, "; ")).toBe("")
	end)

	it("rejects unknown kinds and unsafe names", function()
		expect(function()
			scaffold.plan("wizard", "x")
		end).toThrow()
		expect(function()
			scaffold.plan("control", "Bad Name/../x")
		end).toThrow()
	end)
end)
