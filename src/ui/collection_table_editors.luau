--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local CollectionTypes = require("./collection_types")
local InputTypes = require("./input_types")
local NavigationTypes = require("./navigation_types")
local activation = require("./activation")
local policy = require("./collection_policy")
type Controls = {
	CellEditor: Types.Constructor<CollectionTypes.CellEditorSpec, Frame>,
	TextInput: Types.Constructor<InputTypes.TextInputProps, TextBox | Frame>,
	NumberInput: Types.Constructor<InputTypes.NumberInputProps, TextBox | Frame>,
	Toggle: Types.Constructor<InputTypes.ToggleProps, TextButton>,
	Picker: NavigationTypes.PickerConstructor,
}
local EDITORS = { text = true, number = true, toggle = true, menu = true }
local SETTINGS = { "options", "min", "max", "step", "draft", "validate", "editLabel", "editable" }

return function(ctx: Types.Context, UI: Controls)
	local Compose, read = ctx.Compose, ctx.read
	local D, D2, V2, E = ctx.types.UDim, ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
	local editors = {}
	local function build(spec: CollectionTypes.CellEditorSpec): Frame
		assert(EDITORS[spec.editor], "Facet CellEditor: editor must be text, number, toggle or menu")
		assert(type(spec.onChange) == "function", "Facet CellEditor needs onChange")
		assert(spec.editor ~= "menu" or spec.options ~= nil, "Facet CellEditor: menu needs options")
		assert(
			spec.draft == nil or spec.editor == "text" or spec.editor == "number",
			"Facet CellEditor: only text and number accept a draft"
		)
		assert(
			spec.editing == nil or spec.editor == "text" or spec.editor == "number",
			"Facet CellEditor: only text and number accept editing"
		)
		local draft: ComposeTypes.Cell<CollectionTypes.CellDraft?> = spec.draft
			or Compose.cell(nil :: CollectionTypes.CellDraft?)
		local errorText = Compose.cell("")
		local editing: ComposeTypes.Cell<boolean> = spec.editing or Compose.cell(false)
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
		local display: TextLabel? = nil
		local fieldHeight: ComposeTypes.Readable<UDim2>? = nil
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
				appearance = "utility",
				controlSize = "compact",
				value = input,
				Attributes = { AccessibleLabel = spec.label or spec.editLabel or "Edit value" },
				readOnly = function(use: ComposeTypes.Use): boolean
					return not enabled(use)
				end,
				Selectable = enabled,
				Interactable = enabled,
				errorText = errorText,
				Visible = editing,
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
					editing:set(false)
				end,
				FocusLost = function()
					if errorText:peek() == "" and read(spec.busy) ~= true then
						editing:set(false)
					end
				end,
				Focused = function()
					editing:set(true)
				end,
			}
			local inputKind = ctx.effectiveInput()
			fieldHeight = Compose.formula(function(use: ComposeTypes.Use)
				return D2.new(
					1,
					0,
					0,
					math.max(
						ctx.controlSize("compact", "height", use),
						ctx.controlSize("compact", "iconSize", use),
						if inputKind(use) == "KeyboardAndMouse"
							then 0
							else math.max(44, ctx.metric("targetSizes.minimum", use))
					)
				)
			end)
			do
				local hit: TextButton
				local function rowHit(): GuiObject?
					local parent: Instance? = hit.Parent
					while parent and not parent:IsA("LayerCollector") do
						local row = parent:FindFirstChild("RowHit")
						if row then
							return row :: GuiObject
						end
						parent = parent.Parent
					end
					return nil
				end
				local function activate(input: InputObject?, clicks: number?)
					if activation.consumed(input) then
						return
					end
					local row = rowHit()
					local service = ctx.config.userInputService
					local modified = false
					if service then
						for _, code in
							{
								E.KeyCode.LeftControl,
								E.KeyCode.RightControl,
								E.KeyCode.LeftMeta,
								E.KeyCode.RightMeta,
								E.KeyCode.LeftShift,
								E.KeyCode.RightShift,
							}
						do
							modified = modified or service:IsKeyDown(code)
						end
					end
					if
						not modified
						and enabled()
						and (row == nil or (input and input.UserInputType == E.UserInputType.MouseButton1))
						and (row == nil or (clicks or 0) == 0)
						and (row == nil or row.Interactable)
						and (
							row == nil
							or row:GetAttribute("FacetSelectionRequired") == false
							or row:GetAttribute("FacetOnlySelected") == true
						)
					then
						editing:set(true)
					elseif row then
						activation.trigger(row, input, clicks)
					end
					activation.consume(input)
				end
				hit = ctx.Host.TextButton({
					Name = "EditLabel",
					Attributes = { AccessibleLabel = spec.label or spec.editLabel or "Edit value" } :: Types.Attributes,
					Text = "",
					Size = D2.fromScale(1, 1),
					BackgroundTransparency = 1,
					AutoButtonColor = false,
					Selectable = false,
					Activated = function(input: InputObject?, clicks: number?)
						activate(input, math.max(0, (clicks or 1) - 1))
					end,
				})
				ctx.runtime.connect(hit, "AncestryChanged", function()
					hit.Selectable = rowHit() == nil
				end)
				Compose.cleanup(activation.provide(hit, function(input, clicks)
					activate(input :: InputObject?, clicks :: number?)
				end))
				display = ctx.styled(
					ctx.text({
						Name = "Value",
						Text = function(use: ComposeTypes.Use): string
							return text(value(use))
						end,
						Visible = function(use: ComposeTypes.Use): boolean
							return not use(editing)
						end,
						Size = function(use: ComposeTypes.Use)
							return D2.new(1, 0, 0, use(assert(fieldHeight)).Y.Offset)
						end,
						AutomaticSize = E.AutomaticSize.None,
						BackgroundTransparency = 1,
						TextWrapped = false,
						TextTruncate = E.TextTruncate.AtEnd,
						TextYAlignment = E.TextYAlignment.Center,
						ctx.Host.UIPadding {
							PaddingLeft = D.new(0, 10),
							PaddingRight = D.new(0, 10),
						} :: ComposeTypes.Child,
						hit,
					}),
					"Text"
				) :: TextLabel
				local initialized = Compose.cell(false)
				Compose.watch(function(use: ComposeTypes.Use)
					if use(editing) then
						initialized:set(true)
					end
				end)
				child = ctx.Host.Frame {
					Name = "EditorHost",
					BackgroundTransparency = 1,
					Size = D2.new(1, 0, 0, 0),
					AutomaticSize = E.AutomaticSize.Y,
					Visible = editing,
					Compose.show(initialized, function()
						local editor: GuiObject
						if spec.editor == "number" then
							local numberProps = (props :: unknown) :: InputTypes.NumberInputProps
							numberProps.numericValue = numeric
							numberProps.min, numberProps.max, numberProps.step = spec.min, spec.max, spec.step
							editor = UI.NumberInput(numberProps)
						else
							editor = UI.TextInput((props :: unknown) :: InputTypes.TextInputProps)
						end
						local field = (
							if editor:IsA("TextBox") then editor else editor:FindFirstChildWhichIsA("TextBox", true)
						) :: TextBox
						local function focus()
							if
								editing:peek()
								and enabled()
								and field:FindFirstAncestorWhichIsA("LayerCollector")
								and not field:IsFocused()
							then
								local gui = ctx.config.guiService
								if gui then
									gui.SelectedObject = field
								end
								field:CaptureFocus()
							end
						end
						local function requestFocus()
							if task and task.defer then
								task.defer(focus)
							else
								focus()
							end
						end
						local wasEditing = false
						Compose.watch(function(use: ComposeTypes.Use)
							local active = use(editing)
							if read(spec.enabled, use) == false and active then
								active = false
								editing:set(false)
							end
							if active then
								requestFocus()
							elseif field:IsFocused() then
								field:ReleaseFocus()
							end
							local gui = ctx.config.guiService
							if wasEditing and not active and gui then
								local selected = gui.SelectedObject
								if selected and (selected == field or selected:IsDescendantOf(editor)) then
									gui.SelectedObject = rowHit() or hit
								end
							end
							wasEditing = active
						end)
						ctx.runtime.connect(field, "AncestryChanged", requestFocus)
						return editor
					end),
				}
			end
		end
		local defaults: Types.FrameProps = {
			Size = D2.new(1, 0, 0, 0),
			AutomaticSize = E.AutomaticSize.Y,
			BackgroundTransparency = 1,
			child :: ComposeTypes.Child,
			display :: ComposeTypes.Child,
			if fieldHeight
				then ctx.Host.UISizeConstraint {
					Name = "FieldSize",
					MinSize = function(use: ComposeTypes.Use)
						return V2.new(0, use(assert(fieldHeight)).Y.Offset)
					end,
				}
				else nil,
		}
		local root = ctx.Host.Frame(ctx.props(spec, {
			"editor",
			"value",
			"onChange",
			"draft",
			"editing",
			"editLabel",
			"validate",
			"label",
			"enabled",
			"busy",
			"options",
			"min",
			"max",
			"step",
		}, defaults))
		if spec.editor == "text" or spec.editor == "number" then
			Compose.cleanup(activation.provideEdit(root, {
				label = spec.editLabel or "Edit value",
				enabled = enabled,
				onActivate = function()
					if enabled() then
						editing:set(true)
					end
				end,
			}))
		end
		return root
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
				editLabel = column.editLabel or function(use: ComposeTypes.Use): string
					return "Edit " .. read(column.label or column.id, use)
				end,
				value = function(use: ComposeTypes.Use): unknown
					return raw(use(current))
				end,
				onChange = function(nextValue: unknown)
					onCellChange(key, column.id, nextValue)
				end,
				draft = if column.draft then column.draft(key) else nil,
				validate = column.validate,
				enabled = function(use: ComposeTypes.Use): boolean
					return enabled(use) and policy.allows(column.editable, use(current))
				end,
				options = column.options,
				min = column.min,
				max = column.max,
				step = column.step,
			}
		end
	end
	return editors
end
