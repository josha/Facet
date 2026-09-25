--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local Overlay = require("./overlay_types")
local Inputs = require("./input_types")
local ComposeTypes = require("../vendor/compose/core")
local Theme = require("./theme_types")
local parts = require("./overlay_parts")
local reservations = require("./reservations")
local reducedMotion = require("./motion")
local freeze = require("./freeze")

type Controls = {
	Notice: Types.Constructor<Overlay.NoticeSpec, Frame>,
	NavBar: Types.Constructor<Overlay.NavBarSpec, Frame>,
	Button: Types.Constructor<Inputs.ButtonProps, TextButton>,
}

local NOTICE_KEYS = {
	"message",
	"title",
	"severity",
	"appearance",
	"placement",
	"icon",
	"link",
	"actions",
	"onDismiss",
	"controlSize",
}
local NAV_KEYS = {
	"onBack",
	"backLabel",
	"title",
	"titleSize",
	"leading",
	"center",
	"trailing",
	"gap",
	"padding",
}
local SEVERITIES: { [string]: string } = freeze({
	info = "status.info",
	success = "status.success",
	warning = "status.warning",
	error = "status.error",
})

local REVEAL: { enter: number, exit: number } = freeze({ enter = 0.25, exit = 0.2 })

local ICON_TAGS: { [string]: string } = freeze({
	info = "facet-icon-info",
	success = "facet-icon-success",
	warning = "facet-icon-warning",
	error = "facet-icon-error",
})

