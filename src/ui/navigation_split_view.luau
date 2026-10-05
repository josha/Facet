--!strict
local Shared = require("./types")
local Inputs = require("./input_types")
local Nav = require("./navigation_types")
local parts = require("./overlay_parts")
local scrollLock = require("./scroll_lock")
local dragSession = require("./drag_session")

export type Column = "sidebar" | "detail"
export type Props = Shared.FrameProps & {
	axis: ("x" | "y")?,
	sidebarHeight: Shared.Cell<number>?,
	minSidebarHeight: number?,
	maxSidebarHeight: number?,
	minDetailHeight: number?,
	compactHeight: number?,
	sidebar: Nav.Content,
	detail: Nav.Content,
	detailVisible: Shared.ValueBoolean?,
	preferredCompactColumn: Shared.Cell<Column>?,
	sidebarWidth: Shared.Cell<number>?,
	minSidebarWidth: number?,
	maxSidebarWidth: number?,
	minDetailWidth: number?,
	compactWidth: number?,
	backLabel: Shared.ValueString?,
	detailLabel: Shared.ValueString?,
}
export type Constructor = Shared.Constructor<Props, Frame>
export type Controls = { NavigationSplitView: Constructor }
type Registry = {
	NavigationSplitView: Constructor,
	Button: Shared.Constructor<Inputs.ButtonProps, TextButton>,
	adjustable: (GuiObject, Inputs.AdjustableOptions) -> (),
}

