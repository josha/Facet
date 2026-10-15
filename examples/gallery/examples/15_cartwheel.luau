--!strict

type ExampleContext = typeof(require("@repo/examples/types").Context)
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T
type CartwheelModule = typeof(require("@repo/examples/reference/p2_cartwheel"))
type CartwheelData = typeof(require("@repo/examples/reference/p2_cartwheel/content/data"))

type RadialItem = typeof(require("@repo/tools/typecheck/aliases").RadialItem)
type StringPickerOption = typeof(require("@repo/tools/typecheck/aliases").StringPickerOption)
type Brew = {
	id: number,
	status: string,
	bottles: number,
	items: { { bottles: number, potion: string } },
}
type Seller = { id: string, name: string, bottles: number }
local loadCartwheel: (ModuleScript | string) -> CartwheelModule = require
local loadCartwheelData: (ModuleScript | string) -> CartwheelData = require
local makeView = require("./showcase_view")
local art = require("./showcase_art")
return {
	title = "Cartwheel",
	build = function(ctx: ExampleContext)
		local original = loadCartwheel(
			if script and ctx.find then ctx.find("reference", "p2_cartwheel") else "../../reference/p2_cartwheel"
		)
		local data = loadCartwheelData(
			if script and ctx.find
				then ctx.find("reference", "p2_cartwheel", "content", "data")
				else "../../reference/p2_cartwheel/content/data"
		)
		local reference = original.build(ctx)
		local model, steps = reference.model, reference.steps
		local UI, Host, C = ctx.UI, ctx.Host, ctx.Compose
		local D2 = ctx.types.UDim2
		local view = makeView(ctx)
		local noPin: number? = nil
		local expanded: { [number]: typeof(C.cell(false)) } = {}
		local width, lane, pinned = C.cell(1100), C.cell("new"), C.cell(noPin)
		local summaryOpen = C.cell(false)
		local notice = C.cell("Start a waiting order, or serve one that is already ready.")
		local metric = UI.environment().metricScale
		local wide = C.formula(function(use: Use)
			return use(width) >= 900 * use(metric)
		end)
		local function inspect(id: number)
			expanded[id] = expanded[id] or C.cell(false)
			expanded[id]:set(true)
		end
		local function command(id: number)
			local status = model.orders.statusOf(id)
			if status == "new" then
				steps.start(id)
				notice:set(`Order {id} is being confirmed.`)
			elseif status == "ready" then
				steps.collect(id)
				notice:set(`Serving order {id}…`)
			end
		end
		local function ticket(current: Readable<Brew>): GuiObject
			local id = current:peek().id
			expanded[id] = expanded[id] or C.cell(false)
			local actions: { RadialItem } = {
				{
					id = "inspect",
					label = "Inspect",
					onSelect = function()
						inspect(id)
					end,
				},
				{
					id = "pin",
					label = "Prioritize",
					onSelect = function()
						pinned:set(id)
						notice:set(`Order {id} moved to the front of its queue.`)
					end,
				},
				{
					id = "serve",
					label = "Serve",
					enabled = function(use: Use)
						return use(current).status == "ready"
					end,
					onSelect = function()
						command(id)
					end,
				},
			}
			local contents = {}
			for _, item in current:peek().items do
				table.insert(
					contents,
					view.text("Potion", `{item.bottles} × {assert(data.potionById(item.potion)).name}`)
				)
			end
			return UI.VStack("Order_" .. id) {
				width = "fill",
				padding = "m",
				gap = "s",
				view.text("OrderNumber", function(use: Use)
					return `{if use(pinned) == id then "★ " else ""}Order {id}`
				end, "heading"),
				view.text("BottleCount", `{current:peek().bottles} bottles`),
				UI.DisclosureGroup "OrderContents" {
					label = "What's in this order?",
					expanded = expanded[id],
					content = function(): Instance
						return UI.VStack {
							width = "fill",
							gap = "s",
							table.unpack(contents),
						}
					end,
				},
				C.show(function(use: Use)
					return use(current).status == "brewing"
				end, function()
					return UI.ProgressView "Preparation" {
						label = "Brewing",
						value = function(use: Use)
							use(model.clock.nowSignal)
							return 1 - (model.orders.remaining(id) or 0) / model.orders.brewSeconds()
						end,
					}
				end),
				view.actions({
					view.button("Advance_" .. id, function(use: Use)
						return if use(current).status == "ready"
							then "Serve order"
							elseif use(current).status == "brewing" then "Brewing…"
							else "Start brew"
					end, function()
						command(id)
					end, function(use: Use)
						local status = use(current).status
						local verb = if status == "ready" then "finish" else "start"
						return (status == "new" or status == "ready")
							and use(model.commands.status(verb .. ":" .. id)) ~= "pending"
					end),
					UI.RadialMenu("Actions_" .. id) {
						label = "Order actions",
						contentFit = "radial",
						ringWidth = "wide",
						center = "empty",
						scrim = "dark",
						items = actions,
					},
				}),
				UI.Divider {},
			}
		end
		local function column(status: string, title: string)
			local rows = C.formula(function(use: Use)
				local result: { Brew } = {}
				local priority = use(pinned)
				for _, brew in use(model.orders.brews) do
					if brew.status == status then
						table.insert(result, brew)
					end
				end
				table.sort(result, function(a, b)
					if a.id == priority then
						return b.id ~= priority
					elseif b.id == priority then
						return false
					else
						return a.id < b.id
					end
				end)
				return result
			end)
			return UI.Screen("Lane_" .. status) {
				gap = "s",
				padding = "s",
				view.text("LaneHeading", function(use: Use)
					return `{title} · {#use(rows)}`
				end, "heading"),
				UI.ScrollView "Tickets" {
					gap = "s",
					padding = "s",
					UI.fill(),
					C.keyed({
						from = rows,
						key = function(item: Brew)
							return item.id
						end,
						render = ticket,
					}),
					C.show(function(use: Use)
						return #use(rows) == 0
					end, function()
						return view.text(
							"EmptyLane",
							if status == "brewing"
								then "The kettles are quiet."
								elseif status == "ready" then "Finished orders arrive here."
								else "All caught up!"
						)
					end),
				},
			}
		end
		local function summary()
			return UI.VStack "SummaryBody" {
				width = "fill",
				gap = "m",
				view.text("SummaryTitle", "The day's takings", "heading"),
				view.text("Collected", function(use: Use)
					use(model.stats.version)
					return `{model.stats.collectedBottles()} bottles served`
				end),
				view.text("BestSellers", "Most popular potions", "heading"),
				C.keyed({
					from = C.formula(function(use: Use)
						use(model.stats.version)
						local result: { Seller } = {}
						for _, row in model.stats.topFive("today") do
							table.insert(result, { id = row.potion.id, name = row.potion.name, bottles = row.bottles })
						end
						return result
					end),
					key = function(item: Seller)
						return item.id
					end,
					render = function(current: Readable<Seller>): GuiObject
						return view.text("Seller", function(use: Use)
							local row = use(current)
							return `{row.name} · {row.bottles} bottles`
						end)
					end,
				}),
			}
		end
		local lanes: { StringPickerOption } = {
			{ value = "new", label = "Waiting" },
			{ value = "brewing", label = "Brewing" },
			{ value = "ready", label = "Ready" },
		}
		return {
			screen = function()
				return UI.ScrollView "Cartwheel" {
					padding = "m",
					gap = "m",
					ref = function(node)
						view.observeWidth(width, node)
					end,
					view.text("CartTitle", "Cartwheel · Market day", "title"),
					UI.Image "CartIllustration" {
						image = art.cart,
						scaleMode = "crop",
						Size = function(use: Use)
							return D2.new(1, 0, 0, math.clamp(use(width) * 0.18, 80, 170))
						end,
					},
					view.actions({
						UI.CollapsibleView "Takings" {
							label = "Day's takings",
							expanded = summaryOpen,
							content = summary,
						},
						view.button("AdvanceMarket", "Advance one minute", function()
							steps.advance(60)
							notice:set("A minute passes at the market.")
						end),
					}),
					view.text("MarketNotice", notice),
					C.show(function(use: Use)
						return not use(wide)
					end, function()
						return UI.Picker "OrderLane" {
							label = "Orders",
							selected = lane,
							options = lanes,
						}
					end),
					Host.Frame "OrderBoard" {
						Size = D2.new(1, 0, 0, 500),
						BackgroundTransparency = 1,
						C.show(wide, function()
							return Host.Frame "ThreeQueues" {
								Size = D2.fromScale(1, 1),
								BackgroundTransparency = 1,
								Host.Frame {
									Size = D2.fromScale(1 / 3, 1),
									BackgroundTransparency = 1,
									column("new", "Waiting"),
								},
								Host.Frame {
									Position = D2.fromScale(1 / 3, 0),
									Size = D2.fromScale(1 / 3, 1),
									BackgroundTransparency = 1,
									column("brewing", "Brewing"),
								},
								Host.Frame {
									Position = D2.fromScale(2 / 3, 0),
									Size = D2.fromScale(1 / 3, 1),
									BackgroundTransparency = 1,
									column("ready", "Ready to serve"),
								},
							}
						end, function()
							return C.keyed({
								from = C.formula(function(use: Use)
									return { use(lane) }
								end),
								key = function(id: string)
									return id
								end,
								render = function(current: Readable<string>): GuiObject
									local id = current:peek()
									return column(
										id,
										if id == "new"
											then "Waiting"
											elseif id == "ready" then "Ready to serve"
											else "Brewing"
									)
								end,
							})
						end),
					},
				}
			end,
			report = function()
				local report = reference.report()
				return {
					orders = report.orders,
					stats = report.stats,
					entitlement = report.entitlement,
					identity = report.identity,
					commands = report.commands,
					pinned = pinned:peek(),
				}
			end,
			model = model,
			steps = steps,
			inspect = inspect,
		}
	end,
}
