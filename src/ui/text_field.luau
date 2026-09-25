--!strict
local reducedMotion = require("./motion")
local arithmetic = require("./arithmetic")
local fieldChrome = require("./field_chrome")
local textPress = require("./text_press")
local measuredScroll = require("./measured_scroll")
local InputTypes = require("./input_types")
local Shared = require("./types")
local ComposeTypes = require("../vendor/compose/core")

type Spec = InputTypes.TextInputImplementationProps
type Scrub = {
	start: number,
	text: string,
	written: number,
	promoted: boolean,
}

local TEXT_KEYS = {
	"value",
	"numericValue",
	"presentation",
	"min",
	"max",
	"parse",
	"format",
	"validate",
	"maxLength",
	"enabled",
	"disabled",
	"readOnly",
	"placeholder",
	"multiline",
	"visibleLines",
	"onChange",
	"onCommit",
	"onCancel",
	"invalid",
	"clearButton",
	"clearButtonMode",
	"selectOnFocus",
	"leading",
	"trailing",
	"label",
	"requiredMark",
	"hint",
	"errorText",
	"controlSize",
	"appearance",
	"corners",
	"step",
	"precision",
	"stepButtons",
	"prefix",
	"suffix",
	"scrub",
}
local NUMBER_KEYS = { "step", "precision", "stepButtons", "prefix", "suffix", "scrub" }
local ROOT_KEYS = { "Name", "Size", "Position", "AnchorPoint", "LayoutOrder", "Visible", "ZIndex" }
local SCRUB_PIXELS = 8

