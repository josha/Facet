--!strict

local Facet = require("../../src")
local Types = require("./types")
local S = require("./support")
local Roblox = require("../../tools/vendor/verify/src/roblox")

local workloads: { Types.Workload } = {}

for _, count in { 100, 500 } do
	table.insert(workloads, {
		id = "inventory-" .. count,
		iterations = 200,
		what = `Select among {count} retained slots 200 times; each slot has an activation target and selected state.`,
		prepare = function(world: Types.World, lane: Types.Lane): Types.Scene
			local UI = world.UI
			local initial: { [number]: boolean } = { [1] = true }
			local selected = S.model(world, lane, initial)
			local data: { number } = {}
			for i = 1, count do
				table.insert(data, i)
			end
			local current = 1
			local buttons: { Roblox.Instance } = {}
			local labels: { Roblox.Instance } = {}
			local plates: { Roblox.Instance } = {}
			local stop = S.mount(world, lane, function()
				local spec: Facet.KeyedCollectionSpec<number, number> = {
					from = data,
					key = function(id)
						return id
					end,
					mode = "all",
					columns = 10,
					itemSize = 44,
					gap = 8,
					measure = false,
					selection = assert(selected),
					Size = world.types.UDim2.fromOffset(640, 480),
					render = function(item)
						return UI.Text("Slot" .. item:peek()) {
							text = function(use: Facet.Use)
								return `Item {use(item)}`
							end,
						}
					end,
				}
				return UI.VirtualGrid "Inventory"(spec)
			end, function(screen)
				local root = S.create(world, "ScrollingFrame", "Inventory", screen, {
					Size = world.types.UDim2.fromOffset(640, 480),
					CanvasSize = world.types.UDim2.fromOffset(0, math.ceil(count / 10) * 52),
				})
				local items = S.create(
					world,
					"Frame",
					"Items",
					root,
					{ BackgroundTransparency = 1, Size = world.types.UDim2.fromOffset(640, math.ceil(count / 10) * 52) }
				)
				S.create(world, "UIPadding", "Padding", items)
				for i = 1, count do
					local plate = S.create(
						world,
						"CanvasGroup",
						tostring(i),
						items,
						{ BackgroundTransparency = 1, Size = world.types.UDim2.fromOffset(56, 44) }
					)
					plate.Position = world.types.UDim2.fromOffset((i - 1) % 10 * 64, math.floor((i - 1) / 10) * 52)
					plates[i] = plate
					local button = S.button(world, plate, "RowHit", "", function()
						plates[current]:RemoveTag("facet-selected")
						current = i
						plates[current]:AddTag("facet-selected")
					end)
					button.Size = world.types.UDim2.fromScale(1, 1)
					if i == 1 then
						plate:AddTag("facet-selected")
					end
					buttons[i] = button
					labels[i] = S.text(world, plate, "Slot" .. i, `Item {i}`)
				end
			end)
			if lane == "facet" then
				for i = 1, count do
					labels[i] = S.find(world, "Slot" .. i)
					local row = S.find(world, tostring(i))
					local hit = row:FindFirstChild("RowHit", true)
					assert(hit)
					plates[i] = assert(hit.Parent)
					buttons[i] = hit
				end
			end
			local root = S.find(world, "Inventory")
			world.engine.environment.poke(root, "AbsoluteSize", world.types.Vector2.new(640, 480))
			world.engine.environment.poke(root, "AbsoluteWindowSize", world.types.Vector2.new(640, 480))
			local mouse = { UserInputType = world.types.Enum.UserInputType.MouseButton1 }
			return {
				step = function(index: number)
					world.engine.environment.fire(buttons[index % count + 1], "Activated", mouse, 1)
				end,
				snapshot = function()
					local key = current
					if lane == "facet" then
						for id in assert(selected):peek() do
							key = id
						end
					end
					local selectedKeys: { string } = {}
					for i, plate in plates do
						local active = plate:HasTag("facet-selected")
						if active then
							table.insert(selectedKeys, tostring(i))
						end
					end
					assert(#selectedKeys == 1, "inventory must show one selected slot")
					return tostring(key) .. ":" .. tostring(labels[key].Text) .. ":" .. table.concat(selectedKeys, ",")
				end,
				stop = stop,
			}
		end,
	})
end

table.insert(workloads, {
	id = "shop-filter-200",
	iterations = 10,
	what = "Edit a native TextBox with ten queries, including empty and no match; retain the 200 catalog rows and set their visibility.",
	prepare = function(world: Types.World, lane: Types.Lane): Types.Scene
		local UI, Compose = world.UI, world.Compose
		local query = S.model(world, lane, "")
		local queries = { "1", "20", "Item", "99", "missing", "2", "10", "50", "200", "" }
		local items: { S.Node } = {}
		local function matches(label: string, value: string): boolean
			return string.find(label, value, 1, true) ~= nil
		end
		local stop = S.mount(world, lane, function()
			local children: { Instance } =
				{ UI.TextInput "Filter" { value = assert(query), placeholder = "Filter items" } }
			for i = 1, 200 do
				local label = `Item {i}`
				table.insert(
					children,
					UI.Button("Item" .. i) {
						label = label,
						onActivate = function() end,
						Visible = function(use: Facet.Use)
							return matches(label, use(assert(query)))
						end,
					}
				)
			end
			return UI.ScrollView "Shop" { gap = 8, Size = world.types.UDim2.fromOffset(640, 480), table.unpack(children) }
		end, function(screen)
			local scroll = S.create(world, "ScrollingFrame", "Shop", screen, {
				Size = world.types.UDim2.fromOffset(640, 480),
				AutomaticCanvasSize = world.types.Enum.AutomaticSize.Y,
			})
			local content = S.stack(world, scroll, "Content")
			local input = S.create(world, "TextBox", "Filter", content, {
				Text = "",
				PlaceholderText = "Filter items",
				Size = world.types.UDim2.fromOffset(240, 44),
				ClearTextOnFocus = false,
			})
			input:GetPropertyChangedSignal("Text"):Connect(function()
				local value = input.Text
				assert(type(value) == "string")
				for i = 1, 200 do
					items[i].Visible = matches(`Item {i}`, value)
				end
			end)
			for i = 1, 200 do
				local item = S.button(world, content, "Item" .. i, `Item {i}`, function() end)
				item.Visible = true
				table.insert(items, item)
			end
		end)
		return {
			step = function(index: number)
				S.fire(world, "Filter", "Focused")
				S.find(world, "Filter").Text = queries[index]
				world.frame()
			end,
			snapshot = function()
				local rows = { tostring(S.find(world, "Filter").Text) }
				for i = 1, 200 do
					if S.find(world, "Item" .. i).Visible ~= false then
						table.insert(rows, `Item {i}`)
					end
				end
				return table.concat(rows, "\n")
			end,
			stop = stop,
		}
	end,
})

table.insert(workloads, {
	id = "virtual-scroll-2000",
	iterations = 100,
	what = "Scroll a fixed 40-pixel row window from top to bottom; the plain lane keeps a small reusable row pool.",
	prepare = function(world: Types.World, lane: Types.Lane): Types.Scene
		local UI = world.UI
		local data: { string } = {}
		for i = 1, 2000 do
			table.insert(data, `Row {i}`)
		end
		local scroll: S.Node? = nil
		local pool: { S.Node } = {}
		local stop = S.mount(world, lane, function()
			local spec: Facet.KeyedCollectionSpec<string, string> = {
				from = data,
				key = function(item)
					return item
				end,
				itemSize = 40,
				measure = false,
				overscan = 2,
				Size = world.types.UDim2.fromOffset(640, 400),
				render = function(current)
					return UI.Text { text = current }
				end,
			}
			return UI.VirtualList "Rows"(spec)
		end, function(screen)
			scroll = S.create(world, "ScrollingFrame", "Rows", screen, {
				Size = world.types.UDim2.fromOffset(640, 400),
				CanvasSize = world.types.UDim2.fromOffset(0, 80000),
				CanvasPosition = world.types.Vector2.zero,
			})
			local container = assert(scroll)
			for i = 1, 15 do
				local row = S.text(world, container, "Pool" .. i, data[i], true)
				row.Visible = i <= 12
				row.Size = world.types.UDim2.fromOffset(640, 40)
				row.Position = world.types.UDim2.fromOffset(0, (i - 1) * 40)
				table.insert(pool, row)
			end
			container:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
				local position: unknown = container.CanvasPosition
				assert(typeof(position) == "Vector2")
				local first = math.max(1, math.floor(position.Y / 40) - 1)
				local last = math.min(2000, math.ceil((position.Y + 400) / 40) + 2)
				for i = 1, 15 do
					local row = pool[i]
					local index = first + i - 1
					S.setText(world, row, data[index] or "")
					row.Position = world.types.UDim2.fromOffset(0, (index - 1) * 40)
					row.Visible = index <= last
				end
			end)
		end)
		scroll = S.find(world, "Rows")
		world.engine.environment.poke(assert(scroll), "AbsoluteSize", world.types.Vector2.new(640, 400))
		world.engine.environment.poke(assert(scroll), "AbsoluteWindowSize", world.types.Vector2.new(640, 400))
		return {
			step = function(index: number)
				assert(scroll).CanvasPosition = world.types.Vector2.new(0, math.floor(index * 79600 / 100))
				world.frame()
			end,
			snapshot = function()
				local labels: { string } = {}
				for _, node in assert(scroll):GetDescendants() do
					if
						node:IsA("TextLabel")
						and node.Visible ~= false
						and type(node.Text) == "string"
						and node.Text ~= ""
					then
						table.insert(labels, node.Text)
					end
				end
				table.sort(labels)
				return table.concat(labels, ",")
			end,
			stop = stop,
		}
	end,
})

