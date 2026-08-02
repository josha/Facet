--!strict
-- Extension scaffold (design §17 Phase 4 agentic maintainability;
-- UI-AGENT-001): stamps a complete skeleton so registration cannot be
-- forgotten. plan(kind, name) is PURE (returns the files/edits without
-- touching disk — unit-testable); the CLI (tools/lune/scaffold_cli.luau)
-- applies a plan. Kinds:
--   control — composite control: src/controls/<name>.luau (build() seam +
--             dump surface), tests/<name>.spec.luau (a deliberately-failing
--             TODO test: the red step of the loop), registration edits for
--             tests/run.luau, the controls registry, src/init.luau export,
--             and a docs/reference/api.md stub.
--   adapter — render-target adapter skeleton implementing the §13 target
--             contract (headless-testable; client wiring by hand), plus a
--             tests/<name>.spec.luau conformance stub and its tests/run.luau
--             registration.
-- After applying: implement until tests/run.luau is green, run
-- tools/lune/check_registration_cli, then the phase gate. The full loop is
-- docs/extending/new-control.md.

local scaffold = {}

export type PlannedFile = { path: string, content: string }
-- edits insert `insert` immediately BEFORE the first line containing
-- `before` (or append to the file when before = nil), skipping when the
-- exact `insert` text is already present (idempotent)
export type PlannedEdit = { path: string, before: string?, insert: string }
export type Plan = { kind: string, name: string, files: { PlannedFile }, edits: { PlannedEdit } }

local function pascal(name: string): string
	local out = {}
	for word in string.gmatch(name, "[^_]+") do
		table.insert(out, string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2))
	end
	return table.concat(out)
end

