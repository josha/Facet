--!strict

type CartwheelModule = typeof(require("@repo/examples/reference/p2_cartwheel"))
type CartwheelData = typeof(require("@repo/examples/reference/p2_cartwheel/content/data"))

type RadialItem = typeof(require("@repo/tools/typecheck/aliases").RadialItem)
type PickerOption = typeof(require("@repo/tools/typecheck/aliases").PickerOption)
local loadCartwheel = require :: (string) -> CartwheelModule
local loadCartwheelData = require :: (string) -> CartwheelData
local makeView = require("./showcase_view")
local art = require("./showcase_art")
return {
	title = "Cartwheel",
	build = function(ctx: any)
		local original = if script
			then ctx.load("reference", "p2_cartwheel")
			else loadCartwheel("../../reference/p2_cartwheel")
		local data = if script
			then ctx.load("reference", "p2_cartwheel", "content", "data")
			else loadCartwheelData("../../reference/p2_cartwheel/content/data")
		local reference = original.build(ctx)
		local model, steps = reference.model, reference.steps
		local UI, Host, C = ctx.UI, ctx.Host, ctx.Compose
		local D2 = ctx.types.UDim2
		local view = makeView(ctx)
		local width, lane, pinned = C.cell(1100), C.cell("new"), C.cell(nil)
		local expanded, summaryOpen = {}, C.cell(false)
		local notice = C.cell("Start a waiting order, or serve one that is already ready.")
		local metric = UI.environment().metricScale
		local wide = C.formula(function(use: any)
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
		local function ticket(current: any)
			local id = current:peek().id
			expanded[id] = expanded[id] or C.cell(false)
			local contents = {}
			for _, item in current:peek().items do
				table.insert(contents, view.text("Potion", `{item.bottles} × {data.potionById(item.potion).name}`))
			end
			return UI.VStack("Order_" .. id) {
				width = "fill" :: "fill",
				padding = "m",
				gap = "s",
				view.text("OrderNumber", function(use: any)
					return `{if use(pinned) == id then "★ " else ""}Order {id}`
				end, "heading") :: unknown,
				view.text("BottleCount", `{current:peek().bottles} bottles`),
				UI.DisclosureGroup "OrderContents" {
					label = "What's in this order?",
					expanded = expanded[id],
					content = function(): Instance
						return UI.VStack {
							width = "fill" :: "fill",
							gap = "s",
							table.unpack((contents :: unknown) :: { unknown }),
						}
					end,
				},
				C.show(function(use: any)
					return use(current).status == "brewing"
				end, function()
					return UI.ProgressView "Preparation" {
						label = "Brewing",
						value = function(use: any)
							use(model.clock.nowSignal)
							return 1 - (model.orders.remaining(id) or 0) / model.orders.brewSeconds()
						end,
					}
				end),
				view.actions({
					view.button("Advance_" .. id, function(use: any)
						return if use(current).status == "ready"
							then "Serve order"
							elseif use(current).status == "brewing" then "Brewing…"
							else "Start brew"
					end, function()
						command(id)
					end, function(use: any)
						local status = use(current).status
						local verb = if status == "ready" then "finish" else "start"
						return (status == "new" or status == "ready")
							and use(model.commands.status(verb .. ":" .. id)) ~= "pending"
					end),
					UI.RadialMenu("Actions_" .. id) {
						label = "Order actions",
						contentFit = "radial" :: "radial",
						ringWidth = "wide" :: "wide",
						center = "empty" :: "empty",
						scrim = "dark",
						items = {
							{
								id = "inspect",
								label = "Inspect",
								onSelect = function()
									inspect(id)
								end,
							} :: RadialItem,
							{
								id = "pin",
								label = "Prioritize",
								onSelect = function()
									pinned:set(id)
									notice:set(`Order {id} moved to the front of its queue.`)
								end,
							} :: RadialItem,
							{
								id = "serve",
								label = "Serve",
								enabled = function(use: any)
									return use(current).status == "ready"
								end,
								onSelect = function()
									command(id)
								end,
							} :: RadialItem,
						},
					},
				}),
				UI.Divider {},
			}
		end
		local function column(status: string, title: string)
			local rows = C.formula(function(use: any)
				local result = {}
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
				view.text("LaneHeading", function(use: any)
					return `{title} · {#use(rows)}`
				end, "heading") :: unknown,
				UI.ScrollView "Tickets" {
					gap = "s",
					padding = "s",
					UI.fill() :: unknown,
					C.keyed({
						from = rows,
						key = function(item)
							return item.id
						end,
						render = ticket,
					}),
					C.show(function(use: any)
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
			return UI.VStack {
				width = "fill" :: "fill",
				gap = "m",
				view.text("SummaryTitle", "The day's takings", "heading") :: unknown,
				view.text("Collected", function(use: any)
					use(model.stats.version)
					return `{model.stats.collectedBottles()} bottles served`
				end),
				view.text("BestSellers", "Most popular potions", "heading"),
				C.keyed({
					from = C.formula(function(use: any)
						use(model.stats.version)
						local result = {}
						for _, row in model.stats.topFive("today") do
							table.insert(result, { id = row.potion.id, name = row.potion.name, bottles = row.bottles })
						end
						return result
					end),
					key = function(item)
						return item.id
					end,
					render = function(current): GuiObject
						return view.text("Seller", function(use: any)
							local row = use(current)
							return `{row.name} · {row.bottles} bottles`
						end)
					end,
				}),
			}
		end
		return {
			screen = function()
				return UI.ScrollView "Cartwheel" {
					padding = "m",
					gap = "m",
					ref = view.observeWidth(width),
					view.text("CartTitle", "Cartwheel · Market day", "title") :: unknown,
					UI.Image "CartIllustration" {
						image = art.cart,
						scaleMode = "crop" :: "crop",
						Size = function(use: any)
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
					C.show(function(use: any)
						return not use(wide)
					end, function()
						return UI.Picker "OrderLane" {
							label = "Orders",
							selected = lane,
							options = {
								{ value = "new", label = "Waiting" } :: PickerOption,
								{ value = "brewing", label = "Brewing" } :: PickerOption,
								{ value = "ready", label = "Ready" } :: PickerOption,
							},
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
								} :: unknown,
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
								from = C.formula(function(use: any)
									return { use(lane) }
								end),
								key = function(id)
									return id
								end,
								render = function(current): GuiObject
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
				report.pinned = pinned:peek()
				return report
			end,
			model = model,
			steps = steps,
			inspect = inspect,
		}
	end,
}
