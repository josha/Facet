--!strict
-- Composite-control registry (design §17 Phase 4 agentic maintainability;
-- UI-AGENT-001). ONE row per control class: every composite under src/controls/
-- (the contract module excepted) AND every leaf primitive declared in
-- src/controls/contract.luau. tools/lune/check_registration fails the gate when
-- a control file exists without a row here, when a row's spec / conformance /
-- docs / dump surface is missing, or when an INTERACTIVE control's four-input
-- story is not PROVEN (ui_todo §0: every control supports pointer + touch +
-- keyboard + gamepad; a mouse-only control cannot pass conformance). The
-- scaffold (tools/lune/scaffold) appends a row automatically.
--
-- Fields:
--   name        display name (for leaf rows, the contract.luau class key)
--   kind        "composite" (src/controls/*.luau) | "leaf" (a UI.* primitive)
--   inputProofs the four-input conformance declaration (ui_todo §0):
--                 { pointer = { "<exact spec it() case name>", ... },
--                   touch = {...}, keyboard = {...}, gamepad = {...} }
--               for every INTERACTIVE control — each case name must exist
--               VERBATIM in a spec file that tests/run.luau registers (the
--               checker string-searches the sources), and every one of the
--               four classes must be non-empty unless the pair is a named gap
--               (see PROOF_GAPS in tools/lune/check_registration). A
--               NON-INTERACTIVE control declares `inputProofs = false`
--               EXPLICITLY — silent omission is a checker failure.
--   affordanceProofs the PARADIGM-axis declaration (UI-PARADIGM-001/002; the
--               affordance matrix, artifacts/input-paradigms/affordance-matrix.md).
--               inputProofs proves REACHABILITY (every verb fires on every
--               class); affordanceProofs proves the STRUCTURAL IDIOM each class
--               expects — the SHAPE of the interaction, not merely that it
--               reaches:
--                 { pointer = {...},  -- direct-drag + hover + wheel
--                   touch = {...},    -- 44px + naked-pan-scroll + edit-grip
--                   keyboard = {...}, -- focus ring + Navigate/Activate/Adjust
--                   gamepad = {...},  -- focus + grab-mode + A/B + ten-foot focus
--                   hotSwitch = {...} | false }
--               Each cited case must exist VERBATIM in a registered spec (same
--               string-search rule as inputProofs). `hotSwitch` cites the §C
--               in-flight-transition cases for a control that owns in-flight
--               state (a drag/grab/edit that a mid-gesture class flip must
--               CARRY or CANCEL — Table, TextInput), or `false` for a control
--               that holds none (UI-PARADIGM-002). A NON-INTERACTIVE control
--               declares `affordanceProofs = false` EXPLICITLY — the checker
--               fails a silent omission, an uncited case, or an interactive
--               control missing any class (or hotSwitch). Named per-class gaps
--               live in AFFORDANCE_GAPS in tools/lune/check_registration; the
--               matrix Amendments record every per-class gap as CLOSED, so the
--               table currently cites existing green specs for every cell.
--   -- composite-only (nil on leaf rows):
--   module      source file (relative to the library root)
--   export      the src/init.luau key that exposes it
--   spec        the spec file exercising it
--   conformance file where its conformance-style coverage lives
--   docsAnchor  the docs/reference/api.md heading token for it
--   dumpFunction the DEFINITION of the deterministic dump surface (§10.2),
--               cited exactly: "function <x>.dump" (or "function dump" for a
--               local one). check_registration requires the text to exist in
--               the module as a definition — a free substring proved nothing,
--               which is how a row could cite the module's own name.
--   dump = false + reason  for a module that HAS no dump surface (a stateless
--               module, or the caller-scope shape). The reason says why;
--               silence is a checker failure.

export type InputProofs = {
	pointer: { string },
	touch: { string },
	keyboard: { string },
	gamepad: { string },
}

-- the PARADIGM axis (UI-PARADIGM-001/002): the four live-class structural
-- idioms plus the in-flight hot-switch semantic (a list of §C transition cases,
-- or `false` when the control holds no in-flight state)
export type AffordanceProofs = {
	pointer: { string },
	touch: { string },
	keyboard: { string },
	gamepad: { string },
	hotSwitch: { string } | boolean,
}

export type Entry = {
	name: string,
	kind: string,
	inputProofs: InputProofs | boolean,
	affordanceProofs: AffordanceProofs | boolean,
	module: string?,
	export: string?,
	spec: string?,
	conformance: string?,
	docsAnchor: string?,
	dumpFunction: string?,
	dump: boolean?,
	reason: string?,
}

local registry: { Entry } = {
	-- ===== composite controls (src/controls/*.luau) =====================
	{
		name = "Table",
		kind = "composite",
		module = "src/controls/table.luau",
		export = "newTable",
		spec = "tests/table.spec.luau",
		conformance = "tests/controls_conformance.spec.luau",
		docsAnchor = "newTable",
		dumpFunction = "function dump",
		-- pointer (mouse) proofs are device-true cases in table.spec.luau;
		-- tests/table_input.spec.luau owns the touch/keyboard/gamepad device-true
		-- cases (not the api-direct ones).
		inputProofs = {
			pointer = {
				"header taps cycle the owner-held sortOrder; the table never sorts the data",
				"dragging a selected row drags the WHOLE selection as a block (director example)",
			},
			touch = {
				"a TOUCH drag on the grip previews and commits the new column width",
				"a TOUCH grip drag clamps to the column minWidth",
			},
			keyboard = {
				"keyboard Down + Return select the focused row",
				"keyboard Right/Return drive the header sort identically to the gamepad",
				"keyboard edit-mode grab is input-agnostic: Return grabs, Down steps, Return drops",
			},
			gamepad = {
				"gamepad ButtonA selects the focused row (through presenter Activate dispatch)",
				"gamepad edit-mode: ButtonA grabs, DPadDown steps the row, ButtonA drops",
				"gamepad ButtonA SELECTS the column; the stick then acts on it (sort on Up/Down)",
			},
		},
		-- PARADIGM axis (matrix §B-Table). pointer = direct-drag with no grip +
		-- wheel as a separate channel; touch = naked-pan-scrolls + edit-mode ≡
		-- handle reorder; keyboard/gamepad = grab-mode reorder + focus-gated
		-- Adjust column-resize (the closed GAP, matrix Amendments). hotSwitch =
		-- the §C in-flight rows Table owns: drag/grab CANCEL on capability loss,
		-- edit-mode / grab / pan CARRY across a live-set flip.
		affordanceProofs = {
			pointer = {
				"dragging a selected row drags the WHOLE selection as a block (director example)",
				"the body is a native scroll region: it declares the full content canvas and clips",
			},
			touch = {
				"auto Edit/Done toggle: shown for touch input, hidden for mouse, toggles the handles",
				"a touch drag on the row body defers to the native scroll and never reorders",
				"edit mode grows a trailing handle per row; a TOUCH drag on the handle reorders",
			},
			keyboard = {
				"keyboard edit-mode grab is input-agnostic: Return grabs, Down steps, Return drops",
				"keyboard Comma/Period on the focused grip resize the column by the step",
			},
			gamepad = {
				"gamepad edit-mode: ButtonA grabs, DPadDown steps the row, ButtonA drops",
				"gamepad ButtonL1/ButtonR1 on the focused grip resize the column",
				"a Thumbstick1 y push moves focus down like DPadDown, with the latch",
			},
			hotSwitch = {
				"pointer drag mid-flight + pointer capability lost => CANCEL, revert, no reorder",
				"gamepad grab mid-grab + gamepad capability lost => CANCEL, order reverts, grab cleared",
				"CARRY: edit-mode persists while gamepad stays live after touch leaves",
				"CARRY: a grabbed row keeps following Navigate when a pointer arrives (gamepad stays live)",
				"CARRY: native scroll position survives a class flip",
			},
		},
	},
	{
		name = "VirtualList",
		kind = "composite",
		module = "src/controls/virtual_list.luau",
		export = "newVirtualList",
		spec = "tests/virtualization.spec.luau",
		conformance = "tests/virtualization.spec.luau",
		docsAnchor = "newVirtualList",
		dumpFunction = "function list.dump",
		inputProofs = {
			pointer = {
				"VirtualList pointer: an engine scroll (driveScroll) slides the window",
				"VirtualList pointer: a row tap activates through auto handleActivate",
			},
			touch = {
				"VirtualList touch: a native pan scroll slides the window (driveScroll)",
				"VirtualList touch: a row tap activates",
			},
			keyboard = {
				"VirtualList keyboard: Up/Down moves focus row-by-row through the window",
				"VirtualList keyboard: Return activates the focused row",
			},
			gamepad = {
				"VirtualList gamepad: D-pad moves focus identically to arrows",
				"VirtualList gamepad: ButtonA activates the focused row",
			},
		},
		-- PARADIGM axis (matrix §B-VirtualList). pointer/touch = the NATIVE
		-- ScrollingFrame owns scroll (wheel/pan/momentum); the mirror slides the
		-- window and a scroll never activates. keyboard/gamepad = windowed focus
		-- ring with keep-visible scroll-into-view; gamepad tolerates the
		-- D-pad-as-Thumbstick1 axis. VirtualList advertises NO reorder/grab
		-- (ADR-0013): its only live state is the engine-owned scroll position, pure
		-- presentation that inherently survives any flip — no in-flight GESTURE, so
		-- hotSwitch = false.
		affordanceProofs = {
			pointer = { "VirtualList pointer: an engine scroll (driveScroll) slides the window" },
			touch = { "VirtualList touch: a native pan scroll slides the window (driveScroll)" },
			keyboard = { "VirtualList keyboard: Up/Down moves focus row-by-row through the window" },
			gamepad = {
				"VirtualList gamepad: D-pad moves focus identically to arrows",
				"a Thumbstick1 y push moves focus down like DPadDown, with the latch",
			},
			hotSwitch = false,
		},
	},
	{
		name = "PopupButton",
		kind = "composite",
		module = "src/controls/popup_button.luau",
		export = "newPopupButton",
		spec = "tests/popup_button.spec.luau",
		conformance = "tests/popup_button.spec.luau",
		docsAnchor = "newPopupButton",
		dumpFunction = "function dump",
		inputProofs = {
			pointer = {
				"tapping the trigger opens the popup listing every option",
				"activating an option selects it, fires onChange, closes, and relabels",
			},
			touch = {
				"a TOUCH-typed tap on the trigger opens the popup listing every option",
			},
			keyboard = {
				"keyboard opens, navigates the options, and Activate selects",
			},
			gamepad = {
				"gamepad ButtonA drives the same open+select path",
			},
		},
		-- PARADIGM axis (matrix §B-PopupButton; parity GAPs closed by the new
		-- handleCancel/outsideDismiss/transientScope seams). pointer/touch = tap
		-- opens the panel + tap-away (outside-tap / synthesized catcher)
		-- dismisses without changing selection; keyboard = open rows are focus-
		-- ring Buttons; gamepad = ButtonB Cancel closes and focus is trapped
		-- within the open panel. The open surface is transient, not a gesture the
		-- control snapshots and reverts — dismissal converges non-destructively
		-- through the seams (not an in-flight hot-switch), so hotSwitch = false.
		affordanceProofs = {
			pointer = {
				"tapping the trigger opens the popup listing every option",
				"a tap on a rendered node OUTSIDE the open panel dismisses it (no selection change)",
			},
			touch = {
				"a TOUCH-typed tap on the trigger opens the popup listing every option",
				"the synthesized catcher dismisses on a tap in EMPTY space (Zone B geometry)",
			},
			keyboard = {
				"keyboard opens, navigates the options, and Activate selects",
			},
			gamepad = {
				"gamepad ButtonB while open closes the popup (no selection change)",
				"gamepad Navigate cannot ESCAPE the open popup into a sibling (focus trap)",
			},
			hotSwitch = false,
		},
	},
	{
		name = "TextInput",
		kind = "composite",
		module = "src/controls/text_input.luau",
		export = "newTextInput",
		spec = "tests/text_input.spec.luau",
		conformance = "tests/text_input.spec.luau",
		docsAnchor = "newTextInput",
		dumpFunction = "function dump",
		inputProofs = {
			pointer = {
				"tapping the field enters editing (the control-owned handshake)",
			},
			touch = {
				"a touch tap enters editing and the occlusion keep-visible engages (touch story end to end)",
			},
			keyboard = {
				"focused field + Activate (Return) enters editing",
				"Enter commits, editing ends, and navigation works again (probe fires post-edit)",
				"Tab commits through the field's own path and only THEN advances focus",
			},
			gamepad = {
				"ButtonA enters editing; D-pad does not navigate; ButtonB cancels reverting to the snapshot",
				"ButtonA re-enters editing after a cancel",
			},
		},
		-- PARADIGM axis (matrix §B-TextInput). pointer/touch = tap enters the
		-- control-owned editing handshake; touch also summons the OSK and the
		-- keep-visible offset engages so it never occludes; keyboard/gamepad =
		-- editing raises a SINKING text-entry context (typing stops being
		-- Navigate) and ButtonB cancels to the snapshot. hotSwitch = the §C text-
		-- entry rows TextInput owns: a device arriving mid-edit CARRIES; the
		-- editing surface (OSK) leaving CANCELs via commit — never a wedge, never
		-- lost text.
		affordanceProofs = {
			pointer = { "tapping the field enters editing (the control-owned handshake)" },
			touch = { "a touch tap enters editing and the occlusion keep-visible engages (touch story end to end)" },
			-- keyboard PARADIGM: while editing, typing wins — Space types, the
			-- arrows stay with the field's sinking context, and Tab is the
			-- documented way OUT (commit through validation, then advance)
			keyboard = {
				"Enter commits, editing ends, and navigation works again (probe fires post-edit)",
				"Space does not activate anything while the field is editing",
				"the arrows stay with the field's own sinking context while editing",
			},
			gamepad = { "ButtonA enters editing; D-pad does not navigate; ButtonB cancels reverting to the snapshot" },
			hotSwitch = {
				"a gamepad arriving mid-edit CARRIES the edit (editing stays, text intact)",
				"touch leaving mid-edit CARRIES while a hardware keyboard stays live (keyboard supersedes the OSK)",
				"touch (the on-screen-keyboard surface) leaving mid-edit ends the edit via commit (no wedge)",
				"after the editing-surface loss the sink context comes down and navigation resumes",
			},
		},
	},
	{
		-- the shared value arithmetic behind the value-control family. Not a
		-- control (it renders nothing and has no input surface), but it lives under
		-- src/controls/ so the checker requires a row — declared explicitly rather
		-- than silently exempted.
		name = "ValueModel",
		kind = "composite",
		module = "src/controls/value_model.luau",
		export = "valueModel",
		spec = "tests/value_controls.spec.luau",
		conformance = "tests/value_controls.spec.luau",
		docsAnchor = "valueModel",
		-- STATELESS MODULE: value_model has no instance and no live state to
		-- summarize — `new(spec)` returns a pure stepped model whose whole state is
		-- its arguments. Nothing to dump, said explicitly.
		dump = false,
		reason = "stateless module: pure value arithmetic, no instance state to summarize",
		inputProofs = false,
		affordanceProofs = false,
	},
	{
		name = "ProgressView",
		kind = "composite",
		module = "src/controls/progress_view.luau",
		export = "newProgressView",
		spec = "tests/display_controls.spec.luau",
		conformance = "tests/display_controls.spec.luau",
		docsAnchor = "newProgressView",
		dumpFunction = "function api.dump",
		-- NON-INTERACTIVE: progress reports, it does not accept input. Declared
		-- explicitly rather than being silently absent from conformance.
		inputProofs = false,
		affordanceProofs = false,
	},
	{
		name = "Label",
		kind = "composite",
		module = "src/controls/label.luau",
		export = "newLabel",
		spec = "tests/display_controls.spec.luau",
		conformance = "tests/display_controls.spec.luau",
		docsAnchor = "newLabel",
		dumpFunction = "function api.dump",
		-- NON-INTERACTIVE: a Label displays. Put it inside a Button (which takes
		-- content) when it must be pressable — that keeps ONE activation surface.
		inputProofs = false,
		affordanceProofs = false,
	},
	{
		name = "Picker",
		kind = "composite",
		module = "src/controls/picker.luau",
		export = "newPicker",
		spec = "tests/display_controls.spec.luau",
		conformance = "tests/display_controls.spec.luau",
		docsAnchor = "newPicker",
		dumpFunction = "function api.dump",
		inputProofs = {
			pointer = { "pointer: tapping an option selects it and reports through onChange" },
			touch = { "touch: a finger tap selects identically, and every row meets the floor" },
			keyboard = { "keyboard and gamepad select through the same path" },
			gamepad = { "keyboard and gamepad select through the same path" },
		},
		-- PARADIGM: every option is a focusable Button, so the idioms come from the
		-- primitive; what is Picker-specific is the ADAPTIVE presentation, which keys
		-- on option count and space class — never a device name. hotSwitch = false:
		-- selection is atomic, so there is no in-flight state to carry or cancel.
		affordanceProofs = {
			pointer = { "segmented lays options along x; inline stacks them along y" },
			touch = { "touch: a finger tap selects identically, and every row meets the floor" },
			keyboard = { "selection rides the `selected` style binding, never a bespoke fill" },
			gamepad = { "a live size-class change flips the presentation WITHOUT remounting the options" },
			hotSwitch = false,
		},
	},
	{
		name = "DisclosureGroup",
		kind = "composite",
		module = "src/controls/disclosure_group.luau",
		export = "newDisclosureGroup",
		spec = "tests/display_controls.spec.luau",
		conformance = "tests/display_controls.spec.luau",
		docsAnchor = "newDisclosureGroup",
		dumpFunction = "function api.dump",
		inputProofs = {
			pointer = { "expanding mounts the content; collapsing unmounts it" },
			touch = { "touch: a finger tap toggles it, and the header meets the floor" },
			keyboard = { "keyboard and gamepad toggle it through the same path" },
			gamepad = { "keyboard and gamepad toggle it through the same path" },
		},
		-- PARADIGM: the header is the control on every class. The row the plan
		-- singles out is FOCUS — collapsing while focus sits inside the content must
		-- move focus back to the header BEFORE the content unmounts, or focus is left
		-- on a node that no longer exists. hotSwitch = false: the toggle is atomic.
		affordanceProofs = {
			pointer = { "expanding mounts the content; collapsing unmounts it" },
			touch = { "touch: a finger tap toggles it, and the header meets the floor" },
			keyboard = { "collapsing with focus INSIDE the content moves focus back to the header first" },
			gamepad = { "expanding leaves focus on the header (the player asked to SEE the content)" },
			hotSwitch = false,
		},
	},
	{
		name = "Slider",
		kind = "composite",
		module = "src/controls/slider.luau",
		export = "newSlider",
		spec = "tests/value_controls.spec.luau",
		conformance = "tests/value_controls.spec.luau",
		docsAnchor = "newSlider",
		dumpFunction = "function api.dump",
		-- REACHABILITY: pointer/touch drag or tap the track; keyboard and gamepad
		-- reach the same arithmetic through the focus-gated Adjust verb.
		inputProofs = {
			pointer = { "pointer: tap-to-position jumps to the tapped fraction" },
			touch = { "touch: a touch-typed drag drives it identically" },
			keyboard = {
				"keyboard: Adjust steps predictably rather than requiring a drag",
				"Left/Right adjust a focused horizontal Slider on a GROUPED screen",
			},
			gamepad = { "gamepad: the bumpers Adjust the focused slider" },
		},
		-- PARADIGM: pointer = direct drag on the track (native UIDragDetector, with
		-- the Grip capture path as the corrections-mandated fallback) plus
		-- tap-to-position; touch = the same drag against the enforced 44px floor;
		-- keyboard/gamepad = predictable Adjust increments rather than a mandatory
		-- continuous thumbstick. hotSwitch = CANCEL: a Slider DOES hold in-flight
		-- state, so losing the pointer class mid-drag reverts to the pre-drag
		-- snapshot instead of committing a value the player did not choose.
		affordanceProofs = {
			pointer = { "a native drag moves the value and commits on end" },
			touch = { "the track meets the effective-target floor" },
			keyboard = { "stays inside its bounds from every route" },
			gamepad = { "gamepad: the bumpers Adjust the focused slider" },
			hotSwitch = {
				"Slider hot-switch: losing the pointer class mid-drag CANCELS back to the snapshot",
				"a cancelled capture also reverts (the adapter's own cancel path)",
			},
		},
	},
	{
		name = "Stepper",
		kind = "composite",
		module = "src/controls/stepper.luau",
		export = "newStepper",
		spec = "tests/value_controls.spec.luau",
		conformance = "tests/value_controls.spec.luau",
		docsAnchor = "newStepper",
		dumpFunction = "function api.dump",
		-- REACHABILITY: pointer/touch hit the two Buttons; keyboard and gamepad
		-- reach the SAME arithmetic through the focus-gated Adjust verb.
		inputProofs = {
			pointer = { "pointer: tapping plus and minus steps the owner's value" },
			touch = { "touch: a finger tap on + steps it identically" },
			keyboard = {
				"keyboard: Adjust on the focused control steps without touching a button",
				"Space on the focused button steps the value, in both directions",
				"the axis-independent Adjust keys still reach the same arithmetic",
			},
			gamepad = { "gamepad: ButtonA on the focused + activates, and the bumpers Adjust" },
		},
		-- PARADIGM: pointer = discrete press affordances (no drag); touch = the
		-- enforced 44px floor on both buttons; keyboard = focus then Adjust, bound
		-- ONLY while focus is inside the control; gamepad = the same via bumpers.
		-- hotSwitch = false: each press is atomic, so the control holds NO
		-- in-flight state a live class flip could strand.
		affordanceProofs = {
			pointer = { "the affordance at a bound is DISABLED, not silently inert" },
			touch = { "touch: a finger tap on + steps it identically" },
			keyboard = {
				"no Adjust key is bound while focus sits outside the Stepper (no gameplay bumper shadow)",
			},
			gamepad = { "gamepad: ButtonA on the focused + activates, and the bumpers Adjust" },
			hotSwitch = false,
		},
	},
	{
		name = "Rating",
		kind = "composite",
		module = "src/controls/rating.luau",
		export = "newRating",
		spec = "tests/rating.spec.luau",
		conformance = "tests/rating.spec.luau",
		docsAnchor = "newRating",
		dumpFunction = "function api.dump",
		-- REACHABILITY: pointer/touch land on the ONE Grip that covers the run of
		-- glyphs (tap to set, drag to scrub); keyboard and gamepad reach the SAME
		-- arithmetic through the focus-gated Adjust verb, at ONE focus stop for
		-- the whole control rather than one per star.
		inputProofs = {
			pointer = { "pointer: clicking a star sets the rating to that star" },
			touch = { "touch: a finger drag across the strip scrubs the value live" },
			keyboard = { "keyboard: Adjust on the focused strip rates without touching a star" },
			gamepad = { "gamepad: the bumpers Adjust the focused rating" },
		},
		-- PARADIGM: pointer = direct tap plus scrub; touch = the same gesture
		-- against the Grip's enforced 44px floor; keyboard = focus then Adjust,
		-- bound ONLY while focus is inside the control; gamepad = the same via
		-- bumpers. hotSwitch = TRUE: a scrub IS in-flight state, and the decision
		-- is CANCEL — losing the pointer class mid-drag reverts to the pre-scrub
		-- value, so a half-finished drag never commits a rating nobody chose.
		affordanceProofs = {
			pointer = { "pointer: clicking a star sets the rating to that star" },
			touch = { "touch: a finger drag across the strip scrubs the value live" },
			keyboard = {
				"no Adjust key is bound while focus sits outside the Rating (no gameplay bumper shadow)",
			},
			gamepad = { "gamepad: the bumpers Adjust the focused rating" },
			hotSwitch = { "hotSwitch: losing the pointer mid-scrub CANCELS back, it never commits" },
		},
	},
	{
		name = "Chip",
		kind = "composite",
		module = "src/controls/chip.luau",
		export = "newChip",
		spec = "tests/chip.spec.luau",
		conformance = "tests/chip.spec.luau",
		docsAnchor = "newChip",
		dumpFunction = "function dump",
		-- Four-input proofs (ui_todo §0): each case name must exist VERBATIM in a
		-- registered spec. These cite the four stamped cases in tests/chip.spec.luau
		-- (they FAIL until you implement them — that is the red step).
		inputProofs = {
			pointer = { "Chip pointer: a tap activates through the presenter (device-true)" },
			touch = { "Chip touch: a touch tap/pan drives the control (device-true)" },
			keyboard = { "Chip keyboard: focus + Return drives the control" },
			gamepad = { "Chip gamepad: focus + ButtonA drives the control" },
		},
		-- Paradigm-axis proofs (UI-PARADIGM-001/002): the STRUCTURAL IDIOM per
		-- live class (distinct from inputProofs' reachability) plus the hotSwitch
		-- decision. These cite the four affordance cases + the hot-switch stub in
		-- tests/chip.spec.luau. If your control owns no in-flight state, set
		-- hotSwitch = false and delete the stamped hot-switch spec case.
		affordanceProofs = {
			pointer = { "Chip pointer affordance: the pointer structural idiom (hover/direct-drag/wheel)" },
			touch = { "Chip touch affordance: the touch structural idiom (44px/naked-pan-scroll/edit-grip)" },
			keyboard = {
				"Chip keyboard affordance: the keyboard structural idiom (focus ring/Navigate/Activate/Adjust)",
			},
			gamepad = { "Chip gamepad affordance: the gamepad structural idiom (focus/grab/A-B/ten-foot)" },
			-- a Chip owns NO in-flight state (no drag/grab/open edit): a mid-gesture
			-- class flip has nothing to carry or cancel, so hotSwitch = false.
			hotSwitch = false,
		},
	},
	{
		-- pure shape math for UI.Path (native-substrate NS-A7): NOT a control —
		-- no input surface, no focus role, no affordances. It exists in
		-- src/controls because consumers reach for it beside the composites.
		-- The UI.Path leaf itself is registered below with the non-interactive
		-- primitives; the engine stroke is proven by the 'path_ring' Studio
		-- scenario (artifacts/native-substrate/a7-path.json).
		name = "PathShapes",
		kind = "composite",
		module = "src/controls/path_shapes.luau",
		export = "pathShapes",
		spec = "tests/path.spec.luau",
		conformance = "tests/path.spec.luau",
		docsAnchor = "pathShapes",
		-- STATELESS MODULE: pure shape math, no instance, no live state.
		dump = false,
		reason = "stateless module: pure shape math for UI.Path, no instance state to summarize",
		inputProofs = false,
		affordanceProofs = false,
	},
	{
		-- AsyncImage (native-substrate NS-A14): provider-driven image with
		-- placeholder/ready/failed visuals. NON-INTERACTIVE presentation — no
		-- input surface, no focus role, no affordances; the provider handle is
		-- scope-owned and release semantics are the honest-cancellation rule.
		name = "AsyncImage",
		kind = "composite",
		module = "src/controls/async_image.luau",
		export = "newAsyncImage",
		spec = "tests/async_image.spec.luau",
		conformance = "tests/async_image.spec.luau",
		docsAnchor = "newAsyncImage",
		-- CALLER-SCOPE SHAPE (EXC E-8): newAsyncImage owns nothing of its own — its
		-- provider handle and resources live in the CALLER's scope and die with it,
		-- which is why it has no dispose() either. There is no object here to hold a
		-- dump surface; the state a bug report needs is the provider's.
		dump = false,
		reason = "caller-scope shape (E-8): resources live in the owner's scope, so the control holds no instance state and exposes no dispose()",
		inputProofs = false,
		affordanceProofs = false,
	},
	{
		-- RowActions (row-actions Task 3: composite skeleton, static reveal).
		-- A closed row (no actions revealed) is a TRUE inert passthrough — the
		-- wrapped `content` mounts unwrapped, with no RowActions node at all —
		-- but the moment either edge declares actions, the control attaches its
		-- OWN input contribution (contribution.attach + a routed handleActivate,
		-- mirroring popup_button.luau's api.handleActivate) to dispatch a tap/
		-- Return/ButtonA on a revealed `Action:<id>` tray button, which makes it
		-- an INTERACTIVE control by the checker's own rule (module source
		-- contains "contribution.attach"). This task ships NO drag/swipe/pointer
		-- gesture (Step 3 of the plan is the skeleton only) — every case below
		-- reaches a tray action through the STANDARD UI.Button activation path
		-- (adapter.tap / system.deviceKey against a pre-revealed tray), which is
		-- the honest reachability/paradigm story for what this task built.
		-- Tasks 5-8 add the swipe gesture itself (mouse/touch/keyboard-Delete/
		-- gamepad) and MUST revisit this row: hotSwitch = false is accurate
		-- today (no in-flight state exists yet) but will not be once a drag
		-- owns one.
		name = "RowActions",
		kind = "composite",
		module = "src/controls/row_actions.luau",
		export = "newRowActions",
		spec = "tests/row_actions.spec.luau",
		conformance = "tests/row_actions.spec.luau",
		docsAnchor = "newRowActions",
		dumpFunction = "function dump",
		inputProofs = {
			pointer = { "RowActions pointer: a tap on a revealed tray action activates it (device-true)" },
			touch = { "RowActions touch: a touch tap on a revealed tray action activates it (device-true)" },
			keyboard = { "RowActions keyboard: focus + Return activates a revealed tray action" },
			gamepad = { "RowActions gamepad: focus + ButtonA activates a revealed tray action" },
		},
		affordanceProofs = {
			pointer = {
				"RowActions pointer affordance: the pointer structural idiom (hover on a revealed tray action)",
			},
			touch = {
				"RowActions touch affordance: the touch structural idiom (44px floor on a revealed tray action)",
			},
			keyboard = {
				"RowActions keyboard affordance: the keyboard structural idiom (focus ring/Navigate/Activate)",
			},
			gamepad = {
				"RowActions gamepad affordance: the gamepad structural idiom (ten-foot focus on a revealed tray action)",
			},
			-- no in-flight gesture state exists as of this task (no pointer
			-- handling shipped) — nothing for a mid-gesture class flip to carry
			-- or cancel yet. Tasks 5-8 own turning this into a real §C list.
			hotSwitch = false,
		},
	},
	-- scaffold: new control rows are appended above this line (anchor — keep)

	-- ===== leaf primitives (src/controls/contract.luau classes) =========
	-- INTERACTIVE leaves. Button/Toggle proofs live in tests/auto_input.spec.luau
	-- (the presenter auto-wires their four-input story with zero consumer opts);
	-- TextField's proofs live in the TextInput composite's spec, since TextField
	-- is the text-entry leaf TextInput drives (ui_todo §1).
	{
		name = "Button",
		kind = "leaf",
		inputProofs = {
			pointer = { "pointer tap activates the Button through its onActivate prop" },
			touch = { "Button touch: a finger tap activates through the auto dispatch" },
			keyboard = {
				"keyboard Return activates the focused Button",
				"Space activates the focused control exactly once",
				"Tab and Shift+Tab move the focus ring through a plain form",
			},
			gamepad = { "gamepad ButtonA activates the focused Button" },
		},
		-- PARADIGM axis (matrix §B-Button). pointer = the free hover PREVIEW
		-- layer (the paradigm channel reachability lacks — gated on the live
		-- pointer class, matrix hover Amendment); touch = finger tap through the
		-- auto dispatch (44px floor); keyboard = focus ring + Return; gamepad =
		-- focus + A and a STRENGTHENED focus state at ten-foot (scale + thicker
		-- ring, matrix D.4). No in-flight state → hotSwitch = false.
		affordanceProofs = {
			pointer = {
				"a pointer-live renderer enables hover on interactive nodes and synthetic hover flips their state",
				"the default style defines a hover role distinct from the control rest fill",
			},
			touch = { "Button touch: a finger tap activates through the auto dispatch" },
			-- keyboard PARADIGM (roadmap Step 8): the desktop shape is the focus
			-- CHAIN — Tab/Shift+Tab walk it, Space activates like Return, and both
			-- keys exist only while a keyboard is live and the responder is engaged
			keyboard = {
				"keyboard Return activates the focused Button",
				"Tab and Shift+Tab move the focus ring through a plain form",
				"a PASSIVE HUD binds no Tab and no Space: gameplay is untouched",
			},
			gamepad = {
				"gamepad ButtonA activates the focused Button",
				"focus visuals differ between a Large display and a Medium display",
			},
			hotSwitch = false,
		},
	},
	{
		name = "Toggle",
		kind = "leaf",
		inputProofs = {
			pointer = { "pointer tap flips the value" },
			touch = { "Toggle touch: a finger tap flips the value" },
			keyboard = { "focused Activate (Return) flips the value" },
			gamepad = { "Toggle gamepad: ButtonA on the focused Toggle flips the value" },
		},
		-- PARADIGM axis (matrix §B-Toggle): same profile as Button — hover
		-- preview on pointer, 44px finger flip on touch, focus ring on keyboard,
		-- and ten-foot focus strengthening on gamepad. No in-flight state.
		affordanceProofs = {
			pointer = {
				"a pointer-live renderer enables hover on interactive nodes and synthetic hover flips their state",
				"the default style defines a hover role distinct from the control rest fill",
			},
			touch = { "Toggle touch: a finger tap flips the value" },
			keyboard = { "focused Activate (Return) flips the value" },
			gamepad = {
				"Toggle gamepad: ButtonA on the focused Toggle flips the value",
				"focus visuals differ between a Large display and a Medium display",
			},
			hotSwitch = false,
		},
	},
	{
		name = "TextField",
		kind = "leaf",
		inputProofs = {
			pointer = { "tapping the field enters editing (the control-owned handshake)" },
			touch = {
				"a touch tap enters editing and the occlusion keep-visible engages (touch story end to end)",
			},
			keyboard = { "focused field + Activate (Return) enters editing" },
			gamepad = {
				"ButtonA enters editing; D-pad does not navigate; ButtonB cancels reverting to the snapshot",
			},
		},
		-- PARADIGM axis: TextField is the text-entry leaf TextInput drives, so its
		-- structural idioms and in-flight edit state ARE TextInput's (registry
		-- note) — same OSK/keep-visible on touch, sinking context + ButtonB
		-- cancel on keyboard/gamepad, and the §C text-entry hot-switch rows.
		affordanceProofs = {
			pointer = { "tapping the field enters editing (the control-owned handshake)" },
			touch = { "a touch tap enters editing and the occlusion keep-visible engages (touch story end to end)" },
			keyboard = { "Enter commits, editing ends, and navigation works again (probe fires post-edit)" },
			gamepad = { "ButtonA enters editing; D-pad does not navigate; ButtonB cancels reverting to the snapshot" },
			hotSwitch = {
				"a gamepad arriving mid-edit CARRIES the edit (editing stays, text intact)",
				"touch (the on-screen-keyboard surface) leaving mid-edit ends the edit via commit (no wedge)",
			},
		},
	},
	-- NON-INTERACTIVE leaves: layout/containers, Text, Image, Spacer, Box, and
	-- ScrollView (its "Scroll" contract action is a pointer-wheel / touch-pan
	-- GESTURE, not a focus/Activate surface — focusRole="none"; see the
	-- ScrollView note in check_registration's interactivity gate).
	{ name = "Screen", kind = "leaf", inputProofs = false, affordanceProofs = false },
	{ name = "VStack", kind = "leaf", inputProofs = false, affordanceProofs = false },
	{ name = "HStack", kind = "leaf", inputProofs = false, affordanceProofs = false },
	{ name = "ZStack", kind = "leaf", inputProofs = false, affordanceProofs = false },
	{ name = "ScrollView", kind = "leaf", inputProofs = false, affordanceProofs = false },
	{ name = "Spacer", kind = "leaf", inputProofs = false, affordanceProofs = false },
	{ name = "Box", kind = "leaf", inputProofs = false, affordanceProofs = false },
	-- Path (native-substrate NS-A7): stroked Path2D leaf — pure presentation
	-- (progress rings/needles); no input surface, color via style role hint
	{ name = "Path", kind = "leaf", inputProofs = false, affordanceProofs = false },
	{ name = "Text", kind = "leaf", inputProofs = false, affordanceProofs = false },
	{ name = "Image", kind = "leaf", inputProofs = false, affordanceProofs = false },
	{ name = "Anchor", kind = "leaf", inputProofs = false, affordanceProofs = false },
	{ name = "Grid", kind = "leaf", inputProofs = false, affordanceProofs = false },
	-- adaptive layout (A-AL2) and the axis-aware hairline (A-LV3): both are
	-- layout/presentation only — no focus surface, no semantic action
	{ name = "AdaptiveStack", kind = "leaf", inputProofs = false, affordanceProofs = false },
	{ name = "ViewThatFits", kind = "leaf", inputProofs = false, affordanceProofs = false },
	-- declared-content adaptive composition (ADR-0023): the screen-level sibling
	-- of the two above. Layout/presentation only — no focus surface of its own,
	-- no semantic action; what it OWES focus is the exclusion guarantee, which is
	-- ViewThatFits' `hidden` mechanism at composition scale
	{ name = "Composition", kind = "leaf", inputProofs = false, affordanceProofs = false },
	{ name = "Region", kind = "leaf", inputProofs = false, affordanceProofs = false },
	{ name = "Divider", kind = "leaf", inputProofs = false, affordanceProofs = false },
	-- structural regions (§5.4): mount-layer control flow, no rendered surface
	{ name = "When", kind = "leaf", inputProofs = false, affordanceProofs = false },
	{ name = "ForEach", kind = "leaf", inputProofs = false, affordanceProofs = false },
	{ name = "ErrorBoundary", kind = "leaf", inputProofs = false, affordanceProofs = false },
	-- Grip: the INTERACTIVE primitive Milestone 0 pulled into the registry. It
	-- is opt-in focusable and carries capture-based pointer routing, so it owes
	-- the full four-input + paradigm story like any other control. Its
	-- device-true cases live in the Table specs, which is where the only
	-- production Grip (column resize) is exercised end to end.
	{
		name = "Grip",
		kind = "leaf",
		inputProofs = {
			pointer = {
				"pointer capture: down on a grip routes moves and up to it, with rects",
				"grip drag previews a guide line and commits the width on release",
			},
			touch = {
				"a TOUCH drag on the grip previews and commits the new column width",
			},
			keyboard = {
				"keyboard Comma/Period on the focused grip resize the column by the step",
			},
			gamepad = {
				"gamepad ButtonL1/ButtonR1 on the focused grip resize the column",
			},
		},
		-- PARADIGM axis: pointer = direct capture-drag plus a live MouseIcon
		-- hint that survives leaving the zone; touch = the same drag against the
		-- declared 44px floor; keyboard/gamepad = the focus-gated Adjust verb
		-- (bound ONLY while focus sits on the grip, so a bare screen never
		-- shadows gameplay keys) reached through the auto navigation group.
		-- hotSwitch: a captured grip drag IS in-flight state; Table owns the
		-- §C transition rows for it (CANCEL on capability loss).
		affordanceProofs = {
			pointer = {
				"cursor hint persists across a captured drag even off the grip",
				"a Grip renders as a non-button node and hover requests its cursor hint",
			},
			touch = { "a TOUCH grip drag clamps to the column minWidth" },
			keyboard = { "no Adjust key is bound while focus sits off a RESIZABLE column (no bumper shadow)" },
			gamepad = { "the headers group walks ONE stop per column (the column handle)" },
			hotSwitch = {
				"pointer drag mid-flight + pointer capability lost => CANCEL, revert, no reorder",
			},
		},
	},
}

return registry
