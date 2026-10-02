--!strict
local makeView = require("./showcase_view")
local rules = require("./outpost_terminal/rules")
return {
	title = "Outpost",
	build = function(ctx: any)
		local UI, Host, C = ctx.UI, ctx.Host, ctx.Compose
		local V3, V2, CF, C3, E, D2 =
			ctx.types.Vector3, ctx.types.Vector2, ctx.types.CFrame, ctx.types.Color3, ctx.types.Enum, ctx.types.UDim2
		local view = makeView(ctx)
		local confirmed, draft = C.cell(rules.copy(rules.START)), {}
		local worldMode, controlsOpen = C.cell(false), C.cell(false)
		local notice = C.cell("Restore the door, beacon, and workshop using six power units.")
		for _, consumer in rules.CONSUMERS do
			draft[consumer.id] = C.cell(rules.START[consumer.id])
		end
		local function allocation(use: ((any) -> any)?)
			local values = {}
			for id, cell in draft do
				values[id] = if use then use(cell) else cell:peek()
			end
			return values
		end
		local verdict = C.formula(function(use: any)
			return rules.validate(allocation(use))
		end)
		local function apply()
			local nextState = allocation()
			local valid = rules.validate(nextState)
			if not valid.ok then
				notice:set(valid.message)
				return false
			end
			local previous = confirmed:peek()
			confirmed:set(nextState)
			notice:set(rules.outcomeLine(previous, nextState))
			return true
		end
		local function reset()
			for id, cell in draft do
				cell:set(rules.START[id])
			end
			confirmed:set(rules.copy(rules.START))
			notice:set("Restore the door, beacon, and workshop using six power units.")
		end
		local function panel()
			local children = {
				view.text("Budget", function(use: any)
					return `{rules.spent(allocation(use))} / {rules.TOTAL} power units allocated`
				end, "heading"),
			}
			for _, consumer in rules.CONSUMERS do
				table.insert(
					children,
					UI.Stepper(consumer.id .. "Power")({
						label = `{consumer.label} · needs {consumer.needs}`,
						value = draft[consumer.id],
						min = 0,
						max = consumer.capacity,
						step = 1,
					})
				)
			end
			table.insert(
				children,
				view.text("PowerValidation", function(use: any)
					return if use(verdict).ok then "Ready to apply." else use(verdict).message
				end)
			)
			table.insert(
				children,
				view.actions({
					view.button("ApplyPower", "Apply power", apply, function(use: any)
						return use(verdict).ok
					end),
					view.button("ResetPower", "Reset", reset),
				})
			)
			table.insert(children, view.text("OutpostNotice", notice))
			return UI.VStack "PowerControls" {
				width = "fill" :: "fill",
				gap = "m",
				table.unpack((children :: unknown) :: { unknown }),
			}
		end
		local function model(offset: number)
			local function position(x: number, y: number, z: number)
				return V3.new(x, y + offset, z)
			end
			local function liveColor(id)
				return function(use: any)
					return if rules.isRunning(use(confirmed), id)
						then C3.fromRGB(104, 233, 198)
						else C3.fromRGB(90, 104, 127)
				end
			end
			return Host.Model "OutpostScene" {
				view.part("Platform", V3.new(20, 0.5, 12), position(0, -0.4, 1), C3.fromRGB(49, 58, 77)) :: unknown,
				view.part("Workshop", V3.new(5, 3.6, 3), position(5, 1.8, 3), C3.fromRGB(86, 106, 122)),
				view.part(
					"WorkshopLight",
					V3.new(3.8, 0.5, 0.1),
					position(5, 2.6, 1.44),
					liveColor("workshop"),
					{ Material = E.Material.Neon }
				),
				view.part("DoorFrame", V3.new(4.5, 4.2, 0.8), position(-5, 2.1, 3), C3.fromRGB(117, 138, 150)),
				view.part("BlastDoor", V3.new(3.5, 3.5, 0.9), position(-5, 1.8, 2.7), liveColor("door"), {
					CFrame = function(use: any)
						return CF.new(-5, offset + (if rules.isRunning(use(confirmed), "door") then 4.9 else 1.8), 2.7)
					end,
				}),
				view.part("BeaconPost", V3.new(0.4, 5, 0.4), position(0, 2.5, 5), C3.fromRGB(142, 157, 172)),
				view.part(
					"Beacon",
					V3.new(1.4, 1.4, 1.4),
					position(0, 5.6, 5),
					liveColor("beacon"),
					{ Shape = E.PartType.Ball, Material = E.Material.Neon }
				),
			}
		end
		local function world()
			local camera = ctx.worldTarget and ctx.worldTarget.CurrentCamera
			local oldFrame, oldType, oldFov, oldFovMode, oldFocus
			if camera then
				oldFrame, oldType, oldFov, oldFovMode, oldFocus =
					camera.CFrame, camera.CameraType, camera.FieldOfView, camera.FieldOfViewMode, camera.Focus
				camera.CameraType = E.CameraType.Scriptable
				camera.FieldOfViewMode = E.FieldOfViewMode.Vertical
				camera.FieldOfView = 55
			end
			if ctx.sceneVisible then
				ctx.sceneVisible:set(true)
			end
			C.cleanup(function()
				if camera then
					camera.CFrame = oldFrame
					camera.CameraType = oldType
					camera.FieldOfView = oldFov
					camera.FieldOfViewMode = oldFovMode
					camera.Focus = oldFocus
				end
				if ctx.sceneVisible then
					ctx.sceneVisible:set(false)
				end
			end)
			local stop = ctx.runtime.mount(function()
				return model(6000)
			end, ctx.worldTarget)
			C.cleanup(stop)
			local canvas = C.cell(V2.new(720, 520))
			local bounds = C.cell({ at = V2.zero, size = V2.zero })
			local terminalBounds = Host.Frame "WorldTerminalBounds" {
				BackgroundTransparency = 1,
				Size = D2.new(1, 0, 0, 0),
				UI.fill(),
			}
			local function measure()
				bounds:set({ at = terminalBounds.AbsolutePosition, size = terminalBounds.AbsoluteSize })
			end
			for _, property in { "AbsoluteSize", "AbsolutePosition" } do
				local connection = terminalBounds:GetPropertyChangedSignal(property):Connect(measure)
				C.cleanup(function()
					connection:Disconnect()
				end)
			end
			measure()
			if camera then
				local viewport = C.cell(camera.ViewportSize)
				local connection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
					viewport:set(camera.ViewportSize)
				end)
				C.cleanup(function()
					connection:Disconnect()
				end)
				C.watch(function(use: any)
					local rectangle, screen = use(bounds), use(viewport)
					local scale = if ctx.previewScale then use(ctx.previewScale) else 1
					if rectangle.size.X <= 0 or rectangle.size.Y <= 0 or screen.Y <= 0 then
						return
					end
					local size =
						V2.new(math.min(720, rectangle.size.X / scale), math.min(520, rectangle.size.Y / scale))
					canvas:set(size)
					local layer = terminalBounds:FindFirstAncestorWhichIsA("ScreenGui")
					local function slope(point)
						local ray = if layer and layer.IgnoreGuiInset
							then camera:ViewportPointToRay(point.X, point.Y)
							else camera:ScreenPointToRay(point.X, point.Y)
						local direction = camera.CFrame:VectorToObjectSpace(ray.Direction)
						return V2.new(direction.X / -direction.Z, direction.Y / -direction.Z)
					end
					local first, last = slope(rectangle.at), slope(rectangle.at + rectangle.size)
					local distance = math.max(size.X / (last.X - first.X), size.Y / (first.Y - last.Y)) * 1.02 / 100
					local middle = slope(rectangle.at + rectangle.size / 2)
					local from = V3.new(middle.X * distance, 6003 - middle.Y * distance, -1.175 - distance)
					camera.CFrame = CF.new(from) * CF.Angles(0, math.pi, 0)
					camera.Focus = CF.new(0, 6003, -1)
				end)
			end
			local stopConsole, console = ctx.runtime.mount(function()
				return view.part("ShowcaseConsole", function(use: any)
					local size = use(canvas)
					return V3.new(size.X / 100, size.Y / 100, 0.35)
				end, V3.new(0, 6003, -1), C3.fromRGB(28, 39, 54))
			end, ctx.worldTarget)
			C.cleanup(stopConsole)
			local stopSurface = ctx.runtime.mount(function()
				local style =
					ctx.Facet.themes.createStyleSheet(ctx.runtime, ctx.theme or ctx.Facet.themes.neutralPackage(), {
						types = if ctx.types.Font then ctx.types else nil,
						theme = ctx.themeMode,
						motionLevel = ctx.motionPreference,
					})
				return Host.SurfaceGui "OutpostSurface" {
					Adornee = C.static(console),
					Face = E.NormalId.Front,
					SizingMode = E.SurfaceGuiSizingMode.FixedSize,
					CanvasSize = canvas,
					Active = true,
					AlwaysOnTop = false,
					style :: unknown,
					if style then Host.StyleLink { StyleSheet = C.static(style) } else nil :: unknown,
					UI.Screen "TerminalScreen" {
						gap = "m",
						view.text("TerminalTitle", "OUTPOST 07 / POWER", "title") :: unknown,
						UI.ScrollView "TerminalControls" { width = "fill" :: "fill", UI.fill() :: unknown, panel() },
					},
				}
			end, ctx.inputTarget)
			C.cleanup(stopSurface)
			return UI.VStack "WorldView" {
				width = "fill" :: "fill",
				height = "fill" :: "fill",
				padding = "m",
				gap = "s",
				UI.VStack "WorldCommands" {
					width = "fill" :: "fill",
					view.actions({
						view.button("LeaveWorld", "Back to overview", function()
							worldMode:set(false)
						end),
						UI.CollapsibleView "WorldPowerControls" {
							label = "Power controls",
							expanded = controlsOpen,
							content = panel,
						},
					}),
				} :: unknown,
				terminalBounds,
			}
		end
		local function overview()
			return view.page(
				"OutpostOverview",
				"Bring Outpost 07 back online",
				"Balance the generator, apply your changes, and watch the station respond.",
				{
					view.stage("OutpostPreview", function()
						return model(0)
					end, CF.lookAt(V3.new(16, 12, -20), V3.new(0, 2, 2))),
					UI.ProgressView "SystemsOnline" {
						label = "Systems online",
						value = function(use: any)
							return rules.runningCount(use(confirmed))
						end,
						max = 3,
						showValue = true,
					},
					panel(),
					view.actions({
						view.button("EnterWorld", "Use the world terminal", function()
							worldMode:set(true)
						end),
						UI.RadialMenu "PowerShortcuts" {
							label = "Quick actions",
							contentFit = "radial" :: "radial",
							ringWidth = "wide" :: "wide",
							center = "empty" :: "empty",
							scrim = "dark",
							items = {
								{
									id = "beacon",
									label = "Beacon",
									icon = "flag",
									labelStyle = "icon" :: "icon",
									onSelect = function()
										draft.beacon:set(1)
										notice:set("Beacon power staged. Apply when ready.")
									end,
								} :: typeof(require("@repo/tools/typecheck/example_shapes").RadialItem_any(nil :: any)),
								{
									id = "door",
									label = "Door",
									icon = "chevron.trailing",
									labelStyle = "icon" :: "icon",
									onSelect = function()
										draft.door:set(2)
										notice:set("Door power staged. Apply when ready.")
									end,
								} :: typeof(require("@repo/tools/typecheck/example_shapes").RadialItem_any(nil :: any)),
								{
									id = "workshop",
									label = "Workshop",
									icon = "settings",
									labelStyle = "icon" :: "icon",
									onSelect = function()
										draft.workshop:set(2)
										notice:set("Workshop power staged. Apply when ready.")
									end,
								} :: typeof(require("@repo/tools/typecheck/example_shapes").RadialItem_any(nil :: any)),
							},
						},
					}),
				}
			)
		end
		return {
			screen = function()
				return Host.Frame "Outpost" {
					Size = D2.fromScale(1, 1),
					BackgroundTransparency = 1,
					C.show(function(use: any)
						return use(worldMode) and (not ctx.pageVisible or use(ctx.pageVisible))
					end, world, overview),
				}
			end,
			report = function()
				return {
					allocation = confirmed:peek(),
					draft = allocation(),
					running = rules.runningCount(confirmed:peek()),
					world = worldMode:peek(),
				}
			end,
			apply = apply,
			reset = reset,
			model = { draft = draft, worldMode = worldMode },
		}
	end,
}
