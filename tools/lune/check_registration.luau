--!strict
-- Registration checker (design §17 Phase 4 agentic maintainability;
-- UI-AGENT-001). Fails the gate when the repository's extension seams have
-- drifted from their registrations:
--   1. every composite control under src/controls/ has a complete row in
--      tests/conformance/controls_registry.luau (spec, conformance, docs
--      anchor, dump surface, public export) and every row's artifacts exist;
--   2. the API reference (docs/reference/api.md) covers every public export
--      of src/init.luau and every UI.* constructor UNDER ITS OWN `###`
--      HEADING (a mention in prose or a code sample is not a reference
--      entry), covers every PUBLIC MEMBER of every namespace export
--      (motion, text, themes, …) written QUALIFIED as `<ns>.<member>`, and
--      documents nothing that does not exist (drift in either direction
--      fails);
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

local contract = require("../../src/class_contract")

local check_registration = {}

--[[ NESTED NAMESPACE COVERAGE (ENF-1), DERIVED FROM THE LIVE TREE (ARCH-7).

	A top-level export like `motion` is one token and a whole API underneath, so
	a bare `documented["motion"]` said nothing about `motion.newValueReveal`. The
	checker has always read the LIVE table rather than parsing a literal — but
	WHICH tables to walk was a hand list of eleven names, and the hand list is the
	hole: `UI` was not on it (so `UI.schema`'s fifteen members were invisible, and
	api.md asserted it had eleven while the live table had fifteen), nor were
	`pathShapes`, `contribution` or `renderer`. A checker that exists to catch
	drift cannot itself be a list somebody has to remember to extend.

	THE RULE, and why it stops where it does. Every top-level export whose value
	is a TABLE is a namespace: that is what a namespace IS here, and no judgement
	is involved. Below the top level the walk descends only into a table that
	HOLDS A FUNCTION — `UI.schema` is an API and is walked; `renderer.EMITTED_PROPS`
	is a data set whose keys are prop names already governed by the prop-parity
	checker, and walking it would demand an api.md heading per engine property.
	"Holds a function" is the mechanical form of "is a surface, not a value", and
	it is checked rather than declared.
]]
local NESTED_WALK_DEPTH = 3

local function holdsFunction(value: { [string]: any }): boolean
	for _, member in value do
		if type(member) == "function" then
			return true
		end
	end
	return false
end

-- Members that api.md documents in PROSE rather than as `<namespace>.<member>`.
-- EVERY entry needs a reason — an allowlist without one is just a hole. Keyed
-- "<namespace>.<member>". Deliberately EMPTY: nothing on the current surface
-- qualifies (the members the checker reports today are undocumented outright,
-- not documented differently), and an entry added to silence a report rather
-- than to record a fact is the failure this rule exists to prevent.
local NESTED_DOC_ALLOW: { [string]: string } = {}

