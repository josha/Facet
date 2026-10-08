--!strict
type DropInfo = typeof(require("@repo/tools/typecheck/aliases").DropInfo)
type DraggableSpec = typeof(require("@repo/tools/typecheck/aliases").DraggableSpec)
type UI = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type Host = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type Compose = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type Types = typeof(require("@repo/tools/typecheck/aliases").RobloxTypes)
type Tile = { id: string, letter: string }
type Model = { rack: { Tile }, board: { [number]: Tile } }
type Payload = { collection: string, keys: { string }, items: { Tile } }
type Use = <T>(FacetReadable<T>) -> T
type FacetReadable<T> = { peek: (FacetReadable<T>) -> T }
type FacetCell<T> = FacetReadable<T> & { set: (FacetCell<T>, T) -> (), update: (FacetCell<T>, (T) -> T) -> () }
type Options = {
	reject: boolean?,
	scale: number?,
	scrolled: boolean?,
	touchPickup: ("immediate" | "longPress")?,
	touchDragAxis: ("X" | "Y" | "XY")?,
	statusLabels: boolean?,
}

return function(UI: UI, Host: Host, C: Compose, types: Types, options: Options): GuiObject
	local D2, E = types.UDim2, types.Enum
	local initial: { Tile } = {}
	for index, letter in { "A", "M", "I", "G", "O", "S", "E" } do
		table.insert(initial, { id = tostring(index), letter = letter })
	end
	local model = C.cell({ rack = initial, board = {} } :: Model)
	local notice = C.cell("Drag a letter to the board. Select a letter and press A or Return to carry it.")
	local held: FacetCell<string?> = C.cell(nil :: string?)
	local rackNode: ScrollingFrame?
	local function payload(value: unknown): Payload?
		if type(value) ~= "table" then
			return nil
		end
		local record = value :: { collection: unknown, keys: unknown, items: unknown }
		if type(record.collection) ~= "string" or type(record.keys) ~= "table" or type(record.items) ~= "table" then
			return nil
		end
		return value :: Payload
	end
	local function transfer(value: unknown, boardSlot: number?, rackSlot: number?): boolean
		local data = payload(value)
		if not data or not data.items[1] then
			return false
		end
		local tile = data.items[1]
		local before = model:peek()
		if boardSlot and before.board[boardSlot] and before.board[boardSlot].id ~= tile.id then
			return false
		end
		local next: Model = { rack = {}, board = table.clone(before.board) }
		for _, item in before.rack do
			if item.id ~= tile.id then
				table.insert(next.rack, item)
			end
		end
		for index, item in next.board do
			if item.id == tile.id then
				next.board[index] = nil
			end
		end
		if boardSlot then
			next.board[boardSlot] = tile
		else
			table.insert(next.rack, math.clamp((rackSlot or #next.rack) + 1, 1, #next.rack + 1), tile)
		end
		model:set(next)
		notice:set(if boardSlot then "Placed on board " .. boardSlot else "Placed in rack")
		return true
	end
	local function picked(value: unknown)
		local data = payload(value)
		if data and data.items[1] then
			held:set(data.items[1].id)
		end
	end
	local function ended(accepted: boolean, reason: string?)
		held:set(nil)
		if not accepted then
			notice:set(reason or "Returned to source")
		end
	end
	local cells: { unknown } = {}
	for slot = 1, 25 do
		local aim = C.cell(false)
		local button = UI.Button("BoardSlot" .. slot) {
			label = function(use: Use)
				local tile = use(model).board[slot]
				return if tile and use(held) ~= tile.id then tile.letter else tostring(slot)
			end,
			selected = aim,
			Size = D2.fromScale(1, 1),
			AutomaticSize = E.AutomaticSize.None,
			controlSize = "compact" :: "compact",
			onActivate = function()
				notice:set("Pressed board " .. slot)
			end,
		}
		UI.draggable(button, {
			payload = function()
				local tile = model:peek().board[slot]
				return if tile then { collection = "board", keys = { tile.id }, items = { tile } } else nil
			end,
			hitArea = button,
			returnTravel = true,
			touchPickup = options.touchPickup or "immediate",
			touchDragAxis = options.touchDragAxis,
			statusLabels = options.statusLabels,
			enabled = function(use: Use)
				return use(model).board[slot] ~= nil
			end,
			onStart = function(value: unknown, _mode: "pointer" | "armed")
				picked(value)
			end,
			onEnd = ended,
		})
		UI.dropTarget(button, {
			label = "Board " .. slot,
			travel = true,
			accepts = function(value)
				local data = payload(value)
				local tile = model:peek().board[slot]
				return data ~= nil and not options.reject and (tile == nil or tile.id == data.items[1].id),
					"Occupied or locked"
			end,
			onEnter = function()
				aim:set(true)
			end,
			onLeave = function()
				aim:set(false)
			end,
			onDrop = function(value)
				return transfer(value, slot, nil)
			end,
		})
		table.insert(cells, button)
	end
	local rack = UI.VirtualGrid "TransferRack" {
		from = C.formula(function(use: Use): { Tile }
			return use(model).rack
		end),
		key = "id",
		collectionId = "rack",
		columns = 7,
		itemSize = 52,
		gap = 4,
		mode = "all" :: "all",
		contentOverflow = "clip" :: "clip",
		Size = D2.fromOffset(396, 72),
		drag = function(items: { Tile }, keys: { string }): DraggableSpec
			return {
				payload = { collection = "rack", items = items, keys = keys },
				returnTravel = true,
				statusLabels = options.statusLabels,
				onStart = function(value: unknown, _mode: "pointer" | "armed")
					picked(value)
				end,
				onEnd = ended,
			}
		end,
		reorderable = true,
		onReorder = function(keys, slot)
			for _, tile in model:peek().rack do
				if tile.id == keys[1] then
					transfer({ collection = "rack", items = { tile }, keys = keys }, nil, slot)
					break
				end
			end
		end,
		drop = {
			label = "Rack",
			travel = true,
			landing = function(info: DropInfo)
				local node = assert(rackNode)
				local slot = if info.insertion then info.insertion.slot else #model:peek().rack
				local width = node.AbsoluteWindowSize.X / 7
				return {
					x = node.AbsolutePosition.X + width * slot,
					y = node.AbsolutePosition.Y,
					w = width - 4,
					h = 52 * (options.scale or 1),
				}
			end,
			accepts = function(value)
				return payload(value) ~= nil and not options.reject, "Rack locked"
			end,
			onDrop = function(value: unknown, info: DropInfo)
				return transfer(value, nil, if info.insertion then info.insertion.slot else nil)
			end,
		},
		render = function(current: FacetReadable<Tile>): GuiObject
			return UI.Button {
				label = function(use: Use)
					return use(current).letter
				end,
				Size = D2.fromScale(1, 1),
				AutomaticSize = E.AutomaticSize.None,
				controlSize = "compact" :: "compact",
				onActivate = function()
					notice:set("Pressed rack " .. current:peek().letter)
				end,
			}
		end,
	}
	rackNode = rack
	local gridProps = { Name = "TransferBoard", columns = 5, gap = 4, cellHeight = 52, Size = D2.fromOffset(276, 276) }
	for index, cell in cells do
		(gridProps :: { [unknown]: unknown })[index] = cell
	end
	local content = UI.VStack "ContainerTransfer" {
		gap = "s",
		UI.Text { text = notice, wrap = true, Size = D2.fromOffset(396, 0) },
		Host.Frame {
			Size = D2.fromOffset(396, 400),
			BackgroundTransparency = 1,
			Host.UIScale { Scale = options.scale or 1 } :: unknown,
			UI.VStack {
				gap = "s",
				UI.Grid(gridProps) :: unknown,
				UI.Text {
					text = "Seven-slot rack · A/Return: carry or place · B/Escape: cancel · Y: destination",
					wrap = true,
					Size = D2.fromOffset(396, 0),
				},
				rack :: unknown,
			} :: unknown,
		},
	}
	if options.scrolled then
		return UI.ScrollView "TransferScroll" {
			Size = D2.fromOffset(420, 320),
			CanvasSize = D2.fromOffset(420, 520),
			AutomaticCanvasSize = E.AutomaticSize.None,
			content :: unknown,
		}
	end
	return content
end
