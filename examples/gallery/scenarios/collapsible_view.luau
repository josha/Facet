--!strict
local COPY = {
	title = "Collapsible views",
	intro = "Open a custom settings view, or expand the selected destination below.",
	settings = "Race settings",
	coast = "Coast",
	forest = "Forest",
	summit = "Summit",
}
return {
	title = "Collapsible views",
	ledgerRows = {},
	copy = COPY,
	build = function(ctx)
		local Facet, core = ctx.Facet, ctx.core
		local UI = Facet.UI
		local copy = ctx.copy or COPY
		local scope = core:scope("collapsible-demo")
		local expanded = scope:own(core:signal(false))
		local club = scope:own(core:signal(false))
		local selected = scope:own(core:signal("coast"))
		local label = scope:own(core:memo(function(use)
			return if use(club) then "Club race settings" else copy.settings
		end))
		local icon = scope:own(core:memo(function(use)
			return if use(club) then "check" else "flag"
		end))
		local control = scope:own(Facet.Controls.CollapsibleView(core, {
			id = "Settings",
			label = label,
			icon = icon,
			expanded = expanded,
			content = UI.VStack({
				id = "SettingsContent",
				gap = "m",
				width = UI.fill(),

				UI.Text({ text = copy.settings, textSize = "heading", width = UI.fill() }),
				UI.Toggle({ id = "Club", label = "Club membership", value = club, width = UI.fill() }),
				UI.Text({
					text = "The button summary and image follow the choice in this view.",
					width = UI.fill(),
				}),
			}),
		}))
		local tabs = {}
		for _, key in { "coast", "forest", "summit" } do
			table.insert(tabs, {
				id = key,
				label = copy[key],
				icon = "flag",
				content = function()
					return UI.ScrollView({
						id = "Course",
						width = UI.fill(),
						height = UI.fill(),
						gap = "m",

						UI.Text({ text = copy[key], textSize = "title", width = UI.fill() }),
						UI.Text({
							text = "Expand the navigation button to choose a different destination. Back returns focus to the button.",
							width = UI.fill(),
						}),
						UI.Button({ id = "Practice", label = "Practice this course", width = UI.fill() }),
					})
				end,
			})
		end
		local nav =
			Facet.View.TabView({ id = "Destinations", style = "collapsible", selection = selected, tabs = tabs })
		return {
			screen = UI.Screen({
				id = "CollapsibleView",
				padding = "m",

				UI.ScrollView({
					id = "Page",
					width = UI.fill(),
					height = UI.fill(),
					gap = "m",

					UI.Text({ text = copy.title, textSize = "title", width = UI.fill() }),
					UI.Text({ text = copy.intro, width = UI.fill() }),
					control.blueprint,
					UI.VStack({
						id = "NavigationRegion",
						width = UI.fill(),
						height = { type = "fixed", px = 420 },
						nav,
					}),
				}),
			}),
			steps = {
				open = function()
					expanded:set(true)
				end,
				close = function()
					expanded:set(false)
				end,
				reset = function()
					expanded:set(false)
					club:set(false)
					selected:set("coast")
				end,
			},
			states = function()
				return {
					{
						id = "settings-open",
						kind = "dialog",
						open = function()
							expanded:set(true)
							return true
						end,
					},
				}
			end,
			report = function()
				return { view = control.dump(), selection = selected:get(), club = club:get() }
			end,
			dispose = function()
				scope:dispose()
			end,
		}
	end,
}
