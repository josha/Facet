--!strict

type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T
type Furniture = { id: string, name: string, category: string }
local storage, players = game:GetService("ReplicatedStorage"), game:GetService("Players")
local Facet = require(storage:WaitForChild("Facet"))
local modules = storage:WaitForChild("FacetHome")
local policy = require(modules:WaitForChild("model"))
local pages = modules:WaitForChild("designs")
local remote = storage:WaitForChild("FacetHomeRequest") :: RemoteFunction
local signal = storage:WaitForChild("FacetHomeSelect") :: RemoteEvent
local player = players.LocalPlayer
local Compose = Facet.Compose
local runtime = Facet.Roblox.createRuntime()
local Host = runtime.constructors
local route, panelOpen = Compose.cell("Home"), Compose.cell(true)
local palette, larger, immersive = Compose.cell("Light"), Compose.cell(false), Compose.cell(true)
local chosen, place, finish = Compose.cell("sofa"), Compose.cell(1), Compose.cell("sage")
local layout = Compose.cell(policy.empty())
local status, busy = Compose.cell("Loading your room…"), Compose.cell(false)
local origin = Compose.cell(Vector3.zero)
local query, score = Compose.cell(""), Compose.cell(0)
local activity = Compose.cell("Start with LEAF.")
local presence = Compose.cell("")
local boardMounted = false
local function request(action: string)
	if busy:peek() then
		return
	end
	busy:set(true)
	status:set(if action == "save" then "Saving room…" else "Working…")
	task.spawn(function()
		local ok, response = pcall(function()
			return remote:InvokeServer({
				action = action,
				slot = place:peek(),
				kind = chosen:peek(),
				palette = finish:peek(),
			})
		end)
		busy:set(false)
		if ok and response.ok then
			layout:set(policy.validate(response.layout))
			origin:set(Vector3.new(response.origin[1], 0, response.origin[2]))
			status:set(response.message .. (if response.cloud then "" else " · Session storage"))
		else
			status:set(if ok then response.message else "Could not reach your home. Try again.")
		end
	end)
end
local function text(root: Instance, name: string, value: any)
	local node = root:FindFirstChild(name, true)
	assert(node and node:IsA("TextLabel"), "Missing authored text " .. name)
	runtime.decorate(node, { Text = value })
end
local function action(root: Instance, name: string, callback: () -> ())
	local node = root:FindFirstChild(name, true)
	assert(node and node:IsA("GuiButton"), "Missing authored action " .. name)
	runtime.connect(node, "Activated", callback)
end
local function enter(name: string)
	route:set(name)
	panelOpen:set(true)
end
local function explore()
	immersive:set(true)
	panelOpen:set(false)
end
local function updatePresence()
	local names = {}
	for _, visitor in players:GetPlayers() do
		table.insert(names, visitor.DisplayName .. (if visitor == player then " (you)" else ""))
	end
	table.sort(names)
	presence:set(table.concat(names, "\n"))
