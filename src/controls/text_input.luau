--!strict
local blueprint = require("../blueprint")
-- TextInput control (§17 Phase 5 expansion; the single-line text-field
-- informed). A COMPOSITE over shipped primitives: a ZStack of the new
-- `TextField` leaf primitive (the headless seam the engine maps to a TextBox)
-- plus an optional trailing clear Button shown via the ONE structural seam
-- (UI.When on a `clearVisible` memo). The OWNER holds the `value` signal — the
-- control never creates it (§10.5: state that must outlive the control belongs
-- to the caller). The field's `text` prop is a binding on `value`, so an
-- accepted edit relabels the field with zero structural churn.
--
-- Text-entry-mode handshake (the load-bearing design work): while a field is
-- EDITING, keystrokes are text, not semantic actions. Entering edit raises a
-- high-priority SINKING InputContext that swallows the navigation vocabulary
-- (arrows / D-pad) so typing never moves focus, and binds Cancel (ButtonB) to
-- revert. Activate (Return / ButtonA) is deliberately NOT sunk: re-activating
-- while editing is an idempotent no-op, and sinking the presenter's shared
-- Activate release would corrupt its Bool state and break keyboard/gamepad
-- re-entry. Commit-on-Enter and focus-loss arrive from the ENGINE through the
-- render-adapter text seam (setTextInputHandlers -> onFocusLost), matching a
-- real TextBox which consumes Return itself. Desktop Escape is engine-reserved
-- (D1): the adapter reports it as onFocusLost("cancel").
--
-- Value model: every proposed edit (typing, clear, engine-reported text) is
-- rejected if it is not valid UTF-8, then clamped at the maxLength boundary,
-- then validated; only an accepted change writes `value` and fires onChange.
-- The engine view may briefly diverge past
-- the model when an edit is rejected/clamped; commit/blur reconciles it (the
-- model keeps the last accepted value). Engine-free; Lune-tested in
-- tests/text_input.spec.luau.

local controlContract = require("../class_contract")
local coreContract = require("../core/contract")
local contribution = require("../input/contribution")
local specGuard = require("../spec_guard")
local surfaceEnv = require("../env/surface_env")
local paths = require("../paths")
local rectLib = require("../rect")
local chromeSlots = require("../tokens/chrome_slots")
local themePackage = require("../themes/package")
local themeSnapshot = require("../themes/snapshot")

-- a node id is interpolated into a Lua PATTERN below, so its magic characters
-- have to be escaped first. Module scope, not per-instance: it is a pure
-- function of its argument and every `build()` used to allocate its own
-- (Step 5.5 cleanup ledger C-06).
local patternEscape = paths.escape

local text_input = {}

type StringSignal = coreContract.Signal<string>
export type Spec<V = StringSignal> = {
	presentation: ("plain" | "search" | "number")?,
	numericValue: coreContract.Signal<number>?,
	min: number?,
	max: number?,
	parse: ((string) -> number?)?,
	format: ((number) -> string)?,
	multiline: boolean?,
	height: blueprint.Bound<blueprint.Dim>?,
	onCancel: (() -> ())?,
	enabled: (boolean | coreContract.Readable<boolean>)?,
	id: string?,
	value: V, -- Signal<string>: the field text (owner-held)
	onChange: ((text: string) -> ())?, -- live: every accepted edit while typing
	onCommit: ((text: string, reason: "enter" | "focusLost" | "submit") -> ())?, -- Enter / focus loss
	placeholder: string?,
	disabled: blueprint.Bound<boolean>?, -- boolean | Signal<boolean>
	-- Intent metadata only; Roblox has no public native keyboard-type setter.
	keyboardType: ("default" | "numeric" | "email" | "phone")?,
	-- submitLabel: declared Return-key label hint (data). There is NO reachable
	-- public engine surface for it — TextBox.ReturnKeyType is [Hidden,
	-- NotScriptable] (platform verifier correction 2026-07-21; robloxapi.github
	-- .io/ref/class/TextBox.html) — so it is never applied to the engine (justified engine-absent
	-- exception), carried as intent parity with keyboardType-as-data.
	submitLabel: ("default" | "done" | "go" | "next" | "search" | "send")?,
	clearButton: boolean?, -- trailing × affordance; sugar for clearButtonMode = "always"
	-- WHEN the trailing ✕ is offered, spelled the way the platform convention spells it
	-- (the conventional clear-button modes), because that vocabulary already exists in
	-- every designer's head and the four states are the four real answers:
	--   "never"          no affordance at all (the default)
	--   "whileEditing"   only while the field has focus — the search-field
	--                    convention, and the one that stops a static list of
	--                    filled fields from being a wall of ✕ glyphs
	--   "unlessEditing"  only while it does NOT have focus (a settings row that
	--                    offers "clear this" at rest and gets out of the way once
	--                    you are typing)
	--   "always"         whenever there is text to clear
	-- Every mode is additionally gated on "there is text" and "not disabled":
	-- an empty field has nothing to clear and a disabled one may not.
	clearButtonMode: ("never" | "whileEditing" | "unlessEditing" | "always")?,
	maxLength: number?, -- accepted text clamped at the value-model boundary
	validate: ((proposed: string) -> string?)?, -- accept(normalized) | nil=reject
	-- CALLER-OWNED VALIDITY. A false->true edge shakes the field once (see the
	-- shake block in `build`); the LEVEL is never painted, so the caller still owns
	-- whatever the player reads — the number presentation's own danger-tinted
	-- message is the model. Decorative by construction: reduced motion drops it.
	invalid: coreContract.Readable<boolean>?,
	env: any?, -- Environment: enables keyboard-occlusion keep-visible
	actionSystem: any?, -- injected: enables the text-entry sinking context
}