table.insert(workloads, {
	id = "chat-append-500",
	iterations = 500,
	what = "Append 500 keyed messages; remove the oldest when the log exceeds 100 rows.",
	prepare = function(world: Types.World, lane: Types.Lane): Types.Scene
		local UI, Compose = world.UI, world.Compose
		local initial: { number } = {}
		local messages = S.model(world, lane, initial)
		local plainRows: { S.Node } = {}
		local plainContent: S.Node? = nil
		local stop = S.mount(world, lane, function()
			return UI.ScrollView "Chat" {
				gap = 8,
				Size = world.types.UDim2.fromOffset(640, 480),
				Compose.keyed({
					from = assert(messages),
					key = function(id: number)
						return id
					end,
					render = function(current: Facet.ReadOnlyValue<number>)
						return UI.Text {
							text = function(use: Facet.Use)
								return `Player: message {use(current)}`
							end,
						}
					end,
				}),
			}
		end, function(screen)
			local scroll = S.create(world, "ScrollingFrame", "Chat", screen, {
				Size = world.types.UDim2.fromOffset(640, 480),
				AutomaticCanvasSize = world.types.Enum.AutomaticSize.Y,
			})
			plainContent = S.stack(world, scroll, "Content")
		end)
		return {
			step = function(index: number)
				if lane == "facet" then
					local nextRows = table.clone(assert(messages):peek())
					table.insert(nextRows, index)
					if #nextRows > 100 then
						table.remove(nextRows, 1)
					end
					assert(messages):set(nextRows)
				else
					table.insert(
						plainRows,
						S.text(world, assert(plainContent), "Message" .. index, `Player: message {index}`, true)
					)
					if #plainRows > 100 then
						assert(table.remove(plainRows, 1)):Destroy()
					end
				end
			end,
			snapshot = function()
				local labels: { string } = {}
				for _, node in S.find(world, "Chat"):GetDescendants() do
					if node:IsA("TextLabel") then
						table.insert(labels, tostring(node.Text))
					end
				end
				table.sort(labels)
				return table.concat(labels, "\n")
			end,
			stop = stop,
		}
	end,
})

