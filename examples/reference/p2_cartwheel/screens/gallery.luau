--!strict
-- POTIONS — the gallery (spec §8): a grid where tiles read, a table where
-- columns do, one selection signal across both, and a COMPOSITE sort whose
-- second control appears only when the first one needs it.
--
-- The conditional secondary is the interesting part: Popularity needs a
-- timeframe, Attribute needs an axis, Name needs nothing — so the toolbar's
-- second control is a `When`, not a permanently-present picker that means
-- nothing two thirds of the time.
local data = require("../content/data")
local parts = require("./parts")

local gallery = {}

function gallery.new(app: any): any
	local UI = app.UI
	local Compose = app.Compose
	local S = app.S
	local Facet = app.Facet
	local stats = app.services.stats

	local self: any = {}

	-- ---- presentation state --------------------------------------------------
	local layout = Compose.cell("icons")
	local sortKey = Compose.cell("popularity")
	local timeframe = Compose.cell("today")
	local axisKey = Compose.cell("spark")
	local query = Compose.cell("")
	local selected = Compose.cell("")
	self.layout = layout
	self.sortKey = sortKey
	self.timeframe = timeframe
	self.axisKey = axisKey
	self.query = query
	self.selected = selected

	local function searchText(potion: any): string
		local parts_ = { potion.name }
		for _, id in { potion.base, potion.essence, potion.garnish } do
			local ingredient = data.ingredientById(id)
			if ingredient ~= nil then
				table.insert(parts_, ingredient.name)
			end
		end
		return string.lower(table.concat(parts_, " "))
	end

	local rows = Compose.formula(function(use)
		use(stats.version)
		local text = string.lower(use(query))
		local key = use(sortKey)
		local frame = use(timeframe)
		local axisName = use(axisKey)
		local axis = 1
		for index, name in data.ATTRIBUTES :: any do
			if name == axisName then
				axis = index
			end
		end
		local out: { any } = {}
		for _, potion in data.potions :: any do
			if text == "" or string.find(searchText(potion), text, 1, true) ~= nil then
				table.insert(out, potion)
			end
		end
		table.sort(out, function(a, b)
			if key == "name" then
				if a.name == b.name then
					return a.index < b.index
				end
				return a.name < b.name
			elseif key == "attribute" then
				local left = data.attributesOf(a.base, a.essence, a.garnish)[axis]
				local right = data.attributesOf(b.base, b.essence, b.garnish)[axis]
				if left == right then
					return a.index < b.index
				end
				return left > right
			end
			local left = stats.bottlesFor(a.id, frame)
			local right = stats.bottlesFor(b.id, frame)
			if left == right then
				return a.index < b.index
			end
			return left > right
		end)
		return out
	end)
	self.rows = rows

	-- ---- toolbar -------------------------------------------------------------

	-- The page is built per visit: a node belongs to the mount that made it.
	local function buildPage(): any
		local layoutPicker = UI.Picker("Layout")({
			label = S.t("gallery.layout"),
			options = {
				{ value = "icons", label = S.t("gallery.icons") },
				{ value = "list", label = S.t("gallery.list") },
			},
			selected = layout,
			-- a view switch: both words stay on screen (the picker round's automatic
			-- style would fold two options into a menu on a phone)
			style = "segmented",
		})

		--[[ NO FACTS WIRED, AND THAT IS THE POINT (ADAPT-1, 2026-08-18). This wired
		`sizeClass` and — like all five PopupButton sites in this repository — never
		wired `interactionClasses`, so `touchLive` was false forever and the
		touch->SHEET rung, the reference platform's own default, fired nowhere. Both
		facts now come from the surface's own environment, so a thumb gets the
		bottom sheet with its larger rows and a mouse keeps the anchored plate. The
		gallery's dump reports which one resolved, and the spec pins both. ]]
		local sortMenu = UI.Picker("Sort")({
			options = {
				{ value = "popularity", label = S.t("gallery.sortPopularity") },
				{ value = "name", label = S.t("gallery.sortName") },
				{ value = "attribute", label = S.t("gallery.sortAttribute") },
			},
			selected = sortKey,
		})

		local timeframePicker = UI.Picker("Timeframe")({
			options = {
				{ value = "today", label = S.t("time.today") },
				{ value = "week", label = S.t("time.week") },
				{ value = "month", label = S.t("time.month") },
				{ value = "year", label = S.t("time.year") },
			},
			selected = timeframe,
			sizeClass = app.state.sizeClass,
		})

		local axisOptions: { any } = {}
		for index, name in data.ATTRIBUTES :: any do
			table.insert(axisOptions, { value = name, label = parts.attributeName(app, index) })
		end
		-- the same, one screen over: the facts arrive with the surface (ADAPT-1)
		local axisMenu = UI.Picker("Axis")({
			options = axisOptions,
			selected = axisKey,
		})

		local search = UI.TextInput("Search")({
			value = query,
			placeholder = S.t("gallery.search"),
			clearButtonMode = "whileEditing",
			env = app.env,
			actionSystem = app.actionSystem,
		})

		local sortIsPopularity = Compose.formula(function(use)
			return use(sortKey) == "popularity"
		end)
		local sortIsAttribute = Compose.formula(function(use)
			return use(sortKey) == "attribute"
		end)
		local isEmpty = Compose.formula(function(use)
			return #(use(rows) :: any) == 0
		end)
		local isGrid = Compose.formula(function(use)
			return use(layout) == "icons"
		end)
		local isList = Compose.formula(function(use)
			return use(layout) ~= "icons"
		end)

		local toolbar = UI.VStack("Toolbar")({
			gap = "s",
			width = UI.fill(),

			UI.HStack("Primary")({
				gap = "s",
				align = "center",
				width = UI.fill(),

				layoutPicker,
				sortMenu,
				UI.Button("NewPotion")({
					label = S.t("gallery.newPotion"),
					compactLabel = { icon = "increment" },
					onActivate = function()
						app.actions.openScratch()
					end,
				}),
			}),
			UI.HStack("Secondary")({
				gap = "s",
				align = "center",
				width = UI.fill(),

				app.when("TimeframeWhen")({
					condition = sortIsPopularity,
					thenView = function()
						return timeframePicker
					end,
				}),
				app.when("AxisWhen")({
					condition = sortIsAttribute,
					thenView = function()
						return axisMenu
					end,
				}),
				UI.VStack("SearchSlot")({
					width = UI.fill(),
					search,
				}),
			}),
		})

		-- ---- the grid form -------------------------------------------------------

		local function strongestCaption(potion: any): string
			local attrs = data.attributesOf(potion.base, potion.essence, potion.garnish)
			local axis = data.strongestAxis(attrs)
			return parts.attributeName(app, axis) .. " " .. tostring(attrs[axis])
		end

		local gridCells: { any } = {}
		local selectedMemos: { any } = {}
		for _, potion in data.potions :: any do
			local isSelected = Compose.formula(function(use)
				return use(selected) == potion.id
			end)
			table.insert(selectedMemos, isSelected)
			table.insert(
				gridCells,
				UI.Button("Cell_" .. potion.id)({
					label = potion.name,
					gap = "xs",
					-- THE CELL TAKES ITS COLUMN. A grid cell sizes to its own content by
					-- default, and a `fill` child inside a content-measuring Button
					-- measures against an offer of zero — so the tile collapsed to its
					-- own padding (24px) and the solver said "nothing inside this can
					-- draw". The Button fills; the stack inside it hugs.
					width = UI.fill(),
					selected = isSelected,
					onActivate = function()
						selected:set(potion.id)
						app.actions.openPotion(potion.id)
					end,

					-- ONE child, and it is a VStack: a Button lays its content out as a
					-- ROW, so a mark-over-name-over-caption tile has to say so (three
					-- bare children overflowed a 96px column by 112px, which the
					-- solver reported on every viewport)
					UI.VStack("Cell")({
						gap = "xs",
						align = "center",

						parts.potionMark(app, "Mark", potion, "controls.image.defaultSize"),
						UI.Text("Name")({
							text = potion.name,
							textSize = "label",
							textAlign = "center",
							lineLimit = 2,
							disclose = true,
						}),
						UI.Text("Strongest")({
							text = strongestCaption(potion),
							textSize = "caption",
							role = "secondary",
							textAlign = "center",
							lineLimit = 1,
						}),
					}),
				})
			)
		end

		-- the cells are authored once and REORDERED by the memo: a keyed ForEach
		-- keeps each cell's mounted identity across a re-sort
		local cellById: { [string]: any } = {}
		for index, potion in data.potions :: any do
			cellById[potion.id] = gridCells[index]
		end

		--[[ THE TILE MINIMUM SCALES WITH THE TILE (B-6e's consequence, 2026-08-21).

		`app.cartwheel.tileMin` is 96 device px and everything INSIDE a tile is a
		theme metric, so on a Large display the mark grew to 72px and the button's
		padding to 18 a side — 108px of content asking for a 96px minimum — while the
		column minimum stayed exactly where a phone left it. That is
		the fixed-px-height class read across the distance
		axis: a fixed px number holding content that is not fixed.

		It went unreported until the framework capped the ten-foot content lane
		(controller ruling R14): the lane went from 1292px to 900, the columns
		narrowed with it, and the tile finally ran 7px past its own box on all 17
		visible cells. The cap did not cause this — it stopped the extra pixels from
		hiding it, which is what the always-on overflow sweep is for.

		THE FIX USED TO BE A SCOPE-OWNED MEMO THAT MULTIPLIED BY `metricScale`, and
		it was the wrong shape twice over: it was a ladder this proof had to
		remember to climb — and three of its four neighbours (`chartH`, `heroH`,
		`previewMin`) never got the same treatment, so a television measured a 144px
		tile minimum inside a 160px chart band. The number is a declared app metric
		now, so the framework applies the factor once, to all seven, in
		the place that owns the ladder.

		THE MEMO SURVIVES, DOING SOMETHING ELSE. `Grid.minColumnWidth` takes a px
		number or `"intrinsic"` — it is the one dimension-shaped prop in the library
		that does not accept a theme metric NAME (booked as a follow-up; every other
		call site in this proof spells `"app.cartwheel.*"` directly). So this READS
		the resolved value off the live snapshot rather than deriving it: no
		arithmetic, no factor, and a theme that moves `app.cartwheel.tileMin` moves
		this grid with it. ]]
		-- OWNED (RR-8): a memo the screen builds per mount and nobody disposes is one
		-- leaked memo per build cycle, which `cartwheel_spec`'s registry-neutrality
		-- case counts. `app.scope` is the app's own, and it caught this immediately.
		local tileMin = Compose.formula(function(use)
			local m: any = use(app.env:get("themeMetrics"))
			local group = if type(m) == "table" and type(m.app) == "table" then m.app.cartwheel else nil
			-- the fallback is the DECLARATION, never a literal: a second copy of 96 here
			-- is the very drift the whole channel exists to remove
			return if type(group) == "table" and type(group.tileMin) == "number"
				then group.tileMin
				else app.appMetrics.tileMin
		end)

		local gridForm = UI.Grid("Tiles")({
			minColumnWidth = tileMin,
			gap = "m",

			app.forEach("Cells")({
				items = rows,
				key = function(item)
					return item.id
				end,
				row = function(item)
					return cellById[item.id]
				end,
			}),
		})

		-- ---- the table form ------------------------------------------------------

		local tableSelected = Compose.cell({} :: { [string]: boolean })
		local tableControl = UI.Table("PotionTable")({
			selectedKeys = tableSelected,
			rows = rows,
			key = function(item)
				return item.id
			end,
			columns = {
				{
					id = "potion",
					title = S.t("gallery.colPotion"),
					width = UI.fill(1.6),
					cell = function(row)
						local item = row:peek()
						return UI.HStack("PotionCell")({
							gap = "xs",
							align = "center",
							width = UI.fill(),

							parts.potionMark(app, "Mark", item, "iconSizes.large"),
							UI.Text("Name")({
								text = item.name,
								textSize = "label",
								width = UI.fill(),
								lineLimit = 1,
								disclose = true,
							}),
						})
					end,
					sortable = true,
					disclose = true,
				},
				{
					id = "strongest",
					title = S.t("gallery.colStrongest"),
					width = UI.fill(),
					value = strongestCaption,
				},
			},
			selection = "single",
			header = true,
			scrolls = true,
			rowGap = "controls.table.rowGap",
			env = app.env,
		})

		-- one selection signal across both forms: the table writes it, and the grid
		-- cell's `selected` binding reads it
		local unsubscribe = app.observe(tableSelected, function(keys: any)
			local first: string? = nil
			for key, on in keys :: any do
				if on and (first == nil or key < first) then
					first = key
				end
			end
			if first ~= nil and first ~= selected:peek() then
				selected:set(first)
				app.actions.openPotion(first)
			end
		end)

		local page = UI.VStack("Potions")({
			padding = "m",
			gap = "s",
			width = UI.fill(),
			height = UI.fill(),

			UI.Text("Title")({ text = S.t("gallery.title"), textSize = "title" }),
			toolbar,
			app.when("EmptyWhen")({
				condition = isEmpty,
				thenView = function()
					return parts.empty(app, "Empty", S.t("gallery.empty"))
				end,
			}),
			app.when("GridWhen")({
				condition = isGrid,
				thenView = function()
					return UI.ZStack("GridHost")({
						canvasGroup = true,
						overflow = "clip",
						width = UI.fill(),
						height = UI.fill(),

						UI.ScrollView("GridScroll")({
							axis = "y",
							width = UI.fill(),
							height = UI.fill(),
							gridForm,
						}),
					})
				end,
				transition = { enter = "fade", class = "container" },
			}),
			app.when("TableWhen")({
				condition = isList,
				thenView = function()
					return UI.ZStack("TableHost")({
						canvasGroup = true,
						overflow = "clip",
						width = UI.fill(),
						height = UI.fill(),
						tableControl,
					})
				end,
				transition = { enter = "fade", class = "container" },
			}),
		})

		return page
	end

	self.view = buildPage

	function self.dump(): any
		local order: { string } = {}
		for _, potion in rows:peek() :: any do
			table.insert(order, potion.id)
		end
		return {
			layout = layout:peek(),
			sort = sortKey:peek(),
			timeframe = timeframe:peek(),
			axis = axisKey:peek(),
			query = query:peek(),
			selected = selected:peek(),
			order = order,
			-- WHICH STYLE AND POPUP THE UNWIRED PICKER RESOLVED (ADAPT-1, and the
			-- picker round): the menu family on a thumb and on a pointer, its
			-- popover or sheet by the list's length — decided by the environment
			-- this screen never had to pass in
		}
	end

	return self
end

return gallery
