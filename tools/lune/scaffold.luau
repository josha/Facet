--!strict
-- Extension scaffold (design §17 Phase 4 agentic maintainability;
-- UI-AGENT-001): stamps a complete skeleton so registration cannot be
-- forgotten. plan(kind, name) is PURE (returns the files/edits without
-- touching disk — unit-testable); the CLI (tools/lune/scaffold_cli.luau)
-- applies a plan. Kinds:
--   control — composite control: src/controls/<name>.luau (build() seam +
--             dump surface), tests/<name>.spec.luau (a deliberately-failing
--             TODO test: the red step of the loop), a gallery scenario, and
--             EVERY registration a twentieth control needs — the runner, the
--             controls registry, the src/init.luau export, the api.md stub, the
--             large-text fixture, the guide's capability catalog, the Controls
--             namespace allowlist, the scenario ORDER, the overflow sweep, the
--             demo picker and its pinned root and counts.
--   adapter — render-target adapter skeleton implementing the §13 target
--             contract (headless-testable; client wiring by hand), plus a
--             tests/<name>.spec.luau conformance stub and its tests/run.luau
--             registration.
--
-- ONE DECLARED CONTROL RECORD, and the control branch is where that requirement
-- is met. Measured 2026-08-21, by a fresh-context agent contributing a real
-- control with no other help: the six registrations after `docs/reference/api.md`
-- were EVERY ONE of them discovered by a red test rather than by reading, and one
-- of them (the guide catalog row) reddened four documentation-gate cases the
-- playbook never mentioned. `docs/extending/new-control.md` §6.1 asked for all of
-- it in nine words ("Add it to an instrumented gallery fixture"). A registration a
-- tool can derive from the control's name is a registration a person should never
-- be asked to remember, so this stamps them all, and the playbook only has to name
-- what it cannot stamp.
--
-- After applying: implement until tests/run.luau is green, run
-- tools/lune/check_registration_cli, then the phase gate. The full loop is
-- docs/extending/new-control.md.

local scaffold = {}

export type PlannedFile = { path: string, content: string }
-- edits insert `insert` immediately BEFORE the first line containing
-- `before` (or append to the file when before = nil), skipping when the
-- exact `insert` text is already present (idempotent)
export type PlannedEdit = { path: string, before: string?, insert: string }
--[[ A COUNT PIN THE SCAFFOLD MOVES, which is the one edit shape a plain insert
	cannot express. Two spec files pin catalogue SIZES as literals
	(`expect(#demos).toBe(36)`), deliberately: a ratchet is how this repository
	makes a catalogue change a decision rather than an accident. A scaffolded
	control IS that decision, taken at the moment the author typed the control's
	name, so the tool moves the number and the ratchet keeps biting for every
	hand edit that is not a scaffold run.

	`prefix` and `suffix` are PLAIN TEXT bracketing the number; EVERY occurrence
	is incremented, because the same pin is asserted in two different describes
	and moving one of them is worse than moving neither.

	A bump is NOT idempotent on its own — re-running would keep counting — so it
	carries a `guard`: text that the same run also inserts into the same file. If
	the guard is already there the bump has already happened and is skipped. That
	is why `plan.bumps` is applied BEFORE `plan.edits`. ]]
export type PlannedBump = { path: string, prefix: string, suffix: string, guard: string }
export type Plan = {
	kind: string,
	name: string,
	files: { PlannedFile },
	edits: { PlannedEdit },
	bumps: { PlannedBump },
}

local function pascal(name: string): string
	local out = {}
	for word in string.gmatch(name, "[^_]+") do
		table.insert(out, string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2))
	end
	return table.concat(out)
end

-- the demo picker's ids are kebab-case (`row-actions`, `nested-tree`), one
-- spelling of the same name as the module's lower_snake_case
local function kebab(name: string): string
	return (string.gsub(name, "_", "-"))
end