table.insert(workloads, {
	id = "card-collection-60",
	iterations = 1,
	what = "Mount 60 cards with the same artwork, item title and price caption.",
	prepare = function(world: Types.World, lane: Types.Lane): Types.Scene
		local UI = world.UI
		local stop: () -> () = function() end
		return {
			step = function()
				stop = S.mount(world, lane, function()
					local children: { Instance } = {}
					for i = 1, 60 do
						table.insert(
							children,
							UI.Card("Card" .. i) {
								title = `Kart {i}`,
								caption = `{i * 10} coins`,
								image = "rbxassetid://0",
							}
						)
					end
					return UI.Grid "Cards" { columns = 6, gap = 8, table.unpack(children) }
				end, function(screen)
					local root = S.grid(world, screen, "Cards", 6)
					for i = 1, 60 do
						local card = S.stack(world, root, "Card" .. i)
						local body = S.stack(world, card, "Body")
						S.create(world, "UIPadding", "Padding", body)
						local image = S.create(world, "ImageLabel", "Artwork", body, {
							Image = "rbxassetid://0",
							Size = world.types.UDim2.fromScale(1, 0),
							AutomaticSize = world.types.Enum.AutomaticSize.Y,
						})
						S.create(world, "UIAspectRatioConstraint", "Aspect", image, { AspectRatio = 16 / 9 })
						S.text(world, body, "Title", `Kart {i}`)
						S.text(world, body, "Caption", `{i * 10} coins`)
					end
				end)
			end,
			snapshot = function()
				if #world.target:GetChildren() == 0 then
					return "unmounted"
				end
				local rows: { string } = {}
				for i = 1, 60 do
					local card = S.find(world, "Card" .. i)
					table.insert(
						rows,
						tostring(assert(card:FindFirstChild("Title", true)).Text)
							.. ":"
							.. tostring(assert(card:FindFirstChild("Caption", true)).Text)
							.. ":"
							.. tostring(assert(card:FindFirstChild("Artwork", true)).Image)
					)
				end
				return table.concat(rows, "\n")
			end,
			stop = function()
				stop()
			end,
		}
	end,
})

