--!strict
local Catalog = require("./catalog_types")
type Controls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type Placement = typeof(require("@repo/tools/typecheck/aliases").SpatialPlacement)
type DropInfo = typeof(require("@repo/tools/typecheck/aliases").DropInfo)
type DraggableSpec = typeof(require("@repo/tools/typecheck/aliases").DraggableSpec)
type DropTargetSpec = typeof(require("@repo/tools/typecheck/aliases").DropTargetSpec)
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T
type Item = { id: string, label: string, container: string, at: Placement }

local page: Catalog.PageDefinition = {
	family = "collections",
	cellHeight = 460,
	cellWidth = 600,
	fills = true,
	matrix = false,
	base = function()
		return {}
	end,
	purpose = "Place items that occupy several cells, or move them between containers.",
	alternatives = "Use VirtualGrid for an ordered list of equal-sized items.",
	snippet = "UI.SpatialGrid { from = items, key = key, placement = placement, columns = 5, rows = 4, render = render, drag = drag, drop = drop, footprint = footprint }",
	demonstrates = {
		"from",
		"key",
		"placement",
		"columns",
		"rows",
		"cellSize",
		"gap",
		"render",
		"drag",
		"drop",
		"footprint",
	},
	axes = {},
	states = {},
	make = function(UI: Controls, _: never, c: Catalog.Context): Instance
		local initial: { Item } = {
			{
				id = "Pack",
				label = "Pack",
				container = "Inventory",
				at = { column = 1, row = 1, width = 2, height = 2 },
			},
			{
				id = "Tool",
				label = "Tool",
				container = "Inventory",
				at = { column = 4, row = 1, width = 1, height = 3 },
			},
			{
				id = "Medkit",
				label = "Medkit",
				container = "Loot",
				at = { column = 1, row = 1, width = 2, height = 1 },
			},
		}
		local model = c.cell("inventory", initial)
		local notice = c.cell(
			"status",
			"Drag an item, or select it and press A / Return. On touch, tap an item and then a cell. B / Esc cancels."
		)
		local function find(payload: unknown): Item?
			for _, item in model:peek() do
				if item.id == payload then
					return item
				end
			end
			return nil
		end
		local function container(name: string): GuiObject
			return UI.VStack(name .. "Column") {
				gap = 8,
				width = "hug",
				height = "hug",
				UI.Text { text = name, textRole = "heading" } :: unknown,
				UI.SpatialGrid(name) {
					columns = 5,
					rows = 4,
					cellSize = 48,
					gap = 4,
					from = function(use: Use): { Item }
						local rows: { Item } = {}
						for _, item in use(model) do
							if item.container == name then
								table.insert(rows, item)
							end
						end
						return rows
					end,
					key = function(item: Item): string
						return item.id
					end,
					placement = function(item: Item): Placement
						return item.at
					end,
					footprint = function(payload: unknown): Vector2?
						local item = find(payload)
						return if item then c.types.Vector2.new(item.at.width, item.at.height) else nil
					end,
					drag = function(current: Readable<Item>): DraggableSpec
						return {
							payload = current:peek().id,
							valid = function(): boolean
								return find(current:peek().id) ~= nil
							end,
						}
					end,
					drop = {
						label = name,
						travel = false,
						onReject = function(_payload: unknown, reason: string?)
							notice:set(reason or "Cannot place here")
						end,
						onDrop = function(payload: unknown, info: DropInfo): boolean
							local item, at = find(payload), info.placement
							if item == nil or at == nil then
								return false
							end
							local next = table.clone(model:peek())
							for index, value in next do
								if value.id == item.id then
									local moved = table.clone(value)
									moved.container, moved.at = name, at
									next[index] = moved
								end
							end
							model:set(next)
							notice:set(`{item.label} placed in {name}, column {at.column}, row {at.row}.`)
							return true
						end,
					} :: DropTargetSpec,
					render = function(current: Readable<Item>): GuiObject
						return UI.Button {
							Name = current:peek().id,
							label = current:peek().label,
							appearance = "emphasis",
						}
					end,
				} :: unknown,
			}
		end
		return UI.ScrollView "InventoryScroll" {
			width = "fill",
			height = "fill",
			UI.VStack "InventoryDemo" {
				width = "fill",
				height = "hug",
				gap = 12,
				UI.Text {
					text = notice,
					Size = c.types.UDim2.fromScale(1, 0),
					AutomaticSize = c.types.Enum.AutomaticSize.Y,
					wrap = true,
				} :: unknown,
				UI.AdaptiveStack "Containers" {
					width = "fill",
					height = "hug",
					gap = 16,
					container("Inventory") :: unknown,
					container("Loot") :: unknown,
				} :: unknown,
				UI.Button {
					label = "Reset inventory",
					onActivate = function()
						model:set(initial)
						notice:set("Inventory reset.")
					end,
				} :: unknown,
			} :: unknown,
		}
	end,
}
return page
