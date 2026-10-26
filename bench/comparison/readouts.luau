--!strict

local Types = require("./types")
local S = require("./support")
local Facet = require("../../src")
type BillboardProps = typeof(require("@repo/tools/typecheck/aliases").BillboardGuiNativeProps)
type FolderProps = typeof(require("@repo/tools/typecheck/aliases").FolderNativeProps)

local workloads: { Types.Workload } = {}

table.insert(workloads, {
	id = "main-menu-cold",
	iterations = 1,
	what = "Mount a background, title, six actions and footer; runtime and control-factory setup is excluded.",
	prepare = function(world: Types.World, lane: Types.Lane): Types.Scene
		local UI = world.UI
		local labels = { "Play", "Inventory", "Shop", "Settings", "Credits", "Exit" }
		local stop: () -> () = function() end
		return {
			step = function()
				stop = S.mount(world, lane, function()
					local children: { Instance } = { UI.Text "Title" { text = "Outpost", textRole = "title" } }
					for _, label in labels do
						table.insert(children, UI.Button(label) { label = label, onActivate = function() end })
					end
					table.insert(children, UI.Text "Footer" { text = "Season 4" })
					return UI.VStack "Menu" { width = 640, gap = 8, surface = "surface", table.unpack(children) }
				end, function(screen)
					local root = S.stack(world, screen, "Menu")
					root.BackgroundTransparency = 0
					S.text(world, root, "Title", "Outpost")
					for _, label in labels do
						S.button(world, root, label, label, function() end)
					end
					S.text(world, root, "Footer", "Season 4")
				end)
			end,
			snapshot = function()
				if #world.target:GetChildren() == 0 then
					return "unmounted"
				end
				return S.snapshot(
					world,
					{ "Title", "Play", "Inventory", "Shop", "Settings", "Credits", "Exit", "Footer" }
				)
			end,
			stop = function()
				stop()
			end,
		}
	end,
})

table.insert(workloads, {
	id = "hud-600-frames",
	iterations = 600,
	what = "Update health fill, ammo, currency and timer once per simulated frame.",
	prepare = function(world: Types.World, lane: Types.Lane): Types.Scene
		local UI, Compose = world.UI, world.Compose
		local health, ammo, coins, timer =
			S.model(world, lane, 1), S.model(world, lane, "30"), S.model(world, lane, "0"), S.model(world, lane, "0:00")
		local bareFill: S.Node? = nil
		local bareAmmo: S.Node? = nil
		local bareCoins: S.Node? = nil
		local bareTimer: S.Node? = nil
		local stop = S.mount(world, lane, function()
			return UI.HStack "HUD" {
				width = 640,
				gap = 8,
				UI.ProgressView "Health" { value = assert(health) },
				UI.Text "Ammo" { text = assert(ammo) },
				UI.Text "Coins" { text = assert(coins) },
				UI.Text "Timer" { text = assert(timer) },
			}
		end, function(screen)
			local root = S.stack(world, screen, "HUD", true)
			bareFill = S.progress(world, root, "Health", 1)
			bareAmmo = S.text(world, root, "Ammo", "30")
			bareCoins = S.text(world, root, "Coins", "0")
			bareTimer = S.text(world, root, "Timer", "0:00")
		end)
		return {
			step = function(frame: number)
				local h, a, c, t =
					1 - frame % 100 / 100,
					tostring(30 - frame % 30),
					tostring(frame * 5),
					string.format("%d:%02d", math.floor(frame / 60), frame % 60)
				if lane == "facet" then
					assert(health):set(h)
					assert(ammo):set(a)
					assert(coins):set(c)
					assert(timer):set(t)
				else
					assert(bareFill).Size = world.types.UDim2.fromScale(h, 1)
					assert(bareAmmo).Text = a
					assert(bareCoins).Text = c
					assert(bareTimer).Text = t
				end
				world.frame()
			end,
			snapshot = function()
				return S.snapshot(world, { "Ammo", "Coins", "Timer" }) .. "\nHealth:" .. S.fraction(world, "Health")
			end,
			stop = stop,
		}
	end,
})

