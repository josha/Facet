--!strict
local segmentMetrics = require("./segment_metrics")
local Types = require("./types")
local Nav = require("./navigation_types")
local Inputs = require("./input_types")
local Media = require("./media_types")
local Content = require("./content_types")
local fieldChrome = require("./field_chrome")
local reducedMotion = require("./motion")
local ComposeTypes = require("../vendor/compose/core")

type MenuEntry<V> = { key: string, heading: string?, item: Nav.MenuItem<V>?, ruled: boolean? }

return function(
	ctx: Types.Context,
	UI: {
		Menu: Nav.MenuConstructor,
		Picker: Nav.PickerConstructor,
		SplitButton: Nav.SplitButtonConstructor,
		ComboBox: Types.Constructor<Nav.ComboBoxSpec, Frame>,
		Button: Types.Constructor<Inputs.ButtonProps, TextButton>,
		TextInput: Types.Constructor<Inputs.TextInputProps, TextBox | Frame>,
		Badge: Types.Constructor<Media.BadgeProps, GuiObject>,
		Avatar: Types.Constructor<Media.AvatarProps, TextButton>,
		badged: Content.Badged,
	},
	surfaces: Nav.Surfaces
): ()
	local Host, Compose, runtime, read = ctx.Host, ctx.Compose, ctx.runtime, ctx.read
	local readSource = ctx.readSource
	local POPOVER: Nav.MotionTiming = { enter = 0.15, exit = 0.1 }
	local SLIDE = 32
	local MATERIALIZE = 0.96
	local E, D2, V2, D = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2, ctx.types.UDim
	local function derive<T>(compute: (ComposeTypes.Use?) -> T, ...: unknown): Types.Value<T>
		for index = 1, select("#", ...) do
			local source = select(index, ...)
			if Compose.isReadable(source) or type(source) == "function" then
				return compute
			end
		end
		return compute(nil)
	end
	local function optionLabels(options: unknown): { unknown }
		local labels: { unknown } = {}
		if type(options) == "table" and not Compose.isReadable(options) then
			for _, option in options :: { { label: unknown } } do
				table.insert(labels, option.label)
			end
		end
		return labels
	end
	local function writable(cell: { set: unknown }, name: string)
		assert(type(cell) == "table" and type(cell.set) == "function", name .. " requires a writable Compose cell")
	end
	local MENU_KEYS = {
		"items",
		"query",
		"label",
		"disclosure",
		"trigger",
		"triggers",
		"presentation",
		"backLabel",
		"onOpen",
		"onClose",
		"enabled",
		"isPresented",
		"edge",
		"align",
		"width",
		"maxHeight",
	}
	local DIM_FIELDS: { [string]: { [string]: boolean } } = {
		fixed = { px = true },
		fill = { weight = true, min = true, max = true },
		hug = { min = true, max = true },
		percent = { fraction = true, offset = true, min = true, max = true },
		content = {},
		minMax = { min = true, preferred = true, max = true },
	}
	local function finite(value: unknown): boolean
		return type(value) == "number" and value == value and math.abs(value) < math.huge
	end
	local function checkWidth(width: unknown)
		if width == nil then
			return
		end
		if type(width) == "number" then
			assert(
				finite(width) and width > 0,
				"Facet UI.Menu: width must be a finite number of pixels above 0, a UDim, a UDim2 or a dimension table"
			)
			return
		end
		if typeof(width) == "UDim" or typeof(width) == "UDim2" then
			return
		end
		assert(
			type(width) == "table",
			"Facet UI.Menu: width must be a number of pixels, a UDim, a UDim2 or a dimension table"
		)
		local dim = width :: { [string]: unknown }
		local fields = DIM_FIELDS[tostring(dim.type)]
		if fields == nil then
			error(
				`Facet UI.Menu: width.type must be fixed, fill, hug, percent, content or minMax (got {tostring(dim.type)})`,
				0
			)
		end
		for key, value in dim do
			if key ~= "type" then
				if not fields[key] then
					error(`Facet UI.Menu: a {tostring(dim.type)} width does not take '{tostring(key)}'`, 0)
				end
				if not (finite(value) or (type(value) == "string" and key ~= "fraction" and key ~= "weight")) then
					error(`Facet UI.Menu: width.{tostring(key)} must be a finite number or a theme metric name`, 0)
				end
			end
		end
		if dim.type == "fixed" then
			assert(dim.px ~= nil, "Facet UI.Menu: a fixed width requires px")
		elseif dim.type == "percent" then
			assert(dim.fraction ~= nil, "Facet UI.Menu: a percent width requires fraction")
		end
	end
	local function length(value: Nav.MenuDimLength?, use: ComposeTypes.Use?): number?
		if value == nil then
			return nil
		end
		return if type(value) == "string" then ctx.metric(value, use) else value
	end
	local function resolveWidth(width: Nav.MenuWidth, natural: number, room: number, use: ComposeTypes.Use?): number
		if type(width) == "number" then
			return width
		end
		if typeof(width) == "UDim" then
			local udim = width :: UDim
			return udim.Scale * room + udim.Offset
		end
		if typeof(width) == "UDim2" then
			local udim = (width :: UDim2).X
			return udim.Scale * room + udim.Offset
		end
		local dim = width :: Nav.MenuDim
		local lower, upper = length(dim.min, use) or 0, length(dim.max, use) or math.huge
		local value = if dim.type == "fixed"
			then assert(length(dim.px, use))
			elseif dim.type == "fill" then room
			elseif dim.type == "percent" then (dim.fraction or 0) * room + (dim.offset or 0)
			elseif dim.type == "minMax" then length(dim.preferred, use) or natural
			else natural
		return math.max(0, math.clamp(value, lower, math.max(lower, upper)))
	end
	local function actionItem<V>(item: Nav.MenuItem<V>): Nav.MenuAction<V>
		assert(item.divider ~= true, "Menu action cannot be a divider")
		return item
	end
	local function commitItem<V>(item: Nav.MenuAction<V>): boolean
		if read(item.enabled) == false then
			return false
		end
		if item.checked then
			item.checked:set(not item.checked:peek())
			if item.onChange then
				item.onChange(item.checked:peek())
			end
		elseif item.selected then
			item.selected:set(item.value)
			if item.onChange then
				item.onChange(item.value)
			end
		end
		local onSelect: (() -> ())? = item.onSelect
		if onSelect then
			onSelect()
		end
		return true
	end
	local function menuItems<V>(items: { Nav.MenuItem<V> }, use: ComposeTypes.Use?): { Nav.MenuItem<V> }
		assert(type(items) == "table", "Menu.items must be an array")
		local result: { Nav.MenuItem<V> } = {}
		local identifiers: { [string]: boolean } = {}
		for index = 1, #items do
			local source = items[index]
			local copy = table.clone(source)
			local id = copy.id or tostring(index)
			copy.id = id
			local item: Nav.MenuItem<V> = copy
			assert(not identifiers[id], `Facet UI.Menu: two items at one level share the id '{id}'`)
			identifiers[id] = true
			if item.divider ~= true and item.avatar ~= nil then
				for key in (item.avatar :: unknown) :: { [string]: unknown } do
					if key ~= "name" and key ~= "image" and key ~= "userId" then
						error(`Facet UI.Menu: an avatar takes name, image and userId, not '{key}'`, 0)
					end
				end
			end
			if not item.divider then
				assert(
					type(read(item.label, use)) == "string" and string.find(read(item.label, use), "%S") ~= nil,
					"Menu items require nonempty labels"
				)
				assert(not (item.children and item.onSelect), "A menu item cannot have both children and onSelect")
				assert(
					item.children or item.onSelect or item.checked or item.selected,
					"Menu items require an action, submenu, or selection state"
				)
				assert(not (item.checked and item.selected), "A menu item cannot be both checked and selected")
				if item.children then
					item.children = menuItems(read(item.children, use), use)
				end
			end
			table.insert(result, item)
		end
		return result
	end
	local function menuPanel<V>(
		spec: Nav.MenuSpec<V>,
		close: () -> (),
		anchor: GuiObject,
		nonmodal: boolean?,
		phase: Nav.PresencePhase?
	): Frame
		local appearance = if phase then surfaces.appearance(phase, POPOVER) else nil
		local hitFloor = ctx.hitFloor()
		local path = Compose.cell({} :: { string })
		local pendingFocus: string?
		local sheeted = Compose.cell(false)
		local reduce = reducedMotion(ctx)
		local levelClock = runtime.timeline({ duration = POPOVER.enter, autoplay = false })
		local levelDirection = Compose.cell(0)
		local depthSeen = 0
		Compose.watch(function(use: ComposeTypes.Use)
			local depth = #use(path)
			if depth ~= depthSeen then
				levelDirection:set(if depth > depthSeen then 1 else -1)
				depthSeen = depth
				levelClock:restart()
			end
		end)
		local function level(use: ComposeTypes.Use?): number
			local direction: number = if use then use(levelDirection) else levelDirection:peek()
			if direction == 0 or reduce(use) then
				return 1
			end
			return Compose.easing.outCubic(readSource(levelClock.progress, use))
		end
		local shown: Nav.Appearance? = if appearance
			then function(use: ComposeTypes.Use?): number
				return appearance(use) * (if read(sheeted, use) then 1 else level(use))
			end
			else nil
		local rootItems = Compose.formula(function(use: ComposeTypes.Use)
			return menuItems(read(spec.items, use), use)
		end)
		local current = Compose.formula(function(use: ComposeTypes.Use)
			local items = use(rootItems)
			for _, id in use(path) do
				local found: Nav.MenuAction<V>?
				for _, item in items do
					if item.divider ~= true and item.id == id then
						found = item
						break
					end
				end
				if not found or not found.children then
					break
				end
				items = read(found.children, use)
			end
			return items
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			local items, valid = use(rootItems), {}
			for _, id in path:peek() do
				local found: Nav.MenuAction<V>?
				for _, item in items do
					if item.divider ~= true and item.id == id then
						found = item
						break
					end
				end
				if not found or not found.children then
					break
				end
				table.insert(valid, id)
				items = read(found.children, use)
			end
			if #valid ~= #path:peek() then
				path:set(valid)
			end
		end)
		local function back()
			local previous = table.clone(path:peek())
			if #previous == 0 then
				close()
			else
				pendingFocus = table.remove(previous)
				path:set(previous)
			end
		end
		local widths = Compose.cell({} :: { [string]: number })
		local function landing(items: { Nav.MenuItem<V> }): string?
			for _, item in items do
				if item.divider ~= true then
					local action = actionItem(item)
					if
						action.selected ~= nil
						and read(action.selected) == action.value
						and read(action.enabled) ~= false
					then
						return tostring(item.id)
					end
				end
			end
			return nil
		end
		local entries = Compose.formula(function(use: ComposeTypes.Use): { MenuEntry<V> }
			local out: { MenuEntry<V> } = {}
			local afterRow = false
			for index, item in use(current) do
				local key = tostring(item.id or index)
				if item.divider ~= true then
					local heading = read(actionItem(item).sectionTitle, use)
					if heading ~= nil and heading ~= "" then
						table.insert(out, { key = "Section:" .. key, heading = heading })
						afterRow = false
					end
				end
				table.insert(out, { key = key, item = item, ruled = afterRow and item.divider ~= true })
				afterRow = item.divider ~= true
			end
			return out
		end)
		local rows = Host.Frame "MenuRows" {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = D2.new(1, 0, 0, 0),
			AutomaticSize = E.AutomaticSize.Y,
			Host.UIListLayout({
				FillDirection = E.FillDirection.Vertical,
				SortOrder = E.SortOrder.LayoutOrder,
				Padding = function(use: ComposeTypes.Use)
					return D.new(0, if use(sheeted) then 8 else 0)
				end,
			}) :: Types.Child,
			Compose.show(function()
				return spec.query ~= nil
			end, function()
				return UI.TextInput "Search" {
					value = assert(spec.query),
					placeholder = "Search",
					LayoutOrder = -2,
				}
			end),
			Compose.show(function(use: ComposeTypes.Use)
				return #use(path) > 0 and use(sheeted)
			end, function()
				return UI.Button "Back" {
					label = spec.backLabel or "Back",
					onActivate = back,
					LayoutOrder = -1,
					Size = D2.new(1, 0, 0, 44),
				}
			end),
			Compose.keyed({
				from = entries,
				key = function(entry: MenuEntry<V>)
					return entry.key
				end,
				render = function(
					entrySource: ComposeTypes.Readable<MenuEntry<V>>,
					index: ComposeTypes.Readable<number>
				)
					local entry = entrySource:peek()
					if entry.heading then
						local title = ctx.text({
							Name = "SectionTitle",
							Text = function(use: ComposeTypes.Use): string
								return use(entrySource).heading or ""
							end,
						})
						title:AddTag("facet-type-caption")
						title:AddTag("facet-secondary")
						return Host.Frame(entry.key)({
							LayoutOrder = index,
							BackgroundTransparency = 1,
							Size = D2.new(1, 0, 0, 0),
							AutomaticSize = E.AutomaticSize.Y,
							ctx.padding(12, 4) :: Types.Child,
							title :: Types.Child,
						})
					end
					local source = Compose.formula(function(use: ComposeTypes.Use): Nav.MenuItem<V>
						return assert(use(entrySource).item)
					end)
					local item = source:peek()
					if item.divider then
						return ctx.styled(
							Host.Frame "Divider" { Size = D2.new(1, 0, 0, 1), LayoutOrder = index },
							"divider"
						)
					end
					local rowKey = tostring(item.id or index:peek())
					local row = UI.Button({
						Name = rowKey,
						LayoutOrder = index,
						Size = function(use: ComposeTypes.Use)
							return D2.new(1, 0, 0, hitFloor(use))
						end,
						label = function(use: ComposeTypes.Use)
							return read(actionItem(use(source)).label, use)
						end,
						icon = item.icon,
						role = item.role,
						trailingIcon = if item.children
							then "chevron.trailing"
							elseif item.checked ~= nil or item.selected ~= nil or item.marked ~= nil then "checkmark"
							else nil,
						subtitle = function(use: ComposeTypes.Use)
							return read(actionItem(use(source)).description, use) or ""
						end,
						enabled = function(use: ComposeTypes.Use)
							return read(actionItem(use(source)).enabled, use) ~= false
						end,
						selected = function(use: ComposeTypes.Use)
							local live = actionItem(use(source))
							return if live.checked
								then use(live.checked)
								elseif live.selected then use(live.selected) == live.value
								else read(live.marked, use) == true
						end,
						onActivate = function()
							local live = actionItem(source:peek())
							if read(live.enabled) == false then
								return
							end
							if live.children then
								local nextPath = table.clone(path:peek())
								table.insert(nextPath, assert(live.id))
								pendingFocus = nil
								path:set(nextPath)
							elseif
								commitItem(live)
								and (
									live.dismiss == true
									or (live.dismiss ~= false and not live.checked and not live.selected)
								)
							then
								close()
							end
						end,
					})
					row:AddTag("facet-menu-item")
					surfaces.attach(row, {
						ctx.styled(
							Host.Frame({
								Name = "Hairline",
								Size = D2.new(1, 0, 0, 1),
								ZIndex = 3,
								Visible = function(use: ComposeTypes.Use)
									return use(entrySource).ruled == true and not use(sheeted)
								end,
							}),
							"menu-hairline"
						) :: Types.Child,
					})
					Compose.watch(function(use: ComposeTypes.Use)
						if hitFloor(use) < ctx.metric("targetSizes.minimum", use) then
							row:AddTag("facet-menu-dense")
						elseif row:HasTag("facet-menu-dense") then
							row:RemoveTag("facet-menu-dense")
						end
					end)
					local accessories: { Types.Child } = {
						Host.UIListLayout({
							FillDirection = E.FillDirection.Horizontal,
							SortOrder = E.SortOrder.LayoutOrder,
							VerticalAlignment = E.VerticalAlignment.Center,
							Padding = D.new(0, 8),
						}) :: Types.Child,
					}
					if item.badge ~= nil then
						table.insert(
							accessories,
							UI.Badge({
								Name = "Count",
								LayoutOrder = 1,
								label = function(use: ComposeTypes.Use): string
									local badge = read(actionItem(use(source)).badge, use)
									return if badge == nil then "" else tostring(badge)
								end,
							}) :: Types.Child
						)
					end
					if item.meta ~= nil then
						local meta = ctx.text({
							Name = "Meta",
							LayoutOrder = 0,
							Text = function(use: ComposeTypes.Use): string
								return read(actionItem(use(source)).meta, use) or ""
							end,
						})
						meta:AddTag("facet-secondary")
						table.insert(accessories, meta :: Types.Child)
					end
					if item.shortcutLabel ~= nil then
						local shortcut = ctx.text({
							Name = "Shortcut",
							LayoutOrder = 2,
							Text = function(use: ComposeTypes.Use): string
								return read(actionItem(use(source)).shortcutLabel, use) or ""
							end,
						})
						shortcut:AddTag("facet-secondary")
						table.insert(accessories, shortcut :: Types.Child)
					end
					if #accessories > 1 then
						surfaces.attach(row, {
							Host.Frame "Accessories" {
								BackgroundTransparency = 1,
								AnchorPoint = V2.new(1, 0.5),
								Position = D2.new(
									1,
									if item.checked or item.selected or item.marked then -32 else 0,
									0.5,
									0
								),
								Size = D2.fromOffset(0, 0),
								AutomaticSize = E.AutomaticSize.XY,
								ZIndex = 2,
								table.unpack(accessories),
							} :: Types.Child,
						})
					end
					local avatar = item.avatar
					local rowContent = row:FindFirstChild("Content")
					if avatar and rowContent then
						runtime.mount(function()
							return UI.Avatar({
								Name = "Avatar",
								LayoutOrder = 0,
								name = avatar.name,
								image = avatar.image,
								userId = avatar.userId,
								controlSize = "compact" :: Types.ControlSize,
								Selectable = false,
								Active = false,
								Interactable = false,
							})
						end, rowContent)
					end
					local check = if item.children then nil else row:FindFirstChild("TrailingIcon", true)
					if check and check:IsA("GuiObject") then
						Compose.watch(function(use: ComposeTypes.Use)
							local live = actionItem(use(source))
							check.Visible = if live.checked
								then use(live.checked) == true
								elseif live.selected then use(live.selected) == live.value
								else read(live.marked, use) == true
						end)
					end
					if item.role == "destructive" then
						row:AddTag("facet-menu-destructive")
					end
					local content = row:FindFirstChild("Content")
					if content and content:IsA("GuiObject") then
						local layout = content:FindFirstChildWhichIsA("UIListLayout")
						if layout then
							layout.HorizontalAlignment = E.HorizontalAlignment.Left
						end
						local natural = ctx.observe.AbsoluteSize(content)
						Compose.watch(function(use: ComposeTypes.Use)
							local next = table.clone(widths:peek())
							next[rowKey] = use(natural).X
							widths:set(next)
						end)
						Compose.cleanup(function()
							local next = table.clone(widths:peek())
							next[rowKey] = nil
							widths:set(next)
						end)
					end
					return row
				end,
			}),
			Host.UIPadding({
				PaddingTop = function(use: ComposeTypes.Use)
					return D.new(0, if use(sheeted) then 8 else 0)
				end,
				PaddingBottom = function(use: ComposeTypes.Use)
					return D.new(0, if use(sheeted) then 8 else 0)
				end,
				PaddingLeft = function(use: ComposeTypes.Use)
					return D.new(0, if use(sheeted) then 8 else 0)
				end,
				PaddingRight = function(use: ComposeTypes.Use)
					return D.new(0, if use(sheeted) then 8 else 0)
				end,
			}) :: Types.Child,
		}
		local rowSize = ctx.observe.AbsoluteSize(rows)
		local room = Compose.cell(0)
		local function panelWidth(use: ComposeTypes.Use): number
			local widest = 0
			for _, width in use(widths) do
				widest = math.max(widest, width)
			end
			local natural = math.clamp(widest + 48, 220, 400)
			local authored = read(spec.width, use)
			if authored == nil then
				return natural
			end
			local space = use(room)
			local resolved = resolveWidth(authored, natural, space, use)
			return if space > 0 then math.min(resolved, space) else resolved
		end
		runtime.decorate(rows, {
			Position = function(use: ComposeTypes.Use)
				local direction = use(levelDirection)
				if not use(sheeted) or direction == 0 or reduce(use) then
					return D2.fromOffset(0, 0)
				end
				return D2.fromOffset(direction * SLIDE * (1 - level(use)), 0)
			end,
		})
		local panel = Host.ScrollingFrame "MenuPanel" {
			Selectable = false,
			Size = D2.fromOffset(280, 0),
			BorderSizePixel = 0,
			AutomaticCanvasSize = E.AutomaticSize.Y,
			CanvasSize = D2.fromOffset(0, 0),
			ScrollingDirection = E.ScrollingDirection.Y,
			ScrollBarThickness = 4,
			if shown
				then ctx.styled(
					Host.CanvasGroup "MenuGroup" {
						BackgroundTransparency = 1,
						Size = D2.new(1, 0, 0, 0),
						AutomaticSize = E.AutomaticSize.Y,
						GroupTransparency = function(use: ComposeTypes.Use)
							return 1 - shown(use)
						end,
						rows,
					},
					"menu-group"
				)
				else rows,
		}
		if shown then
			surfaces.attach(panel, {
				Host.UIGradient "PresentationFade" {
					Transparency = function(use: ComposeTypes.Use)
						return ctx.types.NumberSequence.new(1 - shown(use))
					end,
				},
			})
		end
		ctx.styled(panel, "menu")
		surfaces.skin(panel)
		local position = ctx.observe.AbsolutePosition(anchor)
		local size = ctx.observe.AbsoluteSize(anchor)
		local modal = if nonmodal
			then Host.Frame "SuggestionsOverlay" {
				BackgroundTransparency = 1,
				Size = D2.fromScale(1, 1),
				ZIndex = 100,
				panel,
			}
			else surfaces.modal(
				function()
					return panel
				end,
				back,
				{
					backgroundTransparency = 1,
					onOutside = close,
					exiting = if phase then phase.exiting else nil,
					initialFocus = landing(current:peek()),
				}
			)
		if nonmodal then
			ctx.modalPortal(modal, anchor)
			runtime.decorate(panel, { ZIndex = 101 })
		end
		local extent = ctx.observe.AbsoluteSize(modal)
		local origin = ctx.observe.AbsolutePosition(modal)
		local measured = ctx.observe.AbsoluteSize(panel)
		local input = surfaces.service("UserInputService")
		local preferred = if input
			then ctx.observe.PreferredInput(input) :: ComposeTypes.Readable<Enum.PreferredInput?>
			else Compose.cell(nil :: Enum.PreferredInput?)
		local asSheet = Compose.formula(function(use: ComposeTypes.Use)
			local presentation = read(spec.presentation, use)
			if presentation and presentation ~= "automatic" then
				return presentation == "sheet"
			end
			return (use(extent).X > 0 and use(extent).X < math.max(600, (#use(path) + 1) * 288 + 16))
				or use(preferred) == E.PreferredInput.Touch
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			sheeted:set(use(asSheet))
		end)
		local guiService = surfaces.service("GuiService")
		local layerOf = ctx.observe.Parent(modal)
		local function originOf(use: ComposeTypes.Use): Vector2
			use(origin)
			use(layerOf)
			use(extent)
			use(position)
			return modal.AbsolutePosition
		end
		local function insets(use: ComposeTypes.Use): (number, number, number, number)
			use(layerOf)
			use(extent)
			local layer = modal:FindFirstAncestorWhichIsA("ScreenGui")
			if guiService == nil or layer == nil then
				return 0, 0, 0, 0
			end
			local screen = layer :: ScreenGui
			if not (screen.IgnoreGuiInset == true or screen.ScreenInsets == E.ScreenInsets.None) then
				return 0, 0, 0, 0
			end
			local ok, topLeft, bottomRight = pcall(function(): (Vector2, Vector2)
				return (guiService :: GuiService):GetGuiInset()
			end)
			if ok and typeof(topLeft) == "Vector2" and typeof(bottomRight) == "Vector2" then
				return topLeft.X, topLeft.Y, bottomRight.X, bottomRight.Y
			end
			return 0, 0, 0, 0
		end
		Compose.watch(function(use: ComposeTypes.Use)
			local left, _, right = insets(use)
			room:set(math.max(0, use(extent).X - left - right - 16))
		end)
		local function place(use: ComposeTypes.Use): (Vector2, Vector2)
			local at, bounds, offer, panelSize, offset =
				use(position), use(size), use(extent), use(measured), originOf(use)
			local insetLeft, insetTop, insetRight, insetBottom = insets(use)
			local low, high =
				V2.new(insetLeft + 8, insetTop + 8), V2.new(offer.X - insetRight - 8, offer.Y - insetBottom - 8)
			if use(asSheet) then
				return V2.new(12 + insetLeft, math.max(12 + insetTop, offer.Y - insetBottom - panelSize.Y - 12)),
					V2.new(panelSize.X / 2, panelSize.Y)
			end
			local x, y = at.X - offset.X, at.Y - offset.Y
			local depth = #use(path)
			local left, top = x + depth * 288, y + bounds.Y + 4
			local above, after = false, true
			local edge, align = spec.edge or "bottom", spec.align or "start"
			local function along(start: number, extentAcross: number, extentAlong: number): number
				return if align == "center"
					then start + (extentAcross - extentAlong) / 2
					elseif align == "end" then start + extentAcross - extentAlong
					else start
			end
			local vertical = depth > 0 or edge == "top" or edge == "bottom"
			if depth > 0 or (edge == "bottom" and align == "start") then
				if offer.Y > 0 and top + panelSize.Y > high.Y then
					top = y - panelSize.Y - 4
					above = true
				end
			elseif vertical then
				left = along(x, bounds.X, panelSize.X)
				local below, over = y + bounds.Y + 4, y - panelSize.Y - 4
				above = edge == "top"
				if edge == "bottom" and offer.Y > 0 and below + panelSize.Y > high.Y and over >= low.Y then
					above = true
				elseif edge == "top" and over < low.Y and (offer.Y <= 0 or below + panelSize.Y <= high.Y) then
					above = false
				end
				top = if above then over else below
			else
				top = along(y, bounds.Y, panelSize.Y)
				local beyond, before = x + bounds.X + 4, x - panelSize.X - 4
				after = edge == "trailing"
				if edge == "trailing" and offer.X > 0 and beyond + panelSize.X > high.X and before >= low.X then
					after = false
				elseif edge == "leading" and before < low.X and (offer.X <= 0 or beyond + panelSize.X <= high.X) then
					after = true
				end
				left = if after then beyond else before
				if offer.Y > 0 then
					top = math.clamp(top, low.Y, math.max(low.Y, high.Y - panelSize.Y))
				end
			end
			if offer.X > 0 then
				left = math.clamp(left, low.X, math.max(low.X, high.X - panelSize.X))
			end
			top = math.max(low.Y, top)
			local pivot: Vector2
			if vertical then
				local reach = if depth > 0 or align == "start"
					then x + depth * 288
					elseif align == "end" then x + bounds.X
					else x + bounds.X / 2
				pivot = V2.new(math.clamp(reach - left, 0, panelSize.X), if above then panelSize.Y else 0)
			else
				local reach = if align == "start" then y elseif align == "end" then y + bounds.Y else y + bounds.Y / 2
				pivot = V2.new(if after then 0 else panelSize.X, math.clamp(reach - top, 0, panelSize.Y))
			end
			return V2.new(left, top), pivot
		end
		runtime.decorate(panel, {
			Size = function(use: ComposeTypes.Use)
				local _, insetTop, _, insetBottom = insets(use)
				local height = math.min(
					use(rowSize).Y,
					math.max(44, use(extent).Y - 24 - insetTop - insetBottom),
					if spec.maxHeight then math.max(60, spec.maxHeight) else math.huge
				)
				if use(asSheet) then
					local insetLeft, _, insetRight = insets(use)
					return D2.new(1, -24 - insetLeft - insetRight, 0, height)
				end
				return D2.fromOffset(panelWidth(use), height)
			end,
		})
		if shown then
			surfaces.popover(panel, shown, place, MATERIALIZE)
		else
			runtime.decorate(panel, {
				Position = function(use: ComposeTypes.Use)
					local at = place(use)
					return D2.fromOffset(at.X, at.Y)
				end,
			})
		end
		local gui = surfaces.service("GuiService")
		local selected = if gui then ctx.observe.SelectedObject(gui) else Compose.cell(nil :: GuiObject?)
		local function selectedBranch(use: ComposeTypes.Use?): Nav.MenuAction<V>?
			local node = read(selected, use)
			for _, item in read(current, use) do
				if
					item.divider ~= true
					and node
					and item.id == node.Name
					and item.children
					and read(item.enabled, use) ~= false
				then
					return item
				end
			end
			return nil
		end
		ctx.action(modal, "MenuRight", { E.KeyCode.Right, E.KeyCode.DPadRight }, function(use: ComposeTypes.Use)
			return selectedBranch(use) ~= nil
		end, function()
			local item = selectedBranch()
			if item then
				local nextPath = table.clone(path:peek())
				table.insert(nextPath, assert(item.id))
				path:set(nextPath)
			end
		end, { priority = 2100, capture = true })
		ctx.action(modal, "MenuLeft", { E.KeyCode.Left, E.KeyCode.DPadLeft }, function(use: ComposeTypes.Use)
			return #use(path) > 0
		end, back, { priority = 2100, capture = true })
		local focusIn = surfaces.selecting()
		local placed = ctx.observe.Parent(modal)
		Compose.watch(function(use: ComposeTypes.Use)
			local rows = use(current)
			use(placed)
			if gui and not nonmodal and focusIn(use) then
				local target = if pendingFocus then surfaces.firstSelectable(panel, pendingFocus) else nil
				if not target then
					local chosen = landing(rows)
					target = if chosen then surfaces.firstSelectable(panel, chosen) else nil
				end
				if not target then
					for _, item in rows do
						if item.divider ~= true and read(item.enabled, use) ~= false then
							local live = actionItem(item)
							local chosen = if live.selected
								then live.selected:peek() == live.value
								else read(live.marked, use) == true
							if chosen then
								target = surfaces.firstSelectable(panel, tostring(live.id))
								if target then
									break
								end
							end
						end
					end
				end
				if not target then
					for _, item in rows do
						if not item.divider and read(item.enabled, use) ~= false then
							target = surfaces.firstSelectable(panel, tostring(item.id))
							if target then
								break
							end
						end
					end
				end
				if target and modal.Parent then
					gui.SelectedObject = target
				end
			end
		end)
		local centered: string? = nil
		local settling: RBXScriptConnection? = nil
		local function stopSettling()
			if settling then
				settling:Disconnect()
				settling = nil
			end
		end
		Compose.cleanup(stopSettling)
		local rowLayout = rows:FindFirstChildWhichIsA("UIListLayout")
		local laidOut = if rowLayout then ctx.observe.AbsoluteContentSize(rowLayout) else Compose.cell(V2.zero)
		Compose.watch(function(use: ComposeTypes.Use)
			local content = use(laidOut) :: Vector2?
			local level = table.concat(use(path), "/") .. "@" .. tostring(if content then content.Y else 0)
			if centered == level then
				return
			end
			local chosen = landing(use(current))
			if chosen == nil then
				centered = level
				return
			end
			use(measured)
			use(rowSize)
			local row = rows:FindFirstChild(chosen)
			if row == nil or not row:IsA("GuiObject") then
				return
			end
			local function target(): number?
				local window, canvas = panel.AbsoluteSize.Y, rows.AbsoluteSize.Y
				if window <= 0 or canvas <= 0 or row.Parent ~= rows then
					return nil
				end
				local gap = if rowLayout then rowLayout.Padding.Offset else 0
				local top = rows.AbsolutePosition.Y - panel.AbsolutePosition.Y + panel.CanvasPosition.Y
				canvas = math.max(canvas + top, panel.AbsoluteCanvasSize.Y)
				local inset = rows:FindFirstChildWhichIsA("UIPadding")
				if inset then
					local ok, styled = pcall(function(): UDim
						return inset:GetStyled("PaddingTop")
					end)
					top += if ok then styled.Offset else inset.PaddingTop.Offset
				end
				local offset = top
				for _, sibling in rows:GetChildren() do
					if
						sibling ~= row
						and sibling:IsA("GuiObject")
						and sibling.Visible
						and sibling.LayoutOrder < (row :: GuiObject).LayoutOrder
					then
						offset += sibling.AbsoluteSize.Y + gap
					end
				end
				return math.clamp(
					offset + (row :: GuiObject).AbsoluteSize.Y / 2 - window / 2,
					0,
					math.max(0, canvas - window)
				)
			end
			local first = target()
			if first == nil then
				return
			end
			panel.CanvasPosition = V2.new(panel.CanvasPosition.X, first)
			centered = level
			local services = ctx.config.services
			local frames = services and services.RunService
			if frames then
				local remaining = 2
				stopSettling()
				settling = frames.Heartbeat:Connect(function()
					remaining -= 1
					local fresh = target()
					if fresh and panel.CanvasPosition.Y ~= fresh then
						panel.CanvasPosition = V2.new(panel.CanvasPosition.X, fresh)
					end
					if remaining <= 0 then
						stopSettling()
					end
				end)
			end
		end)
		surfaces.attach(modal, {
			Compose.keyed({
				from = function(use: ComposeTypes.Use)
					if use(asSheet) then
						return {}
					end
					local levels: { { id: string, items: { Nav.MenuItem<V> }, prefix: { string }, depth: number } } = {}
					local items = use(rootItems)
					local prefix: { string } = {}
					for depth, selectedId in use(path) do
						table.insert(levels, {
							id = table.concat(prefix, "/"),
							items = items,
							prefix = table.clone(prefix),
							depth = depth,
						})
						local found: Nav.MenuAction<V>?
						for _, item in items do
							if item.divider ~= true and item.id == selectedId then
								found = item
								break
							end
						end
						if not found or not found.children then
							break
						end
						items = read(found.children, use)
						table.insert(prefix, selectedId)
					end
					return levels
				end,
				key = function(level: { id: string, items: { Nav.MenuItem<V> }, prefix: { string }, depth: number })
					return level.id
				end,
				render = function(
					source: ComposeTypes.Readable<{ id: string, items: { Nav.MenuItem<V> }, prefix: { string }, depth: number }>
				)
					return ctx.styled(
						Host.Frame "AncestorMenu" {
							ZIndex = 103,
							BorderSizePixel = 0,
							Size = D2.fromOffset(280, 0),
							AutomaticSize = E.AutomaticSize.Y,
							Position = function(use: ComposeTypes.Use)
								local at, bounds, offset = use(position), use(size), originOf(use)
								local insetLeft, insetTop = insets(use)
								return D2.fromOffset(
									math.max(insetLeft + 8, at.X - offset.X + (use(source).depth - 1) * 288),
									math.max(insetTop + 8, at.Y - offset.Y + bounds.Y + 4)
								)
							end,
							Host.UIListLayout({
								FillDirection = E.FillDirection.Vertical,
								SortOrder = E.SortOrder.LayoutOrder,
							}) :: Types.Child,
							Compose.keyed({
								from = function(use: ComposeTypes.Use)
									return use(source).items
								end,
								key = function(item: Nav.MenuItem<V>, index: number)
									return item.id or index
								end,
								render = function(
									row: ComposeTypes.Readable<Nav.MenuItem<V>>,
									index: ComposeTypes.Readable<number>
								)
									local item = row:peek()
									if item.divider then
										return ctx.styled(
											Host.Frame({ Size = D2.new(1, 0, 0, 1), LayoutOrder = index }),
											"divider"
										)
									end
									local button = UI.Button({
										Name = item.id,
										label = item.label,
										enabled = item.enabled,
										icon = item.icon,
										subtitle = function(use: ComposeTypes.Use)
											return read(item.description, use) or ""
										end,
										LayoutOrder = index,
										Size = function(use: ComposeTypes.Use)
											return D2.new(1, 0, 0, hitFloor(use))
										end,
										selected = function(use: ComposeTypes.Use)
											if use(path)[use(source).depth] == item.id then
												return true
											end
											local live = actionItem(item)
											return if live.checked
												then use(live.checked)
												elseif live.selected then use(live.selected) == live.value
												else read(live.marked, use) == true
										end,
										trailingIcon = if item.children
											then "chevron.trailing"
											elseif
												item.checked ~= nil
												or item.selected ~= nil
												or item.marked ~= nil
											then "checkmark"
											else nil,
										onActivate = function()
											if item.children then
												local next = table.clone(source:peek().prefix)
												table.insert(next, assert(item.id))
												path:set(next)
											elseif
												commitItem(item)
												and (
													item.dismiss == true
													or (
														item.dismiss ~= false
														and not item.checked
														and not item.selected
													)
												)
											then
												close()
											end
										end,
									})
									button:AddTag("facet-menu-item")
									if item.role == "destructive" then
										button:AddTag("facet-menu-destructive")
									end
									local mark = if item.children
										then nil
										else button:FindFirstChild("TrailingIcon", true)
									if mark and mark:IsA("GuiObject") then
										Compose.watch(function(use: ComposeTypes.Use)
											local live = actionItem(item)
											mark.Visible = if live.checked
												then use(live.checked) == true
												elseif live.selected then use(live.selected) == live.value
												else read(live.marked, use) == true
										end)
									end
									local content = button:FindFirstChild("Content")
									local layout = if content
										then content:FindFirstChildWhichIsA("UIListLayout")
										else nil
									if layout then
										layout.HorizontalAlignment = E.HorizontalAlignment.Left
									end
									surfaces.attach(button, {
										ctx.styled(
											Host.Frame({
												Name = "Hairline",
												Size = D2.new(1, 0, 0, 1),
												ZIndex = 3,
												Visible = function(use: ComposeTypes.Use)
													local before = use(source).items[use(index) - 1]
													return before ~= nil and before.divider ~= true
												end,
											}),
											"menu-hairline"
										) :: Types.Child,
									})
									return button
								end,
							}),
						},
						"menu"
					)
				end,
			}),
		})
		return modal
	end

	local function buildMenu<V>(spec: Nav.MenuSpec<V>, wrap: boolean): GuiObject
		assert(spec.items ~= nil, "Menu requires items")
		menuItems(read(spec.items))
		assert(
			spec.edge == nil or table.find({ "top", "bottom", "leading", "trailing" }, spec.edge),
			"Facet UI.Menu: edge must be top, bottom, leading or trailing"
		)
		assert(
			spec.align == nil or table.find({ "start", "center", "end" }, spec.align),
			"Facet UI.Menu: align must be start, center or end"
		)
		assert(
			spec.maxHeight == nil
				or (type(spec.maxHeight) == "number" and spec.maxHeight > 0 and spec.maxHeight < math.huge),
			"Facet UI.Menu: maxHeight must be a finite number of pixels above 0"
		)
		checkWidth(read(spec.width))
		if spec.label ~= nil and spec.trigger ~= nil then
			error("Facet UI.Menu: give label or trigger, not both", 0)
		end
		local opened: ComposeTypes.Cell<boolean> = spec.isPresented or Compose.cell(false)
		local announced = false
		local function announce(state: boolean)
			if state == announced then
				return
			end
			announced = state
			if state and spec.onOpen then
				spec.onOpen()
			elseif not state and spec.onClose then
				spec.onClose()
			end
		end
		local function close()
			if opened:peek() then
				opened:set(false)
			end
			announce(false)
		end
		local function open()
			if read(spec.enabled) == false or opened:peek() then
				return
			end
			opened:set(true)
			announce(true)
		end
		Compose.watch(function(use: ComposeTypes.Use)
			announce(use(opened))
		end)
		Compose.cleanup(function()
			announce(false)
		end)
		local allowed: { Nav.MenuTrigger } = spec.triggers
			or { "activate", "secondary", "longPress", "keyboard", "gamepad" }
		local function allows(trigger: Nav.MenuTrigger): boolean
			return table.find(allowed, trigger) ~= nil
		end
		local authored = if type(spec.trigger) == "function" then spec.trigger() else spec.trigger
		local root: GuiObject
		local trigger: GuiObject
		local automatic = spec.AutomaticSize or (if spec.Size ~= nil then E.AutomaticSize.None else E.AutomaticSize.XY)
		if authored ~= nil and wrap then
			trigger = authored
			root = Host.Frame(ctx.props(spec, MENU_KEYS, {
				Name = "Menu",
				BackgroundTransparency = 1,
				Size = D2.fromOffset(0, 0),
				AutomaticSize = automatic,
				trigger,
			}))
			if allows("activate") then
				runtime.connect(trigger, "Activated", open)
			end
		elseif authored == nil then
			local triggerProps: Inputs.ButtonProps = {
				Name = "Trigger",
				label = spec.label or "Menu",
				enabled = spec.enabled,
				onActivate = if allows("activate") then open else nil,
			}
			if spec.Size ~= nil then
				triggerProps.AutomaticSize = automatic
				triggerProps.Size = function(use: ComposeTypes.Use)
					local sizing = read(automatic, use)
					local width = sizing == E.AutomaticSize.X or sizing == E.AutomaticSize.XY
					local height = sizing == E.AutomaticSize.Y or sizing == E.AutomaticSize.XY
					return D2.new(
						if width then 0 else 1,
						0,
						if height then 0 else 1,
						if height then ctx.controlSize(nil, "height", use) else 0
					)
				end
				triggerProps.TextTruncate = E.TextTruncate.AtEnd
				triggerProps.TextWrapped = false
				triggerProps.ClipsDescendants = true
				local attributes: Types.Attributes = {
					FacetLabel = function(use: ComposeTypes.Use)
						return read(triggerProps.label, use)
					end,
				}
				triggerProps.Attributes = attributes
			end
			if spec.disclosure then
				table.insert(
					triggerProps,
					ctx.icon("chevron.up.chevron.down", {
						Name = "Disclosure",
						Size = D2.fromOffset(12, 12),
						AnchorPoint = V2.new(1, 0.5),
						Position = D2.new(1, 20, 0.5, 0),
						BackgroundTransparency = 1,
					}) :: Types.Child
				)
			end
			local button = UI.Button(triggerProps)
			if spec.disclosure then
				button:AddTag("facet-disclosure")
			end
			trigger = button
			root = Host.Frame(ctx.props(spec, MENU_KEYS, {
				Name = "Menu",
				BackgroundTransparency = 1,
				Size = D2.fromOffset(0, 0),
				AutomaticSize = automatic,
				trigger,
			}))
		else
			trigger = authored
			root = authored
			local native = ctx.props(spec, MENU_KEYS, {})
			local properties: { [string]: unknown } = {}
			local children: { Types.Child } = {}
			for key, value in (native :: unknown) :: { [unknown]: unknown } do
				if type(key) == "number" then
					table.insert(children, value :: Types.Child)
				elseif type(key) == "string" then
					properties[key] = value
				end
			end
			if next(properties) ~= nil then
				runtime.decorate(trigger, properties)
			end
			if #children > 0 then
				surfaces.attach(trigger, children)
			end
			if allows("activate") then
				runtime.connect(trigger, "Activated", open)
			end
		end
		local available = surfaces.available(root)
		local mounted = false
		Compose.watch(function(use: ComposeTypes.Use)
			local active = use(available)
			if active then
				mounted = true
			end
			if mounted and (not active or read(spec.enabled, use) == false) then
				close()
			end
		end)
		if allows("secondary") then
			runtime.connect(trigger, "InputBegan", function(input: InputObject)
				if input.UserInputType == E.UserInputType.MouseButton2 then
					open()
				end
			end)
		end
		if allows("longPress") then
			runtime.connect(trigger, "TouchLongPress", function(_: { Vector2 }, state: Enum.UserInputState)
				if state == E.UserInputState.Begin then
					open()
				end
			end)
		end
		local gui = surfaces.service("GuiService")
		local selected = if gui then ctx.observe.SelectedObject(gui) else Compose.cell(nil :: GuiObject?)
		local bindings: { Types.ActionBinding } = {}
		if allows("keyboard") then
			table.insert(bindings, E.KeyCode.Menu)
			bindings[#bindings + 1] = { KeyCode = E.KeyCode.F10, PrimaryModifier = E.KeyCode.LeftShift }
			bindings[#bindings + 1] = { KeyCode = E.KeyCode.F10, PrimaryModifier = E.KeyCode.RightShift }
		end
		if allows("gamepad") then
			table.insert(bindings, E.KeyCode.ButtonY)
		end
		if #bindings > 0 then
			ctx.action(root, "Menu", bindings, function(use: ComposeTypes.Use)
				return surfaces.within(use(selected), root)
			end, open, { priority = 1200 })
		end
		surfaces.attach(root, {
			surfaces.overlay(root, opened, function(phase: Nav.PresencePhase?)
				return menuPanel(spec, close, trigger, nil, phase)
			end, { motion = POPOVER }),
		})
		return root
	end
	UI.Menu = ctx.construct("Menu", function<V>(spec: Nav.MenuSpec<V>): GuiObject
		return buildMenu(spec, false)
	end)

	local pickerKeys = {
		"selected",
		"options",
		"style",
		"query",
		"placeholder",
		"label",
		"required",
		"multiple",
		"onChanging",
		"onChange",
		"enabled",
		"indicator",
		"axis",
		"sizing",
		"iconOnly",
		"textSize",
		"isPresented",
		"requiredMark",
		"hint",
		"errorText",
		"controlSize",
		"appearance",
		"corners",
		"maxHeight",
		"indicatorPosition",
		"valueAlignment",
	}
	local optionFields: { [string]: boolean } = {
		id = true,
		value = true,
		label = true,
		description = true,
		icon = true,
		badge = true,
		enabled = true,
		meta = true,
		avatar = true,
		sectionTitle = true,
		indicator = true,
	}
	local MENU_WORDS: { [string]: string } = { standard = "standard", contrast = "contrast", utility = "utility" }
	local STRIP_WORDS: { [string]: string } = { filled = "filled", stroke = "stroke", utility = "utility" }
	local function liveIcon<V>(source: ComposeTypes.Readable<Nav.PickerOption<V>>): Types.Value<string>?
		if source:peek().icon == nil then
			return nil
		end
		return function(use: ComposeTypes.Use): string
			return read(use(source).icon, use) or ""
		end
	end
	local function appearanceFor(style: Nav.PickerStyle, word: unknown): string?
		if word == nil then
			return nil
		end
		if style == "menu" or style == "navigationLink" then
			if type(word) ~= "string" or MENU_WORDS[word] == nil then
				error(
					`Facet UI.Picker: a {style} appearance is standard | contrast | utility (got {tostring(word)})`,
					0
				)
			end
		elseif style == "segmented" then
			if type(word) ~= "string" or STRIP_WORDS[word] == nil then
				error(`Facet UI.Picker: a segmented appearance is filled | stroke | utility (got {tostring(word)})`, 0)
			end
		elseif style == "automatic" then
			if type(word) ~= "string" or (MENU_WORDS[word] == nil and STRIP_WORDS[word] == nil) then
				error(
					"Facet UI.Picker: appearance is standard | contrast | utility | filled | stroke "
						.. `(got {tostring(word)})`,
					0
				)
			end
		else
			error(`Facet UI.Picker: a {style} picker takes no appearance`, 0)
		end
		return word :: string
	end
	local function translate(word: string?, style: Nav.PickerStyle): string?
		if word == nil then
			return nil
		end
		if style == "segmented" then
			return if word == "standard" then "filled" elseif word == "contrast" then "stroke" else word
		elseif style == "menu" or style == "navigationLink" then
			return if word == "filled" then "standard" elseif word == "stroke" then "contrast" else word
		end
		return nil
	end
	local chrome = fieldChrome(ctx)
	UI.Picker = ctx.construct("Picker", function<V>(spec: Nav.PickerSpec<V>): GuiObject
		writable(spec.selected, "Picker.selected")
		assert(spec.onChange == nil or type(spec.onChange) == "function", "Picker.onChange must be a function")
		assert(spec.onChanging == nil or type(spec.onChanging) == "function", "Picker.onChanging must be a function")
		assert(spec.required == nil or type(spec.required) == "boolean", "Picker.required must be a boolean")
		assert(
			spec.enabled == nil or type(read(spec.enabled)) == "boolean",
			"Picker.enabled must be a boolean or a readable boolean"
		)
		local declaredStyle: Nav.PickerStyle = spec.style or "automatic"
		chrome.check("Picker", {
			label = spec.label,
			requiredMark = spec.requiredMark,
			hint = spec.hint,
			errorText = spec.errorText,
			controlSize = spec.controlSize,
			corners = spec.corners,
		})
		appearanceFor(declaredStyle, read(spec.appearance))
		assert(
			spec.maxHeight == nil
				or (type(spec.maxHeight) == "number" and spec.maxHeight > 0 and spec.maxHeight < math.huge),
			"Facet UI.Picker: maxHeight must be a finite number of pixels above zero"
		)
		assert(
			spec.maxHeight == nil or table.find({ "automatic", "menu", "navigationLink" }, declaredStyle),
			"Facet UI.Picker: maxHeight belongs to the menu styles"
		)
		assert(
			spec.valueAlignment == nil or spec.valueAlignment == "start" or spec.valueAlignment == "end",
			"Facet UI.Picker: valueAlignment must be start or end"
		)
		assert(
			spec.indicatorPosition == nil or declaredStyle == "radioGroup",
			"Facet UI.Picker: indicatorPosition belongs to the radioGroup style"
		)
		assert(
			spec.indicatorPosition == nil or spec.indicatorPosition == "leading" or spec.indicatorPosition == "trailing",
			"Facet UI.Picker: indicatorPosition must be leading or trailing"
		)
		if spec.requiredMark == "required" and spec.label ~= nil then
			local marked = table.clone(spec)
			local words = spec.label
			marked.requiredMark = nil
			marked.label = function(use: ComposeTypes.Use)
				return (read(words, use) or "") .. " *"
			end
			return UI.Picker(marked)
		end
		if spec.hint ~= nil or spec.errorText ~= nil then
			local inner = table.clone(spec)
			local shell: Types.FrameNativeProps = {}
			local source = (inner :: unknown) :: { [string]: unknown }
			local target = (shell :: unknown) :: { [string]: unknown }
			for _, key in { "Name", "Size", "Position", "AnchorPoint", "LayoutOrder", "Visible", "ZIndex" } do
				target[key], source[key] = source[key], nil
			end
			inner.hint, inner.errorText = nil, nil
			inner.Name = "Control"
			local control = UI.Picker(inner)
			local failure = chrome.errorOf({ errorText = spec.errorText }, nil)
			Compose.watch(function(use: ComposeTypes.Use)
				local failing = failure(use) ~= ""
				for _, node in control:GetDescendants() do
					if node.Name == "Trigger" and node:IsA("GuiObject") then
						if failing then
							node:AddTag("facet-invalid")
						elseif node:HasTag("facet-invalid") then
							node:RemoveTag("facet-invalid")
						end
					end
				end
			end)
			shell.Name = shell.Name or "Picker"
			return chrome.wrap({
				control = "Picker",
				spec = { hint = spec.hint, errorText = spec.errorText },
				plate = control,
				focus = function() end,
				enabled = function(use: ComposeTypes.Use?)
					return read(spec.enabled, use) ~= false
				end,
				native = shell,
			})
		end
		assert(
			type(spec.options) == "table" or type(spec.options) == "function",
			"Facet UI.Picker: options must be an array of { value, label } entries, a Compose readable, or a function(use) that returns one"
		)
		local function isSelected(value: V, use: ComposeTypes.Use?): boolean
			if spec.multiple then
				return read(spec.selected, use)[value] == true
			else
				return read(spec.selected, use) == value
			end
		end
		local function commitSelection<T>(
			selected: ComposeTypes.Cell<T>,
			value: T,
			onChanging: ((T, T) -> boolean?)?,
			onChange: ((T) -> ())?
		)
			local previous = selected:peek()
			if onChanging and onChanging(value, previous) == false then
				return
			end
			runtime:batch(function()
				selected:set(value)
				if onChange then
					onChange(value)
				end
			end)
		end
		local function select(value: V)
			if read(spec.enabled) == false then
				return
			end
			if spec.multiple then
				local previous = spec.selected:peek()
				local nextValue: { [V]: boolean } = {}
				for key, flag in previous do
					if key ~= value then
						nextValue[key] = flag
					end
				end
				if not previous[value] then
					nextValue[value] = true
				end
				if spec.required and next(nextValue) == nil then
					return
				end
				commitSelection(spec.selected, nextValue, spec.onChanging, spec.onChange)
			else
				if value ~= spec.selected:peek() then
					commitSelection(spec.selected, value, spec.onChanging, spec.onChange)
				end
			end
		end
		local declaredIndicator, declaredAxis, declaredSizing = read(spec.indicator), read(spec.axis), read(spec.sizing)
		assert(
			declaredIndicator == nil or table.find({ "automatic", "pill", "underline", "none" }, declaredIndicator),
			"Invalid Picker.indicator"
		)
		assert(declaredAxis == nil or table.find({ "x", "y" }, declaredAxis), "Picker.axis must be x or y")
		assert(
			declaredSizing == nil or table.find({ "fill", "hug" }, declaredSizing),
			"Picker.sizing must be fill or hug"
		)
		local style = spec.style or "automatic"
		if style == "automatic" then
			local input = surfaces.service("UserInputService")
			local preferred = if input
				then ctx.observe.PreferredInput(input) :: ComposeTypes.Readable<Enum.PreferredInput?>
				else Compose.cell(nil :: Enum.PreferredInput?)
			local opened: ComposeTypes.Cell<boolean> = spec.isPresented or Compose.cell(false)
			local width = Compose.cell(0)
			local measure = ctx.text({
				Name = "LabelMeasure",
				Text = derive(function(use: ComposeTypes.Use?)
					local labels = {}
					for _, option in read(spec.options, use) do
						table.insert(labels, tostring(read(option.label, use) or ""))
					end
					return table.concat(labels, "")
				end, spec.options, table.unpack(optionLabels(spec.options))),
				TextSize = spec.textSize,
				TextWrapped = false,
				Visible = false,
			})
			measure:AddTag("facet-type-control")
			local labelBounds = ctx.observe.TextBounds(measure)

			local resolved = Compose.formula(function(use: ComposeTypes.Use): Nav.PickerStyle
				if spec.query then
					return "navigationLink"
				end
				local list: { Nav.PickerOption<V> } = read(spec.options, use)
				local count = #list
				local available = use(width)
				local described = false
				for _, option in list do
					if option.description ~= nil then
						described = true
					end
				end
				local needed = use(labelBounds).X + count * 24 + math.max(0, count - 1) * 4 + 6
				if count <= 4 and not described and (available == 0 or (available >= 360 and needed <= available)) then
					return "segmented"
				end
				local kind = use(preferred)
				if kind == E.PreferredInput.KeyboardAndMouse or kind == E.PreferredInput.Touch then
					return "menu"
				end
				return if count <= 6 then "inline" else "menu"
			end)
			local props = ctx.props(spec, pickerKeys, {
				Name = "Picker",
				BackgroundTransparency = 1,
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
			})
			table.insert(
				props,
				Compose.keyed({
					from = function(use: ComposeTypes.Use)
						return { use(resolved) }
					end,
					render = function(current: ComposeTypes.Readable<Nav.PickerStyle>)
						local presentation: Nav.PickerStyle = current:peek()
						local automatic = props.AutomaticSize
						local size = derive(function(use: ComposeTypes.Use?)
							local sizing = read(automatic, use)
							return D2.fromScale(
								if sizing == E.AutomaticSize.X or sizing == E.AutomaticSize.XY then 0 else 1,
								if sizing == E.AutomaticSize.Y or sizing == E.AutomaticSize.XY then 0 else 1
							)
						end, automatic)
						if spec.multiple then
							local child: Nav.MultiplePickerSpec<V> = {
								options = spec.options,
								query = spec.query,
								placeholder = spec.placeholder,
								label = spec.label,
								required = spec.required,
								enabled = spec.enabled,
								indicator = spec.indicator,
								axis = spec.axis,
								sizing = spec.sizing,
								iconOnly = spec.iconOnly,
								textSize = spec.textSize,
								Name = "Presentation",
								style = presentation,
								isPresented = opened,
								AutomaticSize = automatic,
								Size = size,
								controlSize = spec.controlSize,
								corners = if presentation == "menu"
										or presentation == "segmented"
										or presentation == "navigationLink"
									then spec.corners
									else nil,
								maxHeight = if presentation == "menu" or presentation == "navigationLink"
									then spec.maxHeight
									else nil,
								appearance = if spec.appearance ~= nil
										and (
											presentation == "menu"
											or presentation == "segmented"
											or presentation == "navigationLink"
										)
									then function(use: ComposeTypes.Use): string
										return translate(read(spec.appearance, use), presentation) or "utility"
									end
									else nil,
								valueAlignment = spec.valueAlignment,
								multiple = true :: true,
								selected = spec.selected,
								onChanging = spec.onChanging,
								onChange = spec.onChange,
							}
							return UI.Picker(child)
						else
							local child: Nav.SinglePickerSpec<V> = {
								options = spec.options,
								query = spec.query,
								placeholder = spec.placeholder,
								label = spec.label,
								required = spec.required,
								enabled = spec.enabled,
								indicator = spec.indicator,
								axis = spec.axis,
								sizing = spec.sizing,
								iconOnly = spec.iconOnly,
								textSize = spec.textSize,
								Name = "Presentation",
								style = presentation,
								isPresented = opened,
								AutomaticSize = automatic,
								Size = size,
								controlSize = spec.controlSize,
								corners = if presentation == "menu"
										or presentation == "segmented"
										or presentation == "navigationLink"
									then spec.corners
									else nil,
								maxHeight = if presentation == "menu" or presentation == "navigationLink"
									then spec.maxHeight
									else nil,
								appearance = if spec.appearance ~= nil
										and (
											presentation == "menu"
											or presentation == "segmented"
											or presentation == "navigationLink"
										)
									then function(use: ComposeTypes.Use): string
										return translate(read(spec.appearance, use), presentation) or "utility"
									end
									else nil,
								valueAlignment = spec.valueAlignment,
								multiple = false :: false,
								selected = spec.selected,
								onChanging = spec.onChanging,
								onChange = spec.onChange,
							}
							return UI.Picker(child)
						end
					end,
				})
			)
			table.insert(props, measure)
			local container = Host.Frame(props)
			local measured = ctx.observe.AbsoluteSize(container)
			Compose.watch(function(use: ComposeTypes.Use)
				width:set(use(measured).X)
			end)
			return container
		end
		local options = Compose.formula(function(use: ComposeTypes.Use)
			local query = string.lower(tostring(read(spec.query, use) or ""))
			local result: { Nav.PickerOption<V> } = {}
			local seen: { [V | string]: boolean } = {}
			local list: { Nav.PickerOption<V> } = read(spec.options, use)
			for key in list do
				assert(
					type(key) == "number" and key >= 1 and key <= #list and key % 1 == 0,
					"Picker options require a dense array"
				)
			end
			for _, option in list do
				for field in (option :: unknown) :: { [unknown]: unknown } do
					assert(
						type(field) == "string" and optionFields[field] == true,
						`Unknown Picker option field {tostring(field)}`
					)
				end
				assert(
					option.description == nil or type(read(option.description, use)) == "string",
					"Picker description must be text"
				)
				assert(
					option.enabled == nil or type(read(option.enabled, use)) == "boolean",
					"Picker option enabled must be a boolean"
				)
				assert(
					option.icon == nil or type(read(option.icon, use)) == "string",
					"Picker option icon must be an icon name"
				)
				local badge = read(option.badge, use)
				assert(
					badge == nil or type(badge) == "string" or type(badge) == "number",
					"Picker option badge must be text or a number"
				)
				local key = option.id or option.value
				assert(key ~= nil and not seen[key], "Picker options require unique values or ids")
				seen[key] = true
				assert(
					type(read(option.label, use)) == "string" and string.find(read(option.label, use), "%S") ~= nil,
					"Picker options require nonempty labels"
				)
				assert(
					read(spec.iconOnly) ~= true or option.icon ~= nil,
					"Picker.iconOnly requires an icon on each option"
				)
				local label = tostring(read(option.label, use) or "")
				if query == "" or string.find(string.lower(label), query, 1, true) then
					table.insert(result, option)
				end
			end
			return result
		end)
		if style == "menu" then
			local native: Types.FrameNativeProps = ctx.props(spec, pickerKeys)
			local menuSpec: Nav.MenuSpec<V> = { items = {} }
			for key, value in pairs(native) do
				menuSpec[key] = value
			end
			menuSpec.enabled = spec.enabled
			menuSpec.isPresented = spec.isPresented
			menuSpec.query = spec.query
			menuSpec.maxHeight = spec.maxHeight
			local valueText = function(use: ComposeTypes.Use): string
				local labels = {}
				for _, option in read(spec.options, use) do
					if isSelected(option.value, use) then
						table.insert(labels, read(option.label, use))
					end
				end
				return if #labels > 0
					then table.concat(labels, ", ")
					else read(spec.placeholder, use) or (if spec.label == nil then "Choose" else "Choose")
			end
			local triggerProps: Inputs.ButtonProps = {
				Name = "Trigger",
				label = valueText,
				enabled = spec.enabled,
				controlSize = spec.controlSize,
				corners = spec.corners,
				appearance = if spec.appearance ~= nil
					then function(use: ComposeTypes.Use): string
						local word = appearanceFor("menu", read(spec.appearance, use))
						return if word == "contrast"
							then "emphasis"
							elseif word == "utility" then "utility"
							else "default"
					end
					else nil,
				Attributes = { FacetLabel = valueText } :: Types.Attributes,
				ctx.icon("chevron.up.chevron.down", {
					Name = "Disclosure",
					Size = D2.fromOffset(12, 12),
					AnchorPoint = V2.new(1, 0.5),
					Position = D2.new(1, 20, 0.5, 0),
					BackgroundTransparency = 1,
				}) :: Types.Child,
			}
			if spec.Size ~= nil and spec.label == nil then
				local automatic = spec.AutomaticSize or E.AutomaticSize.None
				triggerProps.AutomaticSize = automatic
				triggerProps.Size = function(use: ComposeTypes.Use)
					local sizing = read(automatic, use)
					local width = sizing == E.AutomaticSize.X or sizing == E.AutomaticSize.XY
					local height = sizing == E.AutomaticSize.Y or sizing == E.AutomaticSize.XY
					return D2.new(
						if width then 0 else 1,
						0,
						if height then 0 else 1,
						if height then ctx.controlSize(spec.controlSize, "height", use) else 0
					)
				end
				triggerProps.TextTruncate = E.TextTruncate.AtEnd
				triggerProps.TextWrapped = false
				triggerProps.ClipsDescendants = true
			end
			local trigger = UI.Button(triggerProps)
			trigger:AddTag("facet-disclosure")
			menuSpec.trigger = function(): GuiObject
				return trigger
			end
			menuSpec.items = function(use: ComposeTypes.Use)
				local items = {}
				for _, option in use(options) do
					table.insert(items, {
						id = option.id or tostring(option.value),
						label = option.label,
						icon = option.icon,
						description = option.description,
						badge = option.badge,
						meta = option.meta,
						avatar = option.avatar,
						sectionTitle = option.sectionTitle,
						dismiss = not spec.multiple,
						marked = function(use: ComposeTypes.Use)
							return isSelected(option.value, use)
						end,
						enabled = option.enabled,
						onSelect = function()
							select(option.value)
						end,
					})
				end
				return items
			end
			if spec.label == nil then
				return buildMenu(menuSpec, true)
			end
			menuSpec.Name = "Value"
			menuSpec.Size = nil
			menuSpec.AutomaticSize = E.AutomaticSize.XY
			menuSpec.AnchorPoint = nil
			menuSpec.Position = nil
			local inline = spec.valueAlignment == "start"
			local label = ctx.text({
				Name = "Label",
				Text = function(use: ComposeTypes.Use)
					return read(spec.label, use) or ""
				end,
				Size = if inline then D2.fromOffset(0, 0) else D2.new(1, 0, 0, 0),
				AutomaticSize = if inline then E.AutomaticSize.XY else E.AutomaticSize.Y,
				TextWrapped = not inline,
				TextXAlignment = E.TextXAlignment.Left,
			})
			if inline then
				local hug = function(use: ComposeTypes.Use): boolean
					return read(spec.sizing, use) == "hug"
				end
				local row = ctx.row(
					{ label, buildMenu(menuSpec, true) },
					ctx.props(spec, pickerKeys, {
						Name = spec.Name or "Picker",
						BackgroundTransparency = 1,
						Size = function(use: ComposeTypes.Use)
							return if hug(use) then D2.fromOffset(0, 0) else D2.new(1, 0, 0, 0)
						end,
						AutomaticSize = function(use: ComposeTypes.Use)
							return if hug(use) then E.AutomaticSize.XY else E.AutomaticSize.Y
						end,
					})
				)
				local layout = assert(row:FindFirstChildWhichIsA("UIListLayout"))
				layout.VerticalAlignment = E.VerticalAlignment.Center
				layout.Wraps = true
				row:SetAttribute("FacetValueAlignment", "start")
				return row
			end
			local column = ctx.column(
				{ label, buildMenu(menuSpec, true) },
				ctx.props(spec, pickerKeys, {
					Name = spec.Name or "Picker",
					BackgroundTransparency = 1,
					Size = D2.new(1, 0, 0, 0),
					AutomaticSize = E.AutomaticSize.Y,
				})
			)
			assert(column:FindFirstChildWhichIsA("UIListLayout")).Padding = D.new(0, 4)
			return column
		end
		if style == "navigationLink" then
			local opened: ComposeTypes.Cell<boolean> = spec.isPresented or Compose.cell(false)
			local chosenText = function(use: ComposeTypes.Use): string
				for _, option in read(spec.options, use) do
					if isSelected(option.value, use) then
						local label: string = read(option.label, use)
						return label
					end
				end
				return read(spec.placeholder, use) or "Choose"
			end
			local native: Types.FrameNativeProps = ctx.props(spec, pickerKeys)
			local triggerProps = (native :: unknown) :: Inputs.ButtonProps
			triggerProps.Name = spec.Name or "Picker"
			triggerProps.enabled = spec.enabled
			triggerProps.label = spec.label or chosenText
			triggerProps.trailingIcon = if spec.label ~= nil then "chevron.trailing" else nil
			triggerProps.controlSize = spec.controlSize
			triggerProps.corners = spec.corners
			triggerProps.appearance = if spec.appearance ~= nil
				then function(use: ComposeTypes.Use): string
					local word = appearanceFor("navigationLink", read(spec.appearance, use))
					return if word == "contrast" then "emphasis" elseif word == "utility" then "utility" else "standard"
				end
				else nil
			triggerProps.onActivate = function()
				opened:set(true)
			end
			local trigger = UI.Button(triggerProps)
			local row = trigger:FindFirstChild("Content")
			if spec.label ~= nil and row then
				runtime.mountFragment(function()
					return {
						ctx.styled(
							ctx.text({
								Name = "Trailing",
								LayoutOrder = 90,
								Text = chosenText,
							}),
							"secondary"
						),
					}
				end, row)
			end
			surfaces.attach(trigger, {
				surfaces.overlay(trigger, opened, function()
					local choices: Nav.PickerSpec<V>
					if spec.multiple then
						local source: Nav.MultiplePickerSpec<V> = spec
						local child = table.clone(source)
						child.Name, child.style, child.isPresented = "Choices", "inline", nil
						child.Size = D2.new(1, 0, 0, 0)
						child.appearance, child.corners, child.maxHeight, child.requiredMark = nil, nil, nil, nil
						child.indicator = "none"
						child.onChange = function(value: { [V]: boolean })
							if source.onChange then
								source.onChange(value)
							end
						end
						choices = child
					else
						local source: Nav.SinglePickerSpec<V> = spec
						local child = table.clone(source)
						child.Name, child.style, child.isPresented = "Choices", "inline", nil
						child.Size = D2.new(1, 0, 0, 0)
						child.appearance, child.corners, child.maxHeight, child.requiredMark = nil, nil, nil, nil
						child.indicator = "none"
						child.onChange = function(value: V)
							opened:set(false)
							if source.onChange then
								source.onChange(value)
							end
						end
						choices = child
					end
					local results: GuiObject = UI.Picker(choices)
					if spec.maxHeight then
						local cap = math.max(44, spec.maxHeight)
						local list = results
						local measured = ctx.observe.AbsoluteSize(list)
						results = Host.ScrollingFrame "Results" {
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							Selectable = false,
							ScrollingDirection = E.ScrollingDirection.Y,
							AutomaticCanvasSize = E.AutomaticSize.Y,
							CanvasSize = D2.fromOffset(0, 0),
							Size = function(use: ComposeTypes.Use)
								local height = use(measured).Y
								return D2.new(1, 0, 0, if height > 0 then math.min(height, cap) else cap)
							end,
							list :: Types.Child,
						}
					end
					return surfaces.modal(function()
						return surfaces.centered(
							ctx.column({
								results,
								UI.Button "Close" {
									label = "Close",
									onActivate = function()
										opened:set(false)
									end,
								},
								ctx.padding(16, 16),
								ctx.corner(),
							}, { Name = "PickerSearch" }),
							560
						)
					end, function()
						opened:set(false)
					end)
				end),
			})
			return trigger
		end
		if style == "cards" then
			local across = read(spec.axis) == "x"
			local function clear()
				if read(spec.enabled) == false or spec.multiple then
					return
				end
				local single = (spec :: unknown) :: Nav.SinglePickerSpec<V>
				local previous = single.selected:peek()
				if single.onChanging and single.onChanging((nil :: unknown) :: V, previous) == false then
					return
				end
				local optional = (single.selected :: unknown) :: ComposeTypes.Cell<V?>
				runtime:batch(function()
					optional:set(nil)
					if single.onChange then
						single.onChange((nil :: unknown) :: V)
					end
				end)
			end
			local cards = ctx.column({
				Compose.keyed({
					from = options,
					key = function(option: Nav.PickerOption<V>)
						return option.id or option.value
					end,
					render = function(
						source: ComposeTypes.Readable<Nav.PickerOption<V>>,
						index: ComposeTypes.Readable<number>
					)
						local key = tostring(source:peek().id or source:peek().value)
						local chosen = function(use: ComposeTypes.Use)
							return isSelected(use(source).value, use)
						end
						local card = UI.Button({
							Name = "Card-" .. key,
							LayoutOrder = index,
							Size = if across then D2.fromOffset(200, 0) else D2.new(1, 0, 0, 0),
							AutomaticSize = E.AutomaticSize.Y,
							label = function(use: ComposeTypes.Use)
								return read(use(source).label, use)
							end,
							subtitle = function(use: ComposeTypes.Use)
								return read(use(source).description, use) or ""
							end,
							icon = liveIcon(source),
							controlSize = spec.controlSize,
							appearance = function(use: ComposeTypes.Use): string
								return if chosen(use) then "emphasis" else "standard"
							end,
							enabled = function(use: ComposeTypes.Use)
								return read(spec.enabled, use) ~= false and read(use(source).enabled, use) ~= false
							end,
							onActivate = function()
								local value = source:peek().value
								if isSelected(value) and spec.required == false then
									clear()
								else
									select(value)
								end
							end,
						})
						card:AddTag("facet-card-option")
						local content = card:FindFirstChild("Content")
						if content then
							runtime.mountFragment(function()
								local parts: { Types.Child } = {}
								if source:peek().meta ~= nil then
									table.insert(
										parts,
										ctx.styled(
											ctx.text({
												Name = "Meta",
												LayoutOrder = 50,
												Text = function(use: ComposeTypes.Use)
													return read(use(source).meta, use) or ""
												end,
											}),
											"secondary"
										)
									)
								end
								if source:peek().badge ~= nil then
									table.insert(
										parts,
										ctx.styled(
											Host.Frame "Badge" {
												LayoutOrder = 60,
												Size = D2.fromOffset(0, 0),
												AutomaticSize = E.AutomaticSize.XY,
												ctx.text({
													Name = "Count",
													Text = function(use: ComposeTypes.Use)
														local badge = read(use(source).badge, use)
														return if badge == nil then "" else tostring(badge)
													end,
												}) :: Types.Child,
											},
											"badge"
										)
									)
								end
								return parts
							end, content)
						end
						Compose.watch(function(use: ComposeTypes.Use)
							card:SetAttribute("FacetLabel", read(use(source).label, use))
						end)
						return card
					end,
				}),
			}, { Name = "Cards", Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y })
			local layout = assert(cards:FindFirstChildWhichIsA("UIListLayout"))
			if across then
				layout.FillDirection = E.FillDirection.Horizontal
				layout.Wraps = true
			end
			local outer = ctx.props(spec, pickerKeys, {
				Name = "Picker",
				BackgroundTransparency = 1,
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
			})
			if spec.label == nil then
				return ctx.column({ cards }, outer)
			end
			return ctx.column({
				ctx.text({
					Name = "Label",
					Text = function(use: ComposeTypes.Use)
						return read(spec.label, use) or ""
					end,
					Size = D2.new(1, 0, 0, 0),
					AutomaticSize = E.AutomaticSize.Y,
					TextWrapped = true,
				}),
				cards,
			}, outer)
		end
		assert(table.find({ "segmented", "inline", "radioGroup", "navigationLink" }, style), "Unknown Picker style")
		local vertical = style ~= "segmented" or read(spec.axis) == "y"
		local function across(use: ComposeTypes.Use?): boolean
			return style == "segmented" and read(spec.axis, use) ~= "y"
		end
		local captionHeights: { [Instance]: number } = {}
		local tallestCaption = Compose.cell(0)
		local textService = surfaces.service("GuiService") :: GuiService?
		local preferredText: ComposeTypes.Readable<unknown>? = if style == "segmented"
				and textService
				and textService.GetPropertyChangedSignal
			then ctx.observe.PreferredTextSize(textService)
			else nil
		local function measureCaptions(): ()
			local tallest = 0
			for _, height in captionHeights do
				tallest = math.max(tallest, height)
			end
			if tallest ~= tallestCaption:peek() then
				tallestCaption:set(tallest)
			end
		end
		local function stripHeight(use: ComposeTypes.Use?): number
			local rung = ctx.controlSize(spec.controlSize, "height", use)
			local package = read(ctx.config.theme, use)
			local recipe = if package and package.chrome then package.chrome.control else nil
			local inset = if recipe then recipe.contentInsets else nil
			local caption = if use then use(tallestCaption) else tallestCaption:peek()
			local preferred = if preferredText == nil
				then nil
				elseif use then use(preferredText)
				else preferredText:peek()
			local enlarged = preferred == E.PreferredTextSize.Large
				or preferred == E.PreferredTextSize.Larger
				or preferred == E.PreferredTextSize.Largest
			if not enlarged or caption <= 0 or recipe == nil or recipe.kind == "native" or recipe.kind == "none" then
				return rung
			end
			local chrome = math.max(0, if inset then inset.top or 0 else 0)
				+ math.max(0, if inset then inset.bottom or 0 else 0)
			return math.max(rung, math.ceil(caption) + chrome + 2 * segmentMetrics.inset)
		end
		local fixedOptions = not (Compose.isReadable(spec.options) or type(spec.options) == "function")
		local children: { ComposeTypes.Child } = {
			Host.UIListLayout({
				FillDirection = derive(function(use: ComposeTypes.Use?)
					return if style ~= "segmented" or read(spec.axis, use) == "y"
						then E.FillDirection.Vertical
						else E.FillDirection.Horizontal
				end, spec.axis),
				SortOrder = E.SortOrder.LayoutOrder,
				Padding = D.new(0, 4),
				Wraps = derive(function(use: ComposeTypes.Use?)
					return style == "segmented" and read(spec.axis, use) ~= "y"
				end, spec.axis),
				HorizontalFlex = derive(function(use: ComposeTypes.Use?)
					return if style == "segmented"
							and read(spec.axis, use) ~= "y"
							and read(spec.sizing, use) ~= "hug"
						then E.UIFlexAlignment.Fill
						else E.UIFlexAlignment.None
				end, spec.axis, spec.sizing),
			}),
		}
		if spec.query then
			table.insert(children, UI.TextInput "Search" { value = spec.query, placeholder = "Search" })
		end
		table.insert(
			children,
			Compose.keyed({
				from = options,
				key = function(option: Nav.PickerOption<V>)
					return option.id or option.value
				end,
				render = function(
					source: ComposeTypes.Readable<Nav.PickerOption<V>>,
					index: ComposeTypes.Readable<number>
				)
					local selected = function(use: ComposeTypes.Use)
						return isSelected(use(source).value, use)
					end
					local current = source:peek()
					local fixed = fixedOptions and spec.query == nil
					local sealed = style == "segmented" and current.icon ~= nil
					local function labelOf(use: ComposeTypes.Use?): string
						if read(spec.iconOnly, use) then
							return ""
						end
						local option = if use then use(source) else source:peek()
						local badge = if style == "segmented" and not sealed then read(option.badge, use) else nil
						local label: string = read(option.label, use)
						return label .. (if badge ~= nil and badge ~= "" then " (" .. tostring(badge) .. ")" else "")
					end
					local function enabledOf(use: ComposeTypes.Use?): boolean
						local option = if use then use(source) else source:peek()
						return read(spec.enabled, use) ~= false and read(option.enabled, use) ~= false
					end
					local button = UI.Button({
						Name = tostring(current.id or current.value),
						LayoutOrder = if fixed then index:peek() else index,
						Size = derive(function(use: ComposeTypes.Use?)
							if across(use) then
								return D2.fromScale(0, 1)
							end
							local height = if spec.controlSize ~= nil
								then ctx.controlSize(spec.controlSize, "height", use)
								else 44
							return D2.new(1, 0, 0, height)
						end, spec.axis, spec.controlSize, if spec.controlSize ~= nil
							then ctx.config.theme
							else nil),
						AutomaticSize = if style ~= "segmented"
							then E.AutomaticSize.Y
							else derive(function(use: ComposeTypes.Use?)
								return if across(use) then E.AutomaticSize.X else E.AutomaticSize.XY
							end, spec.axis),
						label = derive(
							labelOf,
							if fixed then nil else source,
							spec.iconOnly,
							current.badge,
							current.label
						),
						subtitle = if source:peek().description ~= nil
								or style == "radioGroup"
								or Compose.isReadable(spec.options)
								or type(spec.options) == "function"
							then function(use: ComposeTypes.Use)
								return read(use(source).description, use) or ""
							end
							else nil,
						icon = liveIcon(source),
						TextSize = spec.textSize,
						trailingIcon = if read(spec.indicator) == "none" and style ~= "segmented"
							then "checkmark"
							else nil,
						selected = function(use: ComposeTypes.Use)
							local indicator = read(spec.indicator, use)
							return selected(use)
								and indicator ~= "underline"
								and (indicator ~= "none" or style == "segmented")
						end,
						enabled = derive(enabledOf, if fixed then nil else source, spec.enabled, current.enabled),
						haptic = function(use: ComposeTypes.Use)
							return spec.multiple == true or not selected(use)
						end,
						onActivate = function()
							select(source:peek().value)
						end,
					})
					local glyph = if sealed then button:FindFirstChild("LeadingIcon", true) else nil
					if glyph and (current.badge ~= nil or not fixed) then
						local corner = UI.badged(
							Host.Frame({ Name = "Anchor", BackgroundTransparency = 1, Size = D2.fromScale(1, 1) }),
							function(use: ComposeTypes.Use): string?
								local badge = read(use(source).badge, use)
								return if badge == nil then nil else tostring(badge)
							end
						)
						runtime.decorate(corner, { Size = D2.fromScale(1, 1), AutomaticSize = E.AutomaticSize.None })
						runtime.mount(function()
							return corner
						end, glyph)
					end
					if read(spec.indicator) == "none" and style ~= "segmented" then
						local check = button:FindFirstChild("TrailingIcon", true)
						if check and check:IsA("GuiObject") then
							Compose.watch(function(use: ComposeTypes.Use)
								check.Visible = selected(use)
							end)
						end
					end
					local badgeContent = button:FindFirstChild("Content")
					if
						style ~= "segmented"
						and badgeContent
						and (
							current.badge ~= nil
							or Compose.isReadable(spec.options)
							or type(spec.options) == "function"
						)
					then
						runtime.mountFragment(function()
							return {
								Compose.show(function(use: ComposeTypes.Use)
									local badge = read(use(source).badge, use)
									return badge ~= nil and badge ~= ""
								end, function()
									local last = tostring(read(source:peek().badge))
									return UI.Badge({
										Name = "Count",
										LayoutOrder = 900,
										label = function(use: ComposeTypes.Use): string
											local badge = read(use(source).badge, use)
											if badge ~= nil and badge ~= "" then
												last = tostring(badge)
											end
											return last
										end,
									})
								end),
							}
						end, badgeContent)
					end
					if style == "radioGroup" then
						local trailing = spec.indicatorPosition == "trailing"
						runtime.mountFragment(function()
							return {
								ctx.styled(
									Host.Frame "Indicator" {
										Size = D2.fromOffset(18, 18),
										LayoutOrder = if trailing then 1000 else 0,
										BackgroundTransparency = 1,
										ctx.corner(9) :: Types.Child,
										ctx.styled(
											Host.Frame "Dot" {
												AnchorPoint = V2.new(0.5, 0.5),
												Position = D2.fromScale(0.5, 0.5),
												Size = D2.fromOffset(8, 8),
												Visible = selected,
												ctx.corner(4) :: Types.Child,
											},
											"fill"
										) :: Types.Child,
									},
									"radio-mark"
								),
							}
						end, (assert(button:FindFirstChild("Content"), "Picker radio rows use a content row")))
					end
					if
						source:peek().indicator ~= nil
						or Compose.isReadable(spec.options)
						or type(spec.options) == "function"
					then
						local statusUI = (UI :: unknown) :: {
							StatusIndicator: Types.Constructor<Media.StatusIndicatorProps, TextLabel>,
						}
						surfaces.attach(button, {
							Compose.show(function(use: ComposeTypes.Use)
								return use(source).indicator ~= nil
							end, function()
								return statusUI.StatusIndicator({
									Name = "Status",
									AnchorPoint = V2.new(1, 0.5),
									Position = D2.new(1, -8, 0.5, 0),
									status = function(use: ComposeTypes.Use): Media.Status
										local mark = use(source).indicator
										if mark == nil then
											return "neutral"
										end
										local status = read(mark.status, use)
										return if status == nil then "neutral" else status
									end,
									form = source:peek().indicator
										and (source:peek().indicator :: Nav.OptionIndicator).form,
									count = function(use: ComposeTypes.Use)
										local mark = use(source).indicator
										return if mark then read(mark.count, use) else nil
									end,
								})
							end),
						})
					end
					local underlined = Compose.isReadable(spec.indicator)
						or type(spec.indicator) == "function"
						or spec.indicator == "underline"
					surfaces.attach(button, {
						Host.UISizeConstraint({
							MinSize = derive(function(use: ComposeTypes.Use?)
								return V2.new(44, if spec.controlSize ~= nil or across(use) then 0 else 44)
							end, spec.axis),
						}),
						if underlined
							then Compose.show(function(use: ComposeTypes.Use)
								return read(spec.indicator, use) == "underline" and selected(use)
							end, function()
								return ctx.styled(
									Host.Frame "SelectionIndicator" {
										BorderSizePixel = 0,
										Size = D2.new(1, 0, 0, 2),
										Position = D2.new(0, 0, 1, -2),
										Selectable = false,
									},
									"selection-indicator"
								)
							end)
							else nil,
					})
					if fixed and not (Compose.isReadable(current.label) or type(current.label) == "function") then
						button:SetAttribute("FacetLabel", current.label)
					else
						Compose.watch(function(use: ComposeTypes.Use)
							button:SetAttribute("FacetLabel", read(use(source).label, use))
						end)
					end
					local family = if style == "segmented" then "facet-segment" else "facet-choice"
					button:AddTag(family)
					if style == "segmented" then
						local bounds = ctx.observe.TextBounds(button)
						local extent = ctx.observe.AbsoluteSize(button)
						Compose.watch(function(use: ComposeTypes.Use)
							use(bounds)
							use(extent)
							captionHeights[button] = button.TextBounds.Y
							measureCaptions()
						end)
						Compose.cleanup(function()
							captionHeights[button] = nil
							measureCaptions()
						end)
					end
					local content = button:FindFirstChild("Content")
					local layout = if content then content:FindFirstChildWhichIsA("UIListLayout") else nil
					if style ~= "segmented" and layout then
						layout.HorizontalAlignment = E.HorizontalAlignment.Left
					end
					Compose.watch(function(use: ComposeTypes.Use)
						local indicator = read(spec.indicator, use)
						local current = selected(use)
							and indicator ~= "underline"
							and (indicator ~= "none" or style == "segmented")
						if current then
							button:AddTag(family .. "-current")
						elseif button:HasTag(family .. "-current") then
							button:RemoveTag(family .. "-current")
						end
					end)
					local section = source:peek().sectionTitle
					if section ~= nil and style ~= "segmented" then
						runtime.decorate(button, { LayoutOrder = 2 })
						return ctx.column({
							ctx.styled(
								ctx.text({
									Name = "SectionTitle",
									Text = function(use: ComposeTypes.Use)
										return read(section, use) or ""
									end,
								}),
								"type-caption"
							),
							button,
						}, {
							Name = "Section-" .. button.Name,
							LayoutOrder = index,
							Size = D2.new(1, 0, 0, 0),
							AutomaticSize = E.AutomaticSize.Y,
						})
					end
					return button
				end,
			})
		)
		local labelled = spec.label ~= nil and not vertical
		local strip = style == "segmented" and spec.label == nil and (spec.Size ~= nil or spec.AutomaticSize ~= nil)
		local declaredSize, declaredAutomatic = spec.Size, spec.AutomaticSize
		local function tall(use: ComposeTypes.Use): boolean
			local sizing = read(declaredAutomatic, use)
			return across(use) and (sizing == E.AutomaticSize.Y or sizing == E.AutomaticSize.XY)
		end
		local source = spec
		if strip then
			source = table.clone(spec)
			local fields = (source :: unknown) :: { [string]: unknown }
			fields.Size, fields.AutomaticSize = nil, nil
		end
		local defaults: Types.FrameNativeProps = {
			Name = "Picker",
			BackgroundTransparency = if style == "segmented" then nil else 1,
			Size = if strip
				then function(use: ComposeTypes.Use): UDim2
					local rung = ctx.controlSize(spec.controlSize, "height", use)
					local size: UDim2 = read(declaredSize, use) or D2.new(1, 0, 0, rung)
					if tall(use) then
						return D2.new(size.X.Scale, size.X.Offset, 0, rung)
					end
					return size
				end
				elseif style == "segmented" then function(use: ComposeTypes.Use): UDim2
					if not across(use) then
						return D2.new(1, 0, 0, 0)
					end
					return D2.new(if labelled then 0 else 1, 0, 0, stripHeight(use))
				end
				else D2.new(1, 0, 0, 0),
			AutomaticSize = if strip
				then function(use: ComposeTypes.Use): Enum.AutomaticSize
					local sizing: Enum.AutomaticSize = read(declaredAutomatic, use) or E.AutomaticSize.None
					if tall(use) then
						return if sizing == E.AutomaticSize.XY then E.AutomaticSize.X else E.AutomaticSize.None
					end
					return sizing
				end
				elseif style == "segmented" then derive(function(use: ComposeTypes.Use?)
					return if not across(use)
						then E.AutomaticSize.Y
						elseif labelled then E.AutomaticSize.X
						else E.AutomaticSize.None
				end, spec.axis)
				else E.AutomaticSize.Y,
		}
		local p = if spec.label == nil then ctx.props(source, pickerKeys, defaults) else defaults
		for _, child in children do
			table.insert(p, child)
		end
		local picker = Host.Frame(p)
		if style == "segmented" then
			picker:AddTag("facet-segmented")
			surfaces.attach(picker, {
				Host.UISizeConstraint "TargetFloor" {
					MinSize = derive(function(use: ComposeTypes.Use?)
						return V2.new(0, if read(spec.axis, use) == "y" then 0 else 44 + 2 * segmentMetrics.inset)
					end, spec.axis),
				},
			})
			if spec.corners then
				surfaces.attach(picker, {
					Host.UICorner "Corners" { CornerRadius = D.new(if spec.corners == "pill" then 1 else 0, 0) },
				})
				picker:AddTag(if spec.corners == "pill" then "facet-segmented-pill" else "facet-segmented-square")
			end
			if spec.appearance ~= nil then
				Compose.watch(function(use: ComposeTypes.Use)
					local word = appearanceFor("segmented", read(spec.appearance, use))
					local stroke, utility = word == "stroke", word == "utility"
					if stroke then
						picker:AddTag("facet-segmented-stroke")
					elseif picker:HasTag("facet-segmented-stroke") then
						picker:RemoveTag("facet-segmented-stroke")
					end
					if utility then
						picker:AddTag("facet-segmented-utility")
					elseif picker:HasTag("facet-segmented-utility") then
						picker:RemoveTag("facet-segmented-utility")
					end
				end)
			end
		end
		if spec.label == nil then
			return picker
		end
		picker.Name = "Options"
		local label = ctx.text({
			Name = "Label",
			Text = derive(function(use: ComposeTypes.Use?)
				return read(spec.label, use) or ""
			end, spec.label),
			Size = D2.new(if vertical then 1 else 0, 0, 0, 0),
			AutomaticSize = if vertical then E.AutomaticSize.Y else E.AutomaticSize.XY,
			TextWrapped = vertical,
			TextXAlignment = E.TextXAlignment.Left,
		})
		local outer = ctx.props(spec, pickerKeys, {
			Name = "Picker",
			BackgroundTransparency = 1,
			Size = D2.new(1, 0, 0, 0),
			AutomaticSize = E.AutomaticSize.Y,
		})
		if vertical then
			return ctx.column({ label, picker }, outer)
		end
		runtime.mount(function()
			return Host.UIFlexItem({ FlexMode = E.UIFlexMode.Grow })
		end, label)
		local row = ctx.row({ label, picker }, outer)
		local layout = assert(row:FindFirstChildWhichIsA("UIListLayout"))
		layout.VerticalAlignment = E.VerticalAlignment.Center
		layout.Padding = D.new(0, 16)
		layout.Wraps = true
		local rowSize = ctx.observe.AbsoluteSize(row)
		surfaces.attach(picker, {
			Host.UISizeConstraint({
				MaxSize = function(use: ComposeTypes.Use)
					local width = (use(rowSize) :: Vector2).X
					return V2.new(if width > 0 then width else math.huge, math.huge)
				end,
			}),
		})
		return row
	end)

	UI.SplitButton = ctx.construct("SplitButton", function<V>(spec: Nav.SplitButtonSpec<V>): Frame
		local input = surfaces.service("UserInputService")
		local preferred = if input
			then ctx.observe.PreferredInput(input) :: ComposeTypes.Readable<Enum.PreferredInput?>
			else Compose.cell(nil :: Enum.PreferredInput?)
		local touch = Compose.formula(function(use: ComposeTypes.Use)
			return use(preferred) == E.PreferredInput.Touch
		end)
		local opened = Compose.cell(false)
		local enabled = function(use: ComposeTypes.Use)
			return read(spec.enabled, use) ~= false and read(spec.busy, use) ~= true
		end
		local function primary()
			return UI.Button "Primary" {
				label = spec.label,
				onActivate = spec.onActivate,
				enabled = spec.enabled,
				busy = spec.busy,
				shortcut = spec.shortcut,
			}
		end
		return Host.Frame(
			ctx.props(spec, { "label", "onActivate", "items", "enabled", "busy", "shortcut", "menuLabel" }, {
				Name = "SplitButton",
				BackgroundTransparency = 1,
				Size = D2.fromOffset(0, 0),
				AutomaticSize = E.AutomaticSize.XY,
				Compose.show(touch, function()
					local suppressEcho = false
					local trigger = UI.Button "Primary" {
						Size = if spec.Size then D2.fromScale(1, 1) else nil,
						AutomaticSize = if spec.Size then E.AutomaticSize.None else nil,
						label = spec.label,
						enabled = spec.enabled,
						busy = spec.busy,
						onActivate = function()
							if suppressEcho then
								suppressEcho = false
								return
							end
							if spec.onActivate then
								spec.onActivate()
							end
						end,
					}
					return buildMenu({
						Name = "TouchAlternatives",
						Size = if spec.Size then D2.fromScale(1, 1) else nil,
						AutomaticSize = if spec.Size then E.AutomaticSize.None else nil,
						trigger = function(): GuiObject
							return trigger
						end,
						items = spec.items,
						enabled = enabled,
						isPresented = opened,
						triggers = { "longPress", "secondary", "keyboard", "gamepad" } :: { Nav.MenuTrigger },
						onOpen = function()
							suppressEcho = true
						end,
						onClose = function()
							suppressEcho = false
						end,
					}, true)
				end, function()
					return ctx.row({
						primary(),
						UI.Menu "Alternatives" {
							label = spec.menuLabel or "More options",
							items = spec.items,
							enabled = enabled,
							isPresented = opened,
						},
					})
				end),
			})
		)
	end)

	UI.ComboBox = ctx.construct("ComboBox", function(spec: Nav.ComboBoxSpec): Frame
		writable(spec.value, "ComboBox.value")
		writable(spec.text, "ComboBox.text")
		assert(type(spec.value:peek()) == "string", "ComboBox.value must be a string")
		assert(type(read(spec.options)) == "table", "ComboBox requires options")
		assert(type(spec.acceptCustom) == "function", "ComboBox requires acceptCustom")
		local errorText = Compose.cell("")
		local alive = true
		Compose.cleanup(function()
			alive = false
		end)
		local opened, editing = Compose.cell(false), Compose.cell(false)
		local navigating = false
		local popup: Frame?
		local gui = surfaces.service("GuiService")
		local function close()
			opened:set(false)
		end
		local function label(value: string): string
			for _, option in read(spec.options) do
				if (option.value or option.id) == value then
					return read(option.label)
				end
			end
			return value
		end
		local function update(value: string)
			close()
			errorText:set("")
			spec.text:set(label(value))
			if value ~= spec.value:peek() then
				spec.value:set(value)
				if spec.onChange then
					spec.onChange(value)
				end
			end
		end
		local function commit(text: string, reason: Inputs.CommitReason)
			if
				navigating
				or read(spec.enabled) == false
				or (reason == "focusLost" and spec.commitOnFocusLost ~= true)
			then
				return
			end
			for _, option in read(spec.options) do
				if read(option.label) == text then
					if read(option.enabled) == false then
						errorText:set("This option is unavailable.")
					else
						update(option.value or option.id)
					end
					return
				end
			end
			local ok, accepted, message = pcall(spec.acceptCustom, text)
			if not alive or read(spec.enabled) == false then
				return
			end
			if ok and accepted == true then
				update(text)
			else
				errorText:set(message or "This value is not accepted.")
			end
		end
		local function cancel()
			close()
			spec.text:set(label(spec.value:peek()))
			errorText:set("")
		end
		local created = UI.TextInput "Editor" {
			value = spec.text,
			placeholder = spec.placeholder,
			enabled = spec.enabled,
			Size = D2.new(1, -60, 1, 0),
			AutomaticSize = E.AutomaticSize.None,
			onCommit = function(value, reason)
				commit(value, reason)
				if reason == "submit" then
					close()
				end
			end,
			onCancel = cancel,
			onChange = function(value)
				spec.text:set(value)
				opened:set(true)
			end,
			Focused = function()
				editing:set(true)
			end,
			FocusLost = function()
				editing:set(false)
			end,
		}
		assert(created:IsA("TextBox"), "Facet ComboBox: the editor is a TextBox")
		local editor = created

		local function open()
			if read(spec.enabled) ~= false then
				opened:set(true)
			end
		end
		local triggerAttributes: Types.Attributes = { FacetLabel = "Suggestions" }
		local suggestions = Host.Frame "Suggestions" {
			BackgroundTransparency = 1,
			Position = D2.new(1, -56, 0, 0),
			Size = D2.new(0, 56, 1, 0),
			UI.Button "Trigger" {
				label = "",
				icon = "chevron.down",
				enabled = spec.enabled,
				Size = D2.fromScale(1, 1),
				AutomaticSize = E.AutomaticSize.None,
				Attributes = triggerAttributes,
				onActivate = function()
					if opened:peek() then
						close()
					else
						open()
					end
				end,
			},
		}
		local row = Host.Frame "Row" {
			BackgroundTransparency = 1,
			Size = D2.new(1, 0, 0, 44),
			editor :: Instance,
			suggestions,
		}
		local root = ctx.column(
			{
				row,
				Compose.show(function(use: ComposeTypes.Use)
					return use(errorText) ~= ""
				end, function()
					return ctx.text({ Name = "Validation", Text = errorText, TextWrapped = true, LayoutOrder = 2 })
				end),
			},
			ctx.props(spec, {
				"value",
				"text",
				"options",
				"enabled",
				"acceptCustom",
				"onChange",
				"commitOnFocusLost",
				"placeholder",
			}, {
				Name = "ComboBox",
				Size = D2.new(1, 0, 0, 44),
				AutomaticSize = E.AutomaticSize.Y,
			})
		)
		local available = surfaces.available(root)
		Compose.watch(function(use: ComposeTypes.Use)
			if not use(available) or read(spec.enabled, use) == false then
				close()
			end
		end)
		local choices = function(use: ComposeTypes.Use): { Nav.MenuItem<string> }
			local result: { Nav.MenuItem<string> } = {}
			local query = string.lower(use(spec.text))
			for _, option in read(spec.options, use) do
				if string.find(string.lower(read(option.label, use)), query, 1, true) then
					table.insert(result, {
						id = option.id or tostring(option.value),
						label = option.label,
						enabled = option.enabled,
						onSelect = function()
							update(option.value or option.id)
						end,
					})
				end
			end
			return result
		end
		surfaces.attach(root, {
			surfaces.overlay(row, opened, function()
				local panel = menuPanel({ items = choices, presentation = "menu" :: "menu" }, close, row, true)
				popup = panel
				Compose.cleanup(function()
					if gui and surfaces.within(gui.SelectedObject, panel) then
						gui.SelectedObject = if ctx.available(root) then editor else nil
					end
					popup = nil
				end)
				local input = surfaces.service("UserInputService")
				if input then
					runtime.connect(input, "InputBegan", function(event: InputObject)
						if
							event.UserInputType ~= E.UserInputType.MouseButton1
							and event.UserInputType ~= E.UserInputType.Touch
						then
							return
						end
						local function hit(node: GuiObject): boolean
							local at, size, point = node.AbsolutePosition, node.AbsoluteSize, event.Position
							return point.X >= at.X
								and point.Y >= at.Y
								and point.X <= at.X + size.X
								and point.Y <= at.Y + size.Y
						end
						local menu = panel:FindFirstChild("MenuPanel")
						if not hit(row) and menu and menu:IsA("GuiObject") and not hit(menu) then
							close()
						end
					end)
				end
				return panel
			end),
			Compose.show(function(use: ComposeTypes.Use)
				return use(editing) or use(opened)
			end, function()
				ctx.action(root, "ComboSuggestions", { E.KeyCode.Down, E.KeyCode.DPadDown }, editing, function()
					open()
					local panel = popup
					local target: GuiObject?
					if panel then
						for _, item in Compose.sample(choices) do
							if item.divider ~= true and read(item.enabled) ~= false then
								target = surfaces.firstSelectable(panel, item.id)
								if target then
									break
								end
							end
						end
					end
					if target and gui then
						navigating = true
						editor:ReleaseFocus(false)
						navigating = false
						gui.SelectedObject = target
					end
				end, { priority = 11000 })
				ctx.action(root, "ComboCancel", { E.KeyCode.Escape, E.KeyCode.ButtonB }, opened, function()
					cancel()
					if ctx.available(root) then
						editor:CaptureFocus()
					end
				end, { priority = 11000 })
				return Host.Folder({})
			end),
		})
		return root
	end)
end
