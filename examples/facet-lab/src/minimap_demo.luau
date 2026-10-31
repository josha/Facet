--!strict
local Art = require("./minimap_art")
local Catalog = require("./catalog_types")
type Context = {
	UI: typeof(require("@repo/tools/typecheck/aliases").FacetControls),
	Host: typeof(require("@repo/tools/typecheck/aliases").RobloxHost),
	Compose: typeof(require("@repo/tools/typecheck/aliases").ComposeModule),
	cell: typeof(require("@repo/tools/typecheck/aliases").CellFactory),
	app: typeof(require("@repo/tools/typecheck/aliases").App),
	types: typeof(require("@repo/tools/typecheck/aliases").RobloxTypes),
}
type Phase = typeof(require("@repo/tools/typecheck/aliases").TransitionContext)
type Use = typeof(require("@repo/tools/typecheck/aliases").Use)
type Entry = { id: string, value: string? }
type ZoomControls = typeof(require("@repo/tools/typecheck/aliases").ZoomControls)
type Properties = { radar: boolean?, expandable: boolean?, compact: boolean? }

local function visible(node: Instance): boolean
	local current: Instance? = node
	while current do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		if current:IsA("ScreenGui") then
			return current.Enabled and current.Parent ~= nil
		end
		current = current.Parent
	end
	return false
end

