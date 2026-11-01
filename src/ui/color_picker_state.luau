--!strict
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")
local Types = require("./color_picker_types")
local InputProps = require("./input_props")
local Kit = require("./color_picker_kit")

type Use = ComposeTypes.Use
type Value<T> = ComposeTypes.Value<T>
type Hsv = Kit.Hsv
type Item = Kit.Item
type Paint = Kit.Paint
type Spec = InputProps.ColorPickerProps
export type State = {
	spec: Spec,
	hasAlpha: boolean,
	style: string,
	draft: boolean,
	modes: { string },
	labelled: boolean,
	diagnostics: Value<{ string }>,
	held: Value<Color3?>,
	alphaHeld: Value<number>,
	canon: Value<Hsv>,
	enabled: (Use?) -> boolean,
	interactive: (Use?) -> boolean,
	mayEdit: () -> boolean,
	propose: (Hsv) -> boolean,
	proposeAlpha: (number) -> boolean,
	commit: () -> (),
	apply: () -> (),
	restore: () -> (),
	brickName: (Color3?) -> string?,
	valueText: (Use?) -> string,
	semanticName: (Use?) -> string,
	currentPaint: (Use) -> Paint,
	gui: GuiService?,
	selected: ComposeTypes.ReadOnlyValue<GuiObject?>,
	preferred: ComposeTypes.ReadOnlyValue<Enum.PreferredInput> | Value<unknown>,
	touch: (Use?) -> boolean,
	gamepad: (Use?) -> boolean,
	presented: (Use?) -> boolean,
	requestPresented: (boolean) -> (),
	close: (Types.DismissReason) -> (),
	modeCell: Value<string>,
	formatCell: Value<string>,
	hexError: Value<string>,
	placement: Value<string>,
	columns: Value<number>,
	cellSize: (Use?) -> number,
	editing: Value<boolean>,
	saving: boolean,
	removing: boolean,
	swatchList: ComposeTypes.Value<{ Item }>,
}

local isColor, unit, writable = Kit.isColor, Kit.unit, Kit.writable
local MODE_LABEL, MAX_COLUMNS = Kit.MODE_LABEL, Kit.MAX_COLUMNS

return function(ctx: Shared.Context, kit: Kit.Kit, spec: Spec): State
	local Compose, read, readSource = ctx.Compose, ctx.read, ctx.readSource
	local E = ctx.types.Enum
	local color, normalize = kit.color, kit.normalize
	local function refuse(message: string): never
		error(`Facet UI.ColorPicker: {message}`, 0)
	end
	local options = (spec :: unknown) :: { [string]: unknown }
	if spec.allowEmpty ~= nil and type(spec.allowEmpty) ~= "boolean" then
		refuse("`allowEmpty` is true or false.")
	end
	local allowEmpty = spec.allowEmpty == true
	local initial: Color3? = read<<Color3?>>(spec.value)
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
		local listed: unknown = spec.modes
			or if ctx.types.BrickColor
				then { "swatches", "spectrum", "sliders", "brick" }
				else { "swatches", "spectrum", "sliders" }
		if Compose.isValue(listed) or type(listed) ~= "table" or #(listed :: { unknown }) == 0 then
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
	kit.chrome.check("ColorPicker", spec)
	local labelled = spec.label ~= nil

	local diagnostics: Value<{ string }> = Compose.cell({})
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
	local held = Compose.cell(initial)
	Compose.watch(function(use: Use)
		local value: Color3? = read<<Color3?>>(spec.value, use)
		if legalColor(value) then
			held:set(value)
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

	local canon = Compose.cell(color.hsvOf(initial or kit.WHITE))
	local snapshot: { value: Color3?, alpha: number, canon: Hsv } =
		{ value = held:peek(), alpha = alphaHeld:peek(), canon = canon:peek() }
	local function takeSnapshot()
		snapshot = { value = held:peek(), alpha = alphaHeld:peek(), canon = canon:peek() }
	end
	local echo: Color3? = nil
	local alphaEcho: number? = nil
	Compose.watch(function(use: Use)
		local value = use(held)
		if echo ~= nil and value ~= nil and color.same(value, echo) then
			echo = nil
		else
			if value ~= nil and not color.same(value, color.toColor(canon:peek())) then
				canon:set(color.hsvOf(value, canon:peek()))
			end
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
			(spec.onChange :: (Color3?) -> ())(next)
		elseif writable(spec.value) then
			(spec.value :: ComposeTypes.Value<Color3?>):set(next)
		end
	end
	local function changeAlpha(next: number)
		if spec.onAlphaChange then
			spec.onAlphaChange(next)
		elseif writable(spec.alpha) then
			(spec.alpha :: ComposeTypes.Value<number>):set(next)
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
		local onCommit = spec.onCommit
		if disposed or draft or onCommit == nil then
			return
		end
		local value = held:peek()
		if value ~= nil then
			onCommit(value)
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
		local value = readSource(held, use)
		if value == nil then
			return spec.placeholder or ""
		end
		local a = readSource(alphaHeld, use)
		return color.hex(value, if hasAlpha and a < 1 then a else nil)
	end
	local function semanticName(use: Use?): string
		local words = brickName(readSource(held, use)) or valueText(use)
		local label = read(spec.label, use)
		return if type(label) == "string" and label ~= "" then `{label}, {words}` else words
	end
	local function currentPaint(use: Use): Paint
		return { color = use(held), alpha = use(alphaHeld) }
	end

	local gui = ctx.config.services.GuiService
	local input = ctx.config.services.UserInputService
	local selected = if gui then ctx.observe.SelectedObject(gui) else Compose.cell(nil :: GuiObject?)
	local preferred = if input then ctx.observe.PreferredInput(input) else Compose.cell(nil :: unknown)
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
		return readSource(ownOpen, use)
	end
	local function requestPresented(next: boolean)
		if next and (disposed or not interactive()) then
			return
		end
		if spec.onPresentedChange then
			spec.onPresentedChange(next)
		elseif spec.isPresented ~= nil then
			if writable(spec.isPresented) then
				(spec.isPresented :: ComposeTypes.Value<boolean>):set(next)
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
	local targetFloor = ctx.touchFloor()
	local editing = Compose.cell(false)
	local saving = spec.onSaveSwatch ~= nil
	local removing = spec.onRemoveSwatch ~= nil
	local swatchList = Compose.formula(function(use: Use): { Item }
		if spec.swatches == nil then
			return color.standard(use(columns))
		end
		return (normalize(read(spec.swatches, use))) or {}
	end)

	return {
		spec = spec,
		hasAlpha = hasAlpha,
		style = style,
		draft = draft,
		modes = modes,
		labelled = labelled,
		diagnostics = diagnostics,
		held = held,
		alphaHeld = alphaHeld,
		canon = canon,
		enabled = enabled,
		interactive = interactive,
		mayEdit = mayEdit,
		propose = propose,
		proposeAlpha = proposeAlpha,
		commit = commit,
		apply = apply,
		restore = restore,
		brickName = brickName,
		valueText = valueText,
		semanticName = semanticName,
		currentPaint = currentPaint,
		gui = gui,
		selected = selected,
		preferred = preferred,
		touch = touch,
		gamepad = gamepad,
		presented = presented,
		requestPresented = requestPresented,
		close = close,
		modeCell = modeCell,
		formatCell = formatCell,
		hexError = hexError,
		placement = placement,
		columns = columns,
		cellSize = function(use: Use?): number
			return math.max(Kit.CELL, targetFloor(use))
		end,
		editing = editing,
		saving = saving,
		removing = removing,
		swatchList = swatchList,
	}
end
