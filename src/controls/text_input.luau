--!strict
-- Controlled text entry with validation, keyboard avoidance and semantic input.
-- While editing, navigation keys are sunk; Activate remains available so the
-- presenter can receive its matching release. Engine focus loss commits or cancels.

local controlContract = require("../class_contract")
local contribution = require("../input/contribution")
local specGuard = require("../spec_guard")
local surfaceEnv = require("../env/surface_env")
local rectLib = require("../rect")
local chromeSlots = require("../tokens/chrome_slots")
local themePackage = require("../themes/package")
local themeSnapshot = require("../themes/snapshot")
local fieldChrome = require("./field_chrome")
local vocabulary = require("./control_vocabulary")

local text_input = {}

local specTypes = require("../spec_types/text_input")
type StringCell = specTypes.StringCell
export type Spec<V = StringCell> = specTypes.Spec<V>
local CLEAR_MODES: { [string]: boolean } = {
	never = true,
	whileEditing = true,
	unlessEditing = true,
	always = true,
}
local FIELD_HEIGHT = "controls.textInput.fieldHeight"
local CLEAR_SIZE = "controls.textInput.clearSize"
local CLEAR_INSET = "-s"
local KEEP_VISIBLE_MARGIN = 8 -- px gap kept between field bottom and keyboard top
local TEXT_ENTRY_PRIORITY = 10000

local Compose = require("../vendor/compose/core")
local ownedBuild = require("../core/owned_build")
local read = require("../selection_model").read
local function isReadable(v: any): boolean
	return Compose.isReadable(v)
end
local function isWritable(v: any): boolean
	return isReadable(v) and type(v.set) == "function"
end

local rectsEqual = rectLib.equal
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
	-- the shared field chrome (field_chrome.KEYS)
	"label",
	"requiredMark",
	"hint",
	"errorText",
	"leading",
	"trailing",
	"controlSize",
	"appearance",
	"corners",
})

