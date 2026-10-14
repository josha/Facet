--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local Overlay = require("./overlay_types")
local ComposeTypes = require("../vendor/compose/core")
local parts = require("./overlay_parts")
local InputProps = require("./input_props")
local NavigationProps = require("./navigation_props")
local sheetGesture = require("./nav_sheet_gesture")

type Controls = {
	Button: Types.Constructor<InputProps.ButtonProps, TextButton>,
}

export type SheetContent = {
	plaqued: ComposeTypes.Cell<boolean>,
	usable: (Overlay.Action?) -> boolean,
	press: (Overlay.Action) -> (),
	panelWidth: ComposeTypes.Formula<number>,
	contentSize: ComposeTypes.Cell<Vector2>,
	room: parts.Room,
}

return function(
	ctx: Types.Context,
	UI: Controls,
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
		local hero = spec.hero
		local sticky = hero ~= nil and hero.sticky == true
		local overHero = spec.header == false and hero ~= nil
		local closeCommand: TextButton? = nil
		local function linkClose(button: TextButton): TextButton
			closeCommand = button
			button.SelectionOrder = -1
			grabber.NextSelectionDown = button
			grabber.NextSelectionRight = button
			button.NextSelectionUp = grabber
			button.NextSelectionLeft = grabber
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
				return linkClose(UI.Button {
					Name = "Close",
					label = explicit :: Types.Value<string>,
					appearance = if overHero then "inverse" else "link",
					LayoutOrder = 2,
					onActivate = activate,
				})
			end
			return linkClose(UI.Button {
				Name = "Close",
				name = "Close",
				Visible = if explicit == nil then canDismiss else true,
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
						Host.Frame({
							Name = "Strip",
							BackgroundTransparency = 1,
							LayoutOrder = 0,
							Size = function(use: ComposeTypes.Use)
								return D2.new(1, 0, 0, math.max(44, ctx.metric("targetSizes.minimum", use)) + 8)
							end,
						})
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
		local bodyLayout = Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder })
		local bodyPadding = ctx.padding(inset, inset)
		local bodyChildren: { Types.Child } = { bodyLayout }
		local content: Instance = if type(spec.content) == "function"
			then (spec.content :: () -> Instance)()
			else spec.content :: Instance
		local scrollViewport: Frame? = nil
		local bodyContent = content
		if content:IsA("ScrollingFrame") and content.Size.Y.Scale > 0 then
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
			inner[#inner + 1] = ctx.padding(inset, inset)
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
		if closeCommand then
			local command = closeCommand
			local entry: GuiObject? = nil
			local previousUp: GuiObject? = nil
			local function linkContent()
				local nextEntry = surfaces.firstSelectable(body)
				if nextEntry == entry then
					return
				end
				if entry and entry.NextSelectionUp == command then
					local links = (entry :: unknown) :: { NextSelectionUp: GuiObject? }
					links.NextSelectionUp = previousUp
				end
				entry = nextEntry
				local outgoing = (command :: unknown) :: { NextSelectionDown: GuiObject? }
				outgoing.NextSelectionDown = nextEntry
				if nextEntry then
					previousUp = nextEntry.NextSelectionUp
					nextEntry.NextSelectionUp = command
				end
			end
			linkContent()
			runtime.connect(body, "DescendantAdded", linkContent)
			Compose.cleanup(function()
				if entry and entry.NextSelectionUp == command then
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
		local panelWidth = Compose.formula(function(use: ComposeTypes.Use): number
			return math.max(0, math.min(parts.width(ctx, spec.width, use), use(extent).X))
		end)
		local actions = spec.actions or {}
		if #actions > 0 then
			table.insert(
				regions,
				parts.actions(ctx, UI, actions, spec.actionLayout, function(use: ComposeTypes.Use)
					return math.max(0, use(panelWidth) - pad("left", use) - pad("right", use))
				end, press).frame
			)
		end
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
		return {
			plaqued = plaqued,
			usable = usable,
			press = press,
			panelWidth = panelWidth,
			contentSize = contentSize,
			room = room,
		}
	end
end
