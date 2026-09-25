--!strict
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")
local Inputs = require("./input_types")
local Nav = require("./navigation_types")
local Types = require("./color_picker_types")
local colorValue = require("./color_value")
local fieldChrome = require("./field_chrome")

type Use = ComposeTypes.Use
type Hsv = colorValue.Hsv
type Item = colorValue.Swatch
type Paint = { color: Color3?, alpha: number }
type Spec = Types.ColorPickerProps
type Placement = { edge: string, x: number, y: number, w: number, h: number }
type Measure = (Use) -> number
type PanelView = { panel: Frame, chrome: Measure, tech: Measure }
type Deps = {
	ColorPicker: Shared.Constructor<Spec, Frame>,
	Button: Shared.Constructor<Inputs.ButtonProps, TextButton>,
	Slider: Shared.Constructor<Inputs.SliderProps, Frame>,
	TextInput: Shared.Constructor<Inputs.TextInputProps, TextBox | Frame>,
	NumberInput: Shared.Constructor<Inputs.NumberInputProps, TextBox | Frame>,
	ShortcutHint: Shared.Constructor<Inputs.ShortcutHintProps, TextLabel | Frame>,
	Picker: Nav.PickerConstructor,
}

local KEYS = {
	"value",
	"onChange",
	"onCommit",
	"alpha",
	"onAlphaChange",
	"allowEmpty",
	"placeholder",
	"modes",
	"swatches",
	"onSaveSwatch",
	"onRemoveSwatch",
	"style",
	"draft",
	"isPresented",
	"onPresentedChange",
	"onDismiss",
	"enabled",
	"readOnly",
	"label",
	"requiredMark",
	"hint",
	"errorText",
	"controlSize",
	"appearance",
	"corners",
}
local MODE_LABEL: { [string]: string } =
	{ swatches = "Swatches", spectrum = "Spectrum", sliders = "Sliders", brick = "Bricks" }
local DEFAULT_MODES: { Types.Mode } = { "swatches", "spectrum", "sliders" }
local FORMATS = { { value = "rgb", label = "RGB" }, { value = "hsv", label = "HSV" }, { value = "hex", label = "Hex" } }
local CELL, GAP, PAD, SPACE, MARGIN = 44, 4, 12, 8, 8
local MAX_COLUMNS = 8
local PANEL_WIDTH = MAX_COLUMNS * CELL + (MAX_COLUMNS - 1) * GAP + 2 * PAD
local RING, BUBBLE, STRIP = 20, 44, 12
local STICK_SPEED, DEADZONE = 0.6, 0.2
local CHECKER_CELLS = 24
local SAVE_KEY = "\0save"

local function isColor(value: unknown): boolean
	return typeof(value) == "Color3"
end

local function unit(value: unknown): boolean
	return type(value) == "number" and value == value and value >= 0 and value <= 1
end

local function writable(source: unknown): boolean
	return type(source) == "table" and type((source :: { [string]: unknown }).set) == "function"
end

