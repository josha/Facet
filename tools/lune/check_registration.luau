--!strict
-- Registration checker (design §17 Phase 4 agentic maintainability;
-- UI-AGENT-001). Fails the gate when the repository's extension seams have
-- drifted from their registrations:
--   1. every composite control under src/controls/ has a complete row in
--      tests/conformance/controls_registry.luau (spec, conformance, docs
--      anchor, dump surface, public export) and every row's artifacts exist;
--   2. the API reference (docs/reference/api.md) covers every public export
--      of src/init.luau and every UI.* constructor — and documents nothing
--      that does not exist (drift in either direction fails);
--   3. every tests/*.spec.luau is registered in tests/run.luau (a green
--      suite with an unregistered spec is a silent zero);
--   4. every extension playbook exists under docs/extending/;
--   5. FOUR-INPUT CONFORMANCE (ui_todo §0): every control class has an
--      explicit inputProofs declaration; every declared proof case name
--      exists verbatim in a spec tests/run.luau registers; and every
--      INTERACTIVE control (a focusable leaf / a composite that attaches an
--      input contribution) PROVES all four input classes — pointer, touch,
--      keyboard, gamepad. A mouse-only control cannot pass. Named per-pair
--      gaps (PROOF_GAPS) ship the rule enforcing while an absent device-true
--      case is explicit rather than silently weakened.
--   6. PARADIGM-AXIS CONFORMANCE (UI-PARADIGM-001/002; the affordance matrix):
--      every control class has an explicit affordanceProofs declaration; every
--      cited case exists verbatim in a registered spec; every INTERACTIVE
--      control proves the STRUCTURAL IDIOM for all four live classes (distinct
--      from inputProofs' reachability) AND declares its hotSwitch semantic —
--      a list of §C in-flight-transition cases, or explicit `false` when it
--      owns no in-flight state. A silent omission, an uncited case, a missing
--      class, or a missing hotSwitch decision fails. Named per-class gaps
--      (AFFORDANCE_GAPS) ship the rule enforcing while an absence is explicit.
-- check(opts?) -> { ok, problems, counts }; opts injects synthetic drift for
-- the checker's own tests. CLI: tools/lune/check_registration_cli.luau.

local fs = require("@lune/fs")

local contract = require("../../src/controls/contract")

local check_registration = {}

local REQUIRED_PLAYBOOKS = {
	"docs/extending/new-control.md",
	"docs/extending/new-engine-feature.md",
	"docs/extending/new-platform-mode.md",
	"docs/extending/new-render-target.md",
}

-- the four input classes every interactive control must prove (ui_todo §0)
local INPUT_CLASSES = { "pointer", "touch", "keyboard", "gamepad" }

-- Named per-control×class proof gaps: a control/class pair for which NO
-- device-true spec case exists today. Each is a TEST-COVERAGE finding, NOT a
-- framework gap — the missing class's activation runs the SAME code path as a
-- proven sibling class (the shared Activated dispatch). Listed here so the
-- four-input rule ships ENFORCING while the absence is explicit and named,
-- never silently weakened. Remove a pair the moment its device-true case lands.
-- Currently EMPTY: every interactive control proves all four input classes with
-- a device-true case (the last four — Button×touch, Toggle×touch, Toggle×gamepad,
-- PopupButton×touch — landed in auto_input.spec.luau / popup_button.spec.luau).
local PROOF_GAPS: { [string]: { [string]: string } } = {}

-- Named per-control×class PARADIGM (affordance) gaps: a control/class pair for
-- which no spec case proves the class's STRUCTURAL IDIOM today. Mirrors
-- PROOF_GAPS: it lets the paradigm-axis rule ship ENFORCING while an absence is
-- explicit and named, never silently weakened. Currently EMPTY — the affordance
-- matrix Amendments record every per-class GAP as CLOSED, so every interactive
-- control cites an existing green spec case for all four classes.
local AFFORDANCE_GAPS: { [string]: { [string]: string } } = {}

-- ScrollView's only contract action ("Scroll") is a pointer-wheel / touch-pan
-- GESTURE, not a focus/Activate surface (focusRole="none"). §0's four-input bar
-- is about FOCUSABLE surfaces; ScrollView is deliberately non-interactive here.
local INTERACTIVE_ACTION_EXCEPT: { [string]: boolean } = { ScrollView = true }

type Opts = {
	extraControlFiles: { string }?,
	extraExports: { string }?,
	extraDocumented: { string }?,
	extraSpecFiles: { string }?,
	requiredPlaybooks: { string }?,
	-- synthetic four-input rows for the checker's own tests (drift injection):
	-- each is { name, interactive: boolean, inputProofs }
	extraProofRows: { any }?,
}

-- a leaf primitive is interactive when its contract makes it a focus/Activate
-- surface (focusable, or a semantic action) — minus the gesture-only exceptions
local function leafInteractive(className: string): boolean
	local c = contract.forClass(className)
	if c == nil then
		return false
	end
	if INTERACTIVE_ACTION_EXCEPT[className] then
		return false
	end
	return c.focusRole == "focusable" or #c.actions > 0
end

function check_registration.check(opts: Opts?)
	local options: Opts = opts or {}
	local problems: { string } = {}
	local function problem(message: string)
		table.insert(problems, message)
	end

	-- ---- 1. control registry ------------------------------------------
	local registry = require("../../tests/conformance/controls_registry") :: { any }
	local registryByModule: { [string]: any } = {}
	for _, entry in registry do
		if entry.module ~= nil then
			registryByModule[entry.module] = entry
		end
	end

	local controlFiles: { string } = {}
	for _, name in fs.readDir("src/controls") do
		if string.match(name, "%.luau$") and name ~= "contract.luau" then
			table.insert(controlFiles, "src/controls/" .. name)
		end
	end
	for _, ghost in options.extraControlFiles or {} do
		table.insert(controlFiles, "src/controls/" .. ghost .. ".luau")
	end

	local apiMd = fs.readFile("docs/reference/api.md")
	local initSource = fs.readFile("src/init.luau")

	local matchedControls = 0
	for _, file in controlFiles do
		local entry = registryByModule[file]
		if entry == nil then
			problem(
				`control {file} has no row in tests/conformance/controls_registry.luau (scaffold appends one; add it)`
			)
			continue
		end
		matchedControls += 1
		for _, artifact in { entry.module, entry.spec, entry.conformance } do
			if not fs.isFile(artifact) then
				problem(`control {entry.name}: registered artifact missing on disk: {artifact}`)
			end
		end
		if fs.isFile(entry.module) then
			local source = fs.readFile(entry.module)
			if string.find(source, entry.dumpMarker, 1, true) == nil then
				problem(
					`control {entry.name}: dump surface marker '{entry.dumpMarker}' not found in {entry.module} (§10.2 deterministic dump form)`
				)
			end
		end
		if string.find(initSource, entry.export, 1, true) == nil then
			problem(`control {entry.name}: export '{entry.export}' not found in src/init.luau`)
		end
		if string.find(apiMd, "`" .. entry.docsAnchor .. "`", 1, true) == nil then
			problem(`control {entry.name}: docs anchor \`{entry.docsAnchor}\` not found in docs/reference/api.md`)
		end
	end

	-- ---- 2. API reference drift ---------------------------------------
	local exports: { string } = {}
	-- top-level LuauUI table keys
	for key in string.gmatch(initSource, "\n\t(%w+) = ") do
		table.insert(exports, key)
	end
	-- UI.* constructors
	local blueprintSource = fs.readFile("src/blueprint.luau")
	for key in string.gmatch(blueprintSource, "function blueprint%.(%w+)") do
		table.insert(exports, key)
	end
	for _, ghost in options.extraExports or {} do
		table.insert(exports, ghost)
	end

	local documented: { [string]: boolean } = {}
	for line in string.gmatch(apiMd, "[^\n]+") do
		if string.sub(line, 1, 4) == "### " then
			for token in string.gmatch(line, "`([%w_]+)`") do
				documented[token] = true
			end
		end
	end

	local exportSet: { [string]: boolean } = {}
	local exportsDocumented = 0
	for _, export in exports do
		exportSet[export] = true
		if documented[export] then
			exportsDocumented += 1
		elseif string.find(apiMd, "`" .. export .. "`", 1, true) == nil then
			problem(`public export '{export}' is not documented in docs/reference/api.md`)
		else
			exportsDocumented += 1
		end
	end
	for _, ghost in options.extraDocumented or {} do
		documented[ghost] = true
	end
	for token in documented do
		if not exportSet[token] then
			problem(`docs/reference/api.md documents '{token}' which is not a public export (stale reference?)`)
		end
	end

	-- ---- 3. spec registration (silent-zero protection) ----------------
	local runnerSource = fs.readFile("tests/run.luau")
	local specFiles: { string } = {}
	for _, name in fs.readDir("tests") do
		if string.match(name, "%.spec%.luau$") then
			table.insert(specFiles, (string.gsub(name, "%.luau$", "")))
		end
	end
	for _, ghost in options.extraSpecFiles or {} do
		table.insert(specFiles, ghost)
	end
	for _, spec in specFiles do
		if string.find(runnerSource, `require("./{spec}")`, 1, true) == nil then
			problem(
				`tests/{spec}.luau exists but is not registered in tests/run.luau (a green suite with an unregistered spec is a silent zero)`
			)
		end
	end

	-- ---- 4. playbooks --------------------------------------------------
	local playbooks = table.clone(REQUIRED_PLAYBOOKS)
	for _, extra in options.requiredPlaybooks or {} do
		table.insert(playbooks, extra)
	end
	for _, playbook in playbooks do
		if not fs.isFile(playbook) then
			problem(`extension playbook missing: {playbook}`)
		end
	end

	-- ---- 5. four-input conformance (ui_todo §0) -----------------------
	-- the sources of every spec tests/run.luau registers (rule b searches them)
	local registeredSpecSources: { string } = {}
	for path in string.gmatch(runnerSource, 'require%("%./([%w_/]+%.spec)"%)') do
		local file = "tests/" .. path .. ".luau"
		if fs.isFile(file) then
			table.insert(registeredSpecSources, fs.readFile(file))
		end
	end
	local function caseExists(caseName: string): boolean
		for _, src in registeredSpecSources do
			if string.find(src, caseName, 1, true) ~= nil then
				return true
			end
		end
		return false
	end

	-- every leaf class declared in the contract needs a registry row: a new
	-- focusable control cannot slip in mouse-only by simply not being listed
	local leafRowNames: { [string]: boolean } = {}
	for _, entry in registry do
		if entry.kind == "leaf" then
			leafRowNames[entry.name] = true
		end
	end
	for className in contract.all() do
		if not leafRowNames[className] then
			problem(
				`contract control {className} (src/controls/contract.luau) has no leaf row in the registry — declare its inputProofs (or 'inputProofs = false' if non-interactive; silent omission is a failure, ui_todo §0)`
			)
		end
	end

	-- derive interactivity for every real row, then fold in synthetic rows
	local proofRows: { any } = {}
	for _, entry in registry do
		local isInteractive: boolean
		if entry.kind == "leaf" then
			isInteractive = leafInteractive(entry.name)
		else -- composite: interactive iff it attaches an input contribution
			isInteractive = false
			if entry.module ~= nil and fs.isFile(entry.module) then
				isInteractive = string.find(fs.readFile(entry.module), "contribution.attach", 1, true) ~= nil
			end
		end
		table.insert(proofRows, {
			name = entry.name,
			interactive = isInteractive,
			inputProofs = entry.inputProofs,
			affordanceProofs = entry.affordanceProofs,
		})
	end
	for _, ghost in options.extraProofRows or {} do
		table.insert(proofRows, ghost)
	end

	local interactiveControls = 0
	local affordanceControls = 0
	for _, row in proofRows do
		local proofs = row.inputProofs
		-- rule (a): the declaration must be present (table or explicit false)
		if proofs == nil then
			problem(
				`control {row.name}: no inputProofs declared — declare the four-input proofs, or 'inputProofs = false' for a non-interactive control (silent omission is a failure, ui_todo §0)`
			)
			continue
		end
		if proofs == false then
			if row.interactive then
				problem(
					`control {row.name}: inputProofs = false but the control is INTERACTIVE (focusable leaf / attaches an input contribution) — it must PROVE pointer + touch + keyboard + gamepad (ui_todo §0)`
				)
			end
			continue
		end
		-- proofs is the InputProofs table
		local proofTable = proofs :: any
		if row.interactive then
			interactiveControls += 1
		end
		-- rule (b): every declared proof case must exist in a registered spec
		for _, class in INPUT_CLASSES do
			for _, caseName in (proofTable[class] or {}) do
				if not caseExists(caseName) then
					problem(
						`control {row.name}: {class} input proof '{caseName}' is not found verbatim in any spec that tests/run.luau registers (rule b)`
					)
				end
			end
		end
		-- rule (c): an interactive control must prove ALL FOUR input classes
		if row.interactive then
			local gaps = PROOF_GAPS[row.name] or {}
			for _, class in INPUT_CLASSES do
				local list = proofTable[class]
				if (list == nil or #list == 0) and gaps[class] == nil then
					problem(
						`control {row.name}: no {class} input proof (ui_todo §0 — a control cannot pass conformance mouse-only). Cite a device-true {class} spec case, or record the pair as a named gap in check_registration's PROOF_GAPS.`
					)
				end
			end
		end
	end

	-- ---- 6. paradigm-axis conformance (UI-PARADIGM-001/002) -----------------
	-- The STRUCTURAL-IDIOM axis, distinct from inputProofs' reachability. Same
	-- enforcement shape: a declaration is mandatory (table or explicit false),
	-- every cited case must exist in a registered spec, and an interactive
	-- control must prove all four classes AND declare its hotSwitch semantic.
	for _, row in proofRows do
		local aff = row.affordanceProofs
		-- rule (a): the declaration must be present (table or explicit false)
		if aff == nil then
			problem(
				`control {row.name}: no affordanceProofs declared — declare the paradigm-axis proofs per live class (pointer/touch/keyboard/gamepad) plus a hotSwitch decision, or 'affordanceProofs = false' for a non-interactive control (silent omission is a failure, UI-PARADIGM-001)`
			)
			continue
		end
		if aff == false then
			if row.interactive then
				problem(
					`control {row.name}: affordanceProofs = false but the control is INTERACTIVE — it must PROVE the structural idiom for pointer + touch + keyboard + gamepad and declare its hotSwitch semantic (UI-PARADIGM-001/002)`
				)
			end
			continue
		end
		local affTable = aff :: any
		if row.interactive then
			affordanceControls += 1
		end
		-- rule (b): every cited case (per class + hotSwitch) must exist verbatim
		for _, class in INPUT_CLASSES do
			for _, caseName in (affTable[class] or {}) do
				if not caseExists(caseName) then
					problem(
						`control {row.name}: {class} affordance proof '{caseName}' is not found verbatim in any spec that tests/run.luau registers (rule b, paradigm)`
					)
				end
			end
		end
		if type(affTable.hotSwitch) == "table" then
			for _, caseName in affTable.hotSwitch do
				if not caseExists(caseName) then
					problem(
						`control {row.name}: hotSwitch affordance proof '{caseName}' is not found verbatim in any spec that tests/run.luau registers (rule b, paradigm)`
					)
				end
			end
		end
		-- rule (c): an interactive control proves all four class idioms and
		-- declares its in-flight hot-switch semantic
		if row.interactive then
			local gaps = AFFORDANCE_GAPS[row.name] or {}
			for _, class in INPUT_CLASSES do
				local list = affTable[class]
				if (list == nil or #list == 0) and gaps[class] == nil then
					problem(
						`control {row.name}: no {class} AFFORDANCE proof (UI-PARADIGM-001 — reachable is not enough; cite the spec case proving this class's structural idiom, or record the pair as a named gap in check_registration's AFFORDANCE_GAPS).`
					)
				end
			end
			-- hotSwitch must be an explicit decision: a list of §C cases, or false
			if affTable.hotSwitch == nil then
				problem(
					`control {row.name}: affordanceProofs.hotSwitch not declared — cite the §C in-flight transition cases the control owns, or 'hotSwitch = false' when it holds no in-flight state (UI-PARADIGM-002)`
				)
			end
		end
	end

	return {
		ok = #problems == 0,
		problems = problems,
		counts = {
			controls = matchedControls,
			exportsDocumented = exportsDocumented,
			specs = #specFiles,
			interactiveControls = interactiveControls,
			affordanceControls = affordanceControls,
		},
	}
end

return check_registration
