--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local ComposeTypes = require("../vendor/compose/core")
local transitions = require("./transition")
local presentationReadiness = require("./presentation_readiness")
local preparation = require("./preparation")

export type PageLayers = {
	content: <P>(Instance | ((Nav.NavigationEntry<P>?) -> Instance), Nav.NavigationEntry<P>?) -> Instance,
	checkTransition: (Nav.Transition | false?) -> (),
	layer: (
		Types.CanvasGroupNativeProps & Types.FrameNativeProps,
		ComposeTypes.ReadOnlyValue<ComposeTypes.LayerStackState>,
		Nav.Transition | false?,
		(() -> ())?,
		boolean?,
		ComposeTypes.Value<boolean>?,
		ComposeTypes.ReadOnlyValue<boolean>?,
		boolean?
	) -> GuiObject,
	checkedSelection: (ComposeTypes.Value<string>, { Nav.Tab }, string) -> { [string]: Nav.Tab },
}

return function(ctx: Types.Context): PageLayers
	local Host, Compose, runtime = ctx.Host, ctx.Compose, ctx.runtime
	local function content<P>(
		builder: Instance | ((Nav.NavigationEntry<P>?) -> Instance),
		entry: Nav.NavigationEntry<P>?
	): Instance
		return if type(builder) == "function" then builder(entry) else builder
	end
	local checkTransition = transitions.check
	local function plate(panel: GuiObject, scale: ComposeTypes.ReadOnlyValue<number>)
		local ancestry = Compose.cell(0)
		runtime.connect(panel, "AncestryChanged", function()
			ancestry:set(ancestry:peek() + 1)
		end)
		local zooming = Compose.formula(function(use: ComposeTypes.Use): boolean
			return use(scale) ~= 1
		end)
		local backdrop = Compose.formula(function(use: ComposeTypes.Use): Color3?
			if not use(zooming) then
				return nil
			end
			use(ancestry)
			local at: Instance? = panel.Parent
			while at do
				if at:IsA("GuiObject") and (at:GetStyled("BackgroundTransparency") :: number) < 1 then
					return at:GetStyled("BackgroundColor3") :: Color3
				end
				at = at.Parent
			end
			return nil
		end)
		runtime.mountFragment(function()
			return {
				Compose.show(function(use: ComposeTypes.Use): boolean
					return use(backdrop) ~= nil
				end, function()
					local color = assert(backdrop:peek())
					return Host.Frame "TransitionPlate" {
						AnchorPoint = ctx.types.Vector2.new(0.5, 0.5),
						Position = ctx.types.UDim2.fromScale(0.5, 0.5),
						Size = ctx.types.UDim2.fromScale(1, 1),
						BorderSizePixel = 0,
						ZIndex = 0,
						Interactable = false,
						BackgroundColor3 = function(use: ComposeTypes.Use): Color3
							color = use(backdrop) or color
							return color
						end,
						Host.UIScale "TransitionScale" {
							Scale = scale,
						},
					}
				end),
			}
		end, panel)
	end
	local function layer(
		properties: Types.CanvasGroupNativeProps & Types.FrameNativeProps,
		state: ComposeTypes.ReadOnlyValue<ComposeTypes.LayerStackState>,
		transition: Nav.Transition | false?,
		hidden: (() -> ())?,
		immediate: boolean?,
		prepared: ComposeTypes.Value<boolean>?,
		groupReady: ComposeTypes.ReadOnlyValue<boolean>?,
		holdOnExit: boolean?
	): GuiObject
		if transition == nil or transition == false then
			local node = Host.Frame(properties)
			if hidden then
				Compose.watch(function(use: ComposeTypes.Use)
					if not use(state).top then
						hidden()
					end
				end)
			end
			return node
		end
		local presented = Compose.formula(function(use: ComposeTypes.Use): boolean
			return use(state).top
		end)
		local animatedPresented: ComposeTypes.ReadOnlyValue<boolean> = presented
		if groupReady then
			local synchronized = Compose.cell(presented:peek())
			Compose.watch(function(use: ComposeTypes.Use)
				if use(groupReady) then
					synchronized:set(use(presented))
				end
			end)
			animatedPresented = synchronized
		end
		local frames = ctx.config.services.RunService
		local arrived: ComposeTypes.Value<boolean> = prepared or Compose.cell(false)
		arrived:set(frames == nil or frames.PreRender == nil or runtime.host.frames == nil)
		local moving = transitions.create(
			ctx,
			transition,
			presented,
			immediate,
			if immediate then nil else arrived,
			nil,
			animatedPresented,
			holdOnExit
		)
		local content: Frame? = nil
		local pageZoom = if transition.zoom ~= nil then moving.zoom else nil
		if transition.apply or pageZoom then
			content = Host.Frame {
				Name = "TransitionContent",
				BackgroundTransparency = 1,
				AnchorPoint = if pageZoom then ctx.types.Vector2.new(0.5, 0.5) else nil,
				Position = if pageZoom then ctx.types.UDim2.fromScale(0.5, 0.5) else nil,
				Size = ctx.types.UDim2.fromScale(1, 1),
				if pageZoom then Host.UIScale "TransitionZoom" { Scale = pageZoom } else nil,
			}
			local children: { Types.Child } = {}
			local entries = (properties :: unknown) :: { [unknown]: unknown }
			for index, child in entries do
				if type(index) == "number" then
					children[index] = child :: Types.Child
				end
			end
			for index in entries do
				if type(index) == "number" then
					properties[index] = nil
				end
			end
			runtime.mountFragment(function()
				return children
			end, content)
			properties[1] = content
		end
		properties.GroupTransparency = function(use: ComposeTypes.Use)
			return if not use(arrived) then 1 else use(moving.transparency)
		end
		properties.Visible = moving.visible
		properties.Interactable = function(use: ComposeTypes.Use)
			return use(arrived)
				and use(state).top
				and not use(moving.interacting)
				and (
					(
						transition.apply == nil
						and transition.progress == nil
						and transition.scale == nil
						and transition.zoom == nil
					) or use(moving.opacity) == 1
				)
		end
		local panel = ctx.fade(properties, nil, if properties.BackgroundTransparency == 1 then false else nil)
		moving.apply(content or panel, panel)
		local scale = moving.scale
		if scale then
			plate(panel, scale)
		end
		local zoom = moving.zoom
		if zoom then
			Compose.watch(function(use: ComposeTypes.Use)
				panel:SetAttribute("FacetTransitionZoom", use(zoom))
			end)
		end
		if not arrived:peek() and runtime.host.frames then
			local ready = presentationReadiness(ctx, { panel })
			preparation.begin(ctx, panel)
			Compose.watch(function(use: ComposeTypes.Use)
				if use(ready) then
					arrived:set(true)
					preparation.finish(ctx, panel)
				end
			end)
		end
		if hidden then
			Compose.watch(function(use: ComposeTypes.Use)
				if use(moving.completed) then
					hidden()
				end
			end)
		end
		return panel
	end

	local function checkedSelection(
		selection: ComposeTypes.Value<string>,
		entries: { Nav.Tab },
		label: string
	): { [string]: Nav.Tab }
		assert(selection and selection.set, label .. ".selection requires a writable Compose cell")
		assert(type(entries) == "table" and #entries > 0, label .. " requires entries")
		local byId: { [string]: Nav.Tab } = {}
		for _, entry in entries do
			assert(type(entry.id) == "string" and byId[entry.id] == nil, label .. " entries require unique string ids")
			byId[entry.id] = entry
		end
		assert(byId[selection:peek()], label .. ".selection must name an entry")
		return byId
	end
	return {
		content = content,
		checkTransition = checkTransition,
		layer = layer,
		checkedSelection = checkedSelection,
	}
end