return function(ctx: Shared.Context, UI: Deps, surfaces: Nav.Surfaces): ()
	local Compose, Host, runtime, read = ctx.Compose, ctx.Host, ctx.runtime, ctx.read
	local E, D, D2, V2 = ctx.types.Enum, ctx.types.UDim, ctx.types.UDim2, ctx.types.Vector2
	local C3 = ctx.types.Color3
	local chrome = fieldChrome(ctx)
	local color = colorValue({ Color3 = C3, BrickColor = ctx.types.BrickColor })
	local WHITE, BLACK = C3.new(1, 1, 1), C3.new(0, 0, 0)
	local LIGHT, DARK, MUTED = C3.fromRGB(255, 255, 255), C3.fromRGB(204, 204, 204), C3.fromRGB(128, 128, 128)

	local function normalize(list: unknown): ({ Item }?, string?)
		if type(list) ~= "table" then
			return nil, "is an array of Color3 or { color, label? }"
		end
		local out: { Item } = {}
		local seen: { [string]: boolean } = {}
		for index, entry in list :: { unknown } do
			local paint: unknown, label: unknown = entry, nil
			if type(entry) == "table" then
				local fields = entry :: { [unknown]: unknown }
				paint, label = fields.color, fields.label
				for key in fields do
					if key ~= "color" and key ~= "label" then
						return nil, `item {index} has an unknown key '{tostring(key)}' (it is \{ color, label? })`
					end
				end
			end
			if not isColor(paint) or (label ~= nil and type(label) ~= "string") then
				return nil, `item {index} is a Color3 or \{ color = Color3, label = string? }`
			end
			local c = paint :: Color3
			local words = label :: string?
			local key = words or color.hex(c)
			if seen[key] then
				return nil, `repeats '{key}' (a label or hex is the item's key)`
			end
			seen[key] = true
			table.insert(out, { color = c, label = words, key = key })
		end
		return out, nil
	end

	local function ring(name: string): Frame
		local function stroke(tint: Color3, thickness: number): UIStroke
			return Host.UIStroke "Stroke" { Color = tint, Thickness = thickness, Transparency = 0 }
		end
		return Host.Frame(name)({
			Size = D2.fromOffset(RING, RING),
			BackgroundTransparency = 1,
			ctx.corner(RING) :: Shared.Child,
			stroke(BLACK, 1),
			Host.Frame "Band" {
				AnchorPoint = V2.new(0.5, 0.5),
				Position = D2.fromScale(0.5, 0.5),
				Size = D2.new(1, -2, 1, -2),
				BackgroundTransparency = 1,
				ctx.corner(RING) :: Shared.Child,
				stroke(WHITE, 3),
				Host.Frame "Inner" {
					AnchorPoint = V2.new(0.5, 0.5),
					Position = D2.fromScale(0.5, 0.5),
					Size = D2.new(1, -6, 1, -6),
					BackgroundTransparency = 1,
					ctx.corner(RING) :: Shared.Child,
					stroke(BLACK, 1),
				},
			},
		})
	end

	local function swatch(name: string, edge: Shared.Value<UDim2>, paint: (Use) -> Paint): Frame
		local cells: { Shared.Child } = {}
		for index, place in { { 0, 0 }, { 0.5, 0 }, { 0, 0.5 }, { 0.5, 0.5 } } do
			table.insert(
				cells,
				Host.Frame(string.char(64 + index))({
					Size = D2.fromScale(0.5, 0.5),
					Position = D2.fromScale(place[1], place[2]),
					BorderSizePixel = 0,
					BackgroundColor3 = if index == 1 or index == 4 then LIGHT else DARK,
				})
			)
		end
		local checker: Shared.FrameNativeProps = {
			Name = "Checker",
			Size = D2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Visible = function(use: Use)
				local p = paint(use)
				return p.color ~= nil and p.alpha < 1
			end,
		}
		for _, cell in cells do
			table.insert(checker, cell)
		end
		return ctx.styled(
			Host.Frame(name)({
				Size = edge,
				BackgroundTransparency = 1,
				ctx.corner(6) :: Shared.Child,
				Host.UIStroke({ Thickness = 1, ApplyStrokeMode = E.ApplyStrokeMode.Border }),
				Host.Frame(checker),
				Host.Frame "Plate" {
					Size = D2.fromScale(1, 1),
					BorderSizePixel = 0,
					BackgroundColor3 = function(use: Use)
						return paint(use).color or WHITE
					end,
					BackgroundTransparency = function(use: Use)
						local p = paint(use)
						return if p.color == nil then 1 else 1 - p.alpha
					end,
					ctx.corner(6) :: Shared.Child,
				},
				Host.Frame "Empty" {
					AnchorPoint = V2.new(0.5, 0.5),
					Position = D2.fromScale(0.5, 0.5),
					Size = D2.new(1, 0, 0, 1),
					Rotation = -45,
					BorderSizePixel = 0,
					BackgroundColor3 = MUTED,
					Visible = function(use: Use)
						return paint(use).color == nil
					end,
				},
			}),
			"color-swatch"
		)
	end

	local function build(spec: Spec): Frame
		local function refuse(message: string): never
			error(`Facet UI.ColorPicker: {message}`, 0)
		end
		local options = (spec :: unknown) :: { [string]: unknown }
		if spec.allowEmpty ~= nil and type(spec.allowEmpty) ~= "boolean" then
			refuse("`allowEmpty` is true or false.")
		end
		local allowEmpty = spec.allowEmpty == true
		local initial: unknown = read(spec.value)
		if not (isColor(initial) or (initial == nil and allowEmpty)) then
			refuse("`value` is a Color3 (or a readable one); nil only with `allowEmpty = true`.")
		end
		for _, key in
			{
				"onChange",
				"onCommit",
				"onAlphaChange",
				"onPresentedChange",
				"onDismiss",
				"onSaveSwatch",
				"onRemoveSwatch",
			}
		do
			if options[key] ~= nil and type(options[key]) ~= "function" then
				refuse(`\`{key}\` is a function.`)
			end
		end
		local readOnlyNow: unknown = read(spec.readOnly)
		if readOnlyNow ~= nil and type(readOnlyNow) ~= "boolean" then
			refuse("`readOnly` is a boolean or a readable boolean.")
		end
		if spec.onChange == nil and not writable(spec.value) and readOnlyNow ~= true then
			refuse(
				"an interactive ColorPicker needs `onChange(color)` or a writable cell; only a readOnly one may omit it."
			)
		end
		local hasAlpha = spec.alpha ~= nil
		if hasAlpha then
			if not unit(read(spec.alpha)) then
				refuse("`alpha` is a number from 0 to 1 (or a readable one).")
			end
			if spec.onAlphaChange == nil and not writable(spec.alpha) and readOnlyNow ~= true then
				refuse("`alpha` needs `onAlphaChange(alpha)`: the pair mounts the opacity control.")
			end
		elseif spec.onAlphaChange ~= nil then
			refuse("`onAlphaChange` needs `alpha`: without it there is no opacity to change.")
		end
		local style = spec.style or "automatic"
		if style ~= "automatic" and style ~= "inline" then
			refuse('`style` is "automatic" (a well that opens the panel) or "inline" (the panel in place).')
		end
		if style == "inline" and (spec.isPresented ~= nil or spec.onPresentedChange ~= nil) then
			refuse("an inline panel is always shown: `isPresented` and `onPresentedChange` belong to the well.")
		end
		if spec.draft ~= nil and type(spec.draft) ~= "boolean" then
			refuse("`draft` is true or false.")
		end
		local draft = spec.draft == true
		if spec.placeholder ~= nil and type(spec.placeholder) ~= "string" then
			refuse("`placeholder` is a string.")
		end
		local modes: { string } = {}
		do
			local listed: unknown = spec.modes or DEFAULT_MODES
			if Compose.isReadable(listed) or type(listed) ~= "table" or #(listed :: { unknown }) == 0 then
				refuse(
					'`modes` is a non-empty list of "swatches" | "spectrum" | "sliders" | "brick", fixed at construction.'
				)
			end
			local seen: { [string]: boolean } = {}
			for _, word in listed :: { unknown } do
				if type(word) ~= "string" or MODE_LABEL[word] == nil or seen[word] then
					refuse(
						`\`modes\` names each of "swatches" | "spectrum" | "sliders" | "brick" at most once (got '{tostring(
							word
						)}').`
					)
				end
				seen[word :: string] = true
				table.insert(modes, word :: string)
			end
		end
		local brickMode = table.find(modes, "brick") ~= nil
		if brickMode and ctx.types.BrickColor == nil then
			refuse("the brick mode needs BrickColor in the controls' `types`.")
		end
		if spec.swatches ~= nil then
			local _, why = normalize(read(spec.swatches))
			if why ~= nil then
				refuse(`\`swatches\` {why}.`)
			end
		end
		chrome.check("ColorPicker", spec)
		local labelled = spec.label ~= nil

		local diagnostics = Compose.cell({} :: { string })
		local function note(line: string)
			local list = diagnostics:peek()
			if list[#list] ~= line then
				local nextList = table.clone(list)
				table.insert(nextList, line)
				if #nextList > 16 then
					table.remove(nextList, 1)
				end
				diagnostics:set(nextList)
			end
		end
		local function legalColor(value: unknown): boolean
			return isColor(value) or (value == nil and allowEmpty)
		end
		local held = Compose.cell(initial :: Color3?)
		Compose.watch(function(use: Use)
			local value: unknown = read(spec.value, use)
			if legalColor(value) then
				held:set(value :: Color3?)
			else
				note(
					`Facet UI.ColorPicker: \`value\` {if allowEmpty then "is a Color3 or nil" else "is a Color3"}; keeping the last legal value`
				)
			end
		end)
		local alphaHeld = Compose.cell(if hasAlpha then read(spec.alpha) :: number else 1)
		if hasAlpha then
			Compose.watch(function(use: Use)
				local value: unknown = read(spec.alpha, use)
				if unit(value) then
					alphaHeld:set(value :: number)
				else
					note("Facet UI.ColorPicker: `alpha` is a number from 0 to 1; keeping the last legal value")
				end
			end)
		end
		if spec.swatches ~= nil then
			Compose.watch(function(use: Use)
				local _, why = normalize(read(spec.swatches, use))
				if why ~= nil then
					note(`Facet UI.ColorPicker: \`swatches\` {why}; showing none`)
				end
			end)
		end
		local function enabled(use: Use?): boolean
			return read(spec.enabled, use) ~= false
		end
		local function interactive(use: Use?): boolean
			return enabled(use) and read(spec.readOnly, use) ~= true
		end
		local disposed = false
		Compose.cleanup(function()
			disposed = true
		end)
		local function mayEdit(): boolean
			return not disposed and interactive()
		end

		local canon = Compose.cell(color.hsvOf((initial :: Color3?) or WHITE))
		local snapshot: { value: Color3?, alpha: number, canon: Hsv } =
			{ value = held:peek(), alpha = alphaHeld:peek(), canon = canon:peek() }
		local function takeSnapshot()
			snapshot = { value = held:peek(), alpha = alphaHeld:peek(), canon = canon:peek() }
		end
		local echo: Color3? = nil
		local alphaEcho: number? = nil
		Compose.watch(function(use: Use)
			local value = use(held)
			if value ~= nil and not color.same(value, color.toColor(canon:peek())) then
				canon:set(color.hsvOf(value, canon:peek()))
			end
			if echo ~= nil and value ~= nil and color.same(value, echo) then
				echo = nil
			else
				snapshot.value, snapshot.canon = held:peek(), canon:peek()
			end
		end)
		Compose.watch(function(use: Use)
			local value = use(alphaHeld)
			if alphaEcho ~= nil and value == alphaEcho then
				alphaEcho = nil
			else
				snapshot.alpha = value
			end
		end)

		local function change(next: Color3?)
			if spec.onChange then
				((spec.onChange :: unknown) :: (Color3?) -> ())(next)
			elseif writable(spec.value) then
				((spec.value :: unknown) :: ComposeTypes.Cell<Color3?>):set(next)
			end
		end
		local function changeAlpha(next: number)
			if spec.onAlphaChange then
				spec.onAlphaChange(next)
			elseif writable(spec.alpha) then
				((spec.alpha :: unknown) :: ComposeTypes.Cell<number>):set(next)
			end
		end
		local function current(): Color3?
			local value: unknown = read(spec.value)
			return if isColor(value) then value :: Color3 else nil
		end
		local function propose(next: Hsv): boolean
			if not mayEdit() then
				return false
			end
			local proposal = color.toColor(next)
			local now = current()
			if now ~= nil and color.same(now, proposal) then
				canon:set(next)
				return true
			end
			echo = proposal
			change(proposal)
			now = current()
			if now ~= nil and color.same(now, proposal) then
				canon:set(next)
				return true
			end
			echo = nil
			return false
		end
		local function proposeAlpha(next: number): boolean
			if not mayEdit() or not hasAlpha then
				return false
			end
			next = math.clamp(next, 0, 1)
			if next == alphaHeld:peek() then
				return false
			end
			alphaEcho = next
			changeAlpha(next)
			local now: unknown = read(spec.alpha)
			if now == next then
				return true
			end
			alphaEcho = nil
			return false
		end
		local function commit()
			if disposed or draft or spec.onCommit == nil then
				return
			end
			local value = held:peek()
			if value ~= nil then
				spec.onCommit(value)
			end
		end
		local function apply()
			local value = held:peek()
			if spec.onCommit ~= nil and value ~= nil then
				spec.onCommit(value)
			end
			takeSnapshot()
		end
		local function restore()
			local saved = snapshot
			if disposed then
				return
			end
			local now = held:peek()
			if (now == nil) ~= (saved.value == nil) or not color.same(now, saved.value) then
				echo = saved.value
				change(saved.value)
			end
			if hasAlpha and alphaHeld:peek() ~= saved.alpha then
				alphaEcho = saved.alpha
				changeAlpha(saved.alpha)
			end
			canon:set(saved.canon)
		end

		local function brickName(c: Color3?): string?
			if c == nil or not brickMode then
				return nil
			end
			for _, entry in color.brick() do
				if color.same(entry.color, c) then
					return entry.label
				end
			end
			return nil
		end
		local function valueText(use: Use?): string
			local value = read(held, use)
			if value == nil then
				return spec.placeholder or ""
			end
			local a = read(alphaHeld, use)
			return color.hex(value, if hasAlpha and a < 1 then a else nil)
		end
		local function semanticName(use: Use?): string
			local words = brickName(read(held, use)) or valueText(use)
			local label = read(spec.label, use)
			return if type(label) == "string" and label ~= "" then `{label}, {words}` else words
		end
		local function currentPaint(use: Use): Paint
			return { color = use(held), alpha = use(alphaHeld) }
		end

		local gui = ctx.config.services.GuiService
		local input = ctx.config.services.UserInputService
		local selected = if gui then ctx.observe(gui, "SelectedObject") else Compose.cell(nil :: GuiObject?)
		local preferred = if input then ctx.observe(input, "PreferredInput") else Compose.cell(nil :: unknown)
		local function touch(use: Use?): boolean
			return read(preferred, use) == E.PreferredInput.Touch
		end
		local function gamepad(use: Use?): boolean
			return read(preferred, use) == E.PreferredInput.Gamepad
		end

		local ownOpen = Compose.cell(false)
		local function presented(use: Use?): boolean
			if spec.isPresented ~= nil then
				return read(spec.isPresented, use) == true
			end
			return read(ownOpen, use)
		end
		local function requestPresented(next: boolean)
			if next and (disposed or not interactive()) then
				return
			end
			if spec.onPresentedChange then
				spec.onPresentedChange(next)
			elseif spec.isPresented ~= nil then
				if writable(spec.isPresented) then
					((spec.isPresented :: unknown) :: ComposeTypes.Cell<boolean>):set(next)
				end
			else
				ownOpen:set(next)
			end
		end
		local wasOpen = false
		Compose.watch(function(use: Use)
			local open = presented(use)
			if open and not wasOpen then
				takeSnapshot()
			end
			wasOpen = open
		end)
		local function close(reason: Types.DismissReason)
			if style == "inline" or not presented() then
				return
			end
			if draft and reason ~= "apply" then
				restore()
			end
			requestPresented(false)
			if spec.onDismiss then
				spec.onDismiss(reason)
			end
		end

		local modeCell = Compose.cell(modes[1])
		local formatCell = Compose.cell("rgb")
		local hexError = Compose.cell("")
		local placement = Compose.cell(if style == "inline" then "inline" else "closed")
		local columns = Compose.cell(MAX_COLUMNS)
		local editing = Compose.cell(false)
		local saving = spec.onSaveSwatch ~= nil
		local removing = spec.onRemoveSwatch ~= nil
		local swatchList = Compose.formula(function(use: Use): { Item }
			if spec.swatches == nil then
				return color.standard(use(columns))
			end
			return (normalize(read(spec.swatches, use))) or {}
		end)

		local function channelSlider(
			name: string,
			words: string,
			max: number,
			get: (Hsv) -> number,
			with: (Hsv, number) -> Hsv,
			track: (() -> Instance)?,
			knob: ((Inputs.SliderKnob) -> Instance)?
		): Frame
			local props: Inputs.SliderProps = {
				label = words,
				value = function(use: Use): number
					return get(use(canon)) * max
				end,
				min = 0,
				max = max,
				step = 1,
				enabled = function(use: Use): boolean
					return interactive(use)
				end,
				format = function(n: number): string
					return tostring(math.floor(n + 0.5))
				end,
				trackContent = track,
				thumbContent = knob,
				onChange = function(n: number)
					propose(with(canon:peek(), n / max))
				end,
				onCommit = function()
					commit()
				end,
			}
			local node = UI.Slider(name)(props)
			local found = node:FindFirstChild("Track", true)
			if found then
				found:SetAttribute("AccessibleLabel", words)
			end
			return node
		end
		local function bubble(paint: (Use) -> Color3, shown: (Use) -> boolean, place: Shared.FrameNativeProps): Frame
			local props: Shared.FrameNativeProps = {
				Name = "Bubble",
				Size = D2.fromOffset(BUBBLE, BUBBLE),
				BorderSizePixel = 0,
				ZIndex = 6,
				BackgroundColor3 = paint,
				Visible = function(use: Use)
					return touch(use) and shown(use)
				end,
				ctx.corner(BUBBLE) :: Shared.Child,
				Host.UIStroke({ Color = WHITE, Thickness = 2, Transparency = 0 }),
			}
			for key, value in (place :: unknown) :: { [string]: unknown } do
				((props :: unknown) :: { [string]: unknown })[key] = value
			end
			return Host.Frame(props)
		end
		local function ringKnob(paint: (Inputs.SliderKnob) -> (Use) -> Color3): (Inputs.SliderKnob) -> Instance
			return function(info: Inputs.SliderKnob): Instance
				return Host.Frame "Mark" {
					Size = D2.fromOffset(RING, RING),
					BackgroundTransparency = 1,
					ring("Ring"),
					bubble(paint(info), function(use: Use)
						return use(info.dragging)
					end, {
						AnchorPoint = V2.new(0.5, 1),
						Position = D2.new(0.5, 0, 0, -SPACE),
					}),
				}
			end
		end
		local function hueStrip(): Instance
			local points: { ColorSequenceKeypoint } = {}
			for index = 0, 6 do
				table.insert(
					points,
					ctx.types.ColorSequenceKeypoint.new(index / 6, color.toColor({ h = (index % 6) / 6, s = 1, v = 1 }))
				)
			end
			return Host.Frame "HueStrip" {
				AnchorPoint = V2.new(0.5, 0.5),
				Position = D2.fromScale(0.5, 0.5),
				Size = D2.new(1, 0, 0, STRIP),
				BackgroundColor3 = WHITE,
				BorderSizePixel = 0,
				ctx.corner(STRIP) :: Shared.Child,
				Host.UIGradient "Rainbow" { Color = ctx.types.ColorSequence.new(points), Rotation = 0 },
			}
		end
		local function alphaStrip(): Instance
			local rows: { Shared.Child } = {}
			for row = 1, 2 do
				local cells: { Shared.Child } = {}
				for index = 1, CHECKER_CELLS do
					table.insert(
						cells,
						Host.Frame(`C{index}`)({
							Size = D2.fromScale(1 / CHECKER_CELLS, 1),
							BorderSizePixel = 0,
							LayoutOrder = index,
							BackgroundColor3 = if (index + row) % 2 == 0 then LIGHT else DARK,
						})
					)
				end
				local props: Shared.FrameNativeProps = {
					Name = if row == 1 then "Top" else "Bottom",
					Size = D2.fromScale(1, 0.5),
					Position = D2.fromScale(0, (row - 1) / 2),
					BackgroundTransparency = 1,
					Host.UIListLayout({
						FillDirection = E.FillDirection.Horizontal,
						SortOrder = E.SortOrder.LayoutOrder,
					}),
				}
				for _, cell in cells do
					table.insert(props, cell)
				end
				table.insert(rows, Host.Frame(props))
			end
			local checker: Shared.FrameNativeProps = {
				Name = "Checker",
				Size = D2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ClipsDescendants = true,
			}
			for _, row in rows do
				table.insert(checker, row)
			end
			return Host.Frame "AlphaStrip" {
				AnchorPoint = V2.new(0.5, 0.5),
				Position = D2.fromScale(0.5, 0.5),
				Size = D2.new(1, 0, 0, STRIP),
				BackgroundTransparency = 1,
				Host.Frame(checker),
				Host.Frame "Ramp" {
					Size = D2.fromScale(1, 1),
					BorderSizePixel = 0,
					BackgroundColor3 = function(use: Use)
						return use(held) or color.toColor(use(canon))
					end,
					Host.UIGradient({
						Transparency = ctx.types.NumberSequence.new({
							ctx.types.NumberSequenceKeypoint.new(0, 1),
							ctx.types.NumberSequenceKeypoint.new(1, 0),
						}),
						Rotation = 0,
					}),
				},
			}
		end
		local function hueSlider(): Frame
			return channelSlider(
				"Hue",
				"Hue",
				360,
				function(c: Hsv): number
					return c.h
				end,
				function(c: Hsv, f: number): Hsv
					return { h = f, s = c.s, v = c.v }
				end,
				hueStrip,
				ringKnob(function(info: Inputs.SliderKnob): (Use) -> Color3
					return function(use: Use): Color3
						return color.toColor({ h = use(info.value) / 360, s = 1, v = 1 })
					end
				end)
			)
		end

		local function planeView(): Frame
			local dragging = Compose.cell(false)
			local dragStart: Hsv? = nil
			local surface: Frame
			local plane: Frame
			local planeSize: ComposeTypes.Readable<Vector2>
			local function fractions(position: Vector2): (number?, number?)
				local at, size = surface.AbsolutePosition, surface.AbsoluteSize
				if size.X <= 0 or size.Y <= 0 then
					return nil, nil
				end
				return math.clamp((position.X - at.X) / size.X, 0, 1), math.clamp((position.Y - at.Y) / size.Y, 0, 1)
			end
			local function setFrom(position: Vector2)
				local fx, fy = fractions(position)
				if fx == nil or fy == nil then
					return
				end
				local now = canon:peek()
				propose({ h = now.h, s = fx, v = 1 - fy })
			end
			local function beginDrag(position: Vector2)
				if not mayEdit() then
					return
				end
				if not dragging:peek() then
					dragStart = canon:peek()
					dragging:set(true)
				end
				setFrom(position)
			end
			local function endDrag()
				if not dragging:peek() then
					return
				end
				dragging:set(false)
				dragStart = nil
				commit()
			end
			local function cancelDrag()
				if not dragging:peek() then
					return
				end
				dragging:set(false)
				local start = dragStart
				dragStart = nil
				if start ~= nil then
					propose(start)
				end
			end
			local first = true
			Compose.watch(function(use: Use)
				use(preferred)
				if not first then
					cancelDrag()
				end
				first = false
			end)
			Compose.watch(function(use: Use)
				if not interactive(use) then
					cancelDrag()
				end
			end)
			local function spot(use: Use, size: number): (number, number)
				local extent = use(planeSize)
				local c = use(canon)
				local x, y = c.s * extent.X, (1 - c.v) * extent.Y
				return math.clamp(x, size / 2, math.max(size / 2, extent.X - size / 2)),
					math.clamp(y, size / 2, math.max(size / 2, extent.Y - size / 2))
			end
			local mark = ring("Ring")
			surface = Host.Frame "Surface" {
				Size = D2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = 5,
				Selectable = function(use: Use)
					return interactive(use)
				end,
				Host.UIDragDetector "Drag" {
					ResponseStyle = E.UIDragDetectorResponseStyle.CustomOffset,
					Enabled = function(use: Use)
						return interactive(use)
					end,
					DragStart = beginDrag,
					DragContinue = function(position: Vector2)
						if dragging:peek() then
							setFrom(position)
						end
					end,
					DragEnd = endDrag,
				},
			}
			surface:SetAttribute("AccessibleLabel", "Saturation and brightness")
			plane = Host.Frame "Plane" {
				Size = D2.new(1, 0, 0, 4 * CELL),
				BackgroundTransparency = 1,
				Host.Frame "Field" {
					Size = D2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Host.Frame "Hue" {
						Size = D2.fromScale(1, 1),
						BorderSizePixel = 0,
						BackgroundColor3 = WHITE,
						Host.UIGradient "Gradient" {
							Rotation = 0,
							Color = function(use: Use)
								local hue = color.toColor({ h = use(canon).h, s = 1, v = 1 })
								return ctx.types.ColorSequence.new({
									ctx.types.ColorSequenceKeypoint.new(0, WHITE),
									ctx.types.ColorSequenceKeypoint.new(1, hue),
								})
							end,
						},
					},
					Host.Frame "Value" {
						Size = D2.fromScale(1, 1),
						BorderSizePixel = 0,
						BackgroundColor3 = BLACK,
						Host.UIGradient "Gradient" {
							Rotation = 90,
							Transparency = ctx.types.NumberSequence.new({
								ctx.types.NumberSequenceKeypoint.new(0, 1),
								ctx.types.NumberSequenceKeypoint.new(1, 0),
							}),
						},
					},
				},
				surface,
			}
			planeSize = ctx.observe(plane, "AbsoluteSize")
			runtime.decorate(mark, {
				AnchorPoint = V2.new(0.5, 0.5),
				ZIndex = 4,
				Visible = function(use: Use)
					return use(held) ~= nil
				end,
				Position = function(use: Use)
					local extent = use(planeSize)
					if extent.X <= 0 then
						local c = use(canon)
						return D2.fromScale(c.s, 1 - c.v)
					end
					local x, y = spot(use, RING)
					return D2.fromOffset(x, y)
				end,
			})
			surfaces.attach(plane, {
				mark,
				bubble(function(use: Use): Color3
					return color.toColor(use(canon))
				end, function(use: Use): boolean
					return use(dragging)
				end, {
					AnchorPoint = V2.new(0.5, 1),
					Position = function(use: Use)
						local extent = use(planeSize)
						if extent.X <= 0 then
							local c = use(canon)
							return D2.new(c.s, 0, 1 - c.v, -(RING / 2 + SPACE))
						end
						local x, y = spot(use, RING)
						local above = y - RING / 2 - SPACE
						local across = math.max(BUBBLE / 2, extent.X - BUBBLE / 2)
						if above >= BUBBLE then
							return D2.fromOffset(math.clamp(x, BUBBLE / 2, across), above)
						end
						local side = RING / 2 + SPACE + BUBBLE / 2
						local beside = if x + side + BUBBLE / 2 <= extent.X then x + side else x - side
						return D2.fromOffset(
							math.clamp(beside, BUBBLE / 2, across),
							math.clamp(y + BUBBLE / 2, BUBBLE, math.max(BUBBLE, extent.Y))
						)
					end,
				}),
			})
			local function planeSelected(use: Use?): boolean
				return (read(selected, use) :: Instance?) == (surface :: Instance)
			end
			local stick = V2.zero
			local stopFrames: (() -> ())? = nil
			local function endSession()
				local stop = stopFrames
				if stop then
					stopFrames = nil
					stop()
					commit()
				end
			end
			local function steer(dt: number)
				if dt <= 0 then
					return
				end
				if not planeSelected() or not mayEdit() then
					endSession()
					return
				end
				local now = canon:peek()
				propose({
					h = now.h,
					s = math.clamp(now.s + stick.X * STICK_SPEED * dt, 0, 1),
					v = math.clamp(now.v + stick.Y * STICK_SPEED * dt, 0, 1),
				})
			end
			local steerAction = ctx.action(surface, "ColorPlaneSteer", { E.KeyCode.Thumbstick2 }, function(use: Use)
				return planeSelected(use) and interactive(use)
			end, function() end, { priority = 2200 })
			runtime.decorate(steerAction, {
				Type = E.InputActionType.Direction2D,
				StateChanged = function(value: unknown)
					if typeof(value) ~= "Vector2" then
						return
					end
					local direction = value :: Vector2
					if direction.Magnitude < DEADZONE then
						stick = V2.zero
						endSession()
						return
					end
					stick = direction
					if stopFrames == nil then
						stopFrames = assert(runtime.host.frames).onFrame(steer)
					end
				end,
			})
			Compose.watch(function(use: Use)
				if not planeSelected(use) then
					stick = V2.zero
					endSession()
				end
			end)
			Compose.cleanup(function()
				local stop = stopFrames
				stopFrames = nil
				if stop then
					stop()
				end
			end)
			local hintProps: Inputs.ShortcutHintProps =
				{ keys = { { "Right Stick" } }, controlSize = "compact" :: "compact" }
			local hint = ctx.row({
				UI.ShortcutHint("StickKey")(hintProps),
				ctx.styled(ctx.text({ Name = "Words", Text = "Move saturation and brightness" }), "type-caption"),
			}, {
				Name = "StickHint",
				Visible = function(use: Use)
					return gamepad(use) and planeSelected(use)
				end,
			})
			return ctx.column({ plane, hint, hueSlider() }, {
				Name = "Spectrum",
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
			})
		end

		local function landAfterRemoval(grid: Instance, index: number)
			if not gui then
				return
			end
			local cells: { GuiObject } = {}
			for _, child in grid:GetChildren() do
				if child:IsA("GuiObject") then
					table.insert(cells, child)
				end
			end
			table.sort(cells, function(a: GuiObject, b: GuiObject): boolean
				return a.LayoutOrder < b.LayoutOrder
			end)
			local target = cells[math.min(index, #cells)]
			if target then
				gui.SelectedObject = target
			end
		end

		local function gridView(name: string, items: (Use) -> { Item }, removable: boolean): Frame
			local owned: { [Instance]: { item: ComposeTypes.Readable<Item>, index: ComposeTypes.Readable<number> } } =
				{}
			local grid: Frame
			local function removeAt(item: Item, index: number)
				if not mayEdit() then
					return
				end
				local remove = spec.onRemoveSwatch
				if remove == nil then
					return
				end
				remove({ color = item.color, label = item.label, key = item.key })
				if grid:FindFirstChild(item.key) == nil then
					landAfterRemoval(grid, index)
				end
			end
			local function saveCell(index: ComposeTypes.Readable<number>): TextButton
				local function fresh(use: Use?): boolean
					local value = read(held, use)
					if value == nil or read(editing, use) then
						return false
					end
					for _, entry in read(swatchList, use) do
						if color.same(entry.color, value) or entry.key == color.hex(value) then
							return false
						end
					end
					return true
				end
				return UI.Button("Save")({
					name = "Save colour",
					appearance = "utility",
					Size = D2.fromOffset(CELL, CELL),
					AutomaticSize = E.AutomaticSize.None,
					LayoutOrder = function(use: Use)
						return use(index)
					end,
					enabled = function(use: Use)
						return interactive(use) and fresh(use)
					end,
					onActivate = function()
						local value = held:peek()
						local save = spec.onSaveSwatch
						if value ~= nil and save ~= nil and fresh() then
							save(value)
						end
					end,
					Host.Frame "Plus" {
						Size = D2.fromScale(1, 1),
						BackgroundTransparency = 1,
						ctx.icon("increment", {
							Name = "Mark",
							AnchorPoint = V2.new(0.5, 0.5),
							Position = D2.fromScale(0.5, 0.5),
						}),
					},
				})
			end
			local function cell(
				source: ComposeTypes.Readable<Item>,
				index: ComposeTypes.Readable<number>,
				key: string
			): Instance
				if key == SAVE_KEY then
					return saveCell(index)
				end
				local function chosen(use: Use): boolean
					local value = use(held)
					return value ~= nil and color.same(value, use(source).color)
				end
				local node = UI.Button(key)({
					name = function(use: Use): string
						local entry = use(source)
						local named = entry.label or color.hex(entry.color)
						return if removable and use(editing) then `Remove {named}` else named
					end,
					appearance = "utility",
					Size = D2.fromOffset(CELL, CELL),
					AutomaticSize = E.AutomaticSize.None,
					LayoutOrder = function(use: Use)
						return use(index)
					end,
					selected = chosen,
					enabled = function(use: Use)
						return interactive(use)
					end,
					onActivate = function()
						local entry = source:peek()
						if removable and editing:peek() then
							removeAt(entry, index:peek())
							return
						end
						if propose(color.hsvOf(entry.color, canon:peek())) then
							commit()
						end
					end,
					swatch("Swatch", D2.fromScale(1, 1), function(use: Use): Paint
						return { color = use(source).color, alpha = 1 }
					end) :: Shared.Child,
					ctx.icon("checkmark", {
						Name = "Check",
						AnchorPoint = V2.new(0.5, 0.5),
						Position = D2.fromScale(0.5, 0.5),
						Visible = function(use: Use)
							return chosen(use) and not (removable and use(editing))
						end,
					}),
				})
				if removable then
					surfaces.attach(node, {
						ctx.icon("close", {
							Name = "Remove",
							AnchorPoint = V2.new(0.5, 0.5),
							Position = D2.fromScale(0.5, 0.5),
							Visible = editing,
						}),
					})
				end
				owned[node] = { item = source, index = index }
				Compose.cleanup(function()
					owned[node] = nil
				end)
				return node
			end
			grid = Host.Frame(name)({
				BackgroundTransparency = 1,
				Size = function(use: Use)
					local n = math.max(1, math.min(use(columns), #items(use)))
					return D2.fromOffset(n * CELL + (n - 1) * GAP, 0)
				end,
				AutomaticSize = E.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = E.FillDirection.Horizontal,
					SortOrder = E.SortOrder.LayoutOrder,
					Wraps = true,
					Padding = D.new(0, GAP),
				}) :: Shared.Child,
				Compose.keyed({
					from = items,
					key = function(entry: Item): string
						return entry.key
					end,
					render = cell,
				}),
			})
			if removable then
				local function focused(
					use: Use?
				): { item: ComposeTypes.Readable<Item>, index: ComposeTypes.Readable<number> }?
					local node = read(selected, use)
					return if node then owned[node] else nil
				end
				ctx.action(grid, "ColorSwatchRemove", {
					E.KeyCode.Delete,
					E.KeyCode.Backspace,
					E.KeyCode.ButtonX,
				}, function(use: Use)
					return use(editing) and interactive(use) and focused(use) ~= nil
				end, function()
					local entry = focused()
					if entry and editing:peek() then
						removeAt(entry.item:peek(), entry.index:peek())
					end
				end, { priority = 2300 })
			end
			return grid
		end

		local function swatchesView(): Frame
			local items = function(use: Use): { Item }
				local list = table.clone(use(swatchList))
				if saving then
					table.insert(list, { key = SAVE_KEY, color = WHITE })
				end
				return list
			end
			local parts: { Shared.Child } = {}
			if removing then
				table.insert(
					parts,
					UI.Button("Edit")({
						label = function(use: Use)
							return if use(editing) then "Done" else "Edit"
						end,
						appearance = "link",
						enabled = function(use: Use)
							return interactive(use)
						end,
						onActivate = function()
							editing:set(not editing:peek())
						end,
					})
				)
			end
			table.insert(parts, gridView("Swatches", items, removing))
			return ctx.column(parts, { Name = "Saved", Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y })
		end

		local function slidersView(): Frame
			return ctx.column({
				hueSlider(),
				channelSlider("Saturation", "Saturation", 100, function(c: Hsv): number
					return c.s
				end, function(c: Hsv, f: number): Hsv
					return { h = c.h, s = f, v = c.v }
				end),
				channelSlider("Brightness", "Brightness", 100, function(c: Hsv): number
					return c.v
				end, function(c: Hsv, f: number): Hsv
					return { h = c.h, s = c.s, v = f }
				end),
			}, { Name = "Sliders", Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y })
		end

		local function brickView(): Frame
			local bricks = color.brick()
			return ctx.column({
				ctx.styled(
					ctx.row({
						ctx.text({
							Name = "BrickName",
							Text = function(use: Use)
								return brickName(use(held)) or "No engine colour matches"
							end,
						}),
					}, { Name = "NameField", ctx.padding(SPACE, 6) :: Shared.Child }),
					"field"
				),
				gridView("BrickGrid", function(): { Item }
					return bricks
				end, false),
			}, { Name = "Brick", Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y })
		end

		local function numberField(
			name: string,
			words: string,
			max: number,
			get: (Color3, Hsv) -> number,
			with: (number) -> Hsv?
		): GuiObject
			local text, number = Compose.cell(""), Compose.cell(0)
			local function resync()
				local value = held:peek()
				local n = if value == nil then nil else get(value, canon:peek())
				number:set(n or 0)
				text:set(if n == nil then "" else tostring(n))
			end
			Compose.watch(function(use: Use)
				use(held)
				use(canon)
				resync()
			end)
			local props: Inputs.NumberInputProps = {
				label = words,
				value = text,
				numericValue = number,
				min = 0,
				max = max,
				precision = 0,
				enabled = function(use: Use)
					return interactive(use)
				end,
				Size = D2.new(1 / 3, -6, 0, 0),
				onCommit = function(n: number)
					local next = with(n)
					if next ~= nil and propose(next) then
						commit()
					end
					resync()
				end,
			}
			return UI.NumberInput(name)(props)
		end
		local function rgbFields(): Frame
			local function channel(index: number, words: string): GuiObject
				return numberField(`Field{words}`, words, 255, function(value: Color3): number
					return (select(index, color.channels(value)))
				end, function(n: number): Hsv?
					local r, g, b = color.channels(held:peek() or color.toColor(canon:peek()))
					local bytes = { r, g, b }
					bytes[index] = n
					return color.hsvOf(color.fromBytes(bytes[1], bytes[2], bytes[3]), canon:peek())
				end)
			end
			return ctx.row(
				{ channel(1, "R"), channel(2, "G"), channel(3, "B") },
				{ Name = "Fields", Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y }
			)
		end
		local function hsvFields(): Frame
			local function channel(key: "h" | "s" | "v", words: string, max: number): GuiObject
				return numberField(`Field{words}`, words, max, function(_: Color3, c: Hsv): number
					return math.floor(c[key] * max + 0.5)
				end, function(n: number): Hsv?
					local c = table.clone(canon:peek())
					c[key] = n / max
					return c
				end)
			end
			return ctx.row(
				{ channel("h", "H", 360), channel("s", "S", 100), channel("v", "V", 100) },
				{ Name = "Fields", Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y }
			)
		end
		local function hexFields(): Frame
			local text = Compose.cell("")
			local function formatted(): string
				local value = held:peek()
				return if value == nil then "" else color.hex(value, if hasAlpha then alphaHeld:peek() else nil)
			end
			Compose.watch(function(use: Use)
				use(held)
				use(alphaHeld)
				text:set(formatted())
				hexError:set("")
			end)
			local props: Inputs.TextInputProps = {
				label = "Hex",
				value = text,
				errorText = hexError,
				enabled = function(use: Use)
					return interactive(use)
				end,
				onCommit = function(typed: string)
					local parsed, a, why = color.parseHex(typed, hasAlpha)
					if parsed == nil then
						hexError:set(why or "Check this colour.")
						return
					end
					hexError:set("")
					local moved = propose(color.hsvOf(parsed, canon:peek()))
					if a ~= nil then
						moved = proposeAlpha(a) or moved
					end
					if moved then
						commit()
					end
					text:set(formatted())
				end,
			}
			return ctx.row(
				{ UI.TextInput("FieldHex")(props) },
				{ Name = "Fields", Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y }
			)
		end
		local function readoutView(): Frame
			local builders: { [string]: () -> Frame } = { rgb = rgbFields, hsv = hsvFields, hex = hexFields }
			local values: Shared.FrameNativeProps = {
				Name = "Values",
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder }),
			}
			for _, format in FORMATS do
				table.insert(
					values,
					Compose.show(function(use: Use)
						return use(formatCell) == format.value
					end, builders[format.value])
				)
			end
			local formatProps: Nav.SinglePickerSpec<string> = {
				selected = formatCell,
				style = "segmented" :: "segmented",
				options = FORMATS,
				Size = D2.fromOffset(0, CELL),
				AutomaticSize = E.AutomaticSize.X,
			}
			local picker = UI.Picker("Format")(formatProps)
			local head = ctx.row({
				swatch("Preview", D2.fromOffset(CELL, CELL), currentPaint),
				picker,
			}, { Name = "Head", Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y })
			assert(head:FindFirstChildWhichIsA("UIListLayout")).VerticalAlignment = E.VerticalAlignment.Center
			return ctx.column(
				{ head, Host.Frame(values) },
				{ Name = "Readout", Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y }
			)
		end

		local function panelView(
			overlay: boolean,
			sheet: (Use) -> boolean,
			room: ComposeTypes.Readable<number>
		): PanelView
			local builders: { [string]: () -> Frame } =
				{ swatches = swatchesView, spectrum = planeView, sliders = slidersView, brick = brickView }
			local shows: { Frame } = {}
			local technique: Shared.FrameNativeProps = {
				Name = "Technique",
				BackgroundTransparency = 1,
			}
			for _, mode in modes do
				local show = Host.Frame(`Show{MODE_LABEL[mode]}`)({
					Size = D2.new(1, 0, 0, 0),
					AutomaticSize = E.AutomaticSize.Y,
					BackgroundTransparency = 1,
					Visible = function(use: Use)
						return use(modeCell) == mode
					end,
					builders[mode]() :: Shared.Child,
				})
				table.insert(shows, show)
				table.insert(technique, show)
			end
			local heights: { ComposeTypes.Readable<Vector2> } = {}
			for _, show in shows do
				table.insert(heights, ctx.observe(show, "AbsoluteSize"))
			end
			local function tech(use: Use): number
				local tallest = 0
				for _, size in heights do
					tallest = math.max(tallest, use(size).Y)
				end
				return tallest
			end
			technique.Size = function(use: Use)
				return D2.new(1, 0, 0, tech(use))
			end
			local techniqueNode = Host.Frame(technique)
			local width = ctx.observe(techniqueNode, "AbsoluteSize")
			Compose.watch(function(use: Use)
				local w = use(width).X
				columns:set(
					if w > 0 then math.clamp(math.floor((w + GAP) / (CELL + GAP)), 1, MAX_COLUMNS) else MAX_COLUMNS
				)
			end)
			local measured: { { node: GuiObject, size: ComposeTypes.Readable<Vector2> } } = {}
			local function measure(node: GuiObject): GuiObject
				local size: ComposeTypes.Readable<Vector2> = ctx.observe(node, "AbsoluteSize")
				table.insert(measured, { node = node, size = size })
				return node
			end
			local children: { Shared.Child } = {}
			if #modes > 1 then
				local options: { Nav.PickerOption<string> } = {}
				for _, mode in modes do
					table.insert(options, { value = mode, label = MODE_LABEL[mode] })
				end
				local modeProps: Nav.SinglePickerSpec<string> =
					{ selected = modeCell, style = "automatic" :: "automatic", options = options, LayoutOrder = 1 }
				table.insert(children, measure(UI.Picker("Modes")(modeProps)))
			end
			local readout = readoutView()
			runtime.decorate(readout, {
				LayoutOrder = function(use: Use)
					return if touch(use) then 2 else 5
				end,
			})
			table.insert(children, measure(readout))
			local body: GuiObject
			if overlay then
				body = Host.ScrollingFrame "Body" {
					LayoutOrder = 3,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Selectable = false,
					ScrollBarThickness = 4,
					ScrollingDirection = E.ScrollingDirection.Y,
					AutomaticCanvasSize = E.AutomaticSize.Y,
					CanvasSize = D2.fromOffset(0, 0),
					Size = function(use: Use)
						local cap = math.max(0, use(room))
						return D2.new(1, 0, 0, math.min(tech(use), cap))
					end,
					techniqueNode :: Shared.Child,
				}
			else
				runtime.decorate(techniqueNode, { LayoutOrder = 3 })
				body = techniqueNode
			end
			table.insert(children, body)
			if hasAlpha then
				local opacity: Inputs.SliderProps = {
					label = "Opacity",
					LayoutOrder = 4,
					value = function(use: Use): number
						return use(alphaHeld) * 100
					end,
					min = 0,
					max = 100,
					step = 1,
					enabled = function(use: Use): boolean
						return interactive(use)
					end,
					format = function(n: number): string
						return `{math.floor(n + 0.5)}%`
					end,
					trackContent = alphaStrip,
					thumbContent = ringKnob(function(): (Use) -> Color3
						return function(use: Use): Color3
							return use(held) or color.toColor(use(canon))
						end
					end),
					onChange = function(n: number)
						proposeAlpha(n / 100)
					end,
					onCommit = function()
						commit()
					end,
				}
				local slider = UI.Slider("Opacity")(opacity)
				local track = slider:FindFirstChild("Track", true)
				if track then
					track:SetAttribute("AccessibleLabel", "Opacity")
				end
				table.insert(children, measure(slider))
			end
			local actions: { Shared.Child } = {}
			if draft then
				local cancelProps: Inputs.ButtonProps = {
					label = "Cancel",
					role = "cancel" :: "cancel",
					onActivate = function()
						if overlay then
							close("cancel")
						else
							restore()
						end
					end,
				}
				table.insert(actions, UI.Button("Cancel")(cancelProps))
				table.insert(
					actions,
					UI.Button("Apply")({
						label = "Apply",
						appearance = "emphasis",
						onActivate = function()
							apply()
							if overlay then
								close("apply")
							end
						end,
					})
				)
			elseif overlay then
				table.insert(
					actions,
					UI.Button("Done")({
						label = "Done",
						onActivate = function()
							close("activate")
						end,
					})
				)
			end
			if #actions > 0 then
				local row = ctx.row(actions, {
					Name = "Actions",
					LayoutOrder = 6,
					Size = D2.new(1, 0, 0, 0),
					AutomaticSize = E.AutomaticSize.Y,
					Visible = if draft
						then true
						else function(use: Use)
							return sheet(use)
						end,
				})
				assert(row:FindFirstChildWhichIsA("UIListLayout")).HorizontalAlignment = E.HorizontalAlignment.Right
				table.insert(children, measure(row))
			end
			local props: Shared.FrameNativeProps = {
				Name = "Panel",
				BackgroundTransparency = if overlay then 0 else 1,
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = if overlay then E.AutomaticSize.None else E.AutomaticSize.Y,
				Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder, Padding = D.new(0, SPACE) }),
			}
			if overlay then
				table.insert(props, ctx.padding(PAD, PAD))
				table.insert(props, ctx.corner())
			end
			for _, child in children do
				table.insert(props, child)
			end
			local panel = Host.Frame(props)
			local visibility: { ComposeTypes.Readable<boolean> } = {}
			for _, entry in measured do
				table.insert(visibility, ctx.observe(entry.node, "Visible"))
			end
			local function chromeHeight(use: Use): number
				local total, count = 0, 1
				for index, entry in measured do
					if use(visibility[index]) then
						local extent: Vector2 = use(entry.size)
						total += extent.Y
						count += 1
					end
				end
				return total + (count - 1) * SPACE + (if overlay then 2 * PAD else 0)
			end
			return { panel = panel, chrome = chromeHeight, tech = tech }
		end

		local function place(
			use: Use,
			view: PanelView,
			sheet: (Use) -> boolean,
			extent: ComposeTypes.Readable<Vector2>,
			origin: ComposeTypes.Readable<Vector2>,
			at: ComposeTypes.Readable<Vector2>,
			bounds: ComposeTypes.Readable<Vector2>,
			tenFoot: boolean
		): Placement
			local offer = use(extent)
			local corner = use(at) - use(origin)
			local size = use(bounds)
			local natural = view.chrome(use) + view.tech(use)
			if sheet(use) then
				local h = if offer.Y > 0 then math.min(natural, offer.Y - 2 * PAD) else natural
				if tenFoot then
					local w = if offer.X > 0 then math.min(PANEL_WIDTH, offer.X - 2 * PAD) else PANEL_WIDTH
					return {
						edge = "center",
						x = math.max(PAD, (offer.X - w) / 2),
						y = math.max(PAD, (offer.Y - h) / 2),
						w = w,
						h = h,
					}
				end
				return { edge = "sheet", x = PAD, y = math.max(PAD, offer.Y - h - PAD), w = offer.X - 2 * PAD, h = h }
			end
			local w = if offer.X > 0 then math.min(PANEL_WIDTH, math.max(CELL, offer.X - 2 * MARGIN)) else PANEL_WIDTH
			local below = offer.Y - (corner.Y + size.Y + GAP) - MARGIN
			local above = corner.Y - GAP - MARGIN
			local x = math.clamp(corner.X, MARGIN, math.max(MARGIN, offer.X - w - MARGIN))
			if natural <= below then
				return { edge = "bottom", x = x, y = corner.Y + size.Y + GAP, w = w, h = natural }
			end
			if natural <= above then
				return { edge = "top", x = x, y = corner.Y - GAP - natural, w = w, h = natural }
			end
			local right = corner.X + size.X + GAP + w <= offer.X - MARGIN
			local left = corner.X - GAP - w >= MARGIN
			if right or left then
				local h = math.min(natural, math.max(2 * CELL, offer.Y - 2 * MARGIN))
				local y = math.clamp(corner.Y, MARGIN, math.max(MARGIN, offer.Y - h - MARGIN))
				return {
					edge = if right then "right" else "left",
					x = if right then corner.X + size.X + GAP else corner.X - GAP - w,
					y = y,
					w = w,
					h = h,
				}
			end
			if below >= above then
				return { edge = "bottom", x = x, y = corner.Y + size.Y + GAP, w = w, h = math.max(2 * CELL, below) }
			end
			local h = math.max(2 * CELL, above)
			return { edge = "top", x = x, y = corner.Y - GAP - h, w = w, h = h }
		end

		local rootProps = ctx.props(spec, KEYS, {
			Name = "ColorPicker",
			BackgroundTransparency = 1,
			Size = if labelled or style == "inline" then D2.new(1, 0, 0, 0) else D2.fromOffset(0, 0),
			AutomaticSize = if labelled or style == "inline" then E.AutomaticSize.Y else E.AutomaticSize.XY,
		})
		local root: Frame
		if style == "inline" then
			local view = panelView(false, function()
				return false
			end, Compose.cell(math.huge))
			if chrome.present(spec) then
				root = chrome.wrap({
					control = "ColorPicker",
					spec = {
						label = spec.label,
						requiredMark = spec.requiredMark,
						hint = spec.hint,
						errorText = spec.errorText,
						appearance = spec.appearance,
					},
					plate = view.panel,
					focus = function() end,
					enabled = enabled,
					native = rootProps,
				})
			else
				root = ctx.column({ view.panel }, rootProps)
			end
		else
			local parts: { Shared.Child } = {}
			if labelled then
				table.insert(
					parts,
					ctx.text({
						Name = "Title",
						Text = function(use: Use)
							return chrome.labelText(spec, use)
						end,
						Size = D2.new(0, 0, 0, 0),
						AutomaticSize = E.AutomaticSize.XY,
						TextTruncate = E.TextTruncate.AtEnd,
						Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }) :: Shared.Child,
					})
				)
			end
			local edge = if labelled then 24 else 32
			table.insert(parts, swatch("Swatch", D2.fromOffset(edge, edge), currentPaint))
			if labelled then
				table.insert(
					parts,
					ctx.styled(
						ctx.text({
							Name = "Value",
							Text = function(use: Use)
								return valueText(use)
							end,
							TextTruncate = E.TextTruncate.AtEnd,
						}),
						"secondary"
					)
				)
				table.insert(parts, ctx.icon("chevron.down", { Name = "Chevron" }))
			end
			local row = ctx.row(parts, {
				Name = "Row",
				Size = if labelled then D2.fromScale(1, 1) else D2.fromOffset(0, 0),
				AutomaticSize = if labelled then E.AutomaticSize.None else E.AutomaticSize.XY,
				ctx.padding(if labelled then 10 else 6, 0) :: Shared.Child,
			})
			local layout = assert(row:FindFirstChildWhichIsA("UIListLayout"))
			layout.VerticalAlignment = E.VerticalAlignment.Center
			layout.HorizontalAlignment = if labelled then E.HorizontalAlignment.Left else E.HorizontalAlignment.Center
			local well = UI.Button("Well")({
				name = function(use: Use)
					return semanticName(use)
				end,
				appearance = if labelled then nil else "utility",
				enabled = function(use: Use)
					return enabled(use)
				end,
				Size = function(use: Use)
					local height = math.max(CELL, (ctx.controlSize(spec.controlSize, "height", use)))
					return if labelled then D2.new(1, 0, 0, height) else D2.fromOffset(CELL, CELL)
				end,
				AutomaticSize = E.AutomaticSize.None,
				onActivate = function()
					requestPresented(true)
				end,
				row,
			})
			if labelled then
				chrome.paint("ColorPicker", well, spec)
			end
			if spec.hint ~= nil or spec.errorText ~= nil then
				root = chrome.wrap({
					control = "ColorPicker",
					spec = { hint = spec.hint, errorText = spec.errorText },
					plate = well,
					focus = function()
						requestPresented(true)
					end,
					enabled = enabled,
					native = rootProps,
				})
			else
				root = ctx.column({ well }, rootProps)
			end
			local anchorAvailable = surfaces.available(well)
			local anchorSeen = false
			Compose.watch(function(use: Use)
				if use(anchorAvailable) then
					anchorSeen = true
				elseif anchorSeen and presented() then
					close("anchorLost")
				end
			end)
			surfaces.attach(root, {
				surfaces.overlay(well, presented, function()
					local layer = well:FindFirstAncestorWhichIsA("LayerCollector")
					local extent = if layer then ctx.observe(layer, "AbsoluteSize") else Compose.cell(V2.zero)
					local origin = if layer then ctx.observe(layer, "AbsolutePosition") else Compose.cell(V2.zero)
					local at, bounds = ctx.observe(well, "AbsolutePosition"), ctx.observe(well, "AbsoluteSize")
					local tenFoot = false
					if gui then
						local ok, answer = pcall(function(): boolean
							return (gui :: GuiService):IsTenFootInterface()
						end)
						tenFoot = ok and answer == true
					end
					local function sheet(use: Use): boolean
						local offer = use(extent)
						return tenFoot or (touch(use) and offer.X > 0 and offer.X < 600)
					end
					local room = Compose.cell(math.huge)
					local view = panelView(true, sheet, room)
					local where = Compose.formula(function(use: Use): Placement
						return place(use, view, sheet, extent, origin, at, bounds, tenFoot)
					end)
					Compose.watch(function(use: Use)
						local spot = use(where)
						room:set(spot.h - view.chrome(use))
						placement:set(spot.edge)
					end)
					Compose.cleanup(function()
						placement:set("closed")
					end)
					runtime.decorate(view.panel, {
						Size = function(use: Use)
							local spot = use(where)
							return D2.fromOffset(spot.w, spot.h)
						end,
						Position = function(use: Use)
							local spot = use(where)
							return D2.fromOffset(spot.x, spot.y)
						end,
						Attributes = {
							placement = function(use: Use): string
								return use(where).edge
							end,
						} :: Shared.Attributes,
					})
					ctx.styled(view.panel, "panel")
					surfaces.skin(view.panel)
					return surfaces.modal(function()
						return view.panel
					end, function()
						close("cancel")
					end, {
						Name = "ColorPickerModal",
						backgroundTransparency = function(use: Use): number
							return if sheet(use) then 0.5 else 1
						end,
						onOutside = function()
							close("outside")
						end,
					})
				end),
			})
		end
		runtime.decorate(root, {
			Attributes = {
				value = function(use: Use): string
					local value = use(held)
					return if value == nil then "" else color.hex(value)
				end,
				text = function(use: Use): string
					return valueText(use)
				end,
				hue = function(use: Use): number
					return use(canon).h * 360
				end,
				saturation = function(use: Use): number
					return use(canon).s * 100
				end,
				brightness = function(use: Use): number
					return use(canon).v * 100
				end,
				mode = function(use: Use): string
					return use(modeCell)
				end,
				format = function(use: Use): string
					return use(formatCell)
				end,
				presented = function(use: Use): boolean
					return presented(use)
				end,
				placement = function(use: Use): string
					return use(placement)
				end,
				hexError = function(use: Use): string
					return use(hexError)
				end,
				columns = function(use: Use): number
					return use(columns)
				end,
				editing = function(use: Use): boolean
					return use(editing)
				end,
				diagnostics = function(use: Use): string
					return table.concat(use(diagnostics), "\n")
				end,
			} :: Shared.Attributes,
		})
		return ctx.styled(root, "color-picker")
	end

	local constructor = ctx.construct("ColorPicker", build)
	UI.ColorPicker = (constructor :: unknown) :: Shared.Constructor<Spec, Frame>
end
