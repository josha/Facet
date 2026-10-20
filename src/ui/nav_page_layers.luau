--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local ComposeTypes = require("../vendor/compose/core")
local transitions = require("./transition")
local presentationReadiness = require("./presentation_readiness")

export type PageLayers = {
	content: <P>(Instance | ((Nav.NavigationEntry<P>?) -> Instance), Nav.NavigationEntry<P>?) -> Instance,
	checkTransition: (Nav.Transition | false?) -> (),
	layer: (
		Types.CanvasGroupNativeProps & Types.FrameNativeProps,
		ComposeTypes.Readable<ComposeTypes.LayerStackState>,
		Nav.Transition | false?,
		(() -> ())?,
		boolean?,
		ComposeTypes.Cell<boolean>?,
		ComposeTypes.Readable<boolean>?
	) -> GuiObject,
	checkedSelection: (ComposeTypes.Cell<string>, { Nav.Tab }, string) -> { [string]: Nav.Tab },
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
	local function layer(
		properties: Types.CanvasGroupNativeProps & Types.FrameNativeProps,
		state: ComposeTypes.Readable<ComposeTypes.LayerStackState>,
		transition: Nav.Transition | false?,
		hidden: (() -> ())?,
		immediate: boolean?,
		prepared: ComposeTypes.Cell<boolean>?,
		groupReady: ComposeTypes.Readable<boolean>?
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
		local animatedPresented: ComposeTypes.Readable<boolean> = presented
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
		local arrived: ComposeTypes.Cell<boolean> = prepared or Compose.cell(false)
		arrived:set(frames == nil or frames.PreRender == nil or runtime.host.frames == nil)
		local moving = transitions.create(
			ctx,
			transition,
			presented,
			immediate,
			if immediate then nil else arrived,
			nil,
			animatedPresented
		)
		local content: Frame? = nil
		if transition.apply then
			content = Host.Frame {
				Name = "TransitionContent",
				BackgroundTransparency = 1,
				Size = ctx.types.UDim2.fromScale(1, 1),
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
				and ((transition.apply == nil and transition.progress == nil) or use(moving.opacity) == 1)
		end
		local panel = ctx.fade(properties, nil, if properties.BackgroundTransparency == 1 then false else nil)
		moving.apply(content or panel, panel)
		if not arrived:peek() and runtime.host.frames then
			local ready = presentationReadiness(ctx, { panel })
			panel:SetAttribute("FacetPreparing", true)
			Compose.watch(function(use: ComposeTypes.Use)
				if use(ready) then
					arrived:set(true)
					panel:SetAttribute("FacetPreparing", false)
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
		selection: ComposeTypes.Cell<string>,
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
