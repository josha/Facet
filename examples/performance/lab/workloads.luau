--!strict
local motion = require("./motion_workloads")
local workloads = {}
workloads.VERSION = "native-perf-workloads/2"
workloads.ORDER = {
	"hud-binding-storm",
	"settings-churn",
	"scroll-focus-traversal",
	"collection-mutation",
	"animation-interruption",
	"locale-textsize-change",
	"async-image-burst",
	"shadow-storm",
	"virtual-list-scroll",
	"native-scroll-drag",
	"dense-hud",
	"stylesheet-state-churn",
	"async-image-grid",
	"screen-lifecycle-churn",
	"theme-swap-flat",
	"theme-swap-metrics",
	"dense-motion",
	"control-motion",
	"theme-swap-assets",
	"lab-dense-scroll",
	"lab-collection-churn",
	"adaptive-navigation-images",
	"navigation-customization",
	"alert-present-dismiss",
	"picker-menu-open-close",
	"picker-segmented-textsize",
	"radial-menu-open-close",
}
workloads.DATASETS = {
	["hud-binding-storm"] = "HUD Text and Button; 50 unbatched speed writes per iteration",
	["settings-churn"] = "Base HUD plus six-row settings mount and unmount per iteration",
	["scroll-focus-traversal"] = "16 native selectable Buttons; 16 native selection changes per iteration",
	["collection-mutation"] = "Table with 8 keyed rows and 2 columns; replace one row and toggle selection",
	["animation-interruption"] = "One percentage Text; six explicit .35 interpolation writes and runtime frames",
	["locale-textsize-change"] = "8 stable Menu item labels; locale en-us/de-de and preferred text scale1/1.3",
	["async-image-burst"] = "12 plain ImageLabels; replace12keys and complete4modeled loads, count stale/dropped",
	["shadow-storm"] = "100 unchanged rounded shadowed controls; native runtime settle, Engine paint unmeasured",
	["virtual-list-scroll"] = "2000 rows with Image, 2 TextLabels and Toggle; scroll 61 px per iteration",
	["native-scroll-drag"] = "30 UIDragDetector rows; scroll and six-step drag per iteration",
	["dense-hud"] = "8 readouts, ProgressView, 12 keyed markers and 4 Buttons; 24 writes and activation",
	["stylesheet-state-churn"] = "40 Toggles; one-hot rotation changes two controls, then40 native tag reads",
	["async-image-grid"] = "12 AsyncImages; release and rebuild owner with fresh asset keys",
	["screen-lifecycle-churn"] = "Slider, Stepper, Picker, ProgressView, Label and 12 Toggles mounted then removed",
	["theme-swap-flat"] = "Four control fixture; switch equal-metric palette StyleSheets",
	["theme-swap-metrics"] = "Four control fixture; switch 24px and 44px metric StyleSheets",
	["dense-motion"] = "24 springs, four-beat timeline and a 600-row windowed collection reordered",
	["control-motion"] = "30 rows with staggered presence motion, disclosure, invalid input and button motion",
	["theme-swap-assets"] = "Four control fixture; switch flat and image-decorated theme StyleSheets",
	["lab-dense-scroll"] = "Shared seed1 dataset: 2000 async image/two-text/toggle/stepper/open rows with durable models; scroll61px",
	["lab-collection-churn"] = "Shared seed1 dataset: 800 durable async image/two-text/toggle/stepper/open rows; insert/remove/reorder each iteration",
	["adaptive-navigation-images"] = "24 framed image/subtitle Buttons in retained Garage page; native focus and placement round trip",
	["navigation-customization"] = "24 framed image buttons in a 3-destination TabView; reorder tab declarations",
	["alert-present-dismiss"] = "Three-action Alert over a base button; present and dismiss",
	["picker-menu-open-close"] = "Six-option menu Picker; open and close",
	["picker-segmented-textsize"] = "Easy/Normal/Hard Picker, title18 and note14; preferred text scale1/1.3",
	["radial-menu-open-close"] = "Six-action radial menu; open and close",
}

