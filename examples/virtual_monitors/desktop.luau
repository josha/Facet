--!strict
local desktop = {}
function desktop.create(Facet: any, runtime: any, views: any, model: any, progress: any, options: any?)
	local Host, Compose = runtime.constructors, Facet.Compose
	options = options or {}
	local types = options.types or getfenv(0)
	local UDim2 = types.UDim2
	local Vector2, Enum = types.Vector2, types.Enum
	local UI = Facet.controls(runtime, options)
	local adaptive = Facet.adaptive
	return function()
		local env = UI.environment()
		local you = UI.worldAnchor({ target = Compose.cell(options.player), offscreen = "retain" })
		local tabs = {}
		local icons = { Discover = "facet:search", Avatar = "person", Chat = "edit" }
		for _, name in { "Discover", "Avatar", "Chat" } do
			table.insert(tabs, {
				id = name,
				label = name,
				icon = icons[name],
				content = views[name],
				badge = if name == "Chat"
					then function(use)
						local unread = use(model.chatUnread)
						return if unread > 0 then unread else nil
					end
					else nil,
			})
		end
		local root = Host.CanvasGroup "Desktop" {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			GroupTransparency = function(use)
				local t = math.clamp((use(progress) - 0.55) / 0.45, 0, 1)
				return 1 - t * t * (3 - 2 * t)
			end,
			UI.TabView "Apps" {
				selection = model.selectedTab,
				tabs = tabs,
				style = "sidebarAdaptable",
				sidebarPreference = "sidebar",
				railWidth = function(use)
					return if adaptive.sizeClassAtLeast(use(env.sizeClass), "wide") then 176 else 148
				end,
				restoreScroll = false,
				transition = { seconds = 0.18 },
				retention = "top",
				Size = UDim2.fromScale(1, 1),
			},
			Host.TextLabel "YouMarker" {
				Text = "You",
				AutomaticSize = Enum.AutomaticSize.XY,
				AnchorPoint = Vector2.new(0.5, 1),
				BackgroundTransparency = 1,
				ZIndex = 5,
				Visible = function(use)
					local point = use(you.anchor)
					return point.visible and point.onscreen == true and use(progress) < 1
				end,
				Position = function(use)
					local point, insets = use(you.anchor), use(env.safeInsets)
					return UDim2.fromOffset((point.x or 0) - insets.left, (point.y or 0) - insets.top)
				end,
			},
		}
		root:AddTag("facet-surface")
		return root
	end
end
return desktop
