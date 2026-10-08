--!strict
type Controls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type Host = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type StackProps = typeof(require("@repo/tools/typecheck/aliases").StackProps)
type DraggableSpec = typeof(require("@repo/tools/typecheck/aliases").DraggableSpec)

return function(UI: Controls, Host: Host, C: ComposeModule): Frame
	local camera: {
		zoomTo: (({ x: number, y: number, w: number, h: number }) -> boolean)?,
		zoomAt: ((number, Vector2?) -> boolean)?,
		fit: (() -> boolean)?,
	} =
		{}
	local view = UI.ZoomView {
		Name = "CollectionBoardZoom",
		Size = UDim2.new(1, 0, 0, 300),
		contentSize = Vector2.new(780, 780),
		controls = camera,
		content = function(): GuiObject
			local board = Host.Frame { BackgroundColor3 = Color3.fromRGB(45, 70, 90) }
			for index = 1, 25 do
				local cell = UI.Button {
					label = tostring(index),
					Position = UDim2.fromOffset((index - 1) % 5 * 156, math.floor((index - 1) / 5) * 156),
					Size = UDim2.fromOffset(150, 150),
				}
				UI.dropTarget(cell, {
					onDrop = function(): boolean
						return true
					end,
				})
				cell.Parent = board
			end
			return board
		end,
	}
	local rack = UI.VirtualGrid {
		Name = "CollectionPickupRack",
		from = { 1, 2, 3, 4, 5, 6, 7 },
		key = function(id: number): number
			return id
		end,
		columns = 7,
		itemSize = 52,
		mode = "all" :: "all",
		Size = UDim2.new(1, 0, 0, 64),
		drag = function(_items: { number }, _keys: { number }): DraggableSpec
			return {
				payload = "rack tile",
				touchPickup = "immediate",
				statusLabels = false,
				onStart = function()
					assert(camera.zoomAt)(2, view.AbsolutePosition + view.AbsoluteWindowSize / 2)
				end,
				onEnd = function()
					assert(camera.fit)()
				end,
			}
		end,
		render = function(current): GuiObject
			return UI.Button {
				Name = `RackTile{current:peek()}`,
				label = string.char(64 + current:peek()),
				Size = UDim2.fromScale(1, 1),
			}
		end,
	}
	return UI.VStack(({
		width = "fill" :: "fill",
		gap = "s",
		UI.Text {
			text = "Lift a rack tile. The board zooms once. Further camera changes and pan wait for release. Drop or cancel returns to fit.",
			wrap = true,
		} :: unknown,
		view :: unknown,
		rack :: unknown,
	} :: unknown) :: StackProps)
end
