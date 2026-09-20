--!strict
-- A caller-owned trip plan flows through one NavigationStack. Environment facts
-- choose arrangement and controls; every page uses the same theme/input authorities.
return {
	title = "Plan a journey",
	ledgerRows = { "CAPABILITY-NAVIGATION" },
	build = function(ctx)
		local UI, Compose, env = ctx.UI, ctx.Compose, ctx.env
		local path = Compose.cell({})
		local destination = Compose.cell("coast")
		local query = Compose.cell("")
		local journeys = {
			{ id = "coast", label = "Coastal journey" },
			{ id = "forest", label = "Forest journey" },
			{ id = "mountain", label = "Mountain journey" },
		}
		local matches = Compose.formula(function(use)
			local needle = string.lower(use(query))
			local result = {}
			for _, item in journeys do
				if string.find(string.lower(item.label), needle, 1, true) then
					table.insert(result, item)
				end
			end
			return result
		end)
		local notes = Compose.cell("Meet at sunrise.")
		local minimum = Compose.cell("m")
		local alignment = Compose.cell("firstTextBaseline")
		local visits, exits = 0, 0
		local axis = Compose.formula(function(use)
			return if use(env:get("sizeClass")) == "compact" then "y" else "x"
		end)
		-- The path is the caller's: every navigation here is a write to it.
		local function push(entry)
			local nextPath = table.clone(path:peek())
			table.insert(nextPath, entry)
			path:set(nextPath)
		end
		local function back()
			local current = path:peek()
			if #current == 0 then
				return false
			end
			local nextPath = table.clone(current)
			table.remove(nextPath)
			path:set(nextPath)
			return true
		end
		local function popToRoot()
			path:set({})
		end
		-- Each page's content runs under that page's owner.
		local function page(content)
			visits += 1
			Compose.cleanup(function()
				exits += 1
			end)
			content.gap = "m"
			content.width = UI.fill()
			return UI.ScrollView("Scroll")({
				width = UI.fill(),
				height = UI.fill(),
				UI.VStack("Content")(content),
			})
		end
		local function journey()
			return UI.NavigationStack("Journey")({
				path = path,
				backLabel = "Back",
				transition = { enter = "slide-left", exit = "slide-right", class = "container" },
				env = env,
				root = {
					title = "Plan a journey",
					content = function()
						local searchLayout = UI.AdaptiveStack("SearchLayout")({
							axis = axis,
							gap = "m",
							width = UI.fill(),

							UI.VStack("SearchEntry")({
								width = UI.fill(),
								gap = "s",

								UI.Text({ text = "Find a journey", textSize = "heading", width = UI.fill() }),
								UI.TextInput("Search")({
									value = query,
									presentation = "search",
									placeholder = "Search journeys",
									submitLabel = "search",
									env = env,
								}),
							}),
							UI.focusSection(
								UI.VStack("Results")({
									width = UI.fill(),
									gap = "s",

									UI.Text("ResultsHeading")({
										text = function(use)
											return if use(query) == "" then "Suggested journeys" else "Search results"
										end,
										width = UI.fill(),
										textSize = "heading",
									}),
									UI.ForEach("Matches")({
										Compose.keyed({
											from = matches,
											key = function(item)
												return item.id
											end,
											render = function(item)
												local id = item:peek().id
												return UI.Button("Result-" .. id)({
													label = function(use)
														return use(item).label
													end,
													width = UI.fill(),
													onActivate = function()
														destination:set(id)
														push({ id = "details" })
													end,
												})
											end,
										}),
									}),
									UI.When("Empty")({
										Compose.show(function(use)
											return #use(matches) == 0
										end, function()
											return UI.Text({
												text = "No journeys found. Try another name or clear search.",
												width = UI.fill(),
											})
										end),
									}),
								}),
								{ entry = "restore" }
							),
						})
						return page({
							UI.Text({
								text = "Choose a destination. Your choices stay with you when you go back.",
								width = UI.fill(),
							}),
							searchLayout,
							UI.Button("Continue")({
								label = "Plan details",
								onActivate = function()
									push({ id = "details" })
								end,
							}),
						})
					end,
				},
				destinations = {
					details = {
						title = "Journey details",
						content = function()
							return page({
								UI.AdaptiveStack("Columns")({
									axis = axis,
									gap = "m",
									width = UI.fill(),

									UI.VStack("Summary")({
										width = UI.fill(),
										gap = "s",

										UI.HStack("Baseline")({
											align = alignment,
											gap = "s",
											width = UI.fill(),

											UI.Text("Label")({ text = "Days", textSize = "caption" }),
											UI.Text("Value")({ text = "3", textSize = "title" }),
											UI.Spacer("FlexibleGap")({ minLength = minimum }),
											UI.Text("Unit")({ text = "away", textSize = "body" }),
										}),
										UI.HStack("LastBaseline")({
											width = UI.fill(),
											wrap = true,
											align = "lastTextBaseline",
											gap = "s",

											UI.Text({ text = "Travel light", textSize = "heading" }),
											UI.Text({ text = "and enjoy the view", textSize = "caption" }),
										}),
									}),
									UI.VStack("Writing")({
										width = UI.fill(),
										gap = "s",
										UI.Text({ text = "Your notes" }),
										UI.TextInput("Notes")({ value = notes, multiline = true, env = env }),
									}),
								}),
								UI.Button("Review")({
									label = "Review journey",
									onActivate = function()
										push({ id = "review", value = destination:peek() })
									end,
								}),
							})
						end,
					},
					review = {
						title = "Ready to go",
						content = function(_, entry)
							return page({
								UI.Text({
									text = "Destination: " .. tostring(entry.value),
									textSize = "heading",
									width = UI.fill(),
								}),
								UI.Text({ text = notes, width = UI.fill() }),
								UI.Button("StartAgain")({
									label = "Back to the beginning",
									onActivate = function()
										popToRoot()
									end,
								}),
							})
						end,
					},
				},
			})
		end
		return {
			screen = function()
				return UI.Screen("NavigationFlow")({ surface = "base", journey() })
			end,
			steps = {
				search = function()
					query:set("forest")
				end,
				noResults = function()
					query:set("unknown")
				end,
				clearSearch = function()
					query:set("")
				end,
				push = function()
					push({ id = "details" })
				end,
				review = function()
					push({ id = "review", value = destination:peek() })
				end,
				back = function()
					return back()
				end,
				reset = function()
					popToRoot()
				end,
				spacing = function()
					minimum:set(if minimum:peek() == "m" then "xl" else "m")
				end,
				baseline = function()
					alignment:set(
						if alignment:peek() == "firstTextBaseline" then "lastTextBaseline" else "firstTextBaseline"
					)
				end,
			},
			states = function()
				return {
					{
						id = "details",
						kind = "page",
						open = function()
							path:set({ { id = "details" } })
							return true
						end,
					},
					{
						id = "review",
						kind = "page",
						open = function()
							path:set({ { id = "details" }, { id = "review", value = "coast" } })
							return true
						end,
					},
				}
			end,
			report = function()
				return {
					navigation = { depth = #path:peek() },
					visits = visits,
					exits = exits,
					notes = notes:peek(),
					destination = destination:peek(),
					query = query:peek(),
					matches = #matches:peek(),
					axis = axis:peek(),
				}
			end,
		}
	end,
}