local function build(c: Context, p: Properties): Frame
	local UI, Host, C = c.UI, c.Host, c.Compose
	local runtime = c.app.runtime
	local Vector2, UDim2, UDim, Enum = c.types.Vector2, c.types.UDim2, c.types.UDim, c.types.Enum
	local radar, expandable = p.radar == true, p.expandable ~= false
	local path = c.cell("mapPath", {} :: { Entry })
	local progress = c.cell("mapProgress", 0.15)
	local range = c.cell("mapRange", 40)
	local headingUp = c.cell("mapHeadingUp", false)
	local running = c.cell("mapRunning", false)
	local form = c.cell("mapForm", 1)
	local zoom = c.cell("mapZoom", 1)
	local camera: ZoomControls = {}
	local env = UI.environment()
	local open = C.formula(function(use: Use): boolean
		return #use(path) > 0
	end)
	local root: Frame
	local available = C.cell(false)
	local origin = Vector2.new(0.5, 0.5)
	local sourceSize = Vector2.new(112, 112)
	local function showMap()
		if expandable and visible(root) and not open:peek() and not env.gameplaySuspended:peek() then
			local current = root:FindFirstChild(`MapForm{form:peek()}`, true)
			local source = if current
				then current:FindFirstChild("MapClip")
				else root:FindFirstChild("MapFallback", true)
			if source and source:IsA("GuiObject") and root.AbsoluteSize.X > 0 and root.AbsoluteSize.Y > 0 then
				origin = (source.AbsolutePosition + source.AbsoluteSize / 2 - root.AbsolutePosition) / root.AbsoluteSize
				sourceSize = source.AbsoluteSize
			end
			path:set({ { id = "map" } })
		end
	end
	local action = Host.InputAction "OpenMinimap" {
		Type = Enum.InputActionType.Bool,
		Host.InputBinding { KeyCode = Enum.KeyCode.M },
		Host.InputBinding { KeyCode = Enum.KeyCode.ButtonY },
		Pressed = showMap,
	}
	local function mapArt(): Frame
		return Art.draw(Host, C, c.types, progress, radar, range, headingUp)
	end
	local function formView(index: number, size: number): Frame
		local active = C.formula(function(use: Use): boolean
			return use(form) == index
		end)
		return UI.VStack(`MapForm{index}`) {
			width = size,
			gap = "xs",
			align = "stretch",
			Host.CanvasGroup "MapClip" {
				Size = UDim2.fromOffset(size, size),
				BackgroundTransparency = 1,
				Host.UICorner { CornerRadius = UDim.new(if radar then 0.5 else 0, 0) },
				C.show(active, mapArt),
				if expandable
					then UI.Button "OpenMapSurface" {
						name = "Expand map",
						label = "",
						BackgroundTransparency = 1,
						Size = UDim2.fromScale(1, 1),
						ZIndex = 5,
						onActivate = showMap,
					}
					else nil,
			},
			UI.Text { text = if radar then "Nearby contacts" else "Course overview", textRole = "caption", wrap = true },
			if expandable
				then UI.Button "OpenMap" { label = "Open map", shortcutHint = action, onActivate = showMap }
				else nil,
		}
	end
	local function hud(): Frame
		return UI.Composition "MinimapHUD" {
			UI.Region "MapRegion" {
				zone = "topRight",
				rank = 2,
				reveal = false,
				form = form,
				formView(1, if p.compact then 144 else 216),
				formView(2, 112),
				if expandable
					then UI.Button "MapFallback" { label = "Map", shortcutHint = action, onActivate = showMap }
					else nil,
			},
			UI.Region "Drive" {
				zone = "topLeft",
				rank = 1,
				reveal = false,
				UI.VStack "DriveControls" {
					width = 112,
					gap = "s",
					UI.Text { text = if radar then "Radar" else "Coast circuit", textRole = "heading", wrap = true },
					UI.Button "AdvanceMap" {
						label = "Advance",
						onActivate = function()
							progress:set((progress:peek() + 0.07) % 1)
						end,
					},
					UI.Button "PauseMap" {
						label = function(use: Use): string
							return if use(running) then "Pause" else "Run"
						end,
						onActivate = function()
							running:set(not running:peek())
						end,
					},
				},
				UI.Button {
					label = "Advance",
					onActivate = function()
						progress:set((progress:peek() + 0.07) % 1)
					end,
				},
			},
		}
	end
	local function fullMap(): Frame
		return UI.Screen "FullMap" {
			surface = "surface",
			gap = "s",
			UI.NavBar "MapHeader" {
				title = if radar then "Radar map" else "Course map",
				trailing = UI.Button "CloseMap" {
					label = "Close map",
					appearance = "utility",
					onActivate = function()
						path:set({})
					end,
				},
			},
			UI.HStack "MapTools" {
				width = "fill",
				wrap = true,
				gap = "s",
				UI.Button "FitMap" {
					label = "Fit",
					onActivate = function()
						if camera.fit then
							camera.fit()
						end
					end,
				},
				if radar
					then UI.Button "RadarRange" {
						label = function(use: Use): string
							return `Range {use(range)} m`
						end,
						onActivate = function()
							range:set(if range:peek() == 40 then 80 else 40)
						end,
					}
					else UI.Text { text = "▲ You   ● Racers   ◆ Checkpoint", wrap = true },
				if radar
					then UI.Button "RadarHeading" {
						label = function(use: Use): string
							return if use(headingUp) then "Heading up" else "North up"
						end,
						onActivate = function()
							headingUp:set(not headingUp:peek())
						end,
					}
					else nil,
			},
			UI.ZoomView "MapZoom" {
				UI.fill(),
				Size = UDim2.fromScale(1, 1),
				contentSize = Vector2.new(360, 360),
				zoom = zoom,
				controls = camera,
				maxZoom = 4,
				enabled = open,
				content = function(): GuiObject
					return Host.Frame "MapBoard" {
						Size = UDim2.fromOffset(360, 360),
						BackgroundTransparency = 1,
						mapArt(),
					}
				end,
			},
			UI.Text {
				text = "Drag to pan. Pinch or Ctrl-wheel to zoom. Select map: bumpers zoom, right stick pans, Y fits.",
				textRole = "caption",
				wrap = true,
			},
		}
	end
	root = Host.Frame "MinimapDemo" {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Host.InputContext "MinimapCommands" {
			Enabled = function(use: Use): boolean
				return expandable and use(available) and not use(open) and not use(env.gameplaySuspended)
			end,
			action,
		},
		UI.NavigationStack "MapNavigation" {
			path = path,
			chrome = "hidden",
			transition = {
				motion = "zoomPresent",
				apply = function(content: GuiObject, phase: Phase)
					if not content:FindFirstChild("FullMap", true) then
						return
					end
					local size = runtime.observe(root, "AbsoluteSize")
					runtime.decorate(content, {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = function(use: Use): UDim2
							local center = origin:Lerp(Vector2.new(0.5, 0.5), use(phase.progress))
							return UDim2.fromScale(center.X, center.Y)
						end,
					})
					runtime.mountFragment(function(): { unknown }
						return {
							Host.UIScale "MapExpansion" {
								Scale = function(use: Use): number
									local bounds = use(size) :: Vector2
									local start = math.clamp(
										math.min(
											sourceSize.X / math.max(1, bounds.X),
											sourceSize.Y / math.max(1, bounds.Y)
										),
										0.01,
										1
									)
									return start + (1 - start) * use(phase.progress)
								end,
							},
						}
					end, content)
				end,
			},
			root = { content = hud },
			destinations = { map = { content = fullMap, initialFocus = "MapZoom" } },
		},
	}
	local elapsed = 0
	local connection = game:GetService("RunService").Heartbeat:Connect(function(dt: number)
		local shown = visible(root)
		available:set(shown)
		if not shown or not running:peek() or env.reducedMotion:peek() then
			elapsed = 0
			return
		end
		elapsed += dt
		if elapsed >= 0.1 then
			progress:set((progress:peek() + elapsed / 30) % 1)
			elapsed = 0
		end
	end)
	C.cleanup(function()
		connection:Disconnect()
	end)
	return root
end

local page: Catalog.PageDefinition = {
	family = "layout",
	title = "Minimap patterns",
	recipe = true,
	matrix = false,
	fills = true,
	purpose = "Follow a race course or nearby contacts, open the map, then return to the same HUD.",
	note = "The map fills this sample viewport. Mount it at the app root for full screen. Press Run to move contacts, or Advance for one step. Reduced motion pauses the simulation. The game owns drawing and contact visibility.",
	alternatives = "Use a passive radar when no larger map is needed. ZoomView supplies pan and zoom.",
	snippet = 'UI.Region { zone = "topRight", rank = 2, reveal = false, normalMap, compactMap, mapButton }',
	cellWidth = 600,
	cellHeight = 460,
	axes = {
		{ key = "radar", values = { false, true } },
		{ key = "expandable", values = { true, false } },
		{ key = "compact", values = { false, true } },
	},
	states = {},
	make = function(_UI, p: Properties, c: Context): Instance
		return build(c, p)
	end,
}
return { page = page, build = build }