local function build(Facet: any, core: any, spec: Spec, owner: any)
	specGuard.assertKnownKeys("UI.TextInput", spec, TEXT_INPUT_KEYS, "spec")
	assert(
		spec.enabled == nil or spec.disabled == nil,
		"TextInput: do not specify both enabled and disabled; use enabled"
	)
	assert(spec.multiline == nil or type(spec.multiline) == "boolean", "TextInput: multiline must be a boolean")

	for _, name in { "enabled", "disabled" } do
		local value = read(spec[name])
		assert(value == nil or type(value) == "boolean", `TextInput: {name} must be boolean or readable boolean`)
	end
	assert(spec.clearButton == nil or type(spec.clearButton) == "boolean", "TextInput: clearButton must be boolean")
	assert(
		spec.invalid == nil or (isReadable(spec.invalid) and type(read(spec.invalid)) == "boolean"),
		"UI.TextInput: invalid must be a writable Compose cell holding a boolean (a readable boolean; a formula over the value is fine)"
	)

	local presentation = spec.presentation or "plain"
	assert(
		presentation == "plain" or presentation == "search" or presentation == "number",
		"TextInput: presentation must be plain | search | number"
	)
	if presentation == "number" then
		assert(
			isWritable(spec.numericValue)
				and type(read(spec.numericValue)) == "number"
				and read(spec.numericValue) == read(spec.numericValue)
				and math.abs(read(spec.numericValue)) < math.huge,
			"UI.TextInput: numericValue must be a writable Compose cell holding a number"
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
	fieldChrome.assertSpec("UI.TextInput", spec)
	-- a search field already leads with its own mark; a second one beside it would
	-- read as part of the first
	assert(
		spec.leading == nil or presentation ~= "search",
		"UI.TextInput: a search field already leads with its own mark — `leading` would sit beside it "
			.. 'and read as part of it. Use `trailing`, or presentation = "plain" with your own mark.'
	)
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
	assert(
		isWritable(spec.value),
		`UI.TextInput '{id}': value must be a writable Compose cell of the field text (owner-held); `
			.. `a read-only formula cannot be edited (it would error on the first keystroke)`
	)
	assert(type(read(spec.value)) == "string", "TextInput: value must hold a string")
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

	local env = (
		surfaceEnv.resolve(
			"UI.TextInput",
			id,
			core,
			spec.env,
			"a text field lifts itself off the on-screen keyboard, and ends an edit when the editing surface goes away"
		)
	)
	local validationError = Compose.cell("")
	-- the numeric rejection line is the chrome's internal message, outranked by
	-- the caller's `errorText` in one place
	local chrome = fieldChrome.new({
		UI = Facet.UI,
		control = "UI.TextInput",
		spec = spec,
		internalMessage = if presentation == "number" then validationError else nil,
	})

	local nativeTimeline = if Facet.runtime and (spec.invalid ~= nil or presentation == "number")
		then Facet.runtime.timeline({ duration = 0.24, autoplay = false })
		else nil
	local shakeOffset
	if nativeTimeline then
		nativeTimeline:seek(0.24)
		-- Smoothly interpolate the nudge; the solved hit target stays fixed.
		shakeOffset = Compose.formula(function(use)
			if use(env:get("motionPolicy")) == "reduced" then
				return 0
			end
			local elapsed = use(nativeTimeline.progress) * 0.24
			local times, positions = { 0, 0.08, 0.14, 0.2, 0.24 }, { -8, 8, -4, 2, 0 }
			for index = 2, #times do
				if elapsed < times[index] then
					local fraction = (elapsed - times[index - 1]) / (times[index] - times[index - 1])
					return positions[index - 1] + (positions[index] - positions[index - 1]) * fraction
				end
			end
			return 0
		end)
		owner.watch(function(use)
			if use(env:get("motionPolicy")) == "reduced" then
				nativeTimeline:pause()
				nativeTimeline:seek(0.24)
			end
		end)
	else
		shakeOffset = Compose.cell(0)
	end
	local motionClock: any = nil
	local shaking: any = nil
	local SHAKE_PX = 8
	local function shake()
		if nativeTimeline then
			if read(env:get("motionPolicy")) ~= "reduced" then
				nativeTimeline:restart()
			end
			return
		end
		if motionClock == nil then
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
		if not playing:isDone() then
			shaking = playing
		end
	end
	local function rejectWith(message: string)
		validationError:set(message)
		shake()
	end
	if spec.invalid ~= nil then
		local was = read(spec.invalid)
		owner.watch(function(use)
			local now = read(spec.invalid, use)
			if now == true and was ~= true then
				shake()
			end
			was = now
		end)
	end
	local disposed = false
	local editing = Compose.cell(false)
	local fieldRect = Compose.cell(nil :: any) -- solved rect (occlusion)
	local editSnapshot: string = "" -- value at edit-entry (cancel target)
	local fieldFullPath: string? = nil -- learned from the activate that begins editing
	local viewportHeight = if spec.multiline then Compose.cell(0) else nil
	local latestRectOf: ((string) -> any)? = nil
	local renderController: any = nil
	local ownerReservesAppChrome = true
	local touchLiveAtEditStart = false
	local inheritedDisabled = Compose.cell(false)
	local disabledMemo = Compose.formula(function(use)
		if use(inheritedDisabled) then
			return true
		end
		if spec.enabled ~= nil then
			return read(spec.enabled, use) == false
		end
		return read(spec.disabled, use) == true
	end)
	local enabledMemo = Compose.formula(function(use)
		return not use(disabledMemo)
	end)
	local clearMode = spec.clearButtonMode
		or (if spec.clearButton or presentation == "search" then "always" else "never")
	if CLEAR_MODES[clearMode] == nil then
		error(
			`Facet UI.TextInput('{id}'): clearButtonMode '{tostring(spec.clearButtonMode)}' is not a mode `
				.. `(never | whileEditing | unlessEditing | always)`,
			0
		)
	end
	local clearVisible = Compose.formula(function(use)
		if clearMode == "never" then
			return false
		end
		if use(disabledMemo) then
			return false
		end
		if read(spec.value, use) == "" then
			return false
		end
		if clearMode == "whileEditing" then
			return use(editing) == true
		elseif clearMode == "unlessEditing" then
			return use(editing) ~= true
		end
		return true
	end)
	local keepVisibleOffset = Compose.formula(function(use)
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
	end)
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
		owner.own(function()
			if editContext ~= nil then
				editContext.destroy()
				editContext = nil
			end
		end)
	end
	local function applyProposed(proposed: string): boolean
		if disposed or disabledMemo:peek() then
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
		if accepted ~= read(spec.value) then
			spec.value:set(accepted)
			if spec.onChange ~= nil then
				spec.onChange(accepted)
			end
			return true
		end
		return false -- accepted but unchanged (e.g. clamp produced the same text)
	end
	local function beginEditing()
		if disposed then
			return
		end
		if disabledMemo:peek() then
			return -- disabled fields are not editable
		end
		if editing:peek() then
			return -- idempotent: a second Activate while editing is a no-op
		end
		editSnapshot = read(spec.value)
		local classes = env:get("interactionClasses"):peek()
		touchLiveAtEditStart = type(classes) == "table" and classes.touch == true
		editing:set(true)
		ensureEditContext()
		if editContext ~= nil then
			editContext.setEnabled(true)
		end
		if latestRectOf ~= nil and fieldFullPath ~= nil then
			fieldRect:set(latestRectOf(fieldFullPath))
		end
	end

	local function endEditing()
		if not editing:peek() then
			return
		end
		editing:set(false)
		if editContext ~= nil then
			editContext.setEnabled(false)
		end
	end

	owner.watch(function(use)
		local disabled = use(disabledMemo)
		if disabled then
			endEditing()
		end
	end)
	local function commit(reason: string)
		if disposed or disabledMemo:peek() or not editing:peek() then
			return
		end

		local text = read(spec.value)
		if presentation == "number" then
			local ok, number = pcall(spec.parse or tonumber, text)
			if disposed or disabledMemo:peek() then
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
			if disposed or disabledMemo:peek() then
				return
			end
			if not formattedOk or type(formatted) ~= "string" then
				rejectWith("The number could not be formatted.")
				endEditing()
				return
			end
			if spec.validate ~= nil then
				local valid, normalized = pcall(spec.validate, formatted)
				if disposed or disabledMemo:peek() then
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
			core.reactor:batch(function()
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
	cancelEdit = function()
		if not editing:peek() then
			return
		end
		if read(spec.value) ~= editSnapshot then
			spec.value:set(editSnapshot)
		end
		endEditing()
		if spec.onCancel then
			spec.onCancel()
		end
	end
	do
		owner.watch(function(use)
			local classes = use(env:get("interactionClasses"))
			if type(classes) ~= "table" then
				return
			end
			if editing:peek() and touchLiveAtEditStart and classes.touch ~= true and classes.keyboard ~= true then
				commit("focusLost")
			end
		end)
	end
	local function clearValue()
		if disabledMemo:peek() then
			return
		end
		applyProposed("")
	end
	local function onTextChanged(text: string)
		if editing:peek() then
			applyProposed(text)
		end
	end
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
	function api.bindActionSystem(sys: any)
		if actionSystemRef == nil then
			actionSystemRef = sys
		end
	end
	function api.handleTraverse(_path: string, _direction: number): boolean
		if not editing:peek() then
			return false
		end
		commit("focusLost")
		return false -- the edit is closed: let the ring move on
	end
	--[[ WHERE EVERY PART OF THIS CONTROL IS, derived once from four independent
		facts: furniture puts the plate inside a stack, a named rung inside the
		reserved touch floor, accessories put the editor inside a row, multiline
		inside a viewport. Focus, activation and occlusion all read these tails. ]]
	local sizedRung = spec.controlSize ~= nil
	local fieldId = if chrome.active then "Input" else id
	local rootId = if not chrome.active and sizedRung then `{id}+target` else id
	local fieldBase = if chrome.active
		then (if sizedRung then "/Input+target/Input" else "/Input")
		elseif sizedRung then `/{id}`
		else ""
	-- a pinned child and a row member cannot share the plate's right edge, so
	-- anything else inside the plate turns the plate into one row
	local usesRow = chrome.hasAccessories
	local rowPrefix = if usesRow then "/Row" else ""
	local function ownTail(suffix: string): string
		return `/{rootId}{fieldBase}{suffix}`
	end
	local fieldSuffix = rowPrefix .. (if spec.multiline then "/Viewport" else "") .. "/Field"
	local FIELD_TAIL, CLEAR_TAIL = ownTail(fieldSuffix), ownTail(rowPrefix .. "/Clear")
	local TRAILING_TAIL = ownTail("/Row/Trailing")
	local LABEL_TAIL = `/{id}/{chrome.LABEL_ID}`
	-- compared as text, so an id carrying a pattern character needs no escaping
	local function endsWith(path: string, tail: string): boolean
		return string.sub(path, -#tail) == tail
	end
	-- the clear chip and the caller's trailing content are facts only the mounted
	-- tree can answer: a path named in an order and not mounted is a dead stop
	local function mountedUnder(node: any, tail: string): any?
		if type(node.path) == "string" and endsWith(node.path, tail) then
			return node
		end
		for _, child in node.children or {} do
			local found = mountedUnder(child, tail)
			if found ~= nil then
				return found
			end
		end
		return nil
	end
	local function collectStops(node: any, into: { string })
		local class = controlContract.forClass(node.class)
		local props = node.props
		local focusable = if node.class == "Grip"
			then props ~= nil and props.focusable == true
			else class ~= nil and class.focusRole == "focusable" and not (props ~= nil and props.focusable == false)
		if focusable then
			table.insert(into, node.path)
		end
		for _, child in node.children or {} do
			collectStops(child, into)
		end
	end
	-- a contribution owns its subtree's focus, so every stop inside it is named
	-- here: the editor, the mounted clear, then focusables in `trailing`
	function api.focusGroups(rootNode: any): { any }
		if not enabledMemo:peek() then
			return {}
		end
		local order: { string } = { rootNode.path .. fieldBase .. fieldSuffix }
		local clear = mountedUnder(rootNode, CLEAR_TAIL)
		if clear ~= nil then
			table.insert(order, clear.path)
		end
		if chrome.trailing ~= nil then
			local trailing = mountedUnder(rootNode, TRAILING_TAIL)
			if trailing ~= nil then
				collectStops(trailing, order)
			end
		end
		return { { name = `{id}:field`, axis = "horizontal", entry = "first", order = order } }
	end

	-- the field enters editing, the clear empties it, the label focuses its field
	function api.handleActivate(path: string, _meta: any?): boolean
		if endsWith(path, FIELD_TAIL) then
			fieldFullPath = path -- learn our full path for keep-visible
			beginEditing()
			return true
		end
		if endsWith(path, CLEAR_TAIL) then
			clearValue()
			return true
		end
		if spec.label ~= nil and endsWith(path, LABEL_TAIL) then
			beginEditing()
			return true
		end
		return false
	end
	function api.syncGeometry(rectOf: (string) -> any, rootNode: any?)
		if disposed then
			return
		end
		if rootNode ~= nil then
			inheritedDisabled:set(controlContract.isDisabled(rootNode))
		end
		latestRectOf = rectOf
		local platePath = if rootNode then rootNode.path .. fieldBase else nil
		if spec.multiline and platePath then
			local frame = rectOf(platePath)
			local metrics = env:get("themeMetrics"):peek()
			local inset = metrics.chromeInsets and metrics.chromeInsets.field
			local height = if frame then math.max(0, frame.h - (if inset then inset.top + inset.bottom else 0)) else 0
			if height ~= viewportHeight:peek() then
				viewportHeight:set(height)
			end
		end
		if fieldFullPath ~= nil and editing:peek() then
			local r = rectOf(if spec.multiline and platePath then platePath else fieldFullPath)
			if spec.multiline and platePath and renderController then
				renderController.scrollToVisible(platePath)
				local painted = renderController.screenRectOf(platePath)
				if painted then
					r = { x = painted.x, y = painted.y + keepVisibleOffset:peek(), w = painted.w, h = painted.h }
				end
			end
			if not rectsEqual(fieldRect:peek(), r) then
				fieldRect:set(r)
			end
		end
	end
	local function clearButtonView(): any
		return UI.Button({
			id = "Clear",
			onActivate = clearValue,
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
			-- pinned only as the Anchor's own child; in the row it is a member
			anchor = if usesRow then nil else "right",
			offsetX = if usesRow then nil else CLEAR_INSET,
			padding = 0,
			width = { type = "minMax", min = CLEAR_SIZE },
			height = { type = "minMax", min = CLEAR_SIZE, max = FIELD_HEIGHT },
			surface = "chip",
		})
	end

	local defaultHeight = if spec.multiline
		then Compose.formula(function(use)
			local raw = use(env:get("themeMetrics"))
			local metrics = if type(raw) == "table" and raw.controls then raw else themeSnapshot.neutral()
			local height = metrics.controls.textInput.multilineHeight
			local occlusion = use(env:get("keyboardOcclusionRect"))
			if use(editing) and type(occlusion) == "table" then
				local viewport = use(env:get("viewportRect"))
				local insets = use(env:get("coreSafeInsets"))

				local hostChrome = if ownerReservesAppChrome then use(env:get("appChromeInsets")) else nil
				local hostTop = if type(hostChrome) == "table" then math.max(0, tonumber(hostChrome.top) or 0) else 0
				local room = occlusion.y - viewport.y - (insets.top or 0) - hostTop - KEEP_VISIBLE_MARGIN
				height = math.min(height, math.max(metrics.controls.textInput.fieldHeight, room))
			end
			return { type = "fixed", px = height }
		end)
		else { type = "minMax", min = FIELD_HEIGHT }
	local fieldPadding = chrome.padding or { left = "controls.textInput.padding", right = "controls.textInput.padding" }
	local rootView = UI.Anchor
	local rootSpec = {
		id = fieldId,
		width = { type = "fill", weight = 1 },
		-- authored height wins, then the rung's; a multiline editor's height is a
		-- count of lines, so a rung's single-line floor never applies there
		height = spec.height or (if spec.multiline then defaultHeight else chrome.height or defaultHeight),
		offset = Compose.formula(function(use)
			local x = use(shakeOffset)
			return if x == 0 then nil else { x = x, y = 0 }
		end),
		children = {
			UI.TextField({
				id = "Field",
				text = spec.value,
				multiline = spec.multiline,
				surface = "plain",
				-- with an accessory row the ROW owns the inset
				padding = if spec.multiline or usesRow then nil else fieldPadding,

				placeholder = spec.placeholder or (if presentation == "search" then "Search" else nil),
				editing = editing,
				enabled = enabledMemo,
				focusable = enabledMemo,
				maxLength = spec.maxLength,
				keyboardType = spec.keyboardType or "default",
				width = { type = "fill", weight = 1 },
				height = if spec.multiline
					then Compose.formula(function(use)
						return { type = "minMax", min = use(viewportHeight) }
					end)
					else UI.fill(),
				onTextChanged = onTextChanged,
				onFocusGained = onFocusGained,
				onFocusLost = onFocusLost,
			}),

			Compose.show(clearVisible, clearButtonView),
		},
	}
	-- the search mark: pinned to the plate's left edge in the Anchor form, the
	-- first row member in the row form (an anchored child is not carried there)
	local searchMark = if presentation == "search"
		then chromeSlots.attachHint(
			UI.Text({
				id = "SearchIcon",
				text = themePackage.iconGlyph("facet:search"),
				textSize = "control",
				anchor = if usesRow then nil else "left",
				offsetX = if usesRow then nil else "-xl",
				width = if usesRow then UI.hug() else nil,
				height = if usesRow then UI.hug() else nil,
			}),
			{ icon = "facet:search" }
		)
		else nil
	if searchMark ~= nil and not usesRow then
		rootSpec.padding = { left = "xl" }
		table.insert(rootSpec.children, searchMark)
	end
	rootSpec.surface = chrome.surface
	rootSpec.enabled = if spec.enabled ~= nil
		then spec.enabled
		elseif spec.disabled ~= nil then Compose.formula(function(use)
			return read(spec.disabled, use) ~= true
		end)
		else nil
	rootSpec.children[1] = chromeSlots.attachHint(rootSpec.children[1], { slot = chromeSlots.NO_SLOT })
	if spec.multiline then
		local field = rootSpec.children[1]
		rootSpec.children[1] = UI.ScrollView({
			id = "Viewport",
			width = UI.fill(),
			height = Compose.formula(function(use)
				return { type = "fixed", px = use(viewportHeight) }
			end),
			padding = { right = "s" },
			children = { field },
		})
	end
	--[[ THE ACCESSORY ROW. A leading mark is decoration inside a plain hugging
		stack, so a tap across the plate still reaches the editor; a trailing
		Button is its own focus stop after the clear, in document order. ]]
	if usesRow then
		local function holder(holderId: string, content: any): any
			return UI.ZStack({
				id = holderId,
				width = UI.hug(),
				height = UI.hug(),
				alignH = "center",
				alignV = "center",
				children = { content },
			})
		end
		local row: { any } = {}
		if chrome.leading ~= nil then
			table.insert(row, holder("Leading", chrome.leading))
		end
		if searchMark ~= nil then
			table.insert(row, searchMark)
		end
		table.insert(row, rootSpec.children[1])
		table.insert(row, rootSpec.children[2])
		if chrome.trailing ~= nil then
			table.insert(row, holder("Trailing", chrome.trailing))
		end
		rootSpec.children = {
			UI.HStack({
				id = "Row",
				width = UI.fill(),
				height = UI.fill(),
				align = "center",
				gap = "s",
				padding = fieldPadding,
				children = row,
			}),
		}
	end
	local blueprint = chromeSlots.attachHint(rootView(rootSpec), { slot = "field" })
	if spec.corners ~= nil then
		blueprint = UI.corners(blueprint, vocabulary.cornerRadiusFor(spec.corners))
	end
	-- only a named rung can solve the plate under the touch floor, so only a named
	-- rung is mounted inside the container that reserves it
	if sizedRung then
		blueprint = vocabulary.reserveTarget(UI, core, fieldId, blueprint, UI.fill())
	end
	blueprint = chrome.wrap(blueprint, id)
	local function dump()
		local out: any = {
			schema = "facet-text_input-dump/1",
			presentation = presentation,
			validationError = validationError:peek(),
			numericValue = if spec.numericValue then read(spec.numericValue) else nil,
			id = id,
			value = read(spec.value),
			multiline = spec.multiline == true,
			editing = editing:peek(),
			disabled = disabledMemo:peek(),
			placeholderVisible = read(spec.value) == "",
			clearVisible = clearVisible:peek(),
			clearButtonMode = clearMode,
			occlusionOffset = keepVisibleOffset:peek(),
			keyboardType = spec.keyboardType or "default",
			submitLabel = spec.submitLabel or "default",
		}
		chrome.dumpInto(out)
		return out
	end

	return {
		blueprint = contribution.attach(blueprint, {
			focusGroups = api.focusGroups,
			handleActivate = api.handleActivate,
			syncGeometry = api.syncGeometry,
			keepVisibleOffset = keepVisibleOffset,
			bindActionSystem = api.bindActionSystem,
			bindController = api.bindController,
			handleTraverse = api.handleTraverse,
			bindMotion = function(clock: any)
				motionClock = clock
			end,
		}),
		api = api,
		dump = dump,
		dispose = function()
			if disposed then
				return
			end
			endEditing()
			disposed = true
			if shaking ~= nil then
				shaking:interrupt()
				shaking = nil
			end
			owner.dispose()
		end,
	}
end

-- The handle owns one Compose lifetime, including callbacks created after mount.
function text_input.build(Facet: any, core: any, spec: Spec)
	return ownedBuild(core, function(owner)
		return build(Facet, core, spec, owner)
	end)
end

return text_input
