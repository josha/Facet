--!strict
local modelModule = require("./model")
local theme = require("./theme")

local world = {}

local TILE, SPACING = 4.4, 5.2

function world.plotPosition(index: number): Vector3
	local column = (index - 1) % modelModule.COLUMNS
	local row = (index - 1) // modelModule.COLUMNS
	local x = (column - (modelModule.COLUMNS - 1) / 2) * SPACING
	local z = (row - (modelModule.ROWS - 1) / 2) * SPACING
	return Vector3.new(x, 0, z)
end

function world.topFrame(): CFrame
	local width = modelModule.COLUMNS * SPACING
	return CFrame.lookAt(Vector3.new(0, width * 2.2, 0.01), Vector3.zero)
end

local PITCH = math.rad(50)

function world.fitFrame(free: Rect, project: (CFrame, Vector3) -> Vector2): CFrame
	local width = modelModule.COLUMNS * SPACING + 3
	local depth = modelModule.ROWS * SPACING + 3
	local corners = {}
	for _, x in { -width / 2, width / 2 } do
		for _, z in { -depth / 2, depth / 2 } do
			table.insert(corners, Vector3.new(x, 0, z))
			table.insert(corners, Vector3.new(x, 3, z))
		end
	end
	local look = Vector3.new(0, -math.sin(PITCH), -math.cos(PITCH))
	local target, distance = Vector3.zero, width * 1.5
	local frame = CFrame.lookAt(target - look * distance, target)
	for _ = 1, 16 do
		frame = CFrame.lookAt(target - look * distance, target)
		local left, right, top, bottom = math.huge, -math.huge, math.huge, -math.huge
		for _, corner in corners do
			local point = project(frame, corner)
			left, right = math.min(left, point.X), math.max(right, point.X)
			top, bottom = math.min(top, point.Y), math.max(bottom, point.Y)
		end

		local unit = (project(frame, target + frame.RightVector) - project(frame, target)).Magnitude
		local shiftX = ((left + right) / 2 - (free.Min.X + free.Max.X) / 2) / unit
		local shiftY = ((top + bottom) / 2 - (free.Min.Y + free.Max.Y) / 2) / unit
		local scale = math.max((right - left) / free.Width, (bottom - top) / free.Height)
		target += Vector3.new(frame.RightVector.X, 0, frame.RightVector.Z).Unit * shiftX + Vector3.new(
			0,
			0,
			shiftY / math.sin(PITCH)
		)
		distance *= math.clamp(scale, 0.5, 2)
	end
	return CFrame.lookAt(target - look * distance, target)
end

