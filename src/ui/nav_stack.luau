--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local dragSession = require("./drag_session")
local ComposeTypes = require("../vendor/compose/core")
local parts = require("./overlay_parts")
local motion = require("./motion")
local reducedMotion = motion.reduced
local adaptive = require("./adaptive")
local ControlTypes = require("./control_types")
local NavigationProps = require("./navigation_props")
local pageLayers = require("./nav_page_layers")
local fontReadiness = require("./font_readiness")
local textMeasure = require("./text_measure")
local presentationReadiness = require("./presentation_readiness")

return function(
	ctx: Types.Context,
	UI: ControlTypes.BuilderControls,
	surfaces: Nav.Surfaces,
	layers: pageLayers.PageLayers
): ()
	local Host, Compose, runtime, read = ctx.Host, ctx.Compose, ctx.runtime, ctx.read
	local E, D2, V2 = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2
	local content, checkTransition, layer = layers.content, layers.checkTransition, layers.layer
	local navigationDepth = 0
	local function navigationStack<P>(spec: NavigationProps.NavigationStackSpec<P>): Frame
		local pushSpring = ctx.motionSpring("move")
		local parallax = ctx.metric("motion.distances.parallax")
		local dim = ctx.metric("motion.distances.dim")
		assert(
			type(spec.path) == "table" and spec.path.set and spec.root and spec.destinations,
			"NavigationStack requires path, root and destinations"
		)
		checkTransition(spec.transition)
		local gui = surfaces.service("GuiService")
		local selectedObject = if gui then ctx.observe.SelectedObject(gui) else Compose.cell(nil :: GuiObject?)
		local depth = navigationDepth
		local rootEntry: Nav.NavigationEntry<P> = { id = "@root" }
		local errorText: ComposeTypes.Cell<string?> = Compose.cell(nil :: string?)
		local accepted = { rootEntry }
		local reduce = reducedMotion(ctx)
		local level = motion.level(ctx)
		local timing: Nav.Transition? = if type(spec.transition) == "table" then spec.transition else nil
		local animated = spec.transition == nil
		local function validate(path: { Nav.NavigationEntry<P> }): { Nav.NavigationEntry<P> }
			assert(type(path) == "table", "NavigationStack.path must contain an array")
			local list = { rootEntry }
			for _, entry in path do
				assert(
					type(entry) == "table" and type(entry.id) == "string" and spec.destinations[entry.id],
					"NavigationStack path has an undeclared destination"
				)
				table.insert(list, entry)
			end
			return list
		end
		validate(spec.path:peek())
		local entries = Compose.formula(function(use: ComposeTypes.Use)
			local ok, list = pcall(validate, use(spec.path))
			if ok then
				accepted = list
				errorText:set(nil)
			else
				errorText:set(tostring(list))
			end
			return accepted
		end)
		local leaving: ComposeTypes.Cell<Nav.NavigationEntry<P>?> = Compose.cell(nil :: Nav.NavigationEntry<P>?)
		local root: Frame
		local handoff = false
		local shownList = entries:peek()
		Compose.watch(function(use: ComposeTypes.Use)
			local list = use(entries)
			local former = shownList
			shownList = list
			local top = former[#former]
			if top ~= list[#list] and gui and root and surfaces.within(gui.SelectedObject, root) then
				handoff = true
				root:SetAttribute("FacetSelectionOwner", true)
				gui.SelectedObject = nil
			end
			local departing = leaving:peek()
			if table.find(list, top) == nil and (animated or timing ~= nil) and level() ~= "none" then
				leaving:set(top)
			elseif departing and table.find(list, departing) then
				leaving:set(nil)
			end
		end)
		local displayed = Compose.formula(function(use: ComposeTypes.Use)
			local list = use(entries)
			local departing = use(leaving)
			if departing == nil or table.find(list, departing) then
				return list
			end
			local result = table.clone(list)
			table.insert(result, departing)
			return result
		end)
		local offsets: ComposeTypes.Cell<{ [Nav.NavigationEntry<P>]: (ComposeTypes.Use?) -> number }> = Compose.cell({})
		local stackReady = false
		local function pop()
			local path = table.clone(spec.path:peek())
			if #path > 0 then
				table.remove(path)
				spec.path:set(path)
			end
		end
		local function frontOffset(use: ComposeTypes.Use): number
			local list = use(displayed)
			local measure = use(offsets)[list[#list]]
			return if measure then measure(use) else 0
		end
		local backdrop: ComposeTypes.Cell<Color3?> = Compose.cell(nil :: Color3?)
		local moving = Compose.formula(function(use: ComposeTypes.Use): boolean
			return frontOffset(use) > 0 or use(leaving) ~= nil
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			if not use(moving) then
				return
			end
			local at: Instance? = root and root.Parent
			while at do
				if at:IsA("GuiObject") and (at:GetStyled("BackgroundTransparency") :: number) < 1 then
					backdrop:set(at:GetStyled("BackgroundColor3") :: Color3)
					return
				end
				at = at.Parent
			end
			backdrop:set(nil)
		end)
		root = Host.Frame(ctx.props(spec, { "path", "root", "destinations", "backLabel", "chrome", "transition" }, {
			Name = "NavigationStack",
			BackgroundTransparency = 1,
			Size = D2.fromScale(1, 1),
			ClipsDescendants = moving,
			Compose.LayerStack({
				from = displayed,
				retention = "all",
				render = function(
					current: ComposeTypes.Readable<Nav.NavigationEntry<P>>,
					state: ComposeTypes.Readable<ComposeTypes.LayerStackState>
				): Instance
					local entry = current:peek()
					local destination = if entry == rootEntry then spec.root else spec.destinations[entry.id]
					local titled = entry ~= rootEntry or (destination.title ~= nil and destination.title ~= "")
					local function chromeVisible(use: ComposeTypes.Use?): boolean
						local policy = read(destination.chrome, use) or read(spec.chrome, use)
						assert(
							policy == nil or policy == "automatic" or policy == "hidden",
							"Invalid NavigationStack.chrome"
						)
						return titled and policy ~= "hidden"
					end
					local function chrome(use: ComposeTypes.Use?): number
						return if chromeVisible(use) then ctx.metric("targetSizes.minimum", use) else 0
					end
					local role = Compose.formula(function(use: ComposeTypes.Use): string
						local list = use(entries)
						local at = table.find(list, entry)
						return if at == nil then "exiting" elseif at == #list then "top" else "covered"
					end)
					local entering = Compose.cell(stackReady and animated and not reduce())
					local frames = ctx.config.services.RunService
					local prepares = runtime.host.frames ~= nil and frames ~= nil and frames.PreRender ~= nil
					local prepared = Compose.cell(not prepares)
					local function target(use: ComposeTypes.Use): number
						return if use(role) == "exiting" or use(entering) and not reduce(use) then 1 else 0
					end
					local travel: ComposeTypes.Readable<number> = if animated
						then runtime.spring(target, {
							period = pushSpring.period,
							damping = pushSpring.damping,
							tolerance = 1e-3,
							reducedMotion = function(use: ComposeTypes.Use): boolean
								return reduce(use)
							end,
						})
						else Compose.cell(0)
					local fading = Compose.cell(stackReady and animated and level() == "limited")
					local arrival = runtime.tween(function(use: ComposeTypes.Use): number
						return if use(fading) then 0 else 1
					end, { seconds = ctx.metric("motion.reducedFade"), ease = ctx.motionEase("fade") })
					local function offset(use: ComposeTypes.Use?): number
						if not animated or reduce(use) then
							return if read(role, use) == "exiting" then 1 else 0
						end
						return read(travel, use)
					end
					local registered = table.clone(offsets:peek())
					registered[entry] = offset
					offsets:set(registered)
					Compose.cleanup(function()
						local remaining = table.clone(offsets:peek())
						remaining[entry] = nil
						offsets:set(remaining)
					end)
					local function placement(use: ComposeTypes.Use): (string, number)
						local list = use(displayed)
						local at = table.find(list, entry)
						if at == #list then
							return "front", offset(use)
						end
						if at == #list - 1 then
							local above = use(offsets)[list[#list]]
							local moved = if above then above(use) else 0
							if moved > 0 or use(role) == "top" then
								return "beneath", moved
							end
						end
						return "rest", 0
					end
					local function reveal(use: ComposeTypes.Use): number
						local place, moved = placement(use)
						return if place == "beneath" then moved + parallax * (1 - moved) else 1
					end
					local prepareTitle = runtime.host.frames ~= nil and ctx.config.services.RunService ~= nil
					local titleReady = Compose.cell(not prepareTitle)
					local title = ctx.text({
						Visible = titleReady,
						Name = "Title",
						Text = destination.title or "",
						Size = D2.fromScale(1, 1),
						TextTruncate = E.TextTruncate.AtEnd,
						TextXAlignment = function(use: ComposeTypes.Use)
							return if use(state).index > 1 then E.TextXAlignment.Center else E.TextXAlignment.Left
						end,
					})
					runtime.mount(function()
						local function inset(use: ComposeTypes.Use): UDim
							return ctx.types.UDim.new(0, ctx.controlSize(nil, "paddingX", use))
						end
						return Host.UIPadding({ PaddingLeft = inset, PaddingRight = inset })
					end, title)
					local navigationBar = Host.Frame "NavigationBar" {
						BackgroundTransparency = 1,
						Size = function(use: ComposeTypes.Use)
							return D2.new(1, 0, 0, chrome(use))
						end,
						Visible = chromeVisible,
						title :: Types.Child,
						Compose.show(function(use: ComposeTypes.Use)
							return chromeVisible(use) and use(state).index > 1
						end, function()
							return parts.back(ctx, UI, spec.backLabel, pop, {
								AnchorPoint = V2.new(0, 0.5),
								Position = D2.fromScale(0, 0.5),
							})
						end),
					}
					local barSize = ctx.observeNative.AbsoluteSize(navigationBar)
					Compose.watch(function(use: ComposeTypes.Use)
						local large = entry == rootEntry and adaptive.sizeClass(use(barSize).X) ~= "compact"
						title:RemoveTag(if large then "facet-type-heading" else "facet-type-title")
						title:AddTag(if large then "facet-type-title" else "facet-type-heading")
					end)
					if prepareTitle then
						local fontsReady = fontReadiness(ctx, { title })
						local settled = runtime.settled {
							ready = function(): boolean
								return navigationBar.AbsoluteSize.X > 0
									and fontsReady()
									and textMeasure.ready(title)
									and (title.Text == "" or title.TextBounds.X > 0 and title.TextBounds.Y > 0)
							end,
							sample = function(): string
								return `{navigationBar.AbsoluteSize}:{title.AbsoluteSize}:{title.TextBounds}:{title:GetStyled(
									"TextSize"
								)}:{title:GetStyled("FontFace")}`
							end,
						}
						Compose.watch(function(use: ComposeTypes.Use)
							titleReady:set(use(settled))
						end)
					end
					local destinationFrame = Host.Frame "Destination" {
						BackgroundTransparency = 1,
						Position = function(use: ComposeTypes.Use)
							return D2.fromOffset(0, chrome(use))
						end,
						Size = function(use: ComposeTypes.Use)
							return D2.new(1, 0, 1, -chrome(use))
						end,
						Compose.boundary(function()
							navigationDepth += 1
							local ok, built =
								pcall(content, destination.content, if entry == rootEntry then nil else entry)
							navigationDepth -= 1
							if not ok then
								error(built, 0)
							end
							return built
						end, function(failure)
							errorText:set(tostring(failure))
							return ctx.text({
								Name = "DestinationError",
								Text = "This page could not be displayed.",
								TextWrapped = true,
							})
						end),
					}
					local panel: GuiObject
					if timing then
						panel = layer(
							{
								Name = entry.id,
								BackgroundTransparency = 1,
								Size = D2.fromScale(1, 1),
								Visible = function(use: ComposeTypes.Use)
									return use(state).top
								end,
								navigationBar,
								destinationFrame,
							},
							Compose.formula(function(use: ComposeTypes.Use): ComposeTypes.LayerStackState
								local value = table.clone(use(state))
								value.top = use(role) == "top"
								return value
							end),
							timing,
							function()
								if leaving:peek() == entry then
									leaving:set(nil)
								end
							end,
							not stackReady
						)
					else
						panel = ctx.fade({
							Name = entry.id,
							GroupTransparency = function(use: ComposeTypes.Use)
								return if not use(prepared)
									then 1
									elseif level(use) == "limited" then 1 - use(arrival)
									else 0
							end,
							BackgroundTransparency = function(use: ComposeTypes.Use)
								return if use(moving)
										and use(backdrop) ~= nil
										and placement(use) ~= "rest"
									then 0
									else 1
							end,
							BackgroundColor3 = function(use: ComposeTypes.Use)
								return use(backdrop) or ctx.types.Color3.new(0, 0, 0)
							end,
							BorderSizePixel = 0,
							Size = D2.fromScale(1, 1),
							Position = function(use: ComposeTypes.Use)
								local place, moved = placement(use)
								return if place == "front"
									then D2.fromScale(moved, 0)
									elseif place == "beneath" then D2.fromScale(-parallax * (1 - moved), 0)
									else D2.fromScale(0, 0)
							end,
							ClipsDescendants = function(use: ComposeTypes.Use)
								return reveal(use) < 1
							end,
							Visible = function(use: ComposeTypes.Use)
								local place = placement(use)
								return place == "beneath" or place == "front" and use(role) ~= "covered"
							end,
							Interactable = function(use: ComposeTypes.Use)
								return use(prepared) and use(role) == "top"
							end,
							Host.Frame "Page" {
								BackgroundTransparency = 1,
								Size = D2.fromScale(1, 1),
								navigationBar,
								destinationFrame,
							} :: Types.Child,
							Compose.show(function(use: ComposeTypes.Use)
								return placement(use) == "beneath"
							end, function()
								return Host.Frame "Dim" {
									BackgroundColor3 = ctx.types.Color3.new(0, 0, 0),
									BorderSizePixel = 0,
									Size = D2.fromScale(1, 1),
									ZIndex = 10,
									Interactable = false,
									BackgroundTransparency = function(use: ComposeTypes.Use)
										local _, moved = placement(use)
										return 1 - dim * (1 - moved)
									end,
								}
							end) :: Types.Child,
						})
					end
					if prepares and not timing then
						panel:SetAttribute("FacetPreparing", true)
						local ready = presentationReadiness(ctx, { destinationFrame, navigationBar })
						Compose.watch(function(use: ComposeTypes.Use)
							if use(ready) then
								prepared:set(true)
								panel:SetAttribute("FacetPreparing", false)
								entering:set(false)
								fading:set(false)
							end
						end)
					else
						entering:set(false)
						fading:set(false)
					end
					Compose.watch(function(use: ComposeTypes.Use)
						if not use(moving) then
							return
						end
						if gui and surfaces.within(gui.SelectedObject, panel) then
							handoff = true
							root:SetAttribute("FacetSelectionOwner", true)
							gui.SelectedObject = nil
						end
						if
							timing == nil
							and use(role) == "exiting"
							and offset(use) >= 1
							and leaving:peek() == entry
						then
							leaving:set(nil)
						end
					end)
					local visible, parent = ctx.observe.Visible(panel), ctx.observe.Parent(panel)
					local interactable = ctx.observe.Interactable(panel)
					local remembered: GuiObject?
					local rememberedPath: { string } = {}
					local previousTop: boolean?
					local focusing = surfaces.selecting()
					Compose.watch(function(use: ComposeTypes.Use)
						local selected = use(selectedObject)
						if selected and selected:IsA("GuiObject") and surfaces.within(selected, panel) then
							remembered = selected :: GuiObject
							table.clear(rememberedPath)
							local at: Instance? = selected
							while at and at ~= panel do
								table.insert(rememberedPath, 1, at.Name)
								at = at.Parent
							end
						end
					end)
					local function recall(): GuiObject?
						if remembered and remembered.Parent then
							return remembered
						end
						local at: Instance? = panel
						for _, name in rememberedPath do
							at = if at then at:FindFirstChild(name) else nil
						end
						return if at and at ~= panel and at:IsA("GuiObject") then at :: GuiObject else nil
					end
					Compose.watch(function(use: ComposeTypes.Use)
						local top = use(role) == "top"
						if top and (use(moving) or not use(visible) or not use(interactable)) then
							return
						end
						if not use(parent) then
							return
						end
						if
							gui
							and top
							and use(visible)
							and use(parent)
							and previousTop ~= true
							and (previousTop == false or use(state).index > 1)
							and (gui.SelectedObject ~= nil or handoff or focusing(use))
						then
							handoff = false
							local back = recall()
							gui.SelectedObject = if back
									and back.Visible
									and back.Selectable
									and back.Interactable
								then back
								else surfaces.firstSelectable(panel)
							root:SetAttribute("FacetSelectionOwner", false)
						end
						previousTop = top
					end)
					surfaces.keep(destination.content)
					return panel
				end,
			}),
		}))
		stackReady = true
		local swipeOrigin: number? = nil
		local swipeBlocked = false
		local drag = dragSession(ctx)
		local stackUnit = ctx.layoutUnit(root)
		runtime.decorate(root, {
			Active = function(use: ComposeTypes.Use): boolean
				local path = use(spec.path)
				local entry = path[#path]
				local destination = if entry then spec.destinations[entry.id] else spec.root
				return read(spec.Active, use) == true
					or (
						entry ~= nil
						and destination ~= nil
						and (read(destination.chrome, use) or read(spec.chrome, use)) == "hidden"
					)
			end,
		})
		runtime.connect(root, "InputBegan", function(input: InputObject)
			swipeOrigin = if input.UserInputType == E.UserInputType.Touch then input.Position.X else nil
			swipeBlocked = drag.state:peek() ~= nil
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			if use(drag.state) ~= nil and swipeOrigin ~= nil then
				swipeBlocked = true
			end
		end)
		runtime.connect(root, "TouchSwipe", function(direction: Enum.SwipeDirection, touches: number)
			local path = spec.path:peek()
			local entry = path[#path]
			local destination = if entry then spec.destinations[entry.id] else spec.root
			local origin = swipeOrigin
			swipeOrigin = nil
			if
				direction == E.SwipeDirection.Right
				and touches == 1
				and entry
				and destination ~= nil
				and origin ~= nil
				and origin >= root.AbsolutePosition.X
				and origin <= root.AbsolutePosition.X + ctx.metric("controls.navigationBack.swipeEdge") * stackUnit:peek()
				and not moving:peek()
				and not swipeBlocked
				and (read(destination.chrome) or read(spec.chrome)) == "hidden"
				and dragSession(ctx).state:peek() == nil
			then
				pop()
			end
		end)
		if ctx.action then
			local drag = dragSession(ctx)
			root:SetAttribute("FacetNavigationStack", true)
			local nesting = Compose.cell(depth)
			local _, context = ctx.action(
				root,
				"NavigationBack",
				{ "Escape", "ButtonB" },
				function(use: ComposeTypes.Use)
					return use(drag.state) == nil
						and #use(spec.path) > 0
						and (use(nesting) == 0 or surfaces.within(use(selectedObject), root))
				end,
				pop,
				{ priority = 1000 + depth }
			)
			local function locate()
				local count, at = 0, root.Parent
				while at do
					if at:GetAttribute("FacetNavigationStack") == true then
						count += 1
					end
					at = at.Parent
				end
				nesting:set(count)
				context.Priority = 1000 + count
			end
			runtime.connect(root, "AncestryChanged", locate)
			locate()
		end
		Compose.watch(function(use: ComposeTypes.Use)
			root:SetAttribute("FacetError", use(errorText))
		end)
		return root
	end

	UI.NavigationStack = ctx.construct("NavigationStack", navigationStack)
end
