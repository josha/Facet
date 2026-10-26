--!strict
local ControlTypes = require("./control_types")
local Types = require("./types")
local Nav = require("./navigation_types")
local reducedMotion = require("./motion").reduced
local ComposeTypes = require("../vendor/compose/core")
local parts = require("./overlay_parts")
local NavigationProps = require("./navigation_props")
local MenuItems = require("./nav_menu_items")
local MenuRows = require("./nav_menu_rows")

type MenuEntry<V> = MenuItems.MenuEntry<V>

return function(ctx: Types.Context, UI: ControlTypes.BuilderControls, surfaces: Nav.Surfaces)
	local Host, Compose, runtime, read = ctx.Host, ctx.Compose, ctx.runtime, ctx.read
	local readSource = ctx.readSource
	local E, D2, V2, D = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2, ctx.types.UDim
	local itemModel = MenuItems(ctx)
	local actionItem, menuItems, resolveWidth = itemModel.actionItem, itemModel.menuItems, itemModel.resolveWidth
	local menuRow = MenuRows(ctx, UI, surfaces)
	local function menuPanel<V>(
		spec: NavigationProps.MenuSpec<V>,
		close: () -> (),
		anchor: GuiObject,
		nonmodal: boolean?,
		phase: Nav.PresencePhase?,
		motion: Nav.MotionTiming?,
		pointer: ComposeTypes.ReadOnlyValue<Vector2?>?,
		closeCommand: (boolean | "automatic")?
	): Frame
		local popoverTiming, sheetTiming = ctx.motionTiming("popover"), ctx.motionTiming("sheet")
		local timing: Nav.MotionTiming = motion or { enter = popoverTiming.enter, exit = popoverTiming.exit }
		local present = ctx.motionEase("present")
		local slide = ctx.metric("motion.distances.menuSlide")
		local materialize = ctx.metric("motion.materialize.menu")
		local entered = Compose.cell(false)
		local appearance = if phase then surfaces.appearance(phase, timing, entered) else nil
		local hitFloor = ctx.hitFloor()
		local path = Compose.cell({} :: { string })
		local branchYs = Compose.cell({} :: { number })
		local rowNodes: { [string]: GuiObject } = {}
		local enter: (string, GuiObject?, { string }?) -> ()
		local pendingFocus: string?
		local sheeted = Compose.cell(false)
		local reduce = reducedMotion(ctx)
		local levelClock = runtime.timeline({ duration = popoverTiming.enter, autoplay = false })
		local levelDirection = Compose.cell(0)
		local levelReady = Compose.cell(true)
		local pendingLevel = false
		local depthSeen = 0
		Compose.watch(function(use: ComposeTypes.Use)
			local depth = #use(path)
			if depth ~= depthSeen then
				levelDirection:set(if depth > depthSeen then 1 else -1)
				depthSeen = depth
				pendingLevel = true
			end
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			if use(levelReady) and pendingLevel then
				pendingLevel = false
				levelClock:restart()
			end
		end)
		local presentedLevel = 1
		local function level(use: ComposeTypes.Use?): number
			if phase and read(phase.exiting, use) then
				return presentedLevel
			end
			local direction: number = if use then use(levelDirection) else levelDirection:peek()
			if direction == 0 or reduce(use) then
				presentedLevel = 1
				return 1
			end
			if not read(levelReady, use) then
				presentedLevel = 0
				return 0
			end
			presentedLevel = present(readSource(levelClock.progress, use))
			return presentedLevel
		end
		local shown: Nav.Presence? = if appearance
			then {
				opacity = function(use: ComposeTypes.Use?): number
					return appearance.opacity(use) * (if read(sheeted, use) then 1 else level(use))
				end,
				travel = function(use: ComposeTypes.Use?): number
					return appearance.travel(use) * (if read(sheeted, use) then 1 else level(use))
				end,
			}
			else nil
		local rootItems = Compose.formula(function(use: ComposeTypes.Use)
			return menuItems(read(spec.items, use), use)
		end)
		local current = Compose.formula(function(use: ComposeTypes.Use)
			local items = use(rootItems)
			for _, id in use(path) do
				local found: Nav.MenuAction<V>?
				for _, item in items do
					if item.divider ~= true and item.id == id then
						found = item
						break
					end
				end
				if not found or not found.children then
					break
				end
				items = read(found.children, use)
			end
			return items
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			local items, valid = use(rootItems), {}
			for _, id in path:peek() do
				local found: Nav.MenuAction<V>?
				for _, item in items do
					if item.divider ~= true and item.id == id then
						found = item
						break
					end
				end
				if not found or not found.children then
					break
				end
				table.insert(valid, id)
				items = read(found.children, use)
			end
			if #valid ~= #path:peek() then
				path:set(valid)
			end
		end)
		local function back()
			local previous = table.clone(path:peek())
			if #previous == 0 then
				close()
			else
				pendingFocus = table.remove(previous)
				path:set(previous)
			end
		end
		local widths = Compose.cell({} :: { [string]: number })
		local function landing(items: { Nav.MenuItem<V> }): string?
			for _, item in items do
				if item.divider ~= true then
					local action = actionItem(item)
					local chosen = if action.selected ~= nil
						then read(action.selected) == action.value
						else read(action.marked) == true
					if chosen and read(action.enabled) ~= false then
						return tostring(item.id)
					end
				end
			end
			return nil
		end
		local entries = Compose.formula(function(use: ComposeTypes.Use): { MenuEntry<V> }
			local out: { MenuEntry<V> } = {}
			local afterRow = false
			for index, item in use(current) do
				local key = tostring(item.id or index)
				if item.divider ~= true then
					local heading = read(actionItem(item).sectionTitle, use)
					if heading ~= nil and heading ~= "" then
						table.insert(out, { key = "Section:" .. key, heading = heading })
						afterRow = false
					end
				end
				table.insert(out, { key = key, item = item, ruled = afterRow and item.divider ~= true })
				afterRow = item.divider ~= true
			end
			return out
		end)
		local rowState: MenuRows.RowState = {
			hitFloor = hitFloor,
			sheeted = sheeted,
			path = path,
			rowNodes = rowNodes,
			widths = widths,
			enter = function(id: string, node: GuiObject?, prefix: { string }?)
				enter(id, node, prefix)
			end,
			close = close,
		}
		local rows = Host.Frame "MenuRows" {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = D2.new(1, 0, 0, 0),
			AutomaticSize = E.AutomaticSize.Y,
			Host.UIListLayout({
				FillDirection = E.FillDirection.Vertical,
				SortOrder = E.SortOrder.LayoutOrder,
				Padding = function(use: ComposeTypes.Use)
					return D.new(0, if use(sheeted) then 8 else 0)
				end,
			}),
			Compose.show(function()
				return spec.query ~= nil
			end, function()
				return UI.TextInput "Search" {
					value = assert(spec.query),
					placeholder = "Search",
					LayoutOrder = -2,
				}
			end),
			Compose.show(function(use: ComposeTypes.Use)
				return #use(path) > 0 and use(sheeted)
			end, function()
				return parts.back(ctx, UI, spec.backLabel, back, {
					LayoutOrder = -1,
					Size = D2.new(1, 0, 0, 44),
				})
			end),
			Compose.keyed({
				from = entries,
				key = function(entry: MenuEntry<V>)
					local item = entry.item
					return (if item and item.divider ~= true and item.description ~= nil then "D:" else "P:")
						.. entry.key
				end,
				render = function(
					entrySource: ComposeTypes.ReadOnlyValue<MenuEntry<V>>,
					index: ComposeTypes.ReadOnlyValue<number>
				)
					return menuRow.entry(entrySource, index, rowState)
				end,
			}),
			Host.UIPadding({
				PaddingTop = function(use: ComposeTypes.Use)
					return D.new(0, if use(sheeted) then 8 else ctx.metric("space.xs", use))
				end,
				PaddingBottom = function(use: ComposeTypes.Use)
					return D.new(0, if use(sheeted) then 8 else ctx.metric("space.xs", use))
				end,
				PaddingLeft = function(use: ComposeTypes.Use)
					return D.new(0, if use(sheeted) then 8 else ctx.metric("space.xs", use))
				end,
				PaddingRight = function(use: ComposeTypes.Use)
					return D.new(0, if use(sheeted) then 8 else ctx.metric("space.xs", use))
				end,
			}),
		}
		if closeCommand ~= nil and closeCommand ~= false then
			surfaces.attach(rows, {
				Compose.show(function(use: ComposeTypes.Use)
					return closeCommand == true or use(sheeted)
				end, function()
					return UI.Button "CloseCommand" {
						name = "Close",
						icon = "close",
						LayoutOrder = 2147483647,
						Size = D2.new(1, 0, 0, 44),
						AutomaticSize = E.AutomaticSize.None,
						onActivate = close,
					}
				end),
			})
		end
		local room = Compose.cell(0)
		local function panelWidth(use: ComposeTypes.Use): number
			local widest = 0
			for _, width in use(widths) do
				widest = math.max(widest, width)
			end
			local natural = math.clamp(widest + 48, 220, 400)
			local authored = read(spec.width, use)
			if authored == nil then
				return natural
			end
			local space = use(room)
			local resolved = resolveWidth(authored, natural, space, use)
			return if space > 0 then math.min(resolved, space) else resolved
		end
		runtime.decorate(rows, {
			Position = function(use: ComposeTypes.Use)
				local direction = use(levelDirection)
				if not use(sheeted) or direction == 0 or reduce(use) then
					return D2.fromOffset(0, 0)
				end
				return D2.fromOffset(direction * slide * (1 - level(use)), 0)
			end,
		})
		local scroller = Host.ScrollingFrame "MenuScroll" {
			Selectable = false,
			BackgroundTransparency = 1,
			Size = D2.fromScale(1, 1),
			BorderSizePixel = 0,
			AutomaticCanvasSize = E.AutomaticSize.Y,
			CanvasSize = D2.fromOffset(0, 0),
			ScrollingDirection = E.ScrollingDirection.Y,
			ScrollBarThickness = 4,
			VerticalScrollBarInset = E.ScrollBarInset.ScrollBar,
			rows,
		}
		local levelFade = ctx.fade({
			Name = "MenuLevel",
			BackgroundTransparency = 1,
			Size = D2.fromScale(1, 1),
			scroller,
		}, nil, false)
		ctx.fadeTo(levelFade, function(use: ComposeTypes.Use): number
			if not use(sheeted) then
				return 0
			end
			return 1 - level(use)
		end)
		local panel = Host.Frame "MenuPanel" {
			Size = D2.fromOffset(280, 0),
			BorderSizePixel = 0,
			if shown
				then ctx.styled(
					ctx.fade({
						Name = "MenuGroup",
						BackgroundTransparency = 1,
						Size = D2.fromScale(1, 1),
						GroupTransparency = function(use: ComposeTypes.Use)
							return 1 - shown.opacity(use)
						end,
						levelFade,
					}, true, false),
					"menu-group"
				)
				else levelFade,
		}
		if shown then
			surfaces.attach(panel, {
				Host.UIGradient "PresentationFade" {
					Transparency = function(use: ComposeTypes.Use)
						return ctx.types.NumberSequence.new(1 - shown.opacity(use))
					end,
				},
			})
		end
		ctx.styled(panel, "menu")
		surfaces.skin(panel, nil, {
			reserve = function(): number
				return 0
			end,
		})
		local restKey = ""
		local sizes, rested = surfaces.atRest(
			if shown
				then shown.travel
				else function(): number
					return 1
				end,
			entered,
			{ panel, rows },
			function(use: ComposeTypes.Use): string
				local key = table.concat(use(path), "/")
				if phase and use(phase.exiting) then
					return restKey
				end
				restKey = key
				return key
			end
		)
		local measured, rowSize = sizes[1], sizes[2]
		local rowExtent = Compose.cell(rowSize:peek())
		local rowRest = ctx.runtime.settled {
			sample = function(): string
				return tostring(rowSize:peek())
			end,
			ready = function(): boolean
				local size = rowSize:peek()
				return size.X > 0 and size.Y > 0
			end,
			restart = function(use: ComposeTypes.Use): string
				return tostring(use(rowSize))
			end,
		}
		Compose.watch(function(use: ComposeTypes.Use)
			local size = use(rowSize)
			if not use(rested) or use(rowRest) then
				rowExtent:set(size)
			end
		end)
		enter = function(id: string, node: GuiObject?, prefix: { string }?)
			local nextPath = table.clone(prefix or path:peek())
			table.insert(nextPath, id)
			local row = node or rowNodes[id]
			local ys = table.clone(branchYs:peek())
			ys[#nextPath] = if row then row.AbsolutePosition.Y - panel.AbsolutePosition.Y else 0
			branchYs:set(ys)
			pendingFocus = nil
			path:set(nextPath)
		end
		Compose.watch(function(use: ComposeTypes.Use)
			levelReady:set(use(rested))
		end)
		local position = ctx.observe.AbsolutePosition(anchor)
		local size = ctx.observe.AbsoluteSize(anchor)
		local function anchorBounds(use: ComposeTypes.Use): (Vector2, Vector2)
			local point = if pointer then use(pointer) else nil
			return if point then point else use(position), if point then V2.zero else use(size)
		end
		local modal = if nonmodal
			then Host.Frame "SuggestionsOverlay" {
				BackgroundTransparency = 1,
				Size = D2.fromScale(1, 1),
				ZIndex = 100,
				panel,
			}
			else surfaces.modal(
				function()
					return panel
				end,
				back,
				{
					backgroundTransparency = function(use: ComposeTypes.Use): number
						return if use(sheeted) then 0.5 else 1
					end,
					appearance = if shown then shown.opacity else nil,
					onOutside = close,
					exiting = if phase then phase.exiting else nil,
					initialFocus = landing(current:peek()),
				}
			)
		if nonmodal then
			ctx.modalPortal(modal, anchor)
			runtime.decorate(panel, { ZIndex = 101 })
		end
		local extent = ctx.observe.AbsoluteSize(modal)
		local origin = ctx.observe.AbsolutePosition(modal)
		local input = surfaces.service("UserInputService")
		local preferred = if input then ctx.observe.PreferredInput(input) else Compose.cell(nil :: Enum.PreferredInput?)
		local surface = ctx.observe.Parent(modal)
		local asSheet = Compose.formula(function(use: ComposeTypes.Use)
			local presentation = read(spec.presentation, use)
			if presentation and presentation ~= "automatic" then
				return presentation == "sheet"
			end
			local layer = use(surface)
			if layer and layer:IsA("SurfaceGui") then
				return false
			end
			return (use(extent).X > 0 and use(extent).X < math.max(600, #use(path) * 288 + panelWidth(use) + 16))
				or use(preferred) == E.PreferredInput.Touch
				or use(preferred) == E.PreferredInput.Gamepad
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			local sheet = use(asSheet)
			sheeted:set(sheet)
			timing.enter = if sheet then sheetTiming.enter else popoverTiming.enter
			timing.exit = if sheet then sheetTiming.exit else popoverTiming.exit
		end)
		local guiService = surfaces.service("GuiService")
		local layerOf = ctx.observe.Parent(modal)
		local function originOf(use: ComposeTypes.Use): Vector2
			use(origin)
			use(layerOf)
			use(extent)
			use(position)
			return modal.AbsolutePosition
		end
		local function insets(use: ComposeTypes.Use): (number, number, number, number)
			use(layerOf)
			use(extent)
			local layer = modal:FindFirstAncestorWhichIsA("ScreenGui")
			if guiService == nil or layer == nil then
				return 0, 0, 0, 0
			end
			local screen = layer :: ScreenGui
			if not (screen.IgnoreGuiInset == true or screen.ScreenInsets == E.ScreenInsets.None) then
				return 0, 0, 0, 0
			end
			local ok, topLeft, bottomRight = pcall(function(): (Vector2, Vector2)
				return guiService:GetGuiInset()
			end)
			if ok and typeof(topLeft) == "Vector2" and typeof(bottomRight) == "Vector2" then
				return topLeft.X, topLeft.Y, bottomRight.X, bottomRight.Y
			end
			return 0, 0, 0, 0
		end
		Compose.watch(function(use: ComposeTypes.Use)
			local left, _, right = insets(use)
			room:set(math.max(0, use(extent).X - left - right - 16))
		end)
		local presentedPlace: Vector2? = nil
		local presentedPivot = V2.zero
		local function place(use: ComposeTypes.Use): (Vector2, Vector2)
			if phase and use(phase.exiting) and presentedPlace then
				return presentedPlace, presentedPivot
			end
			local at, bounds = anchorBounds(use)
			local offer, panelSize, offset = use(extent), use(measured), originOf(use)
			local insetLeft, insetTop, insetRight, insetBottom = insets(use)
			local low, high =
				V2.new(insetLeft + 8, insetTop + 8), V2.new(offer.X - insetRight - 8, offer.Y - insetBottom - 8)
			if use(asSheet) then
				local at = V2.new(12 + insetLeft, math.max(12 + insetTop, offer.Y - insetBottom - panelSize.Y - 12))
				presentedPlace, presentedPivot = at, V2.zero
				return at, V2.zero
			end
			local x, y = at.X - offset.X, at.Y - offset.Y
			local depth = #use(path)
			local gap = if pointer and use(pointer) then 0 else 4
			local left, top = x + depth * 288, y + bounds.Y + gap
			local above, after = false, true
			local edge, align = spec.edge or "bottom", spec.align or "start"
			local function along(start: number, extentAcross: number, extentAlong: number): number
				return if align == "center"
					then start + (extentAcross - extentAlong) / 2
					elseif align == "end" then start + extentAcross - extentAlong
					else start
			end
			local vertical = depth > 0 or edge == "top" or edge == "bottom"
			if depth > 0 or (edge == "bottom" and align == "start") then
				if offer.Y > 0 and top + panelSize.Y > high.Y then
					top = y - panelSize.Y - gap
					above = true
				end
			elseif vertical then
				left = along(x, bounds.X, panelSize.X)
				local below, over = y + bounds.Y + gap, y - panelSize.Y - gap
				above = edge == "top"
				if edge == "bottom" and offer.Y > 0 and below + panelSize.Y > high.Y and over >= low.Y then
					above = true
				elseif edge == "top" and over < low.Y and (offer.Y <= 0 or below + panelSize.Y <= high.Y) then
					above = false
				end
				top = if above then over else below
			else
				top = along(y, bounds.Y, panelSize.Y)
				local beyond, before = x + bounds.X + 4, x - panelSize.X - 4
				after = edge == "trailing"
				if edge == "trailing" and offer.X > 0 and beyond + panelSize.X > high.X and before >= low.X then
					after = false
				elseif edge == "leading" and before < low.X and (offer.X <= 0 or beyond + panelSize.X <= high.X) then
					after = true
				end
				left = if after then beyond else before
				if offer.Y > 0 then
					top = math.clamp(top, low.Y, math.max(low.Y, high.Y - panelSize.Y))
				end
			end
			if offer.X > 0 then
				left = if depth > 0
					then math.clamp(x, low.X, math.max(low.X, high.X - panelSize.X - depth * 288)) + depth * 288
					else math.clamp(left, low.X, math.max(low.X, high.X - panelSize.X))
			end
			if offer.Y > 0 then
				top = math.clamp(top, low.Y, math.max(low.Y, high.Y - panelSize.Y))
			end
			top = math.max(low.Y, top)
			local pivot: Vector2
			local leaving = if phase then use(phase.exiting) else false
			if vertical and (depth > 0 or use(levelDirection) < 0) and not (leaving and depth == 0) then
				local back = use(levelDirection) < 0
				local y = use(branchYs)[if back then depth + 1 else depth] or 0
				pivot = V2.new(if back then panelSize.X else 0, math.clamp(y, 0, panelSize.Y))
			elseif vertical then
				local reach = if depth > 0 or align == "start"
					then x + depth * 288
					elseif align == "end" then x + bounds.X
					else x + bounds.X / 2
				pivot = V2.new(math.clamp(reach - left, 0, panelSize.X), if above then panelSize.Y else 0)
			else
				local reach = if align == "start" then y elseif align == "end" then y + bounds.Y else y + bounds.Y / 2
				pivot = V2.new(if after then 0 else panelSize.X, math.clamp(reach - top, 0, panelSize.Y))
			end
			local at = V2.new(left, top)
			presentedPlace, presentedPivot = at, pivot
			return at, pivot
		end
		local panelGeometry: Types.FrameNativeProps = {
			Size = function(use: ComposeTypes.Use)
				local function carve(side: string): number
					return surfaces.inset(0, side, nil, use)
				end
				local _, insetTop, _, insetBottom = insets(use)
				local height = math.min(
					use(rowExtent).Y + carve("top") + carve("bottom"),
					math.max(44, use(extent).Y - 24 - insetTop - insetBottom),
					if spec.maxHeight then math.max(60, spec.maxHeight) else math.huge
				)
				if use(asSheet) then
					local insetLeft, _, insetRight = insets(use)
					return D2.new(1, -24 - insetLeft - insetRight, 0, height)
				end
				return D2.fromOffset(panelWidth(use) + carve("left") + carve("right"), height)
			end,
		}
		runtime.decorate(panel, panelGeometry)
		if shown then
			surfaces.popover(panel, shown.travel, place, {
				pinned = true,
				from = materialize,
				rested = rested,
				size = measured,
				geometry = { Size = panelGeometry.Size, AutomaticSize = panelGeometry.AutomaticSize },
				rise = function(use: ComposeTypes.Use): number?
					if not use(asSheet) then
						return nil
					end
					local _, _, _, insetBottom = insets(use)
					return use(measured).Y + 12 + insetBottom
				end,
			})
		else
			runtime.decorate(panel, {
				Position = function(use: ComposeTypes.Use)
					local at = place(use)
					return D2.fromOffset(at.X, at.Y)
				end,
			})
		end
		local gui = surfaces.service("GuiService")
		local selected = if gui then ctx.observe.SelectedObject(gui) else Compose.cell(nil :: GuiObject?)
		local function selectedBranch(use: ComposeTypes.Use?): Nav.MenuAction<V>?
			local node = ctx.readSource(selected, use)
			for _, item in ctx.readSource(current, use) do
				if
					item.divider ~= true
					and node
					and item.id == node.Name
					and item.children
					and read(item.enabled, use) ~= false
				then
					return item
				end
			end
			return nil
		end
		surfaces.attach(modal, {
			Compose.show(function(use: ComposeTypes.Use)
				return selectedBranch(use) ~= nil or #use(path) > 0
			end, function()
				ctx.action(modal, "MenuRight", { E.KeyCode.Right, E.KeyCode.DPadRight }, function(use: ComposeTypes.Use)
					return selectedBranch(use) ~= nil
				end, function()
					local item = selectedBranch()
					if item then
						enter(assert(item.id))
					end
				end, { priority = 2100, capture = true })
				ctx.action(modal, "MenuLeft", { E.KeyCode.Left, E.KeyCode.DPadLeft }, function(use: ComposeTypes.Use)
					return #use(path) > 0
				end, back, { priority = 2100, capture = true })
				return Compose.fragment(function()
					return {}
				end)
			end),
		})
		local focusIn = surfaces.selecting()
		local placed = ctx.observe.Parent(modal)
		local windowSize = ctx.observe.AbsoluteSize(scroller)
		local rowLayout = rows:FindFirstChildWhichIsA("UIListLayout")
		local laidOut = if rowLayout then ctx.observe.AbsoluteContentSize(rowLayout) else Compose.cell(V2.zero)
		Compose.watch(function(use: ComposeTypes.Use)
			local items = use(current)
			use(placed)
			if gui and not nonmodal and focusIn(use) then
				local target = if pendingFocus then surfaces.firstSelectable(panel, pendingFocus) else nil
				if not target then
					local chosen = landing(items)
					target = if chosen then surfaces.firstSelectable(panel, chosen) else nil
					if chosen and not target and rows:FindFirstChild(chosen) == nil then
						use(laidOut)
						return
					end
				end
				if not target then
					for _, item in items do
						if item.divider ~= true and read(item.enabled, use) ~= false then
							local live = actionItem(item)
							local chosen = if live.selected
								then live.selected:peek() == live.value
								else read(live.marked, use) == true
							if chosen then
								target = surfaces.firstSelectable(panel, tostring(live.id))
								if target then
									break
								end
							end
						end
					end
				end
				if not target then
					for _, item in items do
						if not item.divider and read(item.enabled, use) ~= false then
							target = surfaces.firstSelectable(panel, tostring(item.id))
							if target then
								break
							end
						end
					end
				end
				if target and modal.Parent then
					gui.SelectedObject = target
				end
			end
		end)
		local centered: string? = nil
		local settling: RBXScriptConnection? = nil
		local function stopSettling()
			if settling then
				settling:Disconnect()
				settling = nil
			end
		end
		Compose.cleanup(stopSettling)
		Compose.watch(function(use: ComposeTypes.Use)
			local content = use(laidOut)
			local level = table.concat(use(path), "/") .. "@" .. tostring(if content then content.Y else 0)
			if centered == level then
				return
			end
			local chosen = landing(use(current))
			if chosen == nil then
				centered = level
				return
			end
			use(windowSize)
			use(rowSize)
			local row = rows:FindFirstChild(chosen)
			if row == nil or not row:IsA("GuiObject") then
				return
			end
			local function target(): number?
				local window, canvas = scroller.AbsoluteSize.Y, rows.AbsoluteSize.Y
				if window <= 0 or canvas <= 0 or row.Parent ~= rows then
					return nil
				end
				local gap = if rowLayout then rowLayout.Padding.Offset else 0
				local top = rows.AbsolutePosition.Y - scroller.AbsolutePosition.Y + scroller.CanvasPosition.Y
				canvas = math.max(canvas + top, scroller.AbsoluteCanvasSize.Y)
				local inset = rows:FindFirstChildWhichIsA("UIPadding")
				if inset then
					local ok, styled = pcall(function(): UDim
						return inset:GetStyled("PaddingTop")
					end)
					top += if ok then styled.Offset else inset.PaddingTop.Offset
				end
				local offset = top
				for _, sibling in rows:GetChildren() do
					if
						sibling ~= row
						and sibling:IsA("GuiObject")
						and sibling.Visible
						and sibling.LayoutOrder < row.LayoutOrder
					then
						offset += sibling.AbsoluteSize.Y + gap
					end
				end
				return math.clamp(offset + row.AbsoluteSize.Y / 2 - window / 2, 0, math.max(0, canvas - window))
			end
			local first = target()
			if first == nil then
				return
			end
			scroller.CanvasPosition = V2.new(scroller.CanvasPosition.X, first)
			centered = level
			local services = ctx.config.services
			local frames = services and services.RunService
			if frames then
				local remaining = 2
				stopSettling()
				settling = frames.Heartbeat:Connect(function()
					remaining -= 1
					local fresh = target()
					if fresh and scroller.CanvasPosition.Y ~= fresh then
						scroller.CanvasPosition = V2.new(scroller.CanvasPosition.X, fresh)
					end
					if remaining <= 0 then
						stopSettling()
					end
				end)
			end
		end)
		surfaces.attach(modal, {
			Compose.keyed({
				from = function(use: ComposeTypes.Use)
					if use(asSheet) then
						return {}
					end
					local levels: { { id: string, items: { Nav.MenuItem<V> }, prefix: { string }, depth: number } } = {}
					local items = use(rootItems)
					local prefix: { string } = {}
					for depth, selectedId in use(path) do
						table.insert(levels, {
							id = table.concat(prefix, "/"),
							items = items,
							prefix = table.clone(prefix),
							depth = depth,
						})
						local found: Nav.MenuAction<V>?
						for _, item in items do
							if item.divider ~= true and item.id == selectedId then
								found = item
								break
							end
						end
						if not found or not found.children then
							break
						end
						items = read(found.children, use)
						table.insert(prefix, selectedId)
					end
					return levels
				end,
				key = function(level: { id: string, items: { Nav.MenuItem<V> }, prefix: { string }, depth: number })
					return level.id
				end,
				render = function(
					source: ComposeTypes.ReadOnlyValue<{ id: string, items: { Nav.MenuItem<V> }, prefix: { string }, depth: number }>
				)
					local ancestorHeight = Compose.cell(0)
					local ancestor = ctx.styled(
						Host.ScrollingFrame "AncestorMenu" {
							ZIndex = 103,
							CanvasSize = D2.fromOffset(0, 0),
							AutomaticCanvasSize = E.AutomaticSize.Y,
							ScrollingDirection = E.ScrollingDirection.Y,
							ScrollBarThickness = 4,
							Selectable = false,
							BorderSizePixel = 0,
							Size = D2.fromOffset(280, 0),
							AutomaticSize = E.AutomaticSize.Y,
							Position = function(use: ComposeTypes.Use)
								local at = place(use)
								local _, insetTop, _, insetBottom = insets(use)
								local height = use(ancestorHeight)
								return D2.fromOffset(
									at.X - (#use(path) - use(source).depth + 1) * 288,
									math.clamp(
										at.Y,
										insetTop + 8,
										math.max(insetTop + 8, use(extent).Y - insetBottom - 8 - height)
									)
								)
							end,
							Host.UISizeConstraint {
								MaxSize = function(use: ComposeTypes.Use)
									local _, top, _, bottom = insets(use)
									return V2.new(280, math.max(44, use(extent).Y - top - bottom - 16))
								end,
							},
							Host.UIListLayout({
								FillDirection = E.FillDirection.Vertical,
								SortOrder = E.SortOrder.LayoutOrder,
							}),
							Host.UIPadding({
								PaddingTop = function(use: ComposeTypes.Use)
									return D.new(0, ctx.metric("space.xs", use))
								end,
								PaddingBottom = function(use: ComposeTypes.Use)
									return D.new(0, ctx.metric("space.xs", use))
								end,
								PaddingLeft = function(use: ComposeTypes.Use)
									return D.new(0, ctx.metric("space.xs", use))
								end,
								PaddingRight = function(use: ComposeTypes.Use)
									return D.new(0, ctx.metric("space.xs", use))
								end,
							}),
							Compose.keyed({
								from = function(use: ComposeTypes.Use)
									return use(source).items
								end,
								key = function(item: Nav.MenuItem<V>, index: number)
									return item.id or index
								end,
								render = function(
									row: ComposeTypes.ReadOnlyValue<Nav.MenuItem<V>>,
									index: ComposeTypes.ReadOnlyValue<number>
								)
									return menuRow.ancestor(row, index, source, rowState)
								end,
							}),
						},
						"menu"
					)
					local ancestorSize = ctx.observe.AbsoluteSize(ancestor)
					Compose.watch(function(use: ComposeTypes.Use)
						ancestorHeight:set(use(ancestorSize).Y)
					end)
					return ancestor
				end,
			}),
		})
		return modal
	end
	return menuPanel
end