local function finite(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function places(value: number?): number
	if value == nil or value % 1 == 0 then
		return 0
	end
	local text = string.format("%.10f", math.abs(value)):gsub("0+$", "")
	local dot = string.find(text, ".", 1, true)
	return if dot then #text - dot else 0
end

local function round(value: number, digits: number): number
	local scale = 10 ^ digits
	local shifted = value * scale
	if not finite(shifted) then
		return value
	end
	local rounded = math.floor(math.abs(shifted) + 0.5) / scale
	return if value < 0 then -rounded else rounded
end

return function(ctx: Shared.Context, UI: InputTypes.InputControls): ()
	local runtime, Host, Compose = ctx.runtime, ctx.Host, ctx.Compose
	local read = ctx.read
	local D, D2, V2, E = ctx.types.UDim, ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
	local chrome = fieldChrome(ctx)
	local function dynamic(source: unknown): boolean
		return Compose.isReadable(source) or type(source) == "function"
	end
	local function writable(source: unknown): boolean
		return type(source) == "table"
			and Compose.isReadable(source)
			and type((source :: { [string]: unknown }).set) == "function"
	end
	local function attributes(node: Instance, values: Shared.Attributes)
		runtime.decorate(node, { Attributes = values })
	end
	local function build(control: string, spec: Spec): TextBox | Frame
		assert(type(read(spec.value)) == "string", `Facet.{control}: value must resolve to a string`)
		assert(
			writable(spec.value) or type(spec.onChange) == "function",
			`Facet.{control}: a read-only value requires onChange`
		)
		for key, callback in
			{
				parse = spec.parse,
				format = spec.format,
				validate = spec.validate,
				onChange = spec.onChange,
				onCommit = spec.onCommit,
				onCancel = spec.onCancel,
			} :: { [string]: unknown }
		do
			assert(callback == nil or type(callback) == "function", `Facet.{control}: {key} must be a function`)
		end
		local numeric = spec.presentation == "number"
		assert(
			not numeric or writable(spec.numericValue),
			`Facet.{control}: numeric presentation requires numericValue`
		)
		assert(not numeric or spec.multiline ~= true, `Facet.{control}: numeric input must be single-line`)
		assert(spec.enabled == nil or spec.disabled == nil, `Facet.{control}: use enabled or disabled, not both`)
		assert(
			spec.presentation == nil or table.find({ "plain", "search", "number" }, spec.presentation),
			`Facet.{control}: invalid presentation`
		)
		for _, bound in { spec.min, spec.max } do
			assert(bound == nil or finite(bound), `Facet.{control}: numeric bounds must be finite`)
		end
		assert(spec.min == nil or spec.max == nil or spec.min <= spec.max, `Facet.{control}: min must not exceed max`)
		assert(
			spec.maxLength == nil or (spec.maxLength >= 0 and spec.maxLength % 1 == 0),
			`Facet.{control}: maxLength must be a nonnegative integer`
		)
		assert(
			spec.invalid == nil or (Compose.isReadable(spec.invalid) and type(read(spec.invalid)) == "boolean"),
			`Facet.{control}: invalid must be a boolean readable`
		)
		assert(type(read(spec.readOnly) or false) == "boolean", `Facet.{control}: readOnly must be a boolean`)
		for _, key in NUMBER_KEYS do
			assert(
				numeric or (spec :: { [unknown]: unknown })[key] == nil,
				`Facet.{control}: {key} belongs to the number presentation`
			)
		end
		assert(
			spec.step == nil or (finite(spec.step) and (spec.step :: number) > 0),
			`Facet.{control}: step must be finite and above zero`
		)
		assert(
			spec.precision == nil
				or (finite(spec.precision) and spec.precision % 1 == 0 and spec.precision >= 0 and spec.precision <= 10),
			`Facet.{control}: precision must be a whole number from 0 to 10`
		)
		for _, key in { "prefix", "suffix" } do
			local unit = read((spec :: { [unknown]: Shared.Value<unknown> })[key])
			assert(unit == nil or type(unit) == "string", `Facet.{control}: {key} must be a string`)
		end
		assert(
			spec.scrub == nil or type(read(spec.scrub)) == "boolean",
			`Facet.{control}: scrub must be a boolean or a readable boolean`
		)
		assert(spec.visibleLines == nil or spec.multiline == true, `Facet.{control}: visibleLines requires multiline`)
		assert(
			spec.visibleLines == nil
				or (finite(spec.visibleLines) and spec.visibleLines % 1 == 0 and spec.visibleLines >= 1),
			`Facet.{control}: visibleLines must be a whole number of at least 1`
		)
		assert(
			spec.leading == nil or spec.presentation ~= "search",
			`Facet.{control}: a search field already leads with its search mark`
		)
		chrome.check(control, spec)
		local lastPolicy: InputTypes.SelectOnFocus = "none"
		local function policyOf(word: unknown): InputTypes.SelectOnFocus
			if word == nil then
				return "none"
			end
			if word ~= "none" and word ~= "all" and word ~= "end" then
				error(`Facet UI.{control}: selectOnFocus: one of none | all | end (got {tostring(word)})`, 0)
			end
			return word :: InputTypes.SelectOnFocus
		end
		lastPolicy = policyOf(read(spec.selectOnFocus))

		local framed = chrome.present(spec)
			or spec.leading ~= nil
			or spec.trailing ~= nil
			or spec.prefix ~= nil
			or spec.suffix ~= nil
			or spec.stepButtons == true
			or spec.visibleLines ~= nil
		local enabled = function(use: ComposeTypes.Use?): boolean
			return read(spec.enabled, use) ~= false and read(spec.disabled, use) ~= true
		end
		local readOnly = function(use: ComposeTypes.Use?): boolean
			return read(spec.readOnly, use) == true
		end
		local editable = function(use: ComposeTypes.Use?): boolean
			return enabled(use) and not readOnly(use)
		end
		local editing = Compose.cell(false)
		local invalid = Compose.cell(false)
		local validationMessage = Compose.cell("")
		local mayReject = numeric or spec.invalid ~= nil
		local errorTimeline = if mayReject then runtime.timeline({ duration = 0.24, autoplay = false }) else nil
		local errorReduced = if errorTimeline then reducedMotion(ctx) else nil
		if errorTimeline then
			errorTimeline:seek(0.24)
		end
		local textHeight, messageHeight = Compose.cell(18), Compose.cell(0)
		local writing, disposed, snapshot = false, false, read(spec.value)
		local scrubbing: Scrub? = nil
		local node: TextBox
		local function updateValue(value: string): ()
			if read(spec.value) == value then
				return
			end
			if spec.onChange then
				spec.onChange(value)
			else
				(spec.value :: ComposeTypes.Cell<string>):set(value)
			end
		end
		local function setText(value: string): ()
			if node.Text ~= value then
				writing = true
				node.Text = value
				writing = false
			end
		end
		local function markInvalid(value: boolean, message: string?): ()
			invalid:set(value)
			validationMessage:set(if value then message or "Check this value." else "")
			if writable(spec.invalid) then
				(spec.invalid :: ComposeTypes.Cell<boolean>):set(value)
			end
			if value and errorTimeline and errorReduced and not errorReduced() then
				errorTimeline:restart()
			end
		end
		local function normalize(text: string): string?
			local length = utf8.len(text)
			if length == nil then
				return nil
			end
			if spec.maxLength and length > spec.maxLength then
				text = string.sub(text, 1, (utf8.offset(text, spec.maxLength + 1) :: number) - 1)
			end
			local normalized = if spec.validate then spec.validate(text) else text
			if type(normalized) ~= "string" or utf8.len(normalized) == nil then
				return nil
			end
			return normalized
		end
		local function propose(text: string): ()
			if disposed or not editable() then
				setText(read(spec.value))
				return
			end
			local accepted = normalize(text)
			if accepted == nil then
				setText(read(spec.value))
				return
			end
			updateValue(accepted)
			setText(read(spec.value))
		end
		local function releaseFocus()
			if node:IsFocused() then
				node:ReleaseFocus(false)
			end
		end
		local function cancel()
			if not editing:peek() then
				return
			end
			editing:set(false)
			updateValue(snapshot)
			setText(read(spec.value))
			releaseFocus()
			if spec.onCancel then
				spec.onCancel()
			end
		end
		local function digits(): number
			if spec.precision ~= nil then
				return spec.precision
			end
			return math.max(places(spec.step), places(spec.min))
		end
		local function formatNumber(number: number): string?
			local ok, formatted = pcall(function(value: number): string
				if spec.format then
					return spec.format(value)
				end
				if spec.precision ~= nil then
					return string.format(`%.{spec.precision}f`, value)
				end
				return tostring(value)
			end, number)
			if not ok or type(formatted) ~= "string" or utf8.len(formatted) == nil then
				return nil
			end
			if spec.validate then
				local valid, normalized = pcall(spec.validate, formatted)
				if not valid or type(normalized) ~= "string" or utf8.len(normalized) == nil then
					return nil
				end
				formatted = normalized
			end
			if spec.maxLength and (utf8.len(formatted) :: number) > spec.maxLength then
				return nil
			end
			return formatted
		end
		local function clamp(number: number): (number, boolean)
			local clamped = number
			if spec.min and clamped < spec.min then
				clamped = spec.min
			end
			if spec.max and clamped > spec.max then
				clamped = spec.max
			end
			return clamped, clamped ~= number
		end
		local function settleNumber(number: number, reason: InputTypes.CommitReason, report: boolean): boolean
			local numericValue = assert(spec.numericValue)
			local text = formatNumber(number)
			if disposed or not enabled() then
				return false
			end
			if text == nil then
				markInvalid(true)
				return false
			end
			local formatted: string = text
			local accepted = false
			runtime:batch(function()
				updateValue(formatted)
				accepted = read(spec.value) == formatted
				if accepted then
					numericValue:set(number)
				end
			end)
			if not accepted then
				setText(read(spec.value))
				markInvalid(true)
				return false
			end
			setText(formatted)
			markInvalid(false)
			if report and spec.onCommit then
				spec.onCommit(number, reason)
			end
			return true
		end
		local function commitNumber(reason: InputTypes.CommitReason): ()
			local numericValue = assert(spec.numericValue)
			local text = read(spec.value)
			if arithmetic.incomplete(text) then
				if spec.requiredMark == "required" then
					markInvalid(true, "Enter a number.")
					return
				end
				local previous = formatNumber(numericValue:peek())
				if previous then
					updateValue(previous)
					setText(read(spec.value))
				end
				markInvalid(false)
				return
			end
			local ok, parsed = pcall(function(value: string): number?
				return if spec.parse then spec.parse(value) else arithmetic.number(value)
			end, text)
			if disposed or not enabled() then
				return
			end
			if not ok or not finite(parsed) then
				markInvalid(true, "Enter a valid number.")
				return
			end
			local number, clamped = clamp(parsed :: number)
			if spec.precision ~= nil then
				number = round(number, spec.precision)
			end
			settleNumber(number, if clamped then "clamped" else reason, true)
		end
		local function commit(reason: InputTypes.CommitReason): ()
			if disposed or not editing:peek() then
				return
			end
			editing:set(false)
			if not enabled() or readOnly() then
				setText(read(spec.value))
				return
			end
			if numeric then
				commitNumber(reason)
				return
			end
			local value = read(spec.value)
			local normalized = normalize(value)
			if disposed or not enabled() then
				return
			end
			if normalized == nil then
				markInvalid(true)
				return
			end
			value = normalized
			updateValue(value)
			if read(spec.value) ~= value then
				setText(read(spec.value))
				markInvalid(true)
				return
			end
			setText(value)
			if spec.onCommit then
				spec.onCommit(value, reason)
			end
		end
		local function stepped(base: number, count: number): number
			local increment = spec.step or 1
			local target = base + count * increment
			if spec.min ~= nil and spec.max ~= nil then
				local from = spec.min
				target = from + (math.floor((base - from) / increment + 0.5) + count) * increment
			end
			local number = clamp(target)
			return round(number, digits())
		end
		local function stepBy(direction: number)
			if disposed or not editable() then
				return
			end
			if editing:peek() then
				editing:set(false)
				releaseFocus()
			end
			local numericValue = assert(spec.numericValue)
			local number = stepped(numericValue:peek(), direction)
			if number ~= numericValue:peek() or read(spec.value) ~= formatNumber(number) then
				settleNumber(number, "submit", true)
			end
		end

		local nativeProps = ctx.props(spec, TEXT_KEYS, {
			Text = read(spec.value),
			PlaceholderText = spec.placeholder or "",
			ClearTextOnFocus = false,
			MultiLine = spec.multiline == true,
			TextWrapped = spec.multiline == true,
			TextXAlignment = E.TextXAlignment.Left,
			TextYAlignment = if (mayReject and not framed) or spec.multiline == true
				then E.TextYAlignment.Top
				else E.TextYAlignment.Center,
			TextEditable = function(use: ComposeTypes.Use)
				return editable(use)
			end,
			Selectable = function(use: ComposeTypes.Use)
				return enabled(use)
			end,
		})
		local rootProps: Shared.FrameNativeProps = {}
		if framed then
			local source = nativeProps :: { [unknown]: unknown }
			local target = (rootProps :: unknown) :: { [string]: unknown }
			for _, key in ROOT_KEYS do
				target[key], source[key] = source[key], nil
			end
			nativeProps.Name = "Field"
			nativeProps.BackgroundTransparency = 1
			nativeProps.Size = if spec.visibleLines
				then D2.new(1, 0, 0, 0)
				else function(use: ComposeTypes.Use)
					local minimum = if spec.multiline == true then 96 else 36
					return D2.new(0, 0, 0, math.max(minimum, use(textHeight) + 12))
				end
			nativeProps.AutomaticSize = if spec.visibleLines then E.AutomaticSize.Y else nil
		else
			nativeProps.Size = nativeProps.Size
				or function(use: ComposeTypes.Use)
					local message = if use(validationMessage) ~= "" then use(messageHeight) else 0
					local minimum = if spec.multiline == true then 96 else 44
					return D2.new(1, 0, 0, math.max(minimum, use(textHeight) + message + 16))
				end
		end
		nativeProps.Focused = function(...)
			if enabled() and not editing:peek() then
				snapshot = read(spec.value)
				editing:set(true)
			end
			if spec.Focused then
				spec.Focused(...)
			end
		end
		nativeProps.FocusLost = function(enterPressed, input)
			if scrubbing ~= nil then
				editing:set(false)
			elseif input and (input.KeyCode == E.KeyCode.Escape or input.KeyCode == E.KeyCode.ButtonB) then
				cancel()
			else
				commit(if enterPressed then "submit" else "focusLost")
			end
			if spec.FocusLost then
				spec.FocusLost(enterPressed, input)
			end
		end
		table.insert(nativeProps, ctx.padding(if framed then 0 else 10, 6))

		local messageNode: TextLabel?
		if mayReject and not framed then
			local message = ctx.styled(
				ctx.text({
					Name = "ValidationMessage",
					Text = validationMessage,
					Visible = function(use: ComposeTypes.Use)
						return use(validationMessage) ~= ""
					end,
					Size = D2.new(1, 0, 0, 0),
					AutomaticSize = E.AutomaticSize.Y,
					TextWrapped = true,
					Position = function(use: ComposeTypes.Use)
						return D2.fromOffset(0, use(textHeight) + 4)
					end,
				}),
				"validation"
			)
			messageNode = message
			table.insert(nativeProps, message)
		end
		local pulse = if errorTimeline
			then Host.UIScale "ValidationPulse" {
				Scale = function(use: ComposeTypes.Use)
					if assert(errorReduced)(use) then
						return 1
					end
					local phase = use(assert(errorTimeline).progress)
					return 1 - 0.03 * math.sin(math.pi * phase) * (1 - phase)
				end,
			}
			else nil
		if pulse and not framed then
			table.insert(nativeProps, pulse)
		end

		local mode = spec.clearButtonMode
			or (if spec.clearButton or spec.presentation == "search" then "always" else "never")
		assert(
			table.find({ "always", "never", "whileEditing", "unlessEditing" }, mode),
			`Facet.{control}: invalid clearButtonMode`
		)
		local clear = if mode ~= "never"
			then UI.Button "Clear" {
				label = "Clear",
				Size = D2.fromOffset(44, 44),
				AutomaticSize = E.AutomaticSize.None,
				AnchorPoint = if framed then nil else V2.new(1, 0.5),
				Position = if framed then nil else D2.fromScale(1, 0.5),
				LayoutOrder = if framed then 40 else nil,
				Visible = function(use: ComposeTypes.Use)
					return editable(use)
						and read(spec.value, use) ~= ""
						and (
							mode == "always"
							or (mode == "whileEditing" and use(editing))
							or (mode == "unlessEditing" and not use(editing))
						)
				end,
				onActivate = function()
					propose("")
				end,
			}
			else nil
		if clear and not framed then
			table.insert(nativeProps, clear)
		end
		node = ctx.styled(Host.TextBox(nativeProps), "text")
		if not framed then
			ctx.styled(ctx.styled(node, "field"), "text-input")
		end

		local root: TextBox | Frame = node
		if framed then
			local parts: { ComposeTypes.Child } = {}
			local function slot(name: string, order: number, content: Instance)
				table.insert(
					parts,
					Host.Frame({
						Name = name,
						LayoutOrder = order,
						BackgroundTransparency = 1,
						Size = D2.fromOffset(0, 0),
						AutomaticSize = E.AutomaticSize.XY,
						content :: ComposeTypes.Child,
					})
				)
			end
			if spec.presentation == "search" then
				table.insert(
					parts,
					ctx.icon("facet:search", {
						Name = "SearchIcon",
						LayoutOrder = 5,
					})
				)
			end
			if spec.leading then
				slot("Leading", 10, spec.leading)
			end
			local function unit(name: string, order: number, words: Shared.Value<string>?)
				if words ~= nil then
					table.insert(
						parts,
						ctx.styled(ctx.text({ Name = name, LayoutOrder = order, Text = words }), "secondary")
					)
				end
			end
			unit("Prefix", 20, spec.prefix)
			local editor: GuiObject = node
			if spec.visibleLines then
				local lines = spec.visibleLines
				editor = measuredScroll(ctx, {
					Name = "Viewport",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Selectable = false,
					ScrollingDirection = E.ScrollingDirection.Y,
					Size = function(use: ComposeTypes.Use)
						local size = ctx.metric("typography.body.size", use)
						return D2.new(0, 0, 0, math.ceil(lines * size * 1.2) + 12)
					end,
				}, { node :: ComposeTypes.Child })
				local viewport = editor :: ScrollingFrame
				local caret = ctx.observe(node, "CursorPosition")
				local drawn = ctx.observe(node, "TextBounds")
				local window = ctx.observe(viewport, "AbsoluteWindowSize")
				local canvas = ctx.observe(viewport, "AbsoluteCanvasSize")
				Compose.watch(function(use: ComposeTypes.Use)
					local at, extent, view, full = tonumber(use(caret)) or -1, use(drawn), use(window), use(canvas)
					if at < 1 or extent.Y <= 0 or view.Y <= 0 then
						return
					end
					local text = node.Text
					local limit = math.max(0, full.Y - view.Y)
					local top, bottom
					if at > #text then
						top, bottom = limit, full.Y
					else
						local _, lines = string.gsub(text, "\n", "")
						local _, before = string.gsub(string.sub(text, 1, at - 1), "\n", "")
						local line = extent.Y / (lines + 1)
						top, bottom = before * line, (before + 1) * line
					end
					local position = viewport.CanvasPosition
					if bottom > position.Y + view.Y then
						viewport.CanvasPosition = V2.new(position.X, math.min(limit, bottom - view.Y))
					elseif top < position.Y then
						viewport.CanvasPosition = V2.new(position.X, math.max(0, top))
					end
				end)
			end
			runtime.mountFragment(function()
				return { Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }) }
			end, editor)
			table.insert(parts, editor)
			unit("Suffix", 32, spec.suffix)
			if clear then
				table.insert(parts, clear)
			end
			if spec.stepButtons then
				local function stepButton(name: string, glyph: string, direction: number, order: number)
					local button = UI.Button(name)({
						icon = glyph,
						name = name,
						LayoutOrder = order,
						Size = D2.fromOffset(44, 44),
						AutomaticSize = E.AutomaticSize.None,
						enabled = function(use: ComposeTypes.Use)
							if not editable(use) then
								return false
							end
							local number = use(assert(spec.numericValue))
							if direction < 0 then
								return spec.min == nil or number > spec.min
							end
							return spec.max == nil or number < spec.max
						end,
						onActivate = function()
							stepBy(direction)
						end,
					})
					button:AddTag("facet-stepper-button")
					table.insert(parts, button)
				end
				stepButton("Decrement", "decrement", -1, 50)
				stepButton("Increment", "increment", 1, 51)
			end
			if spec.trailing then
				slot("Trailing", 60, spec.trailing)
			end
			if pulse then
				table.insert(parts, pulse)
			end
			local plate = ctx.row(parts, {
				Name = "Input",
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
				BackgroundTransparency = 0,
				ctx.padding(10, 4) :: ComposeTypes.Child,
			})
			local layout = assert(plate:FindFirstChildWhichIsA("UIListLayout"))
			layout.VerticalAlignment = E.VerticalAlignment.Center
			layout.Padding = D.new(0, 4)
			ctx.styled(plate, "text-input")
			local failure = chrome.errorOf(spec, if numeric or spec.invalid then validationMessage else nil)
			chrome.paint(control, plate, spec, function(use: ComposeTypes.Use?)
				return failure(use) ~= "" or read(spec.invalid, use) == true
			end)
			ctx.skin(plate, "field", {
				disabled = function(use: ComposeTypes.Use)
					return not enabled(use)
				end,
			})
			root = chrome.wrap({
				control = control,
				spec = spec,
				plate = plate,
				focus = function()
					if not node:IsFocused() then
						node:CaptureFocus()
					end
				end,
				enabled = enabled,
				message = if numeric or spec.invalid then validationMessage else nil,
				native = rootProps,
			})
		end

		if spec.multiline == true and not messageNode then
			local bounds = ctx.observe(node, "TextBounds")
			Compose.watch(function(use: ComposeTypes.Use)
				textHeight:set(use(bounds).Y)
			end)
		end
		if messageNode then
			local bounds, messageBounds = ctx.observe(node, "TextBounds"), ctx.observe(messageNode, "TextBounds")
			Compose.watch(function(use: ComposeTypes.Use)
				textHeight:set(use(bounds).Y)
				messageHeight:set(use(messageBounds).Y)
			end)
		end
		if mayReject then
			local wasInvalid = false
			Compose.watch(function(use: ComposeTypes.Use)
				local sourceInvalid = read(spec.invalid, use) == true
				if sourceInvalid and not wasInvalid and not invalid:peek() then
					markInvalid(true)
				end
				if not sourceInvalid and wasInvalid then
					markInvalid(false)
				end
				wasInvalid = sourceInvalid
				if assert(errorReduced)(use) then
					assert(errorTimeline):pause()
					assert(errorTimeline):seek(0.24)
				end
			end)
		end
		ctx.action(node, "TextEditing", {
			E.KeyCode.Up,
			E.KeyCode.Down,
			E.KeyCode.Left,
			E.KeyCode.Right,
			E.KeyCode.DPadUp,
			E.KeyCode.DPadDown,
			E.KeyCode.DPadLeft,
			E.KeyCode.DPadRight,
		}, editing, function() end, { priority = 10000 })
		local _, editingContext = ctx.action(
			node,
			"Cancel",
			{ E.KeyCode.Escape, E.KeyCode.ButtonB },
			editing,
			cancel,
			{ priority = 10000 }
		)
		local nativeEditingAvailable = ctx.observe(editingContext, "Enabled")
		Compose.watch(function(use: ComposeTypes.Use)
			if not use(nativeEditingAvailable) and editing:peek() then
				editing:set(false)
				releaseFocus()
			end
		end)
		runtime.connect(node, "ReturnPressedFromOnScreenKeyboard", function()
			if spec.multiline ~= true then
				commit("submit")
				releaseFocus()
			end
		end)
		attributes(node, {
			invalid = function(use: ComposeTypes.Use)
				return use(invalid) or read(spec.invalid, use) == true
			end,
			validationMessage = function(use: ComposeTypes.Use): string
				return use(validationMessage)
			end,
			readOnly = function(use: ComposeTypes.Use)
				return readOnly(use)
			end,
		})
		if spec.label ~= nil then
			attributes(node, {
				AccessibleLabel = function(use: ComposeTypes.Use): string
					return chrome.labelText(spec, use)
				end,
			})
		end
		if spec.selectOnFocus ~= nil then
			attributes(node, {
				selectOnFocus = function(use: ComposeTypes.Use): string
					local ok, policy = pcall(policyOf, read(spec.selectOnFocus, use))
					return if ok then policy :: string else lastPolicy
				end,
			})
		end
		if spec.selectOnFocus ~= nil and dynamic(spec.selectOnFocus) then
			Compose.watch(function(use: ComposeTypes.Use)
				lastPolicy = policyOf(read(spec.selectOnFocus, use))
			end)
		end
		Compose.cleanup(assert(runtime.host.observation).observeProperty(node, "Text", function()
			if not writing and editing:peek() then
				propose(node.Text)
			end
		end))
		Compose.watch(function(use: ComposeTypes.Use)
			setText(read(spec.value, use))
			if enabled(use) then
				node:RemoveTag("facet-disabled")
			else
				node:AddTag("facet-disabled")
			end
			if not enabled(use) and editing:peek() then
				editing:set(false)
				releaseFocus()
			end
		end)

		local function endScrub(restore: boolean)
			local active = scrubbing
			if active == nil then
				return
			end
			scrubbing = nil
			if restore and not disposed then
				assert(spec.numericValue):set(active.start)
				updateValue(active.text)
				setText(read(spec.value))
			elseif restore then
				assert(spec.numericValue):set(active.start)
				if writable(spec.value) then
					(spec.value :: ComposeTypes.Cell<string>):set(active.text)
				end
			end
		end
		local function scrubAllowed(use: ComposeTypes.Use?): boolean
			return read(spec.scrub, use) == true and editable(use)
		end
		local onScrub: textPress.Scrub? = nil
		if numeric and spec.scrub ~= nil then
			onScrub = function(phase: textPress.Phase, argument: (string | number)?): boolean
				if disposed then
					return false
				end
				local numericValue = assert(spec.numericValue)
				if phase == "press" then
					return scrubAllowed()
				elseif phase == "begin" then
					if not scrubAllowed() then
						return false
					end
					local start = numericValue:peek()
					local text = if editing:peek() then snapshot else read(spec.value)
					scrubbing = { start = start, text = text, written = start, promoted = true }
					updateValue(text)
					setText(read(spec.value))
					markInvalid(false)
					return true
				elseif phase == "move" then
					local active = scrubbing
					if active == nil or type(argument) ~= "number" then
						return false
					end
					local travel = argument :: number
					local count = math.floor(math.abs(travel) / SCRUB_PIXELS) * (if travel < 0 then -1 else 1)
					local number = stepped(active.start, count)
					if number ~= numericValue:peek() then
						active.written = number
						settleNumber(number, "submit", false)
						active.written = numericValue:peek()
					end
					return true
				elseif phase == "end" then
					local active = scrubbing
					if active == nil then
						return false
					end
					scrubbing = nil
					if spec.onCommit then
						spec.onCommit(numericValue:peek(), "submit")
					end
					return true
				end
				endScrub(true)
				return true
			end
			Compose.watch(function(use: ComposeTypes.Use)
				local number = use(assert(spec.numericValue))
				local active = scrubbing
				if active ~= nil and number ~= active.written then
					scrubbing = nil
				end
			end)
			Compose.watch(function(use: ComposeTypes.Use)
				if not scrubAllowed(use) then
					endScrub(true)
				end
			end)
			local input = ctx.config.services.UserInputService
			if input then
				local preferred = ctx.observe(input, "PreferredInput")
				local first = true
				Compose.watch(function(use: ComposeTypes.Use)
					use(preferred)
					if not first then
						endScrub(true)
					end
					first = false
				end)
			end
		end
		local input = ctx.config.services.UserInputService
		if input and (spec.selectOnFocus ~= nil or onScrub ~= nil) then
			Compose.cleanup(textPress({
				box = node,
				input = input,
				Enum = (E :: unknown) :: typeof(Enum),
				policy = function(): string?
					return lastPolicy
				end,
				disabled = function(): boolean
					return not enabled()
				end,
				onScrub = onScrub,
			}))
		end
		Compose.cleanup(function()
			endScrub(true)
			disposed = true
		end)
		if not framed then
			ctx.skin(node, "field", {
				disabled = function(use: ComposeTypes.Use)
					return not enabled(use)
				end,
			})
		end
		return root
	end
	local textInput = ctx.construct("TextInput", function(spec: Spec): TextBox | Frame
		return build("TextInput", spec)
	end)
	UI.TextInput = (textInput :: unknown) :: typeof(UI.TextInput)
	local numberInput = ctx.construct("NumberInput", function(spec: Spec): TextBox | Frame
		if spec.presentation ~= nil then
			error("Facet UI.NumberInput: NumberInput IS the number presentation; remove presentation", 0)
		end
		local number = table.clone(spec)
		number.presentation = "number"
		return build("NumberInput", number)
	end)
	UI.NumberInput = (numberInput :: unknown) :: typeof(UI.NumberInput)
end
