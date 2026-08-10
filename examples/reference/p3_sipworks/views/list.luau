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

local metrics = require("../content/metrics")
local parts = require("./parts")

local list = {}

-- ---------------------------------------------------------------------------
-- the shared row
-- ---------------------------------------------------------------------------

function list.blendRow(app: any, blendId: string, itemScope: any, opts: any): any
	local UI = app.UI
	local core = app.core
	local catalog = app.services.catalog
	local i18n = app.services.i18n
	local blend = catalog.blend(blendId)
	local options = opts or {}

	local function own(readable: any): any
		itemScope:own(function()
			readable:dispose()
		end)
		return readable
	end

	local title = own(core:memo(function(use)
		return i18n.nameAt(use(i18n.locale), "blend", blendId, blend.title)
	end))
	local botanicalLine = own(core:memo(function(use)
		local locale = use(i18n.locale)
		local names: { string } = {}
		for _, botanicalId in catalog.tileBotanicals(blendId) do
			local botanical = catalog.botanical(botanicalId)
			table.insert(names, i18n.nameAt(locale, "botanical", botanicalId, botanical.name))
		end
		return i18n.listAt(locale, names)
	end))
	local caffeineLine = own(core:memo(function(use)
		return i18n.at(use(i18n.locale), "row.caffeine", { n = catalog.caffeineMg(blendId) })
	end))
	local selected = own(core:memo(function(use)
		return use(app.state.selectedBlendId) == blendId
	end))

	local children: { any } = {
		UI.Button({
			id = "Open",
			label = title,
			selected = selected,
			width = metrics.fill,
			padding = "s",
			gap = "m",
			align = "center",
			onActivate = function()
				options.onActivate(blendId)
			end,
			children = {
				parts.artPlate(app, "blend", blendId, {
					width = metrics.fixed(metrics.rowArt),
					height = metrics.fixed(metrics.rowArt),
				}),
				UI.VStack({
					id = "Lines",
					gap = "xs",
					width = metrics.fill,
					children = {
						UI.Text({ id = "Title", text = title, textSize = "strong", lineLimit = 1, disclose = true }),
						UI.Text({
							id = "Botanicals",
							text = botanicalLine,
							role = "secondary",
							textSize = "caption",
							lineLimit = 2,
							disclose = true,
						}),
						UI.Text({
							id = "Caffeine",
							text = caffeineLine,
							role = "secondary",
							textSize = "caption",
							lineLimit = 1,
							disclose = true,
						}),
					},
				}),
			},
		}),
	}

	-- THE ONE PLACE THE FAVORITE VERB EXISTS, and the compact-link shell hides
	-- it here (spec §11: "no dead verbs"). `entry` is a build-time fact for a
	-- shell, so this is a Lua branch rather than a `UI.When` over a constant.
	if app.entry == "full" then
		table.insert(children, list.favoriteButton(app, blendId, itemScope, "Favorite"))
	end

	return UI.ZStack({
		-- the ForEach declares `enter = "materialize"`, which fades — so the
		-- region's child has to BE the fade group (the framework refuses any
		-- other node, naming this fix)
		id = "Row-" .. blendId,
		canvasGroup = true,
		width = metrics.fill,
		children = {
			UI.HStack({ id = "Line", gap = "s", align = "center", width = metrics.fill, children = children }),
		},
	})
end

-- the favorite affordance: a circle Button whose MARK changes with the state,
-- so the fact is carried by form and not by hue alone
function list.favoriteButton(app: any, blendId: string, scope: any, id: string): any
	local UI = app.UI
	local core = app.core
	local i18n = app.services.i18n
	local favorites = app.services.favorites
	local blend = app.services.catalog.blend(blendId)

	local function own(readable: any): any
		scope:own(function()
			readable:dispose()
		end)
		return readable
	end

	local isFavorite = own(core:memo(function(use)
		return use(favorites.set)[blendId] == true
	end))
	local label = own(core:memo(function(use)
		local locale = use(i18n.locale)
		local key = if use(isFavorite) then "row.unfavorite" else "row.favorite"
		return i18n.at(locale, key, { title = i18n.nameAt(locale, "blend", blendId, blend.title) })
	end))
	local mark = own(core:memo(function(use)
		return if use(isFavorite) then "*" else "+"
	end))

	return UI.Button({
		id = id,
		label = label,
		shape = "circle",
		selected = isFavorite,
		onActivate = function()
			app.commands.toggleFavorite(blendId)
		end,
		children = { UI.Text({ id = "Mark", text = mark, textSize = "strong", textAlign = "center" }) },
	})
end

-- ---------------------------------------------------------------------------
-- search + botanical suggestions, shared across every section
-- ---------------------------------------------------------------------------

function list.searchBar(app: any): any
	local UI = app.UI
	local core = app.core
	local i18n = app.services.i18n
	local catalog = app.services.catalog
	local field = app.search

	local suggestions = app.own(core:memo(function(use)
		local locale = use(i18n.locale)
		return catalog.suggestions(use(app.state.search), function(kind, id, text)
			return i18n.nameAt(locale, kind, id, text)
		end, 6)
	end))
	local open = app.own(core:memo(function(use)
		return use(field.api.editing) and #use(suggestions) > 0
	end))

	return UI.VStack({
		id = "SearchBar",
		gap = "xs",
		width = metrics.fill,
		children = {
			field.blueprint,
			UI.When({
				id = "Suggestions",
				condition = open,
				transition = { enter = "fade" },
				thenView = function()
					return UI.ZStack({
						id = "SuggestBox",
						canvasGroup = true,
						width = metrics.fill,
						children = {
							UI.VStack({
								id = "SuggestList",
								gap = "xs",
								width = metrics.fill,
								surface = "raised",
								padding = "xs",
								children = {
									UI.ForEach({
										id = "Rows",
										items = suggestions,
										key = function(id: string)
											return id
										end,
										row = function(botanicalId: string, itemScope: any)
											local botanical = catalog.botanical(botanicalId)
											local label = core:memo(function(use)
												return i18n.nameAt(
													use(i18n.locale),
													"botanical",
													botanicalId,
													botanical.name
												)
											end)
											itemScope:own(function()
												label:dispose()
											end)
											return UI.Button({
												id = "Suggest-" .. botanicalId,
												label = label,
												width = metrics.fill,
												onActivate = function()
													app.commands.acceptSuggestion(botanicalId)
												end,
											})
										end,
									}),
								},
							}),
						},
					})
				end,
			}),
		},
	})
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
		UI.ForEach({
			id = "Rows",
			items = spec.items,
			key = function(id: string)
				return id
			end,
			transition = { enter = "materialize" },
			row = function(blendId: string, itemScope: any)
				return list.blendRow(app, blendId, itemScope, { onActivate = spec.onActivate })
			end,
		})
	)
	return UI.ScrollView({
		id = spec.id,
		axis = "y",
		gap = "xs",
		width = metrics.fill,
		height = metrics.fill,
		children = children,
	})
end

return list
