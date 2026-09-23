--!strict
local desktop = {}
function desktop.create(Facet: any, runtime: any, views: any, model: any, progress: any, options: any?)
	local Host, Compose = runtime.constructors, Facet.Compose
	options = options or {}
	local types = options.types or getfenv(0)
	local UDim2 = types.UDim2
	local UI = Facet.controls(runtime, options)
	return function()
		local tabs = {}
		for _, name in { "Discover", "Avatar", "Chat" } do
			table.insert(tabs, { id = name, label = name, content = views[name] })
		end
		return Host.Frame({
			Name = "Desktop",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			UI.TabView({
				Name = "Apps",
				selection = model.selectedTab,
				tabs = tabs,
				style = "sidebarAdaptable",
				sidebarPreference = "topBar",
				restoreScroll = false,
				transition = { seconds = 0.18 },
				retention = "top",
				Size = UDim2.fromScale(1, 1),
			}),
			Compose.show(function(use)
				return use(progress) < 1
			end, function()
				local veil = Host.Frame({
					Name = "PresentationVeil",
					Size = UDim2.fromScale(1, 1),
					ZIndex = 100,
					BorderSizePixel = 0,
					BackgroundTransparency = function(use)
						return math.clamp((use(progress) - 0.45) / 0.55, 0, 1)
					end,
				})
				veil:AddTag("facet-surface")
				return veil
			end),
		})
	end
end
return desktop
