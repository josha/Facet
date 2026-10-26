--!strict
local Facet = require(game.ReplicatedStorage.Packages.Facet)

export type Record = { id: string, name: string, category: string, facts: string, value: number }
export type Order = string
export type Model = {
	query: Facet.Value<string>,
	category: Facet.Value<string>,
	order: Facet.Value<Order>,
	filterPath: Facet.Value<{ Facet.NavigationEntry<string> }>,
	selected: Facet.Value<string>,
	scroll: Vector2,
}
export type Callbacks = { inspect: (string) -> (), close: () -> () }

local function createModel(): Model
	local C = Facet.Compose
	return {
		query = C.cell(""),
		category = C.cell(""),
		order = C.cell("name" :: Order),
		filterPath = C.cell({} :: { Facet.NavigationEntry<string> }),
		selected = C.cell(""),
		scroll = Vector2.zero,
	}
end

return {
	createModel = createModel,
	build = function(
		app: Facet.App,
		records: Facet.ReadOnlyValue<{ Record }>,
		model: Model,
		callbacks: Callbacks
	): Frame
		local C, UI = Facet.Compose, app.UI
		local function reset()
			model.query:set("")
			model.category:set("")
			model.order:set("name")
		end
		local categories = C.formula(function(use: Facet.Use): { Facet.PickerOption<string> }
			local seen: { [string]: boolean } = {}
			local names: { string } = {}
			for _, record in use(records) do
				if not seen[record.category] then
					seen[record.category] = true
					table.insert(names, record.category)
				end
			end
			table.sort(names)
			local options: { Facet.PickerOption<string> } = { { value = "", label = "All types" } }
			for _, name in names do
				table.insert(options, { value = name, label = name })
			end
			local selected = use(model.category)
			if selected ~= "" and not seen[selected] then
				table.insert(options, { value = selected, label = selected .. " (unavailable)" })
			end
			return options
		end)
		local visible = C.formula(function(use: Facet.Use): { Record }
			local query, category, order = string.lower(use(model.query)), use(model.category), use(model.order)
			local matches: { Record } = {}
			for _, record in use(records) do
				local text = string.lower(record.name .. " " .. record.category .. " " .. record.facts)
				if (category == "" or record.category == category) and string.find(text, query, 1, true) then
					table.insert(matches, record)
				end
			end
			table.sort(matches, function(a: Record, b: Record): boolean
				if order == "value" and a.value ~= b.value then
					return a.value < b.value
				end
				if a.name ~= b.name then
					return a.name < b.name
				end
				return a.id < b.id
			end)
			return matches
		end)
		local filterKey = C.formula(function(use: Facet.Use): string
			return use(model.query) .. "\0" .. use(model.category) .. "\0" .. use(model.order)
		end)
		local rows: Facet.KeyedCollectionSpec<Record, string> = {
			from = visible,
			key = "id",
			itemSize = 96,
			measure = true,
			autoFocus = false,
			focusPolicy = "key",
			scrollReset = filterKey,
			CanvasPosition = model.scroll,
			Size = UDim2.fromScale(1, 1),
			render = function(current)
				return UI.Button "Record" {
					Size = UDim2.new(1, 0, 0, 0),
					TextXAlignment = Enum.TextXAlignment.Left,
					appearance = "utility",
					label = function(use)
						return use(current).name
					end,
					subtitle = function(use)
						local record = use(current)
						return record.category .. " · " .. record.facts
					end,
					selected = function(use)
						return use(model.selected) == use(current).id
					end,
					onActivate = function()
						local id = current:peek().id
						model.selected:set(id)
						callbacks.inspect(id)
					end,
				}
			end,
			UI.fill(),
		}
		local list = UI.VirtualList "Records"(rows)
		local scrollConnection = list:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			model.scroll = list.CanvasPosition
		end)
		C.cleanup(function()
			scrollConnection:Disconnect()
		end)
		local orders: { Facet.PickerOption<Order> } = {
			{ value = "name", label = "Name" },
			{ value = "value", label = "Lowest cost" },
		}
		local search: Facet.TextInputCellProps = {
			Size = UDim2.new(1, 0, 0, 0),
			value = model.query,
			presentation = "search",
			placeholder = "Search records",
			UI.fill(),
		}
		local searchInput: (Facet.TextInputCellProps) -> GuiObject = UI.TextInput "Search"
		local body = UI.ZStack "CollectionBody" {
			width = "fill",
			height = "fill",
			alignH = "center",
			UI.fill(),
			UI.VStack "Browse" {
				width = "fill",
				maxWidth = 760,
				height = "fill",
				gap = "xs",
				UI.HStack "SearchAndFilters" {
					width = "fill",
					align = "center",
					gap = "s",
					searchInput(search),
					UI.Button "Filters" {
						label = "Filters",
						appearance = "utility",
						onActivate = function()
							model.filterPath:set({ { id = "filters" } })
						end,
					},
				},
				UI.Text "ResultSummary" {
					wrap = true,
					textRole = "caption",
					text = function(use: Facet.Use): string
						local category = use(model.category)
						return `{#use(visible)} records · {if category == "" then "All types" else category} · {if use(
								model.order
							) == "name"
							then "Name"
							else "Lowest cost"}`
					end,
				},
				UI.ZStack "RecordsBody" {
					width = "fill",
					height = "fill",
					UI.fill(),
					list,
					C.show(function(use: Facet.Use): boolean
						return #use(visible) == 0
					end, function()
						return UI.ScrollView "EmptyResults" {
							width = "fill",
							height = "fill",
							gap = "s",
							UI.Text { text = "No matching records", textRole = "heading", wrap = true },
							UI.Text {
								text = "Change the search or reset all filters to see available records.",
								wrap = true,
							},
							UI.Button { label = "Reset search and filters", onActivate = reset },
						}
					end),
				},
			},
		}
		local function showRecords()
			model.filterPath:set({})
		end
		return UI.NavigationStack "CollectionSteps" {
			path = model.filterPath,
			chrome = "hidden",
			root = {
				content = function(): Instance
					local close: GuiObject = UI.Button {
						label = "Close",
						appearance = "utility",
						onActivate = function()
							callbacks.close()
						end,
					}
					return UI.Screen "Collection" {
						surface = "surface",
						padding = "s",
						gap = "s",
						UI.NavBar { title = "Collection", titleSize = "heading", trailing = close },
						body,
					}
				end,
			},
			destinations = {
				filters = {
					content = function(): Instance
						local done: GuiObject = UI.Button {
							label = function(use: Facet.Use): string
								return `Show {#use(visible)} records`
							end,
							appearance = "utility",
							onActivate = showRecords,
						}
						return UI.Screen "Filters" {
							surface = "surface",
							padding = "s",
							gap = "s",
							UI.NavBar { title = "Filters", titleSize = "heading", onBack = showRecords, trailing = done },
							UI.ZStack "FilterWidth" {
								width = "fill",
								height = "fill",
								alignH = "center",
								UI.fill(),
								UI.ScrollView "FilterStep" {
									width = "fill",
									maxWidth = 560,
									height = "fill",
									gap = "m",
									padding = "s",
									UI.Picker "Type" {
										label = "Type",
										selected = model.category,
										options = categories,
										style = "menu",
									},
									UI.Picker "Sort" {
										label = "Sort",
										selected = model.order,
										options = orders,
										style = "menu",
									},
									UI.Button {
										label = "Reset search and filters",
										appearance = "utility",
										onActivate = reset,
									},
								},
							},
						}
					end,
				},
			},
		}
	end,
}
