--!strict
local desktop = {}
local screens = require("./screens")
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
		local icons = { Discover = "facet:search", Avatar = "person", Chat = "edit", Flap = "chevron.up" }
		for _, name in screens.APPS do
			table.insert(tabs, {
				id = name,
				label = if name == "Flap" then "Facet Flap" else name,
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
		local steps = { "Find server", "Load world", "Join" }
		local function launching(use)
			local launch = use(model.launch)
			return if launch and launch.stage <= 3 then launch else nil
		end
		local function title(use)
			local launch = launching(use)
			for _, item in if launch then use(model.catalog.items) else {} do
				if item.id == launch.id then
					return item.title
				end
			end
			return ""
		end
		local function stage(use)
			local launch = launching(use)
			return if launch then launch.stage else 1
		end
		local function panel(stack, name, ...)
			local plate = stack(name)({ gap = "xs", padding = "s", Host.UICorner({}), ... })
			plate:AddTag("facet-panel")
			return plate
		end
		local overlay = UI.Composition "LaunchOverlay" {
			ZIndex = 4,
			Visible = function(use)
				return launching(use) ~= nil
			end,
			UI.Region "Launch" {
				zone = "bottomRight",
				rank = 1,
				mayDrop = true,
				panel(
					UI.VStack,
					"LaunchCard",
					UI.Text "LaunchTitle" { text = title, textRole = "label" },
					UI.Text "LaunchStage" {
						role = "secondary",
						textRole = "caption",
						text = function(use)
							return `{steps[stage(use)]}, step {stage(use)} of 3 (simulated)`
						end,
					}
				),
				panel(
					UI.HStack,
					"LaunchChip",
					UI.Text "LaunchChipText" {
						textRole = "caption",
						text = function(use)
							return `Joining {stage(use)}/3`
						end,
					}
				),
			},
		}
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
				shoulderNavigation = "content",
				railWidth = function(use)
					return if adaptive.sizeClassAtLeast(use(env.sizeClass), "wide") then 176 else 148
				end,
				restoreScroll = false,
				transition = { seconds = 0.18 },
				retention = "top",
				Size = UDim2.fromScale(1, 1),
			},
			overlay,
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

		UI.responder(root, { passive = false })

		local sidebar = (root:FindFirstChild("Apps") :: any):FindFirstChild("Tabs")
		if sidebar then
			UI.focusSection(sidebar)
		end
		return root
	end
end
return desktop
