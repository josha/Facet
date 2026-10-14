--!strict
local inputKit = require("./input_kit")
local InputTypes = require("./input_types")
local Shared = require("./types")
local ControlTypes = require("./control_types")
local InputProps = require("./input_props")
local ComposeTypes = require("../vendor/compose/core")

return function(ctx: Shared.Context, UI: ControlTypes.Controls, kit: inputKit.Kit): ()
	local Compose, read = ctx.Compose, ctx.read
	local D2, V2, E = ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
	local enabled, writable, attributes = kit.enabled, kit.writable, kit.attributes
	UI.Chip = ctx.construct("Chip", function(spec: InputTypes.ChipImplementationProps): TextButton | Frame
		assert(
			spec.selected == nil or writable(spec.selected) or type(spec.onToggle) == "function",
			"Facet.Chip: read-only selected requires onToggle"
		)
		assert(spec.selected ~= nil or spec.onRemove, "Facet.Chip: selected or onRemove is required")
		assert(spec.editing == nil or spec.onRemove ~= nil, "Facet UI.Chip: editing requires onRemove")
		if spec.selected ~= nil and spec.onRemove ~= nil and spec.editing == nil then
			error("Facet UI.Chip: a selectable chip with onRemove requires editing, the caller's edit-mode cell", 0)
		end
		local removable = spec.onRemove ~= nil
		local function editing(use: ComposeTypes.Use?): boolean
			if not removable then
				return false
			end
			return spec.selected == nil or read(spec.editing, use) == true
		end
		local p = (table.clone(spec) :: unknown) :: InputProps.ButtonProps & {
			onToggle: ((boolean) -> ())?,
			onRemove: (() -> ())?,
			editing: Shared.Value<boolean>?,
			removeLabel: Shared.Value<string>?,
			removeFocusFallback: Shared.Value<GuiObject?>?,
			leading: Instance?,
			trailing: Instance?,
		}
		p.onToggle, p.onRemove, p.editing, p.removeLabel, p.removeFocusFallback, p.leading, p.trailing =
			nil, nil, nil, nil, nil, nil, nil
		p.ref = nil
		local node: TextButton
		local pendingFocus: GuiObject?
		local gui = ctx.config.services.GuiService
		local function candidate(): GuiObject?
			if node.Parent then
				local siblings = node.Parent:GetChildren()
				local ordinal: { [Instance]: number } = {}
				for index, sibling in siblings do
					ordinal[sibling] = index
				end
				table.sort(siblings, function(a: Instance, b: Instance): boolean
					local first = if a:IsA("GuiObject") then a.LayoutOrder else 0
					local second = if b:IsA("GuiObject") then b.LayoutOrder else 0
					return if first == second then ordinal[a] < ordinal[b] else first < second
				end)
				local index = table.find(siblings, node)
				local function target(at: number): GuiObject?
					local sibling = siblings[at]
					if
						sibling
						and sibling:IsA("GuiObject")
						and sibling:GetAttribute("editing") ~= nil
						and sibling.Selectable
						and ctx.available(sibling)
					then
						return sibling
					end
					return nil
				end
				if index then
					for at = index + 1, #siblings do
						local found = target(at)
						if found then
							return found
						end
					end
					for at = index - 1, 1, -1 do
						local found = target(at)
						if found then
							return found
						end
					end
				end
			end
			return read(spec.removeFocusFallback)
		end
		local function restore()
			if
				gui
				and pendingFocus
				and pendingFocus.Parent
				and (gui.SelectedObject == node or gui.SelectedObject == nil)
			then
				gui.SelectedObject = pendingFocus
			end
			pendingFocus = nil
		end
		local function remove()
			if not enabled(spec) or not ctx.available(node) then
				return
			end
			if gui and gui.SelectedObject == node then
				pendingFocus = candidate()
			end
			assert(spec.onRemove)()
			if node.Parent == nil then
				restore()
			end
		end
		p.onActivate = function()
			if editing() then
				remove()
			elseif spec.selected then
				local value = not read(spec.selected)
				if spec.onToggle then
					spec.onToggle(value)
				else
					(spec.selected :: ComposeTypes.Cell<boolean>):set(value)
				end
			end
		end
		p.Selectable = function(use: ComposeTypes.Use)
			return (spec.selected ~= nil or removable) and enabled(spec, use)
		end
		if p.haptic == nil and spec.selected ~= nil then
			p.haptic = true
		end
		if spec.leading or spec.trailing or removable then
			p.Text = ""
			local contents: { ComposeTypes.Child } = {}
			if spec.leading then
				table.insert(contents, spec.leading)
			end
			table.insert(contents, ctx.text({ Name = "Title", Text = spec.label or "" }))
			if spec.trailing then
				table.insert(contents, spec.trailing)
			end
			if removable then
				table.insert(
					contents,
					ctx.text({
						Name = "Remove",
						Text = "×",
						Visible = function(use: ComposeTypes.Use)
							return editing(use)
						end,
					})
				)
			end
			local row = ctx.row(contents, {
				Name = "Content",
				AnchorPoint = V2.new(0, 0.5),
				Position = D2.fromScale(0, 0.5),
			})
			assert(row:FindFirstChildWhichIsA("UIListLayout")).VerticalAlignment = E.VerticalAlignment.Center
			table.insert(p, row)
		end
		if p.haptic == nil and spec.selected ~= nil then
			p.haptic = true
		end
		node = ctx.styled(UI.Button(p), "chip")
		node:AddTag("facet-selection-mark")
		if removable then
			attributes(
				node,
				{
					AccessibleLabel = function(use: ComposeTypes.Use): string
						if not editing(use) then
							return read(spec.label, use) or ""
						end
						local named = read(spec.removeLabel, use)
						return named or `Remove {read(spec.label, use) or ""}`
					end,
					editing = function(use: ComposeTypes.Use)
						return editing(use)
					end,
				} :: Shared.Attributes
			)
			local holding = false
			local function removalHeld(): boolean
				local input = ctx.config.services.UserInputService
				local probe = (input :: unknown) :: {
					IsKeyDown: ((UserInputService, Enum.KeyCode) -> boolean)?,
					GetConnectedGamepads: ((UserInputService) -> { Enum.UserInputType })?,
					IsGamepadButtonDown: ((UserInputService, Enum.UserInputType, Enum.KeyCode) -> boolean)?,
				}?
				if input == nil or probe == nil or probe.IsKeyDown == nil then
					return false
				end
				if input:IsKeyDown(E.KeyCode.Delete) or input:IsKeyDown(E.KeyCode.Backspace) then
					return true
				end
				if probe.GetConnectedGamepads == nil or probe.IsGamepadButtonDown == nil then
					return false
				end
				for _, pad in input:GetConnectedGamepads() do
					if input:IsGamepadButtonDown(pad, E.KeyCode.ButtonX) then
						return true
					end
				end
				return false
			end
			local focused: ComposeTypes.Readable<GuiObject?> = if gui
				then ctx.observe.SelectedObject(gui)
				else Compose.cell(nil :: GuiObject?)
			local wasFocused = false
			Compose.watch(function(use: ComposeTypes.Use)
				local now = use(focused) == (node :: Instance)
				if now and not wasFocused then
					holding = removalHeld()
				end
				wasFocused = now
			end)
			ctx.action(
				node,
				"RemoveChip",
				{ E.KeyCode.Delete, E.KeyCode.Backspace, E.KeyCode.ButtonX },
				function(use: ComposeTypes.Use)
					return use(focused) == (node :: Instance) and editing(use) and enabled(spec, use)
				end,
				function()
					if holding then
						return
					end
					remove()
				end,
				{
					priority = 100,
					onReleased = function()
						holding = false
					end,
				}
			)
		end
		Compose.cleanup(restore)
		return node
	end)
end
