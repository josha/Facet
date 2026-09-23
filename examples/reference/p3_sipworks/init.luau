--!strict
local catalogService = require("@self/services/catalog")
local favoritesService = require("@self/services/favorites")
local rewardsService = require("@self/services/rewards")
local unlockService = require("@self/services/recipe_unlock")
local orderService = require("@self/services/order")
local i18nService = require("@self/services/i18n")
local taskService = require("@self/services/task")
local clockService = require("@self/services/clock")
local art = require("@self/content/art")
local referenceView = require("./view")
local Sipworks = { title = "Sipworks" }
function Sipworks.build(ctx)
	local Compose, UI, runtime = ctx.Compose, ctx.UI, ctx.runtime
	local view = referenceView(ctx)
	local clock = clockService.new(0)
	local function batch(body)
		runtime:batch(body)
	end
	local catalog = catalogService.new()
	local ids = {}
	for _, blend in catalog.blends do
		table.insert(ids, blend.id)
	end
	local favorites = favoritesService.new({ Compose = Compose, batch = batch, seed = 1, ids = ids })
	local rewards = rewardsService.new({ Compose = Compose, batch = batch, startEarned = rewardsService.THRESHOLD - 1 })
	local unlock = unlockService.new({ Compose = Compose, batch = batch, clock = clock })
	local order = orderService.new({ Compose = Compose, batch = batch, clock = clock })
	local taskModel = taskService.new({ Compose = Compose, batch = batch, rewards = rewards, order = order })
	local i18n = i18nService.new({ Compose = Compose, locale = "en" })
	local section, search, selected = Compose.cell("menu"), Compose.cell(""), Compose.cell(nil)
	local batchSize, notice = Compose.cell(1), Compose.cell("")
	local botanical, recipe = Compose.cell(nil), Compose.cell(false)
	local selectedOpen, botanicalOpen = Compose.cell(false), Compose.cell(false)
	local gathered = {}
	local function text(key, params)
		return function(use)
			return i18n.at(use(i18n.locale), key, params)
		end
	end
	local function blendName(id, use)
		local item = catalog.blend(id)
		return i18n.nameAt(use(i18n.locale), "blend", id, item.title)
	end
	local function openBlend(id)
		selected:set(id)
		recipe:set(false)
		selectedOpen:set(true)
	end
	local function place(id, mode)
		if mode == "redeem" and not rewards.canRedeem() then
			return false
		end
		local result = order.placeOrder(id, mode)
		if result.started then
			taskModel.notePlacing()
		else
			notice:set(i18n.t(result.reasonKey or "guard.paymentsDisabled"))
		end
		return result.started
	end
	Compose.cleanup(order.onEvent(function(event, info)
		if event == "confirmed" then
			if info.mode == "redeem" then
				rewards.redeem()
			else
				rewards.earn(1)
			end
			taskModel.noteConfirmed(info.mode)
			notice:set(
				if info.mode == "redeem"
					then i18n.t("order.redeemed")
					else "Your order is confirmed. Your stamp is on the card."
			)
		elseif event == "rejected" then
			taskModel.noteRejected()
			notice:set("The counter is closed. Your stamps are unchanged; try again.")
		elseif event == "ready" then
			notice:set("Your pour is ready.")
		end
	end))
	Compose.cleanup(unlock.onResolved(function(ok)
		notice:set(if ok then "Your Blend Book is unlocked." else "The purchase was declined. Try again.")
	end))
	local heartbeat = ctx.heartbeat or (if game then game:GetService("RunService").Heartbeat else nil)
	if heartbeat then
		Compose.cleanup(heartbeat:Connect(clock.advance))
	end
	Compose.cleanup(function()
		clock.reset()
	end)
	local visible = Compose.formula(function(use)
		local locale, query, which = use(i18n.locale), use(search), use(section)
		use(favorites.set)
		local result = {}
		for _, blend in catalog.blends do
			if
				(which ~= "favorites" or favorites.isFavorite(blend.id))
				and catalog.matches(blend.id, query, function(kind, id, label)
					return i18n.nameAt(locale, kind, id, label)
				end)
			then
				table.insert(result, blend)
			end
		end
		table.sort(result, function(a, b)
			return i18n.sortKey(locale, a.title) < i18n.sortKey(locale, b.title)
		end)
		return result
	end)
	local function menuPage()
		return view.page("Menu", {
			view.text("Sipworks", 30),
			view.text("Browse house blends, collect Steam Stamps, and make your next pour on us."),
			view.text(function(use)
				return "Today's order: "
					.. use(taskModel.phase)
					.. " · "
					.. tostring(use(taskModel.stamps))
					.. " of 10 stamps"
			end),
			view.action("Task", function(use)
				return if use(taskModel.phase) == "redeem" then "Redeem a Mistral Mint" else "Order Amber Harvest"
			end, function()
				place(taskModel.ctaBlendId:peek(), if taskModel.phase:peek() == "redeem" then "redeem" else "paid")
			end, function(use)
				return use(order.status) ~= "pending" and use(taskModel.phase) ~= "done"
			end),
			UI.TextInput({ Name = "Search", value = search, placeholder = "Search blends and botanicals" }),
			view.column("Blends", {
				view.list(visible, function(current)
					local blend = current:peek()
					return view.column(blend.id, {
						view.text(art.of("blend", blend.id).mark, 24),
						view.action("Open", function(use)
							return blendName(blend.id, use)
						end, function()
							openBlend(blend.id)
						end),
						view.text(blend.paragraphs[1].text),
						view.action("Favorite", function(use)
							use(favorites.set)
							return if favorites.isFavorite(blend.id) then "Remove favorite" else "Save favorite"
						end, function()
							favorites.toggle(blend.id)
						end),
					})
				end),
			}),
		})
	end
	local function recipeContent(id)
		local rows = {
			view.text("Recipe", 24),
			UI.Stepper({ Name = "Batch", value = batchSize, min = 1, max = 9, step = 1, label = "Batch size" }),
		}
		for _, measure in catalog.recipeMeasures(id) do
			local ingredient = catalog.botanical(measure.botanicalId)
			local key = id .. "/" .. ingredient.id
			gathered[key] = gathered[key] or Compose.cell(false)
			table.insert(
				rows,
				UI.Toggle({
					Name = ingredient.id,
					value = gathered[key],
					label = function(use)
						return ingredient.name
							.. " · "
							.. i18n.measureAt(use(i18n.locale), measure.value * use(batchSize), measure.unit)
					end,
				})
			)
		end
		return view.column("Recipe", rows)
	end
	local function detail()
		local id = selected:peek()
		local blend = catalog.blend(id)
		local children = { view.text(function(use)
			return blendName(id, use)
		end, 26) }
		for _, paragraph in blend.paragraphs do
			table.insert(children, view.text(paragraph.text, if paragraph.emphasis then 18 else 16))
		end
		table.insert(
			children,
			view.text(
				`{catalog.caffeineMg(id)} mg caffeine · {catalog.leafGrams(id)} g leaves · {catalog.steepMinutes(id)} min steep`
			)
		)
		for _, botanicalId in catalog.tileBotanicals(id) do
			local item = catalog.botanical(botanicalId)
			table.insert(
				children,
				view.action(item.id, item.name, function()
					botanical:set(item.id)
					botanicalOpen:set(true)
				end)
			)
		end
		table.insert(
			children,
			view.action("Order", function(use)
				return if use(order.status) == "pending" then "Confirming…" else "Order · " .. order.price
			end, function()
				place(id, "paid")
			end, function(use)
				return use(order.status) ~= "pending"
			end)
		)
		table.insert(
			children,
			view.action("Recipe", "View recipe", function()
				recipe:set(not recipe:peek())
			end)
		)
		table.insert(
			children,
			Compose.show(recipe, function()
				return Compose.show(function(use)
					return blend.free == true or use(unlock.unlocked)
				end, function()
					return recipeContent(id)
				end, function()
					return view.column("Unlock", {
						view.text(text("unlock.description")),
						view.action(
							"Buy",
							"Unlock Blend Book · " .. unlock.product.price,
							unlock.purchase,
							function(use)
								return use(unlock.availability) == "available" and use(unlock.status) ~= "pending"
							end
						),
					})
				end)
			end)
		)
		return view.page("BlendDetail", children)
	end
	local function stampsPage()
		return view.page("Rewards", {
			view.text("Steam Stamps", 28),
			UI.Picker({
				Name = "Locale",
				selected = i18n.locale,
				options = { { value = "en", label = "English" }, { value = "xa", label = "Expanded" } },
			}),
			view.text(function(use)
				return tostring(use(rewards.earned) - use(rewards.spent)) .. " stamps · ten stamps earn a free pour"
			end),
			UI.ProgressView({
				value = function(use)
					return math.clamp((use(rewards.earned) - use(rewards.spent)) / 10, 0, 1)
				end,
				label = "Stamp card",
			}),
			view.action("Redeem", "Redeem a free Mistral Mint", function()
				place(taskService.FREE_POUR_BLEND, "redeem")
			end, function(use)
				return use(rewards.earned) - use(rewards.spent) >= 10 and use(order.status) ~= "pending"
			end),
			view.action("Acknowledge", "Acknowledge new stamps", rewards.clearUnstamped),
		})
	end
	local function bookPage()
		return view.page("BlendBook", {
			view.text("Blend Book", 28),
			view.text(text("unlock.description")),
			Compose.show(function(use)
				return not use(unlock.unlocked)
			end, function()
				return view.action("Buy", "Unlock · " .. unlock.product.price, unlock.purchase, function(use)
					return use(unlock.availability) == "available" and use(unlock.status) ~= "pending"
				end)
			end),
			view.column("Recipes", {
				view.list(catalog.blends, function(current)
					local blend = current:peek()
					return view.action(blend.id, blend.title, function()
						openBlend(blend.id)
						recipe:set(true)
					end)
				end),
			}),
		})
	end
	local function screen()
		return ctx.Host.Frame({
			Name = "Sipworks",
			BackgroundTransparency = 1,
			Size = ctx.types.UDim2.fromScale(1, 1),
			UI.TabView({
				Name = "Destinations",
				selection = section,
				style = "sidebarAdaptable",
				Size = ctx.types.UDim2.new(1, 0, 1, -64),
				tabs = {
					{ id = "menu", label = "Menu", content = menuPage },
					{ id = "favorites", label = "Favorites", content = menuPage },
					{ id = "rewards", label = "Steam Stamps", content = stampsPage },
					{ id = "book", label = "Blend Book", content = bookPage },
				},
			}),
			UI.Label({
				label = notice,
				Position = ctx.types.UDim2.new(0, 16, 1, -60),
				Size = ctx.types.UDim2.new(1, -32, 0, 56),
				TextWrapped = true,
			}),
			UI.Sheet({
				Name = "Blend",
				isPresented = selectedOpen,
				detent = Compose.cell("large"),
				title = "House blend",
				content = detail,
			}),
			UI.Sheet({
				Name = "Botanical",
				isPresented = botanicalOpen,
				detent = Compose.cell("medium"),
				title = "Botanical",
				content = function()
					local item = catalog.botanical(botanical:peek())
					local showFacts = Compose.cell(false)
					local rows = {
						view.text(item.name, 26),
						view.text(art.of("botanical", item.id).mark, 42),
						view.action("Flip", "Brew facts", function()
							showFacts:set(not showFacts:peek())
						end),
						Compose.show(showFacts, function()
							local facts = {}
							for _, fact in catalog.factsFor(selected:peek(), item.id) do
								table.insert(
									facts,
									view.text(
										i18n.t(fact.key)
											.. ": "
											.. i18n.t("facts." .. fact.kind, { value = fact.value })
									)
								)
							end
							return view.column("MeasuredFacts", facts)
						end, function()
							return view.text(
								`{item.gramsPerTsp} g per teaspoon · {item.caffeinePerGram} mg caffeine per gram`
							)
						end),
					}
					return view.column("BotanicalCard", rows)
				end,
			}),
		})
	end
	local model = {
		catalog = catalog,
		favorites = favorites,
		rewards = rewards,
		unlock = unlock,
		order = order,
		task = taskModel,
		i18n = i18n,
		section = section,
		selected = selected,
		batch = batchSize,
		search = search,
	}
	return {
		screen = screen,
		model = model,
		steps = {
			advance = clock.advance,
			order = place,
			open = openBlend,
			section = function(id)
				section:set(id)
			end,
			favorite = favorites.toggle,
			redeem = function()
				return place(taskService.FREE_POUR_BLEND, "redeem")
			end,
			buyBook = unlock.purchase,
			locale = i18n.setLocale,
		},
		report = function()
			return {
				task = taskModel.dump(),
				favorites = favorites.ids(),
				order = order.status:peek(),
				unlocked = unlock.unlocked:peek(),
			}
		end,
	}
end
return Sipworks
