--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local Overlay = require("./overlay_types")
local Inputs = require("./input_types")
local ComposeTypes = require("../vendor/compose/core")
local parts = require("./overlay_parts")
local toastSchedule = require("./toast_schedule")
local motion = require("./motion")
local reducedMotion = motion.reduced
local reservations = require("./reservations")

type Controls = {
	Toast: Types.Constructor<Overlay.ToastSpec, Frame>,
	Button: Types.Constructor<Inputs.ButtonProps, TextButton>,
}
type Reason = Overlay.ToastDismissReason
type Record = {
	spec: Overlay.ToastSpec,
	state: ComposeTypes.Cell<string>,
	height: ComposeTypes.Cell<number>,
	stack: Stack?,
	id: number?,
	pending: Reason?,
	torn: boolean,
	hovered: boolean,
	row: GuiObject?,
}
type Stack = {
	schedule: toastSchedule.Schedule,
	order: ComposeTypes.Cell<{ Record }>,
	inset: ComposeTypes.Cell<number>,
	time: number,
	stop: (() -> ())?,
	lane: string,
	layer: GuiBase2d,
}

local KEYS = {
	"message",
	"content",
	"icon",
	"action",
	"closeButton",
	"isPresented",
	"onPresentedChange",
	"key",
	"priority",
	"duration",
	"readFloor",
	"position",
	"width",
	"fade",
	"onDismiss",
}
local PASSIVE_ONLY = { "content", "position", "width", "fade" }
local MARGIN, GAP, HUG_MAX, ROW_Z, ACTION_Z = 8, 8, 560, 70, 60

