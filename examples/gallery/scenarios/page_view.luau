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
		local UI, Compose = ctx.UI, ctx.Compose
		local copy = ctx.copy or COPY
		local ids = { "coast", "forest", "summit" }
		local selected = Compose.cell("coast")
		local picked = Compose.cell("Choose a course.")
		local function screen()
			local viewport = ctx.env:get("viewportRect")
			local pages = {}
			for _, key in ids do
				table.insert(pages, {
					id = key,
					title = copy[key],
					content = UI.VStack("Course")({
						width = UI.fill(),
						gap = "m",

						UI.Text({ text = copy[key], textSize = "heading", width = UI.fill() }),
						UI.ZStack("Preview")({
							width = UI.fill(),
							height = { type = "fixed", px = 120 },

							UI.Box("Backdrop")({
								width = UI.fill(),
								height = UI.fill(),
								tint = { role = "accent", blend = 0.2 },
							}),
							UI.Path("Circuit")({
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
						UI.Text({ text = copy[key .. "Text"], width = UI.fill() }),
						UI.Button("Choose")({
							label = "Choose " .. copy[key],
							width = UI.fill(),
							onActivate = function()
								picked:set(copy[key])
							end,
						}),
					}),
				})
			end
			return UI.Screen("PageView")({
				padding = "m",

				UI.ScrollView("Page")({
					width = UI.fill(),
					height = UI.fill(),
					gap = "m",

					UI.Text({ text = copy.title, textSize = "title" }),
					UI.Text({ text = copy.intro, width = UI.fill() }),
					UI.PageView("Courses")({
						selection = selected,
						pages = pages,
						height = function(use)
							return { type = "fixed", px = math.clamp(use(viewport).h * 0.75, 360, 640) }
						end,
					}),
					UI.Text("Picked")({ text = picked, width = UI.fill(), disclose = true }),
				}),
			})
		end
		return {
			screen = screen,
			steps = {
				next = function()
					selected:set(ids[math.min(3, (table.find(ids, selected:peek()) or 1) + 1)])
				end,
				reset = function()
					selected:set("coast")
					picked:set("Choose a course.")
				end,
			},
			report = function()
				return { pager = { selection = selected:peek() }, picked = picked:peek() }
			end,
		}
	end,
}