-- the closed set for `clearButtonMode`. A mode nobody recognises must be an
-- error at BUILD and not a field that silently never offers a ✕ — the enum-props-
-- accept-any-string lesson, applied to a spec field the schema never sees.
local CLEAR_MODES: { [string]: boolean } = {
	never = true,
	whileEditing = true,
	unlessEditing = true,
	always = true,
}

-- theme metrics, resolved on every solve
local FIELD_HEIGHT = "controls.textInput.fieldHeight"
local CLEAR_SIZE = "controls.textInput.clearSize"
-- gap between the trailing clear × and the field's right edge; negative because
-- the button is anchored to that edge and pulled inward
local CLEAR_INSET = "-s"
-- NOT a theme metric: this is the safety margin between the field and the
-- ENGINE's on-screen keyboard, a platform distance rather than a style choice
local KEEP_VISIBLE_MARGIN = 8 -- px gap kept between field bottom and keyboard top
-- above the presenter's modal band (base nav 1500; each modal +500 from 2000):
-- a text field's keystrokes must out-sink every navigation context beneath it.
local TEXT_ENTRY_PRIORITY = 10000

local function isReadable(v: any): boolean
	return type(v) == "table" and (v.kind == "signal" or v.kind == "memo")
end

local rectsEqual = rectLib.equal

-- clamp `s` to at most `maxLen` Unicode scalars (grapheme-approximate; the
-- engine reports whole graphemes so this matches at the value boundary)
local function truncate(s: string, maxLen: number?): string
	if maxLen == nil then
		return s
	end
	local len = utf8.len(s)
	if len == nil or len <= maxLen then
		return s
	end
	local endOffset = utf8.offset(s, maxLen + 1)
	if endOffset == nil then
		return s
	end
	return string.sub(s, 1, endOffset - 1)
end

-- CLOSED SPEC (constitution §4). Exactly the fields this control
-- reads — an unknown one is an authoring mistake, never a silent no-op.
local TEXT_INPUT_KEYS = specGuard.keySet({
	"presentation",
	"numericValue",
	"min",
	"max",
	"parse",
	"format",
	"actionSystem",
	"clearButton",
	"clearButtonMode",
	"disabled",
	"enabled",
	"env",
	"id",
	"keyboardType",
	"maxLength",
	"multiline",
	"height",
	"invalid",
	"onCancel",
	"onChange",
	"onCommit",
	"placeholder",
	"submitLabel",
	"validate",
	"value",
})