local CONTROL_TEMPLATE = [==[
--!strict
-- %DISPLAY% control (scaffolded by tools/lune/scaffold — replace this line
-- with what the control IS and which primitives it composes).
-- Composite-control seam: build(LuauUI, core, spec) returns
-- { blueprint, dump, dispose } (plus any control-specific api). Compose the
-- shipped UI.* primitives; own every resource in the control scope; expose a
-- deterministic dump() (the control contract's diagnostic form).


local %NAME% = {}

function %NAME%.build(LuauUI: any, core: any, spec: any)
	local UI = LuauUI.UI
	-- the input-contribution seam is PUBLIC (LuauUI.contribution), so a control
	-- built outside this repository attaches its bundle exactly like this one
	local contribution = LuauUI.contribution
	local scope = core:scope("%NAME%-" .. tostring(spec.id or "%DISPLAY%"))

	-- TODO: control state (signals/memos) owned by `scope`

	local blueprint = UI.VStack({
		id = spec.id or "%DISPLAY%",
		children = {
			-- TODO: compose primitives here
			UI.Text({ id = "Todo", text = "%DISPLAY%: unimplemented", textSize = 14 }),
		},
	})

	-- THREE AXES every control must satisfy (affordance matrix §A;
	-- UI-PARADIGM-001..003). This control must choose an idiom for each:
	--   1. UI (layout)     — how the tree arranges per sizeClass / distanceProfile.
	--   2. INPUT (reach)   — every verb (Activate/Cancel/Navigate/Adjust) fires on
	--                        every live class (the inputProofs below).
	--   3. PARADIGM (idiom)— the SHAPE each live class expects (affordanceProofs):
	--        pointer  → direct manipulation: direct drag (no grip), a HOVER preview
	--                   layer, wheel as a SEPARATE scroll channel.
	--        touch    → fingers, no hover, 44px hit floor; a NAKED PAN scrolls, so
	--                   any pan-to-reorder needs an edit-mode ≡ grip / long-press.
	--        keyboard → visible focus ring; Navigate (arrows) → Activate (Return);
	--                   Adjust = arrow/comma-period on a focused value.
	--        gamepad  → focus + select (A/B); reorder = grab mode; Adjust =
	--                   focus-then-directional; STRONG focus at ten-foot.
	-- Structural affordances read the LIVE class set (env interactionClasses),
	-- never preferredInput alone (ADR-0015). Fill only your control's idioms.
	--
	-- FOUR-INPUT STORY (ui_todo §0; ADR-0013). A composite advertises its
	-- behavior to the presenter by attaching an input-contribution bundle to its
	-- ROOT blueprint — MOUNTING the control then yields the whole story with NO
	-- consumer wiring (presenter auto-composes focus groups, Activate dispatch,
	-- geometry, keep-visible, Adjust, Cancel/outside-dismiss). Fill the fields
	-- your control needs, then keep this attach (the stamped spec cases below and
	-- the registry row's inputProofs + affordanceProofs enforce it):
	blueprint = contribution.attach(blueprint, {
		-- focusGroups = function(rootNode) ... end,     -- D-pad / arrow navigation
		-- handleActivate = function(path, meta) ... end, -- tap / A / Return
		-- navigateIntercept = function(direction) ... end, -- grab mode, etc.
		-- focusMoved = function(path) ... end,          -- scroll-into-view
		-- syncGeometry = function(rectOf) ... end,
		-- keepVisibleOffset = nil,                       -- Readable<number>
		-- bindActionSystem = function(actionSystem) ... end, -- text-entry sink, etc.
		-- adjustTargets = function(rootNode) ... end,    -- focus-gated Adjust targets
		-- handleAdjust = function(path, direction) ... end, -- +/- on a focused value
		-- handleCancel = function(focusedPath) ... end,  -- gamepad B on a transient surface
		-- outsideDismiss = { active = ..., dismiss = ... }, -- tap-away closes (popup)
		-- transientScope = { active = ..., rootPath = ... }, -- trap+restore focus while open
	})

	-- deterministic diagnostic summary (keep in sync with the control state)
	local function dump()
		return {
			schema = "luauui-%NAME%-dump/1",
			id = spec.id or "%DISPLAY%",
			-- TODO: the state a bug report needs
		}
	end

	return {
		blueprint = blueprint,
		dump = dump,
		dispose = function()
			scope:dispose()
		end,
	}
end

return %NAME%
]==]

local SPEC_TEMPLATE = [==[
--!strict
-- %DISPLAY% control spec (scaffolded). The stamped test FAILS on purpose:
-- that is the red step of the loop (failing test -> implement -> conformance
-- -> dumps -> gate). Replace it with the control's real behavior.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local %NAME% = require("../src/controls/%NAME%")

describe("%DISPLAY% control", function()
	it("TODO: replace with the control's first real behavior", function()
		local core = LuauUI.newCore()
		local control = %NAME%.build(LuauUI, core, { id = "%DISPLAY%" })
		expect(control.blueprint ~= nil).toBeTruthy()
		error("unimplemented: write the control's real failing test, then implement it")
	end)

	-- FOUR-INPUT CONFORMANCE (ui_todo §0): the control must PROVE all four input
	-- classes end to end through the REAL device paths (adapter.tap / pointer
	-- handlers for pointer+touch, presenter + system.deviceKey for
	-- keyboard+gamepad) — NEVER by calling callbacks directly. These four case
	-- names are the inputProofs the registry row cites; the registration checker
	-- fails a control that leaves any of them a mouse-only stub. Implement each,
	-- then delete this comment.
	it("%DISPLAY% pointer: a tap activates through the presenter (device-true)", function()
		error("unimplemented: prove the POINTER (mouse) story via adapter.tap")
	end)
	it("%DISPLAY% touch: a touch tap/pan drives the control (device-true)", function()
		error("unimplemented: prove the TOUCH story via a touch-typed pointer event")
	end)
	it("%DISPLAY% keyboard: focus + Return drives the control", function()
		error("unimplemented: prove the KEYBOARD story via system.deviceKey('Return')")
	end)
	it("%DISPLAY% gamepad: focus + ButtonA drives the control", function()
		error("unimplemented: prove the GAMEPAD story via system.deviceKey('ButtonA')")
	end)

	-- PARADIGM AXIS (UI-PARADIGM-001; affordance matrix §A/§B). The four cases
	-- above prove REACHABILITY (the verb fires). These four prove the STRUCTURAL
	-- IDIOM each live class expects — the SHAPE of the interaction, distinct from
	-- reachability: pointer direct-drag + HOVER + wheel; touch 44px +
	-- naked-pan-scroll + edit-grip; keyboard focus ring + Navigate/Activate/
	-- Adjust; gamepad focus + grab + A/B + STRONG focus at ten-foot. Choose your
	-- control's idiom per class and prove it; the registry row's affordanceProofs
	-- cites these exact names and the registration checker fails a missing one.
	it("%DISPLAY% pointer affordance: the pointer structural idiom (hover/direct-drag/wheel)", function()
		error("unimplemented: prove the POINTER structural idiom, not merely reachability")
	end)
	it("%DISPLAY% touch affordance: the touch structural idiom (44px/naked-pan-scroll/edit-grip)", function()
		error("unimplemented: prove the TOUCH structural idiom, not merely reachability")
	end)
	it("%DISPLAY% keyboard affordance: the keyboard structural idiom (focus ring/Navigate/Activate/Adjust)", function()
		error("unimplemented: prove the KEYBOARD structural idiom, not merely reachability")
	end)
	it("%DISPLAY% gamepad affordance: the gamepad structural idiom (focus/grab/A-B/ten-foot)", function()
		error("unimplemented: prove the GAMEPAD structural idiom, not merely reachability")
	end)

	-- HOT-SWITCH (UI-PARADIGM-002; matrix §C). If your control owns IN-FLIGHT
	-- state (a drag, a grab, an open edit), decide CARRY (the state survives; the
	-- newly-live class's idiom becomes additionally available) or CANCEL (a clean
	-- revert to the pre-gesture snapshot — no data loss, never a wedge) for a
	-- mid-gesture class flip, and prove it here. If the control owns NO in-flight
	-- state, DELETE this case and set affordanceProofs.hotSwitch = false.
	it("%DISPLAY% hot-switch: in-flight state resolves CARRY or CANCEL on a class flip", function()
		error("unimplemented: prove the in-flight class-flip semantic, or set hotSwitch = false")
	end)
end)
]==]

local ADAPTER_TEMPLATE = [==[
--!strict
-- %DISPLAY% render-target adapter (scaffolded): implements the
-- RenderTargetAdapter contract (src/render/target_contract.luau, design's
-- render-target seam). Engine specifics stay INSIDE this file behind
-- capability detection with a headless fallback; the renderer never learns
-- about them. Validate with tests against the contract (see
-- tests/render_target_contract.spec.luau for the conformance pattern).
--
-- THREE LISTS, and the contract module is the authority on all three:
--   REQUIRED  the six below — the renderer calls them unconditionally.
--   OPTIONAL  feature-detected; each absence is ONE named degrade (hit-target
--             floor, wheel channel, z-order, pointer capture, native scrolling,
--             drag detector, touch gestures, text premeasurement, display
--             order, reduced-motion transitions, root visibility, ...).
--             Read the consequence comments in target_contract.luau and decide
--             each one deliberately — "not implemented yet" is a legal answer,
--             a silently missing method is not.
--   THEME     nativeStyleInfo / themeRootGui / setThemePackage /
--             relinkThemeSheet. Without them theme_controller.install cannot
--             theme this target (it degrades to fallback paint, and in native
--             mode errors unless the caller passes opts.rootGui).
-- `target_contract.check(adapter)` reports all three; the stamped spec asserts
-- REQUIRED is complete and prints the other two so the gaps are on the record.

local %NAME% = {}

function %NAME%.new(opts: any?)
	local adapter = {}

	function adapter.createRoot(screenId: string): any
		-- TODO: create the root container for this target
		return { id = screenId }
	end

	-- `decorationHint` and `createOpts` are CREATION-TIME facts (ADR-0019 /
	-- ADR-0022 Decision 2): the decoration slot this node is skinned as, and
	-- `{ canvasGroup = true }` when the node's engine CLASS must be a group so a
	-- subtree can fade as one. Neither can arrive as a later prop write. An
	-- adapter that neither skins nor groups ignores both — but it must still
	-- ACCEPT them, or every renderer call silently drops two arguments.
	function adapter.create(
		rootHandle: any,
		path: string,
		class: string,
		decorationHint: any?,
		createOpts: { canvasGroup: boolean? }?
	): any
		-- TODO: materialize a node for `class`
		return { path = path, class = class, root = rootHandle }
	end

	function adapter.setRect(handle: any, rect: any)
		-- TODO: layout authority writes position/size
	end

	function adapter.setProp(handle: any, prop: string, value: any, authority: string)
		-- TODO: style/binding/presentation writes
	end

	function adapter.remove(handle: any)
		-- TODO: destroy the node's resources
	end

	function adapter.destroyRoot(rootHandle: any)
		-- TODO: tear down everything this root created
	end

	return adapter
end

return %NAME%
]==]

-- The adapter's stamped spec. HEADLESS on purpose: it constructs the adapter
-- table and runs the contract checker against it, so the first thing a new
-- target has is a test that fails the moment a REQUIRED method is missing or
-- renamed — and a printed record of which OPTIONAL/THEME capabilities it is
-- choosing to go without. (Engine writes belong behind capability detection and
-- are proven in a Studio drive; this spec is the part that can run every time.)
local ADAPTER_SPEC_TEMPLATE = [==[
--!strict
-- %DISPLAY% render-target adapter conformance (scaffolded). The contract module
-- is the authority: src/render/target_contract.luau declares REQUIRED (called
-- unconditionally), OPTIONAL (feature-detected; each absence is one named
-- degrade) and THEME (theme_controller's four). Grow this spec into the real
-- conformance pattern in tests/render_target_contract.spec.luau: render a small
-- screen through mount -> renderer.attach(yourAdapter) -> initialRender, and
-- prove destroyRoot releases everything.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local target_contract = require("../src/render/target_contract")
local %NAME% = require("../src/client/%NAME%")

describe("%DISPLAY% render-target adapter", function()
	it("implements every REQUIRED method of the RenderTargetAdapter contract", function()
		local result = target_contract.check(%NAME%.new())
		if #result.missing > 0 then
			error(
				`%DISPLAY% is missing REQUIRED adapter methods: {table.concat(result.missing, ", ")} — `
					.. "the renderer calls these unconditionally, so the target cannot be mounted",
				0
			)
		end
		expect(#result.missing).toBe(0)
	end)

	it("declares which OPTIONAL and THEME capabilities it goes without", function()
		local result = target_contract.check(%NAME%.new())
		-- Not a failure — a RECORD. Each absent name is one degrade named in
		-- target_contract.luau; decide each deliberately, then pin the ones you
		-- DID implement with a behavioural case of its own.
		print(`%DISPLAY%: optional absent = {table.concat(result.optionalAbsent, ", ")}`)
		print(`%DISPLAY%: themeable = {tostring(result.themeable)}`)
		expect(type(result.themeable)).toBe("boolean")
	end)

	it("TODO: renders a small screen and releases it on destroyRoot", function()
		error("unimplemented: mount -> renderer.attach -> initialRender, then prove teardown")
	end)
end)]==]

local REGISTRY_ROW_TEMPLATE = [==[
	{
		name = "%DISPLAY%",
		kind = "composite",
		module = "src/controls/%NAME%.luau",
		export = "new%DISPLAY%",
		spec = "tests/%NAME%.spec.luau",
		conformance = "tests/%NAME%.spec.luau",
		docsAnchor = "new%DISPLAY%",
		-- cite the dump DEFINITION exactly (check_registration requires the text to
		-- exist in the module); a module with no dump surface declares
		-- `dump = false` with a `reason` instead
		dumpFunction = "function dump",
		-- Four-input proofs (ui_todo §0): each case name must exist VERBATIM in a
		-- registered spec. These cite the four stamped cases in tests/%NAME%.spec.luau
		-- (they FAIL until you implement them — that is the red step).
		inputProofs = {
			pointer = { "%DISPLAY% pointer: a tap activates through the presenter (device-true)" },
			touch = { "%DISPLAY% touch: a touch tap/pan drives the control (device-true)" },
			keyboard = { "%DISPLAY% keyboard: focus + Return drives the control" },
			gamepad = { "%DISPLAY% gamepad: focus + ButtonA drives the control" },
		},
		-- Paradigm-axis proofs (UI-PARADIGM-001/002): the STRUCTURAL IDIOM per
		-- live class (distinct from inputProofs' reachability) plus the hotSwitch
		-- decision. These cite the four affordance cases + the hot-switch stub in
		-- tests/%NAME%.spec.luau. If your control owns no in-flight state, set
		-- hotSwitch = false and delete the stamped hot-switch spec case.
		affordanceProofs = {
			pointer = { "%DISPLAY% pointer affordance: the pointer structural idiom (hover/direct-drag/wheel)" },
			touch = { "%DISPLAY% touch affordance: the touch structural idiom (44px/naked-pan-scroll/edit-grip)" },
			keyboard = { "%DISPLAY% keyboard affordance: the keyboard structural idiom (focus ring/Navigate/Activate/Adjust)" },
			gamepad = { "%DISPLAY% gamepad affordance: the gamepad structural idiom (focus/grab/A-B/ten-foot)" },
			hotSwitch = { "%DISPLAY% hot-switch: in-flight state resolves CARRY or CANCEL on a class flip" },
		},
	},]==]

local API_STUB_TEMPLATE = [==[

### `new%DISPLAY%`

`LuauUI.new%DISPLAY%(LuauUI, core, spec) -> { blueprint, dump, dispose }` —
TODO: one-paragraph description, the spec shape, invariants, and a short
usage example (scaffolded stub — the registration checker requires this
anchor; the docs-accuracy review requires it to be REAL).]==]

local function fill(template: string, name: string, display: string): string
	local out = string.gsub(template, "%%NAME%%", name)
	out = string.gsub(out, "%%DISPLAY%%", display)
	-- drop the leading newline the long-string form carries
	return string.gsub(out, "^\n", "")
end

local function controlSource(name: string, display: string): string
	return fill(CONTROL_TEMPLATE, name, display)
end

local function controlSpec(name: string, display: string): string
	return fill(SPEC_TEMPLATE, name, display)
end

local function adapterSource(name: string, display: string): string
	return fill(ADAPTER_TEMPLATE, name, display)
end

local function adapterSpec(name: string, display: string): string
	return fill(ADAPTER_SPEC_TEMPLATE, name, display)
end

function scaffold.plan(kind: string, name: string): Plan
	assert(kind == "control" or kind == "adapter", `unknown scaffold kind '{kind}' (control | adapter)`)
	assert(string.match(name, "^[a-z][a-z0-9_]*$") ~= nil, `unsafe scaffold name '{name}' (lower_snake_case, no paths)`)
	local display = pascal(name)

	if kind == "adapter" then
		-- the adapter branch used to stamp ZERO edits (SEAM-25), so unlike the
		-- control path there was no spec and nothing registered it — and an
		-- unregistered spec is a silent zero (check_registration rule 3). It now
		-- stamps the conformance spec AND its runner line, through the same pure
		-- edit mechanism the control branch uses.
		return {
			kind = kind,
			name = name,
			files = {
				{ path = `src/client/{name}.luau`, content = adapterSource(name, display) },
				{ path = `tests/{name}.spec.luau`, content = adapterSpec(name, display) },
			},
			edits = {
				{
					path = "tests/run.luau",
					before = "local ok = testkit.run()",
					insert = `require("./{name}.spec")`,
				},
			},
		}
	end

	return {
		kind = kind,
		name = name,
		files = {
			{ path = `src/controls/{name}.luau`, content = controlSource(name, display) },
			{ path = `tests/{name}.spec.luau`, content = controlSpec(name, display) },
		},
		edits = {
			{
				path = "tests/run.luau",
				before = "local ok = testkit.run()",
				insert = `require("./{name}.spec")`,
			},
			{
				path = "tests/conformance/controls_registry.luau",
				-- unique sentinel INSIDE the registry array (dry-run defect 1:
				-- a bare '}' anchor matched the export type block first and
				-- corrupted the file)
				before = "scaffold: new control rows are appended above this line",
				insert = fill(REGISTRY_ROW_TEMPLATE, name, display),
			},
			{
				path = "src/init.luau",
				before = "	-- async resources",
				insert = `	new{display} = require("@self/controls/{name}").build,`,
			},
			{
				path = "docs/reference/api.md",
				before = nil, -- append
				insert = fill(API_STUB_TEMPLATE, name, display),
			},
		},
	}
end

-- pure edit application (shared by the CLI and the tests — dry-run defect 1
-- proved the apply must be provably correct, not just the plan): inserts
-- `edit.insert` immediately BEFORE the first line matching `edit.before`
-- (Lua pattern when ^-prefixed, plain substring otherwise), or appends when
-- `before` is nil. Idempotent: returns the source unchanged when the insert
-- text is already present. Errors when the anchor is missing.
function scaffold.applyEdit(source: string, edit: PlannedEdit): string
	if string.find(source, edit.insert, 1, true) ~= nil then
		return source
	end
	if edit.before == nil then
		return source .. edit.insert .. "\n"
	end
	local lines = string.split(source, "\n")
	local out = {}
	local inserted = false
	for _, line in lines do
		local matches = if string.sub(edit.before :: string, 1, 1) == "^"
			then string.match(line, edit.before :: string) ~= nil
			else string.find(line, edit.before :: string, 1, true) ~= nil
		if not inserted and matches then
			table.insert(out, edit.insert)
			inserted = true
		end
		table.insert(out, line)
	end
	assert(inserted, `scaffold.applyEdit: anchor '{edit.before}' not found in the target`)
	return table.concat(out, "\n")
end

return scaffold
