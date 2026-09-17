--!strict
local COPY = {
	title = "Pages and dots",
	intro = "Swipe one course at a time, choose any dot, or focus the dots and use Left / Right.",
	coast = "Coastal circuit",
	forest = "Forest sprint",
	summit = "Summit climb",
	coastText = "Fast harbor straights lead into a narrow old town. Keep a clean line through the final turn.",
	forestText = "Follow the river through a shaded forest. Gentle curves build toward a technical finish.",
	summitText = "Climb above the clouds, then hold your line on the way down. Each lap rewards steady braking.",
}
return {
	title = "Pages and dots",
	ledgerRows = {},
	copy = COPY,
	build = function(ctx)
		local Facet = ctx.Facet
		local UI = Facet.View
		local copy = ctx.copy or COPY
		local selected, setSelected, picked, setPicked
		local Page = Facet.component(function(ui)
			selected, setSelected = ui.state("coast")
			picked, setPicked = ui.state("Choose a course.")
			local viewport = ui.env("viewportRect")
			local pages = {}
			for _, entry in { { "coast", "coastText" }, { "forest", "forestText" }, { "summit", "summitText" } } do
				local key = entry[1]
				table.insert(pages, {
					id = key,
					title = copy[key],
					content = UI.VStack({
						id = "Course",
						width = UI.fill(),
						gap = "m",

						UI.Text({ text = copy[key], textSize = "heading", width = UI.fill() }),
						UI.ZStack({
							id = "Preview",
							width = UI.fill(),
							height = { type = "fixed", px = 120 },

							UI.Box({
								id = "Backdrop",
								width = UI.fill(),
								height = UI.fill(),
								tint = { role = "accent", blend = 0.2 },
							}),
							UI.Path({
								id = "Circuit",
								width = UI.fill(),
								height = UI.fill(),
								points = {
									{ x = 0.15, y = 0.5 },
									{ x = 0.35, y = 0.2 },
									{ x = 0.75, y = 0.25 },
									{ x = 0.85, y = 0.65 },
									{ x = 0.4, y = 0.8 },
									{ x = 0.15, y = 0.5 },
								},
								thickness = 4,
							}),
						}),
						UI.Text({ text = copy[entry[2]], width = UI.fill() }),
						UI.Button({
							id = "Choose",
							label = "Choose " .. copy[key],
							width = UI.fill(),
							onActivate = function()
								setPicked(copy[key])
							end,
						}),
					}),
				})
			end
			local pager = UI.PageView({
				id = "Courses",
				selection = selected,
				onChange = setSelected,
				pages = pages,
				height = function()
					return { type = "fixed", px = math.clamp(viewport().h * 0.75, 360, 640) }
				end,
			})
			return UI.Screen({
				id = "PageView",
				padding = "m",

				UI.ScrollView({
					id = "Page",
					width = UI.fill(),
					height = UI.fill(),
					gap = "m",

					UI.Text({ text = copy.title, textSize = "title" }),
					UI.Text({ text = copy.intro, width = UI.fill() }),
					pager,
					UI.Text({ id = "Picked", text = picked, width = UI.fill(), disclose = true }),
				}),
			})
		end)
		return {
			screen = Page({}),
			steps = {
				next = function()
					local ids = { "coast", "forest", "summit" }
					setSelected(ids[math.min(3, (table.find(ids, selected()) or 1) + 1)])
				end,
				reset = function()
					setSelected("coast")
					setPicked("Choose a course.")
				end,
			},
			report = function()
				return { pager = { selection = selected() }, picked = picked() }
			end,
			dispose = function() end,
		}
	end,
}
