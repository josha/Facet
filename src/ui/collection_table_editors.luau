--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local CollectionTypes = require("./collection_types")
local InputTypes = require("./input_types")
local NavigationTypes = require("./navigation_types")
type Controls = {
	CellEditor: Types.Constructor<CollectionTypes.CellEditorSpec, Frame>,
	TextInput: Types.Constructor<InputTypes.TextInputProps, TextBox | Frame>,
	NumberInput: Types.Constructor<InputTypes.NumberInputProps, TextBox | Frame>,
	Toggle: Types.Constructor<InputTypes.ToggleProps, TextButton>,
	Picker: NavigationTypes.PickerConstructor,
}
local EDITORS = { text = true, number = true, toggle = true, menu = true }
local SETTINGS = { "options", "min", "max", "step", "draft", "validate" }

return function(ctx: Types.Context, UI: Controls)
	local Compose, read = ctx.Compose, ctx.read
	local D2, E = ctx.types.UDim2, ctx.types.Enum
	local editors = {}
	local function build(spec: CollectionTypes.CellEditorSpec): Frame
		assert(EDITORS[spec.editor], "Facet CellEditor: editor must be text, number, toggle or menu")
		assert(type(spec.onChange) == "function", "Facet CellEditor needs onChange")
		assert(spec.editor ~= "menu" or spec.options ~= nil, "Facet CellEditor: menu needs options")
		assert(
			spec.draft == nil or spec.editor == "text" or spec.editor == "number",
			"Facet CellEditor: only text and number accept a draft"
		)
		local draft: ComposeTypes.Cell<CollectionTypes.CellDraft?> = spec.draft
			or Compose.cell(nil :: CollectionTypes.CellDraft?)
		local errorText = Compose.cell("")
		local alive = true
		Compose.cleanup(function()
			alive = false
		end)
		local function enabled(use: ComposeTypes.Use?): boolean
			return read(spec.enabled, use) ~= false and read(spec.busy, use) ~= true
		end
		local function value(use: ComposeTypes.Use?): unknown
			return read(spec.value, use)
		end
		local function text(current: unknown): string
			return if current == nil then "" else tostring(current)
		end
		local function parsed(current: CollectionTypes.CellDraft): unknown
			return if spec.editor == "number" then tonumber(current.text) else current.text
		end
		local function propose(nextValue: unknown)
			if not alive or not enabled() then
				return
			end
			local failure = if spec.validate then spec.validate(nextValue) else nil
			if failure then
				errorText:set(failure)
				local current = draft:peek()
				if current then
					local nextDraft = table.clone(current)
					nextDraft.error = failure
					draft:set(nextDraft)
				end
				return
			end
			errorText:set("")
			if nextValue ~= value() then
				spec.onChange(nextValue)
			end
			if value() == nextValue then
				draft:set(nil)
			elseif read(spec.busy) ~= true then
				errorText:set("Change not accepted. Try again or cancel.")
				local current = draft:peek()
				if current then
					local nextDraft = table.clone(current)
					nextDraft.error = errorText:peek()
					draft:set(nextDraft)
				end
			end
		end
		local child: GuiObject
		if spec.editor == "toggle" then
			child = UI.Toggle(({
				Name = "Editor",
				presentation = "checkbox",
				appearance = "plain",
				label = "",
				name = spec.label,
				value = function(use: ComposeTypes.Use): boolean
					return value(use) == true
				end,
				onChange = propose,
				enabled = enabled,
			} :: unknown) :: InputTypes.ToggleProps)
		elseif spec.editor == "menu" then
			local selected = Compose.cell(value())
			Compose.watch(function(use: ComposeTypes.Use)
				selected:set(value(use))
			end)
			child = UI.Picker(({
				Name = "Editor",
				style = "menu",
				appearance = "utility",
				options = spec.options,
				selected = selected,
				enabled = enabled,
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
				onChanging = function(nextValue: unknown): boolean
					propose(nextValue)
					return false
				end,
			} :: unknown) :: NavigationTypes.PickerSpec<unknown>)
		else
			local input = Compose.cell("")
			local numeric = Compose.cell(tonumber(value()) or 0)
			Compose.watch(function(use: ComposeTypes.Use)
				local confirmed, current = value(use), use(draft)
				if current and parsed(current) == confirmed then
					draft:set(nil)
					current = nil
				end
				input:set(if current then current.text else text(confirmed))
				numeric:set(tonumber(confirmed) or 0)
				errorText:set(
					if current
						then current.error or (if current.original ~= confirmed
							then "Value changed elsewhere. Cancel to use the latest value."
							else "")
						else ""
				)
			end)
			local props = {
				Name = "Editor",
				value = input,
				label = spec.label,
				enabled = enabled,
				errorText = errorText,
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
				onChange = function(nextText: string)
					if not alive then
						return
					end
					input:set(nextText)
					local current = draft:peek()
					draft:set({ text = nextText, original = if current then current.original else value() })
				end,
				onCommit = propose,
				onCancel = function()
					draft:set(nil)
					errorText:set("")
				end,
			}
			if spec.editor == "number" then
				local numberProps = (props :: unknown) :: InputTypes.NumberInputProps
				numberProps.numericValue = numeric
				numberProps.min, numberProps.max, numberProps.step = spec.min, spec.max, spec.step
				child = UI.NumberInput(numberProps)
			else
				child = UI.TextInput((props :: unknown) :: InputTypes.TextInputProps)
			end
		end
		local defaults: Types.FrameProps = {
			Size = D2.new(1, 0, 0, 0),
			AutomaticSize = E.AutomaticSize.Y,
			BackgroundTransparency = 1,
			child :: ComposeTypes.Child,
		}
		return ctx.Host.Frame(ctx.props(spec, {
			"editor",
			"value",
			"onChange",
			"draft",
			"validate",
			"label",
			"enabled",
			"busy",
			"options",
			"min",
			"max",
			"step",
		}, defaults))
	end
	UI.CellEditor = ctx.construct("CellEditor", build)

	function editors.check<V, K>(columns: { CollectionTypes.TableColumn<V, K> }, onCellChange: unknown)
		for _, column in columns do
			assert(
				column.align == nil or column.align == "start" or column.align == "center" or column.align == "end",
				"Facet Table: align must be start, center or end"
			)
			local editor = column.editor
			if editor == nil then
				for _, setting in SETTINGS do
					assert(
						((column :: unknown) :: { [string]: unknown })[setting] == nil,
						`Facet UI.Table: column '{column.id}' sets {setting} without an editor`
					)
				end
				continue
			end
			assert(
				EDITORS[editor] and column.render == nil,
				`Facet UI.Table: column '{column.id}' editor must be text, number, toggle or menu, without render`
			)
			assert(
				editor ~= "menu" or type(column.options) == "table",
				`Facet UI.Table: menu column '{column.id}' needs options`
			)
			assert(type(onCellChange) == "function", "Facet UI.Table: an editor column needs onCellChange")
		end
	end

	function editors.render<V, K>(
		column: CollectionTypes.TableColumn<V, K>,
		raw: (V) -> unknown,
		onCellChange: (key: K, column: string, value: unknown) -> (),
		enabled: (ComposeTypes.Use) -> boolean
	): CollectionTypes.RowRender<V, K>
		return function(current: ComposeTypes.Readable<V>, _placement, key: K): GuiObject
			return UI.CellEditor {
				Name = "CellEditor",
				editor = assert(column.editor),
				label = column.label or column.id,
				value = function(use: ComposeTypes.Use): unknown
					return raw(use(current))
				end,
				onChange = function(nextValue: unknown)
					onCellChange(key, column.id, nextValue)
				end,
				draft = if column.draft then column.draft(key) else nil,
				validate = column.validate,
				enabled = enabled,
				options = column.options,
				min = column.min,
				max = column.max,
				step = column.step,
			}
		end
	end
	return editors
end