local REQUIRED_PLAYBOOKS = {
	"docs/extending/new-control.md",
	-- MAINT-5: the primitive path had no playbook at all — `new-control.md`
	-- deferred it to `new-engine-feature.md`, which only covers adding a property
	-- or a modifier to a class that already exists
	"docs/extending/new-primitive.md",
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

--[[ COMPOSITES WHOSE CONTRIBUTION CARRIES NO VERB (2026-08-16).

	"Attaches an input contribution" is the proxy this checker uses for "a
	composite is interactive", and it was exactly right for every control that
	had ever attached one. But the bundle also carries two seams that are pure
	INTAKE — `syncGeometry` (the surface's solved rects, broadcast on the arrange
	cadence) and `bindMotion` (the presenter's own motion clock) — and a
	composite that declares only those advertises no verb on any input class and
	mounts nothing focusable. The four-input bar then has nothing to be about:
	there is no pointer story, no Return, no ButtonA, because there is no
	surface to press.

	Same shape as INTERACTIVE_ACTION_EXCEPT above and as check_theme_drift's
	ALLOWLIST: an explicit, reviewable row carrying its reason, never a silent
	weakening. And the exemption is GUARDED — a listed module whose source
	mentions any verb-bearing bundle field loses it immediately (see
	VERB_BEARING_FIELDS below), so a control that later grows a handler cannot
	keep an exemption it has stopped deserving. ]]
local CONTRIBUTION_INTAKE_ONLY: { [string]: string } = {
	SelectionIndicator = "its bundle is syncGeometry + bindMotion only. It mounts an Anchor holding a Box, "
		.. "neither of which is in focus_map.FOCUSABLE, and it is declared FIRST inside its ZStack so it paints "
		.. "BEHIND the strip it decorates and can never take a tap from it. What it owes instead of four input "
		.. "proofs is a proof that it stays out of the way, which tests/selection_indicator.spec.luau carries: "
		.. "'the indicator is never a focus stop: wrapping a strip leaves its document order identical'",
}

-- every input-contribution field that makes a control INTERACTIVE. The two
-- deliberately absent (`syncGeometry`, `bindMotion`) are the intake seams above.
local VERB_BEARING_FIELDS = {
	"focusGroups",
	"handleActivate",
	"navigateIntercept",
	"focusMoved",
	"keepVisibleOffset",
	"bindActionSystem",
	"bindController",
	"bindFocusGraph",
	"bindPresent",
	"adjustTargets",
	"handleAdjust",
	"adjustAxis",
	"handleTraverse",
	"handleCancel",
	"outsideDismiss",
	"transientScope",
}

type Opts = {
	extraControlFiles: { string }?,
	extraExports: { string }?,
	extraDocumented: { string }?,
	extraSpecFiles: { string }?,
	requiredPlaybooks: { string }?,
	-- synthetic four-input rows for the checker's own tests (drift injection):
	-- each is { name, interactive: boolean, inputProofs }
	extraProofRows: { any }?,
	-- synthetic nested namespace members: { { namespace, member } }
	extraNestedMembers: { any }?,
	-- synthetic allowlist entries, merged over NESTED_DOC_ALLOW
	extraNestedAllow: { [string]: string }?,
	-- synthetic dump-surface rows: { { name, module, dumpFunction?, dump?, reason? } }
	extraDumpRows: { any }?,
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
	local liveFacet = require("../../src") :: any
	local initSource = fs.readFile("src/init.luau")

	-- ---- dump surface (ENF-1c) ----------------------------------------
	-- `dumpMarker` was a free substring searched in the module source, so a row
	-- could "prove" its dump surface with the module's own name ("async_image")
	-- or with an unrelated constructor ("function value_model.new") and pass. The
	-- rule is now binary and legible: either the row CITES THE DUMP FUNCTION —
	-- exact text `function <x>.dump` / `function dump`, which must exist in the
	-- source as a definition — or it declares `dump = false` with a `reason`
	-- saying why this module has none. Silence is not an option either way.
	local function checkDumpSurface(entry: any)
		if entry.dump == false then
			if type(entry.reason) ~= "string" or #entry.reason == 0 then
				problem(
					`control {entry.name}: dump = false needs a 'reason' string saying why this module has no dump surface (§10.2)`
				)
			end
			return
		end
		local cited = entry.dumpFunction
		if type(cited) ~= "string" then
			problem(
				`control {entry.name}: no dump surface declared — cite the definition as dumpFunction = "function <x>.dump", or declare dump = false with a reason (§10.2 deterministic dump form)`
			)
			return
		end
		if string.match(cited, "^function [%w_%.]*dump$") == nil then
			problem(
				`control {entry.name}: dumpFunction '{cited}' is not a dump definition — it must read exactly 'function <x>.dump' (a free substring proves nothing; that is how 'async_image' passed as a dump surface)`
			)
			return
		end
		if entry.module == nil or not fs.isFile(entry.module) then
			return -- the missing-artifact problem is reported by the caller
		end
		local source = fs.readFile(entry.module)
		if string.find(source, cited .. "(", 1, true) == nil then
			problem(
				`control {entry.name}: dumpFunction '{cited}' is not defined in {entry.module} (§10.2 deterministic dump form)`
			)
		end
	end

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
		checkDumpSurface(entry)
		--[[ RESOLVED ON THE LIVE TABLE, NOT SEARCHED FOR IN THE SOURCE (ADR-0037).
			A substring find in `src/init.luau` says a control is exported when the
			name merely appears anywhere in the file — a comment, a deprecation row, a
			require. It also cannot express a namespaced export at all, and after
			ADR-0037 the canonical route to every composite IS namespaced
			(`Controls.Table`). A dotted lookup on the required table answers the
			question the field actually asks: is this reachable from `Facet`? ]]
		local resolved: any = liveFacet
		for segment in string.gmatch(entry.export, "[^.]+") do
			resolved = if type(resolved) == "table" then resolved[segment] else nil
		end
		if resolved == nil then
			problem(`control {entry.name}: export '{entry.export}' does not resolve on the Facet table`)
		end
		if string.find(apiMd, "`" .. entry.docsAnchor .. "`", 1, true) == nil then
			problem(`control {entry.name}: docs anchor \`{entry.docsAnchor}\` not found in docs/reference/api.md`)
		end
	end
	for _, ghost in options.extraDumpRows or {} do
		checkDumpSurface(ghost)
	end

	-- ---- 2. API reference drift ---------------------------------------
	local exports: { string } = {}
	--[[ TOP-LEVEL KEYS FROM THE LIVE TABLE, NOT FROM THE SOURCE TEXT (ADR-0037).
		This used to scrape `\n\t(%w+) = ` out of `src/init.luau`, which is every
		one-tab `word = ` line in the file and not only the ones inside the `Facet`
		literal. The moment `Facet.Controls` landed as a module-level table, its
		nineteen entries were reported as undocumented TOP-LEVEL exports — a
		checker's own heuristic manufacturing nineteen false failures. The live
		table is the thing the rule is about, it is already required below for the
		nested walk, and it cannot be fooled by indentation. ]]
	local Facet = liveFacet
	for key in Facet do
		if type(key) == "string" then
			table.insert(exports, key)
		end
	end
	table.sort(exports)
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

	-- (a) A HEADING, not a mention. A bare `` `newThing` `` anywhere in api.md —
	-- inside a code sample, a table cell, a sentence about something else —
	-- used to count as coverage, so an export could be "documented" by an
	-- example that happened to call it. The reference documents a public export
	-- under its own `### \`<name>\`` heading or it does not document it.
	local exportSet: { [string]: boolean } = {}
	local exportsDocumented = 0
	for _, export in exports do
		exportSet[export] = true
		if documented[export] then
			exportsDocumented += 1
		else
			problem(
				`public export '{export}' has no \`### \`{export}\`\` heading in docs/reference/api.md (a mention in prose or a code sample is not a reference entry)`
			)
		end
	end
	for _, ghost in options.extraDocumented or {} do
		documented[ghost] = true
	end

	-- ---- 2b. NESTED namespace coverage (ENF-1b) ------------------------
	-- `motion`, `text`, `tokens`, … are single tokens at the top level and whole
	-- APIs underneath. The live table is the source of truth: require src and
	-- walk each namespace, so a member added tomorrow is covered without anyone
	-- updating a list. A member counts as documented when api.md writes it
	-- QUALIFIED — `` `<ns>.<member>` `` (optionally through `Facet.`) — or gives
	-- it its own heading. A bare mention of the short name does not count, for
	-- the same reason (a) does not: `resolve` is four different functions.
	local allow: { [string]: string } = table.clone(NESTED_DOC_ALLOW)
	for key, reason in options.extraNestedAllow or {} do
		allow[key] = reason
	end
	-- a qualified mention, with a right-hand boundary so `tokens.contrast` does
	-- not get credit from `tokens.contrastRatio`
	local function mentionsQualified(qualified: string): boolean
		for _, prefix in { "`" .. qualified, "`Facet." .. qualified } do
			local from = 1
			while true do
				local _, stop = string.find(apiMd, prefix, from, true)
				if stop == nil then
					break
				end
				if string.match(string.sub(apiMd, stop + 1, stop + 1), "[%w_]") == nil then
					return true
				end
				from = stop + 1
			end
		end
		return false
	end

	local nestedMembers: { any } = {}
	local function walkNamespace(prefix: string, tbl: { [string]: any }, depth: number)
		for key, value in tbl do
			if type(key) ~= "string" or string.sub(key, 1, 1) == "_" then
				continue
			end
			local qualified = if prefix == "" then key else `{prefix}.{key}`
			if prefix ~= "" then
				table.insert(nestedMembers, { namespace = prefix, member = key })
			end
			if depth > 0 and type(value) == "table" and (prefix == "" or holdsFunction(value)) then
				walkNamespace(qualified, value, depth - 1)
			end
		end
	end
	walkNamespace("", Facet, NESTED_WALK_DEPTH)
	assert(#nestedMembers > 0, "check_registration: the namespace walk found nothing — the export tree moved")
	for _, ghost in options.extraNestedMembers or {} do
		table.insert(nestedMembers, ghost)
	end

	-- a nested member's own heading is a legitimate reference entry, so it must
	-- not then be reported as a stale token by the reverse check below
	local nestedNames: { [string]: boolean } = {}
	for _, row in nestedMembers do
		nestedNames[row.member] = true
	end

	local nestedDocumented = 0
	for _, row in nestedMembers do
		local qualified = `{row.namespace}.{row.member}`
		local reason = allow[qualified]
		if reason ~= nil then
			if #reason == 0 then
				problem(
					`nested member '{qualified}' is allowlisted in check_registration with an EMPTY reason — every allowlist entry states why the reference documents it in prose instead`
				)
			else
				nestedDocumented += 1
			end
			continue
		end
		if mentionsQualified(qualified) or documented[row.member] then
			nestedDocumented += 1
		else
			problem(
				`nested public member '{qualified}' is not documented in docs/reference/api.md — write it QUALIFIED (\`{qualified}\`) or give it a heading; a namespace's members are public surface, not implementation`
			)
		end
	end

	for token in documented do
		if not exportSet[token] and not nestedNames[token] then
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
				`contract control {className} (src/class_contract.luau) has no leaf row in the registry — declare its inputProofs (or 'inputProofs = false' if non-interactive; silent omission is a failure, ui_todo §0)`
			)
		end
	end

	-- derive interactivity for every real row, then fold in synthetic rows
	local proofRows: { any } = {}
	for _, entry in registry do
		local isInteractive: boolean
		if entry.kind == "leaf" then
			isInteractive = leafInteractive(entry.name)
		else -- composite: interactive iff it attaches an input contribution...
			isInteractive = false
			if entry.module ~= nil and fs.isFile(entry.module) then
				local source = fs.readFile(entry.module)
				isInteractive = string.find(source, "contribution.attach", 1, true) ~= nil
				-- ...unless that contribution is pure INTAKE (see
				-- CONTRIBUTION_INTAKE_ONLY). The exemption is refused the moment the
				-- module mentions a verb-bearing field, so it cannot outlive the
				-- reason it was granted.
				if isInteractive and CONTRIBUTION_INTAKE_ONLY[entry.name] ~= nil then
					local carriesVerb = false
					for _, field in VERB_BEARING_FIELDS do
						if string.find(source, field, 1, true) ~= nil then
							carriesVerb = true
							problem(
								`control {entry.name} is listed in CONTRIBUTION_INTAKE_ONLY but its module mentions `
									.. `'{field}' — a bundle that carries a verb is INTERACTIVE and must prove all four `
									.. "input classes (ui_todo §0). Remove the exemption or remove the field."
							)
							break
						end
					end
					isInteractive = carriesVerb
				end
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
			nestedMembers = #nestedMembers,
			nestedDocumented = nestedDocumented,
			specs = #specFiles,
			interactiveControls = interactiveControls,
			affordanceControls = affordanceControls,
		},
	}
end

return check_registration
