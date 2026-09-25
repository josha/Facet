--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local Overlay = require("./overlay_types")
local ComposeTypes = require("../vendor/compose/core")
local parts = require("./overlay_parts")
local placement = require("./overlay_placement")
local activation = require("./activation")
local freeze = require("./freeze")

type Controls = { Popover: Types.Constructor<Overlay.PopoverSpec, GuiObject> }

local KEYS = {
	"isPresented",
	"onPresentedChange",
	"onDismiss",
	"trigger",
	"source",
	"content",
	"edge",
	"align",
	"gap",
	"crossOffset",
	"tail",
	"maxWidth",
	"maxHeight",
	"compact",
	"title",
}
local POPOVER: { enter: number, exit: number } = freeze({ enter = 0.15, exit = 0.1 })
local SHEET_EXIT = 0.2
local MARGIN = 8
local TAIL = 10
local PADDING = 8

return function(ctx: Types.Context, UI: Controls, surfaces: Nav.Surfaces): ()
	local Compose, Host, runtime, read = ctx.Compose, ctx.Host, ctx.runtime, ctx.read
	local E, D2, V2 = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2

	local function finite(value: unknown): boolean
		return type(value) == "number" and value == value and math.abs(value) < math.huge
	end

	UI.Popover = ctx.construct("Popover", function(spec: Overlay.PopoverSpec): GuiObject
		local where = "UI.Popover"
		if spec.isPresented == nil then
			error(`Facet {where}: isPresented is required; it is the caller's boolean fact`, 0)
		end
		for _, key in { "onPresentedChange", "onDismiss" } do
			local value = (spec :: { [unknown]: unknown })[key]
			if value ~= nil and type(value) ~= "function" then
				error(`Facet {where}: {key} must be a function`, 0)
			end
		end
		if type(spec.content) ~= "function" then
			error(`Facet {where}: content must be a factory that returns the content`, 0)
		end
		if (spec.trigger == nil) == (spec.source == nil) then
			error(`Facet {where}: supply exactly one of trigger or source`, 0)
		end
		local node: GuiObject? = nil
		local rect: Overlay.Rect? = nil
		if spec.source ~= nil then
			local source = (spec.source :: unknown) :: { [string]: unknown }
			if type(source) ~= "table" then
				error(`Facet {where}: source is \{ node = GuiObject } or \{ rect = \{ x, y, w, h } }`, 0)
			end
			for key in source do
				if key ~= "node" and key ~= "rect" then
					error(`Facet {where}: unknown source option '{tostring(key)}'`, 0)
				end
			end
			if (source.node == nil) == (source.rect == nil) then
				error(`Facet {where}: source names exactly one of node or rect`, 0)
			end
			if source.rect ~= nil then
				local box = source.rect :: { [string]: unknown }
				for _, key in { "x", "y", "w", "h" } do
					if not finite(box[key]) then
						error(`Facet {where}: source.rect.{key} must be a finite number`, 0)
					end
				end
				rect = { x = box.x :: number, y = box.y :: number, w = box.w :: number, h = box.h :: number }
			else
				if not parts.instance(source.node) then
					error(`Facet {where}: source.node must be a GuiObject`, 0)
				end
				node = source.node :: GuiObject
			end
		end
		placement.assertEdge(spec.edge, where)
		placement.assertAlign(spec.align, where)
		placement.assertCrossOffset(spec.crossOffset, where)
		for _, key in { "maxWidth", "maxHeight" } do
			local value = (spec :: { [unknown]: unknown })[key]
			if value ~= nil and not (finite(value) and (value :: number) > 0) then
				error(`Facet {where}: {key} must be a positive finite number of pixels`, 0)
			end
		end
		if spec.gap ~= nil and not finite(spec.gap) then
			error(`Facet {where}: gap must be a finite number of pixels`, 0)
		end
		if spec.tail ~= nil and type(spec.tail) ~= "boolean" then
			error(`Facet {where}: tail must be true or false`, 0)
		end
		if spec.title ~= nil and not parts.bound(ctx, spec.title, "string") then
			error(`Facet {where}: title must be a string or a bound string`, 0)
		end
		local compact = spec.compact or "sheet"
		if compact ~= "sheet" and compact ~= "popover" then
			error(`Facet {where}: compact must be sheet or popover`, 0)
		end

		local owner = assert(Compose.currentOwner())
		local props = ctx.props(spec, KEYS, {})
		local root: GuiObject
		if spec.trigger then
			root = spec.trigger
			local native = table.clone((props :: unknown) :: { [unknown]: unknown })
			native.Name = nil
			if next(native) ~= nil then
				runtime.decorate(root, (native :: unknown) :: Types.GuiObjectNativeProps)
			end
		else
			local frame = Host.Frame(
				ctx.props(spec, KEYS, { Name = "Popover", BackgroundTransparency = 1, Size = D2.fromOffset(0, 0) })
			)
			root = frame
		end
		local name = ((props :: unknown) :: { Name: string? }).Name or "Popover"
		local function wanted(): boolean
			return read(spec.isPresented) == true
		end
		local lost = Compose.cell(false)
		local mounted = Compose.cell(true)
		local closing: Overlay.PopoverDismissReason? = nil
		local losing = false
		local disposed = false
		local presented = false
		local warned = false
		local function report(reason: Overlay.PopoverDismissReason)
			if spec.onDismiss then
				spec.onDismiss(reason)
			end
		end
		local function propose(nextValue: boolean, reason: Overlay.PopoverDismissReason): boolean
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
		if spec.trigger then
			local trigger = spec.trigger
			local function pressed()
				if trigger.Interactable ~= false and ctx.available(trigger) then
					propose(not wanted(), "trigger")
				end
			end
			if activation.marked(trigger) then
				Compose.cleanup(activation.listen(trigger, pressed))
			else
				runtime.connect(trigger, "Activated", pressed)
			end
		end
		if node then
			local target = node
			local function check()
				local here = target.Parent ~= nil and target:FindFirstAncestorWhichIsA("LayerCollector") ~= nil
				if not here and presented and not losing then
					losing = true
					lost:set(true)
					mounted:set(false)
					losing = false
					propose(false, "anchorLost")
					closing = nil
					report("anchorLost")
					return
				end
				mounted:set(here)
			end
			runtime.connect(target, "AncestryChanged", check)
			check()
		end
		local input = surfaces.service("UserInputService")
		local preferred: ComposeTypes.Readable<Enum.PreferredInput>? = if input
				and input.GetPropertyChangedSignal
			then ctx.observe.PreferredInput(input)
			else nil
		local layerSize = Compose.cell(V2.zero)
		local layerOwner: ComposeTypes.Owner? = nil
		local function locateLayer()
			if owner.isDisposed() then
				return
			end
			if layerOwner then
				layerOwner.dispose()
			end
			local child = owner.createChild()
			layerOwner = child
			Compose.withOwner(child, function()
				local layer = root:FindFirstAncestorWhichIsA("LayerCollector")
				if layer then
					local size = ctx.observe.AbsoluteSize(layer)
					Compose.watch(function(use: ComposeTypes.Use)
						layerSize:set(use(size))
					end)
				end
			end)
		end
		runtime.connect(root, "AncestryChanged", locateLayer)
		locateLayer()
		local route = Compose.formula(function(use: ComposeTypes.Use): "sheet" | "popover"
			if compact == "popover" then
				return "popover"
			end
			local width = use(layerSize).X
			local kind = if preferred then use(preferred) else nil
			return if kind == E.PreferredInput.Touch and width > 0 and width < 600 then "sheet" else "popover"
		end)
		local motion: Nav.MotionTiming = { enter = POPOVER.enter, exit = POPOVER.exit }
		Compose.watch(function(use: ComposeTypes.Use)
			motion.exit = if use(route) == "sheet" then SHEET_EXIT else POPOVER.exit
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			if read(spec.isPresented, use) ~= true then
				lost:set(false)
			end
		end)
		local condition = function(use: ComposeTypes.Use): boolean
			local want = read(spec.isPresented, use) == true
			local ready = use(mounted)
			if want and not ready and not warned and node ~= nil then
				warned = true
				warn(`Facet {where}: the source node '{node.Name}' is not mounted yet; the popover waits for it`)
			end
			return want and ready and not use(lost)
		end
		local function anchored(phase: Nav.PresencePhase?): Frame
			local amount = surfaces.appearance(phase, POPOVER)
			local layer = assert(root:FindFirstAncestorWhichIsA("LayerCollector"))
			local extent = ctx.observe.AbsoluteSize(layer)
			local origin = ctx.observe.AbsolutePosition(layer)
			local sourceAt: ComposeTypes.Readable<Vector2>, sourceSize: ComposeTypes.Readable<Vector2>
			local anchorNode = node or spec.trigger
			if anchorNode then
				sourceAt, sourceSize = ctx.observe.AbsolutePosition(anchorNode), ctx.observe.AbsoluteSize(anchorNode)
			else
				sourceAt, sourceSize = Compose.cell(V2.zero), Compose.cell(V2.zero)
			end
			local function safe(use: ComposeTypes.Use): Overlay.Rect
				local size = use(extent)
				return {
					x = MARGIN,
					y = MARGIN,
					w = math.max(0, size.X - 2 * MARGIN),
					h = math.max(0, size.Y - 2 * MARGIN),
				}
			end
			local content = spec.content()
			local function cap(use: ComposeTypes.Use): Vector2
				local box = safe(use)
				local width = math.min(spec.maxWidth or math.huge, box.w)
				local height = math.min(spec.maxHeight or math.huge, box.h)
				return V2.new(math.max(0, width - 2 * PADDING), math.max(0, height - 2 * PADDING))
			end
			local limit = Host.UISizeConstraint({
				MaxSize = cap,
			})
			local list = Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder })
			local laidOut = ctx.observe.AbsoluteContentSize(list)
			local bodyProps: Types.ScrollingFrameNativeProps = {
				Name = "Body",
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Size = function(use: ComposeTypes.Use)
					local extent = use(laidOut) :: Vector2
					return D2.fromOffset(0, math.min(extent.Y, cap(use).Y))
				end,
				AutomaticSize = E.AutomaticSize.X,
				ScrollingDirection = E.ScrollingDirection.Y,
				ScrollBarThickness = 4,
				VerticalScrollBarInset = E.ScrollBarInset.ScrollBar,
				Selectable = false,
			}
			table.insert(bodyProps, limit)
			local body = parts.scroller(ctx, bodyProps, { list, content }, { hug = true })
			local panel = ctx.styled(
				Host.CanvasGroup "Panel" {
					BackgroundTransparency = 0,
					BorderSizePixel = 0,
					Size = D2.fromOffset(0, 0),
					AutomaticSize = E.AutomaticSize.XY,
					ZIndex = 2,
					body :: Instance,
					ctx.padding(PADDING, PADDING),
					ctx.corner(),
				},
				"popover"
			)
			ctx.styled(panel, "panel")
			ctx.styled(panel, "floating")
			surfaces.skin(panel, "panel")
			local measured = ctx.observe.AbsoluteSize(panel)
			local tailed = rect == nil and spec.tail ~= false
			local solved = Compose.formula(function(use: ComposeTypes.Use): placement.Placement
				local offset = use(origin)
				local source: Overlay.Rect = if rect
					then rect
					else {
						x = use(sourceAt).X - offset.X,
						y = use(sourceAt).Y - offset.Y,
						w = use(sourceSize).X,
						h = use(sourceSize).Y,
					}
				local size = use(measured)
				return placement.solve({
					source = source,
					size = { w = size.X, h = size.Y },
					safe = safe(use),
					edge = spec.edge,
					align = spec.align,
					gap = spec.gap or 8,
					crossOffset = spec.crossOffset,
					tail = if tailed then TAIL else 0,
					tailInset = 8,
				})
			end)
			surfaces.popover(panel, amount, function(use: ComposeTypes.Use): (Vector2, Vector2)
				local at = use(solved)
				local size = use(measured)
				local origin = if at.edge == "bottom"
					then V2.new(math.clamp((at.tailX or at.x) - at.x, 0, size.X), 0)
					elseif at.edge == "top" then V2.new(math.clamp((at.tailX or at.x) - at.x, 0, size.X), size.Y)
					elseif at.edge == "right" then V2.new(0, math.clamp((at.tailY or at.y) - at.y, 0, size.Y))
					else V2.new(size.X, math.clamp((at.tailY or at.y) - at.y, 0, size.Y))
				return V2.new(at.x, at.y), origin
			end)
			local children: { Types.Child } = { panel }
			if tailed then
				table.insert(
					children,
					ctx.styled(
						Host.Frame "Tail" {
							Size = D2.fromOffset(TAIL, TAIL),
							AnchorPoint = V2.new(0.5, 0.5),
							Rotation = 45,
							BorderSizePixel = 0,
							ZIndex = 1,
							Visible = function(use: ComposeTypes.Use)
								return not use(solved).tailSuppressed
							end,
							Host.UIGradient "PresentationFade" {
								Transparency = function(use: ComposeTypes.Use)
									return ctx.types.NumberSequence.new(1 - amount(use))
								end,
							} :: Types.Child,
							Position = function(use: ComposeTypes.Use)
								local at = use(solved)
								return D2.fromOffset(at.tailX or 0, at.tailY or 0)
							end,
						},
						"panel"
					)
				)
			end
			local modal = surfaces.modal(function()
				return Host.Frame "Popup" {
					BackgroundTransparency = 1,
					Size = D2.fromScale(1, 1),
					table.unpack(children),
				}
			end, function()
				propose(false, "cancel")
			end, {
				Name = name .. "Modal",
				backgroundTransparency = 1,
				onOutside = function()
					propose(false, "outside")
				end,
				exiting = if phase then phase.exiting else nil,
				appearance = amount,
			})
			modal:SetAttribute("FacetRoute", "popover")
			return modal
		end
		local function sheeted(phase: Nav.PresencePhase?): Frame
			local build = assert(surfaces.sheetModal, "Facet UI.Popover requires the Sheet surface")
			local modal = build({
				isPresented = Compose.cell(true),
				detent = Compose.cell("hug"),
				detents = { "hug" :: Nav.SheetDetent },
				title = spec.title,
				content = spec.content,
			}, function(reason: string): boolean
				return propose(false, if reason == "outside" then "outside" else "cancel")
			end, phase)
			modal:SetAttribute("FacetRoute", "sheet")
			return modal
		end
		local gui = surfaces.service("GuiService")
		local pending: { string }? = nil
		local function pathTo(target: Instance?, base: Instance): { string }?
			local path: { string } = {}
			local at = target
			while at and at ~= base do
				table.insert(path, 1, at.Name)
				at = at.Parent
			end
			return if at == base then path else nil
		end
		surfaces.attach(root, {
			surfaces.overlay(root, condition, function(phase: Nav.PresencePhase?)
				presented = true
				Compose.cleanup(function()
					presented = false
					if losing then
						return
					end
					if disposed or owner.isDisposed() then
						closing = nil
						report("cancel")
						return
					end
					local reason: Overlay.PopoverDismissReason = closing or "cancel"
					closing = nil
					if wanted() and not lost:peek() then
						propose(false, "cancel")
						closing = nil
						report("cancel")
					else
						report(reason)
					end
				end)
				return Host.Folder "PopoverRoute" {
					Compose.keyed({
						from = function(use: ComposeTypes.Use): { string }
							return { use(route) }
						end,
						render = function(item: ComposeTypes.Readable<string>): Instance
							local modal = if item:peek() == "sheet" then sheeted(phase) else anchored(phase)
							local restore = pending
							pending = nil
							if restore and gui then
								local found: Instance? = modal
								for _, part in restore do
									found = if found then found:FindFirstChild(part, true) else nil
								end
								if found and found:IsA("GuiObject") then
									gui.SelectedObject = found
								end
							end
							Compose.cleanup(function()
								if gui and not disposed then
									local body = modal:FindFirstChild("Body", true)
										or modal:FindFirstChild("SheetContent", true)
									local path = if body then pathTo(gui.SelectedObject, body) else nil
									if path and #path > 0 then
										pending = { path[#path] }
									end
								end
							end)
							return modal
						end,
					}),
				}
			end, { motion = motion }),
		})
		Compose.cleanup(function()
			disposed = true
		end)
		return root
	end)
end
