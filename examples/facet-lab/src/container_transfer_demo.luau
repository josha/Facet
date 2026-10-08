--!strict
type DropInfo = typeof(require("@repo/tools/typecheck/aliases").DropInfo)
type CommandScope = typeof(require("@repo/tools/typecheck/aliases").CommandScope)
type Command = typeof(require("@repo/tools/typecheck/aliases").Command)
type SlotControls = typeof(require("@repo/tools/typecheck/aliases").SlotControls)
type DraggableSpec = typeof(require("@repo/tools/typecheck/aliases").DraggableSpec)
type UI = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type Host = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type Compose = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type Types = typeof(require("@repo/tools/typecheck/aliases").RobloxTypes)
type Tile = { id: string, letter: string }
type Flight = { id: string, tile: Tile, destination: FacetCell<GuiObject> }
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
	reserveSlots: boolean?,
	commandTyping: boolean?,
	typingEnabled: boolean?,
	duplicateLetters: boolean?,
}

return function(UI: UI, Host: Host, C: Compose, types: Types, options: Options): GuiObject
	local D2, E = types.UDim2, types.Enum
	local initial: { Tile } = {}
	for index, letter in { "A", "M", "I", "G", "O", "S", "E" } do
		table.insert(
			initial,
			{ id = tostring(index), letter = if options.duplicateLetters and index == 7 then "A" else letter }
		)
	end
	local model = C.cell({ rack = initial, board = {} } :: Model)
	local slotKeys = C.cell({ "1", "2", "3", "4", "5", "6", "7" })
	local notice = C.cell("Drag a letter to the board. Select a letter and press A or Return to carry it.")
	local held: FacetCell<string?> = C.cell(nil :: string?)
	local flights = C.cell({} :: { Flight })
	local slotControls: SlotControls = {}
	local boardNodes: { [number]: GuiObject } = {}
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
				local returning = false
				for _, flight in use(flights) do
					returning = returning or (tile ~= nil and flight.id == tile.id)
				end
				return if tile and use(held) ~= tile.id and not returning then tile.letter else tostring(slot)
			end,
			selected = aim,
			Size = D2.fromScale(1, 1),
			AutomaticSize = E.AutomaticSize.None,
			controlSize = "compact" :: "compact",
			onActivate = function()
				notice:set("Pressed board " .. slot)
			end,
		}
		boardNodes[slot] = button
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
		slots = if options.reserveSlots then slotKeys else nil,
		slotControls = if options.reserveSlots then slotControls else nil,
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
				touchPickup = options.touchPickup,
				touchDragAxis = options.touchDragAxis,
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
					if options.reserveSlots then
						local available: { [string]: boolean } = {}
						local current = model:peek().rack
						for _, item in current do
							available[item.id] = true
						end
						local nextSlots, index = {}, 1
						for _, key in slotKeys:peek() do
							if available[key] then
								table.insert(nextSlots, current[index].id)
								index += 1
							else
								table.insert(nextSlots, key)
							end
						end
						slotKeys:set(nextSlots)
					end
					break
				end
			end
		end,
		drop = {
			label = "Rack",
			travel = true,
			landing = if options.reserveSlots
				then nil
				else function(info: DropInfo)
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
	local board = UI.Grid(gridProps)
	local scope: CommandScope?
	if options.commandTyping then
		local targets: { { key: number, node: GuiObject } } = {}
		for slot = 1, 25 do
			table.insert(targets, { key = slot, node = boardNodes[slot] })
		end
		local commands: { Command } = {}
		for byte = string.byte("A"), string.byte("Z") do
			local letter = string.char(byte)
			table.insert(commands, {
				id = "Place" .. letter,
				keys = if letter == "A" then { letter, "ButtonX" } else { letter },
				onInvoke = function(slot: number)
					for _, tile in model:peek().rack do
						if tile.letter == letter then
							if
								transfer({ collection = "rack", items = { tile }, keys = { tile.id } }, slot, nil)
								and scope
							then
								scope.focus(math.min(25, slot + 1))
							end
							break
						end
					end
				end,
			})
		end
		table.insert(commands, {
			id = "RecallFocused",
			keys = { "Backspace", "ButtonY" },
			onInvoke = function(slot: number)
				local tile = model:peek().board[slot]
				if tile then
					transfer({ collection = "board", items = { tile }, keys = { tile.id } }, nil, nil)
				end
			end,
		})
		scope =
			UI.commandScope(board, { targets = targets, commands = commands, enabled = options.typingEnabled ~= false })
	end
	local chat: GuiObject = if options.commandTyping
		then UI.TextInput {
			value = C.cell(""),
			placeholder = "Chat takes letters and Backspace while it edits",
			Size = D2.fromOffset(396, 44),
		}
		else UI.Text { text = "", Visible = false }
	local content = UI.VStack "ContainerTransfer" {
		gap = "s",
		UI.Text { text = notice, wrap = true, Size = D2.fromOffset(396, 0) },
		chat,

		UI.HStack {
			UI.Button {
				label = "Recall",
				onActivate = function()
					local board = table.clone(model:peek().board)
					local nextFlights: { Flight } = {}
					for slot, tile in board do
						local target = if slotControls.nodeOfKey then slotControls.nodeOfKey(tile.id) else nil
						if target then
							table.insert(
								nextFlights,
								{ id = tile.id, tile = tile, destination = C.cell(boardNodes[slot]) }
							)
						else
							transfer({ collection = "board", items = { tile }, keys = { tile.id } }, nil, nil)
						end
					end
					flights:set(nextFlights)
				end,
			},
			UI.Button {
				label = "Release slots",
				onActivate = function()
					local keys: { string } = {}
					for _, tile in model:peek().rack do
						table.insert(keys, tile.id)
					end
					slotKeys:set(keys)
				end,
			},
		},
		Host.Frame {
			Size = D2.fromOffset(0, 0),
			BackgroundTransparency = 1,
			C.keyed {
				from = flights,
				key = function(flight: Flight): string
					return flight.id
				end,
				render = function(current: FacetReadable<Flight>): GuiObject
					local flight = current:peek()
					local travel = UI.Travel {
						destination = flight.destination,
						content = function(): GuiObject
							return UI.Button { label = flight.tile.letter }
						end,
						onLanded = function(destination: GuiObject)
							local target = assert(slotControls.nodeOfKey)(flight.id) :: GuiObject
							if destination ~= target then
								flight.destination:set(target)
								return
							end
							transfer({ collection = "board", items = { flight.tile }, keys = { flight.id } }, nil, nil)
							flights:update(function(values)
								local next: { Flight } = {}
								for _, value in values do
									if value.id ~= flight.id then
										table.insert(next, value)
									end
								end
								return next
							end)
						end,
					}
					return travel
				end,
			},
		},
		Host.Frame {
			Size = D2.fromOffset(396, 400),
			BackgroundTransparency = 1,
			Host.UIScale { Scale = options.scale or 1 } :: unknown,
			UI.VStack {
				gap = "s",
				board :: unknown,
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
