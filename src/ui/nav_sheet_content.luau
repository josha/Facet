--!strict
local ControlTypes = require("./control_types")
local Types = require("./types")
local Nav = require("./navigation_types")
local Overlay = require("./overlay_types")
local ComposeTypes = require("../vendor/compose/core")
local parts = require("./overlay_parts")
local NavigationProps = require("./navigation_props")
local sheetGesture = require("./nav_sheet_gesture")

export type SheetContent = {
	plaqued: ComposeTypes.Cell<boolean>,
	usable: (Overlay.Action?) -> boolean,
	press: (Overlay.Action) -> (),
	panelWidth: ComposeTypes.Formula<number>,
	contentSize: ComposeTypes.Cell<Vector2>,
	room: parts.Room,
	entry: () -> GuiObject?,
}

return function(
	ctx: Types.Context,
	UI: ControlTypes.BuilderControls,
	surfaces: Nav.Surfaces
): (NavigationProps.SheetSpec, sheetGesture.Gesture) -> SheetContent
	local Compose, Host, runtime, read = ctx.Compose, ctx.Host, ctx.runtime, ctx.read
	local E, D2, V2 = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2
	return function(spec: NavigationProps.SheetSpec, gesture: sheetGesture.Gesture): SheetContent
		local grabber, canDismiss, close, unit, extent =
			gesture.grabber, gesture.canDismiss, gesture.close, gesture.unit, gesture.extent
		local pad, standing, hugHeight, tallest = gesture.pad, gesture.standing, gesture.hugHeight, gesture.tallest
		local regions: { GuiObject } = {}
		local plaqued = Compose.cell(false)
		local actionRegion: Frame? = nil
		local hero = spec.hero
		local sticky = hero ~= nil and hero.sticky == true
		local overHero = spec.header == false and hero ~= nil
		local closeCommand: TextButton? = nil
		local function showClose(use: ComposeTypes.Use?): boolean
			return spec.closeButton ~= false
				and (spec.closeButton ~= nil or (not gesture.showGrabber(use) and canDismiss(use)))
		end
		local function linkClose(button: TextButton): TextButton
			closeCommand = button
			button.SelectionOrder = -1
			return button
		end
		local function closeControl(): TextButton?
			local explicit = spec.closeButton
			local function activate()
				close("close")
			end
			if explicit == false then
				return nil
			end
			if explicit ~= nil and explicit ~= true then
				return linkClose(UI.Button "Close" {
					label = explicit :: Types.Value<string>,
					icon = "close",
					appearance = if overHero then "inverse" else "utility",
					LayoutOrder = 2,
					onActivate = activate,
				})
			end
			return linkClose(UI.Button "Close" {
				name = "Close",
				Visible = showClose,
				icon = "close",
				appearance = if overHero then "inverse" else nil,
				LayoutOrder = 2,
				Size = D2.fromOffset(44, 44),
				AutomaticSize = E.AutomaticSize.None,
				onActivate = activate,
			})
		end
		local function heroFrame(): Frame
			local current = assert(hero)
			local frame = parts.media(ctx, current, "Hero")
			if current.content then
				local children: { Types.Child } = {
					Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder }),
					Host.UIPadding({
						PaddingLeft = ctx.types.UDim.new(0, 16),
						PaddingRight = ctx.types.UDim.new(0, 16),
						PaddingBottom = ctx.types.UDim.new(0, 12),
					}),
				}
				if overHero then
					table.insert(
						children,
						Host.Frame "Strip" {
							BackgroundTransparency = 1,
							LayoutOrder = 0,
							Size = function(use: ComposeTypes.Use)
								return D2.new(1, 0, 0, math.max(44, ctx.metric("targetSizes.minimum", use)) + 8)
							end,
						}
					)
				end
				local content = current.content
				local node: Instance = if type(content) == "function" then content() else content :: Instance
				if node:IsA("GuiObject") then
					runtime.decorate(node, { LayoutOrder = 1 })
				end
				table.insert(children, node)
				surfaces.attach(frame, {
					Host.Frame "Art" {
						BackgroundTransparency = 1,
						Size = D2.fromScale(1, 1),
						table.unpack(children),
					},
				})
			end
			if overHero then
				local close = closeControl()
				if close then
					surfaces.attach(frame, {
						Host.Frame "Utilities" {
							BackgroundTransparency = 1,
							AnchorPoint = V2.new(1, 0),
							Position = D2.new(1, -8, 0, 8),
							Size = D2.fromOffset(0, 0),
							AutomaticSize = E.AutomaticSize.XY,
							ZIndex = 3,
							close,
						},
					})
				end
			end
			return frame
		end
		if sticky then
			table.insert(regions, heroFrame())
		end
		if not overHero then
			local header: { Types.Child } = {}
			if spec.header == nil then
				table.insert(
					header,
					ctx.styled(
						ctx.text({
							Name = "Title",
							LayoutOrder = 1,
							Visible = function(use: ComposeTypes.Use)
								return not use(plaqued)
							end,
							Text = function(use: ComposeTypes.Use)
								return read(spec.title, use) or ""
							end,
							TextWrapped = true,
							Size = D2.new(1, 0, 0, 0),
							AutomaticSize = E.AutomaticSize.Y,
							Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }),
						}),
						"type-heading"
					)
				)
			elseif spec.header ~= false then
				local custom = spec.header
				local node: Instance = if type(custom) == "function" then custom() else custom :: Instance
				if node:IsA("GuiObject") then
					surfaces.attach(node, { Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }) })
				end
				table.insert(header, node)
			end
			local close = closeControl()
			if close then
				table.insert(header, close)
			end
			if #header > 0 then
				local row: Types.FrameNativeProps = {
					Name = "Header",
					BackgroundTransparency = 1,
					Size = D2.new(1, 0, 0, 0),
					AutomaticSize = E.AutomaticSize.Y,
				}
				row[#row + 1] = Host.UIListLayout({
					FillDirection = E.FillDirection.Horizontal,
					HorizontalAlignment = E.HorizontalAlignment.Right,
					VerticalAlignment = E.VerticalAlignment.Center,
					SortOrder = E.SortOrder.LayoutOrder,
					Padding = ctx.types.UDim.new(0, 8),
				})
				for _, child in header do
					row[#row + 1] = child
				end
				table.insert(regions, Host.Frame(row))
			end
		end
		local inset = if spec.contentInset == "none" then 0 else 8
		local panelWidth = Compose.formula(function(use: ComposeTypes.Use): number
			return math.max(0, math.min(parts.width(ctx, spec.width, use), use(extent).X))
		end)
		local function contentPadding(): UIPadding
			local function horizontal(use: ComposeTypes.Use): UDim
				local growth = math.max(0, ctx.metric("motion.materialize.lift", use) - 1)
				local width = math.max(0, use(panelWidth) - pad("left", use) - pad("right", use))
				return if width * growth > inset then ctx.types.UDim.new(growth, 0) else ctx.types.UDim.new(0, inset)
			end
			return Host.UIPadding {
				PaddingLeft = if inset == 0 then ctx.types.UDim.new(0, 0) else horizontal,
				PaddingRight = if inset == 0 then ctx.types.UDim.new(0, 0) else horizontal,
				PaddingTop = ctx.types.UDim.new(0, inset),
				PaddingBottom = ctx.types.UDim.new(0, inset),
			}
		end
		local bodyLayout = Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder })
		local bodyPadding = contentPadding()
		local bodyChildren: { Types.Child } = { bodyLayout }
		local content: Instance = if type(spec.content) == "function"
			then (spec.content :: () -> Instance)()
			else spec.content :: Instance
		local scrollViewport: Frame? = nil
		local bodyContent = content
		if content:IsA("GuiObject") and content.Size.Y.Scale > 0 then
			scrollViewport = Host.Frame "SheetScrollViewport" {
				BackgroundTransparency = 1,
				Size = D2.new(1, 0, 0, 0),
				content,
			}
			bodyContent = assert(scrollViewport)
		end
		if hero and not sticky then
			table.insert(bodyChildren, heroFrame())
			local inner: Types.FrameNativeProps = {
				Name = "Inset",
				BackgroundTransparency = 1,
				LayoutOrder = 2,
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
			}
			inner[#inner + 1] = Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder })
			inner[#inner + 1] = contentPadding()
			inner[#inner + 1] = bodyContent
			table.insert(bodyChildren, Host.Frame(inner))
		else
			table.insert(bodyChildren, bodyPadding)
			table.insert(bodyChildren, bodyContent)
		end
		local flex = Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill })
		local bodyProps: Types.ScrollingFrameNativeProps = {
			Name = "SheetContent",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollingDirection = E.ScrollingDirection.Y,
			ScrollBarThickness = 6,
			ClipsDescendants = true,
			Selectable = false,
			SelectionGroup = false,
			flex :: Instance,
		}
		local body = parts.scroller(ctx, bodyProps, bodyChildren, { name = "SheetFlow" })
		if scrollViewport then
			local window = ctx.observe.AbsoluteWindowSize(body)
			runtime.decorate(scrollViewport, {
				Size = function(use: ComposeTypes.Use): UDim2
					return D2.new(1, 0, 0, math.max(0, use(window).Y / use(unit) - inset * 2))
				end,
			})
		end
		local function linkDismissal()
			local entry: GuiObject? = nil
			local command: GuiObject? = nil
			local previousUp: GuiObject? = nil
			local function linkContent(use: ComposeTypes.Use?)
				local nextCommand = if gesture.showGrabber(use)
					then grabber
					elseif showClose(use) then closeCommand
					else nil
				local nextEntry = surfaces.firstSelectable(body)
					or (if actionRegion then surfaces.firstSelectable(actionRegion) else nil)
				if nextEntry == nextCommand then
					nextEntry = surfaces.firstSelectable(content)
				end
				if nextEntry == entry and nextCommand == command then
					return
				end
				if command and entry and entry.NextSelectionUp == command then
					local links = (entry :: unknown) :: { NextSelectionUp: GuiObject? }
					links.NextSelectionUp = previousUp
				end
				if command then
					local links = (
						command :: unknown
					) :: { NextSelectionDown: GuiObject?, NextSelectionRight: GuiObject? }
					links.NextSelectionDown, links.NextSelectionRight = nil, nil
				end
				entry = nextEntry
				command = nextCommand
				if command then
					local outgoing = (
						command :: unknown
					) :: { NextSelectionDown: GuiObject?, NextSelectionRight: GuiObject? }
					outgoing.NextSelectionDown, outgoing.NextSelectionRight = nextEntry, nextEntry
				end
				if nextEntry and command then
					previousUp = nextEntry.NextSelectionUp
					nextEntry.NextSelectionUp = command
				end
			end
			Compose.watch(linkContent)
			runtime.connect(body, "DescendantAdded", function()
				linkContent(nil)
			end)
			Compose.cleanup(function()
				if command and entry and entry.NextSelectionUp == command then
					local links = (entry :: unknown) :: { NextSelectionUp: GuiObject? }
					links.NextSelectionUp = previousUp
				end
			end)
		end
		table.insert(regions, body)
		local function usable(action: Overlay.Action?): boolean
			return parts.usable(ctx, action)
		end
		local function press(action: Overlay.Action)
			if usable(action) then
				action.onActivate()
			end
		end
		local actions = spec.actions or {}
		if #actions > 0 then
			local region = parts.actions(ctx, UI, actions, spec.actionLayout, function(use: ComposeTypes.Use)
				return math.max(0, use(panelWidth) - pad("left", use) - pad("right", use))
			end, press).frame
			actionRegion = region
			table.insert(regions, region)
		end
		linkDismissal()
		local contentSize = ctx.observe.AbsoluteContentSize(bodyLayout)
		local extra = if hero == nil or sticky then inset * 2 else 0
		local function natural(use: ComposeTypes.Use): number
			return use(contentSize).Y / use(unit) + extra
		end
		local chrome = function(use: ComposeTypes.Use): number
			return pad("top", use) + pad("bottom", use)
		end
		local room = parts.room(ctx, regions, body, natural, function(use: ComposeTypes.Use): number
			return math.max(0, standing(use) - chrome(use))
		end, true, unit)
		runtime.decorate(flex, {
			FlexMode = function(use: ComposeTypes.Use)
				return if use(room.tight) then E.UIFlexMode.None else E.UIFlexMode.Fill
			end,
		})
		Compose.watch(function(use: ComposeTypes.Use)
			local want = natural(use) + use(room.pinned) + chrome(use) + 8
			local previous = hugHeight:peek()
			if want > 0 and (previous == nil or math.abs(previous - want) > 0.5) then
				hugHeight:set(want)
			end
		end)
		if spec.scrollPolicy == "atLargestDetent" then
			runtime.decorate(body, {
				ScrollingEnabled = function(use: ComposeTypes.Use)
					return use(tallest) and not use(room.tight)
				end,
				Active = tallest,
			})
		end
		local function entry(): GuiObject?
			local wanted = spec.initialFocus
			local name = if type(wanted) == "function" then wanted() else wanted
			if name then
				local node = body:FindFirstChild(name, true)
					or (if actionRegion then actionRegion:FindFirstChild(name, true) else nil)
				local found = if node then surfaces.firstSelectable(node) else nil
				if found then
					return found
				end
			end
			return surfaces.firstSelectable(body)
				or (if actionRegion then surfaces.firstSelectable(actionRegion) else nil)
		end
		return {
			entry = entry,
			plaqued = plaqued,
			usable = usable,
			press = press,
			panelWidth = panelWidth,
			contentSize = contentSize,
			room = room,
		}
	end
end