function text_input.build(Facet: any, core: any, spec: Spec)
	specGuard.assertKnownKeys("newTextInput", spec, TEXT_INPUT_KEYS, "spec")
	assert(
		spec.enabled == nil or spec.disabled == nil,
		"TextInput: do not specify both enabled and disabled; use enabled"
	)
	assert(spec.multiline == nil or type(spec.multiline) == "boolean", "TextInput: multiline must be a boolean")

	for _, name in { "enabled", "disabled" } do
		local value = spec[name]
		if isReadable(value) then
			value = value:get()
		end
		assert(value == nil or type(value) == "boolean", `TextInput: {name} must be boolean or readable boolean`)
	end
	assert(spec.clearButton == nil or type(spec.clearButton) == "boolean", "TextInput: clearButton must be boolean")
	assert(
		spec.invalid == nil or (isReadable(spec.invalid) and type(spec.invalid:get()) == "boolean"),
		"TextInput: invalid must be a caller-owned Signal<boolean> (a readable boolean; a memo over the value is fine)"
	)

	local presentation = spec.presentation or "plain"
	assert(
		presentation == "plain" or presentation == "search" or presentation == "number",
		"TextInput: presentation must be plain | search | number"
	)
	if presentation == "number" then
		assert(
			type(spec.numericValue) == "table"
				and spec.numericValue.kind == "signal"
				and type(spec.numericValue:get()) == "number"
				and spec.numericValue:get() == spec.numericValue:get()
				and math.abs(spec.numericValue:get()) < math.huge,
			"TextInput: numericValue must be a caller-owned Signal<number>"
		)
		assert(spec.multiline ~= true, "TextInput: numeric entry must be single-line")
		assert(
			spec.min == nil or (type(spec.min) == "number" and spec.min == spec.min and math.abs(spec.min) < math.huge),
			"TextInput: min must be finite"
		)
		assert(
			spec.max == nil or (type(spec.max) == "number" and spec.max == spec.max and math.abs(spec.max) < math.huge),
			"TextInput: max must be finite"
		)
		assert(spec.min == nil or spec.max == nil or spec.min <= spec.max, "TextInput: min must not exceed max")
	else
		assert(
			spec.numericValue == nil
				and spec.min == nil
				and spec.max == nil
				and spec.parse == nil
				and spec.format == nil,
			"TextInput: numericValue, bounds, parse and format require presentation number"
		)
	end
	for _, name in { "parse", "format", "validate", "onChange", "onCommit", "onCancel" } do
		assert(spec[name] == nil or type(spec[name]) == "function", `TextInput: {name} must be a function`)
	end
	assert(
		spec.maxLength == nil
			or (
				type(spec.maxLength) == "number"
				and spec.maxLength >= 0
				and spec.maxLength < math.huge
				and spec.maxLength % 1 == 0
			),
		"TextInput: maxLength must be a nonnegative integer"
	)
	local UI = Facet.UI
	local id = spec.id or "TextInput"
	local scope = core:scope(`text_input-{id}`)

	-- must be a SETTABLE signal: the control calls value:set on every accepted
	-- edit, so a read-only Memo (kind "memo", whose :set asserts) would pass a
	-- bare readable check and then error on the first keystroke — reject it at
	-- BUILD
	assert(
		type(spec.value) == "table" and (spec.value :: any).kind == "signal",
		`TextInput '{id}': value must be a settable Signal of the field text (owner-held); `
			.. `a read-only Memo cannot be edited (it would error on the first keystroke)`
	)
	assert(type(spec.value:get()) == "string", "TextInput: value must hold a string")
	local KEYBOARD_TYPES = { default = true, numeric = true, email = true, phone = true }
	assert(
		spec.keyboardType == nil or KEYBOARD_TYPES[spec.keyboardType] == true,
		`TextInput '{id}': keyboardType must be one of default|numeric|email|phone (got '{tostring(spec.keyboardType)}')`
	)
	local SUBMIT_LABELS = { default = true, done = true, go = true, next = true, search = true, send = true }
	assert(
		spec.submitLabel == nil or SUBMIT_LABELS[spec.submitLabel] == true,
		`TextInput '{id}': submitLabel must be one of default|done|go|next|search|send (got '{tostring(spec.submitLabel)}')`
	)

	--[[ THE ENVIRONMENT THIS FIELD ADAPTS TO. `env` was an optional key
		and three behaviours were gated on it: the keep-visible offset that lifts
		the field off the on-screen keyboard, the touch-at-edit-start snapshot, and
		the dock-mid-edit commit. Without it `occlusionOffset` stayed 0 — measured:
		the field sits UNDER the keyboard and nothing says so — which is the audit's
		D-3 cell. The surface publishes its environment on the core this control was
		built with, so it now arrives with no authoring; a field with no environment
		anywhere refuses to construct, in `tab_view`'s shape, because a text field
		that cannot see the keyboard is the one control whose silent degradation the
		player meets first. ]]
	local env = (
		surfaceEnv.resolve(
			"newTextInput",
			id,
			core,
			spec.env,
			"a text field lifts itself off the on-screen keyboard, and ends an edit when the editing surface goes away"
		)
	)

	-- control-owned state (selection/value lives in the owner's signal)
	local validationError = scope:own(core:signal(""))
	--[[ THE SHAKE (transitions round 2026-09-12). Four legs on the paint-only
		`offset`, +/-8 px, at 0/80/140/200/240 ms. It is a NUDGE, not a move: the
		solver never sees `offset`, so the rect the hit test, the focus order and
		every sibling's layout read stays exactly where it was for the whole
		sequence.

		The shake is DECORATIVE — the information is the danger-tinted message
		(number presentation) or whatever the caller shows beside the field — so a
		reduced-motion session drops it whole. That is the timeline's own policy and
		not a second branch here: under `reduced` it fast-forwards every beat and
		every terminal on the frame it starts, which lands on 0 with nothing painted
		in between.

		Every beat declares `terminal = leg(0)`, so an `interrupt()` — a second
		invalid edge arriving mid-shake — puts the field back at rest on the
		interrupt frame instead of stranding it 8 px off centre. ]]
	local shakeOffset = scope:own(core:signal(0))
	local motionClock: any = nil
	local shaking: any = nil
	local SHAKE_PX = 8
	local function shake()
		if motionClock == nil then
			-- no presenter, no clock, no motion (the same degradation
			-- `bindActionSystem`/`bindController` already declare)
			return
		end
		if shaking ~= nil then
			shaking:interrupt()
			shaking = nil
		end
		local function leg(x: number)
			return function()
				shakeOffset:set(x)
			end
		end
		local rest = leg(0)
		local playing = motionClock:timeline({
			beats = {
				{ at = 0, run = leg(-SHAKE_PX), terminal = rest },
				{ at = 0.08, run = leg(SHAKE_PX), terminal = rest },
				{ at = 0.14, run = leg(-SHAKE_PX * 0.5), terminal = rest },
				{ at = 0.2, run = leg(SHAKE_PX * 0.25), terminal = rest },
				{ at = 0.24, run = rest, terminal = rest },
			},
			onDone = function()
				shaking = nil
				shakeOffset:set(0)
			end,
		})
		-- a reduced-motion (or already-complete) timeline ran inside the call
		-- above, so `onDone` fired BEFORE this assignment: only a still-running
		-- one is worth holding on to for the next `interrupt()`
		if not playing:isDone() then
			shaking = playing
		end
	end
	-- the number presentation's own invalid edge. Every rejected commit shakes,
	-- including a repeat of the same rejection — that retry is exactly when the
	-- nudge is worth the most.
	local function rejectWith(message: string)
		validationError:set(message)
		shake()
	end
	if spec.invalid ~= nil then
		-- the EDGE, not the level: a field that is already invalid when it mounts
		-- has nothing to announce, and a caller re-setting `true` over `true` is
		-- not a new rejection. `core:observe` baselines on the current value and
		-- de-duplicates, so this only ever sees a real change.
		local was = spec.invalid:get()
		scope:own(core:observe(spec.invalid, function(now)
			if now == true and was ~= true then
				shake()
			end
			was = now
		end))
	end
	local disposed = false
	local editing = scope:own(core:signal(false))
	local fieldRect = scope:own(core:signal(nil :: any)) -- solved rect (occlusion)
	local editSnapshot: string = "" -- value at edit-entry (cancel target)
	local fieldFullPath: string? = nil -- learned from the activate that begins editing
	local viewportHeight = if spec.multiline then scope:own(core:signal(0)) else nil
	local latestRectOf: ((string) -> any)? = nil
	local renderController: any = nil
	-- does the surface this field lives on reserve the host app's own chrome band?
	-- Bound by the presenter (`bindController`'s additive second argument); true
	-- until then, which is what the keep-visible arithmetic always assumed
	local ownerReservesAppChrome = true
	-- hot-switch (UI-PARADIGM-002): was touch (the on-screen-keyboard entry
	-- surface) live when this edit began? Used to detect the dock CANCEL — touch
	-- leaving mid-edit with no hardware keyboard to supersede it.
	local touchLiveAtEditStart = false

	-- disabled resolves a boolean or a Signal<boolean> to a plain memo; the
	-- field's enabled/focusable ride its negation
	local inheritedDisabled = scope:own(core:signal(false))
	local disabledMemo = scope:own(core:memo(function(use)
		if use(inheritedDisabled) then
			return true
		end
		if spec.enabled ~= nil then
			return (if isReadable(spec.enabled) then use(spec.enabled) else spec.enabled) == false
		end
		local d = spec.disabled
		if d == nil then
			return false
		end
		if isReadable(d) then
			return use(d) == true
		end
		return d == true
	end))
	local enabledMemo = scope:own(core:memo(function(use)
		return not use(disabledMemo)
	end))
	-- the clear affordance: the declared MODE, then the two gates every mode
	-- shares — there must be something to clear, and a disabled field may not.
	local clearMode = spec.clearButtonMode
		or (if spec.clearButton or presentation == "search" then "always" else "never")
	if CLEAR_MODES[clearMode] == nil then
		error(
			`Facet newTextInput('{id}'): clearButtonMode '{tostring(spec.clearButtonMode)}' is not a mode `
				.. `(never | whileEditing | unlessEditing | always)`,
			0
		)
	end
	local clearVisible = scope:own(core:memo(function(use)
		if clearMode == "never" then
			return false
		end
		if use(disabledMemo) then
			return false
		end
		if use(spec.value) == "" then
			return false
		end
		-- the two focus-sensitive modes read `editing`, so the affordance appears
		-- and disappears with the caret and nothing else has to drive it
		if clearMode == "whileEditing" then
			return use(editing) == true
		elseif clearMode == "unlessEditing" then
			return use(editing) ~= true
		end
		return true
	end))

	-- keep-visible offset: while editing with an env, the minimal upward dy that
	-- keeps the field fully above the on-screen keyboard (+ margin); 0 when
	-- clear. fieldRect is read reactively but is stable during an edit.
	local keepVisibleOffset = scope:own(core:memo(function(use)
		if not use(editing) then
			return 0
		end
		local occ = use(env:get("keyboardOcclusionRect"))
		if type(occ) ~= "table" then
			return 0
		end
		local rect = use(fieldRect)
		if type(rect) ~= "table" then
			return 0
		end
		local overlap = (rect.y + rect.h) + KEEP_VISIBLE_MARGIN - occ.y
		return if overlap > 0 then overlap else 0
	end))

	-- ---- edit-mode sinking context (lazy; owned by the control scope) -------
	-- the action system that raises the sink context: either injected via
	-- spec.actionSystem (back-compat) OR bound by the presenter at present time
	-- via api.bindActionSystem (auto-wiring seam). First writer wins,
	-- so injection + auto-binding never double-create the context.
	local actionSystemRef: any = spec.actionSystem
	local editContext: any = nil
	local cancelEdit -- forward
	local function ensureEditContext()
		if editContext ~= nil or actionSystemRef == nil then
			return
		end
		local ctx = actionSystemRef.createContext({
			name = `TextEntry-{id}`,
			priority = TEXT_ENTRY_PRIORITY,
			sink = true,
		})
		-- swallow the navigation vocabulary: arrows/D-pad must not move focus
		-- while editing (Activate is intentionally left un-sunk — see header)
		local swallow = ctx.createAction("Swallow", "Direction1D")
		for _, key in { "Up", "Down", "Left", "Right", "DPadUp", "DPadDown", "DPadLeft", "DPadRight" } do
			swallow.bind({ keyCode = key, direction = 0 })
		end
		local cancel = ctx.createAction("Cancel", "Bool")
		cancel.bind({ keyCode = "ButtonB" })
		cancel.onPressed(function()
			cancelEdit()
		end)
		ctx.setEnabled(false) -- enabled only while editing
		editContext = ctx
		scope:own(function()
			if editContext ~= nil then
				editContext.destroy()
				editContext = nil
			end
		end)
	end

	-- ---- value pipeline ------------------------------------------------------
	-- reject-invalid-UTF-8 -> clamp -> validate -> accept; returns true iff
	-- `value` actually changed. INVARIANT: the model never accepts a byte
	-- sequence that is not valid UTF-8 — a malformed engine report is rejected
	-- outright (value unchanged, no onChange), the same as a validate-nil, and
	-- so can never slip past maxLength via a truncate no-op.
	local function applyProposed(proposed: string): boolean
		if disposed or disabledMemo:get() then
			return false
		end
		if utf8.len(proposed) == nil then
			return false -- rejected: not valid UTF-8
		end
		local clamped = truncate(proposed, spec.maxLength)
		local accepted: string? = clamped
		if spec.validate ~= nil then
			accepted = spec.validate(clamped)
		end
		if accepted == nil then
			return false -- rejected: value unchanged, no onChange
		end
		if accepted ~= spec.value:get() then
			spec.value:set(accepted)
			if spec.onChange ~= nil then
				spec.onChange(accepted)
			end
			return true
		end
		return false -- accepted but unchanged (e.g. clamp produced the same text)
	end

	-- ---- editing lifecycle ---------------------------------------------------
	local function beginEditing()
		if disposed then
			-- a late Activate racing dispose (stale tap/handle) must be a
			-- harmless no-op, never an own-into-disposed-scope fault
			-- (Studio drive F2, 2026-07-21)
			return
		end
		if disabledMemo:get() then
			return -- disabled fields are not editable
		end
		if editing:get() then
			return -- idempotent: a second Activate while editing is a no-op
		end
		editSnapshot = spec.value:get()
		-- snapshot whether touch was the live entry surface at edit-start, so a
		-- later touch-loss (dock) can be told apart from a device that was never
		-- part of this edit (hot-switch CANCEL gate, UI-PARADIGM-002)
		local classes = env:get("interactionClasses"):get()
		touchLiveAtEditStart = type(classes) == "table" and classes.touch == true
		editing:set(true)
		ensureEditContext()
		if editContext ~= nil then
			editContext.setEnabled(true)
		end
		-- capture the field's solved rect for keep-visible (learned path)
		if latestRectOf ~= nil and fieldFullPath ~= nil then
			fieldRect:set(latestRectOf(fieldFullPath))
		end
	end

	local function endEditing()
		if not editing:get() then
			return
		end
		editing:set(false)
		if editContext ~= nil then
			editContext.setEnabled(false)
		end
	end

	scope:own(core:observe(disabledMemo, function(disabled)
		if disabled then
			endEditing()
		end
	end))

	-- commit (Enter / focus-loss): validate the committed text defensively (all
	-- edits already validated, so this is normally a no-op), fire onCommit
	local function commit(reason: string)
		if disposed or disabledMemo:get() or not editing:get() then
			return
		end

		local text = spec.value:get()
		if presentation == "number" then
			local ok, number = pcall(spec.parse or tonumber, text)
			if disposed or disabledMemo:get() then
				return
			end
			local message = ""
			if not ok or type(number) ~= "number" or number ~= number or math.abs(number) == math.huge then
				message = "Enter a valid number."
			elseif spec.min ~= nil and number < spec.min then
				message = "Enter a value of at least " .. tostring(spec.min) .. "."
			elseif spec.max ~= nil and number > spec.max then
				message = "Enter a value of at most " .. tostring(spec.max) .. "."
			end
			if message ~= "" then
				rejectWith(message)
				endEditing()
				return
			end
			local formattedOk, formatted = pcall(spec.format or tostring, number)
			if disposed or disabledMemo:get() then
				return
			end
			if not formattedOk or type(formatted) ~= "string" then
				rejectWith("The number could not be formatted.")
				endEditing()
				return
			end
			if spec.validate ~= nil then
				local valid, normalized = pcall(spec.validate, formatted)
				if disposed or disabledMemo:get() then
					return
				end
				if not valid or type(normalized) ~= "string" or utf8.len(normalized) == nil then
					rejectWith("The formatted number is not accepted.")
					endEditing()
					return
				end
				formatted = normalized
			end
			if utf8.len(formatted) == nil or (spec.maxLength and utf8.len(formatted) > spec.maxLength) then
				rejectWith("The formatted number exceeds the text limit.")
				endEditing()
				return
			end
			validationError:set("")
			core:transaction(function()
				spec.numericValue:set(number)
				spec.value:set(formatted)
			end)
			text = formatted
		end
		if spec.validate ~= nil and presentation ~= "number" then
			local normalized = spec.validate(text)
			if normalized ~= nil and normalized ~= text then
				spec.value:set(normalized)
				text = normalized
			end
		end
		endEditing()
		if spec.onCommit ~= nil then
			spec.onCommit(text, reason :: any)
		end
	end

	-- cancel: restore the pre-edit snapshot. The revert writes `value` directly
	-- (owner + field binding update) but fires NO onChange — onChange is for
	-- user edits, not the revert; and NO onCommit.
	cancelEdit = function()
		if not editing:get() then
			return
		end
		if spec.value:get() ~= editSnapshot then
			spec.value:set(editSnapshot)
		end
		endEditing()
		if spec.onCancel then
			spec.onCancel()
		end
	end

	-- ---- hot-switch: in-flight class-flip semantics (matrix §C; UI-PARADIGM-002)
	-- Text entry CARRIES across a device ARRIVING mid-edit (a hardware keyboard
	-- supersedes the on-screen one; editing + the sinking context survive with the
	-- text intact) — nothing to do, the edit is class-agnostic. The one CANCEL: the
	-- editing SURFACE class goes away mid-edit — a dock dismisses the on-screen
	-- keyboard (touch was live at edit-start, touch leaves the live set) and no
	-- hardware keyboard remains to supersede it. The engine may not report that as
	-- a FocusLost, so end the edit through the EXISTING commit path: the sink
	-- context comes down (endEditing), navigation resumes, and the value model
	-- keeps the last accepted text (never dropped). Keyed off the LIVE class set, never preferredInput alone.
	do
		scope:own(core:observe(env:get("interactionClasses"), function(classes)
			if type(classes) ~= "table" then
				return
			end
			if editing:get() and touchLiveAtEditStart and classes.touch ~= true and classes.keyboard ~= true then
				commit("focusLost")
			end
		end))
	end

	-- clear affordance: empties the value as a USER edit (runs the pipeline so
	-- validate/maxLength apply); fires onChange, does NOT commit. Focus returns
	-- to the field naturally: the clear button vanishes (value empty) and the
	-- focus graph moves to the nearest survivor on the next refresh.
	local function clearValue()
		if disabledMemo:get() then
			return
		end
		applyProposed("")
	end

	-- ---- render-adapter text handlers (engine -> model) ----------------------
	local function onTextChanged(text: string)
		if editing:get() then
			applyProposed(text)
		end
	end
	-- engine-initiated focus (native TextBox tap / gamepad A on the real engine):
	-- learn the field's full path HERE — on that path handleActivate never runs
	-- (setActivateHandler is a no-op for a non-GuiButton), so this is the only
	-- place the path is learned, and beginEditing must end up occlusion-capable
	-- (F1). Idempotent with the activate path (which also learns the path).
	local function onFocusGained(path: string?)
		if path ~= nil then
			fieldFullPath = path
		end
		beginEditing()
	end
	local function onFocusLost(reason: string)
		if reason == "cancel" then
			cancelEdit()
		else
			commit(reason)
		end
	end

	-- ---- public api ----------------------------------------------------------
	local api = {} :: any
	api.editing = editing
	api.submit = function()
		commit("submit")
	end
	api.cancel = cancelEdit
	api.keepVisibleOffset = keepVisibleOffset
	function api.bindController(controller, reserveAppChrome)
		renderController = controller
		ownerReservesAppChrome = reserveAppChrome ~= false
	end

	-- presenter auto-wiring seam: bind the action system that raises
	-- the edit-mode sink context. Idempotent + guarded so spec.actionSystem
	-- injection and this never double-create the context (first writer wins).
	function api.bindActionSystem(sys: any)
		if actionSystemRef == nil then
			actionSystemRef = sys
		end
	end

	-- TAB LEAVES THROUGH THE COMMIT PATH (roadmap Step 8). Desktop Tab out
	-- of a text field means "I am done with this field" — so it runs the SAME
	-- commit the Return key and a focus loss run (defensive re-validate, then
	-- `onCommit`), ends the edit, and returns false so the presenter advances the
	-- ring. It never types a tab character (the field is out of editing before the
	-- ring moves, and every accepted value still goes through `applyProposed`), and
	-- it never advances out of a still-open edit. Not editing: nothing to consume,
	-- so Tab is plain traversal.
	-- (the presenter only offers this to contributions whose mounted path is a
	-- prefix of the focused one, so `path` is always inside this control)
	function api.handleTraverse(_path: string, _direction: number): boolean
		if not editing:get() then
			return false
		end
		commit("focusLost")
		return false -- the edit is closed: let the ring move on
	end

	-- the field is a single-cell focus group (one horizontal group); a disabled
	-- field contributes nothing (its field opts out of focus). rootNode is the
	-- control's mounted root (the Anchor), so the field path is <root>/Field.
	function api.focusGroups(rootNode: any): { any }
		if not enabledMemo:get() then
			return {}
		end
		return {
			{
				name = `{id}:field`,
				axis = "horizontal",
				entry = "first",
				order = {
					rootNode.path .. (if presentation == "number"
						then "/Input/Field"
						elseif spec.multiline then "/Viewport/Field"
						else "/Field"),
				},
			},
		}
	end

	local idPattern = patternEscape(id) .. (if presentation == "number" then "/Input" else "")

	-- routes a presenter/tap Activate; returns true when the path was ours.
	-- The field enters editing; the clear affordance empties the value.
	function api.handleActivate(path: string, _meta: any?): boolean
		if string.match(path, `/{idPattern}{if spec.multiline then "/Viewport" else ""}/Field$`) ~= nil then
			fieldFullPath = path -- learn our full path for keep-visible
			beginEditing()
			return true
		end
		if string.match(path, `/{idPattern}/ClearWhen/then/Clear$`) ~= nil then
			clearValue()
			return true
		end
		return false
	end

	-- fed the controller's rectOf after each layout (presenter onGeometry seam):
	-- store it (so beginEditing can capture) and refresh the field rect while
	-- editing, guarded by equality so a stable rect never churns the memo
	function api.syncGeometry(rectOf: (string) -> any, rootNode: any?)
		if disposed then
			return
		end
		if rootNode ~= nil then
			inheritedDisabled:set(controlContract.isDisabled(rootNode))
		end
		latestRectOf = rectOf
		if spec.multiline and rootNode then
			local frame = rectOf(rootNode.path)
			local metrics = env:get("themeMetrics"):get()
			local inset = metrics.chromeInsets and metrics.chromeInsets.field
			local height = if frame then math.max(0, frame.h - (if inset then inset.top + inset.bottom else 0)) else 0
			if height ~= viewportHeight:get() then
				viewportHeight:set(height)
			end
		end
		if fieldFullPath ~= nil and editing:get() then
			local r = rectOf(if spec.multiline and rootNode then rootNode.path else fieldFullPath)
			if spec.multiline and rootNode and renderController then
				-- Reveal the editor viewport inside its ancestor scroller before lifting
				-- the surface. Translating an already clipped field cannot reveal it.
				renderController.scrollToVisible(rootNode.path)
				local painted = renderController.screenRectOf(rootNode.path)
				if painted then
					r = { x = painted.x, y = painted.y + keepVisibleOffset:get(), w = painted.w, h = painted.h }
				end
			end
			if not rectsEqual(fieldRect:get(), r) then
				fieldRect:set(r)
			end
		end
	end

	-- ---- blueprint -----------------------------------------------------------
	-- The composite is an Anchor overlay: the TextField fills it (a fill child
	-- stretches to the full anchor), and the clear button is anchored to the
	-- RIGHT edge (vertically centered) and pulled IN by CLEAR_INSET via offsetX.
	-- (An Anchor honors per-child anchor/offsetX — a ZStack does not, and a
	-- ZStack right-padding insets the field AND the ✕ equally, leaving no gap
	-- between them — the WP7 drive defect.) The ✕ glyph is × (U+00D7): the
	-- dingbat ✕ (U+2715) is absent from BuilderSans and rendered as tofu
	-- (live-confirmed in the gallery drive).
	local function clearButtonView(): any
		return UI.Button({
			id = "Clear",
			label = "Clear",
			align = "center",
			children = {
				UI.Spacer({ id = "BeforeMark" }),
				chromeSlots.attachHint(
					UI.Text({
						id = "Mark",
						text = themePackage.iconGlyph("close"),
						textSize = "control",
						textAlign = "center",
					}),
					{ icon = "close" }
				),
				UI.Spacer({ id = "AfterMark" }),
			},
			anchor = "right",
			offsetX = CLEAR_INSET,
			-- A GLYPH CHIP IS NOT A LABELLED BUTTON, and it was being geometried
			-- like one (director round 10, found live 2026-07-26).
			--
			-- `padding = 0`: a Button's default text inset is `controls.button.padding`
			-- — 12 a side — which exists to keep a WORD off a plate's edge. Spent on a
			-- 28px box it leaves 4px for the ×, so the glyph drew at its natural size
			-- outside its own plate. A chip whose entire content is one centred glyph
			-- wants no inset at all.
			--
			-- `minMax`, not `fixed`: 28 is the FLOOR, so flat themes are unchanged to
			-- the pixel, but a package that skins `control` with inset-bearing art
			-- (Glossy Touch reserves 14 a side, Pixel Quest 16) can grow the box for
			-- its own frame instead of reserving that frame out of the glyph's room —
			-- which is how the ✕ ended up outside the button on both of them.
			padding = 0,
			width = { type = "minMax", min = CLEAR_SIZE },
			-- ...AND A CEILING ON THE AXIS THAT HAS ONE (measured 2026-07-27). A
			-- floor alone let the box grow past the thing it lives INSIDE: Pixel
			-- Quest reserves 16px a side, which took a 28px chip to 52 inside a
			-- 44px field, so the ✕ hung out of the field top and bottom. The field's
			-- own height is the honest ceiling, and it is the same metric the field
			-- is built from, so a package that makes its fields taller gets a taller
			-- chip for free. Width needs no ceiling: a field is always far wider
			-- than a glyph plus a frame.
			height = { type = "minMax", min = CLEAR_SIZE, max = FIELD_HEIGHT },
			-- CHIP, so it is not the field's own colour on the field's own
			-- colour. With the default control surface this button was a plate
			-- the same shade as the field it sits inside — invisible on an
			-- a physical phone, where the reporter could not find the clear
			-- affordance at all while a filter was active.
			surface = "chip",
		})
	end

	local defaultHeight = if spec.multiline
		then scope:own(core:memo(function(use)
			local raw = use(env:get("themeMetrics"))
			local metrics = if type(raw) == "table" and raw.controls then raw else themeSnapshot.neutral()
			local height = metrics.controls.textInput.multilineHeight
			local occlusion = use(env:get("keyboardOcclusionRect"))
			if use(editing) and type(occlusion) == "table" then
				local viewport = use(env:get("viewportRect"))
				local insets = use(env:get("coreSafeInsets"))
				--[[ ...and the host's own reserved band when the OWNER surface reserves it:
					above this field for the same reason the platform's row is, and absent
					inside a modal, which takes the screen (`appChromeInsets`, 2026-09-13).

					THE CONDITIONAL `use()` IS SAFE, and that is a claim about the flag
					rather than about this memo. `ownerReservesAppChrome` is not reactive
					and cannot become so: it is one surface's answer, decided once in
					`makeHandle` before a single contribution is bound (and, for an
					anchored surface, INHERITED there from its source), so it is constant
					for as long as this field is mounted. A dependency that appears or
					disappears with a value that can change would be the trap — this one
					changes only by re-presenting the surface, which rebuilds the memo. ]]
				local hostChrome = if ownerReservesAppChrome then use(env:get("appChromeInsets")) else nil
				local hostTop = if type(hostChrome) == "table" then math.max(0, tonumber(hostChrome.top) or 0) else 0
				local room = occlusion.y - viewport.y - (insets.top or 0) - hostTop - KEEP_VISIBLE_MARGIN
				height = math.min(height, math.max(metrics.controls.textInput.fieldHeight, room))
			end
			return { type = "fixed", px = height }
		end))
		else { type = "minMax", min = FIELD_HEIGHT }
	local rootView = UI.Anchor
	local rootSpec = {
		id = if presentation == "number" then "Input" else id,
		width = { type = "fill", weight = 1 },
		height = spec.height or defaultHeight,
		-- the shake, on the FIELD (never the number presentation's outer stack):
		-- the message beneath it is the information and must hold still while the
		-- field it describes moves. `nil` at rest keeps every resting field off the
		-- presentation channel's composition path entirely.
		offset = scope:own(core:memo(function(use)
			local x = use(shakeOffset)
			return if x == 0 then nil else { x = x, y = 0 }
		end)),
		children = {
			UI.TextField({
				id = "Field",
				text = spec.value,
				multiline = spec.multiline,
				surface = "plain",
				-- A centered single line needs horizontal inset; the skin owns
				-- vertical clearance. Multiline keeps its inset on all four sides.
				padding = if spec.multiline
					then nil
					else { left = "controls.textInput.padding", right = "controls.textInput.padding" },

				placeholder = spec.placeholder or (if presentation == "search" then "Search" else nil),
				editing = editing,
				enabled = enabledMemo,
				focusable = enabledMemo,
				maxLength = spec.maxLength,
				keyboardType = spec.keyboardType or "default",
				width = { type = "fill", weight = 1 },
				height = if spec.multiline
					then scope:own(core:memo(function(use)
						return { type = "minMax", min = use(viewportHeight) }
					end))
					else UI.fill(),
				-- engine -> model seam (functions, not engine writes)
				onTextChanged = onTextChanged,
				onFocusGained = onFocusGained,
				onFocusLost = onFocusLost,
			}),

			UI.When({
				id = "ClearWhen",
				condition = clearVisible,
				thenView = clearButtonView,
			}),
		},
	}
	if presentation == "search" then
		rootSpec.padding = { left = "xl" }
		table.insert(
			rootSpec.children,
			chromeSlots.attachHint(
				UI.Text({
					id = "SearchIcon",
					text = themePackage.iconGlyph("facet:search"),
					textSize = "control",
					anchor = "left",
					offsetX = "-xl",
				}),
				{ icon = "facet:search" }
			)
		)
	end
	rootSpec.surface = "chip"
	rootSpec.enabled = if spec.enabled ~= nil
		then spec.enabled
		elseif spec.disabled ~= nil then scope:own(core:memo(function(use)
			return (if isReadable(spec.disabled) then use(spec.disabled) else spec.disabled) ~= true
		end))
		else nil
	rootSpec.children[1] = chromeSlots.attachHint(rootSpec.children[1], { slot = chromeSlots.NO_SLOT })
	if spec.multiline then
		local field = rootSpec.children[1]
		rootSpec.children[1] = UI.ScrollView({
			id = "Viewport",
			width = UI.fill(),
			height = scope:own(core:memo(function(use)
				return { type = "fixed", px = use(viewportHeight) }
			end)),
			padding = { right = "s" },
			children = { field },
		})
	end
	local blueprint = chromeSlots.attachHint(rootView(rootSpec), { slot = "field" })

	if presentation == "number" then
		blueprint = UI.VStack({
			id = id,
			width = UI.fill(),
			gap = "xs",
			children = {
				blueprint,
				UI.Text({
					id = "Validation",
					text = validationError,
					tint = { role = "danger", blend = 1 },
					textSize = "caption",
					width = UI.fill(),
					hidden = scope:own(core:memo(function(use)
						return use(validationError) == ""
					end)),
				}),
			},
		})
	end
	-- deterministic diagnostic summary (§10.2 control contract dump form)
	local function dump()
		return {
			schema = "facet-text_input-dump/1",
			presentation = presentation,
			validationError = validationError:get(),
			numericValue = if spec.numericValue then spec.numericValue:get() else nil,
			id = id,
			value = spec.value:get(),
			multiline = spec.multiline == true,
			editing = editing:get(),
			disabled = disabledMemo:get(),
			placeholderVisible = spec.value:get() == "",
			clearVisible = clearVisible:get(),
			clearButtonMode = clearMode,
			occlusionOffset = keepVisibleOffset:get(),
			-- declared engine-intent hints (data). keyboardType is applied to the
			-- engine behind capability detection; submitLabel has no reachable public
			-- engine surface (justified engine-absent exception) — both stay valid data.
			keyboardType = spec.keyboardType or "default",
			submitLabel = spec.submitLabel or "default",
		}
	end

	return {
		-- attach the input contribution to the root so the presenter auto-wires
		-- the field's four-input story with no consumer opts
		blueprint = contribution.attach(blueprint, {
			focusGroups = api.focusGroups,
			handleActivate = api.handleActivate,
			syncGeometry = api.syncGeometry,
			keepVisibleOffset = keepVisibleOffset,
			bindActionSystem = api.bindActionSystem,
			bindController = api.bindController,
			handleTraverse = api.handleTraverse,
			-- the presenter's own motion clock (contribution.luau bindMotion): the
			-- shake's only time source, so it is headlessly deterministic and a
			-- control mounted WITHOUT a presenter simply never shakes
			bindMotion = function(clock: any)
				motionClock = clock
			end,
		}),
		api = api,
		dump = dump,
		dispose = function()
			-- restore any keep-visible offset BEFORE teardown: ending editing
			-- drives keepVisibleOffset back to 0 while the memo and the
			-- presenter's observer are still live, so disposing the control
			-- mid-occlusion (screen still presented) never leaves the screen
			-- root frozen shifted up. A no-op when not editing
			-- (offset is already 0).
			endEditing()
			disposed = true
			-- ...and stop any shake before the scope goes: the timeline is attached to
			-- the PRESENTER's clock, which outlives this control, so a beat left armed
			-- would keep firing for a node that is no longer in the tree and write a
			-- signal this line is about to dispose
			if shaking ~= nil then
				shaking:interrupt()
				shaking = nil
			end
			scope:dispose()
		end,
	}
end

return text_input
