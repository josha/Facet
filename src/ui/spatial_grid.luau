--!strict
local Types = require("./types")
local Controls = require("./control_types")
local Props = require("./spatial_grid_props")
local Spatial = require("./spatial_grid_types")
local Env = require("./environment_types")
local Drag = require("./drag_types")
local geometry = require("./spatial_grid_geometry")
local sessionOf = require("./drag_session")

return function(ctx: Types.Context, UI: Controls.Controls)
	local C, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local D2, V2, E = ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
	local service = sessionOf(ctx)
	UI.SpatialGrid = ctx.construct("SpatialGrid", function<V, K>(spec: Props.SpatialGridSpec<V, K>): Frame
		assert(
			geometry.integer(spec.columns) and geometry.integer(spec.rows),
			"SpatialGrid needs positive integer columns and rows"
		)
		assert(spec.drop == nil or spec.footprint ~= nil, "SpatialGrid.drop requires footprint(payload)")
		local nodes: { [K]: GuiObject } = {}
		local cells: { TextButton } = {}
		local positions: { Types.Readable<Vector2> } = {}
		local preview = C.cell(nil :: Spatial.Placement?)
		local accepted = C.cell(false)
		local size = C.formula(function(use: Types.Use): number
			local value = ctx.read(spec.cellSize or ctx.metric("targetSizes.minimum", use), use)
			assert(value > 0 and value < math.huge, "SpatialGrid.cellSize must be finite and positive")
			return math.max(ctx.metric("targetSizes.minimum", use), value)
		end)
		local gap = C.formula(function(use: Types.Use): number
			local value = ctx.read(spec.gap or ctx.metric("space.xs", use), use)
			assert(value >= 0 and value < math.huge, "SpatialGrid.gap must be finite and nonnegative")
			return value
		end)
		local items = C.formula(function(use: Types.Use): { V }
			local values = ctx.read(spec.from, use)
			local seen: { [K]: boolean } = {}
			local occupied: { Spatial.Placement } = {}
			for _, item in values do
				local key, at = spec.key(item), spec.placement(item)
				assert(not seen[key], "SpatialGrid requires unique keys")
				assert(geometry.inside(at, spec.columns, spec.rows), "SpatialGrid item is outside its cells")
				for _, other in occupied do
					assert(not geometry.overlaps(at, other), "SpatialGrid items overlap")
				end
				seen[key] = true
				table.insert(occupied, at)
			end
			return values
		end)
		local function dimensions(at: Spatial.Placement, use: Types.Use): UDim2
			local s, g = use(size), use(gap)
			return D2.fromOffset(at.width * (s + g) - g, at.height * (s + g) - g)
		end
		local grid = Host.Frame {
			Name = "Cells",
			BackgroundTransparency = 1,
			Size = D2.fromScale(1, 1),
			Host.UIGridLayout {
				CellSize = function(use: Types.Use): UDim2
					return D2.fromOffset(use(size), use(size))
				end,
				CellPadding = function(use: Types.Use): UDim2
					return D2.fromOffset(use(gap), use(gap))
				end,
				FillDirectionMaxCells = spec.columns,
				SortOrder = E.SortOrder.LayoutOrder,
			},
		}
		local unit: Types.Readable<number>
		local origin = ctx.observe.AbsolutePosition(grid)
		local function position(at: Spatial.Placement, use: Types.Use): UDim2
			local offset = (use(positions[(at.row - 1) * spec.columns + at.column]) - use(origin)) / use(unit)
			return D2.fromOffset(offset.X, offset.Y)
		end
		local function register(node: GuiObject, column: number?, row: number?)
			local drop = spec.drop
			if drop == nil then
				return
			end
			local target = (table.clone(drop) :: unknown) :: Drag.TargetSpec
			target.feedback = false
			if target.landing == nil then
				target.landing = function(info: Env.DropInfo): Env.ScrollRect
					local at = assert(info.placement)
					local cell = cells[(at.row - 1) * spec.columns + at.column]
					local s, g, scale = size:peek(), gap:peek(), unit:peek()
					return {
						x = cell.AbsolutePosition.X,
						y = cell.AbsolutePosition.Y,
						w = (at.width * (s + g) - g) * scale,
						h = (at.height * (s + g) - g) * scale,
					}
				end
			end
			target.propose = function(payload: unknown, info: Drag.Proposal)
				local footprint = assert(spec.footprint)(payload)
				if footprint == nil then
					info.invalid = "This item does not fit this container"
					return
				end
				local x, y = column or 1, row or 1
				if column == nil and info.mode == "armed" then
					for _, item in items:peek() do
						if nodes[spec.key(item)] == node then
							local at = spec.placement(item)
							x, y = at.column, at.row
						end
					end
				end
				local active = service.state:peek()
				if info.position and (info.mode == "pointer" or column == nil) then
					local offset = info.position - grid.AbsolutePosition
					if info.mode == "pointer" and active and info.operation == "move" then
						offset -= active.pickupAnchor * active.pickupSize
					end
					local pitch = (size:peek() + gap:peek()) * unit:peek()
					local rounding = if info.mode == "pointer" then 0.5 else 0
					x, y = math.floor(offset.X / pitch + rounding) + 1, math.floor(offset.Y / pitch + rounding) + 1
				end
				local at: Spatial.Placement = { column = x, row = y, width = footprint.X, height = footprint.Y }
				info.placement = at
				if not geometry.inside(at, spec.columns, spec.rows) then
					info.invalid = "Item is outside the container"
					return
				end
				for _, item in items:peek() do
					if
						not (info.operation == "move" and nodes[spec.key(item)] == info.source)
						and geometry.overlaps(at, spec.placement(item))
					then
						info.invalid = "These cells are occupied"
						return
					end
				end
			end
			target.accepts = function(payload: unknown, info: Drag.Proposal): (boolean, string?)
				if info.invalid then
					return false, info.invalid
				end
				if drop.accepts then
					return drop.accepts(payload, info)
				end
				return true, nil
			end
			target.onUpdate = function(payload: unknown, info: Env.DropInfo, valid: boolean, reason: string?)
				preview:set(info.placement)
				accepted:set(valid)
				if drop.onUpdate then
					drop.onUpdate(payload, info, valid, reason)
				end
			end
			target.onLeave = function(payload: unknown)
				preview:set(nil)
				if drop.onLeave then
					drop.onLeave(payload)
				end
			end
			UI.dropTarget(node, (target :: unknown) :: Env.DropTargetSpec)
		end
		for row = 1, spec.rows do
			for column = 1, spec.columns do
				local cell = UI.Button {
					Name = `Cell{column}_{row}`,
					label = "",
					LayoutOrder = (row - 1) * spec.columns + column,
					AutomaticSize = E.AutomaticSize.None,
					enabled = function(use: Types.Use): boolean
						return spec.drop ~= nil and use(service.state) ~= nil
					end,
				}
				cells[#cells + 1] = cell
				positions[#positions + 1] = ctx.observe.AbsolutePosition(cell)
				register(cell, column, row)
				runtime.mountFragment(function()
					return { cell }
				end, grid)
			end
		end
		local properties = ctx.props(
			spec,
			{ "from", "key", "placement", "columns", "rows", "cellSize", "gap", "render", "drag", "drop", "footprint" },
			{
				Name = "SpatialGrid",
				BackgroundTransparency = 1,
				Size = function(use: Types.Use): UDim2
					return dimensions({ column = 1, row = 1, width = spec.columns, height = spec.rows }, use)
				end,
			}
		)
		local root = Host.Frame(properties)
		unit = ctx.layoutUnit(root)
		register(root)
		local outline = Host.UIStroke {
			Thickness = function(use: Types.Use): number
				return ctx.metric("strokes.hairline", use)
			end,
		}
		C.watch(function(use: Types.Use)
			outline:RemoveTag("facet-drop-accepted")
			outline:RemoveTag("facet-drop-rejected")
			outline:AddTag(if use(accepted) then "facet-drop-accepted" else "facet-drop-rejected")
		end)
		runtime.mountFragment(function()
			return {
				grid,
				C.keyed({
					from = items,
					key = spec.key,
					render = function(current: Types.Readable<V>, _index: Types.Readable<number>, key: K): GuiObject
						local item = spec.render(current, key)
						nodes[key] = item
						C.cleanup(function()
							nodes[key] = nil
						end)
						runtime.decorate(item, {
							Position = function(use: Types.Use): UDim2
								return position(spec.placement(use(current)), use)
							end,
							Size = function(use: Types.Use): UDim2
								return dimensions(spec.placement(use(current)), use)
							end,
							AnchorPoint = V2.zero,
							AutomaticSize = E.AutomaticSize.None,
							Selectable = function(use: Types.Use): boolean
								return use(service.state) == nil
							end,
						})
						if spec.drag then
							local drag = table.clone(spec.drag(current, key))
							if drag.armOnTap == nil then
								drag.armOnTap = true
							end
							UI.draggable(item, drag)
						end
						register(item)
						return item
					end,
				}),
				Host.Frame {
					Name = "PlacementPreview",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					ZIndex = 10,
					Active = false,
					Selectable = false,
					Attributes = { FacetDragFeedback = true } :: Types.Attributes,
					Visible = function(use: Types.Use): boolean
						local at = use(preview)
						return use(service.state) ~= nil and at ~= nil and geometry.inside(at, spec.columns, spec.rows)
					end,
					Position = function(use: Types.Use): UDim2
						local at = use(preview)
						return if at and geometry.inside(at, spec.columns, spec.rows)
							then position(at, use)
							else D2.fromOffset(0, 0)
					end,
					Size = function(use: Types.Use): UDim2
						local at = use(preview)
						return if at and geometry.inside(at, spec.columns, spec.rows)
							then dimensions(at, use)
							else D2.fromOffset(0, 0)
					end,
					outline,
				},
			}
		end, root)
		local gui = ctx.config.guiService
		if gui then
			local carried: GuiObject? = nil
			C.watch(function(use: Types.Use)
				local active = use(service.state)
				local values = use(items)
				if active == nil then
					for index, cell in cells do
						if gui.SelectedObject ~= cell then
							continue
						end
						local at = {
							column = (index - 1) % spec.columns + 1,
							row = math.ceil(index / spec.columns),
							width = 1,
							height = 1,
						}
						local next = if carried and carried.Parent then carried else nil
						if next == nil then
							for _, item in values do
								if geometry.overlaps(at, spec.placement(item)) then
									next = nodes[spec.key(item)]
									break
								end
							end
						end
						gui.SelectedObject = next
						break
					end
					carried = nil
					return
				end
				carried = active.source
				if active.mode ~= "armed" then
					return
				end
				for _, item in values do
					if nodes[spec.key(item)] == active.source and gui.SelectedObject == active.source then
						local at = spec.placement(item)
						gui.SelectedObject = cells[(at.row - 1) * spec.columns + at.column]
					end
				end
			end)
		end
		return root
	end)
end
