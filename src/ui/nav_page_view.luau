--!strict
local ControlTypes = require("./control_types")
local Types = require("./types")
local Nav = require("./navigation_types")
local ComposeTypes = require("../vendor/compose/core")
local reducedMotion = require("./motion").reduced
local NavigationProps = require("./navigation_props")
local pageLayers = require("./nav_page_layers")

local FLING_SPEED = 1200

return function(
	ctx: Types.Context,
	UI: ControlTypes.BuilderControls,
	surfaces: Nav.Surfaces,
	layers: pageLayers.PageLayers
): ()
	local Host, Compose, runtime = ctx.Host, ctx.Compose, ctx.runtime
	local E, D2, V2 = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2
	local content, checkedSelection = layers.content, layers.checkedSelection
	UI.PageView = ctx.construct("PageView", function(spec: NavigationProps.PageViewSpec): Frame
		local byId = checkedSelection(spec.selection, spec.pages, "PageView")
		local indexById: { [string]: number } = {}
		for index, page in spec.pages do
			indexById[page.id] = index
		end
		local footerHeight = (if spec.summary ~= false then 24 else 0)
			+ (if spec.indicators ~= false then 48 else 0)
			+ (if spec.controls ~= false then 48 else 0)
		local pageNodes: { [string]: Frame } = {}
		local reduced = reducedMotion(ctx)
		local fling = Compose.cell(false)
		local flingStyle, pageStyle = ctx.motionStyle("fling"), ctx.motionStyle("page")
		local layout = Host.UIPageLayout "PagesLayout" {
			Animated = function(use: ComposeTypes.Use)
				return not reduced(use)
			end,
			EasingStyle = function(use: ComposeTypes.Use)
				return if use(fling) then flingStyle else pageStyle
			end,
			EasingDirection = E.EasingDirection.Out,
			TweenTime = ctx.metric("motion.durations.pageTurn"),
			Circular = false,
			FillDirection = E.FillDirection.Horizontal,
			SortOrder = E.SortOrder.LayoutOrder,
			GamepadInputEnabled = true,
			TouchInputEnabled = true,
			ScrollWheelInputEnabled = function(use: ComposeTypes.Use): boolean
				return ctx.read(spec.scrollWheel, use) == true
			end,
		}
		local hugs = spec.AutomaticSize == E.AutomaticSize.Y or spec.AutomaticSize == E.AutomaticSize.XY
		local tallest = Compose.cell(0)
		local heights: { ComposeTypes.Readable<Vector2> } = {}
		local children: { Types.Child } = { layout }
		for index, page in spec.pages do
			local body = content(page.content, nil)
			if hugs and body:IsA("GuiObject") then
				table.insert(heights, ctx.observe.AbsoluteSize(body))
			end
			local node = Host.Frame(page.id)({
				BackgroundTransparency = 1,
				Size = D2.fromScale(1, 1),
				LayoutOrder = index,
				body,
			})
			pageNodes[page.id] = node
			table.insert(children, node)
		end
		local pages = Host.Frame "Pages" {
			BackgroundTransparency = 1,
			Size = function(use: ComposeTypes.Use)
				return if hugs then D2.new(1, 0, 0, use(tallest)) else D2.new(1, 0, 1, -footerHeight)
			end,
			ClipsDescendants = true,
		}
		surfaces.attach(pages, children)
		local pressed: { x: number, at: number }? = nil
		local paused = if spec.autoAdvanceSeconds ~= nil then Compose.cell(false) else nil
		local hovering = false
		local function pointer(input: InputObject): boolean
			return input.UserInputType == E.UserInputType.Touch or input.UserInputType == E.UserInputType.MouseButton1
		end
		runtime.connect(pages, "InputBegan", function(input: InputObject)
			if pointer(input) then
				pressed = { x = input.Position.X, at = os.clock() }
				if paused then
					paused:set(true)
				end
			end
		end)
		runtime.connect(pages, "InputEnded", function(input: InputObject)
			local start = pressed
			pressed = nil
			if paused then
				paused:set(hovering)
			end
			if start and pointer(input) then
				local seconds = math.max(os.clock() - start.at, 1 / 120)
				fling:set(math.abs(input.Position.X - start.x) / seconds > FLING_SPEED)
			end
		end)
		local changing = false
		local parent = ctx.observe.Parent(pages)
		Compose.watch(function(use: ComposeTypes.Use)
			local id = use(spec.selection)
			assert(byId[id], "PageView.selection must name a declared page")
			if use(parent) then
				changing = true
				layout:JumpTo(pageNodes[id])
				changing = false
			end
		end)
		local size = ctx.observe.AbsoluteSize(pages)
		Compose.watch(function(use: ComposeTypes.Use)
			local box = use(size)
			if box.X <= 0 or not use(parent) then
				return
			end
			local animated = layout.Animated
			layout.Animated = false
			changing = true
			layout:JumpTo(pageNodes[spec.selection:peek()])
			changing = false
			layout.Animated = animated
		end)
		local gui = surfaces.service("GuiService")
		if paused then
			local interaction = paused
			local later = runtime.scheduler()
			local focused = if gui then ctx.observe.SelectedObject(gui) else nil
			runtime.connect(pages, "MouseEnter", function()
				hovering = true
				interaction:set(true)
			end)
			runtime.connect(pages, "MouseLeave", function()
				hovering = false
				interaction:set(pressed ~= nil)
			end)
			Compose.watch(function(use: ComposeTypes.Use)
				local seconds = ctx.read(spec.autoAdvanceSeconds, use)
				local id = use(spec.selection)
				local held = use(interaction)
				local selected = if focused then use(focused) else nil
				later.cancel("advance")
				if seconds == nil then
					return
				end
				assert(seconds > 0 and seconds < math.huge, "PageView.autoAdvanceSeconds must be finite and positive")
				if held or (selected and surfaces.within(selected, pages)) or #spec.pages < 2 then
					return
				end
				later.replace("advance", seconds, function()
					fling:set(false)
					spec.selection:set(spec.pages[indexById[id] % #spec.pages + 1].id)
				end)
			end)
		end
		local current = ctx.observe.CurrentPage(layout)
		Compose.watch(function(use: ComposeTypes.Use)
			local page = use(current)
			if
				gui
				and page
				and gui.SelectedObject
				and surfaces.within(gui.SelectedObject, pages)
				and not surfaces.within(gui.SelectedObject, page)
			then
				gui.SelectedObject = surfaces.firstSelectable(page)
			end
			if not changing and page and byId[page.Name] and page.Name ~= spec.selection:peek() then
				spec.selection:set(page.Name)
			end
		end)
		local function step(amount: number): ()
			fling:set(false)
			local at = math.clamp(indexById[spec.selection:peek()] + amount, 1, #spec.pages)
			spec.selection:set(spec.pages[at].id)
		end
		if gui and ctx.action then
			local selectedObject = ctx.observe.SelectedObject(gui)
			local function inside(use: ComposeTypes.Use): boolean
				return surfaces.within(use(selectedObject), pages)
			end
			ctx.action(pages, "PageForward", { E.KeyCode.Right, E.KeyCode.DPadRight }, inside, function()
				step(1)
			end, { priority = 1500, capture = true })
			ctx.action(pages, "PageBack", { E.KeyCode.Left, E.KeyCode.DPadLeft }, inside, function()
				step(-1)
			end, { priority = 1500, capture = true })
		end
		local footer: { Types.Child } = {}
		if spec.summary ~= false then
			table.insert(
				footer,
				ctx.text({
					Name = "Summary",
					Text = function(use: ComposeTypes.Use)
						return ctx.phrase(
							"Facet.PageOf",
							"Page {current} of {count}",
							{ current = indexById[use(spec.selection)], count = #spec.pages },
							use
						)
					end,
				})
			)
		end
		if spec.indicators ~= false then
			local dots: { ComposeTypes.Child } = {}
			for index, page in spec.pages do
				local id = page.id
				local dot = UI.Button(id)({
					name = function(use: ComposeTypes.Use): string
						return ctx.phrase(
							"Facet.PageOf",
							"Page {current} of {count}",
							{ current = index, count = #spec.pages },
							use
						)
					end,
					LayoutOrder = index,
					Size = D2.fromOffset(44, 44),
					AutomaticSize = E.AutomaticSize.None,
					BackgroundTransparency = 1,
					selected = function(use: ComposeTypes.Use): boolean
						return use(spec.selection) == id
					end,
					onActivate = function()
						fling:set(false)
						spec.selection:set(id)
					end,
				})
				dot:AddTag("facet-page-indicator")
				runtime.mount(function()
					return ctx.styled(
						Host.Frame "Dot" {
							AnchorPoint = V2.new(0.5, 0.5),
							Position = D2.fromScale(0.5, 0.5),
							Size = D2.fromOffset(8, 8),
							BorderSizePixel = 0,
							Host.UICorner({ CornerRadius = ctx.round }),
						},
						"page-dot"
					)
				end, dot)
				table.insert(dots, dot)
			end
			local row = ctx.row(dots, { Name = "Indicators" })
			assert(row:FindFirstChildWhichIsA("UIListLayout")).Padding = ctx.types.UDim.new(0, 0)
			table.insert(footer, row)
		end
		if spec.controls ~= false then
			table.insert(
				footer,
				ctx.row({
					UI.Button "Previous" {
						label = "Previous",
						enabled = function(use: ComposeTypes.Use)
							return indexById[use(spec.selection)] > 1
						end,
						onActivate = function()
							step(-1)
						end,
					},
					UI.Button "Next" {
						label = "Next",
						enabled = function(use: ComposeTypes.Use)
							return indexById[use(spec.selection)] < #spec.pages
						end,
						onActivate = function()
							step(1)
						end,
					},
				})
			)
		end
		local column = ctx.column(footer, {
			Name = "Footer",
			Position = function(use: ComposeTypes.Use)
				return if hugs then D2.fromOffset(0, use(tallest)) else D2.new(0, 0, 1, -footerHeight)
			end,
			Size = D2.new(1, 0, 0, footerHeight),
			AutomaticSize = E.AutomaticSize.None,
		})
		assert(column:FindFirstChildWhichIsA("UIListLayout")).HorizontalAlignment = E.HorizontalAlignment.Center
		local root = Host.Frame(
			ctx.props(
				spec,
				{ "pages", "selection", "indicators", "summary", "controls", "autoAdvanceSeconds", "scrollWheel" },
				{
					Name = "PageView",
					BackgroundTransparency = 1,
					Size = D2.fromScale(1, 1),
					pages,
					column,
				}
			)
		)
		if hugs then
			local unit = ctx.layoutUnit(root)
			Compose.watch(function(use: ComposeTypes.Use)
				local most = 0
				for _, height in heights do
					most = math.max(most, use(height).Y)
				end
				tallest:set(math.ceil(most / use(unit) - 1e-3))
			end)
		end
		return root
	end)
end
