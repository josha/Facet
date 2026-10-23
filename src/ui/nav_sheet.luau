--!strict
local ControlTypes = require("./control_types")
local Types = require("./types")
local Nav = require("./navigation_types")
local ComposeTypes = require("../vendor/compose/core")
local fontReadiness = require("./font_readiness")
local NavigationProps = require("./navigation_props")
local sheetDetents = require("./nav_sheet_detents")
local sheetGesture = require("./nav_sheet_gesture")
local sheetContent = require("./nav_sheet_content")
local transitions = require("./transition")
local arrival = require("./overlay_arrival")

type Prepared = sheetDetents.Prepared

local KEYS = {
	"title",
	"content",
	"detent",
	"detents",
	"isPresented",
	"onPresentedChange",
	"interactiveDismissDisabled",
	"dragIndicator",
	"placement",
	"edge",
	"width",
	"closeButton",
	"header",
	"hero",
	"actions",
	"actionLayout",
	"contentInset",
	"scrollPolicy",
	"transition",
	"initialFocus",
	"guide",
	"guideAlignment",
}
return function(ctx: Types.Context, UI: ControlTypes.BuilderControls, surfaces: Nav.Surfaces): ()
	local Compose, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local readSource = ctx.readSource
	local E, D2, V2 = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2
	local frames = runtime.host.frames
	local detents = sheetDetents(ctx)
	local prepare, writableDetent = detents.prepare, detents.writableDetent
	local gestureFor = sheetGesture(ctx, UI, surfaces, detents.word)
	local contentFor = sheetContent(ctx, UI, surfaces)

	local function modalFor(
		spec: NavigationProps.SheetSpec,
		detent: ComposeTypes.Cell<string>,
		prepared: Prepared,
		request: Nav.SheetRequest?,
		phase: Nav.PresencePhase?,
		anchor: GuiObject?
	): Frame
		transitions.check(spec.transition)
		assert(
			spec.initialFocus == nil or type(spec.initialFocus) == "string" or type(spec.initialFocus) == "function",
			"Facet.Sheet: initialFocus must be a name or a function that returns one"
		)
		local gesture = gestureFor(spec, detent, prepared, request, phase, anchor)
		local placed, edge, ready, toward = gesture.placed, gesture.edge, gesture.ready, gesture.toward
		local pulled, painted, keyboard, standing = gesture.pulled, gesture.painted, gesture.keyboard, gesture.standing
		local level, handle, detector, pad = gesture.level, gesture.handle, gesture.detector, gesture.pad
		local canDismiss, interactive, lowest = gesture.canDismiss, gesture.interactive, gesture.lowest
		local unit, extent = gesture.unit, gesture.extent
		local sheetBody = contentFor(spec, gesture)
		local room, plaqued, usable, press = sheetBody.room, sheetBody.plaqued, sheetBody.usable, sheetBody.press
		local panelWidth, contentSize = sheetBody.panelWidth, sheetBody.contentSize
		local function anchors(use: ComposeTypes.Use): (number, number)
			local placement = use(placed)
			return if placement == "side" then (if edge == "left" then 0 else 1) else 0.5,
				if placement == "center" then 0.5 else 1
		end
		local shown: Nav.Presence
		local moving: transitions.Motion? = nil
		if spec.transition ~= nil then
			local arrived = arrival.ready(phase)
			moving = transitions.create(
				ctx,
				if spec.transition == false then {} else spec.transition,
				Compose.formula(function(use: Types.Use): boolean
					return phase == nil or not use(phase.exiting)
				end),
				false,
				Compose.formula(function(use: Types.Use): boolean
					return use(ready) and (arrived == nil or use(arrived))
				end),
				spec.transition == false
			)
			local custom = assert(moving)
			if phase then
				transitions.completions[phase] = custom.completed
				Compose.cleanup(function()
					transitions.completions[phase] = nil
				end)
			end
			shown = {
				travel = function(): number
					return 1
				end,
				opacity = function(use: Types.Use?): number
					return ctx.read(custom.opacity, use)
				end,
			}
		else
			shown = surfaces.appearance(phase, ctx.motionTiming("sheet"), ready)
		end
		local function travel(use: ComposeTypes.Use): (number, number)
			local rest = 1 - shown.travel(use)
			if rest <= 0 then
				return if use(placed) == "side" then toward() * pulled(use) else 0, 0
			end
			local placement = use(placed)
			if placement == "side" then
				local shift = pulled(use)
				return toward() * (shift + (use(panelWidth) - shift) * rest), 0
			end
			if placement == "center" then
				return 0, 0
			end
			return 0, math.ceil(painted(use) * rest)
		end
		runtime.decorate(room.frame, {
			[Compose.group({ "Position", "Size" })] = function(use: ComposeTypes.Use): (UDim2, UDim2)
				local left, top, right, bottom =
					pad("left", use), pad("top", use), pad("right", use), pad("bottom", use)
				local height = standing(use) - top - bottom - sheetBody.guideReserve(use)
				return D2.fromOffset(left, top), D2.new(1, -left - right, 0, math.max(0, height))
			end,
		})
		local panelProps: Types.CanvasGroupNativeProps = {
			Name = "SheetPanel",
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			AnchorPoint = function(use: ComposeTypes.Use)
				local anchorX, anchorY = anchors(use)
				return V2.new(anchorX, anchorY)
			end,
			Position = function(use: ComposeTypes.Use)
				local anchorX, anchorY = anchors(use)
				local y = (if anchorY == 1 then -keyboard(use) else -keyboard(use) / 2) + standing(use) - painted(use)
				local dx, dy = travel(use)
				return D2.new(anchorX, dx, anchorY, y + dy)
			end,
			AutomaticSize = E.AutomaticSize.None,
			Size = function(use: ComposeTypes.Use)
				return D2.fromOffset(use(panelWidth), standing(use))
			end,
			GroupTransparency = function(use: ComposeTypes.Use)
				return if moving
					then 0
					elseif not use(ready) then 1
					elseif level(use) == "limited" then 1 - shown.opacity(use)
					else 0
			end,
		}
		for _, child in { handle, room.frame, ctx.corner(), detector("PanelDrag", "panel") } :: { Instance } do
			panelProps[#panelProps + 1] = child
		end
		if sheetBody.guide then
			panelProps[#panelProps + 1] = sheetBody.guide
		end
		local panel = ctx.fade(panelProps, true)
		local presentation: GuiObject = panel
		if moving then
			local custom = moving
			presentation = ctx.fade({
				Name = "SheetTransition",
				BackgroundTransparency = 1,
				AnchorPoint = panelProps.AnchorPoint,
				Position = panelProps.Position,
				Size = panelProps.Size,
				GroupTransparency = function(use: Types.Use): number
					return use(custom.transparency)
				end,
				Interactable = function(use: Types.Use): boolean
					return not use(custom.interacting)
						and use(custom.opacity) == 1
						and (phase == nil or not use(phase.exiting))
				end,
				panel,
			}, nil, false)
			runtime.decorate(panel, {
				AnchorPoint = V2.zero,
				Position = D2.fromScale(0, 0),
				Size = D2.fromScale(1, 1),
			})
			custom.apply(panel)
		end
		ctx.styled(panel, "sheet")
		runtime.decorate(panel, {
			Attributes = {
				FacetPlacement = function(use: ComposeTypes.Use): string
					return use(placed)
				end,
			},
		})
		surfaces.skin(panel, nil, {
			padding = false,
			title = if spec.header == nil then spec.title else nil,
			onCaption = function(on: boolean)
				plaqued:set(on)
			end,
		})
		local overlay = surfaces.modal(function()
			return presentation
		end, function()
			if not canDismiss() then
				return
			end
			if prepared.cancel and usable(prepared.cancel) then
				press(prepared.cancel)
			else
				interactive("cancel")
			end
		end, {
			entry = sheetBody.entry,
			canDismiss = function(use: ComposeTypes.Use)
				return canDismiss(use)
			end,
			onOutside = function()
				interactive("outside")
			end,
			exiting = if phase then phase.exiting else nil,
			appearance = function(use: ComposeTypes.Use?): number
				local base = shown.opacity(use)
				if not canDismiss(use) then
					return base
				end
				if readSource(placed, use) == "side" then
					local width = readSource(panelWidth, use)
					return if width > 0 then base * math.clamp(1 - pulled(use) / width, 0, 1) else base
				end
				local rest = lowest(use)
				return if rest > 0 then base * math.clamp(painted(use) / rest, 0, 1) else base
			end,
		})
		local scale = ctx.layoutUnit(overlay)
		Compose.watch(function(use: ComposeTypes.Use)
			unit:set(use(scale))
		end)
		local size = ctx.layoutSize(overlay, unit)
		local measured = Compose.cell(false)
		Compose.watch(function(use: ComposeTypes.Use)
			local value = use(size)
			if value.Y > 0 then
				extent:set(value)
				measured:set(true)
			end
		end)
		if frames and not ready:peek() then
			local function contentGeometry(): string
				local origin = panel.AbsolutePosition
				local signature: { string } = {}
				for _, node in panel:GetDescendants() do
					if node:IsA("GuiObject") then
						local entry = `{node.AbsolutePosition - origin}:{node.AbsoluteSize}:{node.Visible}`
						if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
							entry ..= `:{node.TextBounds}`
						end
						table.insert(signature, entry)
					end
				end
				return table.concat(signature, ";")
			end
			local fontsReady = fontReadiness(ctx, { panel })
			local settled = runtime.settled {
				ready = fontsReady,
				sample = function(): string
					return string.format(
						"%d %d %d %d %d %s",
						extent:peek().X,
						extent:peek().Y,
						panel.AbsoluteSize.X,
						contentSize:peek().Y,
						room.pinned:peek(),
						contentGeometry()
					)
				end,
				equals = function(left: string, right: string): boolean
					return measured:peek() and left == right
				end,
				timeout = ctx.metric("motion.restLimit"),
			}
			Compose.watch(function(use: ComposeTypes.Use)
				if use(settled) then
					ready:set(true)
				end
			end)
		end
		surfaces.keep(spec.content, spec.header, spec.hero and spec.hero.content)
		return overlay
	end

	UI.Sheet = ctx.construct("Sheet", function(spec: NavigationProps.SheetSpec): Frame
		assert(
			spec.onPresentedChange == nil or type(spec.onPresentedChange) == "function",
			"Sheet.onPresentedChange must be a function"
		)
		local prepared = prepare(spec)
		local detent = writableDetent(spec, prepared)
		assert(
			type(spec.isPresented) == "table" and spec.isPresented.set,
			"Sheet.isPresented requires a writable Compose cell"
		)
		local root = Host.Frame(
			ctx.props(spec, KEYS, { Name = "Sheet", BackgroundTransparency = 1, Size = D2.fromOffset(0, 0) })
		)
		surfaces.attach(root, {
			surfaces.overlay(root, spec.isPresented, function(phase)
				return modalFor(spec, detent, prepared, nil, phase, root)
			end, {
				motion = ctx.motionTiming("sheet"),
				failure = function(failure)
					root:SetAttribute("FacetError", tostring(failure))
					spec.isPresented:set(false)
					if ctx.config.onError then
						ctx.config.onError(failure)
					end
					return Host.Folder "FailedSheet" {}
				end,
			}),
		})
		return root
	end)

	surfaces.sheetModal = function(
		spec: NavigationProps.SheetSpec,
		request: Nav.SheetRequest,
		phase: Nav.PresencePhase?
	): Frame
		local prepared = prepare(spec)
		return modalFor(spec, writableDetent(spec, prepared), prepared, request, phase, nil)
	end
end
