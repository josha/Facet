--!strict
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T
local flight = require("./flap_model")

return function(ctx: any)
	local Compose: typeof(require("@repo/src/vendor/compose/core")), Host, UI = ctx.Compose, ctx.Host, ctx.UI
	local D2, D, V2, C3, E = ctx.D2, ctx.D, ctx.V2, ctx.C3, ctx.E
	local gameModel = ctx.model.flap
	local state = gameModel.state
	local width, height, tile = flight.WIDTH, flight.HEIGHT, flight.TILE
	local ink = C3.fromRGB(30, 53, 62)
	local colors = {
		grass = C3.fromRGB(181, 220, 118),
		earth = C3.fromRGB(216, 186, 139),
		pipe = C3.fromRGB(64, 151, 117),
		cap = C3.fromRGB(99, 191, 139),
	}
	local function text(name: string, content, size, position, bounds, color)
		return Host.TextLabel(name)({
			Text = content,
			Font = E.Font.GothamBold,
			TextScaled = true,
			TextColor3 = color or ink,
			BackgroundTransparency = 1,
			Position = position,
			Size = bounds,
			ZIndex = 5,
			Host.UITextSizeConstraint { MaxTextSize = size, MinTextSize = 8 },
		})
	end
	local function press()
		ctx.model.flapPress()
	end
	local function controlLabel(use: Use)
		local phase = use(state).phase
		return if phase == "ready"
			then "Play"
			elseif phase == "over" then "Try again"
			elseif phase == "paused" then "Resume"
			else "Flap"
	end
	local scene = Host.Frame "FlapViewport" {
		AnchorPoint = V2.new(0.5, 0.5),
		Position = D2.fromScale(0.5, 0.5),
		Size = D2.fromScale(1, 1),
		BackgroundColor3 = C3.fromRGB(180, 222, 232),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Host.UIAspectRatioConstraint { AspectRatio = width / height, AspectType = E.AspectType.FitWithinMaxSize } :: unknown,
		Host.Frame "Sun" {
			Position = D2.fromScale(0.77, 0.13),
			Size = D2.fromScale(0.10, 0.17),
			BackgroundColor3 = C3.fromRGB(255, 239, 185),
			BorderSizePixel = 0,
			Host.UICorner { CornerRadius = D.new(1, 0) },
		},
		Host.Frame "Cloud" {
			Position = D2.fromScale(0.08, 0.19),
			Size = D2.fromScale(0.2, 0.07),
			BackgroundColor3 = C3.fromRGB(239, 249, 241),
			BorderSizePixel = 0,
			Host.UICorner { CornerRadius = D.new(1, 0) },
		},
		Host.Frame "CloudFar" {
			Position = D2.fromScale(0.52, 0.38),
			Size = D2.fromScale(0.13, 0.05),
			BackgroundColor3 = C3.fromRGB(222, 240, 235),
			BorderSizePixel = 0,
			Host.UICorner { CornerRadius = D.new(1, 0) },
		},
		Host.Frame "TileWorld" {
			BackgroundTransparency = 1,
			Size = D2.fromScale(1, 1),
			Position = function(use: Use)
				return D2.fromScale(-use(state).x / width, 0)
			end,
			Compose.TileCollection {
				viewport = function(use: Use): { x: number, y: number, width: number, height: number }
					return { x = use(state).x, y = 0, width = width, height = height }
				end,
				tileSize = { width = tile, height = tile },
				overscan = 1,
				read = function(_use: Use, column: number, row: number): string?
					return flight.tileAt(column, row)
				end,
				render = function(value, placement): GuiObject
					return Host.Frame(`Tile_{placement.column}_{placement.row}`)({
						Position = D2.fromScale(placement.x / width, placement.y / height),
						Size = D2.fromScale(tile / width, tile / height),
						BorderSizePixel = 0,
						BackgroundColor3 = function(use: Use)
							return colors[use(value)]
						end,
						Host.Frame "TileHighlight" {
							Position = D2.fromScale(0.08, 0),
							Size = D2.fromScale(0.1, 1),
							BackgroundColor3 = C3.fromRGB(246, 250, 201),
							BackgroundTransparency = 0.75,
							BorderSizePixel = 0,
						},
					})
				end,
			},
		},
		Host.Frame "Bird" {
			AnchorPoint = V2.new(0.5, 0.5),
			Position = function(use: Use)
				return D2.fromScale(flight.BIRD_X / width, use(state).y / height)
			end,
			Size = D2.fromScale(28 / width, 24 / height),
			BackgroundColor3 = C3.fromRGB(255, 207, 79),
			BorderSizePixel = 0,
			ZIndex = 3,
			Host.UICorner { CornerRadius = D.new(0.3, 0) } :: unknown,
			Host.Frame "Wing" {
				Position = D2.fromScale(-0.18, 0.42),
				Size = D2.fromScale(0.55, 0.42),
				BackgroundColor3 = C3.fromRGB(233, 159, 51),
				BorderSizePixel = 0,
				Host.UICorner { CornerRadius = D.new(0.4, 0) },
			},
			Host.Frame "Eye" {
				Position = D2.fromScale(0.6, 0.18),
				Size = D2.fromScale(0.17, 0.2),
				BackgroundColor3 = ink,
				BorderSizePixel = 0,
			},
			Host.Frame "Beak" {
				Position = D2.fromScale(0.9, 0.46),
				Size = D2.fromScale(0.32, 0.22),
				BackgroundColor3 = C3.fromRGB(238, 116, 64),
				BorderSizePixel = 0,
			},
		},
		text("FlapScore", function(use: Use)
			return tostring(use(state).score)
		end, 52, D2.fromScale(0.44, 0.055), D2.fromScale(0.12, 0.14)),
		text("FlapBest", function(use: Use)
			return `BEST {use(gameModel.best)}`
		end, 16, D2.fromScale(0.76, 0.05), D2.fromScale(0.2, 0.06)),
		Host.Frame "FlightMessage" {
			AnchorPoint = V2.new(0.5, 0.5),
			Position = D2.fromScale(0.5, 0.48),
			Size = D2.fromScale(0.49, 0.31),
			BackgroundColor3 = C3.fromRGB(249, 245, 225),
			BorderSizePixel = 0,
			ZIndex = 6,
			Visible = function(use: Use)
				return use(state).phase ~= "playing"
			end,
			Host.UICorner { CornerRadius = D.new(0.08, 0) } :: unknown,
			text("FlightTitle", function(use: Use)
				local phase = use(state).phase
				return if phase == "over"
					then "Nice flight!"
					elseif phase == "paused" then "Take a breather."
					else "Facet Flap"
			end, 32, D2.fromScale(0.06, 0.16), D2.fromScale(0.88, 0.3)),
			text("FlightHint", function(use: Use)
				local phase = use(state).phase
				return if phase == "over"
					then `Score {use(state).score}  ·  Tap to try again`
					elseif phase == "paused" then "Tap or press Space to resume"
					else "Tap or press Space to fly"
			end, 17, D2.fromScale(0.06, 0.56), D2.fromScale(0.88, 0.2)),
		},
		Host.TextButton "FlapTouch" {
			Text = "",
			BackgroundTransparency = 1,
			Size = D2.fromScale(1, 1),
			AutoButtonColor = false,
			Selectable = false,
			ZIndex = 7,
			Activated = press,
		},
	}
	return UI.VStack "FlapBody" {
		width = "fill" :: "fill",
		height = "fill" :: "fill",
		gap = "s",
		Host.Frame "FlightStage" {
			Size = D2.fromScale(1, 0),
			BackgroundTransparency = 1,
			UI.fill() :: unknown,
			scene,
		} :: unknown,
		UI.HStack "FlightControls" {
			width = "fill" :: "fill",
			gap = "s",
			align = "center" :: "center",
			ctx.button("FlapAction", controlLabel, press) :: unknown,
			ctx.button(
				"FlapPause",
				function(use: Use)
					return if use(state).phase == "paused" then "Resume" else "Pause"
				end,
				gameModel.togglePause,
				{
					enabled = function(use: Use)
						local phase = use(state).phase
						return phase == "playing" or phase == "paused"
					end,
				}
			),
			UI.Text "FlightInstructions" {
				text = "Tap / Space · Fly through the gaps",
				textRole = "caption" :: "caption",
				role = "secondary" :: "secondary",
				TextWrapped = true,
				UI.fill(),
			},
		},
	}
end
