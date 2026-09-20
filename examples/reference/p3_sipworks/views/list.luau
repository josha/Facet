--!strict
-- ONE row blueprint, three sections, two entry flows (spec §6, §11).
--
-- `blendRow` is the shared factory the Menu, Favorites, Blend Book and the
-- compact-link shell all reach — that sharing is a suite pin, not a claim.
--
-- The row is an `HStack` of two controls rather than the spec's single
-- `Button` with a trailing favorite Button inside it: a focusable inside a
-- Button's `children` is REFUSED at construction (it would be a second focus
-- site and a double Activate), so the framework's rule decides the shape. The
-- player-visible result is identical, and the favorite affordance is still the
-- visible-control adaptation of the reference's swipe action (ledger §A) — no
-- swipe gesture is built, on any input class.

local dims = require("../content/dims")
local parts = require("./parts")

local list = {}

-- ---------------------------------------------------------------------------
-- the shared row
-- ---------------------------------------------------------------------------

function list.blendRow(app: any, blendId: string, opts: any): any
	local function BlendRow(): any
		local localeNow = app.services.i18n.locale
		local selectedBlend = app.state.selectedBlendId
		-- Custom row/circle geometry uses the primitive Button; mounted getters
		-- and cleanup still belong to this component.
		local UI = app.UI
		local catalog = app.services.catalog
		local i18n = app.services.i18n
		local blend = catalog.blend(blendId)
		local options = opts or {}
		local title = app.Compose.formula(function(use)
			return i18n.nameAt(use(localeNow), "blend", blendId, blend.title)
		end)
		local botanicalLine = app.Compose.formula(function(use)
			local locale = use(localeNow)
			local names: { string } = {}
			for _, botanicalId in catalog.tileBotanicals(blendId) do
				local botanical = catalog.botanical(botanicalId)
				table.insert(names, i18n.nameAt(locale, "botanical", botanicalId, botanical.name))
			end
			return i18n.listAt(locale, names)
		end)
		local caffeineLine = app.Compose.formula(function(use)
			return i18n.at(use(localeNow), "row.caffeine", { n = catalog.caffeineMg(blendId) })
		end)
		local selected = app.Compose.formula(function(use)
			return use(selectedBlend) == blendId
		end)
		local children: { any } = {
			UI.Button("Open")({
				label = title,
				selected = selected,
				width = dims.fill,
				padding = "s",
				gap = "m",
				align = "center",
				onActivate = function()
					options.onActivate(blendId)
				end,
				parts.artPlate(app, "blend", blendId, {
					width = dims.fixed("app.sip.rowArt"),
					height = dims.fixed("app.sip.rowArt"),
				}),
				UI.VStack("Lines")({
					gap = "xs",
					width = dims.fill,
					UI.Text("Title")({ text = title, textSize = "strong", lineLimit = 1, disclose = true }),
					UI.Text("Botanicals")({
						text = botanicalLine,
						role = "secondary",
						textSize = "caption",
						lineLimit = 2,
						disclose = true,
					}),
					UI.Text("Caffeine")({
						text = caffeineLine,
						role = "secondary",
						textSize = "caption",
						lineLimit = 1,
						disclose = true,
					}),
				}),
			}),
		}
		if app.entry == "full" then
			table.insert(children, list.favoriteButton(app, blendId, "Favorite"))
		end
		return UI.ZStack("Row-" .. blendId)({
			canvasGroup = true,
			width = dims.fill,
			UI.HStack("Line")(app.withChildren({ gap = "s", align = "center", width = dims.fill }, children)),
		})
	end
	return BlendRow()
end

-- the favorite affordance: a circle Button whose MARK changes with the state,
-- so the fact is carried by form and not by hue alone
function list.favoriteButton(app: any, blendId: string, id: string): any
	local function FavoriteButton(): any
		local localeNow = app.services.i18n.locale
		local favoriteSet = app.services.favorites.set
		-- Custom row/circle geometry uses the primitive Button; mounted getters
		-- and cleanup still belong to this component.
		local UI = app.UI
		local i18n = app.services.i18n
		local favorites = app.services.favorites
		local blend = app.services.catalog.blend(blendId)
		local isFavorite = app.Compose.formula(function(use)
			return use(favoriteSet)[blendId] == true
		end)
		local label = app.Compose.formula(function(use)
			local locale = use(localeNow)
			local key = if use(isFavorite) then "row.unfavorite" else "row.favorite"
			return i18n.at(locale, key, { title = i18n.nameAt(locale, "blend", blendId, blend.title) })
		end)
		local mark = app.Compose.formula(function(use)
			return if use(isFavorite) then "*" else "+"
		end)
		return UI.Button(id)({
			label = label,
			shape = "circle",
			selected = isFavorite,
			onActivate = function()
				app.commands.toggleFavorite(blendId)
			end,
			UI.Text("Mark")({ text = mark, textSize = "strong", textAlign = "center" }),
		})
	end
	return FavoriteButton()
end

-- ---------------------------------------------------------------------------
-- search + botanical suggestions, shared across every section
-- ---------------------------------------------------------------------------

function list.searchBar(app: any): any
	local function SearchBar(): any
		local UI = app.UI
		local i18n, catalog = app.services.i18n, app.services.catalog
		local locale, query = i18n.locale, app.state.search
		local editing = app.searchEditing
		local suggestions = app.Compose.formula(function(use)
			local currentLocale = use(locale)
			return catalog.suggestions(use(query), function(kind, id, text)
				return i18n.nameAt(currentLocale, kind, id, text)
			end, 6)
		end)
		return UI.VStack("SearchBar")({
			gap = "xs",
			width = dims.fill,
			app.searchField(),
			app.when("Suggestions")({
				condition = function(use)
					return use(editing) and #use(suggestions) > 0
				end,
				thenView = function()
					return UI.ZStack("SuggestBox")({
						canvasGroup = true,
						width = dims.fill,
						UI.VStack("SuggestList")({
							gap = "xs",
							width = dims.fill,
							surface = "raised",
							padding = "xs",
							app.forEach("Rows")({
								items = suggestions,
								key = function(id)
									return id
								end,
								row = function(id: string)
									local botanical = catalog.botanical(id)
									return UI.Button("Suggest-" .. id)({
										width = dims.fill,
										label = function(use)
											return i18n.nameAt(use(locale), "botanical", id, botanical.name)
										end,
										onActivate = function()
											app.commands.acceptSuggestion(id)
										end,
									})
								end,
							}),
						}),
					})
				end,
			}),
		})
	end
	return SearchBar()
end

-- ---------------------------------------------------------------------------
-- the scrolling list itself
-- ---------------------------------------------------------------------------

-- `spec.leading` rides INSIDE the scroller (the Blend Book's unlock card does).
-- Above it, in the pane's own stack, it would have eaten the list's whole height
-- on a phone — the solver reported the list solving to 0px tall and the pane
-- overflowing by 161px.
function list.blendList(app: any, spec: any): any
	local UI = app.UI
	local children: { any } = {}
	if spec.leading ~= nil then
		table.insert(children, spec.leading)
	end
	table.insert(
		children,
		app.forEach("Rows")({
			items = spec.items,
			key = function(id: string)
				return id
			end,
			transition = { enter = "materialize" },
			row = function(blendId: string)
				return list.blendRow(app, blendId, { onActivate = spec.onActivate })
			end,
		})
	)
	return UI.ScrollView(spec.id)(app.withChildren({
		axis = "y",
		gap = "xs",
		width = dims.fill,
		height = dims.fill,
	}, children))
end

return list
