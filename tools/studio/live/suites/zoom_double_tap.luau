--!strict
type Controls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type Host = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type Live = {
	mount: ((Controls, Host, ComposeModule) -> Instance, { frames: number, motionLevel: "normal"? }?) -> GuiObject,
	find: (Instance, string) -> GuiObject?,
	check: (string, boolean, unknown?) -> (),
	note: (string, unknown) -> (),
	settle: (number) -> (),
}
type Board = { view: GuiObject, presses: { [string]: number }, fit: number, samples: { number } }
type Case = {
	id: string,
	contracts: { string },
	plan: string,
	setup: (Live) -> Board,
	steps: { [string]: (Live, Board) -> () },
}

local function zoomOf(board: Board): number
	local value = board.view:GetAttribute("FacetZoom")
	return if type(value) == "number" then value else -1
end

local cases: { Case } = {
	{
		id = "double-tap-over-cell-buttons-toggles-zoom",
		contracts = { "UI.ZoomView" },
		plan = "single: click cell B2; zoomed: double click cell B2; fitted: double click cell B2",
		setup = function(t: Live): Board
			local presses: { [string]: number } = {}
			local stage = t.mount(function(UI: Controls, Host: Host): Instance
				local cells: { Instance } = {
					Host.UIGridLayout {
						CellSize = UDim2.fromOffset(100, 100),
						CellPadding = UDim2.fromOffset(0, 0),
						SortOrder = Enum.SortOrder.Name,
					},
				}
				for _, row in { "A", "B", "C" } do
					for column = 1, 3 do
						local name = `{row}{column}`
						presses[name] = 0
						table.insert(
							cells,
							Host.TextButton {
								Name = name,
								Text = name,
								Activated = function()
									presses[name] += 1
								end,
							}
						)
					end
				end
				return UI.ZoomView "Board" {
					Size = UDim2.fromOffset(300, 300),
					Position = UDim2.fromOffset(200, 150),
					contentSize = Vector2.new(300, 300),
					doubleTapZoom = 2,
					content = function(): GuiObject
						return Host.Frame { Name = "Cells", Size = UDim2.fromScale(1, 1), table.unpack(cells) }
					end,
				}
			end, { frames = 20, motionLevel = "normal" })
			local view = assert(t.find(stage, "Board"), "the ZoomView is mounted")
			t.settle(10)
			local cell = assert(t.find(stage, "B2"), "cell B2 is on screen")
			local centre = cell.AbsolutePosition + cell.AbsoluteSize / 2
			t.note("points", { cell = { math.floor(centre.X + 0.5), math.floor(centre.Y + 0.5) } })
			local samples: { number } = {}
			local sampler = game:GetService("RunService").Heartbeat:Connect(function()
				local value = view:GetAttribute("FacetZoom")
				if type(value) == "number" and value ~= samples[#samples] then
					table.insert(samples, value)
				end
			end)
			view.Destroying:Connect(function()
				sampler:Disconnect()
			end)
			return { view = view, presses = presses, fit = -1, samples = samples }
		end,
		steps = {
			single = function(t: Live, board: Board)
				t.settle(30)
				board.fit = zoomOf(board)
				t.check("a single click activates the cell once", board.presses.B2 == 1, board.presses)
				t.check("a single click does not zoom", board.fit > 0, board.fit)
			end,
			zoomed = function(t: Live, board: Board)
				t.settle(30)
				local zoom = zoomOf(board)
				t.note("zoom after the double click", zoom)
				local between = 0
				for _, value in board.samples do
					if value > board.fit + 0.01 and value < zoom - 0.01 then
						between += 1
					end
				end
				t.note("zoom samples", board.samples)
				t.check("the zoom animates through intermediate levels", between >= 3, between)
				t.check(
					"a double click over a cell zooms in",
					zoom > board.fit + 0.01,
					{ fit = board.fit, zoom = zoom }
				)
				t.check(
					"the double click activates the cell only on its first click",
					board.presses.B2 == 2,
					board.presses
				)
			end,
			fitted = function(t: Live, board: Board)
				t.settle(30)
				local zoom = zoomOf(board)
				t.check(
					"a second double click fits again",
					math.abs(zoom - board.fit) < 0.01,
					{ fit = board.fit, zoom = zoom }
				)
				t.check("only the first click of each double click activates", board.presses.B2 == 3, board.presses)
			end,
		},
	},
}

return cases
