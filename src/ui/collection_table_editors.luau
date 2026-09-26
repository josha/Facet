--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local CollectionTypes = require("./collection_types")
local InputTypes = require("./input_types")
local NavigationTypes = require("./navigation_types")
type Controls = {
	TextInput: Types.Constructor<InputTypes.TextInputProps, TextBox | Frame>,
	NumberInput: Types.Constructor<InputTypes.NumberInputProps, TextBox | Frame>,
	Toggle: Types.Constructor<InputTypes.ToggleProps, TextButton>,
	Picker: NavigationTypes.PickerConstructor,
}

local EDITORS = { text = true, number = true, toggle = true, menu = true }
local SETTINGS = { "options", "min", "max", "step" }

return function(ctx: Types.Context, UI: Controls)
	local Compose, read = ctx.Compose, ctx.read
	local D2 = ctx.types.UDim2
	local editors = {}

	function editors.check<V, K>(columns: { CollectionTypes.TableColumn<V, K> }, onCellChange: unknown)
		for _, column in columns do
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
			local function value(use: ComposeTypes.Use?): unknown
				return raw(if use then use(current) else current:peek())
			end
			local function propose(nextValue: unknown)
				if nextValue ~= value() then
					onCellChange(key, column.id, nextValue)
				end
			end
			local name = read(column.label) or column.id
			local editor = column.editor
			if editor == "toggle" then
				return UI.Toggle(({
					Name = "Editor",
					presentation = "checkbox",
					appearance = "plain",
					label = "",
					name = name,
					value = function(use: ComposeTypes.Use): boolean
						return value(use) == true
					end,
					onChange = propose,
					enabled = enabled,
				} :: unknown) :: InputTypes.ToggleProps)
			end
			if editor == "menu" then
				local selected = Compose.cell(value())
				Compose.watch(function(use: ComposeTypes.Use)
					selected:set(value(use))
				end)
				return UI.Picker(({
					Name = "Editor",
					style = "menu",
					appearance = "utility",
					options = column.options,
					selected = selected,
					enabled = enabled,
					onChanging = function(nextValue: unknown): boolean
						propose(nextValue)
						return false
					end,
					Size = D2.fromScale(1, 1),
				} :: unknown) :: NavigationTypes.PickerSpec<unknown>)
			end
			local function text(use: ComposeTypes.Use?): string
				local current = value(use)
				return if current == nil then "" else tostring(current)
			end
			local draft = Compose.cell(text())
			Compose.watch(function(use: ComposeTypes.Use)
				draft:set(text(use))
			end)
			if editor == "number" then
				local numeric = Compose.cell(tonumber(value()) or 0)
				Compose.watch(function(use: ComposeTypes.Use)
					numeric:set(tonumber(value(use)) or 0)
				end)
				return UI.NumberInput({
					Name = "Editor",
					value = draft,
					numericValue = numeric,
					enabled = enabled,
					min = column.min,
					max = column.max,
					step = column.step,
					onCommit = function(nextValue: number)
						propose(nextValue)
						numeric:set(tonumber(value()) or 0)
						draft:set(text())
					end,
					Size = D2.fromScale(1, 1),
				} :: InputTypes.NumberInputProps)
			end
			return UI.TextInput({
				Name = "Editor",
				value = draft,
				enabled = enabled,
				onCommit = function(nextValue: string)
					propose(nextValue)
					draft:set(text())
				end,
				Size = D2.fromScale(1, 1),
			} :: InputTypes.TextInputProps)
		end
	end

	return editors
end
