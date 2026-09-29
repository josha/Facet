--!strict
local makeView = require("./showcase_view")
local recipes = {
	{ id = "sun", label = "Bottled sunshine", ingredient = "Sun petals", color = { 255, 192, 77 }, price = 15 },
	{ id = "moon", label = "Moonlight tonic", ingredient = "Moon mint", color = { 160, 146, 244 }, price = 20 },
	{ id = "moss", label = "Mossheart brew", ingredient = "Forest moss", color = { 102, 204, 161 }, price = 12 },
}
local orders = {
	{ name = "Mira", recipe = "sun", quantity = 2, note = "A little sunshine for a long journey." },
	{ name = "Orin", recipe = "moon", quantity = 1, note = "Something for a night under the stars." },
	{ name = "Pip", recipe = "moss", quantity = 3, note = "The whole hiking club is coming!" },
}
local byId = {}
for _, recipe in recipes do
	byId[recipe.id] = recipe
end
return {
	title = "Potion Shop",
	build = function(ctx: any)
		local UI, Host, C = ctx.UI, ctx.Host, ctx.Compose
		local V3, C3, E, D2 = ctx.types.Vector3, ctx.types.Color3, ctx.types.Enum, ctx.types.UDim2
		local view = makeView(ctx)
		local selected, quantity, progress = C.cell("sun"), C.cell(0), C.cell(0)
		local customer, coins, phase = C.cell(1), C.cell(0), C.cell("mixing")
		local ledger, notice = C.cell({}), C.cell("Your first customer wants two bottles of sunshine.")
		local bookOpen, ledgerOpen = C.cell(false), C.cell(false)
		local brewed: { recipe: string, quantity: number }? = nil
		local function advance(dt)
			if phase:peek() ~= "brewing" then
				return
			end
			progress:set(math.min(1, progress:peek() + math.max(0, dt) / 3))
			if progress:peek() >= 1 then
				phase:set("ready")
				notice:set("Freshly brewed. Ready to serve!")
			end
		end
		if ctx.runService then
			ctx.runtime.connect(ctx.runService, "Heartbeat", function(dt)
				if not ctx.pageVisible or ctx.pageVisible:peek() then
					advance(dt)
				end
			end)
		end
		local function brew()
			if phase:peek() ~= "mixing" or customer:peek() > #orders then
				return false
			end
			local order = orders[customer:peek()]
			if selected:peek() ~= order.recipe or quantity:peek() ~= order.quantity then
				notice:set(
					`{order.name} needs {order.quantity} × {byId[order.recipe].label}. Check the recipe and batch size.`
				)
				return false
			end
			brewed = { recipe = selected:peek(), quantity = quantity:peek() }
			progress:set(0)
			phase:set("brewing")
			notice:set("A pinch of patience…")
			return true
		end
		local function serve()
			if phase:peek() ~= "ready" or not brewed then
				return false
			end
			local index = customer:peek()
			local earned = byId[brewed.recipe].price * brewed.quantity
			local entries = table.clone(ledger:peek())
			table.insert(entries, {
				id = index,
				name = orders[index].name,
				recipe = byId[brewed.recipe].label,
				quantity = brewed.quantity,
				earned = earned,
			})
			ctx.runtime:batch(function()
				ledger:set(entries)
				coins:set(coins:peek() + earned)
				customer:set(index + 1)
				quantity:set(0)
				phase:set("mixing")
				progress:set(0)
				notice:set(
					if index == #orders
						then "Three happy customers. A lovely day's work!"
						else orders[index + 1].name .. " is next. Take a look at their order."
				)
			end)
			brewed = nil
			return true
		end
		local function reset()
			ctx.runtime:batch(function()
				selected:set("sun")
				quantity:set(0)
				progress:set(0)
				customer:set(1)
				coins:set(0)
				phase:set("mixing")
				ledger:set({})
				notice:set("Your first customer wants two bottles of sunshine.")
			end)
			brewed = nil
		end
		local function addIngredient(id: string)
			if phase:peek() ~= "mixing" or customer:peek() > #orders or not byId[id] then
				return false
			end
			if quantity:peek() > 0 and selected:peek() ~= id then
				notice:set("Empty the cauldron before changing ingredients.")
				return false
			end
			if quantity:peek() >= 3 then
				return false
			end
			selected:set(id)
			quantity:set(quantity:peek() + 1)
			notice:set(`{quantity:peek()} portions of {byId[id].ingredient}. Check the order, then brew.`)
			return true
		end
		local function counter()
			return view.stage("Cauldron", function()
				local parts = {
					view.part("Counter", V3.new(11, 0.5, 6), V3.new(0, -0.4, 0), C3.fromRGB(108, 75, 62)),
					view.part(
						"Pot",
						V3.new(3.2, 2.3, 3.2),
						V3.new(0, 0.9, 0),
						C3.fromRGB(49, 54, 64),
						{ Shape = E.PartType.Ball }
					),
					view.part(
						"Rim",
						V3.new(3.1, 0.35, 3.1),
						V3.new(0, 1.7, 0),
						C3.fromRGB(115, 100, 91),
						{ Shape = E.PartType.Ball }
					),
					view.part("Brew", V3.new(2.7, 0.3, 2.7), V3.new(0, 1.8, 0), function(use: any)
						return C3.fromRGB(table.unpack(byId[use(selected)].color))
					end, {
						Shape = E.PartType.Ball,
						Material = E.Material.Neon,
						Transparency = function(use: any)
							return if use(quantity) == 0 then 1 else 0.2
						end,
					}),
				}
				for index = 1, 3 do
					table.insert(
						parts,
						view.part(
							"Bubble" .. index,
							V3.new(0.35, 0.35, 0.35),
							V3.new((index - 2) * 0.65, 2 + index * 0.35, 0),
							C3.fromRGB(239, 223, 181),
							{
								Shape = E.PartType.Ball,
								Transparency = function(use: any)
									return if use(phase) == "brewing" then 0.2 else 1
								end,
							}
						)
					)
				end
				return Host.Model "PotionWorkbench" { table.unpack(parts) }
			end, ctx.types.CFrame.lookAt(V3.new(7, 7, 10), V3.new(0, 0.8, 0)), 260)
		end
		local function shop()
			local tickets, ingredients = {}, {}
			for index, order in orders do
				table.insert(
					tickets,
					UI.VStack("Ticket" .. index) {
						width = "fill",
						gap = "xs",
						padding = "s",
						view.text("Customer", function(use: any)
							return `{if use(customer) > index
								then "✓ "
								elseif use(customer) == index then "→ "
								else ""}{order.name}`
						end, "heading"),
						view.text("Request", `{order.quantity} × {byId[order.recipe].label}`, "caption"),
					}
				)
			end
			for _, recipe in recipes do
				local ingredient = UI.Button("Add_" .. recipe.id) {
					label = recipe.ingredient .. "\nAdd one portion",
					Size = D2.new(1, 0, 0, 72),
					enabled = function(use: any)
						return use(phase) == "mixing" and use(customer) <= #orders
					end,
					onActivate = function()
						addIngredient(recipe.id)
					end,
				}
				UI.draggable(ingredient, { payload = { kind = "ingredient", id = recipe.id }, armOnTap = false })
				table.insert(ingredients, ingredient)
			end
			local cauldron = counter()
			UI.dropTarget(cauldron, {
				accepts = function(payload)
					return payload.kind == "ingredient"
				end,
				onDrop = function(payload)
					addIngredient(payload.id)
				end,
			})
			local serveButton = view.button("Serve", "Hand over the order", serve, function(use: any)
				return use(phase) == "ready"
			end)
			UI.draggable(serveButton, { payload = { kind = "order" }, armOnTap = false })
			local rail = UI.Grid "OrderRail" { columns = 3, gap = "m", cellHeight = 104, table.unpack(tickets) }
			UI.dropTarget(rail, {
				accepts = function(payload)
					return payload.kind == "order" and phase:peek() == "ready"
				end,
				onDrop = serve,
			})
			return UI.ScrollView "PotionShop" {
				padding = "l",
				gap = "m",
				view.text("ShopTitle", "The potion counter", "title"),
				rail,
				view.text("Order", function(use: any)
					local order = orders[use(customer)]
					return if order
						then `{order.name}: “{order.note}”`
						else "Every customer served. Your day is complete!"
				end, "heading"),
				cauldron,
				view.text("Batch", function(use: any)
					return if use(quantity) == 0
						then "Empty cauldron · Add ingredients from the shelf below"
						else `{use(quantity)} portions of {byId[use(selected)].ingredient}`
				end),
				UI.Grid "IngredientShelf" { columns = 3, gap = "s", cellHeight = 76, table.unpack(ingredients) },
				C.show(function(use: any)
					return use(phase) == "brewing"
				end, function()
					return UI.ProgressView "BrewProgress" { label = "Brewing", value = progress, showValue = true }
				end),
				view.actions({
					view.button("Brew", "Brew the order", brew, function(use: any)
						return use(phase) == "mixing" and use(quantity) > 0 and use(customer) <= #orders
					end),
					serveButton,
					view.button("EmptyCauldron", "Empty cauldron", function()
						quantity:set(0)
						notice:set("Ready for fresh ingredients.")
					end, function(use: any)
						return use(phase) == "mixing"
					end),
				}),
				view.text("ShopNotice", notice),
				UI.Divider {},
				view.actions({
					view.button("OpenRecipes", "Recipe book", function()
						bookOpen:set(true)
					end),
					view.button("OpenLedger", function(use: any)
						return `{use(coins)} coins · Day's takings`
					end, function()
						ledgerOpen:set(true)
					end),
				}),
			}
		end
		local function book()
			local children = {}
			for _, recipe in recipes do
				table.insert(
					children,
					UI.VStack {
						width = "fill",
						gap = "s",
						view.text(recipe.id .. "Title", recipe.label, "heading"),
						view.text(
							recipe.id .. "Recipe",
							recipe.ingredient .. " + spring water\n" .. recipe.price .. " coins per bottle"
						),
						view.button("Choose_" .. recipe.id, "Use this recipe", function()
							selected:set(recipe.id)
							quantity:set(0)
							bookOpen:set(false)
							notice:set(recipe.label .. ": add " .. recipe.ingredient .. " from the shelf.")
						end, function(use: any)
							return use(phase) == "mixing"
						end),
						UI.Divider {},
					}
				)
			end
			return view.page(
				"RecipeBook",
				"A well-thumbed recipe book",
				"Good things come from simple ingredients.",
				children
			)
		end
		local function accounts()
			return view.page(
				"LedgerPage",
				"Today's takings",
				"Each completed order earns coins. Start a new day whenever you like.",
				{
					view.text("TotalCoins", function(use: any)
						return `{use(coins)} coins`
					end, "title"),
					C.show(function(use: any)
						return #use(ledger) == 0
					end, function()
						return view.text("EmptyLedger", "The first sale is always the sweetest.")
					end),
					C.keyed({
						from = ledger,
						key = function(item)
							return item.id
						end,
						render = function(current)
							return view.text("Sale" .. current:peek().id, function(use: any)
								local sale = use(current)
								return `{sale.name} · {sale.quantity} × {sale.recipe} · +{sale.earned}`
							end)
						end,
					}),
					view.button("NewDay", "Start a new day", reset),
				}
			)
		end
		return {
			screen = function()
				return Host.Frame "PotionShopRoot" {
					Size = D2.fromScale(1, 1),
					BackgroundTransparency = 1,
					shop(),
					UI.Sheet "RecipeBookSheet" {
						title = "Recipe book",
						isPresented = bookOpen,
						closeButton = true,
						detent = C.cell("large"),
						content = book,
					},
					UI.Sheet "LedgerSheet" {
						title = "Today's takings",
						isPresented = ledgerOpen,
						closeButton = true,
						detent = C.cell("large"),
						content = accounts,
					},
				}
			end,
			report = function()
				return {
					customer = customer:peek(),
					coins = coins:peek(),
					phase = phase:peek(),
					progress = progress:peek(),
					sales = #ledger:peek(),
					portions = quantity:peek(),
				}
			end,
			brew = brew,
			serve = serve,
			advance = advance,
			reset = reset,
			addIngredient = addIngredient,
			model = { recipe = selected, quantity = quantity, bookOpen = bookOpen, ledgerOpen = ledgerOpen },
		}
	end,
}