return function(ctx: Shared.Context, UI: Registry, surfaces: Nav.Surfaces)
	local Host, Compose, runtime, read = ctx.Host, ctx.Compose, ctx.runtime, ctx.read
	local D2, V2, E = ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
	UI.NavigationSplitView = ctx.construct("NavigationSplitView", function(spec: Props): Frame
		assert(spec.axis == nil or spec.axis == "x" or spec.axis == "y", "NavigationSplitView.axis must be x or y")
		local vertical = spec.axis == "y"
		local minimum = if vertical then spec.minSidebarHeight or 120 else spec.minSidebarWidth or 240
		local maximum = if vertical then spec.maxSidebarHeight or 600 else spec.maxSidebarWidth or 600
		local detailMinimum = if vertical then spec.minDetailHeight or 120 else spec.minDetailWidth or 320
		local breakpoint = if vertical then spec.compactHeight or 320 else spec.compactWidth or 720
		local function along(value: Vector2): number
			return if vertical then value.Y else value.X
		end
		local function dimensions(scale: number, offset: number, crossScale: number, crossOffset: number): UDim2
			return if vertical
				then D2.new(crossScale, crossOffset, scale, offset)
				else D2.new(scale, offset, crossScale, crossOffset)
		end
		for _, value in { minimum, maximum, detailMinimum, breakpoint } do
			assert(value > 0 and value < math.huge, "NavigationSplitView pane limits must be positive finite numbers")
		end
		assert(maximum >= minimum, "NavigationSplitView maximum sidebar size must be at least its minimum")
		local column: Shared.Cell<Column> = spec.preferredCompactColumn or Compose.cell("sidebar" :: Column)
		local extent: Shared.Cell<number> = if vertical
			then spec.sidebarHeight or Compose.cell(240)
			else spec.sidebarWidth or Compose.cell(360)
		assert(column.set and extent.set, "NavigationSplitView column and pane size require writable cells")
		local root = Host.Frame(ctx.props(spec, {
			"sidebar",
			"detail",
			"detailVisible",
			"preferredCompactColumn",
			"sidebarWidth",
			"axis",
			"sidebarHeight",
			"minSidebarHeight",
			"maxSidebarHeight",
			"minDetailHeight",
			"compactHeight",
			"minSidebarWidth",
			"maxSidebarWidth",
			"minDetailWidth",
			"compactWidth",
			"backLabel",
			"detailLabel",
		}, { Name = "NavigationSplitView", Size = D2.fromScale(1, 1), BackgroundTransparency = 1 }))
		local size, unit = ctx.layoutSize(root), ctx.layoutUnit(root)
		local input, tenFoot, hitFloor = ctx.effectiveInput(), ctx.tenFoot(), ctx.hitFloor()
		local nativeInput = ctx.config.services.UserInputService
		local preferred = if nativeInput then ctx.observe.PreferredInput(nativeInput) else nil
		local hovered, dragging = Compose.cell(false), Compose.cell(false)
		local gamepad = ctx.config.services.GamepadService
		local cursor = if gamepad then ctx.observe.GamepadCursorEnabled(gamepad) else Compose.cell(false)
		local function gutter(use: Shared.Use?): number
			return if input(use) == "KeyboardAndMouse" then 12 else math.max(28, hitFloor(use))
		end
		local shown = Compose.formula(function(use: Shared.Use): boolean
			return spec.detailVisible == nil or read(spec.detailVisible, use)
		end)
		local compact = Compose.formula(function(use: Shared.Use): boolean
			return tenFoot(use) or along(use(size)) < math.max(breakpoint, minimum + detailMinimum + gutter(use))
		end)
		local selectedColumn = Compose.formula(function(use: Shared.Use): Column
			local value = use(column)
			assert(value == "sidebar" or value == "detail", "NavigationSplitView column must be sidebar or detail")
			return if use(shown) then value else "sidebar"
		end)
		local actualExtent = Compose.formula(function(use: Shared.Use): number
			local requested = use(extent)
			assert(
				requested == requested and math.abs(requested) < math.huge,
				"NavigationSplitView sidebar size must be finite"
			)
			return math.clamp(
				requested,
				minimum,
				math.max(minimum, math.min(maximum, along(use(size)) - detailMinimum - gutter(use)))
			)
		end)
		local function split(use: Shared.Use): boolean
			return use(shown) and not use(compact)
		end
		local function chrome(use: Shared.Use): number
			return if use(compact) and use(shown) then ctx.metric("targetSizes.minimum", use) else 0
		end
		local sidebar: Frame
		local detail: Frame
		local detailVisibility: Shared.Readable<boolean>? = nil
		local resize: TextButton
		local function back()
			column:set("sidebar")
		end
		local function build(content: Nav.Content): Instance
			return if type(content) == "function" then content() else content
		end
		local startPosition, startExtent = 0, 0
		local releaseScroll: (() -> ())? = nil
		local function finish()
			dragging:set(false)
			if releaseScroll then
				releaseScroll()
				releaseScroll = nil
			end
		end
		local function setExtent(value: number)
			extent:set(
				math.clamp(
					value,
					minimum,
					math.max(minimum, math.min(maximum, along(size:peek()) - detailMinimum - gutter()))
				)
			)
		end
		Compose.cleanup(finish)
		if ctx.config.services.UserInputService then
			runtime.connect(ctx.config.services.UserInputService, "WindowFocusReleased", finish)
		end
		surfaces.attach(root, {
			(function()
				sidebar = Host.Frame {
					Name = "Sidebar",
					BackgroundTransparency = 1,
					Visible = function(use: Shared.Use): boolean
						return not use(compact) or use(selectedColumn) == "sidebar"
					end,
					Position = function(use: Shared.Use)
						return D2.fromOffset(0, chrome(use))
					end,
					Size = function(use: Shared.Use)
						return if split(use)
							then dimensions(0, use(actualExtent), 1, 0)
							else D2.new(1, 0, 1, -chrome(use))
					end,
					build(spec.sidebar),
				}
				return sidebar
			end)(),
			Compose.show(shown, function()
				detail = Host.Frame {
					Name = "Detail",
					BackgroundTransparency = 1,
					Visible = function(use: Shared.Use): boolean
						return not use(compact) or use(selectedColumn) == "detail"
					end,
					Position = function(use: Shared.Use)
						return if split(use)
							then dimensions(0, use(actualExtent) + gutter(use), 0, 0)
							else D2.fromOffset(0, chrome(use))
					end,
					Size = function(use: Shared.Use)
						return if split(use)
							then dimensions(1, -use(actualExtent) - gutter(use), 1, 0)
							else D2.new(1, 0, 1, -chrome(use))
					end,
					build(spec.detail),
				}
				detailVisibility = ctx.observe.Visible(detail)
				surfaces.keep(spec.detail)
				return detail
			end),
			Host.Frame {
				Name = "NavigationBar",
				BackgroundTransparency = 1,
				Visible = function(use: Shared.Use): boolean
					return use(compact) and use(shown)
				end,
				Size = function(use: Shared.Use)
					return D2.new(1, 0, 0, chrome(use))
				end,
				Compose.show(function(use: Shared.Use)
					return use(selectedColumn) == "detail"
				end, function()
					return parts.back(ctx, UI, spec.backLabel, back)
				end, function()
					return UI.Button {
						Name = "ShowDetail",
						label = spec.detailLabel or "Show detail",
						appearance = "utility",
						onActivate = function()
							column:set("detail")
						end,
					}
				end),
			},
			(function()
				local resizeProps: Shared.TextButtonProps = {
					Name = "Resize",
					Active = true,
					MouseEnter = function()
						hovered:set(true)
					end,
					MouseLeave = function()
						hovered:set(false)
					end,
					Text = "",
					AutoButtonColor = false,
					BackgroundTransparency = 1,
					Visible = split,
					Selectable = true,
					Position = function(use: Shared.Use)
						return dimensions(0, use(actualExtent), 0, 0)
					end,
					Size = function(use: Shared.Use)
						return dimensions(0, gutter(use), 1, 0)
					end,
					Attributes = {
						AccessibleLabel = "Resize split. Use L1 and R1, or comma and period.",
						FacetFocusPart = "Grip",
					} :: Shared.Attributes,
					ctx.styled(
						Host.Frame {
							Name = "Line",
							AnchorPoint = if vertical then V2.new(0, 0.5) else V2.new(0.5, 0),
							Position = dimensions(0.5, 0, 0, 0),
							Size = dimensions(0, 1, 1, 0),
							BorderSizePixel = 0,
						},
						"divider"
					),
					Host.Frame {
						Name = "Grip",
						BackgroundTransparency = 1,
						Active = false,
						Selectable = false,
						AnchorPoint = V2.new(0.5, 0.5),
						Position = D2.fromScale(0.5, 0.5),
						Size = dimensions(0, 8, 0, 36),
						Host.UICorner { CornerRadius = ctx.round } :: Shared.Child,
						ctx.styled(
							Host.Frame {
								Name = "Pill",
								Active = false,
								AnchorPoint = V2.new(0.5, 0.5),
								Position = D2.fromScale(0.5, 0.5),
								Size = dimensions(0, 3, 0, 24),
								BorderSizePixel = 0,
								Visible = function(use: Shared.Use): boolean
									return use(hovered) or use(dragging) or input(use) ~= "KeyboardAndMouse"
								end,
								Host.UICorner { CornerRadius = ctx.round },
							},
							"grabber"
						),
					},
					Host.UIDragDetector {
						Enabled = function(use: Shared.Use): boolean
							return split(use)
								and (
									preferred == nil
									or use(preferred) ~= E.PreferredInput.Gamepad
									or use(cursor) == true
								)
						end,
						CursorIcon = if vertical
							then "rbxasset://SystemCursors/SizeNS"
							else "rbxasset://SystemCursors/SizeEW",
						ActivatedCursorIcon = if vertical
							then "rbxasset://SystemCursors/SizeNS"
							else "rbxasset://SystemCursors/SizeEW",
						DragStyle = E.UIDragDetectorDragStyle.TranslateLine,
						DragAxis = if vertical then V2.new(0, 1) else V2.new(1, 0),
						ResponseStyle = E.UIDragDetectorResponseStyle.CustomOffset,
						DragStart = function(position: Vector2)
							finish()
							dragging:set(true)
							startPosition, startExtent = along(position), actualExtent:peek()
							releaseScroll = scrollLock.holdOwnedAncestors(root)
						end,
						DragContinue = function(position: Vector2)
							if releaseScroll then
								setExtent(startExtent + (along(position) - startPosition) / unit:peek())
							end
						end,
						DragEnd = function(position: Vector2)
							if releaseScroll then
								setExtent(startExtent + (along(position) - startPosition) / unit:peek())
							end
							finish()
						end,
					},
				}
				resize = Host.TextButton(resizeProps)
				UI.adjustable(resize, {
					axis = "none",
					repeats = true,
					enabled = split,
					onAdjust = function(direction: number)
						setExtent(actualExtent:peek() + direction * 16)
					end,
				})
				return resize
			end)(),
		})
		surfaces.keep(spec.sidebar)
		local gui = surfaces.service("GuiService")
		local selecting = surfaces.selecting()
		local selected = if gui then ctx.observe.SelectedObject(gui) else Compose.cell(nil :: GuiObject?)
		local lastSidebar: GuiObject? = nil
		local lastDetail: GuiObject? = nil
		local previousPane: Frame? = nil
		Compose.watch(function(use: Shared.Use)
			local current = use(selected) :: GuiObject?
			local pane = if surfaces.within(current, sidebar)
				then sidebar
				elseif detail and surfaces.within(current, detail) then detail
				else nil
			local crossed = previousPane ~= nil and pane ~= nil and pane ~= previousPane
			previousPane = pane
			if crossed and split(use) and gui then
				previousPane = nil
				gui.SelectedObject = resize
				return
			end
			if surfaces.within(current, sidebar) then
				lastSidebar = current
				if vertical then
					resize.NextSelectionUp = current :: GuiObject
				else
					resize.NextSelectionLeft = current :: GuiObject
				end
			end
			if detail and surfaces.within(current, detail) then
				lastDetail = current
				if vertical then
					resize.NextSelectionDown = current :: GuiObject
				else
					resize.NextSelectionRight = current :: GuiObject
				end
			end
		end)
		local previousCompact, previousColumn, previousShown = compact:peek(), selectedColumn:peek(), shown:peek()
		local pendingFocus = false
		local sidebarVisibility = ctx.observe.Visible(sidebar)
		Compose.watch(function(use: Shared.Use)
			local collapsed, current, visible = use(compact), use(selectedColumn), use(shown)
			use(sidebarVisibility)
			if detailVisibility then
				use(detailVisibility)
			end
			root:SetAttribute("FacetSplitCollapsed", collapsed)
			root:SetAttribute("FacetSplitColumn", current)
			if not split(use) then
				finish()
			end
			local changed = collapsed ~= previousCompact or current ~= previousColumn or visible ~= previousShown
			previousCompact, previousColumn, previousShown = collapsed, current, visible
			if changed then
				pendingFocus = gui ~= nil
					and (surfaces.within(gui.SelectedObject, root) or (not use(cursor) and selecting(use)))
			end
			if pendingFocus and gui and ctx.available(root, use) then
				if not collapsed and gui.SelectedObject ~= resize and ctx.available(gui.SelectedObject or root) then
					pendingFocus = false
					return
				end
				local pane = if collapsed and current == "detail" then detail else sidebar
				if not pane or not ctx.available(pane, use) then
					return
				end
				local saved = if pane == sidebar then lastSidebar else lastDetail
				local target = if saved
						and ctx.available(saved)
						and saved.Selectable
					then saved
					else surfaces.firstSelectable(pane)
				if target then
					pendingFocus = false
					gui.SelectedObject = target
				end
			end
		end)
		local drag = dragSession(ctx)
		root:SetAttribute("FacetNavigationStack", true)
		local _, actionContext = ctx.action(
			root,
			"SplitBack",
			{ "Escape", "ButtonB" },
			function(use: Shared.Use): boolean
				return use(compact) and use(shown) and use(selectedColumn) == "detail" and use(drag.state) == nil
			end,
			back,
			{ priority = 1001 }
		)
		local function locate()
			local depth, at = 0, root.Parent
			while at do
				if at:GetAttribute("FacetNavigationStack") == true then
					depth += 1
				end
				at = at.Parent
			end
			actionContext.Priority = 1000 + depth
		end
		runtime.connect(root, "AncestryChanged", locate)
		locate()
		return root
	end)
end
