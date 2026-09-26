--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local Overlay = require("./overlay_types")
local ComposeTypes = require("../vendor/compose/core")
local parts = require("./overlay_parts")
local toastSchedule = require("./toast_schedule")

type Controls = { Toast: Types.Constructor<Overlay.ToastSpec, Frame> }
type Record = {
	shown: ComposeTypes.Cell<boolean>,
	height: ComposeTypes.Cell<number>,
	retired: boolean,
	spec: Overlay.ToastSpec,
}
type Placed = { stack: Stack, id: number, layer: GuiBase2d }
type Stack = {
	schedule: toastSchedule.Schedule,
	order: ComposeTypes.Cell<{ Record }>,
	time: number,
	stop: (() -> ())?,
}

local KEYS =
	{ "message", "content", "key", "priority", "duration", "readFloor", "position", "width", "fade", "onDismiss" }
local MARGIN, GAP, HUG_MAX, ROW_Z = 8, 8, 560, 70

return function(ctx: Types.Context, UI: Controls, surfaces: Nav.Surfaces): ()
	local Compose, Host, runtime, read = ctx.Compose, ctx.Host, ctx.runtime, ctx.read
	local E, D2, V2 = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2
	local frames = runtime.host.frames
	local gui = surfaces.service("GuiService")
	local stacks: { [Instance]: { [string]: Stack } } = setmetatable({} :: any, { __mode = "k" })

	local function stackFor(layer: Instance, edge: string): Stack
		local byEdge = stacks[layer] or {}
		stacks[layer] = byEdge
		local existing = byEdge[edge]
		if existing then
			return existing
		end
		local stack: Stack
		local schedule = toastSchedule.new({
			now = function(): number
				return stack.time
			end,
			onDismiss = function(entry: toastSchedule.Entry, reason: string)
				local record = entry.data :: Record
				record.retired = true
				record.shown:set(false)
				if record.spec.onDismiss then
					record.spec.onDismiss(reason :: Overlay.ToastDismissReason)
				end
			end,
			onChange = function()
				local order: { Record } = {}
				for _, entry in stack.schedule.visible() do
					local record = entry.data :: Record
					record.shown:set(true)
					table.insert(order, record)
				end
				stack.order:set(order)
				if stack.schedule.isEmpty() and stack.stop then
					stack.stop()
					stack.stop = nil
				end
			end,
		})
		stack = { schedule = schedule, order = Compose.cell({} :: { Record }), time = 0, stop = nil }
		byEdge[edge] = stack
		return stack
	end

	local function validate(spec: Overlay.ToastSpec)
		local where = "UI.Toast"
		if (spec.message == nil) == (spec.content == nil) then
			error(`Facet {where}: give exactly one of message or content`, 0)
		end
		if spec.message ~= nil and not parts.bound(ctx, spec.message, "string") then
			error(`Facet {where}: message is a string or a bound string`, 0)
		end
		if spec.content ~= nil and type(spec.content) ~= "function" then
			error(`Facet {where}: content is a factory that returns the body`, 0)
		end
		if spec.position ~= nil and spec.position ~= "top" and spec.position ~= "bottom" then
			error(`Facet {where}: position is top or bottom`, 0)
		end
		if spec.width ~= nil and spec.width ~= "fill" and spec.width ~= "hug" then
			error(`Facet {where}: width is fill or hug`, 0)
		end
		for _, key in { "duration", "readFloor" } do
			local value = ((spec :: unknown) :: { [string]: unknown })[key]
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
		if spec.onDismiss ~= nil and type(spec.onDismiss) ~= "function" then
			error(`Facet {where}: onDismiss is a function`, 0)
		end
	end

	local function reduced(use: ComposeTypes.Use?, setting: ComposeTypes.Readable<boolean>?): boolean
		if read(ctx.config.reducedMotion, use) == true then
			return true
		end
		if use and setting then
			return use(setting)
		end
		return gui ~= nil and gui.ReducedMotionEnabled == true
	end

	local function rowFor(record: Record, stack: Stack, layer: GuiBase2d, phase: Nav.PresencePhase?): Instance
		local spec = record.spec
		local bottom = spec.position == "bottom"
		local hug = spec.width == "hug"
		local extent = ctx.observe.AbsoluteSize(layer)
		local setting = if gui then ctx.observe.ReducedMotionEnabled(gui) else nil
		local body: Instance
		if spec.content then
			body = spec.content()
		else
			local message = spec.message
			body = ctx.text({
				Name = "Message",
				Text = function(use: ComposeTypes.Use)
					return read(message, use) or ""
				end,
				TextWrapped = true,
				Size = if hug then D2.fromOffset(0, 0) else D2.fromScale(1, 0),
				AutomaticSize = if hug then E.AutomaticSize.XY else E.AutomaticSize.Y,
			})
		end
		local entered = Compose.cell(false)
		local slide = runtime.tween(function(use: ComposeTypes.Use): number
			return if phase and use(phase.exiting) then 0 elseif use(entered) then 1 else 0
		end, { seconds = 0.2, ease = Compose.easing.outCubic })
		local function amount(use: ComposeTypes.Use): number
			if reduced(use, setting) then
				return if phase and use(phase.exiting) then 0 else 1
			end
			return use(slide)
		end
		local function target(use: ComposeTypes.Use): number
			local offset = MARGIN
			for _, other in use(stack.order) do
				if other == record then
					break
				end
				offset += use(other.height) + GAP
			end
			return offset
		end
		local settle = runtime.tween(target, { seconds = 0.2, ease = Compose.easing.outCubic })
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
				local y = if reduced(use, setting) then target(use) else use(settle)
				local travel = (1 - amount(use)) * (use(record.height) + MARGIN)
				local offset = y - travel
				return if bottom then D2.new(0.5, 0, 1, -offset) else D2.new(0.5, 0, 0, offset)
			end,
			body,
		}
		table.insert(props, ctx.padding(12, 8))
		table.insert(props, ctx.corner())
		if hug then
			table.insert(
				props,
				Host.UISizeConstraint({
					Name = "WidthCap",
					MaxSize = function(use: ComposeTypes.Use)
						return V2.new(math.max(0, math.min(HUG_MAX, use(extent).X - 32)), math.huge)
					end,
				})
			)
		end
		local row = ctx.styled(ctx.fade(props), "snackbar")
		ctx.styled(row, "panel")
		ctx.styled(row, "floating")
		surfaces.skin(row, "panel")
		if spec.fade then
			ctx.fadeTo(row, function(use: ComposeTypes.Use)
				return 1 - amount(use)
			end)
		end
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

	UI.Toast = ctx.construct("Toast", function(spec: Overlay.ToastSpec): Frame
		validate(spec)
		local root = Host.Frame(
			ctx.props(spec, KEYS, { Name = "Toast", BackgroundTransparency = 1, Size = D2.fromOffset(0, 0) })
		)
		local record: Record = { shown = Compose.cell(false), height = Compose.cell(0), retired = false, spec = spec }
		local edge = spec.position or "top"
		local placed: Placed? = nil
		local function locate()
			local layer = root:FindFirstAncestorWhichIsA("LayerCollector")
			if placed or layer == nil or record.retired then
				return
			end
			local stack = stackFor(layer, edge)
			if stack.stop == nil and frames then
				stack.stop = frames.onFrame(function(dt: number)
					stack.time += dt
					stack.schedule.update()
				end)
			end
			local here: Placed = { stack = stack, id = 0, layer = layer :: GuiBase2d }
			placed = here
			here.id = stack.schedule.push({
				key = spec.key,
				priority = spec.priority,
				duration = spec.duration,
				readFloor = spec.readFloor,
				data = record,
			})
		end
		runtime.connect(root, "AncestryChanged", locate)
		locate()
		Compose.cleanup(function()
			if placed and not record.retired then
				placed.stack.schedule.dismiss(placed.id, "manual")
			end
		end)
		surfaces.attach(root, {
			surfaces.overlay(root, record.shown, function(phase)
				local at = assert(placed)
				return rowFor(record, at.stack, at.layer, phase)
			end, {
				presence = {
					exit = function()
						if reduced() then
							return { completed = Compose.cell(true) }
						end
						return { completed = runtime.timeline({ duration = 0.2 }).completed }
					end,
				},
			}),
		})
		Compose.watch(function(use: ComposeTypes.Use)
			root:SetAttribute("ToastVisible", use(record.shown))
		end)
		return root
	end)
end
