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
		local UI, Compose = ctx.UI, ctx.Compose
		local copy = ctx.copy or COPY
		local expanded = Compose.cell(false)
		local club = Compose.cell(false)
		local selected = Compose.cell("coast")
		local label = Compose.formula(function(use)
			return if use(club) then "Club race settings" else copy.settings
		end)
		local icon = Compose.formula(function(use)
			return if use(club) then "check" else "flag"
		end)
		local function settingsContent()
			return UI.VStack("SettingsContent")({
				gap = "m",
				width = UI.fill(),

				UI.Text({ text = copy.settings, textSize = "heading", width = UI.fill() }),
				UI.frame(UI.Toggle("Club")({ label = "Club membership", value = club }), { maxWidth = "infinity" }),
				UI.Text({
					text = "The button summary and image follow the choice in this view.",
					width = UI.fill(),
				}),
			})
		end
		local tabs = {}
		for _, key in { "coast", "forest", "summit" } do
			table.insert(tabs, {
				id = key,
				label = copy[key],
				icon = "flag",
				content = function()
					return UI.ScrollView("Course")({
						width = UI.fill(),
						height = UI.fill(),
						gap = "m",

						UI.Text({ text = copy[key], textSize = "title", width = UI.fill() }),
						UI.Text({
							text = "Expand the navigation button to choose a different destination. Back returns focus to the button.",
							width = UI.fill(),
						}),
						UI.Button("Practice")({
							label = "Practice this course",
							width = UI.fill(),
							onActivate = function() end,
						}),
					})
				end,
			})
		end
		local function Example()
			return UI.Screen("CollapsibleView")({
				padding = "m",

				UI.ScrollView("Page")({
					width = UI.fill(),
					height = UI.fill(),
					gap = "m",

					UI.Text({ text = copy.title, textSize = "title", width = UI.fill() }),
					UI.Text({ text = copy.intro, width = UI.fill() }),
					UI.CollapsibleView("Settings")({
						label = label,
						icon = icon,
						expanded = expanded,
						content = settingsContent,
					}),
					UI.VStack("NavigationRegion")({
						width = UI.fill(),
						height = { type = "fixed", px = 420 },
						UI.TabView("Destinations")({ style = "collapsible", selection = selected, tabs = tabs }),
					}),
				}),
			})
		end
		return {
			screen = Example,
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
				return { expanded = expanded:peek(), selection = selected:peek(), club = club:peek() }
			end,
			dispose = function() end,
		}
	end,
}
