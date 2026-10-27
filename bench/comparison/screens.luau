--!strict

local Facet = require("../../src")
local Types = require("./types")
local S = require("./support")
type FrameProps = typeof(require("@repo/tools/typecheck/aliases").FrameNativeProps)
type FolderProps = typeof(require("@repo/tools/typecheck/aliases").FolderNativeProps)

type Player = { id: number, name: string, score: number, wins: number }
type Sort = { column: string, direction: "ascending" | "descending" }
type Controls = {
	indexOfKey: ((number) -> number?)?,
	offsetOf: ((number, ("center" | "end" | "start")?, number?) -> number)?,
	placementOf: ((number) -> Facet.CollectionPlacement)?,
}

local workloads: { Types.Workload } = {}

table.insert(workloads, {
	id = "leaderboard-100",
	iterations = 6,
	what = "Sort 100 retained player rows by name, score and wins; replace every score after each sort.",
	prepare = function(world: Types.World, lane: Types.Lane): Types.Scene
		local UI, Compose = world.UI, world.Compose
		local initial: { Player } = {}
		for i = 1, 100 do
			table.insert(
				initial,
				{ id = i, name = string.format("Player %03d", i), score = i * 7 % 101, wins = i * 3 % 97 }
			)
		end
		local source = S.model(world, lane, initial)
		local initialSort: Sort? = { column = "name", direction = "ascending" }
		local sort = S.model(world, lane, initialSort)
		local controls: Controls = {}
		local bareRows: { [number]: S.Node } = {}
		local bareScores: { [number]: S.Node } = {}
		local rows = initial
		local currentSort: Sort = { column = "name", direction = "ascending" }
		local function order()
			local ordered = table.clone(rows)
			local column = currentSort.column
			if column == "name" then
				table.sort(ordered, function(a: Player, b: Player)
					return a.name < b.name
				end)
			elseif column == "score" then
				table.sort(ordered, function(a: Player, b: Player)
					return a.score < b.score
				end)
			else
				table.sort(ordered, function(a: Player, b: Player)
					return a.wins < b.wins or (a.wins == b.wins and a.id < b.id)
				end)
			end
			for index, row in ordered do
				bareRows[row.id].LayoutOrder = index
			end
		end
		local columns: { Facet.TableColumn<Player, number> } = {
			{
				id = "name",
				label = "Player",
				value = function(row)
					return row.name
				end,
				width = 200,
				render = function(current)
					return UI.Text("Name" .. current:peek().id) {
						text = function(use: Facet.Use)
							return use(current).name
						end,
					}
				end,
			},
			{
				id = "score",
				label = "Score",
				value = function(row)
					return row.score
				end,
				width = 100,
				render = function(current)
					return UI.Text("Score" .. current:peek().id) {
						text = function(use: Facet.Use)
							return tostring(use(current).score)
						end,
					}
				end,
			},
			{
				id = "wins",
				label = "Wins",
				value = function(row)
					return row.wins
				end,
				width = 100,
				render = function(current)
					return UI.Text("Wins" .. current:peek().id) {
						text = function(use: Facet.Use)
							return tostring(use(current).wins)
						end,
					}
				end,
			},
		}
		local stop = S.mount(world, lane, function()
			local spec: Facet.KeyedTableSpec<Player, number> = {
				from = assert(source),
				key = function(row)
					return row.id
				end,
				columns = columns,
				sort = assert(sort),
				mode = "all",
				controls = controls,
				Size = world.types.UDim2.fromOffset(640, 480),
			}
			return UI.Table "Leaderboard"(spec)
		end, function(screen)
			local root = S.stack(world, screen, "Leaderboard")
			local header = S.stack(world, root, "Header", true)
			for _, column in columns do
				local label = column.label
				assert(type(label) == "string")
				S.button(world, header, column.id, label, function()
					currentSort = { column = column.id, direction = "ascending" }
					order()
				end)
			end
			local scroll = S.create(world, "ScrollingFrame", "Body", root, {
				Size = world.types.UDim2.fromOffset(640, 400),
				AutomaticCanvasSize = world.types.Enum.AutomaticSize.Y,
			})
			local items = S.stack(world, scroll, "Items")
			for _, row in rows do
				local node = S.stack(world, items, "Player" .. row.id, true)
				bareRows[row.id] = node
				S.text(world, node, "Name" .. row.id, row.name, true)
				bareScores[row.id] = S.text(world, node, "Score" .. row.id, tostring(row.score), true)
				S.text(world, node, "Wins" .. row.id, tostring(row.wins), true)
			end
			order()
		end)
		return {
			step = function(index: number)
				if index % 2 == 1 then
					currentSort = { column = columns[math.ceil(index / 2)].id, direction = "ascending" }
					if lane == "facet" then
						assert(sort):set(currentSort)
					else
						order()
					end
				else
					local updated: { Player } = {}
					for _, row in rows do
						table.insert(
							updated,
							{ id = row.id, name = row.name, score = (row.score + index) % 101, wins = row.wins }
						)
					end
					rows = updated
					if lane == "facet" then
						assert(source):set(updated)
					else
						for _, row in rows do
							S.setText(world, bareScores[row.id], tostring(row.score))
						end
						order()
					end
				end
				world.frame()
			end,
			snapshot = function()
				local result: { string } = {}
				for id = 1, 100 do
					local position = if lane == "facet"
						then assert(controls.indexOfKey)(id)
						else bareRows[id].LayoutOrder
					table.insert(result, tostring(id) .. ":" .. tostring(position))
				end
				local names: { string } = {}
				for id = 1, 100 do
					table.insert(names, "Name" .. id)
					table.insert(names, "Score" .. id)
					table.insert(names, "Wins" .. id)
				end
				return table.concat(result, ",") .. "\n" .. S.snapshot(world, names)
			end,
			stop = stop,
		}
	end,
})

