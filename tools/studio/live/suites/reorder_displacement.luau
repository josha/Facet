--!strict

type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type Tile = { id: string }
type Cells = { set: (Cells, { Tile }) -> (), peek: (Cells) -> { Tile } }
type Live = {
	mount: ((FacetControls, RobloxHost, ComposeModule) -> Instance, { frames: number? }) -> Instance,
	settle: (number) -> (),
	find: (Instance, string) -> Instance?,
	check: (string, boolean, unknown?) -> (),
	note: (string, unknown) -> (),
}
type Probe = { tiles: Cells, rack: Instance, left: { [string]: number } }
type Case = {
	id: string,
	contracts: { string },
	plan: string,
	setup: (Live) -> Probe,
	steps: { [string]: (Live, Probe) -> () },
}

local TILE = 72

local function tileNode(rack: Instance, id: string): GuiObject?
	for _, node in rack:GetDescendants() do
		if node.Name == `Tile{id}` and node:IsA("GuiObject") then
			return node
		end
	end
	return nil
end

local function order(tiles: Cells): string
	local ids: { string } = {}
	for _, tile in tiles:peek() do
		table.insert(ids, tile.id)
	end
	return table.concat(ids, ",")
end

local cases: { Case } = {
	{
		id = "held-tile-opens-its-slot-and-settles-on-drop",
		contracts = {},
		plan = "held: hold A over the C slot; dropped: release",
		setup = function(t: Live): Probe
			local tiles: Cells
			local rack = t.mount(function(UI: FacetControls, Host: RobloxHost, Compose: ComposeModule): Instance
				local initial: { Tile } = {}
				for _, id in { "A", "B", "C", "D", "E", "F", "G" } do
					table.insert(initial, { id = id })
				end
				tiles = Compose.cell(initial)
				return UI.VirtualList "Rack" {
					from = tiles,
					key = "id",
					direction = "horizontal",
					itemSize = TILE,
					mode = "all",
					reorderable = true,
					Size = UDim2.fromOffset(TILE * 7, TILE),
					Position = UDim2.fromOffset(200, 200),
					onReorder = function(keys: { string }, slot: number)
						local carried: { Tile }, remaining: { Tile } = {}, {}
						for _, tile in tiles:peek() do
							table.insert(if table.find(keys, tile.id) then carried else remaining, tile)
						end
						for index, tile in carried do
							table.insert(remaining, slot + index, tile)
						end
						tiles:set(remaining)
					end,
					render = function(current): GuiObject
						return UI.Button {
							Name = function(use): string
								return `Tile{use(current).id}`
							end,
							label = function(use): string
								return use(current).id
							end,
							Size = UDim2.fromScale(1, 1),
						}
					end,
				}
			end, { frames = 20 })
			t.settle(10)
			local left: { [string]: number } = {}
			for _, id in { "A", "B", "C", "D" } do
				local node = tileNode(rack, id)
				left[id] = if node then node.AbsolutePosition.X else -1
			end
			local a = assert(tileNode(rack, "A"), "tile A is on screen")
			local c = assert(tileNode(rack, "C"), "tile C is on screen")
			local y = a.AbsolutePosition.Y + a.AbsoluteSize.Y / 2
			t.note("points", {
				from = { math.floor(a.AbsolutePosition.X + a.AbsoluteSize.X / 2), math.floor(y) },
				to = { math.floor(c.AbsolutePosition.X + c.AbsoluteSize.X * 0.6), math.floor(y) },
			})
			t.note("before", left)
			return { tiles = tiles, rack = rack, left = left }
		end,
		steps = {
			held = function(t: Live, probe: Probe)
				t.settle(30)
				local b, c, d = tileNode(probe.rack, "B"), tileNode(probe.rack, "C"), tileNode(probe.rack, "D")
				local shiftB = if b then probe.left.B - b.AbsolutePosition.X else 0
				local shiftC = if c then probe.left.C - c.AbsolutePosition.X else 0
				local shiftD = if d then probe.left.D - d.AbsolutePosition.X else 0
				t.note("held", { b = shiftB, c = shiftC, d = shiftD, order = order(probe.tiles) })
				t.check("the source order does not change while held", order(probe.tiles) == "A,B,C,D,E,F,G")
				t.check(
					"B and C slide one slot toward the origin to open the slot under the held tile",
					math.abs(shiftB - TILE) <= 2 and math.abs(shiftC - TILE) <= 2,
					{ b = shiftB, c = shiftC }
				)
				t.check("D past the slot stays put", math.abs(shiftD) <= 2, shiftD)
			end,
			dropped = function(t: Live, probe: Probe)
				t.settle(30)
				t.check("the drop commits A after C", order(probe.tiles) == "B,C,A,D,E,F,G", order(probe.tiles))
				local a, d = tileNode(probe.rack, "A"), tileNode(probe.rack, "D")
				t.check(
					"A settles into the third slot",
					a ~= nil and math.abs(a.AbsolutePosition.X - probe.left.C) <= 2,
					a and a.AbsolutePosition.X
				)
				t.check("D did not move", d ~= nil and math.abs(d.AbsolutePosition.X - probe.left.D) <= 2)
			end,
		},
	},
}

return cases
