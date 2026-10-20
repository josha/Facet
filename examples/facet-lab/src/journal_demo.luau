--!strict
type Controls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type Phase = typeof(require("@repo/tools/typecheck/aliases").TransitionContext)
type Tab = typeof(require("@repo/tools/typecheck/aliases").Tab)
type Runtime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
type Compose = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type Types = typeof(require("@repo/tools/typecheck/aliases").RobloxTypes)
type Host = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type Readable<T> = { peek: (Readable<T>) -> T }
type Cell<T> = Readable<T> & { set: (Cell<T>, T) -> (), update: (Cell<T>, (T) -> T) -> () }
type Use = <T>(Readable<T>) -> T

return function(UI: Controls, runtime: Runtime, C: Compose, types: Types, selected: Cell<string>): Instance
	local Host = (runtime.constructors :: unknown) :: Host
	local D2, V2, E = types.UDim2, types.Vector2, types.Enum
	local ink = types.Color3.fromRGB(56, 49, 38)
	local paperColor = types.Color3.fromRGB(243, 229, 193)
	local paperGradient = types.ColorSequence.new({
		types.ColorSequenceKeypoint.new(0, types.Color3.fromRGB(207, 186, 147)),
		types.ColorSequenceKeypoint.new(0.13, types.Color3.fromRGB(255, 250, 232)),
		types.ColorSequenceKeypoint.new(0.8, types.Color3.new(1, 1, 1)),
		types.ColorSequenceKeypoint.new(1, types.Color3.fromRGB(231, 213, 176)),
	})
	local function paperTint(at: number): Color3
		local stops = paperGradient.Keypoints
		for index = 2, #stops do
			local left, right = stops[index - 1], stops[index]
			if at <= right.Time then
				return left.Value:Lerp(right.Value, (at - left.Time) / (right.Time - left.Time))
			end
		end
		return stops[#stops].Value
	end
	local held: Cell<number?> = C.cell(nil :: number?)
	local dragging = C.cell(false)
	local settled = C.cell(true)
	local environment = UI.environment()
	local origin, destination = "crossing", "ridge"
	local startX, lastX, lastTime, velocity, distance = 0, 0, 0, 0, 0
	local movedAt = 0
	local gestureWidth = 1
	local gesture: GuiObject
	C.cleanup(function()
		if dragging:peek() then
			selected:set(origin)
		end
	end)
	local function move(position: Vector2)
		if not dragging:peek() then
			return
		end
		local direction = if origin == "crossing" then -1 else 1
		local now = os.clock()
		if math.abs(position.X - lastX) >= 1 and now > lastTime then
			velocity = direction * (position.X - lastX) / (now - lastTime) / gestureWidth
			movedAt = now
		end
		lastX, lastTime = position.X, now
		distance = math.clamp(direction * (position.X - startX) / gestureWidth, 0, 1)
		if environment.motionLevel:peek() == "normal" then
			held:set(math.acos(1 - 2 * distance) / math.pi)
		end
	end
	local function spread(name: string): Instance
		local board = Host.Frame "BookSpread" {
			BackgroundTransparency = 1,
			AnchorPoint = V2.new(0.5, 0),
			Position = D2.new(0.5, 0, 0, 28),
			Size = D2.new(1, -24, 1, -56),
			Host.UISizeConstraint { MaxSize = V2.new(640, 10000) },
		}
		local size = runtime.observe(board, "AbsoluteSize") :: Readable<Vector2>
		local function paper(id: string, number: string, title: string, body: string): GuiObject
			return Host.Frame(id) {
				BackgroundColor3 = paperColor,
				BorderSizePixel = 0,
				Size = D2.fromScale(1, 1),
				Host.UIGradient {
					Rotation = if id == "Route" or id == "Notes" then 180 else 0,
					Color = paperGradient,
				},
				Host.Frame "Ink" {
					BackgroundTransparency = 1,
					Size = D2.fromScale(1, 1),
					UI.VStack "Print" {
						width = "fill",
						height = "fill",
						padding = 16,
						gap = 12,
						UI.Text { text = number, textRole = "caption", tint = ink },
						UI.Text { text = title, textRole = "heading", tint = ink, wrap = true },
						Host.Frame "Rule" {
							BackgroundColor3 = ink,
							BackgroundTransparency = 0.65,
							BorderSizePixel = 0,
							Size = D2.new(1, 0, 0, 1),
						},
						UI.Text { text = body, tint = ink, wrap = true },
					},
				},
			}
		end
		runtime.mountFragment(function()
			return {
				Host.Frame "Cover" {
					BackgroundColor3 = types.Color3.fromRGB(31, 73, 76),
					BorderSizePixel = 0,
					Position = D2.fromOffset(-8, -8),
					Size = D2.new(1, 16, 1, 20),
					Host.UICorner { CornerRadius = types.UDim.new(0, 5) },
					Host.UIStroke { Color = types.Color3.fromRGB(173, 142, 82), Thickness = 2 },
				},
				Host.Frame "PageBlock" {
					BackgroundColor3 = types.Color3.fromRGB(179, 158, 116),
					BorderSizePixel = 0,
					Position = D2.fromOffset(0, 5),
					Size = D2.fromScale(1, 1),
				},
				Host.Frame "LeftPage" {
					BackgroundTransparency = 1,
					Size = D2.fromScale(0.5, 1),
					paper(
						"Route",
						"FIELD JOURNAL",
						"The route",
						"Cross the river.\nFollow the ridge.\nFind the beacon."
					),
				},
				Host.Frame "RightPage" {
					BackgroundTransparency = 1,
					Position = D2.fromScale(0.5, 0),
					Size = D2.fromScale(0.5, 1),
					paper(
						"Ridge",
						"03",
						"The ridge",
						"The clouds have lifted. The beacon is just beyond the next rise."
					),
				},
				Host.Frame "TurnShadow" {
					BorderSizePixel = 0,
					BackgroundColor3 = types.Color3.new(0, 0, 0),
					BackgroundTransparency = 0.7,
					Position = D2.fromScale(0.5, 0),
					Size = D2.fromScale(0, 1),
					Host.UIGradient {
						Transparency = types.NumberSequence.new(0, 1),
					},
				},
				Host.Frame "TurningLeaf" {
					BackgroundTransparency = 1,
					ZIndex = 3,
					ClipsDescendants = true,
					Position = D2.fromScale(0.5, 0),
					Size = D2.fromScale(0.5, 1),
					Host.Frame "LeafFront" {
						BackgroundTransparency = 1,
						Size = function(use: Use): UDim2
							return D2.new(0, use(size).X / 2, 1, 0)
						end,
						paper(
							"Crossing",
							"01",
							"The crossing",
							"The old bridge is gone. Take the shallow path before dusk."
						),
					},
					Host.Frame "LeafBack" {
						BackgroundTransparency = 1,
						Size = function(use: Use): UDim2
							return D2.new(0, use(size).X / 2, 1, 0)
						end,
						paper(
							"Notes",
							"02",
							"Trail notes",
							"Pack a lantern.\nKeep the river on your left.\nWatch for loose stones."
						),
					},
				},
				Host.Frame "Fold" {
					BackgroundTransparency = 1,
					ZIndex = 2,
					Size = D2.fromScale(1, 1),
					Visible = false,
				},
				Host.Frame "Spine" {
					ZIndex = 1,
					BorderSizePixel = 0,
					BackgroundColor3 = types.Color3.new(0, 0, 0),
					BackgroundTransparency = 0.7,
					Position = D2.new(0.5, -8, 0, 0),
					Size = D2.new(0, 16, 1, 0),
					Host.UIGradient {
						Transparency = types.NumberSequence.new({
							types.NumberSequenceKeypoint.new(0, 1),
							types.NumberSequenceKeypoint.new(0.5, 0),
							types.NumberSequenceKeypoint.new(1, 1),
						}),
					},
				},
			}
		end, board)
		board:SetAttribute("Spread", name)
		return board
	end
	gesture = UI.ZStack "JournalGesture" {
		width = "fill",
		height = function(use: Use): number
			return math.clamp(use(environment.viewportHeight) / use(environment.metricScale) - 220, 240, 320)
		end,
		Host.UIDragDetector "PageSwipe" {
			ResponseStyle = E.UIDragDetectorResponseStyle.CustomOffset,
			Enabled = function(use: Use): boolean
				return use(dragging) or (use(settled) and use(environment.effectiveInput) ~= "Gamepad")
			end,
			DragStart = function(position: Vector2)
				origin = selected:peek()
				destination = if origin == "crossing" then "ridge" else "crossing"
				startX, lastX, lastTime = position.X, position.X, os.clock()
				movedAt = lastTime
				velocity, distance = 0, 0
				gestureWidth = math.max(1, math.min(640, gesture.AbsoluteSize.X - 24))
				runtime:batch(function()
					dragging:set(true)
					if environment.motionLevel:peek() == "normal" then
						held:set(0)
						selected:set(destination)
					end
				end)
			end,
			DragContinue = move,
			DragEnd = function()
				if not dragging:peek() then
					return
				end
				local commit = distance >= 0.5 or (distance >= 0.08 and velocity > 0.8 and os.clock() - movedAt < 0.12)
				runtime:batch(function()
					selected:set(if commit then destination else origin)
					held:set(nil)
					dragging:set(false)
				end)
			end,
		},
		UI.TabView "JournalPages" {
			selection = selected,
			placement = "none",
			Size = D2.fromScale(1, 1),
			transition = {
				motion = "pageTurn",
				fade = false,
				progress = held,
				apply = function(content: GuiObject, phase: Phase)
					C.watch(function(use: Use)
						if use(phase.isPresented) then
							settled:set(use(phase.progress) == 1)
						end
					end)
					local board = content:FindFirstChild("BookSpread", true) :: GuiObject
					local leaf = board:FindFirstChild("TurningLeaf") :: GuiObject
					local progress = C.formula(function(use: Use): number
						local progress = use(phase.progress)
						return if board:GetAttribute("Spread") == "ridge" then progress else 1 - progress
					end)
					local turn = progress
					local width = C.formula(function(use: Use): number
						return math.cos(math.pi * use(turn))
					end)
					runtime.decorate(board:FindFirstChild("RightPage") :: GuiObject, {
						Visible = function(use: Use): boolean
							return use(turn) > 0
						end,
					})
					runtime.decorate(board:FindFirstChild("LeftPage") :: GuiObject, {
						Visible = function(use: Use): boolean
							return use(turn) < 1
						end,
					})
					local fold = board:FindFirstChild("Fold") :: GuiObject
					runtime.decorate(fold, {
						Visible = function(use: Use): boolean
							local value = use(turn)
							return value > 0 and value < 1
						end,
					})
					runtime.mountFragment(function()
						local strips: { unknown } = {}
						for index = 1, 32 do
							local function point(u: number, value: number): Vector2
								local angle = math.pi * value
								local lift = math.sin(angle)
								local curl = 0.16 * lift * math.sin(math.pi * u)
								local depth = u * lift
								local perspective = 1 / (1 - depth * 0.16)
								return V2.new(0.5 + (u * math.cos(angle) + curl) * perspective / 2, perspective)
							end
							local geometry = C.formula(
								function(use: Use): { left: number, width: number, height: number, rotation: number }
									local a = point((index - 1) / 32, use(turn))
									local b = point(index / 32, use(turn))
									return {
										left = math.min(a.X, b.X),
										width = math.abs(b.X - a.X),
										height = (a.Y + b.Y) / 2,
										rotation = if b.X < a.X then 180 else 0,
									}
								end
							)
							table.insert(
								strips,
								Host.Frame("PaperStrip" .. index) {
									BorderSizePixel = 0,
									AnchorPoint = V2.new(0, 0.5),
									Position = function(use: Use): UDim2
										return D2.fromScale(use(geometry).left, 0.5)
									end,
									Size = function(use: Use): UDim2
										local g = use(geometry)
										return D2.new(g.width, 1, g.height, 0)
									end,
									BackgroundColor3 = function(use: Use): Color3
										local angle = math.pi * use(turn)
										local light = 0.72
											+ 0.28
												* math.abs(
													math.cos(
														angle + 0.4 * math.sin(index / 32 * math.pi) * math.sin(angle)
													)
												)
										return paperColor:Lerp(types.Color3.new(0, 0, 0), 1 - light)
									end,
									Host.UIGradient {
										Color = types.ColorSequence.new(
											paperTint((index - 1) / 32),
											paperTint(index / 32)
										),
										Rotation = function(use: Use): number
											return use(geometry).rotation
										end,
									},
								}
							)
						end
						return strips
					end, fold)
					runtime.decorate(leaf, {
						AnchorPoint = function(use: Use): Vector2
							return V2.new(if use(width) < 0 then 1 else 0, 0)
						end,
						Size = function(use: Use): UDim2
							return D2.fromScale(math.abs(use(width)) / 2, 1)
						end,
					})
					runtime.decorate(leaf:FindFirstChild("LeafFront") :: GuiObject, {
						Visible = function(use: Use): boolean
							return use(turn) <= 0.5
						end,
					})
					runtime.decorate(leaf:FindFirstChild("LeafBack") :: GuiObject, {
						Visible = function(use: Use): boolean
							return use(turn) > 0.5
						end,
					})
					for _, id in { "Crossing", "Notes" } do
						runtime.decorate(leaf:FindFirstChild(id, true) :: GuiObject, {
							BackgroundTransparency = function(use: Use): number
								local value = use(turn)
								return if value > 0 and value < 1 then 1 else 0
							end,
						})
					end
					runtime.decorate(board:FindFirstChild("TurnShadow") :: GuiObject, {
						AnchorPoint = function(use: Use): Vector2
							return V2.new(if use(width) < 0 then 1 else 0, 0)
						end,
						Size = function(use: Use): UDim2
							return D2.fromScale(math.sin(math.pi * use(turn)) * 0.45, 1)
						end,
					})
					runtime.decorate(
						(board:FindFirstChild("TurnShadow") :: Instance):FindFirstChildWhichIsA(
								"UIGradient"
							) :: UIGradient,
						{
							Rotation = function(use: Use): number
								return if use(width) < 0 then 180 else 0
							end,
						}
					)
				end,
			},
			tabs = {
				{
					id = "crossing",
					content = function(): Instance
						return spread("crossing")
					end,
				},
				{
					id = "ridge",
					content = function(): Instance
						return spread("ridge")
					end,
				},
			} :: { Tab },
		},
	}
	return UI.VStack "JournalContent" {
		width = "fill",
		height = "hug",
		gap = 12,
		UI.HStack "PageActions" {
			width = "fill",
			gap = 8,
			UI.Button "PreviousPage" {
				label = "Previous",
				enabled = function(use: Use): boolean
					return not use(dragging) and use(selected) == "ridge"
				end,
				onActivate = function()
					selected:set("crossing")
				end,
			},
			UI.Button "NextPage" {
				label = "Next",
				enabled = function(use: Use): boolean
					return not use(dragging) and use(selected) == "crossing"
				end,
				onActivate = function()
					selected:set("ridge")
				end,
			},
			UI.Text { text = "Drag to turn", textRole = "caption" },
		},
		gesture,
	}
end