table.insert(workloads, {
	id = "theme-swap-200",
	iterations = 10,
	what = "Swap two neutral packages on 200 themed buttons; Facet updates its StyleSheet tokens while bare relinks one of two prebuilt theme StyleSheets.",
	prepare = function(world: Types.World, lane: Types.Lane): Types.Scene
		local Compose, Host = world.Compose, world.Host
		local first, second = Facet.themes.neutralPackage(), Facet.themes.neutralPackage()
		second.style.themes[1].colors.content = { r = 0.8, g = 0.9, b = 1 }
		local function freeze(value: unknown)
			if type(value) == "table" and not table.isfrozen(value) then
				for key, child in value :: { [unknown]: unknown } do
					freeze(key)
					freeze(child)
				end
				table.freeze(value)
			end
		end
		freeze(first)
		freeze(second)
		local theme = S.model(world, lane, first)
		local UI = if lane == "facet"
			then Facet.controls(world.runtime, { types = world.types, theme = assert(theme) })
			else world.UI
		local sheet: StyleSheet? = nil
		local link: S.Node? = nil
		local sheets: { Instance } = {}
		local stop = S.mount(world, lane, function()
			local children: { Instance } = {}
			for i = 1, 200 do
				table.insert(children, UI.Button("Themed" .. i) { label = `Action {i}`, onActivate = function() end })
			end
			sheet = Facet.themes.createStyleSheet(world.runtime, assert(theme), { types = world.types })
			local content: { Facet.Child } = {
				sheet,
				Host.StyleLink { StyleSheet = Compose.static(sheet) },
				UI.Grid "Controls" { columns = 10, gap = 8, table.unpack(children) },
			}
			local props: FrameProps = { Name = "ThemedScreen", table.unpack(content) }
			return Host.Frame(props)
		end, function(screen)
			for _, package in { first, second } do
				world.runtime.mount(function()
					local made = Facet.themes.createStyleSheet(world.runtime, package, { types = world.types })
					table.insert(sheets, made)
					return made
				end, screen)
			end
			local made: S.Node = world.engine.new("StyleLink")
			made.StyleSheet = sheets[1]
			made.Parent = screen
			link = made
			local root = S.grid(world, screen, "Controls", 10)
			for i = 1, 200 do
				S.button(world, root, "Themed" .. i, `Action {i}`, function() end)
			end
		end, true)
		return {
			step = function(index: number)
				local package = if index % 2 == 1 then second else first
				if lane == "facet" then
					assert(theme):set(package)
				else
					assert(link).StyleSheet = if package == first then sheets[1] else sheets[2]
				end
			end,
			snapshot = function()
				local color: unknown = if lane == "facet"
					then assert(sheet):GetAttribute("FacetColor_content")
					else (assert(link).StyleSheet :: Instance):GetAttribute("FacetColor_content")
				return tostring(color)
			end,
			stop = stop,
		}
	end,
})

