--!strict
local Types = require("./types")
local Content = require("./content_types")
local Inputs = require("./input_types")
local Nav = require("./navigation_types")
local ComposeTypes = require("../vendor/compose/core")
local values = require("./content_values")
local parts = require("./overlay_parts")
local reducedMotion = require("./motion")

local LIFT = 1.04
local ACTION_KEYS: { [string]: boolean } = { label = true, icon = true, onActivate = true, enabled = true, busy = true }
local MENU_KEYS: { [string]: boolean } = { items = true, label = true }

return function(
	ctx: Types.Context,
	UI: {
		Card: Types.Constructor<Content.CardSpec, Frame>,
		Button: Types.Constructor<Inputs.ButtonProps, TextButton>,
		Menu: Nav.MenuConstructor,
	}
): ()
	local Host, Compose, read, runtime = ctx.Host, ctx.Compose, ctx.read, ctx.runtime
	local E, D2, D = ctx.types.Enum, ctx.types.UDim2, ctx.types.UDim
	local function nonempty(value: unknown): boolean
		return type(value) == "string" and string.find(value, "%S") ~= nil
	end
	local function text(value: unknown): boolean
		return type(value) == "string"
	end
	local function within(node: Instance?, ancestor: Instance): boolean
		while node do
			if node == ancestor then
				return true
			end
			node = node.Parent
		end
		return false
	end

	UI.Card = ctx.construct("Card", function(spec: Content.CardSpec): Frame
		assert(
			spec.artwork == nil or type(spec.artwork) == "function",
			"Facet UI.Card: artwork must be a function that returns a GuiObject"
		)
		assert(
			nonempty(read(spec.image)) or (spec.artwork ~= nil and spec.image == nil),
			"Facet UI.Card: image is required: a nonempty image string, or artwork"
		)
		assert(nonempty(read(spec.title)), "Facet UI.Card: title is required: a nonempty string")
		assert(spec.caption == nil or text(read(spec.caption)), "Facet UI.Card: caption must be a string")
		local ratio = spec.imageAspectRatio or 16 / 9
		assert(
			type(ratio) == "number" and ratio > 0 and ratio < math.huge,
			"Facet UI.Card: imageAspectRatio must be a positive finite number"
		)
		assert(
			spec.imageFraming == nil or spec.imageFraming == "fit" or spec.imageFraming == "crop",
			"Facet UI.Card: imageFraming must be fit or crop"
		)
		local reveal = spec.reveal or "automatic"
		assert(reveal == "automatic" or reveal == "always", "Facet UI.Card: reveal must be automatic or always")
		assert(
			spec.onActivate == nil or type(spec.onActivate) == "function",
			"Facet UI.Card: onActivate must be a function"
		)
		assert(
			spec.browseTarget == nil or type(spec.browseTarget) == "function",
			"Facet UI.Card: browseTarget must be a function that returns the browse stop"
		)
		local primary = spec.primaryAction
		if primary ~= nil then
			assert(type(primary) == "table", "Facet UI.Card: primaryAction must be a table")
			for key in (primary :: unknown) :: { [string]: unknown } do
				assert(ACTION_KEYS[key], `Facet UI.Card: primaryAction has the unknown field '{key}'`)
			end
			assert(nonempty(read(primary.label)), "Facet UI.Card: primaryAction.label must be a nonempty string")
			assert(type(primary.onActivate) == "function", "Facet UI.Card: primaryAction.onActivate is required")
		end
		local menu = spec.menu
		if menu ~= nil then
			assert(type(menu) == "table", "Facet UI.Card: menu must be a table")
			for key in (menu :: unknown) :: { [string]: unknown } do
				assert(MENU_KEYS[key], `Facet UI.Card: menu has the unknown field '{key}'`)
			end
			assert(menu.items ~= nil, "Facet UI.Card: menu.items is required")
		end
		local checks = values(ctx, "Card")
		local title = checks.legal("title", spec.title, nonempty, "must be a nonempty string")
		local image = if spec.image == nil
			then ""
			else checks.legal("image", spec.image, nonempty, "must be a nonempty image string")
		local caption = checks.legal("caption", spec.caption or "", text, "must be a string")
		local enabled = function(use: ComposeTypes.Use?): boolean
			return read(spec.enabled, use) ~= false
		end
		local gui = ctx.config.services.GuiService
		local input = ctx.config.services.UserInputService
		local selected = if gui then ctx.observe.SelectedObject(gui) else Compose.cell(nil :: GuiObject?)
		local touchEnabled = if input then ctx.observe.TouchEnabled(input) else Compose.cell(false)
		local preferred = if input then ctx.observe.PreferredInput(input) else nil
		local function prefersTouch(use: ComposeTypes.Use): boolean
			return preferred ~= nil and use(preferred) == E.PreferredInput.Touch
		end
		local hovered, entered, menuOpen = Compose.cell(false), Compose.cell(false), Compose.cell(false)
		local pressingBody = Compose.cell(false)
		local reduced = reducedMotion(ctx)
		local root: Frame? = nil
		local primaryButton: TextButton?
		local moreTrigger: GuiObject?
		local actionStates = Compose.cell({} :: { ComposeTypes.Readable<boolean> })
		local function holding(button: GuiObject): ComposeTypes.Readable<boolean>
			local down = Compose.cell(false)
			local state = ctx.observe.GuiState(button)
			local function pointer(input: InputObject): boolean
				return input.UserInputType == E.UserInputType.MouseButton1
					or input.UserInputType == E.UserInputType.Touch
			end
			runtime.connect(button, "InputBegan", function(input: InputObject)
				if pointer(input) then
					down:set(true)
				end
			end)
			runtime.connect(button, "InputEnded", function(input: InputObject)
				if pointer(input) then
					down:set(false)
				end
			end)
			return Compose.formula(function(use: ComposeTypes.Use): boolean
				return use(down) or use(state) == E.GuiState.Press
			end)
		end
		local hasStop = spec.onActivate ~= nil or spec.browseTarget ~= nil
		local focusWithin = Compose.formula(function(use: ComposeTypes.Use): boolean
			local node, card = use(selected), root
			return node ~= nil and card ~= nil and within(node, card)
		end)
		local browsing = Compose.formula(function(use: ComposeTypes.Use): boolean
			local node = use(selected)
			local target: Instance? = if spec.browseTarget then spec.browseTarget() else nil
			return node ~= nil and target ~= nil and (node :: Instance) == target
		end)
		local pressing = Compose.formula(function(use: ComposeTypes.Use): boolean
			if use(pressingBody) then
				return true
			end
			for _, state in use(actionStates) do
				if use(state) then
					return true
				end
			end
			return false
		end)
		local engaged = Compose.formula(function(use: ComposeTypes.Use): boolean
			return use(hovered) or use(focusWithin) or use(pressing) or use(menuOpen) or use(entered) or use(browsing)
		end)
		local touch = function(use: ComposeTypes.Use): boolean
			return use(touchEnabled) == true or prefersTouch(use)
		end
		local revealed = Compose.formula(function(use: ComposeTypes.Use): boolean
			return reveal == "always" or not hasStop or touch(use) or use(engaged)
		end)
		local lifting = Compose.formula(function(use: ComposeTypes.Use): boolean
			if prefersTouch(use) then
				return false
			end
			return use(engaged)
		end)
		local liftTarget = Compose.formula(function(use: ComposeTypes.Use): number
			return if use(lifting) then LIFT else 1
		end)
		local spring = runtime.spring(function(use: ComposeTypes.Use)
			return use(liftTarget)
		end, { period = 0.2, damping = 1 })
		local scale = Compose.formula(function(use: ComposeTypes.Use): number
			return if reduced(use) then 1 else use(spring)
		end)
		local fade = runtime.tween(function(use: ComposeTypes.Use)
			return if use(revealed) then 1 else 0
		end, { seconds = 0.15 })
		local function eligible(): GuiObject?
			local card = root
			if not enabled() or card == nil or card.Parent == nil then
				return nil
			end
			if primaryButton and primary and read(primary.enabled) ~= false and read(primary.busy) ~= true then
				return primaryButton
			end
			if moreTrigger then
				return moreTrigger
			end
			return nil
		end
		local function restore()
			if not gui then
				return
			end
			local target = if spec.browseTarget then spec.browseTarget() else nil
			if target and target.Parent then
				gui.SelectedObject = target
			elseif root and (root :: Frame).Parent then
				local body = (root :: Frame):FindFirstChild("Body")
				if body and body:IsA("GuiObject") and body.Selectable then
					gui.SelectedObject = body
				end
			end
		end
		local function enterActions(): boolean
			local first = eligible()
			if first == nil then
				return false
			end
			entered:set(true)
			if gui then
				gui.SelectedObject = first
			end
			return true
		end
		local function leaveActions()
			if not entered:peek() then
				return
			end
			entered:set(false)
			if gui and root and within(gui.SelectedObject, root :: Frame) then
				restore()
			end
		end
		if spec.controls then
			spec.controls.enterActions = enterActions
			spec.controls.leaveActions = leaveActions
			spec.controls.engaged = engaged
			spec.controls.revealed = revealed
			spec.controls.scale = scale
			spec.controls.lifting = lifting
			spec.controls.diagnostics = checks.list
		end
		local cardWidth = Compose.cell(0)
		local artwork = Host.ImageLabel({
			Name = "Artwork",
			LayoutOrder = 1,
			BackgroundTransparency = 1,
			Image = image,
			Size = function(use: ComposeTypes.Use): UDim2
				return D2.new(1, 0, 0, math.round(use(cardWidth) / ratio))
			end,
			ScaleType = if spec.imageFraming == "fit" then E.ScaleType.Fit else E.ScaleType.Crop,
		})
		if spec.artwork then
			local build = spec.artwork
			runtime.mount(function()
				local live = build()
				assert(parts.instance(live) and live:IsA("GuiObject"), "Facet UI.Card: artwork must return a GuiObject")
				runtime.decorate(live, { Size = D2.fromScale(1, 1) })
				return live
			end, artwork)
		end
		local titleLabel = ctx.text({
			Name = "Title",
			LayoutOrder = 2,
			Text = title,
			Size = D2.fromScale(1, 0),
			AutomaticSize = E.AutomaticSize.Y,
			TextWrapped = true,
		})
		titleLabel:AddTag("facet-type-label")
		local function inset(bottom: boolean): UIPadding
			local function side(use: ComposeTypes.Use): UDim
				return D.new(0, ctx.metric("space.s", use))
			end
			return Host.UIPadding({
				PaddingLeft = side,
				PaddingRight = side,
				PaddingBottom = if bottom then side else nil,
			})
		end
		runtime.mount(function()
			return inset(false)
		end, titleLabel)
		local captionLabel = ctx.text({
			Name = "Caption",
			LayoutOrder = 3,
			Text = caption,
			Visible = function(use: ComposeTypes.Use): boolean
				return use(caption) ~= ""
			end,
			Size = D2.fromScale(1, 0),
			AutomaticSize = E.AutomaticSize.Y,
			TextWrapped = true,
		})
		captionLabel:AddTag("facet-type-caption")
		captionLabel:AddTag("facet-secondary")
		runtime.mount(function()
			return inset(true)
		end, captionLabel)
		local bodyChildren: { Types.Child } = {
			Host.UIListLayout({
				FillDirection = E.FillDirection.Vertical,
				SortOrder = E.SortOrder.LayoutOrder,
				Padding = function(use: ComposeTypes.Use)
					return D.new(0, ctx.metric("space.xs", use))
				end,
			}) :: Types.Child,
			artwork :: Types.Child,
			titleLabel :: Types.Child,
			captionLabel :: Types.Child,
		}
		local body: GuiObject
		if spec.onActivate then
			local onActivate = spec.onActivate
			local props: Inputs.ButtonProps = {
				Name = "Body",
				LayoutOrder = 1,
				label = "",
				name = title,
				Size = D2.fromScale(1, 0),
				AutomaticSize = E.AutomaticSize.Y,
				enabled = enabled,
				onActivate = function(input: InputObject?)
					onActivate(input)
				end,
				onPointerDown = function()
					pressingBody:set(true)
				end,
				onPointerUp = function()
					pressingBody:set(false)
				end,
				onPointerCancel = function()
					pressingBody:set(false)
				end,
			}
			for _, child in bodyChildren do
				table.insert(props, child)
			end
			local button = UI.Button(props)
			button:AddTag("facet-panel")
			body = button
			runtime.mount(function()
				return Host.UIShadow({
					Name = "LiftShadow",
					Enabled = lifting,
				})
			end, button)
		else
			local props: Types.FrameNativeProps = {
				Name = "Body",
				LayoutOrder = 1,
				Size = D2.fromScale(1, 0),
				AutomaticSize = E.AutomaticSize.Y,
				Attributes = {
					label = title,
				} :: Types.Attributes,
			}
			for _, child in bodyChildren do
				table.insert(props, child)
			end
			body = ctx.styled(Host.Frame(props), "panel")
		end
		local actionEnabled = function(use: ComposeTypes.Use?): boolean
			return enabled(use) and read(revealed, use)
		end
		local rowChildren: { Types.Child } = {
			Host.UIListLayout({
				FillDirection = E.FillDirection.Horizontal,
				SortOrder = E.SortOrder.LayoutOrder,
				VerticalAlignment = E.VerticalAlignment.Center,
				Padding = function(use: ComposeTypes.Use)
					return D.new(0, ctx.metric("space.s", use))
				end,
			}) :: Types.Child,
		}
		if primary then
			local action = primary
			local button = UI.Button({
				Name = "Primary",
				LayoutOrder = 1,
				label = action.label,
				icon = action.icon,
				appearance = "emphasis",
				busy = action.busy,
				enabled = function(use: ComposeTypes.Use): boolean
					return enabled(use) and read(action.enabled, use) ~= false
				end,
				onActivate = function()
					if actionEnabled() then
						action.onActivate()
					end
				end,
			})
			primaryButton = button
			local states = table.clone(actionStates:peek())
			table.insert(states, holding(button))
			actionStates:set(states)
			table.insert(rowChildren, button :: Types.Child)
		end
		if menu then
			local more = UI.Menu({
				Name = "More",
				LayoutOrder = 2,
				label = menu.label or "More",
				items = menu.items,
				isPresented = menuOpen,
				enabled = enabled,
			})
			local trigger = more:FindFirstChild("Trigger")
			if trigger and trigger:IsA("GuiObject") then
				moreTrigger = trigger
				local states = table.clone(actionStates:peek())
				table.insert(states, holding(trigger))
				actionStates:set(states)
			end
			table.insert(rowChildren, more :: Types.Child)
		end
		local rowProps: Types.FrameNativeProps = {
			Name = "Row",
			BackgroundTransparency = 1,
			Size = D2.fromScale(1, 0),
			AutomaticSize = E.AutomaticSize.Y,
			SelectionGroup = true,
		}
		for _, side in
			{ "SelectionBehaviorUp", "SelectionBehaviorDown", "SelectionBehaviorLeft", "SelectionBehaviorRight" }
		do
			(rowProps :: { [unknown]: unknown })[side] = function(use: ComposeTypes.Use): Enum.SelectionBehavior
				return if use(entered) then E.SelectionBehavior.Stop else E.SelectionBehavior.Escape
			end
		end
		for _, child in rowChildren do
			table.insert(rowProps, child)
		end
		local row = Host.Frame(rowProps)
		local plate = Host.CanvasGroup "Reveal" {
			LayoutOrder = 2,
			BackgroundTransparency = 1,
			Size = D2.fromScale(1, 0),
			AutomaticSize = E.AutomaticSize.Y,
			Interactable = revealed,
			GroupTransparency = function(use: ComposeTypes.Use): number
				if reduced(use) then
					return if use(revealed) then 0 else 1
				end
				return 1 - use(fade)
			end,
			row :: Types.Child,
		}
		local liftScale = Host.UIScale({ Name = "Lift", Scale = scale })
		local card = Host.Frame(ctx.props(spec, {
			"image",
			"artwork",
			"title",
			"caption",
			"imageAspectRatio",
			"imageFraming",
			"onActivate",
			"primaryAction",
			"menu",
			"reveal",
			"browseTarget",
			"enabled",
			"controls",
		}, {
			Name = "Card",
			BackgroundTransparency = 1,
			Size = D2.fromScale(1, 0),
			AutomaticSize = E.AutomaticSize.Y,
			MouseEnter = function()
				hovered:set(true)
			end,
			MouseLeave = function()
				hovered:set(false)
			end,
			Attributes = {
				FacetReveal = checks.attribute(reveal),
				FacetRevealed = checks.attribute(revealed),
				FacetEngaged = checks.attribute(engaged),
				FacetLifting = checks.attribute(lifting),
				FacetHovered = checks.attribute(hovered),
				FacetFocusWithin = checks.attribute(focusWithin),
				FacetPressing = checks.attribute(pressing),
				FacetBrowsing = checks.attribute(browsing),
				FacetEntered = checks.attribute(entered),
				FacetMenuOpen = checks.attribute(menuOpen),
				FacetBody = checks.attribute(if spec.onActivate then "button" else "informational"),
			} :: Types.Attributes,
			Host.UIListLayout({
				FillDirection = E.FillDirection.Vertical,
				SortOrder = E.SortOrder.LayoutOrder,
				Padding = function(use: ComposeTypes.Use)
					return D.new(0, ctx.metric("space.xs", use))
				end,
			}) :: Types.Child,
			liftScale :: Types.Child,
			body :: Types.Child,
			plate :: Types.Child,
		}))
		root = card
		local extent = ctx.observe.AbsoluteSize(card)
		if (spec :: { [unknown]: unknown }).Position == nil then
			runtime.decorate(card, {
				Position = function(use: ComposeTypes.Use): UDim2
					local factor = math.max(use(scale), 0.001)
					local grown = use(extent) * (1 - 1 / factor) / 2
					return D2.fromOffset(-grown.X, -grown.Y)
				end,
			})
		end
		Compose.watch(function(use: ComposeTypes.Use)
			local painted = liftScale.Scale
			cardWidth:set(math.round(use(extent).X / (if painted > 0 then painted else 1)))
		end)
		local revealExtent = Compose.formula(function(use: ComposeTypes.Use): { body: number }
			return { body = use(extent).Y }
		end)
		if spec.controls then
			spec.controls.revealExtent = revealExtent
		end
		Compose.watch(function(use: ComposeTypes.Use)
			if not enabled(use) and entered:peek() then
				leaveActions()
			end
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			local node = use(selected)
			if entered:peek() and not menuOpen:peek() and node ~= nil and not within(node, card) then
				entered:set(false)
			end
		end)
		if spec.browseTarget then
			local browseTarget = spec.browseTarget
			local attachedTo: Instance? = nil
			local stopScale: (() -> ())? = nil
			Compose.watch(function(use: ComposeTypes.Use)
				use(selected)
				local target = browseTarget()
				if target == attachedTo then
					return
				end
				if stopScale then
					stopScale()
					stopScale = nil
				end
				attachedTo = target
				if target then
					stopScale = runtime.mount(function()
						return Host.UIScale({ Name = "CardLift", Scale = scale })
					end, target)
				end
			end)
			Compose.cleanup(function()
				if stopScale then
					stopScale()
				end
			end)
		end
		ctx.action(card, "CardCancel", { E.KeyCode.Escape, E.KeyCode.ButtonB }, function(use: ComposeTypes.Use)
			return use(entered) and not use(menuOpen)
		end, leaveActions, { priority = 1500 })
		if input then
			runtime.connect(input, "InputBegan", function(event: InputObject)
				if not entered:peek() or menuOpen:peek() then
					return
				end
				if
					event.UserInputType ~= E.UserInputType.MouseButton1
					and event.UserInputType ~= E.UserInputType.Touch
				then
					return
				end
				local at, size, point = card.AbsolutePosition, card.AbsoluteSize, event.Position
				if point.X < at.X or point.Y < at.Y or point.X > at.X + size.X or point.Y > at.Y + size.Y then
					entered:set(false)
				end
			end)
		end
		Compose.cleanup(function()
			if entered:peek() and gui and within(gui.SelectedObject, card) then
				entered:set(false)
				local target = if spec.browseTarget then spec.browseTarget() else nil
				gui.SelectedObject = if target and target.Parent and not within(target, card) then target else nil
			end
		end)
		return card
	end)
end
