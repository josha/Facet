--!strict
local COPY = {
	title = "Detent sheets",
	intro = "Open a race briefing. Drag its header to resize, or focus Size and use Left / Right. On a distant screen the panel moves to the center.",
	open = "Open race briefing",
	briefing = "Coastal circuit",
	description = "Three laps along the harbor, through the old town, and back to the starting grid. Resize this briefing to see more while keeping the track in view.",
	join = "Join the club event",
	start = "Start practice",
	status = "Ready for practice.",
}
return {
	title = "Detent sheets",
	ledgerRows = {},
	copy = COPY,
	build = function(ctx)
		local UI, Compose = ctx.UI, ctx.Compose
		local Host = ctx.Host
		local Compose = ctx.Compose
		local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Vector2 = Vector2, Color3 = Color3, Enum = Enum }
		local UDim, UDim2, Vector2, Color3, Enum =
			nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum
		local copy = ctx.copy or COPY
		local detent = Compose.cell("medium")
		local membership = Compose.cell(false)
		local status = Compose.cell(copy.status)
		local presented = Compose.cell(false)
		local function open()
			presented:set(true)
			return true
		end
		local function close()
			presented:set(false)
		end
		local function setDetent(value)
			detent:set(value)
		end
		local function reset()
			close()
			detent:set("medium")
			membership:set(false)
			status:set(copy.status)
		end
		local function Briefing()
			return Host.Frame({
				Name = "Sheet",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
				Host.UIPadding({
					PaddingTop = UDim.new(0, 16),
					PaddingBottom = UDim.new(0, 16),
					PaddingLeft = UDim.new(0, 16),
					PaddingRight = UDim.new(0, 16),
				}),
				Host.ScrollingFrame({
					Name = "Page",
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					AutomaticCanvasSize = Enum.AutomaticSize.Y,
					CanvasSize = UDim2.new(),
					ScrollBarThickness = 6,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Vertical,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 16),
					}),
					UI.Label({
						LayoutOrder = 1,
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						Text = copy.title,
						TextSize = 28,
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					UI.Label({
						LayoutOrder = 2,
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						Text = copy.intro,
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					UI.Label({
						LayoutOrder = 3,
						Name = "Status",
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						Text = status,
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					UI.Button({
						LayoutOrder = 4,
						Name = "Open",
						label = copy.open,
						onActivate = open,
					}),
				}),
				UI.Sheet({
					Name = "Briefing",
					title = copy.briefing,
					isPresented = presented,
					detent = detent,
					detents = { { id = "compact", fraction = 0.35 }, "medium", "large" },
					content = function()
						return Host.Frame({
							Name = "Details",
							BackgroundTransparency = 1,
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							Host.UIListLayout({
								FillDirection = Enum.FillDirection.Vertical,
								SortOrder = Enum.SortOrder.LayoutOrder,
								Padding = UDim.new(0, 16),
							}),
							UI.Label({
								LayoutOrder = 1,
								Name = "Description",
								BackgroundTransparency = 1,
								BorderSizePixel = 0,
								Size = UDim2.new(1, 0, 0, 0),
								AutomaticSize = Enum.AutomaticSize.Y,
								Text = copy.description,
								TextWrapped = true,
								TextYAlignment = Enum.TextYAlignment.Top,
								TextXAlignment = Enum.TextXAlignment.Left,
							}),
							UI.Label({
								LayoutOrder = 2,
								BackgroundTransparency = 1,
								BorderSizePixel = 0,
								Size = UDim2.new(1, 0, 0, 0),
								AutomaticSize = Enum.AutomaticSize.Y,
								Text = "Weather: clear skies. Surface: dry. Recommended tires: sport.",
								TextWrapped = true,
								TextYAlignment = Enum.TextYAlignment.Top,
								TextXAlignment = Enum.TextXAlignment.Left,
							}),
							UI.Toggle({
								LayoutOrder = 3,
								Name = "Membership",
								label = copy.join,
								value = membership,
							}),
							UI.Label({
								LayoutOrder = 4,
								BackgroundTransparency = 1,
								BorderSizePixel = 0,
								Size = UDim2.new(1, 0, 0, 0),
								AutomaticSize = Enum.AutomaticSize.Y,
								Text = "The first corner tightens as you exit. Leave room for the next driver, then accelerate toward the harbor straight.",
								TextWrapped = true,
								TextYAlignment = Enum.TextYAlignment.Top,
								TextXAlignment = Enum.TextXAlignment.Left,
							}),
							UI.Button({
								LayoutOrder = 5,
								Name = "Start",
								Size = UDim2.new(1, 0, 0, 0),
								AutomaticSize = Enum.AutomaticSize.Y,
								label = copy.start,
								onActivate = function()
									status:set("Practice started.")
									close()
								end,
							}),
						})
					end,
				}),
			})
		end
		return {
			screen = Briefing,
			steps = {
				open = open,
				close = close,
				reset = reset,
				medium = function()
					setDetent("medium")
				end,
				large = function()
					setDetent("large")
				end,
			},
			states = function()
				return {
					{ id = "medium", kind = "dialog", open = open },
					{
						id = "large",
						kind = "dialog",
						open = function()
							setDetent("large")
							return open()
						end,
					},
				}
			end,
			report = function()
				return {
					sheet = { presented = presented:peek(), detent = detent:peek() },
					membership = membership:peek(),
					status = status:peek(),
				}
			end,

			dispose = function() end,
		}
	end,
}
