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
		local Facet, core = ctx.Facet, ctx.core
		local UI = Facet.UI
		local copy = ctx.copy or COPY
		local scope = core:scope("page-view-demo")
		local selected = scope:own(core:signal("coast"))
		local picked = scope:own(core:signal("Choose a course."))
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
					children = {
						UI.Text({ text = copy[key], textSize = "heading", width = UI.fill() }),
						UI.ZStack({
							id = "Preview",
							width = UI.fill(),
							height = { type = "fixed", px = 120 },
							children = {
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
							},
						}),
						UI.Text({ text = copy[entry[2]], width = UI.fill() }),
						UI.Button({
							id = "Choose",
							label = "Choose " .. copy[key],
							width = UI.fill(),
							onActivate = function()
								picked:set(copy[key])
							end,
						}),
					},
				}),
			})
		end
		local pager = scope:own(Facet.Controls.PageView(core, {
			id = "Courses",
			selection = selected,
			pages = pages,
			height = scope:own(core:memo(function(use)
				return { type = "fixed", px = math.clamp(use(ctx.env:get("viewportRect")).h * 0.75, 360, 640) }
			end)),
		}))
		return {
			screen = UI.Screen({
				id = "PageView",
				padding = "m",
				children = {
					UI.ScrollView({
						id = "Page",
						width = UI.fill(),
						height = UI.fill(),
						gap = "m",
						children = {
							UI.Text({ text = copy.title, textSize = "title" }),
							UI.Text({ text = copy.intro, width = UI.fill() }),
							pager.blueprint,
							UI.Text({ id = "Picked", text = picked, width = UI.fill(), disclose = true }),
						},
					}),
				},
			}),
			steps = {
				next = function()
					local ids = { "coast", "forest", "summit" }
					selected:set(ids[math.min(3, (table.find(ids, selected:get()) or 1) + 1)])
				end,
				reset = function()
					selected:set("coast")
					picked:set("Choose a course.")
				end,
			},
			report = function()
				return { pager = pager.dump(), picked = picked:get() }
			end,
			dispose = function()
				scope:dispose()
			end,
		}
	end,
}
