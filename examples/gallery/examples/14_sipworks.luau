--!strict

type ExampleContext = typeof(require("@repo/examples/types").Context)
type Child = typeof(require("@repo/tools/typecheck/aliases").Child)
type Use = typeof(require("@repo/tools/typecheck/aliases").Use)
type SipworksModule = typeof(require("@repo/examples/reference/p3_sipworks"))
type Entry = { id: string, value: string? }
local searchPresentation: "search" = "search"
local loadSipworks: (ModuleScript | string) -> SipworksModule = require
local makeView = require("./showcase_view")
local art = require("./showcase_art")
return {
	title = "Sipworks",
	build = function(ctx: ExampleContext)
		local original = loadSipworks(
			if script and ctx.find then ctx.find("reference", "p3_sipworks") else "../../reference/p3_sipworks"
		)
		local reference = original.build(ctx)
		local model, catalog = reference.model, reference.model.catalog
		local UI, Host, C = ctx.UI, ctx.Host, ctx.Compose
		local D2, V2, E = ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
		local view = makeView(ctx)
		local noEntries: { Entry } = {}
		local path, query, servings = C.cell(noEntries), C.cell(""), C.cell(1)
		local gathered: { [string]: typeof(C.cell(false)) } = {}
		local indices: { [string]: number } = {}
		local env = UI.environment()
		local wideAt, columnWidth = env.scaled(830), env.scaled(190)
		for index, blend in catalog.blends do
			indices[blend.id] = index
		end
		local function open(id: string)
			path:set({ { id = "recipe", value = id } })
		end
		local function push(kind: string, id: string)
			local nextPath = table.clone(path:peek())
			table.insert(nextPath, { id = kind, value = id })
			path:set(nextPath)
		end
		local function back()
			local nextPath = table.clone(path:peek())
			table.remove(nextPath)
			path:set(nextPath)
		end
		local function picture(id: string, height: number)
			local index = indices[id] - 1
			local col, row = index % 3 + 1, math.floor(index / 3) + 1
			return UI.Image "TeaIllustration" {
				image = art.teas,
				scaleMode = if height >= 240 then "fit" else "crop",
				Size = D2.new(1, 0, 0, height),
				ImageRectOffset = V2.new(art.teaColumns[col], art.teaRows[row]),
				ImageRectSize = V2.new(
					art.teaColumns[col + 1] - art.teaColumns[col],
					art.teaRows[row + 1] - art.teaRows[row]
				),
			}
		end
		local function recipe(entry: Entry?)
			local blend = assert(catalog.blend(assert(entry and entry.value)))
			local related: { Child } = {}
			for _, measure in catalog.recipeMeasures(blend.id) do
				local ingredient = assert(catalog.botanical(measure.botanicalId))
				local key = blend.id .. "/" .. ingredient.id
				gathered[key] = gathered[key] or C.cell(false)

				if not ingredient.water then
					table.insert(
						related,
						view.button("Botanical_" .. ingredient.id, ingredient.name .. " →", function()
							push("ingredient", ingredient.id)
						end)
					)
				end
			end
			return UI.ScrollView "RecipeDetail" {
				padding = "m",
				gap = "m",
				picture(blend.id, 240),
				view.text("RecipeTitle", blend.title, "title"),
				view.text("Description", blend.paragraphs[1].text),
				view.actions({
					UI.Toggle "FavoriteRecipe" {
						label = "Saved",
						presentation = "button",
						corners = "pill",
						value = function(use: Use)
							use(model.favorites.set)
							return model.favorites.isFavorite(blend.id)
						end,
						onChange = function()
							model.favorites.toggle(blend.id)
						end,
					},
					UI.CollapsibleView "BrewingNotes" {
						label = "Brewing notes",
						expanded = C.cell(false),
						content = function(): Instance
							local rows = {
								view.text(
									"SteepTime",
									`Steep for {catalog.steepMinutes(blend.id)} minutes.`,
									"heading"
								),
							}
							for _, paragraph in blend.paragraphs do
								table.insert(rows, view.text("Note", paragraph.text))
							end
							return UI.VStack {
								width = "fill",
								gap = "m",
								table.unpack(rows),
							}
						end,
					},
				}),
				UI.Stepper "Servings" { label = "Cups to make", value = servings, min = 1, max = 8, step = 1 },
				UI.DisclosureGroup "Ingredients" {
					label = "Gather your ingredients",
					expanded = C.cell(true),
					content = function(): Instance
						local ingredientRows: { Instance } = {}
						for _, measure in catalog.recipeMeasures(blend.id) do
							local ingredient = assert(catalog.botanical(measure.botanicalId))
							local key = blend.id .. "/" .. ingredient.id
							table.insert(
								ingredientRows,
								UI.Toggle("Gather_" .. ingredient.id)({
									value = gathered[key],
									presentation = "checkbox",
									label = function(use: Use)
										return `{measure.value * use(servings)} {measure.unit} · {ingredient.name}`
									end,
								})
							)
						end
						return UI.VStack {
							width = "fill",
							gap = "s",
							table.unpack(ingredientRows),
						}
					end,
				},
				view.text("ExploreIngredients", "Explore the botanicals", "heading"),
				view.actions(related),
			}
		end
		local function ingredient(entry: Entry?)
			local botanical = assert(catalog.botanical(assert(entry and entry.value)))
			local recipes: { Child } = {}
			for _, blend in catalog.blends do
				if catalog.measureFor(blend.id, botanical.id) then
					table.insert(
						recipes,
						view.button("Related_" .. blend.id, blend.title .. " →", function()
							push("recipe", blend.id)
						end)
					)
				end
			end
			return UI.ScrollView "BotanicalDetail" {
				padding = "m",
				gap = "m",
				view.text("BotanicalTitle", botanical.name, "title"),
				view.text(
					"BotanicalDescription",
					`A teaspoon weighs about {botanical.gramsPerTsp} g. Steep for {botanical.steepMinutes} minutes.`
				),
				view.text("RelatedHeading", "Recipes with " .. botanical.name, "heading"),
				table.unpack(recipes),
			}
		end
		local function belongs(blend: { id: string }, category: string): boolean
			if category == "saved" then
				return model.favorites.isFavorite(blend.id)
			end
			if category == "herbal" then
				return catalog.caffeineMg(blend.id) == 0
			end
			if category == "black" then
				return catalog.measureFor(blend.id, "assam") ~= nil
			end
			if category == "green" then
				return catalog.measureFor(blend.id, "sencha") ~= nil or catalog.measureFor(blend.id, "oolong") ~= nil
			end
			return true
		end
		local function library(category: string)
			local width, gridWidth = C.cell(1000), C.cell(400)
			local wide = C.formula(function(use: Use)
				return use(width) >= use(wideAt)
			end)
			local visible = C.formula(function(use: Use)
				use(model.favorites.set)
				local found = {}
				for _, blend in catalog.blends do
					if
						belongs(blend, category)
						and catalog.matches(blend.id, use(query), function(_, _, name)
							return name
						end)
					then
						table.insert(found, blend)
					end
				end
				return found
			end)
			local function collection()
				return UI.Screen "RecipeLibrary" {
					padding = "m",
					gap = "m",
					view.text("LibraryIntro", "A recipe for every kind of afternoon."),
					UI.TextInput "FindRecipe" {
						presentation = searchPresentation,
						value = query,
						placeholder = "Find a blend or ingredient…",
					},
					C.show(function(use: Use)
						return #use(visible) == 0
					end, function()
						return view.text("NoRecipes", "No recipes here yet. Try another search or save a blend.")
					end),
					UI.VirtualGrid "RecipeGrid" {
						from = visible,
						key = "id",
						gap = 12,
						measure = true,
						itemSize = 240,
						columns = function(use: Use)
							return math.max(1, math.floor(use(gridWidth) / use(columnWidth)))
						end,
						Size = D2.new(1, 0, 0, 300),
						ref = function(node: ScrollingFrame)
							UI.fill().Parent = node
							view.observeWidth(gridWidth, node)
						end,
						recycle = false,
						render = function(current): GuiObject
							local blend = current:peek()
							return UI.Card("Recipe_" .. blend.id)({
								title = blend.title,
								caption = (function(): string
									local count = #catalog.tileBotanicals(blend.id)
									return `{catalog.steepMinutes(blend.id)} min · {count} {if count == 1
										then "botanical"
										else "botanicals"}`
								end)(),
								artwork = function()
									return picture(blend.id, 150)
								end,
								imageAspectRatio = 1.25,
								Size = D2.new(1, 0, 0, 0),
								AutomaticSize = E.AutomaticSize.Y,
								onActivate = function()
									open(blend.id)
								end,
							})
						end,
					},
				}
			end
			local function detailArea()
				return UI.NavigationStack "RecipeNavigation" {
					path = path,
					root = {
						title = "Recipe book",
						content = function(): Instance
							return UI.ScrollView {
								padding = "l",
								gap = "m",
								picture("lantern-oolong", 280),
								view.text("ChooseRecipe", "What will you brew?", "title"),
								view.text(
									"ChooseHint",
									"Choose a recipe. Follow its botanicals to discover another blend."
								),
								view.button("FeaturedRecipe", "Open Lantern Oolong", function()
									open("lantern-oolong")
								end),
							}
						end,
					},
					destinations = {
						recipe = { title = "Recipe", content = recipe },
						ingredient = { title = "Botanical", content = ingredient },
					},
				}
			end
			local root = Host.Frame "SipworksLibrary" {
				Size = D2.fromScale(1, 1),
				BackgroundTransparency = 1,
				C.show(wide, function()
					return Host.Frame "LibrarySplit" {
						Size = D2.fromScale(1, 1),
						BackgroundTransparency = 1,
						Host.Frame "CatalogColumn" {
							Size = D2.fromScale(0.46, 1),
							BackgroundTransparency = 1,
							collection(),
						},
						Host.Frame "DetailColumn" {
							Position = D2.fromScale(0.46, 0),
							Size = D2.fromScale(0.54, 1),
							BackgroundTransparency = 1,
							detailArea(),
						},
					}
				end, function()
					return UI.NavigationStack "RecipeNavigation" {
						path = path,
						root = { title = "Sipworks", content = collection },
						destinations = {
							recipe = { title = "Recipe", content = recipe },
							ingredient = { title = "Botanical", content = ingredient },
						},
					}
				end),
			}
			view.observeWidth(width, root)
			return root
		end
		local pages = {}
		for _, group in
			{
				{ "all", "All recipes" },
				{ "black", "Black tea" },
				{ "green", "Green & oolong" },
				{ "herbal", "Herbal" },
				{ "saved", "Saved" },
			}
		do
			table.insert(pages, {
				id = group[1],
				label = group[2],
				content = function(): Instance
					return library(group[1])
				end,
			})
		end
		local tabs = view.tabs("Sipworks", pages, function(): { [string]: unknown }
			return { path = path:peek(), servings = servings:peek(), favorites = model.favorites.ids() }
		end)
		return {
			screen = tabs.screen,
			select = tabs.select,
			report = tabs.report,
			model = { path = path, servings = servings, gathered = gathered, query = query, catalog = catalog },
			open = open,
			push = push,
			back = back,
		}
	end,
}