return function(ctx: Types.Context, UI: Controls, surfaces: Nav.Surfaces): ()
	local Compose, Host, runtime, read = ctx.Compose, ctx.Host, ctx.runtime, ctx.read
	local E, D2, V2, UD = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2, ctx.types.UDim
	local frames = runtime.host.frames
	local gui = surfaces.service("GuiService")
	local stacks: { [Instance]: { [string]: Stack } } = setmetatable({} :: any, { __mode = "k" })
	local actionRows: { [GuiObject]: boolean } = setmetatable({} :: any, { __mode = "k" })
	local actionTokens: { [unknown]: boolean } = setmetatable({} :: any, { __mode = "k" })
	local returnTo: GuiObject? = nil

	local function wanted(record: Record): boolean
		return record.spec.isPresented == nil or read(record.spec.isPresented) == true
	end

	local function retire(record: Record, reason: Reason)
		record.id = nil
		record.state:set("idle")
		local row, spec = record.row, record.spec
		if gui and row and surfaces.within(gui.SelectedObject, row) then
			gui.SelectedObject = if returnTo and returnTo.Parent then returnTo else nil
		end
		local change = spec.onPresentedChange
		if spec.isPresented ~= nil and change and not record.torn and wanted(record) then
			parts.call(change, nil, false)
		end
		record.pending = nil
		if spec.onDismiss then
			spec.onDismiss(reason)
		end
	end

	local function offer(record: Record, reason: Reason, fn: () -> ())
		record.pending = reason
		parts.call(fn, function()
			if record.id ~= nil and wanted(record) then
				record.pending = nil
			end
		end)
	end

	local function dismiss(record: Record, reason: Reason)
		local stack, id = record.stack, record.id
		if stack and id then
			stack.schedule.dismiss(id, reason)
		end
	end

	local function finish(record: Record, reason: Reason)
		if record.id == nil then
			return
		end
		local change = record.spec.onPresentedChange
		if record.spec.isPresented ~= nil and change then
			offer(record, reason, function()
				change(false)
			end)
		else
			dismiss(record, reason)
		end
	end

	local function paused(stack: Stack): boolean
		local top = stack.schedule.visible()[1]
		if stack.lane ~= "action" or top == nil then
			return false
		end
		local record = top.data :: Record
		if record.row == nil or record.hovered then
			return true
		end
		return (gui ~= nil and surfaces.within(gui.SelectedObject, record.row)) or #ctx.modalScopes:peek() > 0
	end

	local function stackFor(layer: GuiBase2d, lane: string): Stack
		local byLane = stacks[layer] or {}
		stacks[layer] = byLane
		local existing = byLane[lane]
		if existing then
			return existing
		end
		local stack: Stack
		local schedule = toastSchedule.new({
			maxVisible = if lane == "action" then 1 else nil,
			now = function(): number
				return stack.time
			end,
			onDismiss = function(entry: toastSchedule.Entry, reason: string)
				retire(entry.data :: Record, reason :: Reason)
			end,
			onPropose = function(entry: toastSchedule.Entry, reason: string)
				finish(entry.data :: Record, reason :: Reason)
			end,
			onChange = function()
				for _, entry in stack.schedule.queued() do
					(entry.data :: Record).state:set("queued")
				end
				local order: { Record } = {}
				for _, entry in stack.schedule.visible() do
					local record = entry.data :: Record
					record.state:set("shown")
					table.insert(order, record)
				end
				stack.order:set(order)
				if stack.schedule.isEmpty() and stack.stop then
					stack.stop()
					stack.stop = nil
				end
			end,
		})
		stack = {
			schedule = schedule,
			order = Compose.cell({} :: { Record }),
			inset = Compose.cell(0),
			time = 0,
			stop = nil,
			lane = lane,
			layer = layer,
		}
		byLane[lane] = stack
		return stack
	end

	local function push(record: Record)
		local stack = record.stack :: Stack
		if stack.stop == nil and frames then
			stack.stop = frames.onFrame(function(dt: number)
				if not paused(stack) then
					stack.time += dt
				end
				stack.inset:set(
					if stack.lane == "action"
						then reservations.reserved(stack.layer, "bottom", actionTokens)
						else reservations.reserved(stack.layer, stack.lane :: reservations.Edge)
				)
				stack.schedule.update()
			end)
		end
		local spec = record.spec
		local duration = spec.duration
		if spec.action then
			duration = if duration
				then math.max(duration, spec.readFloor or toastSchedule.DEFAULTS.readFloor)
				else math.huge
		end
		record.state:set("queued")
		local id = stack.schedule.push({
			key = spec.key,
			priority = spec.priority,
			duration = duration,
			readFloor = spec.readFloor,
			data = record,
			held = spec.isPresented ~= nil,
		})
		if record.state:peek() ~= "idle" then
			record.id = id
		end
	end

	local function validate(spec: Overlay.ToastSpec)
		local where = "UI.Toast"
		local fields = (spec :: unknown) :: { [string]: unknown }
		local interactive = spec.action ~= nil
		if (spec.message == nil) == (spec.content == nil) then
			error(`Facet {where}: give exactly one of message or content`, 0)
		end
		if spec.message ~= nil and not parts.bound(ctx, spec.message, "string") then
			error(`Facet {where}: message is a string or a bound string`, 0)
		end
		if spec.content ~= nil and type(spec.content) ~= "function" then
			error(`Facet {where}: content is a factory that returns the body`, 0)
		end
		if interactive then
			for _, key in PASSIVE_ONLY do
				if fields[key] ~= nil then
					error(`Facet {where}: {key} is for a toast without an action; one with an action docks bottom`, 0)
				end
			end
			if type(spec.action) ~= "table" then
				error(`Facet {where}: action must be \{ label, onActivate }`, 0)
			end
			local action = spec.action :: Overlay.ToastAction
			parts.known(where, (action :: unknown) :: { [string]: unknown }, { "label", "onActivate" }, "action")
			if not parts.bound(ctx, action.label, "string") or type(action.onActivate) ~= "function" then
				error(`Facet {where}: action needs a label and an onActivate function`, 0)
			end
		elseif spec.closeButton ~= nil then
			error(`Facet {where}: closeButton needs an action; a toast without one is display-only`, 0)
		end
		if spec.closeButton ~= nil and type(spec.closeButton) ~= "boolean" then
			error(`Facet {where}: closeButton must be true or false`, 0)
		end
		if spec.icon ~= nil and (type(spec.icon) ~= "string" or spec.icon == "") then
			error(`Facet {where}: icon must be an icon name or an image source`, 0)
		end
		if spec.position ~= nil and spec.position ~= "top" and spec.position ~= "bottom" then
			error(`Facet {where}: position is top or bottom`, 0)
		end
		if spec.width ~= nil and spec.width ~= "fill" and spec.width ~= "hug" then
			error(`Facet {where}: width is fill or hug`, 0)
		end
		for _, key in { "duration", "readFloor" } do
			local value = fields[key]
			if value ~= nil and not (type(value) == "number" and value >= 0 and value < math.huge) then
				error(`Facet {where}: {key} is seconds, 0 or more`, 0)
			end
		end
		if spec.priority ~= nil and not (type(spec.priority) == "number" and math.abs(spec.priority) < math.huge) then
			error(`Facet {where}: priority is a finite number`, 0)
		end
		if spec.key ~= nil and type(spec.key) ~= "string" then
			error(`Facet {where}: key is a string`, 0)
		end
		if spec.fade ~= nil and type(spec.fade) ~= "boolean" then
			error(`Facet {where}: fade is a boolean`, 0)
		end
		for _, key in { "onDismiss", "onPresentedChange" } do
			if fields[key] ~= nil and type(fields[key]) ~= "function" then
				error(`Facet {where}: {key} is a function`, 0)
			end
		end
		if spec.isPresented ~= nil and not parts.bound(ctx, spec.isPresented, "boolean") then
			error(`Facet {where}: isPresented is the caller's boolean fact`, 0)
		end
		local endsItself = not interactive or spec.closeButton ~= false or spec.duration ~= nil
		if spec.isPresented ~= nil and endsItself and spec.onPresentedChange == nil then
			error(
				`Facet {where}: a bound toast that can end itself (a duration or a close button) needs `
					.. "onPresentedChange. A read-only one has an action, closeButton = false and no duration.",
				0
			)
		end
		if spec.isPresented == nil and spec.onPresentedChange ~= nil then
			error(`Facet {where}: onPresentedChange answers isPresented; give both or neither`, 0)
		end
	end

	local function withIcon(icon: string?, message: Instance, hug: boolean): Instance
		if icon == nil then
			return message
		end
		surfaces.attach(message, { Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }) })
		local props: Types.FrameNativeProps = {
			Name = "Body",
			BackgroundTransparency = 1,
			Size = if hug then D2.fromOffset(0, 0) else D2.fromScale(1, 0),
			AutomaticSize = if hug then E.AutomaticSize.XY else E.AutomaticSize.Y,
			Host.UIListLayout({
				FillDirection = E.FillDirection.Horizontal,
				VerticalAlignment = E.VerticalAlignment.Center,
				SortOrder = E.SortOrder.LayoutOrder,
				Padding = UD.new(0, 8),
			}),
			ctx.icon(icon, { Name = "Icon", LayoutOrder = 0 }),
			message,
		}
		return Host.Frame(props)
	end

	local function limitedSlide(
		phase: Nav.PresencePhase?,
		entered: ComposeTypes.Readable<boolean>,
		level: (ComposeTypes.Use?) -> motion.Level
	): (ComposeTypes.Readable<number>, (
		ComposeTypes.Use,
		(ComposeTypes.Use) -> number
	) -> number)
		local toastTiming = ctx.motionTiming("toast")
		local present, fade, trail = ctx.motionEase("present"), ctx.motionEase("fade"), ctx.motionEase("trail")
		local function shown(use: ComposeTypes.Use): number
			return if phase and use(phase.exiting) then 0 elseif use(entered) then 1 else 0
		end
		local function seconds(_: ComposeTypes.Use): number
			if level() == "limited" then
				return ctx.metric("motion.reducedFade")
			end
			return if phase and phase.exiting:peek() then toastTiming.exit else toastTiming.enter
		end
		local slide = runtime.tween(shown, {
			seconds = seconds,
			ease = function(t: number): number
				return if level() == "limited" then fade(t) else present(t)
			end,
		})
		local trailing = runtime.tween(shown, { seconds = seconds, ease = trail })
		return slide,
			function(use: ComposeTypes.Use, amount: (ComposeTypes.Use) -> number): number
				local current = level(use)
				return if current == "limited"
					then use(slide)
					elseif current == "normal" then use(trailing)
					else amount(use)
			end
	end

	local function passiveRow(record: Record, stack: Stack, phase: Nav.PresencePhase?): Instance
		local spec, layer = record.spec, stack.layer
		local bottom = spec.position == "bottom"
		local hug = spec.width == "hug"
		local extent = ctx.layoutSize(layer)
		local reduced = reducedMotion(ctx)
		local level = motion.level(ctx)
		local body: Instance
		if spec.content then
			body = spec.content()
		else
			local message = spec.message
			body = withIcon(
				spec.icon,
				ctx.text({
					Name = "Message",
					Text = function(use: ComposeTypes.Use)
						return read(message, use) or ""
					end,
					TextWrapped = true,
					LayoutOrder = 1,
					Size = if hug then D2.fromOffset(0, 0) else D2.fromScale(1, 0),
					AutomaticSize = if hug then E.AutomaticSize.XY else E.AutomaticSize.Y,
				}),
				hug
			)
		end
		local toastTiming, present = ctx.motionTiming("toast"), ctx.motionEase("present")
		local entered = Compose.cell(false)
		local slide, opacity = limitedSlide(phase, entered, level)
		local function amount(use: ComposeTypes.Use): number
			if reduced(use) then
				return if level(use) == "none" and phase and use(phase.exiting) then 0 else 1
			end
			return use(slide)
		end
		local function target(use: ComposeTypes.Use): number
			local offset = MARGIN + use(stack.inset)
			for _, other in use(stack.order) do
				if other == record then
					break
				end
				offset += use(other.height) + GAP
			end
			return offset
		end
		local settle = runtime.tween(target, { seconds = toastTiming.enter, ease = present })
		local props: Types.CanvasGroupNativeProps = {
			Name = "ToastRow",
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			Active = false,
			Interactable = false,
			ZIndex = ROW_Z,
			AnchorPoint = V2.new(0.5, if bottom then 1 else 0),
			AutomaticSize = if hug then E.AutomaticSize.XY else E.AutomaticSize.Y,
			Size = function(use: ComposeTypes.Use)
				return if hug then D2.fromOffset(0, 0) else D2.fromOffset(math.max(0, use(extent).X - 32), 0)
			end,
			Position = function(use: ComposeTypes.Use)
				local y = if reduced(use) then target(use) else use(settle)
				local travel = (1 - amount(use)) * (use(record.height) + MARGIN + use(stack.inset))
				local offset = y - travel
				return if bottom then D2.new(0.5, 0, 1, -offset) else D2.new(0.5, 0, 0, offset)
			end,
			body,
		}
		props[#props + 1] = ctx.padding(12, 8)
		props[#props + 1] = ctx.corner()
		if hug then
			props[#props + 1] = Host.UISizeConstraint({
				Name = "WidthCap",
				MaxSize = function(use: ComposeTypes.Use)
					return V2.new(math.max(0, math.min(HUG_MAX, use(extent).X - 32)), math.huge)
				end,
			})
		end
		local row = ctx.styled(ctx.fade(props), "snackbar")
		ctx.styled(row, "panel")
		ctx.styled(row, "floating")
		surfaces.skin(row, "panel")
		ctx.fadeTo(row, function(use: ComposeTypes.Use)
			if spec.fade == false and level(use) == "normal" then
				return 0
			end
			return 1 - opacity(use, amount)
		end)
		local measured = ctx.observe.AbsoluteSize(row)
		Compose.watch(function(use: ComposeTypes.Use)
			record.height:set(use(measured).Y)
		end)
		for _, node in row:GetDescendants() do
			if node:IsA("GuiObject") then
				node.Selectable = false
			end
		end
		local parent = ctx.observe.Parent(row)
		Compose.watch(function(use: ComposeTypes.Use)
			if use(parent) then
				entered:set(true)
			end
		end)
		return row
	end

	local function actionRow(record: Record, stack: Stack, phase: Nav.PresencePhase?): Instance
		local spec, layer = record.spec, stack.layer
		local origin = ctx.observe.AbsolutePosition(layer)
		local closable = spec.closeButton ~= false
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
		local unit = ctx.layoutUnit(measure)
		local extent = ctx.layoutSize(layer, unit)
		local function cap(use: ComposeTypes.Use): number
			return math.max(0, math.min(ctx.metric("controls.snackbar.maxWidth", use), use(extent).X - 32))
		end
		local natural = ctx.layoutBounds(measure, unit)
		local actionWidth = Compose.cell(0)
		local function chrome(use: ComposeTypes.Use): number
			local package = ctx.read(ctx.config.theme, use)
			local panel = if package and package.chrome then package.chrome.panel else nil
			local insets = if panel then panel.contentInsets else nil
			return math.max(8, if insets then insets.left or 0 else 0)
				+ math.max(8, if insets then insets.right or 0 else 0)
				+ (if spec.icon then ctx.controlSize(nil, "iconSize", use) + 8 else 0)
				+ (if closable then 44 + 8 else 0)
		end
		local beside = Compose.formula(function(use: ComposeTypes.Use): boolean
			return math.ceil(use(natural).X) + use(actionWidth) + 8 + chrome(use) <= cap(use)
		end)
		local message = ctx.text({
			Name = "Message",
			Text = function(use: ComposeTypes.Use)
				return read(spec.message, use) or ""
			end,
			TextWrapped = true,
			LayoutOrder = 1,
			Size = D2.new(1, 0, 0, 0),
			AutomaticSize = E.AutomaticSize.Y,
		})
		surfaces.attach(message, {
			Host.UIFlexItem({
				FlexMode = function(use: ComposeTypes.Use)
					return if use(beside) then E.UIFlexMode.Fill else E.UIFlexMode.None
				end,
			}),
		})
		local action = spec.action :: Overlay.ToastAction
		local button = UI.Button "Action" {
			label = action.label,
			LayoutOrder = 2,
			onActivate = function()
				if record.state:peek() ~= "shown" then
					return
				end
				if spec.isPresented ~= nil then
					offer(record, "action", action.onActivate)
				else
					parts.call(action.onActivate, function()
						dismiss(record, "action")
					end)
				end
			end,
		}
		local buttonSize = ctx.layoutSize(button, unit)
		Compose.watch(function(use: ComposeTypes.Use)
			actionWidth:set(use(buttonSize).X)
		end)
		local bodyProps: Types.FrameNativeProps = {
			Name = "Body",
			BackgroundTransparency = 1,
			LayoutOrder = 2,
			Size = D2.new(0, 0, 0, 0),
			AutomaticSize = E.AutomaticSize.Y,
			Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }),
			Host.UIListLayout({
				FillDirection = function(use: ComposeTypes.Use)
					return if use(beside) then E.FillDirection.Horizontal else E.FillDirection.Vertical
				end,
				HorizontalAlignment = E.HorizontalAlignment.Right,
				VerticalAlignment = E.VerticalAlignment.Center,
				SortOrder = E.SortOrder.LayoutOrder,
				Padding = UD.new(0, 8),
			}),
			message,
			measure,
			button,
		}
		local rowProps: Types.CanvasGroupNativeProps = {
			Name = "Snack",
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			ZIndex = ACTION_Z,
			AnchorPoint = V2.new(0.5, 1),
			AutomaticSize = E.AutomaticSize.Y,
			Size = function(use: ComposeTypes.Use)
				return D2.fromOffset(cap(use), 0)
			end,
			ctx.padding(8, 8),
			ctx.corner(),
			Host.UIListLayout({
				FillDirection = E.FillDirection.Horizontal,
				VerticalAlignment = E.VerticalAlignment.Center,
				SortOrder = E.SortOrder.LayoutOrder,
				Padding = UD.new(0, 8),
			}),
			Host.Frame(bodyProps),
		}
		if spec.icon then
			rowProps[#rowProps + 1] = ctx.icon(spec.icon, { Name = "Icon", LayoutOrder = 0 })
		end
		if closable then
			rowProps[#rowProps + 1] = UI.Button "Close" {
				name = "Close",
				icon = "close",
				LayoutOrder = 3,
				Size = D2.fromOffset(44, 44),
				AutomaticSize = E.AutomaticSize.None,
				onActivate = function()
					finish(record, "close")
				end,
			}
		end
		local row = ctx.styled(ctx.fade(rowProps), "snackbar")
		ctx.styled(row, "panel")
		ctx.styled(row, "floating")
		surfaces.skin(row, "panel")
		local reduced = reducedMotion(ctx)
		local level = motion.level(ctx)
		local shown = Compose.cell(false)
		local slide, opacity = limitedSlide(phase, shown, level)
		local function amount(use: ComposeTypes.Use): number
			if reduced(use) then
				return if level(use) == "none" and phase and use(phase.exiting) then 0 else 1
			end
			return use(slide)
		end
		ctx.fadeTo(row, function(use: ComposeTypes.Use)
			return 1 - opacity(use, amount)
		end)
		local measured = ctx.observe.AbsoluteSize(row)
		runtime.decorate(row, {
			Position = function(use: ComposeTypes.Use)
				local travel = (1 - amount(use)) * (use(measured).Y + 16 + use(stack.inset))
				return D2.new(0.5, 0, 1, -16 - use(stack.inset) + travel)
			end,
			Interactable = function(use: ComposeTypes.Use)
				return not (phase and use(phase.exiting))
			end,
		})
		local state = ctx.observe.GuiState(row)
		Compose.watch(function(use: ComposeTypes.Use)
			record.hovered = use(state) == E.GuiState.Hover
		end)
		record.row = row
		actionRows[row] = true
		local token = {}
		actionTokens[token] = true
		local at = ctx.observe.AbsolutePosition(row)
		Compose.watch(function(use: ComposeTypes.Use)
			local box = use(measured)
			local offset = use(origin)
			use(extent)
			if box.Y > 0 then
				reservations.set(layer, token, "bottom", use(at).Y - offset.Y, box.Y)
			end
		end)
		Compose.cleanup(function()
			if gui and surfaces.within(gui.SelectedObject, row) then
				gui.SelectedObject = if returnTo and returnTo.Parent then returnTo else nil
			end
			reservations.clear(layer, token)
			actionRows[row] = nil
			if record.row == row then
				record.row = nil
			end
		end)
		local selection: ComposeTypes.Readable<GuiObject?> = if gui and gui.GetPropertyChangedSignal
			then ctx.observe.SelectedObject(gui)
			else Compose.cell(nil :: GuiObject?)
		ctx.action(row, "ToastCancel", { E.KeyCode.ButtonB, E.KeyCode.Escape }, function(use: ComposeTypes.Use)
			local selected = use(selection)
			return selected ~= nil and surfaces.within(selected, row)
		end, function()
			local back = returnTo
			finish(record, "cancel")
			if gui and back and back.Parent and gui.SelectedObject ~= back then
				gui.SelectedObject = back
			end
		end, { priority = 2500 })
		local raiser = returnTo
		local target = surfaces.firstSelectable(row)
		if raiser and target and (raiser.NextSelectionDown :: GuiObject?) == nil then
			raiser.NextSelectionDown = target
			local function unlink()
				if raiser.NextSelectionDown == target then
					raiser.NextSelectionDown = nil :: any
				end
			end
			Compose.watch(function(use: ComposeTypes.Use)
				local selected = use(selection)
				if selected ~= nil and selected ~= raiser and not surfaces.within(selected, row) then
					unlink()
				end
			end)
			Compose.cleanup(unlink)
		end
		local parent = ctx.observe.Parent(row)
		Compose.watch(function(use: ComposeTypes.Use)
			if use(parent) then
				shown:set(true)
			end
		end)
		return row
	end

	local function trackReturn()
		if gui and gui.GetPropertyChangedSignal then
			local selection = ctx.observe.SelectedObject(gui)
			Compose.watch(function(use: ComposeTypes.Use)
				local selected = use(selection)
				if selected == nil then
					return
				end
				for row in actionRows do
					if surfaces.within(selected, row) then
						return
					end
				end
				returnTo = selected
			end)
		end
	end

	UI.Toast = ctx.construct("Toast", function(spec: Overlay.ToastSpec): Frame
		validate(spec)
		local interactive = spec.action ~= nil
		local level = motion.level(ctx)
		if interactive then
			trackReturn()
		end
		local root = Host.Frame(
			ctx.props(spec, KEYS, { Name = "Toast", BackgroundTransparency = 1, Size = D2.fromOffset(0, 0) })
		)
		local record: Record = {
			spec = spec,
			state = Compose.cell("idle"),
			height = Compose.cell(0),
			stack = nil,
			id = nil,
			pending = nil,
			torn = false,
			hovered = false,
			row = nil,
		}
		local armed = wanted(record)
		local function sync()
			if armed and record.stack and record.id == nil then
				armed = false
				push(record)
			end
		end
		local function locate()
			local collector = root:FindFirstAncestorWhichIsA("LayerCollector")
			local layer = if collector then surfaces.parent(root) else nil
			if record.stack == nil and layer then
				record.stack = stackFor(layer :: GuiBase2d, if interactive then "action" else spec.position or "top")
				sync()
			end
		end
		runtime.connect(root, "AncestryChanged", locate)
		locate()
		if spec.isPresented ~= nil then
			local last = armed
			Compose.watch(function(use: ComposeTypes.Use)
				local want = read(spec.isPresented, use) == true
				if want == last then
					return
				end
				last = want
				armed = want
				if want then
					sync()
				else
					dismiss(record, record.pending or "cancel")
				end
			end)
		end
		Compose.cleanup(function()
			record.torn = true
			armed = false
			dismiss(record, if spec.isPresented ~= nil then "cancel" else "manual")
		end)
		surfaces.attach(root, {
			surfaces.overlay(root, function(use: ComposeTypes.Use): boolean
				return use(record.state) == "shown"
			end, function(phase)
				local stack = assert(record.stack)
				return if interactive then actionRow(record, stack, phase) else passiveRow(record, stack, phase)
			end, {
				presence = {
					exit = function()
						local current = level()
						if current == "none" then
							return { completed = Compose.cell(true) }
						end
						local seconds = if current == "limited"
							then ctx.metric("motion.reducedFade")
							else ctx.metric("motion.toast.exit")
						return { completed = runtime.timeline({ duration = seconds }).completed }
					end,
				},
			}),
		})
		Compose.watch(function(use: ComposeTypes.Use)
			local state = use(record.state)
			root:SetAttribute("ToastVisible", state == "shown")
			root:SetAttribute("ToastQueued", state == "queued")
		end)
		return root
	end)
end
