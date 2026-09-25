--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local Overlay = require("./overlay_types")
local Inputs = require("./input_types")
local ComposeTypes = require("../vendor/compose/core")
local parts = require("./overlay_parts")
local reservations = require("./reservations")

type Controls = {
	Snackbar: Types.Constructor<Overlay.SnackbarSpec, Frame>,
	Button: Types.Constructor<Inputs.ButtonProps, TextButton>,
}
type Phase = string
type Record = {
	serial: number,
	spec: Overlay.SnackbarSpec,
	phase: ComposeTypes.Cell<Phase>,
	readable: number,
	pending: Overlay.SnackbarDismissReason?,
	reported: boolean,
	forced: boolean,
	askedTimeout: boolean,
	askedSupersede: boolean,
	hovered: boolean,
	row: GuiObject?,
}

local KEYS = {
	"isPresented",
	"message",
	"icon",
	"action",
	"closeButton",
	"onPresentedChange",
	"onDismiss",
	"duration",
	"priority",
}
local CAPACITY = 9
local READ_FLOOR = 2.5
local ROW_Z = 60

return function(ctx: Types.Context, UI: Controls, surfaces: Nav.Surfaces): ()
	local Compose, Host, runtime, read = ctx.Compose, ctx.Host, ctx.runtime, ctx.read
	local E, D2, V2, UD = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2, ctx.types.UDim
	local frames = runtime.host.frames
	local gui = surfaces.service("GuiService")

	local records: { Record } = {}
	local serial = 0
	local admitted = 0
	local stopTick: (() -> ())? = nil
	local returnTo: GuiObject? = nil

	local function finite(value: unknown): boolean
		return type(value) == "number" and value == value and math.abs(value) < math.huge
	end

	local function validate(spec: Overlay.SnackbarSpec)
		local where = "UI.Snackbar"
		if spec.isPresented == nil or not parts.bound(ctx, spec.isPresented, "boolean") then
			error(`Facet {where}: isPresented is required; it is the caller's boolean fact`, 0)
		end
		if not parts.bound(ctx, spec.message, "string") then
			error(`Facet {where}: message is required; it is a string or a bound string`, 0)
		end
		if spec.icon ~= nil and (type(spec.icon) ~= "string" or spec.icon == "") then
			error(`Facet {where}: icon must be an icon name or an image source`, 0)
		end
		local action = spec.action
		if action ~= nil then
			if type(action) ~= "table" then
				error(`Facet {where}: action must be \{ label, onActivate }`, 0)
			end
			parts.known(where, (action :: unknown) :: { [string]: unknown }, { "label", "onActivate" }, "action")
			if not parts.bound(ctx, action.label, "string") or type(action.onActivate) ~= "function" then
				error(`Facet {where}: action needs a label and an onActivate function`, 0)
			end
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
		if spec.duration ~= nil and not (finite(spec.duration) and (spec.duration :: number) > 0) then
			error(`Facet {where}: duration must be positive finite seconds, or nil for a persistent row`, 0)
		end
		if spec.priority ~= nil and not finite(spec.priority) then
			error(`Facet {where}: priority must be a finite number`, 0)
		end
		if (spec.closeButton ~= false or spec.duration ~= nil) and spec.onPresentedChange == nil then
			error(
				`Facet {where}: a close button or a duration proposes a close and needs onPresentedChange. `
					.. "A read-only snackbar sets closeButton = false and no duration.",
				0
			)
		end
	end

	local function wanted(rec: Record): boolean
		return read(rec.spec.isPresented) == true
	end

	local function active(): Record?
		for _, rec in records do
			if rec.phase:peek() == "active" then
				return rec
			end
		end
		return nil
	end

	local function report(rec: Record, reason: Overlay.SnackbarDismissReason)
		if rec.forced or rec.reported then
			return
		end
		rec.reported = true
		if rec.spec.onDismiss then
			rec.spec.onDismiss(reason)
		end
	end

	local function finish(rec: Record)
		local index = table.find(records, rec)
		if index then
			table.remove(records, index)
			admitted -= 1
		end
	end

	local schedule: () -> ()

	local function propose(rec: Record, reason: Overlay.SnackbarDismissReason): boolean
		local change = rec.spec.onPresentedChange
		if rec.phase:peek() == "retiring" or change == nil then
			return false
		end
		rec.pending = reason
		local accepted = false
		parts.call(change, function()
			accepted = rec.phase:peek() == "retiring" or not wanted(rec)
			if not accepted then
				rec.pending = nil
			end
		end, false)
		return accepted
	end

	local function remove(rec: Record, reason: Overlay.SnackbarDismissReason)
		local phase = rec.phase:peek()
		if phase == "retiring" then
			return
		end
		if phase == "queued" then
			finish(rec)
			rec.phase:set("retiring")
		else
			local row = rec.row
			if gui and row and surfaces.within(gui.SelectedObject, row) then
				gui.SelectedObject = if returnTo and returnTo.Parent then returnTo else nil
			end
			rec.phase:set("retiring")
			if rec.row == nil then
				finish(rec)
			end
		end
		report(rec, reason)
		schedule()
	end

	local function paused(rec: Record): boolean
		if rec.row == nil or rec.hovered then
			return true
		end
		if gui and surfaces.within(gui.SelectedObject, rec.row) then
			return true
		end
		return #ctx.modalScopes:peek() > 0
	end

	local function tick(dt: number)
		local rec = active()
		if rec == nil then
			if stopTick then
				stopTick()
				stopTick = nil
			end
			return
		end
		if not paused(rec) then
			rec.readable += dt
		end
		local spec = rec.spec
		if spec.duration and not rec.askedTimeout and rec.readable >= math.max(spec.duration, READ_FLOOR) then
			rec.askedTimeout = true
			propose(rec, "timeout")
			return
		end
		schedule()
	end

	local function ensureTick()
		if stopTick == nil and frames then
			stopTick = frames.onFrame(tick)
		end
	end

	function schedule()
		local current = active()
		local best: Record? = nil
		for _, rec in records do
			if rec.phase:peek() == "queued" then
				local priority = rec.spec.priority or 0
				if best == nil or priority > (best.spec.priority or 0) then
					best = rec
				end
			end
		end
		if current == nil then
			if best then
				best.phase:set("active")
				ensureTick()
			end
			return
		end
		if
			best
			and (best.spec.priority or 0) > (current.spec.priority or 0)
			and current.readable >= READ_FLOOR
			and not current.askedSupersede
		then
			current.askedSupersede = true
			propose(current, "superseded")
		end
	end

	local function admit(spec: Overlay.SnackbarSpec): Record
		if admitted >= CAPACITY then
			error(
				`Facet UI.Snackbar: the snackbar queue is full ({CAPACITY} shown, waiting or leaving). `
					.. "Hide one before showing another; this admission was refused and nothing else moved.",
				0
			)
		end
		serial += 1
		local phase: ComposeTypes.Cell<Phase> = Compose.cell("queued" :: Phase)
		local rec: Record = {
			serial = serial,
			spec = spec,
			phase = phase,
			readable = 0,
			pending = nil,
			reported = false,
			forced = false,
			askedTimeout = false,
			askedSupersede = false,
			hovered = false,
			row = nil,
		}
		table.insert(records, rec)
		admitted += 1
		schedule()
		return rec
	end

	local function trackReturn()
		if gui and gui.GetPropertyChangedSignal then
			local selection = ctx.observe.SelectedObject(gui)
			Compose.watch(function(use: ComposeTypes.Use)
				local selected = use(selection)
				if selected == nil then
					return
				end
				for _, rec in records do
					if rec.row and surfaces.within(selected, rec.row) then
						return
					end
				end
				returnTo = selected
			end)
		end
	end

	local function rowFor(rec: Record, phase: Nav.PresencePhase?, anchor: GuiObject): Instance
		local spec = rec.spec
		local layer = anchor:FindFirstAncestorWhichIsA("LayerCollector")
		if layer == nil then
			return Host.Folder "Detached" {}
		end
		local extent = ctx.observe.AbsoluteSize(layer)
		local origin = ctx.observe.AbsolutePosition(layer)
		local closable = spec.closeButton ~= false
		local constrained = spec.action ~= nil or closable
		local function cap(use: ComposeTypes.Use): number
			return math.max(0, math.min(ctx.metric("controls.snackbar.maxWidth", use), use(extent).X - 32))
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
		local actionWidth = Compose.cell(0)
		local chrome = function(use: ComposeTypes.Use): number
			local package = ctx.read(ctx.config.theme, use)
			local panel = if package and package.chrome then package.chrome.panel else nil
			local insets = if panel then panel.contentInsets else nil
			return math.max(8, if insets then insets.left or 0 else 0)
				+ math.max(8, if insets then insets.right or 0 else 0)
				+ (if spec.icon then ctx.controlSize(nil, "iconSize", use) + 8 else 0)
				+ (if closable then 44 + 8 else 0)
		end
		local beside = Compose.formula(function(use: ComposeTypes.Use): boolean
			if spec.action == nil then
				return true
			end
			return math.ceil(use(natural).X) + use(actionWidth) + 8 + chrome(use) <= cap(use)
		end)
		local width = Compose.formula(function(use: ComposeTypes.Use): number
			if constrained then
				return cap(use)
			end
			return math.min(cap(use), math.ceil(use(natural).X) + chrome(use) + 2)
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
		local bodyProps: Types.FrameNativeProps = {
			Name = "Body",
			BackgroundTransparency = 1,
			LayoutOrder = 2,
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
				HorizontalAlignment = E.HorizontalAlignment.Right,
				VerticalAlignment = E.VerticalAlignment.Center,
				SortOrder = E.SortOrder.LayoutOrder,
				Padding = UD.new(0, 8),
			})
		)
		local messageFlex = Host.UIFlexItem({
			FlexMode = function(use: ComposeTypes.Use)
				return if use(beside) then E.UIFlexMode.Fill else E.UIFlexMode.None
			end,
		})
		surfaces.attach(message, { messageFlex })
		table.insert(bodyProps, message)
		table.insert(bodyProps, measure)
		if spec.action then
			local action = spec.action
			local button = UI.Button "Action" {
				label = action.label,
				appearance = "link",
				LayoutOrder = 2,
				onActivate = function()
					if rec.phase:peek() ~= "active" then
						return
					end
					rec.pending = "action"
					parts.call(action.onActivate, function()
						if rec.phase:peek() ~= "retiring" then
							rec.pending = nil
						end
					end)
				end,
			}
			local size = ctx.observe.AbsoluteSize(button)
			Compose.watch(function(use: ComposeTypes.Use)
				actionWidth:set(use(size).X)
			end)
			table.insert(bodyProps, button)
		end
		local rowProps: Types.CanvasGroupNativeProps = {
			Name = "Snack",
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			ZIndex = ROW_Z,
			AnchorPoint = V2.new(0.5, 1),
			AutomaticSize = E.AutomaticSize.Y,
			Size = function(use: ComposeTypes.Use)
				return D2.fromOffset(use(width), 0)
			end,
		}
		local function inset(side: "left" | "right" | "top" | "bottom"): (ComposeTypes.Use) -> UDim
			return function(use: ComposeTypes.Use): UDim
				local package = ctx.read(ctx.config.theme, use)
				local chrome = if package and package.chrome then package.chrome.panel else nil
				local insets = if chrome then chrome.contentInsets else nil
				local value = if insets then insets[side] else nil
				return UD.new(0, math.max(8, value or 0))
			end
		end
		table.insert(
			rowProps,
			Host.UIPadding({
				PaddingLeft = inset("left"),
				PaddingRight = inset("right"),
				PaddingTop = inset("top"),
				PaddingBottom = inset("bottom"),
			})
		)
		table.insert(rowProps, ctx.corner())
		table.insert(
			rowProps,
			Host.UIListLayout({
				FillDirection = E.FillDirection.Horizontal,
				VerticalAlignment = E.VerticalAlignment.Center,
				SortOrder = E.SortOrder.LayoutOrder,
				Padding = UD.new(0, 8),
			})
		)
		if spec.icon then
			table.insert(rowProps, ctx.icon(spec.icon, { Name = "Icon", LayoutOrder = 0 }))
		end
		table.insert(rowProps, Host.Frame(bodyProps))
		if closable then
			table.insert(
				rowProps,
				UI.Button "Close" {
					name = "Close",
					icon = "close",
					LayoutOrder = 3,
					Size = D2.fromOffset(44, 44),
					AutomaticSize = E.AutomaticSize.None,
					onActivate = function()
						propose(rec, "close")
					end,
				}
			)
		end
		local row = ctx.styled(Host.CanvasGroup(rowProps), "snackbar")
		ctx.styled(row, "panel")
		surfaces.skin(row, "panel")
		local gone = Compose.cell(0)
		local reduced = if gui then ctx.observe.ReducedMotionEnabled(gui) else Compose.cell(false)
		local shown = Compose.cell(false)
		local slide = runtime.tween(function(use: ComposeTypes.Use)
			return if phase and use(phase.exiting) then 0 elseif use(shown) then 1 else 0
		end, { seconds = 0.2, ease = Compose.easing.outCubic })
		local function amount(use: ComposeTypes.Use): number
			if read(ctx.config.reducedMotion, use) == true or use(reduced) then
				return if phase and use(phase.exiting) then 0 else 1
			end
			return use(slide)
		end
		local measured = ctx.observe.AbsoluteSize(row)
		runtime.decorate(row, {
			Position = function(use: ComposeTypes.Use)
				local travel = (1 - amount(use)) * (use(measured).Y + 16)
				return D2.new(0.5, 0, 1, -16 + travel + use(gone))
			end,
			GroupTransparency = function(use: ComposeTypes.Use)
				return 1 - amount(use)
			end,
			Interactable = function(use: ComposeTypes.Use)
				return not (phase and use(phase.exiting))
			end,
		})
		local state = ctx.observe.GuiState(row)
		Compose.watch(function(use: ComposeTypes.Use)
			rec.hovered = use(state) == E.GuiState.Hover
		end)
		rec.row = row
		local token = {}
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
			reservations.clear(layer, token)
			if rec.row == row then
				rec.row = nil
			end
			if rec.phase:peek() == "retiring" then
				finish(rec)
				schedule()
			end
		end)
		local selection: ComposeTypes.Readable<GuiObject?> = if gui and gui.GetPropertyChangedSignal
			then ctx.observe.SelectedObject(gui)
			else Compose.cell(nil :: GuiObject?)
		ctx.action(row, "SnackbarCancel", { E.KeyCode.ButtonB, E.KeyCode.Escape }, function(use: ComposeTypes.Use)
			local selected = use(selection)
			return selected ~= nil and surfaces.within(selected, row)
		end, function()
			local back = returnTo
			propose(rec, "cancel")
			if gui and back and back.Parent and gui.SelectedObject ~= back then
				gui.SelectedObject = back
			end
		end, { priority = 2500 })
		local parent = ctx.observe.Parent(row)
		Compose.watch(function(use: ComposeTypes.Use)
			if use(parent) then
				shown:set(true)
			end
		end)
		return row
	end

	UI.Snackbar = ctx.construct("Snackbar", function(spec: Overlay.SnackbarSpec): Frame
		validate(spec)
		trackReturn()
		local root = Host.Frame(
			ctx.props(spec, KEYS, { Name = "Snackbar", BackgroundTransparency = 1, Size = D2.fromOffset(0, 0) })
		)
		local slot: ComposeTypes.Cell<Record?> = Compose.cell(nil :: Record?)
		local function sync(want: boolean)
			local current = slot:peek()
			if want and (current == nil or current.phase:peek() == "retiring") then
				slot:set(admit(spec))
			elseif not want and current and current.phase:peek() ~= "retiring" then
				remove(current, current.pending or "cancel")
			end
		end
		local initial = read(spec.isPresented) == true
		if initial then
			sync(true)
		end
		local last = initial
		Compose.watch(function(use: ComposeTypes.Use)
			local want = read(spec.isPresented, use) == true
			if want ~= last then
				last = want
				sync(want)
			end
		end)
		local phaseOf = function(use: ComposeTypes.Use): string?
			local current = use(slot)
			if current == nil then
				return nil
			end
			local phase: string = use(current.phase)
			return phase
		end
		local function current(): Record?
			return slot:peek()
		end
		surfaces.attach(root, {
			surfaces.overlay(root, function(use: ComposeTypes.Use): boolean
				return phaseOf(use) == "active"
			end, function(phase)
				return rowFor(assert(current()), phase, root)
			end, {
				presence = {
					exit = function()
						if read(ctx.config.reducedMotion) == true or (gui ~= nil and gui.ReducedMotionEnabled) then
							return { completed = Compose.cell(true) }
						end
						local motion = runtime.timeline({ duration = 0.2 })
						return { completed = motion.completed }
					end,
				},
			}),
		})
		Compose.cleanup(function()
			local mine = slot:peek()
			if mine and mine.phase:peek() ~= "retiring" then
				remove(mine, "cancel")
			end
		end)
		root:SetAttribute("SnackbarAdmitted", false)
		Compose.watch(function(use: ComposeTypes.Use)
			local phase = phaseOf(use)
			root:SetAttribute("SnackbarAdmitted", phase ~= nil and phase ~= "retiring")
			root:SetAttribute("SnackbarVisible", phase == "active")
			root:SetAttribute("SnackbarQueued", phase == "queued")
		end)
		return root
	end)
end