end
local connections = {
	players.PlayerAdded:Connect(updatePresence),
	players.PlayerRemoving:Connect(function()
		task.defer(updatePresence)
	end),
	signal.OnClientEvent:Connect(function(index: number)
		place:set(index)
		enter("Furnish")
	end),
}
updatePresence()
local stop = runtime.mount(function()
	local theme = Facet.themes.define(Facet.themes.neutralPackage())
	local UI = Facet.controls(runtime, {
		theme = theme,
		keyboardNavigation = true,
		environment = {
			preferredTextSize = Compose.formula(function(use: Use)
				return if use(larger) then "Largest" else game:GetService("GuiService").PreferredTextSize.Name
			end),
		},
	})
	local sheet =
		Facet.themes.createStyleSheet(runtime, theme, { theme = palette, tenFoot = UI.environment().isTenFoot })
	local function page(): GuiObject
		local name = route:peek()
		local components: { [string]: (Facet.Controls, { [string]: any }?) -> GuiObject } = {
			Home = require(pages:WaitForChild("Home")),
			Furnish = require(pages:WaitForChild("Furnish")),
			Activities = require(pages:WaitForChild("Activities")),
			People = require(pages:WaitForChild("People")),
			Settings = require(pages:WaitForChild("Settings")),
		}
		local component = assert(components[name])
		local inputs: { [string]: any } = {
			InventoryRows = Compose.formula(function(use: Use)
				local rows = {}
				for _, item in policy.catalog do
					if policy.matches(item, use(query)) then
						local count = 0
						for _, piece in use(layout).slots do
							if piece.kind == item.id then
								count += 1
							end
						end
						table.insert(rows, {
							id = item.id,
							name = item.name,
							category = item.category,
							quantity = count,
							finish = use(finish),
						})
					end
				end
				return rows
			end),
			ChooseFurniture = function(item: Furniture)
				chosen:set(item.id)
			end,
			PlaceFurniture = function(item: Furniture)
				chosen:set(item.id)
				request("place")
			end,
		}
		local root = component(UI, inputs)
		if name == "Home" then
			local destinations: { [string]: string } =
				{ OpenFurnish = "Furnish", OpenActivities = "Activities", OpenPeople = "People" }
			for button, destination in destinations do
				action(root, button, function()
					enter(destination)
				end)
			end
			action(root, "Explore", explore)
			text(root, "ProjectProgress", function(use: Use)
				return tostring(math.min(3, policy.count(use(layout)))) .. " / 3 pieces placed"
			end)
			text(root, "RoomSummary", function(use: Use)
				return tostring(policy.count(use(layout))) .. " pieces placed · Your space, your pace."
			end)
		elseif name == "Furnish" then
			text(root, "Selection", function(use: Use)
				local id = use(chosen)
				local label = id
				for _, item in policy.catalog do
					if item.id == id then
						label = item.name
						break
					end
				end
				return label .. " · Place " .. use(place) .. " · " .. use(finish)
			end)
			local search = root:FindFirstChild("FurnitureSearch", true) :: TextBox
			local changed = search:GetPropertyChangedSignal("Text"):Connect(function()
				query:set(search.Text)
			end)
			Compose.cleanup(function()
				changed:Disconnect()
			end)
			runtime.decorate(search, { Text = query })
			local empty = root:FindFirstChild("EmptyFurniture", true) :: GuiObject
			runtime.decorate(empty, {
				Visible = function(use: Use)
					for _, item in policy.catalog do
						if policy.matches(item, use(query)) then
							return false
						end
					end
					return true
				end,
			})
			for index = 1, policy.SLOTS do
				action(root, "Slot_" .. index, function()
					place:set(index)
				end)
			end
			for _, command in { "Place", "Rotate", "Remove", "Save", "Restore" } do
				action(root, command, function()
					request(string.lower(command))
				end)
			end
			for _, color in policy.palettes do
				action(root, "Palette_" .. color, function()
					finish:set(color)
					if layout:peek().slots[tostring(place:peek())] then
						request("paint")
					end
				end)
			end
		elseif name == "Activities" then
			text(root, "ActivityProgress", function(use: Use)
				return tostring(use(score)) .. " / 4 notes"
			end)
			text(root, "ActivityResult", activity)
			for index = 1, 4 do
				action(root, "Note_" .. index, function()
					local nextScore, correct = policy.puzzleNext(score:peek(), index)
					score:set(nextScore)
					activity:set(
						if nextScore == 4
							then "A little harmony. You completed the sequence!"
							elseif correct then "Lovely. Choose the next note."
							else "Try again. Start with LEAF."
					)
				end)
			end
			action(root, "ResetActivity", function()
				score:set(0)
				activity:set("Start with LEAF.")
			end)
			action(root, "Garden", explore)
		elseif name == "People" then
			text(root, "Presence", presence)
			action(root, "ExploreNeighborhood", explore)
		elseif name == "Settings" then
			action(root, "TogglePalette", function()
				palette:set(if palette:peek() == "Light" then "Dark" else "Light")
			end)
			action(root, "ToggleText", function()
				larger:set(not larger:peek())
			end)
			action(root, "ToggleMode", function()
				immersive:set(not immersive:peek())
			end)
		end
		return root
	end
	local buttons: { Instance } = {}
	for index, name in { "Home", "Furnish", "Activities", "People", "Settings" } do
		table.insert(
			buttons,
			UI.Button("Go" .. name) {
				label = if name == "Activities" then "Play" elseif name == "Furnish" then "Build" else name,
				appearance = function(use: Use)
					return if use(route) == name then "soft" else "utility"
				end,
				AutomaticSize = Enum.AutomaticSize.None,
				Size = UDim2.new(0.2, -7, 0, 44),
				LayoutOrder = index,
				onActivate = function()
					enter(name)
				end,
			}
		)
	end
	local panel = Host.Frame "HomePanel" {
		Visible = panelOpen,
		Position = function(use: Use)
			return if use(immersive) then UDim2.fromOffset(12, 12) else UDim2.new(0.5, 0, 0, 12)
		end,
		AnchorPoint = function(use: Use)
			return if use(immersive) then Vector2.zero else Vector2.new(0.5, 0)
		end,
		Size = UDim2.new(1, -24, 1, -76),
		Host.UISizeConstraint {
			MaxSize = function(use: Use)
				return Vector2.new(if use(immersive) then 600 else 720, 100000)
			end,
		},
		Host.UICorner {},
		Host.Frame "Navigation" {
			Size = UDim2.new(1, 0, 0, 48),
			BackgroundTransparency = 1,
			Host.UIListLayout {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			},
			table.unpack(buttons),
		},
		Host.Frame "Page" {
			Position = UDim2.fromOffset(0, 52),
			Size = UDim2.new(1, 0, 1, -52),
			BackgroundTransparency = 1,
			Compose.keyed({
				from = function(use: Use)
					return { use(route) }
				end,
				key = function(name)
					return name
				end,
				render = function()
					return page()
				end,
			}),
		},
	}
	local panelFrame = panel :: Frame
	panelFrame:AddTag("facet-panel")
	Compose.watch(function(use: Use)
		local camera = workspace.CurrentCamera
		if camera then
			camera.CameraType = if use(immersive) and not use(panelOpen)
				then Enum.CameraType.Custom
				else Enum.CameraType.Scriptable
			if not use(immersive) or use(panelOpen) then
				camera.CFrame =
					CFrame.lookAt(use(origin) + Vector3.new(24, 22, -29), use(origin) + Vector3.new(-4, 2, 0))
			end
		end
	end)
	local camera = workspace.CurrentCamera
	if camera then
		local changed = camera:GetPropertyChangedSignal("CameraType"):Connect(function()
			if (panelOpen:peek() or not immersive:peek()) and camera.CameraType ~= Enum.CameraType.Scriptable then
				camera.CameraType = Enum.CameraType.Scriptable
			end
		end)
		Compose.cleanup(function()
			changed:Disconnect()
		end)
	end
	local dock = Host.Frame "HomeDock" {
		Position = UDim2.new(0, 12, 1, -56),
		Size = UDim2.new(1, -24, 0, 48),
		Host.UICorner {},
		UI.Button "HomeToggle" {
			label = function(use: Use)
				return if use(panelOpen) then "Explore" else "Open Home"
			end,
			appearance = "emphasis",
			Size = UDim2.fromOffset(118, 44),
			onActivate = function()
				if panelOpen:peek() then
					explore()
				else
					panelOpen:set(true)
				end
			end,
		},
		UI.Text "Status" {
			text = function(use: Use)
				return use(status)
			end,
			textRole = "caption" :: "caption",
			Position = UDim2.fromOffset(132, 0),
			Size = UDim2.new(1, -132, 0, 48),
			AutomaticSize = Enum.AutomaticSize.None,
			wrap = true,
		},
	}
	local dockFrame = dock :: Frame
	dockFrame:AddTag("facet-panel")
	return Host.ScreenGui "FacetHomeUI" {
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		SafeAreaCompatibility = Enum.SafeAreaCompatibility.None,
		sheet,
		Host.StyleLink { StyleSheet = Compose.static(sheet) },
		panel,
		dock,
		UI.focusRing(player:WaitForChild("PlayerGui")),
	}
end, player:WaitForChild("PlayerGui"))
request("load")
local homes = workspace:WaitForChild("FacetHomes")
local function mountBoard(room: Instance)
	if boardMounted or room:GetAttribute("OwnerUserId") ~= player.UserId then
		return
	end
	local board = room:WaitForChild("HomeBoard") :: BasePart
	boardMounted = true
	runtime.mount(function()
		local theme = Facet.themes.define(Facet.themes.neutralPackage())
		local UI = Facet.controls(runtime, { theme = theme })
		local sheet = Facet.themes.createStyleSheet(runtime, theme, { theme = "Dark" })
		return Host.SurfaceGui "HomeWallUI" {
			Adornee = board,
			Face = Enum.NormalId.Front,
			CanvasSize = Vector2.new(800, 380),
			sheet,
			Host.StyleLink { StyleSheet = Compose.static(sheet) },
			require(pages:WaitForChild("Wall"))(UI),
		}
	end, player.PlayerGui)
end
for _, room in homes:GetChildren() do
	task.spawn(mountBoard, room)
end
table.insert(connections, homes.ChildAdded:Connect(mountBoard))
script.Destroying:Connect(function()
	for _, connection in connections do
		connection:Disconnect()
	end
	stop()
	runtime:dispose()
end)
