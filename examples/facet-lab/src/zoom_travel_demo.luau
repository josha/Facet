--!strict
type Controls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type Host = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type StackProps = typeof(require("@repo/tools/typecheck/aliases").StackProps)
type FrameProps = typeof(require("@repo/tools/typecheck/aliases").FrameProps)
type ZoomControls = { fit: (() -> boolean)?, zoomTo: (({ x: number, y: number, w: number, h: number }) -> boolean)? }

local demo = {}

function demo.zoom(UI: Controls, Host: Host, Compose: ComposeModule, maxZoom: number, enabled: boolean): Frame
	local zoom = Compose.cell(0.5)
	local controls: ZoomControls = {}
	local tile: TextButton? = nil
	local children: { unknown } = {}
	for index = 1, 169 do
		local row, col = math.floor((index - 1) / 13), (index - 1) % 13
		table.insert(
			children,
			UI.Text {
				Name = `Cell{index}`,
				text = `{row + 1},{col + 1}`,
				Size = UDim2.fromOffset(60, 60),
				Position = UDim2.fromOffset(col * 60, row * 60),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				BackgroundTransparency = 0,
				BackgroundColor3 = Color3.fromRGB(40 + row * 3, 65 + col * 3, 90),
			}
		)
	end
	local stack = (
		{
			width = "fill",
			gap = "s",
			UI.HStack {
				gap = "s",
				UI.Button {
					label = "Fit",
					onActivate = function()
						assert(controls.fit)()
					end,
				},
				UI.Button {
					label = "Zoom to cell 7,7",
					onActivate = function()
						assert(controls.zoomTo)({ x = 360, y = 360, w = 180, h = 180 })
					end,
				},
			} :: unknown,
			UI.Text {
				text = "Pinch or double tap. Ctrl-wheel zooms. Select the view: triggers zoom, right stick pans, Y fits. Drag A: the board stays still.",
				wrap = true,
			} :: unknown,
			UI.ZoomView {
				Name = "BoardZoom",
				contentSize = Vector2.new(780, 780),
				zoom = zoom,
				maxZoom = maxZoom,
				enabled = enabled,
				controls = controls,
				Size = UDim2.new(1, 0, 0, 360),
				content = function(): GuiObject
					local props: FrameProps =
						{ Name = "Board", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }
					for _, child in children do
						props[#props + 1] = child
					end
					tile = UI.Button {
						Name = "TileA",
						label = "A",
						Size = UDim2.fromOffset(60, 60),
						Position = UDim2.fromOffset(360, 360),
						ZIndex = 2,
					}
					UI.draggable(tile :: TextButton, { payload = "A", touchPickup = "immediate", statusLabels = false })
					props[#props + 1] = tile
					return Host.Frame(props)
				end,
			} :: unknown,
		} :: unknown
	) :: StackProps
	return UI.VStack(stack)
end

function demo.travel(UI: Controls, Host: Host, Compose: ComposeModule, path: "straight" | "arc"): Frame
	local first = Host.Frame {
		Name = "SourceRow",
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundTransparency = 0.7,
		ClipsDescendants = true,
	}
	local second = Host.Frame {
		Name = "DestinationRow",
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundTransparency = 0.7,
		ClipsDescendants = true,
	}
	local start = Host.Frame {
		Name = "SourceSlot",
		Size = UDim2.fromOffset(60, 60),
		BackgroundTransparency = 1,
		Parent = Compose.static(first),
	}
	local finish = Host.Frame {
		Name = "DestinationSlot",
		Size = UDim2.fromOffset(60, 60),
		Position = UDim2.new(1, -60, 0, 0),
		BackgroundTransparency = 1,
		Parent = Compose.static(second),
	}
	local destination = Compose.cell(start :: GuiObject)
	local stack = (
		{
			width = "fill",
			gap = "l",
			UI.HStack {
				gap = "s",
				UI.Button {
					label = "Send",
					onActivate = function()
						destination:set(finish)
					end,
				},
				UI.Button {
					label = "Return",
					onActivate = function()
						destination:set(start)
					end,
				},
			} :: unknown,
			first :: unknown,
			UI.Text {
				text = "Send the tile between clipped rows. Press Return during travel to change its destination.",
				wrap = true,
			} :: unknown,
			second :: unknown,
			UI.Travel {
				Name = "RowTravel",
				destination = destination,
				path = path,
				content = function(): GuiObject
					return UI.Button {
						Name = "TravellingTile",
						label = "A",
						Size = UDim2.fromScale(1, 1),
						AutomaticSize = Enum.AutomaticSize.None,
					}
				end,
			} :: unknown,
		} :: unknown
	) :: StackProps
	return UI.VStack(stack)
end

function demo.many(UI: Controls, Host: Host, Compose: ComposeModule): Frame
	local board = Host.Frame { Name = "ManyItems", Size = UDim2.fromOffset(320, 320), BackgroundTransparency = 1 }
	local destinations: { typeof(require("@repo/tools/typecheck/aliases").ZoomDestinationCell) } = {}
	local slots: { Frame } = {}
	for index = 1, 64 do
		local slot = Host.Frame {
			Name = `Slot{index}`,
			Size = UDim2.fromOffset(36, 36),
			Position = UDim2.fromOffset((index - 1) % 8 * 40, math.floor((index - 1) / 8) * 40),
			BackgroundTransparency = 1,
			Parent = Compose.static(board),
		}
		slots[index] = slot
	end
	for index = 1, 64 do
		destinations[index] = Compose.cell(slots[index] :: GuiObject)
		local anchor = UI.Travel {
			motion = "spring" :: "spring",
			destination = destinations[index],
			content = function(): GuiObject
				return UI.Text {
					text = tostring(index),
					TextXAlignment = Enum.TextXAlignment.Center,
					TextYAlignment = Enum.TextYAlignment.Center,
					BackgroundTransparency = 0,
				}
			end,
		}
		anchor.Parent = board
	end
	local flipped = false
	return UI.VStack(({
		gap = "s",
		UI.Button {
			label = "Move 64 items",
			onActivate = function()
				flipped = not flipped
				for index, cell in destinations do
					cell:set(slots[if flipped then 65 - index else index])
				end
			end,
		} :: unknown,
		board :: unknown,
	} :: unknown) :: StackProps)
end

return demo