local CONTROL_TEMPLATE = [==[
--!strict
-- %DISPLAY% control (scaffolded by tools/lune/scaffold — replace this line
-- with what the control IS and which primitives it composes).
-- Composite-control seam: build(Facet, core, spec) returns
-- { blueprint, dump, dispose } (plus any control-specific api). Compose the
-- shipped UI.* primitives; own every resource in the control scope; expose a
-- deterministic dump() (the control contract's diagnostic form).

local %NAME% = {}

export type Spec = {
	id: string?,
	-- TODO: the real spec keys. `Facet.Controls.%DISPLAY%` in src/init.luau
	-- declares this type, so a caller gets argument checking, not `any`.
	[string]: any,
}

function %NAME%.build(Facet: any, core: any, spec: Spec)
	local UI = Facet.UI
	-- the input-contribution seam is PUBLIC (Facet.contribution), so a control
	-- built outside this repository attaches its bundle exactly like this one
	local contribution = Facet.contribution
	local scope = core:scope("%NAME%-" .. tostring(spec.id or "%DISPLAY%"))

	-- TODO: control state (signals/memos) owned by `scope`

	local blueprint = UI.VStack({
		id = spec.id or "%DISPLAY%",
		children = {
			-- TODO: compose primitives here
			-- NO `textSize`: a bare number here is a theme-owned metric written into
			-- the control, and `tools/lune/check_theme_drift` rejects it — which
			-- used to make this scaffold's own output fail the playbook's stated
			-- pass condition (MAINT-3). Omitting it is not a shortcut: the renderer
			-- resolves the intrinsic size from the type ROLE for the class, so the
			-- text scales with the package and with the player's text-size
			-- preference. Name a role when you want a different one
			-- (`role = "caption"`), never a number.
			-- `disclose = true` says: if this string ever has to be cut, there is a
			-- path to the whole value. It is stamped because WITHOUT IT THE
			-- SCAFFOLD'S OWN OUTPUT WAS RED — `tests/large_text_matrix.spec`'s
			-- LT8-CTL row measured this very line truncating at the Largest text
			-- preference under the Parchment package, "essential text truncated with
			-- no full-value path", on the first end-to-end run of this scaffold
			-- (2026-08-21). A tool must not hand its author a failure it wrote
			-- itself. Keep the declaration on any text a player must be able to read
			-- in full; the sweep will tell you, in these words, if you drop it.
			UI.Text({ id = "Todo", text = "%DISPLAY%: unimplemented", disclose = true }),
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
			schema = "facet-%NAME%-dump/1",
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

local Facet = require("../src") :: any
local %NAME% = require("../src/controls/%NAME%")

describe("%DISPLAY% control", function()
	it("TODO: replace with the control's first real behavior", function()
		local core = Facet.newCore()
		local control = %NAME%.build(Facet, core, { id = "%DISPLAY%" })
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
	it("%DISPLAY% pointer affordance: hover, direct drag, wheel channel", function()
		error("unimplemented: prove the POINTER structural idiom, not merely reachability")
	end)
	it("%DISPLAY% touch affordance: 44px floor, naked-pan scroll, edit grip", function()
		error("unimplemented: prove the TOUCH structural idiom, not merely reachability")
	end)
	it("%DISPLAY% keyboard affordance: focus ring, Navigate, Activate, Adjust", function()
		error("unimplemented: prove the KEYBOARD structural idiom, not merely reachability")
	end)
	it("%DISPLAY% gamepad affordance: focus, grab mode, A and B, ten-foot ring", function()
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

-- the large-text sweep row (tests/lib/large_text_fixtures.luau). The stub
-- control already renders a Text, so the sweep has something real to measure at
-- every preference offset and in both reference themes from day one.
local LARGE_TEXT_FIXTURE_TEMPLATE = [==[
	{
		id = "%DISPLAY%",
		class = "%DISPLAY%",
		-- STAMPED BY THE SCAFFOLD. Grow it with the control: a fixture that mounts
		-- the stub proves the stub, and the sweep's whole question is whether THIS
		-- control's text still fits its boxes at +14px in a wider theme.
		build = function(core: any)
			return Facet.Controls.%DISPLAY%(core, { id = "Ctl" }).blueprint
		end,
	},
]==]

--[[ THE GALLERY SCENARIO (standing rule 4). "Every gap closure ships its
	showcase demo, registered in `scenarios/init.luau` ORDER **and**
	`demo_picker.DEMOS`, swept by `tests/overflow_sweep.spec.luau` at all
	viewports, and verified across every shipped theme" — four registrations that
	`docs/extending/new-control.md` used to compress into nine words, and that a
	fresh-context author met as four separate red tests in three files.

	The stub is a REAL surface from the first commit rather than a placeholder: it
	mounts the control on a page that scrolls, so the always-on sweeps have
	something to measure at every viewport, every text preference and every
	shipped theme while the control is still a stub. That is the same argument the
	large-text fixture below it makes, and on this repository's own evidence it is
	the strongest thing here — the two always-on sweeps caught two real defects in
	the first control contributed through this scaffold, neither of which any test
	its author wrote would have found. ]]
local SCENARIO_TEMPLATE = [==[
--!strict
-- Scenario '%NAME%' (scaffolded by tools/lune/scaffold): the showcase surface
-- for `Facet.Controls.%DISPLAY%` — the demo `%KEBAB%` in the picker, and
-- `Facet_Scenario = "%NAME%"` before Play.
--
-- GROW THIS WITH THE CONTROL. A fixture exists so a person can DRIVE the control
-- on a device, which is the half no headless case can hold: give it
-- deterministic state, add one named `step` per verb the control offers plus a
-- `reset`, and make `report()` return what a bug report needs.
-- `examples/gallery/scenarios/branch_scope.luau` and `lifecycle_hidden.luau`
-- are the two smallest complete worked examples.
--
-- THE PAGE SCROLLS ON PURPOSE. Content that overflows with nothing to scroll it
-- is this repository's named recurring defect, and `tests/overflow_sweep.spec`
-- measures this surface at nine viewports by four text preferences by every
-- shipped theme from the moment it is registered.
--
-- NO LITERAL METRICS. Type sizes come from ROLES, not numbers, so the surface
-- follows the theme package and the player's own text-size preference.

return {
	title = "%DISPLAY%",
	ledgerRows = {},
	build = function(ctx: any)
		local UI = ctx.Facet.UI
		local control = ctx.Facet.Controls.%DISPLAY%(ctx.core, { id = "Ctl" })

		local screen = UI.Screen({
			id = "%DISPLAY%",
			padding = 12,
			gap = 8,
			children = {
				UI.ScrollView({
					id = "Page",
					axis = "y",
					gap = 8,
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.Text({ id = "Title", text = "%DISPLAY%" }),
						control.blueprint,
					},
				}),
			},
		})

		return {
			screen = screen,
			-- TODO: one named step per verb a person would drive, plus `reset`
			steps = {},
			report = function()
				return control.dump()
			end,
		}
	end,
}
]==]

-- the guide's capability-catalog row. Its ABSENCE is what reddened four
-- documentation-gate cases for the first agent to contribute a control, with
-- nothing in any playbook saying the row was mandatory.
local GUIDE_CATALOG_ROW_TEMPLATE =
	[==[| `Controls.%DISPLAY%` | TODO: one sentence, in a Roblox developer's words, about what this control does. | [api](../reference/api.md#controls%LOWERDISPLAY%) |]==]

-- the Controls namespace allowlist. A post-ADR-0037 control has no old form and
-- no deprecation row, so it joins POST_ADR_NAMES rather than the migration set.
local NAMESPACE_NAME_TEMPLATE = [==[	"%DISPLAY%",]==]

local SCENARIO_ORDER_TEMPLATE = [==[	-- scaffolded showcase surface for `Facet.Controls.%DISPLAY%`. Also in
	-- `demo_picker.DEMOS`. TODO: say what a player can only learn by DRIVING it.
	"%NAME%",]==]

local SWEEP_ROW_TEMPLATE = [==[	-- ...and the scaffolded `%DISPLAY%` surface, swept from its first commit so
	-- the control cannot reach a device with an overflow nobody measured.
	"%NAME%",]==]

local DEMO_ROW_TEMPLATE = [==[	-- scaffolded: the surface a person opens on a phone to drive %DISPLAY%.
	{
		id = "%KEBAB%",
		title = "%DISPLAY%",
		blurb = "TODO: what a person can do with this control on a device",
		kind = "fixture",
		module = "%NAME%",
	},]==]

local DEMO_ROOT_ROW_TEMPLATE = [==[	["%KEBAB%"] = "%DISPLAY%",]==]

local REGISTRY_ROW_TEMPLATE = [==[
	{
		name = "%DISPLAY%",
		kind = "composite",
		module = "src/controls/%NAME%.luau",
		export = "Controls.%DISPLAY%",
		spec = "tests/%NAME%.spec.luau",
		conformance = "tests/%NAME%.spec.luau",
		docsAnchor = "Controls.%DISPLAY%",
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
			pointer = { "%DISPLAY% pointer affordance: hover, direct drag, wheel channel" },
			touch = { "%DISPLAY% touch affordance: 44px floor, naked-pan scroll, edit grip" },
			keyboard = { "%DISPLAY% keyboard affordance: focus ring, Navigate, Activate, Adjust" },
			gamepad = { "%DISPLAY% gamepad affordance: focus, grab mode, A and B, ten-foot ring" },
			hotSwitch = { "%DISPLAY% hot-switch: in-flight state resolves CARRY or CANCEL on a class flip" },
		},
	},]==]

local API_STUB_TEMPLATE = [==[

### `Controls.%DISPLAY%`

`Facet.Controls.%DISPLAY%(core, spec) -> { blueprint, dump, dispose }` —
TODO: one-paragraph description, the spec shape, invariants, and a short
usage example (scaffolded stub — the registration checker requires this
anchor; the docs-accuracy review requires it to be REAL).

ADR-0037: a control created after 0.10.0 has ONE public spelling. There is no
`Facet.new%DISPLAY%` — the nineteen that exist are the pre-ADR set, kept working
and deprecated, and a new control is not born deprecated.]==]

local function fill(template: string, name: string, display: string): string
	local out = string.gsub(template, "%%NAME%%", name)
	-- LOWERDISPLAY before DISPLAY: `%DISPLAY%` is a prefix of `%DISPLAYX%` only
	-- by accident of naming, but the anchor token must be substituted while it is
	-- still whole
	out = string.gsub(out, "%%LOWERDISPLAY%%", string.lower(display))
	out = string.gsub(out, "%%DISPLAY%%", display)
	out = string.gsub(out, "%%KEBAB%%", kebab(name))
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
			bumps = {},
		}
	end

	return {
		kind = kind,
		name = name,
		files = {
			{ path = `src/controls/{name}.luau`, content = controlSource(name, display) },
			{ path = `tests/{name}.spec.luau`, content = controlSpec(name, display) },
			{
				path = `examples/gallery/scenarios/{name}.luau`,
				content = fill(SCENARIO_TEMPLATE, name, display),
			},
		},
		--[[ THE CATALOGUE COUNT PINS, moved BEFORE anything is inserted. Both live
			in tests/gallery_demo_picker.spec.luau and both are guarded by the
			DEMO_ROOT row this same run adds to that file, so a second scaffold run
			finds the guard and counts nothing twice. `expect(fixtures).toBe(N)` is
			asserted in TWO describes and both have to move together, which is why
			the bump is every-match rather than first-match. ]]
		bumps = {
			{
				path = "tests/gallery_demo_picker.spec.luau",
				prefix = "expect(#demos).toBe(",
				suffix = ")",
				guard = fill(DEMO_ROOT_ROW_TEMPLATE, name, display),
			},
			{
				path = "tests/gallery_demo_picker.spec.luau",
				prefix = "expect(fixtures).toBe(",
				suffix = ")",
				guard = fill(DEMO_ROOT_ROW_TEMPLATE, name, display),
			},
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
			--[[ THE CANONICAL EXPORT (ADR-0037). Two edits, because the namespace
				entry names the module twice — once to call it and once for the spec
				type it declares — so the module needs a local. There is deliberately no
				`new{display}` line: the nineteen old-form builders are the pre-ADR set,
				deprecated in the ledger, and a control scaffolded today is not born
				into a deprecated spelling. ]]
			{
				path = "src/init.luau",
				before = "local asyncResources = ",
				insert = `local {name} = require("@self/controls/{name}")`,
			},
			{
				path = "src/init.luau",
				before = "	AsyncImage = function(core: any, spec: any)",
				insert = `	{display} = function(core: any, spec: {name}.Spec)\n`
					.. `		return {name}.build(library, core, spec)\n`
					.. `	end,`,
			},
			--[[ ...AND THE LARGE-TEXT SWEEP (MAINT-3/MAINT-29, 2026-08-17). Without
				this row the scaffold's own output failed `LT8-COVER` the moment it
				landed — "every controls_registry row is swept or carries a declared
				reason" — and no playbook mentioned large-text fixtures at all, so the
				author met a red case with no instruction anywhere. A fixture, not a
				waiver: the stub already renders text, which is exactly what the sweep
				measures, so the new control is covered from its first commit and the
				author edits a real fixture rather than removing an exemption. ]]
			{
				path = "tests/lib/large_text_fixtures.luau",
				before = "scaffold: new control fixtures are appended above this line",
				insert = fill(LARGE_TEXT_FIXTURE_TEMPLATE, name, display),
			},
			{
				path = "docs/reference/api.md",
				before = nil, -- append
				insert = fill(API_STUB_TEMPLATE, name, display),
			},
			--[[ ...AND THE SIX THAT WERE NOBODY'S TO REMEMBER (2026-08-21). Each of
				these was discovered by a fresh-context control author as a RED TEST,
				not by reading, and the first of them reddened four documentation-gate
				cases at once. They are stamped from the same one declared name as
				everything above. ]]
			--[[ 1. THE GUIDE'S CAPABILITY CATALOG. A missing row here fails four
				cases in tests/theme_docs.spec ("the capability catalog does not name
				'Controls.X'"), and no playbook said the row was mandatory — §4 asked
				only for an api.md entry and a guide PARAGRAPH when the control
				introduces a new concept. The anchor is the api.md heading the stub
				above writes, so the two land together or not at all. It is inserted
				before `valueModel`, the first non-control row of that table: the
				controls stay together and the two value helpers stay last. ]]
			{
				path = "docs/guide/README.md",
				before = "| `valueModel` |",
				insert = fill(GUIDE_CATALOG_ROW_TEMPLATE, name, display),
			},
			-- 2. the Controls namespace allowlist (ADR-0037). A post-ADR control has
			-- no old form and no deprecation row, so it joins POST_ADR_NAMES rather
			-- than the migration set the other three cases in that file are about.
			{
				path = "tests/controls_namespace.spec.luau",
				before = "scaffold: new control names are appended above this line",
				insert = fill(NAMESPACE_NAME_TEMPLATE, name, display),
			},
			-- 3 and 4. standing rule 4's first two halves: the scenario is
			-- REGISTERED where the runner and the showcase can reach it, and SWEPT
			-- for overflow at every viewport, preference and theme. The sweep's own
			-- RULE 4 case asserts these two lists are the same set, so stamping one
			-- without the other would be a red test with a very good error message.
			{
				path = "examples/gallery/scenarios/init.luau",
				before = "scaffold: new control scenarios are appended above this line",
				insert = fill(SCENARIO_ORDER_TEMPLATE, name, display),
			},
			{
				path = "tests/overflow_sweep.spec.luau",
				before = "scaffold: new control scenarios are appended above this line",
				insert = fill(SWEEP_ROW_TEMPLATE, name, display),
			},
			-- 5 and 6. the demo picker's catalogue entry and the root screen the
			-- host sweep looks for. A demo with no pinned root is advanced through
			-- and never actually looked at, which is the defect one level up — so
			-- the scenario stub names its root screen after the control and this row
			-- pins that same name.
			{
				path = "examples/gallery/client/demo_picker.luau",
				before = "scaffold: new control demos are appended above this line",
				insert = fill(DEMO_ROW_TEMPLATE, name, display),
			},
			{
				path = "tests/gallery_demo_picker.spec.luau",
				before = "scaffold: new control roots are appended above this line",
				insert = fill(DEMO_ROOT_ROW_TEMPLATE, name, display),
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

--[[ pure count-pin application, the twin of applyEdit.

	PLAIN TEXT, NOT A PATTERN, on purpose: `expect(#demos).toBe(` is four
	characters of Lua-pattern magic in a row, and a tool whose job is to edit
	assertions is the last place to introduce an escaping question. Every
	occurrence of `prefix <digits> suffix` has its number incremented; a prefix
	NOT followed by digits-then-suffix is copied through untouched, so a
	near-miss elsewhere in the file cannot be mangled.

	Returns the source unchanged when `bump.guard` is already present — a bump
	has no natural idempotence of its own, and that is what the guard is for.
	Errors when nothing matched, for the same reason applyEdit errors on a
	missing anchor: a count pin that silently moved nowhere is a scaffold that
	reports success and leaves a red test behind. ]]
function scaffold.applyBump(source: string, bump: PlannedBump): string
	if string.find(source, bump.guard, 1, true) ~= nil then
		return source
	end
	local out: { string } = {}
	local pos = 1
	local moved = 0
	while true do
		local start, stop = string.find(source, bump.prefix, pos, true)
		if start == nil then
			break
		end
		local digits = string.match(source, "^(%d+)", (stop :: number) + 1)
		local afterDigits = if digits == nil then nil else (stop :: number) + 1 + #digits
		local suffixHere = if afterDigits == nil
			then nil
			else string.sub(source, afterDigits :: number, (afterDigits :: number) + #bump.suffix - 1)
		if digits == nil or suffixHere ~= bump.suffix then
			table.insert(out, string.sub(source, pos, stop :: number))
			pos = (stop :: number) + 1
			continue
		end
		table.insert(out, string.sub(source, pos, (start :: number) - 1))
		table.insert(out, bump.prefix)
		table.insert(out, tostring((tonumber(digits) :: number) + 1))
		moved += 1
		pos = afterDigits :: number
	end
	assert(
		moved > 0,
		`scaffold.applyBump: no '{bump.prefix}<number>{bump.suffix}' in the target — the pin moved or was renamed`
	)
	table.insert(out, string.sub(source, pos))
	return table.concat(out)
end

return scaffold