function world.mount(runtime: any, Compose: any, farm: any, parent: Instance): () -> ()
	local Host = runtime.constructors
	local function paint(name: string): Color3
		return theme.color(Color3, name)
	end
	local function part(name: string, props: { [string]: any }): Part
		local native: { [string]: any } = {
			Name = name,
			Anchored = true,
			CanCollide = false,
			CastShadow = true,
			Material = Enum.Material.SmoothPlastic,
		}
		for key, value in props do
			native[key] = value
		end
		return Host.Part(native)
	end

	local function crop(index: number, key: string)
		local crop, state = string.match(key, "^(%w+):(%w+)$")
		local base = world.plotPosition(index) + Vector3.new(0, 0.2, 0)
		local plot = function(use): any
			return use(farm.plots)[index]
		end
		local function grown(use): number
			return 0.35 + 0.65 * modelModule.progress(plot(use), use(farm.now))
		end
		local parts: { any } = {}
		local function add(instance)
			table.insert(parts, instance)
		end
		if state == "withered" then
			add(part("DryStem", {
				Size = Vector3.new(0.2, 1.4, 0.2),
				CFrame = CFrame.new(base + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.rad(35)),
				Color = paint("dry"),
			}))
			add(part("DryLeaf", {
				Size = Vector3.new(0.9, 0.08, 0.35),
				CFrame = CFrame.new(base + Vector3.new(0.4, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(-25)),
				Color = paint("dry"),
			}))
		elseif state == "growing" then
			add(part("Stem", {
				Size = function(use)
					return Vector3.new(0.18, 1.4 * grown(use), 0.18)
				end,
				CFrame = function(use)
					return CFrame.new(base + Vector3.new(0, 0.7 * grown(use), 0))
				end,
				Color = paint("sprout"),
			}))
			for side = -1, 1, 2 do
				add(part("Leaf", {
					Size = function(use)
						local scale = grown(use)
						return Vector3.new(0.8 * scale, 0.08, 0.45 * scale)
					end,
					CFrame = function(use)
						local scale = grown(use)
						return CFrame.new(base + Vector3.new(0.35 * side * scale, 1.1 * scale, 0))
							* CFrame.Angles(0, 0, math.rad(20 * side))
					end,
					Color = paint("sprout"),
				}))
			end
		elseif crop == "wheat" then
			for stalk = 1, 7 do
				local angle = stalk * 2.4
				local offset = Vector3.new(math.cos(angle) * 0.9, 0, math.sin(angle) * 0.9) * (stalk % 3) / 2
				add(part("Stalk", {
					Size = Vector3.new(0.12, 2.2, 0.12),
					CFrame = CFrame.new(base + offset + Vector3.new(0, 1.1, 0)),
					Color = paint("stalk"),
				}))
				add(part("Head", {
					Size = Vector3.new(0.34, 0.8, 0.34),
					CFrame = CFrame.new(base + offset + Vector3.new(0, 2.4, 0)),
					Color = paint("wheat"),
					Shape = Enum.PartType.Cylinder,
				}))
			end
		elseif crop == "carrot" then
			add(part("Root", {
				Size = Vector3.new(1.1, 0.7, 0.7),
				CFrame = CFrame.new(base + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
				Color = paint("carrot"),
				Shape = Enum.PartType.Cylinder,
			}))
			for leaf = -1, 1 do
				add(part("Top", {
					Size = Vector3.new(0.12, 1.3, 0.3),
					CFrame = CFrame.new(base + Vector3.new(0.25 * leaf, 1.3, 0))
						* CFrame.Angles(0, 0, math.rad(-18 * leaf)),
					Color = paint("stalk"),
				}))
			end
		elseif crop == "strawberry" then
			for berry = 1, 3 do
				local angle = berry * 2.1
				add(part("Berry", {
					Size = Vector3.new(0.7, 0.8, 0.7),
					CFrame = CFrame.new(base + Vector3.new(math.cos(angle) * 0.7, 0.45, math.sin(angle) * 0.7)),
					Color = paint("strawberry"),
					Shape = Enum.PartType.Ball,
				}))
			end
			add(part("Bush", {
				Size = Vector3.new(1.8, 0.5, 1.8),
				CFrame = CFrame.new(base + Vector3.new(0, 0.3, 0)),
				Color = paint("stalk"),
				Shape = Enum.PartType.Ball,
			}))
		else
			add(part("Pumpkin", {
				Size = Vector3.new(2.4, 1.7, 2.4),
				CFrame = CFrame.new(base + Vector3.new(0, 0.85, 0)),
				Color = paint("pumpkin"),
				Shape = Enum.PartType.Ball,
			}))
			add(part("Rib", {
				Size = Vector3.new(1.6, 1.8, 2.5),
				CFrame = CFrame.new(base + Vector3.new(0, 0.85, 0)),
				Color = paint("carrot"),
				Shape = Enum.PartType.Ball,
			}))
			add(part("Stem", {
				Size = Vector3.new(0.25, 0.6, 0.25),
				CFrame = CFrame.new(base + Vector3.new(0, 1.9, 0)) * CFrame.Angles(0, 0, math.rad(12)),
				Color = paint("stalk"),
			}))
		end
		return Host.Model(crop .. state)(parts)
	end

	local function tile(index: number)
		local position = world.plotPosition(index)
		local function stage(use): string
			return modelModule.stateAt(use(farm.plots)[index], use(farm.now))
		end
		local ground = part("Plot" .. index, {
			Size = Vector3.new(TILE, 0.4, TILE),
			CFrame = CFrame.new(position),
			Color = function(use)
				local state = stage(use)
				return paint(if state == "grass" then "grass" elseif state == "withered" then "withered" else "plowed")
			end,
			Material = function(use)
				return if stage(use) == "grass" then Enum.Material.Grass else Enum.Material.Ground
			end,
		})
		local detector = Host.ClickDetector { MaxActivationDistance = 1000 }
		runtime.connect(detector, "MouseClick", function()
			farm.act(index)
		end)
		detector.Parent = ground
		local furrows = {}
		for row = 1, 3 do
			table.insert(
				furrows,
				part("Furrow" .. row, {
					Size = Vector3.new(TILE * 0.8, 0.12, 0.28),
					CFrame = CFrame.new(position + Vector3.new(0, 0.24, (row - 2) * 1.2)),
					Color = paint("furrow"),
					Transparency = function(use)
						return if stage(use) == "grass" then 1 else 0
					end,
				})
			)
		end
		return Host.Model("Tile" .. index)({
			ground,
			table.unpack(furrows),
			Compose.keyed({
				from = function(use)
					local state = stage(use)
					if state == "grass" or state == "plowed" then
						return {}
					end
					return { use(farm.plots)[index].crop .. ":" .. state }
				end,
				render = function(current)
					return crop(index, current:peek())
				end,
			}),
		})
	end

	return runtime.mount(function()
		local tiles = {}
		for index = 1, modelModule.COLUMNS * modelModule.ROWS do
			table.insert(tiles, tile(index))
		end
		local width = modelModule.COLUMNS * SPACING + 2
		local depth = modelModule.ROWS * SPACING + 2
		local fence = {}
		for side = -1, 1, 2 do
			table.insert(
				fence,
				part("RailX", {
					Size = Vector3.new(width, 0.5, 0.4),
					CFrame = CFrame.new(0, 1, side * depth / 2),
					Color = paint("fence"),
					Material = Enum.Material.WoodPlanks,
				})
			)
			table.insert(
				fence,
				part("RailZ", {
					Size = Vector3.new(0.4, 0.5, depth),
					CFrame = CFrame.new(side * width / 2, 1, 0),
					Color = paint("fence"),
					Material = Enum.Material.WoodPlanks,
				})
			)
		end
		for corner = 0, 3 do
			local x = if corner % 2 == 0 then -width / 2 else width / 2
			local z = if corner < 2 then -depth / 2 else depth / 2
			table.insert(
				fence,
				part("Post", {
					Size = Vector3.new(0.7, 2, 0.7),
					CFrame = CFrame.new(x, 0.9, z),
					Color = paint("fenceEdge"),
					Material = Enum.Material.Wood,
				})
			)
		end
		return Host.Model "FacetFarmWorld" {
			part("Meadow", {
				Size = Vector3.new(220, 1, 220),
				CFrame = CFrame.new(0, -0.7, 0),
				Color = paint("grass"),
				Material = Enum.Material.Grass,
				CastShadow = false,
			}),
			part("Field", {
				Size = Vector3.new(width, 0.3, depth),
				CFrame = CFrame.new(0, -0.1, 0),
				Color = paint("fence"),
				Material = Enum.Material.Ground,
			}),
			Host.Model "Fence"(fence),
			Host.Model "Plots"(tiles),
		}
	end, parent)
end

return world
