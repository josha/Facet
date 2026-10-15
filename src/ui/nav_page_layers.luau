--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local ComposeTypes = require("../vendor/compose/core")
local motion = require("./motion")

export type PageLayers = {
	content: <P>(Instance | ((Nav.NavigationEntry<P>?) -> Instance), Nav.NavigationEntry<P>?) -> Instance,
	checkTransition: (Nav.Transition | false?) -> (),
	layer: (
		Types.CanvasGroupNativeProps & Types.FrameNativeProps,
		ComposeTypes.Readable<ComposeTypes.LayerStackState>,
		Nav.Transition | false?,
		(() -> ())?,
		boolean?
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
	local function checkTransition(transition: Nav.Transition | false?): ()
		if transition == nil or transition == false then
			return
		end
		assert(type(transition) == "table", "Navigation transition uses Compose tween options")
		for key in transition do
			assert(key == "seconds" or key == "ease", "Navigation transition uses Compose tween options: seconds, ease")
		end
	end
	local function layer(
		properties: Types.CanvasGroupNativeProps & Types.FrameNativeProps,
		state: ComposeTypes.Readable<ComposeTypes.LayerStackState>,
		transition: Nav.Transition | false?,
		hidden: (() -> ())?,
		immediate: boolean?
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
		checkTransition(transition)
		local mounted = Compose.cell(false)
		local level = motion.level(ctx)
		local opacity = runtime.tween(function(use: ComposeTypes.Use)
			return if (immediate or use(mounted)) and use(state).top then 1 else 0
		end, transition)
		local function still(use: ComposeTypes.Use): boolean
			return level(use) == "none"
		end
		properties.GroupTransparency = function(use: ComposeTypes.Use)
			return if still(use) then 0 else 1 - use(opacity)
		end
		properties.Visible = function(use: ComposeTypes.Use)
			return use(state).top or not still(use) and use(opacity) > 0
		end
		properties.Interactable = function(use: ComposeTypes.Use)
			return use(state).top
		end
		local panel = ctx.fade(properties, nil, if properties.BackgroundTransparency == 1 then false else nil)
		local parent = ctx.observe.Parent(panel)
		Compose.watch(function(use: ComposeTypes.Use)
			mounted:set(use(parent) ~= nil)
		end)
		if hidden then
			Compose.watch(function(use: ComposeTypes.Use)
				if not use(state).top and (still(use) or use(opacity) == 0) then
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