return function(ctx: Types.Context, UI: Controls, surfaces: Nav.Surfaces): ()
	local Compose, Host, runtime, read = ctx.Compose, ctx.Host, ctx.runtime, ctx.read
	local E, D2, UD = ctx.types.Enum, ctx.types.UDim2, ctx.types.UDim

	local function space(value: (number | string)?, fallback: string, use: ComposeTypes.Use?): number
		if type(value) == "number" then
			return value
		end
		return ctx.metric("space." .. (value or fallback), use)
	end

	UI.Notice = ctx.construct("Notice", function(spec: Overlay.NoticeSpec): Frame
		local where = "UI.Notice"
		if not parts.bound(ctx, spec.message, "string") then
			error(`Facet {where}: message is required; it is a string or a bound string`, 0)
		end
		if spec.title ~= nil and not parts.bound(ctx, spec.title, "string") then
			error(`Facet {where}: title must be a string or a bound string`, 0)
		end
		local severity = spec.severity or "info"
		if SEVERITIES[severity] == nil then
			error(`Facet {where}: severity must be info, success, warning or error`, 0)
		end
		local appearance = spec.appearance or "standard"
		if appearance ~= "standard" and appearance ~= "emphasis" then
			error(`Facet {where}: appearance must be standard or emphasis`, 0)
		end
		local placement = spec.placement or "inline"
		if placement ~= "inline" and placement ~= "affixed" then
			error(`Facet {where}: placement must be inline or affixed`, 0)
		end
		if spec.icon ~= nil and type(spec.icon) ~= "boolean" and (type(spec.icon) ~= "string" or spec.icon == "") then
			error(`Facet {where}: icon must be true, false, or an icon name or image source`, 0)
		end
		local link = spec.link
		if link ~= nil then
			if type(link) ~= "table" then
				error(`Facet {where}: link must be \{ label, onActivate }`, 0)
			end
			parts.known(where, (link :: unknown) :: { [string]: unknown }, { "label", "onActivate" }, "link")
			if not parts.bound(ctx, link.label, "string") or type(link.onActivate) ~= "function" then
				error(`Facet {where}: link needs a label and an onActivate function`, 0)
			end
		end
		if spec.onDismiss ~= nil and type(spec.onDismiss) ~= "function" then
			error(`Facet {where}: onDismiss must be a function`, 0)
		end
		local size = ctx.read(spec.controlSize)
		if size ~= nil and size ~= "xsmall" and size ~= "compact" and size ~= "regular" and size ~= "large" then
			error(`Facet {where}: controlSize must be xsmall, compact, regular or large`, 0)
		end
		local actions: { Overlay.Action } = spec.actions or {}
		parts.checkActions(ctx, where, spec.actions, 2, { "Link", "Close" })
		local reduce = reducedMotion(ctx)
		local present = Compose.cell(false)
		local leaving = Compose.cell(false)
		local travel = runtime.tween(function(use: ComposeTypes.Use): number
			return if use(present) then 1 else 0
		end, {
			seconds = function(_: ComposeTypes.Use): number
				return if present:peek() then REVEAL.enter else REVEAL.exit
			end,
			ease = Compose.easing.outCubic,
		})
		local function progress(use: ComposeTypes.Use?): number
			if reduce(use) then
				return if read(present, use) then 1 else 0
			end
			return read(travel, use)
		end
		local emphasis = appearance == "emphasis"
		local status = "facet-status-" .. severity
		local offered = Compose.cell(0)
		local copyNatural = Compose.cell(0)
		local accessoryWidth = Compose.cell(0)
		local function panelCarve(use: ComposeTypes.Use?): { left: number, right: number, top: number, bottom: number }
			local package = if emphasis then nil else read(ctx.config.theme, use)
			local chrome: { [string]: Theme.SkinLayer } = if package then package.chrome or {} else {}
			local recipe = chrome.panel
			local inset: Theme.Insets = if recipe then recipe.contentInsets or {} else {}
			return {
				left = math.max(8, inset.left or 0),
				right = math.max(8, inset.right or 0),
				top = math.max(8, inset.top or 0),
				bottom = math.max(8, inset.bottom or 0),
			}
		end
		local beside = Compose.formula(function(use: ComposeTypes.Use): boolean
			if link == nil and #actions == 0 then
				return true
			end
			local carve = panelCarve(use)
			local chrome = ctx.metric("targetSizes.minimum", use) * 2 + 4 * 8 + carve.left + carve.right - 16
			return use(copyNatural) + use(accessoryWidth) + chrome <= use(offered)
		end)
		local function lettering<N>(node: N & Instance): N & Instance
			if emphasis then
				node:AddTag(status)
			end
			return node
		end
		local copy: { Types.Child } = {}
		if spec.title ~= nil then
			local title = spec.title
			local heading = lettering(ctx.text({
				Name = "Title",
				Text = function(use: ComposeTypes.Use)
					return read(title, use) or ""
				end,
				TextWrapped = true,
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
			}))
			heading:AddTag("facet-type-label")
			heading:AddTag("facet-strong")
			table.insert(copy, heading)
		end
		local message = lettering(ctx.text({
			Name = "Message",
			Text = function(use: ComposeTypes.Use)
				return read(spec.message, use) or ""
			end,
			TextWrapped = true,
			Size = D2.new(1, 0, 0, 0),
			AutomaticSize = E.AutomaticSize.Y,
		}))
		table.insert(copy, message)
		local textService = ctx.config.services and ctx.config.services.TextService
		if textService then
			local width = ctx.observe.AbsoluteSize(message)
			local face = ctx.observeStyled.FontFace(message)
			local points = ctx.observeStyled.TextSize(message)
			local serial, last = 0, ""
			Compose.watch(function(use: ComposeTypes.Use)
				local wide = use(width).X
				local text: string = read(spec.message, use) or ""
				local font, size = use(face) :: Font, use(points) :: number
				local key = `{wide}|{text}|{size}|{font.Family}|{font.Weight.Name}`
				if wide <= 0 or text == "" or key == last then
					return
				end
				last = key
				serial += 1
				local ticket = serial
				task.spawn(function()
					local ok, bounds = pcall(function()
						local params = ((Host :: unknown) :: { [string]: (props: { [string]: unknown }) -> Instance }).GetTextBoundsParams({
							Text = text,
							Font = font,
							Size = size,
							Width = wide,
						})
						return (textService :: TextService):GetTextBoundsAsync(params :: GetTextBoundsParams)
					end)
					if ok and ticket == serial and message.Parent ~= nil and bounds.Y > 0 then
						message.AutomaticSize = E.AutomaticSize.None
						message.Size = D2.new(1, 0, 0, math.ceil(bounds.Y))
					end
				end)
			end)
		end
		local measure = ctx.text({
			Name = "MessageMeasure",
			Text = function(use: ComposeTypes.Use)
				return read(spec.message, use) or ""
			end,
			TextWrapped = false,
			TextTransparency = 1,
			Size = D2.fromOffset(0, 0),
			AutomaticSize = E.AutomaticSize.None,
			Visible = false,
		})
		local natural = ctx.observe.TextBounds(measure)
		Compose.watch(function(use: ComposeTypes.Use)
			copyNatural:set(math.ceil(use(natural).X))
		end)
		table.insert(copy, measure)
		local copyFrame = ctx.column(copy, {
			Name = "Copy",
			Size = D2.new(1, 0, 0, 0),
			AutomaticSize = E.AutomaticSize.Y,
			Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }) :: Instance,
		})
		local bodyChildren: { Types.Child } = { copyFrame }
		if link ~= nil or #actions > 0 then
			local accessories: { Types.Child } = {}
			if link then
				table.insert(
					accessories,
					UI.Button "Link" {
						label = link.label,
						appearance = if emphasis then nil else "link",
						controlSize = spec.controlSize,
						onActivate = link.onActivate,
					}
				)
			end
			for _, action in actions do
				table.insert(
					accessories,
					UI.Button({
						Name = action.id,
						label = action.label,
						enabled = action.enabled,
						busy = action.busy,
						role = if action.role == "destructive" then "destructive" :: "destructive" else nil,
						appearance = if action.role == "default" and not emphasis then "emphasis" else nil,
						controlSize = spec.controlSize,
						onActivate = action.onActivate,
					})
				)
			end
			local row = ctx.row(accessories, { Name = "Accessories" })
			local list = row:FindFirstChildWhichIsA("UIListLayout") :: UIListLayout?
			if list then
				list.Wraps = true
				list.VerticalAlignment = E.VerticalAlignment.Center
			end
			local rowSize = ctx.observe.AbsoluteSize(row)
			Compose.watch(function(use: ComposeTypes.Use)
				accessoryWidth:set(use(rowSize).X)
			end)
			table.insert(bodyChildren, row)
		end
		local bodyProps: Types.FrameNativeProps = {
			Name = "Body",
			BackgroundTransparency = 1,
			Size = D2.new(0, 0, 0, 0),
			AutomaticSize = E.AutomaticSize.Y,
		}
		table.insert(bodyProps, Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }))
		table.insert(
			bodyProps,
			Host.UIListLayout({
				FillDirection = function(use: ComposeTypes.Use)
					return if use(beside) then E.FillDirection.Horizontal else E.FillDirection.Vertical
				end,
				VerticalAlignment = E.VerticalAlignment.Center,
				SortOrder = E.SortOrder.LayoutOrder,
				Padding = UD.new(0, 8),
			})
		)
		for index, child in bodyChildren do
			runtime.decorate(child :: Instance, { LayoutOrder = index })
			table.insert(bodyProps, child)
		end
		local rowChildren: { Types.Child } = {}
		if spec.icon ~= false then
			local mark = ctx.icon(if type(spec.icon) == "string" then spec.icon else SEVERITIES[severity], {
				Name = "Icon",
				LayoutOrder = 1,
			})
			if not emphasis then
				mark:AddTag(ICON_TAGS[severity])
			end
			table.insert(rowChildren, mark)
		end
		local body = Host.Frame(bodyProps)
		table.insert(rowChildren, body)
		local gui = surfaces.service("GuiService")
		local frames = runtime.host.frames
		local noticeOwner = assert(Compose.currentOwner())
		local root: Frame
		local stopWaiting: (() -> ())? = nil
		local function stopWatching()
			local stop = stopWaiting
			stopWaiting = nil
			if stop then
				stop()
			end
		end
		Compose.cleanup(stopWatching)
		local function collapse(report: () -> ())
			if leaving:peek() then
				return
			end
			local function finish()
				leaving:set(false)
				report()
				if not noticeOwner.isDisposed() then
					present:set(true)
				end
			end
			if frames == nil or reduce() or progress() <= 0 then
				finish()
				return
			end
			leaving:set(true)
			if gui and surfaces.within(gui.SelectedObject, root) then
				gui.SelectedObject = nil
			end
			present:set(false)
			stopWaiting = frames.onFrame(function()
				if progress() > 0 and not reduce() then
					return
				end
				stopWatching()
				finish()
			end)
		end
		if spec.onDismiss then
			local dismiss = spec.onDismiss
			table.insert(
				rowChildren,
				UI.Button "Close" {
					name = "Close",
					icon = "close",
					controlSize = spec.controlSize,
					Size = D2.fromOffset(44, 44),
					AutomaticSize = E.AutomaticSize.None,
					LayoutOrder = 3,
					onActivate = function()
						collapse(dismiss)
					end,
				}
			)
		end
		local defaults: Types.FrameNativeProps = {
			Name = "Notice",
			Size = D2.new(1, 0, 0, 0),
			AutomaticSize = E.AutomaticSize.Y,
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			ZIndex = if placement == "affixed" then 50 else nil,
		}
		local native = (ctx.props(spec, NOTICE_KEYS, defaults) :: unknown) :: { [unknown]: unknown }
		local restSize, restAutomatic, restClip, restInteractable =
			native.Size, native.AutomaticSize, native.ClipsDescendants, native.Interactable
		local inset = Host.UIPadding({
			PaddingLeft = function(use: ComposeTypes.Use)
				return UD.new(0, panelCarve(use).left)
			end,
			PaddingRight = function(use: ComposeTypes.Use)
				return UD.new(0, panelCarve(use).right)
			end,
			PaddingTop = function(use: ComposeTypes.Use)
				return UD.new(0, panelCarve(use).top)
			end,
			PaddingBottom = function(use: ComposeTypes.Use)
				return UD.new(0, panelCarve(use).bottom)
			end,
		})
		local bodyExtent = ctx.observe.AbsoluteSize(body)
		local function settled(use: ComposeTypes.Use): boolean
			return progress(use) >= 1
		end
		native.AutomaticSize = function(use: ComposeTypes.Use): unknown
			return if settled(use) then read(restAutomatic, use) else E.AutomaticSize.None
		end
		native.Size = function(use: ComposeTypes.Use): unknown
			local rest = read(restSize, use)
			if settled(use) then
				return rest
			end
			local width = if typeof(rest) == "UDim2" then (rest :: UDim2).X else UD.new(1, 0)
			local tallest = use(bodyExtent).Y
			for _, child in rowChildren do
				if typeof(child) == "Instance" and child ~= body and (child :: Instance):IsA("GuiObject") then
					tallest = math.max(tallest, (child :: GuiObject).Size.Y.Offset)
				end
			end
			local height = tallest + inset.PaddingTop.Offset + inset.PaddingBottom.Offset
			return D2.new(width.Scale, width.Offset, 0, math.floor(height * progress(use) + 0.5))
		end
		native.ClipsDescendants = function(use: ComposeTypes.Use): unknown
			return if settled(use) then read(restClip, use) == true else true
		end
		native.Interactable = function(use: ComposeTypes.Use): unknown
			return not use(leaving) and read(restInteractable, use) ~= false
		end
		root = Host.Frame((native :: unknown) :: Types.FrameNativeProps)
		present:set(true)
		surfaces.attach(root, {
			inset,
			ctx.corner(),
			Host.UIListLayout({
				FillDirection = E.FillDirection.Horizontal,
				VerticalAlignment = E.VerticalAlignment.Top,
				SortOrder = E.SortOrder.LayoutOrder,
				Padding = UD.new(0, 8),
			}),
		})
		surfaces.attach(root, rowChildren)
		ctx.styled(root, "notice")
		ctx.styled(root, if emphasis then "status-" .. severity else "panel")
		root:SetAttribute("NoticeSeverity", severity)
		local extent = ctx.observe.AbsoluteSize(root)
		Compose.watch(function(use: ComposeTypes.Use)
			offered:set(use(extent).X)
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			root:SetAttribute("NoticeAccessories", if use(beside) then "beside" else "below")
		end)
		if placement == "affixed" then
			local owner = assert(Compose.currentOwner())
			local token = {}
			local at = ctx.observe.AbsolutePosition(root)
			local layerOwner: ComposeTypes.Owner? = nil
			local current: Instance? = nil
			local function locate()
				if owner.isDisposed() then
					return
				end
				if layerOwner then
					layerOwner.dispose()
				end
				if current then
					reservations.clear(current, token)
					current = nil
				end
				local child = owner.createChild()
				layerOwner = child
				Compose.withOwner(child, function()
					local layer = root:FindFirstAncestorWhichIsA("LayerCollector")
					if layer == nil then
						return
					end
					current = layer
					local origin = ctx.observe.AbsolutePosition(layer)
					local height = ctx.observe.AbsoluteSize(layer)
					local function publish()
						local box = root.AbsoluteSize
						local paints = box.X > 0 and box.Y > 0 and root.Visible
						local top = root.AbsolutePosition.Y - (layer :: GuiBase2d).AbsolutePosition.Y
						reservations.set(
							layer,
							token,
							"top",
							if paints then top else nil,
							if paints then box.Y else nil
						)
					end
					local services = ctx.config.services
					local frames = services and services.RunService
					local connection: RBXScriptConnection? = nil
					local function release()
						if connection then
							connection:Disconnect()
							connection = nil
						end
					end
					Compose.cleanup(release)
					Compose.watch(function(use: ComposeTypes.Use)
						use(height)
						use(at)
						use(origin)
						use(extent)
						publish()
						if frames then
							release()
							connection = frames.Heartbeat:Connect(function()
								release()
								publish()
							end)
						end
					end)
				end)
			end
			runtime.connect(root, "AncestryChanged", locate)
			locate()
			Compose.cleanup(function()
				if current then
					reservations.clear(current, token)
				end
			end)
		end
		return root
	end)

	UI.NavBar = ctx.construct("NavBar", function(spec: Overlay.NavBarSpec): Frame
		local where = "UI.NavBar"
		if spec.onBack ~= nil and type(spec.onBack) ~= "function" then
			error(`Facet {where}: onBack must be a function`, 0)
		end
		if spec.trailing ~= nil and not parts.instance(spec.trailing) then
			error(`Facet {where}: trailing is one GuiObject; put a cluster in a frame`, 0)
		end
		for _, key in { "leading", "center" } do
			local slot = (spec :: { [unknown]: unknown })[key]
			if slot ~= nil and not parts.instance(slot) then
				error(`Facet {where}: {key} must be a GuiObject`, 0)
			end
		end
		if spec.title ~= nil and not parts.bound(ctx, spec.title, "string") then
			error(`Facet {where}: title must be a string or a bound string`, 0)
		end
		local gap = function(use: ComposeTypes.Use?): number
			return space(spec.gap, "s", use)
		end
		local primary: { Types.Child } = {}
		if spec.onBack then
			table.insert(
				primary,
				UI.Button "Back" {
					label = spec.backLabel or "Back",
					icon = "chevron.leading",
					appearance = "link",
					onActivate = spec.onBack,
				}
			)
		end
		if spec.leading then
			table.insert(primary, ctx.row({ spec.leading }, { Name = "Leading" }))
		end
		local center: Instance? = spec.center
		local titleMeasure: TextLabel? = nil
		if center == nil and spec.title ~= nil then
			local title = spec.title
			local label = ctx.text({
				Name = "Title",
				Text = function(use: ComposeTypes.Use)
					return read(title, use) or ""
				end,
				TextWrapped = false,
				TextTruncate = E.TextTruncate.AtEnd,
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
			})
			label:AddTag("facet-type-" .. (spec.titleSize or "title"))
			center = label
			local measure = ctx.text({
				Name = "TitleMeasure",
				Text = function(use: ComposeTypes.Use)
					return read(title, use) or ""
				end,
				Visible = false,
				TextWrapped = false,
				Size = D2.fromOffset(0, 0),
				AutomaticSize = E.AutomaticSize.XY,
			})
			measure:AddTag("facet-type-" .. (spec.titleSize or "title"))
			titleMeasure = measure
		end
		local centerProps: Types.FrameNativeProps = {
			Name = "Center",
			BackgroundTransparency = 1,
			Size = D2.new(0, 0, 0, 0),
			AutomaticSize = E.AutomaticSize.Y,
		}
		table.insert(centerProps, Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }))
		table.insert(
			centerProps,
			Host.UIListLayout({
				FillDirection = E.FillDirection.Horizontal,
				VerticalAlignment = E.VerticalAlignment.Center,
				SortOrder = E.SortOrder.LayoutOrder,
			})
		)
		if center then
			table.insert(centerProps, center)
		end
		if titleMeasure then
			table.insert(centerProps, titleMeasure)
		end
		local centerFrame = Host.Frame(centerProps)
		table.insert(primary, centerFrame)
		local primaryFrame = ctx.row(primary, {
			Name = "Primary",
			Size = D2.new(1, 0, 0, 0),
			AutomaticSize = E.AutomaticSize.Y,
		})
		local stacked = Compose.cell(false)
		local rootChildren: { Types.Child } = { primaryFrame }
		local trailingFrame: Frame? = nil
		if spec.trailing then
			local trailing = ctx.row({ spec.trailing }, { Name = "Trailing" })
			trailingFrame = trailing
			table.insert(rootChildren, trailing)
		end
		local root = ctx.row(
			rootChildren,
			ctx.props(spec, NAV_KEYS, {
				Name = "NavBar",
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
			})
		)
		local list = root:FindFirstChildWhichIsA("UIListLayout") :: UIListLayout?
		if list then
			runtime.decorate(list, {
				FillDirection = function(use: ComposeTypes.Use)
					return if use(stacked) then E.FillDirection.Vertical else E.FillDirection.Horizontal
				end,
				HorizontalAlignment = E.HorizontalAlignment.Right,
				VerticalAlignment = E.VerticalAlignment.Center,
				Padding = function(use: ComposeTypes.Use)
					return UD.new(0, gap(use))
				end,
			})
		end
		local rows: { Frame } = { primaryFrame }
		if trailingFrame then
			table.insert(rows, trailingFrame)
		end
		for _, frame in rows do
			local layout = frame:FindFirstChildWhichIsA("UIListLayout") :: UIListLayout?
			if layout then
				runtime.decorate(layout, {
					VerticalAlignment = E.VerticalAlignment.Center,
					Padding = function(use: ComposeTypes.Use)
						return UD.new(0, gap(use))
					end,
				})
			end
		end
		local primaryFlex = Host.UIFlexItem({
			FlexMode = function(use: ComposeTypes.Use)
				return if use(stacked) then E.UIFlexMode.None else E.UIFlexMode.Fill
			end,
		})
		surfaces.attach(primaryFrame, { primaryFlex })
		runtime.decorate(primaryFrame, {
			Size = function(use: ComposeTypes.Use)
				return if use(stacked) then D2.new(1, 0, 0, 0) else D2.new(0, 0, 0, 0)
			end,
		})
		if spec.padding ~= nil then
			surfaces.attach(root, { ctx.padding(space(spec.padding, "s"), space(spec.padding, "s")) })
		end
		if trailingFrame then
			local box = ctx.observe.AbsoluteSize(root)
			local sides = ctx.observe.AbsoluteSize(trailingFrame)
			local main = ctx.observe.AbsoluteSize(primaryFrame)
			local middle = ctx.observe.AbsoluteSize(centerFrame)
			local natural = if titleMeasure then ctx.observe.TextBounds(titleMeasure) else nil
			Compose.watch(function(use: ComposeTypes.Use)
				local width = use(box).X
				if width <= 0 then
					return
				end
				local fixed = use(main).X - use(middle).X
				local room = width - fixed - use(sides).X - gap(use)
				local wanted = if natural then use(natural).X else ctx.metric("controls.popup.panelWidth", use)
				local floor = math.min(wanted, width - fixed)
				local next = room < floor
				if next ~= stacked:peek() then
					stacked:set(next)
				end
			end)
		end
		return root
	end)
end
