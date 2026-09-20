--!strict
-- BREWS — the orders surface (spec §6): a sortable multi-column table where
-- there is room, a sectioned list where there is not, one search field over
-- both, and BULK COMPLETE ON BOTH. That last one is deliberate: the reference
-- shipped bulk completion in the table only, so the phone could not do what the
-- desktop could — a cross-input defect, and the proof closes it rather than
-- reproducing it.
local parts = require("./parts")
local strings = require("../content/strings")

local brews = {}

local STATUS_RANK = { new = 1, brewing = 2, ready = 3, done = 4 }
local STATUS_ORDER = { "new", "brewing", "ready", "done" }

function brews.new(app: any): any
	local UI = app.UI
	local Compose = app.Compose
	local S = app.S
	local Facet = app.Facet
	local orders = app.services.orders

	local self: any = {}

	-- ---- presentation state (client-local, never replicated) ----------------
	local query = Compose.cell("")
	local sortOrder = Compose.cell({ column = "status", ascending = true })
	local selectionMode = Compose.cell(false)
	local listSelected = Compose.cell({} :: { [string]: boolean })
	self.query = query
	self.sortOrder = sortOrder
	self.selectionMode = selectionMode
	self.listSelected = listSelected

	-- ---- the derived rows ----------------------------------------------------
	-- filter (id + potion + ingredient names — the reference searched the id
	-- alone), then sort. THE DEFAULT SORT IS DECIDED: Status ascending (New
	-- first), ties Placed descending, so the work to do is at the top.
	local filtered = Compose.formula(function(use)
		local text = string.lower(use(query))
		local out: { any } = {}
		for _, brew in use(orders.brews) :: any do
			if text == "" or string.find(orders.searchText(brew), text, 1, true) ~= nil then
				table.insert(out, brew)
			end
		end
		return out
	end)

	local sorted = Compose.formula(function(use)
		local rows = table.clone(use(filtered) :: any)
		local order = use(sortOrder) :: any
		local column = if order == nil then "status" else order.column
		local ascending = if order == nil then true else order.ascending
		table.sort(rows, function(a, b)
			local left, right
			if column == "brew" then
				left, right = a.id, b.id
			elseif column == "bottles" then
				left, right = a.bottles, b.bottles
			elseif column == "placed" then
				left, right = a.placedAt, b.placedAt
			else
				left, right = STATUS_RANK[a.status] or 9, STATUS_RANK[b.status] or 9
			end
			if left == right then
				-- the tie-break is fixed and stated: newest placement first
				return a.placedAt > b.placedAt
			end
			if ascending then
				return left < right
			end
			return left > right
		end)
		return rows
	end)
	self.rows = sorted

	-- ---- the selection, one answer for both modes ---------------------------
	-- the table's selection: a caller-owned key set the control writes
	local tableSelected = Compose.cell({} :: { [string]: boolean })

	local function selectedIds(): { number }
		local ids: { number } = {}
		if selectionMode:peek() then
			for key in listSelected:peek() :: any do
				table.insert(ids, tonumber(key) :: number)
			end
		else
			for key, on in tableSelected:peek() :: any do
				if on then
					table.insert(ids, tonumber(key) :: number)
				end
			end
		end
		table.sort(ids)
		return ids
	end
	self.selectedIds = selectedIds

	local selectionCount = Compose.formula(function(use)
		if use(selectionMode) then
			local n = 0
			for _ in use(listSelected) :: any do
				n += 1
			end
			return n
		end
		local n = 0
		for _, on in use(tableSelected) :: any do
			if on then
				n += 1
			end
		end
		return n
	end)

	local hasSelection = Compose.formula(function(use)
		return use(selectionCount) > 0
	end)
	local noSelection = Compose.formula(function(use)
		return not use(hasSelection)
	end)
	local isEmpty = Compose.formula(function(use)
		return #(use(sorted) :: any) == 0
	end)
	local isListMode = Compose.formula(function(use)
		return not use(app.state.isTableMode)
	end)
	local bandUp = Compose.formula(function(use)
		return use(selectionMode) and use(hasSelection)
	end)

	-- one memo per row key, cached: a Toggle's value read inside a row factory
	-- would build (and leak) a memo on every mount
	local pickMemos: { [string]: any } = {}
	local function pickMemo(key: string): any
		local existing = pickMemos[key]
		if existing == nil then
			-- cached across visits, so it lives under the app owner
			existing = app.rooted(function()
				return Compose.formula(function(use)
					return (use(listSelected) :: any)[key] == true
				end)
			end)
			pickMemos[key] = existing
		end
		return existing
	end

	local function collectSelected()
		local ids = selectedIds()
		if #ids == 0 then
			return
		end
		app.actions.collectBrews(ids)
	end

	-- ---- the toolbar ---------------------------------------------------------

	local listEntries = Compose.formula(function(use)
		local rows = use(sorted) :: any
		local out: { any } = {}
		for _, status in STATUS_ORDER do
			local group: { any } = {}
			for _, brew in rows do
				if brew.status == status then
					table.insert(group, brew)
				end
			end
			if #group == 0 then
				continue -- empty groups are ABSENT, not empty headings
			end
			table.insert(out, { kind = "heading", key = "h:" .. status, status = status, count = #group })
			for _, brew in group do
				table.insert(out, { kind = "row", key = "r:" .. tostring(brew.id), brew = brew })
			end
		end
		return out
	end)
	self.listEntries = listEntries

	-- The page is built per visit: a node belongs to the mount that made it.
	local function buildPage(): any
		local search = UI.TextInput("Search")({
			value = query,
			placeholder = S.t("brews.search"),
			clearButtonMode = "whileEditing",
			env = app.env,
			actionSystem = app.actionSystem,
		})
		self.search = search

		local collectLabel = Compose.formula(function(use)
			return S.t("brews.collectSelected", { n = use(selectionCount) })
		end)

		local function openSelected()
			local ids = selectedIds()
			if ids[1] ~= nil then
				app.actions.openBrew(ids[1])
			end
		end

		local function actionRow(id: string, compact: boolean): any
			return UI.HStack(id)({
				gap = "s",
				align = "center",

				UI.Button("Open")({
					label = S.t("brews.open"),
					compactLabel = if compact then { text = "Open" } else nil,
					enabled = hasSelection,
					onActivate = openSelected,
				}),
				UI.Button("Collect")({
					label = collectLabel,
					compactLabel = if compact then { icon = "checkmark" } else nil,
					surface = "accent",
					enabled = hasSelection,
					onActivate = collectSelected,
				}),
			})
		end

		local toolbar = UI.HStack("Toolbar")({
			gap = "s",
			align = "center",
			width = UI.fill(),

			UI.VStack("SearchSlot")({
				width = UI.fill(),
				search,
			}),
			app.when("SelectWhen")({
				condition = app.state.isCompact,
				thenView = function()
					return UI.Button("SelectMode")({
						label = Compose.formula(function(use)
							return if use(selectionMode) then S.t("brews.selectDone") else S.t("brews.select")
						end),
						selected = selectionMode,
						onActivate = function()
							local on = not selectionMode:peek()
							selectionMode:set(on)
							if not on then
								listSelected:set({})
							end
						end,
					})
				end,
			}),
			app.when("ActionsWhen")({
				condition = app.state.isTableMode,
				thenView = function()
					return UI.ViewThatFits("Actions")({
						actionRow("Full", false),
						actionRow("Compact", true),
					})
				end,
			}),
		})

		-- "DISABLED STAYS INSPECTABLE" — on its own line. The reason the two toolbar
		-- verbs are refusing has to be readable, and inside the action row it was
		-- 20px of overflow on a landscape phone (the solver said so on every solve).
		local toolbarHint = app.when("HintWhen")({
			condition = noSelection,
			thenView = function()
				return UI.Text("Hint")({
					text = S.t("brews.openHint"),
					textSize = "caption",
					role = "secondary",
					lineLimit = 2,
					disclose = true,
				})
			end,
		})

		-- ---- the table (regular / wide) -----------------------------------------
		--
		-- THE ROW'S OWN VERBS ARE TWO SMALL BUTTONS, NOT AN ELLIPSIS MENU, and that
		-- is a measured deviation from the spec's `newPopupButton` (§6). A popup
		-- trigger is `controls.popup.triggerHeight` (40px) and a DENSE POINTER TABLE
		-- ROW is `controls.table.rowHeight.pointer` (36px) — two theme metrics that
		-- disagree — so a menu in a row overflows it by 4px and paints over its
		-- neighbours, which the solver reports on every pointer viewport. Two
		-- `padding = "xs"` buttons carry the same two verbs (Open, Collect), fit the
		-- row, and cost one fewer press. The metric mismatch is a framework finding,
		-- recorded for framework-fixes.md rather than papered over here.

		-- a table cell builder receives its row as a readable
		local function brewCell(row: any): any
			local item = row:peek()
			return UI.HStack("BrewCell")({
				gap = "xs",
				align = "center",
				width = UI.fill(),

				parts.thumbStack(app, "Thumbs", item.items, "iconSizes.large"),
				-- the label TAKES the leftover instead of its natural width: a
				-- column narrows with the table, and a fixed-width label inside one
				-- paints over the cell beside it (7px on a landscape phone)
				UI.Text("Id")({
					text = S.t("brews.rowLabel", { id = item.id }),
					textSize = "label",
					width = UI.fill(),
					lineLimit = 1,
					disclose = true,
				}),
			})
		end

		local function statusText(item: any): string
			return S.t("status." .. item.status)
		end

		local tableControl = UI.Table("BrewTable")({
			selectedKeys = tableSelected,
			rows = sorted,
			key = function(item)
				return tostring(item.id)
			end,
			columns = {
				{
					id = "brew",
					title = S.t("brews.colBrew"),
					width = UI.fill(1.6),
					cell = brewCell,
					sortable = true,
					disclose = true,
					resizable = true,
				},
				{
					id = "bottles",
					title = S.t("brews.colBottles"),
					width = UI.fill(0.6),
					alignment = { h = "trailing" },
					value = function(item)
						return tostring(item.bottles)
					end,
				},
				{
					id = "status",
					title = S.t("brews.colStatus"),
					width = UI.fill(0.8),
					value = statusText,
				},
				{
					id = "placed",
					title = S.t("brews.colPlaced"),
					width = UI.fill(0.8),
					value = function(item)
						return strings.clockTime(item.placedAt)
					end,
				},
				{
					id = "actions",
					title = S.t("brews.colActions"),
					width = UI.fill(0.8),
					cell = function(row)
						local item = row:peek()
						-- ONE verb in the row, and it is the one the row is FOR. The
						-- other half of the reference's ellipsis menu — Open — is the
						-- toolbar's, where §6 already requires it (select a row, press
						-- Open), because two labelled buttons cannot fit the Actions
						-- column of a table beside a sidebar on a landscape phone: the
						-- solver reported 39px of overflow, then 9px with both compacted
						-- to marks, and a column weight that fixes one viewport moves it
						-- to another.
						--[[ THE AUTHORED `textSize` HERE IS DELETED, AND THAT IS THE POINT
						(ADAPT-10, 2026-08-18). It said `textSize = "label"`, and the comment
						under it recorded why: unsized, this button takes the `control` role
						— 18px near, 27px once the ten-foot type floor reached unauthored
						text — which is 41px of button inside a 36px row, and the solver
						reported 5px of overflow on all 24 visible rows at 1920x1080. The
						example absorbed a FRAMEWORK defect it had no business absorbing:
						a television was getting the DENSEST table row the library ships,
						because the density ladder had no distance rung.

						The ladder has one now (`controls.table.rowHeight.tenFoot`), so the
						row is tall enough for the button the natural declaration produces
						and this cell says nothing about type at all. Which is the whole
						test: an example that has to size its own text is an example
						reporting a defect somewhere else. ]]
						return UI.Button("Collect")({
							label = S.t("brews.collectShort"),
							compactLabel = { icon = "checkmark" },
							padding = "xs",
							onActivate = function()
								app.actions.collectBrews({ item.id })
							end,
						})
					end,
				},
			},
			selection = "multi",
			sortOrder = sortOrder,
			header = true,
			scrolls = true,
			rowGap = "controls.table.rowGap",
			env = app.env,
		})
		self.table = tableControl

		-- ---- the sectioned list (compact) ---------------------------------------
		-- ONE keyed ForEach over a flat entry list, not a ForEach of ForEaches: a
		-- nested items memo would have to be built inside a row factory, and the
		-- flat form keys headings and rows in the same reconciliation.

		local function listRow(entry: any): any
			if entry.kind == "heading" then
				return UI.HStack("Heading")({
					gap = "s",
					align = "center",
					padding = "xs",

					UI.Text("Title")({ text = S.t("status." .. entry.status), textSize = "heading" }),
					parts.badge(app, "Count", tostring(entry.count)),
				})
			end
			local brew = entry.brew
			local key = tostring(brew.id)
			return UI.HStack("Row")({
				gap = "s",
				align = "center",
				width = UI.fill(),

				app.when("PickWhen")({
					condition = selectionMode,
					thenView = function()
						-- the Toggle writes its own cell; the set stays the one answer
						local picked = Compose.cell((listSelected:peek() :: any)[key] == true)
						Compose.watch(function(use)
							picked:set((use(listSelected) :: any)[key] == true)
						end)
						return UI.Toggle("Pick")({
							label = S.t("brews.rowLabel", { id = brew.id }),
							value = picked,
							onChange = function(on: boolean)
								local current = table.clone(listSelected:peek() :: any)
								current[key] = if on then true else nil
								listSelected:set(current)
							end,
						})
					end,
				}),
				UI.Button("Open")({
					label = S.t("brews.rowLabel", { id = brew.id }),
					width = UI.fill(),
					onActivate = function()
						app.actions.openBrew(brew.id)
					end,

					parts.thumbStack(app, "Thumbs", brew.items, "iconSizes.large"),
					UI.Text("Name")({
						text = S.t("brews.rowLabel", { id = brew.id }),
						textSize = "body",
						lineLimit = 1,
						disclose = true,
					}),
					UI.Spacer("Gap")({ width = UI.fill() }),
					parts.badge(app, "Bottles", tostring(brew.bottles)),
				}),
			})
		end

		local listBody = UI.ScrollView("List")({
			axis = "y",
			gap = "xs",
			width = UI.fill(),
			height = UI.fill(),

			app.forEach("Entries")({
				items = listEntries,
				key = function(entry)
					return entry.key
				end,
				row = listRow,
			}),
		})

		-- the bottom band: bulk complete in LIST mode too
		local selectBand = app.when("BandWhen")({
			condition = bandUp,
			thenView = function()
				return UI.HStack("Band")({
					gap = "s",
					padding = "s",
					align = "center",
					width = UI.fill(),

					UI.Button("CollectSelected")({
						label = collectLabel,
						compactLabel = { icon = "checkmark" },
						surface = "accent",
						width = UI.fill(),
						onActivate = collectSelected,
					}),
				})
			end,
		})

		local page = UI.VStack("Brews")({
			padding = "m",
			gap = "s",
			width = UI.fill(),
			height = UI.fill(),

			UI.VStack("Body")({
				gap = "s",
				width = UI.fill(),
				height = UI.fill(),

				UI.Text("Title")({ text = S.t("brews.title"), textSize = "title" }),
				toolbar,
				toolbarHint,
				app.when("TableWhen")({
					condition = app.state.isTableMode,
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
				app.when("ListWhen")({
					condition = isListMode,
					thenView = function()
						return UI.ZStack("ListHost")({
							canvasGroup = true,
							overflow = "clip",
							width = UI.fill(),
							height = UI.fill(),
							listBody,
						})
					end,
					transition = { enter = "fade", class = "container" },
				}),
				-- an empty result says so in words rather than leaving a blank page
				app.when("EmptyWhen")({
					condition = isEmpty,
					thenView = function()
						return parts.empty(app, "Empty", S.t("brews.empty"))
					end,
				}),
				selectBand,
			}),
		})

		return page
	end

	self.view = buildPage

	-- Cancel exits selection mode BEFORE it pops navigation (spec §17)
	function self.handleCancel(): boolean
		if selectionMode:peek() then
			selectionMode:set(false)
			listSelected:set({})
			return true
		end
		return false
	end

	function self.dump(): any
		local statuses: { [string]: number } = {}
		for _, brew in sorted:peek() :: any do
			statuses[brew.status] = (statuses[brew.status] or 0) + 1
		end
		local order = sortOrder:peek() :: any
		return {
			query = query:peek(),
			rows = #(sorted:peek() :: any),
			first = ((sorted:peek() :: any)[1] or {}).id,
			sort = { column = order.column, ascending = order.ascending },
			selectionMode = selectionMode:peek(),
			selected = selectedIds(),
			entries = #(listEntries:peek() :: any),
			statuses = statuses,
		}
	end

	return self
end

return brews