function workloads.create(ctx, name, dataset)
	assert(workloads.DATASETS[name], `unknown performance workload {name}`)
	if name == "dense-motion" or name == "control-motion" then
		return motion.create(ctx, name, dataset)
	end
	local Compose, runtime, Host, UI, types = ctx.Facet.Compose, ctx.runtime, ctx.Host, ctx.UI, ctx.types
	local D2, V2, E, C3 = types.UDim2, types.Vector2, types.Enum, types.Color3
	local state = {
		n = 0,
		name = name,
		observed = {},
		nodes = {},
		controls = {},
		status = Compose.cell({
			mode = "windowed",
			direction = "vertical",
			total = 0,
			retained = 0,
			first = 0,
			last = 0,
			firstRow = 0,
			lastRow = 0,
			rowCount = 0,
			extent = 0,
			following = false,
			measured = 0,
		}),
	}
	Compose.cleanup(function()
		if state.close then
			state.close()
			state.close = nil
		end
	end)
	ctx.rowModels = ctx.rowModels or { values = {}, toggles = {} }
	state.rowModels = ctx.rowModels
	local opened, detailShown = Compose.cell(nil), Compose.cell(false)
	ctx.onRowActivate = function(item)
		opened:set(item)
		detailShown:set(true)
	end
	function state.disclosure()
		return UI.Alert({
			Name = "RowDetail",
			isPresented = detailShown,
			title = Compose.formula(function(use)
				local item = use(opened)
				return if item then item.name else "Item"
			end),
			message = Compose.formula(function(use)
				local item = use(opened)
				return if item then item.detail else ""
			end),
			actions = { { id = "close", label = "Close" } },
		})
	end
	local function readText(value, index)
		return Host.TextLabel({
			Name = `Readout{index or 1}`,
			TextSize = if name == "hud-binding-storm" then 18 else 14,
			Text = value,
			Size = D2.new(1, 0, 0, 24),
			BackgroundTransparency = 1,
		})
	end
	local function stack(children)
		local props = {
			Size = D2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder }),
		}
		for index, node in children do
			if type(node) ~= "function" and node:IsA("GuiObject") then
				runtime.decorate(node, { LayoutOrder = index })
			end
			table.insert(props, node)
		end
		return Host.Frame(props)
	end
	local function bindCell(value)
		local cell = Compose.cell(value)
		table.insert(state.observed, cell)
		return cell
	end
	local function viewport(node)
		if ctx.engine then
			node.AbsoluteSize = V2.new(ctx.viewport.w, ctx.viewport.h)
			if node.ClassName == "ScrollingFrame" then
				node.AbsoluteWindowSize = V2.new(ctx.viewport.w, math.max(120, ctx.viewport.h - 80))
			end
		end
		return node
	end
	local function row(current)
		return ctx.rowBuilder(ctx, current, { full = string.sub(name, 1, 4) == "lab-" })
	end

	local function list(count)
		local full = string.sub(name, 1, 4) == "lab-"
		local data = dataset.build({ count = ctx.rowCount or count, seed = 1 })
		if not full then
			for index, item in data do
				item.id = `racer{index}`
				item.name = `Racer {index}`
				item.detail = `Lap {index % 5 + 1} · P{index % 24 + 1}`
				item.imageKey = "rbxassetid://0"
				item.enabled = false
			end
		end
		state.rows = Compose.cell(data)
		state.list = UI.VirtualList({
			from = state.rows,
			key = function(item)
				return item.id
			end,
			render = row,
			itemSize = if full then ctx.rowSize or 56 else 56,
			measure = full,
			gap = if full then 4 else 0,
			overscan = 2,
			status = state.status,
			controls = state.controls,
			Size = D2.fromScale(1, 1),
			if full then state.disclosure() else nil,
		})
		viewport(state.list)
		return state.list
	end
	local function images()
		local children = { Host.UIGridLayout({ CellSize = D2.fromOffset(64, 64) }) }
		state.images = {}
		state.requests = {}
		state.async = state.async or { completed = 0, stale = 0, dropped = 0 }
		for index = 1, 12 do
			local source = Compose.cell(
				if name == "async-image-grid" then `rbxthumb://gen={state.n}&id={index}` else "rbxassetid://0"
			)
			state.images[index] = source
			table.insert(
				children,
				UI.AsyncImage({
					source = source,
					loader = if ctx.engine
						then function(content, resolve)
							local request = { resolve = resolve, content = content, cancelled = false }
							table.insert(state.requests, request)
							return function()
								request.cancelled = true
								if not request.completed then
									state.async.dropped += 1
								end
								local at = table.find(state.requests, request)
								if at then
									table.remove(state.requests, at)
								end
							end
						end
						else nil,
					Size = D2.fromOffset(64, 64),
				})
			)
		end
		return Host.Frame(children)
	end
	local function transient(kind)
		state.presented, state.selected = Compose.cell(false), Compose.cell("1")
		local options = {}
		for index = 1, 6 do
			options[index] = {
				id = tostring(index),
				value = tostring(index),
				label = `Action {index}`,
				onActivate = function()
					state.presented:set(false)
				end,
				onSelect = function()
					state.presented:set(false)
				end,
			}
		end
		if kind == "alert" then
			return UI.Alert({
				title = "Delete this save?",
				message = "The save slot is cleared and the run restarts from the last checkpoint.",
				isPresented = state.presented,
				actions = {
					{ id = "Delete", label = "Delete", role = "destructive" },
					{ id = "Keep", label = "Keep a copy" },
					{ id = "Cancel", label = "Cancel", role = "cancel" },
				},
			})
		elseif kind == "radial" then
			return UI.RadialMenu({ items = options, isPresented = state.presented, preset = "compass" })
		end
		return UI.Picker({
			options = options,
			selected = state.selected,
			isPresented = state.presented,
			onChange = function(value)
				state.selected:set(value)
			end,
			style = "menu",
		})
	end
	local function lifecycle()
		local volume, quality, selected = Compose.cell(50), Compose.cell(2), Compose.cell("medium")
		local children = {
			UI.Label({ text = "Settings" }),
			UI.Slider({
				label = "Volume",
				value = volume,
				min = 0,
				max = 100,
				onChange = function(next)
					volume:set(next)
				end,
			}),
			UI.Stepper({
				label = "Quality",
				value = quality,
				min = 0,
				max = 4,
				onChange = function(next)
					quality:set(next)
				end,
			}),
			UI.Picker({
				label = "Detail",
				selected = selected,
				options = {
					{ value = "low", label = "Low" },
					{ value = "medium", label = "Medium" },
					{ value = "high", label = "High" },
				},
				onChange = function(next)
					selected:set(next)
				end,
			}),
			UI.ProgressView({ value = 0.4 }),
		}
		local toggles = {}
		for index = 1, 12 do
			local checked = Compose.cell(index % 2 == 0)
			table.insert(
				toggles,
				UI.Toggle({
					label = `Flag {index}`,
					value = checked,
					onChange = function(next)
						checked:set(next)
					end,
				})
			)
		end
		local flags = stack(toggles)
		runtime.decorate(flags, { Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y })
		table.insert(children, flags)
		return stack(children)
	end
	function state.build()
		if name == "virtual-list-scroll" or name == "lab-dense-scroll" then
			return list(2000)
		elseif name == "lab-collection-churn" then
			return list(800)
		elseif name == "hud-binding-storm" then
			state.speed = bindCell(0)
			return stack({
				readText(function(use)
					return `{use(state.speed)} sps`
				end),
				UI.Button({
					label = "Boost",
				}),
			})
		elseif name == "settings-churn" or name == "screen-lifecycle-churn" or name == "async-image-grid" then
			state.anchor =
				Host.Frame({ Size = D2.fromScale(1, 1), if name ~= "async-image-grid" then readText("HUD") else nil })
			return state.anchor
		elseif name == "collection-mutation" then
			local items = {}
			for index = 1, ctx.rowCount or 8 do
				items[index] = { id = `r{index}`, name = `Racer {index}` }
			end
			state.rows, state.selected = Compose.cell(items), Compose.cell({})
			local function cell(current)
				return Host.TextLabel({
					Text = function(use)
						return use(current).name
					end,
					TextSize = 14,
					BackgroundTransparency = 1,
					Size = D2.fromScale(1, 1),
				})
			end
			local node = UI.Table({
				from = state.rows,
				key = function(item)
					return item.id
				end,
				columns = { { id = "name", minWidth = 80, render = cell }, { id = "n", width = 48, render = cell } },
				itemSize = 40,
				header = false,
				selection = state.selected,
				selectionMode = "multi",
				status = state.status,
			})
			for _, child in node:GetChildren() do
				if child.Name == "Body" then
					viewport(child)
				end
			end
			return node
		elseif name == "async-image-burst" then
			state.images, state.inflight = {}, {}
			state.async = { completed = 0, stale = 0, dropped = 0 }
			local children = {}
			for index = 1, 12 do
				local image = Compose.cell("rbxassetid://0")
				state.images[index] = image
				table.insert(
					children,
					Host.ImageLabel({ Name = `Img{index}`, Image = image, Size = D2.fromOffset(64, 64) })
				)
			end
			return stack(children)
		elseif name == "animation-interruption" then
			state.value, state.current = bindCell(0), 0
			return Host.TextLabel({
				Name = "Meter",
				Text = function(use)
					return string.format("%.1f%%", use(state.value) * 100)
				end,
				TextSize = 20,
				BackgroundTransparency = 1,
				Size = D2.fromScale(1, 1),
			})
		elseif name == "locale-textsize-change" or name == "picker-segmented-textsize" then
			state.expanded, state.textSize = bindCell(false), bindCell(1)
			state.locale = Compose.cell("en-us")
			local children = {}
			local function label(text, size)
				return Host.TextLabel({
					Text = text,
					TextSize = function(use)
						return size * use(state.textSize)
					end,
					Size = D2.new(1, 0, 0, 30),
				})
			end
			if name == "locale-textsize-change" then
				for index = 1, 8 do
					table.insert(children, label(`Menu item {index}`, 16))
				end
			else
				state.selected = Compose.cell("normal")
				table.insert(children, label("Race setup", 18))
				table.insert(
					children,
					UI.Picker({
						label = "Difficulty",
						style = "segmented",
						selected = state.selected,
						textSize = function(use)
							return 16 * use(state.textSize)
						end,
						options = {
							{ value = "easy", label = "Easy" },
							{ value = "normal", label = "Normal" },
							{ value = "hard", label = "Hard" },
						},
					})
				)
				table.insert(children, label("Affects rival speed and damage.", 14))
			end
			return stack(children)
		elseif
			name == "alert-present-dismiss"
			or name == "picker-menu-open-close"
			or name == "radial-menu-open-close"
		then
			return stack({
				UI.Button({
					label = "Open",
					onActivate = function()
						state.presented:set(true)
					end,
				}),
				transient(
					if name == "alert-present-dismiss"
						then "alert"
						elseif name == "radial-menu-open-close" then "radial"
						else "picker"
				),
			})
		elseif name == "scroll-focus-traversal" or name == "native-scroll-drag" then
			local children = { CanvasSize = D2.fromOffset(0, 1500), Size = D2.fromScale(1, 1), Host.UIListLayout({}) }
			for index = 1, if name == "scroll-focus-traversal" then 16 else 30 do
				local node = UI.Button({
					Name = `Row{index}`,
					label = `Row {index}`,
					Size = if name == "native-scroll-drag" then D2.new(1, 0, 0, 48) else nil,
				})
				table.insert(state.nodes, node)
				if name == "native-scroll-drag" then
					local drag = Host.UIDragDetector({
						DragStart = function(position)
							state.dragActive = true
							state.lastDrag = position
						end,
						DragContinue = function(position)
							assert(state.dragActive, "drag move has no native session")
							state.lastDrag = position
							state.dragMoves = (state.dragMoves or 0) + 1
						end,
						DragEnd = function(position)
							assert(state.dragActive, "drag end has no native session")
							state.dragActive = false
							if position.X >= 0 and position.X <= 400 and position.Y >= 0 and position.Y <= 200 then
								state.dropTarget = if position.X < 200 then "SlotA" else "SlotB"
								state.drops = (state.drops or 0) + 1
							end
						end,
					})
					runtime.mount(function()
						return drag
					end, node)
					table.insert(state.controls, drag)
				end
				table.insert(children, node)
			end
			state.list = viewport(Host.ScrollingFrame(children))
			return state.list
		elseif name == "adaptive-navigation-images" or name == "navigation-customization" then
			state.selected = Compose.cell("garage")
			state.placement = Compose.cell("topBar")
			state.contentBuilds = 0
			state.tabs = {
				{
					id = "garage",
					label = "Garage",
					content = function()
						state.contentBuilds += 1
						local children = {
							Name = "Cars",
							Size = D2.fromScale(1, 1),
							AutomaticCanvasSize = E.AutomaticSize.Y,
							Host.UIGridLayout({ CellSize = D2.fromOffset(180, 180) }),
						}
						for index = 1, 24 do
							local card = UI.Button({
								Name = `Car{index}`,
								label = `Race car {index}`,
								subtitle = "Ready to race",
								image = dataset.IMAGE_KEYS[(index - 1) % #dataset.IMAGE_KEYS + 1],
								imageFraming = { width = 256, height = 256, focusY = 0.25 },
								onActivate = function() end,
							})
							table.insert(state.nodes, card)
							table.insert(children, card)
						end
						return Host.ScrollingFrame(children)
					end,
				},
				{
					id = "race",
					label = "Race",
					content = function()
						return readText("Race")
					end,
				},
				{
					id = "settings",
					label = "Settings",
					content = function()
						return readText("Settings")
					end,
				},
			}
			state.customization = Compose.cell({ order = { "garage", "race", "settings" } })
			state.afterRun = function()
				if ctx.frame then
					for _ = 1, 60 do
						ctx.frame()
					end
				end
			end
			return UI.TabView({
				tabs = state.tabs,
				selection = state.selected,
				customization = state.customization,
				placement = state.placement,
				style = "sidebarAdaptable",
			})
		elseif string.sub(name, 1, 11) == "theme-swap-" then
			state.packages = assert(ctx.themePackages, "theme workload requires original package fixtures")
			state.palette = Compose.cell(state.packages[1])
			state.themeName = Compose.cell(if ctx.themeNames then ctx.themeNames[1] else nil)
			local themed = ctx.Facet.controls(runtime, { types = types, theme = state.palette })
			local sheet =
				ctx.Facet.themes.createStyleSheet(runtime, state.palette, { types = types, theme = state.themeName })
			state.themeControls = {
				themed.Label({ Name = "Head", text = "Garage", TextSize = 20 }),
				themed.Button({ Name = "Go", label = "Go", onActivate = function() end }),
				themed.Toggle({ Name = "Flag", label = "Flag", value = Compose.cell(true) }),
				themed.ProgressView({ Name = "Bar", value = 0.6 }),
			}
			state.themeSheet = sheet
			return stack({
				sheet,
				Host.StyleLink({ StyleSheet = Compose.static(sheet) }),
				state.themeControls[1],
				Host.Frame({
					Size = D2.new(1, 0, 0, 0),
					AutomaticSize = E.AutomaticSize.Y,
					BackgroundTransparency = 1,
					Host.UIListLayout({ FillDirection = E.FillDirection.Horizontal, Padding = types.UDim.new(0, 8) }),
					state.themeControls[2],
					state.themeControls[3],
				}),
				state.themeControls[4],
			})
		else
			local children = {}
			local count = if name == "shadow-storm" then 100 elseif name == "stylesheet-state-churn" then 40 else 8
			for index = 1, count do
				local value = bindCell(if name == "stylesheet-state-churn" then index == 1 else 0)
				if name == "shadow-storm" then
					table.insert(
						children,
						Host.Frame({
							BackgroundTransparency = value,
							Size = D2.fromOffset(30, 30),
							Host.UICorner({}),
							Host.UIStroke({ Thickness = 2 }),
							Host.UIShadow({ Transparency = value, BlurRadius = types.UDim.new(0, 8) }),
						})
					)
				elseif name == "stylesheet-state-churn" then
					local control = UI.Toggle({ label = `Option {index}`, value = value })
					table.insert(state.nodes, control)
					table.insert(children, control)
				else
					table.insert(
						children,
						readText(function(use)
							return tostring(use(value))
						end, index)
					)
				end
			end
			if name == "dense-hud" then
				state.progress = Compose.cell(0)
				state.boosts = Compose.cell(0)
				state.activate = function()
					state.boosts:set(state.boosts:peek() + 1)
				end
				state.boostText = readText(function(use)
					return `Boost x{use(state.boosts)}`
				end, "Boosts")
				table.insert(children, state.boostText)
				table.insert(
					children,
					UI.ProgressView({
						value = state.progress,
					})
				)
				local markers = {}
				for index = 1, 12 do
					markers[index] = { id = `m{index}`, x = index * 7 }
				end
				state.markers = Compose.cell(markers)
				table.insert(
					children,
					Host.Frame({
						Name = "Markers",
						BackgroundTransparency = 1,
						Size = D2.new(1, 0, 0, 6),
						Compose.keyed({
							from = state.markers,
							key = function(item)
								return item.id
							end,
							render = function(current)
								return Host.Frame({ Name = `Dot-{current:peek().id}`, Size = D2.fromOffset(6, 6) })
							end,
						}),
					})
				)
				for index = 1, 4 do
					local button = UI.Button({ label = `Action {index}`, onActivate = state.activate })
					table.insert(state.nodes, button)
					table.insert(children, button)
				end
			end
			return stack(children)
		end
	end
	function state.step()
		state.n += 1
		local phases
		if name == "hud-binding-storm" then
			for index = 1, 50 do
				state.speed:set(state.n * 50 + index)
			end
		elseif name == "settings-churn" or name == "screen-lifecycle-churn" or name == "async-image-grid" then
			if state.close then
				state.close()
				state.close = nil
			end
			local stop = runtime.mount(function()
				if name == "screen-lifecycle-churn" then
					return lifecycle()
				elseif name == "async-image-grid" then
					return images()
				end
				local children = {}
				for index = 1, 6 do
					table.insert(
						children,
						Host.Frame({
							Size = D2.new(1, 0, 0, 40),
							Host.UIListLayout({
								FillDirection = E.FillDirection.Horizontal,
								Padding = types.UDim.new(0, 8),
							}),
							Host.TextLabel({
								Text = `Setting {index}`,
								Size = D2.fromOffset(0, 24),
								BackgroundTransparency = 1,
								TextXAlignment = E.TextXAlignment.Left,
								TextTruncate = E.TextTruncate.AtEnd,
								Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }),
							}),
							UI.Toggle({ label = `Toggle {index}`, value = Compose.cell(index % 2 == 0) }),
						})
					)
				end
				return stack(children)
			end, state.anchor)
			if name == "async-image-grid" then
				state.close = stop
			else
				stop()
			end
		elseif name == "virtual-list-scroll" or name == "lab-dense-scroll" or name == "native-scroll-drag" then
			local increment = if name == "native-scroll-drag" then 37 else 61
			state.scroll = (state.scroll or 0) + increment
			local maximum = if name == "native-scroll-drag"
				then 600
				elseif name == "virtual-list-scroll" then 2000 * 56 - 400
				else #state.rows:peek() * ((ctx.rowSize or 56) + 4) - math.max(120, ctx.viewport.h - 80)
			if name == "native-scroll-drag" then
				state.scroll %= maximum
			elseif state.scroll > maximum then
				state.scroll = 0
			end
			state.list.CanvasPosition = V2.new(0, state.scroll)
			if name == "native-scroll-drag" and ctx.engine then
				state.controls[1].DragStart.fire(V2.new(10, 10))
				for index = 1, 6 do
					state.controls[1].DragContinue.fire(V2.new(10 + index * 30, 10 + index * 12))
				end
				state.controls[1].DragEnd.fire(V2.new(210, 90))
			end
		elseif name == "lab-collection-churn" or name == "collection-mutation" then
			local items = table.clone(state.rows:peek())
			if name == "collection-mutation" then
				local item = { id = `r{state.n + #items}`, name = `Racer {state.n + #items}` }
				items[((state.n - 1) % #items) + 1] = item
				state.nextSelectionKey = item.id
			elseif name == "lab-collection-churn" then
				local item = {
					id = `ins{state.n}`,
					name = `Inserted {state.n}`,
					detail = "inserted during churn",
					team = "Ember",
					imageKey = dataset.IMAGE_KEYS[(state.n % #dataset.IMAGE_KEYS) + 1],
					value = 0.5,
					enabled = true,
					rank = math.max(1, math.floor(#items * 0.25)),
				}
				table.insert(items, math.max(1, math.floor(#items * 0.25)), item)
				table.remove(items, math.max(1, math.floor(#items * 0.6)))
				local at = math.max(1, (state.n * 7) % #items)
				table.insert(items, math.max(1, ((state.n * 7) % #items) + 3), table.remove(items, at))
			end
			state.rows:set(items)
			if state.nextSelectionKey then
				local key = state.nextSelectionKey
				state.selected:update(function(previous)
					local next = table.clone(previous)
					next[key] = if next[key] then nil else true
					return next
				end)
			end
		elseif name == "async-image-burst" then
			for index, source in state.images do
				if state.inflight[index] then
					state.async.stale += 1
					state.async.dropped += 1
				end
				local content = `rbxassetid://{state.n * 100 + index}`
				source:set(content)
				state.inflight[index] = content
			end
			for index = 1, 4 do
				state.inflight[index] = nil
				state.async.completed += 1
			end
		elseif name == "animation-interruption" then
			local target = if state.n % 2 == 0 then 1 else 0
			for _ = 1, 6 do
				state.current += (target - state.current) * 0.35
				state.value:set(state.current)
				if ctx.frame then
					ctx.frame()
				end
			end
		elseif name == "locale-textsize-change" or name == "picker-segmented-textsize" then
			state.expanded:set(state.n % 2 == 1)
			state.textSize:set(if state.n % 2 == 1 then 1.3 else 1)
			if name == "locale-textsize-change" then
				state.locale:set(if state.n % 2 == 0 then "en-us" else "de-de")
			end
		elseif
			name == "alert-present-dismiss"
			or name == "picker-menu-open-close"
			or name == "radial-menu-open-close"
		then
			state.presented:set(true)
			local ticks = if name == "radial-menu-open-close" then 2 else 1
			if ctx.frame then
				for _ = 1, ticks do
					ctx.frame()
				end
			end
			state.presented:set(false)
			if ctx.frame then
				for _ = 1, ticks do
					ctx.frame()
				end
			end
		elseif name == "adaptive-navigation-images" then
			local started = os.clock()
			if ctx.frame then
				ctx.frame()
			end
			phases = { idle = os.clock() - started }
			started = os.clock()
			local card = state.nodes[state.n % 2 + 1]
			if ctx.engine then
				if state.focused then
					state.focused.SelectionLost.fire()
				end
				card.SelectionGained.fire()
			else
				game:GetService("GuiService").SelectedObject = card
			end
			state.focused = card
			if ctx.frame then
				ctx.frame()
			end
			phases.focus = os.clock() - started
			started = os.clock()
			state.placement:set("sidebar")
			if ctx.frame then
				ctx.frame()
			end
			state.placement:set("topBar")
			if ctx.frame then
				ctx.frame()
				ctx.frame()
			end
			phases.navigation = os.clock() - started
			assert(state.contentBuilds == 1, "navigation chrome rebuilt retained inventory")
		elseif name == "navigation-customization" then
			local started = os.clock()
			state.customization:set({
				order = if state.n % 2 == 1 then { "race", "garage", "settings" } else { "garage", "race", "settings" },
			})
			assert(state.contentBuilds == 1, "customization rebuilt retained inventory")
			phases = { customization = os.clock() - started }
		elseif string.sub(name, 1, 11) == "theme-swap-" then
			state.palette:set(state.packages[state.n % 2 + 1])
			if ctx.themeNames then
				state.themeName:set(ctx.themeNames[state.n % 2 + 1])
			end
		elseif name == "scroll-focus-traversal" then
			for _, node in state.nodes do
				if ctx.engine then
					if state.focused then
						state.focused.SelectionLost.fire()
					end
					node.SelectionGained.fire()
					state.focused = node
					state.focusMoves = (state.focusMoves or 0) + 1
				else
					game:GetService("GuiService").SelectedObject = node
				end
			end
		elseif name == "stylesheet-state-churn" then
			local selected = state.n % 40 + 1
			for index, value in state.observed do
				value:set(index == selected)
			end
			state.tagCount = 0
			for _, node in state.nodes do
				state.tagCount += #node:GetTags()
			end
		elseif name ~= "shadow-storm" then
			for index, value in state.observed do
				if name == "dense-hud" then
					for offset = 0, 2 do
						value:set(state.n * 10 + index + offset)
					end
				else
					value:set(state.n % 2)
				end
			end
			if state.progress then
				state.progress:set((state.n % 100) / 100)
			end
			if name == "dense-hud" then
				local started = os.clock()
				if ctx.engine then
					state.nodes[1].Activated.fire()
				else
					state.activate()
				end
				assert(state.boostText.Text == `Boost x{state.boosts:peek()}`, "native activation did not reach text")
				phases = { inputToVisible = os.clock() - started }
			end
		end
		if state.requests then
			for _ = 1, math.min(4, #state.requests) do
				local request = table.remove(state.requests, 1)
				request.completed = true
				request.resolve(request.content)
				if request.cancelled then
					state.async.stale += 1
				else
					state.async.completed += 1
				end
			end
		end
		if
			ctx.frame
			and name ~= "animation-interruption"
			and name ~= "adaptive-navigation-images"
			and name ~= "navigation-customization"
			and name ~= "alert-present-dismiss"
			and name ~= "picker-menu-open-close"
			and name ~= "radial-menu-open-close"
		then
			ctx.frame()
		end
		return phases
	end
	return state
end
return workloads
