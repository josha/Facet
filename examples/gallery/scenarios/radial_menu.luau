--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type Child = typeof(require("@repo/tools/typecheck/aliases").Child)
type RadialSpec = typeof(require("@repo/tools/typecheck/aliases").RadialSpec)
type RegionZone = typeof(require("@repo/tools/typecheck/aliases").RegionZone)
type Radial = typeof(require("@repo/tools/typecheck/aliases").RadialItem)
type Fit = "both" | "radial" | "angular" | "none"
type Corner = "bottom-left" | "bottom-right" | "top-right" | "top-left"
type Center = "empty" | "back"
type Scrim = "none" | "dark" | "light"
type Scene = {
	id: string,
	kind: string,
	skin: boolean,
	separate: boolean,
	fit: Fit,
	corner: Corner,
	center: Center,
	passThrough: boolean,
	scrim: Scrim,
}
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T
type ExampleContext = typeof(require("@repo/examples/types").Context)

return {
	title = "Quick actions",
	ledgerRows = {},
	build = function(ctx: ExampleContext)
		local UI = ctx.UI
		local Host = ctx.Host
		local Compose: ComposeModule = ctx.Compose
		local nativeTypes = ctx.types
		local UDim, UDim2, Vector2, Color3, Enum =
			nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum
		local selected = Compose.cell("corner")
		local status = Compose.cell("Ready for a little adventure")
		local glow = Compose.cell(false)
		local moving = Compose.cell(false)
		local skinned = Compose.cell(false)
		local separate = Compose.cell(false)
		local initialCorner: Corner = "bottom-left"
		local corner = Compose.cell(initialCorner)
		local corners: { Corner } = { "bottom-left", "bottom-right", "top-right", "top-left" }
		local cornerZones: { [Corner]: RegionZone } = {
			["bottom-left"] = "bottomLeft",
			["bottom-right"] = "bottomRight",
			["top-right"] = "topRight",
			["top-left"] = "topLeft",
		}
		local initialFit: Fit = "radial"
		local fitting = Compose.cell(initialFit)
		local fitModes: { Fit } = { "both", "radial", "angular", "none" }
		local fitNames = { both = "Hug content", radial = "Slim band", angular = "Short arcs", none = "Full arcs" }
		local advanced = Compose.cell(false)
		local passThrough = Compose.cell(false)
		local initialCenter: Center = "empty"
		local centerPolicy = Compose.cell(initialCenter)
		local initialScrim: Scrim = "none"
		local dim = Compose.cell(initialScrim)
		local lastAction = Compose.cell("ready")
		local current: Frame? = nil
		local currentPresented: typeof(Compose.cell(false))? = nil
		local worldState: (() -> { angle: number, unpacked: boolean, taken: boolean })? = nil
		local function action(id: string, text: string)
			return function()
				lastAction:set(id)
				status:set(text)
			end
		end
		local scenes = Compose.formula(function(use: Use): { Scene }
			return {
				{
					id = use(selected)
						.. ":"
						.. tostring(use(skinned))
						.. ":"
						.. tostring(use(centerPolicy))
						.. ":"
						.. tostring(use(passThrough))
						.. ":"
						.. tostring(use(separate))
						.. ":"
						.. tostring(use(fitting))
						.. ":"
						.. tostring(use(corner))
						.. ":"
						.. tostring(use(dim)),
					kind = use(selected),
					skin = use(skinned),
					separate = use(separate),
					fit = use(fitting),
					corner = use(corner),
					center = use(centerPolicy),
					passThrough = use(passThrough),
					scrim = use(dim),
				},
			}
		end)
		local function scene(itemReadable: Readable<Scene>)
			local item = itemReadable:peek()
			local items: { Radial }
			local menu = nil
			local presented = Compose.cell(false)
			local turnAngle, unpacked, taken = Compose.cell(0), Compose.cell(false), Compose.cell(false)
			local stage: GuiObject?
			local Vector3, CFrame = ctx.types.Vector3, ctx.types.CFrame
			local spec: RadialSpec = {
				Name = "Commands",
				items = {},

				center = "empty",
				contentFit = item.fit,
				scrim = item.scrim,
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
					Visible = function(use: Use)
						return not use(taken)
					end,
					content = function(runtime, world): (() -> ())?
						return runtime.mount(function()
							return Host.Model("TrailPack")({
								Host.Part("Bag")({
									Anchored = true,
									CanCollide = false,
									Color = Color3.fromRGB(91, 121, 80),
									Size = function(use: Use)
										return Vector3.new(1.7, if use(unpacked) then 2.5 else 1.8, 0.9)
									end,
									CFrame = function(use: Use)
										return CFrame.Angles(0, math.rad(use(turnAngle)), 0)
									end,
								}),
								Host.Part("Pocket")({
									Anchored = true,
									CanCollide = false,
									Color = Color3.fromRGB(51, 76, 44),
									Size = Vector3.new(1.2, 0.75, 0.35),
									Position = Vector3.new(0, -0.35, 0.6),
								}),
							})
						end, world)
					end,
				}
				worldState = function()
					return { angle = turnAngle:peek(), unpacked = unpacked:peek(), taken = taken:peek() }
				end
				spec.preset, spec.center = "donut", "empty"
				spec.anchor = stage
				spec.ringWidth = "narrow"
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
				local packItems: { Radial } = {
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
				}
				items = {
					{
						id = "look",
						label = "Look",
						icon = "facet:search",
						onSelect = action("look", "You spotted a trail beyond the trees."),
					},
					{
						id = "pack",
						label = "Pack",
						icon = "menu",
						navigation = "replace",
						children = packItems,
					},
					{
						id = "wave",
						label = "Wave",
						icon = "flag",
						onSelect = action("wave", "You wave hello to a friend."),
					},
				}
			elseif item.kind == "gestures" then
				spec.preset = "donut"
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
				spec.ringWidth = "narrow"
				local toolItems: { Radial } = {
					{
						id = "lantern",
						label = "Lantern",
						compactLabel = { icon = "increment" },
						checked = glow,
						onChange = function(on: boolean)
							status:set(if on then "Lantern on. A little light for the trail." else "Lantern off.")
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
				}
				local equipmentItems: { Radial } = {
					{
						id = "tools",
						label = "Tools",
						icon = "edit",
						navigation = "expand",
						expansion = "fan",
						children = toolItems,
					},
					{
						id = "wear",
						label = "Wear",
						completion = "back",
						onSelect = action("wear", "Your adventure gear is on."),
					},
				}
				items = {
					{
						id = "equipment",
						label = "Equipment",
						compactLabel = { icon = "menu", prefer = true },
						icon = "menu",
						navigation = "replace",
						children = equipmentItems,
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
			local armAngle = Compose.formula(function(use: Use)
				local a = use(lastAction)
				return if a == "wave" or a == "cheer" then -55 elseif a == "point" then -90 else 12
			end)
			local bodyY = Compose.formula(function(use: Use)
				return if use(lastAction) == "sit" then 14 else 0
			end)
			local orbit = ctx.runtime.timeline({ duration = 4, repeats = math.huge, autoplay = false })
			Compose.watch(function(use: Use)
				if use(moving) then
					orbit:play()
				else
					orbit:pause()
				end
			end)
			local silhouette = Host.Frame("Explorer")({
				BackgroundTransparency = 1,
				Size = UDim2.new(0, 76, 0, 110),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = function(use: Use)
					return UDim2.new(0.5, 32 * math.sin(use(orbit.progress) * math.pi * 2), 0.5, use(bodyY))
				end,
				Host.Frame("Head")({
					BackgroundColor3 = Color3.fromRGB(229, 181, 139),
					Size = UDim2.new(0, 32, 0, 32),
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 0, 0),
				}),
				Host.Frame("Coat")({
					BackgroundColor3 = Color3.fromRGB(80, 135, 93),
					Size = UDim2.new(0, 40, 0, 46),
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.new(0.5, 0, 0.5, 0),
				}),
				Host.Frame("Arm")({
					Position = UDim2.fromOffset(60, 32),
					BackgroundColor3 = Color3.fromRGB(80, 135, 93),
					Size = UDim2.new(0, 12, 0, 42),
					Rotation = armAngle,
				}),
				Host.Frame("LegLeft")({
					Position = UDim2.fromOffset(22, 80),
					BackgroundColor3 = Color3.fromRGB(43, 59, 84),
					Size = UDim2.new(0, 13, 0, 30),
				}),
				Host.Frame("LegRight")({
					Position = UDim2.fromOffset(42, 80),
					BackgroundColor3 = Color3.fromRGB(43, 59, 84),
					Size = UDim2.new(0, 13, 0, 30),
				}),
			})
			if item.kind == "character" or item.kind == "gestures" then
				spec.anchor = silhouette
			end
			local menuNode = UI.RadialMenu(spec)
			current, currentPresented = menu, presented
			Compose.cleanup(function()
				if current == menu then
					current, currentPresented, worldState = nil, nil, nil
				end
			end)
			local zone: RegionZone = if item.kind == "corner" then cornerZones[item.corner] else "bottomLeft"
			return UI.Composition "Scene" {
				LayoutOrder = 3,
				Size = UDim2.new(1, 0, 0, 260),
				Host.UIFlexItem({ FlexMode = Enum.UIFlexMode.Grow }),
				UI.Region "Subject" {
					zone = "center",
					rank = 1,
					if item.kind == "world"
						then stage
						else Host.Frame("Orbit")({
							BackgroundTransparency = 1,
							Size = UDim2.fromOffset(140, 120),
							silhouette,
						}),
				},
				UI.Region "LauncherCorner" {
					zone = zone,
					rank = 2,
					menuNode,
				},
			}
		end
		local modes = {
			{ value = "corner", label = "Corner commands" },
			{ value = "gestures", label = "Quick gestures" },
			{ value = "character", label = "Character commands" },
			{ value = "world", label = "Nearby item" },
		}
		local instruction = Compose.formula(function(use: Use)
			local tab = use(selected)
			return if tab == "gestures"
				then "Tap •••, then choose. Or press, slide to an action, and release."
				elseif tab == "corner" then "Open the corner menu. Pack takes you into your supplies."
				elseif tab == "world" then "Open the pack’s actions, then inspect, unpack, or pick it up."
				else "Open your commands. Equipment leads to Tools. The explorer stays in view."
		end)
		local disclosure = UI.DisclosureGroup "Advanced" {
			LayoutOrder = 5,
			label = "More options",
			expanded = advanced,
			content = function(): Instance
				local children: { Child } = {
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Vertical,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
					}),
					UI.Button "ContentFit" {
						label = Compose.formula(function(use: Use)
							return "Arc shape: " .. fitNames[use(fitting)]
						end),
						onActivate = function()
							fitting:set(fitModes[assert(table.find(fitModes, fitting:peek())) % #fitModes + 1])
						end,
					},
					UI.Button "CornerPosition" {
						label = Compose.formula(function(use: Use)
							return "Corner: " .. use(corner)
						end),
						onActivate = function()
							corner:set(corners[assert(table.find(corners, corner:peek())) % #corners + 1])
						end,
					},
					UI.Toggle "Separate" {
						label = "Separate character icons",
						value = separate,
					},
					UI.Toggle "Skin" { label = "Jewel buttons", value = skinned },
					UI.Toggle "Move" { label = "Let the explorer wander", value = moving },
					UI.Toggle "PassThrough" {
						label = "Allow taps through the center",
						value = passThrough,
					},
					UI.Button "Scrim" {
						label = Compose.formula(function(use: Use)
							return "Page dim: " .. use(dim)
						end),
						onActivate = function()
							local order: { Scrim } = { "none", "dark", "light" }
							dim:set(order[assert(table.find(order, dim:peek())) % #order + 1])
						end,
					},
					UI.Button "CenterPolicy" {
						label = Compose.formula(function(use: Use)
							return "Center: " .. use(centerPolicy)
						end),
						onActivate = function()
							centerPolicy:set(if centerPolicy:peek() == "empty" then "back" else "empty")
						end,
					},
				}
				return Host.Frame({
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					table.unpack(children),
				})
			end,
		}
		local function sceneRows()
			return Compose.OrderedCollection({
				from = function(use: Use)
					return use(scenes)
				end,
				key = function(s)
					return s.id
				end,
				render = scene,
			})
		end
		local function controls(): { Child }
			return {
				UI.Picker "Tabs" {
					LayoutOrder = 1,
					selected = selected,
					options = modes,
				},
				Host.Frame("InstructionPlate")({
					LayoutOrder = 2,
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
				}),
				Host.Frame("ResultPlate")({
					LayoutOrder = 4,
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
				}),
				disclosure,
			}
		end
		local function screen()
			local content = controls()
			table.insert(content, 3, sceneRows())
			return UI.ScrollView "RadialMenu" {
				padding = 16,
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				ScrollBarThickness = 6,
				Host.Frame("Body")({
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					AutomaticSize = Enum.AutomaticSize.Y,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Vertical,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 12),
					}),
					table.unpack(content),
				}),
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
