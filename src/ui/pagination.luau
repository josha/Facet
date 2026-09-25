--!strict
local Types = require("./types")
local Content = require("./content_types")
local Inputs = require("./input_types")
local ComposeTypes = require("../vendor/compose/core")
local window = require("./pagination_window")
local values = require("./content_values")

type Entry = { kind: "page" | "gap" | "label" | "first" | "previous" | "next" | "last", key: string, page: number? }
type State = { current: number?, count: number?, hasPrevious: boolean, hasNext: boolean }

local MAX_SAFE = 9007199254740991
local MAX_WINDOW = 20
local ARROWS = { "first", "previous", "next", "last" }

return function(
	ctx: Types.Context,
	UI: {
		Pagination: Types.Constructor<Content.PaginationSpec, Frame>,
		Button: Types.Constructor<Inputs.ButtonProps, TextButton>,
	}
): ()
	local Host, Compose, read = ctx.Host, ctx.Compose, ctx.read
	local E, D2, V2 = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2
	local function isPage(value: unknown): boolean
		return type(value) == "number" and value == value and value % 1 == 0 and math.abs(value) <= MAX_SAFE
	end
	local function isCount(value: unknown): boolean
		return value == nil or (isPage(value) and (value :: number) >= 0)
	end
	local function isFlag(value: unknown): boolean
		return value == nil or type(value) == "boolean"
	end

	UI.Pagination = ctx.construct("Pagination", function(spec: Content.PaginationSpec): Frame
		assert(
			isPage(read(spec.page)),
			"Facet UI.Pagination: page is required: a finite whole number or a readable of one"
		)
		assert(type(spec.onChange) == "function", "Facet UI.Pagination: onChange(nextPage) is required")
		assert(
			isCount(read(spec.pageCount)),
			"Facet UI.Pagination: pageCount is a whole number of 0 or more, or nil for an unknown count"
		)
		for _, key in { "hasNext", "hasPrevious", "enabled" } do
			assert(
				isFlag(read((spec :: { [unknown]: unknown })[key])),
				`Facet UI.Pagination: {key} is a boolean or a readable boolean`
			)
		end
		for _, key in { "siblingCount", "boundaryCount" } do
			local value = (spec :: { [unknown]: unknown })[key]
			assert(
				value == nil or (isPage(value) and (value :: number) >= 0 and (value :: number) <= MAX_WINDOW),
				`Facet UI.Pagination: {key} is a whole number from 0 to {MAX_WINDOW}`
			)
		end
		assert(
			spec.showFirstLast == nil or type(spec.showFirstLast) == "boolean",
			"Facet UI.Pagination: showFirstLast is a boolean"
		)
		local form: Content.PaginationForm = spec.form or "numbers"
		assert(
			form == "numbers" or form == "arrows" or form == "label",
			"Facet UI.Pagination: form is numbers, arrows or label"
		)
		local direction = spec.direction or "ltr"
		assert(direction == "ltr" or direction == "rtl", "Facet UI.Pagination: direction is ltr or rtl")
		local automatic = read(spec.AutomaticSize)
		assert(
			automatic ~= E.AutomaticSize.X and automatic ~= E.AutomaticSize.XY,
			"Facet UI.Pagination: AutomaticSize cannot include X. The window narrows to the width that it is offered"
		)
		local sibling, boundary = spec.siblingCount or 1, spec.boundaryCount or 1
		local showFirstLast = spec.showFirstLast == true
		local onChange = spec.onChange
		local checks = values(ctx, "Pagination")
		if spec.controls then
			spec.controls.diagnostics = checks.list
		end
		local pageIn = checks.legal("page", spec.page, isPage, "must be a finite whole number")
		local countIn =
			checks.legal("pageCount", spec.pageCount, isCount, "must be a whole number of 0 or more, or nil")
		local nextIn = checks.legal("hasNext", spec.hasNext, isFlag, "must be a boolean")
		local previousIn = checks.legal("hasPrevious", spec.hasPrevious, isFlag, "must be a boolean")
		local enabled = function(use: ComposeTypes.Use?): boolean
			return read(spec.enabled, use) ~= false
		end
		local lastClamp: string? = nil
		local state = Compose.formula(function(use: ComposeTypes.Use): State
			local page, count = use(pageIn), use(countIn)
			local current: number?
			if count == 0 then
				current = nil
			elseif count ~= nil then
				current = math.clamp(page, 1, count)
			else
				current = math.max(page, 1)
			end
			local clamp = if current ~= nil and current ~= page then `{page}->{current}` else nil
			if clamp ~= nil and clamp ~= lastClamp then
				checks.note(`Facet UI.Pagination: page {page} is outside 1 to {count or "?"}; the row shows {current}`)
			end
			lastClamp = clamp
			if current == nil then
				return { current = nil, count = count, hasPrevious = false, hasNext = false }
			elseif count ~= nil then
				return { current = current, count = count, hasPrevious = current > 1, hasNext = current < count }
			end
			return {
				current = current,
				count = nil,
				hasPrevious = use(previousIn) == true and current > 1,
				hasNext = use(nextIn) == true and current < MAX_SAFE,
			}
		end)
		local function target(kind: string, page: number?, use: ComposeTypes.Use?): number?
			local st = read(state, use)
			local current = st.current
			if current == nil then
				return nil
			end
			if kind == "previous" then
				return if st.hasPrevious then current - 1 else nil
			elseif kind == "next" then
				return if st.hasNext then current + 1 else nil
			elseif kind == "first" then
				return if st.hasPrevious then 1 else nil
			elseif kind == "last" then
				return if st.count ~= nil and current < st.count then st.count else nil
			elseif page ~= nil and page ~= current and page >= 1 and (st.count == nil or page <= st.count) then
				return page
			end
			return nil
		end

		local floor = function(use: ComposeTypes.Use?): number
			return math.max(
				(ctx.metric("targetSizes.minimum", use)),
				(ctx.controlSize(spec.controlSize, "height", use))
			)
		end
		local gap = function(use: ComposeTypes.Use?): number
			return (ctx.metric("space.xs", use))
		end
		local function measure(name: string, text: Types.Value<string>): TextLabel
			local label = ctx.text({ Name = name, Text = text, Visible = false, TextWrapped = false })
			label:AddTag("facet-button")
			return label
		end
		local digits = measure("DigitMeasure", "0000000000")
		local ellipsis = measure("EllipsisMeasure", "…")
		local widest = measure("LabelMeasure", function(use: ComposeTypes.Use): string
			local st = use(state)
			if st.current == nil then
				return "No pages"
			end
			if st.count ~= nil then
				return `Page {string.rep("0", #tostring(st.count))} of {st.count}`
			end
			return `Page {string.rep("0", math.max(4, #tostring(st.current)))}`
		end)
		local digitBounds, ellipsisBounds, widestBounds =
			ctx.observe(digits, "TextBounds"), ctx.observe(ellipsis, "TextBounds"), ctx.observe(widest, "TextBounds")
		local offered = Compose.cell(0)
		local function slotWidth(page: number, use: ComposeTypes.Use?): number
			local digit = read(digitBounds, use).X / 10
			local chrome = 2 * ctx.controlSize("compact", "paddingX", use)
			return math.max(floor(use), math.ceil(digit * #tostring(page) + chrome))
		end
		local entries = Compose.formula(function(use: ComposeTypes.Use): { Entry }
			local st = use(state)
			local out: { Entry } = {}
			local current = st.current
			if current == nil then
				table.insert(out, { kind = "label", key = "label" })
				return out
			end
			local chosen: Content.PaginationForm = form
			if chosen == "numbers" and st.count == nil then
				chosen = "label"
			end
			local pages: { window.Entry } = {}
			if chosen == "numbers" then
				pages = window(current, assert(st.count), sibling, boundary)
				local spacing = gap(use)
				local arrows = 2 + (if showFirstLast then 2 else 0)
				local function need(): number
					local total, previous: number? = arrows * (floor(use) + spacing), nil
					for _, entry in pages do
						if previous ~= nil and entry.page > previous + 1 then
							total += use(ellipsisBounds).X + spacing
						end
						total += slotWidth(entry.page, use) + spacing
						previous = entry.page
					end
					return total
				end
				local width = use(offered)
				local room = if width > 0 then width else math.huge
				while need() > room do
					local drop: number? = nil
					for _, role in { "boundary", "neighbor" } do
						for index, entry in pages do
							if entry.role == role then
								local distance = math.abs(entry.page - current)
								local best = if drop ~= nil then math.abs(pages[drop].page - current) else -1
								if
									distance > best or (distance == best and entry.page > pages[drop :: number].page)
								then
									drop = index
								end
							end
						end
						if drop ~= nil then
							break
						end
					end
					if drop == nil then
						break
					end
					table.remove(pages, drop)
				end
				if need() > room then
					chosen = "label"
				end
			end
			if showFirstLast then
				table.insert(out, { kind = "first", key = "first" })
			end
			table.insert(out, { kind = "previous", key = "previous" })
			if chosen == "numbers" then
				local previous: number? = nil
				for _, entry in pages do
					if previous ~= nil and entry.page > previous + 1 then
						table.insert(out, { kind = "gap", key = `gap-{previous}` })
					end
					table.insert(out, { kind = "page", key = tostring(entry.page), page = entry.page })
					previous = entry.page
				end
			elseif chosen == "label" then
				table.insert(out, { kind = "label", key = "label" })
			end
			table.insert(out, { kind = "next", key = "next" })
			if showFirstLast and st.count ~= nil then
				table.insert(out, { kind = "last", key = "last" })
			end
			if direction == "rtl" then
				local reversed: { Entry } = {}
				for index = #out, 1, -1 do
					table.insert(reversed, out[index])
				end
				out = reversed
			end
			return out
		end)
		local disposed = false
		Compose.cleanup(function()
			disposed = true
		end)
		local function propose(kind: string, page: number?)
			if disposed or not enabled() then
				return
			end
			local nextPage = target(kind, page)
			if nextPage ~= nil then
				onChange(nextPage)
			end
		end
		local icons: { [string]: string } = {
			first = if direction == "rtl" then "chevron.last" else "chevron.first",
			previous = if direction == "rtl" then "chevron.trailing" else "chevron.leading",
			next = if direction == "rtl" then "chevron.leading" else "chevron.trailing",
			last = if direction == "rtl" then "chevron.first" else "chevron.last",
		}
		local names: { [string]: string } =
			{ first = "First page", previous = "Previous page", next = "Next page", last = "Last page" }
		local gui = ctx.config.services.GuiService
		local pageButtons: { [number]: TextButton } = {}
		local arrowButtons: { [string]: TextButton } = {}
		local lostFocus = false
		local lost = Compose.cell(0)
		local function watchFocus(button: TextButton)
			Compose.cleanup(function()
				if gui and gui.SelectedObject == button then
					lostFocus = true
					lost:update(function(count: number): number
						return count + 1
					end)
				end
			end)
		end
		local items = Compose.keyed({
			from = entries,
			key = function(entry: Entry): string
				return entry.key
			end,
			render = function(source: ComposeTypes.Readable<Entry>, index: ComposeTypes.Readable<number>): Instance
				local entry = source:peek()
				if entry.kind == "page" then
					local page = assert(entry.page)
					local button = UI.Button({
						Name = `Page-{page}`,
						label = tostring(page),
						controlSize = "compact" :: Types.ControlSize,
						AnchorPoint = V2.new(0.5, 0.5),
						Position = D2.fromScale(0.5, 0.5),
						selected = function(use: ComposeTypes.Use)
							return use(state).current == page
						end,
						enabled = enabled,
						onActivate = function()
							propose("page", page)
						end,
						Host.UISizeConstraint "SlotLimit" {
							MaxSize = function(use: ComposeTypes.Use)
								return V2.new(slotWidth(page, use), math.huge)
							end,
						},
					})
					pageButtons[page] = button
					watchFocus(button)
					Compose.cleanup(function()
						if pageButtons[page] == button then
							pageButtons[page] = nil
						end
					end)
					return Host.Frame({
						Name = `Slot-{page}`,
						LayoutOrder = index,
						BackgroundTransparency = 1,
						Size = function(use: ComposeTypes.Use)
							return D2.fromOffset(slotWidth(page, use), floor(use))
						end,
						button,
					})
				elseif entry.kind == "gap" then
					local mark = ctx.text({ Name = entry.key, Text = "…", LayoutOrder = index })
					mark:AddTag("facet-secondary")
					return mark
				elseif entry.kind == "label" then
					return ctx.text({
						Name = "Label",
						LayoutOrder = index,
						Text = function(use: ComposeTypes.Use): string
							local st = use(state)
							if st.current == nil then
								return "No pages"
							end
							return if st.count ~= nil then `Page {st.current} of {st.count}` else `Page {st.current}`
						end,
						TextXAlignment = E.TextXAlignment.Center,
						AutomaticSize = function(use: ComposeTypes.Use)
							return if use(widestBounds).X > 0 then E.AutomaticSize.None else E.AutomaticSize.XY
						end,
						Size = function(use: ComposeTypes.Use)
							return D2.fromOffset(math.ceil(use(widestBounds).X), floor(use))
						end,
					})
				end
				local kind = entry.kind
				local button = UI.Button({
					Name = string.upper(string.sub(kind, 1, 1)) .. string.sub(kind, 2),
					LayoutOrder = index,
					label = "",
					name = names[kind],
					icon = icons[kind],
					Size = function(use: ComposeTypes.Use)
						return D2.fromOffset(floor(use), floor(use))
					end,
					AutomaticSize = E.AutomaticSize.None,
					enabled = function(use: ComposeTypes.Use)
						return enabled(use) and target(kind, nil, use) ~= nil
					end,
					onActivate = function()
						propose(kind)
					end,
				})
				arrowButtons[kind] = button
				watchFocus(button)
				Compose.cleanup(function()
					if arrowButtons[kind] == button then
						arrowButtons[kind] = nil
					end
				end)
				return button
			end,
		})
		local row = Host.ScrollingFrame({
			Name = "Row",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = D2.fromScale(1, 1),
			CanvasSize = D2.fromOffset(0, 0),
			AutomaticCanvasSize = E.AutomaticSize.X,
			ScrollingDirection = E.ScrollingDirection.X,
			ScrollBarThickness = 0,
			Host.UIListLayout({
				FillDirection = E.FillDirection.Horizontal,
				HorizontalAlignment = E.HorizontalAlignment.Center,
				VerticalAlignment = E.VerticalAlignment.Center,
				SortOrder = E.SortOrder.LayoutOrder,
				Padding = function(use: ComposeTypes.Use)
					return ctx.types.UDim.new(0, gap(use))
				end,
			}) :: Types.Child,
			items,
		})
		if gui and gui.GetPropertyChangedSignal then
			local selected = ctx.observe(gui, "SelectedObject")
			ctx.runtime.decorate(row, {
				Selectable = function(use: ComposeTypes.Use)
					local current = use(selected)
					return not (current ~= nil and current:IsDescendantOf(row))
				end,
			})
		end
		Compose.watch(function(use: ComposeTypes.Use)
			local current = use(state).current
			row:SetAttribute("FacetEntry", if current then `Page-{current}` else nil)
		end)
		local root = Host.Frame(ctx.props(spec, {
			"page",
			"onChange",
			"pageCount",
			"hasNext",
			"hasPrevious",
			"siblingCount",
			"boundaryCount",
			"showFirstLast",
			"form",
			"direction",
			"controlSize",
			"enabled",
			"controls",
		}, {
			Name = "Pagination",
			BackgroundTransparency = 1,
			Size = function(use: ComposeTypes.Use)
				return D2.new(1, 0, 0, floor(use))
			end,
			Attributes = {
				FacetCurrent = function(use: ComposeTypes.Use)
					return use(state).current
				end,
				FacetCount = function(use: ComposeTypes.Use)
					return use(state).count
				end,
				FacetForm = form,
				FacetDirection = direction,
			} :: Types.Attributes,
			digits :: Types.Child,
			ellipsis :: Types.Child,
			widest :: Types.Child,
			row :: Types.Child,
		}))
		local rootSize = ctx.observe(root, "AbsoluteSize")
		Compose.watch(function(use: ComposeTypes.Use)
			offered:set(use(rootSize).X)
		end)
		local function neighbour(): GuiObject?
			local layer = root:FindFirstAncestorWhichIsA("LayerCollector")
			if layer == nil then
				return nil
			end
			local centre = root.AbsolutePosition + root.AbsoluteSize / 2
			local best: GuiObject?, distance = nil, math.huge
			for _, node in layer:GetDescendants() do
				if
					node:IsA("GuiObject")
					and node.Selectable
					and node.Visible
					and not node:IsDescendantOf(root)
					and node.AbsoluteSize.X > 0
					and node.AbsoluteSize.Y > 0
				then
					local gap = (node.AbsolutePosition + node.AbsoluteSize / 2 - centre).Magnitude
					if gap < distance then
						best, distance = node, gap
					end
				end
			end
			return best
		end
		Compose.watch(function(use: ComposeTypes.Use)
			use(entries)
			use(lost)
			local st = use(state)
			if not gui then
				return
			end
			local selected = gui.SelectedObject
			local dead = false
			for kind, button in arrowButtons do
				if selected == button and target(kind) == nil then
					dead = true
				end
			end
			if not lostFocus and not dead then
				return
			end
			lostFocus = false
			local landing: GuiObject? = if st.current then pageButtons[st.current] else nil
			if landing and landing.Parent == nil then
				landing = nil
			end
			if landing == nil then
				for _, kind in ARROWS do
					local button = arrowButtons[kind]
					if button and target(kind) ~= nil then
						landing = button
						break
					end
				end
			end
			if landing == nil then
				landing = neighbour()
			end
			if landing then
				pcall(function()
					gui.SelectedObject = landing
				end)
			end
		end)
		root:SetAttribute("FacetSelectionOwner", true)
		return root
	end)
end
