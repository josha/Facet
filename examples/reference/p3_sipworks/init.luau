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
	local function botanicalName(item, use)
		return i18n.nameAt(use(i18n.locale), "botanical", item.id, item.name)
	end
	local function paragraph(id, index, body)
		return function(use)
			return i18n.nameAt(use(i18n.locale), "paragraph", id .. "#" .. index, body)
		end
	end
	local function number(value, use)
		return i18n.numberAt(use(i18n.locale), value)
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
			notice:set(result.reasonKey or "guard.paymentsDisabled")
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
			notice:set(if info.mode == "redeem" then "order.redeemed" else "notice.confirmed")
		elseif event == "rejected" then
			taskModel.noteRejected()
			notice:set("notice.rejected")
		elseif event == "ready" then
			notice:set("notice.ready")
		end
	end))
	Compose.cleanup(unlock.onResolved(function(ok)
		notice:set(if ok then "notice.unlocked" else "notice.declined")
	end))
	local heartbeat = ctx.heartbeat or (if game then game:GetService("RunService").Heartbeat else nil)
	if heartbeat then
		local beat = heartbeat:Connect(clock.advance)
		Compose.cleanup(function()
			beat:Disconnect()
		end)
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
			view.text(text("app.title"), 30),
			view.text(text("menu.intro")),
			view.text(function(use)
				local locale = use(i18n.locale)
				return i18n.at(locale, "menu.status", {
					phase = i18n.at(locale, "task.phase." .. use(taskModel.phase)),
					n = i18n.numberAt(locale, use(taskModel.stamps)),
				})
			end),
			view.action("Task", function(use)
				local key = if use(taskModel.phase) == "redeem" then "task.cta.redeemOne" else "task.cta.order"
				return i18n.at(use(i18n.locale), key, { title = blendName(use(taskModel.ctaBlendId), use) })
			end, function()
				place(taskModel.ctaBlendId:peek(), if taskModel.phase:peek() == "redeem" then "redeem" else "paid")
			end, function(use)
				return use(order.status) ~= "pending" and use(taskModel.phase) ~= "done"
			end),
			UI.TextInput "Search" { value = search, placeholder = text("search.placeholder") },
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
						view.text(paragraph(blend.id, 1, blend.paragraphs[1].text)),
						view.action("Favorite", function(use)
							use(favorites.set)
							return i18n.at(
								use(i18n.locale),
								if favorites.isFavorite(blend.id) then "row.remove" else "row.save"
							)
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
			view.text(text("recipe.title"), 24),
			UI.Stepper "Batch" { value = batchSize, min = 1, max = 9, step = 1, label = text("recipe.batchSize") },
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
						local locale = use(i18n.locale)
						return i18n.at(locale, "recipe.line", {
							name = botanicalName(ingredient, use),
							measure = i18n.measureAt(locale, measure.value * use(batchSize), measure.unit),
						})
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
		for index, entry in blend.paragraphs do
			table.insert(children, view.text(paragraph(id, index, entry.text), if entry.emphasis then 18 else 16))
		end
		table.insert(
			children,
			view.text(function(use)
				return i18n.at(use(i18n.locale), "detail.stats", {
					caffeine = number(catalog.caffeineMg(id), use),
					grams = number(catalog.leafGrams(id), use),
					minutes = number(catalog.steepMinutes(id), use),
				})
			end)
		)
		for _, botanicalId in catalog.tileBotanicals(id) do
			local item = catalog.botanical(botanicalId)
			table.insert(
				children,
				view.action(item.id, function(use)
					return botanicalName(item, use)
				end, function()
					botanical:set(item.id)
					botanicalOpen:set(true)
				end)
			)
		end
		table.insert(
			children,
			view.action("Order", function(use)
				return if use(order.status) == "pending"
					then i18n.at(use(i18n.locale), "detail.confirming")
					else i18n.at(use(i18n.locale), "detail.order", { price = order.price })
			end, function()
				place(id, "paid")
			end, function(use)
				return use(order.status) ~= "pending"
			end)
		)
		table.insert(
			children,
			view.action("Recipe", text("detail.viewRecipe"), function()
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
						Compose.show(function(use)
							return use(unlock.availability) == "available"
						end, function()
							return view.action(
								"Buy",
								text("detail.unlock", { price = unlock.product.price }),
								unlock.purchase,
								function(use)
									return use(unlock.status) ~= "pending"
								end
							)
						end),
					})
				end)
			end)
		)
		return view.page("BlendDetail", children)
	end
	local function stampsPage()
		return view.page("Rewards", {
			view.text(text("rewards.title"), 28),
			UI.Picker "Locale" {
				selected = i18n.locale,
				options = function(use)
					local locale = use(i18n.locale)
					local options = {}
					for _, id in i18nService.LOCALES do
						table.insert(options, { value = id, label = i18n.at(locale, "locale." .. id) })
					end
					return options
				end,
			},
			view.text(function(use)
				local locale = use(i18n.locale)
				return i18n.at(
					locale,
					"rewards.summary",
					{ n = i18n.numberAt(locale, use(rewards.earned) - use(rewards.spent)) }
				)
			end),
			UI.ProgressView({
				value = function(use)
					return math.clamp((use(rewards.earned) - use(rewards.spent)) / 10, 0, 1)
				end,
				label = text("rewards.card"),
			}),
			view.action("Redeem", function(use)
				return i18n.at(
					use(i18n.locale),
					"rewards.redeemFree",
					{ title = blendName(taskService.FREE_POUR_BLEND, use) }
				)
			end, function()
				place(taskService.FREE_POUR_BLEND, "redeem")
			end, function(use)
				return use(rewards.earned) - use(rewards.spent) >= 10 and use(order.status) ~= "pending"
			end),
			view.action("Acknowledge", text("rewards.acknowledge"), rewards.clearUnstamped),
		})
	end
	local function bookPage()
		return view.page("BlendBook", {
			view.text(text("nav.book"), 28),
			view.text(text("unlock.description")),
			Compose.show(function(use)
				return not use(unlock.unlocked) and use(unlock.availability) == "available"
			end, function()
				return view.action(
					"Buy",
					text("book.unlock", { price = unlock.product.price }),
					unlock.purchase,
					function(use)
						return use(unlock.status) ~= "pending"
					end
				)
			end),
			view.column("Recipes", {
				view.list(catalog.blends, function(current)
					local blend = current:peek()
					return view.action(blend.id, function(use)
						return blendName(blend.id, use)
					end, function()
						openBlend(blend.id)
						recipe:set(true)
					end)
				end),
			}),
		})
	end
	local function screen()
		return ctx.Host.Frame "Sipworks" {
			BackgroundTransparency = 1,
			Size = ctx.types.UDim2.fromScale(1, 1),
			UI.TabView "Destinations" {
				selection = section,
				style = "sidebarAdaptable",
				Size = ctx.types.UDim2.new(1, 0, 1, -64),
				tabs = {
					{ id = "menu", label = text("nav.menu"), content = menuPage },
					{ id = "favorites", label = text("nav.favorites"), content = menuPage },
					{ id = "rewards", label = text("nav.stamps"), content = stampsPage },
					{ id = "book", label = text("nav.book"), content = bookPage },
				},
			},
			UI.Label({
				text = function(use)
					local key = use(notice)
					return if key == "" then "" else i18n.at(use(i18n.locale), key)
				end,
				Position = ctx.types.UDim2.new(0, 16, 1, -60),
				Size = ctx.types.UDim2.new(1, -32, 0, 56),
				AutomaticSize = ctx.types.Enum.AutomaticSize.None,
				TextWrapped = true,
			}),
			UI.Sheet "Blend" {
				isPresented = selectedOpen,
				detent = Compose.cell("large"),
				title = text("sheet.blend"),
				closeButton = text("common.done"),
				content = detail,
			},
			UI.Sheet "Botanical" {
				isPresented = botanicalOpen,
				detent = Compose.cell("medium"),
				title = text("sheet.botanical"),
				closeButton = text("common.done"),
				content = function()
					local item = catalog.botanical(botanical:peek())
					local showFacts = Compose.cell(false)
					local rows = {
						view.text(function(use)
							return botanicalName(item, use)
						end, 26),
						view.text(art.of("botanical", item.id).mark, 42),
						view.action("Flip", text("card.factsOpen"), function()
							showFacts:set(not showFacts:peek())
						end),
						Compose.show(showFacts, function()
							local facts = {}
							for _, fact in catalog.factsFor(selected:peek(), item.id) do
								table.insert(
									facts,
									view.text(function(use)
										local locale = use(i18n.locale)
										return i18n.at(locale, "facts.line", {
											label = i18n.at(locale, fact.key),
											value = i18n.at(
												locale,
												"facts." .. fact.kind,
												{ value = i18n.numberAt(locale, fact.value) }
											),
										})
									end)
								)
							end
							return view.column("MeasuredFacts", facts)
						end, function()
							return view.text(function(use)
								return i18n.at(use(i18n.locale), "botanical.summary", {
									grams = number(item.gramsPerTsp, use),
									caffeine = number(item.caffeinePerGram, use),
								})
							end)
						end),
					}
					return view.column("BotanicalCard", rows)
				end,
			},
		}
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
