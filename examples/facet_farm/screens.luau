--!strict
local modelModule = require("./model")
local theme = require("./theme")

local screens = {}

local TOOLS = {
	{ value = "plow", label = "Plow" },
	{ value = "plant", label = "Plant" },
	{ value = "harvest", label = "Harvest" },
}

function screens.farm(Facet: any, UI: any, Host: any, types: any, farm: any)
	local Compose = Facet.Compose
	local shapes = Facet.pathShapes
	local D2, E = types.UDim2, types.Enum
	local function paint(name: string): Color3
		return theme.color(types.Color3, name)
	end

	local function line(x1: number, y1: number, x2: number, y2: number): { any }
		return {
			{ x = x1, y = y1, inX = 0, inY = 0, outX = 0, outY = 0 },
			{ x = x2, y = y2, inX = 0, inY = 0, outX = 0, outY = 0 },
		}
	end
	local function circle(cx: number, cy: number, radius: number): { any }
		local points = shapes.ring({ radius = radius * 2 })
		for index, point in points do
			local moved = table.clone(point)
			moved.x += cx - 0.5
			moved.y += cy - 0.5
			points[index] = moved
		end
		return points
	end
	local function stroke(name: string, points: { any }, color: string, thickness: number, closed: boolean?)
		return UI.Path(name)({
			points = points,
			tint = paint(color),
			thickness = thickness,
			closed = closed,
			Size = D2.fromScale(1, 1),
		})
	end
	local function art(name: string, parts: { any })
		return UI.ZStack(name)({
			AnchorPoint = types.Vector2.new(0.5, 0.5),
			Position = D2.fromScale(0.5, 0.5),
			Size = D2.fromScale(0.8, 0.8),
			table.unpack(parts),
		})
	end

	local function cropArt(crop: string, stage: string)
		if stage == "withered" then
			return art("Dry", {
				stroke("Stem", line(0.5, 0.85, 0.46, 0.45), "dry", 4),
				stroke("Droop", line(0.46, 0.45, 0.3, 0.6), "dry", 4),
				stroke("Leaf", line(0.47, 0.6, 0.66, 0.72), "dry", 3),
			})
		elseif stage == "growing" then
			return art("Sprout", {
				stroke("Stem", line(0.5, 0.82, 0.5, 0.5), "sprout", 4),
				stroke("LeafLeft", circle(0.4, 0.46, 0.08), "sprout", 6, true),
				stroke("LeafRight", circle(0.6, 0.46, 0.08), "sprout", 6, true),
			})
		elseif crop == "wheat" then
			local parts = {}
			for index, tip in { { 0.3, 0.3 }, { 0.5, 0.2 }, { 0.7, 0.3 } } do
				table.insert(parts, stroke("Stalk" .. index, line(0.5, 0.88, tip[1], tip[2] + 0.08), "stalk", 3))
				table.insert(parts, stroke("Grain" .. index, circle(tip[1], tip[2], 0.07), "wheat", 7, true))
			end
			return art("Wheat", parts)
		elseif crop == "carrot" then
			return art("Carrot", {
				stroke("LeafLeft", line(0.5, 0.38, 0.36, 0.14), "stalk", 4),
				stroke("LeafMiddle", line(0.5, 0.38, 0.5, 0.1), "stalk", 4),
				stroke("LeafRight", line(0.5, 0.38, 0.64, 0.14), "stalk", 4),
				stroke("Root", line(0.5, 0.4, 0.5, 0.86), "carrot", 12),
			})
		elseif crop == "strawberry" then
			return art("Strawberry", {
				stroke("Berry", circle(0.5, 0.58, 0.16), "strawberry", 16, true),
				stroke("CapLeft", line(0.5, 0.4, 0.38, 0.34), "stalk", 4),
				stroke("CapRight", line(0.5, 0.4, 0.62, 0.34), "stalk", 4),
				stroke("Stem", line(0.5, 0.4, 0.5, 0.26), "stalk", 3),
			})
		end
		return art("Pumpkin", {
			stroke("Left", circle(0.4, 0.6, 0.16), "pumpkin", 14, true),
			stroke("Right", circle(0.6, 0.6, 0.16), "pumpkin", 14, true),
			stroke("Middle", circle(0.5, 0.6, 0.17), "carrot", 14, true),
			stroke("Stem", line(0.5, 0.42, 0.54, 0.28), "stalk", 5),
		})
	end

	local function plotView(index: number)
		local function plot(use): any
			return use(farm.plots)[index]
		end
		local function stage(use): string
			return modelModule.stateAt(plot(use), use(farm.now))
		end
		local function describe(use): string
			local current, state = plot(use), stage(use)
			if state == "grass" then
				return `Plot {index}, grass`
			elseif state == "plowed" then
				return `Plot {index}, plowed`
			end
			local crop = modelModule.crop(current.crop).label
			return `Plot {index}, {crop} {if state == "ready"
				then "ready"
				elseif state == "withered" then "withered"
				else "growing"}`
		end
		return UI.Button("Plot" .. index)({
			name = describe,
			onActivate = function()
				farm.act(index)
			end,
			Size = D2.fromScale(1, 1),
			AutomaticSize = E.AutomaticSize.None,
			BackgroundTransparency = 1,
			Host.UIPadding {
				PaddingLeft = types.UDim.new(0, 1),
				PaddingRight = types.UDim.new(0, 1),
				PaddingTop = types.UDim.new(0, 1),
				PaddingBottom = types.UDim.new(0, 1),
			},
			UI.ZStack "Tile" {
				width = "fill",
				height = "fill",
				Host.Frame "Soil" {
					Size = D2.new(1, -4, 1, -4),
					Position = D2.fromOffset(2, 2),
					BorderSizePixel = 0,
					BackgroundColor3 = function(use)
						local state = stage(use)
						return paint(
							if state == "grass" then "grass" elseif state == "withered" then "withered" else "plowed"
						)
					end,
					Host.UICorner { CornerRadius = types.UDim.new(0, 12) },
					Host.UIStroke {
						Thickness = 3,
						Color = function(use)
							return paint(if stage(use) == "grass" then "grassEdge" else "soilEdge")
						end,
					},
				},
				Compose.show(function(use)
					return stage(use) ~= "grass"
				end, function()
					local rows = {}
					for row = 1, 3 do
						local y = 0.25 * row
						table.insert(
							rows,
							UI.Path("Furrow" .. row)({
								points = {
									{ x = 0.18, y = y, inX = 0, inY = 0, outX = 0, outY = 0 },
									{ x = 0.82, y = y, inX = 0, inY = 0, outX = 0, outY = 0 },
								},
								tint = paint("furrow"),
								thickness = 3,
								Size = D2.fromScale(1, 1),
							})
						)
					end
					return UI.ZStack "Furrows" { width = "fill", height = "fill", table.unpack(rows) }
				end),
				Compose.keyed({
					from = function(use)
						local state = stage(use)
						if state == "grass" or state == "plowed" then
							return {}
						end
						return { plot(use).crop .. ":" .. state }
					end,
					render = function(current)
						local crop, state = string.match(current:peek(), "^(%w+):(%w+)$")
						return cropArt(crop :: string, state :: string)
					end,
				}),
				Compose.show(function(use)
					return stage(use) == "growing"
				end, function()
					return UI.ProgressView "Growth" {
						presentation = "circular",
						diameter = 22,
						value = function(use)
							return modelModule.progress(plot(use), use(farm.now))
						end,
						AnchorPoint = types.Vector2.new(1, 0),
						Position = D2.new(1, -6, 0, 6),
					}
				end),
				Compose.show(function(use)
					return stage(use) == "ready"
				end, function()
					return UI.StatusIndicator "Ready" {
						status = "success",
						name = "Ready to harvest",
						AnchorPoint = types.Vector2.new(1, 0),
						Position = D2.new(1, -8, 0, 8),
					}
				end),
			},
		})
	end

	local plots = {}
	for index = 1, modelModule.COLUMNS * modelModule.ROWS do
		table.insert(plots, plotView(index))
	end

	local seedOptions = {}
	for _, crop in modelModule.CROPS do
		table.insert(seedOptions, {
			value = crop.id,
			label = `{crop.label} · {crop.cost}`,
			enabled = function(use)
				return modelModule.levelOf(use(farm.xp)) >= crop.unlock
			end,
		})
	end
	local toolItems = {}
	for _, tool in TOOLS do
		table.insert(toolItems, { id = tool.value, label = tool.label, selected = farm.tool, value = tool.value })
	end
	local function marketRows()
		local rows = {}
		for _, crop in modelModule.CROPS do
			table.insert(
				rows,
				UI.Button("Seed_" .. crop.id)({
					row = {
						title = crop.label,
						description = `{crop.cost} coins · grows in {crop.grow} s · sells for {crop.sell} · level {crop.unlock}`,
					},
					enabled = function(use)
						return modelModule.levelOf(use(farm.xp)) >= crop.unlock
					end,
					onActivate = function()
						farm.seed:set(crop.id)
						farm.tool:set("plant")
						farm.marketOpen:set(false)
					end,
				})
			)
		end
		return rows
	end

	local env = UI.environment()
	local function blend(use): number
		if farm.blend then
			return use(farm.blend)
		end
		return if use(farm.view) == "3d" then 1 else 0
	end
	local GAP, INSET = 8, 14
	local function short(use): boolean
		return use(env.viewportHeight) < 520
	end
	local function narrow(use): boolean
		return not short(use) and use(env.viewportWidth) < 640
	end
	local function stacked(use): boolean
		return short(use) or narrow(use)
	end
	local function cell(use): number
		local width, height = use(env.viewportWidth), use(env.viewportHeight)
		local rows, columns = modelModule.ROWS, modelModule.COLUMNS
		if short(use) then
			local down = (height - 20 - 2 * INSET - (rows - 1) * GAP) / rows
			local across = (width - 28 - 352 - 2 * INSET - (columns - 1) * GAP) / columns
			return math.floor(math.clamp(math.min(down, across), 30, 118))
		end
		local across = math.min(820, width - 48) - 2 * INSET - (columns - 1) * GAP
		local down = height - (if narrow(use) then 420 else 230) - 2 * INSET - (rows - 1) * GAP
		return math.floor(math.clamp(math.min(across / columns, down / rows), 36, 118))
	end
	local function coins()
		return UI.Badge "Coins" {
			label = function(use)
				return `{use(farm.coins)} coins`
			end,
			status = "warning",
			appearance = "status",
		}
	end
	local function level()
		return UI.Badge "Level" {
			label = function(use)
				return `Level {use(farm.level)}`
			end,
			status = "success",
			appearance = "status",
		}
	end
	local function experience(width: number)
		return UI.ProgressView "Experience" {
			Size = D2.fromOffset(width, 0),
			value = function(use)
				local xp, current = use(farm.xp), use(farm.level)
				local low, high = modelModule.xpFor(current), modelModule.xpFor(current + 1)
				return (xp - low) / math.max(1, high - low)
			end,
			label = function(use)
				local current = use(farm.level)
				return `{use(farm.xp)} / {modelModule.xpFor(current + 1)} XP`
			end,
		}
	end
	local function fill(): UIFlexItem
		return Host.UIFlexItem { FlexMode = E.UIFlexMode.Fill }
	end

	return UI.ZStack "FarmRoot" {
		width = "fill",
		height = "fill",
		UI.Screen "Farm" {
			gap = "s",
			padding = { top = "s", right = "m", bottom = "s", left = "m" },
			UI.HStack "Hud" {
				width = "fill",
				gap = "m",
				align = "center",
				padding = "s",
				BackgroundColor3 = paint("meadow"),
				BackgroundTransparency = function(use)
					return if use(farm.view) == "3d" then 0.1 else 1
				end,
				Host.UICorner { CornerRadius = types.UDim.new(0, 14) },
				Visible = function(use)
					return not stacked(use)
				end,
				UI.VStack "Brand" {
					gap = "xs",
					UI.Text "Title" { text = "Facet Farm", textRole = "title" },
					UI.Text "Tagline" { text = "Plow · Plant · Harvest", role = "secondary", textRole = "label" },
				},
				UI.Spacer {},
				UI.HStack "Stats" {
					gap = "s",
					align = "center",
					coins(),
					level(),
					experience(240),
				},
			},
			Host.Frame "Arena" {
				BackgroundTransparency = 1,
				Size = D2.fromScale(1, 0),
				fill(),
				Host.UIListLayout {
					FillDirection = function(use)
						return if short(use) then E.FillDirection.Horizontal else E.FillDirection.Vertical
					end,
					HorizontalAlignment = function(use)
						return if blend(use) >= 0.35 and short(use)
							then E.HorizontalAlignment.Right
							else E.HorizontalAlignment.Center
					end,
					VerticalAlignment = function(use)
						return if blend(use) >= 0.35 and not short(use)
							then E.VerticalAlignment.Bottom
							else E.VerticalAlignment.Center
					end,
					SortOrder = E.SortOrder.LayoutOrder,
					Padding = types.UDim.new(0, 12),
				},
				UI.ZStack "Board" {
					LayoutOrder = 1,
					Visible = function(use)
						return blend(use) < 0.35
					end,
					Host.UIScale {
						Scale = function(use)
							return 1 - 0.25 * math.clamp(blend(use) / 0.35, 0, 1)
						end,
					},
					Host.Frame "Fence" {
						Size = D2.fromScale(1, 1),
						BorderSizePixel = 0,
						BackgroundColor3 = paint("fence"),
						Host.UICorner { CornerRadius = types.UDim.new(0, 22) },
						Host.UIStroke { Thickness = 4, Color = paint("fenceEdge") },
					},
					UI.VStack "Plots" {
						padding = INSET,
						UI.Grid "Field" {
							columns = modelModule.COLUMNS,
							gap = GAP,
							cellHeight = cell,
							width = function(use)
								return cell(use) * modelModule.COLUMNS + (modelModule.COLUMNS - 1) * GAP
							end,
							table.unpack(plots),
						},
					},
				},
				Host.Frame "Controls" {
					LayoutOrder = 2,
					BackgroundColor3 = paint("meadow"),
					BackgroundTransparency = function(use)
						return if blend(use) >= 0.35 then 0.1 else 1
					end,
					Host.UICorner { CornerRadius = types.UDim.new(0, 16) },
					Host.UIPadding {
						PaddingLeft = types.UDim.new(0, 10),
						PaddingRight = types.UDim.new(0, 10),
						PaddingTop = types.UDim.new(0, 8),
						PaddingBottom = types.UDim.new(0, 8),
					},
					AutomaticSize = E.AutomaticSize.XY,
					Size = D2.fromOffset(0, 0),
					Host.UIListLayout {
						FillDirection = function(use)
							return if stacked(use) then E.FillDirection.Vertical else E.FillDirection.Horizontal
						end,
						HorizontalAlignment = E.HorizontalAlignment.Center,
						VerticalAlignment = E.VerticalAlignment.Center,
						SortOrder = E.SortOrder.LayoutOrder,
						Padding = types.UDim.new(0, 8),
					},
					UI.VStack "PocketStats" {
						LayoutOrder = 0,
						gap = "xs",
						padding = "s",
						BackgroundColor3 = paint("meadow"),
						BackgroundTransparency = function(use)
							return if use(farm.view) == "3d" then 0.1 else 1
						end,
						Host.UICorner { CornerRadius = types.UDim.new(0, 12) },
						Visible = stacked,
						UI.Text "PocketTitle" { text = "Facet Farm", textRole = "heading" },
						UI.HStack "PocketBadges" { gap = "xs", coins(), level() },
						experience(200),
					},
					UI.Picker "Tool" {
						LayoutOrder = 1,
						selected = farm.tool,
						style = "segmented",
						options = TOOLS,
						Size = function(use)
							return D2.fromOffset(if short(use) then 264 else 330, 44)
						end,
						AutomaticSize = E.AutomaticSize.None,
					},
					UI.HStack "Actions" {
						LayoutOrder = 2,
						gap = "s",
						align = "center",
						UI.Picker "Seed" {
							selected = farm.seed,
							style = "menu",
							options = seedOptions,
						},
						UI.Button "HarvestAll" {
							label = "Harvest all",
							icon = "checkmark",
							onActivate = function()
								farm.harvestAll()
							end,
						},
					},
					Host.Frame "More" {
						LayoutOrder = 3,
						BackgroundTransparency = 1,
						AutomaticSize = E.AutomaticSize.XY,
						Size = D2.fromOffset(0, 0),
						Host.UIListLayout {
							FillDirection = E.FillDirection.Horizontal,
							HorizontalAlignment = E.HorizontalAlignment.Center,
							VerticalAlignment = E.VerticalAlignment.Center,
							SortOrder = E.SortOrder.LayoutOrder,
							Padding = types.UDim.new(0, 8),
						},
						UI.HStack "Shop" {
							LayoutOrder = 1,
							gap = "s",
							align = "center",
							UI.Button "Market" {
								label = function(use)
									return if short(use) then "Market" else "Seed market"
								end,
								appearance = "accent",
								onActivate = function()
									farm.marketOpen:set(true)
								end,
							},
							UI.RadialMenu "QuickTools" {
								label = "Tools",
								items = toolItems,
							},
						},
						UI.HStack "Settings" {
							LayoutOrder = 2,
							gap = "s",
							align = "center",
							UI.Toggle "Music" {
								label = "Music",
								value = farm.music,
							},
							UI.Button "View" {
								label = function(use)
									return if use(farm.view) == "3d" then "2D board" else "3D farm"
								end,
								onActivate = function()
									farm.view:set(if farm.view:peek() == "3d" then "2d" else "3d")
								end,
							},
						},
					},
				},
			},
			UI.Sheet "SeedMarket" {
				title = "Seed market",
				isPresented = farm.marketOpen,
				detent = Compose.cell("medium"),
				content = function()
					return UI.VStack "Seeds" {
						width = "fill",
						gap = "s",
						table.unpack(marketRows()),
					}
				end,
			},
			UI.Alert "LevelUp" {
				isPresented = farm.levelUp,
				title = function()
					return `Level {farm.level:peek()}!`
				end,
				message = "New seeds may be waiting in the market.",
				actions = { { id = "ok", label = "Keep farming" } },
			},
			Compose.keyed({
				from = function(use)
					local toast = use(farm.toast)
					return if toast then { toast.serial } else {}
				end,
				render = function(current)
					local serial = current:peek()
					return UI.Snackbar("Toast" .. serial)({
						isPresented = function(use)
							local toast = use(farm.toast)
							return toast ~= nil and toast.serial == serial
						end,
						onPresentedChange = function(value)
							if not value then
								local toast = farm.toast:peek()
								if toast and toast.serial == serial then
									farm.toast:set(nil)
								end
							end
						end,
						message = function()
							local toast = farm.toast:peek()
							return if toast then toast.message else ""
						end,
						duration = 3,
					})
				end,
			}),
		},
	}
end

function screens.backdrop(Host: any, types: any, farm: any)
	local function blend(use): number
		if farm.blend then
			return use(farm.blend)
		end
		return if use(farm.view) == "3d" then 1 else 0
	end
	return Host.Frame "Meadow" {
		Visible = function(use)
			return blend(use) < 1
		end,
		BackgroundTransparency = function(use)
			return math.clamp(blend(use) / 0.35, 0, 1)
		end,
		Size = types.UDim2.fromScale(1, 1),
		BorderSizePixel = 0,
		BackgroundColor3 = theme.color(types.Color3, "meadow"),
	}
end

return screens
