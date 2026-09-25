--!strict

return {
	title = "Quick actions",
	ledgerRows = {},
	build = function(ctx)
		local UI = ctx.UI
		local Host = ctx.Host
		local Compose = ctx.Compose
		local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Vector2 = Vector2, Color3 = Color3, Enum = Enum }
		local UDim, UDim2, Vector2, Color3, Enum =
			nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum
		local selected = Compose.cell("corner")
		local status = Compose.cell("Ready for a little adventure")
		local glow = Compose.cell(false)
		local moving = Compose.cell(false)
		local skinned = Compose.cell(false)
		local separate = Compose.cell(false)
		local corner = Compose.cell("bottom-left")
		local corners = { "bottom-left", "bottom-right", "top-right", "top-left" }
		local fitting = Compose.cell("radial")
		local fitModes = { "both", "radial", "angular", "none" }
		local fitNames = { both = "Hug content", radial = "Slim band", angular = "Short arcs", none = "Full arcs" }
		local advanced = Compose.cell(false)
		local passThrough = Compose.cell(false)
		local centerPolicy = Compose.cell("empty")
		local lastAction = Compose.cell("ready")
		local current, currentPresented = nil, nil
		local worldState = nil
		local function action(id, text)
			return function()
				lastAction:set(id)
				status:set(text)
			end
		end
		local scenes = Compose.formula(function(use)
			return {
				{
					id = use(selected) .. ":" .. tostring(use(skinned)) .. ":" .. use(centerPolicy) .. ":" .. tostring(
						use(passThrough)
					) .. ":" .. tostring(use(separate)) .. ":" .. use(fitting) .. ":" .. use(corner),
					kind = use(selected),
					skin = use(skinned),
					separate = use(separate),
					fit = use(fitting),
					corner = use(corner),
					center = use(centerPolicy),
					passThrough = use(passThrough),
				},
			}
		end)
		local function scene(itemReadable)
			local item = itemReadable:peek()
			local items
			local menu = nil
			local presented = Compose.cell(false)
			local turnAngle, unpacked, taken = Compose.cell(0), Compose.cell(false), Compose.cell(false)
			local stage
			local Vector3, CFrame = ctx.types.Vector3, ctx.types.CFrame
			local spec = {
				Name = "Commands",

				center = "empty",
				label = "Quick actions",
				contentFit = item.fit,
				isPresented = presented,
				ref = function(record)
					menu = record
				end,
			}
			if item.kind == "world" then
				stage = UI.Stage "TrailPack" {
					Size = UDim2.fromOffset(260, 200),
					Position = UDim2.fromScale(0.5, 0.5),
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundTransparency = 1,
					Visible = function(use)
						return not use(taken)
					end,
					content = function(runtime, world)
						return runtime.mount(function()
							return Host.Model "TrailPack" {
								Host.Part "Bag" {
									Anchored = true,
									CanCollide = false,
									Color = Color3.fromRGB(91, 121, 80),
									Size = function(use)
										return Vector3.new(1.7, if use(unpacked) then 2.5 else 1.8, 0.9)
									end,
									CFrame = function(use)
										return CFrame.Angles(0, math.rad(use(turnAngle)), 0)
									end,
								},
								Host.Part "Pocket" {
									Anchored = true,
									CanCollide = false,
									Color = Color3.fromRGB(51, 76, 44),
									Size = Vector3.new(1.2, 0.75, 0.35),
									Position = Vector3.new(0, -0.35, 0.6),
								},
							}
						end, world)
					end,
				}
				worldState = function()
					return { angle = turnAngle:peek(), unpacked = unpacked:peek(), taken = taken:peek() }
				end
				spec.preset, spec.center = "donut", "empty"
				spec.anchor = stage
				spec.ringWidth = 48
				spec.appearance = if item.separate then "buttons" else "wedges"
				items = {
					{
						id = "inspect",
						label = "Inspect",
						icon = "facet:search",
						completion = "stay",
						onSelect = function()
							turnAngle:update(function(value)
								return value + 45
							end)
							action("inspect", "A sturdy trail pack. Turn it to inspect the pocket.")()
						end,
					},
					{
						id = "resize",
						label = "Unpack",
						icon = "menu",
						completion = "stay",
						onSelect = function()
							unpacked:update(function(value)
								return not value
							end)
							action("resize", "The pack expands. The menu adjusts around it.")()
						end,
					},
					{
						id = "take",
						label = "Pick up",
						icon = "checkmark",
						onSelect = function()
							taken:set(true)
							action("take", "Pack collected. Switch tabs and return to try again.")()
						end,
					},
				}
			elseif item.kind == "corner" then
				spec.preset = item.corner
				spec.appearance = "buttons"
				items = {
					{
						id = "look",
						label = "Look",
						icon = "facet:search",
						labelStyle = "both",
						onSelect = action("look", "You spotted a trail beyond the trees."),
					},
					{
						id = "pack",
						label = "Pack",
						icon = "menu",
						navigation = "replace",
						children = {
							{
								id = "map",
								label = "Map",
								compactLabel = { icon = "flag" },
								onSelect = action("map", "Map opened. The lookout is just ahead."),
							},
							{
								id = "snack",
								label = "Snack",
								compactLabel = { icon = "checkmark" },
								onSelect = action("snack", "A quick snack. Ready to keep exploring."),
							},
						},
					},
					{
						id = "wave",
						label = "Wave",
						icon = "flag",
						onSelect = action("wave", "You wave hello to a friend."),
					},
				}
			elseif item.kind == "gestures" then
				spec.preset = "circle"
				spec.distribution = "compass"
				spec.gestureSelection = "direction"
				spec.center = "back"
				spec.appearance = "wedges"
				items = {
					{
						id = "wave",
						label = "Wave",
						slot = "N",
						icon = "flag",
						onSelect = action("wave", "You wave hello to a friend."),
					},
					{
						id = "cheer",
						label = "Cheer",
						slot = "NE",
						icon = "increment",
						onSelect = action("cheer", "A cheer for the next adventure!"),
					},
					{
						id = "point",
						label = "Point",
						slot = "E",
						icon = "chevron.trailing",
						onSelect = action("point", "You point toward the lookout."),
					},
					{
						id = "sit",
						label = "Sit",
						slot = "SW",
						icon = "chevron.down",
						onSelect = action("sit", "You take a seat and enjoy the view."),
					},
					{
						id = "inspect",
						label = "Inspect",
						slot = "W",
						icon = "facet:search",
						onSelect = action("inspect", "Trail guide · explorer · ready to help"),
					},
				}
			else
				spec.preset = "donut"
				spec.appearance = if item.separate then "buttons" else "wedges"
				spec.center = item.center
				spec.centerPassThrough = item.passThrough
				spec.clearance = 82
				spec.ringWidth = 48
				items = {
					{
						id = "equipment",
						label = "Equipment",
						compactLabel = { icon = "menu", prefer = true },
						icon = "menu",
						navigation = "replace",
						children = {
							{
								id = "tools",
								label = "Tools",
								icon = "edit",
								navigation = "expand",
								expansion = "fan",
								children = {
									{
										id = "lantern",
										label = "Lantern",
										compactLabel = { icon = "increment" },
										checked = glow,
										onChange = function(on)
											status:set(
												if on
													then "Lantern on. A little light for the trail."
													else "Lantern off."
											)
										end,
									},
									{
										id = "stow",
										label = "Stow",
										compactLabel = { icon = "chevron.leading" },
										completion = "back",
										onSelect = action("stow", "Tools tucked away. Back to equipment."),
									},
									{
										id = "ready",
										label = "Ready",
										compactLabel = { icon = "checkmark" },
										completion = "root",
										onSelect = action("ready", "All set. Back to your main commands."),
									},
								},
							},
							{
								id = "wear",
								label = "Wear",
								completion = "back",
								onSelect = action("wear", "Your adventure gear is on."),
							},
						},
					},
					{
						id = "wave",
						label = "Wave",
						icon = "flag",
						labelStyle = "icon",
						completion = "close",
						onSelect = action("wave", "You wave, then return to exploring."),
					},
					{
						id = "inspect",
						label = "Inspect",
						compactLabel = { icon = "facet:search", prefer = true },
						completion = "stay",
						onSelect = action(
							"inspect",
							"Trail guide · explorer · lantern " .. (if glow:peek() then "on" else "off")
						),
					},
				}
			end
			spec.items = items
			if item.skin then
				spec.appearance = "buttons"
				spec.buttonSurface = "none"

				spec.skin =
					{ item = { default = "rbxassetid://75192659975960", pressed = "rbxassetid://119648517302972" } }
			end
			local armAngle = Compose.formula(function(use)
				local a = use(lastAction)
				return if a == "wave" or a == "cheer" then -55 elseif a == "point" then -90 else 12
			end)
			local bodyY = Compose.formula(function(use)
				return if use(lastAction) == "sit" then 14 else 0
			end)
			local orbit = ctx.runtime.timeline({ duration = 4, repeats = math.huge, autoplay = false })
			Compose.watch(function(use)
				if use(moving) then
					orbit:play()
				else
					orbit:pause()
				end
			end)
			local silhouette = Host.Frame "Explorer" {
				BackgroundTransparency = 1,
				Size = UDim2.new(0, 76, 0, 110),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = function(use)
					return UDim2.new(0.5, 32 * math.sin(use(orbit.progress) * math.pi * 2), 0.5, use(bodyY))
				end,
				Host.Frame "Head" {
					BackgroundColor3 = Color3.fromRGB(229, 181, 139),
					Size = UDim2.new(0, 32, 0, 32),
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 0, 0),
				},
				Host.Frame "Coat" {
					BackgroundColor3 = Color3.fromRGB(80, 135, 93),
					Size = UDim2.new(0, 40, 0, 46),
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.new(0.5, 0, 0.5, 0),
				},
				Host.Frame "Arm" {
					Position = UDim2.fromOffset(60, 32),
					BackgroundColor3 = Color3.fromRGB(80, 135, 93),
					Size = UDim2.new(0, 12, 0, 42),
					Rotation = armAngle,
				},
				Host.Frame "LegLeft" {
					Position = UDim2.fromOffset(22, 80),
					BackgroundColor3 = Color3.fromRGB(43, 59, 84),
					Size = UDim2.new(0, 13, 0, 30),
				},
				Host.Frame "LegRight" {
					Position = UDim2.fromOffset(42, 80),
					BackgroundColor3 = Color3.fromRGB(43, 59, 84),
					Size = UDim2.new(0, 13, 0, 30),
				},
			}
			if item.kind == "character" then
				spec.anchor = silhouette
			end
			local menuNode = UI.RadialMenu(spec)
			current, currentPresented = menu, presented
			Compose.cleanup(function()
				if current == menu then
					current, currentPresented, worldState = nil, nil, nil
				end
			end)
			local root = Host.Frame "Scene" {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 380),
				if item.kind == "world" then stage else silhouette,
				menuNode,
			}
			return root
		end
		local modes = {
			{ value = "corner", label = "Corner commands" },
			{ value = "gestures", label = "Quick gestures" },
			{ value = "character", label = "Character commands" },
			{ value = "world", label = "Nearby item" },
		}
		local instruction = Compose.formula(function(use)
			local tab = use(selected)
			return if tab == "gestures"
				then "Tap •••, then choose. Or press, slide to an action, and release."
				elseif tab == "corner" then "Open the corner menu. Pack takes you into your supplies."
				elseif tab == "world" then "Open the pack’s actions, then inspect, unpack, or pick it up."
				else "Open your commands. Equipment leads to Tools. The explorer stays in view."
		end)
		local disclosure = UI.DisclosureGroup "Advanced" {
			label = "More options",
			expanded = advanced,
			content = function()
				return Host.Frame({
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Vertical,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
					}),
					UI.Button "ContentFit" {
						label = Compose.formula(function(use)
							return "Arc shape: " .. fitNames[use(fitting)]
						end),
						onActivate = function()
							fitting:set(fitModes[(table.find(fitModes, fitting:peek()) :: number) % #fitModes + 1])
						end,
					},
					UI.Button "CornerPosition" {
						label = Compose.formula(function(use)
							return "Corner: " .. use(corner)
						end),
						onActivate = function()
							corner:set(corners[(table.find(corners, corner:peek()) :: number) % #corners + 1])
						end,
					},
					UI.Toggle "Separate" {
						label = "Separate character icons",
						value = separate,
					},
					UI.Toggle "Skin" {
						label = "Jewel buttons",
						value = skinned,
					},
					UI.Toggle "Move" {
						label = "Let the explorer wander",
						value = moving,
					},
					UI.Toggle "PassThrough" {
						label = "Allow taps through the center",
						value = passThrough,
					},
					UI.Button "CenterPolicy" {
						label = Compose.formula(function(use)
							return "Center: " .. use(centerPolicy)
						end),
						onActivate = function()
							centerPolicy:set(if centerPolicy:peek() == "empty" then "back" else "empty")
						end,
					},
				})
			end,
		}
		local function sceneRows()
			return Compose.OrderedCollection({
				from = scenes,
				key = function(s)
					return s.id
				end,
				render = scene,
			})
		end
		local function controls()
			return {
				UI.Picker "Tabs" {
					selected = selected,
					options = modes,
				},
				Host.Frame "InstructionPlate" {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					UI.Text "Instruction" {
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = instruction,
						textRole = "caption",
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					},
				},
				Host.Frame "ResultPlate" {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					UI.Text "Result" {
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = status,
						textRole = "body",
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					},
				},
				disclosure,
			}
		end
		local function screen()
			local content = controls()
			table.insert(content, 3, sceneRows())
			return Host.ScrollingFrame "RadialMenu" {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				CanvasSize = UDim2.fromOffset(0, 0),
				ScrollBarThickness = 6,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 12),
				}),
				Host.UIPadding({
					PaddingTop = UDim.new(0, 16),
					PaddingBottom = UDim.new(0, 16),
					PaddingLeft = UDim.new(0, 16),
					PaddingRight = UDim.new(0, 16),
				}),
				table.unpack(content),
			}
		end
		return {
			screen = screen,
			steps = {
				world = function()
					selected:set("world")
				end,
				fitBoth = function()
					fitting:set("both")
				end,
				fitRadial = function()
					fitting:set("radial")
				end,
				fitAngular = function()
					fitting:set("angular")
				end,
				fitNone = function()
					fitting:set("none")
				end,
				corner = function()
					selected:set("corner")
				end,
				gestures = function()
					selected:set("gestures")
				end,
				orbit = function()
					selected:set("character")
					separate:set(true)
				end,
				wedges = function()
					separate:set(false)
				end,
				skin = function()
					skinned:set(true)
				end,
				native = function()
					skinned:set(false)
				end,
				move = function()
					moving:set(true)
				end,
				still = function()
					moving:set(false)
				end,
				passThrough = function()
					passThrough:set(true)
				end,
				centerBack = function()
					centerPolicy:set("back")
				end,
				close = function()
					if currentPresented then
						currentPresented:set(false)
					end
				end,
				open = function()
					if currentPresented then
						currentPresented:set(true)
					end
				end,
				character = function()
					selected:set("character")
				end,
				reset = function()
					if currentPresented then
						currentPresented:set(false)
					end
					selected:set("gestures")
					glow:set(false)
					moving:set(false)
					skinned:set(false)
					separate:set(false)
					passThrough:set(false)
					centerPolicy:set("empty")
					advanced:set(false)
					fitting:set("both")
					status:set("Ready for a little adventure")
					lastAction:set("ready")
				end,
			},
			report = function()
				return {
					tab = selected:peek(),
					status = status:peek(),
					menu = if currentPresented then { isPresented = currentPresented:peek() } else nil,
					world = if worldState then worldState() else nil,
				}
			end,
		}
	end,
}
