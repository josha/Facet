--!strict
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")
local Nav = require("./navigation_types")
local InputProps = require("./input_props")
local NavigationProps = require("./navigation_props")
local Kit = require("./color_picker_kit")
local PickerState = require("./color_picker_state")
local createSliders = require("./color_picker_sliders")
local createSpectrum = require("./color_picker_spectrum")
local createSwatches = require("./color_picker_swatches")
local createReadout = require("./color_picker_readout")

type Use = ComposeTypes.Use
type Measure = (Use) -> number
export type PanelView = { panel: Frame, chrome: Measure, tech: Measure }
export type Panel = (boolean, (Use) -> boolean, ComposeTypes.Readable<number>, number?) -> PanelView

local MODE_LABEL, GAP, PAD, SPACE, MAX_COLUMNS = Kit.MODE_LABEL, Kit.GAP, Kit.PAD, Kit.SPACE, Kit.MAX_COLUMNS

return function(
	ctx: Shared.Context,
	UI: Kit.Deps,
	surfaces: Nav.Surfaces,
	kit: Kit.Kit,
	state: PickerState.State
): Panel
	local Compose, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local E, D, D2 = ctx.types.Enum, ctx.types.UDim, ctx.types.UDim2
	local modes, draft = state.modes, state.draft
	local modeCell, columns = state.modeCell, state.columns
	local touch, close = state.touch, state.close
	local sliders = createSliders(ctx, UI, kit, state)
	local planeView = createSpectrum(ctx, UI, surfaces, kit, state, sliders)
	local swatches = createSwatches(ctx, UI, surfaces, kit, state)
	local readoutView = createReadout(ctx, UI, kit, state)
	local swatchesView, slidersView, brickView = swatches.swatchesView, sliders.slidersView, swatches.brickView

	local function panelView(
		overlay: boolean,
		sheet: (Use) -> boolean,
		room: ComposeTypes.Readable<number>,
		width: number?
	): PanelView
		if width and width > 0 then
			local available = width - surfaces.inset(PAD, "left") - surfaces.inset(PAD, "right")
			columns:set(math.clamp(math.floor((available + GAP) / (state.cellSize() + GAP)), 1, MAX_COLUMNS))
		end
		local builders: { [string]: () -> Frame } =
			{ swatches = swatchesView, spectrum = planeView, sliders = slidersView, brick = brickView }
		local shows: { Frame } = {}
		local technique: Shared.FrameNativeProps = {
			Name = "Technique",
			BackgroundTransparency = 1,
		}
		for _, mode in modes do
			local visited = Compose.cell(modeCell:peek() == mode)
			if not visited:peek() then
				Compose.watch(function(use: Use)
					if use(modeCell) == mode then
						visited:set(true)
					end
				end)
			end
			local show = Host.Frame(`Show{MODE_LABEL[mode]}`)({
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Visible = function(use: Use)
					return use(modeCell) == mode
				end,
				Compose.show(visited, builders[mode]),
			})
			table.insert(shows, show)
			technique[#technique + 1] = show
		end
		local heights: { ComposeTypes.Readable<Vector2> } = {}
		for _, show in shows do
			table.insert(heights, runtime.observe(show, "AbsoluteSize") :: ComposeTypes.Readable<Vector2>)
		end
		local techniqueNode = Host.Frame(technique)
		local unit = ctx.layoutUnit(techniqueNode)
		local function active(use: Use): number
			local index = table.find(modes, use(modeCell))
			return if index then use(heights[index]).Y / use(unit) else 0
		end
		local function tech(use: Use): number
			return if overlay then 6 * state.cellSize(use) + 5 * GAP else active(use)
		end
		local extent = runtime.observe(techniqueNode, "AbsoluteSize") :: ComposeTypes.Readable<Vector2>
		Compose.watch(function(use: Use)
			local w = use(extent).X / use(unit)
			if w > 0 then
				columns:set(math.clamp(math.floor((w + GAP) / (state.cellSize(use) + GAP)), 1, MAX_COLUMNS))
			end
		end)
		local measured: { { node: GuiObject, size: ComposeTypes.Readable<Vector2> } } = {}
		local function measure(node: GuiObject): GuiObject
			local size = runtime.observe(node, "AbsoluteSize") :: ComposeTypes.Readable<Vector2>
			table.insert(measured, { node = node, size = size })
			return node
		end
		local children: { Shared.Child } = {}
		if #modes > 1 then
			local options: { Nav.PickerOption<string> } = {}
			for _, mode in modes do
				table.insert(options, { value = mode, label = MODE_LABEL[mode] })
			end
			local modeProps: NavigationProps.SinglePickerSpec<string> = {
				Name = "Modes",
				selected = modeCell,
				style = "automatic" :: "automatic",
				options = options,
				LayoutOrder = 1,
			}
			table.insert(children, measure(UI.Picker(modeProps)))
		end
		local readout = readoutView()
		runtime.decorate(readout, {
			LayoutOrder = function(use: Use)
				return if touch(use) then 2 else 5
			end,
		})
		table.insert(children, measure(readout))
		local body = Host.ScrollingFrame "Body" {
			LayoutOrder = 3,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Selectable = false,
			ScrollBarThickness = 4,
			VerticalScrollBarInset = E.ScrollBarInset.ScrollBar,
			ScrollingDirection = E.ScrollingDirection.Y,
			AutomaticCanvasSize = E.AutomaticSize.Y,
			CanvasSize = D2.fromOffset(0, 0),
			Size = function(use: Use)
				local height = math.ceil(tech(use))
				return D2.new(1, 0, 0, if overlay then math.min(height, math.max(0, use(room))) else height)
			end,
			techniqueNode :: Shared.Child,
		}
		runtime.decorate(techniqueNode, {
			Size = function(use: Use)
				return D2.new(1, 0, 0, active(use))
			end,
		})
		table.insert(children, body)
		if state.hasAlpha then
			table.insert(children, measure(sliders.opacitySlider()))
		end
		local actions: { Shared.Child } = {}
		if draft then
			local cancelProps: InputProps.ButtonProps = {
				Name = "Cancel",
				label = "Cancel",
				role = "cancel" :: "cancel",
				onActivate = function()
					if overlay then
						close("cancel")
					else
						state.restore()
					end
				end,
			}
			table.insert(actions, UI.Button(cancelProps))
			table.insert(
				actions,
				UI.Button("Apply")({
					label = "Apply",
					appearance = "emphasis",
					onActivate = function()
						state.apply()
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
			props[#props + 1] = ctx.padding(PAD, PAD)
			props[#props + 1] = ctx.corner()
		end
		for _, child in children do
			props[#props + 1] = child
		end
		local panel = if overlay
			then ctx.fade((props :: unknown) :: Shared.CanvasGroupNativeProps)
			else Host.Frame(props)
		local visibility: { ComposeTypes.Readable<boolean> } = {}
		for _, entry in measured do
			table.insert(visibility, ctx.observe.Visible(entry.node))
		end
		local function chromeHeight(use: Use): number
			local total, count = 0, 1
			for index, entry in measured do
				if use(visibility[index]) then
					local extent: Vector2 = use(entry.size)
					total += extent.Y / use(unit)
					count += 1
				end
			end
			return total
				+ (count - 1) * SPACE
				+ (
					if overlay
						then surfaces.inset(PAD, "top", nil, use) + surfaces.inset(PAD, "bottom", nil, use)
						else 0
				)
		end
		return { panel = panel, chrome = chromeHeight, tech = tech }
	end

	return panelView
end
