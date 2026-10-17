--!strict
local ControlTypes = require("./control_types")
local Types = require("./types")
local Nav = require("./navigation_types")
local ComposeTypes = require("../vendor/compose/core")
local reducedMotion = require("./motion").reduced
local NavigationProps = require("./navigation_props")
local pageLayers = require("./nav_page_layers")
local contacts = require("./input_contacts")

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
		assert(
			spec.indicatorPlacement == nil
				or spec.indicatorPlacement == "footer"
				or spec.indicatorPlacement == "overlay",
			"PageView.indicatorPlacement must be footer or overlay"
		)
		local overlayIndicators = spec.indicatorPlacement == "overlay"
		local byId = checkedSelection(spec.selection, spec.pages, "PageView")
		local indexById: { [string]: number } = {}
		for index, page in spec.pages do
			indexById[page.id] = index
		end
		local footerHeight = (if spec.summary ~= false then 24 else 0)
			+ (if spec.indicators ~= false and not overlayIndicators then 48 else 0)
			+ (if spec.controls ~= false then 48 else 0)
		local pageNodes: { [string]: Frame } = {}
		local reduced = reducedMotion(ctx)
		local hugs = spec.AutomaticSize == E.AutomaticSize.Y or spec.AutomaticSize == E.AutomaticSize.XY
		local tallest = Compose.cell(0)
		local heights: { ComposeTypes.Readable<Vector2> } = {}
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
		end
		local width = Compose.cell(1)
		local effectiveInput = ctx.effectiveInput()
		local function nativeScroll(use: ComposeTypes.Use): boolean
			return effectiveInput(use) == "Touch" or ctx.read(spec.scrollWheel, use) == true
		end
		local function Page(current: ComposeTypes.Readable<Nav.Tab>): GuiObject
			return assert(pageNodes[current:peek().id])
		end
		local pages = UI.VirtualList "Pages" {
			from = spec.pages,
			key = function(page: Nav.Tab): string
				return page.id
			end,
			render = Page,
			mode = "all",
			direction = "horizontal",
			itemSize = width,
			gap = 0,
			snap = "item",
			Active = nativeScroll,
			ScrollingEnabled = nativeScroll,
			ScrollBarThickness = 0,
			Selectable = true,
			ElasticBehavior = E.ElasticBehavior.Never,
			BackgroundTransparency = 1,
			Size = function(use: ComposeTypes.Use)
				return if hugs then D2.new(1, 0, 0, use(tallest)) else D2.new(1, 0, 1, -footerHeight)
			end,
			ClipsDescendants = true,
		}
		local held = Compose.cell(false)
		local target: number? = nil
		local paused = if spec.autoAdvanceSeconds ~= nil then Compose.cell(false) else nil
		local hovering = false
		contacts(ctx, pages, function()
			target = nil
			held:set(true)
			UI.scrollTo(pages, pages.CanvasPosition, { animated = false })
			if paused then
				paused:set(true)
			end
		end, function()
			held:set(false)
			if paused then
				paused:set(hovering)
			end
		end)
		local parent = ctx.observe.Parent(pages)
		local available = surfaces.available(pages)
		local gui = surfaces.service("GuiService")
		local focusPending = false
		local unit = ctx.layoutUnit(pages)
		local size = ctx.observe.AbsoluteWindowSize(pages)
		local canvasSize = ctx.observe.AbsoluteCanvasSize(pages)
		local initialized = Compose.cell(false)
		local wasAvailable, lastWidth = false, 0
		Compose.watch(function(use: ComposeTypes.Use)
			local box = use(size)
			local id = use(spec.selection)
			assert(byId[id], "PageView.selection must name a declared page")
			local scale = use(unit)
			if box.X <= 0 or not use(parent) or not use(available) then
				wasAvailable = false
				initialized:set(false)
				return
			end
			local resized = lastWidth ~= box.X
			width:set(box.X / math.max(scale, 0.001))
			if math.abs(use(canvasSize).X - box.X * #spec.pages) > 0.5 then
				initialized:set(false)
				return
			end
			target = (indexById[id] - 1) * box.X
			if gui and surfaces.within(gui.SelectedObject, pages) then
				focusPending = true
			end
			initialized:set(true)
			UI.scrollTo(pages, V2.new(target, 0), { animated = wasAvailable and not resized and not reduced(use) })
			wasAvailable, lastWidth = true, box.X
		end)
		local position = ctx.observe.CanvasPosition(pages)
		Compose.watch(function(use: ComposeTypes.Use)
			local at = use(position).X
			local box = use(size)
			if
				not use(initialized)
				or not use(available)
				or use(held)
				or box.X <= 0
				or (target and math.abs(at - target) > 0.5)
			then
				return
			end
			target = nil
			local index = math.clamp(math.floor(at / box.X + 0.5) + 1, 1, #spec.pages)
			if math.abs(at - (index - 1) * box.X) < 0.5 then
				local id = spec.pages[index].id
				if spec.selection:peek() ~= id then
					spec.selection:set(id)
				end
				local page = pageNodes[id]
				local selected = if gui then gui.SelectedObject else nil
				if gui and ((focusPending and selected == nil) or surfaces.within(selected, pages)) then
					focusPending = false
					if not surfaces.within(selected, page) then
						local nextControl: GuiObject? = nil
						for _, node in page:GetChildren() do
							nextControl = surfaces.firstSelectable(node)
							if nextControl then
								break
							end
						end
						if nextControl == nil then
							page.Selectable = true
							nextControl = page
						end
						gui.SelectedObject = nextControl
					end
				end
			end
		end)
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
				interaction:set(held:peek())
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
					spec.selection:set(spec.pages[indexById[id] % #spec.pages + 1].id)
				end)
			end)
		end
		local function step(amount: number): ()
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
		local indicatorRow: GuiObject? = nil
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
					Size = D2.fromOffset(if overlayIndicators then 24 else 44, 44),
					target = if overlayIndicators then "inline" else "hit",
					AutomaticSize = E.AutomaticSize.None,
					BackgroundTransparency = 1,
					selected = function(use: ComposeTypes.Use): boolean
						return use(spec.selection) == id
					end,
					onActivate = function()
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
			local rowProps: Types.FrameProps = { Name = "Indicators" }
			if overlayIndicators then
				rowProps.AnchorPoint = V2.new(0.5, 1)
				rowProps.Position = function(use: ComposeTypes.Use): UDim2
					return if hugs then D2.new(0.5, 0, 0, use(tallest)) else D2.new(0.5, 0, 1, -footerHeight)
				end
				rowProps.ZIndex = 2
			end
			local row = ctx.row(dots, rowProps)
			assert(row:FindFirstChildWhichIsA("UIListLayout")).Padding = ctx.types.UDim.new(0, 0)
			if overlayIndicators then
				indicatorRow = row
			else
				table.insert(footer, row)
			end
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
		local defaults: Types.FrameProps = {
			Name = "PageView",
			BackgroundTransparency = 1,
			Size = D2.fromScale(1, 1),
			pages,
			column,
		}
		if indicatorRow then
			defaults[#defaults + 1] = indicatorRow
		end
		local root = Host.Frame(ctx.props(spec, {
			"pages",
			"selection",
			"indicators",
			"indicatorPlacement",
			"summary",
			"controls",
			"autoAdvanceSeconds",
			"scrollWheel",
		}, defaults))
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