table.insert(workloads, {
	id = "heavy-screen-20-cycles",
	iterations = 20,
	what = "Mount and dispose 200 action controls and 200 text rows, 20 complete lifetimes.",
	prepare = function(world: Types.World, lane: Types.Lane): Types.Scene
		local UI = world.UI
		local completed = 0
		return {
			step = function()
				local stop = S.mount(world, lane, function()
					local children: { Instance } = {}
					for i = 1, 200 do
						table.insert(
							children,
							UI.Button("Action" .. i) { label = `Action {i}`, onActivate = function() end }
						)
						table.insert(children, UI.Text("Detail" .. i) { text = `Detail {i}` })
					end
					return UI.ScrollView "Heavy" {
						gap = 8,
						Size = world.types.UDim2.fromOffset(640, 480),
						table.unpack(children),
					}
				end, function(screen)
					local root = S.create(world, "ScrollingFrame", "Heavy", screen, {
						Size = world.types.UDim2.fromOffset(640, 480),
						AutomaticCanvasSize = world.types.Enum.AutomaticSize.Y,
					})
					local content = S.stack(world, root, "Content")
					for i = 1, 200 do
						S.button(world, content, "Action" .. i, `Action {i}`, function() end)
						S.text(world, content, "Detail" .. i, `Detail {i}`)
					end
				end)
				assert(#S.find(world, "Heavy"):GetDescendants() >= 400)
				stop()
				completed += 1
			end,
			snapshot = function()
				return tostring(completed) .. ":" .. tostring(#world.target:GetChildren())
			end,
			stop = function() end,
		}
	end,
})

table.insert(workloads, {
	id = "tile-transfer-20",
	iterations = 20,
	what = "Pick up 20 tiles with gamepad activation and drop each into the second grid; Facet also installs pointer drag and cancellation policy.",
	prepare = function(world: Types.World, lane: Types.Lane): Types.Scene
		local UI, Compose, Host = world.UI, world.Compose, world.Host
		local ids: { number } = {}
		for i = 1, 20 do
			table.insert(ids, i)
		end
		local targets: { [number]: Facet.Value<Instance> } = {}
		local destinations: { [number]: string } = {}
		local bareTiles: { [number]: S.Node } = {}
		local gridB: S.Node? = nil
		local held: number? = nil
		local stop = S.mount(world, lane, function()
			local source = UI.Grid "GridA" { columns = 5, gap = 8 }
			local target = UI.Grid "GridB" { columns = 5, gap = 8 }
			local drop = UI.Button "Drop" { label = "Move here" }
			UI.dropTarget(drop, {
				onDrop = function(payload)
					assert(type(payload) == "number")
					targets[payload]:set(target)
					destinations[payload] = "GridB"
				end,
			})
			local content: { Facet.Child } = {
				source,
				target,
				drop,
				Compose.keyed {
					from = function()
						return ids
					end,
					key = function(id: number)
						return id
					end,
					render = function(current: Facet.ReadOnlyValue<number>)
						local id = current:peek()
						local parent: Instance = source
						targets[id] = Compose.cell(parent)
						destinations[id] = "GridA"
						local props: FolderProps = {
							Name = "TileOwner" .. id,
							Compose.portal(source, function(): { unknown }
								local tile = UI.Button("Tile" .. id) { label = `Tile {id}` }
								UI.draggable(tile, { payload = id })
								Compose.watch(function(use: Facet.Use)
									tile.Parent = use(targets[id])
								end)
								return { tile }
							end),
						}
						return Host.Folder(props)
					end,
				},
			}
			local props: FrameProps = { Name = "Transfer", table.unpack(content) }
			return Host.Frame(props)
		end, function(screen)
			local source = S.grid(world, screen, "GridA", 5)
			gridB = S.grid(world, screen, "GridB", 5)
			for i = 1, 20 do
				bareTiles[i] = S.button(world, source, "Tile" .. i, `Tile {i}`, function()
					held = i
				end)
				S.create(world, "UIDragDetector", "Drag", bareTiles[i])
				destinations[i] = "GridA"
			end
			S.button(world, screen, "Drop", "Move here", function()
				local id = assert(held)
				bareTiles[id].Parent = gridB
				destinations[id] = "GridB"
				held = nil
			end)
		end)
		local pad =
			{ UserInputType = world.types.Enum.UserInputType.Gamepad1, KeyCode = world.types.Enum.KeyCode.ButtonA }
		return {
			step = function(index: number)
				S.fire(world, "Tile" .. index, "Activated", pad)
				S.fire(world, "Drop", "Activated", pad)
				world.frame()
			end,
			snapshot = function()
				local rows: { string } = {}
				for i = 1, 20 do
					local tile = S.find(world, "Tile" .. i)
					table.insert(rows, tostring(tile.Text) .. ":" .. tostring(assert(tile.Parent).Name))
				end
				return table.concat(rows, "\n")
			end,
			stop = stop,
		}
	end,
})

return workloads
