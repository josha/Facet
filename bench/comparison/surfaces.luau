--!strict

local Facet = require("../../src")
local Types = require("./types")
local S = require("./support")
type FrameProps = typeof(require("@repo/tools/typecheck/aliases").FrameNativeProps)

local workloads: { Types.Workload } = {}

local function labels(world: Types.World, prefix: string): string
	local rows: { string } = {}
	for _, node in world.target:GetDescendants() do
		if node:IsA("TextLabel") and type(node.Text) == "string" and string.sub(node.Text, 1, #prefix) == prefix then
			table.insert(rows, node.Text)
		end
	end
	table.sort(rows)
	return table.concat(rows, "\n")
end

table.insert(workloads, {
	id = "dialog-50-cycles",
	iterations = 100,
	what = "Open a confirmation dialog, then activate Confirm and close it, 50 times.",
	prepare = function(world: Types.World, lane: Types.Lane): Types.Scene
		local UI = world.UI
		local open = S.model(world, lane, false)
		local confirmed = 0
		local panel: S.Node? = nil
		local parent: S.Node? = nil
		local stop = S.mount(world, lane, function()
			local actions: { Facet.DialogAction } = {
				{
					id = "Confirm",
					label = "Confirm",
					role = "default",
					onActivate = function()
						confirmed += 1
					end,
				},
			}
			local spec: Facet.DialogSpec = {
				isPresented = assert(open),
				onPresentedChange = function(value)
					assert(open):set(value)
				end,
				title = "Buy kart?",
				content = function()
					return UI.Text "Terms" { text = "Purchase costs 100 coins." }
				end,
				actions = actions,
			}
			return UI.Dialog "ConfirmDialog"(spec)
		end, function(screen)
			parent = screen
		end)
		return {
			step = function(index: number)
				if index % 2 == 1 then
					if lane == "facet" then
						assert(open):set(true)
					else
						panel = S.create(
							world,
							"Frame",
							"DialogLayer",
							assert(parent),
							{ Size = world.types.UDim2.fromScale(1, 1) }
						)
						S.button(world, assert(panel), "Scrim", "", function()
							if panel then
								panel:Destroy()
								panel = nil
							end
						end)
						local body = S.stack(world, panel, "Panel")
						S.text(world, body, "Title", "Buy kart?")
						local scroll = S.create(world, "ScrollingFrame", "Content", body, {
							AutomaticCanvasSize = world.types.Enum.AutomaticSize.Y,
							Size = world.types.UDim2.fromOffset(320, 120),
						})
						S.text(world, scroll, "Terms", "Purchase costs 100 coins.")
						S.button(world, body, "Confirm", "Confirm", function()
							confirmed += 1
							assert(panel):Destroy()
							panel = nil
						end)
					end
				else
					S.fire(world, "Confirm", "Activated")
				end
				world.frame(1)
			end,
			snapshot = function()
				return tostring(confirmed) .. ":" .. labels(world, "Purchase costs")
			end,
			stop = stop,
		}
	end,
})

table.insert(workloads, {
	id = "toast-stream-100",
	iterations = 200,
	what = "Show 100 one-shot result toasts and let each auto-dismiss after its four-second display duration.",
	prepare = function(world: Types.World, lane: Types.Lane): Types.Scene
		local UI, Compose = world.UI, world.Compose
		local initial: { number } = {}
		local messages = S.model(world, lane, initial)
		local panel: S.Node? = nil
		local parent: S.Node? = nil
		local remaining = 0
		local connection = world.engine.heartbeat:Connect(function(dt: number)
			if lane == "bare" and panel then
				remaining -= dt
				if remaining <= 0 then
					panel:Destroy()
					panel = nil
				end
			end
		end)
		local stop = S.mount(world, lane, function()
			local Host = world.Host
			local props: FrameProps = {
				Name = "Toasts",
				Compose.keyed {
					from = assert(messages),
					key = function(id: number)
						return id
					end,
					render = function(current: Facet.ReadOnlyValue<number>)
						return UI.Toast {
							message = function(use: Facet.Use)
								return `Reward {use(current)}`
							end,
						}
					end,
				},
			}
			return Host.Frame(props)
		end, function(screen)
			parent = screen
		end)
		return {
			step = function(index: number)
				if index % 2 == 1 then
					local id = math.ceil(index / 2)
					if lane == "facet" then
						assert(messages):set({ id })
					else
						panel = S.stack(world, assert(parent), "Toast")
						S.text(world, assert(panel), "Message", `Reward {id}`)
						remaining = 4
					end
					world.frame()
				else
					world.frame(5)
					world.frame(1)
				end
			end,
			snapshot = function()
				return labels(world, "Reward ")
			end,
			stop = function()
				connection:Disconnect()
				stop()
			end,
		}
	end,
})

table.insert(workloads, {
	id = "tabs-5-100-switches",
	iterations = 100,
	what = "Switch 100 times among five peer pages; retain each visited page and its content.",
	prepare = function(world: Types.World, lane: Types.Lane): Types.Scene
		local UI = world.UI
		local selection = S.model(world, lane, "1")
		local current = "1"
		local pages: { [string]: S.Node } = {}
		local tabs: { Facet.Tab } = {}
		for i = 1, 5 do
			table.insert(tabs, {
				id = tostring(i),
				label = `Tab {i}`,
				content = function()
					return UI.Text("Page" .. i) { text = `Page {i} content` }
				end,
			})
		end
		local stop = S.mount(world, lane, function()
			return UI.TabView "Tabs" {
				selection = assert(selection),
				tabs = tabs,
				placement = "topBar",
				transition = false,
			}
		end, function(screen)
			local root = S.stack(world, screen, "Tabs")
			local bar = S.stack(world, root, "TabBar", true)
			local function select(id: string)
				for _, page in pages do
					page.Visible = false
				end
				current = id
				if not pages[id] then
					pages[id] = S.text(world, root, "Page" .. id, `Page {id} content`)
				end
				pages[id].Visible = true
			end
			for i = 1, 5 do
				S.button(world, bar, "Tab" .. i, `Tab {i}`, function()
					select(tostring(i))
				end)
			end
			select("1")
		end)
		return {
			step = function(index: number)
				local id = tostring(index % 5 + 1)
				if lane == "facet" then
					assert(selection):set(id)
				else
					S.fire(world, "Tab" .. id, "Activated")
				end
				world.frame()
			end,
			snapshot = function()
				local id = if lane == "facet" then assert(selection):peek() else current
				return tostring(S.find(world, "Page" .. id).Text) .. ":" .. labels(world, "Page ")
			end,
			stop = stop,
		}
	end,
})

table.insert(workloads, {
	id = "radial-50-cycles",
	iterations = 100,
	what = "Open a four-command radial menu, select Wave and close, 50 times; bare positions four native buttons around the same centre.",
	prepare = function(world: Types.World, lane: Types.Lane): Types.Scene
		local UI = world.UI
		local open = S.model(world, lane, false)
		local actions = { "Wave", "Dance", "Point", "Cheer" }
		local items: { Facet.RadialItem<string> } = {}
		local selected = ""
		for _, label in actions do
			local item: Facet.RadialAction<string> = {
				id = label,
				label = label,
				onSelect = function()
					selected = label
				end,
			}
			table.insert(items, item)
		end
		local panel: S.Node? = nil
		local parent: S.Node? = nil
		local stop = S.mount(world, lane, function()
			local spec: Facet.RadialMenuSpec<string> =
				{ label = "Emotes", isPresented = assert(open), items = items, preset = "donut" }
			return UI.RadialMenu "Emotes"(spec)
		end, function(screen)
			parent = screen
			S.button(world, screen, "Launcher", "Emotes", function() end)
		end)
		return {
			step = function(index: number)
				if index % 2 == 1 then
					if lane == "facet" then
						assert(open):set(true)
					else
						panel = S.create(
							world,
							"Frame",
							"Ring",
							assert(parent),
							{ Size = world.types.UDim2.fromOffset(320, 320), BackgroundTransparency = 1 }
						)
						for i, label in actions do
							local button = S.button(world, assert(panel), label, label, function()
								selected = label
								assert(panel):Destroy()
								panel = nil
							end)
							local radians = (i - 1) * math.pi / 2
							button.Position = world.types.UDim2.fromOffset(
								160 + math.cos(radians) * 100,
								160 + math.sin(radians) * 100
							)
						end
						S.button(world, assert(panel), "Close", "Close", function()
							assert(panel):Destroy()
							panel = nil
						end)
					end
				else
					local target: S.Node? = nil
					for _, node in world.target:GetDescendants() do
						if node:IsA("TextButton") and node.Text == "Wave" then
							target = node
							break
						end
					end
					assert(target, "Wave target missing")
					world.engine.environment.fire(target, "Activated")
					if lane == "facet" then
						assert(open):set(false)
					end
				end
				world.frame(1)
			end,
			snapshot = function()
				return selected
			end,
			stop = stop,
		}
	end,
})

table.insert(workloads, {
	id = "navigation-5-20-cycles",
	iterations = 200,
	what = "Push five child pages and pop them, 20 times; root has no Back action and covered pages remain retained.",
	prepare = function(world: Types.World, lane: Types.Lane): Types.Scene
		local UI, Compose = world.UI, world.Compose
		local initial: { Facet.NavigationEntry<number> } = {}
		local path = S.model(world, lane, initial)
		local depth = 0
		local pages: { S.Node } = {}
		local parent: S.Node? = nil
		local function barePush(level: number)
			if #pages > 0 then
				pages[#pages].Visible = false
			end
			local page = S.stack(world, assert(parent), "Level" .. level)
			local bar = S.stack(world, page, "NavigationBar", true)
			if level > 0 then
				local back = S.button(world, bar, "Back" .. level, "", function() end)
				local row = S.stack(world, back, "Content", true)
				S.create(world, "ImageLabel", "LeadingIcon", row, { Size = world.types.UDim2.fromOffset(20, 20) })
				S.text(world, row, "Title", "Back")
			end
			S.text(world, bar, "Title", `Level {level}`)
			local destination = S.stack(world, page, "Destination")
			S.text(world, destination, "PageText" .. level, `Destination {level}`)
			table.insert(pages, page)
		end
		local destinations: { [string]: Facet.NavigationDestination<number> } = {
			level = {
				title = "Details",
				content = function(entry)
					assert(entry and entry.value)
					return UI.Text("PageText" .. entry.value) { text = `Destination {entry.value}` }
				end,
			},
		}
		local stop = S.mount(world, lane, function()
			return UI.NavigationStack "Navigation" {
				path = assert(path),
				root = {
					title = "Home",
					content = function()
						return UI.Text "PageText0" { text = "Destination 0" }
					end,
				},
				destinations = destinations,
				transition = false,
			}
		end, function(screen)
			parent = S.stack(world, screen, "Navigation")
			barePush(0)
		end)
		return {
			step = function(index: number)
				local phase = (index - 1) % 10
				depth += if phase < 5 then 1 else -1
				if lane == "facet" then
					local nextPath = table.clone(assert(path):peek())
					if phase < 5 then
						table.insert(nextPath, { id = "level", value = depth })
					else
						table.remove(nextPath)
					end
					assert(path):set(nextPath)
				elseif phase < 5 then
					barePush(depth)
				else
					assert(table.remove(pages)):Destroy()
					pages[#pages].Visible = true
				end
				world.frame()
			end,
			snapshot = function()
				return tostring(S.find(world, "PageText" .. depth).Text) .. ":" .. labels(world, "Destination ")
			end,
			stop = stop,
		}
	end,
})

return workloads