table.insert(workloads, {
	id = "mixed-scroll-300",
	iterations = 100,
	what = "Scroll 300 retained mixed rows: 100 text rows, 100 action buttons and 100 text cards.",
	prepare = function(world: Types.World, lane: Types.Lane): Types.Scene
		local UI = world.UI
		local stop = S.mount(world, lane, function()
			local children: { Instance } = {}
			for i = 1, 300 do
				local name, label = "Row" .. i, `Row {i}`
				if i % 3 == 0 then
					table.insert(children, UI.Card(name) { title = label })
				elseif i % 3 == 1 then
					table.insert(children, UI.Text(name) { text = label })
				else
					table.insert(children, UI.Button(name) { label = label, onActivate = function() end })
				end
			end
			return UI.ScrollView "Mixed" {
				gap = 8,
				Size = world.types.UDim2.fromOffset(640, 480),
				table.unpack(children),
			}
		end, function(screen)
			local root = S.create(world, "ScrollingFrame", "Mixed", screen, {
				Size = world.types.UDim2.fromOffset(640, 480),
				AutomaticCanvasSize = world.types.Enum.AutomaticSize.Y,
			})
			local content = S.stack(world, root, "Content")
			for i = 1, 300 do
				local name, label = "Row" .. i, `Row {i}`
				if i % 3 == 0 then
					local card = S.stack(world, content, name)
					local body = S.stack(world, card, "Body")
					S.create(world, "UIPadding", "Padding", body)
					S.text(world, body, "Title", label)
				elseif i % 3 == 1 then
					S.text(world, content, name, label)
				else
					S.button(world, content, name, label, function() end)
				end
			end
		end)
		return {
			step = function(index: number)
				S.find(world, "Mixed").CanvasPosition = world.types.Vector2.new(0, index * 100)
				world.frame()
			end,
			snapshot = function()
				local rows = {}
				for i = 1, 300 do
					local node = S.find(world, "Row" .. i)
					table.insert(
						rows,
						tostring(if i % 3 == 0 then assert(node:FindFirstChild("Title", true)).Text else node.Text)
					)
				end
				local position: unknown = S.find(world, "Mixed").CanvasPosition
				assert(typeof(position) == "Vector2")
				table.insert(rows, tostring(position.Y))
				return table.concat(rows, "\n")
			end,
			stop = stop,
		}
	end,
})

return workloads
