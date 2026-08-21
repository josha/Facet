--!strict
-- Composite-control registry (design §17 Phase 4 agentic maintainability;
-- UI-AGENT-001). ONE row per control class: every composite under src/controls/
-- (the contract module excepted) AND every leaf primitive declared in
-- src/class_contract.luau. tools/lune/check_registration fails the gate when
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
		export = "Controls.Table",
		spec = "tests/table.spec.luau",
		conformance = "tests/controls_conformance.spec.luau",
		docsAnchor = "newTable",
		dumpFunction = "function dump",
		-- pointer (mouse) proofs are device-true cases in table.spec.luau;
		-- tests/table_input.spec.luau owns the touch/keyboard/gamepad device-true
		-- cases (not the api-direct ones).
		--
		-- Task 10 (row-actions): `spec.rowActions` is a NEW interactive surface
		-- on Table, composed against the SAME device-true idioms above rather
		-- than a parallel proof set — reorder-vs-swipe axis arbitration is a
		-- pointer-class question (the mouse citation below), and the row's own
		-- keyboard Delete rides row_actions.luau's OWN device-true suite
		-- (registered separately) once Table wires focus/action-system through
		-- it, proven end-to-end through a Table mount by the keyboard citation.
		--
		-- `onPrimaryAction` (parity round 2 §3.4) is a SECOND interactive verb on
		-- the same rows — "open this", as distinct from "select this" — so it
		-- carries its own device-true case in every one of the four classes.
		-- Touch follows Apple's documented model rather than the pointer one: a
		-- plain SINGLE TAP activates, and EDIT MODE is the touch selection mode
		-- (`contextMenu(forSelectionType:menu:primaryAction:)` + `EditMode`; a
		-- double-TAP is documented as ZOOM and was never a candidate). All THREE
		-- halves are cited below — the tap case is the activation reachability
		-- proof, the edit-mode case is the price and the escape, and the third is
		-- the proof that the escape is REACHABLE on the table shape that has no
		-- other reason to offer it (selectable + primary action + NOT reorderable:
		-- the auto Edit/Done toggle used to appear for `reorderable` alone, which
		-- left touch SELECTION unreachable on exactly that shape, 2026-08-13). A
		-- capability whose only route is edit mode is not proven by a case that
		-- reaches edit mode for an unrelated reason, so the edit-mode case above it
		-- does not stand in for this one. The rule is written down in table.luau
		-- beside the dispatch and beside the toggle predicate.
		inputProofs = {
			pointer = {
				"header taps cycle the owner-held sortOrder; the table never sorts the data",
				"dragging a selected row drags the WHOLE selection as a block (director example)",
				"mouse horizontal drag on the same reorderable + wrapped row reveals actions instead of reordering",
				"Table pointer: a double-click on a row fires onPrimaryAction once, and a single click never does",
				"Table pointer: two clicks SLOWER than the window are two single clicks, not an open",
			},
			touch = {
				"a TOUCH drag on the grip previews and commits the new column width",
				"a TOUCH grip drag clamps to the column minWidth",
				"Table touch: a plain single tap on a row activates it — the first tap, on any row",
				"Table touch: EDIT MODE is the selection mode — tap toggles selection (multi's DESELECT is back) and never opens",
				'Table touch: with selection = "none" a single tap opens, exactly as it does in every other mode',
				"Table touch: a selectable NON-reorderable table with a primary action can still be put into edit mode, so touch can select at all",
				-- ...and the OTHER edit-mode shape the same widening created: no
				-- selection to make, so the tap must still open (redteam item 6).
				'Table touch: a selection = "none" reorderable table still OPENS a row while editing',
			},
			keyboard = {
				"keyboard Down + Return select the focused row",
				"keyboard Right/Return drive the header sort identically to the gamepad",
				"keyboard edit-mode grab is input-agnostic: Return grabs, Down steps, Return drops",
				"Delete key on a focused row deletes via the row's destructive action",
				"Table keyboard: Return on the focused row fires onPrimaryAction for THAT row",
				-- ...INCLUDING while edit mode is on, on the shape that cannot
				-- reorder. Widening the toggle put those tables into edit mode for
				-- the first time and the grab branch then swallowed every device
				-- Activate they had (redteam item 3): the four-input bar broken by
				-- the very change made to satisfy it, so both device classes carry
				-- their own citation for it rather than sharing one.
				"Table keyboard: in edit mode a NON-reorderable table still opens rows — Return is not swallowed by a grab it cannot do",
			},
			gamepad = {
				"gamepad ButtonA selects the focused row (through presenter Activate dispatch)",
				"gamepad edit-mode: ButtonA grabs, DPadDown steps the row, ButtonA drops",
				"gamepad ButtonA SELECTS the column; the stick then acts on it (sort on Up/Down)",
				"Table gamepad: ButtonA on the focused row fires onPrimaryAction for THAT row",
				"Table gamepad: in edit mode a NON-reorderable table still opens rows — ButtonA is not swallowed by a grab it cannot do",
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
		export = "Controls.VirtualList",
		spec = "tests/virtualization.spec.luau",
		conformance = "tests/virtualization.spec.luau",
		docsAnchor = "newVirtualList",
		dumpFunction = "function list.dump",
		--[[ TWO AXES, BOTH PROVEN ON ALL FOUR CLASSES. `axis = "x"` (parity round 2
			§2.3) is new interactive behaviour — it changes which engine coordinate
			every scroll write lands on and which direction the focus group walks —
			so it carries its own four-input proof rather than inheriting the
			vertical one. The horizontal cases live in
			`tests/virtual_list_axis.spec.luau`; the vertical ones stay where they
			were. A regression that transposed only ONE of the two would redden
			exactly one column here. ]]
		inputProofs = {
			pointer = {
				"VirtualList pointer: an engine scroll (driveScroll) slides the window",
				"VirtualList pointer: a row tap activates through auto handleActivate",
				"VirtualList pointer: a horizontal engine scroll slides the window along x",
				"VirtualList pointer: a tap on a horizontal item activates through auto handleActivate",
			},
			touch = {
				"VirtualList touch: a native pan scroll slides the window (driveScroll)",
				"VirtualList touch: a row tap activates",
				"VirtualList touch: a native sideways pan slides the window and never activates",
				"VirtualList touch: a tap on a horizontal item activates",
			},
			keyboard = {
				"VirtualList keyboard: Up/Down moves focus row-by-row through the window",
				"VirtualList keyboard: Return activates the focused row",
				"VirtualList keyboard: Left/Right steps a horizontal list item-by-item",
				"VirtualList keyboard: Return activates the focused horizontal item",
			},
			gamepad = {
				"VirtualList gamepad: D-pad moves focus identically to arrows",
				"VirtualList gamepad: ButtonA activates the focused row",
				"VirtualList gamepad: DPadLeft/DPadRight move focus identically to arrows",
				"VirtualList gamepad: ButtonA activates the focused horizontal item",
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
			touch = { "VirtualList touch: a native sideways pan slides the window and never activates" },
			-- the STRUCTURAL idiom for a keyboard list is "the focus ring walks the
			-- list's own axis and nothing else does": the horizontal case is cited
			-- here because it is the one that proves the ring reads the axis rather
			-- than a hard-coded direction
			keyboard = {
				"VirtualList keyboard: Up/Down moves focus row-by-row through the window",
				"VirtualList keyboard: Up/Down do NOT step a horizontal list — ONE map, read one way",
			},
			gamepad = {
				"VirtualList gamepad: D-pad moves focus identically to arrows",
				"VirtualList gamepad: DPadLeft/DPadRight move focus identically to arrows",
				"a Thumbstick1 y push moves focus down like DPadDown, with the latch",
			},
			hotSwitch = false,
		},
	},
	{
		-- VirtualList's REORDER / DROP-TARGET / AUTOSCROLL block (2026-08-15). NOT a
		-- control: it mounts nothing and has no blueprint — it is the drag half of
		-- VirtualList, the window-space→canvas arithmetic every drop question is
		-- answered in, the reorder commits, the slide-to-new-slot motion, the
		-- per-row `UI.draggable`/`UI.dropTarget` wiring and the edge-autoscroll
		-- model. Lifted out of src/controls/virtual_list.luau verbatim because it
		-- writes no mutable upvalue of that closure, which is what took that file
		-- back under the 200,000-char `Script.Source` WRITE cap
		-- (docs/lessons/the-200k-source-cap-is-on-writing-not-loading.md) and
		-- restored its live sync into an open Studio session.
		--
		-- Its four-input story IS the VirtualList row's above: these are the very
		-- gestures every one of those cited reorder/drop cases drives.
		name = "VirtualReorder",
		kind = "composite",
		module = "src/controls/virtual_reorder.luau",
		export = "Controls.VirtualList",
		spec = "tests/virtualization.spec.luau",
		conformance = "tests/virtualization.spec.luau",
		docsAnchor = "newVirtualList",
		-- NO INSTANCE AND NO SEPARATE STATE: every number it holds is already in
		-- VirtualList's own dump() (`dropIndex`, `autoscroll`, the window), which is
		-- where a drag report reads them; the slide springs are presentation-only.
		dump = false,
		reason = "the drag half of VirtualList: its live state (dropIndex, autoscroll band, the window) is already reported by list.dump(), and a second copy here would be the same numbers twice",
		inputProofs = false,
		affordanceProofs = false,
	},
	{
		-- VirtualList's WINDOWING ARITHMETIC (2026-08-15). NOT a control: it mounts
		-- nothing — it is the running-offset index over src/virtual_extents.luau,
		-- the measurement cache's storage, the row->index map, the canvas Dim, the
		-- clamped scroll offset, the keyed window and the row-path spelling. Lifted
		-- out of src/controls/virtual_list.luau verbatim because the only mutable
		-- upvalues it writes are its own memo-input cache, which is what took that
		-- file back under the 200,000-char `Script.Source` WRITE cap
		-- (docs/lessons/the-200k-source-cap-is-on-writing-not-loading.md).
		--
		-- Its four-input story IS the VirtualList row's above: every windowing case
		-- cited there is this arithmetic answering.
		name = "VirtualWindow",
		kind = "composite",
		module = "src/controls/virtual_window.luau",
		export = "Controls.VirtualList",
		spec = "tests/virtualization.spec.luau",
		conformance = "tests/virtualization.spec.luau",
		docsAnchor = "newVirtualList",
		-- NO INSTANCE: it returns a bag of reactive nodes VirtualList closes over,
		-- and every number in them is already in list.dump() (contentExtent,
		-- scrollTop, window, measuredRows/measureEpoch) — a second copy here would
		-- be the same numbers twice.
		dump = false,
		reason = "returns the reactive index VirtualList closes over; its live values (contentExtent, scrollTop, the window, the measurement epoch) are already reported by list.dump()",
		inputProofs = false,
		affordanceProofs = false,
	},
	{
		--[[ THE CARD PARADIGM'S ARRANGEMENT, for `newVirtualList`'s
			`itemExtent = "cards"` (ADAPT-17, audit cells B-1/B-7/B-8). NOT a control:
			it builds no blueprint and mounts nothing. It answers one question — how
			many cards belong in view here, and therefore how wide one card is —
			validates the `cards` options table, and raises the ADAPT-1 refusal on the
			host's behalf when a rail that adapts has no environment to adapt from.
			The thresholds it decides with are `layout/adaptive.luau`'s, exported and
			pure, so the next card surface reaches them without copying a number out
			of a control.

			Its four-input story is its host's: the arrangement it picks is the one
			`newVirtualList` then paints, scrolls, snaps and traverses, and every case
			proving that is cited on that row. ]]
		name = "CardRail",
		kind = "composite",
		module = "src/controls/card_rail.luau",
		export = "Controls.VirtualList",
		spec = "tests/paradigm_cards.spec.luau",
		conformance = "tests/paradigm_cards.spec.luau",
		docsAnchor = "newVirtualList",
		-- NOTHING DURABLE TO REPORT: the arrangement is a pure function of the live
		-- viewport, gap and interaction class, and the host publishes the resolved
		-- answer on its own dump() as `cardsPerView` and `itemExtent` — which is
		-- where a "why is this rail two-up" bug report already looks.
		dump = false,
		reason = "a pure arrangement decision with no state of its own: the resolved answer (cardsPerView, itemExtent) is published by the host control's dump(), which is where a bug report about it already looks",
		inputProofs = false,
		affordanceProofs = false,
	},
	{
		--[[ THE SNAP MACHINE, shared by `newVirtualList` and `newVirtualGrid`
			(ADAPT-17, audit cell B-7). NOT a control: it mounts nothing, holds no
			blueprint and owns no scroll driver. It answers one arithmetic question —
			given where a scroll came to rest, where the travel started and how fast it
			went, which offset should it hold — and runs the small state machine that
			decides WHEN to ask, on the presenter's motion clock. The host writes; this
			only says where.

			Its four-input story is its two hosts': every touch flick, wheel settle,
			keyboard keep-visible and pad traversal it acts on arrives through their
			own mirrors, and the cases proving each are cited on their rows. ]]
		name = "ScrollSnap",
		kind = "composite",
		module = "src/controls/scroll_snap.luau",
		export = "Controls.VirtualList",
		spec = "tests/scroll_snap.spec.luau",
		conformance = "tests/paradigm_cards.spec.luau",
		docsAnchor = "newVirtualList",
		-- NO INSTANCE AND NO PERSISTENT STATE: what it holds is one travel's origin
		-- and peak, both of which are consumed at the settle they describe, and the
		-- consequence — where the scroller came to rest — is reported by the host
		-- control's own dump() (`scrollTop`, `snap`, `cardsPerView`). `debug()` is
		-- the test-only reader, deliberately not a dump surface.
		dump = false,
		reason = "arithmetic and one settle's transient state: the only durable consequence is the offset the host control already reports through its own dump() (scrollTop, snap, cardsPerView)",
		inputProofs = false,
		affordanceProofs = false,
	},
	{
		-- THE ENGINE SCROLL MIRROR'S ARBITRATION, shared by VirtualList,
		-- VirtualGrid (both axes) and Table (O-31, 2026-08-15). NOT a control: it
		-- mounts nothing, holds no reactive node and knows nothing about scrolling
		-- — it decides WHEN a mirror is (re)installed and hands every caller the
		-- same stop function, so that the framework's own auto-bind and a
		-- consumer's explicit `bindNativeScroll` can never each hold half of the
		-- teardown. The mirror itself is the `install` callback each control
		-- passes in, which is the only part that differs between them.
		--
		-- Its four-input story IS the three host rows': every pointer/touch scroll
		-- case they cite is a mirror this module decided to install.
		name = "NativeScrollBinding",
		kind = "composite",
		module = "src/controls/native_scroll_binding.luau",
		export = "Controls.VirtualList",
		spec = "tests/native_scroll_autobind.spec.luau",
		conformance = "tests/native_scroll_autobind.spec.luau",
		docsAnchor = "newVirtualList",
		-- NO INSTANCE AND NO STATE WORTH REPORTING: the one fact it holds is which
		-- (controller, path) is currently mirroring, and each host already reports
		-- the consequence — `scrollTop` and the window — through its own dump().
		dump = false,
		reason = "arbitration only: it holds which (controller, path) is currently mirroring, and every consequence of that is already reported by the host control's own dump() (scrollTop, the window)",
		inputProofs = false,
		affordanceProofs = false,
	},
	{
		name = "PopupButton",
		kind = "composite",
		module = "src/controls/popup_button.luau",
		export = "Controls.PopupButton",
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
		export = "Controls.TextInput",
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
		export = "Controls.ProgressView",
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
		export = "Controls.Label",
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
		export = "Controls.Picker",
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
		export = "Controls.DisclosureGroup",
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
		export = "Controls.Slider",
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
		export = "Controls.Stepper",
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
		export = "Controls.Rating",
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
		export = "Controls.Chip",
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
		export = "Controls.AsyncImage",
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
		-- RowActions (row-actions Tasks 3-6: composite skeleton, static reveal,
		-- spring motion, the mouse gesture, and now touch).
		-- A closed row (no actions revealed) is a TRUE inert passthrough — the
		-- wrapped `content` mounts unwrapped, with no RowActions node at all —
		-- but the moment either edge declares actions, the control attaches its
		-- OWN input contribution (contribution.attach + a routed handleActivate,
		-- mirroring popup_button.luau's api.handleActivate) to dispatch a tap/
		-- Return/ButtonA on a revealed `Action:<id>` tray button, which makes it
		-- an INTERACTIVE control by the checker's own rule (module source
		-- contains "contribution.attach"). Task 3's proofs below still reach a
		-- tray action through the STANDARD UI.Button activation path
		-- (adapter.tap / system.deviceKey against a pre-revealed tray) — the
		-- honest reachability/paradigm story for what those tasks built;
		-- Task 5 adds the swipe GESTURE (axis lock, live drag, flick velocity,
		-- full-swipe commit — tests/row_actions_input.spec.luau), reached
		-- through `adapter.pointerDown/pointerMove/pointerUp` against the
		-- `Content/Hit` grip, MOUSE only at the time. Task 6 (spike:
		-- artifacts/row-actions/touch-spike.md — a live Studio session confirmed
		-- the device emulator is now MCP-drivable, but no MCP tool in that
		-- session could drive input into a running client at all, reconfirming
		-- the 2026-07-23 NS-M4/NS-A6 finding under current tooling; the decision
		-- rests on a code-trace plus table.luau's own shipped, device-verified
		-- precedent instead — see the artifact) accepts TOUCH through the
		-- identical seam: `onPointerDown` now declines only a pointerType that is
		-- neither "mouse" nor "touch", and every downstream branch (axis lock,
		-- clampDrag, settle) is unconditionally shared between the two classes —
		-- see the hotSwitch note below for why this row's in-flight gesture state
		-- now demands (and has) a real §C citation. Task 8 ships keyboard
		-- Delete/Backspace (a destructive action, scoped to the row's own
		-- mounted subtree — content, a revealed tray button, or an open
		-- menu row — holding focus, and inert while the menu is open (it
		-- owns input then) — tests/row_actions_input.spec.luau "RowActions
		-- Task 8: keyboard Delete") and the gamepad ButtonX action menu (a
		-- PopupButton-pattern popup listing every action — "RowActions Task
		-- 8: the action menu (ButtonX)"). Task 8 itself left `Shift+Return`
		-- unbound (NEEDS_CONTEXT: no modifier slot on an IAS binding, and
		-- Return was already the base screen's Activate key — see the Task
		-- 8 report). Task 8b shipped it: an additive `modifiers` slot on
		-- `action.bind` (src/input/actions.luau + its real-engine adapter
		-- src/client/roblox_input.luau) lets `RowActionsMenu` bind
		-- `Return` with `modifiers = { shift = true }` in the SAME
		-- sink=true, priority-10000 context as Delete/ButtonX — the menu is
		-- now reachable via keyboard (Shift+Return, toggles) OR gamepad
		-- (ButtonX, toggles); "RowActions Task 8b: the action menu
		-- (Shift+Return)" is the citation, including the double-fire
		-- regression test ("Shift+Return fires ONLY the menu toggle…") the
		-- whole follow-up existed to prove.
		name = "RowActions",
		kind = "composite",
		module = "src/controls/row_actions.luau",
		export = "Controls.RowActions",
		spec = "tests/row_actions.spec.luau",
		conformance = "tests/row_actions.spec.luau",
		docsAnchor = "newRowActions",
		dumpFunction = "function dump",
		inputProofs = {
			pointer = { "RowActions pointer: a tap on a revealed tray action activates it (device-true)" },
			touch = {
				"RowActions touch: a touch tap on a revealed tray action activates it (device-true)",
				-- ...and the REVEAL itself, which the case above assumes rather
				-- than proves (director device round 2026-08-13, finding 2). Every
				-- swipe case in the suite drove `"mouse"`, so the one gesture this
				-- control exists for had no touch proof on the shape the report
				-- named: touch + a declared primary action + NOT in edit mode.
				-- Both edges, on the hosted Table surface.
				-- ...and it survives the engine's own release `Activated` — the
				-- signal the driver never sent, which is why the "a swipe is not
				-- a tap" half of that case could not fail (redteam BLOCKER,
				-- 2026-08-13). Named at the "after InputEnded" order, the one
				-- that used to close the tray in the frame it appeared; the
				-- "before" order and the mouse pointer kind are the same case's
				-- other three generated instances.
				"RowActions touch: a swipe reveals the tray on a table NOT in edit mode and survives its release Activate (after)",
			},
			keyboard = {
				"RowActions keyboard: focus + Return activates a revealed tray action",
				-- Task 8: a SECOND, structurally different keyboard path —
				-- Delete, not Return/Activate, and it never taps a tray
				-- button at all (the tray need not even be open).
				"Delete on a focused row fires the first destructive action",
				-- Task 8b: a THIRD keyboard path — Shift+Return opens/closes
				-- the SAME action menu ButtonX reaches, via the action
				-- system's new `modifiers` binding slot.
				"Shift+Return opens the menu, entering focus on its first row — identical outcome to ButtonX",
			},
			gamepad = {
				"RowActions gamepad: focus + ButtonA activates a revealed tray action",
				-- Task 8: ButtonX opens the action menu (a second gamepad
				-- surface this control offers, distinct from the tray).
				"ButtonX opens the menu, entering focus on its first row; Activate on a non-destructive item runs it exactly once and closes",
			},
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
			-- Task 5 SHIPPED real in-flight gesture state (`drag`, held between
			-- pointerDown and pointerUp/cancel: origin, start offset, and the axis
			-- verdict itself) but kept `hotSwitch = false`, because at that point
			-- `onPointerDown` DECLINED any `pos.pointerType ~= "mouse"` outright, so
			-- `drag` could only ever be created and touched by ONE class — there was
			-- no second class it could hot-switch TO or FROM. Task 6 (touch-spike.md)
			-- is exactly the point the row's own prior comment named as the deadline:
			-- `onPointerDown` now accepts BOTH "mouse" and "touch", so a real
			-- mid-gesture class flip is possible for the first time — `drag` (one
			-- record, either class) is what a second class's own `onPointerDown`
			-- attempt would have to steal, and the adapter's own single-capture
			-- model (`fake_target.luau` `pointerDown`: "a live capture OWNS the
			-- pointer... ignored, never a steal") means it never can: a touch press
			-- mid-mouse-drag, or a mouse press mid-touch-drag, is silently ignored
			-- before this composite's own `onPointerDown` even runs, so the FIRST
			-- class's gesture always CARRIES uninterrupted through a second class's
			-- failed attempt — the same shape Table's own `hotSwitch` citations use
			-- for "CARRY: native scroll position survives a class flip". A capture
			-- LOSS (not a flip) still CANCELs identically for touch and mouse alike
			-- (`onPointerCancel`'s existing `close()` on a horizontal-axis drag,
			-- unchanged by Task 6 — same-class capability loss, matching Table's own
			-- "pointer drag mid-flight + pointer capability lost => CANCEL" reading).
			-- No keyboard/gamepad entry point into `drag` exists yet (`_commitFirst`,
			-- Task 8's future keyboard-Delete seam, is a separate ATOMIC operation
			-- that never reads or writes `drag`), so these three cases are the whole
			-- citation for now; Task 8 revisits this list, not just this comment.
			hotSwitch = {
				"hotSwitch: a touch press arriving mid-mouse-drag is declined; the mouse drag CARRIES uninterrupted",
				"hotSwitch: a mouse press arriving mid-touch-drag is declined; the touch drag CARRIES uninterrupted",
				"hotSwitch: touch pointer cancel mid-drag springs back to closed (capability lost => CANCEL)",
			},
		},
	},
	{
		-- the ActionSpec authoring contract behind `newRowActions` (2026-08-14).
		-- NOT a control: it renders nothing, holds no state and has no input
		-- surface — it is the pure validation/leaf-helper half of
		-- src/controls/row_actions.luau, lifted out so that file could get back
		-- under the 200,000-char `Script.Source` WRITE cap and live-sync into an
		-- open Studio session again (docs/lessons/
		-- the-200k-source-cap-is-on-writing-not-loading.md, tools/check_source_size.py).
		-- Same explicit-row-rather-than-silent-exemption treatment as ValueModel
		-- and PathShapes above; `export`/`docsAnchor` name the PUBLIC export this
		-- module is part of the implementation of, since it has none of its own.
		name = "RowActionsSpec",
		kind = "composite",
		module = "src/controls/row_actions_spec.luau",
		export = "Controls.RowActions",
		spec = "tests/row_actions.spec.luau",
		conformance = "tests/row_actions.spec.luau",
		docsAnchor = "newRowActions",
		-- STATELESS MODULE: six pure functions of their arguments, no instance.
		dump = false,
		reason = "stateless module: pure ActionSpec validation and leaf string/id helpers, no instance state to summarize",
		inputProofs = false,
		affordanceProofs = false,
	},
	{
		--[[ NOT A CONTROL, and not an export either: `controls/table_columns.luau`
			is the pure half of Table's column-width RESOLUTION — the DIR-4 clamp
			that keeps committed resize widths from pushing a column off a narrower
			viewport. It has a row here for the same reason `RowActionsSpec` does:
			`check_registration` walks `src/controls/` and a module with no row is a
			module nothing knows about. It was extracted the day it was written,
			because writing it inside `newTable` put that file over the
			200,000-char `Script.Source` WRITE cap
			(docs/lessons/the-200k-source-cap-is-on-writing-not-loading.md). ]]
		name = "TableColumns",
		kind = "composite",
		module = "src/controls/table_columns.luau",
		export = "Controls.Table",
		spec = "tests/table.spec.luau",
		conformance = "tests/table.spec.luau",
		docsAnchor = "newTable",
		-- STATELESS MODULE: one pure function of its arguments, no instance.
		dump = false,
		reason = "stateless module: one pure width-resolution function of (columns, overrides, available), no instance state to summarize",
		inputProofs = false,
		affordanceProofs = false,
	},
	{
		--[[ NOT A CONTROL, and not an export either: `controls/table_rows.luau` is
			Table's ROW/CELL BUILDER — one row's whole mounted shape (`Row` hit,
			cells, the edit-mode ≡ gutter, the row-actions wrap) and the pointer
			handlers that begin on it, behind the parameter object that makes the
			require one-way. It has a row here for the same reason `TableColumns`
			does: `check_registration` walks `src/controls/` and a module with no row
			is a module nothing knows about.

			IT MOUNTS REAL INPUT AND STILL DECLARES `inputProofs = false`, which is
			the `RowActionsReorder` precedent above and is the honest answer: this
			module builds Table's row and hands every gesture straight back to
			Table's own state machine (`api.handleActivate`, `cancelDrag`, the shared
			`rowGesture` record). It has no verb of its own to reach, and no session
			can put focus on it as a thing. Its four-input and PARADIGM stories ARE
			Table's row's, proven cell by cell in the `Table` row at the top of this
			file — which is what those proofs have always exercised, before and after
			2026-08-18's extraction, because the row is byte-identical either way.

			WHY IT LEFT `table.luau`: `docs/handoff/SOURCE_CAP_LEDGER.md`'s row for
			that file made the move a PRECONDITION of the next change of any size —
			it was 1,236 characters from the 200,000-char `Script.Source` WRITE cap
			(docs/lessons/the-200k-source-cap-is-on-writing-not-loading.md). ]]
		name = "TableRows",
		kind = "composite",
		module = "src/controls/table_rows.luau",
		export = "Controls.Table",
		spec = "tests/table.spec.luau",
		conformance = "tests/table.spec.luau",
		docsAnchor = "newTable",
		-- NO INSTANCE OF ITS OWN: `new(deps)` returns one closure, and every piece
		-- of state it touches is the table's — the shared `rowGesture` record, the
		-- table's signals, the per-row `row_actions` handles Table itself owns and
		-- prunes. Table's `dump()` is where a report reads all of it.
		dump = false,
		reason = "no instance: new(deps) returns one blueprint closure over state the TABLE owns (the shared rowGesture record, its signals, its row_actions handles) — newTable's own dump() is where a report reads it",
		inputProofs = false,
		affordanceProofs = false,
	},
	{
		--[[ NOT A CONTROL: `controls/table_header.luau` is `newTable`'s header BAND —
			the column headings, their sort marks and the resize divider between them,
			plus the tap that divider does not claim. It has a row here for the same
			reason `TableColumns`, `TableRows` and `TableDisclosure` do:
			`check_registration` walks `src/controls/` and a module with no row is a
			module nothing knows about.

			IT BUILDS THE BAND AND STARTS THE GESTURE; the table decides what a width
			MEANS (`setColumnWidth`, `stepColumnWidth`, the committed overrides all
			stayed behind). Its four-input and PARADIGM stories are `newTable`'s
			header, proven cell by cell in the `Table` row at the top of this file —
			the mouse and touch grip drags, the keyboard `,`/`.` and the gamepad
			bumper, the pad Activate that SELECTS a column, and the 44px divider band
			with its forwarded tap.

			WHY IT LEFT `table.luau`: `docs/handoff/SOURCE_CAP_LEDGER.md`'s row named
			this exact seam and set its trigger, and the column-collapse paradigm put
			that file back inside the 190,000-char warning band the same day. ]]
		name = "TableHeader",
		kind = "composite",
		module = "src/controls/table_header.luau",
		export = "Controls.Table",
		spec = "tests/table_input.spec.luau",
		conformance = "tests/playlist_columns.spec.luau",
		docsAnchor = "newTable",
		-- NO INSTANCE: `band(deps)` returns one blueprint and closes over state the
		-- TABLE owns — the shared `resizeGesture` record, its signals, its api.
		dump = false,
		reason = "band(deps) returns one blueprint over state the TABLE owns (the shared resizeGesture record, resizing/previewX, the committed overrides) — newTable's own dump is where a report reads it",
		inputProofs = false,
		affordanceProofs = false,
	},
	{
		--[[ NOT A CONTROL: `controls/table_disclosure.luau` is the route back to a
			column the table COLLAPSED (ADAPT-18). It builds the plate's facts and its
			content and hands both to `src/region_expand.luau`, which is the framework's
			ONE disclosure presentation — the anchored panel, the sheet fallback and
			all four dismissals are that file's, not this one's. It has a row here for
			the same reason `TableColumns` and `TableRows` do: `check_registration`
			walks `src/controls/` and a module with no row is a module nothing knows
			about.

			ITS FOUR-INPUT AND PARADIGM STORIES ARE `newTable`'s ROW, and they are
			proven there: the chip is a Table focus stop with a 44px band, A/Return
			open the plate, B and the plate's own Close leave it, and an outside tap
			dismisses — `tests/table_input.spec.luau`'s ADAPT-18 family drives every
			one through the real input seams, and `tests/overflow_sweep.spec.luau`
			sweeps "a collapsed column with no route" across every shipped surface at
			every viewport, text preference and package. ]]
		name = "TableDisclosure",
		kind = "composite",
		module = "src/controls/table_disclosure.luau",
		export = "Controls.Table",
		spec = "tests/table_input.spec.luau",
		conformance = "tests/table_input.spec.luau",
		docsAnchor = "newTable",
		-- NO INSTANCE: it returns `region_expand`'s engine, whose open/closed state
		-- is on `newTable`'s own dump as `columnPlate` — which is where a report
		-- reads it, beside the `hiddenColumns` that explain why it exists.
		dump = false,
		reason = "returns region_expand's engine and holds nothing else: newTable's dump carries the state (hiddenColumns + columnPlate), and the plate's own teardown count is region_expand's",
		inputProofs = false,
		affordanceProofs = false,
	},
	{
		-- `Facet.newRowActionsCoordinator`, whole (2026-08-14). NOT a control: it
		-- renders nothing and has no input surface — it is a one-slot registry of
		-- "which row is currently open on this list surface", talking to rows only
		-- through their public `_close`/`_closeMenu` handle. It was already a
		-- PUBLIC export living inside src/controls/row_actions.luau's private body,
		-- which made it the clearest seam there when that file had to shed
		-- periphery to get back under the 200,000-char `Script.Source` WRITE cap
		-- (docs/lessons/the-200k-source-cap-is-on-writing-not-loading.md).
		name = "RowActionsCoordinator",
		kind = "composite",
		module = "src/controls/row_actions_coordinator.luau",
		export = "newRowActionsCoordinator",
		spec = "tests/row_actions.spec.luau",
		conformance = "tests/row_actions.spec.luau",
		docsAnchor = "newRowActionsCoordinator",
		-- STATELESS-BY-SHAPE: three closures over one plain local (the claimed
		-- row's own API table). There is no reactive state here to summarize, and
		-- the state a bug report needs is the claimed ROW's own dump().
		dump = false,
		reason = "three closures over one plain local: the claimed row's own dump() is the state a report needs, not a second copy of it here",
		inputProofs = false,
		affordanceProofs = false,
	},
	{
		-- `row_actions.composeWithReorder`, whole (2026-08-14). NOT a control: it
		-- mounts nothing and owns no node — it is the deferred-down ARBITER that
		-- lets one raw pointer capture (ADR-0008) be claimed by either the row's
		-- horizontal swipe or Table's vertical drag-to-reorder, replaying the
		-- original down into exactly one of them at the axis lock. Its own
		-- four-input story is Table's and RowActions': the same handler tables it
		-- composes, proven by their rows above (and by table.spec.luau's
		-- "mouse horizontal drag on the same reorderable + wrapped row reveals
		-- actions instead of reordering", cited there).
		name = "RowActionsReorder",
		kind = "composite",
		module = "src/controls/row_actions_reorder.luau",
		export = "Controls.RowActions",
		spec = "tests/table.spec.luau",
		conformance = "tests/table.spec.luau",
		docsAnchor = "newRowActions",
		-- STATELESS-BY-SHAPE: one `pending` record per LIVE gesture, local to the
		-- returned closure and gone at pointer up. The state a report needs is the
		-- row engine's own dump() and Table's.
		dump = false,
		reason = "per-gesture arbiter: its only state is one pending record that dies at pointer up; the row engine's and Table's dumps are what a report needs",
		inputProofs = false,
		affordanceProofs = false,
	},
	{
		-- every live pixel amount a row-actions band is made of (2026-08-14). NOT a
		-- control: it mounts nothing — it resolves the four `controls.rowActions.*`
		-- theme metrics, owns the per-action NATURAL width signals, and does the
		-- band arithmetic (`bandWidth` = the number the row TRAVELS) plus the
		-- edit-mode gutter. Lifted out of src/controls/row_actions.luau because
		-- every value it returns is a pure function of build-time facts, which let
		-- that file get back under the 200,000-char `Script.Source` WRITE cap
		-- (docs/lessons/the-200k-source-cap-is-on-writing-not-loading.md).
		name = "RowActionsMetrics",
		kind = "composite",
		module = "src/controls/row_actions_metrics.luau",
		export = "Controls.RowActions",
		spec = "tests/row_actions.spec.luau",
		conformance = "tests/row_actions.spec.luau",
		docsAnchor = "newRowActions",
		-- NO INSTANCE: `build()` returns a bag of already-owned reactive nodes that
		-- the row engine closes over. Their live values are already in the row's
		-- own dump() (trayWidth/offset/phase), which is where a report reads them.
		dump = false,
		reason = "returns reactive nodes the row engine owns and already reports through its own dump(); a second copy here would be the same numbers twice",
		inputProofs = false,
		affordanceProofs = false,
	},
	{
		-- the tray blueprints both modes share (2026-08-14): the plate buttons, the
		-- per-action reveal-scaled width and padding props, the band's own gutter
		-- and inter-plate gap, and the two `UI.When`s that mount a tray while its
		-- edge is open OR its close flight is still visibly running. NOT a control
		-- in its own right — it is the VIEW half of RowActions, called once per
		-- engine and handed either to the composite's own row root (standalone,
		-- Table) or to the host's one shared overlay (VirtualList). Lifted out of
		-- src/controls/row_actions.luau because every input is a build-time
		-- constant, which is what took that file back under the 200,000-char
		-- `Script.Source` WRITE cap (docs/lessons/
		-- the-200k-source-cap-is-on-writing-not-loading.md) and restored its live
		-- sync into an open Studio session.
		--
		-- Its four-input story IS the RowActions row's above: these are the very
		-- nodes every one of those cited cases taps, focuses and activates.
		name = "RowActionsTrays",
		kind = "composite",
		module = "src/controls/row_actions_trays.luau",
		export = "Controls.RowActions",
		spec = "tests/row_actions.spec.luau",
		conformance = "tests/row_actions.spec.luau",
		docsAnchor = "newRowActions",
		-- NO INSTANCE: `build()` returns blueprints. What a report needs about a
		-- revealed tray — which edge is open, how far, how wide the band is — is
		-- already in the row engine's own dump(), which owns the state these read.
		dump = false,
		reason = "returns blueprints, holds no instance: the row engine's dump() already reports the edge/offset/trayWidth these views are derived from",
		inputProofs = false,
		affordanceProofs = false,
	},
	{
		-- the standalone/Table row NODE (2026-08-14): the root Anchor, the trays
		-- under it, the `Content` ZStack that slides over them (sign-following
		-- anchor, edit-gutter padding, collapse `overflow`), the drag Hit Grip on
		-- top of `content`, and the edit-mode leading minus painted over the lot.
		-- HOSTED MODE BUILDS NONE OF IT — a closed hosted row costs its host
		-- nothing — which is why this is a separate call rather than a branch
		-- inside one blueprint. NOT a control in its own right: it is the node half
		-- of RowActions, and its four-input story is that row's, since these ARE
		-- the nodes every cited case presses, focuses and activates.
		--
		-- ITS PAINT ORDER IS A DEVICE FACT, not a style: the Hit Grip goes AFTER
		-- `content` because the engine delivers a press to the TOPMOST interactive
		-- object only (docs/lessons/a-button-eats-the-swipe-underneath-it.md), and
		-- the minus goes after Content so a trailing swipe passes under it.
		name = "RowActionsRoot",
		kind = "composite",
		module = "src/controls/row_actions_root.luau",
		export = "Controls.RowActions",
		spec = "tests/row_actions.spec.luau",
		conformance = "tests/row_actions.spec.luau",
		docsAnchor = "newRowActions",
		-- NO INSTANCE: `build()` returns one blueprint. The row engine's own dump()
		-- reports the state these nodes are bound to (edge, offset, phase, height).
		dump = false,
		reason = "returns one blueprint, holds no instance: the row engine's dump() already reports the edge/offset/phase/height these nodes are bound to",
		inputProofs = false,
		affordanceProofs = false,
	},
	{
		name = "VirtualGrid",
		kind = "composite",
		module = "src/controls/virtual_grid.luau",
		export = "Controls.VirtualGrid",
		spec = "tests/virtual_grid.spec.luau",
		conformance = "tests/virtual_grid_input.spec.luau",
		docsAnchor = "newVirtualGrid",
		dumpFunction = "function grid.dump",
		--[[ THE LAZY GRID (SwiftUI's `LazyVGrid`). Its reachability story is a
			scrolling collection's — the engine ScrollingFrame owns pointer/touch
			scroll, the contributed group owns the ring — but its PARADIGM story has
			one claim `newVirtualList` cannot make and this row exists to pin: DOWN
			MOVES A WHOLE LINE, NOT ONE CELL. The mounted cells are ONE group in
			row-major document order with `axis = "horizontal"`, so ±1 is a sideways
			step; the vertical axis arrives through `navigateIntercept` because the
			focus graph has no two-dimensional group axis. Emitting the group as
			`vertical` would have been REACHABLE and wrong in SHAPE, which is the
			whole difference between the two axes below. ]]
		inputProofs = {
			pointer = {
				"VirtualGrid pointer: an engine scroll (driveScroll) slides the window",
				"VirtualGrid pointer: a cell tap activates through auto handleActivate",
			},
			touch = {
				"VirtualGrid touch: a native pan scroll slides the window and never activates a cell",
				"VirtualGrid touch: a cell tap activates",
			},
			keyboard = {
				"VirtualGrid keyboard: Left/Right steps cell-by-cell ACROSS a line",
				"VirtualGrid keyboard: Down moves a whole LINE, not one cell",
				"VirtualGrid keyboard: Return activates the focused cell",
			},
			gamepad = {
				"VirtualGrid gamepad: DPadRight steps a cell and DPadDown steps a whole line",
				"VirtualGrid gamepad: ButtonA activates the focused cell",
			},
		},
		-- PARADIGM axis. pointer/touch = the NATIVE ScrollingFrame owns scroll
		-- (wheel/pan/momentum) and a scroll never activates; the viewport is a real
		-- clip host so partial lines crop. keyboard/gamepad = a windowed focus ring
		-- whose SHAPE is two-dimensional, with keep-visible scroll-into-view (a step
		-- into the overscan band scrolls the window, which materializes the next line
		-- for the step after it — the ring never has to focus an unmounted node).
		-- The grid advertises no reorder, no grab and no edit: its only live state is
		-- the engine-owned scroll offset, pure presentation that inherently survives
		-- any class flip. No in-flight GESTURE, so hotSwitch = false.
		affordanceProofs = {
			pointer = { "VirtualGrid pointer: partial lines crop via the engine clip host" },
			touch = { "VirtualGrid touch: a native pan scroll slides the window and never activates a cell" },
			keyboard = {
				"VirtualGrid keyboard: Down moves a whole LINE, not one cell",
				"VirtualGrid keyboard: focus past the window edge scrolls the line into view",
			},
			gamepad = { "VirtualGrid gamepad: DPadRight steps a cell and DPadDown steps a whole line" },
			hotSwitch = false,
		},
	},
	{
		-- The D4 sliding-selection seam. NOT a public construct (director ruling
		-- 2026-08-16): the authoring surface is the `indicator` PROPERTY on the
		-- controls that consume it, so this row names `newPicker` — the same shape
		-- `VirtualWindow`/`RowActionsTrays` already use for a module that returns
		-- what its control mounts.
		name = "SelectionIndicator",
		kind = "composite",
		module = "src/controls/selection_indicator.luau",
		export = "Controls.Picker",
		spec = "tests/selection_indicator.spec.luau",
		conformance = "tests/selection_indicator.spec.luau",
		docsAnchor = "newPicker",
		-- NO DUMP OF ITS OWN: an internal seam with a second schema string is a
		-- schema a bug report has to be taught to look for. Its live state
		-- (`state()`) is reported inside `picker.dump().indicator`.
		dump = false,
		reason = "the DECORATION half of Picker's `indicator` property: its live state (skin, axis, the resolved segment rect, placements vs slides, geometry updates) is reported by picker.dump().indicator, and a second copy here would be the same numbers twice",
		-- NON-INTERACTIVE, and structurally so rather than by policy: this seam
		-- mounts an `Anchor` holding a `Box`, and neither class is in focus_map's
		-- FOCUSABLE set — so it takes no verb on any input class, and there is no
		-- four-input story to prove. What it owes instead is a proof that it STAYS
		-- OUT OF THE WAY, because a decoration that became a Tab stop would sit
		-- between every pair of tabs it decorates: "the indicator is never a focus
		-- stop: wrapping a strip leaves its document order identical". Its own
		-- geometry, motion and reduced-motion behaviour are proved through the
		-- presenter in the same spec.
		inputProofs = false,
		affordanceProofs = false,
	},
	{
		-- The ONE menu row and the ONE presentation rule (navigation-and-menus D2,
		-- director call §5). Not a control: it renders no tree of its own and owns
		-- no state — it is the per-row body `row_actions.buildMenuRows` already
		-- wrote, plus `popup_button.resolvePresentation` relocated verbatim, in one
		-- place so the three menus that render action lists cannot drift apart.
		-- *"Three copies of a menu row is how the icon-first ruling gets silently
		-- lost."*
		name = "MenuRecipe",
		kind = "composite",
		module = "src/controls/menu_recipe.luau",
		export = "Controls.Menu",
		spec = "tests/menu.spec.luau",
		conformance = "tests/menu.spec.luau",
		docsAnchor = "newMenu",
		-- NO DUMP OF ITS OWN: it returns blueprints its three callers mount, and
		-- every one of them already reports the rows it built through its own
		-- dump() (`menu.dump().items`, `popup_button.dump().options`,
		-- `row_actions.dump().menuItems`).
		dump = false,
		reason = "returns the row blueprints its three callers mount and the presentation string they resolve; each caller already reports what it built through its own dump(), and a second copy here would be the same rows twice",
		-- NON-INTERACTIVE, structurally: it attaches no input contribution and
		-- takes no verb. The rows it returns are ordinary `UI.Button`s whose
		-- four-input story belongs to whichever control mounted them — proved
		-- there (Menu, PopupButton and RowActions each cite their own).
		inputProofs = false,
		affordanceProofs = false,
	},
	{
		-- The freestanding ACTION menu (navigation-and-menus D2). Items are VERBS,
		-- not values — which is why it is a control of its own rather than a
		-- property on PopupButton, whose `value` is a `Signal<string>` a verb list
		-- cannot fill. Attaches to ANY blueprint, presents on D1's anchored seam,
		-- and closes `.contextMenu` by consuming the normalized gesture layer that
		-- shipped with nothing reading it.
		name = "Menu",
		kind = "composite",
		module = "src/controls/menu.luau",
		export = "Controls.Menu",
		spec = "tests/menu.spec.luau",
		conformance = "tests/menu.spec.luau",
		docsAnchor = "newMenu",
		dumpFunction = "function dump",
		inputProofs = {
			pointer = {
				"a pointer SECONDARY click on the trigger opens the menu",
				"activating an item runs its onSelect exactly once and closes the menu",
			},
			touch = {
				"a touch LONG-PRESS on the trigger opens the menu, through the normalized gesture layer",
			},
			keyboard = {
				"the keyboard context chord opens the menu, and Return activates the focused item",
			},
			gamepad = {
				"the gamepad menu button opens it, and ButtonB closes ONE level",
			},
		},
		-- PARADIGM axis. pointer/touch = the trigger opens on a secondary click or
		-- a long press and a tap outside closes every level; keyboard = the open
		-- items are ordinary focus-ring Buttons and Left/Right leave and enter a
		-- submenu in document order; gamepad = ButtonB unwinds one level at a time.
		-- The SHEET presentation is the touch idiom and it replaces the panel's
		-- contents rather than stacking a second one — the one place the idioms
		-- genuinely differ, and it is resolved from space and live input class,
		-- never a device name.
		--
		-- hotSwitch: an open submenu chain IS in-flight state, so this is not the
		-- `false` PopupButton can claim. A class flip while a submenu is open
		-- CARRIES the open path and re-presents it in the newly resolved idiom.
		affordanceProofs = {
			pointer = {
				"a pointer SECONDARY click on the trigger opens the menu",
				"tap-away closes EVERY level, not just the innermost",
			},
			touch = {
				"a touch LONG-PRESS on the trigger opens the menu, through the normalized gesture layer",
				"under `sheet` a submenu REPLACES the sheet's contents and grows a Back row",
			},
			keyboard = {
				"Right enters the focused submenu and Left leaves it, in document order",
			},
			gamepad = {
				"the gamepad menu button opens it, and ButtonB closes ONE level",
			},
			hotSwitch = {
				"a live class flip while a submenu is open CARRIES the open path into the new presentation",
			},
		},
	},
	{
		-- The APP-PUSHED coach mark (navigation-and-menus D3b) — TipKit's
		-- `popoverTip`, not a tooltip. A tooltip is player-PULLED, pointer-only and
		-- invisible on touch, and it is a PROP (`help`) rather than a control; this
		-- is the other mechanism, raised by the app from eligibility rules, shown on
		-- every input class, carrying D1's arrow tail. It is a control rather than a
		-- property because it owns state a property cannot: an eligibility rule, a
		-- permanent invalidation, and a turn in a one-at-a-time queue.
		name = "Callout",
		kind = "composite",
		module = "src/controls/callout.luau",
		export = "Controls.Callout",
		spec = "tests/callout.spec.luau",
		conformance = "tests/callout.spec.luau",
		docsAnchor = "newCallout",
		dumpFunction = "function dump",
		--[[ FOUR-INPUT PROOFS (ui_todo §0). The verb a Callout owns is DISMISS —
			it presents nothing else to press — and a coach mark a player cannot
			retire is a modal wearing an arrow, so all four classes prove exactly
			that. Pointer and touch tap the plate's own `Dismiss` row (which also
			meets the 44px floor); keyboard and gamepad reach that row with the ring
			and press Return / ButtonA. ]]
		inputProofs = {
			pointer = {
				"pointer: a click on the dismiss affordance retires it",
				"a tap in empty space retires it through the presenter's own non-consuming catcher",
			},
			touch = {
				"touch: a tap on the dismiss affordance retires it, and it meets the 44px floor",
			},
			keyboard = {
				"keyboard: Return on the focused dismiss affordance retires it",
			},
			gamepad = {
				"gamepad: ButtonA on the focused dismiss affordance retires it",
			},
		},
		--[[ PARADIGM axis. The structural idiom this construct has to get right is
			NOT-BLOCKING, and it reads differently per class: a pointer or a finger
			expects tap-away to work AND to reach what was underneath (the
			non-consuming catcher, driven by counting the activation on the very
			control the arrow points at); a keyboard or a pad expects the ring to
			stay where the player left it and the plate to be ONE arrow press away,
			not a trap it has to escape.

			hotSwitch: `false`. A callout holds no in-flight gesture state — it is
			either waiting, queued, showing or retired, and every one of those
			survives a live class flip unchanged, because none of them is a
			half-finished interaction. ]]
		affordanceProofs = {
			pointer = {
				"THE CONTROL IT POINTS AT STAYS OPERABLE: a tap on it still activates it",
				"a tap in empty space retires it through the presenter's own non-consuming catcher",
			},
			touch = {
				"touch: a tap on the dismiss affordance retires it, and it meets the 44px floor",
			},
			keyboard = {
				"presenting one does not move the focus ring",
				"it is NOT a modal: the screen underneath keeps its own focus scope",
			},
			gamepad = {
				"...and one arrow press reaches it, so a pad player is never stuck with a plate",
			},
			hotSwitch = false,
		},
	},
	{
		name = "TabView",
		kind = "composite",
		module = "src/controls/tab_view.luau",
		export = "Controls.TabView",
		spec = "tests/tab_view.spec.luau",
		conformance = "tests/tab_view.spec.luau",
		docsAnchor = "newTabView",
		dumpFunction = "function api.dump",
		-- Four-input proofs (ui_todo §0). A tab is a `newPicker` segment — the
		-- strip IS that control (navigation-and-menus D5) — so the four verbs come
		-- from the primitive, and what these prove is that COMPOSING it left them
		-- reachable in every home the placement policy can put the strip in.
		inputProofs = {
			pointer = { "TabView pointer: a tap activates through the presenter (device-true)" },
			touch = { "TabView touch: a touch tap/pan drives the control (device-true)" },
			keyboard = { "TabView keyboard: focus + Return drives the control" },
			gamepad = { "TabView gamepad: focus + ButtonA drives the control" },
		},
		-- PARADIGM: the strip's own idioms are the picker's (a tab is a focusable
		-- Button with a 44px floor); what is TabView-specific is that the strip is
		-- a SCROLL HOST, so the pointer reaches an overflowing strip through the
		-- engine's own wheel/drag channel and a touch NAKED PAN scrolls it with no
		-- grip, while the gamepad SHOULDERS page — bound dynamically, only while
		-- focus sits on a tab, so a screen carrying a TabView never shadows
		-- gameplay bumpers (ADR-0013). hotSwitch = false: there is no drag, no grab
		-- and no open edit, and a tab switch is a single Signal write, so a live
		-- class flip mid-anything has nothing to carry or cancel — the same answer
		-- Picker gives, for the same reason.
		affordanceProofs = {
			pointer = { "TabView pointer affordance: the pointer structural idiom (hover/direct-drag/wheel)" },
			touch = { "TabView touch affordance: the touch structural idiom (44px/naked-pan-scroll/edit-grip)" },
			keyboard = {
				"TabView keyboard affordance: the keyboard structural idiom (focus ring/Navigate/Activate/Adjust)",
			},
			gamepad = { "TabView gamepad affordance: the gamepad structural idiom (focus/grab/A-B/ten-foot)" },
			hotSwitch = false,
		},
	},
	{
		name = "LevelPicker",
		kind = "composite",
		module = "src/controls/level_picker.luau",
		export = "Controls.LevelPicker",
		spec = "tests/level_picker.spec.luau",
		conformance = "tests/level_picker.spec.luau",
		docsAnchor = "newLevelPicker",
		dumpFunction = "function api.dump",
		-- REACHABILITY: pointer/touch land on the ONE Grip that covers the run of
		-- segments (tap to set, drag to scrub); keyboard and gamepad reach the SAME
		-- arithmetic through the focus-gated Adjust verb, at ONE focus stop for the
		-- whole control rather than one per segment — the generalization of the
		-- Rating row below, held for a caller-chosen `count`.
		inputProofs = {
			pointer = { "LevelPicker pointer: tapping a segment sets the level to that segment" },
			touch = { "LevelPicker touch: a finger drag across the strip scrubs the level live" },
			keyboard = { "LevelPicker keyboard: Adjust on the focused strip sets the level" },
			gamepad = { "LevelPicker gamepad: the bumpers Adjust the focused level picker" },
		},
		-- PARADIGM: pointer = ONE direct-manipulation target over the whole run, no
		-- per-segment hit surface at any count; touch = the same gesture against the
		-- DECLARED 44px floor (load-bearing here, because a bar segment has no
		-- content height of its own); keyboard = Adjust bound ONLY while focus is
		-- inside the control, so a screen with a picker never shadows gameplay keys;
		-- gamepad = the bumpers Adjust, and at the limit the ARROW goes back to
		-- navigation so nothing after a maxed-out picker is unreachable.
		-- hotSwitch = TRUE: a scrub IS in-flight state, and the decision is CANCEL —
		-- losing the pointer class mid-drag reverts to the pre-scrub value.
		affordanceProofs = {
			pointer = { "LevelPicker pointer affordance: ONE drag target covers the run, at every count" },
			touch = { "LevelPicker touch affordance: the strip declares the 44px effective target" },
			keyboard = { "LevelPicker keyboard affordance: no Adjust key is bound while focus sits outside" },
			gamepad = { "LevelPicker gamepad affordance: at the limit the arrow goes back to navigation" },
			hotSwitch = { "LevelPicker hot-switch: losing the pointer mid-scrub CANCELS back, it never commits" },
		},
	},
	-- scaffold: new control rows are appended above this line (anchor — keep)

	-- ===== leaf primitives (src/class_contract.luau classes) =========
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
	-- Stage (ViewportFrame adoption 2026-08-08): the engine-content box. It draws a
	-- scene and owns no input surface at all — interaction is composed AROUND it by
	-- the consumer (a Grip sibling to orbit, a Button overlay to act), so the
	-- four-input story belongs to those controls, not to the picture.
	{ name = "Stage", kind = "leaf", inputProofs = false, affordanceProofs = false },
	-- Foreign (ADR-0034): the 2-D sibling of Stage — a box for a GuiObject Facet
	-- does not wrap. It owns no input surface either, and for a stronger reason:
	-- the framework has never seen the content, so it could not route input to it
	-- if it wanted to. The four-input story belongs to the controls composed
	-- around the box, exactly as it does for a Stage.
	{ name = "Foreign", kind = "leaf", inputProofs = false, affordanceProofs = false },
	{ name = "Text", kind = "leaf", inputProofs = false, affordanceProofs = false },
	{ name = "Image", kind = "leaf", inputProofs = false, affordanceProofs = false },
	{ name = "Anchor", kind = "leaf", inputProofs = false, affordanceProofs = false },
	{ name = "Grid", kind = "leaf", inputProofs = false, affordanceProofs = false },
	-- the row grid's row (parity round 2 §2.2): pure layout, exactly as `Grid` is.
	-- It owns no focus surface and no semantic action of its own — its CELLS keep
	-- theirs, in declaration order, which is what makes a row grid navigable
	-- without a rule of its own
	{ name = "GridRow", kind = "leaf", inputProofs = false, affordanceProofs = false },
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