table.insert(workloads, {
	id = "progress-20-120-frames",
	iterations = 120,
	what = "Drive 20 measured progress fills with per-frame values; both lanes use the same linear frame sequence.",
	prepare = function(world: Types.World, lane: Types.Lane): Types.Scene
		local UI, Compose = world.UI, world.Compose
		local values: { Facet.Value<number> } = {}
		local fills: { S.Node } = {}
		for _ = 1, 20 do
			if lane == "facet" then
				table.insert(values, Compose.cell(0))
			end
		end
		local stop = S.mount(world, lane, function()
			local children: { Instance } = {}
			for i, value in values do
				table.insert(children, UI.ProgressView("Progress" .. i) { value = value })
			end
			return UI.VStack "Progress" { width = 640, gap = 8, table.unpack(children) }
		end, function(screen)
			local root = S.stack(world, screen, "Progress")
			for i = 1, 20 do
				table.insert(fills, S.progress(world, root, "Progress" .. i, 0))
			end
		end)
		return {
			step = function(frame: number)
				for i = 1, 20 do
					local fraction = math.min(1, frame / 120)
					if lane == "facet" then
						values[i]:set(fraction)
					else
						fills[i].Size = world.types.UDim2.fromScale(fraction, 1)
					end
				end
				world.frame()
			end,
			snapshot = function()
				local rows = {}
				for i = 1, 20 do
					table.insert(rows, S.fraction(world, "Progress" .. i))
				end
				return table.concat(rows, ",")
			end,
			stop = stop,
		}
	end,
})

table.insert(workloads, {
	id = "badges-30-300-updates",
	iterations = 300,
	what = "Update all 30 notification counts, 300 times; badges keep their native text nodes.",
	prepare = function(world: Types.World, lane: Types.Lane): Types.Scene
		local UI, Compose = world.UI, world.Compose
		local values: { Facet.Value<string> } = {}
		local names: { string } = {}
		local nodes: { S.Node } = {}
		for i = 1, 30 do
			if lane == "facet" then
				table.insert(values, Compose.cell("1"))
			end
			table.insert(names, "Badge" .. i)
		end
		local stop = S.mount(world, lane, function()
			local children: { Instance } = {}
			for i, value in values do
				table.insert(
					children,
					UI.Badge(names[i]) {
						label = function(use: Facet.Use)
							return use(value)
						end,
					}
				)
			end
			return UI.Grid "Badges" { columns = 6, gap = 8, table.unpack(children) }
		end, function(screen)
			local root = S.grid(world, screen, "Badges", 6)
			for _, name in names do
				local node = S.text(world, root, name, "1")
				table.insert(nodes, node)
				S.create(world, "UIPadding", "Padding", node)
			end
		end)
		return {
			step = function(frame: number)
				for i = 1, 30 do
					local label = tostring((frame + i) % 99 + 1)
					if lane == "facet" then
						values[i]:set(label)
					else
						nodes[i].Text = label
					end
				end
			end,
			snapshot = function()
				return S.snapshot(world, names)
			end,
			stop = stop,
		}
	end,
})

table.insert(workloads, {
	id = "world-markers-50",
	iterations = 100,
	what = "Update the labels of 50 native BillboardGui markers anchored to Parts.",
	prepare = function(world: Types.World, lane: Types.Lane): Types.Scene
		local UI, Compose, Host = world.UI, world.Compose, world.Host
		local values: { Facet.Value<string> } = {}
		local names: { string } = {}
		local nodes: { S.Node } = {}
		for i = 1, 50 do
			if lane == "facet" then
				table.insert(values, Compose.cell("Target " .. i))
			end
			table.insert(names, "MarkerLabel" .. i)
		end
		local stop = S.mount(world, lane, function()
			local children: { Instance } = {}
			for i, value in values do
				local anchor = Host.Part { Name = "Anchor" .. i, Anchored = true }
				table.insert(children, anchor)
				local props: BillboardProps = {
					Name = "Marker" .. i,
					Adornee = Compose.static(anchor),
					Size = world.types.UDim2.fromOffset(120, 32),
					UI.Text(names[i]) { text = value },
				}
				table.insert(children, Host.BillboardGui(props))
			end
			local props: FolderProps = { Name = "Markers", table.unpack(children) }
			return Host.Folder(props)
		end, function(screen)
			local root = S.create(world, "Folder", "Markers", screen)
			for i, name in names do
				local anchor = S.create(world, "Part", "Anchor" .. i, root, { Anchored = true })
				local billboard = S.create(
					world,
					"BillboardGui",
					"Marker" .. i,
					root,
					{ Adornee = anchor, Size = world.types.UDim2.fromOffset(120, 32) }
				)
				table.insert(nodes, S.text(world, billboard, name, "Target " .. i))
			end
		end)
		return {
			step = function(frame: number)
				for i = 1, 50 do
					local label = `Target {i}: {frame}m`
					if lane == "facet" then
						values[i]:set(label)
					else
						nodes[i].Text = label
					end
				end
			end,
			snapshot = function()
				return S.snapshot(world, names)
			end,
			stop = stop,
		}
	end,
})

return workloads
