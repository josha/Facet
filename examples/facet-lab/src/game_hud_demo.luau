--!strict
local CatalogTypes = require("./catalog_types")
type Context = CatalogTypes.Context

local function Demo(c: Context): Instance
	local UI, Host, Compose = c.UI, c.Host, c.Compose
	local remaining, charges = Compose.cell(6), Compose.cell(2)
	local world = Compose.cell(false)
	local clock = c.app.runtime.clock({ step = 0.05 })
	local started = Compose.cell(0)
	Compose.watch(function(use: CatalogTypes.Use)
		remaining:set(math.max(0, 6 - (use(clock) - use(started))))
	end)
	local help = {
		title = "Action",
		body = "Inspect the action before using it.",
		rows = { { label = "Range", value = "Near" }, { label = "Target", value = "Selected object" } },
		cost = "Cost: 12 energy",
		cooldown = "Cooldown: 6 seconds",
		flavour = "A short supporting detail.",
	}
	return UI.VStack "GameHUD" {
		gap = "m",
		align = "stretch",
		width = "fill",
		UI.Text { text = "Use the action. Hover, select, or long-press it to inspect its details.", wrap = true },
		UI.Button "ActionSlot" {
			label = "",
			icon = "bolt",
			Size = UDim2.fromOffset(64, 64),
			AutomaticSize = Enum.AutomaticSize.None,
			cooldown = { remaining = remaining, total = 6 },
			charges = charges,
			help = help,
			onActivate = function()
				started:set(clock:peek())
				charges:set(math.max(0, charges:peek() - 1))
			end,
		},
		UI.Button {
			label = "Restore charges",
			onActivate = function()
				charges:set(2)
			end,
		},
		UI.Toggle { label = "Show world surfaces", value = world },
		Compose.show(world, function()
			local player = game:GetService("Players").LocalPlayer
			local playerGui = player:FindFirstChildWhichIsA("PlayerGui")
			assert(playerGui)
			local camera = assert(workspace.CurrentCamera)
			local part = Host.Part "HUDSurfaceTarget" {
				Anchored = true,
				CanCollide = false,
				CanQuery = true,
				Size = Vector3.new(5, 3, 0.2),
				CFrame = camera.CFrame * CFrame.new(0, 0, -12),
			}
			local nameplate = Host.BillboardGui "HUDNameplate" {
				Adornee = Compose.static(part),
				Size = UDim2.fromOffset(220, 48),
				StudsOffsetWorldSpace = Vector3.new(0, 2, 0),
				MaxDistance = 80,
				Active = true,
			}
			local prompt = Host.SurfaceGui "HUDPrompt" {
				Adornee = Compose.static(part),
				Face = Enum.NormalId.Back,
				SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
				CanvasSize = Vector2.new(400, 240),
				MaxDistance = 80,
				Active = true,
			}
			return Host.Folder {
				Compose.portal(workspace, function()
					return { part }
				end),
				Compose.portal(playerGui, function()
					return { nameplate, prompt }
				end),
				UI.worldSurface(nameplate, function()
					return UI.Text { text = "World target", textRole = "heading", Size = UDim2.fromScale(1, 1) }
				end),
				UI.worldSurface(prompt, function()
					return UI.Button {
						label = "Restore charges",
						Size = UDim2.fromScale(1, 1),
						onActivate = function()
							charges:set(2)
						end,
					}
				end),
			}
		end),
	}
end

local page: CatalogTypes.PageDefinition = {
	family = "input",
	title = "Game HUD",
	recipe = true,
	facet = true,
	purpose = "Use an action slot, inspect its details, and interact with a world prompt in one mounted tree.",
	snippet = 'UI.Button { icon = "bolt", cooldown = { remaining = remaining, total = 6 }, charges = charges }',
	demonstrates = { "cooldown", "charges", "help", "worldSurface" },
	axes = {},
	states = {},
	make = function(_UI: CatalogTypes.FacetControls, _props: {}, c: Context): Instance
		return Demo(c)
	end,
}
return function(pages: { [string]: CatalogTypes.PageDefinition })
	pages.WorldMarker = require("./world_marker_demo")
	pages.GameHUD = page
	pages.worldSurface = {
		family = "input",
		host = "GameHUD",
		purpose = "Place themed content on a native world surface from the mounted tree.",
		axes = {},
		states = {},
	}
end
