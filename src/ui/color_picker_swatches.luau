--!strict
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")
local Nav = require("./navigation_types")
local Kit = require("./color_picker_kit")
local PickerState = require("./color_picker_state")

type Use = ComposeTypes.Use
type Item = Kit.Item
type Paint = Kit.Paint
export type Swatches = { swatchesView: () -> Frame, brickView: () -> Frame }

local CELL, GAP, SPACE = Kit.CELL, Kit.GAP, Kit.SPACE
local SAVE_KEY = "\0save"

return function(
	ctx: Shared.Context,
	UI: Kit.Deps,
	surfaces: Nav.Surfaces,
	kit: Kit.Kit,
	state: PickerState.State
): Swatches
	local Compose, Host, read, readSource = ctx.Compose, ctx.Host, ctx.read, ctx.readSource
	local E, D, D2, V2 = ctx.types.Enum, ctx.types.UDim, ctx.types.UDim2, ctx.types.Vector2
	local color, swatch, WHITE = kit.color, kit.swatch, kit.WHITE
	local spec, saving, removing = state.spec, state.saving, state.removing
	local gui, selected, held, canon = state.gui, state.selected, state.held, state.canon
	local modeCell, columns, editing, swatchList = state.modeCell, state.columns, state.editing, state.swatchList
	local interactive, mayEdit, propose, commit, brickName =
		state.interactive, state.mayEdit, state.propose, state.commit, state.brickName

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

	local function gridView(name: string, items: (Use) -> { Item }, removable: boolean, mode: string): Frame
		local owned: { [Instance]: { item: ComposeTypes.Readable<Item>, index: ComposeTypes.Readable<number> } } = {}
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
				local value = readSource(held, use)
				if value == nil or readSource(editing, use) then
					return false
				end
				for _, entry in readSource(swatchList, use) do
					if color.same(entry.color, value) or entry.key == color.hex(value) then
						return false
					end
				end
				return true
			end
			return ctx.styled(
				UI.Button("Save")({
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
					ctx.styled(
						Host.Frame "Plus" {
							Size = D2.fromScale(1, 1),
							BackgroundTransparency = 1,
							ctx.corner() :: Shared.Child,
							Host.UIStroke({ Thickness = 1, ApplyStrokeMode = E.ApplyStrokeMode.Border }),
							ctx.icon("increment", {
								Name = "Mark",
								AnchorPoint = V2.new(0.5, 0.5),
								Position = D2.fromScale(0.5, 0.5),
							}),
						},
						"color-swatch"
					),
				}),
				"color-cell"
			)
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
				if use(modeCell) ~= mode then
					return false
				end
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
			ctx.styled(node, "color-cell")
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

	local function centred(column: Frame): Frame
		assert(column:FindFirstChildWhichIsA("UIListLayout")).HorizontalAlignment = E.HorizontalAlignment.Center
		return column
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
					label = function(use: Use): string
						return if use(editing) then "Done" else "Edit"
					end,
					appearance = "link",
					enabled = function(use: Use): boolean
						return interactive(use)
					end,
					onActivate = function()
						editing:set(not editing:peek())
					end,
				})
			)
		end
		table.insert(parts, gridView("Swatches", items, removing, "swatches"))
		return centred(
			ctx.column(parts, { Name = "Saved", Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y })
		)
	end

	local function brickView(): Frame
		local bricks = color.brick()
		return centred(ctx.column({
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
			end, false, "brick"),
		}, { Name = "Brick", Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y }))
	end

	return { swatchesView = swatchesView, brickView = brickView }
end
