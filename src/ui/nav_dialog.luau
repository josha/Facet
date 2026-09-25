--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local Overlay = require("./overlay_types")
local Inputs = require("./input_types")
local ComposeTypes = require("../vendor/compose/core")
local parts = require("./overlay_parts")

type Controls = {
	Dialog: Types.Constructor<Overlay.DialogSpec, Frame>,
	Button: Types.Constructor<Inputs.ButtonProps, TextButton>,
}

local KEYS = {
	"isPresented",
	"onPresentedChange",
	"onDismiss",
	"title",
	"content",
	"hero",
	"actionLabel",
	"actions",
	"actionLayout",
	"closeButton",
	"width",
	"contentSelectable",
}
local DIALOG = table.freeze({ enter = 0.2, exit = 0.15 })

return function(ctx: Types.Context, UI: Controls, surfaces: Nav.Surfaces): ()
	local Compose, Host, runtime, read = ctx.Compose, ctx.Host, ctx.runtime, ctx.read
	local E, D2, V2 = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2

	local function blank(value: unknown): boolean
		return type(value) ~= "string" or string.match(value, "%S") == nil
	end

	local function keyboardHeight(input: UserInputService?): (ComposeTypes.Use) -> number
		if input == nil or not input.GetPropertyChangedSignal then
			return function()
				return 0
			end
		end
		local visible = ctx.observe(input, "OnScreenKeyboardVisible")
		local size = ctx.observe(input, "OnScreenKeyboardSize")
		return function(use: ComposeTypes.Use): number
			local extent = use(size)
			return if use(visible) == true and typeof(extent) == "Vector2" then (extent :: Vector2).Y else 0
		end
	end

	UI.Dialog = ctx.construct("Dialog", function(spec: Overlay.DialogSpec): Frame
		local where = "UI.Dialog"
		if spec.isPresented == nil then
			error(`Facet {where}: isPresented is required; it is the caller's boolean fact`, 0)
		end
		for _, key in { "onPresentedChange", "onDismiss" } do
			local value = (spec :: { [unknown]: unknown })[key]
			if value ~= nil and type(value) ~= "function" then
				error(`Facet {where}: {key} must be a function`, 0)
			end
		end
		if spec.closeButton ~= nil and type(spec.closeButton) ~= "boolean" then
			error(`Facet {where}: closeButton must be true or false`, 0)
		end
		local closeButton = spec.closeButton ~= false
		if closeButton and spec.onPresentedChange == nil then
			error(
				`Facet {where}: the close button proposes a close and needs onPresentedChange. `
					.. "Without it, set closeButton = false. The backdrop and Cancel then do nothing.",
				0
			)
		end
		if spec.width ~= nil and parts.WIDTHS[spec.width] == nil then
			error(`Facet {where}: width must be automatic, narrow or wide`, 0)
		end
		if
			spec.actionLayout ~= nil
			and spec.actionLayout ~= "automatic"
			and spec.actionLayout ~= "row"
			and spec.actionLayout ~= "stacked"
		then
			error(`Facet {where}: actionLayout must be automatic, row or stacked`, 0)
		end
		if spec.contentSelectable ~= nil and type(spec.contentSelectable) ~= "boolean" then
			error(`Facet {where}: contentSelectable must be true or false`, 0)
		end
		if spec.content ~= nil and type(spec.content) ~= "function" then
			error(`Facet {where}: content must be a factory that returns the body`, 0)
		end
		for _, key in { "title", "actionLabel" } do
			local value = (spec :: { [unknown]: unknown })[key]
			if value ~= nil and not parts.bound(ctx, value, "string") then
				error(`Facet {where}: {key} must be a string or a bound string`, 0)
			end
		end
		parts.checkMedia(where, spec.hero)
		local actions: { Overlay.Action } = spec.actions or {}
		parts.checkActions(ctx, where, spec.actions, math.huge)
		local cancelAction: Overlay.Action? = nil
		for _, action in actions do
			if action.role == "cancel" then
				cancelAction = action
			end
		end
		local function draws(value: unknown): boolean
			return value ~= nil and not (type(value) == "string" and blank(value))
		end
		if
			not draws(spec.title)
			and not draws(spec.actionLabel)
			and spec.hero == nil
			and spec.content == nil
			and #actions == 0
		then
			error(`Facet {where}: nothing to show. Supply a title, content, hero, actionLabel or actions`, 0)
		end

		local owner = assert(Compose.currentOwner())
		local root = Host.Frame(
			ctx.props(spec, KEYS, { Name = "Dialog", BackgroundTransparency = 1, Size = D2.fromOffset(0, 0) })
		)
		local function wanted(): boolean
			return read(spec.isPresented) == true
		end
		local condition = function(use: ComposeTypes.Use): boolean
			return read(spec.isPresented, use) == true
		end
		local closing: Overlay.DialogDismissReason? = nil
		local disposed = false
		local function report(reason: Overlay.DialogDismissReason)
			if spec.onDismiss then
				spec.onDismiss(reason)
			end
		end
		local function propose(nextValue: boolean, reason: Overlay.DialogDismissReason): boolean
			local change = spec.onPresentedChange
			if change == nil then
				return false
			end
			if not nextValue then
				closing = reason
			end
			local accepted = false
			parts.call(change, function()
				accepted = wanted() == nextValue
				if not accepted then
					closing = nil
				end
			end, nextValue)
			return accepted
		end
		local function press(action: Overlay.Action)
			if not parts.usable(ctx, action) then
				return
			end
			closing = "action"
			parts.call(action.onActivate, function()
				if wanted() then
					closing = nil
				end
			end)
		end
		local function cancel()
			if cancelAction and parts.usable(ctx, cancelAction) then
				press(cancelAction)
			else
				propose(false, "cancel")
			end
		end
		local input = surfaces.service("UserInputService")
		surfaces.attach(root, {
			surfaces.overlay(root, condition, function(phase: Nav.PresencePhase?)
				local layer = assert(root:FindFirstAncestorWhichIsA("LayerCollector"))
				local extent = ctx.observe(layer, "AbsoluteSize")
				local keyboard = keyboardHeight(input)
				local function margin(use: ComposeTypes.Use?): number
					return ctx.metric("space.m", use)
				end
				local function widthPx(use: ComposeTypes.Use): number
					return math.max(0, math.min(parts.width(ctx, spec.width, use), use(extent).X - 2 * margin(use)))
				end
				local function roomPx(use: ComposeTypes.Use): number
					return math.max(0, use(extent).Y - keyboard(use) - 4 * margin(use))
				end
				local regions: { GuiObject } = {}
				if spec.hero then
					table.insert(regions, parts.media(ctx, spec.hero, "Hero"))
				end
				local header: { Types.Child } = {}
				if spec.title ~= nil then
					local title = spec.title
					local heading = ctx.text({
						Name = "Title",
						Text = function(use: ComposeTypes.Use)
							return read(title, use) or ""
						end,
						TextWrapped = true,
						Size = D2.new(1, 0, 0, 0),
						AutomaticSize = E.AutomaticSize.Y,
						Visible = function(use: ComposeTypes.Use)
							return not blank(read(title, use))
						end,
						Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }),
					})
					heading:AddTag("facet-type-heading")
					table.insert(header, heading)
				end
				if closeButton then
					table.insert(
						header,
						UI.Button "Close" {
							name = "Close",
							icon = "close",
							Size = D2.fromOffset(44, 44),
							AutomaticSize = E.AutomaticSize.None,
							onActivate = function()
								propose(false, "close")
							end,
						}
					)
				end
				if #header > 0 then
					local row = ctx.row(
						header,
						{ Name = "Header", Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y }
					)
					local layout = row:FindFirstChildWhichIsA("UIListLayout") :: UIListLayout?
					if layout then
						layout.VerticalAlignment = E.VerticalAlignment.Center
					end
					table.insert(regions, row)
				end
				local body: ScrollingFrame? = nil
				local bodyContent: Frame? = nil
				if spec.content then
					local scroller, flow = parts.scroller(
						ctx,
						{
							Name = "Body",
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							ScrollBarThickness = 4,
							ScrollingDirection = E.ScrollingDirection.Y,
							Selectable = false,
						},
						{ Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder }), spec.content() },
						{ name = "Content" }
					)
					bodyContent = flow
					body = scroller
					table.insert(regions, assert(body))
				end
				if spec.actionLabel ~= nil then
					local label = spec.actionLabel
					table.insert(
						regions,
						ctx.styled(
							ctx.text({
								Name = "ActionLabel",
								Text = function(use: ComposeTypes.Use)
									return read(label, use) or ""
								end,
								TextWrapped = true,
								Size = D2.new(1, 0, 0, 0),
								AutomaticSize = E.AutomaticSize.Y,
								Visible = function(use: ComposeTypes.Use)
									return not blank(read(label, use))
								end,
							}),
							"secondary"
						)
					)
				end
				local group: parts.ActionGroup? = nil
				if #actions > 0 then
					group = parts.actions(ctx, UI, actions, spec.actionLayout, function(use: ComposeTypes.Use)
						return widthPx(use) - 2 * margin(use)
					end, press)
					table.insert(regions, assert(group).frame)
				end
				local naturalSize: ComposeTypes.Readable<Vector2> = if bodyContent
					then ctx.observe(bodyContent, "AbsoluteSize")
					else Compose.cell(V2.zero)
				local room = parts.room(ctx, regions, body, function(use: ComposeTypes.Use): number
					return use(naturalSize).Y
				end, function(use: ComposeTypes.Use)
					return roomPx(use)
				end, false)
				if body and spec.contentSelectable ~= false then
					local scroller = body
					runtime.decorate(scroller, { Selectable = room.overflowing })
					scroller:SetAttribute("FacetSelectionOwner", true)
					local gui = surfaces.service("GuiService")
					local selected: ComposeTypes.Readable<GuiObject?> = if gui
						then ctx.observe(gui, "SelectedObject")
						else Compose.cell(nil :: GuiObject?)
					local canvas = ctx.observe(scroller, "CanvasPosition")
					local window = ctx.observe(scroller, "AbsoluteWindowSize")
					local content = ctx.observe(assert(bodyContent), "AbsoluteSize")
					local function step(direction: number)
						local box = scroller.AbsoluteWindowSize.Y
						local limit = math.max(0, scroller.AbsoluteCanvasSize.Y - box)
						local at = scroller.CanvasPosition
						local target = math.clamp(at.Y + direction * math.max(1, box * 0.8), 0, limit)
						scroller.CanvasPosition = V2.new(at.X, target)
					end
					local function bind(name: string, direction: number, keys: { Enum.KeyCode })
						ctx.action(scroller, name, keys, function(use: ComposeTypes.Use)
							if use(selected) ~= (scroller :: GuiObject) or not use(room.overflowing) then
								return false
							end
							local y = use(canvas).Y
							local limit = math.max(0, use(content).Y - use(window).Y)
							return if direction > 0 then y < limit - 0.5 else y > 0.5
						end, function()
							step(direction)
						end, { priority = 3000, capture = true })
					end
					bind("DialogBodyDown", 1, { E.KeyCode.Down, E.KeyCode.DPadDown })
					bind("DialogBodyUp", -1, { E.KeyCode.Up, E.KeyCode.DPadUp })
				end
				local shown = surfaces.appearance(phase, DIALOG)
				local panel = ctx.styled(
					Host.CanvasGroup({
						Name = "Panel",
						AnchorPoint = V2.new(0.5, 0.5),
						Position = function(use: ComposeTypes.Use)
							return D2.new(0.5, 0, 0.5, -keyboard(use) / 2)
						end,
						Size = function(use: ComposeTypes.Use)
							return D2.fromOffset(widthPx(use), 0)
						end,
						AutomaticSize = E.AutomaticSize.Y,
						BackgroundTransparency = 0,
						BorderSizePixel = 0,
						GroupTransparency = function(use: ComposeTypes.Use)
							return 1 - shown(use)
						end,
						room.frame :: Instance,
						ctx.padding(16, 16),
						ctx.corner(),
						Host.UIScale "PresentationScale" {
							Scale = function(use: ComposeTypes.Use)
								return 0.94 + 0.06 * shown(use)
							end,
						} :: Instance,
					}),
					"dialog"
				)
				ctx.styled(panel, "panel")
				surfaces.skin(panel, "panel")
				local initial: string? = if cancelAction and parts.usable(ctx, cancelAction)
					then cancelAction.id
					else nil
				if initial == nil then
					for _, action in actions do
						if action.role ~= "destructive" and parts.usable(ctx, action) then
							initial = action.id
							break
						end
					end
				end
				Compose.cleanup(function()
					if disposed or owner.isDisposed() then
						closing = nil
						report("cancel")
						return
					end
					local reason: Overlay.DialogDismissReason = closing or "cancel"
					closing = nil
					if wanted() then
						propose(false, "cancel")
						closing = nil
						report("cancel")
					else
						report(reason)
					end
				end)
				return surfaces.modal(function()
					return panel
				end, function()
					cancel()
				end, {
					Name = "DialogModal",
					initialFocus = initial,
					onOutside = function()
						propose(false, "outside")
					end,
					exiting = if phase then phase.exiting else nil,
					appearance = shown,
				})
			end, { motion = DIALOG }),
		})
		Compose.cleanup(function()
			disposed = true
		end)
		return root
	end)
end
