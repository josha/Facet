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
local metrics = require("../content/metrics")
local parts = require("./parts")

local gallery = {}

function gallery.new(app: any): any
	local UI = app.UI
	local core = app.core
	local S = app.S
	local Facet = app.Facet
	local stats = app.services.stats

	local self: any = {}

	-- ---- presentation state --------------------------------------------------
	local layout = core:signal("icons")
	local sortKey = core:signal("popularity")
	local timeframe = core:signal("today")
	local axisKey = core:signal("spark")
	local query = core:signal("")
	local selected = core:signal("")
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

	local rows = core:memo(function(use)
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

	local layoutPicker = Facet.Controls.Picker(core, {
		id = "Layout",
		label = S.t("gallery.layout"),
		options = {
			{ value = "icons", label = S.t("gallery.icons") },
			{ value = "list", label = S.t("gallery.list") },
		},
		selected = layout,
		sizeClass = app.state.sizeClass,
	})

	--[[ NO FACTS WIRED, AND THAT IS THE POINT (ADAPT-1, 2026-08-18). This wired
		`sizeClass` and — like all five PopupButton sites in this repository — never
		wired `interactionClasses`, so `touchLive` was false forever and the
		touch->SHEET rung, the reference platform's own default, fired nowhere. Both
		facts now come from the surface's own environment, so a thumb gets the
		bottom sheet with its larger rows and a mouse keeps the anchored plate. The
		gallery's dump reports which one resolved, and the spec pins both. ]]
	local sortMenu = Facet.Controls.PopupButton(core, {
		id = "Sort",
		options = {
			{ id = "popularity", label = S.t("gallery.sortPopularity") },
			{ id = "name", label = S.t("gallery.sortName") },
			{ id = "attribute", label = S.t("gallery.sortAttribute") },
		},
		value = sortKey,
	})

	local timeframePicker = Facet.Controls.Picker(core, {
		id = "Timeframe",
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
		table.insert(axisOptions, { id = name, label = parts.attributeName(app, index) })
	end
	-- the same, one screen over: the facts arrive with the surface (ADAPT-1)
	local axisMenu = Facet.Controls.PopupButton(core, {
		id = "Axis",
		options = axisOptions,
		value = axisKey,
	})

	local search = Facet.Controls.TextInput(core, {
		id = "Search",
		value = query,
		placeholder = S.t("gallery.search"),
		clearButtonMode = "whileEditing",
		env = app.env,
		actionSystem = app.actionSystem,
	})

	local sortIsPopularity = core:memo(function(use)
		return use(sortKey) == "popularity"
	end)
	local sortIsAttribute = core:memo(function(use)
		return use(sortKey) == "attribute"
	end)
	local isEmpty = core:memo(function(use)
		return #(use(rows) :: any) == 0
	end)
	local isGrid = core:memo(function(use)
		return use(layout) == "icons"
	end)
	local isList = core:memo(function(use)
		return use(layout) ~= "icons"
	end)

	local toolbar = UI.VStack({
		id = "Toolbar",
		gap = "s",
		width = { type = "fill", weight = 1 },
		children = {
			UI.HStack({
				id = "Primary",
				gap = "s",
				align = "center",
				width = { type = "fill", weight = 1 },
				children = {
					layoutPicker.blueprint,
					sortMenu.blueprint,
					UI.Button({
						id = "NewPotion",
						label = S.t("gallery.newPotion"),
						compactLabel = { icon = "increment" },
						onActivate = function()
							app.actions.openScratch()
						end,
					}),
				},
			}),
			UI.HStack({
				id = "Secondary",
				gap = "s",
				align = "center",
				width = { type = "fill", weight = 1 },
				children = {
					UI.When({
						id = "TimeframeWhen",
						condition = sortIsPopularity,
						thenView = function()
							return timeframePicker.blueprint
						end,
					}),
					UI.When({
						id = "AxisWhen",
						condition = sortIsAttribute,
						thenView = function()
							return axisMenu.blueprint
						end,
					}),
					UI.VStack({
						id = "SearchSlot",
						width = { type = "fill", weight = 1 },
						children = { search.blueprint },
					}),
				},
			}),
		},
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
		local isSelected = core:memo(function(use)
			return use(selected) == potion.id
		end)
		table.insert(selectedMemos, isSelected)
		table.insert(
			gridCells,
			UI.Button({
				id = "Cell_" .. potion.id,
				label = potion.name,
				align = "center",
				gap = "xs",
				-- THE CELL TAKES ITS COLUMN. A grid cell sizes to its own content by
				-- default, and a `fill` child inside a content-measuring Button
				-- measures against an offer of zero — so the tile collapsed to its
				-- own padding (24px) and the solver said "nothing inside this can
				-- draw". The Button fills; the stack inside it hugs.
				width = { type = "fill", weight = 1 },
				selected = isSelected,
				onActivate = function()
					selected:set(potion.id)
					app.actions.openPotion(potion.id)
				end,
				children = {
					-- ONE child, and it is a VStack: a Button lays its content out as a
					-- ROW, so a mark-over-name-over-caption tile has to say so (three
					-- bare children overflowed a 96px column by 112px, which the
					-- solver reported on every viewport)
					UI.VStack({
						id = "Cell",
						gap = "xs",
						align = "center",
						children = {
							parts.potionMark(app, "Mark", potion, "controls.image.defaultSize"),
							UI.Text({
								id = "Name",
								text = potion.name,
								textSize = "label",
								textAlign = "center",
								lineLimit = 2,
								disclose = true,
							}),
							UI.Text({
								id = "Strongest",
								text = strongestCaption(potion),
								textSize = "caption",
								role = "secondary",
								textAlign = "center",
								lineLimit = 1,
							}),
						},
					}),
				},
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

		`metrics.tileMin` is 96 device px and everything INSIDE a tile is a theme
		metric, so on a Large display the mark grew to 72px and the button's padding
		to 18 a side — 108px of content asking for a 96px minimum — while the column
		minimum stayed exactly where a phone left it. That is
		`docs/lessons/facet-fixed-px-heights.md`'s class read across the distance
		axis: a fixed px number holding content that is not fixed.

		It went unreported until the framework capped the ten-foot content lane
		(controller ruling R14): the lane went from 1292px to 900, the columns
		narrowed with it, and the tile finally ran 7px past its own box on all 17
		visible cells. The cap did not cause this — it stopped the extra pixels from
		hiding it, which is what the always-on overflow sweep is for.

		So the minimum takes the same factor its contents take: the environment's own
		`metricScale` (ADR-0039's one ten-foot number). At near distance it is 1 and
		this is byte-identical to the literal it replaces. ]]
	-- OWNED (RR-8): a memo the screen builds per mount and nobody disposes is one
	-- leaked memo per build cycle, which `cartwheel_spec`'s registry-neutrality
	-- case counts. `app.scope` is the app's own, and it caught this immediately.
	local tileMin = app.scope:own(core:memo(function(use)
		local m = use(app.env:get("themeMetrics"))
		local scale = if type(m) == "table" and type((m :: any).metricScale) == "number"
			then (m :: any).metricScale
			else 1
		return math.floor(metrics.tileMin * scale)
	end))

	local gridForm = UI.Grid({
		id = "Tiles",
		minColumnWidth = tileMin,
		gap = "m",
		children = {
			UI.ForEach({
				id = "Cells",
				items = rows,
				key = function(item)
					return item.id
				end,
				row = function(item)
					return cellById[item.id]
				end,
			}),
		},
	})

	-- ---- the table form ------------------------------------------------------

	local tableControl = Facet.Controls.Table(core, {
		id = "PotionTable",
		rows = rows,
		key = function(item)
			return item.id
		end,
		columns = {
			{
				id = "potion",
				title = S.t("gallery.colPotion"),
				width = { type = "fill", weight = 1.6 },
				cell = function(item)
					return UI.HStack({
						id = "PotionCell",
						gap = "xs",
						align = "center",
						width = { type = "fill", weight = 1 },
						children = {
							parts.potionMark(app, "Mark", item, "iconSizes.large"),
							UI.Text({
								id = "Name",
								text = item.name,
								textSize = "label",
								width = { type = "fill", weight = 1 },
								lineLimit = 1,
								disclose = true,
							}),
						},
					})
				end,
				sortable = true,
				disclose = true,
			},
			{
				id = "strongest",
				title = S.t("gallery.colStrongest"),
				width = { type = "fill", weight = 1 },
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
	local unsubscribe = core:observe(tableControl.api.selectedKeys, function(keys: any)
		local first = (keys :: any)[1]
		if first ~= nil and first ~= selected:get() then
			selected:set(first)
			app.actions.openPotion(first)
		end
	end)

	local page = UI.VStack({
		id = "Potions",
		padding = "m",
		gap = "s",
		width = { type = "fill", weight = 1 },
		height = { type = "fill", weight = 1 },
		children = {
			UI.Text({ id = "Title", text = S.t("gallery.title"), textSize = "title" }),
			toolbar,
			UI.When({
				id = "EmptyWhen",
				condition = isEmpty,
				thenView = function()
					return parts.empty(app, "Empty", S.t("gallery.empty"))
				end,
			}),
			UI.When({
				id = "GridWhen",
				condition = isGrid,
				thenView = function()
					return UI.ZStack({
						id = "GridHost",
						canvasGroup = true,
						overflow = "clip",
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						children = {
							UI.ScrollView({
								id = "GridScroll",
								axis = "y",
								width = { type = "fill", weight = 1 },
								height = { type = "fill", weight = 1 },
								children = { gridForm },
							}),
						},
					})
				end,
				transition = { enter = "fade", class = "container" },
			}),
			UI.When({
				id = "TableWhen",
				condition = isList,
				thenView = function()
					return UI.ZStack({
						id = "TableHost",
						canvasGroup = true,
						overflow = "clip",
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						children = { tableControl.blueprint },
					})
				end,
				transition = { enter = "fade", class = "container" },
			}),
		},
	})

	function self.view(): any
		return page
	end

	function self.dump(): any
		local order: { string } = {}
		for _, potion in rows:get() :: any do
			table.insert(order, potion.id)
		end
		return {
			layout = layout:get(),
			sort = sortKey:get(),
			timeframe = timeframe:get(),
			axis = axisKey:get(),
			query = query:get(),
			selected = selected:get(),
			order = order,
			-- WHICH IDIOM THE UNWIRED POPUP RESOLVED (ADAPT-1): "menu" on a
			-- pointer, "sheet" under a thumb — decided by the environment this
			-- screen never had to pass in
			sortPresentation = sortMenu.presentation(),
		}
	end

	function self.dispose()
		unsubscribe()
		tableControl.dispose()
		search.dispose()
		axisMenu.dispose()
		timeframePicker.dispose()
		sortMenu.dispose()
		layoutPicker.dispose()
		for _, memo in selectedMemos do
			memo:dispose()
		end
		isList:dispose()
		isGrid:dispose()
		isEmpty:dispose()
		sortIsAttribute:dispose()
		sortIsPopularity:dispose()
		rows:dispose()
		selected:dispose()
		query:dispose()
		axisKey:dispose()
		timeframe:dispose()
		sortKey:dispose()
		layout:dispose()
	end

	return self
end

return gallery
