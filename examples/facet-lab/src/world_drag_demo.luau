--!strict
local Catalog = require("./catalog_types")
type DropInfo = typeof(require("@repo/tools/typecheck/aliases").DropInfo)
type DraggableSpec = typeof(require("@repo/tools/typecheck/aliases").DraggableSpec)

return function(c: Catalog.Context): Instance
	local UI, Host, C = c.UI, c.Host, c.Compose
	local example = c.ctx
	local world = example and example.worldTarget
	if not world then
		return UI.Text { text = "Open the Lab in Play to place world tiles." }
	end
	local V3, CF, D2, E = c.types.Vector3, c.types.CFrame, c.types.UDim2, c.types.Enum
	local rack = CF.new(-4, 6000.65, 4)
	local position = C.cell(rack)
	local held = C.cell(false)
	local status = C.cell("Drag the rack tile to a cell, or select Pick up tile, then select a cell.")
	local pickup: GuiObject = UI.Button { label = "Pick up tile" }
	local choices: { GuiObject } = {}
	for index = 1, 3 do
		choices[index] = UI.Button { label = "Cell " .. index }
	end
	local function place(payload: unknown, info: DropInfo): boolean
		if payload ~= "rack-tile" or not info.worldPlacement then
			return false
		end
		position:set(info.worldPlacement)
		status:set("Tile placed in " .. info.target.Name .. ".")
		return true
	end
	local stop = c.app.runtime.mount(function()
		local tile = Host.Part {
			Name = "RackTile",
			Anchored = true,
			Size = V3.new(1.8, 1, 1.8),
			CFrame = position,
			Material = E.Material.Wood,
		}
		local draggable: DraggableSpec = {
			payload = "rack-tile",
			world = {
				plane = CF.new(0, 6000.65, 0),
				lift = 0.5,
				focusTarget = pickup,
				maxActivationDistance = 10000,
			},
			onStart = function()
				held:set(true)
				status:set("Choose a cell. Escape or B cancels.")
			end,
			onEnd = function(accepted)
				held:set(false)
				if not accepted then
					status:set("Tile returned. Choose Pick up tile to try again.")
				end
			end,
		}
		UI.draggable(tile, draggable)
		local cells: { Instance } = { tile }
		for index, choice in choices do
			local cell = Host.Part {
				Name = "Cell" .. index,
				Anchored = true,
				Size = V3.new(2.4, 0.2, 2.4),
				CFrame = CF.new((index - 2) * 3, 6000, 0),
				Material = E.Material.Slate,
			}
			UI.dropTarget(cell, {
				label = "Cell " .. index,
				focusTarget = choice,
				placement = { column = index, row = 1, width = 1, height = 1 },
				worldPlacement = CF.new((index - 2) * 3, 6000.65, 0),
				onDrop = place,
			})
			table.insert(cells, cell)
		end
		return Host.Model { Name = "WorldTilePlacement", unpack(cells) }
	end, world)
	C.cleanup(stop)
	if example and example.sceneVisible then
		example.sceneVisible:set(true)
		C.cleanup(function()
			assert(example.sceneVisible):set(false)
		end)
	end
	local camera = if world:IsA("Workspace") then world.CurrentCamera else nil
	if camera then
		local kind, frame, fov = camera.CameraType, camera.CFrame, camera.FieldOfView
		camera.CameraType = E.CameraType.Scriptable
		camera.CFrame = CF.lookAt(V3.new(0, 6011, 16), V3.new(0, 6000, 1))
		camera.FieldOfView = 50
		C.cleanup(function()
			camera.CameraType, camera.CFrame, camera.FieldOfView = kind, frame, fov
		end)
	end
	local commands: { Instance } = { pickup }
	for _, choice in choices do
		table.insert(commands, choice)
	end
	return UI.VStack {
		width = "fill",
		height = "fill",
		gap = "m",
		BackgroundTransparency = 1,
		UI.Text { text = status, wrap = true },
		Host.Frame { Size = D2.new(1, 0, 0, 200), BackgroundTransparency = 1, UI.fill() },
		UI.HStack { gap = "m", wrap = true, unpack(commands) },
		UI.Button {
			label = "Return to rack",
			enabled = function(use)
				return not use(held)
			end,
			onActivate = function()
				position:set(rack)
				status:set("Tile returned to the rack.")
			end,
		},
	}
end
