--!strict
-- Screen mode owns presentation; application models survive page disposal.
local desktop = {}
function desktop.create(Compose: any, app: any, apps: any, mode: any, selectedTab: any, modeProgress: any?)
	local UI = app.controls
	local function progress(use)
		return if modeProgress then use(modeProgress) else (if use(mode) == "Screen" then 1 else 0)
	end
	local tabs = {}
	for _, name in { "Discover", "Avatar", "Chat" } do
		table.insert(tabs, { id = name, label = name, content = apps[name] })
	end
	return function()
		return UI.Screen("Desktop")({
			surface = function(use)
				return "plain"
			end,
			hidden = function(use)
				return progress(use) <= 0
			end,
			padding = 0,
			gap = "m",
			Compose.show(function(use)
				return progress(use) > 0
			end, function()
				return UI.ZStack("Presentation")({
					width = { type = "fill" },
					height = { type = "fill" },
					surface = "base",
					opacity = function(use)
						return math.clamp((progress(use) - 0.45) / 0.55, 0, 1)
					end,
					UI.TabView("Apps")({
						style = "sidebarAdaptable",
						sidebarPreference = "topBar",
						selection = selectedTab,
						restoreScroll = false,
						transition = { fade = true },
						tabs = tabs,
					}),
				})
			end),
		})
	end
end
return desktop
